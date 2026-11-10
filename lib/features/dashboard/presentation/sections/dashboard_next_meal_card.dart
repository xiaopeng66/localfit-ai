import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/number_format.dart';
import 'package:localfit_ai/app/design/widgets/design_card.dart';
import 'package:localfit_ai/app/design/widgets/lf_buttons.dart';
import 'package:localfit_ai/app/design/widgets/lf_progress_bar.dart';
import 'package:localfit_ai/app/design/widgets/text_fit.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart'
    show MealSlot;
import 'package:localfit_ai/features/nutrition/presentation/meal_slot_icons.dart';

/// 今日页「下一餐」预算卡（Round7 A `.next-meal`，`app.js:142-144` +
/// `refinement.css:7`）。
///
/// A 的结构：`card-row`（标题 + 餐次图标块）→ `budget-line`（剩余额度 22 +
/// 「kcal」小字 / 一句状态）→ 品牌轨（今日摄入进度）→ 块级软底按钮。
///
/// 【2026-10-31 用户两条改动】
/// 1. **下一餐按系统时间动态判断**（原话：「下一餐不能永远显示晚餐」）：
///    槽位由 [DashboardPage] 用 `nextMealSlotFor(now)` 算好传进来——标题、
///    图标、按钮文案都跟着变（0–9 早餐 / 9–14 午餐 / 14–20 晚餐 / 20–24 加餐）。
///    卡片自己不读系统时间：时刻只有一个来源，边界才能被穷举测试。
/// 2. **删掉「N 笔已记」「目标 N」两行**（原话：「删除下方 N 笔已记和目标 N」）：
///    `budget-facts` 整块退役。目标是剩余额度的分母、笔数是产物，两条都不再
///    重复上屏；剩余额度与进度轨保持不变。
///
/// 【数据只读既有事实】剩余额度 = `目标上限 − 今日已摄入`（不足记 0，
/// 与 A `Math.max(0,total.remaining)` 同口径）。未设目标时写 `—` +
/// 「尚未设定热量目标」，轨道画 0——**不编一个目标**。
///
/// 【写路径不变】按钮仍走既有餐食编辑弹层并预选 [slot]（一次性意向通道，
/// 见 `nutrition_intents.dart`），不是新的写入路径。
class DashboardNextMealCard extends StatelessWidget {
  const DashboardNextMealCard({
    super.key,
    required this.consumedKcal,
    required this.targetKcal,
    required this.slot,
    this.onLogMeal,
  });

  /// 今日已摄入热量（kcal）。
  final double consumedKcal;

  /// 今日热量目标上限；null = 未设目标。
  final double? targetKcal;

  /// 下一餐是哪一餐（由 `nextMealSlotFor(now)` 算好传入）。
  final MealSlot slot;

  /// 「记录<餐次>」：打开餐食编辑并预选 [slot]。
  final VoidCallback? onLogMeal;

  /// A `.next-meal{padding-top:10px}`。
  static const EdgeInsets cardPadding = EdgeInsets.fromLTRB(
    LfDimens.spaceLarge,
    LfDimens.spaceSmallPlus,
    LfDimens.spaceLarge,
    LfDimens.spaceLarge,
  );

  /// A `.budget-line{margin:12px 0}`。
  static const double lineMargin = 12;

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
          ? '下一餐 · ${slot.label}，今日剩余 ${remaining.round()} 千卡'
          : '下一餐 · ${slot.label}，尚未设定热量目标',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '下一餐 · ${slot.label}',
                  key: const Key('dashboard-next-meal-title'),
                  style: LfText.title.copyWith(color: c.cardForeground),
                ),
              ),
              // A `chip('moon','mint')`：28dp 圆角图标块（brand-soft 底 +
              // brand-strong 图标）。图标随餐次走（早太阳 / 午碗 / 晚月亮 /
              // 加餐杯），与记录页槽位卡头同一套 [MealSlotIcons]——同一餐在
              // 两个页面上不长两个样。
              Container(
                key: const Key('dashboard-next-meal-chip'),
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: LfColors.brandSoft(Theme.of(context).brightness),
                  borderRadius: BorderRadius.circular(LfDimens.radiusMd),
                ),
                child: Icon(
                  slot.icon,
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
          // 【2026-10-31 用户】「N 笔已记」「目标 N」两行整块退役（`budget-facts`
          // 与 [_Fact] 一起删）：目标是剩余额度的分母、笔数是产物，两条都在
          // 重复上屏。卡上留给用户的是「还剩多少」与「去记录」两件事。
          if (onLogMeal != null)
            LfSoftButton(
              key: const Key('cta-log-next-meal'),
              label: '记录${slot.label}',
              icon: Icons.add,
              expand: true,
              onPressed: onLogMeal,
            ),
        ],
      ),
    );
  }
}
