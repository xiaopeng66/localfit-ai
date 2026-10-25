import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';

/// 记录页「选中日期」一行（A `.selected-date`，docs/21 §5.2
/// `nutrition-record-selected-date`）。
///
/// A 实测：`2026 / 10 / 13 · 今天`，12px `--muted`，**裸在页面上**（不是卡片），
/// 紧贴在周条之下。它替下了旧页首卡里的日期文案（`nutrition-record-hero-date`，
/// 已随 hero 退役）。
///
/// 「· 今天」只在选中日**就是**今天时出现：翻看往日时把往日说成今天，就是
/// 在说假话（§6.1 诚实规则）。
class NutritionRecordSelectedDate extends StatelessWidget {
  const NutritionRecordSelectedDate({
    super.key,
    required this.selectedDate,
    required this.now,
  });

  final DateTime selectedDate;
  final DateTime now;

  /// A 的日期形态：`2026 / 10 / 13`（月、日补零）。
  static String formatDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')} / '
      '${date.month.toString().padLeft(2, '0')} / '
      '${date.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final isToday = DateUtils.isSameDay(selectedDate, now);
    return Text(
      isToday ? '${formatDate(selectedDate)} · 今天' : formatDate(selectedDate),
      key: const Key('nutrition-record-selected-date'),
      style: LfText.caption.copyWith(color: c.mutedForeground),
    );
  }
}
