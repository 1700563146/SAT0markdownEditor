// ============================================================================
// buildProxyUrl / normalizeProxyPrefix 白名单测试（T-03）
//
// 安全约束：代理与目标 URL 仅允许 https，防止更新包被明文劫持。
// ============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:mdreader/services/update_service.dart';

void main() {
  group('normalizeProxyPrefix', () {
    test('接受 https 前缀', () {
      expect(
        UpdateService.normalizeProxyPrefix('https://ghproxy.com/'),
        'https://ghproxy.com/',
      );
    });

    test('自动补全结尾斜杠', () {
      expect(
        UpdateService.normalizeProxyPrefix('https://ghproxy.com'),
        'https://ghproxy.com/',
      );
    });

    test('拒绝 http 前缀', () {
      expect(UpdateService.normalizeProxyPrefix('http://ghproxy.com/'), isNull);
    });

    test('拒绝空串与纯空白', () {
      expect(UpdateService.normalizeProxyPrefix(''), isNull);
      expect(UpdateService.normalizeProxyPrefix('   '), isNull);
    });

    test('拒绝非 URL 字符串', () {
      expect(UpdateService.normalizeProxyPrefix('not a url'), isNull);
      expect(UpdateService.normalizeProxyPrefix('ftp://ghproxy.com/'), isNull);
    });
  });

  group('buildProxyUrl', () {
    const target = 'https://github.com/jiuxina/ushio-md/releases/download/'
        'v1.6.9/ushio-md-v1.6.9-arm64-v8a.apk';

    test('https 代理 + https 目标正常拼接', () {
      expect(
        UpdateService.buildProxyUrl('https://p.com/', target),
        'https://p.com/$target',
      );
    });

    test('http 代理被拒绝', () {
      expect(UpdateService.buildProxyUrl('http://p.com/', target), isNull);
    });

    test('http 目标被拒绝', () {
      expect(
        UpdateService.buildProxyUrl('https://p.com/', 'http://evil.com/a.apk'),
        isNull,
      );
    });

    test('非法目标被拒绝', () {
      expect(UpdateService.buildProxyUrl('https://p.com/', ''), isNull);
      expect(UpdateService.buildProxyUrl('https://p.com/', 'file:///a.apk'), isNull);
      expect(UpdateService.buildProxyUrl('https://p.com/', 'javascript:alert(1)'), isNull);
    });

    test('非法代理前缀返回 null', () {
      expect(UpdateService.buildProxyUrl('', target), isNull);
      expect(UpdateService.buildProxyUrl('http://p.com', target), isNull);
    });
  });
}
