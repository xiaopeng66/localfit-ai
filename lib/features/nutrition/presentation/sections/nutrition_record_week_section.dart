import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/features/nutrition/application/build_calorie_trend.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/nutrition_record_selected_date.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/nutrition_record_week_strip.dart';

/// 记录页的「本周」区块（A：`.date-strip` → `.selected-date` 两件紧邻）。
///
/// 从 `record_tab.dart` 提出来的原因只是行数预算（docs/07 §9.3 每文件
/// ≤ 500 行）——组成与 A 一致：
///
///  * [NutritionRecordWeekStrip] 恒渲染（它是切换日期的主入口）；
///  * [NutritionRecordSelectedDate] 紧贴周条之下（A 的 16px 页间隙减去
///    `margin-top:-8px`，实为 8dp）。
///
/// 【2026-10-31 用户：「删除复用历史餐食按钮和功能」】周条右侧那枚历史
/// 圆钮（`meal-reuse-history`）**整枚退役**——历史餐已能在记录页按日期翻到、
/// 整卡点开合并编辑，再开一条「把某天整餐复制到今天」的旁路既多余又容易
/// 记错账。`NutritionActions.reuseMeal` 与弹层保留给其它调用点/测试，
/// 但记录页不再有入口。
///
/// 滑动切周的手势只覆盖周条本身，不含这一行日期文案。
class NutritionRecordWeekSection extends StatelessWidget {
  const NutritionRecordWeekSection({
    super.key,
    required this.bars,
    required this.selectedDate,
    required this.now,
    required this.onSelect,
    this.onBackToToday,
  });

  final CalorieTrendBars bars;
  final DateTime selectedDate;
  final DateTime now;
  final ValueChanged<DateTime> onSelect;

  /// 【N-4】非今天时给「回到今天」入口；null = 不渲染。
  final VoidCallback? onBackToToday;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      NutritionRecordWeekStrip(
        bars: bars,
        selectedDate: selectedDate,
        now: now,
        onSelect: onSelect,
      ),
      const SizedBox(height: LfDimens.spaceSmall),
      NutritionRecordSelectedDate(
        selectedDate: selectedDate,
        now: now,
        onBackToToday: onBackToToday,
      ),
    ],
  );
}
