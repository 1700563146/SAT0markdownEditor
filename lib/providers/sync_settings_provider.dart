// ============================================================================
// 同步领域设置 Provider（T-09 拆分）
//
// 管理云同步相关的设置选项：
// - 同步类型（WebDAV / FTP）与凭据
// - 同步文件夹、路径前缀、自动同步
// - 浮动按钮显示模式
//
// 由门面 SettingsProvider 组合并转发，不直接暴露给 UI。
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'settings_persistence_mixin.dart';

/// 同步领域设置提供者
class SyncSettingsProvider extends ChangeNotifier
    with SettingsPersistenceMixin {
  // ==================== 安全存储 ====================

  /// 安全存储（用于敏感信息如密码）
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  // ==================== 云同步设置 ====================

  /// 同步类型（webdav 或 ftp）
  String _syncType = 'webdav';

  /// 浮动按钮显示模式：auto（智能隐藏）、always（永久显示）、never（永久隐藏）
  String _floatingButtonsMode = 'auto';

  // ==================== 云同步凭据 ====================

  /// WebDAV 服务器地址
  String _webdavUrl = '';

  /// WebDAV 用户名
  String _webdavUsername = '';

  /// WebDAV 密码
  String _webdavPassword = '';

  /// FTP 服务器 URL (格式: ftp://host:port)
  String _ftpUrl = '';

  /// FTP 用户名
  String _ftpUsername = '';

  /// FTP 密码
  String _ftpPassword = '';

  /// 云端同步文件夹名称
  String _syncFolderName = 'Taku-MD';

  /// 云端文件夹路径前缀（不含文件夹名称）
  String _syncRemotePath = '/storage/emulated/0/';

  /// 是否启用自动同步
  bool _autoSyncEnabled = false;

  /// 上次同步时间
  DateTime? _lastSyncTime;

  // ==================== Getters ====================

  String get syncType => _syncType;
  String get floatingButtonsMode => _floatingButtonsMode;
  String get webdavUrl => _webdavUrl;
  String get webdavUsername => _webdavUsername;
  // 密码不通过公共 getter 暴露，仅在内部使用
  // String get webdavPassword => _webdavPassword;  // 已移除：安全性改进
  String get ftpUrl => _ftpUrl;

  /// 从 FTP URL 解析主机名
  String get ftpHost {
    try {
      final url = _ftpUrl.trim();
      if (url.isEmpty) return '';

      // 移除 ftp:// 前缀和末尾斜杠
      String cleanUrl = url;
      if (cleanUrl.startsWith('ftp://')) {
        cleanUrl = cleanUrl.substring(6);
      }
      cleanUrl = cleanUrl.replaceAll(RegExp(r'/+$'), '');

      // 分离主机和端口
      if (cleanUrl.contains(':')) {
        return cleanUrl.split(':')[0];
      }
      return cleanUrl;
    } catch (e) {
      return '';
    }
  }

  /// 从 FTP URL 解析端口
  int get ftpPort {
    try {
      final url = _ftpUrl.trim();
      if (url.isEmpty) return 21;

      // 移除 ftp:// 前缀和末尾斜杠
      String cleanUrl = url;
      if (cleanUrl.startsWith('ftp://')) {
        cleanUrl = cleanUrl.substring(6);
      }
      cleanUrl = cleanUrl.replaceAll(RegExp(r'/+$'), '');

      // 提取端口
      if (cleanUrl.contains(':')) {
        final parts = cleanUrl.split(':');
        if (parts.length >= 2) {
          return int.tryParse(parts[1]) ?? 21;
        }
      }
      return 21;
    } catch (e) {
      return 21;
    }
  }

  String get ftpUsername => _ftpUsername;
  // 密码不通过公共 getter 暴露，仅在内部使用
  // String get ftpPassword => _ftpPassword;  // 已移除：安全性改进
  String get syncFolderName => _syncFolderName;
  String get syncRemotePath => _syncRemotePath;
  bool get autoSyncEnabled => _autoSyncEnabled;
  DateTime? get lastSyncTime => _lastSyncTime;

  bool get isWebdavConfigured =>
      _webdavUrl.isNotEmpty &&
      _webdavUsername.isNotEmpty &&
      _webdavPassword.isNotEmpty;
  bool get isFtpConfigured =>
      _ftpUrl.isNotEmpty && _ftpUsername.isNotEmpty && _ftpPassword.isNotEmpty;
  bool get isSyncConfigured =>
      _syncType == 'webdav' ? isWebdavConfigured : isFtpConfigured;

  // ==================== 云同步凭据 Getters ====================

  /// 安全地获取 WebDAV 凭据（仅用于创建服务实例）
  /// 不要在 UI 层调用此方法
  Map<String, String> getWebdavCredentials() {
    return {
      'url': _webdavUrl,
      'username': _webdavUsername,
      'password': _webdavPassword,
    };
  }

  /// 安全地获取 FTP 凭据（仅用于创建服务实例）
  /// 不要在 UI 层调用此方法
  Map<String, String> getFtpCredentials() {
    return {'url': _ftpUrl, 'username': _ftpUsername, 'password': _ftpPassword};
  }

  // ==================== 初始化 ====================

  /// 读取同步领域设置
  Future<void> initialize(SharedPreferences prefs) async {
    _syncType = prefs.getString('sync_type') ?? 'webdav';
    _floatingButtonsMode = prefs.getString('floating_buttons_mode') ?? 'auto';
    _webdavUrl = prefs.getString('webdav_url') ?? '';
    _webdavUsername = prefs.getString('webdav_username') ?? '';

    // FTP URL 设置（包含从旧格式的迁移逻辑）
    _ftpUrl = prefs.getString('ftp_url') ?? '';
    if (_ftpUrl.isEmpty) {
      // 迁移旧格式：从 ftp_host 和 ftp_port 生成 URL
      final oldHost = prefs.getString('ftp_host') ?? '';
      final oldPort = prefs.getInt('ftp_port') ?? 21;
      if (oldHost.isNotEmpty) {
        _ftpUrl = 'ftp://$oldHost:$oldPort';
        // 保存新格式
        await prefs.setString('ftp_url', _ftpUrl);
        // 清理旧数据
        await prefs.remove('ftp_host');
        await prefs.remove('ftp_port');
      }
    }

    _ftpUsername = prefs.getString('ftp_username') ?? '';
    _syncFolderName = prefs.getString('sync_folder_name') ?? 'Taku-MD';
    _syncRemotePath =
        prefs.getString('sync_remote_path') ?? '/storage/emulated/0/';
    _autoSyncEnabled = prefs.getBool('auto_sync_enabled') ?? false;
    final lastSyncMs = prefs.getInt('last_sync_time');
    _lastSyncTime = lastSyncMs != null
        ? DateTime.fromMillisecondsSinceEpoch(lastSyncMs)
        : null;

    // 从安全存储读取密码（包含迁移逻辑）
    _webdavPassword = await _secureStorage.read(key: 'webdav_password') ?? '';
    _ftpPassword = await _secureStorage.read(key: 'ftp_password') ?? '';

    // 迁移：如果安全存储中没有但 SharedPreferences 中有，则迁移
    if (_webdavPassword.isEmpty) {
      final oldPassword = prefs.getString('webdav_password');
      if (oldPassword != null && oldPassword.isNotEmpty) {
        _webdavPassword = oldPassword;
        await _secureStorage.write(key: 'webdav_password', value: oldPassword);
        await prefs.remove('webdav_password'); // 删除明文密码
      }
    }
  }

  // ==================== 云同步设置方法 ====================

  /// 设置同步类型
  Future<void> setSyncType(String type) async {
    _syncType = type;
    notifyListeners();
    schedulePersist('sync_type', type);
  }

  /// 设置浮动按钮显示模式
  Future<void> setFloatingButtonsMode(String mode) async {
    if (_floatingButtonsMode == mode) return;
    _floatingButtonsMode = mode;
    notifyListeners();
    schedulePersist('floating_buttons_mode', mode);
  }

  /// 设置 WebDAV 服务器地址
  Future<void> setWebdavUrl(String url) async {
    _webdavUrl = url;
    notifyListeners();
    schedulePersist('webdav_url', url);
  }

  /// 设置 WebDAV 用户名
  Future<void> setWebdavUsername(String username) async {
    _webdavUsername = username;
    notifyListeners();
    schedulePersist('webdav_username', username);
  }

  /// 设置 WebDAV 密码（安全存储）
  Future<void> setWebdavPassword(String password) async {
    _webdavPassword = password;
    await _secureStorage.write(key: 'webdav_password', value: password);
    notifyListeners();
  }

  /// 设置 FTP 服务器 URL
  Future<void> setFtpUrl(String url) async {
    // 规范化 URL：移除末尾的斜杠
    String cleanUrl = url.trim().replaceAll(RegExp(r'/+$'), '');

    _ftpUrl = cleanUrl;
    notifyListeners();
    schedulePersist('ftp_url', cleanUrl);
  }

  /// 设置 FTP 用户名
  Future<void> setFtpUsername(String username) async {
    _ftpUsername = username;
    notifyListeners();
    schedulePersist('ftp_username', username);
  }

  /// 设置 FTP 密码（安全存储）
  Future<void> setFtpPassword(String password) async {
    _ftpPassword = password;
    await _secureStorage.write(key: 'ftp_password', value: password);
    notifyListeners();
  }

  /// 设置云端同步文件夹名称
  Future<void> setSyncFolderName(String folderName) async {
    _syncFolderName = folderName;
    notifyListeners();
    schedulePersist('sync_folder_name', folderName);
  }

  /// 设置云端文件夹路径前缀
  Future<void> setSyncRemotePath(String path) async {
    _syncRemotePath = path;
    notifyListeners();
    schedulePersist('sync_remote_path', path);
  }

  /// 获取完整的云端文件夹路径（路径前缀 + 文件夹名称）
  String getFullSyncPath() {
    String fullPath = _syncRemotePath.trim();

    // 如果没有路径前缀，直接返回文件夹名称
    if (fullPath.isEmpty) {
      return _syncFolderName;
    }

    // 确保路径以 / 结尾
    if (!fullPath.endsWith('/')) {
      fullPath += '/';
    }

    // 自动补齐文件夹名称（如果路径不以文件夹名称结尾）
    if (!fullPath.endsWith('$_syncFolderName/') &&
        !fullPath.endsWith(_syncFolderName)) {
      fullPath += _syncFolderName;
    }

    return fullPath;
  }

  /// 设置自动同步开关
  Future<void> setAutoSyncEnabled(bool enabled) async {
    _autoSyncEnabled = enabled;
    notifyListeners();
    schedulePersist('auto_sync_enabled', enabled);
  }

  /// 更新上次同步时间
  Future<void> updateLastSyncTime() async {
    _lastSyncTime = DateTime.now();
    notifyListeners();
    schedulePersist('last_sync_time', _lastSyncTime!.millisecondsSinceEpoch);
  }

  /// 保存所有 WebDAV 凭据
  ///
  /// 密码使用安全存储，URL 和用户名使用 SharedPreferences
  Future<void> saveWebdavCredentials({
    required String url,
    required String username,
    required String password,
  }) async {
    _webdavUrl = url;
    _webdavUsername = username;
    _webdavPassword = password;

    final prefs = await this.prefs();
    await prefs.setString('webdav_url', url);
    await prefs.setString('webdav_username', username);
    // 密码使用安全存储
    await _secureStorage.write(key: 'webdav_password', value: password);
    notifyListeners();
  }
}
