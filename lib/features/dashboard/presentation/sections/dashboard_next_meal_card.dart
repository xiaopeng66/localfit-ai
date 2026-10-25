import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/number_format.dart';
import 'package:localfit_ai/app/design/widgets/design_card.dart';
import 'package:localfit_ai/app/design/widgets/lf_buttons.dart';
import 'package:localfit_ai/app/design/widgets/lf_progress_bar.dart';
import 'package:localfit_ai/app/design/widgets/text_fit.dart';

/// 今日页「下一餐」预算卡（Round7 A `.next-meal`，`app.js:142-144` +
/// `refinement.css:7`）。
///
/// A 的结构：`card-row`（标题「下一餐，留给晚餐」+ 月亮图标块）→
/// `budget-line`（剩余额度 22 + 「kcal」小字 / 一句状态）→ 品牌轨（今日摄入
/// 进度）→ `budget-facts`（N 笔已记 / 目标 N）→ 块级软底按钮「记录晚餐」。
///
/// 【数据只读既有事实】剩余额度 = `目标上限 − 今日已摄入`（不足记 0，
/// 与 A `Math.max(0,total.remaining)` 同口径）；笔数 = 当天餐食条数；
/// 目标 = 当天的热量目标上限（`DailyNutritionTarget.calorieMaxKcal`）。
/// 未设目标时 A 写 `—` + 「尚未设定热量目标」，轨道画 0——本卡照此，
/// **不编一个目标**。
///
/// 【不接管「下一餐是哪一餐」的判断】A 的标题是固定文案；真正的槽位决策
/// 仍在记录页的 `NextMealEntryCard`（读本地时刻与已记餐次），本卡只回答
/// 「今天还剩多少额度、记了几笔」。按钮打开的是既有餐食编辑弹层并预选晚餐
/// （一次性意向通道，见 `nutrition_intents.dart`），不是新的写入路径。
class DashboardNextMealCard extends StatelessWidget {
  const DashboardNextMealCard({
    super.key,
    required this.consumedKcal,
    required this.targetKcal,
    required this.mealCount,
    this.onLogDinner,
  });

  /// 今日已摄入热量（kcal）。
  final double consumedKcal;

  /// 今日热量目标上限；null = 未设目标。
  final double? targetKcal;

  /// 今日已记录的餐食条数。
  final int mealCount;

  /// 「记录晚餐」：打开餐食编辑（预选晚餐槽位）。
  final VoidCallback? onLogDinner;

  /// A `.next-meal{padding-top:10px}`。
  static const EdgeInsets cardPadding = EdgeInsets.fromLTRB(
    LfDimens.spaceLarge,
    LfDimens.spaceSmallPlus,
    LfDimens.spaceLarge,
    LfDimens.spaceLarge,
  );

  /// A `.budget-line{margin:12px 0}`。
  static const double lineMargin = 12;

  /// A `.budget-facts{gap:18px}`。
  static const double factsGap = 18;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final target = targetKcal;
    final hasTarget = target != null && target > 0;
    final remaining = hasTarget
        ? (target - consumedKcal).clamp(0.0, target)
        : 0.0;
    final progress = hasTarget ? (consumedKcal / target).clamp(0.0, 1.0) : 0.0;

