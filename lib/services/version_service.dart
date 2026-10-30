// ============================================================================
// 版本存储服务
//
// 管理文档的版本历史，包括：
// - 创建版本快照（.versions/{文件名}/v{n}.md）
// - 版本元数据管理（.versions/{文件名}/metadata.json）
// - 版本内容读取与恢复
// - 版本备注更新
//
// 目录结构：
//   .versions/
//     {文件名不含扩展名}/
//       v1.md
//       v2.md
//       metadata.json
//
// 使用原子写入模式（先写临时文件，再重命名）。
// ============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../models/document_version.dart';
import '../utils/debug_log.dart';

/// 版本存储服务
///
/// 管理文档版本的创建、读取、删除、恢复等操作。
/// 每个文件的版本存储在独立的子目录中。
class VersionService {
  /// 版本存储根目录名（公开常量，供文件扫描、云同步等处统一排除）
  static const String versionsDirName = '.versions';

  /// 元数据文件名
  static const String _metadataFileName = 'metadata.json';

  /// 单文件默认保留的最新快照数量（T-13 起可由设置覆盖）
  static const int defaultMaxVersionsPerFile = 20;

  /// 单文件快照数量硬上限（含每日锚点），防止历史无限增长
  static const int maxVersionsHardCap = 60;

  /// 按文件路径的写入锁，确保同一文件的版本操作串行执行
  final Map<String, Future<void>> _writeLocks = {};

  /// 串行执行 [action]，保证同一 [key] 的操作按调用顺序完成
  Future<T> _synchronized<T>(String key, Future<T> Function() action) async {
    final previous = _writeLocks[key] ?? Future<void>.value();
    final completer = Completer<void>();
    _writeLocks[key] = completer.future;
    try {
      await previous;
      return await action();
    } finally {
      completer.complete();
      // 若没有新的排队者，清理锁记录避免 Map 无限增长
      if (identical(_writeLocks[key], completer.future)) {
        _writeLocks.remove(key);
      }
    }
  }

  // ==================== 路径计算 ====================

  /// 获取文件对应的版本存储目录
  ///
  /// [filePath] 原始文件的绝对路径
  ///
  /// 返回 `.versions/{文件名不含扩展名}/` 的绝对路径
  String getVersionsDir(String filePath) {
    final file = File(filePath);
    final parentDir = file.parent.path;
    final baseName = _getBaseNameWithoutExtension(file.path);
    return '$parentDir${Platform.pathSeparator}$versionsDirName${Platform.pathSeparator}$baseName';
  }

  /// 获取版本文件路径
  ///
  /// [filePath] 原始文件的绝对路径
  /// [versionNumber] 版本号
  String getVersionFilePath(String filePath, int versionNumber) {
    final dir = getVersionsDir(filePath);
    return '$dir${Platform.pathSeparator}v$versionNumber.md';
  }

  /// 获取元数据文件路径
  ///
  /// [filePath] 原始文件的绝对路径
  String getMetadataFilePath(String filePath) {
    final dir = getVersionsDir(filePath);
    return '$dir${Platform.pathSeparator}$_metadataFileName';
  }

  /// 从文件路径提取不含扩展名的文件名
  String _getBaseNameWithoutExtension(String filePath) {
    final fileName = filePath.split(Platform.pathSeparator).last;
    final lastDot = fileName.lastIndexOf('.');
    return lastDot > 0 ? fileName.substring(0, lastDot) : fileName;
  }

  // ==================== 版本创建 ====================

