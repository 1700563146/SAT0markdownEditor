# 构建脚本说明

## Android APK 构建

### build_abi_release.bat - Android APK 构建

构建分架构的 Android APK (arm64-v8a, armeabi-v7a, x86_64)

**优点:**
- 每个 APK 体积更小
- 用户只下载适合其设备的版本

**输出:**
- `app-arm64-v8a-release.apk` - 适用于 64 位 ARM 设备
- `app-armeabi-v7a-release.apk` - 适用于 32 位 ARM 设备
- `app-x86_64-release.apk` - 适用于 x86_64 模拟器设备

---

### build_debug.bat - 调试版构建

构建调试版 APK，用于日常开发验证。

---

## 版本更新

### Q: 如何更新版本号?

A: 编辑 `pubspec.yaml` 文件中的 `version` 字段:

```yaml
version: 1.6.9+4105
# 格式: version_name+version_code
```

---

## 应用图标

图标源文件为仓库根目录的 `app.png`，通过 `flutter_launcher_icons` 生成各平台启动图标。

---

## 相关链接

- [Flutter Android 支持](https://docs.flutter.dev/platform-integration/android/overview)
- [Flutter 打包与发布](https://docs.flutter.dev/deployment/android)
