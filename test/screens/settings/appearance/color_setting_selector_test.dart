import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mdreader/l10n/app_localizations.dart';
import 'package:mdreader/screens/settings/appearance/color_setting_selector.dart';

void main() {
  const presets = [Color(0xFF111111), Color(0xFF222222), Color(0xFF333333)];

  late List<int> presetTaps;
  late List<Color> customPicks;

  Future<void> pumpSelector(
    WidgetTester tester, {
    Color? customColor,
    int? selectedPresetIndex,
  }) async {
    presetTaps = [];
    customPicks = [];
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('zh'), Locale('en')],
        locale: const Locale('zh'),
        home: Scaffold(
          body: SingleChildScrollView(
            child: ColorSettingSelector(
              presets: presets,
              customColor: customColor,
              customLabel: '自定义颜色',
              pickerInitialColor: presets[0],
              selectedPresetIndex: selectedPresetIndex,
              onPresetSelected: presetTaps.add,
              onCustomColorPicked: customPicks.add,
            ),
          ),
        ),
      ),
    );
  }

  group('ColorSettingSelector', () {
    testWidgets('预设色块后只多一个自定义入口，且不渲染任何开关', (tester) async {
      await pumpSelector(tester, selectedPresetIndex: 0);

      final swatches = find.descendant(
        of: find.byType(ColorSettingSelector),
        matching: find.byType(GestureDetector),
      );
      expect(swatches, findsNWidgets(presets.length + 1));
      expect(find.byIcon(Icons.tune), findsOneWidget);
      expect(find.byType(Switch), findsNothing);
    });

    testWidgets('点预设只回调下标，不弹取色窗', (tester) async {
      await pumpSelector(tester, selectedPresetIndex: 0);

      await tester.tap(find.byIcon(Icons.check).first);
      await tester.pumpAndSettle();

      // 下标 0 已选中，重复点击仍回调 0，由上层负责清除自定义
      expect(presetTaps, [0]);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('点自定义色块直达取色弹窗，确认后回传颜色', (tester) async {
      await pumpSelector(tester, selectedPresetIndex: 0);

      await tester.tap(find.byIcon(Icons.tune));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      // 取色弹窗只保留 RGB，HSL 已删除
      expect(find.text('HSL'), findsNothing);
      expect(find.text('RGB'), findsNothing);
      expect(find.textContaining('R:'), findsOneWidget);
      expect(find.textContaining('G:'), findsOneWidget);
      expect(find.textContaining('B:'), findsOneWidget);

      await tester.tap(find.text('确认'));
      await tester.pumpAndSettle();

      expect(customPicks, hasLength(1));
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('已有自定义色时自定义入口处于选中态', (tester) async {
      await pumpSelector(tester, customColor: const Color(0xFFABCDEF));

      expect(find.byIcon(Icons.tune), findsNothing);
      expect(find.byIcon(Icons.check), findsNWidgets(1));
    });
  });
}
