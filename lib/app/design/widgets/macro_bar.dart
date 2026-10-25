import 'package:flutter/material.dart';

import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';

/// 宏量横条（docs/21 §3.2，2026-10-14 按 Round7 A `.macro-column` 重排）：
/// 标签行（[cardDotSize]dp 数据色圆点 + 12px muted 名称 …… 值 15px + 「/ 目标 g」
/// 11px muted）+ [cardTrackHeight]dp 全圆角轨道 + 按比例填充。
///
/// A 有效值：`.macro-column{display:grid;grid-template-columns:auto 1fr;row-gap:6px}`
/// + `.macro-dot{width:5px;height:5px}` + `.macro-column b{font-size:15px}`
/// + `.macro-column small{font-size:11px;color:var(--muted)}`，卡内轨道
/// `.data-track{height:5px}`（`refinement.css` 覆盖 `styles.css` 的 4px）。
/// 旧件 `MacroPill`（32dp 药丸）按 §3.1 废弃，已于阶段 I-2b 删除。
class MacroBar extends StatelessWidget {
  const MacroBar({
    super.key,
    required this.label,
    required this.color,
    required this.current,
    required this.target,
    this.unit = 'g',
  });

  /// 标签行圆点直径（A `.macro-dot`）。
  static const double cardDotSize = 5;

  /// 卡内轨道高（A `.data-track` 在卡内的有效值）。
  static const double cardTrackHeight = 5;

  final String label;

  /// 数据色（蛋白=珊瑚 / 碳水=蜜黄 / 脂肪=雾紫，编码永不调换）。
  final Color color;
  final num current;
  final num target;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final ratio = target > 0 ? (current / target).clamp(0.0, 1.0) : 0.0;
    // key 不外传：`key: key ?? ValueKey(...)` 会让同一个 key 在树里出现两次
    // （组件自身 + 内层 Column），`find.byKey` 命中 2 个，语义树也重复。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              key: const Key('macro-bar-dot'),
              width: cardDotSize,
              height: cardDotSize,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: LfDimens.spaceTiny),
            Expanded(
              child: Text(
                label,
                style: LfText.caption.copyWith(color: c.mutedForeground),
              ),
            ),
            // 数值串在极端字号（2.0× + 320dp）下比整行还宽，改用可缩放兜底：
            // `Flexible` 给它剩余宽度，`scaleDown` 只在放不下时等比缩小，1.0×
            // 下与不缩一致（与大字号溢出用同一套处理，见 docs/27 §6）。
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '$current',
                        style: LfText.title.copyWith(color: c.cardForeground),
                      ),
                      TextSpan(
                        text: ' / $target $unit',
                        style: LfText.label.copyWith(color: c.mutedForeground),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: LfDimens.spaceTiny),
        ClipRRect(
          borderRadius: BorderRadius.circular(LfDimens.radiusFull),
          child: SizedBox(
            key: const Key('macro-bar-track'),
            height: cardTrackHeight,
            width: double.infinity,
            child: Stack(
              children: [
                ColoredBox(color: c.muted, child: const SizedBox.expand()),
                FractionallySizedBox(
                  widthFactor: ratio,
                  child: ColoredBox(
                    color: color,
                    child: const SizedBox.expand(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 热量占比行（docs/21 §3.2；2026-10-14 按 Round7 A `.macro-ratios` 重排）：
/// 「能量占比」+ 逐项「数据色圆点 + 名称 + 百分比」，10px（A `font-size:10px`）。
/// 用于 4/4/9 之类宏量热量占比展示。
///
/// 形态：A 的片段在宽屏一行、窄屏按 flex 收缩换行；这里用 [Wrap] 直译——
/// 每项自身不折行，项与项之间换行（320dp + 2.0× 下不再把「蛋白质 / 20%」
/// 劈成两行）。
class MacroRatioRow extends StatelessWidget {
  const MacroRatioRow({super.key, required this.entries, this.leading});

  /// (名称, 颜色, 百分比 0..100)
  final List<(String, Color, num)> entries;

  /// 行首前缀（能量卡写「能量占比」）。
  final String? leading;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: LfDimens.spaceMedium,
      runSpacing: LfDimens.spaceXSmall,
      children: [
        if (leading != null)
          Text(
            leading!,
            style: LfText.micro.copyWith(color: c.mutedForeground),
          ),
        for (final entry in entries)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: MacroBar.cardDotSize,
                height: MacroBar.cardDotSize,
                decoration: BoxDecoration(
                  color: entry.$2,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: LfDimens.spaceXSmall),
              Text(
                '${entry.$1} ',
                style: LfText.micro.copyWith(color: c.mutedForeground),
              ),
              Text(
                '${entry.$3}%',
                style: LfText.micro.copyWith(
                  color: entry.$2,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
      ],
    );
  }
}
