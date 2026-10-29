/// 轻量级调试日志工具
///
/// 在 release 模式下，所有调用会被 Dart 编译器 tree-shaking 移除，
/// 不会执行字符串拼接，也不会产生任何运行时开销。
///
/// 用法：将 `debugPrint(...)` 替换为 `appDebugLog(...)` 即可。

import 'package:flutter/foundation.dart';

/// 仅在 debug 模式下输出日志。
/// release 模式下整个函数体（包括参数的字符串拼接）会被编译器消除。
void appDebugLog(String message) {
  if (kDebugMode) {
    debugPrint(message);
  }
}

/// 打开文档的里程碑计时开关：`flutter build --dart-define=OPEN_TRACE=true` 才生效。
///
/// 注意 `bool.fromEnvironment` 只认字符串 "true"/"false"，写 `=1` 会被当成未定义。
/// 默认关闭（const 为 false，整段被 tree-shaking 消除），这样 release 里既没有
/// 平台通道打印开销，又能在需要时量出真机上每次打开的分段耗时。
const bool openTraceEnabled = bool.fromEnvironment('OPEN_TRACE');

void openTrace(String message) {
  if (openTraceEnabled) {
    debugPrint('[OPEN] $message');
  }
}
