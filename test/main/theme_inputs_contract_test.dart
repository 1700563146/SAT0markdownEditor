import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mdreader/main.dart';
import 'package:mdreader/providers/settings_provider.dart';
import 'package:mdreader/utils/app_style.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePathProviderPlatform extends PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() async => 'C:/fake/documents';

  @override
  Future<String?> getApplicationSupportPath() async => 'C:/fake/support';

  @override
  Future<String?> getTemporaryPath() async => 'C:/fake/tmp';
}

Future<SettingsProvider> _freshSettings() async {
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  PathProviderPlatform.instance = _FakePathProviderPlatform();
  final settings = SettingsProvider();
  await settings.initialize();
  return settings;
}

void main() {
  // SettingsProvider.initialize 会读 WidgetsBinding.instance 取系统语言
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ThemeInputs 覆盖全部主题相关设置', () {
    // ThemeInputs 是 Selector 的比较依据：漏掉某个字段，该设置就会静默失效。
    // 这里逐个改动设置项，断言 ThemeInputs 一定随之变化。
    final mutations = <String, Future<void> Function(SettingsProvider)>{
      'primaryColorIndex': (s) => s.setPrimaryColorIndex(3),
      'customThemeColor': (s) => s.setCustomThemeColor(const Color(0xFF123456)),
      'uiFontColorIndex': (s) => s.setUiFontColorIndex(5),
      'customUiFontColor': (s) => s.setCustomUiFontColor(const Color(0xFF654321)),
      'uiFontFamily': (s) => s.setUiFontFamily('Noto Sans SC'),
      'lightThemeIndex': (s) => s.setLightThemeIndex(2),
      'darkThemeIndex': (s) => s.setDarkThemeIndex(3),
      'buttonStyleMode': (s) => s.setButtonStyleMode(AppButtonStyleMode.classic),
      'cardOpacity': (s) => s.setCardOpacity(0.6),
      'customCardColor': (s) => s.setCustomCardColor(const Color(0xFF1E1E1E)),
      'customIconColor': (s) => s.setCustomIconColor(const Color(0xFF10B981)),
      'themeMode': (s) => s.setThemeMode(ThemeMode.dark),
      // 测试环境系统语言即 en，必须挑一个与默认不同的语种
      'locale': (s) => s.setLocale(const Locale('zh')),
    };
    // editorFontColorIndex 不在此列：编辑器文字色由 editor_screen 直接读取，
    // 不进 ThemeData，因此不应触发 MaterialApp 重建。

    for (final entry in mutations.entries) {
      test('改动 ${entry.key} 必须反映到 ThemeInputs', () async {
        final baseline = ThemeInputs.from(await _freshSettings());
        final changed = await _freshSettings();
        await entry.value(changed);

        expect(
          ThemeInputs.from(changed),
          isNot(equals(baseline)),
          reason: '${entry.key} 变了但 ThemeInputs 没变，说明它漏了字段，'
              '该设置不会触发主题重建',
        );
      });
    }

    test('设置未变时 ThemeInputs 相等，可抑制无谓重建', () async {
      final a = ThemeInputs.from(await _freshSettings());
      final b = ThemeInputs.from(await _freshSettings());
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('界面文字色按明暗分别解析，深色变体更亮', () async {
      final settings = await _freshSettings();
      await settings.setUiFontColorIndex(0);
      final inputs = ThemeInputs.from(settings);

      expect(
        inputs.uiFontColorFor(Brightness.dark).computeLuminance(),
        greaterThan(inputs.uiFontColorFor(Brightness.light).computeLuminance()),
      );
    });

    test('自定义文字色在两种明暗下原样生效', () async {
      const custom = Color(0xFF123456);
      final settings = await _freshSettings();
      await settings.setCustomUiFontColor(custom);
      final inputs = ThemeInputs.from(settings);

      expect(inputs.uiFontColorFor(Brightness.light), custom);
      expect(inputs.uiFontColorFor(Brightness.dark), custom);
    });
  });
}
