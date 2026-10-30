// ============================================================================
// 编辑器领域设置 Provider（T-09 拆分）
//
// 管理编辑器相关的设置选项：
// - 字体大小、行高、字间距、段落间距
// - 自动保存、退出保存
// - 启动行为、最近打开文件、默认目录、工作区
//
// 由门面 SettingsProvider 组合并转发，不直接暴露给 UI。
// ============================================================================

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/platform_adapter.dart';
import 'settings_persistence_mixin.dart';

/// 编辑器领域设置提供者
class EditorSettingsProvider extends ChangeNotifier
    with SettingsPersistenceMixin {
  // ==================== 编辑器设置 ====================

  /// 编辑器字体大小（6-80px）
  double _fontSize = 16.0;

  /// 是否启用自动保存
  bool _autoSave = false;

  /// 自动保存间隔（秒）
  int _autoSaveInterval = 30;

  /// 退出文档时自动保存
  bool _saveOnExit = false;

  /// 行高（1.0-2.5）
  double _lineHeight = 1.6;

  /// 字间距（-2.0 到 10.0，单位 px）
  double _letterSpacing = 0.0;

  /// 段落间距（0-40px）
  double _paragraphSpacing = 8.0;

  /// 启动行为：blank（空白页）/ restore（恢复上次文件）
  String _startupBehavior = 'blank';

  /// 上次打开的文件路径
  String? _lastOpenedFilePath;

  /// 默认目录路径
  String? _defaultDirectory;

  /// 工作区文件夹名称
  String _workspaceName = 'Taku-md';

  /// 自定义工作区基础路径（可选，为null时使用平台默认路径）
  String? _customWorkspaceBasePath;

  // ==================== Getters ====================

  double get fontSize => _fontSize;
  double get lineHeight => _lineHeight;
  double get letterSpacing => _letterSpacing;
  double get paragraphSpacing => _paragraphSpacing;
  bool get autoSave => _autoSave;
  int get autoSaveInterval => _autoSaveInterval;
  bool get saveOnExit => _saveOnExit;
  String? get defaultDirectory => _defaultDirectory;
  String get workspaceName => _workspaceName;
  String? get customWorkspaceBasePath => _customWorkspaceBasePath;
  String get startupBehavior => _startupBehavior;
  String? get lastOpenedFilePath => _lastOpenedFilePath;

  // ==================== 初始化 ====================

  /// 读取编辑器领域设置
  Future<void> initialize(SharedPreferences prefs) async {
    _fontSize = prefs.getDouble('font_size') ?? 16.0;
    _autoSave = prefs.getBool('auto_save') ?? false;
    _autoSaveInterval = prefs.getInt('auto_save_interval') ?? 30;
    _saveOnExit = prefs.getBool('save_on_exit') ?? false;
    _lineHeight = prefs.getDouble('line_height') ?? 1.6;
    _letterSpacing = prefs.getDouble('letter_spacing') ?? 0.0;
    _paragraphSpacing = prefs.getDouble('paragraph_spacing') ?? 8.0;
    _startupBehavior = prefs.getString('startup_behavior') ?? 'restore';
    _lastOpenedFilePath = prefs.getString('last_opened_file_path');
    if (prefs.containsKey('debug_enabled')) {
      // 调试模式已整体移除，清掉遗留键避免它继续被读回
      await prefs.remove('debug_enabled');
    }
    if (prefs.containsKey('tab_bar_style')) {
      // 导航栏样式已并入「UI 风格」，这个键不再有读取方
      await prefs.remove('tab_bar_style');
    }
    _defaultDirectory = prefs.getString('default_directory');
    _workspaceName = prefs.getString('workspace_name') ?? 'Taku-md';

    // 自定义工作区基础路径 - 如果未设置，使用平台默认路径
    final savedCustomPath = prefs.getString('custom_workspace_base_path');
    if (savedCustomPath != null && savedCustomPath.isNotEmpty) {
      _customWorkspaceBasePath = savedCustomPath;
    } else {
      // 使用平台默认路径
      _customWorkspaceBasePath =
          await PlatformAdapter.getDefaultWorkspaceBasePath();
    }
  }

  // ==================== 编辑器设置方法 ====================

  /// 设置编辑器字体大小
  Future<void> setFontSize(double size) async {
    _fontSize = size;
    notifyListeners();
    schedulePersist('font_size', size);
  }

  /// 设置是否启用自动保存
  Future<void> setAutoSave(bool value) async {
    _autoSave = value;
    notifyListeners();
    schedulePersist('auto_save', value);
  }

  /// 设置自动保存间隔
  Future<void> setAutoSaveInterval(int seconds) async {
    _autoSaveInterval = seconds;
    notifyListeners();
    schedulePersist('auto_save_interval', seconds);
  }

  /// 设置退出文档时是否自动保存
  Future<void> setSaveOnExit(bool value) async {
    _saveOnExit = value;
    notifyListeners();
    schedulePersist('save_on_exit', value);
  }

  /// 设置行高
  Future<void> setLineHeight(double height) async {
    _lineHeight = height;
    notifyListeners();
    schedulePersist('line_height', height);
  }

  /// 设置字间距
  Future<void> setLetterSpacing(double spacing) async {
    _letterSpacing = spacing;
    notifyListeners();
    schedulePersist('letter_spacing', spacing);
  }

  /// 设置段落间距
  Future<void> setParagraphSpacing(double spacing) async {
    _paragraphSpacing = spacing;
    notifyListeners();
    schedulePersist('paragraph_spacing', spacing);
  }

  /// 设置启动行为
  Future<void> setStartupBehavior(String behavior) async {
    _startupBehavior = behavior;
    notifyListeners();
    schedulePersist('startup_behavior', behavior);
  }

  /// 设置上次打开的文件路径
  Future<void> setLastOpenedFilePath(String? path) async {
    _lastOpenedFilePath = path;
    notifyListeners();
    if (path != null) {
      schedulePersist('last_opened_file_path', path);
    } else {
      final prefs = await this.prefs();
      await prefs.remove('last_opened_file_path');
    }
  }

  /// 设置默认目录
  Future<void> setDefaultDirectory(String? path) async {
    _defaultDirectory = path;
    notifyListeners();
    final prefs = await this.prefs();
    if (path != null) {
      await prefs.setString('default_directory', path);
    } else {
      await prefs.remove('default_directory');
    }
  }

  /// 设置工作区文件夹名称
  Future<void> setWorkspaceName(String name) async {
    _workspaceName = name;
    notifyListeners();
    schedulePersist('workspace_name', name);
  }

  /// 设置自定义工作区基础路径
  Future<void> setCustomWorkspaceBasePath(String? path) async {
    _customWorkspaceBasePath = path;
    notifyListeners();
    final prefs = await this.prefs();
    if (path != null && path.isNotEmpty) {
      await prefs.setString('custom_workspace_base_path', path);
    } else {
      await prefs.remove('custom_workspace_base_path');
    }
  }
}
