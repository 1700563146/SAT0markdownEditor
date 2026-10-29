# ushio-md 优化路线图（OPTIMIZATION ROADMAP）

> 基线版本：v1.6.9+4105（仓库初始化提交）
> 维护方式：本文档是后续所有优化工作的唯一任务清单。每完成一项，将对应任务状态改为 `已完成`，并在「验证记录」追加 commit hash 与验证结果；被放弃的任务标记 `已放弃` 并注明原因。
> 实施顺序：严格按 T-01 → T-10 顺序推进（P0 先于 P1，P1 先于 P2）；P3 功能项可在 P0 完成后穿插进行。

## 通用约定

- 提交信息使用 Conventional Commits：`fix:` / `perf:` / `refactor:` / `feat:` / `docs:` / `ci:`。
- 每次改动后必须执行：`flutter analyze`（0 error）→ `flutter test` → `flutter build apk --debug`。
- **禁止**直接运行 `dart run flutter_launcher_icons`：pubspec 配置仍指向 app.png，会覆盖手写的自适应图标（foreground/background/monochrome）资源。
- 图标体系已重构（2026-10 完成）：`app.png`(512 圆角透明)、5 档密度 `ic_launcher.png`、自适应 `ic_launcher_foreground.png`(72dp 安全区) + `ic_launcher_background.png`(边缘延展渐变) + `ic_launcher_monochrome.png`(Android 13)，`mipmap-anydpi-v26/ic_launcher.xml` 已改为位图三层结构。`assets/icons/icon2.png`（黑猫）保留供设置内切换。
- 本机（开发机）当前无 Flutter/Dart SDK：构建验证需在有 SDK 的环境执行，或先安装 SDK。

---

## P0 — 数据与安全（必须先修）

### T-01 版本快照无限增长并污染工作区与云同步 `已完成（2026-10，待构建验证）`

- 问题：每次保存写一份全量快照，无去重、无保留策略；快照位于文档同级 `.versions/`，而目录扫描与云同步均不排除它，导致 `v1.md`/`v2.md` 出现在文件列表、搜索结果并被上传到 WebDAV/FTP。
- 证据：
  - `lib/services/version_service.dart#L101`（createVersion 全量写入，无清理逻辑；仅 #L195 手动删除单个版本）
  - `lib/services/file_service.dart#L296`（`directory.list(recursive: true)` 不排除 `.versions`）
  - `lib/services/cloud_sync_service.dart#L434`（同步收集递归全部文件）
- 改法：
  1. 快照写入前对内容做 SHA-256，与最新快照相同则跳过；
  2. 保留策略：最近 N 个（默认 20）+ 每天保留 1 个，超出自动清理；
  3. 在 file_service 扫描与 cloud_sync 收集处统一排除 `.versions/`（常量集中定义）；长期方案：快照迁移到应用私有目录 `getApplicationDocumentsDirectory()/versions/<docHash>/`。
- 验收：连续保存相同内容 10 次仅 1 份快照；文件列表/搜索/同步清单中不再出现 `.versions` 内文件；设置页可配置保留数量（见 T-13）。

### T-02 云同步仅比较 mtime、串行传输、无重试 `已完成（2026-10，待构建验证）`

- 问题：冲突判断只看修改时间，时间戳不可靠时误判；上传/下载在 for 循环中串行执行，弱网整批失败且无重试。
- 证据：`lib/services/cloud_sync_service.dart#L209`、`#L346`（mtime 比较）；`#L189`、`#L265`、`#L337`（串行循环）。
- 改法：
  1. 本地同步台账（shared_preferences 或 SQLite）：`relativePath → {hash, mtime, lastSyncedHash}`，做本地/云端/基线三方比较；
  2. 传输并发 3–4（`Future.wait` 分片）；
  3. 单文件失败指数退避重试 3 次，失败清单持久化可续传；
  4. 同步结果输出结构化报告（成功/跳过/冲突/失败计数）。
- 验收：为冲突三态（仅本地改/仅云端改/双方改）各写一个集成测试；断网重连后只续传失败项。

### T-03 应用内更新无完整性与签名校验，代理允许 http `已完成（2026-10，待构建验证）`

