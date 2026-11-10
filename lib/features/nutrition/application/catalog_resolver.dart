import 'package:localfit_ai/core/nutrition/nutrition_units.dart';
import 'package:localfit_ai/features/nutrition/data/dish_library_repository.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/data/supply_catalog_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/dish_record.dart';
import 'package:localfit_ai/features/nutrition/domain/food_record.dart';

export 'package:localfit_ai/features/nutrition/application/nutrition_math.dart';

/// 食物 / 食堂供应 / 旧菜品的**唯一解析入口**（docs/67 §6.4）。
///
/// 输入：`[food:id]`、`[canteen-dish:id]`、`[dish:id]`、或精确名字。
/// 输出：主食物 / 供应 / 旧菜品 / 歧义 / 缺失 / 需要先分析。
///
/// **[canteen-dish:] 永远指供应，不偷换成主食物**（docs/67 §3.4）：它的营养
/// 从供应所链主食物的生效修订派生，每份克数来自供应自己。**旧 [dish:] 保持
/// 原来的每份语义**，不会被当成每 100g。
sealed class CatalogResolution {
  const CatalogResolution();
}

final class CatalogFood extends CatalogResolution {
  const CatalogFood(this.food);
  final FoodRecord food;
}

/// 一条食堂供应（已链接主食物且营养完整）。
final class CatalogSupply extends CatalogResolution {
  const CatalogSupply(this.supply);

  final SupplyCatalogItem supply;

  String get supplyId => supply.id;
  String get displayName => supply.displayName;
  String? get foodId => supply.foodId;
  double get kcalPer100g => supply.kcalPer100g!;
  double get proteinPer100g => supply.proteinPer100g!;
  double get carbsPer100g => supply.carbsPer100g!;
  double get fatPer100g => supply.fatPer100g!;
  double? get servingGrams => supply.servingGrams;
  ServingGramsStatus get servingGramsStatus => supply.servingGramsStatus;
  ServingGramsSource get servingGramsSource => supply.servingGramsSource;
  String? get revisionId => supply.revisionId;
  bool get canRecordByServing => supply.canRecordByServing;
}

/// 旧菜品库条目（每份口径）。**只为兼容旧引用保留**，新流程不再产生。
final class CatalogLegacyDish extends CatalogResolution {
  const CatalogLegacyDish(this.dish);
  final DishRecord dish;

  /// 旧口径能否按克解释：需要可信的每份克数。
  bool get hasTrustedServingGrams =>
      !dish.basisAssumed && dish.servingGrams != null && dish.servingGrams! > 0;
}

/// 旧名字：`CatalogDish` 现在明确是"旧菜品库条目（每份口径）"。
/// 保留别名是为了不改动只做模式匹配的调用方。
typedef CatalogDish = CatalogLegacyDish;

/// 同一个名字在主库/旧菜品库都有，或一个库里有多条同名。
final class CatalogAmbiguous extends CatalogResolution {
  const CatalogAmbiguous({
    required this.reference,
    required this.foods,
    required this.dishes,
    this.supplies = const [],
  });

  final String reference;
  final List<FoodRecord> foods;
  final List<DishRecord> dishes;

  /// 同名供应也进候选——但它们在 UI 上是"某窗口的一份"，不是重复行。
  final List<SupplyCatalogItem> supplies;
}

final class CatalogMissing extends CatalogResolution {
  const CatalogMissing(this.reference);
  final String reference;
}

/// 供应存在但还没有可用营养（未链接主食物 / 四项不齐）。
final class CatalogNeedsAnalysis extends CatalogResolution {
  const CatalogNeedsAnalysis(this.menuItemId);
  final String menuItemId;
}

/// 同名候选清单（选择卡的数据源）。
final class CatalogCandidates {
  const CatalogCandidates({
    required this.reference,
    required this.foods,
    required this.dishes,
    this.supplies = const [],
  });

