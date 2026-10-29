// ============================================================================
// ThemeTones 色调派生测试
// ============================================================================
//
// 锁两件事：
// 1. ColorScheme 角色塌缩（Flutter 的 `tertiary ?? secondary` 等回退）不得复发；
// 2. 派生出的 onX/X 色对在全部 11 套纸色方案上满足 WCAG AA。
// 断言对任意输入色成立，因此换色板前后都应绿。

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mdreader/providers/settings_provider.dart';
import 'package:mdreader/utils/constants.dart';
import 'package:mdreader/utils/theme_tones.dart';

const Color _neonCyan = Color(0xFF22D3EE);

void main() {
  final allPapers = [
    ...AppConstants.lightThemeSchemes,
    ...AppConstants.darkThemeSchemes,
  ];

  ColorScheme schemeFor(
    ThemeScheme paper, {
    required bool isDark,
    Color? seed,
  }) {
    return ThemeTones.scheme(
      brightness: isDark ? Brightness.dark : Brightness.light,
      primary: seed ?? SettingsProvider.themeColors[0],
      themeScheme: paper,
      error: AppConstants.errorColor,
    );
  }

  group('ThemeTones 派生', () {
    test('legibleOnDark 与 SettingsProvider 转发实现一致', () {
      for (final color in SettingsProvider.themeColors) {
        expect(
          ThemeTones.legibleOnDark(color),
          SettingsProvider.legibleOnDark(color),
        );
      }
    });

    test('浅色 accent 原样，深色 accent 压饱和并抬明度到 0.78', () {
      const base = Color(0xFF4B4F86);
      expect(ThemeTones.accent(base, isDark: false), base);

      final dark = HSLColor.fromColor(ThemeTones.accent(base, isDark: true));
      // HSL→RGB→HSL 往返有 8bit 量化误差，容差 0.01
      expect(dark.saturation, lessThanOrEqualTo(0.31));
      expect(dark.lightness, closeTo(0.78, 0.01));
    });

    test('secondary 与 primary 同色相，不再引入第二色相', () {
      for (final isDark in [false, true]) {
        for (final preset in SettingsProvider.themeColors) {
          final base = HSLColor.fromColor(
            ThemeTones.accent(preset, isDark: isDark),
          );
          final second = HSLColor.fromColor(
            ThemeTones.secondary(preset, isDark: isDark),
          );
          expect(second.hue, closeTo(base.hue, 0.001));
        }
      }
    });

    test('ColorScheme 角色塌缩签名全部消失', () {
      for (final paper in allPapers) {
        for (final isDark in [false, true]) {
          final cs = schemeFor(paper, isDark: isDark);
          expect(cs.primaryContainer, isNot(equals(cs.primary)));
          expect(cs.secondaryContainer, isNot(equals(cs.secondary)));
          expect(cs.tertiary, isNot(equals(cs.secondary)));
          expect(cs.tertiaryContainer, isNot(equals(cs.tertiary)));
          expect(cs.errorContainer, isNot(equals(cs.error)));
          expect(cs.outline, isNot(equals(Colors.white)));
          expect(cs.outline, isNot(equals(Colors.black)));
          expect(cs.inversePrimary, isNot(equals(cs.onPrimary)));
          expect(cs.surfaceTint, Colors.transparent);
          expect(cs.shadow, Colors.black);
        }
      }
    });

    test('纸色与文字色直接采用方案值，不被默认常量覆盖', () {
      for (final paper in allPapers) {
        final isDark = AppConstants.darkThemeSchemes.contains(paper);
        final cs = schemeFor(paper, isDark: isDark);
        expect(cs.surface, paper.surface);
        expect(cs.background, paper.background);
        expect(cs.onSurface, paper.text);
        expect(cs.onSurfaceVariant, paper.textSecondary);
      }
    });

    test('没有任何角色是荧光青', () {
      for (final paper in allPapers) {
        for (final isDark in [false, true]) {
          final cs = schemeFor(paper, isDark: isDark);
          for (final role in _accentFamily(cs)) {
            expect(
              _distance(role, _neonCyan),
              greaterThan(60),
              reason: '角色 ${role.toARGB32().toRadixString(16)} 仍接近荧光青',
            );
          }
        }
      }
    });

    test('accent 家族角色饱和度受控', () {
      for (final preset in SettingsProvider.themeColors) {
        final dark = HSLColor.fromColor(
          ThemeTones.accent(preset, isDark: true),
        );
        expect(dark.saturation, lessThanOrEqualTo(0.31));
        final darkTertiary = HSLColor.fromColor(
          ThemeTones.tertiary(preset, isDark: true),
        );
        expect(darkTertiary.saturation, lessThanOrEqualTo(0.29));
      }
    });

    test('onX 与其底色的对比度满足 AA', () {
      for (final paper in allPapers) {
        for (final isDark in [false, true]) {
          final cs = schemeFor(paper, isDark: isDark);
          _expectReadable('onPrimary/onPrimary', cs.onPrimary, cs.primary, 4.5);
          _expectReadable(
            'onSecondary/onSecondary',
            cs.onSecondary,
            cs.secondary,
            4.5,
          );
          _expectReadable(
            'onTertiary/onTertiary',
            cs.onTertiary,
            cs.tertiary,
            4.5,
          );
          _expectReadable(
            'onPrimaryContainer',
            cs.onPrimaryContainer,
            cs.primaryContainer,
            4.5,
          );
          _expectReadable(
            'onSecondaryContainer',
            cs.onSecondaryContainer,
            cs.secondaryContainer,
            4.5,
          );
          _expectReadable(
            'onTertiaryContainer',
            cs.onTertiaryContainer,
            cs.tertiaryContainer,
            4.5,
          );
          _expectReadable(
            'onErrorContainer',
            cs.onErrorContainer,
            cs.errorContainer,
            4.5,
          );
          _expectReadable('onSurface/surface', cs.onSurface, cs.surface, 4.5);
          _expectReadable(
            'onBackground/background',
            cs.onBackground,
            cs.background,
            4.5,
          );
        }
      }
    });

    test('每个预设作为深色 accent 时都在全部深色方案上可读', () {
      for (final paper in AppConstants.darkThemeSchemes) {
        for (final preset in SettingsProvider.themeColors) {
          final cs = schemeFor(paper, isDark: true, seed: preset);
          _expectReadable('accent on bg', cs.primary, cs.background, 4.5);
          _expectReadable('accent on surface', cs.primary, cs.surface, 4.5);
        }
      }
    });

    test('任意用户自定义色（含高饱和）都被压回受控色调', () {
      const wild = [
        Color(0xFF22D3EE), // 荧光青
        Color(0xFF00FF00), // 纯绿
        Color(0xFFFF00FF), // 纯品红
        Color(0xFFFFFFFF), // 纯白
        Color(0xFF000000), // 纯黑
      ];
      for (final color in wild) {
        for (final isDark in [false, true]) {
          final accent = ThemeTones.accent(color, isDark: isDark);
          final ink = ThemeTones.onAccent(color, isDark: isDark);
          _expectReadable('onAccent/accent', ink, accent, 3.0);
          final container = ThemeTones.container(color, isDark: isDark);
          final onContainer = ThemeTones.onContainer(color, isDark: isDark);
          _expectReadable('onContainer/container', onContainer, container, 4.5);
        }
      }
    });
  });
}

