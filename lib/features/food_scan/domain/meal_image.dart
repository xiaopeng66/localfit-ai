import 'dart:typed_data';

enum MealImageSource { camera, gallery }

final class SelectedMealImage {
  const SelectedMealImage({required this.bytes, required this.source});

  final Uint8List bytes;
  final MealImageSource source;
}

final class PreparedMealImage {
  const PreparedMealImage({
    required this.path,
    required this.width,
    required this.height,
    required this.byteLength,
  });

  final String path;
  final int width;
  final int height;
  final int byteLength;
  String get mediaType => 'image/jpeg';
}

final class ProcessedMealImage {
  const ProcessedMealImage({
    required this.bytes,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final int width;
  final int height;
}

final class MealImageFailure implements Exception {
  const MealImageFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract interface class MealImagePicker {
  Future<SelectedMealImage?> pick(MealImageSource source);
  Future<SelectedMealImage?> recoverLost();
}

abstract interface class MealImageProcessor {
  Future<ProcessedMealImage> process(SelectedMealImage selected);
}

abstract interface class TemporaryMealImageStore {
  Future<PreparedMealImage> save(ProcessedMealImage image);
  Future<void> delete(PreparedMealImage image);

  /// 过期清扫：启动时兜底删掉超过保留窗口的图片（扫描中断留下的残骸）。
  Future<void> clearStale();

  /// 整目录清理：「清除全部本地数据」用（docs/08 的隐私承诺是餐照只留在
  /// 临时目录、且随全清一起消失）。**不能用 [clearStale] 代替**——它的
  /// 保留窗口会让用户刚拍的餐照留在盘上。
  Future<void> clearAll();
}
