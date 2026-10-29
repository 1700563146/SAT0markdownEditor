// ============================================================================
// 云同步服务
//
// 协调本地工作区与 WebDAV 远程服务器的同步：
// - 全量同步
// - 单文件同步
// - 冲突解决（T-14: 基于 T-02 台账 base 哈希的三方合并，
//   冲突块交互式选择；无法合并时跳过，不再二选一覆盖）
// ============================================================================

import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'sync_service_interface.dart';
import 'sync_ledger.dart';
import 'sync_base_store.dart';
import 'my_files_service.dart';
import 'version_service.dart';
import '../utils/debug_log.dart';
import '../utils/three_way_merge.dart';

/// 同步状态枚举
enum SyncStatus {
  idle, // 空闲
  syncing, // 同步中
  success, // 成功
  error, // 错误
}

/// 同步结果
class SyncResult {
  final bool success;
  final int uploadedCount;
  final int downloadedCount;
  final int deletedCount;
  final String? errorMessage;

  /// 同步失败的文件相对路径列表（下次同步会自动续传）
  final List<String> failedPaths;

  const SyncResult({
    required this.success,
    this.uploadedCount = 0,
    this.downloadedCount = 0,
    this.deletedCount = 0,
    this.errorMessage,
    this.failedPaths = const [],
  });

  /// 失败文件数
  int get failedCount => failedPaths.length;

  factory SyncResult.failed(String message) {
    return SyncResult(success: false, errorMessage: message);
  }

  factory SyncResult.empty() {
    return const SyncResult(success: true);
  }
}

/// 同步冲突类型
enum ConflictResolution {
  keepLocal, // 保留本地版本
  keepRemote, // 保留远程版本
  skip, // 跳过此文件
  merge, // T-14: 三方合并（逐冲突块交互式选择）
}

/// 同步冲突信息
class SyncConflict {
  final String relativePath;
  final String localPath;
  final DateTime localModified;
  final DateTime remoteModified;
  ConflictResolution resolution;

  /// T-14: 是否可进行三方合并（文本、大小受限、base 存在、远程内容可获取）
  bool canMerge;

  /// T-14: 冲突块数量（仅 [canMerge] 时有效）
  int conflictBlockCount;

  /// T-14: 冲突块内容（供 UI 逐块展示与决策）
  List<MergeConflictBlock> mergeBlocks;

  /// T-14: 用户对冲突块的选择（顺序与 [mergeBlocks] 一致）
  List<MergeBlockChoice> mergeDecisions;

  SyncConflict({
    required this.relativePath,
    required this.localPath,
    required this.localModified,
    required this.remoteModified,
    this.resolution = ConflictResolution.skip,
    this.canMerge = false,
    this.conflictBlockCount = 0,
    this.mergeBlocks = const [],
    this.mergeDecisions = const [],
  });

  /// 本地是否更新
  bool get isLocalNewer => localModified.isAfter(remoteModified);

  /// 时间差（绝对值，秒）
  int get timeDifferenceSeconds =>
      (localModified.difference(remoteModified).inSeconds).abs();
}

/// 预览结果（同步前的检测结果）
class SyncPreview {
  final List<String> toUpload; // 需要上传的文件（本地新增）
  final List<String> toDownload; // 需要下载的文件（远程新增）
  final List<SyncConflict> conflicts; // 存在冲突的文件

  const SyncPreview({
    this.toUpload = const [],
    this.toDownload = const [],
    this.conflicts = const [],
  });

  bool get hasConflicts => conflicts.isNotEmpty;
  bool get isEmpty =>
      toUpload.isEmpty && toDownload.isEmpty && conflicts.isEmpty;
}

/// 同步进度信息
class SyncProgress {
  final int totalFiles;
  final int processedFiles;
  final String currentFile;
  final String operation; // 'upload' or 'download'

  const SyncProgress({
    required this.totalFiles,
    required this.processedFiles,
    required this.currentFile,
    required this.operation,
  });

  double get percentage =>
      totalFiles > 0 ? (processedFiles / totalFiles) * 100 : 0;
}

/// 云同步服务类
class CloudSyncService {
  /// 传输并发数
  static const int _maxConcurrency = 4;

