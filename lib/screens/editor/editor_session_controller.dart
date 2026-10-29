import 'package:flutter/foundation.dart';

import '../../services/file_service.dart';
import 'models/editor_patterns.dart';

/// T-09：编辑器文档生命周期控制器
///
/// 从 `_EditorScreenState` 中拆出的文档生命周期职责：
/// - 文件加载 / 保存（含换行归一化，保证「打开再保存」逐字节保持原样）
/// - 修改 / 保存 / 自动保存状态
/// - 增量合并与版本回退所需的内容基线（originalMarkdown / originalLineEnding /
///   lastWebMarkdown）
/// - 字数统计缓存
///
/// 不持有 BuildContext：文件服务通过 [fileServiceProvider] 注入；
/// UI 刷新由页面 State 负责（调用方在方法返回后自行 setState）。
class EditorSessionController extends ChangeNotifier {
  EditorSessionController({
    required this.filePath,
    required FileService Function() fileServiceProvider,
  }) : _fileServiceProvider = fileServiceProvider;

  /// 当前文档路径
  final String filePath;

  final FileService Function() _fileServiceProvider;

  // ==================== 修改 / 保存状态 ====================

  /// 是否存在未保存的修改
  bool isModified = false;

  /// 是否正在保存（防止并发保存）
  bool isSaving = false;

  /// 是否正在自动保存（用于 UI 提示）
  bool isAutoSaving = false;

  /// 最近一次成功保存时间
  DateTime? lastSaveTime;

  // ==================== 内容基线 ====================

  /// 上次保存 / 加载的内容（增量合并与未保存 Diff 的基准）
  String originalMarkdown = '';

  /// 首次加载时检测到的换行风格，保存时保持该风格
  String originalLineEnding = '\n';

  /// T-06：Web 侧「最后一次成功回写」的完整 markdown 基线。行级增量 patch
  /// 基于该基线逐次应用（与 Web 侧 lastSentMarkdown 严格同步）；full 回写时
  /// 直接重置。基线缺失或 patch 越界时视为不同步，请求 Web 侧全量对齐。
  String? lastWebMarkdown;

  // ==================== 字数统计缓存 ====================

  int cachedCharCount = 0;
  int cachedGlyphCount = 0;
  int cachedWordCount = 0;

  FileService get _fileService => _fileServiceProvider();

  // ==================== 加载 / 保存 ====================

  /// 读取文件内容
  Future<String> loadContent() => _fileService.readFile(filePath);

  /// 应用加载完成的内容：更新基线、重置修改状态并重算字数缓存。
  /// 文本控制器的写入与编辑历史由页面 State 负责。
  void applyLoadedContent(String content) {
    originalMarkdown = content;
    originalLineEnding = content.contains('\r\n') ? '\r\n' : '\n';
    // T-06：新文档加载后 Web 侧基线未建立，置空等待首个 full 回写重建，
    // 防止残留上一文档的增量基线导致 patch 错位。
    lastWebMarkdown = null;
    isModified = false;
    lastSaveTime = null;
    updateWordCount(content);
  }

  /// 归一化换行，保持文件原始换行风格
  String normalizeLineEndings(String text) {
    return FileService.normalizeLineEndings(
      text,
      lineEnding: originalLineEnding,
    );
  }

  /// 保存内容：归一化换行后写盘，并同步更新保存状态与基线。
  ///
  /// [text] 为编辑器当前未归一化的文本；写盘内容按 [originalLineEnding] 归一化，
  /// 基线保留未归一化文本以匹配编辑器内容。
  Future<void> saveContent(String text) async {
    final normalized = normalizeLineEndings(text);
    await _fileService.saveFile(filePath, normalized);
    originalMarkdown = text;
    isModified = false;
    lastSaveTime = DateTime.now();
  }

  /// 更新字数统计缓存（字符 / 非空字形 / 单词）
  void updateWordCount(String text) {
    cachedCharCount = text.length;
    cachedGlyphCount = text.runes.where((char) {
      final value = String.fromCharCode(char);
      return value.trim().isNotEmpty;
    }).length;
    cachedWordCount = text
        .split(wordSplitRegex)
        .where((w) => w.isNotEmpty)
        .length;
  }
}
