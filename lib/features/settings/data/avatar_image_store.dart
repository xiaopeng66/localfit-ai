import 'dart:io';
import 'dart:typed_data';

import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/features/backup/application/clear_all_local_data.dart'
    show AvatarImageStoreRef;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// 用户头像的本地存储：应用**文档**目录下的 `localfit_ai/avatar/`。
///
/// docs/32 §3 D9：与 `DishImageStore` / `FileChatImageStore` 同一个模式——
/// 选图后**复制进私有目录再存路径**，绝不引用相册原始 URI（相册路径会随
/// 系统整理失效）。不用临时目录：系统可随时回收。
///
/// **替换即删旧文件**（D9 要求）；删除只认本目录内的路径（防篡改的 `.lfb`
/// 塞进 `../` 让恢复后的应用删到私有目录之外）。删除失败不影响落库
/// （孤儿文件好过写库失败），与菜品照片同款「尽力而为」。
class AvatarImageStore implements AvatarImageStoreRef {
  const AvatarImageStore({required this.idGenerator});

  final IdGenerator idGenerator;

  /// 目录名（`<应用文档目录>/localfit_ai/avatar/`）。
  static const String directoryName = 'avatar';

  /// 把头像字节复制进 `avatar/`，返回可入库的绝对路径。
  ///
  /// 写入用 partial + rename 的原子模式：半截文件绝不以正式名存在。
  Future<String> copyBytes(
    Uint8List bytes, {
    required DateTime createdAt,
    String extension = '.jpg',
  }) async {
    final safeExtension = RegExp(r'^\.[a-zA-Z0-9]+$').hasMatch(extension)
        ? extension
        : '.jpg';
    File? partial;
    File? finalFile;
    try {
      final directory = await ensureDirectory();
      final stamp = createdAt.toUtc().millisecondsSinceEpoch;
      final fileName = 'avatar-$stamp-${idGenerator.next()}$safeExtension';
      finalFile = File(path.join(directory.path, fileName));
      partial = File('${finalFile.path}.partial');
      await partial.writeAsBytes(bytes, flush: true);
      await partial.rename(finalFile.path);
      return finalFile.path;
    } catch (_) {
      if (partial != null) await _deleteQuietly(partial);
      if (finalFile != null) await _deleteQuietly(finalFile);
      throw const AvatarStoreException('无法保存头像，请检查设备存储空间。');
    }
  }

  /// 该路径是否落在本目录内。`.lfb` 恢复侧与写入侧共用同一条判据。
  Future<bool> isInsideStore(String filePath) async {
    try {
      final directory = await ensureDirectory();
      final candidate = path.canonicalize(filePath);
      final root = '${path.canonicalize(directory.path)}${path.separator}';
      return candidate.startsWith(root);
    } catch (_) {
      return false;
    }
  }

  /// 删除头像文件；路径不在本目录内直接拒绝（不抛出，调用方在落库路径上）。
  Future<void> deleteQuietly(String? filePath) async {
    if (filePath == null || filePath.isEmpty) return;
    if (!await isInsideStore(filePath)) return;
    await _deleteQuietly(File(filePath));
  }

  /// 头像文件是否真的存在（决定界面显图还是回退首字母）。
  Future<bool> exists(String? filePath) async {
    if (filePath == null || filePath.isEmpty) return false;
    if (!await isInsideStore(filePath)) return false;
    return File(filePath).exists();
  }

  /// 全清只认固定私有目录，包含孤儿/partial 文件；不读取已删的档案路径。
  /// 目录不存在时不创建，清理失败必须上抛，不能谎报「全部清除」。
  @override
  Future<void> clearAll() async {
    try {
      final target = Directory(await _directoryPath());
      if (await target.exists()) {
        await target.delete(recursive: true);
        return;
      }
      final stray = File(target.path);
      if (await stray.exists()) await stray.delete();
    } catch (_) {
      throw const AvatarStoreException('本地头像清理失败，请重试。');
    }
  }

  Future<String> _directoryPath() async {
    final documents = await getApplicationDocumentsDirectory();
    return path.join(documents.path, 'localfit_ai', directoryName);
  }

  Future<Directory> ensureDirectory() async {
    final directory = Directory(await _directoryPath());
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // 尽力而为：删不掉就留着孤儿文件，不让它打断落库。
    }
  }
}

/// 头像保存失败（可上屏的中文原因）。
final class AvatarStoreException implements Exception {
  const AvatarStoreException(this.message);

  final String message;

  @override
  String toString() => message;
}
