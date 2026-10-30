// ============================================================================
// 三路合并（Three-way merge）
//
// T-14: 基于 T-02 云同步台账（sync_ledger）的 base 哈希做三路合并。
// 输入为 base（最近一次同步的内容）、local（本地当前内容）、remote（云端当前内容）。
//
// 算法：
//   1. 分别计算 diff(base, local) 与 diff(base, remote)（复用 T-08 patience diff）。
//   2. 从 diff 结果提取"变更区间"（hunk），hunk 行号基于 base 文档（1-based）。
//   3. 将 base 上重叠的本地/远程变更区间标记为冲突块；不重叠的变更自动采用。
//   4. 输出片段序列（unchanged / local / remote / conflict），
//      冲突块由调用方交互式选择（保留本地 / 保留远程 / 两者），再合成合并文本。
//
// 本模块不依赖任何 UI 与存储，纯函数式设计，便于单测。
// ============================================================================
library;

import 'line_diff_calculator.dart';

/// 合并片段类型
enum MergeFragmentKind {
  /// base 原文（自动保留）
  unchanged,

  /// 仅本地修改（自动采用本地）
  local,

  /// 仅远程修改（自动采用远程）
  remote,

  /// 双方在 base 同一区域修改（需交互选择）
  conflict,
}

/// 冲突块的选择方式（交互式三选一）
enum MergeBlockChoice {
  /// 保留本地侧内容
  keepLocal,

  /// 保留远程侧内容
  keepRemote,

  /// 两者都保留（本地在前，远程在后）
  keepBoth,
}

/// 合并分析结果中的一个片段
class MergeFragment {
  final MergeFragmentKind kind;

  /// 该片段对应的 base 行区间（1-based，含边界；纯插入时 [baseStart, baseStart]）
  final int baseStart;
  final int baseEnd;

  /// unchanged / local / remote：采用的内容行
  final List<String> lines;

  /// conflict：本地侧内容行
  final List<String> localLines;

  /// conflict：远程侧内容行
  final List<String> remoteLines;

  const MergeFragment({
    required this.kind,
    required this.baseStart,
    required this.baseEnd,
    this.lines = const [],
    this.localLines = const [],
    this.remoteLines = const [],
  });

  /// 是否属于需要用户决策的冲突块
  bool get isConflict => kind == MergeFragmentKind.conflict;

  @override
  String toString() =>
      'MergeFragment(${kind.name}, base[$baseStart,$baseEnd], '
      'lines=${lines.length}, local=${localLines.length}, remote=${remoteLines.length})';
}

/// 冲突块（供 UI 展示与决策）
class MergeConflictBlock {
  /// base 上的冲突区间（1-based，含边界）
  final int baseStart;
  final int baseEnd;

  /// 本地侧内容行
  final List<String> localLines;

  /// 远程侧内容行
  final List<String> remoteLines;

  const MergeConflictBlock({
    required this.baseStart,
    required this.baseEnd,
    required this.localLines,
    required this.remoteLines,
  });
}

/// 三路合并分析结果
class MergeAnalysis {
  /// 有序片段序列（unchanged / local / remote / conflict）
  final List<MergeFragment> fragments;

  /// 冲突块列表（顺序与 [fragments] 中的 conflict 片段一致）
  final List<MergeConflictBlock> conflicts;

  const MergeAnalysis({required this.fragments, required this.conflicts});

  /// 是否存在需要用户决策的冲突块
  bool get hasConflicts => conflicts.isNotEmpty;

  /// 无冲突时直接合成合并文本；有冲突时冲突块默认采用本地侧（保守）
  String get autoMergedText => renderMergedText(this, const []);
}

/// 单个变更区间（hunk），行号基于 base 文档（1-based）
class _MergeHunk {
  final int baseStart;
  final int baseEnd;

  /// 该区间在新文档中的行内容（added 行）
  final List<String> newLines;

  /// 被替换的 base 行内容（removed 行）
  final List<String> baseLines;

  /// 是否属于本地侧（false 为远程侧）
  final bool isLocal;

  const _MergeHunk({
    required this.baseStart,
    required this.baseEnd,
    required this.newLines,
    required this.baseLines,
    required this.isLocal,
  });

