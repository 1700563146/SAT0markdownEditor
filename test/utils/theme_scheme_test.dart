import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mdreader/providers/settings_provider.dart';
import 'package:mdreader/utils/constants.dart';

void main() {
  group('预设主题配色', () {
    test('深浅色主题数量与命名保持稳定', () {
      expect(AppConstants.darkThemeSchemes, hasLength(6));
      expect(AppConstants.lightThemeSchemes, hasLength(5));

      final darkNames = AppConstants.darkThemeSchemes.map((s) => s.name);
      final lightNames = AppConstants.lightThemeSchemes.map((s) => s.name);
      expect(darkNames.toSet(), hasLength(darkNames.length));
      expect(lightNames.toSet(), hasLength(lightNames.length));
    });

    test('所有主题颜色均不透明且背景与表面色不同', () {
      for (final scheme in AppConstants.darkThemeSchemes) {
        _expectOpaqueSchemeColors(
          scheme.name,
          scheme.background,
          scheme.surface,
        );
        expect(scheme.background, isNot(equals(scheme.surface)));
      }
      for (final scheme in AppConstants.lightThemeSchemes) {
        _expectOpaqueSchemeColors(
          scheme.name,
          scheme.background,
          scheme.surface,
        );
        expect(scheme.background, isNot(equals(scheme.surface)));
      }
    });

    test('主文字在背景与表面上均满足 WCAG AA 对比度', () {
      for (final scheme in AppConstants.darkThemeSchemes) {
        _expectReadableText(
          scheme.name,
          scheme.text,
          scheme.background,
          scheme.surface,
          minimumContrast: 4.5,
        );
      }
      for (final scheme in AppConstants.lightThemeSchemes) {
        _expectReadableText(
          scheme.name,
          scheme.text,
          scheme.background,
          scheme.surface,
          minimumContrast: 4.5,
        );
      }
    });

    test('次要文字在背景与表面上保持可读', () {
      for (final scheme in AppConstants.darkThemeSchemes) {
        _expectReadableText(
          scheme.name,
          scheme.textSecondary,
          scheme.background,
          scheme.surface,
          minimumContrast: 3.0,
        );
      }
      for (final scheme in AppConstants.lightThemeSchemes) {
        _expectReadableText(
          scheme.name,
          scheme.textSecondary,
          scheme.background,
          scheme.surface,
          minimumContrast: 3.0,
        );
      }
    });
  });

  group('文字色预设的深色变体', () {
    // 深色模式下预设会被 legibleOnDark 变换，变换结果必须在全部深色方案上可读
    for (final scheme in AppConstants.darkThemeSchemes) {
      test('全部文字预设在「${scheme.name}」上满足 WCAG AA', () {
        for (var i = 0; i < SettingsProvider.uiFontColors.length; i++) {
          final color = SettingsProvider.legibleOnDark(
            SettingsProvider.uiFontColors[i],
          );
          _expectReadableText(
            'uiFontColors[$i]',
            color,
            scheme.background,
            scheme.surface,
            minimumContrast: 4.5,
          );
        }
        for (var i = 0; i < SettingsProvider.editorFontColors.length; i++) {
          final color = SettingsProvider.legibleOnDark(
            SettingsProvider.editorFontColors[i],
          );
          _expectReadableText(
            'editorFontColors[$i]',
            color,
            scheme.background,
            scheme.surface,
            minimumContrast: 4.5,
          );
        }
      });
    }

    test('深色变体只提亮不降亮，且饱和度被压住', () {
      for (final preset in SettingsProvider.uiFontColors) {
        final dark = SettingsProvider.legibleOnDark(preset);
        final src = HSLColor.fromColor(preset);
        final dst = HSLColor.fromColor(dark);
        // HSL→RGB→HSL 往返有精度损失，留 0.01 容差
        expect(dst.lightness, greaterThanOrEqualTo(src.lightness - 0.01));
        expect(dst.lightness, greaterThanOrEqualTo(0.81));
        expect(dst.saturation, lessThanOrEqualTo(0.51));
      }
    });

    test('已满足亮度要求的颜色不被改动', () {
      const alreadyLight = Color(0xFFEDEDED);
      expect(SettingsProvider.legibleOnDark(alreadyLight), alreadyLight);
    });
  });

  group('预设色板的浅色纸面与填充可读性', () {
    // 预设同时充当 UI 文字色，而浅色模式下取的是原文，
    // 这一档此前没有任何测试覆盖。
    test('预设原文在全部浅色方案背景与表面上满足 WCAG AA', () {
      for (final scheme in AppConstants.lightThemeSchemes) {
        for (var i = 0; i < SettingsProvider.uiFontColors.length; i++) {
          _expectReadableText(
            'uiFontColors[$i]',
            SettingsProvider.uiFontColors[i],
            scheme.background,
            scheme.surface,
            minimumContrast: 4.5,
          );
        }
      }
    });

    test('预设作填充色时白字仍达 AA（按钮与图标底板用白前景）', () {
      for (final preset in SettingsProvider.themeColors) {
        final ratio = _contrastRatio(const Color(0xFFFFFFFF), preset);
        expect(
          ratio,
          greaterThanOrEqualTo(4.5),
          reason:
              '#${preset.toARGB32().toRadixString(16)} 上白字只有 ${ratio.toStringAsFixed(2)}',
        );
      }
    });

    test('预设饱和度与亮度受控，不含 Tailwind-500 级荧光', () {
      for (final preset in SettingsProvider.themeColors) {
        final hsl = HSLColor.fromColor(preset);
        expect(
          hsl.saturation,
          lessThanOrEqualTo(0.45),
          reason: '#${preset.toARGB32().toRadixString(16)} 饱和度过高',
        );
        expect(
          hsl.lightness,
          lessThanOrEqualTo(0.45),
          reason: '#${preset.toARGB32().toRadixString(16)} 过亮，作文字色会发虚',
        );
      }
    });
  });
}

void _expectOpaqueSchemeColors(String name, Color background, Color surface) {
  expect(background.toARGB32() >>> 24, 255, reason: '$name 背景色不透明');
  expect(surface.toARGB32() >>> 24, 255, reason: '$name 表面色不透明');
}

void _expectReadableText(
  String name,
  Color text,
  Color background,
  Color surface, {
  required double minimumContrast,
}) {
  final onBackground = _contrastRatio(text, background);
  final onSurface = _contrastRatio(text, surface);
  expect(
    onBackground,
    greaterThanOrEqualTo(minimumContrast),
    reason: '$name 文字在背景上的对比度不足: $onBackground',
  );
  expect(
    onSurface,
    greaterThanOrEqualTo(minimumContrast),
    reason: '$name 文字在表面上的对比度不足: $onSurface',
  );
}

double _contrastRatio(Color a, Color b) {
  final lighter = math.max(_relativeLuminance(a), _relativeLuminance(b));
  final darker = math.min(_relativeLuminance(a), _relativeLuminance(b));
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

  final r = linearize((argb >> 16) & 0xFF);
  final g = linearize((argb >> 8) & 0xFF);
  final b = linearize(argb & 0xFF);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}
