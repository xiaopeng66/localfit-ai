import 'package:flutter/material.dart';

import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';

/// 餐次胶囊（**三处记录弹层共用的一颗**：按食材 `MealEditorDialog` /
/// 按菜品 `DishMealEditorSheet` / 自定义一顿 `CustomMealSheet`）。
///
/// 2026-10-28 用户：「我要的是按食材记录这样，自定义一顿也是一样」——
/// 三个弹层的餐次选择此前是三副长相（按食材 = 实心选中胶囊、按菜品 =
/// 同款副本、自定义 = `LfFilterChip` 浅底描边），统一为本件。
///
/// 视觉与语义沿用 `MealEditorDialog._SlotPill` 的既有实现（选中 = `primary`
/// 实心（brandStrong）+ 反色字（onBrandStrong），未选中 = `muted` 底 + `foreground` 字，
/// `Semantics(selected:)` 可读），几何对齐 44dp 触达线（§5.8.3）。
class MealSlotPill extends StatelessWidget {
  const MealSlotPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: ExcludeSemantics(
        child: Material(
          color: selected
              ? LfColors.brandStrong(Theme.of(context).brightness)
              : c.muted,
          borderRadius: BorderRadius.circular(LfDimens.radiusFull),
          child: InkWell(
            borderRadius: BorderRadius.circular(LfDimens.radiusFull),
            onTap: onTap,
            child: ConstrainedBox(
              // 命中高度对齐 44dp 触达线（视觉上是整块胶囊，不是只给文字）。
              constraints: const BoxConstraints(
                minHeight: LfDimens.minTouchTarget,
                minWidth: LfDimens.minTouchTarget,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: LfDimens.spaceLarge,
                ),
                child: Center(
                  widthFactor: 1,
                  child: Text(
                    label,
                    style: LfText.bodyStrong.copyWith(
                      color: selected
                          ? LfColors.onBrandStrong(Theme.of(context).brightness)
                          : c.foreground,
                    ),
                    maxLines: 1,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 四枚餐次的一横排（`Wrap`：320dp × 2.0× 下四枚会超一行，自动折行，
/// `Row` 只会溢出——`MealEditorDialog._slotRow` 的既有实测结论）。
class MealSlotPillRow extends StatelessWidget {
  const MealSlotPillRow({
    super.key,
    required this.selected,
    required this.onChanged,
    this.pillKeyFor,
  });

  final bool Function(MealSlot slot) selected;
  final ValueChanged<MealSlot> onChanged;

  /// 每颗胶囊的 Key（调用方各自的键契约：`meal-slot` 组内无键 /
  /// `custom-meal-slot-<storedValue>` / `dish-meal-slot-<name>`）。
  final Key? Function(MealSlot slot)? pillKeyFor;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: LfDimens.spaceSmall,
      runSpacing: LfDimens.spaceSmall,
      children: [
        for (final slot in MealSlot.values)
          MealSlotPill(
            key: pillKeyFor?.call(slot),
            label: slot.label,
            selected: selected(slot),
            onTap: () => onChanged(slot),
          ),
      ],
    );
  }
}
