// ============================================================================
// 应用设置状态管理器（门面，T-09 拆分）
//
// T-09 将按领域拆分的设置逻辑下沉到四个子 Provider：
// - [AppearanceSettingsProvider]：主题 / 文字颜色 / 背景 / 底栏 / 图标 / 语言 / 字体
// - [EditorSettingsProvider]：编辑器（字号、行高、自动保存、工作区）
// - [SyncSettingsProvider]：云同步（WebDAV / FTP / 自动同步）
// - [UpdateSettingsProvider]：更新（自动检查 / 通道 / 代理）
//
// 本类保持原有 `SettingsProvider` 类名与全部公共成员（getter / setter /
// 静态色板 / initialize），通过组合子 Provider 转发实现，对调用方透明：
// 既保留 `context.watch<SettingsProvider>()` 等全部引用面，又让每个领域
// 实现收敛在独立文件内。
//
// 所有设置使用 SharedPreferences 持久化存储，敏感凭据使用安全存储。
// ============================================================================

import 'package:flutter/material.dart';

import 'appearance_settings_provider.dart';
import 'editor_settings_provider.dart';
import 'sync_settings_provider.dart';
import 'update_settings_provider.dart';

/// 设置状态提供者（门面）
///
/// 管理应用的外观和行为设置。领域实现见四个子 Provider。
class SettingsProvider extends ChangeNotifier {
  // ==================== 领域子 Provider ====================

  /// 外观领域设置（主题 / 颜色 / 背景 / 底栏 / 图标 / 语言 / 字体）
  final AppearanceSettingsProvider appearance = AppearanceSettingsProvider();

  /// 编辑器领域设置（字号 / 行高 / 自动保存 / 工作区）
  final EditorSettingsProvider editor = EditorSettingsProvider();

  /// 同步领域设置（WebDAV / FTP / 自动同步）
  final SyncSettingsProvider sync = SyncSettingsProvider();

  /// 更新领域设置（自动检查 / 通道 / 代理）
  final UpdateSettingsProvider update = UpdateSettingsProvider();

  // ==================== 预设色板（静态转发） ====================

  /// 10 种沉稳预设色。同一张表兼作主题色、UI 文字色与图标色，
  /// 因此每个色都必须能在浅色纸面上直接读、且作填充色时白字仍达 AA。
  static const List<Color> themeColors = AppearanceSettingsProvider.themeColors;

  /// UI 文字颜色预设与主题色调色板保持一致
  static const List<Color> uiFontColors = AppearanceSettingsProvider.uiFontColors;

  /// 8种精选编辑器文字颜色（适合长时间编辑阅读）
  static const List<Color> editorFontColors =
      AppearanceSettingsProvider.editorFontColors;

  /// 全局图标颜色预设与主题色调色板保持一致
  static const List<Color> globalIconColors =
      AppearanceSettingsProvider.globalIconColors;

  /// 强调色与墨色预设都是为浅色纸面调校的，深色表面上需压饱和并提亮才可读。
  static Color legibleOnDark(Color color) =>
      AppearanceSettingsProvider.legibleOnDark(color);

  // ==================== 初始化 ====================

  /// 读取并恢复全部设置
  Future<void> initialize() async {
    // 子 Provider 按序初始化；appearance 内部包含莫奈配色一次性迁移。
    // 领域间无共享键依赖，顺序仅用于保持日志与副作用的一致性。
    await appearance.initialize();
    await editor.initialize();
    await sync.initialize();
    await update.initialize();
    notifyListeners();
  }

  // ==================== 主题设置（外观） ====================

  ThemeMode get themeMode => appearance.themeMode;
  int get primaryColorIndex => appearance.primaryColorIndex;
  Color get primaryColor => appearance.primaryColor;
  Color? get customThemeColor => appearance.customThemeColor;

  /// 设置主题模式
  ///
  /// [mode] ThemeMode.system / ThemeMode.light / ThemeMode.dark
  Future<void> setThemeMode(ThemeMode mode) async {
    await appearance.setThemeMode(mode);
    notifyListeners();
  }

