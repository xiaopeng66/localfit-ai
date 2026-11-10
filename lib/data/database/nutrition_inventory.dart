import 'package:localfit_ai/core/nutrition/legacy_nutrition_rules.dart';
import 'package:localfit_ai/core/nutrition/nutrition_units.dart';
import 'package:localfit_ai/data/database/app_database.dart';

/// 旧数据**只读盘点**与迁移对账基线（docs/67 §7.1、§7.3、U02）。
///
/// 只读：本文件里没有任何 insert/update/delete。它存在的意义是把
/// 「迁移前有什么、迁移后少了什么」变成可比较的数，而不是靠行数猜。
///
/// 盘点口径：
/// * 旧键清单 = 迁移台账必须逐条覆盖的实体（`dish_library` + 旧供应）；
/// * 快照摘要 = 历史餐的日期/名称/克数/营养快照的稳定指纹——**迁移不许改它**；
/// * 媒体清单 = 图片路径字符串（不是图片字节；路径存在不等于文件已备份）；
/// * 待补全清单 = 不能安全换算的旧键与原因。
final class NutritionInventory {
  const NutritionInventory({
    required this.foodCount,
    required this.completeFoodCount,
    required this.foodsWithoutActiveRevision,
    required this.revisionCount,
    required this.dishLibraryCount,
    required this.dishBasisCounts,
    required this.dishTrustedServingCount,
    required this.dishAssumedServingCount,
    required this.menuItemCount,
    required this.linkedMenuItemCount,
    required this.menuItemAnalyzableCount,
    required this.menuItemRangeOnlyCount,
    required this.menuItemUnknownServingCount,
    required this.mealCount,
    required this.mealItemCount,
    required this.mealSnapshotDigest,
    required this.mediaPaths,
    required this.legacyKeys,
    required this.ledgerKeys,
    required this.pendingCompletionKeys,
  });

  final int foodCount;
  final int completeFoodCount;
  final int foodsWithoutActiveRevision;
  final int revisionCount;
  final int dishLibraryCount;
  final Map<String, int> dishBasisCounts;
  final int dishTrustedServingCount;
  final int dishAssumedServingCount;
  final int menuItemCount;
  final int linkedMenuItemCount;
  final int menuItemAnalyzableCount;
  final int menuItemRangeOnlyCount;
  final int menuItemUnknownServingCount;
  final int mealCount;
  final int mealItemCount;

  /// 历史餐快照的稳定指纹：迁移前后必须逐字节相同。
  final String mealSnapshotDigest;

  /// 图片路径（去重、排序）。**不是**图片字节清单。
  final List<String> mediaPaths;

  /// 旧实体键（`kind:id`），迁移台账必须逐条覆盖。
  final List<String> legacyKeys;

  /// 台账里已有的旧实体键。
  final List<String> ledgerKeys;

  /// 台账里判为待补全/冲突的旧键。
  final List<String> pendingCompletionKeys;

  /// 旧键是否被台账一条不漏地覆盖。
  ///
  /// 故意做成"漏一条就红"：迁移对账不是比较行数，而是逐条核销。
  bool get everyLegacyKeyAccounted {
    final accounted = ledgerKeys.toSet();
    return legacyKeys.every(accounted.contains);
  }

  /// 待补全的键（差集），用于失败时指出具体是哪一条。
  List<String> get unaccountedLegacyKeys {
    final accounted = ledgerKeys.toSet();
    return legacyKeys.where((key) => !accounted.contains(key)).toList();
  }

  Map<String, Object?> toJson() => {
    'foods': foodCount,
    'complete_foods': completeFoodCount,
    'foods_without_active_revision': foodsWithoutActiveRevision,
    'revisions': revisionCount,
    'dish_library': dishLibraryCount,
    'dish_basis': dishBasisCounts,
    'dish_trusted_serving': dishTrustedServingCount,
    'dish_assumed_serving': dishAssumedServingCount,
    'menu_items': menuItemCount,
    'menu_items_linked': linkedMenuItemCount,
    'menu_items_analyzable': menuItemAnalyzableCount,
    'menu_items_range_only': menuItemRangeOnlyCount,
    'menu_items_unknown_serving': menuItemUnknownServingCount,
    'meals': mealCount,
    'meal_items': mealItemCount,
    'meal_snapshot_digest': mealSnapshotDigest,
    'media_paths': mediaPaths,
    'legacy_keys': legacyKeys,
    'ledger_keys': ledgerKeys,
    'pending_completion_keys': pendingCompletionKeys,
    'every_legacy_key_accounted': everyLegacyKeyAccounted,
  };
}

