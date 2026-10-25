import 'package:flutter/material.dart';
import 'package:localfit_ai/features/nutrition/data/dish_library_repository.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/dish_record.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';
import 'package:localfit_ai/features/nutrition/presentation/nutrition_actions.dart';

/// 「记一餐」抽屉的**无页面依赖**入口（`RV4-P1-04`，`docs/56` R2 / 方案 B）。
///
/// 【为什么要有这个文件】原来主页「记录晚餐」的入口拥有者选错了：
/// `app_router.onLogMeal` 先写一次性意向再 `go(nutrition)`，由目标页开层。
/// 用户看到的是「被带到饮食页（而且停在食物库 tab）」，退出弹层自然回不去主页。
///
/// 修法是把「开抽屉」这件事从页面状态里抽出来：路由层拿到 shell 的
/// `BuildContext` 直接开层，**不切页**。
///
/// 复用而非复制：内部就是 [NutritionActions.chooseRecordEntry] 那段流程
/// （按食材 / 按菜品两个入口 → 对应的既有弹层 → 既有落库路径）。
/// `NutritionActions` 需要 `context` + `selectedDate()`，所以这里给一份
/// 「今天」的最小实现，**不新增任何写逻辑**。
Future<void> openMealRecordSheet(
  BuildContext context, {
  required FoodRepository foods,
  required MealRepository meals,
  MealSlot? slot,
  DishLibraryRepository? dishes,
  Future<void> Function(DishRecord dish, {MealSlot? slotOverride})? addDish,
}) {
  // 记到「今天」：主页的记录入口是当场决策，不是翻历史日期时的补录
  // （补录走记录页的编辑入口）。
  final today = DateTime.now();
  final date = DateTime(today.year, today.month, today.day);
  final actions = NutritionActions(
    context: context,
    selectedDate: () => date,
    onDateSelected: (_) {},
    dishLibraryRepository: dishes,
    onAddDishToMeal: addDish,
  );
  return actions.chooseRecordEntry(foods, meals, initialSlot: slot);
}
