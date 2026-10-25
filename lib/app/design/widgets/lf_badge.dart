import 'package:flutter/material.dart';

import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/dashed_border.dart';

/// 徽章与标签族（docs/21 §3.9，2026-10-03 补章）。
///
/// §3.5 点名过 `StatusBadge`/`UnitBadge`/`HotBadge`/`PlannedTag` 四件，但实现层
/// 从未把它们做成共享件，于是各页面各写一份（`dashboard_weight_card.dart` 的
/// `_UnitBadge`、`food_card.dart` 的 `_Tag`…）。收敛为**一件带变体的 LfBadge**。
///
/// 【不并入证据徽章】`LfEvidenceBadge` / `AppEvidenceBadge` 承载的是「已确认 /
/// AI 估算 / 待补全」的**证据等级**语义（docs/07 诚实性条款），不是装饰标签，
/// 保持独立。
///
/// 【形状】8 圆角 / `px-2 py-1` / 11px w500——与 §2.3「`rounded-[8px]` 只用于
/// 徽章（3 次）」一致。
enum LfBadgeVariant {
  /// muted 底 + mutedForeground 字。单位 / 口径标（原 `UnitBadge`，如「周」
  /// 「每 100g」）。
  neutral,

  /// 浅品牌底 + 品牌字（亮 mint-100 + mint-700 / 暗 mintDark-100 + mint-400）。
  /// 状态标（原 `StatusBadge`，如「燃脂中」）。
  mint,

  /// honey（carbs）系底 + 深字。`本周热门`（原 `HotBadge`）。
  honey,

  /// 虚线边（mint-300）+ 品牌字 + 透明底。「晚餐 · 计划」计划态（原
  /// `PlannedTag`）。
  dashed,

  /// 实线边（mint-300）+ 品牌字 + 透明底——与 [dashed] **同源色，只把虚线
  /// 改实线**。品牌名（docs/29 §P8a 需求 26）：食物卡左下角的品牌 chip 要
  /// **与右下角的自建/内置徽标同几何**（同高、同字号、同圆角），只靠「实底 /
  /// 描边」区分档位。
  outlinedBrand,
}

class LfBadge extends StatelessWidget {
  const LfBadge(
    this.text, {
    super.key,
    this.variant = LfBadgeVariant.neutral,
    this.icon,
  });

  const LfBadge.neutral(this.text, {super.key, this.icon})
    : variant = LfBadgeVariant.neutral;

  const LfBadge.mint(this.text, {super.key, this.icon})
    : variant = LfBadgeVariant.mint;

  const LfBadge.honey(this.text, {super.key, this.icon})
    : variant = LfBadgeVariant.honey;

  const LfBadge.dashed(this.text, {super.key, this.icon})
    : variant = LfBadgeVariant.dashed;

  const LfBadge.outlinedBrand(this.text, {super.key, this.icon})
    : variant = LfBadgeVariant.outlinedBrand;

  final String text;
  final LfBadgeVariant variant;

  /// 前置小图标（16dp，如「燃脂中」的 flame、「本周热门」的 flame）。
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final brightness = Theme.of(context).brightness;
    final mint = LfColors.mint(brightness);
    // honey 档取分类数据色里的 carbs 一族（HTML 注释就写着
    // `--lf-carbs: #FFC94D; /* honey — carbs */`，`--lf-evidence-b` 同理是
    // honey100）。文字色用 `cardForeground`：与既有 `LfEvidenceBadge` 在
    // evidence 浅底上用 `cardForeground` 是同一套写法，明暗两态都成立。
    final (bg, fg) = switch (variant) {
      LfBadgeVariant.neutral => (c.muted, c.mutedForeground),
      LfBadgeVariant.mint => (mint.tone(100), LfColors.mintText(brightness)),
      LfBadgeVariant.honey => (c.carbs100, c.cardForeground),
      LfBadgeVariant.dashed => (null, LfColors.mintText(brightness)),
      LfBadgeVariant.outlinedBrand => (null, LfColors.mintText(brightness)),
    };
    // 描边档把 1px 边从内边距里让出来：8-1=7、4-1=3。**必须走 `Container`**
    // ——CSS 里 `border` 与 `padding` 都算进盒尺寸，Flutter 只有 `Container`
    // 会把 `decoration.padding`（= `Border.dimensions` 每边 1px）算进布局；
    // `DecoratedBox` 只画边、不占位，外框会比实底档矮 2dp（写测试时被抓过）。
    // 虚线档的 painter 不占 layout，维持原样。
    final outlined = variant == LfBadgeVariant.outlinedBrand;
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: LfDimens.iconSm, color: fg),
          const SizedBox(width: LfDimens.spaceXSmall),
        ],
        // 文字走 `Flexible` + 省略号：食物卡左下角的品牌 chip 会被长品牌名撑
        // （「Nichirei日冷」、2.0× 更甚），`Flexible` 给到有界宽度后省略号才
        // 生效；宽度无界时（Row 的 `mainAxisSize.min` 之外）Flexible 自动退化
        // 成按内容定宽，与不带它时一致。
        Flexible(
          child: Text(
            text,
            style: LfText.label.copyWith(color: fg),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
    if (outlined) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          border: Border.all(color: mint.tone(300)),
          borderRadius: BorderRadius.circular(LfDimens.radiusSm),
        ),
        child: content,
      );
    }
    final padded = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: content,
    );
    if (bg == null) {
      return CustomPaint(
        foregroundPainter: DashedBorderPainter(
          color: mint.tone(300),
          radius: LfDimens.radiusSm,
        ),
        child: padded,
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(LfDimens.radiusSm),
      ),
      child: padded,
    );
  }
}
