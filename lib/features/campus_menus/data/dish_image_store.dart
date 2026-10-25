import 'dart:io';
import 'dart:typed_data';

import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/features/backup/application/clear_all_local_data.dart'
    show DishImageStoreRef;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// 菜品照片的本地存储：应用**文档**目录下的 `localfit_ai/dish_images/`。
///
/// docs/29 §P7 需求 16：与聊天图片（`FileChatImageStore`）同一个模式——
/// 选图后**复制进私有目录再存路径**，绝不引用相册里的原始 URI（相册
/// 路径会随系统整理/删除失效，而菜品照片是目录数据的一部分）。
/// 不用临时目录：临时目录可被系统随时回收。
///
/// 删除守卫与聊天图片同款：只删本目录内的路径（防篡改的备份包塞进
/// `../` 让恢复后的应用删到私有目录之外），尽力而为、失败不影响落库
/// （孤儿文件好过写库失败）。
///
/// 刻意**非 final**：`canteen_repository_test` 用记录型假实现验证「替换/
/// 移除/删除菜品时仓库是否按语义清旧文件」，真实文件 IO 由
/// `dish_image_store_test` 覆盖；本类没有继承链，开放继承无风险。
class DishImageStore implements DishImageStoreRef {
  const DishImageStore({required this.idGenerator});

  final IdGenerator idGenerator;

  /// 把照片字节复制进 `dish_images/`，返回可直接入库的绝对路径。
  ///
  /// [extension] 必须以 `.` 开头且只含字母数字（如 `.jpg`）；缺省 `.jpg`。
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
      final directory = await _directory();
      final fileName = await _uniqueFileName(
        createdAt,
        directory,
        safeExtension,
      );
      finalFile = File(path.join(directory.path, fileName));
      partial = File('${finalFile.path}.partial');
      await partial.writeAsBytes(bytes, flush: true);
      await partial.rename(finalFile.path);
      return finalFile.path;
    } catch (_) {
      if (partial != null) await _deleteQuietly(partial);
      if (finalFile != null) await _deleteQuietly(finalFile);
      throw const DishImageStoreException('无法保存照片，请检查设备存储空间。');
    }
  }

  /// 删除一张菜品照片；路径不在本目录内直接拒绝（不抛出，调用方在
  /// 落库路径上，删除失败不该打断数据操作）。
  Future<void> deleteQuietly(String? filePath) async {
    if (filePath == null || filePath.isEmpty) return;
    try {
      final directory = await _directory();
      final candidate = path.canonicalize(filePath);
      final root = '${path.canonicalize(directory.path)}${path.separator}';
      if (!candidate.startsWith(root)) return;
      final file = File(candidate);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // 尽力而为：残留文件不阻塞数据操作。
    }
  }

  /// 「清除全部本地数据」用：整目录删掉菜品照片（`docs/21 §5.8.1` 的不变量
  /// 「全清之后不留任何用户字节」）。菜品照片不在数据库里，只删行删不掉它。
  /// 与聊天图片同一口径：不先建目录（清理不该反过来创建目录），能清就清，
  /// 清不掉才报错。
  @override
  Future<void> clearAll() async {
    try {
      final target = Directory(await _directoryPath());
      if (target.existsSync()) {
        await target.delete(recursive: true);
        return;
      }
      final stray = File(target.path);
      if (stray.existsSync()) await stray.delete();
    } catch (_) {
      throw const DishImageStoreException('本地菜品照片清理失败，请重试。');
    }
  }

  /// `dish_20261006_153012_ab12.jpg`：时间可读 + 短随机后缀（尾部随机段，
  /// 与 FileChatImageStore 同理——取前缀会同秒撞名静默覆盖）。
  Future<String> _uniqueFileName(
    DateTime createdAt,
    Directory directory,
    String extension,
  ) async {
    final local = createdAt.toLocal();
    final stamp =
        '${local.year.toString().padLeft(4, '0')}'
        '${local.month.toString().padLeft(2, '0')}'
        '${local.day.toString().padLeft(2, '0')}_'
        '${local.hour.toString().padLeft(2, '0')}'
        '${local.minute.toString().padLeft(2, '0')}'
        '${local.second.toString().padLeft(2, '0')}';
    for (var attempt = 0; attempt < 5; attempt++) {
      final compact = idGenerator.next().replaceAll(
        RegExp(r'[^a-zA-Z0-9]'),
        '',
      );
      final suffix =
          (compact.length <= 4
                  ? compact.padRight(4, '0')
                  : compact.substring(compact.length - 4))
              .toLowerCase();
      final name = 'dish_${stamp}_$suffix$extension';
      if (!File(path.join(directory.path, name)).existsSync()) return name;
    }
    throw const DishImageStoreException('照片命名冲突，请重试。');
  }

  /// 照片目录路径（不创建目录：清理路径不该反过来创建它）。
  Future<String> _directoryPath() async {
    final documents = await getApplicationDocumentsDirectory();
    return path.join(documents.path, 'localfit_ai', 'dish_images');
  }

  Future<Directory> _directory() async {
    final directory = Directory(await _directoryPath());
    await directory.create(recursive: true);
    return directory;
  }

  Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // 尽力清理。
    }
  }
}

/// 照片存储失败的用户可读语义（原始 IO 异常不外泄）。
final class DishImageStoreException implements Exception {
  const DishImageStoreException(this.userMessage);

  final String userMessage;

  @override
  String toString() => 'DishImageStoreException($userMessage)';
}
