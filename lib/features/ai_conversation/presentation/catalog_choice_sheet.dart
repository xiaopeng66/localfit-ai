import 'package:flutter/material.dart';

import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/app_sheet.dart';
import 'package:localfit_ai/app/design/widgets/lf_badge.dart';
import 'package:localfit_ai/core/nutrition/nutrition_units.dart';
import 'package:localfit_ai/features/nutrition/application/catalog_resolver.dart';

/// 同名候选「选择卡」（docs/67 §6.4）：
/// 一个名字同时命中主食物 / 食堂供应 / 旧菜品时，让用户挑**按哪条记**——
/// App 不猜（名字不裁定身份）。
///
/// 选中即回 [CatalogPick]；调用方把它翻译成 `[food:id]` /
/// `[canteen-dish:id]` / `[dish:id]` 改写待应用提议并重放该行
/// （控制器 `retryEditRowWithReference`）。
enum CatalogPickKind { food, supply, dish }

final class CatalogPick {
  const CatalogPick.food(this.id, this.label) : kind = CatalogPickKind.food;

  /// 食堂供应：`[canteen-dish:id]`，按该供应自己的每份克数记。
  const CatalogPick.supply(this.id, this.label) : kind = CatalogPickKind.supply;

  const CatalogPick.dish(this.id, this.label) : kind = CatalogPickKind.dish;

  final CatalogPickKind kind;
  final String id;

  /// 用户挑中的那条的名字（提示文案用）。
  final String label;
}

Future<CatalogPick?> showCatalogChoiceSheet(
  BuildContext context, {
  required CatalogCandidates candidates,
}) {
  return AppSheet.show<CatalogPick>(
    context,
    title: '「${candidates.reference}」有多条候选',
    content: CatalogChoiceSheet(candidates: candidates),
  );
}

class CatalogChoiceSheet extends StatelessWidget {
  const CatalogChoiceSheet({super.key, required this.candidates});

  final CatalogCandidates candidates;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _GroupLabel('按食物记（每 100g，按克数）'),
        for (final food in candidates.foods)
          _Row(
            key: Key('catalog-choice-food-${food.id}'),
            title: food.name,
            subtitle: '${food.kcalPer100g.round()} kcal/100g',
            badge: '食物库',
            onPick: () =>
                Navigator.pop(context, CatalogPick.food(food.id, food.name)),
          ),
        if (candidates.foods.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: LfDimens.spaceXSmall),
            child: Text(
              '（食物库没有同名条目）',
              style: LfText.caption.copyWith(color: c.mutedForeground),
            ),
          ),
        if (candidates.supplies.isNotEmpty) ...[
          const SizedBox(height: LfDimens.spaceSmall),
          const _GroupLabel('按食堂供应记（该窗口的一份，按份/克数）'),
          for (final supply in candidates.supplies)
            _Row(
              key: Key('catalog-choice-supply-${supply.id}'),
              title: supply.displayName,
              subtitle:
                  '${supply.windowLabel} · ${supply.kcalPer100g!.round()} kcal/100g'
                  '${switch (supply.servingGramsStatus) {
                    ServingGramsStatus.known => ' · 每份 ${_grams(supply.servingGrams!)}g',
                    ServingGramsStatus.estimated => ' · 每份约 ${_grams(supply.servingGrams!)}g（估计）',
                    ServingGramsStatus.unknown => ' · 份量未知（按克记）',
                  }}',
              badge: '食堂',
              onPick: () => Navigator.pop(
                context,
                CatalogPick.supply(supply.id, supply.displayName),
              ),
            ),
        ],
        const SizedBox(height: LfDimens.spaceSmall),
        const _GroupLabel('按菜品记（每份，按份/克数）'),
        for (final dish in candidates.dishes)
          _Row(
            key: Key('catalog-choice-dish-${dish.id}'),
            title: dish.name,
            subtitle: dish.energyLabel,
            badge: '菜品库',
            onPick: () =>
                Navigator.pop(context, CatalogPick.dish(dish.id, dish.name)),
          ),
        if (candidates.dishes.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: LfDimens.spaceXSmall),
            child: Text(
              '（菜品库没有同名条目）',
              style: LfText.caption.copyWith(color: c.mutedForeground),
            ),
          ),
        const SizedBox(height: LfDimens.spaceXSmall),
        Text(
          '同名不是同一条：口径（每 100g / 每份）由你挑的这一条决定，'
          '选完只重放这一行。',
          style: LfText.caption.copyWith(color: c.mutedForeground),
        ),
      ],
    );
  }
}

String _grams(double value) => value == value.roundToDouble()
    ? value.round().toString()
    : value.toStringAsFixed(1);

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    return Padding(
      padding: const EdgeInsets.only(bottom: LfDimens.spaceXSmall),
      child: Text(
        text,
        style: LfText.label.copyWith(
          color: c.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    super.key,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.onPick,
  });

  final String title;
  final String subtitle;
  final String badge;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    return InkWell(
      onTap: onPick,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: LfDimens.spaceSmall,
          vertical: LfDimens.spaceSmall,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: LfText.body.copyWith(
                      color: c.foreground,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: LfText.caption.copyWith(color: c.mutedForeground),
                  ),
                ],
              ),
            ),
            const SizedBox(width: LfDimens.spaceSmall),
            LfBadge.outlinedBrand(badge),
          ],
        ),
      ),
    );
  }
}