  /// 选择预设主题色（同时清除自定义覆盖）
  Future<void> setPrimaryColorIndex(int index) async {
    await appearance.setPrimaryColorIndex(index);
    notifyListeners();
  }

  /// 设置自定义主题色；传 null 恢复预设
  Future<void> setCustomThemeColor(Color? color) async {
    await appearance.setCustomThemeColor(color);
    notifyListeners();
  }

  // ==================== 界面字体颜色（外观） ====================

  int get uiFontColorIndex => appearance.uiFontColorIndex;
  Color? get customUiFontColor => appearance.customUiFontColor;

  /// 选择预设界面字体颜色（同时清除自定义覆盖）
  Future<void> setUiFontColorIndex(int index) async {
    await appearance.setUiFontColorIndex(index);
    notifyListeners();
  }

  /// 设置自定义界面字体颜色；传 null 恢复预设
  Future<void> setCustomUiFontColor(Color? color) async {
    await appearance.setCustomUiFontColor(color);
    notifyListeners();
  }

  // ==================== 编辑器文字颜色（外观） ====================

  int get editorFontColorIndex => appearance.editorFontColorIndex;
  Color? get customEditorFontColor => appearance.customEditorFontColor;

  /// 按表面明暗解析编辑器文字颜色（自定义原样生效，预设深色提亮）
  Color editorFontColorFor(Brightness brightness) =>
      appearance.editorFontColorFor(brightness);

  /// 按表面明暗解析 UI 文字颜色（自定义原样生效，预设深色提亮）
  Color uiFontColorFor(Brightness brightness) =>
      appearance.uiFontColorFor(brightness);

  /// 选择预设编辑器文字颜色（同时清除自定义覆盖）
  Future<void> setEditorFontColorIndex(int index) async {
    await appearance.setEditorFontColorIndex(index);
    notifyListeners();
  }

  /// 设置自定义编辑器文字颜色；传 null 恢复预设
  Future<void> setCustomEditorFontColor(Color? color) async {
    await appearance.setCustomEditorFontColor(color);
    notifyListeners();
  }

  // ==================== 背景设置（外观） ====================

  String? get backgroundImagePath => appearance.backgroundImagePath;
  String? get editorBackgroundImagePath =>
      appearance.editorBackgroundImagePath;
  bool get editorBackgroundImageExists =>
      appearance.editorBackgroundImageExists;
  String get backgroundEffect => appearance.backgroundEffect;
  double get backgroundBlur => appearance.backgroundBlur;
  double get backgroundBrightness => appearance.backgroundBrightness;
  bool get editorBackgroundBlurEnabled =>
      appearance.editorBackgroundBlurEnabled;
  double get editorBackgroundBlur => appearance.editorBackgroundBlur;
  double get editorBackgroundBrightness =>
      appearance.editorBackgroundBrightness;

  /// 设置背景图片（复制到应用私有目录，避免清理缓存后图片丢失）
  Future<void> setBackgroundImage(String? path) async {
    await appearance.setBackgroundImage(path);
    notifyListeners();
  }

  /// 设置编辑器背景图片（复制到应用私有目录，避免清理缓存后图片丢失）
  Future<void> setEditorBackgroundImage(String? path) async {
    await appearance.setEditorBackgroundImage(path);
    notifyListeners();
  }

  /// 设置背景效果
  Future<void> setBackgroundEffect(String effect) async {
    await appearance.setBackgroundEffect(effect);
    notifyListeners();
  }

  /// 设置模糊强度
  Future<void> setBackgroundBlur(double blur) async {
    await appearance.setBackgroundBlur(blur);
    notifyListeners();
  }

  /// 仅在内存中更新背景亮度（不持久化），用于 Slider 拖动时实时预览
  void updateBackgroundBrightnessInMemory(double brightness) {
    appearance.updateBackgroundBrightnessInMemory(brightness);
    notifyListeners();
  }

  /// 设置背景亮度（立即刷新 UI，再异步持久化）
  Future<void> setBackgroundBrightness(double brightness) async {
    await appearance.setBackgroundBrightness(brightness);
    notifyListeners();
  }

  /// 设置编辑器背景模糊开关
  Future<void> setEditorBackgroundBlurEnabled(bool enabled) async {
    await appearance.setEditorBackgroundBlurEnabled(enabled);
    notifyListeners();
  }