  /// 创建新版本
  ///
  /// [filePath] 原始文件的绝对路径
  /// [content] 版本内容
  /// [note] 用户备注（可选）
  /// [maxVersions] 保留数量 N（T-13 设置项；缺省使用 [defaultMaxVersionsPerFile]）
  ///
  /// 返回创建的版本信息；若内容与最新快照一致则去重，直接返回最新快照。
  /// 自动创建 `.versions` 目录和文件独立子目录（如不存在）。
  /// 创建后按保留策略自动清理超量快照。
  Future<DocumentVersion> createVersion(
    String filePath,
    String content, {
    String note = '',
    int? maxVersions,
  }) {
    return _synchronized<DocumentVersion>(filePath, () async {
      final versionsDir = getVersionsDir(filePath);

      // 确保版本目录存在
      await Directory(versionsDir).create(recursive: true);

      // 读取现有元数据列表
      final metadataList = await _readMetadataList(filePath);

      // 内容哈希去重：与最新快照一致时跳过，避免每次保存都产生新快照。
      // 带备注的快照（如恢复前备份）承载用户意图，不去重。
      final contentHash = sha256.convert(utf8.encode(content)).toString();
      if (metadataList.isNotEmpty && note.isEmpty) {
        final latest = metadataList.reduce(
          (a, b) => a.versionNumber > b.versionNumber ? a : b,
        );
        var latestHash = latest.contentHash;
        var backfilled = false;
        if (latestHash == null) {
          // 兼容旧快照（无哈希记录）：回读内容比较，并回填哈希
          try {
            final latestContent = await getVersionContent(
              filePath,
              latest.versionNumber,
            );
            latestHash = sha256.convert(utf8.encode(latestContent)).toString();
            final index = metadataList.indexOf(latest);
            metadataList[index] = latest.copyWith(contentHash: latestHash);
            backfilled = true;
          } catch (_) {
            latestHash = null;
          }
        }
        if (latestHash != null && latestHash == contentHash) {
          // 持久化回填的哈希，避免下次保存再次回读旧快照
          if (backfilled) {
            await _writeMetadataList(filePath, metadataList);
          }
          appDebugLog('VersionService: 内容未变化，跳过快照 for $filePath');
          return latest;
        }
      }

      // 计算下一个版本号
      final nextVersionNumber = metadataList.isEmpty
          ? 1
          : metadataList
                    .map((v) => v.versionNumber)
                    .reduce((a, b) => a > b ? a : b) +
                1;

      // 写入版本文件（原子写入）
      final versionPath = getVersionFilePath(filePath, nextVersionNumber);
      await _atomicWrite(versionPath, content);

      // 构建版本记录
      final version = DocumentVersion(
        versionId: 'v_${DateTime.now().millisecondsSinceEpoch}_$nextVersionNumber',
        versionNumber: nextVersionNumber,
        timestamp: DateTime.now(),
        note: note,
        filePath: filePath,
        versionPath: versionPath,
        fileSize: utf8.encode(content).length,
        contentHash: contentHash,
      );

      // 更新元数据并按保留策略裁剪
      metadataList.add(version);
      final retained = await _pruneVersions(
        filePath,
        metadataList,
        maxVersions: maxVersions,
      );
      await _writeMetadataList(filePath, retained);

      appDebugLog('VersionService: 创建版本 v$nextVersionNumber for $filePath');
      return version;
    });
  }

  // ==================== 版本查询 ====================

  /// 获取版本历史列表
  ///
  /// [filePath] 原始文件的绝对路径
  ///
  /// 返回按版本号降序排列的版本列表（最新版本在前）。
  /// 如果 `.versions` 目录或元数据文件不存在，返回空列表。
  Future<List<DocumentVersion>> getVersionHistory(String filePath) async {
    final metadataList = await _readMetadataList(filePath);

    // 按版本号降序排列
    metadataList.sort((a, b) => b.versionNumber.compareTo(a.versionNumber));
    return metadataList;
  }

  /// 获取版本内容
  ///
  /// [filePath] 原始文件的绝对路径
  /// [versionNumber] 版本号
  ///
  /// 返回版本的 Markdown 内容。
  /// 如果版本文件不存在或损坏，抛出异常。
  Future<String> getVersionContent(String filePath, int versionNumber) async {
    final versionPath = getVersionFilePath(filePath, versionNumber);
    final file = File(versionPath);

    if (!await file.exists()) {
      throw Exception('版本文件不存在: v$versionNumber');
    }

    try {
      return await file.readAsString();
    } catch (e) {
      appDebugLog('VersionService: 读取版本文件失败: $e');
      throw Exception('版本文件损坏: v$versionNumber');
    }
  }

  // ==================== 版本删除 ====================

  /// 删除指定版本
  ///
  /// [filePath] 原始文件的绝对路径
  /// [versionNumber] 版本号
  ///
  /// 删除版本文件和对应的元数据记录。
  /// 如果版本不存在，静默处理。
  Future<void> deleteVersion(String filePath, int versionNumber) {
    return _synchronized<void>(filePath, () async {
      // 删除版本文件
      final versionPath = getVersionFilePath(filePath, versionNumber);
      final versionFile = File(versionPath);
      if (await versionFile.exists()) {
        await versionFile.delete();
      }

      // 更新元数据
      final metadataList = await _readMetadataList(filePath);
      metadataList.removeWhere((v) => v.versionNumber == versionNumber);
      await _writeMetadataList(filePath, metadataList);

      appDebugLog('VersionService: 删除版本 v$versionNumber for $filePath');
    });
  }