  final SyncServiceInterface _syncService;
  final MyFilesService _myFilesService;

  SyncStatus _status = SyncStatus.idle;
  SyncStatus get status => _status;

  /// 同步状态变化回调
  ValueNotifier<SyncStatus> statusNotifier = ValueNotifier(SyncStatus.idle);

  /// 同步进度变化回调
  ValueNotifier<SyncProgress?> progressNotifier = ValueNotifier(null);

  CloudSyncService({
    required SyncServiceInterface syncService,
    required MyFilesService myFilesService,
  }) : _syncService = syncService,
       _myFilesService = myFilesService;

  /// 释放资源
  void dispose() {
    statusNotifier.dispose();
    progressNotifier.dispose();
  }

  /// 执行全量同步
  ///
  /// [resolvedConflicts] 用户已解决的冲突列表（可选）
  /// 如果没有提供，发现冲突时将跳过冲突文件
  Future<SyncResult> syncAll({List<SyncConflict>? resolvedConflicts}) async {
    if (_status == SyncStatus.syncing) {
      return SyncResult.failed('同步进行中，请稍候');
    }

    _setStatus(SyncStatus.syncing);
    progressNotifier.value = null; // 重置进度

    try {
      // 测试连接
      if (!await _syncService.testConnection()) {
        _setStatus(SyncStatus.error);
        progressNotifier.value = null;
        return SyncResult.failed('无法连接到远程服务器');
      }

      // 确保远程工作区存在
      await _syncService.ensureRemoteWorkspace();

      int uploaded = 0;
      int downloaded = 0;
      int skipped = 0;
      final failedPaths = <String>[];

      // 加载同步台账（三方比较的基础）
      final workspacePath = await _myFilesService.getWorkspacePath();
      final ledger = await SyncLedger.load(workspacePath);

      // 获取本地文件列表
      final localFiles = await _collectLocalFiles();

      // 获取远程文件列表
      final remoteFiles = await _collectRemoteFiles();
      final remoteFileMap = _buildRemoteFileMap(remoteFiles);

      // 传输任务队列
      final pendingUploads = <_PendingUpload>[];
      final pendingDownloads = <_PendingDownload>[];
      final pendingMerges = <_PendingMerge>[];
      final queuedDownloadPaths = <String>{};
      void queueDownload(String relativePath, String localPath) {
        if (queuedDownloadPaths.add(relativePath)) {
          pendingDownloads.add(_PendingDownload(relativePath, localPath));
        }
      }

      // 构建已解决冲突的路径映射
      final resolvedMap = <String, ConflictResolution>{};
      final mergeDecisionsMap = <String, List<MergeBlockChoice>>{};
      if (resolvedConflicts != null) {
        for (final conflict in resolvedConflicts) {
          resolvedMap[conflict.relativePath] = conflict.resolution;
          if (conflict.resolution == ConflictResolution.merge) {
            mergeDecisionsMap[conflict.relativePath] = conflict.mergeDecisions;
          }
        }
      }

      // 阶段一：本地文件三方比较，生成上传/下载任务（此阶段不做网络传输）
      for (final localFile in localFiles) {
        final relativePath = await _getRelativePath(localFile.path);
        final remoteFile = remoteFileMap[relativePath];

        final localHash = await _hashFile(localFile);
        if (localHash == null) {
          appDebugLog('CloudSync: 哈希计算失败，跳过 $relativePath');
          failedPaths.add(relativePath);
          continue;
        }
        final localMtime = await localFile.lastModified();

        if (remoteFile == null) {
          // 远程不存在，上传（本地新增）
          pendingUploads.add(
            _PendingUpload(localFile.path, relativePath, localHash, localMtime),
          );
          continue;
        }

        final remoteMtime =
            remoteFile.modifiedTime ?? DateTime.fromMillisecondsSinceEpoch(0);

        // 用户已决定冲突处理
        final resolution = resolvedMap[relativePath];
        if (resolution != null) {
          switch (resolution) {
            case ConflictResolution.keepLocal:
              pendingUploads.add(
                _PendingUpload(
                  localFile.path,
                  relativePath,
                  localHash,
                  localMtime,
                ),
              );
              break;
            case ConflictResolution.keepRemote:
              queueDownload(relativePath, localFile.path);
              break;
            case ConflictResolution.skip:
              skipped++;
              break;
            case ConflictResolution.merge:
              // T-14: 三方合并（用户已交互选择冲突块）
              pendingMerges.add(
                _PendingMerge(
                  localFile.path,
                  relativePath,
                  mergeDecisionsMap[relativePath] ?? const [],
                ),
              );
              break;
          }
          continue;
        }

        final entry = ledger.get(relativePath);
        if (entry != null) {
          // 台账三方比较：哈希判断本地变更，容差 mtime 判断远程变更
          final localChanged = entry.contentHash != localHash;
          final remoteChanged = ledger.isRemoteChanged(
            relativePath,
            remoteMtime,
          );

          if (!localChanged && !remoteChanged) {
            skipped++;
          } else if (localChanged && !remoteChanged) {
            pendingUploads.add(
              _PendingUpload(
                localFile.path,
                relativePath,
                localHash,
                localMtime,
              ),
            );
          } else if (!localChanged && remoteChanged) {
            queueDownload(relativePath, localFile.path);
          } else {
            // 双方都变更（T-14）：进入三方合并队列；无法合并时跳过，
            // 不再按"最新保存优先"二选一覆盖
            pendingMerges.add(
              _PendingMerge(
                localFile.path,
                relativePath,
                mergeDecisionsMap[relativePath] ?? const [],
              ),
            );
          }
          continue;
        }

        // 无台账记录（首次同步该文件）：回退 mtime 策略并初始化台账
        final timeDiff = localMtime.difference(remoteMtime).inSeconds.abs();
        if (timeDiff <= 5) {
          ledger.set(
            relativePath,
            SyncLedgerEntry(
              contentHash: localHash,
              lastSyncedLocalMtime: localMtime.millisecondsSinceEpoch,
              lastSyncedRemoteMtime: remoteMtime.millisecondsSinceEpoch,
            ),
          );
          skipped++;
        } else if (localMtime.isAfter(remoteMtime)) {
          pendingUploads.add(
            _PendingUpload(localFile.path, relativePath, localHash, localMtime),
          );
        } else {
          queueDownload(relativePath, localFile.path);
        }
      }

      // 阶段一补充：远程独有文件（本地不存在），加入下载队列
      for (final remoteFile in remoteFiles) {
        if (remoteFile.isDirectory) continue;

        final relativePath = _getRemoteRelativePath(remoteFile.path);

        // 安全检查：验证路径，防止路径遍历攻击
        final localPath = await _buildSafeLocalPath(relativePath, workspacePath);
        if (localPath == null) {
          appDebugLog('[Security] Skipping malicious path: $relativePath');
          continue;
        }

        if (!await File(localPath).exists()) {
          queueDownload(relativePath, localPath);
        }
      }

      // 阶段一.5：处理三方合并（T-14）
      // 合并需要读取远程内容，串行执行（冲突文件通常很少）
      if (pendingMerges.isNotEmpty) {
        for (final task in pendingMerges) {
          final merged = await _tryMergeFile(task);
          if (merged == null) {
            // 无法合并（二进制/超大/base 缺失/远程不可读/未完整决策）：
            // 跳过，不二选一覆盖
            skipped++;
            continue;
          }
          // 合并成功：写回本地并排队上传合并结果
          pendingUploads.add(
            _PendingUpload(
              task.localPath,
              task.relativePath,
              merged.contentHash,
              merged.localMtime,
            ),
          );
        }
      }

      // 进度显示（仅统计实际传输的文件）
      var processedFiles = 0;
      final totalFiles = pendingUploads.length + pendingDownloads.length;
      void reportProgress(String relativePath, String operation) {
        processedFiles++;
        progressNotifier.value = SyncProgress(
          totalFiles: totalFiles,
          processedFiles: processedFiles,
          currentFile: relativePath,
          operation: operation,
        );
      }

      // 阶段二：并发上传（带指数退避重试；失败不写台账，下次自动续传）
      final uploadedNow = <_PendingUpload>[];
      await _forEachConcurrent<_PendingUpload>(
        pendingUploads,
        _maxConcurrency,
        (task) async {
          reportProgress(task.relativePath, 'upload');
          final ok = await _retry(
            () => _syncService.uploadFile(task.localPath, task.relativePath),
            '上传 $task.relativePath',
          );
          if (ok) {
            uploaded++;
            uploadedNow.add(task);
          } else {
            failedPaths.add(task.relativePath);
          }
        },
      );

      // 上传完成后刷新一次远程列表，将新的远程 mtime 写入台账
      Map<String, RemoteFileInfo>? freshRemoteMap;
      if (uploadedNow.isNotEmpty) {
        try {
          freshRemoteMap = _buildRemoteFileMap(await _collectRemoteFiles());
        } catch (e) {
          appDebugLog('CloudSync: 上传后刷新远程列表失败: $e');
        }
      }
      for (final task in uploadedNow) {
        final remoteMtime = freshRemoteMap?[task.relativePath]?.modifiedTime;
        ledger.set(
          task.relativePath,
          SyncLedgerEntry(
            contentHash: task.contentHash,
            lastSyncedLocalMtime: task.localMtime.millisecondsSinceEpoch,
            lastSyncedRemoteMtime: remoteMtime?.millisecondsSinceEpoch,
          ),
        );
        // T-14: 同步完成后保存 base 内容（供下次三方合并使用）
        await _saveBaseFromFile(task.relativePath, task.localPath);
      }

      // 阶段三：并发下载
      await _forEachConcurrent<_PendingDownload>(
        pendingDownloads,
        _maxConcurrency,
        (task) async {
          reportProgress(task.relativePath, 'download');
          final ok = await _retry(
            () => _syncService.downloadFile(task.relativePath, task.localPath),
            '下载 $task.relativePath',
          );
          if (!ok) {
            failedPaths.add(task.relativePath);
            return;
          }
          downloaded++;

          // 下载成功后记录台账（内容哈希 + 本地 mtime + 远程 mtime）
          final file = File(task.localPath);
          final hash = await _hashFile(file);
          if (hash == null) {
            // 哈希失败不记录，下次同步回退 mtime 策略
            ledger.remove(task.relativePath);
            return;
          }
          final remoteFile = remoteFileMap[task.relativePath];
          ledger.set(
            task.relativePath,
            SyncLedgerEntry(
              contentHash: hash,
              lastSyncedLocalMtime:
                  (await file.lastModified()).millisecondsSinceEpoch,
              lastSyncedRemoteMtime:
                  remoteFile?.modifiedTime?.millisecondsSinceEpoch,
            ),
          );
          // T-14: 下载完成即视为新的 base
          await _saveBaseFromFile(task.relativePath, task.localPath);
        },
      );

      // 阶段四：持久化台账
      await ledger.save();

      _setStatus(SyncStatus.success);
      progressNotifier.value = null; // 清除进度
      return SyncResult(
        success: true,
        uploadedCount: uploaded,
        downloadedCount: downloaded,
        deletedCount: skipped,
        failedPaths: List.unmodifiable(failedPaths),
      );
    } catch (e) {
      appDebugLog('CloudSync 同步失败: $e');
      _setStatus(SyncStatus.error);
      progressNotifier.value = null; // 清除进度
      return SyncResult.failed('同步失败: $e');
    }
  }

