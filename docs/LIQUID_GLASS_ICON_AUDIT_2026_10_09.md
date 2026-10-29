# 液态玻璃风格图标与样式叠加 · 完整审计报告

日期：2026-10-09
范围：`lib/` 全部 101 个 Dart 文件 + 平台目录（android / windows / ios）
基线提交：`257c173`
性质：静态搜索与源码核实，**未改动任何代码**

---

## 0. 结论摘要

项目在“液态玻璃”风格下存在三类系统性问题，按影响面排序：

| 排名 | 问题 | 实测影响面 |
|---|---|---|
| 1 | `ColorScheme` 只设置 4 个字段，其余角色回退到硬编码纯黑/纯白 | **249 个调用点** |
| 2 | 图标颜色存在 4 条互不相通的取色路径 | **101 个可明确归类**（84 个为纯黑/白） |
| 3 | 全项目未使用插件提供的页面级玻璃容器（`GlassPage`） | 4 个已发现问题可一处解决 |

其余为局部问题（49 个实色对话框、桌面端双标题栏、4 处死代码等），详见第 4 节。

**最有效的单点改动**：接入插件 `GlassPage`（含 `LiquidGlassScope` + `GlassBackgroundSource` + `AdaptiveLiquidGlassLayer` + `statusBarStyle`），可同时解决玻璃采样、渲染层、状态栏、主题化背景四个问题。

---

## 1. 背景与方法

### 1.1 任务

搜索“液态玻璃风格下仍存在非库内样式叠加、可能导致玻璃效果被覆盖”的位置，并输出报告。

### 1.2 判定标准

玻璃模式的生效路径只有三条：

1. `AppSurface` → `LiquidGlassCard` → 插件 `GlassContainer`
2. `GlassCard` / `EditorHeader` → `LiquidGlassCard`
3. 插件组件直接使用（`GlassTabBar` / `GlassIconButton` / `GlassContainer`）

其余任何自带 `BoxDecoration(color:)`、`colorScheme.*`、主题渐变、实色 pill 的写法，在玻璃模式下都属于“库外样式”，会盖住或削弱玻璃效果。

### 1.3 方法

滚动式排查：每轮从不同维度检索 → 深入源码核实 → 排除误报 → 汇总。
共 50 轮，覆盖：

主题层 → 组件层 → 页面层 → 分支逻辑层 → 渲染架构层 → 着色器/采样层 →
WebView 产物层 → 全局绘制顺序层 → 数据转换层 → 资源/导出层 →
Material elevation 机制 → 桌面/平台层 → 图标取色链路 → 死代码与统计审计。

### 1.4 数据可靠性

报告中的所有计数均用统一命令实测（排除 3 个死代码文件）：

```bash
rg -n '<pattern>' lib -g '*.dart' \
  --glob '!**/appearance_settings_screen.dart' \
  --glob '!**/markdown_preview.dart' \
  --glob '!**/unified_ui.dart'
```

审计过程中发现并修正了 **4 处统计错误**（详见第 6 节），本节数字为最终修正值。

---

## 2. 核心根因：三层并存的颜色体系

项目实际存在**三套颜色体系**，彼此未打通：

| 体系 | 载体 | 状态 | 服务对象 |
|---|---|---|---|
| A. 项目自有 | `AppConstants.*ThemeSchemes` + `AppStyleTheme` | ✅ 完整 | 自建组件（约 250 处图标、全部文字） |
| B. Material | `ColorScheme` | ⚠️ **只设 4 / 29 字段** | 所有 SDK 组件 |
| C. 玻璃库 | `GlassThemeData` | ⚠️ **只接亮度，未接色调** | 全部玻璃件 |

### 2.1 `ColorScheme` 只设置了 4 个字段

`lib/main.dart:225`（默认路径，`monetEnabled = false`，即默认配置）：

```dart
ColorScheme.light(
  primary: primaryColor,
  secondary: AppConstants.accentColor,
  surface: scheme.surface,
  error: AppConstants.errorColor,
);
```

未设置的语义角色会按 SDK 回退链落到硬编码值：

```
onSurface      = Colors.black / Colors.white        （硬编码基线）
   ↑
onBackground   ?? onSurface
   ↑                      ↑                    ↑
onSurfaceVariant    outline              outlineVariant
   ??                        ??                      ??
```

