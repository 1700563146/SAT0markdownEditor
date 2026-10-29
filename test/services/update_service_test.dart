// ============================================================================
// UpdateService 测试
// ============================================================================

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mdreader/services/update_service.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

// Mocks
class MockHttpClient extends Mock implements http.Client {}

class MockHttpResponse extends Mock implements http.StreamedResponse {}

class MockAppInstaller extends Mock implements AppInstaller {}

class FakePathProviderPlatform extends PathProviderPlatform {
  final String _tempPath;
  FakePathProviderPlatform(this._tempPath);

  @override
  Future<String?> getTemporaryPath() async => _tempPath;
}

/// 先吐两个字节再抛错，模拟传输中途断开
Stream<Uint8List> _interruptedStream() async* {
  yield Uint8List.fromList([1, 2]);
  throw StateError('连接中断');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const originalUrl = 'https://github.com/app.apk';
  const proxyA = 'https://a.example.com/';
  const proxyB = 'https://b.example.com/';

  group('UpdateService', () {
    late Directory tempDir;
    late MockHttpClient mockClient;
    late MockAppInstaller mockInstaller;

    /// 请求过的 URL，用于断言尝试顺序
    late List<String> requested;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('update_test');
      PathProviderPlatform.instance = FakePathProviderPlatform(tempDir.path);

      mockClient = MockHttpClient();
      mockInstaller = MockAppInstaller();
      requested = [];

      when(() => mockInstaller.install(any())).thenAnswer((_) async => true);

      registerFallbackValue(
        http.Request('GET', Uri.parse('http://example.com')),
      );
    });

    tearDown(() {
      try {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      } catch (_) {}
    });

    MockHttpResponse okResponse() {
      final response = MockHttpResponse();
      when(() => response.statusCode).thenReturn(200);
      when(() => response.contentLength).thenReturn(10);
      when(
        () => response.stream,
      ).thenAnswer((_) => http.ByteStream.fromBytes([1, 2, 3]));
      return response;
    }

    /// 让 [urls] 成功、其余请求抛异常
    void respondWith(Map<String, bool> outcomes) {
      when(() => mockClient.send(any())).thenAnswer((invocation) async {
        final request = invocation.positionalArguments.first as http.Request;
        final url = request.url.toString();
        requested.add(url);
        if (outcomes[url] == true) return okResponse();
        throw Exception('下载失败: $url');
      });
    }

    group('buildProxyUrl', () {
      test('补全缺失的结尾斜杠', () {
        expect(
          UpdateService.buildProxyUrl('https://p.example.com', originalUrl),
          'https://p.example.com/$originalUrl',
        );
      });

      test('保留代理前缀中的路径段', () {
        expect(
          UpdateService.buildProxyUrl('https://p.example.com/gh/', originalUrl),
          'https://p.example.com/gh/$originalUrl',
        );
      });

      test('非 http/https 前缀返回 null', () {
        expect(
          UpdateService.buildProxyUrl('ftp://p.example.com/', originalUrl),
          isNull,
        );
        expect(
          UpdateService.buildProxyUrl('p.example.com/', originalUrl),
          isNull,
        );
        expect(UpdateService.buildProxyUrl('', originalUrl), isNull);
        expect(UpdateService.buildProxyUrl('   ', originalUrl), isNull);
      });

      test('目标地址非法时返回 null', () {
        expect(
          UpdateService.buildProxyUrl(proxyA, 'github.com/app.apk'),
          isNull,
        );
        expect(UpdateService.buildProxyUrl(proxyA, ''), isNull);
      });
    });

    test('列表顺序尝试，第一个代理成功即停止', () async {
      respondWith({'$proxyA$originalUrl': true});

      final success = await UpdateService.downloadAndInstallUpdate(
        originalUrl,
        'update.apk',
        proxies: [proxyA, proxyB],
        client: mockClient,
        installer: mockInstaller,
      );

      expect(success, true);
      expect(requested, ['$proxyA$originalUrl']);
      verify(
        () => mockInstaller.install(any(that: contains('update.apk'))),
      ).called(1);
    });

    test('前一个代理失败后依次尝试，全部失败回退原始链接', () async {
      respondWith({
        '$proxyA$originalUrl': false,
        '$proxyB$originalUrl': false,
        originalUrl: true,
      });

      final success = await UpdateService.downloadAndInstallUpdate(
        originalUrl,
        'update.apk',
        proxies: [proxyA, proxyB],
        client: mockClient,
        installer: mockInstaller,
      );

      expect(success, true);
      expect(requested, [
        '$proxyA$originalUrl',
        '$proxyB$originalUrl',
        originalUrl,
      ]);
    });

    test('代理传输中途断开视为失败并继续回退', () async {
      final broken = MockHttpResponse();
      when(() => broken.statusCode).thenReturn(200);
      when(() => broken.contentLength).thenReturn(null);
      when(
        () => broken.stream,
      ).thenAnswer((_) => http.ByteStream(_interruptedStream()));

      final ok = okResponse();
      when(() => mockClient.send(any())).thenAnswer((invocation) async {
        final request = invocation.positionalArguments.first as http.Request;
        final url = request.url.toString();
        requested.add(url);
        if (url == '$proxyA$originalUrl') return broken;
        if (url == originalUrl) return ok;
        throw Exception('Unexpected URL: $url');
      });

      final success = await UpdateService.downloadAndInstallUpdate(
        originalUrl,
        'update_partial.apk',
        proxies: [proxyA],
        client: mockClient,
        installer: mockInstaller,
      );

      expect(success, true);
      expect(requested, ['$proxyA$originalUrl', originalUrl]);
    });

    test('无效代理条目被跳过，不发起请求', () async {
      respondWith({'$proxyB$originalUrl': true});

      final success = await UpdateService.downloadAndInstallUpdate(
        originalUrl,
        'update.apk',
        proxies: ['', 'not a url', 'ftp://p.example.com/', proxyB],
        client: mockClient,
        installer: mockInstaller,
      );

      expect(success, true);
      expect(requested, ['$proxyB$originalUrl']);
    });

    test('无代理时直接使用原始链接（不再内置镜像）', () async {
      respondWith({originalUrl: true});

      final success = await UpdateService.downloadAndInstallUpdate(
        originalUrl,
        'update.apk',
        client: mockClient,
        installer: mockInstaller,
      );

      expect(success, true);
      expect(requested, [originalUrl]);
      expect(requested.any((url) => url.contains('gh-proxy')), false);
    });

    test('原始链接也失败时不触发安装', () async {
      respondWith({});

      final success = await UpdateService.downloadAndInstallUpdate(
        originalUrl,
        'update_fail.apk',
        proxies: [proxyA],
        client: mockClient,
        installer: mockInstaller,
      );

      expect(success, false);
      verifyNever(() => mockInstaller.install(any()));
    });
  });
}
