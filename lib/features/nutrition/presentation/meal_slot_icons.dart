import 'package:flutter/material.dart';

import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';

/// 餐次的图标（Round7 A `app.js:136/167`：`sun` / `bowl` / `moon` / `cup`）。
///
/// A 的四个槽位图标是**固定映射**（早餐太阳 / 午餐碗 / 晚餐月亮 / 加餐杯），
/// 与 A 的记录页槽位卡、今日餐次行共用同一组。放在这里只有一处真相：
/// 今日页餐次行与记录页槽位分组都用它，不要各自再写一遍 switch。
extension MealSlotIcons on MealSlot {
  IconData get icon => switch (this) {
    MealSlot.breakfast => Icons.wb_sunny_outlined,
    MealSlot.lunch => Icons.rice_bowl_outlined,
    MealSlot.dinner => Icons.nightlight_outlined,
    MealSlot.snack => Icons.local_cafe_outlined,
  };
}
