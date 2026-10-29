/// Line-level diff calculator using patience-diff based algorithm.
///
/// Computes line-by-line differences between two texts, producing
/// a list of [DiffLine] entries with added/removed/unchanged status
/// and corresponding line numbers for both old and new documents.
///
/// T-08: replaces the previous O(n·m) LCS matrix implementation with
/// a patience-diff based algorithm (expected O((N+M)·D)), and falls
/// back to a statistical summary (no line-by-line alignment) when a
/// document exceeds [diffAlignLineLimit] lines.
library;

/// The type of a single line in the diff result.
enum DiffLineType {
  /// Line was added in the new text.
  added,

  /// Line was removed from the old text.
  removed,

  /// Line is present in both old and new text (unchanged).
  unchanged,
}

/// A single line entry in the diff result.
///
/// Contains the line content, its change type, and the line numbers
/// in the original ([oldLineNumber]) and new ([newLineNumber]) documents.
/// A value of `null` for a line number means the line does not exist
/// in that document (e.g., an added line has no old line number).
class DiffLine {
  /// The text content of this line (without trailing newline).
  final String content;

  /// The change type of this line.
  final DiffLineType type;

  /// Line number in the old document (1-indexed), or `null` if added.
  final int? oldLineNumber;

  /// Line number in the new document (1-indexed), or `null` if removed.
  final int? newLineNumber;

  const DiffLine({
    required this.content,
    required this.type,
    this.oldLineNumber,
    this.newLineNumber,
  });

  @override
  String toString() =>
      'DiffLine(${type.name}, old:$oldLineNumber, new:$newLineNumber, '
      '"${_truncate(content, 30)}")';

  static String _truncate(String s, int max) =>
      s.length > max ? '${s.substring(0, max)}…' : s;
}

/// The result of a line-level diff computation.
class DiffResult {
  /// All diff lines in order. Empty when [isSummary] is true.
  final List<DiffLine> lines;

  /// Number of added lines.
  final int addedCount;

  /// Number of removed lines.
  final int removedCount;

  /// Number of unchanged lines.
  final int unchangedCount;

  /// Whether this result is a statistical summary only.
  ///
  /// When a document exceeds [diffAlignLineLimit] lines, line-by-line
  /// alignment is skipped and only aggregate statistics are produced
  /// ([lines] is empty). The statistics are approximated from the
  /// common prefix/suffix of the two documents.
  final bool isSummary;

  const DiffResult({
    required this.lines,
    required this.addedCount,
    required this.removedCount,
    required this.unchangedCount,
    this.isSummary = false,
  });

  /// Whether there are any differences.
  bool get hasChanges => addedCount > 0 || removedCount > 0;

  /// Total number of lines in the result.
  int get totalCount => lines.length;

  /// Empty diff result (no lines).
  static const empty = DiffResult(
    lines: [],
    addedCount: 0,
    removedCount: 0,
    unchangedCount: 0,
  );

  @override
  String toString() =>
      'DiffResult(+$addedCount -$removedCount =$unchangedCount, '
      '${lines.length} lines${isSummary ? ', summary' : ''})';
}

/// Maximum line count for line-by-line alignment.
///
/// If either input has more lines than this limit, [calculateLineDiff]
/// returns a statistical summary instead of aligned diff lines.
const int diffAlignLineLimit = 5000;

/// Maximum product size of a fallback range before it is collapsed
/// into a remove-all/add-all block (keeps worst case O(N+M)).
const int _lcsFallbackMaxSize = 256;

