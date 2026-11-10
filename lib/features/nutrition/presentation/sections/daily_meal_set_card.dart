import 'dart:async';
import 'dart:io';

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
import 'package:localfit_ai/features/nutrition/presentation/sections/dish_visuals.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/food_card.dart'
    show MacroDotLine;
import 'package:localfit_ai/features/retrieval/application/feedback_store.dart'
    show normalizeFeedbackName;

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
    this.likedDishNames = const {},
    this.swapping = false,
  });

  /// 早/午/晚三段的推荐结果（顺序即展示顺序）。
  final List<MealRecommendation> meals;

  /// 每餐当前展示的候选。
  final Map<MealSlot, DailyMealSetSlotView> views;

  /// 已点过「不错」的菜名（归一化）。命中的那一段把按钮换成「已记下」的
  /// 选中胶囊——点击结果要留在界面上，而不是只弹一条会消失的 SnackBar。
  final Set<String> likedDishNames;

  final void Function(MealSlot slot) onShowCandidates;
  final Future<void> Function(DishRecord dish, {MealSlot? slotOverride})?
  onAddToMeal;
  final VoidCallback? onOpenCanteen;
  final Future<void> Function(DishRecord dish) onLike;

  /// 「换一整套」（`RV4-P2-08` / `docs/56` R10-a，已锁裁决 D3）。
  ///
  /// **一直可点**：未配置 AI 时走本地重排 + 一句实话（不出死按钮、也不隐藏）。
  final VoidCallback onRepickSet;

  /// 【R-4】内联 AI 换一套进行中：按钮转「挑菜中…」且禁用（不跳页、原地等）。
  final bool swapping;

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
                  // 【R-4】AI 换一套在**原界面**进行：按钮就地变「挑菜中…」，
                  // 不再跳 AI 对话页（用户原话：显示加载中、直接原地询问 AI）。
                  label: swapping ? 'AI 正在从食堂目录挑菜…' : '换一整套',
                  icon: swapping ? Icons.hourglass_top : Icons.shuffle,
                  height: LfDimens.minTouchTarget,
                  onPressed: swapping ? null : onRepickSet,
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
              likedDishNames: likedDishNames,
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
    required this.likedDishNames,
    required this.onShowCandidates,
    required this.onAddToMeal,
    required this.onOpenCanteen,
    required this.onLike,
  });

  final MealRecommendation recommendation;
  final DailyMealSetSlotView view;

  /// 三餐段在页面里的序号（0..2）：菜品卡的 Key 用它。
  final int index;
  final Set<String> likedDishNames;
  final VoidCallback onShowCandidates;
  final Future<void> Function(DishRecord dish, {MealSlot? slotOverride})?
  onAddToMeal;
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
    final liked =
        displayed != null &&
        likedDishNames.contains(normalizeFeedbackName(displayed.name));
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
                //
                // 【2026-11-02 用户：点完还是「不错」，只弹提示等于没反馈】
                // 已点过的菜画成选中胶囊「已记下」：颜色/图标/文案三者同时
                // 变化，并且这个状态来自落库的 `FeedbackStore`，重进页面
                // 仍然成立。仍可继续点——反馈计数需要两次同向才影响排序。
                if (displayed != null)
                  liked
                      ? LfPillButton(
                          key: _mealKey('-like'),
                          label: '已记下',
                          icon: Icons.check,
                          selected: true,
                          dense: true,
                          onPressed: () => onLike(displayed),
                        )
                      : LfTextButton(
                          key: _mealKey('-like'),
                          label: '不错',
                          icon: Icons.thumb_up_outlined,
                          onPressed: () => onLike(displayed),
                        ),
              ],
            ),
          ),
          const SizedBox(height: LfDimens.spaceSmall),
          if (displayed != null) ...[
            // 【2026-10-29（R-4，用户：推荐卡做小图模式、图在左、点图放大）】
            // 推荐段改用紧凑卡（左 64dp 缩略图 + 右详情）；Key
            // `nutrition-menu-dish-card-<n>` 沿用（既有测试与 Key 表的锚）。
            DishCompactCard(
              dish: displayed,
              index: index,
              slot: _slot,
              targetKcal: recommendation.budgetKcal,
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
                // 文案取**这一段推荐的餐次**：按钮说什么就必须记进哪一餐。
                // 菜品自己的 `mealSlot` 只是它在库里的默认归属（食堂窗口
                // 06:00–21:00 的菜会被算成「加餐」），拿它当按钮文案会让
                // 「午餐」段出现「加入加餐」，于是真的记进了加餐。
                addLabel: '加入${DishVisuals.mealSlotLabel(_slot.storedValue)}',
                onAdd: onAddToMeal == null
                    ? null
                    : () => onAddToMeal!(displayed, slotOverride: _slot),
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

/// 推荐段的小图卡（R-4，2026-10-29 用户：「小图模式，图片就放在卡片左边，
/// 右边是详细信息」「小图可以点击放大查看」）。
///
/// 左 64dp 圆角缩略图（有本地照片显示照片，没有用与 `DishCard` 同一套
/// 宏量渐变占位）+ 右侧详情（名称 / 餐次 · kcal / 三宏量 / 本餐预算条）。
/// 点缩略图 → 全屏查看（`InteractiveViewer`，不引第三方依赖）；无照片时
/// 不响应点击（不给点了没反应的入口）。
///
/// Key 与 `DishCard` 同口径：整卡 `nutrition-menu-dish-card-<n>`。
/// 2026-10-31 用户：推荐卡的右下三点菜单及其功能退役；菜品营养管理仍
/// 保留在食堂目录，不在「今天吃什么」的推荐卡上制造第二条管理路径。
class DishCompactCard extends StatelessWidget {
  const DishCompactCard({
    super.key,
    required this.dish,
    required this.index,
    required this.slot,
    this.targetKcal,
  });

  final DishRecord dish;
  final int index;

  /// 这张卡所在的推荐餐次（不是菜品自己的默认餐次）。
  final MealSlot slot;
  final double? targetKcal;

  static const double _thumbSize = 64;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final hasPhoto = (dish.imagePath ?? '').isNotEmpty;
    final budget = targetKcal;
    final ratio = budget == null || budget <= 0
        ? null
        : (dish.kcal / budget).clamp(0.0, 1.0);
    return DesignCard(
      key: Key('nutrition-menu-dish-card-$index'),
      padding: const EdgeInsets.all(LfDimens.spaceMedium),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 左：缩略图（可点放大）。
          Semantics(
            button: hasPhoto,
            label: hasPhoto ? '查看${dish.name}的图片' : null,
            child: GestureDetector(
              key: Key('nutrition-menu-dish-thumb-$index'),
              onTap: hasPhoto ? () => showDishImage(context, dish) : null,
              child: Container(
                width: _thumbSize,
                height: _thumbSize,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(LfDimens.radiusMd),
                  // 固定底色：图片在解码中/加载失败时都不是空白（占位渐变
                  // 画在 Box 上层）。
                  gradient: DishVisuals.placeholderGradient(context, dish),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(LfDimens.radiusMd),
                  child: hasPhoto
                      ? Image.file(
                          File(dish.imagePath!),
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              DishPhotoPlaceholder(dish: dish),
                        )
                      : DishPhotoPlaceholder(dish: dish),
                ),
              ),
            ),
          ),
          const SizedBox(width: LfDimens.spaceMedium),
          // 右：详情。
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        dish.name,
                        style: LfText.title.copyWith(color: c.cardForeground),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: LfDimens.spaceMicro),
                Text(
                  '${DishVisuals.mealSlotLabel(slot.storedValue)} · '
                  '${dish.kcal > 0 ? '${dish.kcal.round()} kcal' : '未分析营养'}',
                  style: LfText.caption.copyWith(color: c.mutedForeground),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: LfDimens.spaceXSmall),
                MacroDotLine(
                  protein: dish.proteinG,
                  carbs: dish.carbsG,
                  fat: dish.fatG,
                ),
                if (ratio != null) ...[
                  const SizedBox(height: LfDimens.spaceXSmall),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(LfDimens.radiusFull),
                    child: LinearProgressIndicator(
                      value: ratio,
                      minHeight: 4,
                      backgroundColor: c.muted,
                      valueColor: AlwaysStoppedAnimation(c.primary),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 全屏看图弹层（R-4）：`InteractiveViewer` 双指缩放 + 关闭。
/// 不引 `photo_view`（本轮不加依赖）。
Future<void> showDishImage(BuildContext context, DishRecord dish) {
  // 【2026-10-29 实机反馈】旧实现 Dialog 背景透明 + 黑遮罩：大图解码期间
  // 整屏近乎纯黑、只有一枚小关闭钮——用户实机看到的就是「软件黑屏了」。
  // 改为不透明黑底弹层（图片容器化），观感是「查看器」而不是「应用挂了」。
  return showDialog<void>(
    context: context,
    useRootNavigator: true,
    barrierColor: Colors.black54,
    builder: (dialogContext) => Dialog(
      key: const Key('dish-image-viewer'),
      backgroundColor: Colors.black,
      insetPadding: const EdgeInsets.all(12),
      child: Stack(
        children: [
          InteractiveViewer(
            maxScale: 4,
            child: Image.file(
              File(dish.imagePath!),
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => Center(
                child: Text(
                  '图片读取失败（文件可能已被删除）。',
                  style: LfText.body.copyWith(color: Colors.white),
                ),
              ),
            ),
          ),
          Positioned(
            top: 4,
            right: 4,
            // 共享图标钮（浅底圆，黑遮罩上仍可辨）；不用裸 IconButton。
            child: LfIconButton(
              key: const Key('dish-image-viewer-close'),
              icon: Icons.close,
              semanticLabel: '关闭大图',
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
          ),
        ],
      ),
    ),
  );
}