对照：Monet 动态配色路径（`lib/models/monet_config.dart:166`
`toFlutterColorScheme`）**完整设置了 29 个字段**——说明正确的写法项目里已有，只是默认路径没用上。

### 2.2 受影响调用点（实测 249 处）

| 角色 | 调用点 | 位置 |
|---|---|---|
| `colorScheme.outline` | **93** | — |
| `colorScheme.onSurface` | **38** | — |
| `colorScheme.onSurfaceVariant` | **25** | — |
| `ThemeData.dividerColor`（M3 下 `??= colorScheme.outline`） | **31** | 项目未设 `dividerColor` |
| `colorScheme.outlineVariant` | **3** | 版本历史面板 |
| `.appIconColor`（`AppStyleTheme.iconColor` ← `colorScheme.onSurface`） | **31** | — |
| `.appMutedIconColor`（← `onSurfaceVariant`） | **28** | — |
| **合计** | **249** | — |

要点：

- `appIconColor` / `appMutedIconColor` 是项目自建的统一入口，**结构正确**，但其默认值仍来自未设置的 `onSurface` / `onSurfaceVariant`，因此**默认配置下也是纯黑/纯白**。
- 用户只有在“设置 → 外观 → 自定义图标颜色”中主动开启时，这 59 处才会跟随设置变化。

### 2.3 `outline` 的 7 类消费者

```
outline（未设置 → onBackground → onSurface → 纯黑/白）
  ├─ 1. 边框（Border.all）
  ├─ 2. 分隔线
  ├─ 3. 次要文字
  ├─ 4. outlineVariant（派生角色）
  ├─ 5. ThemeData.dividerColor（派生角色）
  ├─ 6. TextField 边框
  └─ 7. CircleAvatar 背景（搜索序号徽章）
```

### 2.4 预设主题不影响这些值

预设主题（11 套：Catppuccin / Rosé Pine / Nord / Tokyo Night / Dracula / Gruvbox / Solarized …）
的字段只有 4 个（`background` / `surface` / `text` / `textSecondary`），
其中**只有 `surface` 被传入 `ColorScheme`**（`lib/main.dart:229`），
`text` / `textSecondary` 走 `AppStyleTheme` 的另一条路。

因此：**切换预设主题时，上述 249 处调用点不会发生任何变化。**

### 2.5 两套分隔线样式并存

| 路径 | 来源 | 色相 | alpha | 使用点 |
|---|---|---|---|---|
| A. `Divider()` 组件 | `dividerTheme`（`main.dart:545`，用 `textSecondaryColor`） | ✅ 跟随主题 | 0.1 ~ 0.3 | 13 |
| B. 直接读 `Theme.of(context).dividerColor` | `colorScheme.outline` | ❌ 纯黑/白 | 0.35 ~ 0.5 | **31** |

同一屏内可能出现“主题色细线”与“半透明黑线”并存。

---

## 3. 图标取色：4 条互不相通的路径

全项目 `Icon(` 使用点 **255 个**（排除死代码）。按取色方式归类：

| # | 路径 | 图标数 | 最终色值 | 是否受用户设置影响 |
|---|---|---|---|---|
| 1 | 按钮内图标 → `iconButtonTheme.foregroundColor` = `textColor`（**界面文字色**） | 37 | **靛蓝 `#6366F1`**（默认） | ⚠️ 受“文字颜色”影响，不受“图标颜色”影响 |
| 2 | SDK 容器（`InputDecoration.prefixIcon` / `ListTile.leading`） → `onSurfaceVariant` | 25 | 纯黑 / 纯白 | ❌ |
| 3 | 项目自建（`.appIconColor` / `.appMutedIconColor`） | **59** | 纯黑 / 纯白（默认） | ✅ 仅当开启“自定义图标颜色” |
| 4 | 插件内部（`GlassTabBar` → `CupertinoColors.label`） | 8 | 系统标签色 | ❌ |
| 5 | 显式 `Colors.*`（语义色：成功/错误/警告/白底深色图标） | 29 | 绿/红/橙/蓝/白 | ❌（设计如此，合理） |
| 6 | `Icon(Icons.x)` 无 color（继承） | 52 | 混合（见下） | ❌ |
| 7 | 其他（多行形式 / 变量） | ~45 | 混合 | — |

### 3.1 用户的设置覆盖率仅 37.6%

