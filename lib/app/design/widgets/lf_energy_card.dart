import 'package:flutter/material.dart';

import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/number_format.dart';
import 'package:localfit_ai/app/design/widgets/design_card.dart';
import 'package:localfit_ai/app/design/widgets/lf_badge.dart';
import 'package:localfit_ai/app/design/widgets/lf_calorie_ring.dart';
import 'package:localfit_ai/app/design/widgets/macro_bar.dart';
import 'package:localfit_ai/app/design/widgets/text_fit.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';

/// 热量 / 宏量卡（Round7 A `.energy-summary`，`design/round7/app.js:125-128`）。
///
/// **两页共用的同一件**：今日页（`energy()`，标题「今日营养」）与饮食记录页
/// （`energy(ui.date)`，非今天时标题「当日营养」）画的是同一张卡——A 的
/// `app.js` 里就是同一个函数，所以这里也只做一份，锚点与标题由调用方注入。
///
/// 结构（A 有效层叠）：
///
/// - `card-row`：标题 15px + 状态 pill（`已超目标 / 接近上限 / 额度充足 / 未设目标`，
///   超目标时换 `warning` 档 honey 底——A `app.js:125` 的
///   `class="pill ${...?'warning':'today'}"`）；
/// - `energy-main{grid 120px|1fr;gap:20px;padding:18px 0}`：环 120（中心
///   `值 26px` + `已摄入 kcal`）＋ 宏量三行（`macro-column` 网格：标签 12px muted
///   + 值 15px + `/ 目标 g` 11px，轨道 5px 跨两列）；
/// - `energy-foot{border-top 1px var(--track);padding-top:11px}`：左「目标 N kcal」、
///   右「还可摄入/超出 N kcal」；
/// - `macro-ratios{10px;margin-top:10px}`：能量占比三格。
///
/// 诚实规则不因换图失效：无目标时不画进度弧、写「尚未设定目标」且不编百分比；
/// 全 0 摄入不写「0%/0%/0%」，写「暂无记录，记录后显示营养占比」。
class LfEnergyCard extends StatelessWidget {
  const LfEnergyCard({
    super.key,
    required this.consumed,
    required this.target,
    required this.title,
    required this.cardKey,
    required this.keyPrefix,
    this.remainingKey,
    this.ratiosKey,
    this.statusKey,
  });

  final NutritionValues consumed;

  /// null = 未设定目标：脚注诚实显示「尚未设定目标」，不编数字。
  final DailyNutritionTarget? target;

  /// 卡标题：今日页「今日营养」，记录页看历史日期时「当日营养」。
  final String title;

  /// 整卡锚点（今日页 `dashboard-calorie-ring`、记录页沿用各自既有 Key）。
  final Key cardKey;

  /// 环内三段文字与脚注「目标」的锚点前缀（`<prefix>-consumed` /
  /// `-percent` / `-target`）。
  final String keyPrefix;

  /// 「还可摄入/超出 N kcal」那一行的锚点（今日页历史 Key
  /// `dashboard-remaining-line` 迁到此处）。
  final Key? remainingKey;

  /// 占比行的锚点（今日页 `dashboard-macro-ratios`）。
  final Key? ratiosKey;

  /// 状态 pill 的锚点（今日页 `dashboard-ring-status`）。
  final Key? statusKey;

  /// A `.energy-main{padding:18px 0}`；卡内边距 `16px 18px 18px`。
  static const double mainVerticalPadding = 18;

  /// A `.energy-foot{padding-top:11px}`。
  static const double footPaddingTop = 11;

  /// A `.energy-main{grid-template-columns:120px minmax(0,1fr);gap:20px}`。
  static const double gridColumnGap = 20;

  /// 环中心数值 / 目标 / 占比的语义状态文案（A `status`）。
  ///
  /// 只按「已摄入 vs 目标」这一个本地事实分级，**不推断身体状态**：
  /// 达到 90% 以上写「接近上限」，超目标写「已超目标」。
  static String statusLabel({
    required double consumedKcal,
    double? targetKcal,
  }) {
    if (targetKcal == null || targetKcal <= 0) return '未设目标';
    final ratio = consumedKcal / targetKcal;
    if (ratio > 1) return overTargetLabel;
    if (ratio >= 0.9) return '接近上限';
    return '额度充足';
  }

