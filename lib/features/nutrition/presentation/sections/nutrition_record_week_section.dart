import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/widgets/lf_top_bar.dart';
import 'package:localfit_ai/features/nutrition/application/build_calorie_trend.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/nutrition_record_selected_date.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/nutrition_record_week_strip.dart';

/// 记录页的「本周」区块（A：`.date-strip` → `.selected-date` 两件紧邻）。
///
/// 从 `record_tab.dart` 提出来的原因只是行数预算（docs/07 §9.3 每文件
/// ≤ 500 行）——组成与 A 一致：
///
///  * [NutritionRecordWeekStrip] 恒渲染（它是切换日期的主入口）；
///  * 「复用历史餐食」入口（设计稿未画，按裁决 ② 保留逻辑，收在周条右侧的
///    工具位；取消全局 AppBar 后它没有别处可放）；
///  * [NutritionRecordSelectedDate] 紧贴周条之下（A 的 16px 页间隙减去
///    `margin-top:-8px`，实为 8dp）。
///
/// 滑动切周的手势只覆盖周条本身，不含这一行日期文案。
class NutritionRecordWeekSection extends StatelessWidget {
  const NutritionRecordWeekSection({
    super.key,
    required this.bars,
    required this.selectedDate,
    required this.now,
    required this.onSelect,
    this.onReuseHistory,
  });

  final CalorieTrendBars bars;
  final DateTime selectedDate;
  final DateTime now;
  final ValueChanged<DateTime> onSelect;

  /// 为 null 时不渲染复用入口（该入口本身是可选的页面动作）。
  final VoidCallback? onReuseHistory;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: NutritionRecordWeekStrip(
              bars: bars,
              selectedDate: selectedDate,
              now: now,
              onSelect: onSelect,
            ),
          ),
          if (onReuseHistory != null)
            LfCircleIconButton(
              key: const Key('meal-reuse-history'),
              tooltip: '复用历史餐食',
              icon: Icons.history,
              onPressed: onReuseHistory,
            ),
        ],
      ),
      const SizedBox(height: LfDimens.spaceSmall),
      NutritionRecordSelectedDate(selectedDate: selectedDate, now: now),
    ],
  );
}
