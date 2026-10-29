import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';

/// 液态玻璃胶囊底部导航目的地。
class LiquidGlassCapsuleDestination {
  final IconData icon;
  final IconData selectedIcon;
  final String label;

  const LiquidGlassCapsuleDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
}

/// 移动端液态玻璃胶囊底部导航栏，基于 liquid_glass_widgets 的 GlassTabBar。
class LiquidGlassCapsuleTabBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<LiquidGlassCapsuleDestination> destinations;

  const LiquidGlassCapsuleTabBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
  });

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final tabBarOpacity = settings.tabBarOpacity.clamp(0.1, 1.0);

    return GlassTabBar.bottom(
      tabs: [
        for (final destination in destinations)
          GlassTab(
            icon: Icon(destination.icon),
            activeIcon: Icon(destination.selectedIcon),
            semanticLabel: destination.label,
          ),
      ],
      selectedIndex: selectedIndex,
      onTabSelected: onDestinationSelected,
      settings: LiquidGlassSettings(
        visibility: tabBarOpacity,
        glassColor: Theme.of(context).brightness == Brightness.dark
            ? const Color(0x14FFFFFF)
            : const Color(0x2EFFFFFF),
      ),
    );
  }
}
