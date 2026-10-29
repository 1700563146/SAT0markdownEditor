import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mdreader/providers/settings_provider.dart';
import 'package:mdreader/widgets/liquid_glass_capsule_tab_bar.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePathProviderPlatform extends PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() async => 'C:/fake/documents';

  @override
  Future<String?> getApplicationSupportPath() async => 'C:/fake/support';

  @override
  Future<String?> getTemporaryPath() async => 'C:/fake/tmp';
}

const _destinations = [
  LiquidGlassCapsuleDestination(
    icon: Icons.home_outlined,
    selectedIcon: Icons.home_rounded,
    label: 'Home',
  ),
  LiquidGlassCapsuleDestination(
    icon: Icons.folder_special_outlined,
    selectedIcon: Icons.folder_special_rounded,
    label: 'My Files',
  ),
  LiquidGlassCapsuleDestination(
    icon: Icons.history_outlined,
    selectedIcon: Icons.history_rounded,
    label: 'History',
  ),
  LiquidGlassCapsuleDestination(
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings_rounded,
    label: 'Settings',
  ),
];

class _TabBarHarness extends StatefulWidget {
  final int initialIndex;
  final ValueChanged<int>? onSelected;

  const _TabBarHarness({required this.initialIndex, this.onSelected});

  @override
  State<_TabBarHarness> createState() => _TabBarHarnessState();
}

class _TabBarHarnessState extends State<_TabBarHarness> {
  late int _index = widget.initialIndex;

  @override
  Widget build(BuildContext context) {
    return LiquidGlassCapsuleTabBar(
      selectedIndex: _index,
      onDestinationSelected: (index) {
        widget.onSelected?.call(index);
        setState(() => _index = index);
      },
      destinations: _destinations,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<SettingsProvider> createSettings() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    PathProviderPlatform.instance = _FakePathProviderPlatform();
    final provider = SettingsProvider();
    await provider.initialize();
    return provider;
  }

  Future<void> pumpBar(
    WidgetTester tester, {
    required int selectedIndex,
    required ValueChanged<int> onDestinationSelected,
  }) async {
    final settings = await createSettings();
    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsProvider>.value(
        value: settings,
        child: MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: _TabBarHarness(
                initialIndex: selectedIndex,
                onSelected: onDestinationSelected,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('渲染 4 个仅图标目的地', (tester) async {
    await pumpBar(
      tester,
      selectedIndex: 0,
      onDestinationSelected: (_) {},
    );

    expect(find.byIcon(Icons.home_rounded), findsOneWidget);
    expect(find.byIcon(Icons.folder_special_outlined), findsOneWidget);
    expect(find.byIcon(Icons.history_outlined), findsOneWidget);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
    expect(find.text('Home'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.label == 'Home',
      ),
      findsWidgets,
    );
  });

  testWidgets('点击目的地会返回对应索引并更新选中图标', (tester) async {
    int? tappedIndex;
    await pumpBar(
      tester,
      selectedIndex: 0,
      onDestinationSelected: (index) => tappedIndex = index,
    );

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    expect(tappedIndex, 3);
    expect(find.byIcon(Icons.settings_rounded), findsOneWidget);
  });
}
