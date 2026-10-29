// ============================================================================
// 色调派生
// ============================================================================
//
// ColorScheme 的每个角色都必须由这里显式产出。Flutter 的 getter 回退链
// （`tertiary ?? secondary`、`secondaryContainer ?? secondary`、
// `primaryContainer ?? primary`、`outline ?? onBackground ?? onSurface` 等）
// 会把未赋值的角色静默塌缩成另一个角色——本应用的荧光青外溢与「深色下
// outline 是纯白」都源于此。宁多勿缺：这里一次性写满全部语义角色。
//
// 派生原则：单一强调色相（secondary 即 primary），容器用不透明浅/深色调，
// 前景色按对比度就近取白或近黑墨色，因此任意用户自定义色都不会产出发光感。
// ============================================================================

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'constants.dart';

abstract final class ThemeTones {
  /// 压在亮色上的近黑墨色，避免纯黑带来的生硬对比。
  static const Color ink = Color(0xFF101319);

  static const double _darkAccentSaturation = 0.30;

  /// 0.78 是实测下限：再低，强调色作为文字/图标色在最深的深色方案上跌破 AA。
  static const double _darkAccentLightness = 0.78;
  static const double _darkTertiarySaturation = 0.28;
  static const double _darkTertiaryLightness = 0.72;
  static const double _lightTertiarySaturation = 0.24;
  static const double _lightTertiaryLightness = 0.42;
  static const double _containerSaturationLight = 0.22;
  static const double _containerSaturationDark = 0.16;
  static const double _containerLightnessLight = 0.90;
  static const double _containerLightnessDark = 0.26;

  /// 强调色与墨色预设都是为浅色纸面调校的，深色表面上需压饱和并提亮才可读。
  static Color legibleOnDark(Color color) {
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withSaturation(hsl.saturation > 0.5 ? 0.5 : hsl.saturation)
        .withLightness(hsl.lightness < 0.82 ? 0.82 : hsl.lightness)
        .toColor();
  }

  /// 主强调色：浅色原样，深色同色相压饱和提亮。
  static Color accent(Color base, {required bool isDark}) => isDark
      ? _retone(
          base,
          maxSaturation: _darkAccentSaturation,
          lightness: _darkAccentLightness,
        )
      : base;

  /// 副强调色与主色同相——「主色 + 荧光青副色」正是模板配色的标志。
  static Color secondary(Color base, {required bool isDark}) =>
      accent(base, isDark: isDark);

  /// 第三色相只比主色暗/亮一档，用于徽章与浮动按钮，避免多色相打架。
  static Color tertiary(Color base, {required bool isDark}) => isDark
      ? _retone(
          base,
          maxSaturation: _darkTertiarySaturation,
          lightness: _darkTertiaryLightness,
        )
      : _retone(
          base,
          maxSaturation: _lightTertiarySaturation,
          lightness: _lightTertiaryLightness,
        );

  /// 色调容器：不透明的浅/深底，替代「主色原色当容器」的满饱和块。
  static Color container(Color base, {required bool isDark}) => isDark
      ? _retone(
          base,
          maxSaturation: _containerSaturationDark,
          lightness: _containerLightnessDark,
        )
      : _retone(
          base,
          maxSaturation: _containerSaturationLight,
          lightness: _containerLightnessLight,
        );

  static Color onAccent(Color base, {required bool isDark}) =>
      readableOn(accent(base, isDark: isDark));

  static Color onSecondary(Color base, {required bool isDark}) =>
      readableOn(secondary(base, isDark: isDark));

  static Color onTertiary(Color base, {required bool isDark}) =>
      readableOn(tertiary(base, isDark: isDark));

  static Color onContainer(Color base, {required bool isDark}) =>
      readableOn(container(base, isDark: isDark));

  /// 在给定底色上取对比度更高的白或墨色。
  static Color readableOn(Color background) =>
      _contrast(Colors.white, background) >= _contrast(ink, background)
      ? Colors.white
      : ink;

  static Color outline(Color textSecondary, {required bool isDark}) =>
      textSecondary.withValues(alpha: isDark ? 0.35 : 0.22);

  static Color outlineVariant(Color textSecondary, {required bool isDark}) =>
      textSecondary.withValues(alpha: isDark ? 0.20 : 0.12);

  /// 一次性产出完整、无塌缩的 ColorScheme。
  ///
  /// [primary] 是用户所选预设色或自定义色；[themeScheme] 提供纸色与文字色。
  static ColorScheme scheme({
    required Brightness brightness,
    required Color primary,
    required ThemeScheme themeScheme,
    required Color error,
  }) {
    final isDark = brightness == Brightness.dark;

    final accentColor = accent(primary, isDark: isDark);
    final secondaryColor = secondary(primary, isDark: isDark);
    final tertiaryColor = tertiary(primary, isDark: isDark);
    final containerColor = container(primary, isDark: isDark);
    final onContainerColor = onContainer(primary, isDark: isDark);
    final errorColor = accent(error, isDark: isDark);
    final errorContainerColor = container(error, isDark: isDark);

    return ColorScheme(
      brightness: brightness,
      primary: accentColor,
      onPrimary: readableOn(accentColor),
      primaryContainer: containerColor,
      onPrimaryContainer: onContainerColor,
      secondary: secondaryColor,
      onSecondary: readableOn(secondaryColor),
      secondaryContainer: containerColor,
      onSecondaryContainer: onContainerColor,
      tertiary: tertiaryColor,
      onTertiary: readableOn(tertiaryColor),
      tertiaryContainer: containerColor,
      onTertiaryContainer: onContainerColor,
      error: errorColor,
      onError: readableOn(errorColor),
      errorContainer: errorContainerColor,
      onErrorContainer: onContainer(error, isDark: isDark),
      // background/onBackground 虽已废弃，但它们是 outline 与 outlineVariant
      // 的回退父级（`outline ?? onBackground`），且页面底色与卡片底色本就不同，
      // 留空会让 outline 塌缩到 onSurface。
      // ignore: deprecated_member_use
      background: themeScheme.background,
      // ignore: deprecated_member_use
      onBackground: themeScheme.text,
      surface: themeScheme.surface,
      onSurface: themeScheme.text,
      onSurfaceVariant: themeScheme.textSecondary,
      surfaceTint: Colors.transparent,
      outline: outline(themeScheme.textSecondary, isDark: isDark),
      outlineVariant: outlineVariant(themeScheme.textSecondary, isDark: isDark),
      inversePrimary: accent(primary, isDark: !isDark),
      inverseSurface: themeScheme.text,
      onInverseSurface: themeScheme.background,
      shadow: Colors.black,
    );
  }

  static Color _retone(
    Color color, {
    required double maxSaturation,
    required double lightness,
  }) {
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withSaturation(math.min(hsl.saturation, maxSaturation))
        .withLightness(lightness)
        .toColor();
  }

  static double _contrast(Color a, Color b) {
    final lightest = math.max(_luminance(a), _luminance(b));
    final darkest = math.min(_luminance(a), _luminance(b));
    return (lightest + 0.05) / (darkest + 0.05);
  }

  static double _luminance(Color color) {
    final argb = color.toARGB32();
    double linearize(int channel) {
      final value = channel / 255;
      return value <= 0.03928
          ? value / 12.92
          : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
    }

    return 0.2126 * linearize((argb >> 16) & 0xFF) +
        0.7152 * linearize((argb >> 8) & 0xFF) +
        0.0722 * linearize(argb & 0xFF);
  }
}
