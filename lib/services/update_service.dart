// ============================================================================
// 更新检查服务
// ============================================================================
//
// 通过 GitHub API 检查应用是否有新版本。
// 仓库地址：https://github.com/jiuxina/ushio-md
// ============================================================================

import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../utils/debug_log.dart';

/// 安装器抽象
class AppInstaller {
  static const platform = MethodChannel('com.ushiomd/install');

  Future<bool?> install(String filePath) async {
    try {
      final result = await platform.invokeMethod<bool>('installApk', {
        'filePath': filePath,
      });
      return result;
    } catch (e) {
      appDebugLog('Install error: $e');
      return false;
    }
  }
}

/// 更新信息
class UpdateInfo {
  final String latestVersion;
  final String currentVersion;
  final String downloadUrl;
  final String changelog;
  final bool hasUpdate;

  UpdateInfo({
    required this.latestVersion,
    required this.currentVersion,
    required this.downloadUrl,
    required this.changelog,
    required this.hasUpdate,
  });
}

/// 更新规则
enum UpdateChannel { stable, prerelease }

/// 更新检查服务
class UpdateService {
  /// GitHub 稳定版 API 地址
  static const String _apiUrl =
      'https://api.github.com/repos/jiuxina/ushio-md/releases/latest';

  /// GitHub 全部发布列表地址
  static const String _allReleasesUrl =
      'https://api.github.com/repos/jiuxina/ushio-md/releases';

  /// 检查更新
  ///
  /// [currentVersion] 当前应用版本号
  /// [channel] 更新规则，稳定版检查 latest，测试版扫描全部发布
  /// 返回 UpdateInfo 或 null（检查失败时）
  static Future<UpdateInfo?> checkForUpdate(
    String currentVersion, {
    UpdateChannel channel = UpdateChannel.stable,
  }) async {
    final client = http.Client();
    try {
      final url = channel == UpdateChannel.stable ? _apiUrl : _allReleasesUrl;
      final response = await client
          .get(
            Uri.parse(url),
            headers: {'Accept': 'application/vnd.github.v3+json'},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final dynamic decoded = jsonDecode(response.body);

        final List<dynamic> releases = decoded is List ? decoded : [decoded];
        final Map<String, dynamic>? release = _selectRelease(releases, channel);

        if (release == null) {
          appDebugLog('没有找到符合更新规则的发布版本');
          return null;
        }
        final data = release;

        // 获取最新版本号（去掉 v 前缀）
        final latestVersion = (data['tag_name'] as String).replaceFirst(
          'v',
          '',
        );

        // 获取下载链接（查找 APK 文件）
        String downloadUrl = data['html_url'] ?? '';
        final assets = data['assets'] as List<dynamic>?;
        if (assets != null && assets.isNotEmpty) {
          // 优先查找 arm64 版本
          for (final asset in assets) {
            final name = asset['name'] as String? ?? '';
            if (name.contains('arm64') && name.endsWith('.apk')) {
              downloadUrl = asset['browser_download_url'] ?? downloadUrl;
              break;
            }
          }
          // 如果没找到 arm64，查找任意 APK
          if (downloadUrl == data['html_url']) {
            for (final asset in assets) {
              final name = asset['name'] as String? ?? '';
              if (name.endsWith('.apk')) {
                downloadUrl = asset['browser_download_url'] ?? downloadUrl;
                break;
              }
            }
          }
        }

        // 获取更新日志
        final changelog = data['body'] as String? ?? '暂无更新说明';

        // 比较版本号
        final hasUpdate = _compareVersions(latestVersion, currentVersion) > 0;

        return UpdateInfo(
          latestVersion: latestVersion,
          currentVersion: currentVersion,
          downloadUrl: downloadUrl,
          changelog: changelog,
          hasUpdate: hasUpdate,
        );
      } else {
        appDebugLog('检查更新失败: HTTP ${response.statusCode}');
        return null;
      }
    } catch (e) {
      appDebugLog('检查更新异常: $e');
      return null;
    } finally {
      client.close();
    }
  }

  /// 按更新规则选择 GitHub release
  static Map<String, dynamic>? _selectRelease(
    List<dynamic> releases,
    UpdateChannel channel,
  ) {
    if (channel == UpdateChannel.stable) {
      final release = releases.isNotEmpty ? releases.first : null;
      return release is Map<String, dynamic> ? release : null;
    }

    for (final release in releases) {
      if (release is! Map<String, dynamic>) continue;
      if (release['draft'] == true) continue;
      if (release['prerelease'] != true) continue;
      return release;
    }
    return null;
  }

  /// 比较版本号
  ///
  /// 返回值：
  /// - 正数：v1 > v2
  /// - 0：v1 == v2
  /// - 负数：v1 < v2
  static int _compareVersions(String v1, String v2) {
    final parts1 = v1.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final parts2 = v2.split('.').map((e) => int.tryParse(e) ?? 0).toList();

    // 补齐长度
    while (parts1.length < 3) {
      parts1.add(0);
    }
    while (parts2.length < 3) {
      parts2.add(0);
    }

    for (int i = 0; i < 3; i++) {
      if (parts1[i] > parts2[i]) return 1;
      if (parts1[i] < parts2[i]) return -1;
    }
    return 0;
  }

