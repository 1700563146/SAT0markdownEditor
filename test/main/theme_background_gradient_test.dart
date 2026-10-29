// ============================================================================
// 页面背景渐变单一来源测试
// ============================================================================
//
// 渐变此前在 main.dart / app_background.dart / editor_screen.dart 各写一份、
// 色值互不一致，且把用户所选纸色方案对页面背景的影响完全屏蔽。
// 这里钉住两件事：渐变由方案派生，且 lib/ 内不得再出现写死的渐变字面量。

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mdreader/providers/settings_provider.dart';
import 'package:mdreader/utils/app_style.dart';
import 'package:mdreader/utils/constants.dart';
import 'package:mdreader/utils/theme_tones.dart';

AppStyleTheme _styleFor(ThemeScheme paper, {required bool isDark}) {
  final scheme = ThemeTones.scheme(
    brightness: isDark ? Brightness.dark : Brightness.light,
    primary: SettingsProvider.themeColors[0],
    themeScheme: paper,
    error: AppConstants.errorColor,
  );
  return AppStyleTheme.resolve(
    brightness: isDark ? Brightness.dark : Brightness.light,
    colorScheme: scheme,
    backgroundColor: paper.background,
    textSecondary: paper.textSecondary,
    buttonStyleMode: AppButtonStyleMode.classic,
    cardOpacity: 1.0,
  );
}

void main() {
  group('背景渐变单一来源', () {
    test('渐变起点就是所选方案的背景色', () {
      for (final paper in AppConstants.lightThemeSchemes) {
        final gradient = _styleFor(paper, isDark: false).backgroundGradient;
        expect(gradient.colors, hasLength(2));
        expect(gradient.colors.first, paper.background);
      }
      for (final paper in AppConstants.darkThemeSchemes) {
        final gradient = _styleFor(paper, isDark: true).backgroundGradient;
        expect(gradient.colors, hasLength(2));
        expect(gradient.colors.first, paper.background);
      }
    });

    test('渐变随方案变化，不再是全站同一个常量', () {
      final first = _styleFor(
        AppConstants.lightThemeSchemes.first,
        isDark: false,
      ).backgroundGradient;
      for (final paper in AppConstants.lightThemeSchemes.skip(1)) {
        final other = _styleFor(paper, isDark: false).backgroundGradient;
        expect(
          other.colors,
          isNot(equals(first.colors)),
          reason: '${paper.name} 与首个方案的渐变相同，说明未跟随方案',
        );
      }
    });

    test('过渡极浅：浅色端亮度降幅有限，深色端绝对差小于 12/255', () {
      for (final paper in AppConstants.lightThemeSchemes) {
        final colors = _styleFor(
          paper,
          isDark: false,
        ).backgroundGradient.colors;
        final start = colors.first.computeLuminance();
        final end = colors.last.computeLuminance();
        expect(end, lessThan(start), reason: '浅色端应当略微下沉而非变亮');
        expect(
          end / start,
          greaterThanOrEqualTo(0.85),
          reason: '${paper.name} 的浅色渐变过深，会出现可辨色带',
        );
      }
      for (final paper in AppConstants.darkThemeSchemes) {
        final colors = _styleFor(paper, isDark: true).backgroundGradient.colors;
        final delta = (colors.first.r - colors.last.r) * 255;
        expect(
          delta.abs(),
          lessThanOrEqualTo(12),
          reason: '${paper.name} 的深色渐变绝对跨度过大',
        );
        expect(
          colors.last.computeLuminance(),
          lessThan(colors.first.computeLuminance()),
        );
      }
    });

    test('lerp 与 copyWith 都保留渐变字段', () {
      final style = _styleFor(
        AppConstants.lightThemeSchemes.first,
        isDark: false,
      );
      expect(
        style.copyWith(cardOpacity: 0.5).backgroundGradient,
        style.backgroundGradient,
      );
      final other = _styleFor(
        AppConstants.lightThemeSchemes.last,
        isDark: false,
      );
      expect(
        style.lerp(other, 0.9).backgroundGradient,
        other.backgroundGradient,
      );
      expect(style.lerp(null, 0.5), style);
    });

    test('lib/ 内不得再出现写死的旧渐变字面量', () {
      final forbidden = RegExp(
        r'0xff(1a1a2e|16213e|0f0f23|f8f9ff|e8eeff|f0f4ff|dde4ff)',
        caseSensitive: false,
      );
      final offenders = <String>[];
      for (final file in _dartFiles(Directory('lib'))) {
        if (forbidden.hasMatch(file.readAsStringSync())) {
          offenders.add(file.path);
        }
      }
      expect(offenders, isEmpty, reason: '仍存在写死的背景渐变色值');
    });
  });
}

Iterable<File> _dartFiles(Directory dir) => dir
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'));