  // ==================== 版本备注 ====================

  /// 更新版本备注
  ///
  /// [filePath] 原始文件的绝对路径
  /// [versionNumber] 版本号
  /// [note] 新备注内容
  ///
  /// 如果版本不存在，抛出异常。
  Future<void> updateVersionNote(
    String filePath,
    int versionNumber,
    String note,
  ) {
    return _synchronized<void>(filePath, () async {
      final metadataList = await _readMetadataList(filePath);
      final index = metadataList.indexWhere(
        (v) => v.versionNumber == versionNumber,
      );

      if (index == -1) {
        throw Exception('版本不存在: v$versionNumber');
      }

      metadataList[index] = metadataList[index].copyWith(note: note);
      await _writeMetadataList(filePath, metadataList);

      appDebugLog('VersionService: 更新版本 v$versionNumber 备注');
    });
  }

  // ==================== 版本恢复 ====================

  /// 恢复到指定版本
  ///
  /// [filePath] 原始文件的绝对路径
  /// [versionNumber] 要恢复的版本号
  /// [maxVersions] T-13 保留数量设置；内部创建的备份与恢复快照同样遵守
  ///
  /// 操作步骤：
  /// 1. 读取当前文件内容，创建备份版本
  /// 2. 读取目标版本内容
  /// 3. 将目标版本内容写入原始文件
  ///
  /// 返回恢复后的新版本信息（包含备份）。
  /// 如果目标版本不存在，抛出异常。
  Future<DocumentVersion> restoreVersion(
    String filePath,
    int versionNumber, {
    int? maxVersions,
  }) async {
    // 读取目标版本内容
    final targetContent = await getVersionContent(filePath, versionNumber);

    // 读取当前文件内容并创建备份
    final currentFile = File(filePath);
    if (await currentFile.exists()) {
      final currentContent = await currentFile.readAsString();
      await createVersion(
        filePath,
        currentContent,
        note: '恢复前自动备份',
        maxVersions: maxVersions,
      );
    }

    // 将目标版本内容写入原始文件（原子写入）
    await _atomicWrite(filePath, targetContent);

    // 创建恢复版本记录
    final restoredVersion = await createVersion(
      filePath,
      targetContent,
      note: '从 v$versionNumber 恢复',
      maxVersions: maxVersions,
    );

    appDebugLog('VersionService: 恢复到版本 v$versionNumber for $filePath');
    return restoredVersion;
  }

  // ==================== 从版本创建新文件 ====================

  /// 从版本创建新文档
  ///
  /// [filePath] 原始文件的绝对路径
  /// [versionNumber] 版本号
  ///
  /// 在原始文件同目录下创建新文件，文件名带时间戳后缀。
  /// 例如：`笔记.md` → `笔记_20260513_143022.md`
  ///
  /// 返回新文件的绝对路径。
  /// 如果版本不存在，抛出异常。
  Future<String> createNewDocFromVersion(
    String filePath,
    int versionNumber,
  ) async {
    // 读取版本内容
    final content = await getVersionContent(filePath, versionNumber);

    // 构建新文件名
    final file = File(filePath);
    final parentDir = file.parent.path;
    final baseName = _getBaseNameWithoutExtension(filePath);
    final now = DateTime.now();
    final timestamp =
        '${now.year}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}';
    final newFileName = '${baseName}_$timestamp.md';
    final newFilePath = '$parentDir${Platform.pathSeparator}$newFileName';

    // 写入新文件（原子写入）
    await _atomicWrite(newFilePath, content);

    appDebugLog('VersionService: 从版本 v$versionNumber 创建新文件 $newFileName');
    return newFilePath;
  }

  // ==================== 保留策略 ====================