  /// 纯插入：base 上无删除行
  bool get isPureInsert => baseStart > baseEnd;

  /// 参与重叠判定的有效区间（纯插入视为单点）
  int get effEnd => isPureInsert ? baseStart : baseEnd;

  bool overlapsWith(_MergeHunk other) {
    return baseStart <= other.effEnd && other.baseStart <= effEnd;
  }

  @override
  String toString() =>
      '_MergeHunk(base[$baseStart,$baseEnd], +${newLines.length} -${baseLines.length}'
      '${isLocal ? ',local' : ',remote'})';
}

/// 一组相互重叠的 hunk（合并为一个片段）
class _MergeGroup {
  final List<_MergeHunk> hunks;
  final bool hasLocal;
  final bool hasRemote;

  int get baseStart => hunks.first.baseStart;
  int get baseEnd => hunks.map((h) => h.effEnd).reduce((a, b) => a > b ? a : b);

  List<String> get localLines => [
    for (final h in hunks)
      if (h.isLocal) ...h.newLines,
  ];

  List<String> get remoteLines => [
    for (final h in hunks)
      if (!h.isLocal) ...h.newLines,
  ];

  bool get isConflict => hasLocal && hasRemote;

  _MergeGroup(this.hunks)
      : hasLocal = hunks.any((h) => h.isLocal),
        hasRemote = hunks.any((h) => !h.isLocal);
}

/// 从 diff 结果提取变更区间列表
List<_MergeHunk> _extractHunks(DiffResult diff, {required bool isLocal}) {
  if (diff.isSummary || diff.lines.isEmpty) return const [];
  final hunks = <_MergeHunk>[];
  final lines = diff.lines;
  var i = 0;
  while (i < lines.length) {
    if (lines[i].type == DiffLineType.unchanged) {
      i++;
      continue;
    }
    final removed = <String>[];
    final added = <String>[];
    int? firstOld;
    int? lastOld;
    while (i < lines.length && lines[i].type != DiffLineType.unchanged) {
      final d = lines[i];
      if (d.type == DiffLineType.removed) {
        removed.add(d.content);
        final n = d.oldLineNumber!;
        firstOld ??= n;
        lastOld = n;
      } else {
        added.add(d.content);
      }
      i++;
    }
    int baseStart;
    int baseEnd;
    if (removed.isEmpty) {
      // 纯插入：插入点位于前一个 unchanged 行的下一行；hunk 在开头则为 1
      baseStart = _prevUnchangedOldLine(lines, i - 1) + 1;
      baseEnd = baseStart - 1;
    } else {
      baseStart = firstOld!;
      baseEnd = lastOld!;
    }
    hunks.add(
      _MergeHunk(
        baseStart: baseStart,
        baseEnd: baseEnd,
        newLines: added,
        baseLines: removed,
        isLocal: isLocal,
      ),
    );
  }
  return hunks;
}

/// 在 [lines] 的 [endIndex] 之前（含）寻找最近的 unchanged 行的 oldLineNumber；
/// 不存在时返回 0。
int _prevUnchangedOldLine(List<DiffLine> lines, int endIndex) {
  for (var j = endIndex; j >= 0; j--) {
    if (lines[j].type == DiffLineType.unchanged) {
      return lines[j].oldLineNumber ?? 0;
    }
  }
  return 0;
}

/// 将本地/远程 hunk 按 base 顺序分组，重叠的归为一组
List<_MergeGroup> _groupHunks(
  List<_MergeHunk> localHunks,
  List<_MergeHunk> remoteHunks,
) {
  final all = [...localHunks, ...remoteHunks]
    ..sort((a, b) {
      final c = a.baseStart.compareTo(b.baseStart);
      if (c != 0) return c;
      // 同起点：纯插入排在替换前，避免被区间覆盖吞并
      if (a.isPureInsert != b.isPureInsert) {
        return a.isPureInsert ? -1 : 1;
      }
      return 0;
    });
  if (all.isEmpty) return const [];

  final groups = <_MergeGroup>[];
  var current = <_MergeHunk>[];
  for (final h in all) {
    if (current.isEmpty) {
      current = [h];
      continue;
    }
    final overlaps = current.any((c) => c.overlapsWith(h));
    if (overlaps) {
      current.add(h);
    } else {
      groups.add(_MergeGroup(current));
      current = [h];
    }
  }
  if (current.isNotEmpty) {
    groups.add(_MergeGroup(current));
  }
  return groups;
}

