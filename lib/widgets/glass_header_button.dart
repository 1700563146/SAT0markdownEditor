import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../utils/app_style.dart';
import 'app_surface.dart';

/// 头部图标按钮：玻璃风格使用 GlassIconButton，其余风格沿用 AppSurface。
class GlassHeaderButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;
  final Color? iconColor;
  final bool isActive;
  final String? tooltip;

  const GlassHeaderButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.size = 40,
    this.iconSize = 20,
    this.iconColor,
    this.isActive = false,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final appStyle = Theme.of(context).extension<AppStyleTheme>()!;
    final bool glassButton = appStyle.useLiquidGlass;
    final Color? explicitColor = iconColor ??
        (isActive ? Theme.of(context).colorScheme.primary : null);
    final Color? effectiveIconColor;
    if (explicitColor != null) {
      effectiveIconColor = explicitColor;
    } else if (glassButton && onPressed == null) {
      // Let GlassIconButton apply its own disabled-state tint.
      effectiveIconColor = null;
    } else {
      effectiveIconColor = context.appIconColor;
    }

    final button = glassButton
        ? GlassIconButton(
            onPressed: onPressed,
            size: size,
            iconSize: iconSize,
            shape: GlassIconButtonShape.roundedSquare,
            borderRadius: 12,
            icon: effectiveIconColor != null
                ? Icon(icon, color: effectiveIconColor, size: iconSize)
                : Icon(icon, size: iconSize),
          )
        : SizedBox(
            width: size,
            height: size,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: onPressed,
                child: AppSurface(
                  borderRadius: BorderRadius.circular(12),
                  alignment: Alignment.center,
                  prominent: appStyle.useBorderlessButtons,
                  child: Icon(icon, size: iconSize, color: effectiveIconColor),
                ),
              ),
            ),
          );

    if (tooltip == null) return button;
    return Tooltip(message: tooltip, child: button);
  }
}
