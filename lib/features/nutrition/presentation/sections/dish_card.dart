import 'dart:io';

import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/design_card.dart';
import 'package:localfit_ai/app/design/widgets/lf_badge.dart';
import 'package:localfit_ai/app/design/widgets/lf_buttons.dart';
import 'package:localfit_ai/app/design/widgets/lf_progress_bar.dart';
import 'package:localfit_ai/features/nutrition/domain/dish_record.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_evidence.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart'
    show MealSlot;

/// 菜品卡（docs/21 §5.3 DishCard；docs/28 §4.2 强化三宏量小卡与主按钮位置）。
///
/// 结构：4:3 图片占位（无照片时渐变 + 图标，**不伪造菜品照片**）→ 餐次与
/// 供应时段角标 → 热门角标 → 菜名 → **三宏量小卡**（圆点 + 名称 + 克数 +
/// 该项热量贡献）→ 微量营养素行（有才渲染）→ 大号 kcal + 来源徽标 →
/// 每日目标进度条（有目标才渲染）→ 营养师点评块（有才渲染）→
/// 「加入早餐/午餐/晚餐」主按钮（卡底、整宽）。
///
/// 主按钮放卡底而不是与 kcal 同排：同排时它挤在大号数字右边当「小按钮」，
/// 而它是这张卡的主行动（docs/28 §4.2 末项）。
///
/// **2026-10-14（Round7 阶段 3 步骤 1，D27）** 起这枚按钮可关：[showAddButton]
/// ——菜单页把加入动作移到块底 `.dish-action-row`（A `app.js:182` 的
/// 「查看候选 N 道 + 加入<槽>」同排），卡内再画第二枚会让同一动作在一页上
/// 出现两种按钮档。默认 true，直连 `DishCard` 的其它调用者与既有单测不变。
///
/// **不渲染设计稿的「配料行」**：`DishLibrary` 没有配料列，§5.3 的数据来源表
/// 也逐项列了每个元素取哪个列、唯独没有它（docs/21 §6.2 裁决 13）。
/// 凭菜名去猜配料就是编事实。
class DishCard extends StatelessWidget {
  const DishCard({
    super.key,
    required this.dish,
    required this.index,
    this.targetKcal,
    this.progressLabel = defaultProgressLabel,
    this.onAddToMeal,
    this.showAddButton = true,
  });

  /// 进度条说明的默认值：分母是全天的目标。
  static const String defaultProgressLabel = '每日目标进度';

  final DishRecord dish;

  /// 列表序号（测试 Key `nutrition-menu-dish-card-<n>` / `cta-add-meal-<n>`）。
  final int index;

  /// 进度条分母（`DailyTargets.calorieMaxKcal`；菜单页三餐块传的是**该餐
  /// 预算**）；null → 不画进度条。
  final double? targetKcal;

  /// 进度条说明：分母是全天目标还是本餐预算，同一句话说不清两件事。
  final String progressLabel;

  /// null → 不渲染「加入」按钮（未接线时不给点了没反应的按钮）。
  final Future<void> Function(DishRecord dish)? onAddToMeal;

  /// false → 卡内不画「加入」按钮，由宿主画（菜单页的块底动作行，D27）。
  /// [onAddToMeal] 仍要传：宿主用它同一份回调。
  final bool showAddButton;

  // 2026-10-24（`RV4-P2-09` / `docs/56` R10-c，已锁裁决 D2）：
  // 「陈旧提示 + 手动同步」整族退役——自动同步已覆盖建菜/改名/换照片/
  // 写营养/删菜/删窗口/删地点七条写路径，正常路径下陈旧状态不可能出现；
  // 唯一还能出现的是「用户手改过营养」的行，而那种行现在**冻结**
  // （`DishLibraryRepository.upsertBySource` 跳过 `userEdited`）。
  // 所以 `staleness` / `onSync` 两个参数与那枚角标、那条「同步」链一起删除。

  /// 三宏量中哪一项热量贡献最大（用于图片占位的色系映射）。
  static MacroAccent dominantMacro(DishRecord dish) {
    final protein = dish.proteinG * 4;
    final carbs = dish.carbsG * 4;
    final fat = dish.fatG * 9;
    if (protein >= carbs && protein >= fat) return MacroAccent.protein;
    if (carbs >= fat) return MacroAccent.carbs;
    return MacroAccent.fat;
  }