/// 根据分组构建有序片段序列
List<MergeFragment> _buildFragments(
  List<String> baseLines,
  List<_MergeGroup> groups,
) {
  final fragments = <MergeFragment>[];
  var pos = 1;
  for (final g in groups) {
    if (g.baseStart > pos) {
      final end = g.baseStart - 1 < baseLines.length
          ? g.baseStart - 1
          : baseLines.length;
      if (pos <= end) {
        fragments.add(
          MergeFragment(
            kind: MergeFragmentKind.unchanged,
            baseStart: pos,
            baseEnd: end,
            lines: baseLines.sublist(pos - 1, end),
          ),
        );
      }
    }
    if (g.isConflict) {
      fragments.add(
        MergeFragment(
          kind: MergeFragmentKind.conflict,
          baseStart: g.baseStart,
          baseEnd: g.baseEnd,
          localLines: g.localLines,
          remoteLines: g.remoteLines,
        ),
      );
    } else {
      fragments.add(
        MergeFragment(
          kind: g.hasLocal
              ? MergeFragmentKind.local
              : MergeFragmentKind.remote,
          baseStart: g.baseStart,
          baseEnd: g.baseEnd,
          lines: g.hasLocal ? g.localLines : g.remoteLines,
        ),
      );
    }
    pos = g.baseEnd + 1;
  }
  if (pos <= baseLines.length) {
    fragments.add(
      MergeFragment(
        kind: MergeFragmentKind.unchanged,
        baseStart: pos,
        baseEnd: baseLines.length,
        lines: baseLines.sublist(pos - 1),
      ),
    );
  }
  return fragments;
}

/// 执行三路合并分析。
///
/// 返回 null 表示无法进行行级合并（任一文档超过行级对齐阈值），
/// 调用方应降级为文件级二选一。
MergeAnalysis? performThreeWayMerge(
  String baseText,
  String localText,
  String remoteText,
) {
  final baseLines = baseText.split('\n');
  final localDiff = calculateLineDiff(baseText, localText);
  final remoteDiff = calculateLineDiff(baseText, remoteText);
  if (localDiff.isSummary || remoteDiff.isSummary) return null;

  final localHunks = _extractHunks(localDiff, isLocal: true);
  final remoteHunks = _extractHunks(remoteDiff, isLocal: false);
  final groups = _groupHunks(localHunks, remoteHunks);
  final fragments = _buildFragments(baseLines, groups);
  final conflicts = <MergeConflictBlock>[
    for (final g in groups)
      if (g.isConflict)
        MergeConflictBlock(
          baseStart: g.baseStart,
          baseEnd: g.baseEnd,
          localLines: g.localLines,
          remoteLines: g.remoteLines,
        ),
  ];
  return MergeAnalysis(fragments: fragments, conflicts: conflicts);
}

/// 依据用户对冲突块的选择合成最终合并文本。
///
/// [decisions] 长度必须与 [analysis.conflicts] 一致；缺省时对应冲突块
/// 保守采用本地侧，避免静默丢失数据。
String renderMergedText(
  MergeAnalysis analysis,
  List<MergeBlockChoice> decisions,
) {
  final out = <String>[];
  var di = 0;
  for (final f in analysis.fragments) {
    switch (f.kind) {
      case MergeFragmentKind.unchanged:
      case MergeFragmentKind.local:
      case MergeFragmentKind.remote:
        out.addAll(f.lines);
      case MergeFragmentKind.conflict:
        if (di >= decisions.length) {
          out.addAll(f.localLines);
          continue;
        }
        switch (decisions[di++]) {
          case MergeBlockChoice.keepLocal:
            out.addAll(f.localLines);
          case MergeBlockChoice.keepRemote:
            out.addAll(f.remoteLines);
          case MergeBlockChoice.keepBoth:
            out.addAll(f.localLines);
            out.addAll(f.remoteLines);
        }
    }
  }
  return out.join('\n');
}
