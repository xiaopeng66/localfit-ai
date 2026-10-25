import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_image.dart';
import 'package:localfit_ai/features/food_scan/domain/meal_image.dart';

/// 从相册选一张图作为聊天附件（docs/21 §5.7 数据来源：图片消息复用现有
/// 图片处理管线——`MealImagePicker` + `MealImageProcessor`）。
///
/// 只走相册：设计稿的 AI 对话页只有 `btn-image-upload`（加号），没有拍照
/// 入口，拍照在「拍照识别」chip 里（推入 `/meal-recognition`）。
final class PickChatImage {
  const PickChatImage({
    required this.picker,
    required this.processor,
    required this.store,
    required this.clock,
  });

  final MealImagePicker picker;
  final MealImageProcessor processor;
  final ChatImageStore store;
  final AppClock clock;

  /// 返回 null 表示用户取消选择（不是错误）。
  Future<ChatImage?> pick() async {
    final selected = await picker.pick(MealImageSource.gallery);
    if (selected == null) return null;
    final processed = await processor.process(selected);
    return store.save(processed, createdAt: clock.nowUtc());
  }

  /// 丢弃一张不再使用的聊天图片（尽力而为，失败由调用方决定是否提示）。
  Future<void> discard(ChatImage image) => store.delete(image.path);
}