  /// 预览同步（检测冲突）
  ///
  /// 返回需要上传、下载的文件列表，以及存在冲突的文件列表
  /// 用于在同步前显示确认对话框
  Future<SyncPreview?> previewSync() async {
    try {
      // 测试连接
      if (!await _syncService.testConnection()) {
        return null;
      }

      final toUpload = <String>[];
      final toDownload = <String>[];
      final conflicts = <SyncConflict>[];

      final workspacePath = await _myFilesService.getWorkspacePath();
      final ledger = await SyncLedger.load(workspacePath);

      // 获取本地文件列表
      final localFiles = await _collectLocalFiles();

      // 获取远程文件列表
      final remoteFiles = await _collectRemoteFiles();
      final remoteFileMap = _buildRemoteFileMap(remoteFiles);

      // 分类本地文件
      for (final localFile in localFiles) {
        final relativePath = await _getRelativePath(localFile.path);
        final remoteFile = remoteFileMap[relativePath];

        if (remoteFile == null) {
          // 远程不存在，需要上传
          toUpload.add(relativePath);
          continue;
        }

        final localMtime = await localFile.lastModified();
        final remoteMtime =
            remoteFile.modifiedTime ?? DateTime.fromMillisecondsSinceEpoch(0);

        final entry = ledger.get(relativePath);
        if (entry == null) {
          // 无台账记录：沿用 mtime 判断（时间差超过5秒视为冲突）
          final timeDiff = localMtime.difference(remoteMtime).inSeconds.abs();
          if (timeDiff > 5) {
            conflicts.add(
              SyncConflict(
                relativePath: relativePath,
                localPath: localFile.path,
                localModified: localMtime,
                remoteModified: remoteMtime,
              ),
            );
          }
          continue;
        }

        // 台账三方比较：未变更的文件不再因 mtime 漂移被误报为冲突
        final localChanged = entry.contentHash != await _hashFile(localFile);
        final remoteChanged = ledger.isRemoteChanged(relativePath, remoteMtime);

        if (localChanged && remoteChanged) {
          // 双方都变更：交给用户决策（T-14: 可尝试三方合并）
          final conflict = SyncConflict(
            relativePath: relativePath,
            localPath: localFile.path,
            localModified: localMtime,
            remoteModified: remoteMtime,
          );
          await _analyzeMergeForConflict(conflict);
          conflicts.add(conflict);
        } else if (localChanged) {
          toUpload.add(relativePath);
        } else if (remoteChanged) {
          // 仅远程变更：以冲突形式呈现，由用户选择"保留远程"
          conflicts.add(
            SyncConflict(
              relativePath: relativePath,
              localPath: localFile.path,
              localModified: localMtime,
              remoteModified: remoteMtime,
            ),
          );
        }
        // 两侧均未变更：跳过
      }

      // 检查远程独有文件
      for (final remoteFile in remoteFiles) {
        if (remoteFile.isDirectory) continue;

        final relativePath = _getRemoteRelativePath(remoteFile.path);

        // 安全检查：验证路径，防止路径遍历攻击
        final localPath = await _buildSafeLocalPath(
          relativePath,
          workspacePath,
        );
        if (localPath == null) {
          // 路径不安全，跳过此文件
          appDebugLog(
            '[Security] Skipping malicious path in preview: $relativePath',
          );
          continue;
        }

        if (!await File(localPath).exists()) {
          // 本地不存在，需要下载
          toDownload.add(relativePath);
        }
      }

      return SyncPreview(
        toUpload: toUpload,
        toDownload: toDownload,
        conflicts: conflicts,
      );
    } catch (e) {
      appDebugLog('CloudSync 预览失败: $e');
      return null;
    }
  }