  /// 状态 pill 的档位（阶段 2B D20，取 A `app.js:125` 的三元式）：
  /// **已超目标换 warning 档**（honey 底，`refinement.css:3`
  /// `.pill.warning{background:#FFF4D6;color:#795700}`），其余走 mint 档。
  /// 恒 mint 会让「超了」与「额度充足」同色——颜色是这张卡唯一的分级通道，
  /// 而 `statusLabel` 已经是文字通道，两通道必须同步换挡。
  static LfBadgeVariant statusVariant({
    required double consumedKcal,
    double? targetKcal,
  }) =>
      statusLabel(consumedKcal: consumedKcal, targetKcal: targetKcal) ==
          overTargetLabel
      ? LfBadgeVariant.honey
      : LfBadgeVariant.mint;

  /// 超目标档的文案（[statusVariant] 的分档判据与它同源，避免两处各写一遍
  /// 字符串常量后漂移）。
  static const String overTargetLabel = '已超目标';

  /// 宏量占比（4/4/9 kcal/g）。无可计算总量时返回 null（全 0 摄入）。
  static (int protein, int carbs, int fat)? macroRatios(
    NutritionValues consumed,
  ) {
    final proteinKcal = consumed.proteinGrams * 4;
    final carbsKcal = consumed.carbsGrams * 4;
    final fatKcal = consumed.fatGrams * 9;
    final total = proteinKcal + carbsKcal + fatKcal;
    if (total <= 0) return null;
    final p = (proteinKcal / total * 100).round();
    final c = (carbsKcal / total * 100).round();
    // 脂肪取余数：三数之和恒为 100，不会因四舍五入出现 99/101。
    return (p, c, (100 - p - c).clamp(0, 100));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final targets = target;
    final hasGoal = targets != null && targets.calorieMaxKcal > 0;
    final remaining = hasGoal ? targets.calorieMaxKcal - consumed.kcal : null;

    final macroRows = [
      (
        key: const Key('nutrition-macro-protein'),
        label: '蛋白质',
        color: c.protein,
        current: consumed.proteinGrams.round(),
        target: targets?.proteinMaxGrams.round() ?? 0,
      ),
      (
        key: const Key('nutrition-macro-carbs'),
        label: '碳水',
        color: c.carbs,
        current: consumed.carbsGrams.round(),
        target: targets?.carbsMaxGrams.round() ?? 0,
      ),
      (
        key: const Key('nutrition-macro-fat'),
        label: '脂肪',
        color: c.fat,
        current: consumed.fatGrams.round(),
        target: targets?.fatMaxGrams.round() ?? 0,
      ),
    ];
    final macros = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final row in macroRows) ...[
          MacroBar(
            key: row.key,
            label: row.label,
            color: row.color,
            current: row.current,
            target: row.target,
          ),
          // A `.macro-summary{gap:12px}`。
          if (row != macroRows.last)
            const SizedBox(height: LfDimens.spaceMedium),
        ],
      ],
    );

    return DesignCard(
      key: cardKey,
      // A `.energy-summary{padding:16px}`（refinement.css，无前缀覆盖）：
      // 四边均 16。2A 曾按 `16px 18px 18px` 实现——那是漏看选择器前缀的
      // 读数；本轮浏览器实测（getComputedStyle）四边都是 16，已改正。
      padding: const EdgeInsets.all(LfDimens.spaceLarge),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DesignCardHeader(
            title: title,
            trailing: LfBadge(
              statusLabel(
                consumedKcal: consumed.kcal,
                targetKcal: targets?.calorieMaxKcal,
              ),
              key: statusKey,
              variant: statusVariant(
                consumedKcal: consumed.kcal,
                targetKcal: targets?.calorieMaxKcal,
              ),
            ),
          ),
          _main(context, macros),
          _foot(context, hasGoal: hasGoal, remaining: remaining),
          const SizedBox(height: LfDimens.spaceSmallPlus),
          if (macroRatios(consumed) case final ratios?)
            MacroRatioRow(
              key: ratiosKey ?? const Key('energy-card-macro-ratios'),
              leading: '能量占比',
              entries: [
                ('蛋白质', c.protein, ratios.$1),
                ('碳水', c.carbs, ratios.$2),
                ('脂肪', c.fat, ratios.$3),
              ],
            )
          else
            Text(
              '暂无记录，记录后显示营养占比',
              key: ratiosKey ?? const Key('energy-card-macro-ratios'),
              style: LfText.micro.copyWith(color: c.mutedForeground),
            ),
        ],
      ),
    );
  }

  /// 环 + 宏量列。A 是无断点的 `grid 120px|1fr`；放不下（320dp 或大字号）
  /// 时竖排降级——判据沿用 [fitsRow] 的设计稿预算口径（docs/27 §6）。
  Widget _main(BuildContext context, Widget macros) {
    final ring = LfCalorieRing(
      consumedKcal: consumed.kcal.round(),
      targetKcal: target?.calorieMaxKcal.round() ?? 0,
      keyPrefix: keyPrefix,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!fitsRow(
          context,
          available: constraints.maxWidth,
          baseNeed: LfRowBudgets.calorieCard,
        )) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: mainVerticalPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(child: ring),
                const SizedBox(height: LfDimens.spaceLarge),
                macros,
              ],
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: mainVerticalPadding),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ring,
              const SizedBox(width: gridColumnGap),
              Expanded(child: macros),
            ],
          ),
        );
      },
    );
  }

  /// 脚注：目标 + 还可摄入/超出（A `.energy-foot`）。
  Widget _foot(
    BuildContext context, {
    required bool hasGoal,
    required double? remaining,
  }) {
    final c = context.lf;
    final value = remaining;
    final targetKcal = target?.calorieMaxKcal;
    final goalText = Text(
      // A `.energy-foot` 左格 = `'目标 '+format(goal)+' kcal'`，
      // `format()` 是 `toLocaleString`，四位数起带千分位（与本页
      // 饮水/步数/下一餐三张卡同一口径）。数值语义不变（仍取整），
      // 只对齐 A 的书写形式。
      hasGoal && targetKcal != null
          ? '目标 ${withThousandsSeparator(targetKcal.round())} kcal'
          : '尚未设定目标',
      key: Key('$keyPrefix-target'),
      style: LfText.label.copyWith(color: c.mutedForeground),
    );
    final progressText = value == null
        ? Text(
            '设置目标后查看进度',
            style: LfText.label.copyWith(color: c.mutedForeground),
          )
        : Text.rich(
            key: remainingKey,
            TextSpan(
              style: LfText.label.copyWith(color: c.mutedForeground),
              children: [
                TextSpan(text: value >= 0 ? '还可摄入 ' : '超出 '),
                TextSpan(
                  // A：`format(Math.abs(remaining))`（四位起千分位）。
                  text: withThousandsSeparator(value.abs().round()),
                  style: LfText.caption.copyWith(
                    color: LfColors.mintText(Theme.of(context).brightness),
                    fontWeight: FontWeight.w600,
                    fontFeatures: LfText.caption.fontFeatures,
                  ),
                ),
                const TextSpan(text: ' kcal'),
              ],
            ),
          );
    return Container(
      padding: const EdgeInsets.only(top: footPaddingTop),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: context.lfc.ringTrack)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // A 的 `.energy-foot` 是**两端对齐的一行**（原型无断点）。但大字
          // 字态下这两段各自就要一整行：2.0× / 320dp 实测右段单独需要
          // 344dp、卡内只有 252dp ⇒ 并排必溢 92px（round7 2A 实测的
          // RenderFlex：左段被 `Expanded` 压成 ~0 宽、逐字竖排，右段仍出界）。
          // 判据沿用本卡 `_main` 的 [fitsRow] 预算口径（docs/27 §6）：
          // 放不下就竖排——两句事实都留，不裁字也不缩字号。
          if (!fitsRow(
            context,
            available: constraints.maxWidth,
            baseNeed: LfRowBudgets.energyFoot,
          )) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                goalText,
                const SizedBox(height: LfDimens.spaceXSmall),
                progressText,
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: goalText),
              progressText,
            ],
          );
        },
      ),
    );
  }
}