/// Calculates line-level diff between [oldText] and [newText].
///
/// Uses a patience-diff based algorithm (expected O((N+M)·D)) to find
/// matching lines between old and new text. Each line in the result
/// carries its content, change type, and the corresponding line numbers
/// in both documents. When either text exceeds [diffAlignLineLimit]
/// lines, only a statistical summary is returned ([DiffResult.isSummary]).
DiffResult calculateLineDiff(String oldText, String newText) {
  // Fast path: identical strings
  if (oldText == newText) {
    if (oldText.isEmpty) return DiffResult.empty;
    final lines = oldText.split('\n');
    return DiffResult(
      lines: [
        for (var i = 0; i < lines.length; i++)
          DiffLine(
            content: lines[i],
            type: DiffLineType.unchanged,
            oldLineNumber: i + 1,
            newLineNumber: i + 1,
          ),
      ],
      addedCount: 0,
      removedCount: 0,
      unchangedCount: lines.length,
    );
  }

  // Fast path: one side empty
  if (oldText.isEmpty) {
    final lines = newText.split('\n');
    return DiffResult(
      lines: [
        for (var i = 0; i < lines.length; i++)
          DiffLine(
            content: lines[i],
            type: DiffLineType.added,
            newLineNumber: i + 1,
          ),
      ],
      addedCount: lines.length,
      removedCount: 0,
      unchangedCount: 0,
    );
  }
  if (newText.isEmpty) {
    final lines = oldText.split('\n');
    return DiffResult(
      lines: [
        for (var i = 0; i < lines.length; i++)
          DiffLine(
            content: lines[i],
            type: DiffLineType.removed,
            oldLineNumber: i + 1,
          ),
      ],
      addedCount: 0,
      removedCount: lines.length,
      unchangedCount: 0,
    );
  }

  final oldLines = oldText.split('\n');
  final newLines = newText.split('\n');

  // T-08: 超阈值时只输出统计摘要，不做行级对齐
  if (oldLines.length > diffAlignLineLimit ||
      newLines.length > diffAlignLineLimit) {
    return _computeSummary(oldLines, newLines);
  }

  final editScript = _computePatienceDiff(oldLines, newLines);

  // Build result with line numbers
  final result = <DiffLine>[];
  var addedCount = 0;
  var removedCount = 0;
  var unchangedCount = 0;
  var oldLine = 1;
  var newLine = 1;

  for (final edit in editScript) {
    switch (edit.type) {
      case DiffLineType.unchanged:
        result.add(DiffLine(
          content: edit.content,
          type: DiffLineType.unchanged,
          oldLineNumber: oldLine,
          newLineNumber: newLine,
        ));
        oldLine++;
        newLine++;
        unchangedCount++;
      case DiffLineType.removed:
        result.add(DiffLine(
          content: edit.content,
          type: DiffLineType.removed,
          oldLineNumber: oldLine,
        ));
        oldLine++;
        removedCount++;
      case DiffLineType.added:
        result.add(DiffLine(
          content: edit.content,
          type: DiffLineType.added,
          newLineNumber: newLine,
        ));
        newLine++;
        addedCount++;
    }
  }

  return DiffResult(
    lines: result,
    addedCount: addedCount,
    removedCount: removedCount,
    unchangedCount: unchangedCount,
  );
}

/// Computes a statistical summary for very large documents.
///
/// Line-by-line alignment is skipped; unchanged count is approximated
/// by the common prefix/suffix of the two inputs, and the remaining
/// middle section is counted as removed (old) / added (new).
DiffResult _computeSummary(List<String> oldLines, List<String> newLines) {
  final n = oldLines.length;
  final m = newLines.length;

  var prefix = 0;
  final maxPrefix = n < m ? n : m;
  while (prefix < maxPrefix && oldLines[prefix] == newLines[prefix]) {
    prefix++;
  }

  var suffix = 0;
  while (suffix < n - prefix &&
      suffix < m - prefix &&
      oldLines[n - 1 - suffix] == newLines[m - 1 - suffix]) {
    suffix++;
  }

  final unchanged = prefix + suffix;
  return DiffResult(
    lines: const [],
    addedCount: m - unchanged,
    removedCount: n - unchanged,
    unchangedCount: unchanged,
    isSummary: true,
  );
}

// ---------------------------------------------------------------------------
// Patience-diff internals
// ---------------------------------------------------------------------------

class _Edit {
  final String content;
  final DiffLineType type;
  const _Edit(this.content, this.type);
}

/// A matched line pair (position in old range, position in new range).
typedef _Match = ({int a, int b});

/// Computes the diff between [oldLines] and [newLines] using a
/// patience-diff based algorithm. Unique common lines anchor the
/// recursion; remaining ranges are resolved recursively or with a
/// bounded LCS fallback, so memory stays O(N+M) and time is
/// expected O((N+M)·D).
List<_Edit> _computePatienceDiff(List<String> oldLines, List<String> newLines) {
  return _diffRange(oldLines, 0, oldLines.length, newLines, 0, newLines.length);
}

