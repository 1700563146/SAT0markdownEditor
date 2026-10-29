// ============================================================================
// 全局工作区搜索页（T-12）
//
// 入口：文件页搜索框右侧的「全局搜索」图标按钮。
// 行为：输入防抖 300ms 后启动 WorkspaceSearchSession（复用 T-07 索引 +
// 后台 isolate 全文 grep）；搜索过程中可随时取消；结果按文件分组展示，
// 点击任一命中行/文件分组即通过 EditorNavigationHelper 打开对应文件。
// ============================================================================

import 'dart:io';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/workspace_search_service.dart';
import '../utils/debouncer.dart';
import '../utils/editor_navigation_helper.dart';
import '../widgets/empty_state.dart';

class WorkspaceSearchScreen extends StatefulWidget {
  /// 工作区根目录绝对路径
  final String rootPath;

  const WorkspaceSearchScreen({super.key, required this.rootPath});

  @override
  State<WorkspaceSearchScreen> createState() => _WorkspaceSearchScreenState();
}

class _WorkspaceSearchScreenState extends State<WorkspaceSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final Debouncer _debouncer = Debouncer(
    duration: const Duration(milliseconds: 300),
  );

  WorkspaceSearchSession? _session;
  WorkspaceSearchResult? _result;
  bool _searching = false;
  String _query = '';

  @override
  void dispose() {
    _session?.cancel();
    _debouncer.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    setState(() => _query = value);
    _debouncer.run(() => _startSearch(value));
  }

  Future<void> _startSearch(String rawQuery) async {
    // 取消上一个还在跑的搜索会话（旧 isolate 立即终止）
    _session?.cancel();
    _session = null;

    final query = rawQuery.trim();
    if (query.isEmpty) {
      if (mounted) {
        setState(() {
          _searching = false;
          _result = null;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _searching = true;
        _result = null;
      });
    }

    final session = WorkspaceSearchSession(
      rootPath: widget.rootPath,
      query: query,
    );
    _session = session;

    final result = await session.result;
    // 会话已被更新的搜索取代（用户又输入了新词）时丢弃旧结果
    if (!mounted || session != _session) return;

    setState(() {
      _searching = false;
      _result = result;
      _session = null;
    });
  }

  void _cancelSearch() {
    _session?.cancel();
    _session = null;
    if (mounted) {
      setState(() {
        _searching = false;
        _result = null;
      });
    }
  }

  void _openFile(String path) {
    EditorNavigationHelper.openEditor(context, path);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        titleSpacing: 0,
        title: Text(l10n.globalSearch),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: l10n.cancel,
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildSearchField(l10n),
            if (_searching) _buildSearchingIndicator(l10n),
            Expanded(child: _buildBody(l10n)),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchField(AppLocalizations l10n) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: TextField(
        controller: _searchController,
        autofocus: true,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: l10n.globalSearchHint,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: colorScheme.outlineVariant),
          ),
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear),
                  tooltip: l10n.cancel,
                  onPressed: () {
                    _searchController.clear();
                    _onQueryChanged('');
                  },
                ),
        ),
        onChanged: _onQueryChanged,
      ),
    );
  }

  Widget _buildSearchingIndicator(AppLocalizations l10n) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              l10n.searchingWorkspace,
              style: TextStyle(color: colorScheme.outline),
            ),
          ),
          TextButton.icon(
            onPressed: _cancelSearch,
            icon: const Icon(Icons.close, size: 18),
            label: Text(l10n.cancel),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(AppLocalizations l10n) {
    if (_searching) {
      return const SizedBox.shrink();
    }

    final result = _result;
    if (result == null) {
      return const SizedBox.shrink();
    }

    if (result.cancelled) {
      return EmptyState(message: l10n.searchCancelled);
    }

    if (result.isEmpty) {
      return EmptyState(message: l10n.noGlobalSearchResults);
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 32),
      itemCount: result.hits.length,
      itemBuilder: (context, index) {
        return _FileGroupTile(
          hit: result.hits[index],
          query: result.query,
          onOpenFile: _openFile,
        );
      },
    );
  }
}

/// 单个文件的命中分组：文件标题行 + 命中行列表。
class _FileGroupTile extends StatelessWidget {
  final WorkspaceSearchFileHit hit;
  final String query;
  final ValueChanged<String> onOpenFile;

  const _FileGroupTile({
    required this.hit,
    required this.query,
    required this.onOpenFile,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final fileName = hit.path.split(Platform.pathSeparator).last;
    final dirName = hit.path.substring(
      0,
      hit.path.length - fileName.length,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 文件分组标题：整体可点击（打开文件）
        InkWell(
          onTap: () => onOpenFile(hit.path),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Icon(
                  Icons.description_outlined,
                  size: 18,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    fileName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${hit.matches.length}',
                  style: TextStyle(
                    color: colorScheme.outline,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 42, bottom: 8),
          child: Text(
            dirName,
            style: TextStyle(
              color: colorScheme.outline,
              fontSize: 12,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        // 命中行
        for (final match in hit.matches)
          _MatchLine(
            match: match,
            query: query,
            onTap: () => onOpenFile(hit.path),
          ),
        Divider(
          height: 16,
          indent: 16,
          endIndent: 16,
          color: colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ],
    );
  }
}

/// 单个命中行（点击打开所在文件）。
class _MatchLine extends StatelessWidget {
  final WorkspaceSearchMatch match;
  final String query;
  final VoidCallback onTap;

  const _MatchLine({
    required this.match,
    required this.query,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // 命中关键词高亮（大小写不敏感）
    final text = match.lineText;
    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final highlight = _HighlightSpan.build(lowerText, text, lowerQuery);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 42, vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${match.lineNumber}',
              style: TextStyle(
                color: colorScheme.outline,
                fontSize: 12,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text.rich(
                TextSpan(
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 13,
                    height: 1.4,
                  ),
                  children: highlight,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 把命中关键词切成普通/高亮片段（大小写不敏感，可多次命中）。
class _HighlightSpan {
  static List<TextSpan> build(
    String lowerText,
    String text,
    String lowerQuery,
  ) {
    if (lowerQuery.isEmpty) {
      return [TextSpan(text: text)];
    }
    final spans = <TextSpan>[];
    var start = 0;
    while (true) {
      final idx = lowerText.indexOf(lowerQuery, start);
      if (idx < 0) {
        if (start < text.length) {
          spans.add(TextSpan(text: text.substring(start)));
        }
        break;
      }
      if (idx > start) {
        spans.add(TextSpan(text: text.substring(start, idx)));
      }
      spans.add(
        TextSpan(
          text: text.substring(idx, idx + lowerQuery.length),
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: Color(0xFFE53935),
          ),
        ),
      );
      start = idx + lowerQuery.length;
      if (start >= text.length) break;
    }
    return spans;
  }
}