  /// 同步单个文件
  ///
  /// [localPath] 本地文件路径
  /// 上传成功后更新台账（含上传后的远程 mtime），避免下次全量同步重复传输
  Future<bool> syncFile(String localPath) async {
    try {
      final relativePath = await _getRelativePath(localPath);
      final ok = await _retry(
        () => _syncService.uploadFile(localPath, relativePath),
        '上传 $relativePath',
      );
      if (!ok) return false;

      try {
        final file = File(localPath);
        final hash = await _hashFile(file);
        if (hash == null) return true;

        final workspacePath = await _myFilesService.getWorkspacePath();
        final ledger = await SyncLedger.load(workspacePath);

        // 列出父目录获取上传后的远程 mtime
        int? remoteMtime;
        final slash = relativePath.lastIndexOf('/');
        final parentDir = slash == -1 ? '' : relativePath.substring(0, slash);
        final name = slash == -1 ? relativePath : relativePath.substring(slash + 1);
        final listing = await _syncService.listRemoteFiles(remotePath: parentDir);
        for (final info in listing ?? const <RemoteFileInfo>[]) {
          if (!info.isDirectory && info.name == name) {
            remoteMtime = info.modifiedTime?.millisecondsSinceEpoch;
            break;
          }
        }

        ledger.set(
          relativePath,
          SyncLedgerEntry(
            contentHash: hash,
            lastSyncedLocalMtime: (await file.lastModified()).millisecondsSinceEpoch,
            lastSyncedRemoteMtime: remoteMtime,
          ),
        );
        await ledger.save();
        // T-14: 单文件上传成功后保存 base
        await _saveBaseFromFile(relativePath, localPath);
      } catch (e) {
        // 台账更新失败只影响下次同步的判断精度，不影响本次上传结果
        appDebugLog('CloudSync: 单文件同步台账更新失败: $e');
      }
      return true;
    } catch (e) {
      appDebugLog('CloudSync 单文件同步失败: $e');
      return false;
    }
  }

