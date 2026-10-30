// ============================================================================
// 外观领域设置 Provider（T-09 拆分）
//
// 管理应用外观相关的设置选项：
// - 主题模式（跟随系统/浅色/深色）与主题色
// - 界面 / 编辑器文字颜色
// - 背景个性化（背景图片、模糊效果）
// - 底栏 / 图标 / 语言
// - 夜间主题、字体与代码块主题
//
// 由门面 SettingsProvider 组合并转发，不直接暴露给 UI。
// ============================================================================

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/app_style.dart';
import '../utils/debug_log.dart';
import '../utils/theme_tones.dart';
import 'settings_persistence_mixin.dart';

/// 外观领域设置提供者
class AppearanceSettingsProvider extends ChangeNotifier
    with SettingsPersistenceMixin {
  // ==================== 主题设置 ====================

  /// 主题模式（system/light/dark）
  ThemeMode _themeMode = ThemeMode.system;

  /// 主题色索引（对应 themeColors 列表）
  int _primaryColorIndex = 0;

  /// 自定义主题色；非空即表示用户覆盖了预设
  Color? _customThemeColor;

  /// 界面字体颜色索引（对应 uiFontColors 列表）
  int _uiFontColorIndex = 0;

  /// 自定义界面字体颜色；非空即表示用户覆盖了预设
  Color? _customUiFontColor;

  /// 编辑器文字颜色索引（对应 editorFontColors 列表）
  int _editorFontColorIndex = 0;

  /// 自定义编辑器文字颜色；非空即表示用户覆盖了预设
  Color? _customEditorFontColor;

  /// 夜间主题索引（对应 AppConstants.darkThemeSchemes 列表）
  int _darkThemeIndex = 0;

  /// 浅色主题索引（对应 AppConstants.lightThemeSchemes 列表）
  int _lightThemeIndex = 0;

  /// UI 字体族（System 表示系统默认）
  String _uiFontFamily = 'System';

  /// 按钮风格（经典描边 / 简洁立体）
  AppButtonStyleMode _buttonStyleMode = AppButtonStyleMode.liquidGlass;

  /// 编辑器字体族
  String _editorFontFamily = 'System';

  /// 代码块字体族
  String _codeFontFamily = 'System';

  /// 代码块主题索引（对应 AppConstants.codeBlockThemes 列表）
  int _codeBlockThemeIndex = 0;

  // ==================== 背景设置 ====================

  /// 背景图片路径（null 表示无背景图）
  String? _backgroundImagePath;

  /// 编辑器背景图片路径（null 表示无背景图）
  String? _editorBackgroundImagePath;

  /// 编辑器背景图片是否存在（在设置路径时异步验证，避免 build 中 existsSync）
  bool _editorBackgroundImageExists = false;

  /// 背景效果类型：none（无）、blur（模糊）
  String _backgroundEffect = 'none';

  /// 模糊效果强度（0-30）
  double _backgroundBlur = 10.0;

  /// 主背景亮度（0.2-1.8，1.0 为原始亮度）
  double _backgroundBrightness = 1.0;

  /// 编辑器背景是否启用模糊
  bool _editorBackgroundBlurEnabled = false;

  /// 编辑器背景模糊强度（0-30）
  double _editorBackgroundBlur = 10.0;

  /// 编辑器背景亮度（0.2-1.8，1.0 为原始亮度）
  double _editorBackgroundBrightness = 1.0;

  // ==================== 底栏设置 ====================

  /// 卡片透明度（0.4–1.0）
  double _cardOpacity = 1.0;

  /// 底部导航栏透明度（0.1–1.0）
  double _tabBarOpacity = 0.95;

  /// 自定义卡片颜色；非空即表示用户覆盖了主题默认色
  Color? _customCardColor;

  // ==================== 图标设置 ====================

  /// 自定义全局图标颜色；非空即表示用户覆盖了主题默认色
  Color? _customIconColor;

  /// 桌面图标索引（0=默认 app.png, 1=icon2.png）
  int _appIconIndex = 0;

  /// 主页左上角图标模式：default / icon2 / custom / none
  String _homeIconMode = 'default';

  /// 主页自定义图标路径（仅当 homeIconMode == 'custom' 时有效）
  String? _homeIconCustomPath;

  /// 主页左上角标题文字
  String _homeTitleText = '沢';

  // ==================== 语言设置 ====================

  /// 当前语言环境（默认中文）
  Locale _locale = const Locale('zh');

  // ==================== 预设主题色 ====================

  /// 10 种沉稳预设色。同一张表兼作主题色、UI 文字色与图标色，
  /// 因此每个色都必须能在浅色纸面上直接读、且作填充色时白字仍达 AA。
  static const List<Color> themeColors = [
    Color(0xFF4B4F86), // 墨蓝（默认）
    Color(0xFF725C3B), // 赭石
    Color(0xFF6C5280), // 暮紫
    Color(0xFF54623C), // 橄榄
    Color(0xFF44617E), // 雾蓝
    Color(0xFF804842), // 陶红
    Color(0xFF3E636A), // 石青
    Color(0xFF824F60), // 灰玫
    Color(0xFF3A6455), // 苔绿
    Color(0xFF71503D), // 棕褐
  ];

  /// 旧 12 色（Tailwind-500）到新色板的色相最近邻映射，下标为旧索引。
  /// 用色相而非 Lab 距离：Lab 最近邻会把「琥珀」判给「陶红」（ΔE 107.8）。
  static const List<int> _legacyPaletteHueRemap = [
    0,
    4,
    8,
    1,
    5,
    2,
    7,
    8,
    9,
    3,
    6,
    2,
  ];

  // ==================== 预设界面字体颜色 ====================

  /// UI 文字颜色预设与主题色调色板保持一致
  static const List<Color> uiFontColors = themeColors;

  // ==================== 预设编辑器文字颜色 ====================

  /// 8种精选编辑器文字颜色（适合长时间编辑阅读）
  static const List<Color> editorFontColors = [
    Color(0xFF1F2937), // 深灰（默认）- 近黑色，经典编辑器风格
    Color(0xFF2D3748), // 蓝灰 - 柔和护眼
    Color(0xFF1E3A5F), // 深蓝 - 沉稳专注
    Color(0xFF1B4332), // 深绿 - 自然清新
    Color(0xFF4A1D1D), // 深红 - 温暖复古
    Color(0xFF3B2D5F), // 深紫 - 优雅独特
    Color(0xFF374151), // 灰色 - 中等深度
    Color(0xFF0F172A), // 纯黑 - 高对比度
  ];

  // ==================== 预设全局图标颜色 ====================

  /// 全局图标颜色预设与主题色调色板保持一致
  static const List<Color> globalIconColors = themeColors;

  // ==================== Getters ====================

  ThemeMode get themeMode => _themeMode;
  int get primaryColorIndex => _primaryColorIndex;
  Color get primaryColor =>
      _customThemeColor ?? themeColors[_primaryColorIndex];
  Color? get customThemeColor => _customThemeColor;

  // 界面字体颜色 Getters
  int get uiFontColorIndex => _uiFontColorIndex;
  Color? get customUiFontColor => _customUiFontColor;

  // 编辑器文字颜色 Getters
  int get editorFontColorIndex => _editorFontColorIndex;
  Color? get customEditorFontColor => _customEditorFontColor;

  /// 强调色与墨色预设都是为浅色纸面调校的，深色表面上需压饱和并提亮才可读。
  static Color legibleOnDark(Color color) => ThemeTones.legibleOnDark(color);

  /// 预设索引越界（旧版残留或色板缩短）时夹回有效范围，避免取值抛错。
  static int _clampPaletteIndex(int index) {
    if (index < 0) return 0;
    return index >= themeColors.length ? themeColors.length - 1 : index;
  }

  /// 色板整体更换后，把已存的旧索引按色相最近邻换算一次，
  /// 否则用户选过的颜色会在升级后被静默换成不相干色相。
  /// 超出旧表长度的值不可能是旧索引，交给 [_clampPaletteIndex] 处理。
  Future<void> _remapLegacyPaletteIndices(SharedPreferences prefs) async {
    if (prefs.getBool('palette_v2_remap_done') ?? false) return;

    final legacyPrimary = prefs.getInt('primary_color_index');
    if (legacyPrimary != null &&
        legacyPrimary < _legacyPaletteHueRemap.length) {
      _primaryColorIndex = _legacyPaletteHueRemap[legacyPrimary];
      await prefs.setInt('primary_color_index', _primaryColorIndex);
    }

    final legacyUiFont = prefs.getInt('ui_font_color_index');
    if (legacyUiFont != null && legacyUiFont < _legacyPaletteHueRemap.length) {
      _uiFontColorIndex = _legacyPaletteHueRemap[legacyUiFont];
      await prefs.setInt('ui_font_color_index', _uiFontColorIndex);
    }

    await prefs.setBool('palette_v2_remap_done', true);
  }

  /// 自定义色是用户显式取的，两种模式下都原样生效；预设则按表面明暗取变体。
  static Color _resolveTextColor(
    Color? custom,
    Color preset,
    Brightness brightness,
  ) {
    if (custom != null) return custom;
    return brightness == Brightness.dark ? legibleOnDark(preset) : preset;
  }

  Color uiFontColorFor(Brightness brightness) => _resolveTextColor(
    _customUiFontColor,
    uiFontColors[_uiFontColorIndex],
    brightness,
  );

  Color editorFontColorFor(Brightness brightness) => _resolveTextColor(
    _customEditorFontColor,
    editorFontColors[_editorFontColorIndex],
    brightness,
  );

  String? get backgroundImagePath => _backgroundImagePath;
  String? get editorBackgroundImagePath => _editorBackgroundImagePath;
  bool get editorBackgroundImageExists => _editorBackgroundImageExists;
  String get backgroundEffect => _backgroundEffect;
  double get backgroundBlur => _backgroundBlur;
  double get backgroundBrightness => _backgroundBrightness;
  bool get editorBackgroundBlurEnabled => _editorBackgroundBlurEnabled;
  double get editorBackgroundBlur => _editorBackgroundBlur;
  double get editorBackgroundBrightness => _editorBackgroundBrightness;

  double get cardOpacity => _cardOpacity;
  double get tabBarOpacity => _tabBarOpacity;
  Color? get customCardColor => _customCardColor;

  // 图标设置 Getters
  Color? get customIconColor => _customIconColor;
  int get appIconIndex => _appIconIndex;
  String get homeIconMode => _homeIconMode;
  String? get homeIconCustomPath => _homeIconCustomPath;
  String get homeTitleText => _homeTitleText;

  Locale get locale => _locale;
  int get darkThemeIndex => _darkThemeIndex;
  int get lightThemeIndex => _lightThemeIndex;
  String get uiFontFamily => _uiFontFamily;
  AppButtonStyleMode get buttonStyleMode => _buttonStyleMode;
  bool get useBorderlessButtons =>
      _buttonStyleMode == AppButtonStyleMode.softShadow;
  String get editorFontFamily => _editorFontFamily;
  String get codeFontFamily => _codeFontFamily;
  int get codeBlockThemeIndex => _codeBlockThemeIndex;

  // ==================== 初始化 ====================

  /// 读取外观领域设置
  Future<void> initialize(SharedPreferences prefs) async {
    // 主题设置
    final themeModeIndex = prefs.getInt('theme_mode') ?? 0;
    _themeMode = ThemeMode.values[themeModeIndex];
    _primaryColorIndex = _clampPaletteIndex(
      prefs.getInt('primary_color_index') ?? 0,
    );
    _customThemeColor = await migrateCustomColor(
      prefs,
      colorKey: 'custom_theme_color',
      legacyFlagKey: 'use_custom_theme_color',
    );

    // 界面字体颜色设置
    _uiFontColorIndex = _clampPaletteIndex(
      prefs.getInt('ui_font_color_index') ?? 0,
    );
    _customUiFontColor = await migrateCustomColor(
      prefs,
      colorKey: 'custom_ui_font_color',
      legacyFlagKey: 'use_custom_ui_font_color',
    );
    await _remapLegacyPaletteIndices(prefs);

    // 编辑器文字颜色设置
    _editorFontColorIndex = prefs.getInt('editor_font_color_index') ?? 0;
    _customEditorFontColor = await migrateCustomColor(
      prefs,
      colorKey: 'custom_editor_font_color',
      legacyFlagKey: 'use_custom_editor_font_color',
    );
    // 「自适应渐变」开关从未被任何渲染路径读取，连同旧键一并移除
    await prefs.remove('adaptive_gradient_enabled');
    await prefs.remove('ui_font_adaptive_gradient_enabled');
    await prefs.remove('editor_font_adaptive_gradient_enabled');

    // 背景设置
    _backgroundImagePath = prefs.getString('background_image_path');
    _editorBackgroundImagePath = prefs.getString(
      'editor_background_image_path',
    );
    // 异步验证背景图是否存在
    if (_editorBackgroundImagePath != null) {
      _editorBackgroundImageExists = await File(
        _editorBackgroundImagePath!,
      ).exists();
    }
    // 旧版本的 'overlay' 态在 UI 上已不可达（模糊开关只会写 'blur'/'none'），
    // 残留该值的用户无法自行关闭，统一归一为 'blur'。
    final savedEffect = prefs.getString('background_effect') ?? 'none';
    _backgroundEffect = savedEffect == 'overlay' ? 'blur' : savedEffect;
    if (savedEffect == 'overlay') {
      await prefs.setString('background_effect', 'blur');
    }
    _backgroundBlur = prefs.getDouble('background_blur') ?? 10.0;
    _backgroundBrightness = prefs.getDouble('background_brightness') ?? 1.0;
    _editorBackgroundBlurEnabled =
        prefs.getBool('editor_background_blur_enabled') ?? false;
    _editorBackgroundBlur = prefs.getDouble('editor_background_blur') ?? 10.0;
    _editorBackgroundBrightness =
        prefs.getDouble('editor_background_brightness') ?? 1.0;
    await prefs.remove('background_overlay_opacity');

    // 语言设置
    // 如果用户没有设置过语言，则使用系统语言
    final savedLocaleCode = prefs.getString('locale');
    if (savedLocaleCode != null && savedLocaleCode.isNotEmpty) {
      // 用户已设置过语言，使用保存的语言（只保存语言代码，不带国家代码）
      _locale = Locale(savedLocaleCode);
    } else {
      // 首次启动，根据系统语言自动设置
      // 默认使用中文，只有系统语言明确为英语时才使用英语
      final systemLocale = WidgetsBinding.instance.platformDispatcher.locale;
      if (systemLocale.languageCode == 'en') {
        _locale = const Locale('en');
      } else {
        _locale = const Locale('zh');
      }
    }

    // 底栏设置
    _cardOpacity = prefs.getDouble('card_opacity') ?? 1.0;
    _tabBarOpacity = prefs.getDouble('tab_bar_opacity') ?? 0.95;

    // 自定义卡片颜色
    _customCardColor = await migrateCustomColor(
      prefs,
      colorKey: 'custom_card_color',
      legacyFlagKey: 'use_custom_card_color',
    );

    // 自定义全局图标颜色
    _customIconColor = await migrateCustomColor(
      prefs,
      colorKey: 'custom_icon_color',
      legacyFlagKey: 'use_custom_icon_color',
    );

    // 图标设置
    _appIconIndex = prefs.getInt('app_icon_index') ?? 0;
    _homeIconMode = prefs.getString('home_icon_mode') ?? 'default';
    _homeIconCustomPath = prefs.getString('home_icon_custom_path');
    _homeTitleText = prefs.getString('home_title_text') ?? '沢';

    // 夜间主题和字体设置
    _darkThemeIndex = prefs.getInt('dark_theme_index') ?? 0;
    _lightThemeIndex = prefs.getInt('light_theme_index') ?? 0;

    final buttonStyleName = prefs.getString('button_style_mode');
    _buttonStyleMode = AppButtonStyleMode.values.firstWhere(
      (mode) => mode.name == buttonStyleName,
      orElse: () => AppButtonStyleMode.liquidGlass,
    );

    // 字体设置迁移逻辑
    final oldFontFamily = prefs.getString('font_family');
    _uiFontFamily =
        prefs.getString('font_family_ui') ?? oldFontFamily ?? 'System';
    _editorFontFamily =
        prefs.getString('font_family_editor') ?? oldFontFamily ?? 'System';
    _codeFontFamily =
        prefs.getString('font_family_code') ??
        'JetBrains Mono'; // 代码块默认使用 JetBrains Mono 如果有

    // 代码块主题设置
    _codeBlockThemeIndex = prefs.getInt('code_block_theme_index') ?? 0;

    // 莫奈配色系统已删除，此处只做一次性迁移
    final monetAccent = await migrateMonetAccent(prefs, _themeMode);
    if (monetAccent != null) {
      // 莫奈此前在渲染上无条件压过自定义主题色，迁移结果显式落盘，
      // 否则二次启动 monet 键已消失，界面会回跳到一直被压制的旧自定义色。
      _customThemeColor = monetAccent;
      await prefs.setInt('custom_theme_color', monetAccent.toARGB32());
    }
  }

  // ==================== 主题设置方法 ====================

  /// 设置主题模式
  ///
  /// [mode] ThemeMode.system / ThemeMode.light / ThemeMode.dark
  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    schedulePersist('theme_mode', mode.index);
  }

  /// 选择预设主题色（同时清除自定义覆盖）
  Future<void> setPrimaryColorIndex(int index) async {
    _primaryColorIndex = index;
    _customThemeColor = null;
    notifyListeners();
    schedulePersist('primary_color_index', index);
    await writeCustomColor('custom_theme_color', null);
  }

  /// 设置自定义主题色；传 null 恢复预设
  Future<void> setCustomThemeColor(Color? color) async {
    _customThemeColor = color;
    notifyListeners();
    await writeCustomColor('custom_theme_color', color);
  }

  // ==================== 界面字体颜色设置方法 ====================

  /// 选择预设界面字体颜色（同时清除自定义覆盖）
  Future<void> setUiFontColorIndex(int index) async {
    _uiFontColorIndex = index;
    _customUiFontColor = null;
    notifyListeners();
    schedulePersist('ui_font_color_index', index);
    await writeCustomColor('custom_ui_font_color', null);
  }

  /// 设置自定义界面字体颜色；传 null 恢复预设
  Future<void> setCustomUiFontColor(Color? color) async {
    _customUiFontColor = color;
    notifyListeners();
    await writeCustomColor('custom_ui_font_color', color);
  }

  // ==================== 编辑器文字颜色设置方法 ====================

  /// 选择预设编辑器文字颜色（同时清除自定义覆盖）
  Future<void> setEditorFontColorIndex(int index) async {
    _editorFontColorIndex = index;
    _customEditorFontColor = null;
    notifyListeners();
    schedulePersist('editor_font_color_index', index);
    await writeCustomColor('custom_editor_font_color', null);
  }

  /// 设置自定义编辑器文字颜色；传 null 恢复预设
  Future<void> setCustomEditorFontColor(Color? color) async {
    _customEditorFontColor = color;
    notifyListeners();
    await writeCustomColor('custom_editor_font_color', color);
  }

  // ==================== 背景设置方法 ====================

  /// 设置背景图片
  ///
  /// 将图片复制到应用私有目录，避免清理缓存后图片丢失
  Future<void> setBackgroundImage(String? path) async {
    if (path == null) {
      // 清除背景图片
      // 删除旧的背景图片文件
      if (_backgroundImagePath != null) {
        try {
          final oldFile = File(_backgroundImagePath!);
          if (await oldFile.exists()) {
            await oldFile.delete();
          }
        } catch (e) {
          appDebugLog('操作失败: $e');
        }
      }
      _backgroundImagePath = null;
      final prefs = await this.prefs();
      await prefs.remove('background_image_path');
      notifyListeners();
      return;
    }

    try {
      // 将图片复制到应用私有目录
      final appDir = await getApplicationSupportDirectory();
      final bgDir = Directory('${appDir.path}/backgrounds');
      if (!await bgDir.exists()) {
        await bgDir.create(recursive: true);
      }

      final sourceFile = File(path);
      final fileName =
          'background_${DateTime.now().millisecondsSinceEpoch}.${path.split('.').last}';
      final destPath = '${bgDir.path}/$fileName';

      // 复制文件
      await sourceFile.copy(destPath);

      // 删除旧的背景图片文件（如果有）
      if (_backgroundImagePath != null && _backgroundImagePath != destPath) {
        try {
          final oldFile = File(_backgroundImagePath!);
          if (await oldFile.exists()) {
            await oldFile.delete();
          }
        } catch (e) {
          appDebugLog('操作失败: $e');
        }
      }

      _backgroundImagePath = destPath;
      final prefs = await this.prefs();
      await prefs.setString('background_image_path', destPath);
      notifyListeners();
    } catch (e) {
      // 如果复制失败，直接使用原路径（回退方案）
      _backgroundImagePath = path;
      final prefs = await this.prefs();
      await prefs.setString('background_image_path', path);
      notifyListeners();
    }
  }

  /// 设置编辑器背景图片
  ///
  /// 将图片复制到应用私有目录，避免清理缓存后图片丢失
  Future<void> setEditorBackgroundImage(String? path) async {
    if (path == null) {
      // 清除编辑器背景图片
      if (_editorBackgroundImagePath != null) {
        try {
          final oldFile = File(_editorBackgroundImagePath!);
          if (await oldFile.exists()) {
            await oldFile.delete();
          }
        } catch (e) {
          appDebugLog('操作失败: $e');
        }
      }
      _editorBackgroundImagePath = null;
      _editorBackgroundImageExists = false;
      final prefs = await this.prefs();
      await prefs.remove('editor_background_image_path');
      notifyListeners();
      return;
    }

    try {
      final appDir = await getApplicationSupportDirectory();
      final bgDir = Directory('${appDir.path}/editor_backgrounds');
      if (!await bgDir.exists()) {
        await bgDir.create(recursive: true);
      }

      final sourceFile = File(path);
      final fileName =
          'editor_background_${DateTime.now().millisecondsSinceEpoch}.${path.split('.').last}';
      final destPath = '${bgDir.path}/$fileName';

      await sourceFile.copy(destPath);

      if (_editorBackgroundImagePath != null &&
          _editorBackgroundImagePath != destPath) {
        try {
          final oldFile = File(_editorBackgroundImagePath!);
          if (await oldFile.exists()) {
            await oldFile.delete();
          }
        } catch (e) {
          appDebugLog('操作失败: $e');
        }
      }

      _editorBackgroundImagePath = destPath;
      _editorBackgroundImageExists = true;
      final prefs = await this.prefs();
      await prefs.setString('editor_background_image_path', destPath);
      notifyListeners();
    } catch (e) {
      // 如果复制失败，直接使用原路径（回退方案）
      _editorBackgroundImagePath = path;
      _editorBackgroundImageExists = await File(path).exists();
      final prefs = await this.prefs();
      await prefs.setString('editor_background_image_path', path);
      notifyListeners();
    }
  }

  /// 设置背景效果
  Future<void> setBackgroundEffect(String effect) async {
    _backgroundEffect = effect;
    notifyListeners();
    schedulePersist('background_effect', effect);
  }

  /// 设置模糊强度
  Future<void> setBackgroundBlur(double blur) async {
    _backgroundBlur = blur;
    notifyListeners();
    schedulePersist('background_blur', blur);
  }

  /// 仅在内存中更新背景亮度（不持久化），用于 Slider 拖动时实时预览
  void updateBackgroundBrightnessInMemory(double brightness) {
    _backgroundBrightness = brightness;
    notifyListeners();
  }

  /// 设置背景亮度（立即刷新 UI，再异步持久化）
  Future<void> setBackgroundBrightness(double brightness) async {
    _backgroundBrightness = brightness;
    notifyListeners();
    schedulePersist('background_brightness', brightness);
  }

  /// 设置编辑器背景模糊开关
  Future<void> setEditorBackgroundBlurEnabled(bool enabled) async {
    _editorBackgroundBlurEnabled = enabled;
    notifyListeners();
    schedulePersist('editor_background_blur_enabled', enabled);
  }

  /// 设置编辑器背景模糊强度
  Future<void> setEditorBackgroundBlur(double blur) async {
    _editorBackgroundBlur = blur;
    notifyListeners();
    schedulePersist('editor_background_blur', blur);
  }

  /// 仅在内存中更新编辑器背景亮度（不持久化），用于 Slider 拖动时实时预览
  void updateEditorBackgroundBrightnessInMemory(double brightness) {
    _editorBackgroundBrightness = brightness;
    notifyListeners();
  }

  /// 设置编辑器背景亮度（立即刷新 UI，再异步持久化）
  Future<void> setEditorBackgroundBrightness(double brightness) async {
    _editorBackgroundBrightness = brightness;
    notifyListeners();
    schedulePersist('editor_background_brightness', brightness);
  }

  // ==================== 语言设置方法 ====================

  /// 设置应用语言
  Future<void> setLocale(Locale locale) async {
    _locale = locale;
    notifyListeners();
    schedulePersist('locale', locale.languageCode);
  }

  // ==================== 底栏设置方法 ====================

  /// 设置卡片透明度
  Future<void> setCardOpacity(double opacity) async {
    _cardOpacity = opacity;
    notifyListeners();
    schedulePersist('card_opacity', opacity);
  }

  /// 设置底部导航栏透明度
  Future<void> setTabBarOpacity(double opacity) async {
    _tabBarOpacity = opacity;
    notifyListeners();
    schedulePersist('tab_bar_opacity', opacity);
  }

  /// 设置自定义卡片颜色；传 null 恢复主题默认
  Future<void> setCustomCardColor(Color? color) async {
    _customCardColor = color;
    notifyListeners();
    await writeCustomColor('custom_card_color', color);
  }

  // ==================== 图标设置方法 ====================

  /// 设置自定义全局图标颜色；传 null 恢复主题默认
  Future<void> setCustomIconColor(Color? color) async {
    _customIconColor = color;
    notifyListeners();
    await writeCustomColor('custom_icon_color', color);
  }

  /// 设置桌面图标索引（0=默认, 1=icon2）
  Future<void> setAppIconIndex(int index) async {
    _appIconIndex = index;
    notifyListeners();
    schedulePersist('app_icon_index', index);
  }

  /// 设置主页图标模式
  Future<void> setHomeIconMode(String mode) async {
    _homeIconMode = mode;
    notifyListeners();
    schedulePersist('home_icon_mode', mode);
  }

  /// 设置主页自定义图标路径
  Future<void> setHomeIconCustomPath(String? path) async {
    _homeIconCustomPath = path;
    notifyListeners();
    final prefs = await this.prefs();
    if (path != null) {
      await prefs.setString('home_icon_custom_path', path);
    } else {
      await prefs.remove('home_icon_custom_path');
    }
  }

  /// 设置主页标题文字（允许为空）
  Future<void> setHomeTitleText(String text) async {
    _homeTitleText = text.trim();
    notifyListeners();
    schedulePersist('home_title_text', text.trim());
  }

  // ==================== 夜间主题和字体设置方法 ====================

  /// 设置夜间主题索引
  Future<void> setDarkThemeIndex(int index) async {
    _darkThemeIndex = index;
    notifyListeners();
    schedulePersist('dark_theme_index', index);
  }

  /// 设置浅色主题索引
  Future<void> setLightThemeIndex(int index) async {
    _lightThemeIndex = index;
    notifyListeners();
    schedulePersist('light_theme_index', index);
  }

  /// 设置按钮风格
  Future<void> setButtonStyleMode(AppButtonStyleMode mode) async {
    _buttonStyleMode = mode;
    notifyListeners();
    schedulePersist('button_style_mode', mode.name);
  }

  /// 设置 UI 字体
  Future<void> setUiFontFamily(String fontFamily) async {
    _uiFontFamily = fontFamily;
    notifyListeners();
    schedulePersist('font_family_ui', fontFamily);
  }

  /// 设置编辑器字体
  Future<void> setEditorFontFamily(String fontFamily) async {
    _editorFontFamily = fontFamily;
    notifyListeners();
    schedulePersist('font_family_editor', fontFamily);
  }

  /// 设置代码块字体
  Future<void> setCodeFontFamily(String fontFamily) async {
    _codeFontFamily = fontFamily;
    notifyListeners();
    schedulePersist('font_family_code', fontFamily);
  }

  /// 设置代码块主题索引
  Future<void> setCodeBlockThemeIndex(int index) async {
    _codeBlockThemeIndex = index;
    notifyListeners();
    schedulePersist('code_block_theme_index', index);
  }
}
