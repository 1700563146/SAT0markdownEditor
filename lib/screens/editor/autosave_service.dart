import 'dart:async';

/// T-09：编辑器自动保存服务
///
/// 从 `_EditorScreenState` 中拆出的定时保存调度职责。
/// 由编辑器页面在 initState 中创建，并随页面 dispose 释放。
class AutosaveService {
  AutosaveService();

  Timer? _timer;

  /// 是否启用自动保存
  bool enabled = false;

  /// 自动保存间隔
  Duration interval = const Duration(seconds: 30);

  /// 当前是否已启动
  bool get isActive => _timer != null;

  /// 配置并按 [enabled] 启动 / 停止定时保存。
  ///
  /// [onTick] 为每次触发时执行的回调（页面负责执行实际保存逻辑）。
  void configure({
    required bool enabled,
    required Duration interval,
    required Future<void> Function() onTick,
  }) {
    stop();
    this.enabled = enabled;
    this.interval = interval;
    if (enabled) {
      _timer = Timer.periodic(interval, (_) {
        unawaited(onTick());
      });
    }
  }

  /// 停止定时保存（不改变已保存的配置）
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// 释放资源
  void dispose() {
    stop();
  }
}