  // ==================== 私有方法 ====================

  void _setStatus(SyncStatus status) {
    _status = status;
    statusNotifier.value = status;
  }

  /// 收集本地所有文件
  Future<List<File>> _collectLocalFiles() async {
    final workspacePath = await _myFilesService.getWorkspacePath();
    final files = <File>[];

    await _collectFilesRecursive(Directory(workspacePath), files);
    return files;
  }

  Future<void> _collectFilesRecursive(Directory dir, List<File> files) async {
    if (!await dir.exists()) return;

    await for (final entity in dir.list()) {
      if (entity is File) {
        files.add(entity);
      } else if (entity is Directory) {
        // 跳过版本快照目录，版本历史不参与云同步
        final name = entity.path.split(RegExp(r'[/\\]')).last;
        if (name == VersionService.versionsDirName) continue;
        await _collectFilesRecursive(entity, files);
      }
    }
  }

  /// 收集远程所有文件（递归）
  Future<List<RemoteFileInfo>> _collectRemoteFiles() async {
    final files = <RemoteFileInfo>[];
    await _collectRemoteFilesRecursive('', files);
    return files;
  }

  Future<void> _collectRemoteFilesRecursive(
    String path,
    List<RemoteFileInfo> files,
  ) async {
    final remoteFiles = await _syncService.listRemoteFiles(remotePath: path);
    if (remoteFiles == null) return;

    for (final file in remoteFiles) {
      if (file.isDirectory) {
        // 跳过远程版本快照目录，避免把历史遗留数据重新下载回工作区
        if (file.name == VersionService.versionsDirName) continue;
        final subPath = path.isEmpty ? file.name : '$path/${file.name}';
        await _collectRemoteFilesRecursive(subPath, files);
      } else {
        files.add(file);
      }
    }
  }

