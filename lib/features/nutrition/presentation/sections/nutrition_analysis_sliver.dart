import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/features/nutrition/application/build_calorie_trend.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/nutrition_analysis_section.dart';
import 'package:localfit_ai/features/progress/application/trend_calculator.dart';

/// 「记录」sub-tab 底部的营养分析 sliver（docs/21 §5.2
/// `nutrition-record-analysis`）。
///
/// 从 `record_tab.dart` 拆出（docs/07 §9.3 的 500 行预算：补置信摘要后
/// 记录页 481→503 行，超预算）。拆出的边界是**语义完整的一块**：分析卡 +
/// 卡与底栏之间的间距，参数只取它自己需要的那几项。
///
/// 阶段 2B 步骤 4：卡尾 `footer` 槽位退场——置信摘要按 A 的
/// `.source-summary` 挪到页级一行（`NutritionRecordSourceSummary`），
/// 分析卡恢复成一件自足的分析件（趋势统计 + 周均 + 达成率）。
class NutritionAnalysisSliver extends StatelessWidget {
  const NutritionAnalysisSliver({
    super.key,
    required this.trend,
    required this.bars,
    this.targetMinKcal,
    this.targetMaxKcal,
  });

  final IntakeTrend trend;
  final CalorieTrendBars bars;
  final double? targetMinKcal;
  final double? targetMaxKcal;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        // 顶距 16 = A 的页级间隙：旧装配是 0，分析卡的边框直接贴在最后一张
        // 槽位卡的边框上（阶段 2B 步骤 6 审看发现的缺陷 ⑦）。
        padding: const EdgeInsets.fromLTRB(
          LfDimens.pagePadding,
          LfDimens.pagePadding,
          LfDimens.pagePadding,
          LfDimens.spaceMedium,
        ),
        child: NutritionAnalysisSection(
          trend: trend,
          bars: bars,
          targetMinKcal: targetMinKcal,
          targetMaxKcal: targetMaxKcal,
        ),
      ),
    );
  }
}
