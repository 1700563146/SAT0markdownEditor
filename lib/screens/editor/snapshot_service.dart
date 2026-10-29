import '../../models/document_version.dart';
import '../../services/version_service.dart';

/// T-09：编辑器版本快照服务
///
/// 从 `_EditorScreenState` 中拆出的版本快照职责，封装对 [VersionService]（T-01）
/// 的调用，按文档维度复用，与 UI 解耦。
///
/// 方法签名与 [VersionService] 保持一致；页面 State 可通过构造参数注入替换实现。
class SnapshotService {
  SnapshotService({VersionService? versionService})
    : _versionService = versionService ?? VersionService();

  final VersionService _versionService;

  /// 创建版本快照（内容与最新快照一致时自动去重）
  ///
  /// [maxVersions] T-13 保留数量设置；由调用方（编辑器）从
  /// SettingsProvider.versions 读取后传入。
  Future<DocumentVersion> createVersion(
    String filePath,
    String content, {
    String note = '',
    int? maxVersions,
  }) {
    return _versionService.createVersion(
      filePath,
      content,
      note: note,
      maxVersions: maxVersions,
    );
  }

  /// 获取版本历史（按时间倒序）
  Future<List<DocumentVersion>> getVersionHistory(String filePath) {
    return _versionService.getVersionHistory(filePath);
  }

  /// 获取指定版本的内容
  Future<String> getVersionContent(String filePath, int versionNumber) {
    return _versionService.getVersionContent(filePath, versionNumber);
  }

  /// 更新版本备注
  Future<void> updateVersionNote(
    String filePath,
    int versionNumber,
    String note,
  ) {
    return _versionService.updateVersionNote(filePath, versionNumber, note);
  }

  /// 回退到指定版本（内部自动备份当前内容）
  Future<DocumentVersion> restoreVersion(
    String filePath,
    int versionNumber, {
    int? maxVersions,
  }) {
    return _versionService.restoreVersion(
      filePath,
      versionNumber,
      maxVersions: maxVersions,
    );
  }

  /// 从指定版本创建新文档，返回新文档路径
  Future<String> createNewDocFromVersion(
    String filePath,
    int versionNumber,
  ) {
    return _versionService.createNewDocFromVersion(filePath, versionNumber);
  }

  /// 释放资源（当前无持有资源，保持接口一致性）
  void dispose() {}
}