| 设置项 | 影响的图标 | 占比 |
|---|---|---|
| 界面**文字**颜色（`uiFontColor`） | 37 | 14.5% |
| 自定义**图标**颜色（`customIconColor`） | 59 | 23.1% |
| **合计** | **96** | **37.6%** |
| **不受任何设置影响** | **159** | **62.4%** |

其中高频可见的 34 个：输入框 prefix/suffix 图标（17）、设置页列表项 leading（9）、底部导航（8）。

### 3.2 `customIconColor` 未接入 `ColorScheme`

传播链：

```
settings.customIconColor
  → _buildTheme(customIconColor:)
  → AppStyleTheme.resolve(...)
  → AppStyleTheme.iconColor / mutedIconColor
  → context.appIconColor / appMutedIconColor
  → 59 处
```

**未传入 `ColorScheme`**，因此读取 `ColorScheme` 的组件（`InputDecoration`、`ListTile`、`NavigationRail`）与插件组件（`GlassTabBar`）都拿不到这个值。

### 3.3 编辑器顶栏一行三个按钮色值不一致

`lib/screens/editor/components/editor_header.dart`：

| 按钮 | 取色 | 未修改态 | 保存中 / 已修改 |
|---|---|---|---|
| 返回（`GlassHeaderButton`） | `appIconColor` | 纯黑 | 不变 |
| **保存** | `primary` / `secondary` / `appMutedIconColor` | 纯黑 | **靛蓝 / 青** |
| 更多（`GlassHeaderButton`） | `appIconColor` | 纯黑 | 不变 |

保存按钮的三态设计本身合理，但与相邻两个按钮的基线色（纯黑）形成强烈对比。

### 3.4 `GlassIconButton` 的禁用态色被外层显式色绕过

`lib/widgets/glass_header_button.dart:44` 显式传入 `Icon(color: effectiveIconColor)`，
优先于插件内部的 `IconTheme`（`CupertinoColors.label` / `tertiaryLabel`），
使插件的禁用灰化、明暗自适应失效。

### 3.5 `IconButton` 的图标色由文字色决定

`main.dart:501`：

```dart
iconButtonTheme: IconButtonThemeData(
  style: IconButton.styleFrom(
    foregroundColor: textColor,   // = uiFontColor（文字色）
```

SDK 的 `effectiveIconColor()` 优先取 `foregroundColor`，并强制覆盖 `IconTheme`。
**结果：调“文字颜色”会连带改变 24~37 个按钮图标；调“图标颜色”对它们无效。**

### 3.6 13 个 AppBar 的返回按钮继承实色底

`BackButton extends _ActionButton extends IconButton`，因此继承
`iconButtonTheme.backgroundColor = useBorderlessButtons ? strongSurface : null`。
玻璃模式下 `useBorderlessButtons == true` → 返回按钮带 `strongSurface`（α0.88~0.90）近实色底。
13 个 AppBar **均未显式设置 `leading`**。

### 3.7 其他图标色问题

| 问题 | 位置 | 说明 |
|---|---|---|
| `Tooltip` 硬编码灰/白 | 未设 `tooltipTheme` | Flutter 默认 `Colors.grey[700]` / `Colors.white`，9 处 |
| `ListTile` 标题与副标题同色 | 未设 `onSurfaceVariant` | 两者都落到 `onSurface`，丧失层次 |
| 搜索序号徽章对比度不足 | `search_sheet.dart:152` | 黑 20% 底 + 纯黑字 |
| `MarkdownToolbar` 单组件内 4 条路径 | `markdown_toolbar.dart` | 33 个图标 |

---

## 4. 玻璃渲染链路问题

### 4.1 未使用 `GlassPage`（影响最大）

插件提供 70+ 组件，项目仅使用 5 个（约 7%）：
`GlassContainer`、`GlassIconButton`、`GlassTabBar`、`LiquidRoundedSuperellipse`、`LiquidGlassWidgets`。

未使用 `GlassPage` / `GlassScaffold` / `LiquidGlassScope` / `GlassBackgroundSource` / `GlassThemeData` / `AdaptiveLiquidGlassLayer`。

`GlassPage` 一个组件即可覆盖 4 个已发现问题：

