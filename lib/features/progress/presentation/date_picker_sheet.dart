import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/app_sheet.dart';
import 'package:localfit_ai/app/design/widgets/lf_buttons.dart';
import 'package:localfit_ai/app/design/widgets/lf_top_bar.dart';
import 'package:localfit_ai/features/progress/domain/weight_measurement.dart';

/// 选日期（docs/29 §P9 需求 33）。
///
/// **不用 `showDatePicker`**：它会拉出 Material 的原生日历——英文月份与
/// 「CANCEL/OK」（本仓没有 `flutter_localizations`，中文需要它）、
/// `Dialog` 而非底部弹层（与全 App 51 处 `AppSheet` 形态不一致）、
/// 一套与 `lf_tokens` 无关的配色。这里按设计语言手写一个月历：
/// 同一套 mint 令牌、同一个弹层壳、同样的 B6 取消 + 主行动按钮。
///
/// 边界（调用方给）：[firstDate] / [lastDate] 都含端点。**未来日不在可选
/// 范围**——明天还没发生，记一条明天的体重是编事实（弹层内也不画「下一月」
/// 按钮：翻到没有可选日子的月份只是空转）。
class DatePickerSheet extends StatefulWidget {
  const DatePickerSheet({
    super.key,
    required this.selected,
    required this.firstDate,
    required this.lastDate,
  });

  /// 当前选中的 `yyyy-MM-dd`。
  final String selected;
  final String firstDate;
  final String lastDate;

  @override
  State<DatePickerSheet> createState() => _DatePickerSheetState();
}

class _DatePickerSheetState extends State<DatePickerSheet> {
  /// 正在看的月份（1 号，避免 31 号跳到只有 30 天的月份时溢出）。
  late DateTime _month;

  @override
  void initState() {
    super.initState();
    final selected = parseLocalDate(widget.selected);
    _month = DateTime(selected.year, selected.month);
  }

  DateTime get _first => parseLocalDate(widget.firstDate);
  DateTime get _last => parseLocalDate(widget.lastDate);

  bool _isSelectable(DateTime day) =>
      !day.isBefore(_first) && !day.isAfter(_last);

  /// 能否翻到相邻月份：只有那一个月里存在可选的日子才允许。
  bool _canGo(int monthDelta) {
    final target = DateTime(_month.year, _month.month + monthDelta);
    final targetsFirst = DateTime(target.year, target.month);
    final targetsLast = DateTime(target.year, target.month + 1, 0); // 该月最后一天
    return !targetsLast.isBefore(_first) && !targetsFirst.isAfter(_last);
  }

  void _go(int monthDelta) =>
      setState(() => _month = DateTime(_month.year, _month.month + monthDelta));

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final selected = parseLocalDate(widget.selected);
    final mint = LfColors.mintText(Theme.of(context).brightness);
    // 周一起始（与 `WeekStrip`、训练页的「今天 = 周一索引 0」同一口径）。
    final leadingBlanks = DateTime(_month.year, _month.month).weekday - 1;
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('选择日期', style: LfText.headline.copyWith(color: c.cardForeground)),
        const SizedBox(height: LfDimens.spaceLarge),
        Row(
          children: [
            LfCircleIconButton(
              key: const Key('date-picker-prev-month'),
              icon: Icons.chevron_left,
              tooltip: '上一个月',
              onPressed: _canGo(-1) ? () => _go(-1) : null,
            ),
            Expanded(
              child: Text(
                '${_month.year} 年 ${_month.month} 月',
                key: const Key('date-picker-month'),
                textAlign: TextAlign.center,
                style: LfText.bodyStrong.copyWith(color: c.cardForeground),
              ),
            ),
            LfCircleIconButton(
              key: const Key('date-picker-next-month'),
              icon: Icons.chevron_right,
              tooltip: '下一个月',
              onPressed: _canGo(1) ? () => _go(1) : null,
            ),
          ],
        ),
        const SizedBox(height: LfDimens.spaceSmall),
        Row(
          children: [
            for (final label in const ['一', '二', '三', '四', '五', '六', '日'])
              Expanded(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: LfText.micro.copyWith(color: c.mutedForeground),
                ),
              ),
          ],
        ),
        const SizedBox(height: LfDimens.spaceXSmall),
        for (var week = 0; week * 7 < leadingBlanks + daysInMonth; week++)
          Row(
            children: [
              for (var slot = 0; slot < 7; slot++)
                Expanded(
                  child: _dayCell(
                    context: context,
                    dayNumber: week * 7 + slot - leadingBlanks + 1,
                    daysInMonth: daysInMonth,
                    selected: selected,
                    mint: mint,
                  ),
                ),
            ],
          ),
        const SizedBox(height: LfDimens.spaceLarge),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            LfTextButton(label: '取消', onPressed: () => Navigator.pop(context)),
            LfConfirmButton(
              key: const Key('date-picker-confirm'),
              label: '确定',
              expand: false,
              onPressed: () => Navigator.pop(context, _formatIsoDate(selected)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _dayCell({
    required BuildContext context,
    required int dayNumber,
    required int daysInMonth,
    required DateTime selected,
    required Color mint,
  }) {
    if (dayNumber < 1 || dayNumber > daysInMonth) {
      return const SizedBox(height: LfDimens.minTouchTarget);
    }
    final c = context.lf;
    final day = DateTime(_month.year, _month.month, dayNumber);
    final isSelected =
        day.year == selected.year &&
        day.month == selected.month &&
        day.day == selected.day;
    final selectable = _isSelectable(day);
    final iso = _formatIsoDate(day);
    return Semantics(
      button: true,
      selected: isSelected,
      enabled: selectable,
      label: '$iso${isSelected ? '，已选中' : ''}',
      child: ExcludeSemantics(
        child: SizedBox(
          height: LfDimens.minTouchTarget,
          child: Center(
            child: SizedBox(
              width: 36,
              height: 36,
              child: Material(
                color: isSelected ? c.primary : Colors.transparent,
                shape: const CircleBorder(),
                child: InkWell(
                  key: Key('date-picker-day-$iso'),
                  customBorder: const CircleBorder(),
                  // 不可选的日子（未来 / 早于下界）不给回调：点了没反应比
                  // 「点了弹一句错误」更诚实——它不是做错了什么。
                  onTap: selectable ? () => Navigator.pop(context, iso) : null,
                  child: Center(
                    child: Text(
                      '$dayNumber',
                      style: LfText.body.copyWith(
                        color: isSelected
                            ? c.primaryForeground
                            : selectable
                            ? c.cardForeground
                            : c.mutedForeground.withValues(alpha: 0.5),
                      ),
                    ),
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

/// `yyyy-MM-dd` 格式化（零依赖，与 `parseLocalDate` 同一格式）。
String _formatIsoDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// 弹出月历并返回选中的 `yyyy-MM-dd`（点遮罩/返回 = null = 未改）。
Future<String?> showDatePickerSheet(
  BuildContext context, {
  required String selected,
  required String firstDate,
  required String lastDate,
}) => AppSheet.showCustom<String>(
  context,
  builder: (_) => DatePickerSheet(
    selected: selected,
    firstDate: firstDate,
    lastDate: lastDate,
  ),
);
