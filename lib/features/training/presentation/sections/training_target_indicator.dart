import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';

/// 训练达标指标（docs/21 §5.1 第 5 项）：今日 / 本周计划完成进度。
///
/// 语义色：达标用成功绿、未达标用警告橙（不是装饰色，是状态编码）。
/// 进度条与数值同时呈现——颜色不单独表达状态，读屏也能得到「3/5」。
class TrainingTargetIndicator extends StatelessWidget {
  const TrainingTargetIndicator({
    super.key,
    required this.label,
    required this.completed,
    required this.total,
    this.unit = '天',
  });

  /// 指标名（如「今日计划」「本周计划」）。
  final String label;

  /// 已完成数。
  final int completed;

  /// 计划总数；<= 0 表示没有计划，此时不渲染达标状态。
  final int total;

  /// 计数单位（默认「天」）。
  final String unit;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final ratio = total <= 0 ? 0.0 : (completed / total).clamp(0.0, 1.0);
    final met = total > 0 && completed >= total;
    final color = met ? c.success : c.warningText;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: LfText.caption.copyWith(color: c.mutedForeground),
              ),
            ),
            Text(
              total <= 0 ? '—' : '$completed/$total $unit',
              style: LfText.headline.copyWith(color: c.cardForeground),
            ),
          ],
        ),
        const SizedBox(height: LfDimens.spaceTiny),
        ClipRRect(
          borderRadius: BorderRadius.circular(LfDimens.radiusFull),
          child: SizedBox(
            height: 6,
            child: ColoredBox(
              color: color.withValues(alpha: 0.18),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: ratio,
                  child: ColoredBox(color: color),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