  /// 餐次的中文标签。库里存的是 `breakfast` 这类存储值（`MealSlot`），
  /// 直接渲染会把 `breakfast` 印在角标和按钮上。
  static String mealSlotLabel(String storedValue) =>
      MealSlot.fromStoredValue(storedValue).label;

  /// 图片占位的渐变：按**主要宏量**稳定映射（docs/21 §2.5），同一道菜每次
  /// 渲染同一个色系——按 `index` 取色会让列表滚动后颜色乱跳。
  static LinearGradient placeholderGradient(
    BuildContext context,
    DishRecord dish,
  ) {
    final c = context.lf;
    final brightness = Theme.of(context).brightness;
    return switch (dominantMacro(dish)) {
      MacroAccent.protein => LfGradients.proteinPlaceholder(c),
      MacroAccent.carbs => LfGradients.mintPlaceholder(brightness),
      MacroAccent.fat => LfGradients.fatPlaceholder(c),
    };
  }

  /// 菜名行的图标（设计稿是三张卡各配 utensils / salad / fish）。
  static IconData placeholderIcon(DishRecord dish) =>
      switch (dominantMacro(dish)) {
        MacroAccent.protein => Icons.egg_alt_outlined,
        MacroAccent.carbs => Icons.rice_bowl_outlined,
        MacroAccent.fat => Icons.set_meal_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final progress = dish.targetProgress(targetKcal);
    final micro = <(IconData, String, String)>[];
    // 微量营养素：null = 无数据 → **不渲染该项**（docs/21 §6.2 裁决 10）。
    if (dish.fiberG case final fiber?) {
      micro.add((Icons.grass_outlined, '膳食纤维', '${_grams(fiber)}g'));
    }
    if (dish.sodiumMg case final sodium?) {
      micro.add((Icons.water_drop_outlined, '钠', '${_grams(sodium)}mg'));
    }
    if (dish.vitaminDMcg case final vitaminD?) {
      micro.add((Icons.wb_sunny_outlined, '维D', '${_grams(vitaminD)}μg'));
    }

    // 卡壳收归 §3.1 的 DesignCard（原手写 DecoratedBox + ClipRRect，逐字复刻的
    // 就是 DesignCard 的形态）。内容自带内边距（首层是 4:3 图片头，不带内边距），
    // 所以这里 padding 归零。
    return DesignCard(
      key: Key('nutrition-menu-dish-card-$index'),
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PhotoHeader(dish: dish, index: index),
          Padding(
            padding: const EdgeInsets.all(LfDimens.cardPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dish.name,
                  style: LfText.titleLarge.copyWith(color: c.cardForeground),
                ),
                const SizedBox(height: LfDimens.spaceMedium),
                // 三宏量小卡（docs/28 §4.2）：圆点 + 名称 + 克数 + 该项热量
                // 贡献。贡献值由克数按 4/4/9 算出（本文件的 `dominantMacro`
                // 早就在用同一套系数），是既有数据的算术，不是编事实。
                _MacroTileRow(dish: dish, index: index),
                if (micro.isNotEmpty) ...[
                  const SizedBox(height: LfDimens.spaceSmall),
                  Wrap(
                    spacing: LfDimens.spaceMedium,
                    runSpacing: LfDimens.spaceXSmall,
                    children: [
                      for (final (icon, label, value) in micro)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(icon, size: 12, color: c.mutedForeground),
                            const SizedBox(width: LfDimens.spaceXSmall),
                            Text(
                              '$label $value',
                              style: LfText.caption.copyWith(
                                color: c.mutedForeground,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: LfDimens.spaceMedium),
                Wrap(
                  spacing: LfDimens.spaceSmall,
                  runSpacing: LfDimens.spaceSmall,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '${dish.kcal.round()} kcal',
                      style: LfText.headline.copyWith(color: c.cardForeground),
                    ),
                    evidenceBadgeForSource(
                      dish.source,
                      key: Key('nutrition-menu-dish-source-$index'),
                    ),
                    // 份量未知（历史回填 / 从未填过）⇒ 明确标「按 100g 估算」，
                    // 不假装知道这一份多少克（docs/41 D8）。
                    if (dish.basisAssumed)
                      LfBadge.neutral(
                        '按 100g 估算',
                        key: Key('nutrition-menu-dish-basis-$index'),
                      ),
                  ],
                ),
                if (progress != null) ...[
                  const SizedBox(height: LfDimens.spaceMedium),
                  Row(
                    children: [
                      Text(
                        progressLabel,
                        style: LfText.micro.copyWith(color: c.mutedForeground),
                      ),
                      const Spacer(),
                      Text(
                        '${(progress * 100).round()}%',
                        style: LfText.micro.copyWith(color: c.mutedForeground),
                      ),
                    ],
                  ),
                  const SizedBox(height: LfDimens.spaceXSmall),
                  LfProgressBar(value: progress),
                ],
                // 营养师点评：为空则**整块不渲染**（docs/21 §6.1）。
                if (dish.comment case final comment?)
                  Padding(
                    padding: const EdgeInsets.only(top: LfDimens.spaceMedium),
                    child: Container(
                      key: Key('nutrition-menu-dish-comment-$index'),
                      padding: const EdgeInsets.only(top: LfDimens.spaceMedium),
                      decoration: BoxDecoration(
                        border: Border(top: BorderSide(color: c.border)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.format_quote,
                            size: 16,
                            color: LfColors.mint(Theme.of(context).brightness)
                                .tone(600),
                          ),
                          const SizedBox(width: LfDimens.spaceSmall),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '营养师点评',
                                  style: LfText.microStrong.copyWith(
                                    color: LfColors.mint(
                                      Theme.of(context).brightness,
                                    ).tone(600),
                                  ),
                                ),
                                const SizedBox(height: LfDimens.spaceMicro),
                                Text(
                                  comment,
                                  style: LfText.caption.copyWith(
                                    color: c.mutedForeground,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                // 主按钮（docs/28 §4.2 末项）：卡底、整宽。
                if (onAddToMeal != null && showAddButton) ...[
                  const SizedBox(height: LfDimens.spaceMedium),
                  LfPrimaryButton(
                    key: Key('cta-add-meal-$index'),
                    icon: Icons.add,
                    label: '加入${mealSlotLabel(dish.mealSlot)}',
                    expand: true,
                    onPressed: () => onAddToMeal!(dish),
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

/// 4:3 图片区：有本地照片就显示照片，否则渐变占位（docs/21 §2.5 / §6.1）。
///
/// 供应时段在这里**只画一次**（右上角）：卡体里再画一行会让同一信息在一张
/// 卡上出现两次，且设计稿的卡体行是「配料行」不是时段行。
class _PhotoHeader extends StatelessWidget {
  const _PhotoHeader({required this.dish, required this.index});

  final DishRecord dish;
  final int index;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 4 / 3,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (dish.imagePath case final path?)
            Image.file(
              File(path),
              fit: BoxFit.cover,
              // 用户删了照片文件时不能整页崩：退回同一套渐变占位。
              errorBuilder: (context, error, stackTrace) =>
                  _Placeholder(dish: dish),
            )
          else
            _Placeholder(dish: dish),
          Positioned(
            top: LfDimens.spaceMedium,
            left: LfDimens.spaceMedium,
            child: _AlbumBadge(text: DishCard.mealSlotLabel(dish.mealSlot)),
          ),
          if (dish.servingWindow case final window?)
            Positioned(
              top: LfDimens.spaceMedium,
              right: LfDimens.spaceMedium,
              child: _AlbumBadge(text: window),
            ),
          // 「本周热门」仅 isHot 为真时渲染（docs/21 §5.3 数据来源表）。
          if (dish.isHot)
            Positioned(
              bottom: LfDimens.spaceMedium,
              left: LfDimens.spaceMedium,
              // 收归 §3.9 的 LfBadge.honey（原手写 `primary@15%` 胶囊）；
              // 原文用 `LfText.captionStrong` + 12px 火苗，与徽章族不一致。
              child: LfBadge.honey(
                '本周热门',
                key: Key('nutrition-menu-dish-hot-$index'),
                icon: Icons.local_fire_department,
              ),
            ),
        ],
      ),
    );
  }
}

/// 图片占位：渐变 + 图标（**不伪造菜品照片**，docs/21 §6.1）。
class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.dish});

  final DishRecord dish;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: DishCard.placeholderGradient(context, dish),
      ),
      child: Center(
        child: Icon(
          DishCard.placeholderIcon(dish),
          size: 48,
          color: c.primaryForeground.withValues(alpha: 0.6),
        ),
      ),
    );
  }
}

/// 图片上的胶囊角标（餐次 / 供应时段）：半透明白底 + 深字。
class _AlbumBadge extends StatelessWidget {
  const _AlbumBadge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: LfDimens.spaceSmallPlus,
        vertical: LfDimens.spaceXSmall,
      ),
      decoration: BoxDecoration(
        color: c.card.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(LfDimens.radiusFull),
      ),
      child: Text(
        text,
        style: LfText.captionStrong.copyWith(color: c.cardForeground),
      ),
    );
  }
}

