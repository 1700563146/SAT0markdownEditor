import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// T-09：设置持久化基础设施（mixin）
///
/// 供按领域拆分的子 Provider 复用：SharedPreferences 缓存、防抖持久化、
/// 自定义颜色一次性迁移、已删除的莫奈配色系统一次性迁移。
///
/// 方法命名不带下划线，是因为 Dart 私有成员不可跨库继承访问：
/// 子 Provider 位于独立文件（独立库），只能调用本 mixin 的公有成员。
/// 这些方法仅面向 SettingsProvider 领域子类，请勿在 UI 层调用。
mixin SettingsPersistenceMixin on ChangeNotifier {
  // ==================== 持久化缓存 ====================

  /// 缓存的 SharedPreferences 实例，避免每次 setter 都 getInstance()
  SharedPreferences? _prefsCache;

  /// 防抖持久化 Timer，用于 Slider 等高频更新场景
  Timer? _persistDebounce;

  /// 待持久化的键值对
  final Map<String, dynamic> _pendingPersist = {};

  /// 获取（并缓存）SharedPreferences 实例
  Future<SharedPreferences> prefs() async {
    return _prefsCache ??= await SharedPreferences.getInstance();
  }

  /// 防抖持久化：500ms 内多次调用只执行一次写入
  void schedulePersist(String key, dynamic value) {
    _pendingPersist[key] = value;
    _persistDebounce?.cancel();
    _persistDebounce = Timer(const Duration(milliseconds: 500), () async {
      final entries = Map<String, dynamic>.from(_pendingPersist);
      _pendingPersist.clear();
      final prefs = await this.prefs();
      for (final entry in entries.entries) {
        final k = entry.key;
        final v = entry.value;
        if (v is double)
          await prefs.setDouble(k, v);
        else if (v is int)
          await prefs.setInt(k, v);
        else if (v is bool)
          await prefs.setBool(k, v);
        else if (v is String)
          await prefs.setString(k, v);
      }
    });
  }

  /// 写入自定义颜色；传 null 表示清除覆盖、回落预设
  Future<void> writeCustomColor(String key, Color? color) async {
    final prefs = await this.prefs();
    if (color == null) {
      await prefs.remove(key);
    } else {
      await prefs.setInt(key, color.toARGB32());
    }
  }

  /// 一次性迁移旧的「自定义颜色」格式：旧模型靠 `use_custom_*` 开关判定是否覆盖预设，
  /// 新模型只看颜色键。开关为 false 时残留的颜色值要一并删除，否则下次启动因开关键已
  /// 消失而把它当成自定义色复活。
  Future<Color?> migrateCustomColor(
    SharedPreferences prefs, {
    required String colorKey,
    required String legacyFlagKey,
  }) async {
    final value = prefs.getInt(colorKey);
    if (!prefs.containsKey(legacyFlagKey)) {
      return value != null ? Color(value) : null;
    }
    final useCustom = prefs.getBool(legacyFlagKey) ?? false;
    await prefs.remove(legacyFlagKey);
    if (!useCustom) {
      await prefs.remove(colorKey);
      return null;
    }
    return value != null ? Color(value) : null;
  }

  /// 一次性迁移已删除的莫奈配色系统。
  ///
  /// 莫奈在渲染上整块替换 colorScheme，用户实际看到的是它派生出的 primary，
  /// 因此把激活方案的 primary 迁成「自定义主题色」，避免升级后界面突然变色。
  /// 三个 monet 键无条件删除，保证只迁移一次。
  Future<Color?> migrateMonetAccent(
    SharedPreferences prefs,
    ThemeMode themeMode,
  ) async {
    final enabled = prefs.getBool('monet_enabled') ?? false;
    final activeId = prefs.getString('active_monet_config_id');
    final rawConfigs = prefs.getString('saved_monet_configs');
    await prefs.remove('monet_enabled');
    await prefs.remove('active_monet_config_id');
    await prefs.remove('saved_monet_configs');

    if (!enabled ||
        activeId == null ||
        rawConfigs == null ||
        rawConfigs.isEmpty) {
      return null;
    }
    try {
      final configs = json.decode(rawConfigs) as List<dynamic>;
      final active = configs.whereType<Map<String, dynamic>>().firstWhere(
        (c) => c['id'] == activeId,
      );
      final scheme = active['scheme'] as Map<String, dynamic>?;
      if (scheme == null) return null;
      // 取用户当时真正看到的那一套：深色用 darkScheme，其余用 lightScheme
      final bucket = themeMode == ThemeMode.dark
          ? 'darkScheme'
          : 'lightScheme';
      final primary = (scheme[bucket] as Map<String, dynamic>?)?['primary'];
      return primary is int ? Color(primary) : null;
    } catch (_) {
      return null;
    }
  }
}
