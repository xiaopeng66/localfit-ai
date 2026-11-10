import 'package:flutter/material.dart';

import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';

/// 「选项行」的**唯一形态**（需求 11a，2026-10-25）。
///
/// 用户原话：「记录一餐里，『按食材记录』和『按菜品记录』两个界面看起来是两套
/// 东西」。核对下来确实如此：按食材走食物库的 `FoodCard`（40dp 图标 + 名称 +
/// 副行 + 右侧动作），按菜品走弹层里的**朴素 `InkWell` 行**（只有两行文字）。
///
/// 本件把那一行的几何与字号收成一处：
/// * 左件固定 40dp（图标 / 首字圆都装得下）；
/// * 左件与文字之间固定 [leadingGap]；
/// * 标题 `bodyStrong`、副行 `caption`（与食物卡同一档）；
/// * 右侧动作交给调用方（热量环 / 来源徽标 / chevron），**间距由
///   [trailingGap] 统一**。
///
/// 两处都用它 ⇒ 行高、字号、间距、右侧动作的位置不再靠「各自抄一遍」对齐。
/// **Key 由调用方给**（三个位置各一个可选 Key），所以既有 Key 一个不退役。
class LfPickerRow extends StatelessWidget {
  const LfPickerRow({
    super.key,
    required this.title,
    this.titleSuffix,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.titleKey,
    this.subtitleKey,
    this.trailingKey,
    this.leadingKey,
    this.trailingGap = defaultTrailingGap,
  });

  /// 左件尺寸（图标 / 首字圆 / 分类图标共用一档）。
  static const double leadingSize = 40;

  /// 左件与文字之间（A `.food-row{gap:10px}` 的同一口径）。
  static const double leadingGap = LfDimens.spaceSmallPlus;

  /// 文字与右侧动作之间（食物卡既有 10 + 4 = 14，保持不动）。
  static const double defaultTrailingGap =
      LfDimens.spaceSmallPlus + LfDimens.spaceXSmall;

  final String title;

  /// 紧跟标题之后的小件（食物卡的「营养不完整」警示图标用它）。
  final Widget? titleSuffix;

  /// 副行（品牌 / 餐次 + 热量）；null = 不占位。
  final String? subtitle;

  /// 左件（图标 / 首字圆）；null = 不占位（此时文字贴左）。
  final Widget? leading;

  /// 右侧动作（热量环 / 来源徽标 / chevron）。
  final Widget? trailing;

  final VoidCallback? onTap;

  final Key? titleKey;
  final Key? subtitleKey;
  final Key? trailingKey;
  final Key? leadingKey;

  final double trailingGap;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final sub = subtitle;
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (leading != null) ...[
          SizedBox(
            key: leadingKey,
            width: leadingSize,
            height: leadingSize,
            child: Center(child: leading),
          ),
          const SizedBox(width: leadingGap),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      title,
                      key: titleKey,
                      style: LfText.bodyStrong.copyWith(
                        color: c.cardForeground,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (titleSuffix != null) ...[
                    const SizedBox(width: LfDimens.spaceTiny),
                    titleSuffix!,
                  ],
                ],
              ),
              if (sub != null && sub.isNotEmpty)
                Text(
                  sub,
                  key: subtitleKey,
                  style: LfText.caption.copyWith(color: c.mutedForeground),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
        if (trailing != null) ...[
          SizedBox(width: trailingGap),
          KeyedSubtree(key: trailingKey, child: trailing!),
        ],
      ],
    );
    if (onTap == null) return row;
    return InkWell(
      onTap: onTap,
      // 整行可点（与食物库行同一命中行为）。
      child: row,
    );
  }
}
