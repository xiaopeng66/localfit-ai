import 'dart:io';
import 'dart:typed_data';

import 'package:localfit_ai/features/food_scan/domain/meal_image.dart';

abstract interface class PreparedMealImageBytesReader {
  Future<Uint8List> read(PreparedMealImage image);
}

final class FilePreparedMealImageBytesReader
    implements PreparedMealImageBytesReader {
  const FilePreparedMealImageBytesReader();

  @override
  Future<Uint8List> read(PreparedMealImage image) async {
    try {
      return await File(image.path).readAsBytes();
    } on FileSystemException {
      throw const MealImageFailure('无法读取已处理的餐食图片。');
    }
  }
}
