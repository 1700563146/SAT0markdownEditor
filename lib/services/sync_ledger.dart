// ============================================================================
// 云同步台账
//
// 记录每个文件最近一次成功同步时的状态，用于三方比较：
// - contentHash：同步完成时本地内容的 SHA-256
// - lastSyncedLocalMtime：同步完成时本地文件的修改时间（毫秒）
// - lastSyncedRemoteMtime：同步完成时远程文件在列表中的修改时间（毫秒）
//
// 台账让"本地是否变更 / 远程是否变更"可以被精确判断，
// 避免仅依赖 mtime 造成的时间漂移误判与重复传输。
//
// 续传机制：传输失败时不写入台账，文件下次同步仍会被判定为"待同步"，
// 因此失败清单天然可续传，无需额外持久化。
//
// 台账以 JSON 形式持久化在 SharedPreferences 中，并绑定工作区路径；
// 工作区变更时自动重置。
// ============================================================================

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../utils/debug_log.dart';

/// 单个文件的同步台账记录
class SyncLedgerEntry {
  /// 同步完成时的本地内容 SHA-256
  final String contentHash;

  /// 同步完成时的本地 mtime（毫秒时间戳）
  final int lastSyncedLocalMtime;

  /// 同步完成时远程文件的 mtime（毫秒时间戳；未知为 null）
  final int? lastSyncedRemoteMtime;

  const SyncLedgerEntry({
    required this.contentHash,
    required this.lastSyncedLocalMtime,
    this.lastSyncedRemoteMtime,
  });

  factory SyncLedgerEntry.fromJson(Map<String, dynamic> json) {
    return SyncLedgerEntry(
      contentHash: json['h'] as String,
      lastSyncedLocalMtime: json['lm'] as int,
      lastSyncedRemoteMtime: json['rm'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {'h': contentHash, 'lm': lastSyncedLocalMtime, 'rm': lastSyncedRemoteMtime};
  }
}

/// 云同步台账
class SyncLedger {
  static const String _prefsKey = 'cloud_sync_ledger_v1';

  /// 远程 mtime 比较容差（毫秒），吸收服务器时间精度与取整差异
  static const int remoteMtimeToleranceMs = 2000;

  final String workspacePath;
  final Map<String, SyncLedgerEntry> _entries = {};

  SyncLedger._(this.workspacePath);

  /// 从持久化存储加载台账；工作区路径不一致时返回空台账
  static Future<SyncLedger> load(String workspacePath) async {
    final ledger = SyncLedger._(workspacePath);
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return ledger;

      final data = jsonDecode(raw) as Map<String, dynamic>;
      if (data['workspacePath'] != workspacePath) {
        appDebugLog('SyncLedger: 工作区变更，重置台账');
        return ledger;
      }
      final files = data['files'] as Map<String, dynamic>? ?? {};
      files.forEach((key, value) {
        try {
          ledger._entries[key] = SyncLedgerEntry.fromJson(
            value as Map<String, dynamic>,
          );
        } catch (_) {
          // 单条记录损坏，忽略
        }
      });
    } catch (e) {
      appDebugLog('SyncLedger: 加载失败，使用空台账: $e');
    }
    return ledger;
  }

  /// 查询台账记录
  SyncLedgerEntry? get(String relativePath) => _entries[relativePath];

  /// 写入台账记录（内存），需调用 [save] 持久化
  void set(String relativePath, SyncLedgerEntry entry) {
    _entries[relativePath] = entry;
  }

  /// 删除台账记录（内存），需调用 [save] 持久化
  void remove(String relativePath) {
    _entries.remove(relativePath);
  }

  /// 判断远程文件自上次同步以来是否被修改
  ///
  /// 无台账记录或远程 mtime 未知时返回 true（保守处理，回退到 mtime 比较）。
  bool isRemoteChanged(String relativePath, DateTime remoteMtime) {
    final entry = _entries[relativePath];
    if (entry == null || entry.lastSyncedRemoteMtime == null) return true;
    return (remoteMtime.millisecondsSinceEpoch - entry.lastSyncedRemoteMtime!)
            .abs() >
        remoteMtimeToleranceMs;
  }

  /// 持久化到 SharedPreferences
  Future<void> save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = jsonEncode({
        'workspacePath': workspacePath,
        'files': _entries.map((key, value) => MapEntry(key, value.toJson())),
      });
      await prefs.setString(_prefsKey, payload);
    } catch (e) {
      appDebugLog('SyncLedger: 保存失败: $e');
    }
  }
}
