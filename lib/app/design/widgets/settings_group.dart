import 'package:flutter/material.dart';

import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';

/// 设置分组（docs/21 §3.3 **新建**）：`overflow-hidden rounded-[16px] +
/// divide-y` 行分隔，每行 `min-h-[52px] px-4`。组标题在**组外**（11px
/// muted，`mb-2 px-1`），与设计稿「我的」页一致。
///
/// 行分隔用 [Column] + 中间 1px Container：设计稿的 divide-y 只分隔行，
/// 外层圆角裁剪已保证分隔线不延伸到圆角外。
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({
    super.key,
    required this.title,
    required this.children,
    this.titleKey,
    this.trailingLabel,
    this.trailingKey,
  });

  /// 组标题（组外）。null = 不渲染标题（纯组合容器）。
  final String? title;

  /// 标题的测试 Key（如 `settings-group-ai`）。
  final Key? titleKey;

  /// 标题行右端的说明（Round7 逐页对账批次 2：A `app.js:248/252` 的
  /// `.section-title.with-link` 是「左标题 + 右 quiet-label」两端形态——
  /// 健康卡「资料与今日记录」、成就卡「N / N 已解锁」）。
  final String? trailingLabel;

  /// 右端说明的测试 Key。
  final Key? trailingKey;

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final labelStyle = LfText.label.copyWith(color: c.mutedForeground);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.only(
              left: LfDimens.spaceMicro,
              bottom: LfDimens.spaceSmall,
            ),
            child: trailingLabel == null
                ? Text(title!, key: titleKey, style: labelStyle)
                : Row(
                    children: [
                      Expanded(
                        child: Text(title!, key: titleKey, style: labelStyle),
                      ),
                      const SizedBox(width: LfDimens.spaceSmall),
                      Text(trailingLabel!, key: trailingKey, style: labelStyle),
                    ],
                  ),
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(LfDimens.radiusLg),
            border: Border.all(color: c.border),
            boxShadow: LfShadows.surface(
              Theme.of(context).brightness == Brightness.light,
            ),
          ),
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) Container(height: 1, color: c.border),
                children[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}