List<Color> _accentFamily(ColorScheme cs) => [
  cs.primary,
  cs.secondary,
  cs.tertiary,
  cs.primaryContainer,
  cs.secondaryContainer,
  cs.tertiaryContainer,
  cs.inversePrimary,
];

/// RGB 欧氏距离，仅用于「离荧光青有多远」的量级判断。
double _distance(Color a, Color b) {
  final dr = (a.r - b.r) * 255;
  final dg = (a.g - b.g) * 255;
  final db = (a.b - b.b) * 255;
  return math.sqrt(dr * dr + dg * dg + db * db);
}

void _expectReadable(String name, Color fg, Color bg, double minimum) {
  final ratio = _contrastRatio(fg, bg);
  expect(
    ratio,
    greaterThanOrEqualTo(minimum),
    reason:
        '$name 对比度不足: ${ratio.toStringAsFixed(2)} < $minimum '
        '(fg=#${fg.toARGB32().toRadixString(16)} bg=#${bg.toARGB32().toRadixString(16)})',
  );
}

double _contrastRatio(Color a, Color b) {
  final la = _relativeLuminance(a);
  final lb = _relativeLuminance(b);
  final lighter = math.max(la, lb);
  final darker = math.min(la, lb);
  return (lighter + 0.05) / (darker + 0.05);
}

double _relativeLuminance(Color color) {
  final argb = color.toARGB32();
  double linearize(int channel) {
    final value = channel / 255;
    return value <= 0.03928
        ? value / 12.92
        : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * linearize((argb >> 16) & 0xFF) +
      0.0722 * linearize(argb & 0xFF) +
      0.7152 * linearize((argb >> 8) & 0xFF);
}
