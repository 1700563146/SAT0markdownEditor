// ============================================================================
// 工作区全局搜索服务（T-12）
//
// 复用 T-07 已建的内存索引（FileService._scanIndex / getIndexedMarkdownPaths）
// 直接取得工作区全部 Markdown 文件路径，避免对同一批文件重复递归扫描；
// 全文 grep 在独立后台 isolate 中执行（文件分块流式读取，不整文件载入内存），
// 结果以可跨 isolate 发送的扁平结构回传主 isolate，再按文件分组展示；
// 支持中途取消（会话持有 Isolate 句柄，kill 即时终止，UI 立即响应）。
// ============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'file_service.dart';
import '../utils/debug_log.dart';

/// 单个匹配行（主 isolate 侧模型）。
class WorkspaceSearchMatch {
  /// 1-based 行号
  final int lineNumber;

  /// 匹配行文本（已 trim + 截断，仅用于预览）
  final String lineText;

  const WorkspaceSearchMatch(this.lineNumber, this.lineText);
}

/// 单个文件的命中分组（主 isolate 侧模型）。
class WorkspaceSearchFileHit {
  /// 文件绝对路径
  final String path;

  /// 命中行列表
  final List<WorkspaceSearchMatch> matches;

  const WorkspaceSearchFileHit(this.path, this.matches);
}

/// 一次全局搜索的结果（主 isolate 侧模型）。
class WorkspaceSearchResult {
  final String query;

  /// 是否被取消
  final bool cancelled;

  /// 搜索耗时（毫秒，含索引路径准备）
  final int elapsedMs;

  /// 参与搜索的文件总数
  final int scannedFiles;

  /// 按文件分组的命中结果（按命中数降序）
  final List<WorkspaceSearchFileHit> hits;

  /// 全部命中的行数（跨文件求和）
  final int totalMatchCount;

  const WorkspaceSearchResult({
    required this.query,
    required this.cancelled,
    required this.elapsedMs,
    required this.scannedFiles,
    required this.hits,
    required this.totalMatchCount,
  });

  bool get isEmpty => hits.isEmpty;
}

/// 搜索会话：持有后台 isolate 句柄，可随时取消。
///
/// 使用方式：
/// ```dart
/// final session = WorkspaceSearchSession(rootPath: root, query: query);
/// final result = await session.result;
/// ```
/// 取消：`session.cancel()`（幂等；发起新搜索前应取消旧会话）。
class WorkspaceSearchSession {
  final String rootPath;
  final String query;

  late final Future<WorkspaceSearchResult> result = _execute();

  Isolate? _isolate;
  ReceivePort? _receivePort;
  Completer<WorkspaceSearchResult>? _completer;
  bool _cancelled = false;
  bool _completed = false;
  final Stopwatch _stopwatch = Stopwatch();

  WorkspaceSearchSession({required this.rootPath, required this.query});

  /// 终止当前后台 grep（幂等；终止后 [result] 以 cancelled 结果完成）。
  void cancel() {
    if (_completed) return;
    _cancelled = true;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _completeIfNeeded(
      WorkspaceSearchResult(
        query: query,
        cancelled: true,
        elapsedMs: _stopwatch.elapsedMilliseconds,
        scannedFiles: 0,
        hits: const [],
        totalMatchCount: 0,
      ),
    );
  }

  Future<WorkspaceSearchResult> _execute() async {
    _stopwatch.start();

    // 查询为空直接返回空结果，不启动 isolate。
    final queryLower = query.trim().toLowerCase();
    if (queryLower.isEmpty) {
      return _finish(WorkspaceSearchResult(
        query: query,
        cancelled: false,
        elapsedMs: _stopwatch.elapsedMilliseconds,
        scannedFiles: 0,
        hits: const [],
        totalMatchCount: 0,
      ));
    }

    // 复用 T-07 内存索引拿文件路径；索引未构建时先触发一次扫描回填。
    var paths = FileService.getIndexedMarkdownPaths();
    if (paths.isEmpty) {
      await FileService().listMarkdownFiles(rootPath);
      paths = FileService.getIndexedMarkdownPaths();
    }
    if (_cancelled) {
      return _finish(WorkspaceSearchResult(
        query: query,
        cancelled: true,
        elapsedMs: _stopwatch.elapsedMilliseconds,
        scannedFiles: 0,
        hits: const [],
        totalMatchCount: 0,
      ));
    }

    final completer = Completer<WorkspaceSearchResult>();
    _completer = completer;
    final receivePort = ReceivePort();
    _receivePort = receivePort;

    try {
      final isolate = await Isolate.spawn(
        workspaceGrepIsolate,
        <Object>[paths, queryLower, receivePort.sendPort],
        debugName: 'workspace-grep',
      );
      _isolate = isolate;
    } catch (e) {
      appDebugLog('WorkspaceSearch spawn isolate failed: $e');
      return _finish(WorkspaceSearchResult(
        query: query,
        cancelled: false,
        elapsedMs: _stopwatch.elapsedMilliseconds,
        scannedFiles: 0,
        hits: const [],
        totalMatchCount: 0,
      ));
    }

    // 若在 spawn 等待期间已被取消，立即终止刚启动的 isolate 并收口。
    if (_cancelled) {
      _isolate?.kill(priority: Isolate.immediate);
      return _finish(WorkspaceSearchResult(
        query: query,
        cancelled: true,
        elapsedMs: _stopwatch.elapsedMilliseconds,
        scannedFiles: 0,
        hits: const [],
        totalMatchCount: 0,
      ));
    }

    receivePort.listen((message) {
      if (message is! List || message.length < 2) return;
      final scanned = message[0] as int;
      final flatHits = message[1] as List;
      final hits = _groupHits(flatHits);
      _completeIfNeeded(WorkspaceSearchResult(
        query: query,
        cancelled: _cancelled,
        elapsedMs: _stopwatch.elapsedMilliseconds,
        scannedFiles: scanned,
        hits: hits,
        totalMatchCount: hits.fold<int>(
          0,
          (sum, hit) => sum + hit.matches.length,
        ),
      ));
    });

    return completer.future;
  }