  /// 获取相对于工作区的路径
  Future<String> _getRelativePath(String absolutePath) async {
    final workspacePath = await _myFilesService.getWorkspacePath();
    if (absolutePath.startsWith(workspacePath)) {
      return absolutePath
          .substring(workspacePath.length + 1)
          .replaceAll(Platform.pathSeparator, '/');
    }
    return absolutePath.split(Platform.pathSeparator).last;
  }

  /// 获取远程文件相对路径
  String _getRemoteRelativePath(String remotePath) {
    final fullRemotePath = _syncService.getFullRemotePath();
    final prefix = '$fullRemotePath/';
    if (remotePath.startsWith(prefix)) {
      return remotePath.substring(prefix.length);
    }
    return remotePath;
  }

  /// 安全地构建本地文件路径，防止路径遍历攻击
  ///
  /// 验证远程路径不会导致文件写入到工作区之外
  /// 返回 null 表示路径不安全
  Future<String?> _buildSafeLocalPath(
    String relativePath,
    String workspacePath,
  ) async {
    try {
      // 1. 规范化相对路径（移除 ./ 和 ../ 等）
      final normalizedRelative = path.normalize(relativePath);

      // 2. 检查是否包含路径遍历尝试
      if (normalizedRelative.startsWith('..') ||
          normalizedRelative.contains('/..') ||
          normalizedRelative.contains('\\..')) {
        appDebugLog('[Security] Path traversal detected in: $relativePath');
        return null;
      }

      // 3. 构建完整的本地路径
      final localPath = path.join(
        workspacePath,
        normalizedRelative.replaceAll('/', Platform.pathSeparator),
      );

      // 4. 规范化本地路径
      final normalizedLocalPath = File(localPath).absolute.path;

      // 5. 确保规范化后的路径仍在工作区内
      if (!normalizedLocalPath.startsWith(workspacePath)) {
        appDebugLog(
          '[Security] Path escapes workspace: $relativePath -> $normalizedLocalPath',
        );
        return null;
      }

      return normalizedLocalPath;
    } catch (e) {
      appDebugLog('[Security] Path validation error: $e');
      return null;
    }
  }

