import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/design_card.dart';
import 'package:localfit_ai/app/design/widgets/lf_badge.dart';
import 'package:localfit_ai/app/design/widgets/lf_buttons.dart';
import 'package:localfit_ai/features/nutrition/application/build_daily_meal_recommendation.dart';
import 'package:localfit_ai/features/nutrition/domain/dish_record.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/dish_card.dart';

/// 某一餐当前展示的候选（「换一个」的偏移由页面持有）。
final class DailyMealSetSlotView {
  const DailyMealSetSlotView({
    required this.candidates,
    this.displayed,
    this.displayedIndex = 0,
  });

  final List<DishRecord> candidates;
  final DishRecord? displayed;
  final int displayedIndex;
}

/// 「今日三餐推荐」整套卡（2026-10-22 用户：**根据食堂菜品，直接给出从早餐
/// 到晚餐的一整套推荐，而不是分开**）。
///
/// 旧形态是三张独立的 `DesignCard`（早/午/晚各一块），数据虽然由同一个
/// [buildDailyMealRecommendation] 一次算出，但视觉上是三件互不相干的东西。
/// 现在收进**一张卡**：卡头说明这是「一整套」，卡内三段用分隔线连接，同一道
/// 菜不跨餐重复这条规则也写在卡头上。
///
/// 内部仍按餐次保留 `nutrition-menu-meal-<slot>` 这族 Key：既有测试、截图
/// 与 docs/21 Key 表都以它为锚；变的是外壳（三张卡 → 一张卡），不是每餐的
/// 内容与动作。
class DailyMealSetCard extends StatelessWidget {
  const DailyMealSetCard({
    super.key,
    required this.meals,
    required this.views,
    required this.onShowCandidates,
    required this.onAddToMeal,
    required this.onOpenCanteen,
    required this.onLike,
    required this.onRepickSet,
  });

  /// 早/午/晚三段的推荐结果（顺序即展示顺序）。
  final List<MealRecommendation> meals;

  /// 每餐当前展示的候选。
  final Map<MealSlot, DailyMealSetSlotView> views;

  final void Function(MealSlot slot) onShowCandidates;
  final Future<void> Function(DishRecord dish)? onAddToMeal;
  final VoidCallback? onOpenCanteen;
  final Future<void> Function(DishRecord dish) onLike;

  /// 「换一整套」（`RV4-P2-08` / `docs/56` R10-a，已锁裁决 D3）。
  ///
  /// **一直可点**：未配置 AI 时走本地重排 + 一句实话（不出死按钮、也不隐藏）。
  final VoidCallback onRepickSet;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    return DesignCard(
      key: const Key('nutrition-menu-daily-set'),
      // 横向内边距交给卡头与每段自己：这样 `nutrition-menu-meal-<slot>` 的
      // 矩形仍是「整卡宽 - 两侧 16」，既有几何断言（「换一个」落在卡内右
      // 边界）不用改口径。
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              LfDimens.cardPadding,
              LfDimens.spaceMediumPlus,
              LfDimens.cardPadding,
              0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: LfDimens.spaceSmall,
                  runSpacing: LfDimens.spaceXSmall,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '今日三餐推荐',
                      key: const Key('nutrition-menu-daily-set-title'),
                      style: LfText.title.copyWith(color: c.cardForeground),
                    ),
                    const LfBadge.mint(
                      '一整套',
                      key: Key('nutrition-menu-daily-set-badge'),
                    ),
                  ],
                ),
                const SizedBox(height: LfDimens.spaceXSmall),
                Text(
                  '早餐 → 午餐 → 晚餐 一次排出 · 同一道菜不跨餐重复 · '
                  '换就整整齐齐换一套',
                  key: const Key('nutrition-menu-daily-set-intro'),
                  style: LfText.caption.copyWith(color: c.mutedForeground),
                ),
                const SizedBox(height: LfDimens.spaceSmallPlus),
                // `RV4-P2-08`（`docs/56` R10-a / D3）：「换一整套」。
                // 三格各自的「换一个」退役后，这是整套重排的唯一入口。
                LfPillButton(
                  key: const Key('nutrition-menu-daily-set-repick'),
                  label: '换一整套',
                  icon: Icons.shuffle,
                  height: LfDimens.minTouchTarget,
                  onPressed: onRepickSet,
                ),
              ],
            ),
          ),
          for (var i = 0; i < meals.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                indent: LfDimens.cardPadding,
                endIndent: LfDimens.cardPadding,
                color: c.border,
              ),
            _MealSection(
              recommendation: meals[i],
              view:
                  views[meals[i].slot] ??
                  const DailyMealSetSlotView(candidates: []),
              index: i,
              onShowCandidates: () => onShowCandidates(meals[i].slot),
              onAddToMeal: onAddToMeal,
              onOpenCanteen: onOpenCanteen,
              onLike: onLike,
            ),
          ],
        ],
      ),
    );
  }
}

/// 整套卡里的一段（原 `_MealBlock` 的内容，外壳从独立卡变成卡内一段）。
class _MealSection extends StatelessWidget {
  const _MealSection({
    required this.recommendation,
    required this.view,
    required this.index,
    required this.onShowCandidates,
    required this.onAddToMeal,
    required this.onOpenCanteen,
    required this.onLike,
  });

  final MealRecommendation recommendation;
  final DailyMealSetSlotView view;