    return DesignCard(
      key: const Key('dashboard-next-meal'),
      padding: cardPadding,
      semanticLabel: hasTarget
          ? '下一餐预算，今日剩余 ${remaining.round()} 千卡，已记 $mealCount 笔'
          : '下一餐预算，尚未设定热量目标，已记 $mealCount 笔',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '下一餐，留给晚餐',
                  style: LfText.title.copyWith(color: c.cardForeground),
                ),
              ),
              // A `chip('moon','mint')`：28dp 圆角图标块（brand-soft 底 +
              // brand-strong 图标）。与记录页槽位卡头同一形态。
              Container(
                key: const Key('dashboard-next-meal-chip'),
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: LfColors.brandSoft(Theme.of(context).brightness),
                  borderRadius: BorderRadius.circular(LfDimens.radiusMd),
                ),
                child: Icon(
                  Icons.nightlight_outlined,
                  size: 18,
                  color: LfColors.mintText(Theme.of(context).brightness),
                ),
              ),
            ],
          ),
          const SizedBox(height: lineMargin),
          LayoutBuilder(
            builder: (context, constraints) {
              final valueText = Text.rich(
                key: const Key('dashboard-next-meal-remaining'),
                TextSpan(
                  children: [
                    TextSpan(
                      text: hasTarget
                          ? withThousandsSeparator(remaining.round())
                          : '—',
                      style: LfText.displayLarge.copyWith(
                        color: c.cardForeground,
                      ),
                    ),
                    TextSpan(
                      text: ' kcal',
                      style: LfText.caption.copyWith(color: c.mutedForeground),
                    ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              );
              final noteText = Text(
                hasTarget ? '今日剩余额度' : '尚未设定热量目标',
                key: const Key('dashboard-next-meal-note'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: LfText.caption.copyWith(color: c.mutedForeground),
              );
              // A `.budget-line` 是**两端一行**（值在左、注在右）。旧件把值包
              // `Expanded`、注包 `Flexible`——两个 flex 1 的孩子把这行劈成两半，
              // 2.0× / 320dp 下值只剩一半宽，`ellipsis` 静默把「1,275 kcal」裁成
              // 「1,2…」（round7 2A 整页渲染审看在 `today-dark-320-2.0.png`
              // 抓到）。大字下竖排：两段各占一行、都完整；1.0×/1.5× 仍照 A 并排。
              if (!fitsRow(
                context,
                available: constraints.maxWidth,
                baseNeed: LfRowBudgets.nextMealLine,
              )) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    valueText,
                    const SizedBox(height: LfDimens.spaceXSmall),
                    noteText,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: valueText),
                  const SizedBox(width: LfDimens.spaceSmall),
                  noteText,
                ],
              );
            },
          ),
          const SizedBox(height: LfDimens.spaceMedium),
          LfProgressBar(value: progress),
          const SizedBox(height: lineMargin),
          // A `.budget-facts{display:flex;gap:18px}`（不换行）。DOM 无断点，
          // 本仓硬约束是 320dp × 2.0× 也不许溢出：那时两格合计比卡片内容宽
          // 多 4.3px（`large_font_layout_audit_test` 实测抓到，报的就是这里）。
          // 与其让尾字被裁（`Flexible`+ellipsis 会吃掉「笔已记 / 目标」），
          // 大字下换行——两条事实都还在；1.0× 仍是 A 的一行、gap 18。
          Wrap(
            spacing: factsGap,
            runSpacing: LfDimens.spaceXSmall,
            children: [
              _Fact(
                key: const Key('dashboard-next-meal-count'),
                icon: Icons.rice_bowl_outlined,
                label: '$mealCount 笔已记',
              ),
              _Fact(
                key: const Key('dashboard-next-meal-goal'),
                icon: Icons.my_location_outlined,
                label: hasTarget
                    ? '目标 ${withThousandsSeparator(target.round())}'
                    : '目标 —',
              ),
            ],
          ),
          const SizedBox(height: lineMargin),
          if (onLogDinner != null)
            LfSoftButton(
              key: const Key('cta-log-dinner'),
              label: '记录晚餐',
              icon: Icons.add,
              expand: true,
              onPressed: onLogDinner,
            ),
        ],
      ),
    );
  }
}

/// `budget-facts` 里的一条（A `icon('bowl'|'target',16)` + 文案）。
class _Fact extends StatelessWidget {
  const _Fact({super.key, required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: LfDimens.iconSm, color: c.mutedForeground),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: LfText.label.copyWith(color: c.mutedForeground),
          ),
        ),
      ],
    );
  }
}