  /// 用代理前缀拼出最终下载地址；任一输入非法时返回 null
  ///
  /// 约定：代理条目就是 `https://<代理域名>/` 这一段前缀，下载时直接拼接原始链接。
  /// 缺少结尾斜杠会自动补全，否则 `https://p.com` + `https://x/a.apk` 会拼成坏地址。
  static String? buildProxyUrl(String prefix, String target) {
    final normalizedPrefix = normalizeProxyPrefix(prefix);
    if (normalizedPrefix == null) return null;

    final trimmedTarget = target.trim();
    final targetUri = Uri.tryParse(trimmedTarget);
    if (targetUri == null ||
        !(targetUri.isScheme('http') || targetUri.isScheme('https')) ||
        !targetUri.hasAuthority) {
      return null;
    }

    return '$normalizedPrefix$trimmedTarget';
  }

  /// 校验并归一化代理前缀；非法返回 null
  static String? normalizeProxyPrefix(String rawPrefix) {
    final trimmed = rawPrefix.trim();
    if (trimmed.isEmpty) return null;

    final uri = Uri.tryParse(trimmed);
    if (uri == null ||
        !(uri.isScheme('http') || uri.isScheme('https')) ||
        uri.host.isEmpty) {
      return null;
    }

    return trimmed.endsWith('/') ? trimmed : '$trimmed/';
  }

  /// 下载并安装更新
  ///
  /// [url] APK 下载链接
  /// [fileName] 保存的文件名
  /// [proxies] 用户自定义代理前缀列表，按顺序尝试；为空或全部失败时直连 [url]
  /// [onProgress] 进度回调 (0.0 - 1.0)
  static Future<bool> downloadAndInstallUpdate(
    String url,
    String fileName, {
    Function(double)? onProgress,
    http.Client? client,
    AppInstaller? installer,
    List<String> proxies = const [],
  }) async {
    File? apkFile;

    for (final prefix in proxies) {
      final proxyUrl = buildProxyUrl(prefix, url);
      if (proxyUrl == null) {
        appDebugLog('代理条目非法，已跳过: $prefix');
        continue;
      }

      if (await _downloadFile(
        proxyUrl,
        fileName,
        onProgress: onProgress,
        client: client,
      )) {
        apkFile = await _getLocalFile(fileName);
        break;
      }
      appDebugLog('代理下载失败，尝试下一个: $proxyUrl');
    }

    if (apkFile == null) {
      if (await _downloadFile(
        url,
        fileName,
        onProgress: onProgress,
        client: client,
      )) {
        apkFile = await _getLocalFile(fileName);
      } else {
        appDebugLog('直连原始链接下载失败: $url');
      }
    }

    if (apkFile != null && apkFile.existsSync()) {
      // 安装
      appDebugLog('开始安装: ${apkFile.path}');
      final appInstaller = installer ?? AppInstaller();
      final result = await appInstaller.install(apkFile.path);
      return result == true;
    }

    return false;
  }

  /// 获取本地临时文件
  static Future<File> _getLocalFile(String fileName) async {
    final dir = await getTemporaryDirectory();
    return File('${dir.path}/$fileName');
  }

  /// 下载文件内部实现
  static Future<bool> _downloadFile(
    String url,
    String fileName, {
    Function(double)? onProgress,
    http.Client? client,
  }) async {
    final bool shouldCloseClient = client == null;
    final http.Client finalClient = client ?? http.Client();
    IOSink? sink;
    Object? streamError;

    try {
      final request = http.Request('GET', Uri.parse(url));
      final response = await finalClient
          .send(request)
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final totalBytes = response.contentLength ?? 0;
        int receivedBytes = 0;

        final file = await _getLocalFile(fileName);
        sink = file.openWrite();

        await response.stream
            .listen(
              (List<int> chunk) {
                receivedBytes += chunk.length;
                sink!.add(chunk);
                if (totalBytes > 0 && onProgress != null) {
                  onProgress(receivedBytes / totalBytes);
                }
              },
              onDone: () async {
                await sink?.close();
              },
              onError: (e) {
                // 断流必须算失败，否则坏代理会中断回退链并被当成下载成功
                streamError = e;
                appDebugLog('下载流错误: $e');
              },
              cancelOnError: true,
            )
            .asFuture();

        return streamError == null;
      } else {
        appDebugLog('下载失败: HTTP ${response.statusCode}');
        return false;
      }
    } catch (e) {
      appDebugLog('下载异常: $url, $e');
      return false;
    } finally {
      // 确保关闭文件流
      try {
        await sink?.close();
      } catch (e) {
        appDebugLog('关闭文件流异常: $e');
      }
      // 如果是自己创建的 client，需要关闭
      if (shouldCloseClient) {
        finalClient.close();
      }
    }
  }
}
