import 'package:localfit_ai/features/food_scan/domain/meal_image.dart';

/// 聊天图片（docs/21 §5.7「用户图片」形态）。
///
/// 与餐食扫描的临时图不同：聊天图片是**用户消息的一部分**，必须活到
/// 用户主动删除为止，所以存在应用文档目录（不是可被系统回收的临时目录）。
final class ChatImage {
  const ChatImage({
    required this.path,
    required this.fileName,
    required this.width,
    required this.height,
  });

  final String path;

  /// 真实文件名（预览条与消息里显示的就是它，不另外编展示名）。
  final String fileName;
  final int width;
  final int height;
}

/// 聊天图片的存取契约（docs/21 §5.7 数据来源：图片消息复用图片处理管线）。
abstract interface class ChatImageStore {
  /// 保存一张已处理（缩放/转 JPEG）的图片，返回聊天目录里的最终路径。
  Future<ChatImage> save(
    ProcessedMealImage image, {
    required DateTime createdAt,
  });

  /// 删除聊天目录内的图片；目录外的路径必须拒绝（防越权删除）。
  Future<void> delete(String path);

  /// 该路径的图片是否还在（用户可能从系统相册/文件管理器里删掉过）。
  Future<bool> exists(String path);

  /// 整目录清理：「清除全部本地数据」用（docs/08 全清承诺不留用户字节）。
  Future<void> clearAll();
}

/// 聊天图片失败（保存/删除/清理），消息给用户看，不吞错。
final class ChatImageFailure implements Exception {
  const ChatImageFailure(this.message);

  final String message;

  @override
  String toString() => message;
}