  /// 设置编辑器背景模糊强度
  Future<void> setEditorBackgroundBlur(double blur) async {
    await appearance.setEditorBackgroundBlur(blur);
    notifyListeners();
  }

  /// 仅在内存中更新编辑器背景亮度（不持久化），用于 Slider 拖动时实时预览
  void updateEditorBackgroundBrightnessInMemory(double brightness) {
    appearance.updateEditorBackgroundBrightnessInMemory(brightness);
    notifyListeners();
  }

  /// 设置编辑器背景亮度（立即刷新 UI，再异步持久化）
  Future<void> setEditorBackgroundBrightness(double brightness) async {
    await appearance.setEditorBackgroundBrightness(brightness);
    notifyListeners();
  }

  // ==================== 编辑器设置（编辑器） ====================

  double get fontSize => editor.fontSize;
  double get lineHeight => editor.lineHeight;
  double get letterSpacing => editor.letterSpacing;
  double get paragraphSpacing => editor.paragraphSpacing;
  bool get autoSave => editor.autoSave;
  int get autoSaveInterval => editor.autoSaveInterval;
  bool get saveOnExit => editor.saveOnExit;
  String? get defaultDirectory => editor.defaultDirectory;
  String get workspaceName => editor.workspaceName;
  String? get customWorkspaceBasePath => editor.customWorkspaceBasePath;
  String get startupBehavior => editor.startupBehavior;
  String? get lastOpenedFilePath => editor.lastOpenedFilePath;

  /// 设置编辑器字体大小
  Future<void> setFontSize(double size) async {
    await editor.setFontSize(size);
    notifyListeners();
  }

  /// 设置是否启用自动保存
  Future<void> setAutoSave(bool value) async {
    await editor.setAutoSave(value);
    notifyListeners();
  }

  /// 设置自动保存间隔
  Future<void> setAutoSaveInterval(int seconds) async {
    await editor.setAutoSaveInterval(seconds);
    notifyListeners();
  }

  /// 设置退出文档时是否自动保存
  Future<void> setSaveOnExit(bool value) async {
    await editor.setSaveOnExit(value);
    notifyListeners();
  }

  /// 设置行高
  Future<void> setLineHeight(double height) async {
    await editor.setLineHeight(height);
    notifyListeners();
  }

  /// 设置字间距
  Future<void> setLetterSpacing(double spacing) async {
    await editor.setLetterSpacing(spacing);
    notifyListeners();
  }

  /// 设置段落间距
  Future<void> setParagraphSpacing(double spacing) async {
    await editor.setParagraphSpacing(spacing);
    notifyListeners();
  }

  /// 设置启动行为
  Future<void> setStartupBehavior(String behavior) async {
    await editor.setStartupBehavior(behavior);
    notifyListeners();
  }

  /// 设置上次打开的文件路径
  Future<void> setLastOpenedFilePath(String? path) async {
    await editor.setLastOpenedFilePath(path);
    notifyListeners();
  }

  /// 设置默认目录
  Future<void> setDefaultDirectory(String? path) async {
    await editor.setDefaultDirectory(path);
    notifyListeners();
  }

  /// 设置工作区文件夹名称
  Future<void> setWorkspaceName(String name) async {
    await editor.setWorkspaceName(name);
    notifyListeners();
  }

  /// 设置自定义工作区基础路径
  Future<void> setCustomWorkspaceBasePath(String? path) async {
    await editor.setCustomWorkspaceBasePath(path);
    notifyListeners();
  }

  // ==================== 语言设置（外观） ====================

  Locale get locale => appearance.locale;

  /// 设置应用语言
  Future<void> setLocale(Locale locale) async {
    await appearance.setLocale(locale);
    notifyListeners();
  }

  // ==================== 更新设置（更新） ====================

  bool get autoCheckUpdate => update.autoCheckUpdate;
  String get updateChannel => update.updateChannel;
  List<String> get updateProxies => update.updateProxies;

  /// 设置启动时是否自动检查更新
  Future<void> setAutoCheckUpdate(bool value) async {
    await update.setAutoCheckUpdate(value);
    notifyListeners();
  }

