import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/widgets/app_sheet.dart';
import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart';
import 'package:localfit_ai/features/campus_menus/presentation/canteen_dish_actions_sheet.dart';
import 'package:localfit_ai/features/campus_menus/presentation/manual_nutrition_sheet.dart';

/// 菜品动作弹层（docs/21 §3.6）：改名 / AI 分析 / 手动营养 / 删除。
/// 从 [MenuTabView] 拆出（500 行预算）；写操作外壳（忙态/错误文案）由
/// [onManualNutrition] / [forms] 的宿主继续承担。
Future<void> showCanteenDishActions(
  BuildContext context,
  CanteenDish dish, {
  required CanteenRepository repository,
  required Future<void> Function(List<CanteenDish> dishes)? onAnalyze,
  required Future<void> Function(CanteenDish dish) onManualNutrition,
  required Future<void> Function(Future<void> Function() action) runWrite,
  required bool Function() isMounted,
  required Future<void> Function(CanteenDish dish) onEdit,
  required Future<void> Function(CanteenDish dish) onDelete,
}) async {
  // 裸 `showModalBottomSheet` → `AppSheet.show`：拿回共享弹层的把手/圆角/
  // 动效与标题排印；动作闭包用 `Builder` 取弹层内 context 弹出（弹层挂在
  // 根导航器上，见 AppSheet 的注释）。
  final action = await AppSheet.show<String>(
    context,
    title: dish.name,
    content: Text(
      dish.hasNutrition
          ? '${dish.kcalPer100g!.toStringAsFixed(0)} kcal/100g · '
                '${dish.evidenceGrade} 级'
          : '未分析营养',
    ),
    actions: CanteenDishActionsSheet(
      showAnalyze: !dish.hasNutrition && onAnalyze != null,
    ),
  );
  if (action == null) return;
  switch (action) {
    case 'edit':
      await onEdit(dish);
    case 'analyze':
      await onAnalyze!([dish]);
    case 'manual':
      await onManualNutrition(dish);
    case 'delete':
      await onDelete(dish);
  }
}

/// D10（docs/41 §7「无 AI 可用」）：手动填写每 100g（origin=user_input）。
/// AI 不可用时这是唯一营养来源；有 AI 时也可覆盖（用户手填最权威）。
Future<void> showManualNutritionSheet(
  BuildContext context,
  CanteenDish dish, {
  required CanteenRepository repository,
  required Future<void> Function(Future<void> Function() action) runWrite,
}) {
  return ManualNutritionSheet.show(
    context,
    dish: dish,
    onSubmit: (kcal, protein, carbs, fat) async {
      await runWrite(() async {
        await repository.recordNutrition(
          dishId: dish.id,
          kcalPer100g: kcal,
          proteinPer100g: protein,
          carbsPer100g: carbs,
          fatPer100g: fat,
          grade: 'D',
          confidence: 1.0,
          origin: 'user_input',
          sourceText: '用户手动填写',
        );
      });
      // 写失败时已由外壳就地弹过 AppSnackBar；返回 null 让弹层关闭（成功路径）。
      return null;
    },
  );
}
