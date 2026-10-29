// ============================================================================
// 更新领域设置 Provider（T-09 拆分）
//
// 管理应用更新相关的设置选项：
// - 启动时自动检查更新
// - 更新通道（stable / prerelease）
// - 自定义下载代理前缀列表
//
// 由门面 SettingsProvider 组合并转发，不直接暴露给 UI。
// ============================================================================

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'settings_persistence_mixin.dart';

/// 更新领域设置提供者
class UpdateSettingsProvider extends ChangeNotifier
    with SettingsPersistenceMixin {
  // ==================== 更新设置 ====================

  /// 是否在启动时自动检查更新（默认开启）
  bool _autoCheckUpdate = true;

  /// 更新规则：stable=稳定版，prerelease=测试版
  String _updateChannel = 'stable';

  /// 用户自定义下载代理前缀列表，按顺序尝试；为空则直连
  List<String> _updateProxies = [];

  // ==================== Getters ====================

  bool get autoCheckUpdate => _autoCheckUpdate;

  /// 当前更新规则
  String get updateChannel => _updateChannel;

  /// 自定义下载代理前缀列表（按顺序尝试）
  List<String> get updateProxies => List.unmodifiable(_updateProxies);

  // ==================== 初始化 ====================

  /// 读取更新领域设置
  Future<void> initialize(SharedPreferences prefs) async {
    _autoCheckUpdate = prefs.getBool('auto_check_update') ?? true;
    _updateChannel = prefs.getString('update_channel') == 'prerelease'
        ? 'prerelease'
        : 'stable';
    _updateProxies = _decodeProxies(prefs.getString('update_proxies'));
  }

  // ==================== 更新设置方法 ====================

  /// 设置启动时是否自动检查更新
  Future<void> setAutoCheckUpdate(bool value) async {
    _autoCheckUpdate = value;
    notifyListeners();
    schedulePersist('auto_check_update', value);
  }

  /// 设置更新规则
  Future<void> setUpdateChannel(String value) async {
    _updateChannel = value == 'prerelease' ? 'prerelease' : 'stable';
    notifyListeners();
    schedulePersist('update_channel', _updateChannel);
  }

  /// 设置自定义下载代理列表；去空行、去重，顺序即尝试顺序
  Future<void> setUpdateProxies(List<String> proxies) async {
    _updateProxies = _normalizeProxies(proxies);
    notifyListeners();
    schedulePersist('update_proxies', jsonEncode(_updateProxies));
  }

  /// 解析持久化的代理列表，损坏数据按空处理
  static List<String> _decodeProxies(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return _normalizeProxies(decoded.whereType<String>().toList());
    } catch (_) {
      return [];
    }
  }

  static List<String> _normalizeProxies(List<String> items) {
    final result = <String>[];
    for (final item in items) {
      final trimmed = item.trim();
      if (trimmed.isEmpty || result.contains(trimmed)) continue;
      result.add(trimmed);
    }
    return result;
  }
}
