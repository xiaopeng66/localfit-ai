import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/design_card.dart';
import 'package:localfit_ai/app/design/widgets/lf_buttons.dart';
import 'package:localfit_ai/features/nutrition/domain/dish_record.dart';
import 'package:localfit_ai/features/nutrition/domain/source_badge.dart';
import 'package:localfit_ai/features/retrieval/application/dish_search.dart';

/// 菜单页搜索框的结果区（docs/43 A1 / docs/39 §8）。
///
/// 抽成独立件有两个理由：
/// 1. 菜单页已接近 500 行预算（docs/43 §6 风险表）——结果行不该再挤进页面；
/// 2. 结果区是**只读展示 + 一个加入动作**，与页面状态（推荐/换一个/陈旧）
///    没有耦合，分开后可以单独测空态与几何。
///
/// 纪律：检索不可用/索引为空时**照常出结果**（关键词 + 标签），不弹错；
/// 「为什么命中」如实列出参与的路，不编造语义命中。
class MenuSearchResultsSliver extends StatelessWidget {
  const MenuSearchResultsSliver({
    super.key,
    required this.query,
    required this.hits,
    required this.dishes,
    this.degradedNotice = '',
    this.isAdding,
    this.onAddToMeal,
  });

  final String query;
  final List<FoodHit> hits;

  /// id → 菜品（「加入餐」要用完整 [DishRecord]）。
  final List<DishRecord> dishes;

  /// 语义不可用时的降级提示（RV-P1-09）。空串 = 不渲染。
  final String degradedNotice;

  /// 在途判断（RV-P1-05）：true 时「加入餐」禁用，防止双击写两条。
  final bool Function(String dishId)? isAdding;

  /// null = 不渲染「加入餐」（未接线时不给点了没反应的按钮）。
  final Future<void> Function(DishRecord dish)? onAddToMeal;

  @override
  Widget build(BuildContext context) {
    if (hits.isEmpty) {
      return SliverPadding(
        padding: const EdgeInsets.fromLTRB(
          LfDimens.pagePadding,
          LfDimens.cardGap,
          LfDimens.pagePadding,
          0,
        ),
        sliver: SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (degradedNotice.isNotEmpty)
                _DegradedNote(text: degradedNotice),
              _SearchEmpty(query: query),
            ],
          ),
        ),
      );
    }
    final byId = {for (final dish in dishes) dish.id: dish};
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(
        LfDimens.pagePadding,
        LfDimens.cardGap,
        LfDimens.pagePadding,
        0,
      ),
      sliver: SliverList.list(
        children: [
          _CountLine(count: hits.length),
          const SizedBox(height: LfDimens.spaceSmall),
          for (var i = 0; i < hits.length; i++) ...[
            if (i > 0) const SizedBox(height: LfDimens.cardGap),
            _SearchHitRow(
              hit: hits[i],
              dish: byId[hits[i].id],
              isAdding: isAdding?.call(hits[i].id) ?? false,
              onAddToMeal: onAddToMeal,
            ),
          ],
        ],
      ),
    );
  }
}

/// 结果头：`找到 N 道`（Key `nutrition-menu-search-count`）。
class _CountLine extends StatelessWidget {
  const _CountLine({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    return Text(
      '找到 $count 道',
      key: const Key('nutrition-menu-search-count'),
      style: LfText.captionStrong.copyWith(color: c.mutedForeground),
    );
  }
}

/// 空态（Key `nutrition-menu-search-empty`）：两句——没有匹配 + 怎么改。
class _SearchEmpty extends StatelessWidget {
  const _SearchEmpty({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    return Padding(
      key: const Key('nutrition-menu-search-empty'),
      padding: const EdgeInsets.symmetric(vertical: LfDimens.spaceLarge),
      child: Column(
        children: [
          Text(
            '没有匹配「$query」的菜。',
            textAlign: TextAlign.center,
            style: LfText.body.copyWith(color: c.cardForeground),
          ),
          const SizedBox(height: LfDimens.spaceXSmall),
          Text(
            '试试更短的关键词或口味词。',
            textAlign: TextAlign.center,
            style: LfText.caption.copyWith(color: c.mutedForeground),
          ),
        ],
      ),
    );
  }
}

/// 一条命中（Key `nutrition-menu-search-hit-<id>`）。
class _SearchHitRow extends StatelessWidget {
  const _SearchHitRow({
    required this.hit,
    required this.dish,
    required this.isAdding,
    required this.onAddToMeal,
  });

  final FoodHit hit;
  final DishRecord? dish;
  final bool isAdding;
  final Future<void> Function(DishRecord dish)? onAddToMeal;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final add = onAddToMeal;
    return DesignCard(
      key: Key('nutrition-menu-search-hit-${hit.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 名称 + kcal：窄屏/大字时整行换行而不是裁字。
          Wrap(
            spacing: LfDimens.spaceSmall,
            runSpacing: LfDimens.spaceXSmall,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                hit.name,
                style: LfText.bodyStrong.copyWith(color: c.cardForeground),
              ),
              Text(
                '${hit.kcal.round()} kcal/份',
                style: LfText.caption.copyWith(color: c.mutedForeground),
              ),
            ],
          ),
          const SizedBox(height: LfDimens.spaceXSmall),
          Wrap(
            spacing: LfDimens.spaceSmall,
            runSpacing: LfDimens.spaceXSmall,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              LfSourceBadgePair.forMealSource(
                hit.kind == 'menuItem' ? 'canteen' : 'dish_library',
                keyPrefix: 'nutrition-menu-search-hit-${hit.id}',
              ),
              if (hit.window != null && hit.window!.isNotEmpty)
                Text(
                  hit.window!,
                  style: LfText.caption.copyWith(color: c.mutedForeground),
                ),
              if (hit.reasons.isNotEmpty)
                Text(
                  '命中：${hit.reasons.join('+')}',
                  key: Key('nutrition-menu-search-reasons-${hit.id}'),
                  style: LfText.caption.copyWith(color: c.mutedForeground),
                ),
            ],
          ),
          if (add != null && dish != null) ...[
            const SizedBox(height: LfDimens.spaceSmall),
            Align(
              alignment: Alignment.centerRight,
              child: LfSoftButton(
                key: Key('nutrition-menu-search-add-${hit.id}'),
                label: '加入餐',
                onPressed: isAdding ? null : () => add(dish!),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 降级提示行（RV-P1-09）：文案来自 `degradation_matrix.dart`，只做排版。
class _DegradedNote extends StatelessWidget {
  const _DegradedNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    return Padding(
      padding: const EdgeInsets.only(bottom: LfDimens.spaceSmall),
      child: Text(
        text,
        key: const Key('nutrition-menu-degraded-note'),
        style: LfText.caption.copyWith(color: c.mutedForeground),
      ),
    );
  }
}