| # | 已发现问题 | `GlassPage` 对应能力 |
|---|---|---|
| 1 | 无 `GlassBackgroundSource`，玻璃采样 1×1 透明 dummy 图 | `enableBackgroundSampling` |
| 2 | 无全局玻璃渲染层 | 内置 `AdaptiveLiquidGlassLayer` |
| 3 | 4 个无 AppBar 页面状态栏图标不可读 | `statusBarStyle: auto`（尊重 `ThemeMode`） |
| 4 | 玻璃采样背景硬编码渐变 | `background` 参数 |

插件源码注释本身即描述了第 3 点：

> Without this, pages without a GlassAppBar lose the status bar icons
> because CupertinoPageRoute's default region overrides the imperative
> SystemChrome call from GlassPage.

### 4.2 玻璃浮在 WebView（PlatformView）之上

编辑器的三个玻璃件全部压在 `InAppWebView` 之上：顶栏信息胶囊、头部按钮、右下 FAB。

插件默认 `platformViewMode = PlatformViewGlassMode.fallbackColor`
且 `platformViewFallbackColor = null` → 采样不到内容时**渲染为不透明黑色**
（插件源码注释：*“Over a platform view (a map, a camera preview, a video, a webview)
that texture is empty … resolves to solid black.”*）。

项目未设置 `platformViewBackdrop` / `platformViewMode` / `platformViewFallbackColor`。
Android 日志确认 WebView 使用 hybrid composition PlatformView。

**这解释了历史上实机截图中的“顶栏黑色块”现象。**

### 4.3 `AnimatedOpacity` 强制玻璃进入独立合成层

`lib/screens/editor_screen.dart:2777 / 2808`：

```dart
AnimatedOpacity(          // → FadeTransition → RenderOpacity
  opacity: showButtons ? 1.0 : 0.0,
  child: AnimatedScale(
    child: Column(children: [AnimatedFab(...), AnimatedFab(...)]),
```

`RenderOpacity.alwaysNeedsCompositing` 的条件是 `alpha > 0`——
**即使 opacity 为 1.0 也会 `isRepaintBoundary = true`**，用 `OpacityLayer` 隔离子树。
玻璃的 `BackdropFilterLayer` 因此采样不到页面背景，透射效果失效。

（同为 UI 层级的 `MarkdownToolbar` 也被 `AnimatedOpacity` 包裹。）

### 4.4 `Transform.scale` 作用于玻璃

`animated_fab.dart:62`（按下缩放 0.85）+ `editor_screen.dart` 外层 `AnimatedScale`（0.8）+ 两处拖拽代理（1.05）。
插件通过 `InheritedGeometryRenderLink` 通知变换，但项目无全局玻璃层 → 通知链无接收方 → 采样坐标不同步。

### 4.5 `GlassContainer` 嵌套（插件明确标注的反模式）

`lib/screens/settings/appearance/appearance_settings_mixin.dart:1431`：

```dart
LiquidGlassCard(          // = GlassContainer
  child: AppSurface(      // 玻璃模式下又包一层 LiquidGlassCard
```

插件文档（`glass_container.dart:76`）标题即：
*“⚠️ Anti-Pattern: Do Not Place Glass Controls Inside a GlassContainer”*。
内层玻璃会被降级为 `_VibrancyFill`（无背景模糊）——**静默降级，不报错**。

### 4.6 `GlassCard` 双重内边距

`lib/widgets/glass_card.dart`：内容已有 `Padding(16)`，玻璃分支又包一层 `Padding(16)` → **32px**（非玻璃模式 16px）。
影响“最近文件 / 最近文件夹”页。

### 4.7 Material elevation 与 `surfaceTint`

`main.dart:366 / 390 / 450`：`elevation: appStyle.useBorderlessButtons ? 4 : 0`
→ 玻璃模式下为 **4**，且 `shadowColor` 为黑 α0.14~0.18（非透明）。
同时 `surfaceTint` 未清空（`ColorScheme.surfaceTint` 回退到 `primary`），
M3 会按 elevation 叠加一层不透明色（`ElevationOverlay.applySurfaceTint` 使用 `Color.alphaBlend`）。

### 4.8 其他渲染层问题

| 问题 | 位置 | 说明 |
|---|---|---|
| `_shader == null` 退化 | `main.dart:79` 未调 `LightweightLiquidGlass.preWarm()` | 冷启动时玻璃退化为 15% 单色矩形 |
| 玻璃本体色固定 | 未传 `GlassThemeData` | 插件固定冷蓝白（light `RGBO(210,220,240,.12)` / dark `RGBO(255,255,255,.08)`），与暖色主题（复古暖纸、松林晨光）色相冲突 |
| 底栏 `glassColor` 硬编码 | `liquid_glass_capsule_tab_bar.dart:51` | 仅按明暗切换白色，不读主题色 |
| 玻璃件被 `ClipRRect`/`Transform` 影响 | 多处 | 采样坐标与裁剪边界 |

