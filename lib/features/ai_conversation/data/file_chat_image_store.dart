import 'dart:io';

import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_image.dart';
import 'package:localfit_ai/features/food_scan/domain/meal_image.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// 聊天图片的文件实现：应用**文档**目录下的 `localfit_ai/chat_images/`。
///
/// 不用 `getTemporaryDirectory`（餐食扫描用那个）：临时目录可被系统随时
/// 回收，而聊天里的图片是用户消息的一部分，不能自己消失。
final class FileChatImageStore implements ChatImageStore {
  const FileChatImageStore({required this.idGenerator});

  final IdGenerator idGenerator;

  @override
  Future<ChatImage> save(
    ProcessedMealImage image, {
    required DateTime createdAt,
  }) async {
    File? partial;
    File? finalFile;
    // 目录不可写（只读存储、路径被同名文件占位）也要报成 ChatImageFailure：
    // 原始 IO 异常的类型不属于本仓储的契约，上层无法按语义处理。
    try {
      final directory = await _directory();
      final fileName = await _uniqueFileName(createdAt, directory);
      finalFile = File(path.join(directory.path, fileName));
      partial = File('${finalFile.path}.partial');
      await partial.writeAsBytes(image.bytes, flush: true);
      await partial.rename(finalFile.path);
      return ChatImage(
        path: finalFile.path,
        fileName: fileName,
        width: image.width,
        height: image.height,
      );
    } catch (error) {
      if (partial != null) await _deleteQuietly(partial);
      if (finalFile != null) await _deleteQuietly(finalFile);
      // 语义化失败（如命名冲突）原样上抛，别改写成「存储空间」误导用户。
      if (error is ChatImageFailure) rethrow;
      throw const ChatImageFailure('无法保存图片，请检查设备存储空间。');
    }
  }

  @override
  Future<void> delete(String filePath) async {
    try {
      final directory = await _directory();
      final candidate = path.canonicalize(filePath);
      final root = '${path.canonicalize(directory.path)}${path.separator}';
      if (!candidate.startsWith(root)) {
        throw const ChatImageFailure('拒绝删除聊天目录之外的文件。');
      }
      final file = File(candidate);
      if (await file.exists()) await file.delete();
    } on ChatImageFailure {
      rethrow; // 越权拒绝不能被下面的兜底改写成「删除失败」
    } catch (_) {
      throw const ChatImageFailure('删除图片失败，请重试。');
    }
  }

  @override
  Future<bool> exists(String filePath) async {
    try {
      return await File(filePath).exists();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> clearAll() async {
    // 不先建目录（清理不该反过来创建目录），也不吞掉路径被同名文件占位的
    // 异常状态：能清掉就清掉，清不掉才报错。
    try {
      final target = Directory(await _chatDirectoryPath());
      if (target.existsSync()) {
        await target.delete(recursive: true);
        return;
      }
      final stray = File(target.path);
      if (stray.existsSync()) await stray.delete();
    } catch (_) {
      throw const ChatImageFailure('本地聊天图片清理失败，请重试。');
    }
  }

  /// `photo_20261001_153012_ab12.jpg`：时间可读 + 短随机后缀。
  ///
  /// 后缀取 id 的**尾部**而不是前缀：UuidV7 的前 12 位是毫秒时间戳，
  /// 同一秒内几乎不变——取前缀会让同秒选的两张图得到同一个文件名而
  /// **静默覆盖**前一张（阶段 G 用可预测 id 复现）。尾部是随机段；
  /// 万一仍然撞名（同名文件已存在），换一个 id 重试，绝不覆盖已有图片。
  Future<String> _uniqueFileName(
    DateTime createdAt,
    Directory directory,
  ) async {
    final stamp = _stamp(createdAt);
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
      final name = 'photo_${stamp}_$suffix.jpg';
      if (!File(path.join(directory.path, name)).existsSync()) return name;
    }
    // id 生成器坏了（恒定输出）才会走到这里：如实报错，不覆盖。
    throw const ChatImageFailure('图片命名冲突，请重试。');
  }

  String _stamp(DateTime createdAt) {
    final local = createdAt.toLocal();
    return '${local.year.toString().padLeft(4, '0')}'
        '${local.month.toString().padLeft(2, '0')}'
        '${local.day.toString().padLeft(2, '0')}_'
        '${local.hour.toString().padLeft(2, '0')}'
        '${local.minute.toString().padLeft(2, '0')}'
        '${local.second.toString().padLeft(2, '0')}';
  }

  Future<Directory> _directory() async {
    final directory = Directory(await _chatDirectoryPath());
    await directory.create(recursive: true);
    return directory;
  }

  Future<String> _chatDirectoryPath() async {
    final documents = await getApplicationDocumentsDirectory();
    return path.join(documents.path, 'localfit_ai', 'chat_images');
  }

  Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // 尽力清理：残留文件由 clearAll 兜底。
    }
  }
}