/// 三宏量小卡一行（docs/28 §4.2）：三项等宽，每项 = 圆点 + 名称 + 克数 +
/// 该项热量贡献。
///
/// 等宽（`Row` + `Expanded`）而不是 `Wrap`：扫一列卡片时三列必须对齐，
/// 宽度按内容伸缩会让「蛋白质/碳水/脂肪」在每张卡上落在不同位置。
/// 每项 `FittedBox.scaleDown` 兜底：2.0× 字号把「蛋白质 12.3g」折成两行
/// 会让三列基线错位，宁可等比缩小。
class _MacroTileRow extends StatelessWidget {
  const _MacroTileRow({required this.dish, required this.index});

  final DishRecord dish;
  final int index;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    return IntrinsicHeight(
      // 等高语义在组容器：stretch 需要确定的行高，而本行在滚动视图里纵向
      // 约束是无限的（直接 stretch 会把 infinite height 传给子项）。
      child: Row(
        key: Key('nutrition-menu-macro-row-$index'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _MacroTile(
              color: c.protein,
              label: '蛋白质',
              grams: dish.proteinG,
              kcalPerGram: 4,
            ),
          ),
          const SizedBox(width: LfDimens.spaceSmall),
          Expanded(
            child: _MacroTile(
              color: c.carbs,
              label: '碳水',
              grams: dish.carbsG,
              kcalPerGram: 4,
            ),
          ),
          const SizedBox(width: LfDimens.spaceSmall),
          Expanded(
            child: _MacroTile(
              color: c.fat,
              label: '脂肪',
              grams: dish.fatG,
              kcalPerGram: 9,
            ),
          ),
        ],
      ),
    );
  }
}

