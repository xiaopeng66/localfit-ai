import 'dart:io';

import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/features/food_scan/domain/meal_image.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

final class FileTemporaryMealImageStore implements TemporaryMealImageStore {
  const FileTemporaryMealImageStore({
    required this.idGenerator,
    this.staleAfter = const Duration(hours: 24),
  });

  final IdGenerator idGenerator;
  final Duration staleAfter;

  @override
  Future<PreparedMealImage> save(ProcessedMealImage image) async {
    final directory = await _directory();
    final id = idGenerator.next().replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '');
    final finalFile = File(path.join(directory.path, '$id.jpg'));
    final partial = File(path.join(directory.path, '$id.partial'));
    try {
      await partial.writeAsBytes(image.bytes, flush: true);
      await partial.rename(finalFile.path);
      return PreparedMealImage(
        path: finalFile.path,
        width: image.width,
        height: image.height,
        byteLength: image.bytes.length,
      );
    } catch (_) {
      await _deleteIfPresent(partial);
      await _deleteIfPresent(finalFile);
      throw const MealImageFailure('无法保存本地处理后的图片，请检查设备存储空间。');
    }
  }

  @override
  Future<void> delete(PreparedMealImage image) async {
    final directory = await _directory();
    final candidate = path.canonicalize(image.path);
    final root = '${path.canonicalize(directory.path)}${path.separator}';
    if (!candidate.startsWith(root)) {
      throw const MealImageFailure('拒绝删除应用临时目录之外的文件。');
    }
    await _deleteIfPresent(File(candidate));
  }

  @override
  Future<void> clearStale() async {
    final directory = await _directory();
    final cutoff = DateTime.now().subtract(staleAfter);
    await for (final entity in directory.list()) {
      if (entity is! File) continue;
      final name = path.basename(entity.path);
      if (!name.endsWith('.jpg') && !name.endsWith('.partial')) continue;
      try {
        if ((await entity.lastModified()).isBefore(cutoff)) {
          await entity.delete();
        }
      } catch (_) {
        // A concurrent cleanup or OS cache eviction is harmless.
      }
    }
  }

  @override
  Future<void> clearAll() async {
    final directory = await _directory();
    try {
      if (directory.existsSync()) await directory.delete(recursive: true);
    } catch (_) {
      throw const MealImageFailure('本地临时图片清理失败，请重试。');
    }
  }

  Future<Directory> _directory() async {
    final temporary = await getTemporaryDirectory();
    final directory = Directory(
      path.join(temporary.path, 'localfit_ai', 'meal_scan'),
    );
    await directory.create(recursive: true);
    return directory;
  }

  Future<void> _deleteIfPresent(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      throw const MealImageFailure('本地临时图片清理失败，请重试。');
    }
  }
}