  /// 按保留策略裁剪版本列表，返回应保留的版本（超量快照文件会被删除）
  ///
  /// [maxVersions] T-13 设置项：单文档保留快照数 N；缺省使用
  /// [defaultMaxVersionsPerFile]。
  ///
  /// 策略：
  /// 1. 始终保留最新 N 个版本；
  /// 2. 更早的版本中，每天保留最新一个作为锚点，带用户备注的版本始终保留；
  /// 3. 总数超过 [maxVersionsHardCap] 时，从最旧的未备注版本开始删除。
  Future<List<DocumentVersion>> _pruneVersions(
    String filePath,
    List<DocumentVersion> list, {
    int? maxVersions,
  }) async {
    final maxV =
        (maxVersions ?? defaultMaxVersionsPerFile).clamp(
          1,
          maxVersionsHardCap,
        );
    if (list.length <= maxV) return list;

    final newest = list.sublist(list.length - maxV);
    final older = list.sublist(0, list.length - maxV);

    // older 按版本号升序，倒序遍历即从新到旧；首次遇到的日期即当天最新快照
    final dailyAnchors = <DocumentVersion>[];
    String? lastKeptDay;
    for (final v in older.reversed) {
      final t = v.timestamp;
      final day =
          '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
      if (v.note.isNotEmpty || day != lastKeptDay) {
        dailyAnchors.add(v);
        lastKeptDay = day;
      }
    }

    final retained = <DocumentVersion>[...dailyAnchors.reversed, ...newest];

    // 硬上限：从最旧的未备注版本开始删除，防止每日锚点无限累积
    while (retained.length > maxVersionsHardCap) {
      final index = retained.indexWhere((v) => v.note.isEmpty);
      if (index == -1) break;
      await _deleteVersionFile(retained.removeAt(index));
    }

    if (retained.length != list.length) {
      appDebugLog(
        'VersionService: 保留策略清理 ${list.length - retained.length} 个旧快照 for $filePath',
      );
    }
    return retained;
  }

