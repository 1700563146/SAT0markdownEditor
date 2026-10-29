import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import '../../../providers/file_provider.dart';
import '../../../utils/app_style.dart';
import '../../../widgets/app_background.dart';

/// 存储权限引导页（Android「所有文件访问」）
///
/// 采用系统 onboarding 版式：整页左对齐、说明在上、动作沉底，
/// 背景沿用 [AppBackground]，与主界面保持同一套视觉语言。
class PermissionScreen extends StatelessWidget {
  final FileProvider fileProvider;

  const PermissionScreen({super.key, required this.fileProvider});

  Future<void> _requestPermission(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final granted = await fileProvider.requestPermissions();
    if (granted || !context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.storagePermissionDenied),
        action: SnackBarAction(
          label: l10n.openSettings,
          onPressed: fileProvider.openSettings,
        ),
      ),
    );
  }

  /// 液态玻璃主题会把 FilledButton 的 backgroundColor 换成半透明
  /// [ButtonStyle.backgroundBuilder]，导致主按钮和其他按钮没有层级差；
  /// 这里显式替换回实色填充，保证唯一的主行动点足够醒目。
  ButtonStyle _primaryActionStyle(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return FilledButton.styleFrom(
      foregroundColor: colorScheme.onPrimary,
    ).copyWith(
      backgroundBuilder: (context, states, child) => DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.primary,
          borderRadius: BorderRadius.circular(16),
        ),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AppBackground(
      wrapWithSafeArea: false,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 40),
                        Icon(
                          Icons.folder_open,
                          size: 32,
                          color: context.appIconColor,
                        ),
                        const SizedBox(height: 20),
                        Text(
                          l10n.storagePermissionTitle,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          l10n.storagePermissionDesc,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 28),
                        _Point(
                          icon: Icons.check_circle_outline,
                          text: l10n.storagePermissionCan,
                        ),
                        const SizedBox(height: 12),
                        _Point(
                          icon: Icons.error_outline,
                          text: l10n.storagePermissionWithout,
                        ),
                        const Spacer(),
                        const SizedBox(height: 32),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            style: _primaryActionStyle(context),
                            onPressed: () => _requestPermission(context),
                            child: Text(l10n.grantStoragePermission),
                          ),
                        ),
                        const SizedBox(height: 4),
                        SizedBox(
                          width: double.infinity,
                          child: TextButton(
                            onPressed: fileProvider.openSettings,
                            child: Text(l10n.openSystemSettings),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          l10n.storagePermissionManualHint,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 18, color: context.appMutedIconColor),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}
