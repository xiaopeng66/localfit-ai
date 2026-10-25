import 'package:flutter/material.dart';

import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';

/// 卡内空状态（Round7 A `.empty-state`，`styles.css:142-146`）。
///
/// 与 [AppEmptyState]（80dp 渐变圆 + emoji + 浮动动画，docs/21 §3.7 旧稿）
/// 是两个不同形态：A 的空态是**扁平图标块**——52dp R18 `brand-soft` 底 +
/// `brand-strong` 20dp 图标 + **14px w600 标题**（`strong`）+ 12px 说明
/// （行高 1.8、最大宽 230、居中），整块在卡片里居中，周围不做动画。
///
/// 行动入口由调用方以 `action` 传入（A 的空态行动按 §3.8 一律文字按钮）。
class LfEmptyState extends StatelessWidget {
  const LfEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  /// A `.empty-state .icon-chip{width:52px;height:52px;border-radius:18px}`。
  static const double iconChipSize = 52;
  static const double iconChipRadius = 18;

  /// A `.empty-state .icon-chip` 内的 svg 默认 20（`chip()` → `icon(name)`）。
  static const double iconSize = 20;

  /// A `.empty-state p{max-width:230px;line-height:1.8}`。
  static const double messageMaxWidth = 230;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final brightness = Theme.of(context).brightness;
    return Padding(
      // A `.empty-state{padding:28px 12px}`（28 无既有档位，按 A 字面量）。
      padding: const EdgeInsets.symmetric(
        horizontal: LfDimens.spaceMedium,
        vertical: 28,
      ),
      // A 的 `.empty-state` 是 **div（块级）**：铺满卡片内容宽，内容靠
      // `align-items:center` 居中。不显式给宽度时 `Column` 会收缩到最宽子件
      // （最长 230 的说明），块本身只占左边一块——已有一条既有断言
      // （round5 需求 63「不许只占左边一小块、外观对称」）正是量这个。
      child: SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: iconChipSize,
              height: iconChipSize,
              decoration: BoxDecoration(
                color: LfColors.brandSoft(brightness),
                borderRadius: BorderRadius.circular(iconChipRadius),
              ),
              child: Icon(
                icon,
                size: iconSize,
                color: LfColors.mintText(brightness),
              ),
            ),
            const SizedBox(height: LfDimens.spaceSmallPlus),
            Text(
              title,
              textAlign: TextAlign.center,
              // A `.empty-state strong{font-size:14px}` 的 `strong` 是 **w600**——
              // Round7 阶段 3 · 3-2 收口把此前登记的字重偏差（`LfText.body`
              // 14 w400）改齐；判据在 `round7_components_test.dart`。
              style: LfText.bodyStrong.copyWith(color: c.cardForeground),
            ),
            if (message != null) ...[
              const SizedBox(height: LfDimens.spaceSmallPlus),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: messageMaxWidth),
                child: Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: LfText.caption.copyWith(
                    color: c.mutedForeground,
                    height: 1.8,
                  ),
                ),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: LfDimens.spaceSmallPlus),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
