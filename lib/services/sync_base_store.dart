// ============================================================================
// 同步基线内容存储（Sync base store）
//
// T-14: 三路合并需要"最近一次同步的内容"作为 base。
// 台账（sync_ledger）仅记录 base 内容的 SHA-256 哈希，不保存内容本身；
// 本模块在应用私有目录保存同步完成时的文本内容副本，按相对路径哈希命名，
// 供三方合并时读取 base。
//
// 存储位置：<应用支持目录>/sync_bases/<sha256(relativePath)>.txt
// 仅保存文本且大小受限的文件（超大或二进制文件不参与合并，冲突降级为二选一）。
// ============================================================================
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import '../utils/debug_log.dart';

/// 同步基线内容存储
class SyncBaseStore {
  /// 参与三方合并的最大文本大小（UTF-8 字节）；超过则不做行级合并
  static const int maxMergeFileBytes = 512 * 1024;

  /// 参与三方合并的最大行数（与 line_diff_calculator 的行级对齐阈值一致）
  static const int maxMergeLines = 5000;

  static Directory? _cachedDir;

  /// 获取基线存储目录（应用私有目录，不随工作区同步）
  static Future<Directory> getBaseDirectory() async {
    if (_cachedDir != null) return _cachedDir!;
    final support = await getApplicationSupportDirectory();
    final dir = Directory(
      '${support.path}${Platform.pathSeparator}sync_bases',
    );
    await dir.create(recursive: true);
    _cachedDir = dir;
    return dir;
  }

  /// 由相对路径生成稳定的存储文件名
  static String _keyFor(String relativePath) {
    return sha256.convert(utf8.encode(relativePath)).toString();
  }

  /// 保存同步完成时的 base 内容（文本）
  static Future<void> saveBase(String relativePath, String content) async {
    try {
      if (utf8.encode(content).length > maxMergeFileBytes) return;
      if (content.split('\n').length > maxMergeLines) return;
      final dir = await getBaseDirectory();
      final file = File(
        '${dir.path}${Platform.pathSeparator}${_keyFor(relativePath)}.txt',
      );
      await file.writeAsString(content, flush: true);
    } catch (e) {
      appDebugLog('SyncBaseStore: 保存 base 失败 $relativePath: $e');
    }
  }

  /// 读取 base 内容；不存在或读取失败时返回 null
  static Future<String?> loadBase(String relativePath) async {
    try {
      final dir = await getBaseDirectory();
      final file = File(
        '${dir.path}${Platform.pathSeparator}${_keyFor(relativePath)}.txt',
      );
      if (!await file.exists()) return null;
      return await file.readAsString();
    } catch (e) {
      appDebugLog('SyncBaseStore: 读取 base 失败 $relativePath: $e');
      return null;
    }
  }

  /// 删除 base 内容
  static Future<void> removeBase(String relativePath) async {
    try {
      final dir = await getBaseDirectory();
      final file = File(
        '${dir.path}${Platform.pathSeparator}${_keyFor(relativePath)}.txt',
      );
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      appDebugLog('SyncBaseStore: 删除 base 失败 $relativePath: $e');
    }
  }

  /// base 是否存在
  static Future<bool> hasBase(String relativePath) async {
    try {
      final dir = await getBaseDirectory();
      final file = File(
        '${dir.path}${Platform.pathSeparator}${_keyFor(relativePath)}.txt',
      );
      return await file.exists();
    } catch (e) {
      return false;
    }
  }
}
