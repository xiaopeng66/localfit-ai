/// 食堂供应 → 推荐/菜单卡用的 `DishRecord` 候选（docs/67 §6.5）。
///
/// **只有这一处**做这个映射：本地每日推荐与 AI「换一套」都必须用同一份
/// 每份克数和同一套预算口径。旧实现两边各写一套（一边按菜品库每份值比较
/// 预算，一边把食堂 per100g 当"一份 100g"），于是预览的数字和真正记进去的
/// 数字不是同一个东西。
library;

import 'package:localfit_ai/features/daily_plan/application/menu_service_window.dart'
    show parseHhmmToMinute;
import 'package:localfit_ai/features/nutrition/data/supply_catalog_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/dish_record.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';

/// 把一批供应映射成 `DishRecord`（每份口径）。
///
/// [strict] 语义（docs/67 §6.5 的边界）：
/// * `strict: true`（**AI 自动应用**的候选池）：只接受
///   [SupplyCatalogItem.isAutoRecommendable]——完整营养 + 可信份量 + 未归档；
///   估计份量不进这个池（自动选菜不能拿"约 200g"当可信事实）。
/// * `strict: false`（**本地推荐清单**，用户手动点「加入」）：放宽到
///   「完整营养 + 未归档 + 份量非未知」——估计份量的菜也进清单（显示"约"），
///   因为用户在手动确认这一餐，不存在"静默当事实"的风险。
///   待分析（无营养）与份量未知仍不进清单：没有可显示的每份数。
List<DishRecord> supplyDishCandidates(
  List<SupplyCatalogItem> supplies, {
  required DateTime now,
  bool strict = true,
  bool includePendingAnalysis = false,
}) {
  // 保留 includePendingAnalysis 参数以兼容旧调用；未知值无法诚实地装进
  // 非空数值的 DishRecord。待分析/份量未知由 UI 直接展示 SupplyCatalogItem，
  // 不能用 0 千卡或默认 100g 冒充可计算候选。
  bool eligible(SupplyCatalogItem supply) =>
      supply.foodArchived == false &&
      supply.canRecordByServing &&
      supply.kcalPerServing?.isFinite == true &&
      (!strict || supply.isAutoRecommendable);

  final stamp = now.toUtc();
  return [
    for (final supply in supplies)
      if (eligible(supply))
        DishRecord(
          id: supply.id,
          name: supply.displayName,
          mealSlot: mealSlotForWindow(
            supply.openTime,
            supply.closeTime,
          ).storedValue,
          servingWindow: supply.servingWindow,
          kcal: supply.kcalPerServing!,
          proteinG: _scale(supply.proteinPer100g!, supply.servingGrams!),
          carbsG: _scale(supply.carbsPer100g!, supply.servingGrams!),
          fatG: _scale(supply.fatPer100g!, supply.servingGrams!),
          source: 'canteen',
          imagePath: supply.imagePath,
          servingGrams: supply.servingGrams,
          // 有供应自身的份量，不是拿每 100g 当一份；估计状态由供应行标约。
          basisAssumed: false,
          sourceType: kCanteenSourceType,
          sourceId: supply.foodId,
          createdAt: stamp,
          updatedAt: stamp,
        ),
  ];
}

double _scale(double per100g, double servingGrams) =>
    per100g * servingGrams / 100;

/// 窗口营业时段 → 餐次（延续旧 `AddCanteenDishesToLibrary._mealSlotForWindow`
/// 的判定同源：按**结束时间**归餐，因为窗口是为某一餐开的）。
MealSlot mealSlotForWindow(String openTime, String closeTime) {
  final close = parseHhmmToMinute(closeTime);
  if (close <= 9 * 60 + 30) return MealSlot.breakfast;
  if (close <= 14 * 60) return MealSlot.lunch;
  if (close <= 20 * 60 + 30) return MealSlot.dinner;
  return MealSlot.snack;
}