  /// 将 isolate 回传的扁平 `[path, [[lineNo, text], ...]]` 组装为分组模型。
  List<WorkspaceSearchFileHit> _groupHits(List flatHits) {
    final hits = <WorkspaceSearchFileHit>[];
    for (final entry in flatHits) {
      if (entry is! List || entry.length < 2) continue;
      final path = entry[0] as String;
      final rawMatches = entry[1] as List;
      final matches = <WorkspaceSearchMatch>[];
      for (final raw in rawMatches) {
        if (raw is! List || raw.length < 2) continue;
        matches.add(WorkspaceSearchMatch(
          raw[0] as int,
          raw[1] as String,
        ));
      }
      if (matches.isNotEmpty) {
        hits.add(WorkspaceSearchFileHit(path, matches));
      }
    }
    // 按命中数降序，平局按路径字母序，便于快速定位重点文件。
    hits.sort((a, b) {
      final byCount = b.matches.length.compareTo(a.matches.length);
      if (byCount != 0) return byCount;
      return a.path.toLowerCase().compareTo(b.path.toLowerCase());
    });
    return hits;
  }

  void _completeIfNeeded(WorkspaceSearchResult result) {
    if (_completed) return;
    _completed = true;
    _isolate = null;
    _receivePort?.close();
    _receivePort = null;
    _stopwatch.stop();
    _completer?.complete(result);
    _completer = null;
  }

  /// 统一收口：标记完成并返回结果。
  WorkspaceSearchResult _finish(WorkspaceSearchResult result) {
    _completed = true;
    _isolate = null;
    _receivePort?.close();
    _receivePort = null;
    _stopwatch.stop();
    return result;
  }
}

/// 后台 grep isolate 入口（顶层函数，供 `Isolate.spawn` 使用）。
///
/// 参数必须是可跨 isolate 发送的扁平结构：
/// `[List<String> paths, String queryLower, SendPort replyPort]`。
/// 完成后经 replyPort 回传 `[int scanned, List flatHits]`，
/// flatHits 元素为 `[String path, List matches]`，matches 元素为
/// `[int lineNumber, String lineText]`。
Future<void> workspaceGrepIsolate(List<Object?> args) async {
  final paths = (args[0] as List).cast<String>();
  final queryLower = args[1] as String;
  final replyPort = args[2] as SendPort;

  final flatHits = <List<Object>>[];
  var scanned = 0;
  try {
    for (final path in paths) {
      scanned++;
      final matches = await _grepFile(path, queryLower);
      if (matches.isNotEmpty) {
        flatHits.add(<Object>[path, matches]);
      }
    }
  } catch (e) {
    appDebugLog('WorkspaceGrepIsolate error: $e');
  }
  replyPort.send(<Object>[scanned, flatHits]);
}

/// 对单个文件做全文 grep（分块流式读取 + 逐行匹配，大小写不敏感）。
///
/// 返回 `List<List<Object>>`，每个元素 `[lineNumber, lineText]`；
/// 单文件命中数达到上限后提前结束读取（早期退出，控制响应时间）；
/// 文件读取失败返回空列表（单个文件失败不阻塞整体搜索）。
Future<List<List<Object>>> _grepFile(String path, String queryLower) async {
  const int maxMatchesPerFile = 300;
  const int previewMaxChars = 160;

  final File file = File(path);
  final matches = <List<Object>>[];
  try {
    final stream = file.openRead().transform(const Utf8Decoder());
    String carry = '';
    var lineNumber = 0;
    var hitCap = false;

    // 流式分块：逐块解码并按 \n 切行，块边界未完成行携带到下一块。
    final iterator = StreamIterator(stream);
    while (await iterator.moveNext()) {
      final combined = carry + iterator.current;
      final lines = combined.split('\n');
      carry = lines.isEmpty ? '' : lines.removeLast();
      for (final line in lines) {
        lineNumber++;
        if (line.toLowerCase().contains(queryLower)) {
          matches.add(<Object>[
            lineNumber,
            _truncateLine(line, previewMaxChars),
          ]);
          if (matches.length >= maxMatchesPerFile) {
            hitCap = true;
            break;
          }
        }
      }
      if (hitCap) break;
    }
    // 处理最后一段未换行结尾的残余内容。
    if (!hitCap && carry.isNotEmpty) {
      lineNumber++;
      if (carry.toLowerCase().contains(queryLower)) {
        matches.add(<Object>[
          lineNumber,
          _truncateLine(carry, previewMaxChars),
        ]);
      }
    }
  } catch (e) {
    // 权限/编码/IO 异常：单个文件失败不影响整体搜索
    appDebugLog('WorkspaceGrep skip $path: $e');
    return const [];
  }
  return matches;
}

/// 精简匹配行用于预览：去首尾空白，超长截断并加省略号。
String _truncateLine(String line, int maxChars) {
  var text = line.trim();
  if (text.length <= maxChars) return text;
  return '${text.substring(0, maxChars)}…';
}