---

## 5. 非玻璃实色区域（“玻璃被覆盖”的直接来源）

### 5.1 编辑器内三个组件 / 50 个图标

| 组件 | 图标数 | 容器底色 | 是否玻璃 |
|---|---|---|---|
| `MarkdownToolbar` | 33（21 个 `_ToolbarButton`） | `scaledSurfaceColor α0.95` + 黑阴影 | ❌ |
| `editor_search_bar` | 12 | `scaledSurfaceColor α0.98` | ❌ |
| `search_sheet` | 5 | `colorScheme.surface`（实色） | ❌ |
| **合计** | **50** | — | — |

### 5.2 49 个对话框走实色 95%

`main.dart:555`：

```dart
dialogTheme: DialogThemeData(
  backgroundColor: appStyle.scaledSurfaceColor(effectiveColorScheme, alpha: 0.95),
```

`AlertDialog` / `showDialog` 共 **49 处**，玻璃模式下全部为 95% 实色板。
插件提供 `GlassDialog`（自带渲染层），项目未使用。

### 5.3 其他实色浮层与容器

| 位置 | 说明 |
|---|---|
| `toc_overlay` / `version_history_sheet` / `search_sheet` / 更多菜单 / `file_actions` ×2 / `folder_browser_screen` / `cloud_sync` ×3 | `colorScheme.surface` 实色底（15+ 处） |
| `desktop_navigation_shell.dart:43` | `scaledSurfaceColor α0.82` 实色导航栏 |
| `main_screen.dart:418` | 经典底栏 `α = tabBarOpacity`（默认 0.95） |
| `debug_settings_screen.dart:79` | 日志容器 `Colors.black α0.08`（深色模式几乎不可见） |
| `file_import_helper.dart:188` | 对话框内套 `surfaceContainerHighest α0.5` 提示条 |
| `themed_feedback.dart` | `Color.alphaBlend(accent, surface)` 生成不透明色 |
| `appearance_settings_mixin.dart:1690` ⚠️ | 主题选择器为**裸 `Container` + `scheme.surface`**（无玻璃、无 `InkWell`） |

---

## 6. 桌面端

| 问题 | 位置 | 说明 |
|---|---|---|
| **双标题栏** | `main.dart:62` | `titleBarStyle: TitleBarStyle.normal`（注释却写 “We'll use custom title bar”）与 `CustomTitleBar` 同时显示。Windows 原生标题栏无法被 Flutter 主题影响 |
| 桌面外壳未玻璃化 | `desktop_navigation_shell.dart` | 导航栏实色 α0.82 + 圆角外框 |
| `NavigationRail` 指示器 | `desktop_navigation_shell.dart:67` | `useIndicator: true` → M3 默认 `secondaryContainer` 实色 Stadium 块 |
| `CustomTitleBar` 取色绕过主题 | `custom_title_bar.dart:90` | 直读 `AppConstants.*ThemeSchemes`，玻璃模式下另加黑阴影 |

---

## 7. WebView 层

| 问题 | 位置 | 说明 |
|---|---|---|
| `surface` 丢失 alpha | `milkdown_webview_editor.dart:1620` `_toCssHex` | 丢弃 alpha 通道；`--milkdown-color-surface` 被用在代码块、行号槽、语言输入框等 15 处 |
| 代码块字体设置失效 | `--milkdown-font-code` 无写入方 | Dart 发 `font.mono` → `--milkdown-font-mono`（0 引用） |
| 加载覆盖层全屏实色 | `milkdown_webview_editor.dart:1528 / 1567` | 每次打开编辑器必经 |
| SVG 图标 | index.html | 25 处 `stroke="currentColor"`，无硬编码 ✅（正常） |
| `--crepe-color-*` 变量 | index.html | 17 个死变量（0 引用）——**此前曾误判为映射缺口，已排除** |

---

## 8. 状态栏（系统级图标）

