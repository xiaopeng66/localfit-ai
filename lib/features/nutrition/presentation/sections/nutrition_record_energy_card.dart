import 'package:flutter/material.dart';

import 'package:localfit_ai/app/design/widgets/lf_energy_card.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';

/// 饮食·记录页顶部卡（Round7 A `energy(ui.date)`；阶段 2B **D10**）。
///
/// A 的记录页与今日页画的是**同一个 `energy()`**，唯一的差别是标题：
/// `app.js` 里 `energy(date)` 的标题按 `date === today ? '今日' : '当日'` 选词。
/// 阶段 2A 已把卡体收敛成两页共享的 [LfEnergyCard]，本类只负责记录页那一侧的
/// 锚点与标题（与今日页的 `DashboardCalorieCard` 对称）：
///
///  * 标题「今日营养 / 当日营养」——由 `selectedDate` 与 `now` 现场判，规则只此一处；
///  * 卡 Key `nutrition-record-energy`、环内前缀 `nutrition-record-energy`
///    （`-consumed` / `-percent` / `-target`）、脚注剩余行 `-remaining`、
///    占比行 `-ratios`、状态 pill `-status`。
///
/// **被它取代的旧件**（`NutritionRecordHero`，2B 退役）：标题「饮食记录」+
/// 日期 + 三段统计 + 达成度进度条。三段统计与百分比是**同一批事实**，现在落在
/// 环心（已摄入 / 百分比）、脚注（目标 / 还可摄入）与状态 pill 上——A 里记录页
/// 本来就没有第二张统计卡，页首日期也改用 `.selected-date` 一行（strip 之下），
/// 所以旧件不是「被藏起来」而是被这一件吃掉了。诚实规则随卡体一起继承：
/// 无目标不充弧、不编百分比、脚注写「尚未设定目标 / 设置目标后查看进度」。
class NutritionRecordEnergyCard extends StatelessWidget {
  const NutritionRecordEnergyCard({
    super.key,
    required this.consumed,
    required this.target,
    required this.selectedDate,
    required this.now,
  });

  final NutritionValues consumed;

  /// null = 未设定目标（`DailyTargets` 无当前生效行）。
  final DailyNutritionTarget? target;

  /// 页面当前选中的那一天（历史日 ⇒ 标题「当日营养」）。
  final DateTime selectedDate;

  /// 应用时钟的「今天」（A 的 `date === today` 判据；注入而不是读真钟，
  /// 与页面其余部分同一份时钟）。
  final DateTime now;

  @override
  Widget build(BuildContext context) => LfEnergyCard(
    consumed: consumed,
    target: target,
    title: DateUtils.isSameDay(selectedDate, now) ? '今日营养' : '当日营养',
    cardKey: const Key('nutrition-record-energy'),
    keyPrefix: 'nutrition-record-energy',
    remainingKey: const Key('nutrition-record-energy-remaining'),
    ratiosKey: const Key('nutrition-record-energy-ratios'),
    statusKey: const Key('nutrition-record-energy-status'),
  );
}
