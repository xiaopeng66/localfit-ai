import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/features/dashboard/presentation/sections/dashboard_confidence_summary.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';

/// 记录页的当日置信摘要行（A `sourceSummary(ui.date)`）。
///
/// A 的整页顺序是 `date-strip → selected-date → energy → source-summary →
/// nutritionTrend → meal-timeline`：摘要是**热量卡之下的一行**，不是卡片
/// （`.source-summary{padding:4px 0}`，4px 由摘要件自己带）。阶段 2B 之前它
/// 挂在分析卡卡尾（`NutritionAnalysisSliver.footer`），2B 步骤 4 按 A 挪到
/// 页级；数据流与空态规则不变：走选中日的餐食流，空列表整条不渲染。
class NutritionRecordSourceSummary extends StatelessWidget {
  const NutritionRecordSourceSummary({
    super.key,
    required this.mealRepository,
    required this.localDate,
  });

  final MealRepository mealRepository;

  /// 选中日期（`yyyy-MM-dd`）：摘要按这一天的餐食计数。
  final String localDate;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LfDimens.pagePadding),
      child: StreamBuilder<List<MealRecord>>(
        stream: mealRepository.watchForDate(localDate),
        builder: (context, snapshot) {
          final meals = snapshot.data ?? const <MealRecord>[];
          // 段间距与内容**同生共死**：空列表整行（含它上方那 16dp）一起退场，
          // 否则零餐的日子会在热量卡与下一段之间凭空多出一段空白
          // （docs/29 §P6 需求 12 量的是真空白，不是「有个 Padding 件」）。
          if (meals.isEmpty) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(top: LfDimens.pagePadding),
            child: DashboardConfidenceSummary(meals: meals),
          );
        },
      ),
    );
  }
}
