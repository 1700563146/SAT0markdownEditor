import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mdreader/screens/settings/appearance/background_settings_screen.dart';
import 'package:mdreader/screens/settings/appearance/color_setting_selector.dart';
import 'package:mdreader/screens/settings/appearance/color_theme_screen.dart';
import 'package:mdreader/screens/settings/appearance/font_settings_screen.dart';
import 'package:mdreader/screens/settings/appearance_categories_screen.dart';

import 'appearance_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('外观设置三层结构', () {
    testWidgets('分类页只列 3 个入口', (tester) async {
      final settings = await createAppearanceSettings();
      await pumpAppearancePage(
        tester,
        settings,
        const AppearanceCategoriesScreen(),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('配色与主题'), findsOneWidget);
      expect(find.text('文字与字体'), findsOneWidget);
      expect(find.text('表面与背景'), findsOneWidget);
      // 旧页面入口不应残留
      expect(find.text('主题设置'), findsNothing);
      expect(find.text('其他外观设置'), findsNothing);
    });

    testWidgets('配色与主题页：按解析后的明暗只显示对应一套方案', (tester) async {
      final settings = await createAppearanceSettings();
      await pumpAppearancePage(tester, settings, const ColorThemeScreen());

      expect(tester.takeException(), isNull);
      for (final name in schemeNames(dark: false)) {
        expect(find.text(name), findsOneWidget, reason: '缺少浅色方案 $name');
      }
      for (final name in schemeNames(dark: true)) {
        expect(find.text(name), findsNothing, reason: '浅色下不该有深色方案 $name');
      }
      // 强调色一个取色入口 + 从图片取色按钮
      expect(find.byIcon(Icons.tune), findsOneWidget);
      expect(find.text('从图片取色'), findsOneWidget);
      expect(find.textContaining('莫奈'), findsNothing);
    });

    testWidgets('配色与主题页：深色下只显示深色方案', (tester) async {
      final settings = await createAppearanceSettings();
      await pumpAppearancePage(
        tester,
        settings,
        const ColorThemeScreen(),
        brightness: Brightness.dark,
      );

      expect(tester.takeException(), isNull);
      for (final name in schemeNames(dark: true)) {
        expect(find.text(name), findsOneWidget, reason: '缺少深色方案 $name');
      }
      for (final name in schemeNames(dark: false)) {
        expect(find.text(name), findsNothing, reason: '深色下不该有浅色方案 $name');
      }
    });

    testWidgets('文字与字体页：承载两个文字色区块，无遗留开关', (tester) async {
      final settings = await createAppearanceSettings();
      await pumpAppearancePage(tester, settings, const FontSettingsScreen());

      expect(find.byType(ColorSettingSelector), findsNWidgets(2));
      expect(find.byIcon(Icons.tune), findsNWidgets(2));
      expect(find.byType(Switch), findsNothing);
      expect(find.text('语言'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('表面与背景页：承载 UI 风格、卡片、图标色与背景', (tester) async {
      final settings = await createAppearanceSettings();
      // 「使用主题默认」只在存在自定义色时出现，先各设一个
      await settings.setCustomCardColor(const Color(0xFF1E1E1E));
      await settings.setCustomIconColor(const Color(0xFF10B981));
      await pumpAppearancePage(
        tester,
        settings,
        const BackgroundSettingsScreen(),
      );

      expect(tester.takeException(), isNull);
      // UI 风格：三个选项收小并排在同一行（同一水平线、横向依次排开）
      final styleTops = <Offset>[];
      for (final title in ['经典描边', '简洁立体', '液态玻璃']) {
        expect(find.text(title), findsOneWidget, reason: '缺少 UI 风格 $title');
        expect(
          tester.getSize(find.text(title)).width,
          lessThan(300),
          reason: '$title 未收小',
        );
        styleTops.add(tester.getTopLeft(find.text(title)));
      }
      for (final p in styleTops) {
        expect(p.dy, closeTo(styleTops.first.dy, 1.0), reason: 'UI 风格选项不在同一行');
      }
      expect(styleTops[0].dx, lessThan(styleTops[1].dx));
      expect(styleTops[1].dx, lessThan(styleTops[2].dx));
      // 卡片色 + 图标色
      expect(find.byIcon(Icons.check), findsNWidgets(2));
      expect(find.text('使用主题默认'), findsNWidgets(2));
      expect(find.text('背景'), findsWidgets);
      expect(find.text('编辑器背景'), findsWidgets);
      expect(find.text('选择图片'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });
}