| 项 | 结论 |
|---|---|
| `SystemUiOverlayStyle` 配置 | **0 处** |
| 有 `AppBar` 的页面（13） | ✅ 自动跟随 `brightness` |
| **无 `AppBar` 的页面（4）** | ❌ 回退到 Android Activity 主题 |

无 `AppBar` 的可达页面：

| 页面 | 文件 |
|---|---|
| **主界面**（最高频） | `main_screen.dart:275` |
| 编辑器 | `editor_screen.dart:2236` |
| 文件浏览 | `folder_browser_screen.dart:394 / 401` |
| 权限页 | `permission_screen.dart:11` |

触发条件：用户将 `ThemeMode` 从默认 `system` 改为强制 light/dark，且与系统深色模式不一致 →
状态栏图标与页面背景同色（页面背景由 `AppBackground` 按应用主题渲染，
状态栏由 Android `values/` + `values-night/` 按系统主题渲染，**两者依据不同**）。

---

## 9. 死代码与遗留依赖

| # | 名称 | 行数 | 引用 | 发现 |
|---|---|---|---|---|
| 1 | `lib/screens/settings/appearance_settings_screen.dart` | 3387 | 0 | 入口已改为分类页 + 4 个子页面 |
| 2 | `lib/widgets/markdown_preview.dart` | 718 | 0 | 编辑器已改用 Milkdown WebView |
| 3 | `lib/widgets/unified_ui.dart` | 236 | 0 | 7 个 API 全部零调用 |
| 4 | `lib/utils/constants.dart` 的 `lightTheme` / `darkTheme` | ~84 | 0 | 前玻璃时代的 ThemeData |
| | **合计** | **~4425** | | 含约 55 处硬编码色 |

其他：

- `flutter_highlight` 依赖（`pubspec.yaml:45`）唯一使用者是死文件 `markdown_preview.dart` → **死依赖**
- 主题配置与实际组件不匹配 4 处：`appBarTheme`（被 13 处局部覆盖）、`floatingActionButtonTheme`（无使用点）、`dropdownMenuTheme`（`DropdownButton` 不读，10 处）、`popupMenuTheme`（无使用点）

---

## 10. 统计修正记录

审计过程中发现并修正了 4 处统计错误，均源于“目测替代全量计数”：

| # | 轮次 | 原值 | 修正值 | 偏差 |
|---|---|---|---|---|
| 1 | 第 19 轮起（传播 5 轮） | `appIconColor` ~250 | **31**（排除死代码） | 8× |
| 2 | 第 32/33 轮 | `outline` 系列合计 ~440 | **222**（后续含 `appMutedIconColor` 为 249） | 2× |
| 3 | 第 38 轮 | `appMutedIconColor` 2 | **28**（排除死代码） | 14× |
| 4 | 第 43 轮 | 工具栏按钮 14 | **21** | 1.5× |

**教训**：跨轮沿用的估算会固化偏差，后续轮次会在错误基数上继续叠加。定期用统一命令重测是必要的。

---

## 11. 已排除项（累计 223 项）

以下曾被怀疑、经源码核实后确认**不是问题**：

| 类别 | 结论 |
|---|---|
| `appBarTheme` α0.92 / FAB 主题 | 死配置（无对象或全被覆盖） |
| 玻璃组件“完全无渲染” | 仅 premium 路径受影响，项目走 standard |
| WebView `--crepe-color-*` 映射缺口 | 17 个变量 0 引用，无影响 |
| 自定义图标字体 / `ImageIcon` / Android 原生启动图标 | 未使用或无冲突 |
| `InkWell` 水波纹 / `Switch`-`Slider`-`Checkbox` 主题 / `Tooltip` 的 `waitDuration` | 走主题默认，无局部覆写 |
| `ClipRRect` / `ShaderMask` / `BlendMode` 包裹玻璃 | 无实例 |
| `MonetColorScheme.toFlutterColorScheme` / `fromJson` | 完整实现 ✅ |
| `dividerTheme`（对 `Divider` 组件）/ `textTheme` / `scaffoldBackgroundColor` | 正确配置 ✅ |
| 30 处硬编码图标色 | 语义色（20）、深色/彩底上的白图标（10）、占位灰（3），全部合理 |
| `ThemeData` 的其他遗留字段（`canvasColor`/`cardColor`/`focusColor` 等） | M3 下回退到已设角色或视觉中性 |

---

## 12. 修复建议优先级

### 第 1 档：一处改动、多处收益

