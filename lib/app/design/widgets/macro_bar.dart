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
    this.targetMin,
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

  /// 目标**上限**；**null = 没有目标**，右端只写当前值。
  ///
  /// 【2026-10-26 看图复核缺陷 6】未设目标时调用点曾退成 `?? 0`，右端于是写出
  /// 「60 / 0 g」——那会被读成「目标是 0 克」，是一个**编出来的目标**。用户
  /// 反复强调「算不出来就说数据不足，不许给假数字」，所以这里改成可空：
  /// 没有目标就只写当前值，进度条也不填（没有分母可比）。
  final num? target;

  /// 目标**下限**（需求 1，2026-10-25）：非 null 且 ≥ 0 时右端写**区间**
  /// `min–max g`（用户点名：「三宏量块显示区间：90–130 g」）。
  ///
  /// 进度条分母仍取 [target]（上限）：进度条必须有单一确定分母，取上限是
  /// 保守做法且与「不超上限」一致——这是**有意的取舍**，不是漏改。
  ///
  /// 【2026-10-29 用户：「区间要在进度条上显示出来，不然我怎么知道区间在哪」】
  /// 下限不再只写在文字里：轨道上画一段 `min/max → 1.0` 的**区间带**
  /// （同色 35% 透明度），实心填充仍是当前值——「带在哪 = 目标区间在哪、
  /// 填充到哪 = 现在到哪」一眼可读。
  final num? targetMin;

  final String unit;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final goal = target;
    final ratio = goal != null && goal > 0
        ? (current / goal).clamp(0.0, 1.0)
        : 0.0;
    // 区间带：上下限都有、上限 > 0、下限 ≥ 0 且严格小于上限时才画
    // （min == max 是单值目标，没有「带」可言）。
    final min = targetMin;
    final bandWidth = goal != null && goal > 0 && min != null && min >= 0
        ? (1 - min / goal).clamp(0.0, 1.0).toDouble()
        : null;
    final hasBand = bandWidth != null && bandWidth > 0 && bandWidth < 1;
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
                        // 有区间 ⇒ 写区间（`90–130 g`）；只有上限 ⇒ 单值；
                        // 都没有（未设目标）⇒ **不写右端**，只留当前值。
                        text: switch ((targetMin, target)) {
                          (final num min, final num max) =>
                            ' / $min–$max $unit',
                          (_, final num max) => ' / $max $unit',
                          _ => '',
                        },
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
                // 区间带（右对齐到上限端）：只在「有下限且小于上限」时出现。
                if (hasBand)
                  Positioned.fill(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: FractionallySizedBox(
                        widthFactor: bandWidth,
                        heightFactor: 1,
                        child: ColoredBox(
                          key: const Key('macro-bar-range-band'),
                          color: color.withValues(alpha: 0.35),
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ),
                  ),
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
