// ============================================================================
// SettingsProvider 单元测试
// ============================================================================

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:mdreader/providers/settings_provider.dart';
import 'package:mdreader/utils/app_style.dart';

class _FakePathProviderPlatform extends PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() async => 'C:/fake/documents';

  @override
  Future<String?> getApplicationSupportPath() async => 'C:/fake/support';

  @override
  Future<String?> getTemporaryPath() async => 'C:/fake/tmp';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> flushPersist() =>
      Future<void>.delayed(const Duration(milliseconds: 600));

  group('SettingsProvider', () {
    late SettingsProvider provider;

    setUp(() async {
      // 模拟 SharedPreferences 初始数据
      SharedPreferences.setMockInitialValues({});
      // 模拟 FlutterSecureStorage 初始数据
      FlutterSecureStorage.setMockInitialValues({});
      // 模拟 path_provider，避免测试环境缺少平台实现
      PathProviderPlatform.instance = _FakePathProviderPlatform();

      provider = SettingsProvider();
      await provider.initialize();
    });

    test('默认值应正确', () {
      expect(provider.themeMode, ThemeMode.system);
      expect(provider.fontSize, 16.0);
      expect(provider.autoSave, false);
      expect(provider.autoSaveInterval, 30);
      expect(provider.webdavUrl, isEmpty);
      expect(provider.syncFolderName, 'Ushio-MD');
      expect(provider.buttonStyleMode, AppButtonStyleMode.liquidGlass);
      expect(provider.customIconColor, isNull);
      expect(provider.customCardColor, isNull);
    });

    test('UI文字颜色与全局图标颜色预设应和主题色调色板一致', () {
      expect(SettingsProvider.uiFontColors, same(SettingsProvider.themeColors));
      expect(
        SettingsProvider.globalIconColors,
        same(SettingsProvider.themeColors),
      );
    });

    test('setCustomIconColor 应立即生效，且不再写旧的开关键', () async {
      const color = Color(0xFF00BCD4);
      await provider.setCustomIconColor(color);

      expect(provider.customIconColor, color);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('custom_icon_color'), color.toARGB32());
      expect(prefs.containsKey('use_custom_icon_color'), isFalse);
    });

    test('setCustomIconColor(null) 应清除覆盖并落盘', () async {
      await provider.setCustomIconColor(const Color(0xFF00BCD4));
      await provider.setCustomIconColor(null);

      expect(provider.customIconColor, isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('custom_icon_color'), isFalse);
    });

    test('setCustomCardColor(null) 与图标色清除语义一致', () async {
      await provider.setCustomCardColor(const Color(0xFF1E1E1E));
      expect(provider.customCardColor, const Color(0xFF1E1E1E));

      await provider.setCustomCardColor(null);
      expect(provider.customCardColor, isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('custom_card_color'), isFalse);
    });

    test('颜色未自定义时应取预设', () {
      expect(provider.customThemeColor, isNull);
      expect(provider.primaryColor, SettingsProvider.themeColors[0]);
      expect(
        provider.uiFontColorFor(Brightness.light),
        SettingsProvider.uiFontColors[0],
      );
      expect(
        provider.editorFontColorFor(Brightness.light),
        SettingsProvider.editorFontColors[0],
      );
    });

    test('setCustomEditorFontColor 应立即生效并持久化', () async {
      const color = Color(0xFF123456);
      await provider.setCustomEditorFontColor(color);

      expect(provider.editorFontColorFor(Brightness.light), color);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('custom_editor_font_color'), color.toARGB32());
    });

    test('选择预设颜色应清除自定义覆盖', () async {
      await provider.setCustomUiFontColor(const Color(0xFFABCDEF));
      await provider.setUiFontColorIndex(2);

      expect(provider.customUiFontColor, isNull);
      expect(
        provider.uiFontColorFor(Brightness.light),
        SettingsProvider.uiFontColors[2],
      );

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('custom_ui_font_color'), isFalse);
    });

    test('旧版开关为 true 时应迁移成自定义颜色并删除开关键', () async {
      const color = Color(0xFF654321);
      SharedPreferences.setMockInitialValues({
        'use_custom_ui_font_color': true,
        'custom_ui_font_color': color.toARGB32(),
      });
      FlutterSecureStorage.setMockInitialValues({});

      final restored = SettingsProvider();
      await restored.initialize();

      expect(restored.uiFontColorFor(Brightness.light), color);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('use_custom_ui_font_color'), isFalse);
    });

    test('旧版开关为 false 时残留颜色不应在重启后复活', () async {
      const color = Color(0xFF654321);
      SharedPreferences.setMockInitialValues({
        'use_custom_ui_font_color': false,
        'custom_ui_font_color': color.toARGB32(),
      });
      FlutterSecureStorage.setMockInitialValues({});

      final first = SettingsProvider();
      await first.initialize();
      expect(first.customUiFontColor, isNull);

      // 迁移已删除开关键，二次启动只看颜色键；颜色键必须一并清掉，否则会复活
      final second = SettingsProvider();
      await second.initialize();
      expect(second.customUiFontColor, isNull);
      expect(
        second.uiFontColorFor(Brightness.light),
        SettingsProvider.uiFontColors[0],
      );
    });

    test('initialize 应加载自定义图标颜色', () async {
      const color = Color(0xFF10B981);
      SharedPreferences.setMockInitialValues({
        'custom_icon_color': color.toARGB32(),
      });
      FlutterSecureStorage.setMockInitialValues({});

      final restored = SettingsProvider();
      await restored.initialize();

      expect(restored.customIconColor, color);
    });

    test('图标色旧的 use_custom 开关应被一次性迁移掉', () async {
      const color = Color(0xFF10B981);
      SharedPreferences.setMockInitialValues({
        'use_custom_icon_color': true,
        'custom_icon_color': color.toARGB32(),
        'use_custom_card_color': false,
        'custom_card_color': const Color(0xFF1E1E1E).toARGB32(),
      });
      FlutterSecureStorage.setMockInitialValues({});

      final first = SettingsProvider();
      await first.initialize();

      // 开关为 true 的图标色迁移成自定义覆盖；开关为 false 的卡片色残留值应丢弃
      expect(first.customIconColor, color);
      expect(first.customCardColor, isNull);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('use_custom_icon_color'), isFalse);
      expect(prefs.containsKey('use_custom_card_color'), isFalse);
      expect(prefs.containsKey('custom_card_color'), isFalse);

      // 二次启动不得让被丢弃的卡片色复活
      final second = SettingsProvider();
      await second.initialize();
      expect(second.customIconColor, color);
      expect(second.customCardColor, isNull);
    });

    test('旧版残留的 overlay 背景效果应归一为 blur 并落盘', () async {
      SharedPreferences.setMockInitialValues({
        'background_effect': 'overlay',
        'background_overlay_opacity': 0.8,
      });
      FlutterSecureStorage.setMockInitialValues({});

      final first = SettingsProvider();
      await first.initialize();

      expect(first.backgroundEffect, 'blur');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('background_effect'), 'blur');
      expect(prefs.containsKey('background_overlay_opacity'), isFalse);
    });

    test('莫奈启用时迁移应把方案 primary 落成自定义主题色并清空 monet 键', () async {
      const monetPrimary = Color(0xFF7C4DFF);
      const suppressedCustom = Color(0xFFFF0000);
      SharedPreferences.setMockInitialValues({
        'theme_mode': ThemeMode.light.index,
        'monet_enabled': true,
        'active_monet_config_id': 'cfg-1',
        'saved_monet_configs': jsonEncode([
          {
            'id': 'cfg-1',
            'name': '我的配色',
            'sourceColor': const Color(0xFF112233).toARGB32(),
            'scheme': {
              'lightScheme': {'primary': monetPrimary.toARGB32()},
              'darkScheme': {'primary': const Color(0xFFAAAAAA).toARGB32()},
            },
          },
        ]),
        'use_custom_theme_color': true,
        'custom_theme_color': suppressedCustom.toARGB32(),
      });
      FlutterSecureStorage.setMockInitialValues({});

      final first = SettingsProvider();
      await first.initialize();

      // 渲染上莫奈一直压过自定义色，迁移结果必须取莫奈的 primary
      expect(first.customThemeColor, monetPrimary);
      expect(first.primaryColor, monetPrimary);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('monet_enabled'), isFalse);
      expect(prefs.containsKey('active_monet_config_id'), isFalse);
      expect(prefs.containsKey('saved_monet_configs'), isFalse);
      expect(prefs.getInt('custom_theme_color'), monetPrimary.toARGB32());

      // 二次启动不得回跳到被莫奈压制的旧自定义色
      final second = SettingsProvider();
      await second.initialize();
      expect(second.customThemeColor, monetPrimary);
    });

    test('莫奈未启用时迁移只清键、不改主题色', () async {
      const custom = Color(0xFF123456);
      SharedPreferences.setMockInitialValues({
        'monet_enabled': false,
        'active_monet_config_id': 'cfg-1',
        'saved_monet_configs': '[]',
        'use_custom_theme_color': true,
        'custom_theme_color': custom.toARGB32(),
      });
      FlutterSecureStorage.setMockInitialValues({});

      final provider = SettingsProvider();
      await provider.initialize();

      expect(provider.customThemeColor, custom);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('monet_enabled'), isFalse);
    });

    test('setThemeMode 应更新内存和持久化存储', () async {
      await provider.setThemeMode(ThemeMode.dark);
      expect(provider.themeMode, ThemeMode.dark);
      await flushPersist();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('theme_mode'), ThemeMode.dark.index);
    });

    test('setFontSize 应更新内存和持久化存储', () async {
      await provider.setFontSize(20.0);
      expect(provider.fontSize, 20.0);
      await flushPersist();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('font_size'), 20.0);
    });

    test('setButtonStyleMode 应更新内存和持久化存储', () async {
      await provider.setButtonStyleMode(AppButtonStyleMode.softShadow);
      expect(provider.buttonStyleMode, AppButtonStyleMode.softShadow);
      expect(provider.useBorderlessButtons, isTrue);
      await flushPersist();

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('button_style_mode'),
        AppButtonStyleMode.softShadow.name,
      );
    });

    test('WebDAV 密码应存储在 SecureStorage 中', () async {
      const password = 'secret_password';
      await provider.setWebdavPassword(password);

      // 使用安全方法验证密码
      final creds = provider.getWebdavCredentials();
      expect(creds['password'], password);

      // 验证 SecureStorage
      const storage = FlutterSecureStorage();
      expect(await storage.read(key: 'webdav_password'), password);
    });

    test('setAutoSyncEnabled 应更新状态', () async {
      await provider.setAutoSyncEnabled(true);
      expect(provider.autoSyncEnabled, true);
      await flushPersist();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('auto_sync_enabled'), true);
    });

    test('setSyncFolderName 应更新状态', () async {
      await provider.setSyncFolderName('MyFolder');
      expect(provider.syncFolderName, 'MyFolder');
      await flushPersist();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('sync_folder_name'), 'MyFolder');
    });

    test('编辑器背景模糊设置应更新并持久化', () async {
      await provider.setEditorBackgroundBlurEnabled(true);
      await provider.setEditorBackgroundBlur(18.0);
      expect(provider.editorBackgroundBlurEnabled, isTrue);
      expect(provider.editorBackgroundBlur, 18.0);
      await flushPersist();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('editor_background_blur_enabled'), isTrue);
      expect(prefs.getDouble('editor_background_blur'), 18.0);
    });

    test('背景亮度设置应更新并持久化', () async {
      await provider.setBackgroundBrightness(1.25);
      await provider.setEditorBackgroundBrightness(0.8);

      expect(provider.backgroundBrightness, 1.25);
      expect(provider.editorBackgroundBrightness, 0.8);
      await flushPersist();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('background_brightness'), 1.25);
      expect(prefs.getDouble('editor_background_brightness'), 0.8);
    });

    test('下载代理列表应去空行去重，并按顺序持久化', () async {
      await provider.setUpdateProxies([
        'https://a.example.com/',
        '  ',
        'https://b.example.com',
        'https://a.example.com/',
      ]);

      expect(provider.updateProxies, [
        'https://a.example.com/',
        'https://b.example.com',
      ]);
      await flushPersist();

      final prefs = await SharedPreferences.getInstance();
      expect(jsonDecode(prefs.getString('update_proxies')!), <String>[
        'https://a.example.com/',
        'https://b.example.com',
      ]);
    });

    test('重启后应恢复代理列表，损坏数据按空处理', () async {
      await provider.setUpdateProxies(['https://a.example.com/']);
      await flushPersist();

      final reloaded = SettingsProvider();
      await reloaded.initialize();
      expect(reloaded.updateProxies, ['https://a.example.com/']);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('update_proxies', '{损坏的 JSON');

      final corrupted = SettingsProvider();
      await corrupted.initialize();
      expect(corrupted.updateProxies, isEmpty);
    });

    test('旧色板索引应一次性按色相映射到新色板且可幂等', () async {
      SharedPreferences.setMockInitialValues({
        'primary_color_index': 3, // 旧「琥珀」
        'ui_font_color_index': 11, // 旧「洋红」
      });

      final migrated = SettingsProvider();
      await migrated.initialize();

      expect(migrated.primaryColorIndex, 1); // 新「赭石」
      expect(migrated.uiFontColorIndex, 2); // 新「暮紫」
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('palette_v2_remap_done'), isTrue);
      expect(prefs.getInt('primary_color_index'), 1);

      final second = SettingsProvider();
      await second.initialize();
      expect(second.primaryColorIndex, 1);
      expect(second.uiFontColorIndex, 2);
    });

    test('越界索引应夹回有效范围而不是抛错', () async {
      SharedPreferences.setMockInitialValues({'primary_color_index': 47});

      final provider = SettingsProvider();
      await provider.initialize();

      expect(
        provider.primaryColorIndex,
        SettingsProvider.themeColors.length - 1,
      );
      expect(provider.primaryColor, isNotNull);
    });
  });
}