1. **接入 `GlassPage`**（或 `GlassScaffold`）
   - 补 `LiquidGlassScope` + `GlassBackgroundSource` → 真实背景采样
   - 补 `AdaptiveLiquidGlassLayer` → 渲染层（同时修复 `Transform` 通知链）
   - `statusBarStyle: auto` → 修复 4 个页面的状态栏
   - `background:` → 让采样背景跟随主题

### 第 2 档：补齐 `ColorScheme`

2. 设置 `outline` / `outlineVariant` / `onSurface` / `onSurfaceVariant` / `surfaceTint` / `secondaryContainer`
   → 一次性修复 249 处调用点
3. 把 `customIconColor` 同步写入 `ColorScheme`（如 `onSurface` / `onSurfaceVariant`）
   → 图标设置覆盖率从 37.6% 提升
4. 统一图标取色入口（`iconButtonTheme.foregroundColor` 改为 `appIconColor`）
   → 消除“文字色影响图标色”

### 第 3 档：替换为插件现成组件

| 替换对象 | 替换为 | 规模 |
|---|---|---|
| `MarkdownToolbar`（手写 21 按钮） | `GlassToolbar` + `GlassButton` | 1 个组件 |
| `SlidingSegmentToggle`（实色） | `GlassSegmentedControl` | 1 个组件 |
| 49 个 `AlertDialog` | `GlassDialog` | 49 处 |
| 桌面 `Container` + `NavigationRail` | `GlassNavigationShell` / `GlassVerticalBar` | 1 个组件 |
| `DropdownButton`（10 处） | `GlassPullDownButton` | 10 处 |

### 第 4 档：局部修正

- 玻璃浮在 WebView 上：`platformViewMode: passthrough` 或 `platformViewBackdrop: true`
- 移除 `AnimatedOpacity` 包裹玻璃（改用 `AnimatedScale` + 条件渲染）
- 修 `GlassCard` 双重内边距
- 清空 `surfaceTint`、玻璃模式下 `elevation: 0`
- 给玻璃件传 `GlassThemeData`（色调跟随主题）
- 桌面端 `titleBarStyle: TitleBarStyle.hidden`
- 覆盖 `tooltipTheme`、`listTileTheme`
- 删除 4 处死代码 + `flutter_highlight` 依赖
- 4 个无 AppBar 页面加 `AnnotatedRegion`（或直接用 `GlassPage`）

---

## 13. 需要实机验证的项

以下 4 项无法通过静态分析定论，需要改代码后在真机/模拟器上截图对比：

1. 接入 `GlassPage` 前后的玻璃观感对比（采样、折射、色调）
2. 开启粒子效果后的覆盖程度（`GlobalParticleOverlay` 挂在 `MaterialApp.builder`，粒子绘制在所有 UI 之上）
3. `surfaceTint` 的 elevation overlay 是否实际绘制
4. 桌面端双标题栏与 `Transform.scale` 下玻璃错位的实际表现

---

## 14. 附录

### 14.1 核查范围

| 目录 | 文件数 | 状态 |
|---|---|---|
| `lib/screens` | 41 | ✅ 全覆盖 |
| `lib/widgets` | 20 | ✅ 全覆盖 |
| `lib/utils` | 关键文件 | ✅ |
| `lib/services` | 13 | ✅（纯逻辑） |
| `lib/models` | 6 | ✅（纯数据） |
| `lib/` 合计 | **101** | ✅ 全覆盖 |
| `android/` / `windows/` / `ios/` | 平台资源 | ✅ |

### 14.2 关键命令

```bash
# 图标总使用量（排除死代码）
rg -n 'Icon\(' lib -g '*.dart' \
  --glob '!**/appearance_settings_screen.dart' \
  --glob '!**/markdown_preview.dart' \
  --glob '!**/unified_ui.dart' | wc -l
# → 255

# 未设置的语义角色（应为 0 命中）
rg -n '^\s+(outline|onSurface|onSurfaceVariant|outlineVariant|surfaceTint):' lib/main.dart

# 玻璃插件配置（应为 0 命中）
rg -n 'GlassThemeData|platformViewBackdrop|useOwnLayer|LiquidGlassScope|GlassBackgroundSource|preWarm' lib
```

### 14.3 基线

本报告基于提交 `257c173`（`fix: align editor header components at equal height`），
工作区干净，未做任何代码改动。