  /// 三餐段在页面里的序号（0..2）：菜品卡的 Key 用它。
  final int index;
  final VoidCallback onShowCandidates;
  final Future<void> Function(DishRecord dish)? onAddToMeal;
  final VoidCallback? onOpenCanteen;
  final Future<void> Function(DishRecord dish) onLike;

  MealSlot get _slot => recommendation.slot;

  /// 本段所有 Key 的前缀。字面前缀必须写在 `Key('…')` 里：docs/21 Key 表
  /// 的三方对账只认字面 Key 里的前缀。
  Key _mealKey([String suffix = '']) =>
      Key('nutrition-menu-meal-${_slot.storedValue}$suffix');

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final displayed = view.displayed;
    final swapEnabled = view.candidates.length > 1;
    return Padding(
      key: _mealKey(),
      padding: const EdgeInsets.symmetric(
        horizontal: LfDimens.cardPadding,
        vertical: LfDimens.spaceMediumPlus,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // heading 行（A `.section-title.with-link`）：左端槽名 + 时段带 +
          // 状态徽标，右端「不错 / 换一个」。
          SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: LfDimens.spaceSmall,
              runSpacing: LfDimens.spaceXSmall,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Wrap(
                  spacing: LfDimens.spaceSmall,
                  runSpacing: LfDimens.spaceXSmall,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      _slot.label,
                      style: LfText.title.copyWith(color: c.cardForeground),
                    ),
                    Text(
                      mealBandLabels[_slot]!,
                      style: LfText.caption.copyWith(color: c.mutedForeground),
                    ),
                    _statusBadge(),
                  ],
                ),
                // `RV4-P2-08`（`docs/56` R10-a）：「换一个」退役——三格各换
                // 一个会破坏整套营养平衡（用户：「换就整整齐齐换一套」）。
                // 整套重排的入口在卡头（`nutrition-menu-daily-set-repick`）。
                if (displayed != null)
                  LfTextButton(
                    key: _mealKey('-like'),
                    label: '不错',
                    onPressed: () => onLike(displayed),
                  ),
              ],
            ),
          ),
          const SizedBox(height: LfDimens.spaceSmall),
          if (displayed != null) ...[
            DishCard(
              dish: displayed,
              index: index,
              // 进度条分母是**本餐预算**（不是全天目标）。
              targetKcal: recommendation.budgetKcal,
              progressLabel: '本餐预算',
              // 加入动作归段底动作行，按钮不画在卡内。
              showAddButton: false,
            ),
            const SizedBox(height: LfDimens.spaceSmall),
            Text(
              recommendation.reason,
              key: _mealKey('-reason'),
              style: LfText.caption.copyWith(color: c.mutedForeground),
            ),
            if (swapEnabled || onAddToMeal != null) ...[
              const SizedBox(height: LfDimens.spaceSmallPlus),
              _HostActionRow(
                candidatesKey: _mealKey('-candidates'),
                candidatesLabel: '查看候选 ${view.candidates.length} 道',
                onShowCandidates: onShowCandidates,
                addKey: Key('cta-add-meal-$index'),
                // 文案取**菜自己的餐次**：`AddDishToMeal` 写的是
                // `dish.mealSlot`，按钮说的必须是同一件事。
                addLabel: '加入${DishCard.mealSlotLabel(displayed.mealSlot)}',
                onAdd: onAddToMeal == null
                    ? null
                    : () => onAddToMeal!(displayed),
              ),
            ],
          ] else ...[
            Text(
              recommendation.reason,
              key: _mealKey('-reason'),
              style: LfText.body.copyWith(color: c.cardForeground),
            ),
            // 空态「一个行动」：只有真的接了线的动作才画按钮。
            if (recommendation.action == MealEmptyAction.openCanteen &&
                onOpenCanteen != null) ...[
              const SizedBox(height: LfDimens.spaceSmall),
              Align(
                alignment: Alignment.centerLeft,
                child: LfPillButton(
                  key: _mealKey('-action'),
                  label: '去维护食堂目录',
                  icon: Icons.edit_note,
                  tone: LfPillTone.soft,
                  onPressed: onOpenCanteen,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _statusBadge() {
    final key = _mealKey('-badge');
    return switch (recommendation.state) {
      MealRecommendationState.planned => LfBadge.mint('已记录', key: key),
      MealRecommendationState.recommended => LfBadge.mint('已推荐', key: key),
      MealRecommendationState.empty => LfBadge.neutral('暂无推荐', key: key),
    };
  }
}

/// 段底动作行（A `.dish-action-row`）：候选链在左、加入钮在右。
///
/// **必须撑满整行宽**：`Wrap` 会收缩到最长一行的宽度，收缩之后
/// `spaceBetween` 没有可分配的余量，右端件只会挨着左组排。
class _HostActionRow extends StatelessWidget {
  const _HostActionRow({
    this.candidatesKey,
    this.candidatesLabel,
    this.onShowCandidates,
    this.addKey,
    this.addLabel,
    this.onAdd,
  });

  final Key? candidatesKey;
  final String? candidatesLabel;
  final VoidCallback? onShowCandidates;
  final Key? addKey;
  final String? addLabel;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      if (candidatesLabel != null)
        LfTextButton(
          key: candidatesKey,
          label: candidatesLabel!,
          onPressed: onShowCandidates,
        ),
      if (addLabel != null)
        LfSoftButton(key: addKey, label: addLabel!, onPressed: onAdd),
    ];
    if (children.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      width: double.infinity,
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: LfDimens.spaceSmall,
        runSpacing: LfDimens.spaceXSmall,
        children: children,
      ),
    );
  }
}
