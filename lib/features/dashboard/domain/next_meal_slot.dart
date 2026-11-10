import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';

/// 「下一餐是哪一餐」的唯一口径（2026-10-31 用户口径）。
///
/// 用户原话：**下一餐不能永远显示晚餐，要按系统时间动态判断**——
/// 0–9 点早餐、9–14 点午餐、14–20 点晚餐、20 点–次日 0 点加餐。
///
/// 边界全部**左闭右开**，与用户给的半开区间一一对应：
///
/// | 时刻 | 餐次 |
/// |---|---|
/// | 00:00–08:59 | 早餐 |
/// | 09:00–13:59 | 午餐 |
/// | 14:00–19:59 | 晚餐 |
/// | 20:00–23:59 | 加餐 |
///
/// 为什么不复用 `build_daily_meal_recommendation` 的 `_mealBands`：那套是
/// **食堂供应窗口**的分界（09:30 / 14:00 / 20:30，且没有加餐），回答的是
/// 「这一餐的窗口还开着吗」；这里回答的是「现在该吃哪一餐」。两者混用会
/// 让 09:15 的今日页写「下一餐 · 早餐」（窗口已关）。
///
/// 纯函数、无 Flutter、无时钟依赖：时刻由调用方给（`DashboardPage.now`），
/// 所以边界可穷举测试，测试也不需要假装系统时间。
MealSlot nextMealSlotFor(DateTime now) {
  final minute = now.hour * 60 + now.minute;
  if (minute < 9 * 60) return MealSlot.breakfast;
  if (minute < 14 * 60) return MealSlot.lunch;
  if (minute < 20 * 60) return MealSlot.dinner;
  return MealSlot.snack;
}
