import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:localfit_ai/features/nutrition/data/food_csv_importer.dart';

/// 食物 CSV 的文件来源。UI 永远不直接碰 picker 插件——测试注入内存实现，
/// 与 `BackupFileStore` 同一约定（docs/28 §5.6）。
abstract interface class FoodCsvFileSource {
  /// 让用户挑一份 CSV。返回文件字节；取消返回 null。
  Future<Uint8List?> pickFoodCsv();
}

final class FilePickerFoodCsvSource implements FoodCsvFileSource {
  const FilePickerFoodCsvSource();

  @override
  Future<Uint8List?> pickFoodCsv() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );
    if (file == null) return null;
    // 只问大小、不读内容：选择器报回的 size 优先，超限文件根本不读进内存
    // （与 `FilePickerBackupFileStore.pickRestoreFile` 同一顺序）。
    final length = await file.length();
    final violation = FoodCsvImporter.sizeViolation(bytes: length);
    if (violation != null) throw FormatException(violation);
    return file.readAsBytes();
  }
}
