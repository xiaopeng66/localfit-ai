import 'package:localfit_ai/features/nutrition/data/dish_library_repository.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/data/supply_catalog_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/dish_record.dart';
import 'package:localfit_ai/features/nutrition/domain/food_record.dart';

/// 主食物 + 食堂供应 + 旧菜品库的**统一检索**（docs/67 §6.4）。
///
/// 三个选食物入口（食物库、记餐、食堂新建供应）共用同一个身份查询：
/// * 主食物 → 按克记；
/// * 供应 → 按"份"或"克"记，并带上窗口与份量；
/// * 旧菜品 → 只读兼容，按旧每份口径（份量不可信时要补全）。
///
/// 排序策略可以各自不同，但**归一化口径只有一份**（`normalizeSearchText`）。
final class CatalogSearch {
  const CatalogSearch({
    required this.foods,
    required this.dishes,
    this.supplies,
  });

  final FoodRepository foods;

  /// 旧菜品库：只读兼容。新流程不再往这里写（docs/67 P2-U23）。
  final DishLibraryRepository? dishes;

  /// 食堂供应：与主食物同一主库的不同投影。
  final SupplyCatalogRepository? supplies;

  Future<CatalogSearchResult> search(String query, {int dishLimit = 20}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return const CatalogSearchResult(foods: [], dishes: [], supplies: []);
    }
    final foodHits = await foods.search(trimmed, limit: 10);
    final dishRepo = dishes;
    final dishHits = dishRepo == null
        ? const <DishRecord>[]
        : await dishRepo.searchByName(trimmed, limit: dishLimit);
    final supplyHits =
        await supplies?.search(trimmed, limit: dishLimit) ??
        const <SupplyCatalogItem>[];
    return CatalogSearchResult(
      foods: foodHits,
      dishes: dishHits,
      supplies: supplyHits
          .where((item) => item.isAnalyzable)
          .toList(growable: false),
    );
  }
}

final class CatalogSearchResult {
  const CatalogSearchResult({
    required this.foods,
    required this.dishes,
    this.supplies = const [],
  });

  final List<FoodRecord> foods;
  final List<DishRecord> dishes;

  /// 有完整营养的食堂供应（待分析的供应不在记餐搜索里出现）。
  final List<SupplyCatalogItem> supplies;

  bool get isEmpty => foods.isEmpty && dishes.isEmpty && supplies.isEmpty;
}
