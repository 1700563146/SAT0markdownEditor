import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../utils/debug_log.dart';
import 'milkdown_webview_editor.dart';

/// 冷启动预热视图。
///
/// 应用启动后用一个 1x1 离屏 WebView 把编辑器页面完整跑一遍（加载 + 求值 + 建一次
/// 空文档编辑器），把下面这些成本从「打开文档」挪到「打开软件」：
/// - Chromium/V8 引擎与渲染进程的一次性初始化；
/// - 资源的 HTTP 缓存与 V8 代码缓存落盘；
/// - ProseMirror/Crepe 首次建实例的代码路径。
///
/// Android 公开 SDK 没有 `WebView.warmUp()/startUp()`（是 @hide/@SystemApi），
/// 所以只能真的起一个 WebView 来预热。预热完成后由父组件把它移出树。
class MilkdownWarmupView extends StatefulWidget {
  const MilkdownWarmupView({required this.onWarmed, super.key});

  /// 预热结束（成功或超时）后回调，父组件据此移除本视图。
  final VoidCallback onWarmed;

  /// 用户已经开始真正打开文档时调用：立刻放弃预热，避免低端机上同时存在
  /// 两个 WebView 实例抢内存。
  static void cancel() => _cancelCallback?.call();

  static VoidCallback? _cancelCallback;

  @override
  State<MilkdownWarmupView> createState() => _MilkdownWarmupViewState();
}

class _MilkdownWarmupViewState extends State<MilkdownWarmupView> {
  static const _hardTimeout = Duration(seconds: 12);
  static const _settleDelay = Duration(milliseconds: 800);

  String? _url;
  bool _finished = false;
  bool _editorBooted = false;
  Timer? _settleTimer;

  @override
  void initState() {
    super.initState();
    MilkdownWarmupView._cancelCallback = _finish;
    unawaited(_resolveUrl());
    // 页面卡住（服务器没起来、JS 抛错）也不能让预热视图常驻树里。
    Timer(_hardTimeout, _finish);
  }

  @override
  void dispose() {
    _settleTimer?.cancel();
    if (identical(MilkdownWarmupView._cancelCallback, _finish)) {
      MilkdownWarmupView._cancelCallback = null;
    }
    super.dispose();
  }

  Future<void> _resolveUrl() async {
    final url = await milkdownRuntimeUrl();
    if (!mounted) return;
    if (url == null) {
      _finish();
      return;
    }
    setState(() => _url = url);
  }

  void _finish() {
    if (_finished || !mounted) return;
    _finished = true;
    _settleTimer?.cancel();
    widget.onWarmed();
  }

  /// 让 WebView 有机会把代码缓存写盘，再移出树。
  void _scheduleFinish() {
    _settleTimer?.cancel();
    _settleTimer = Timer(_settleDelay, _finish);
  }

  Future<void> _bootEditor(InAppWebViewController controller) async {
    if (_editorBooted) return;
    _editorBooted = true;
    openTrace('warmup: page loaded, booting editor');
    await controller.evaluateJavascript(
      source: '''
        (function() {
          var b = window.__USHIO_BRIDGE__;
          if (!b || !b.onFlutterMessage) return;
          b.onFlutterMessage({
            v: 1, source: 'flutter', target: 'web', type: 'init_doc',
            requestId: 'warmup', ts: Date.now(),
            payload: { markdown: '# \\u9884\\u70ed', readOnly: true, baseDirectory: '' }
          });
        })();
      ''',
    );
  }

  void _onBridgeMessage(List<dynamic> args) {
    if (args.isEmpty || args.first is! Map) return;
    final type = (args.first as Map)['type'];
    if (type == 'on_render_complete' || type == 'on_ready') {
      openTrace('warmup: editor instance ready');
      _scheduleFinish();
    }
  }

  @override
  Widget build(BuildContext context) {
    final url = _url;
    if (url == null || _finished) return const SizedBox.shrink();
    return InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(url)),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        cacheEnabled: true,
        transparentBackground: true,
      ),
      onWebViewCreated: (controller) {
        controller.addJavaScriptHandler(
          handlerName: 'bridge',
          callback: (args) {
            _onBridgeMessage(args);
            return {'ok': true};
          },
        );
      },
      onLoadStop: (controller, _) => _bootEditor(controller),
    );
  }
}