abstract final class NutritionInventoryReader {
  /// 读一遍库，产出盘点报告。**不写任何一行。**
  static Future<NutritionInventory> read(AppDatabase database) async {
    final foods = await database.select(database.foods).get();
    final revisions = await database
        .select(database.foodNutritionRevisions)
        .get();
    final dishes = await database.select(database.dishLibrary).get();
    final menuItems = await database.select(database.menuItems).get();
    final evidence = await database
        .select(database.menuItemNutritionEvidence)
        .get();
    final ledger = await database.select(database.legacyEntityMappings).get();
    final meals = await database.select(database.meals).get();
    final mealItems = await database.select(database.mealItems).get();

    final latestEvidence = <String, MenuItemNutritionEvidenceData>{};
    for (final row in evidence) {
      final current = latestEvidence[row.menuItemId];
      if (current == null || row.createdAt.isAfter(current.createdAt)) {
        latestEvidence[row.menuItemId] = row;
      }
    }

    final completeFoods = foods
        .where(
          (row) => isCompleteNutrition(
            kcalPer100g: row.kcalPer100g,
            proteinPer100g: row.proteinPer100g,
            carbsPer100g: row.carbsPer100g,
            fatPer100g: row.fatPer100g,
          ),
        )
        .length;

    final dishBasis = <String, int>{};
    var trustedServing = 0;
    var assumedServing = 0;
    for (final row in dishes) {
      dishBasis.update(
        row.nutritionBasis,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
      final grams = row.servingGrams;
      if (row.basisAssumed ||
          grams == null ||
          !grams.isFinite ||
          grams <= 0 ||
          grams > NutritionLimits.maxServingGrams) {
        assumedServing++;
      } else {
        trustedServing++;
      }
    }

    var analyzable = 0;
    var rangeOnly = 0;
    for (final item in menuItems) {
      final row = latestEvidence[item.id];
      if (row == null) continue;
      if (isCompleteNutrition(
        kcalPer100g: row.kcalPer100g,
        proteinPer100g: row.proteinPer100g,
        carbsPer100g: row.carbsPer100g,
        fatPer100g: row.fatPer100g,
      )) {
        analyzable++;
      } else if (row.kcalMin != null || row.kcalMax != null) {
        rangeOnly++;
      }
    }

    final media = <String>{
      for (final row in dishes)
        if (row.imagePath != null && row.imagePath!.isNotEmpty) row.imagePath!,
      for (final row in menuItems)
        if (row.imagePath != null && row.imagePath!.isNotEmpty) row.imagePath!,
    }.toList()..sort();

    final legacyKeys = <String>[
      for (final row in dishes) 'dish_library:${row.id}',
      for (final row in menuItems)
        if (row.foodId == null) 'menu_item:${row.id}',
    ]..sort();

    final ledgerKeys = <String>[
      for (final row in ledger) '${row.legacyKind}:${row.legacyId}',
    ]..sort();

    final pending = <String>[
      for (final row in ledger)
        if (row.outcome != LegacyOutcome.converted.storedValue &&
            row.outcome != LegacyOutcome.reused.storedValue)
          '${row.legacyKind}:${row.legacyId}',
    ]..sort();

    return NutritionInventory(
      foodCount: foods.length,
      completeFoodCount: completeFoods,
      foodsWithoutActiveRevision: foods
          .where((row) => row.currentRevisionId == null)
          .length,
      revisionCount: revisions.length,
      dishLibraryCount: dishes.length,
      dishBasisCounts: dishBasis,
      dishTrustedServingCount: trustedServing,
      dishAssumedServingCount: assumedServing,
      menuItemCount: menuItems.length,
      linkedMenuItemCount: menuItems.where((row) => row.foodId != null).length,
      menuItemAnalyzableCount: analyzable,
      menuItemRangeOnlyCount: rangeOnly,
      menuItemUnknownServingCount: menuItems
          .where((row) => row.servingGramsStatus == 'unknown')
          .length,
      mealCount: meals.length,
      mealItemCount: mealItems.length,
      mealSnapshotDigest: mealSnapshotDigestOf(meals, mealItems),
      mediaPaths: media,
      legacyKeys: legacyKeys,
      ledgerKeys: ledgerKeys,
      pendingCompletionKeys: pending,
    );
  }

  /// 历史餐快照的稳定指纹：**只包含用户可见的历史事实**。
  ///
  /// 名称、日期、实际克数、四项营养快照——这几样在迁移前后必须完全一样；
  /// 来源 id 的兼容映射不在指纹里（映射允许变，快照不许）。
  static String mealSnapshotDigestOf(List<Meal> meals, List<MealItem> items) {
    final mealById = {for (final meal in meals) meal.id: meal};
    final entries = <String>[];
    for (final item in items) {
      final meal = mealById[item.mealId];
      entries.add(
        [
          meal?.localDate ?? '',
          meal?.slot ?? '',
          item.foodNameSnapshot,
          item.grams.toString(),
          item.kcalSnapshot.toString(),
          item.proteinSnapshot.toString(),
          item.carbsSnapshot.toString(),
          item.fatSnapshot.toString(),
        ].join('\u0001'),
      );
    }
    entries.sort();
    return stableContentFingerprint(entries.join('\u0002'));
  }
}