  /// 设置更新规则
  Future<void> setUpdateChannel(String value) async {
    await update.setUpdateChannel(value);
    notifyListeners();
  }

  /// 设置自定义下载代理列表；去空行、去重，顺序即尝试顺序
  Future<void> setUpdateProxies(List<String> proxies) async {
    await update.setUpdateProxies(proxies);
    notifyListeners();
  }

  // ==================== 底栏设置（外观） ====================

  double get cardOpacity => appearance.cardOpacity;
  double get tabBarOpacity => appearance.tabBarOpacity;
  Color? get customCardColor => appearance.customCardColor;

  /// 设置卡片透明度
  Future<void> setCardOpacity(double opacity) async {
    await appearance.setCardOpacity(opacity);
    notifyListeners();
  }

  /// 设置底部导航栏透明度
  Future<void> setTabBarOpacity(double opacity) async {
    await appearance.setTabBarOpacity(opacity);
    notifyListeners();
  }

  /// 设置自定义卡片颜色；传 null 恢复主题默认
  Future<void> setCustomCardColor(Color? color) async {
    await appearance.setCustomCardColor(color);
    notifyListeners();
  }

  // ==================== 图标设置（外观） ====================

  Color? get customIconColor => appearance.customIconColor;
  int get appIconIndex => appearance.appIconIndex;
  String get homeIconMode => appearance.homeIconMode;
  String? get homeIconCustomPath => appearance.homeIconCustomPath;
  String get homeTitleText => appearance.homeTitleText;

  /// 设置自定义全局图标颜色；传 null 恢复主题默认
  Future<void> setCustomIconColor(Color? color) async {
    await appearance.setCustomIconColor(color);
    notifyListeners();
  }

  /// 设置桌面图标索引（0=默认, 1=icon2）
  Future<void> setAppIconIndex(int index) async {
    await appearance.setAppIconIndex(index);
    notifyListeners();
  }

  /// 设置主页图标模式
  Future<void> setHomeIconMode(String mode) async {
    await appearance.setHomeIconMode(mode);
    notifyListeners();
  }

  /// 设置主页自定义图标路径
  Future<void> setHomeIconCustomPath(String? path) async {
    await appearance.setHomeIconCustomPath(path);
    notifyListeners();
  }

  /// 设置主页标题文字（允许为空）
  Future<void> setHomeTitleText(String text) async {
    await appearance.setHomeTitleText(text);
    notifyListeners();
  }

  // ==================== 夜间主题和字体设置（外观） ====================

  int get darkThemeIndex => appearance.darkThemeIndex;
  int get lightThemeIndex => appearance.lightThemeIndex;
  String get uiFontFamily => appearance.uiFontFamily;
  AppButtonStyleMode get buttonStyleMode => appearance.buttonStyleMode;
  bool get useBorderlessButtons => appearance.useBorderlessButtons;
  String get editorFontFamily => appearance.editorFontFamily;
  String get codeFontFamily => appearance.codeFontFamily;
  int get codeBlockThemeIndex => appearance.codeBlockThemeIndex;

  /// 设置夜间主题索引
  Future<void> setDarkThemeIndex(int index) async {
    await appearance.setDarkThemeIndex(index);
    notifyListeners();
  }

  /// 设置浅色主题索引
  Future<void> setLightThemeIndex(int index) async {
    await appearance.setLightThemeIndex(index);
    notifyListeners();
  }

  /// 设置按钮风格
  Future<void> setButtonStyleMode(AppButtonStyleMode mode) async {
    await appearance.setButtonStyleMode(mode);
    notifyListeners();
  }

  /// 设置 UI 字体
  Future<void> setUiFontFamily(String fontFamily) async {
    await appearance.setUiFontFamily(fontFamily);
    notifyListeners();
  }

  /// 设置编辑器字体
  Future<void> setEditorFontFamily(String fontFamily) async {
    await appearance.setEditorFontFamily(fontFamily);
    notifyListeners();
  }

  /// 设置代码块字体
  Future<void> setCodeFontFamily(String fontFamily) async {
    await appearance.setCodeFontFamily(fontFamily);
    notifyListeners();
  }

