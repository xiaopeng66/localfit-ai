import 'package:flutter/material.dart';

import 'package:localfit_ai/app/design/widgets/lf_energy_card.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';

/// 今日页热量卡（docs/21 §5.1 CalorieRingCard → Round7 A `.energy-summary`）。
///
/// 2026-10-14（阶段 2A）：卡体整体换成两页共用的 [LfEnergyCard]——A 的
/// `app.js` 里今日页与记录页画的是同一个 `energy()`，形状、文案、脚注
/// （目标 / 还可摄入）都只有一份实现。本类只负责今日页的锚点与标题：
/// 标题「今日营养」、卡 Key `dashboard-calorie-ring`、环内前缀 `dashboard-ring`、
/// 脚注剩余额度行沿用历史 Key `dashboard-remaining-line`、占比行
/// `dashboard-macro-ratios`、状态 pill `dashboard-ring-status`。
///
/// 状态 pill 的**火苗图标已删**（阶段 2B D20）：A 的 `.pill` 只有文字，图标是
/// 自绘件加的装饰；同一处补上了超目标的换挡（honey 底），见
/// [LfEnergyCard.statusVariant]。
class DashboardCalorieCard extends StatelessWidget {
  const DashboardCalorieCard({
    super.key,
    required this.consumed,
    required this.target,
  });

  final NutritionValues consumed;

  /// null = 未设定目标：靶标位置诚实显示「尚未设定目标」，不编数字。
  final DailyNutritionTarget? target;

  /// 宏量占比（4/4/9 kcal/g）。无可计算总量时返回 null（全 0 摄入）。
  static (int protein, int carbs, int fat)? macroRatios(
    NutritionValues consumed,
  ) => LfEnergyCard.macroRatios(consumed);

  /// 圆环状态徽标（A `status`）。
  static String statusLabel({
    required double consumedKcal,
    double? targetKcal,
  }) => LfEnergyCard.statusLabel(
    consumedKcal: consumedKcal,
    targetKcal: targetKcal,
  );

  @override
  Widget build(BuildContext context) => LfEnergyCard(
    consumed: consumed,
    target: target,
    title: '今日营养',
    cardKey: const Key('dashboard-calorie-ring'),
    keyPrefix: 'dashboard-ring',
    remainingKey: const Key('dashboard-remaining-line'),
    ratiosKey: const Key('dashboard-macro-ratios'),
    statusKey: const Key('dashboard-ring-status'),
  );
}
