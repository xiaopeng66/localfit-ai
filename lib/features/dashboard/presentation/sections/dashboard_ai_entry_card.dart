import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';

/// 今日页 AI 入口（Round7 A `.ai-entry-line`，`app.js:152` +
/// `styles.css:215-219`）。
///
/// A 的形态是一条**平卡**（不是渐变 hero）：R16 / min-height 72 /
/// padding 12 15 / 36dp mint 图标块 + 「AI 创作」13px + 一行 12px muted
/// 说明 + 右侧 chevron。跳 AI 工作台（`cta-ai-workbench`，§5.1 交互表）。
class DashboardAiEntryCard extends StatelessWidget {
  const DashboardAiEntryCard({super.key, required this.onTap});

  final VoidCallback onTap;

  /// A `.ai-entry-line{min-height:72px;padding:12px 15px}`。
  static const double minHeight = 72;
  static const EdgeInsets padding = EdgeInsets.symmetric(
    horizontal: 15,
    vertical: LfDimens.spaceMedium,
  );

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final brightness = Theme.of(context).brightness;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(LfDimens.radiusLg),
        border: Border.all(
          color: Theme.of(context).brightness == Brightness.light
              ? Colors.transparent
              : c.border,
        ),
        boxShadow: brightness == Brightness.light
            ? const [
                BoxShadow(
                  color: Color(0x051A201D),
                  offset: Offset(0, 1),
                  blurRadius: 3,
                ),
              ]
            : const <BoxShadow>[],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: const Key('cta-ai-workbench'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(LfDimens.radiusLg),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: minHeight),
            child: Padding(
              padding: padding,
              child: Row(
                children: [
                  // A `chip('spark','mint')`：36dp 图标块（R12、brand-soft 底、
                  // brand-strong 图标）。
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: LfColors.brandSoft(brightness),
                      borderRadius: BorderRadius.circular(LfDimens.radiusMd),
                    ),
                    child: Icon(
                      Icons.auto_awesome,
                      size: LfDimens.iconMd,
                      color: LfColors.mintText(brightness),
                    ),
                  ),
                  const SizedBox(width: LfDimens.spaceMedium),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'AI 创作',
                          style: LfText.bodySmall.copyWith(
                            fontWeight: FontWeight.w700,
                            color: c.cardForeground,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '饮食与训练，从一个想法开始',
                          style: LfText.caption.copyWith(
                            color: c.mutedForeground,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: LfDimens.spaceSmall),
                  Icon(Icons.chevron_right, size: 17, color: c.mutedForeground),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
