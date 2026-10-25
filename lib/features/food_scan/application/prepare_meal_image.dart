import 'package:localfit_ai/features/food_scan/domain/meal_image.dart';

final class PrepareMealImage {
  const PrepareMealImage({
    required this.picker,
    required this.processor,
    required this.store,
  });

  final MealImagePicker picker;
  final MealImageProcessor processor;
  final TemporaryMealImageStore store;

  Future<void> initialize() => store.clearStale();

  Future<PreparedMealImage?> select(
    MealImageSource source, {
    PreparedMealImage? current,
  }) async {
    final selected = await picker.pick(source);
    if (selected == null) return null;
    return _prepare(selected, current: current);
  }

  Future<PreparedMealImage?> recover({PreparedMealImage? current}) async {
    final selected = await picker.recoverLost();
    if (selected == null) return null;
    return _prepare(selected, current: current);
  }

  Future<PreparedMealImage> _prepare(
    SelectedMealImage selected, {
    PreparedMealImage? current,
  }) async {
    final processed = await processor.process(selected);
    final prepared = await store.save(processed);
    // 旧图删除是尽力而为：失败时仍要返回新图，否则已保存的文件
    // 会滞留成孤儿（由 clearStale 兜底清理）。
    try {
      if (current != null) await store.delete(current);
    } on Object {
      // 尽力清理，失败不阻断新图流程。
    }
    return prepared;
  }

  Future<void> discard(PreparedMealImage? image) async {
    if (image != null) await store.delete(image);
  }
}
