import 'package:flutter/material.dart';

import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';

/// 设置行（docs/21 §3.3 **新建**）：`min-h-[52px] px-4 py-3.5`，
/// 左 = 20px 图标（muted）+ 14px 名称；右 = 值（14px muted）/ chevron / 开关。
class SettingRow extends StatelessWidget {
  const SettingRow({
    super.key,
    required this.icon,
    required this.title,
    this.value,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.showChevron = false,
    this.destructive = false,
  });

  /// 20px 轮廓图标（muted 色）。
  final IconData icon;
  final String title;

  /// 右侧值文本（与 [trailing] 互斥使用）。
  final String? value;

  /// 标题下方的一行说明（muted 小字，可折行）。
  ///
  /// 长状态句（如「导入扩展食物目录（可选）」的当前进度）不该挤进右侧的
  /// `value`——那一格是给短数字/短词的，长句会先被省略掉半句，剩下的信息
  /// 反而比不显示更糟。副标题留在标题列里（`Expanded`），窄屏会自己折行。
  final String? subtitle;

  /// 右侧控件（[SettingToggle] 等）。
  final Widget? trailing;
  final VoidCallback? onTap;

  /// 是否显示右侧 chevron（可点行）。
  final bool showChevron;

  /// 破坏性操作（清除数据）：标题用 error 色。
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final titleColor = destructive ? c.error : c.cardForeground;
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 52),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: LfDimens.spaceLarge,
          vertical: 14,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final titleStyle = LfText.body.copyWith(color: titleColor);
            final valueStyle = LfText.body.copyWith(color: c.mutedForeground);
            double textWidth(String text, TextStyle style) {
              final painter = TextPainter(
                text: TextSpan(text: text, style: style),
                textDirection: Directionality.of(context),
                textScaler: MediaQuery.textScalerOf(context),
                maxLines: 1,
              )..layout();
              final width = painter.width;
              painter.dispose();
              return width;
            }

            final trailingWidth = switch (trailing) {
              SizedBox(width: final width?) => width,
              null => 0.0,
              _ => 44.0,
            };
            final detailWidth = value == null
                ? trailingWidth
                : textWidth(value!, valueStyle);
            final leadingWidth = LfDimens.iconMd + LfDimens.spaceMedium;
            final chevronWidth = showChevron ? LfDimens.iconMd : 0.0;
            final stacked =
                (value != null || trailing != null) &&
                leadingWidth +
                        textWidth(title, titleStyle) +
                        8 +
                        detailWidth +
                        chevronWidth >
                    constraints.maxWidth;
            final titleText = Text(title, style: titleStyle);
            // 副标题住进标题列（而不是右格）：右格宽度由 `stacked` 判定参与
            // 计算，塞进长句会让「标题 + 值」横向判据失真。
            final leading = subtitle == null
                ? titleText
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      titleText,
                      const SizedBox(height: LfDimens.spaceMicro),
                      Text(
                        subtitle!,
                        style: LfText.caption.copyWith(
                          color: c.mutedForeground,
                        ),
                      ),
                    ],
                  );
            final detail = value == null
                ? trailing
                : Text(value!, style: valueStyle);
            final chevron = Icon(
              Icons.chevron_right,
              size: LfDimens.iconMd,
              color: c.mutedForeground,
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(icon, size: LfDimens.iconMd, color: c.mutedForeground),
                    const SizedBox(width: LfDimens.spaceMedium),
                    Expanded(child: leading),
                    if (!stacked && detail != null) ...[
                      const SizedBox(width: 8),
                      detail,
                    ],
                    if (showChevron) chevron,
                  ],
                ),
                if (stacked && detail != null)
                  Padding(
                    padding: EdgeInsets.only(left: leadingWidth, top: 8),
                    child: detail,
                  ),
              ],
            );
          },
        ),
      ),
    );
    if (onTap == null) return row;
    return InkWell(onTap: onTap, child: row);
  }
}

/// 开关（docs/21 §3.3 **新建**）：`role=switch`，44×24 全圆角；
/// 开 = primary 底 + 右侧白圆，关 = muted 底 + 左侧圆。
class SettingToggle extends StatelessWidget {
  const SettingToggle({
    super.key,
    required this.value,
    required this.onChanged,
    this.semanticLabel,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    return Semantics(
      label: semanticLabel,
      toggled: value,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(!value),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOutCubic,
              width: 44,
              height: 24,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: value ? c.primary : c.muted,
                borderRadius: BorderRadius.circular(LfDimens.radiusFull),
                border: Border.all(color: c.border),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOutCubic,
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: value ? c.primaryForeground : c.mutedForeground,
                    shape: BoxShape.circle,
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
