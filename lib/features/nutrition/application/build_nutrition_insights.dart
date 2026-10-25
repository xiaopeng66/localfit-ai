import 'package:localfit_ai/features/nutrition/application/build_calorie_trend.dart';
import 'package:localfit_ai/features/progress/application/trend_calculator.dart';

/// 营养分析卡的一条洞察。
final class NutritionInsight {
  const NutritionInsight({required this.text, required this.tone});

  final String text;
  final InsightTone tone;
}

/// 洞察的彩点色档（docs/21 §5.2「3 条彩点洞察文本」）：
/// 中性 = primary、需要留意 = warning、结构占比 = fat 色。
enum InsightTone { neutral, warning, macro }

/// 近 7 日摄入 + 目标 → 最多 3 条洞察（docs/21 §5.2 NutritionAnalysisCard）。
///
/// **每条都必须是本地事实的复述**，不是通用健康建议：设计稿那三条
/// （「蛋白质摄入稳定，周均达标率 92%」等）是 demo 文案，数值与结论都
/// 不可用（§6.1 诚实规则）。这里只做可复算的陈述：
///
///  * 周均摄入 vs 目标区间（有目标才说）；
///  * 达标天数（有目标才说）；
///  * 三大宏量的热量占比（有摄入才说）。
///
/// 数据不足时**返回更少的条目**，宁可只有一条也不补话。
List<NutritionInsight> buildNutritionInsights({
  required IntakeTrend trend,
  required CalorieTrendBars bars,
  double? targetMinKcal,
  double? targetMaxKcal,
}) {
  final insights = <NutritionInsight>[];
  final average = trend.averageKcal;
  final hitCount = bars.hitCount;
  final tracked = trend.trackedDays;

  // ① 周均摄入。分母写 trackedDays 而不是 7：只记了 2 天时说「周均」会把
  // 没记录的日子当成 0 摄入算进去，那是编数字。
  if (average != null && tracked > 0) {
    insights.add(
      NutritionInsight(
        text: targetMaxKcal == null
            ? '近 7 日有 $tracked 天记录，日均摄入 ${average.round()} kcal。'
            : '近 7 日有 $tracked 天记录，日均摄入 ${average.round()} kcal'
                  '（目标 ${targetMinKcal?.round() ?? 0}–'
                  '${targetMaxKcal.round()} kcal）。',
        tone: InsightTone.neutral,
      ),
    );
  }

  // ② 达标天数（未超上限）+ 低于下限的天数。
  //
  // 2026-10-23 用户：「今日达标但没变 0/7」。达标改按「未超上限」判定后，
  // 这句话必须把两件事都说清：多少天没超上限、多少天低于下限——只报前者
  // 会把「吃太少」说成达标，只报后者又会让人以为没有达标日。
  final belowMin = bars.belowMinCount;
  if (hitCount != null && tracked > 0) {
    final lowNote = (belowMin != null && belowMin > 0)
        ? '，另有 $belowMin 天低于目标下限'
              ' ${targetMinKcal?.round() ?? 0} kcal（未超上限，但可能吃太少）'
        : '';
    insights.add(
      NutritionInsight(
        text: '其中 $hitCount 天摄入未超过目标上限$lowNote。',
        tone: (belowMin != null && belowMin > 0) || hitCount * 2 < tracked
            ? InsightTone.warning
            : InsightTone.neutral,
      ),
    );
  }

  // ③ 宏量热量占比（4/4/9）。占比是按**实际摄入总量**算的，与目标无关，
  // 所以无目标也能给。
  final macros = trend.averageMacros;
  if (macros != null && average != null && average > 0) {
    final proteinKcal = macros.proteinGrams * 4;
    final carbsKcal = macros.carbsGrams * 4;
    final fatKcal = macros.fatGrams * 9;
    final total = proteinKcal + carbsKcal + fatKcal;
    if (total > 0) {
      // 脂肪取余数，保证三项之和恒为 100（四舍五入不会出现 99/101）。
      final protein = (proteinKcal / total * 100).round();
      final carbs = (carbsKcal / total * 100).round();
      final fat = (100 - protein - carbs).clamp(0, 100);
      insights.add(
        NutritionInsight(
          text: '三大宏量热量占比：蛋白质 $protein%、碳水 $carbs%、脂肪 $fat%。',
          tone: InsightTone.macro,
        ),
      );
    }
  }

  return List.unmodifiable(insights.take(3));
}
