import 'package:drift/drift.dart' show OrderingTerm;
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/data/dish_library_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/dish_record.dart';

/// 「同步食堂营养」的唯一写路径（docs/40 §6）。
///
/// 分工：`DishStalenessChecker` 只**判定**并提示；本类只在用户点「同步」时
/// 执行一次写入。**绝不自动同步**，`userEdited` 的行默认拒绝（页面文案说明
/// 「你改过这份营养，不会自动覆盖」），除非调用方显式 `force`（例如用户
/// 在确认框里再点一次「覆盖」）。
///
/// 换算沿用唯一口径：营养只有每 100g 一种事实，菜品库展示列是「每份」，
/// 所以 `每份 = per100g × servingGrams / 100`。份量来自菜品库自己的
/// `servingGrams`（用户的模板），来源侧没有份量列也不影响。
enum DishSyncOutcome {
  /// 已写入。
  applied,

  /// 这道菜没有 `sourceId`（手工菜/导入菜）。
  notLinked,

  /// 来源（menu_item）已被删除。
  sourceMissing,

  /// 来源还没有营养证据（没分析过）。
  noNutrition,

  /// 来源没有比菜品库新。
  upToDate,

  /// 用户手改过这一行，拒绝覆盖。
  userEdited,
}

/// 一次同步的结果；`message` 直接上屏（页面不再各写一份文案）。
final class DishSyncResult {
  const DishSyncResult(this.outcome, {this.dish});

  final DishSyncOutcome outcome;

  /// 写入后的记录（仅 [DishSyncOutcome.applied] 时非空）。
  final DishRecord? dish;

  bool get applied => outcome == DishSyncOutcome.applied;

  String get message => switch (outcome) {
    DishSyncOutcome.applied => '已同步食堂最新营养',
    DishSyncOutcome.notLinked => '这道菜没有关联食堂来源。',
    DishSyncOutcome.sourceMissing => '来源已被删除，无法同步。',
    DishSyncOutcome.noNutrition => '来源还没有营养值，先去食堂目录做分析。',
    DishSyncOutcome.upToDate => '已是最新，无需同步。',
    DishSyncOutcome.userEdited => '你改过这份营养，不会自动覆盖。',
  };
}

/// 执行同步（只读来源 + 一次写菜品库）。
final class DishSourceSync {
  const DishSourceSync({required this.database, required this.dishes});

  final AppDatabase database;
  final DishLibraryRepository dishes;

  Future<DishSyncResult> apply(DishRecord dish, {bool force = false}) async {
    final sourceId = dish.sourceId?.trim();
    if (sourceId == null || sourceId.isEmpty) {
      return const DishSyncResult(DishSyncOutcome.notLinked);
    }
    if (dish.userEdited && !force) {
      return DishSyncResult(DishSyncOutcome.userEdited, dish: dish);
    }

    final item =
        await (database.select(database.menuItems)
              ..where((row) => row.id.equals(sourceId))
              ..limit(1))
            .getSingleOrNull();
    if (item == null) {
      return const DishSyncResult(DishSyncOutcome.sourceMissing);
    }

    // 判据与 DishStalenessChecker 同源：sourceUpdatedAt 为空或早于来源即陈旧。
    final syncedAt = dish.sourceUpdatedAt;
    if (syncedAt != null && !syncedAt.isBefore(item.updatedAt)) {
      return DishSyncResult(DishSyncOutcome.upToDate, dish: dish);
    }

    final evidence =
        await (database.select(database.menuItemNutritionEvidence)
              ..where((row) => row.menuItemId.equals(sourceId))
              ..orderBy([(row) => OrderingTerm.desc(row.createdAt)])
              ..limit(1))
            .getSingleOrNull();
    final kcalPer100g = evidence?.kcalPer100g;
    final proteinPer100g = evidence?.proteinPer100g;
    final carbsPer100g = evidence?.carbsPer100g;
    final fatPer100g = evidence?.fatPer100g;
    if (kcalPer100g == null ||
        proteinPer100g == null ||
        carbsPer100g == null ||
        fatPer100g == null) {
      return const DishSyncResult(DishSyncOutcome.noNutrition);
    }

    // 份量未知 = 历史/回填行：按 100g 折算，与「按 100g 估算」徽标同一口径。
    final grams = dish.servingGrams ?? 100;
    final factor = grams / 100;
    final updated = await dishes.updateNutritionFromSource(
      id: dish.id,
      kcal: _round1(kcalPer100g * factor),
      proteinG: _round1(proteinPer100g * factor),
      carbsG: _round1(carbsPer100g * factor),
      fatG: _round1(fatPer100g * factor),
      sourceUpdatedAt: item.updatedAt,
    );
    return DishSyncResult(DishSyncOutcome.applied, dish: updated);
  }

  /// 一位小数：与菜品卡的数字格式（`toStringAsFixed(1)`）同粒度，
  /// 避免 0.30000000000000004 这类浮点尾巴进库。
  static double _round1(double value) => (value * 10).roundToDouble() / 10;
}