  /// 构建远程文件 Map 索引，O(1) 查找替代 O(n) 线性搜索
  Map<String, RemoteFileInfo> _buildRemoteFileMap(
    List<RemoteFileInfo> remoteFiles,
  ) {
    final map = <String, RemoteFileInfo>{};
    for (final file in remoteFiles) {
      final remoteRelative = _getRemoteRelativePath(file.path);
      map[remoteRelative] = file;
    }
    return map;
  }

  /// 计算文件内容 SHA-256（基于原始字节，兼容二进制文件），失败返回 null
  Future<String?> _hashFile(File file) async {
    try {
      final bytes = await file.readAsBytes();
      return sha256.convert(bytes).toString();
    } catch (e) {
      appDebugLog('CloudSync: 哈希计算失败 ${file.path}: $e');
      return null;
    }
  }

  /// T-14: 分析冲突文件是否可进行三方合并，并填充冲突块展示信息
  Future<void> _analyzeMergeForConflict(SyncConflict conflict) async {
    try {
      final localFile = File(conflict.localPath);
      if (!await localFile.exists()) return;
      final localBytes = await localFile.readAsBytes();
      if (localBytes.length > SyncBaseStore.maxMergeFileBytes) return;
      final localText = utf8.decode(localBytes, allowMalformed: false);
      final baseText = await SyncBaseStore.loadBase(conflict.relativePath);
      if (baseText == null) return;

      final tempFile = await _newMergeTempFile('ushio_preview_', conflict.relativePath);
      try {
        final ok = await _retry(
          () => _syncService.downloadFile(
            conflict.relativePath,
            tempFile.path,
          ),
          '合并预览下载 ${conflict.relativePath}',
        );
        if (!ok) return;
        final remoteBytes = await tempFile.readAsBytes();
        if (remoteBytes.length > SyncBaseStore.maxMergeFileBytes) return;
        final remoteText = utf8.decode(remoteBytes, allowMalformed: false);

        final analysis = performThreeWayMerge(baseText, localText, remoteText);
        if (analysis == null) return;

        conflict.canMerge = true;
        conflict.conflictBlockCount = analysis.conflicts.length;
        conflict.mergeBlocks = List.unmodifiable(analysis.conflicts);
        conflict.mergeDecisions = List<MergeBlockChoice>.filled(
          analysis.conflicts.length,
          MergeBlockChoice.keepLocal,
        );
      } finally {
        await _deleteQuietly(tempFile);
      }
    } catch (e) {
      appDebugLog('CloudSync: 合并预览分析失败 ${conflict.relativePath}: $e');
    }
  }

