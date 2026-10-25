import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/app_motion.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';

/// 「大卡」形态的单选件（引导页与「编辑资料」共用的**同一件**）。
///
/// 2026-10-16 用户：「编辑资料里的训练目标做成引导页那种形式」——原先资料页是
/// 三行 `RadioListTile`，引导页是三张大卡；这里是那份大卡的公共实现，
/// 两页共用（引导页的私有 `_GoalBigCard` 已删）。
///
/// 形态（Round7 A）：图标 32 + 4 间距 + 标签；选中 = mint-50 底 + primary
/// 描边 1.6 + 图标/文字同色（mint-700）、未选 = muted 底 + 无描边 + 压暗 0.97。
///
/// 动画：mint 底随 springStandard（380ms easeOutBack 微过冲）吞没选中卡，
/// 选中卡弹起 1.0、未选压暗 0.97；减弱动画时直接呈现终态（AppMotion.reduced）。
class GoalBigCard extends StatelessWidget {
  const GoalBigCard({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.expand = true,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// true = 自己 `Expanded`（在 `Row` 里三等分，引导页与资料页都是这一档）。
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final duration = AppMotion.reduced(context)
        ? Duration.zero
        : AppMotion.springStandardDuration;
    final mint = LfColors.mint(Theme.of(context).brightness);
    final card = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(LfDimens.radiusMd),
        child: AnimatedScale(
          duration: duration,
          curve: Curves.easeOutBack,
          scale: selected ? 1.0 : 0.97,
          child: AnimatedContainer(
            duration: duration,
            curve: Curves.easeOutBack,
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: selected ? mint.tone(50) : context.lf.muted,
              borderRadius: BorderRadius.circular(LfDimens.radiusMd),
              border: Border.all(
                color: selected ? context.lf.primary : Colors.transparent,
                width: 1.6,
              ),
            ),
            child: Column(
              children: [
                Icon(
                  icon,
                  size: 32,
                  color: selected ? mint.tone(700) : context.lf.mutedForeground,
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: LfText.label.copyWith(
                    color: selected
                        ? mint.tone(700)
                        : context.lf.mutedForeground,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    // 单选项必须让读屏听出「选中」——引导页与编辑资料页都用这张卡做训练目标的
    // 单选，没有 `selected` 语义时读屏只能听到「减脂，按钮」。
    // 执行期新发现（与 `RV4-P1-09` 同族），在批次 4 B2 一并修。
    final semanticCard = Semantics(
      button: true,
      selected: selected,
      child: ExcludeSemantics(child: card),
    );
    return expand ? Expanded(child: semanticCard) : semanticCard;
  }
}
