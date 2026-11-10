import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:localfit_ai/features/food_scan/domain/meal_image.dart';

final class ImagePickerMealImagePicker
    implements MealImagePicker, PathMealImagePicker {
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

  /// 多选 + 只返回路径（不读字节）：给「选中即显示、后台再处理」用。
  ///
  /// 相机只能拍一张（系统相机没有多选语义）；相册走 `pickMultiImage`。
  @override
  Future<List<SelectedMealImageRef>> pickRefs(
    MealImageSource source, {
    int limit = 9,
  }) async {
    final effectiveLimit = limit < 1 ? 1 : limit;
    try {
      if (source == MealImageSource.camera) {
        final file = await _picker.pickImage(
          source: ImageSource.camera,
          requestFullMetadata: false,
        );
        return file == null ? const [] : [_ref(file, source)];
      }
      final files = await _picker.pickMultiImage(
        requestFullMetadata: false,
        limit: effectiveLimit,
      );
      return [
        for (final file in files.take(effectiveLimit)) _ref(file, source),
      ];
    } on Object {
      throw const MealImageFailure('无法选择图片，请检查相机或相册权限后重试。');
    }
  }

  SelectedMealImageRef _ref(XFile file, MealImageSource source) =>
      SelectedMealImageRef(
        path: file.path,
        fileName: file.name.isEmpty ? file.path.split('/').last : file.name,
        source: source,
      );

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
