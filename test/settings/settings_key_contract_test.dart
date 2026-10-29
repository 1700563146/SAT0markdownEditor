import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 防止「假设置」重新长出来。
///
/// 本轮重构前存在的四类问题都能被这里的两条不变量拦住：
/// - particleGlobal / backgroundOverlayOpacity：有持久化键、有 getter，但 lib/ 里
///   没有任何消费方，用户改了毫无反应；
/// - 莫奈开启后主题色失效：属于渲染层覆写，由 theme_inputs_contract_test 覆盖。
void main() {
  final providerFile = File('lib/providers/settings_provider.dart');
  final libDir = Directory('lib');

  late String providerSource;
  late Map<String, String> allSources;

  setUpAll(() {
    expect(providerFile.existsSync(), isTrue, reason: 'provider 路径变了要同步改本测试');
    providerSource = providerFile.readAsStringSync();
    allSources = {
      for (final f
          in libDir
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart')))
        f.path: f.readAsStringSync(),
    };
  });

  test('每个颜色/字体相关持久化键都必须被读回', () {
    // 只统计真实写入；prefs.remove 是一次性迁移清理，本就不该再被读
    final written =
        _keysMatch(
          providerSource,
          RegExp(
            r"prefs\.set(?:String|Int|Double|Bool|StringList)\(\s*'([^']+)'",
          ),
        ).union(
          _keysMatch(providerSource, RegExp(r"_schedulePersist\(\s*'([^']+)'")),
        );

    final colorKeys = written.where(_isColorOrTypeKey).toSet();
    expect(colorKeys, isNotEmpty, reason: '键名规则失效会让本测试静默空跑');

    final orphaned = colorKeys.where((key) {
      final direct = RegExp(
        "prefs\\.get(?:String|Int|Double|Bool|StringList)\\(\\s*'$key'",
      ).hasMatch(providerSource);
      // 迁移/取色辅助函数以 colorKey: 'x' 形式接收，内部再用变量读取
      final viaHelper = RegExp(
        "(?:colorKey|legacyFlagKey):\\s*'${RegExp.escape(key)}'",
      ).hasMatch(providerSource);
      return !direct && !viaHelper;
    }).toList();

    expect(orphaned, isEmpty, reason: '这些键只写不读，重启后设置会丢：$orphaned');
  });

  test('每个颜色/字体相关 getter 都必须有消费方', () {
    final getters =
        RegExp(
              r'^\s*(?:Color|Locale|ThemeMode|double|int|bool|String\??)\s+get\s+(\w+)',
              multiLine: true,
            )
            .allMatches(providerSource)
            .map((m) => m.group(1)!)
            .where(_isColorOrTypeKey)
            .toSet();

    expect(getters, isNotEmpty, reason: 'getter 规则失效会让本测试静默空跑');

    final unconsumed = <String>[];
    for (final name in getters) {
      final usage = RegExp('\\.$name\\b');
      final usedElsewhere = allSources.entries.any(
        (entry) =>
            entry.key != providerFile.path &&
            !entry.key.contains(
              '${Platform.pathSeparator}l10n${Platform.pathSeparator}',
            ) &&
            usage.hasMatch(entry.value),
      );
      if (!usedElsewhere) unconsumed.add(name);
    }

    expect(
      unconsumed,
      isEmpty,
      reason:
          '这些设置项能被修改并持久化，但没有任何界面或主题代码读取它们，'
          '属于用户改了没反应的假设置：$unconsumed',
    );
  });

  test('已删除的死键不得回流到 provider', () {
    // 这些键的读取方已随功能一起删除；若重新出现说明有人又写回了只存不读的状态
    const retired = [
      'debug_enabled',
      'tab_bar_style',
      'monet_enabled',
      'active_monet_config_id',
      'saved_monet_configs',
      'particle_global',
      'background_overlay_opacity',
    ];
    for (final key in retired) {
      final written = RegExp(
        "(?:prefs\\.set\\w+|_schedulePersist)\\(\\s*'$key'",
      ).hasMatch(providerSource);
      expect(written, isFalse, reason: '$key 已被删除，不应再被写入');
    }
  });
}

Set<String> _keysMatch(String source, RegExp pattern) =>
    pattern.allMatches(source).map((m) => m.group(1)!).toSet();

/// 只关心本轮重构涉及的颜色/字体/表面相关键，避免把云同步等无关键卷进来。
bool _isColorOrTypeKey(String name) {
  const lowered = [
    'color',
    'theme',
    'font',
    'opacity',
    'icon',
    'card',
    'style',
    'locale',
  ];
  return lowered.any(name.toLowerCase().contains);
}
