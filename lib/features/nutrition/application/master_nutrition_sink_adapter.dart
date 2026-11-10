import 'package:localfit_ai/features/campus_menus/domain/master_nutrition_sink.dart';
import 'package:localfit_ai/features/nutrition/application/food_catalog_service.dart';

/// 把食堂域的营养批准接到统一主库（docs/67 §3.2）。
///
/// 只有这一条实现：食堂证据行保留为**分析记录**，当前营养写进主食物修订。
/// 这样"食堂编辑器"和"主库编辑器"改的是同一个生效位置，不会各存一套。
final class CatalogMasterNutritionSink implements MasterNutritionSink {
  const CatalogMasterNutritionSink(this.catalog);

  final FoodCatalogService catalog;

  @override
  Future<String?> createMasterFromAnalysis({
    required String displayName,
    required ApprovedPer100g values,
    required String origin,
    required bool isEstimated,
    String? rawValuesJson,
  }) => catalog.createMasterFood(
    name: displayName,
    kcalPer100g: values.kcalPer100g,
    proteinPer100g: values.proteinPer100g,
    carbsPer100g: values.carbsPer100g,
    fatPer100g: values.fatPer100g,
    origin: origin,
    isEstimated: isEstimated,
  );

  @override
  Future<void> applyApprovedNutrition({
    required String foodId,
    required ApprovedPer100g values,
    required String origin,
    required bool isEstimated,
    String? rawValuesJson,
  }) async {
    await catalog.reviseMasterFood(
      foodId: foodId,
      kcalPer100g: values.kcalPer100g,
      proteinPer100g: values.proteinPer100g,
      carbsPer100g: values.carbsPer100g,
      fatPer100g: values.fatPer100g,
      origin: origin,
      isEstimated: isEstimated,
    );
  }
}
