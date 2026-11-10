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

/// 已选中图片的**本机可读路径**（不读字节）。
///
/// 【为什么需要它（2026-11-07 用户：选完要等一秒缩略图才出现）】
/// 原链路是「读字节 → isolate 解码 → 缩放重编码 → 写文档目录副本 → 上屏」，
/// 一张 12MP 的手机照片跑完要接近一秒。有了路径就能**先把原图挂上预览**
/// （系统相册选出来的文件 App 本来就可读），重活放后台做，完成后再换成本地
/// 文档目录的副本（那份才是随聊天记录长期保留的）。
final class SelectedMealImageRef {
  const SelectedMealImageRef({
    required this.path,
    required this.fileName,
    required this.source,
  });

  final String path;
  final String fileName;
  final MealImageSource source;
}

/// 支持**多选**并暴露原路径的选图器（可选能力）。
///
/// 独立成一个接口而不是往 [MealImagePicker] 加方法：既有实现与测试桩不必
/// 跟着改（`is PathMealImagePicker` 判断，不支持就退回单选老链路）。
abstract interface class PathMealImagePicker {
  /// 选 1..[limit] 张；返回本机可读路径（**不读字节**）。用户取消返回空。
  Future<List<SelectedMealImageRef>> pickRefs(
    MealImageSource source, {
    int limit = 9,
  });
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
