import 'package:flutter/material.dart';

import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';

/// 周条（docs/21 §3.2 **新建**）：7 列，每列 = 星期字 + 日期数字圆。
/// 今天 = 实心 mint 圆 + 白字；异常日 = warning 底；其余 = 无底。
/// 「今天必须按真实星期推导」（docs/21 §6.2 裁决），由调用方传入
/// [todayIndex]（0=周一..6=周日）。
class WeekStrip extends StatelessWidget {
  const WeekStrip({super.key, required this.days, required this.todayIndex});

  /// 7 天（周一..周日）。
  final List<WeekDay> days;
  final int todayIndex;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    assert(days.length == 7, '周条固定 7 列');
    assert(todayIndex >= 0 && todayIndex < 7);
    final scaler = MediaQuery.textScalerOf(context);
    var circleSize = 32.0;
    for (final day in days) {
      final painter = TextPainter(
        text: TextSpan(text: day.label, style: LfText.body),
        textDirection: Directionality.of(context),
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      circleSize = circleSize < painter.width + 8
          ? painter.width + 8
          : circleSize;
      circleSize = circleSize < painter.height + 4
          ? painter.height + 4
          : circleSize;
      painter.dispose();
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final contentWidth = (circleSize + 8) * days.length;
        final width = contentWidth > constraints.maxWidth
            ? contentWidth
            : constraints.maxWidth;
        final row = SizedBox(
          width: width,
          child: Row(
            key: key == null ? const Key('week-strip') : null,
            children: [
              for (var i = 0; i < days.length; i++)
                Expanded(
                  child: _WeekColumn(
                    day: days[i],
                    isToday: i == todayIndex,
                    circleSize: circleSize,
                    mutedForeground: c.mutedForeground,
                    cardForeground: c.cardForeground,
                    todayBg: c.primary,
                    todayFg: c.primaryForeground,
                    // RV-P1-13：`warning` 当填充、白字只有 2.16:1。
                    // 异常日改成 tint 底 + warningText（实测 4.95:1）。
                    warnBg: c.warning.withValues(alpha: 0.12),
                    warnFg: c.warningText,
                  ),
                ),
            ],
          ),
        );
        if (contentWidth <= constraints.maxWidth) return row;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: row,
        );
      },
    );
  }
}

class _WeekColumn extends StatelessWidget {
  const _WeekColumn({
    required this.day,
    required this.isToday,
    required this.circleSize,
    required this.mutedForeground,
    required this.cardForeground,
    required this.todayBg,
    required this.todayFg,
    required this.warnBg,
    required this.warnFg,
  });

  final WeekDay day;
  final bool isToday;
  final double circleSize;
  final Color mutedForeground;
  final Color cardForeground;
  final Color todayBg;
  final Color todayFg;
  final Color warnBg;
  final Color warnFg;

  @override
  Widget build(BuildContext context) {
    final isAbnormal = day.state == WeekDayState.abnormal;
    final circleColor = isToday
        ? todayBg
        : isAbnormal
        ? warnBg
        : Colors.transparent;
    final numberColor = isToday
        ? todayFg
        : isAbnormal
        ? warnFg
        : mutedForeground;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          day.weekdayLabel,
          style: LfText.micro.copyWith(color: mutedForeground),
        ),
        const SizedBox(height: LfDimens.spaceTiny),
        Container(
          width: circleSize,
          height: circleSize,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: circleColor, shape: BoxShape.circle),
          child: Text(
            day.label,
            style: LfText.body.copyWith(color: numberColor),
          ),
        ),
      ],
    );
  }
}

/// 周条单日数据。
class WeekDay {
  const WeekDay({
    required this.weekdayLabel,
    required this.label,
    this.state = WeekDayState.normal,
  });

  /// 星期字（一/二/…/日）。
  final String weekdayLabel;

  /// 日期数字（1..31）。
  final String label;
  final WeekDayState state;
}

enum WeekDayState { normal, abnormal }