/// 单项宏量小卡：底色 `muted`（比卡面低一档的弱底），圆点 + 名称一行，
/// 克数 + 热量贡献一行。
class _MacroTile extends StatelessWidget {
  const _MacroTile({
    required this.color,
    required this.label,
    required this.grams,
    required this.kcalPerGram,
  });

  final Color color;
  final String label;
  final double grams;
  final int kcalPerGram;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: LfDimens.spaceSmallPlus,
        vertical: LfDimens.spaceSmall,
      ),
      decoration: BoxDecoration(
        color: c.muted,
        borderRadius: BorderRadius.circular(LfDimens.radiusMd),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: LfDimens.spaceXSmall),
                Text(
                  label,
                  style: LfText.micro.copyWith(color: c.mutedForeground),
                ),
              ],
            ),
            const SizedBox(height: LfDimens.spaceMicro),
            Text(
              '${_grams(grams)}g',
              style: LfText.captionStrong.copyWith(color: c.cardForeground),
            ),
            Text(
              '${(grams * kcalPerGram).round()} kcal',
              style: LfText.micro.copyWith(color: c.mutedForeground),
            ),
          ],
        ),
      ),
    );
  }
}

enum MacroAccent { protein, carbs, fat }

/// 克数显示：整数不拖小数点。
String _grams(double value) =>
    value.toStringAsFixed(value == value.roundToDouble() ? 0 : 1);
