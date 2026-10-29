import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../utils/app_style.dart';

/// 液态玻璃卡片，基于 liquid_glass_widgets 的真实折射效果。
class LiquidGlassCard extends StatelessWidget {
  final Widget child;
  final BorderRadius? borderRadius;

  const LiquidGlassCard({
    super.key,
    required this.child,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final appStyle = Theme.of(context).extension<AppStyleTheme>()!;

    if (!appStyle.useLiquidGlass) {
      return child;
    }

    final radius = borderRadius ?? BorderRadius.circular(16);

    return GlassContainer(
      shape: LiquidRoundedSuperellipse(borderRadius: radius.topLeft.x),
      child: child,
    );
  }
}
