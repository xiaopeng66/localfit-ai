import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/app_motion.dart';

/// chip 的形态档（docs/21 §3.12 地点 chip）。
///
/// 只在这里加档，不新造第三个 chip 件：防回退审计（`ui_spec_key_sync` 之外的
/// 形态审计）依赖「全仓只有这一枚 chip」这个事实。
enum AppMorphChipVariant {
  /// 变形档（默认，docs/21 §3）：未选中为 s 圆角扁块（surfaceAlt 底），
  /// 选中吞没为 full 胶囊（brandTint 浅底 + brandStrong 文字）。
  morph,

  /// 描边档（地点 chip，docs/21 §3.12，2026-10-06 选中态重做）：常态
  /// `card` 底 + 1px `border` 边 + `foreground` 字；选中**同底色** +
  /// **2px `mint-600` 描边** + `mintText` 字 + 轻抬升
  /// （`0 1px 3px` mint-500 30%）；**恒为胶囊**，高 44（触达线）。
  ///
  /// 旧选中态（mint-50 淡底 + mint-200 淡边 + 6dp 圆点）三个信号里两个
  /// 接近纸面（用户原话「选中态丑」）⇒ 重做后形状信息由**描边宽度变化**
  /// （1px→2px）承担——色觉障碍下可辨，替代被删掉的圆点；不再换底色，
  /// 「换底」正是第二个弱信号的来源。
  ///
  /// 为什么这两个档要分开：变形档的表达是「形状变化」，会被误读成
  /// 「折叠/展开」；地点选择是**单选**，需要的是「同一形状里强调」。
  outlined,
}

/// docs/21 §3 变形 Chip（「圆角吞没」）：未选中为 s 圆角扁块（surfaceAlt 底），
/// 选中吞没为 full 胶囊（brandTint 浅底 + brandStrong 文字），springQuick
/// （约 240ms）平滑变形；减弱动画时直接呈现终态（无变形过程）。
///
/// 统一替换 FilterChip/ChoiceChip/ActionChip：
/// - 给 [onSelected] → 点击回调 !selected（选择语义）；
/// - 给 [onPressed] → 点击只走 onPressed（动作语义，优先于 onSelected）；
/// - 两者皆空 → 禁用（点击无回调）。
final class AppMorphChip extends StatelessWidget {
  const AppMorphChip({
    required this.label,
    this.selected = false,
    this.onSelected,
    this.onPressed,
    this.variant = AppMorphChipVariant.morph,
    super.key,
  });

  final String label;
  final bool selected;
  final ValueChanged<bool>? onSelected;
  final VoidCallback? onPressed;

  /// 形态档；[AppMorphChipVariant.outlined] 见该枚举的注释。
  final AppMorphChipVariant variant;

  bool get _enabled => onSelected != null || onPressed != null;

  void _handleTap() {
    final press = onPressed;
    if (press != null) {
      press();
    } else {
      onSelected?.call(!selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final semantic = context.lf;
    final brightness = Theme.of(context).brightness;
    final reduced = AppMotion.reduced(context);
    final morph = variant == AppMorphChipVariant.morph;
    // 变形档：未选中 s 圆角（扁块）→ 选中 full 胶囊。描边档恒为胶囊。
    final radius = morph && !selected ? LfDimens.radiusMd : LfDimens.radiusFull;
    // 变形档选中吞没为 mint-100 浅底；描边档（2026-10-06 重做）**不换底**，
    // 选中 = 2px 主色描边 + 主色字 + 轻抬升（见枚举注释）。
    final selectedFill = morph
        ? LfColors.mint(brightness).tone(100)
        : semantic.card;
    return Semantics(
      button: true,
      selected: selected,
      enabled: _enabled,
      child: AnimatedContainer(
        duration: reduced ? Duration.zero : AppMotion.springQuickDuration,
        curve: Curves.easeOutCubic,
        constraints: BoxConstraints(
          minHeight: morph ? 32 : LfDimens.minTouchTarget,
        ),
        decoration: BoxDecoration(
          color: selected
              ? selectedFill
              : (morph ? semantic.muted : semantic.card),
          borderRadius: BorderRadius.circular(radius),
          border: morph
              ? null
              : Border.all(
                  color: selected
                      ? LfColors.mint(brightness).tone(600)
                      : semantic.border,
                  width: selected ? 2 : 1,
                ),
          // 抬升只属于描边档的选中态（docs/21 §3.12）：这不是按钮 CTA
          // 阴影（§2.4 的白名单不管控件态表达），值取 mint-500 30%。
          boxShadow: !morph && selected
              ? [
                  BoxShadow(
                    offset: const Offset(0, 1),
                    blurRadius: 3,
                    color: LfColors.mint(brightness)
                        .tone(500)
                        .withValues(alpha: 0.30),
                  ),
                ]
              : null,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: _enabled ? _handleTap : null,
            borderRadius: BorderRadius.circular(radius),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: morph ? 14 : LfDimens.spaceMedium,
                vertical: morph ? 8 : LfDimens.spaceSmall,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 选中圆点已随选中态重做移除（docs/21 §3.12）：形状信息
                  // 改由描边 1px→2px 的宽度变化承担，色觉障碍下同样可辨。
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: selected
                            ? LfColors.mintText(brightness)
                            : semantic.foreground,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
