import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:localfit_ai/features/food_scan/domain/meal_image.dart';

final class ImagePickerMealImagePicker implements MealImagePicker {
  ImagePickerMealImagePicker({ImagePicker? picker})
    : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<SelectedMealImage?> pick(MealImageSource source) async {
    try {
      final file = await _picker.pickImage(
        source: source == MealImageSource.camera
            ? ImageSource.camera
            : ImageSource.gallery,
        requestFullMetadata: false,
      );
      if (file == null) return null;
      return _selected(await file.readAsBytes(), source);
    } catch (_) {
      throw const MealImageFailure('无法选择图片，请检查相机或相册权限后重试。');
    }
  }

  @override
  Future<SelectedMealImage?> recoverLost() async {
    try {
      final response = await _picker.retrieveLostData();
      if (response.isEmpty) return null;
      if (response.exception != null || response.files == null) {
        throw const MealImageFailure('上次选择的图片无法恢复，请重新选择。');
      }
      final file = response.files!.firstOrNull;
      if (file == null) return null;
      return _selected(await file.readAsBytes(), MealImageSource.gallery);
    } on MealImageFailure {
      rethrow;
    } catch (_) {
      throw const MealImageFailure('上次选择的图片无法恢复，请重新选择。');
    }
  }

  SelectedMealImage _selected(Uint8List bytes, MealImageSource source) {
    if (bytes.isEmpty) throw const MealImageFailure('所选图片为空。');
    return SelectedMealImage(bytes: bytes, source: source);
  }
}
