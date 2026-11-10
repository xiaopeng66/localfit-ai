import 'package:flutter/material.dart';

import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/features/nutrition/domain/dish_record.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart'
    show MealSlot;

/// 菜品展示的稳定视觉映射（从已退役的完整 `DishCard` 中提取）。
///
/// 推荐小图卡与记录弹层仍要“同一道菜长一样”，所以这三件事保留在一个
/// 无状态 helper 里：餐次中文名、按主要宏量选渐变、按主要宏量选图标。
enum MacroAccent { protein, carbs, fat }

abstract final class DishVisuals {
  static MacroAccent dominantMacro(DishRecord dish) {
    final protein = dish.proteinG * 4;
    final carbs = dish.carbsG * 4;
    final fat = dish.fatG * 9;
    if (protein >= carbs && protein >= fat) return MacroAccent.protein;
    if (carbs >= fat) return MacroAccent.carbs;
    return MacroAccent.fat;
  }

  static String mealSlotLabel(String storedValue) =>
      MealSlot.fromStoredValue(storedValue).label;

  static LinearGradient placeholderGradient(
    BuildContext context,
    DishRecord dish,
  ) {
    final c = context.lf;
    final brightness = Theme.of(context).brightness;
    return switch (dominantMacro(dish)) {
      MacroAccent.protein => LfGradients.proteinPlaceholder(c),
      MacroAccent.carbs => LfGradients.mintPlaceholder(brightness),
      MacroAccent.fat => LfGradients.fatPlaceholder(c),
    };
  }

  static IconData placeholderIcon(DishRecord dish) =>
      switch (dominantMacro(dish)) {
        MacroAccent.protein => Icons.egg_alt_outlined,
        MacroAccent.carbs => Icons.rice_bowl_outlined,
        MacroAccent.fat => Icons.set_meal_outlined,
      };
}

/// 菜品图片占位（无照片时的宏量渐变 + 图标，不伪造菜品照片）。
class DishPhotoPlaceholder extends StatelessWidget {
  const DishPhotoPlaceholder({super.key, required this.dish});

  final DishRecord dish;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: DishVisuals.placeholderGradient(context, dish),
      ),
      child: Center(
        child: Icon(
          DishVisuals.placeholderIcon(dish),
          size: 48,
          color: c.primaryForeground.withValues(alpha: 0.6),
        ),
      ),
    );
  }
}