  /// 设置代码块主题索引
  Future<void> setCodeBlockThemeIndex(int index) async {
    await appearance.setCodeBlockThemeIndex(index);
    notifyListeners();
  }

  // ==================== 云同步设置（同步） ====================

  String get syncType => sync.syncType;
  String get floatingButtonsMode => sync.floatingButtonsMode;
  String get webdavUrl => sync.webdavUrl;
  String get webdavUsername => sync.webdavUsername;
  // 密码不通过公共 getter 暴露，仅在内部使用
  String get ftpUrl => sync.ftpUrl;
  String get ftpHost => sync.ftpHost;
  int get ftpPort => sync.ftpPort;
  String get ftpUsername => sync.ftpUsername;
  String get syncFolderName => sync.syncFolderName;
  String get syncRemotePath => sync.syncRemotePath;
  bool get autoSyncEnabled => sync.autoSyncEnabled;
  DateTime? get lastSyncTime => sync.lastSyncTime;
  bool get isWebdavConfigured => sync.isWebdavConfigured;
  bool get isFtpConfigured => sync.isFtpConfigured;
  bool get isSyncConfigured => sync.isSyncConfigured;

  /// 安全地获取 WebDAV 凭据（仅用于创建服务实例）
  /// 不要在 UI 层调用此方法
  Map<String, String> getWebdavCredentials() => sync.getWebdavCredentials();

  /// 安全地获取 FTP 凭据（仅用于创建服务实例）
  /// 不要在 UI 层调用此方法
  Map<String, String> getFtpCredentials() => sync.getFtpCredentials();

  /// 获取完整的云端文件夹路径（路径前缀 + 文件夹名称）
  String getFullSyncPath() => sync.getFullSyncPath();

  /// 设置同步类型
  Future<void> setSyncType(String type) async {
    await sync.setSyncType(type);
    notifyListeners();
  }

  /// 设置 WebDAV 服务器地址
  Future<void> setWebdavUrl(String url) async {
    await sync.setWebdavUrl(url);
    notifyListeners();
  }

  /// 设置 WebDAV 用户名
  Future<void> setWebdavUsername(String username) async {
    await sync.setWebdavUsername(username);
    notifyListeners();
  }

  /// 设置 WebDAV 密码（安全存储）
  Future<void> setWebdavPassword(String password) async {
    await sync.setWebdavPassword(password);
    notifyListeners();
  }

  /// 设置 FTP 服务器 URL
  Future<void> setFtpUrl(String url) async {
    await sync.setFtpUrl(url);
    notifyListeners();
  }

  /// 设置 FTP 用户名
  Future<void> setFtpUsername(String username) async {
    await sync.setFtpUsername(username);
    notifyListeners();
  }

  /// 设置 FTP 密码（安全存储）
  Future<void> setFtpPassword(String password) async {
    await sync.setFtpPassword(password);
    notifyListeners();
  }

  /// 设置云端同步文件夹名称
  Future<void> setSyncFolderName(String folderName) async {
    await sync.setSyncFolderName(folderName);
    notifyListeners();
  }

  /// 设置云端文件夹路径前缀
  Future<void> setSyncRemotePath(String path) async {
    await sync.setSyncRemotePath(path);
    notifyListeners();
  }

  /// 设置自动同步开关
  Future<void> setAutoSyncEnabled(bool enabled) async {
    await sync.setAutoSyncEnabled(enabled);
    notifyListeners();
  }

  /// 设置浮动按钮显示模式
  Future<void> setFloatingButtonsMode(String mode) async {
    await sync.setFloatingButtonsMode(mode);
    notifyListeners();
  }

  /// 更新上次同步时间
  Future<void> updateLastSyncTime() async {
    await sync.updateLastSyncTime();
    notifyListeners();
  }

  /// 保存所有 WebDAV 凭据
  ///
  /// 密码使用安全存储，URL 和用户名使用 SharedPreferences
  Future<void> saveWebdavCredentials({
    required String url,
    required String username,
    required String password,
  }) async {
    await sync.saveWebdavCredentials(
      url: url,
      username: username,
      password: password,
    );
    notifyListeners();
  }
}
