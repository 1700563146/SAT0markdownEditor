# 快速开始指南

## Android 用户

### 安装
1. 下载对应的 APK 文件：
   - `沢-1.4.4-arm64-v8a.apk` - 推荐（大多数现代设备）
   - `沢-1.4.4-armeabi-v7a.apk` - 旧款 32 位设备
   - `沢-1.4.4-x86_64.apk` - 模拟器 / x86 设备
2. 安装 APK
3. 授予文件访问权限

### 系统要求
- Android 5.0+ (API 21)

### 工作区位置
默认工作区: `/storage/emulated/0/Documents/Ushio-md`

## 开发者

### 构建 Android 版本
```batch
# 分架构 APK（推荐）
.\build_abi_release.bat

# 通用 APK
flutter build apk --release
```

### 调试版构建
```batch
.\build_debug.bat
```

## 常见问题

### Q: Android 提示无法访问文件？
A: 在设置中授予应用文件访问权限

### Q: 如何修改工作区位置？
A: 在应用设置中更改工作区路径

### Q: 如何导入外部 Markdown 文件？
A: 使用文件管理器打开文件，选择用「沢」打开

### Q: 数据会丢失吗？
A: 所有文件保存在本地工作区，不会丢失。建议定期备份。

## 技术支持
- GitHub Issues: https://github.com/jiuxina/ushio-md/issues
- 文档: 项目 `docs/` 目录
