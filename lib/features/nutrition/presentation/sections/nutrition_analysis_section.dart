import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/design_card.dart';
import 'package:localfit_ai/features/nutrition/application/build_calorie_trend.dart';
import 'package:localfit_ai/features/nutrition/application/build_nutrition_insights.dart';
import 'package:localfit_ai/features/progress/application/trend_calculator.dart';

/// 近 7 日营养分析卡（docs/21 §5.2 `nutrition-record-analysis`）。
///
/// 三格统计（周均摄入 / 目标达成率 / 达标天数）+ 最多 3 条彩点洞察。
/// 每一格在**数据不存在时写占位**而不是 0：没设目标时达成率与达标天数都
/// 无定义，写「—」。整卡在完全无记录时由调用方跳过，不渲染一张全占位卡。
class NutritionAnalysisSection extends StatelessWidget {
  const NutritionAnalysisSection({
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

  /// 达成率：日均摄入 / 目标上限。无目标或目标为 0 时返回 null。
  static int? achievementPercent({
    required double? averageKcal,
    double? targetMaxKcal,
  }) {
    if (averageKcal == null || targetMaxKcal == null || targetMaxKcal <= 0) {
      return null;
    }
    return (averageKcal / targetMaxKcal * 100).round();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final mint = LfColors.mint(Theme.of(context).brightness);
    final percent = achievementPercent(
      averageKcal: trend.averageKcal,
      targetMaxKcal: targetMaxKcal,
    );
    final insights = buildNutritionInsights(
      trend: trend,
      bars: bars,
      targetMinKcal: targetMinKcal,
      targetMaxKcal: targetMaxKcal,
    );

    return DesignCard(
      key: const Key('nutrition-record-analysis'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, size: LfDimens.iconSm, color: c.primary),
              const SizedBox(width: LfDimens.spaceSmall),
              Text(
                '营养分析',
                style: LfText.title.copyWith(color: c.cardForeground),
              ),
            ],
          ),
          const SizedBox(height: LfDimens.spaceMedium),
          Row(
            children: [
              Expanded(
                child: _StatTile(
                  value: trend.averageKcal == null
                      ? '—'
                      : trend.averageKcal!.round().toString(),
                  label: '周均摄入 kcal',
                  valueColor: c.cardForeground,
                ),
              ),
              const SizedBox(width: LfDimens.spaceSmall),
              Expanded(
                child: _StatTile(
                  value: percent == null ? '—' : '$percent%',
                  label: '目标达成率',
                  valueColor: mint.tone(600),
                ),
              ),
              const SizedBox(width: LfDimens.spaceSmall),
              Expanded(
                child: _StatTile(
                  value: bars.hitCount == null ? '—' : '${bars.hitCount}/7',
                  label: '达标天数',
                  valueColor: c.cardForeground,
                ),
              ),
            ],
          ),
          if (insights.isNotEmpty) ...[
            const SizedBox(height: LfDimens.spaceMedium),
            for (final insight in insights)
              Padding(
                padding: const EdgeInsets.only(bottom: LfDimens.spaceSmall),
                child: _InsightRow(insight: insight),
              ),
          ],
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.value,
    required this.label,
    required this.valueColor,
  });

  final String value;
  final String label;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    return MutedBlock(
      padding: const EdgeInsets.symmetric(
        horizontal: LfDimens.spaceSmall,
        vertical: LfDimens.spaceSmall,
      ),
      child: Column(
        children: [
          // 数值不许裁字（阶段 2B 步骤 6 审看发现的缺陷 ⑨：320dp×2.0× 下
          // 「30%」被 `ellipsis` 静默裁成「3…」——那是把 30% 说成 3）。
          // `FittedBox(scaleDown)` 是仓内信息性数值的既定兜底（`LfStatTile`
          // 同款）：放得下就不动字号，放不下整体等比缩小。
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              maxLines: 1,
              style: LfText.titleLarge.copyWith(color: valueColor),
            ),
          ),
          const SizedBox(height: LfDimens.spaceMicro),
          Text(
            label,
            textAlign: TextAlign.center,
            style: LfText.micro.copyWith(color: c.mutedForeground),
            maxLines: 2,
          ),
        ],
      ),
    );
  }
}

class _InsightRow extends StatelessWidget {
  const _InsightRow({required this.insight});

  final NutritionInsight insight;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final color = switch (insight.tone) {
      InsightTone.neutral => c.primary,
      InsightTone.warning => c.warning,
      InsightTone.macro => c.fat,
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        ),
        const SizedBox(width: LfDimens.spaceSmall),
        Expanded(
          child: Text(
            insight.text,
            style: LfText.caption.copyWith(color: c.mutedForeground),
          ),
        ),
      ],
    );
  }
}