  /// 删除版本文件（忽略失败，不阻塞裁剪流程）
  Future<void> _deleteVersionFile(DocumentVersion version) async {
    try {
      final file = File(version.versionPath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      appDebugLog('VersionService: 删除快照文件失败: $e');
    }
  }

  // ==================== 版本历史管理（T-13） ====================

  /// 递归扫描工作区根目录下全部 `.versions` 目录并汇总统计。
  ///
  /// [rootPath] 工作区根目录绝对路径。只读操作，不修改任何文件。
  /// 返回按最近快照时间降序排列的汇总列表。
  Future<List<VersionDirSummary>> getAllVersionSummaries(
    String rootPath,
  ) async {
    final summaries = <VersionDirSummary>[];
    final stack = <String>[rootPath];
    while (stack.isNotEmpty) {
      final current = stack.removeLast();
      late final List<FileSystemEntity> entities;
      try {
        entities = Directory(current).listSync(followLinks: false);
      } catch (_) {
        continue; // 权限错误等不可读目录，跳过
      }
      for (final entity in entities) {
        if (entity is! Directory) continue;
        final name = entity.uri.pathSegments.isEmpty
            ? ''
            : entity.uri.pathSegments.last;
        if (name == versionsDirName) {
          final summary = _summarizeVersionsDir(entity.path);
          if (summary != null) summaries.add(summary);
        } else {
          stack.add(entity.path);
        }
      }
    }
    summaries.sort((a, b) => b.lastModified.compareTo(a.lastModified));
    return summaries;
  }

  /// 统计单个 `.versions/{文档名}/` 目录；目录为空或不可读时返回 null。
  VersionDirSummary? _summarizeVersionsDir(String versionsDir) {
    var count = 0;
    var size = 0;
    DateTime? lastModified;
    try {
      final entries = Directory(versionsDir).listSync(followLinks: false);
      for (final entry in entries) {
        if (entry is! File) continue;
        final fileName = entry.uri.pathSegments.isEmpty
            ? ''
            : entry.uri.pathSegments.last;
        if (fileName == _metadataFileName) continue;
        final stat = entry.statSync();
        count++;
        size += stat.size;
        final modified = stat.modified;
        if (lastModified == null || modified.isAfter(lastModified)) {
          lastModified = modified;
        }
      }
    } catch (_) {
      return null;
    }
    if (count == 0) return null;
    return VersionDirSummary(
      versionsDir: versionsDir,
      docBaseName: _docBaseNameFromVersionsDir(versionsDir),
      snapshotCount: count,
      totalSizeBytes: size,
      lastModified: lastModified ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  /// 从 `.versions/{文档名}/` 目录路径提取文档名（不含扩展名）。
  String _docBaseNameFromVersionsDir(String versionsDir) {
    final segments = versionsDir.split(Platform.pathSeparator);
    return segments.isEmpty ? versionsDir : segments.last;
  }

  /// 删除单个文档的全部版本快照（含元数据）。
  ///
  /// [filePath] 原始文件的绝对路径。目录不存在时静默返回。
  Future<void> deleteDocumentVersions(String filePath) {
    return _synchronized<void>(filePath, () async {
      final versionsDir = getVersionsDir(filePath);
      final dir = Directory(versionsDir);
      if (!await dir.exists()) return;
      await dir.delete(recursive: true);
      appDebugLog('VersionService: 清理文档全部版本快照 for $filePath');
    });
  }

  /// 删除指定版本目录的全部快照（含元数据）。
  ///
  /// [versionsDir] `.versions/{文档名}/` 目录的绝对路径（T-13 管理页传入，
  /// 由 [getAllVersionSummaries] 产出）。目录不存在时静默返回。
  Future<void> deleteVersionsDir(String versionsDir) {
    return _synchronized<void>(versionsDir, () async {
      final dir = Directory(versionsDir);
      if (!await dir.exists()) return;
      await dir.delete(recursive: true);
      appDebugLog('VersionService: 清理版本目录 $versionsDir');
    });
  }

  /// 一键清理：删除工作区根目录下全部 `.versions` 目录（含元数据）。
  Future<void> deleteAllVersions(String rootPath) {
    return _synchronized<void>('__delete_all__', () async {
      final summaries = await getAllVersionSummaries(rootPath);
      for (final summary in summaries) {
        final dir = Directory(summary.versionsDir);
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      }
      appDebugLog(
        'VersionService: 一键清理全部版本快照（${summaries.length} 个文档）',
      );
    });
  }

  /// 容量上限裁剪：全部快照总占用超过 [maxTotalSizeMb]（MB）时，
  /// 从最旧的未备注快照开始删除，直到总占用不高于上限；全部为备注快照
  /// 仍超限时退化为按最旧删除（含备注），避免容量无限增长。
  ///
  /// [rootPath] 工作区根目录绝对路径；[maxTotalSizeMb] 为 0 或空表示不限制。
  /// 全局锁防重入：同一时间只会执行一次全盘裁剪。
  Future<void> enforceCapacityLimit(
    String rootPath, {
    int? maxTotalSizeMb,
  }) async {
    if (maxTotalSizeMb == null || maxTotalSizeMb <= 0) return;
    final limitBytes = maxTotalSizeMb * 1024 * 1024;
    await _synchronized<void>('__capacity__', () async {
      final summaries = await getAllVersionSummaries(rootPath);
      var totalSize = 0;
      for (final summary in summaries) {
        totalSize += summary.totalSizeBytes;
      }
      if (totalSize <= limitBytes) return;

      // 收集全部快照条目（含备注信息，用于优先删除未备注快照）
      final entries = <_SnapshotEntry>[];
      for (final summary in summaries) {
        final metadataList = await _readMetadataListFromDir(summary.versionsDir);
        final byNumber = <int, DocumentVersion>{
          for (final v in metadataList) v.versionNumber: v,
        };
        late final List<FileSystemEntity> entities;
        try {
          entities = Directory(summary.versionsDir).listSync(followLinks: false);
        } catch (_) {
          continue;
        }
        for (final entity in entities) {
          if (entity is! File) continue;
          final fileName = entity.uri.pathSegments.isEmpty
              ? ''
              : entity.uri.pathSegments.last;
          if (fileName == _metadataFileName) continue;
          final versionNumber = _versionNumberFromFileName(fileName);
          final meta = versionNumber != null ? byNumber[versionNumber] : null;
          try {
            final stat = entity.statSync();
            entries.add(
              _SnapshotEntry(
                versionsDir: summary.versionsDir,
                versionPath: entity.path,
                versionNumber: versionNumber ?? -1,
                size: stat.size,
                mtime: stat.modified,
                note: meta?.note ?? '',
              ),
            );
          } catch (_) {
            // 单个文件 stat 失败跳过
          }
        }
      }

      // 排序：未备注在前，同组内按修改时间升序（最旧优先删除）
      entries.sort((a, b) {
        final aNoteEmpty = a.note.isEmpty ? 0 : 1;
        final bNoteEmpty = b.note.isEmpty ? 0 : 1;
        if (aNoteEmpty != bNoteEmpty) return aNoteEmpty.compareTo(bNoteEmpty);
        return a.mtime.compareTo(b.mtime);
      });

      var deletedCount = 0;
      for (final entry in entries) {
        if (totalSize <= limitBytes) break;
        try {
          final file = File(entry.versionPath);
          if (await file.exists()) {
            await file.delete();
            totalSize -= entry.size;
            deletedCount++;
            // 同步元数据（按目录分组移除版本号）
            await _removeVersionFromMetadata(
              entry.versionsDir,
              entry.versionNumber,
            );
          }
        } catch (e) {
          appDebugLog('VersionService: 容量裁剪删除快照失败: $e');
        }
      }
      if (deletedCount > 0) {
        appDebugLog(
          'VersionService: 容量上限裁剪清理 $deletedCount 个快照'
          '（总占用 ${(totalSize / 1024 / 1024).toStringAsFixed(2)}MB）',
        );
      }
    });
  }

  /// 从 metadata.json 中移除指定版本号（目录不存在或元数据损坏时静默）。
  Future<void> _removeVersionFromMetadata(
    String versionsDir,
    int versionNumber,
  ) async {
    if (versionNumber <= 0) return;
    try {
      final metadataPath =
          '$versionsDir${Platform.pathSeparator}$_metadataFileName';
      final metadataFile = File(metadataPath);
      if (!await metadataFile.exists()) return;
      final content = await metadataFile.readAsString();
      final jsonList = jsonDecode(content) as List<dynamic>;
      final updated = jsonList
          .whereType<Map<String, dynamic>>()
          .where((json) => (json['versionNumber'] as int?) != versionNumber)
          .toList();
      if (updated.length == jsonList.length) return;
      final jsonText = const JsonEncoder.withIndent('  ').convert(updated);
      await _atomicWrite(metadataPath, jsonText);
    } catch (_) {
      // 元数据写入失败不影响容量裁剪主流程
    }
  }

  /// 从快照文件名 `v{n}.md` 提取版本号；无法解析时返回 null。
  int? _versionNumberFromFileName(String fileName) {
    if (!fileName.startsWith('v') || !fileName.endsWith('.md')) return null;
    final digits = fileName.substring(1, fileName.length - 3);
    return int.tryParse(digits);
  }

  // ==================== 内部方法 ====================

  /// 读取元数据列表
  ///
  /// 如果元数据文件不存在或损坏，返回空列表。
  Future<List<DocumentVersion>> _readMetadataList(String filePath) async {
    return _readMetadataListFromDir(getVersionsDir(filePath));
  }

  /// 从 `.versions/{文档名}/` 目录读取元数据列表
  ///
  /// 如果元数据文件不存在或损坏，返回空列表。
  Future<List<DocumentVersion>> _readMetadataListFromDir(
    String versionsDir,
  ) async {
    final metadataPath = '$versionsDir${Platform.pathSeparator}$_metadataFileName';
    final file = File(metadataPath);

    if (!await file.exists()) {
      return [];
    }

    try {
      final content = await file.readAsString();
      final List<dynamic> jsonList = jsonDecode(content) as List<dynamic>;
      return jsonList
          .map((json) => DocumentVersion.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      appDebugLog('VersionService: 读取元数据失败，返回空列表: $e');
      return [];
    }
  }

  /// 写入元数据列表（原子写入）
  Future<void> _writeMetadataList(
    String filePath,
    List<DocumentVersion> metadataList,
  ) async {
    final metadataPath = getMetadataFilePath(filePath);
    final jsonList = metadataList.map((v) => v.toJson()).toList();
    final content = const JsonEncoder.withIndent('  ').convert(jsonList);
    await _atomicWrite(metadataPath, content);
  }

  /// 原子写入
  ///
  /// 先写入临时文件，再重命名，确保写入过程的原子性。
  Future<void> _atomicWrite(String path, String content) async {
    final tempFile = File('$path.tmp');

    try {
      await tempFile.writeAsString(content, flush: true);
      await tempFile.rename(path);
    } catch (e) {
      // 清理临时文件
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      rethrow;
    }
  }
}

/// 容量裁剪候选快照条目（仅用于 enforceCapacityLimit 内部排序）
class _SnapshotEntry {
  /// 所属 `.versions/{文档名}/` 目录
  final String versionsDir;

  /// 快照文件绝对路径
  final String versionPath;

  /// 版本号；无法解析时为 -1（仍可删除文件，但不改元数据）
  final int versionNumber;

  /// 快照大小（字节）
  final int size;

  /// 修改时间
  final DateTime mtime;

  /// 用户备注（空串表示无备注，容量裁剪优先删除）
  final String note;

  const _SnapshotEntry({
    required this.versionsDir,
    required this.versionPath,
    required this.versionNumber,
    required this.size,
    required this.mtime,
    required this.note,
  });
}
