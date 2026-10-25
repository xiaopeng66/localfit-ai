import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';

/// docs/21 §3 证据等级角标：A（薄荷）/B（蜜黄）/C（雾紫）/D（灰绿状态色）。
/// 「X级」文字常驻（docs/07 §9.3：不只用颜色表达状态），色块只做背景辅助。
final class AppEvidenceBadge extends StatelessWidget {
  const AppEvidenceBadge({required this.grade, super.key});

  /// 等级字母：'A' / 'B' / 'C' / 'D'（未知按 D 呈现，窄列兜底）。
  final String grade;

  /// 等级配色。设计稿（`饮食 · 菜单.html`）只画了两级：
  /// A 底 `--lf-evidence-a` + 文字 `--lf-mint-700`；B 底 `--lf-evidence-b` +
  /// 文字 `--lf-foreground`。C 与 B 同走前景色（设计稿没有三宏量的文字级
  /// 深档，直接拿 `fat` 等数据色当文字在 100 档底上对比不足），等级由
  /// 100 档底色 + 常驻「X级」文字共同表达；未知按 D 走中性档。
  (Color, Color) _colors(BuildContext context) {
    final c = context.lf;
    return switch (grade.toUpperCase()) {
      'A' => (c.evidenceA, LfColors.mintText(Theme.of(context).brightness)),
      'B' => (c.evidenceB, c.foreground),
      'C' => (c.evidenceC, c.foreground),
      _ => (c.muted, c.mutedForeground),
    };
  }

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = _colors(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(LfDimens.radiusSm),
      ),
      child: Text(
        '$grade级',
        maxLines: 1,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: foreground, fontWeight: FontWeight.w600),
      ),
    );
  }
}
