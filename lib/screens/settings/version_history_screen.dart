// ============================================================================
// 版本历史管理页面（T-13）
//
// 设置内新增「版本历史」：保留数量/容量上限配置、单文档快照列表与一键清理。
// 依赖 T-01 保留策略：快照排除 .versions 并在应用私有目录管理。
// ============================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../models/document_version.dart';
import '../../providers/settings_provider.dart';
import '../../services/my_files_service.dart';
import '../../services/version_service.dart';
import '../../utils/app_style.dart';
import '../../utils/capsule_nav_insets.dart';
import '../../widgets/app_background.dart';
import '../../widgets/app_surface.dart';

class VersionHistoryScreen extends StatefulWidget {
  const VersionHistoryScreen({super.key});

  @override
  State<VersionHistoryScreen> createState() => _VersionHistoryScreenState();
}

class _VersionHistoryScreenState extends State<VersionHistoryScreen> {
  final VersionService _versionService = VersionService();
  final MyFilesService _myFilesService = MyFilesService();

  String _workspacePath = '';
  List<VersionDirSummary> _summaries = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final settings = context.read<SettingsProvider>();
      _myFilesService.setSettingsProvider(settings);
      _init();
    });
  }

  Future<void> _init() async {
    final path = await _myFilesService.getWorkspacePath();
    if (!mounted) return;
    setState(() => _workspacePath = path);
    await _reloadSummaries();
  }

  Future<void> _reloadSummaries() async {
    if (_workspacePath.isEmpty) return;
    setState(() => _loading = true);
    final summaries = await _versionService.getAllVersionSummaries(
      _workspacePath,
    );
    if (!mounted) return;
    setState(() {
      _summaries = summaries;
      _loading = false;
    });
  }

  int get _totalSnapshotCount =>
      _summaries.fold(0, (sum, s) => sum + s.snapshotCount);

  int get _totalSizeBytes =>
      _summaries.fold(0, (sum, s) => sum + s.totalSizeBytes);

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final local = time.toLocal();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(local.year, local.month, local.day);
    final diff = today.difference(day).inDays;
    final hm =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    if (diff == 0) return '今天 $hm';
    if (diff == 1) return '昨天 $hm';
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} $hm';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AppBackground(
      wrapWithSafeArea: false,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: Text(l10n.versionHistory),
          centerTitle: true,
        ),
        body: ListView(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            20 + systemNavBottomInset(context),
          ),
          children: [
            _buildOverview(l10n),
            const SizedBox(height: 16),
            _buildConfigSection(l10n),
            const SizedBox(height: 16),
            _buildSnapshotListSection(l10n),
            const SizedBox(height: 16),
            _buildClearAllButton(l10n),
          ],
        ),
      ),
    );
  }

  Widget _buildOverview(AppLocalizations l10n) {
    return AppSurface(
      padding: const EdgeInsets.all(16),
      color: Theme.of(
        context,
      ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      border: null,
      child: Row(
        children: [
          Expanded(
            child: _overviewItem(
              icon: Icons.description_outlined,
              label: l10n.myFiles,
              value: '${_summaries.length}',
            ),
          ),
          Expanded(
            child: _overviewItem(
              icon: Icons.history,
              label: l10n.versionSnapshot,
              value: '$_totalSnapshotCount',
            ),
          ),
          Expanded(
            child: _overviewItem(
              icon: Icons.sd_storage_outlined,
              label: l10n.versionStorageUsed,
              value: _formatBytes(_totalSizeBytes),
            ),
          ),
        ],
      ),
    );
  }

  Widget _overviewItem({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Column(
      children: [
        Icon(icon, size: 20, color: context.appMutedIconColor),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: context.appMutedIconColor),
        ),
      ],
    );
  }

  Widget _buildConfigSection(AppLocalizations l10n) {
    return Consumer<SettingsProvider>(
      builder: (context, settings, _) {
        return _buildSection(
          l10n.versionHistoryTitle,
          Icons.tune,
          [
            _buildRetentionSlider(l10n, settings),
            const SizedBox(height: 12),
            _buildCapacitySlider(l10n, settings),
          ],
        );
      },
    );
  }

  Widget _buildRetentionSlider(
    AppLocalizations l10n,
    SettingsProvider settings,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.photo_library_outlined, color: context.appMutedIconColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l10n.versionRetentionCount,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Text(
              '${settings.maxVersionsPerFile}',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ),
        Slider(
          value: settings.maxVersionsPerFile.toDouble().clamp(1, 60),
          min: 1,
          max: 60,
          divisions: 59,
          label: '${settings.maxVersionsPerFile}',
          onChanged: (value) {
            settings.setMaxVersionsPerFile(value.round());
          },
        ),
        Text(
          l10n.versionRetentionCountDesc,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: context.appMutedIconColor),
        ),
      ],
    );
  }

  Widget _buildCapacitySlider(
    AppLocalizations l10n,
    SettingsProvider settings,
  ) {
    final currentMb = settings.maxTotalSizeMb;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.speed_outlined, color: context.appMutedIconColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l10n.versionCapacityLimit,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Text(
              currentMb <= 0
                  ? l10n.versionCapacityUnlimited
                  : '$currentMb MB',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ),
        Slider(
          value: (currentMb <= 0 ? 0 : currentMb).clamp(0, 1024).toDouble(),
          min: 0,
          max: 1024,
          divisions: 128,
          label: currentMb <= 0
              ? l10n.versionCapacityUnlimited
              : '$currentMb MB',
          onChanged: (value) {
            final mb = value.round();
            settings.setMaxTotalSizeMb(mb);
            if (mb > 0 && _workspacePath.isNotEmpty) {
              _applyCapacityLimit(mb);
            }
          },
        ),
        Text(
          l10n.versionCapacityLimitDesc,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: context.appMutedIconColor),
        ),
      ],
    );
  }

  Widget _buildSnapshotListSection(AppLocalizations l10n) {
    return _buildSection(
      l10n.versionSnapshotsList,
      Icons.photo_library,
      [
        if (_loading)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Column(
                children: [
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.versionScanning,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(
                      color: context.appMutedIconColor,
                    ),
                  ),
                ],
              ),
            ),
          )
        else if (_summaries.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                l10n.versionNoSnapshots,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: context.appMutedIconColor,
                ),
              ),
            ),
          )
        else
          ..._summaries.map((s) => _buildDocumentTile(l10n, s)),
      ],
    );
  }

  Widget _buildDocumentTile(
    AppLocalizations l10n,
    VersionDirSummary summary,
  ) {
    return Column(
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            Icons.insert_drive_file_outlined,
            color: context.appMutedIconColor,
          ),
          title: Text(
            summary.docBaseName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          subtitle: Text(
            '${l10n.versionSnapshotCount(summary.snapshotCount)} · ${_formatBytes(summary.totalSizeBytes)} · ${_formatTime(summary.lastModified)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: TextButton(
            onPressed: summary.snapshotCount == 0
                ? null
                : () => _confirmClearDocument(l10n, summary),
            child: Text(l10n.clear),
          ),
        ),
        const Divider(height: 1),
      ],
    );
  }

  Widget _buildClearAllButton(AppLocalizations l10n) {
    final hasAny = _summaries.any((s) => s.snapshotCount > 0);
    return AppSurface(
      padding: const EdgeInsets.all(16),
      border: null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.delete_sweep_outlined,
                size: 20,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                l10n.versionClearAll,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            l10n.versionClearAllDesc,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: context.appMutedIconColor),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: (!hasAny || _loading)
                  ? null
                  : () => _confirmClearAll(l10n),
              icon: const Icon(Icons.cleaning_services),
              label: Text(
                '${l10n.versionClearAll} (${l10n.versionSnapshotCount(_totalSnapshotCount)})',
              ),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _applyCapacityLimit(int mb) async {
    await _versionService.enforceCapacityLimit(_workspacePath, mb);
    await _reloadSummaries();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check, color: Colors.green),
            const SizedBox(width: 12),
            Expanded(child: Text(l10nOf(context).versionCapacityPruned)),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  AppLocalizations l10nOf(BuildContext context) =>
      AppLocalizations.of(context)!;

  Future<void> _confirmClearDocument(
    AppLocalizations l10n,
    VersionDirSummary summary,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(l10n.versionClearDocument),
        content: Text(
          '${summary.docBaseName}\n${l10n.versionClearDocumentConfirm}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            child: Text(l10n.confirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await _versionService.deleteVersionsDir(summary.versionsDir);
    await _reloadSummaries();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check, color: Colors.green),
            const SizedBox(width: 12),
            Expanded(child: Text(l10n.versionCleaned)),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _confirmClearAll(AppLocalizations l10n) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(l10n.versionClearAll),
        content: Text(l10n.versionClearAllConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            child: Text(l10n.confirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final clearedDocs = _summaries.length;
    final clearedBytes = _totalSizeBytes;
    await _versionService.deleteAllVersions(_workspacePath);
    await _reloadSummaries();
    if (!mounted) return;
    final freed = _formatBytes(clearedBytes);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check, color: Colors.green),
            const SizedBox(width: 12),
            Expanded(
              child: Text(l10n.versionCleanedResult(clearedDocs, freed)),
            ),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildSection(String title, IconData icon, List<Widget> children) {
    final appStyle = Theme.of(context).extension<AppStyleTheme>()!;
    return AppSurface(
      padding: const EdgeInsets.all(16),
      color: appStyle.scaledSurfaceColor(
        Theme.of(context).colorScheme,
        alpha: 0.7,
      ),
      border: appStyle.useBorderlessButtons
          ? null
          : Border.all(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                color: Theme.of(context).colorScheme.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}
