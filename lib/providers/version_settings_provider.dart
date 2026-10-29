// ============================================================================
// 版本历史设置（T-13）
//
// 管理版本历史管理页的配置项：
// - 单文档保留快照数 N（默认 20，与 T-01 默认策略一致，范围 1~60）
// - 版本容量上限（MB，0 表示不限制，超出后由 VersionService 清理最旧快照）
//
// 采用与其它子 Provider 相同的 SettingsPersistenceMixin 防抖持久化。
// ============================================================================

import 'package:flutter/foundation.dart';

import 'settings_persistence_mixin.dart';

/// 版本历史设置提供者（T-13）
class VersionSettingsProvider extends ChangeNotifier
    with SettingsPersistenceMixin {
  // ==================== 键名与常量 ====================

  /// SharedPreferences 键：单文档保留快照数
  static const String kMaxVersionsPerFileKey = 'version_max_versions_per_file';

  /// SharedPreferences 键：版本容量上限（MB）
  static const String kMaxTotalSizeMbKey = 'version_max_total_size_mb';

  /// 单文档默认保留快照数（与 VersionService.defaultMaxVersionsPerFile 对齐）
  static const int defaultMaxVersionsPerFile = 20;

  /// 单文档保留快照数下限
  static const int minVersionsPerFile = 1;

  /// 单文档保留快照数上限（与 VersionService.maxVersionsHardCap 对齐）
  static const int maxVersionsPerFileHard = 60;

  /// 容量上限默认值（0 = 不限制）
  static const int defaultMaxTotalSizeMb = 0;

  /// 容量上限可配置的最大值（MB，约 2GB，防止误配置导致频繁全盘裁剪）
  static const int maxTotalSizeMbCap = 2048;

  // ==================== 状态 ====================

  int _maxVersionsPerFile = defaultMaxVersionsPerFile;
  int _maxTotalSizeMb = defaultMaxTotalSizeMb;

  /// 单文档保留快照数 N
  int get maxVersionsPerFile => _maxVersionsPerFile;

  /// 版本容量上限（MB），0 表示不限制
  int get maxTotalSizeMb => _maxTotalSizeMb;

  /// 是否启用了容量上限
  bool get capacityLimitEnabled => _maxTotalSizeMb > 0;

  // ==================== 初始化 ====================

  /// 从 SharedPreferences 恢复版本历史设置
  Future<void> initialize() async {
    final prefs = await this.prefs();
    final rawN = prefs.getInt(kMaxVersionsPerFileKey) ?? defaultMaxVersionsPerFile;
    _maxVersionsPerFile = rawN.clamp(minVersionsPerFile, maxVersionsPerFileHard);
    final rawMb =
        prefs.getInt(kMaxTotalSizeMbKey) ?? defaultMaxTotalSizeMb;
    _maxTotalSizeMb = rawMb.clamp(0, maxTotalSizeMbCap);
  }

  // ==================== 设置方法 ====================

  /// 设置单文档保留快照数（自动钳制到 [minVersionsPerFile, maxVersionsPerFileHard]）
  Future<void> setMaxVersionsPerFile(int n) async {
    final value = n.clamp(minVersionsPerFile, maxVersionsPerFileHard);
    if (value == _maxVersionsPerFile) return;
    _maxVersionsPerFile = value;
    notifyListeners();
    schedulePersist(kMaxVersionsPerFileKey, value);
  }

  /// 设置版本容量上限（MB，0 表示不限制，自动钳制到 [0, maxTotalSizeMbCap]）
  Future<void> setMaxTotalSizeMb(int mb) async {
    final value = mb.clamp(0, maxTotalSizeMbCap);
    if (value == _maxTotalSizeMb) return;
    _maxTotalSizeMb = value;
    notifyListeners();
    schedulePersist(kMaxTotalSizeMbKey, value);
  }
}
