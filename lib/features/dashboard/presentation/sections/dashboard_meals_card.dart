import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/number_format.dart';
import 'package:localfit_ai/app/design/widgets/design_card.dart';
import 'package:localfit_ai/app/design/widgets/lf_buttons.dart';
import 'package:localfit_ai/app/design/widgets/lf_empty_state.dart';
import 'package:localfit_ai/features/dashboard/presentation/sections/dashboard_confidence_summary.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';
import 'package:localfit_ai/features/nutrition/presentation/meal_slot_icons.dart';

/// 今日餐次列表里的一条（原「时间线」条目，docs/21 §5.1 MealTimelineCard）。
///
/// Round7 A 起卡片不再是竖线时间线而是普通行（`app.js:151` 的
/// `mealRows`），但**组装逻辑不变**：当天已记录的餐按就餐时刻升序。
final class RecordedTimelineEntry {
  RecordedTimelineEntry(this.meal)
    : slot = meal.slot,
      sortKey = _minutesOf(meal.eatenAt);

  final MealRecord meal;

  final MealSlot slot;

  /// 排序键：`eatenAt` 的分钟数。
  final int sortKey;

  /// 标题：餐次。
  String get title => slot.label;

  static int _minutesOf(DateTime value) {
    final local = value.toLocal();
    return local.hour * 60 + local.minute;
  }

  /// 就餐时刻（`HH:mm`）。
  String get timeLabel {
    final local = meal.eatenAt.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  /// 热量数值（不带单位，单位由行内 `kcal` 小字承担）。
  String get kcalLabel => withThousandsSeparator(meal.nutrition.kcal.round());

  String get metaLabel => '$timeLabel · ${meal.nutrition.kcal.round()} kcal';

  String get dishLabel => meal.items.isEmpty
      ? '暂无菜品明细'
      : meal.items.map((item) => item.foodName).join(' · ');
}

/// 时间线数据组装：当天已记录的餐，按就餐时刻排序。
List<RecordedTimelineEntry> buildMealTimeline({
  required List<MealRecord> meals,
}) {
  final entries = [for (final meal in meals) RecordedTimelineEntry(meal)];
  entries.sort((a, b) => a.sortKey.compareTo(b.sortKey));
  return List.unmodifiable(entries);
}

/// 今日餐次卡（Round7 A `.meals-card`，`app.js:151` + `styles.css:220-230`）。
///
/// 结构：`section-title.with-link`（「今天吃了什么」+「查看全部」）→ 行列表
/// （`mealRows`）或空态 → 置信摘要（[DashboardConfidenceSummary]，零餐不渲染，
/// 见证据文件阶段 2 决策 D5）→ 块级软底按钮「记录饮食」。
///
/// 行是**扁平行**不是时间线：A 的 `mealRows` 没有竖线与节点，一行里
/// 36dp 图标块 + （槽位 12 w600 + 时刻 11 muted）+ 菜名 12 muted +
/// 热量 14 w600（`kcal` 小字换行）。
///
/// 【行本身不可点】A 的今日页 `mealRows` 是静态行（没有 `data-action`），
/// 编辑入口是「查看全部」→ 记录页的行。旧件 `DashboardMealTimeline` 有一个
/// `onTapRecorded` 参数，但页面从未接线（实测点不动），所以这里不再保留
/// 该参数——不新增交互、也不留死参数。
class DashboardMealsCard extends StatelessWidget {
  const DashboardMealsCard({
    super.key,
    required this.entries,
    required this.meals,
    this.onViewAll,
    this.onLogMeal,
  });

  final List<RecordedTimelineEntry> entries;

  /// 原始餐食（置信摘要按食物项统计，需要完整记录）。
  final List<MealRecord> meals;

  /// 「查看全部」→ 饮食页记录 tab（A `link('查看全部','nutrition-records')`）。
  final VoidCallback? onViewAll;

