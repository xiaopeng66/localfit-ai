import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/features/dashboard/domain/next_meal_slot.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';

/// 2026-10-31 用户口径：「下一餐不能永远显示晚餐，要按系统时间动态判断」——
/// 0–9 早餐、9–14 午餐、14–20 晚餐、20–次日 0 点加餐。
///
/// 判据是**边界**：四个区间的接缝（09:00 / 14:00 / 20:00 / 次日 00:00）各测
/// 两侧一分钟，区间内部各测一处。用 `DateTime` 而不是 `TimeOfDay`：真实调用
/// 方拿到的是 `now`，这里同构。
void main() {
  MealSlot slotAt(int hour, [int minute = 0]) =>
      nextMealSlotFor(DateTime(2026, 10, 31, hour, minute));

  group('nextMealSlotFor：四个时段（左闭右开）', () {
    test('00:00 是早餐（新一天从早餐开始）', () {
      expect(slotAt(0), MealSlot.breakfast);
    });

    test('08:59 仍是早餐，09:00 切到午餐', () {
      expect(slotAt(8, 59), MealSlot.breakfast);
      expect(slotAt(9), MealSlot.lunch);
    });

    test('13:59 仍是午餐，14:00 切到晚餐', () {
      expect(slotAt(13, 59), MealSlot.lunch);
      expect(slotAt(14), MealSlot.dinner);
    });

    test('19:59 仍是晚餐，20:00 切到加餐', () {
      expect(slotAt(19, 59), MealSlot.dinner);
      expect(slotAt(20), MealSlot.snack);
    });

    test('23:59 是加餐（20 点–次日 0 点）', () {
      expect(slotAt(23, 59), MealSlot.snack);
    });

    test('区间内部各取一处', () {
      expect(slotAt(3, 30), MealSlot.breakfast);
      expect(slotAt(11, 15), MealSlot.lunch);
      expect(slotAt(17, 45), MealSlot.dinner);
      expect(slotAt(21, 10), MealSlot.snack);
    });
  });
}