/// Recursively diffs the range `a[aLo..aHi)` against `b[bLo..bHi)`.
List<_Edit> _diffRange(
  List<String> a,
  int aLo,
  int aHi,
  List<String> b,
  int bLo,
  int bHi,
) {
  final result = <_Edit>[];

  // Trim common prefix (recorded as unchanged)
  while (aLo < aHi && bLo < bHi && a[aLo] == b[bLo]) {
    result.add(_Edit(a[aLo], DiffLineType.unchanged));
    aLo++;
    bLo++;
  }
  // Trim common suffix (recorded as unchanged, emitted in order later)
  final suffix = <_Edit>[];
  while (aLo < aHi && bLo < bHi && a[aHi - 1] == b[bHi - 1]) {
    suffix.add(_Edit(a[aHi - 1], DiffLineType.unchanged));
    aHi--;
    bHi--;
  }

  if (aLo == aHi) {
    for (var j = bLo; j < bHi; j++) {
      result.add(_Edit(b[j], DiffLineType.added));
    }
    result.addAll(suffix.reversed);
    return result;
  }
  if (bLo == bHi) {
    for (var i = aLo; i < aHi; i++) {
      result.add(_Edit(a[i], DiffLineType.removed));
    }
    result.addAll(suffix.reversed);
    return result;
  }

  // Count line occurrences inside the current ranges
  final aCounts = <String, int>{};
  for (var i = aLo; i < aHi; i++) {
    aCounts[a[i]] = (aCounts[a[i]] ?? 0) + 1;
  }
  final bCounts = <String, int>{};
  for (var j = bLo; j < bHi; j++) {
    bCounts[b[j]] = (bCounts[b[j]] ?? 0) + 1;
  }

  // Lines that appear exactly once on both sides are unique anchors
  final uniqueCommon = <String>{};
  for (final entry in aCounts.entries) {
    if (entry.value == 1 && bCounts[entry.key] == 1) {
      uniqueCommon.add(entry.key);
    }
  }

  if (uniqueCommon.isEmpty) {
    result.addAll(_fallbackRange(a, aLo, aHi, b, bLo, bHi));
    result.addAll(suffix.reversed);
    return result;
  }

  // Position of each unique common line inside the old range
  final aPos = <String, int>{};
  for (var i = aLo; i < aHi; i++) {
    if (uniqueCommon.contains(a[i])) {
      aPos[a[i]] = i;
    }
  }

  // Walk the new range in order, keeping old positions strictly
  // increasing (greedy approximation of the LIS used by patience).
  final matches = <_Match>[];
  var lastA = aLo - 1;
  var lastB = bLo - 1;
  for (var j = bLo; j < bHi; j++) {
    final line = b[j];
    if (!uniqueCommon.contains(line)) continue;
    final ai = aPos[line]!;
    if (ai > lastA && j > lastB) {
      matches.add((a: ai, b: j));
      lastA = ai;
      lastB = j;
    }
  }

  if (matches.isEmpty) {
    result.addAll(_fallbackRange(a, aLo, aHi, b, bLo, bHi));
    result.addAll(suffix.reversed);
    return result;
  }

  // Recurse between matched anchors
  var curALo = aLo;
  var curBLo = bLo;
  for (final match in matches) {
    result.addAll(_diffRange(a, curALo, match.a, b, curBLo, match.b));
    result.add(_Edit(a[match.a], DiffLineType.unchanged));
    curALo = match.a + 1;
    curBLo = match.b + 1;
  }
  result.addAll(_diffRange(a, curALo, aHi, b, curBLo, bHi));
  result.addAll(suffix.reversed);
  return result;
}

/// Fallback for ranges without unique common anchors.
///
/// Small ranges use an exact LCS; large ranges are collapsed into a
/// remove-all/add-all block to keep worst-case time linear.
List<_Edit> _fallbackRange(
  List<String> a,
  int aLo,
  int aHi,
  List<String> b,
  int bLo,
  int bHi,
) {
  final n = aHi - aLo;
  final m = bHi - bLo;
  if (n * m <= _lcsFallbackMaxSize * _lcsFallbackMaxSize) {
    return _lcsRange(a, aLo, aHi, b, bLo, bHi);
  }
  final edits = <_Edit>[];
  for (var i = aLo; i < aHi; i++) {
    edits.add(_Edit(a[i], DiffLineType.removed));
  }
  for (var j = bLo; j < bHi; j++) {
    edits.add(_Edit(b[j], DiffLineType.added));
  }
  return edits;
}

/// Exact LCS diff over a bounded range (see [_lcsFallbackMaxSize]).
List<_Edit> _lcsRange(
  List<String> a,
  int aLo,
  int aHi,
  List<String> b,
  int bLo,
  int bHi,
) {
  final n = aHi - aLo;
  final m = bHi - bLo;
  final dp = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));

  for (var i = 1; i <= n; i++) {
    for (var j = 1; j <= m; j++) {
      if (a[aLo + i - 1] == b[bLo + j - 1]) {
        dp[i][j] = dp[i - 1][j - 1] + 1;
      } else {
        dp[i][j] = dp[i - 1][j] > dp[i][j - 1] ? dp[i - 1][j] : dp[i][j - 1];
      }
    }
  }

  // Backtrack to produce edit script (reversed)
  final edits = <_Edit>[];
  var i = n;
  var j = m;

  while (i > 0 && j > 0) {
    if (a[aLo + i - 1] == b[bLo + j - 1]) {
      edits.add(_Edit(a[aLo + i - 1], DiffLineType.unchanged));
      i--;
      j--;
    } else if (dp[i - 1][j] > dp[i][j - 1]) {
      edits.add(_Edit(a[aLo + i - 1], DiffLineType.removed));
      i--;
    } else {
      edits.add(_Edit(b[bLo + j - 1], DiffLineType.added));
      j--;
    }
  }

  while (i > 0) {
    edits.add(_Edit(a[aLo + i - 1], DiffLineType.removed));
    i--;
  }
  while (j > 0) {
    edits.add(_Edit(b[bLo + j - 1], DiffLineType.added));
    j--;
  }

  return edits.reversed.toList();
}
