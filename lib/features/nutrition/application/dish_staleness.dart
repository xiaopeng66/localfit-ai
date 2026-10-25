import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/domain/dish_record.dart';

/// 来源陈旧检测（docs/40 §6）：食堂菜重新分析营养后，指向它的菜品库行
/// 要能提示「食堂营养有更新」——**只提示，不自动同步**（用户点才改；
/// `userEdited` 的行连提示都只作参考，绝不覆盖）。
///
/// 判据：`dish_library.sourceUpdatedAt < menu_items.updatedAt`。
/// 来源被删除（`sourceId` 悬空）另给「来源已删除」状态，不级联删菜品。
enum DishStalenessState {
  /// 没有来源链接（手工菜 / 导入菜）：无从比较。
  unlinked,

  /// 来源已删除：链接悬空。
  sourceMissing,

  /// 来源有更新（`sourceUpdatedAt` 早于来源的 updatedAt）。
  sourceUpdated,

  /// 已是最新。
  upToDate,
}

/// 一条陈旧判定结果。
final class DishStaleness {
  const DishStaleness({
    required this.dishId,
    required this.state,
    this.sourceMenuItemId,
    this.sourceUpdatedAt,
    this.currentUpdatedAt,
    this.userEdited = false,
  });

  final String dishId;
  final DishStalenessState state;
  final String? sourceMenuItemId;
  final DateTime? sourceUpdatedAt;
  final DateTime? currentUpdatedAt;

  /// 用户手改过：**只提示、不覆盖**。
  final bool userEdited;

  /// 是否应该显示「食堂营养有更新」提示。
  bool get shouldPrompt => state == DishStalenessState.sourceUpdated;

  /// 提示文案（页面直接用；不要各页再写一份）。
  String? get notice => switch (state) {
    DishStalenessState.sourceUpdated =>
      userEdited ? '食堂营养有更新（你改过这份营养，不会自动覆盖）' : '食堂营养有更新',
    DishStalenessState.sourceMissing => '来源已删除',
    _ => null,
  };
}

/// 计算菜品库与食堂来源的陈旧状态（只读）。
final class DishStalenessChecker {
  const DishStalenessChecker({required this.database});

  final AppDatabase database;

  /// 单条判定。
  Future<DishStaleness> check(DishRecord dish) async {
    final sourceId = dish.sourceId;
    if (sourceId == null || sourceId.isEmpty) {
      return DishStaleness(dishId: dish.id, state: DishStalenessState.unlinked);
    }
    final row = await (database.select(
      database.menuItems,
    )..where((item) => item.id.equals(sourceId))).getSingleOrNull();
    if (row == null) {
      return DishStaleness(
        dishId: dish.id,
        state: DishStalenessState.sourceMissing,
        sourceMenuItemId: sourceId,
      );
    }
    final sourceUpdatedAt = dish.sourceUpdatedAt;
    final current = row.updatedAt;
    return DishStaleness(
      dishId: dish.id,
      state: sourceUpdatedAt == null || sourceUpdatedAt.isBefore(current)
          ? DishStalenessState.sourceUpdated
          : DishStalenessState.upToDate,
      sourceMenuItemId: sourceId,
      sourceUpdatedAt: sourceUpdatedAt,
      currentUpdatedAt: current,
    );
  }

  /// 批量判定（列表页一次拿全）。
  Future<Map<String, DishStaleness>> checkAll(List<DishRecord> dishes) async {
    final result = <String, DishStaleness>{};
    for (final dish in dishes) {
      result[dish.id] = await check(dish);
    }
    return result;
  }
}