  /// 用户原话里的引用（选择卡标题用）。
  final String reference;
  final List<FoodRecord> foods;
  final List<DishRecord> dishes;
  final List<SupplyCatalogItem> supplies;

  bool get isEmpty => foods.isEmpty && dishes.isEmpty && supplies.isEmpty;
}

final class CatalogResolver {
  const CatalogResolver({
    required this.foods,
    required this.dishes,
    this.supplies,
  });

  final FoodRepository foods;
  final DishLibraryRepository dishes;

  /// 供应读取口；测试里可以只给食物/旧菜品（旧解析行为不变）。
  final SupplyCatalogRepository? supplies;

  static final RegExp _prefixed = RegExp(
    r'^\[(food|dish|canteen-dish):([^\]]+)\]$',
  );

  Future<CatalogResolution> resolve(String reference) async {
    final raw = reference.trim();
    if (raw.isEmpty) return const CatalogMissing('');

    final match = _prefixed.firstMatch(raw);
    if (match != null) {
      final kind = match.group(1)!;
      final id = match.group(2)!.trim();
      switch (kind) {
        case 'food':
          final food = await foods.getById(id);
          return food == null ? CatalogMissing(raw) : CatalogFood(food);
        case 'dish':
          // 旧卡片里的 [dish:] 保持"每份"语义；不因为主库统一就把值当每 100g。
          final dish = await dishes.getById(id);
          return dish == null ? CatalogMissing(raw) : CatalogLegacyDish(dish);
        case 'canteen-dish':
          final supply = await supplies?.getById(id);
          if (supply == null) {
            // 没有供应读取口时退回旧映射（只读兼容），但单位仍是"每份"。
            final dish = await dishes.findBySource(
              sourceType: kCanteenSourceType,
              sourceId: id,
            );
            return dish == null
                ? CatalogNeedsAnalysis(id)
                : CatalogLegacyDish(dish);
          }
          return supply.isAnalyzable
              ? CatalogSupply(supply)
              : CatalogNeedsAnalysis(id);
      }
    }

    // 身份优先：**裸 id 也是身份**。快照里给的是 `[canteen-dish:x]`，但模型
    // 有时只抄了 `x`；`x` 是稳定主键、不是名字，精确命中就该认（名字才需要
    // 走后面的候选判定）。顺序固定：食物 id → 供应 id → 旧菜品 id。
    final byFoodId = await foods.getById(raw);
    if (byFoodId != null) return CatalogFood(byFoodId);
    final bySupplyId = await supplies?.getById(raw);
    if (bySupplyId != null) {
      return bySupplyId.isAnalyzable
          ? CatalogSupply(bySupplyId)
          : CatalogNeedsAnalysis(bySupplyId.id);
    }
    final byDishId = await dishes.getById(raw);
    if (byDishId != null) return CatalogLegacyDish(byDishId);

    final foodMatches = await foods.searchExact(raw);
    final dishMatches = await dishes.searchExact(raw);
    final supplyMatches = await supplies?.search(raw, limit: 10) ?? const [];
    final analyzableSupplies = supplyMatches
        .where((item) => item.isAnalyzable)
        .toList(growable: false);

    if (foodMatches.length == 1 &&
        dishMatches.isEmpty &&
        analyzableSupplies.isEmpty) {
      return CatalogFood(foodMatches.single);
    }
    if (dishMatches.length == 1 &&
        foodMatches.isEmpty &&
        analyzableSupplies.isEmpty) {
      return CatalogLegacyDish(dishMatches.single);
    }
    if (foodMatches.isEmpty && dishMatches.isEmpty && supplyMatches.isEmpty) {
      return CatalogMissing(raw);
    }
    // 无前缀的名字只给候选，**不挑第一条**——名字不裁定身份（D11）。
    return CatalogAmbiguous(
      reference: raw,
      foods: foodMatches,
      dishes: dishMatches,
      supplies: analyzableSupplies,
    );
  }
}