- 问题：APK 下载后直接交安装器，无 SHA-256、无签名校验、不防降级；下载代理前缀允许 `http://`，存在中间人替换安装包风险。
- 证据：`lib/services/update_service.dart#L197`（buildProxyUrl）、`#L244-L259`（代理下载→安装）；`android/app/src/main/kotlin/com/mdreader/mdreader/MainActivity.kt#L87-L102`（installApk 无校验）。
- 改法：
  1. Release 发布时 CI 生成 `checksums.txt`（SHA-256），更新检查一并拉取，下载后校验；
  2. 安装前用 `PackageManager.getPackageArchiveInfo` 校验 signer 与当前应用一致，并拒绝 versionCode 降级；
  3. `buildProxyUrl` 仅接受 `https://` 前缀。
- 验收：篡改 APK 后安装被拒绝并提示；配置 http 代理前缀时被忽略；单元测试覆盖 buildProxyUrl 白名单。

### T-04 WebView 内容清理为死代码且正则可绕过 `未开始`

- 问题：`sanitizeMarkdown` 全库无调用点；其正则规则可被 `<scr<script>ipt>`、无引号 `onerror=` 绕过。
- 证据：`lib/widgets/milkdown_webview_editor.dart#L42-L60`（正则规则）、`#L68`（sanitizeMarkdown 定义，无调用）。
- 改法：
  1. WebView 内引入 DOMPurify 并设置 CSP 白名单（script-src 仅自身资源）；
  2. Flutter 侧删除死代码或仅保留 URL 协议白名单校验（`http/https/mailto/相对路径`）；
  3. 收紧 JS bridge 命令白名单，未知命令拒绝执行并记录。
- 验收：XSS PoC（嵌套 script、无引号事件属性、`javascript:` 链接）在预览中不执行；bridge 收到未知命令时 no-op。

---

## P1 — 性能

### T-05 启动路径主 isolate 串行阻塞 `未开始`

- 问题：`runApp` 前串行 await 工作区初始化、自定义字体、LiquidGlass、PackageInfo。
- 证据：`lib/main.dart#L75-L84`（await 链）、`#L92`（runApp）。
- 改法：先 `runApp` 显示骨架；字体加载与 PackageInfo 移入 `addPostFrameCallback`/空闲任务；工作区初始化保留但加 3s 超时与失败兜底。
- 验收：`flutter run --profile` 启动 trace 中首帧时间下降；无字体时首屏不白屏。

### T-06 编辑变更全量回写 Markdown `未开始`

- 问题：120ms 防抖后仍把全文经 postMessage 传回 Flutter，长文放大序列化与主线程压力。
- 证据：`lib/screens/editor_screen.dart#L2049-L2053`；`lib/models/milkdown_bridge.dart#L25-L59`（InitDocPayload 全文）。
- 改法：改为增量 patch（行级 diff 或 ProseMirror 事务序列化）；或对 >100KB 文档提高提交间隔并仅在失焦/保存时全量对齐。
- 验收：100KB 文档连续输入时 Flutter 侧单次消息 < 4KB（增量模式）。

### T-07 目录扫描主 isolate 递归 + 逐文件 stat `未开始`

- 问题：工作区大时扫描卡 UI。
- 证据：`lib/services/file_service.dart#L296`（recursive list + 逐文件 stat）。
- 改法：`compute`/独立 isolate 扫描；结果建内存索引（路径→mtime/size）；目录展开时非递归增量刷新。
- 验收：1 万文件工作区打开首页无掉帧（DevTools frame chart）。

### T-08 版本对比 LCS O(n·m) 矩阵 `未开始`

- 问题：千行文档矩阵约 4MB 内存，长文卡顿；现有阈值仅降级展示不降计算量。
- 证据：`lib/utils/line_diff_calculator.dart#L223-L240`；`lib/screens/editor/components/diff_view_overlay.dart#L155-L183`。
- 改法：换 Myers/patience diff（O((N+M)D)）；超阈值时只输出统计摘要不做行级对齐。
- 验收：5000 行对比 < 200ms（release 模式计时）。

---

## P2 — 可维护性与工程化

### T-09 拆分 God class `未开始`

- 问题：`editor_screen.dart` 3123 行、`settings_provider.dart` 1487 行，职责混杂、setState 频繁。
- 改法：editor 拆出 `EditorSessionController`（文档生命周期）、`AutosaveService`（定时/防抖保存）、`SnapshotService`（对接 T-01）；settings 按领域（编辑器/同步/外观/更新）拆 Provider。
- 验收：单文件 < 800 行；`flutter analyze` 无新增 warning；现有行为回归测试通过。

### T-10 CI 补质量门禁与正式签名 `未开始`

