import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
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
    this.onBackToToday,
  });

  final DateTime selectedDate;
  final DateTime now;

  /// 【N-4（2026-10-29 用户：翻到其他日期后想返回今天很困难）】非今天时
  /// 在日期旁给一枚「回到今天」胶囊。
  final VoidCallback? onBackToToday;

  /// A 的日期形态：`2026 / 10 / 13`（月、日补零）。
  static String formatDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')} / '
      '${date.month.toString().padLeft(2, '0')} / '
      '${date.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final isToday = DateUtils.isSameDay(selectedDate, now);
    // 【N-4 实测（320dp × 2.0×）】日期 + 胶囊一行放不下会溢出 103px——
    // 改 Wrap：放不下时胶囊整体换到下一行，不裁不缩。
    return Wrap(
      spacing: LfDimens.spaceSmall,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          isToday
              ? '${formatDate(selectedDate)} · 今天'
              : formatDate(selectedDate),
          key: const Key('nutrition-record-selected-date'),
          style: LfText.caption.copyWith(color: c.mutedForeground),
        ),
        if (!isToday && onBackToToday != null)
          InkWell(
            key: const Key('nutrition-record-back-to-today'),
            onTap: onBackToToday,
            borderRadius: BorderRadius.circular(LfDimens.radiusFull),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: LfDimens.spaceXSmall + 2,
                vertical: 2,
              ),
              child: Text(
                '回到今天',
                // 【2026-10-31 用户：这行文字跟日期不一样大】两处名义都是
                // 12sp，但数字字形只有 ~9px 高、汉字占满 12px 字框——光学
                // 上胶囊大了 ~30%。用 11sp 的 captionOptical 做光学对齐
                // （颜色/字重保留，供识别它是入口）。
                style: LfText.captionOptical.copyWith(
                  color: LfColors.mintText(Theme.of(context).brightness),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