  /// T-14: 执行三方合并并写回本地；无法合并时返回 null
  Future<_MergedFile?> _tryMergeFile(_PendingMerge task) async {
    final localFile = File(task.localPath);
    if (!await localFile.exists()) return null;
    final localBytes = await localFile.readAsBytes();
    if (localBytes.length > SyncBaseStore.maxMergeFileBytes) return null;
    String localText;
    try {
      localText = utf8.decode(localBytes, allowMalformed: false);
    } catch (_) {
      return null; // 非 UTF-8 文本不做合并
    }
    final baseText = await SyncBaseStore.loadBase(task.relativePath);
    if (baseText == null) return null;

    final tempFile = await _newMergeTempFile('ushio_merge_', task.relativePath);
    try {
      final ok = await _retry(
        () => _syncService.downloadFile(task.relativePath, tempFile.path),
        '合并下载 ${task.relativePath}',
      );
      if (!ok) return null;
      final remoteBytes = await tempFile.readAsBytes();
      if (remoteBytes.length > SyncBaseStore.maxMergeFileBytes) return null;
      final remoteText = utf8.decode(remoteBytes, allowMalformed: false);

      final analysis = performThreeWayMerge(baseText, localText, remoteText);
      if (analysis == null) return null;

      String mergedText;
      if (analysis.hasConflicts) {
        if (task.mergeDecisions.length != analysis.conflicts.length) {
          // 冲突块决策未完整：跳过，避免二选一覆盖
          return null;
        }
        mergedText = renderMergedText(analysis, task.mergeDecisions);
      } else {
        // 无冲突：自动合并
        mergedText = analysis.autoMergedText;
      }

      await localFile.writeAsString(mergedText, flush: true);
      final hash = await _hashFile(localFile);
      if (hash == null) return null;
      return _MergedFile(hash, await localFile.lastModified());
    } finally {
      await _deleteQuietly(tempFile);
    }
  }

  /// T-14: 从文件读取文本并保存为同步 base（非文本/超限自动跳过）
  Future<void> _saveBaseFromFile(String relativePath, String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return;
      final bytes = await file.readAsBytes();
      if (bytes.length > SyncBaseStore.maxMergeFileBytes) return;
      final text = utf8.decode(bytes, allowMalformed: false);
      await SyncBaseStore.saveBase(relativePath, text);
    } catch (e) {
      appDebugLog('CloudSync: 保存 base 失败 $relativePath: $e');
    }
  }

  /// 生成合并用临时文件（位于系统临时目录，避免污染工作区）
  Future<File> _newMergeTempFile(String prefix, String relativePath) async {
    final tempDir = await getTemporaryDirectory();
    final key = sha256.convert(utf8.encode(relativePath)).toString();
    return File(
      '${tempDir.path}${Platform.pathSeparator}$prefix$key.tmp',
    );
  }

  /// 静默删除临时文件
  Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  /// 带指数退避的重试（最多尝试 [maxAttempts] 次）
  Future<bool> _retry(
    Future<bool> Function() action,
    String label, {
    int maxAttempts = 3,
  }) async {
    Object? lastError;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        if (await action()) return true;
        lastError = '操作返回 false';
      } catch (e) {
        lastError = e;
      }
      if (attempt < maxAttempts) {
        await Future<void>.delayed(
          Duration(milliseconds: 300 << (attempt - 1)),
        );
      }
    }
    appDebugLog('CloudSync: $label 重试 $maxAttempts 次仍失败: $lastError');
    return false;
  }

  /// 并发执行任务，最多 [concurrency] 个同时进行
  Future<void> _forEachConcurrent<T>(
    List<T> items,
    int concurrency,
    Future<void> Function(T) task,
  ) async {
    if (items.isEmpty) return;
    var index = 0;
    Future<void> worker() async {
      while (index < items.length) {
        final item = items[index++];
        try {
          await task(item);
        } catch (e) {
          appDebugLog('CloudSync: 并发任务异常: $e');
        }
      }
    }

    final workers = <Future<void>>[];
    for (var i = 0; i < concurrency && i < items.length; i++) {
      workers.add(worker());
    }
    await Future.wait(workers);
  }
}

/// 待上传任务
class _PendingUpload {
  final String localPath;
  final String relativePath;
  final String contentHash;
  final DateTime localMtime;

  const _PendingUpload(
    this.localPath,
    this.relativePath,
    this.contentHash,
    this.localMtime,
  );
}

/// 待下载任务
class _PendingDownload {
  final String relativePath;
  final String localPath;

  const _PendingDownload(this.relativePath, this.localPath);
}

/// 待三方合并任务（T-14）
class _PendingMerge {
  final String localPath;
  final String relativePath;
  final List<MergeBlockChoice> mergeDecisions;

  const _PendingMerge(
    this.localPath,
    this.relativePath,
    this.mergeDecisions,
  );
}

/// 合并结果（写回本地后的哈希与 mtime）
class _MergedFile {
  final String contentHash;
  final DateTime localMtime;

  const _MergedFile(this.contentHash, this.localMtime);
}
