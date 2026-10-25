import 'dart:io';

import 'package:localfit_ai/features/campus_menus/domain/menu_raw_content_store.dart';
import 'package:path/path.dart' as path;

/// 文件系统实现：原文写在 `<rootDir>/menu_raw/<snapshotId>.raw`，入库的
/// 相对路径固定为 `menu_raw/<snapshotId>.raw`（docs/07 §6.1）。
final class FileMenuRawContentStore implements MenuRawContentStore {
  const FileMenuRawContentStore(this.rootDir);

  /// 应用私有根目录（原文子目录由 [directoryName] 决定）。
  final String rootDir;

  static const String directoryName = 'menu_raw';

  @override
  Future<String> save({
    required String snapshotId,
    required String rawText,
  }) async {
    // 快照 id 直接进文件名与入库的相对路径，只接受单个路径段（否则
    // `../x` 这类 id 会让相对路径逃出根目录）。
    if (snapshotId.isEmpty || snapshotId.contains(RegExp(r'[\\/]'))) {
      throw const MenuRawContentFailure('菜单快照 id 不能为空或包含路径分隔符。');
    }
    final relativePath = '$directoryName/$snapshotId.raw';
    try {
      await Directory(path.join(rootDir, directoryName))
          .create(recursive: true);
      await File(resolve(relativePath)).writeAsString(rawText, flush: true);
    } catch (_) {
      throw const MenuRawContentFailure('无法保存菜单原文，请检查设备存储空间。');
    }
    return relativePath;
  }

  @override
  String resolve(String relativePath) {
    // 用 normalize（纯文本归约）而不是 canonicalize：判据要的是「`..` 段有没有
    // 逃出去」，而 canonicalize 在 Windows 上会顺手改盘符大小写，会让返回的
    // 路径与入库值不再逐字相同（历史的绝对路径用例依赖逐字相同）。
    final root = path.normalize(rootDir);
    // 2.0-7b 之前的版本按绝对路径入库（并写在根目录下）。升级后这些行
    // 仍指向真实文件，按原路径读取，不因为布局调整而失效——但只认「直接
    // 躺在应用私有根目录下」这一个位置：入库的路径可能来自被篡改/迁移的
    // 备份包，绝对路径原样返回就等于让备份文件指定读哪个本地文件。
    if (path.isAbsolute(relativePath)) {
      final normalized = path.normalize(relativePath);
      if (path.dirname(normalized) != root) {
        throw const MenuRawContentFailure('菜单原文路径不在应用私有目录内。');
      }
      return normalized;
    }
    // 相对路径同理：`..` 之类的段一旦逃出根目录就整条拒绝（save 只写
    // `menu_raw/<id>.raw`，没有任何合法的出界写法）。**两个分隔符都要切**：
    // 只切 `/` 时 `..\x` 会被当成一个普通段名，落在根目录里成了个怪文件名
    // （本次测出来的：判定必须与入库/读取时认识的路径语法一致）。
    final segments = relativePath.split(RegExp(r'[\\/]'));
    if (segments.contains('..')) {
      throw const MenuRawContentFailure('菜单原文路径越出应用私有目录。');
    }
    final resolved = path.normalize(path.joinAll([rootDir, ...segments]));
    if (resolved != root && !path.isWithin(root, resolved)) {
      throw const MenuRawContentFailure('菜单原文路径越出应用私有目录。');
    }
    return resolved;
  }

  @override
  Future<void> clearAll() async {
    final directory = Directory(path.join(rootDir, directoryName));
    try {
      if (directory.existsSync()) await directory.delete(recursive: true);
      await _clearLegacyFiles();
    } catch (_) {
      throw const MenuRawContentFailure('本地菜单原文清理失败，请重试。');
    }
  }

  /// 删除 2.0-7b 之前写在根目录下的 `<snapshotId>.raw`（升级用户的历史
  /// 原文：不删就违反「清除全部本地数据不留用户字节」）。
  Future<void> _clearLegacyFiles() async {
    final root = Directory(rootDir);
    if (!root.existsSync()) return;
    await for (final entity in root.list()) {
      if (entity is File && entity.path.endsWith('.raw')) {
        await entity.delete();
      }
    }
  }
}
