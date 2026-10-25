import 'package:flutter/material.dart';

import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';

/// 证据分级徽章（docs/21 §3.3 改造）：三档
/// 「已确认/营养师确认」= evidenceA、「AI 估算」= evidenceB、
/// 「待补全/不完整」= evidenceC。形状 `rounded-[8px] px-2 py-1` 11px w500。
///
/// 旧件 `AppEvidenceBadge` 保留到旧页重建完成；新页面用本件。
class LfEvidenceBadge extends StatelessWidget {
  const LfEvidenceBadge.confirmed({super.key, this.text = '已确认'})
    : grade = LfEvidenceGrade.confirmed;

  const LfEvidenceBadge.estimated({super.key, this.text = 'AI 估算'})
    : grade = LfEvidenceGrade.estimated;

  const LfEvidenceBadge.incomplete({super.key, this.text = '待补全'})
    : grade = LfEvidenceGrade.incomplete;

  final LfEvidenceGrade grade;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final (bg, fg) = switch (grade) {
      LfEvidenceGrade.confirmed => (c.evidenceA, c.cardForeground),
      LfEvidenceGrade.estimated => (c.evidenceB, c.cardForeground),
      LfEvidenceGrade.incomplete => (c.evidenceC, c.cardForeground),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(LfDimens.radiusSm),
      ),
      child: Text(text, style: LfText.label.copyWith(color: fg)),
    );
  }
}

enum LfEvidenceGrade { confirmed, estimated, incomplete }
