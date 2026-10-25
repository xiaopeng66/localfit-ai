/// 菜单原文存储失败（磁盘不可写、目录被占用等）。
final class MenuRawContentFailure implements Exception {
  const MenuRawContentFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 导入菜单原文的本地存储（docs/07 §6.1：原文写应用私有目录，数据库只保存
/// 相对路径、哈希和摘要）。
///
/// 数据库里存的是相对于存储根目录的**相对路径**：[save] 返回它，
/// [resolve] 再把它还原成本地路径。这样备份包里的路径不绑定某台设备的
/// 绝对目录，[clearAll] 也能整目录删除。
abstract interface class MenuRawContentStore {
  /// 保存一次导入的原文，返回入库用的相对路径（如 `menu_raw/<id>.raw`）。
  Future<String> save({required String snapshotId, required String rawText});

  /// 把入库的相对路径还原成本地路径（读取原文用）。
  String resolve(String relativePath);

  /// 删除全部已保存原文。目录不存在时是 no-op。
  Future<void> clearAll();
}
