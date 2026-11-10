import 'dart:io';

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
  /// [source] = 相册（默认）或相机（2026-10-31「+」三选弹层）。
  Future<ChatImage?> pick({
    MealImageSource source = MealImageSource.gallery,
  }) async {
    final selected = await picker.pick(source);
    if (selected == null) return null;
    final processed = await processor.process(selected);
    return store.save(processed, createdAt: clock.nowUtc());
  }

  /// 选图器是否支持「多选 + 只给路径」（不支持就退回 [pick] 的单选老链路）。
  bool get supportsFastPreview => picker is PathMealImagePicker;

  /// 只选、不处理：返回本机可读路径，调用方可以**立刻**挂上预览。
  ///
  /// 用户取消返回空列表；[limit] 是本次最多选几张（页面按剩余槽位传入）。
  Future<List<SelectedMealImageRef>> pickRefs({
    MealImageSource source = MealImageSource.gallery,
    int limit = 9,
  }) {
    final fast = picker;
    if (fast is! PathMealImagePicker) {
      throw const MealImageFailure('当前选图器不支持多选。');
    }
    // 两个接口互不继承（可选能力），is 之后仍要显式 cast 才能调。
    return (fast as PathMealImagePicker).pickRefs(source, limit: limit);
  }

  /// 把一张已选中的原图处理成**本地文档目录副本**（缩放 + 重编码 + 落盘）。
  ///
  /// 这是原来 [pick] 里那一段重活：现在放到预览之后在后台跑，完成后页面用
  /// 返回的副本替换占位预览——聊天记录长期保留的就是这份副本。
  Future<ChatImage> materialize(SelectedMealImageRef ref) async {
    final bytes = await File(ref.path).readAsBytes();
    if (bytes.isEmpty) throw const MealImageFailure('所选图片为空。');
    final processed = await processor.process(
      SelectedMealImage(bytes: bytes, source: ref.source),
    );
    return store.save(processed, createdAt: clock.nowUtc());
  }

  /// 丢弃一张不再使用的聊天图片（尽力而为，失败由调用方决定是否提示）。
  Future<void> discard(ChatImage image) => store.delete(image.path);
}
