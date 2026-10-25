import 'package:flutter/material.dart';

import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';

/// 区间范围条（docs/32 §3 D4 / 需求 59）。
///
/// 把一个 `[min, max]` 区间**只按位置**画到 `[0, max × 1.2]` 的轨道上：
/// 不显示百分比、不显示完成度——它不是进度条，是「你这一档落在哪」。
///
/// 为什么除 1.2 而不是除 max：除 max 会让每行的填充都顶到右端（区间上界
/// 恒等于轨道右端），四行的差别被抹平、只剩装饰；留 20% 余量后右端刻度
/// 才是各行的 `max`，左端刻度的差异可见。
///
/// 归一函数（[weights]）是纯函数，边界口径见其文档。
class TargetRangeBar extends StatelessWidget {
  const TargetRangeBar({
    super.key,
    required this.min,
    required this.max,
    required this.color,
    this.height = 6,
  });

  final num min;
  final num max;
  final Color color;
  final double height;

  /// 轨道右端的余量倍数：轨道量程 = `max × headroom`。
  static const double headroom = 1.2;

  /// 归一结果：`left`/`width`/`right` 都是 0..1 的分数。
  ///
  /// 边界口径（docs/32 §3 D4「纯位置可视化，不引入假精度」）：
  /// - `max <= 0` ⇒ `null`：没有量程可言，**不画**填充（不是画在 0 位置）；
  /// - `min > max`（异常输入）⇒ `null`：整段隐藏，只留数值；
  /// - `min < 0` ⇒ 把 `min` 夹到 0（不画出轨道左界之外）；
  /// - 区间极窄（`min == max`）⇒ 仍返回一个可见宽度，`null` 只在真的
  ///   没有量程时给。
  static ({double left, double width, double right})? weights({
    required num min,
    required num max,
  }) {
    if (max <= 0 || min > max) return null;
    final span = max * headroom;
    final left = (min < 0 ? 0.0 : min / span).clamp(0.0, 1.0).toDouble();
    final right = (max / span).clamp(0.0, 1.0).toDouble();
    // 最小区分宽度：极窄区间也要看得见（否则等于没画）。
    const minVisible = 0.015;
    final width = (right - left) < minVisible ? minVisible : (right - left);
    final clampedLeft = (left + width > 1.0) ? (1.0 - width) : left;
    return (left: clampedLeft, width: width, right: right);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final w = weights(min: min, max: max);
    return ClipRRect(
      borderRadius: BorderRadius.circular(LfDimens.radiusFull),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final trackWidth = constraints.maxWidth;
            return Stack(
              children: [
                ColoredBox(color: c.muted, child: const SizedBox.expand()),
                if (w != null)
                  Positioned(
                    left: trackWidth * w.left,
                    width: trackWidth * w.width,
                    top: 0,
                    bottom: 0,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(height / 2),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 抽屉里的一行宏量区间：数据色圆点 + 名称 + 数值 + 范围条。
class TargetRangeRow extends StatelessWidget {
  const TargetRangeRow({
    super.key,
    required this.label,
    required this.color,
    required this.min,
    required this.max,
  });

  final String label;
  final Color color;
  final num min;
  final num max;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: LfDimens.spaceTiny),
            Expanded(
              child: Text(
                label,
                style: LfText.caption.copyWith(color: c.cardForeground),
              ),
            ),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '$min–$max g',
                  style: LfText.captionStrong.copyWith(color: c.cardForeground),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: LfDimens.spaceSmall),
        TargetRangeBar(min: min, max: max, color: color),
      ],
    );
  }
}