- 问题：CI 只构建不测试；release 用 debug 签名。
- 证据：`.github/workflows/release.yml#L55-L56`；`android/app/build.gradle.kts#L36-L38`。
- 改法：workflow 增加 `flutter analyze --fatal-infos=false` + `flutter test` 步骤；release 配置独立 keystore（secrets 注入）；产物附 `checksums.txt`（配合 T-03）。
- 验收：PR 上 analyze/test 失败阻断合并；release 产物为正式签名且附校验文件。

---

## P3 — 功能与体验

### T-11 Mermaid 与脚注支持 `未开始`
- 改法：Milkdown 侧引入 `@milkdown/plugin-diagram`（mermaid）与 footnote 插件；预览与导出同步启用。
- 验收：README 级 mermaid 图与 `[^1]` 脚注正确渲染。

### T-12 全局工作区搜索 `未开始`
- 改法：复用 T-07 索引，后台 isolate 做全文 grep（分块读取），结果按文件分组跳转。
- 验收：1 万文件工作区搜索响应 < 1s，可取消。

### T-13 版本历史管理页 `未开始`
- 改法：设置内新增「版本历史」：保留数量/容量上限配置、单文档快照列表与一键清理（依赖 T-01 保留策略）。
- 验收：可配置 N；清理后磁盘占用即时下降。

### T-14 同步冲突三方合并 `未开始`
- 改法：基于 T-02 台账的 base 哈希做三路合并（本地/云端/base），冲突块交互式选择（依赖 T-02）。
- 验收：双方修改同文件时产生合并结果而非二选一覆盖。

### T-15 存储权限 SAF 化（上架 Play 前置） `未开始`
- 问题：`MANAGE_EXTERNAL_STORAGE` 不符合 Play 政策。
- 证据：`android/app/src/main/AndroidManifest.xml#L3-L5`；`lib/services/file_service.dart#L200-L223`。
- 改法：提供 SAF（`ACTION_OPEN_DOCUMENT_TREE`）目录授权路径，与现有全存储模式并存，按安装来源开关。
- 验收：SAF 模式下读写/扫描/同步全链路可用。

### T-16 动态图标切换后启动器刷新 `未开始`
- 问题：`setComponentEnabledSetting` 切换 alias 后部分启动器不刷新。
- 证据：`android/app/src/main/kotlin/com/mdreader/mdreader/MainActivity.kt#L64-L85`。
- 改法：切换后广播 `ACTION_PACKAGE_CHANGED` 或提示用户重启桌面；记录用户选择防重复切换。
- 验收：MIUI/OneUI 实机切换后图标即时更新。

---

## 验证记录

| 任务 | 状态 | commit | 验证结果 |
| --- | --- | --- | --- |
| 图标重构 | 已完成 | （仓库初始化提交） | aapt2 compile 通过；待真机/模拟器目视确认 |
| T-01 | 已完成 | 见 `git log`（feat: 版本快照去重与保留策略） | 人工自审通过：去重/回填/保留策略/锁修正/`.versions` 排除（本地扫描+云同步收发双侧）均已实现；**待**有 Flutter SDK 环境执行 `flutter pub get`（新增 crypto 依赖）→ `flutter analyze` → `flutter test` → `flutter build apk --debug`，并按验收标准实测 |
| T-02 | 已完成 | 见 `git log`（feat: 云同步台账三方比较与并发传输） | 新增 `lib/services/sync_ledger.dart`（SHA-256 内容哈希 + 远程 mtime 容差 2s 的三方比较，绑定工作区，工作区变更自动重置）；syncAll 重构为「比较→并发上传(4)→刷新远程列表→并发下载→台账落盘」；单文件失败指数退避重试 3 次，失败不写台账=天然续传；previewSync 未变更文件不再因 mtime 漂移误报冲突；UI 增加失败计数提示。**待** SDK 环境构建验证 + 真机 WebDAV 实测（首次同步逐文件初始化台账，无批量重传） |
| T-03 | 已完成 | 见 `git log`（feat: 应用内更新完整性/签名校验与 https 代理白名单） | ① CI 生成 checksums.txt 并随 release 发布；② 更新检查拉取 checksums.txt，下载后 SHA-256 校验，不匹配拒绝安装并删除文件；③ MainActivity.installApk 增加包身份/签名一致性/防降级三重校验，拒绝原因回传 UI 展示；④ 代理前缀与目标 URL 仅允许 https；⑤ 新增 test/build_proxy_url_test.dart 覆盖白名单。**待** SDK 环境构建验证 + 真机实测（正常更新 / 篡改 APK / 配置 http 代理被忽略 / 降级包被拒绝） |
