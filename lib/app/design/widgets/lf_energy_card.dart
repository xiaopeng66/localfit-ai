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
    this.onEditTarget,
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

  /// 点「依据 / 尚未设定目标」那一格时做什么（null = 不可点）。
  ///
  /// 2026-10-26：记录页接上「手动指定营养目标」弹层；今日页不接（null），
  /// 两处观感不变——不给点了没反应的入口。
  final VoidCallback? onEditTarget;

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
    // 需求 1（2026-10-25 用户：「要区间的方案」）：
    // 「还可摄入」也是**区间** —— 下限侧 `min − 已摄入`、上限侧 `max − 已摄入`。
    // 原来只算 `max − 已摄入`（一个保守的单值），与卡头/三宏量的区间口径不一致。
    // 两侧都夹到 0（`docs/60` §9 的写法）：负数侧不是「你可以欠着」，而是
    // 「这一侧已经没有余量」——`还可摄入 0–492` 比 `−8–492` 诚实也读得懂。
    final remainingLow = hasGoal
        ? (targets.calorieMinKcal - consumed.kcal).clamp(0.0, double.infinity)
        : null;
    final remainingHigh = hasGoal
        ? (targets.calorieMaxKcal - consumed.kcal).clamp(0.0, double.infinity)
        : null;
    final overLimit = hasGoal && targets.calorieMaxKcal - consumed.kcal < 0;

    final macroRows = [
      (
        key: const Key('nutrition-macro-protein'),
        label: '蛋白质',
        color: c.protein,
        current: consumed.proteinGrams.round(),
        // 未设目标 ⇒ **null**（不写「/ 0 g」：那是编出来的目标）。
        target: targets?.proteinMaxGrams.round(),
        targetMin: targets?.proteinMinGrams.round(),
      ),
      (
        key: const Key('nutrition-macro-carbs'),
        label: '碳水',
        color: c.carbs,
        current: consumed.carbsGrams.round(),
        target: targets?.carbsMaxGrams.round(),
        targetMin: targets?.carbsMinGrams.round(),
      ),
      (
        key: const Key('nutrition-macro-fat'),
        label: '脂肪',
        color: c.fat,
        current: consumed.fatGrams.round(),
        target: targets?.fatMaxGrams.round(),
        targetMin: targets?.fatMinGrams.round(),
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
            targetMin: row.targetMin,
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
          // 【需求 1】卡头大号位写**目标区间**（不再显示单个上限/中点）。
          // 用户原话：「要区间的方案，另外你的热量目标……都要根据区间来设计」。
          _targetRangeLine(context, targets),
          _main(context, macros),
          _foot(
            context,
            hasGoal: hasGoal,
            remainingLow: remainingLow,
            remainingHigh: remainingHigh,
            overLimit: overLimit,
          ),
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

  /// 卡头下方的**目标区间行**（需求 1）：`1,700 – 1,900 kcal` + 依据一行。
  ///
  /// 【为什么要独立一行】原来「目标」只出现在卡脚（`目标 N kcal`，单值），
  /// 与「今天还剩多少」chip 的区间口径对不上——用户看到同一件事两种说法。
  /// 现在卡头说的是**区间本身**（大号），依据（公式与目标档）跟在它下面一行。
  ///
  /// 锚点仍挂在 `$keyPrefix-target` 上（docs/21 §5.1 的今日页 Key 表不变，
  /// 只是内容从单值变成区间）。
  Widget _targetRangeLine(BuildContext context, DailyNutritionTarget? targets) {
    final c = context.lf;
    final min = targets?.calorieMinKcal;
    final max = targets?.calorieMaxKcal;
    if (targets == null || min == null || max == null || max <= 0) {
      // 未设目标：如实说，不编区间（§6.1「未设目标不编数字」的既有规则）。
      return Padding(
        padding: const EdgeInsets.only(top: LfDimens.spaceSmall),
        child: Text(
          '尚未设定目标',
          key: Key('$keyPrefix-target'),
          style: LfText.label.copyWith(color: c.mutedForeground),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: LfDimens.spaceSmall),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 大号区间（与环心「已摄入」同一档次的家常写法：数字 + 小单位）。
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${withThousandsSeparator(min.round())} – '
                  '${withThousandsSeparator(max.round())}',
                  key: Key('$keyPrefix-target'),
                  // 档位取 `headline`（19px）：比正文强、比环心的大数字弱——
                  // 它是「这份目标」的标题数字，不与「已摄入」抢主位。
                  style: LfText.headline.copyWith(
                    color: c.cardForeground,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: LfDimens.spaceXSmall),
                Text(
                  'kcal',
                  style: LfText.caption.copyWith(color: c.mutedForeground),
                ),
              ],
            ),
          ),
          // 【依据只出现一次】它放在卡脚左格（`-foot-basis`）——那里本来就
          // 是「目标 N kcal」的位置。这里不再重复一遍：同一个事实写两次是
          // 噪音（取帧复核的第一版就是两处都有，测试立刻抓到 findsNWidgets(2)）。
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
      // 需求 1：把区间下限交给环 —— 环上画「绿带 = 目标区间」+ 指针。
      targetMinKcal: target?.calorieMinKcal.round(),
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
    required double? remainingLow,
    required double? remainingHigh,
    required bool overLimit,
  }) {
    final c = context.lf;
    final high = remainingHigh;
    final over = overLimit;
    // 超上限时右格报「超出」的量：`已摄入 − max`（两侧已夹到 0，所以这里
    // 用目标上限反推真实超出量）。
    final overBy = over
        ? (consumed.kcal - (target?.calorieMaxKcal ?? consumed.kcal))
        : 0.0;
    // 【2026-10-28 用户】「这里文字换行了，不要显示左边那个说明」：脚注左格
    // 的公式/档位说明（「Mifflin–St Jeor × 活动系数，减脂 −15%」）撤下。
    // 「推荐要有依据」的口径由 docs/60 §9 承担（数据核实表 + 计算器单测），
    // 卡上不再占一行。左格让给**编辑目标入口**（铅笔圆钮，仅记录页接线时
    // 出现；今日页不接 ⇒ 脚注只剩右侧「还可摄入」一行，永不再换行）。
    //
    // 未设目标时的「尚未设定目标」仍保留在**卡头区间行**（`-target`），
    // 那是「没目标」的诚实文案位。

    /// 编辑目标入口（图标钮，整枚可点）。[onEditTarget] 为 null 时左格不渲染。
    ///
    /// 【为什么只给图标不给文字】左格的所有文字（公式 + 档位，以及
    /// 「尚未设定目标」的重复）全部撤下；「没目标」的诚实文案留在卡头区间行
    /// （`-target`）。图标钮 18dp 在 320dp × 2.0× 下也放得下，不再需要
    /// 「余量够才画图标」的降级分支。
    Widget? editTargetEntry() {
      final onTap = onEditTarget;
      if (onTap == null) return null;
      return Semantics(
        button: true,
        label: '调整营养目标',
        child: InkWell(
          key: Key('$keyPrefix-edit-target'),
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Padding(
            padding: const EdgeInsets.all(LfDimens.spaceSmall),
            child: Icon(Icons.tune, size: 18, color: c.mutedForeground),
          ),
        ),
      );
    }

    final progressText = !hasGoal || high == null
        ? Text(
            '设置目标后查看进度',
            style: LfText.label.copyWith(color: c.mutedForeground),
          )
        : Text.rich(
            key: remainingKey,
            TextSpan(
              style: LfText.label.copyWith(color: c.mutedForeground),
              children: [
                TextSpan(text: over ? '超出 ' : '还可摄入 '),
                TextSpan(
                  // 【需求 1】区间写法：`450–850 kcal`（超过上界时只报超出量，
                  // 那是单个事实，不写成区间）。
                  text: over
                      ? withThousandsSeparator(overBy.round())
                      : '${withThousandsSeparator(remainingLow!.round())}–'
                            '${withThousandsSeparator(high.round())}',
                  style: LfText.caption.copyWith(
                    color: over
                        ? c.warningText
                        : LfColors.mintText(Theme.of(context).brightness),
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
          // A 的 `.energy-foot` 是**两端对齐的一行**（原型无断点）。2026-10-28
          // 起左格只剩（可选的）编辑目标图标钮：无入口时脚注就是右侧一句话，
          // 恒单行；有入口时图标在左、「还可摄入」在右（18dp 图标 + 一句
          // 话在 320dp × 2.0× 也放得下——右段本身有 FittedBox 兜底不了，
          // 所以放不下时图标升到上方一行，两句事实都在、不裁不缩）。
          final entry = editTargetEntry();
          if (entry == null) {
            return Align(alignment: Alignment.centerLeft, child: progressText);
          }
          if (!fitsRow(
            context,
            available: constraints.maxWidth,
            baseNeed: LfRowBudgets.energyFoot,
          )) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                entry,
                const SizedBox(height: LfDimens.spaceXSmall),
                progressText,
              ],
            );
          }
          return Row(
            children: [
              Expanded(
                child: Align(alignment: Alignment.centerLeft, child: entry),
              ),
              progressText,
            ],
          );
        },
      ),
    );
  }
}