  /// 「记录饮食」→ 打开餐食编辑（不指定槽位）。
  final VoidCallback? onLogMeal;

  /// A `.meals-card{padding-top:8px}`（其余三边仍是 `.card` 的 16）。
  static const EdgeInsets cardPadding = EdgeInsets.fromLTRB(
    LfDimens.spaceLarge,
    LfDimens.spaceSmall,
    LfDimens.spaceLarge,
    LfDimens.spaceLarge,
  );

  /// A `.meals-card > .btn{margin-top:9px}`。
  static const double buttonMarginTop = 9;

  /// A `.meal-row{gap:10px;padding:12px 0}`。
  static const double rowPadding = 12;
  static const double rowGap = 10;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    return DesignCard(
      key: const Key('dashboard-meals-card'),
      padding: cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '今天吃了什么',
                  style: LfText.title.copyWith(color: c.cardForeground),
                ),
              ),
              if (onViewAll != null)
                LfTextButton(
                  key: const Key('cta-view-all-meals'),
                  label: '查看全部',
                  onPressed: onViewAll,
                ),
            ],
          ),
          if (entries.isEmpty)
            LfEmptyState(
              key: const Key('dashboard-meals-empty'),
              icon: Icons.rice_bowl_outlined,
              title: '从第一餐开始',
              message: '从食物库选择，记录实际吃下的食物。',
            )
          else
            for (var i = 0; i < entries.length; i++)
              _MealRow(
                entry: entries[i],
                index: i,
                isLast: i == entries.length - 1,
              ),
          // 2026-10-22 用户：「已确认 n 项 / 估算 n 项没用就删了」+「不需要
          // 记录饮食的按钮」。两件整块退场：记餐入口仍在今日页的下一餐卡
          // （`cta-log-dinner`）与饮食页 FAB（`记录一餐`），不因删按钮而断路。
        ],
      ),
    );
  }
}

class _MealRow extends StatelessWidget {
  const _MealRow({
    required this.entry,
    required this.index,
    required this.isLast,
  });

  final RecordedTimelineEntry entry;
  final int index;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final content = Padding(
      padding: EdgeInsets.symmetric(vertical: DashboardMealsCard.rowPadding),
      child: Row(
        children: [
          // A `.meal-symbol{background:var(--bg);color:var(--muted)}`：
          // 灰底图标块（不是品牌色，餐次身份靠图标形状）。
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: c.background,
              borderRadius: BorderRadius.circular(LfDimens.radiusMd),
            ),
            child: Icon(
              entry.slot.icon,
              size: LfDimens.iconMd,
              color: c.mutedForeground,
            ),
          ),
          const SizedBox(width: DashboardMealsCard.rowGap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      entry.title,
                      style: LfText.captionStrong.copyWith(
                        color: c.cardForeground,
                      ),
                    ),
                    const SizedBox(width: LfDimens.spaceSmall),
                    // 长串（时刻 + 大字）放不下时整串等比缩小，不换行。
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          entry.timeLabel,
                          style: LfText.label.copyWith(
                            color: c.mutedForeground,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: LfDimens.spaceXSmall),
                Text(
                  entry.dishLabel,
                  style: LfText.caption.copyWith(color: c.mutedForeground),
                ),
              ],
            ),
          ),
          const SizedBox(width: DashboardMealsCard.rowGap),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                entry.kcalLabel,
                style: LfText.bodyStrong.copyWith(color: c.cardForeground),
              ),
              const SizedBox(height: 3),
              Text(
                'kcal',
                style: LfText.label.copyWith(
                  color: c.mutedForeground,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ],
      ),
    );

    return DecoratedBox(
      key: Key('dashboard-meal-row-${entry.slot.storedValue}-$index'),
      decoration: BoxDecoration(
        // A `.meal-row{border-bottom:1px solid var(--border)}`，末行不画。
        border: isLast ? null : Border(bottom: BorderSide(color: c.border)),
      ),
      child: content,
    );
  }
}
