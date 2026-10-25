import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/number_format.dart';
import 'package:localfit_ai/features/nutrition/application/build_calorie_trend.dart';

/// 记录页周条（docs/21 §5.2 `nutrition-record-week-strip`）。
///
/// 视觉 = Round7 A 的 `.date-strip`（浏览器实测，360dp）：单元格
/// `min-height:91` + `padding:8px 2px` + 圆角 10，内容顶对齐；星期字 10px
/// `--muted`（选中日也不加深）；日期数字 15px w600，未选中 `--fg`、选中
/// `--brand-strong`；选中日垫 `--brand-soft` 胶囊；底部是 5×24 的轨道，
/// 短条自底向上长，高度 = `clamp(kcal / 2200, 6%, 100%)`（选中日取
/// `--brand-strong`）。
///
/// **短条按真实摄入算**，不画设计稿的手写高度——那七个 30/20/34/40px 是
/// demo 数据（§6.1 诚实规则）。无记录的日子画 4dp 灰标记（D21：A 只画空，
/// 本仓保留可见标记，否则「没记录」与「比例极小」看起来一样）。
///
/// 交互：点某天 → [onSelect]；未来日期禁用（`onSelect` 不触发）；左右滑切换
/// 上/下一周同日（不越过未来）。周条只画选中日所在的一周，没有滑动手势的话
/// 用户**翻不到别的周**——这条是旧周条的行为契约，阶段 I-2b 迁移时曾被漏掉，
/// 已在 I-2c 补回并配测试。
///
/// 每天的 [Semantics] 标签写真实事实（A 的 `aria-label` 同款）：柱高只是缩放
/// 图，真实数值只有语义标签与趋势卡给得出。
class NutritionRecordWeekStrip extends StatefulWidget {
  const NutritionRecordWeekStrip({
    super.key,
    required this.bars,
    required this.selectedDate,
    required this.now,
    required this.onSelect,
  });

  /// 与趋势柱图同源的 7 天数据（同窗口同口径）。两处**各自成图**：周条短条
  /// 恒以 [kTrendBaseKcal] 为分母，趋势纵轴另有取法，条高不可直接互比
  /// （A 亦如此；真实数值在语义标签与趋势卡里都能读到）。
  final CalorieTrendBars bars;
  final DateTime selectedDate;
  final DateTime now;
  final ValueChanged<DateTime> onSelect;

  /// 单元格最小高度（A `.date-strip button{min-height:91px}`）。
  static const double cellMinHeight = 91;

  /// 单元格圆角（A 字面 10px；档位表只有 8/12/16，按 A 取 10）。
  static const double cellRadius = 10;

  /// 短条轨道与条宽（A `.date-mini` 5×24，条自底部向上长）。
  static const double barTrackHeight = 24;
  static const double barWidth = 5;

  /// 有记录时的最小可见比例（A `clamp(kcal / 2200, 6%, 100%)`）。
  /// 6% ≈ 1.44dp，与无记录的 4dp 标记仍分辨得出。
  static const double barMinFraction = 0.06;

  /// 无记录日的标记高度（D21）。
  static const double noRecordBarHeight = 4;

  /// 「今天但未选中」的单元格描边线宽（D14）。
  static const double todayRingWidth = 1.2;

  /// 滑动切周触发阈值（累计位移，dp）。
  ///
  /// 用累计位移而不是速度：测试同帧事件下速度阈值不可靠（旧件注释同款
  /// 理由），且慢速拖动也应当能切周。
  static const double swipeThreshold = 60;

  @override
  State<NutritionRecordWeekStrip> createState() =>
      _NutritionRecordWeekStripState();
}

class _NutritionRecordWeekStripState extends State<NutritionRecordWeekStrip> {
  double _dragDx = 0;

  void _onDragUpdate(DragUpdateDetails details) => _dragDx += details.delta.dx;

  void _onDragEnd(DragEndDetails details) {
    final dx = _dragDx;
    _dragDx = 0;
    if (dx.abs() < NutritionRecordWeekStrip.swipeThreshold) return;
    // 右滑（内容右移）回上一周、左滑进下一周；以当前选中日同日为锚点，
    // 目标越过今天（未来）则不切换。
    final today = DateUtils.dateOnly(widget.now);
    final anchor = DateUtils.dateOnly(widget.selectedDate);
    final target = dx > 0
        ? anchor.subtract(const Duration(days: 7))
        : anchor.add(const Duration(days: 7));
    if (target.isAfter(today)) return;
    widget.onSelect(target);
  }

  @override
  Widget build(BuildContext context) {
    final bars = widget.bars;
    final today = DateUtils.dateOnly(widget.now);
    final selected = DateUtils.dateOnly(widget.selectedDate);
    assert(bars.dates.length == 7, '周条固定 7 列');

    return GestureDetector(
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      child: Row(
        key: const Key('nutrition-record-week-strip'),
        // 单元格等高：靠每格统一的 `min-height:91`，**不用** `stretch`——本行在
        // 页面里是高度无界的 sliver 子节点，`stretch` 会把行拉成整屏（单测
        // 实测 600dp）或直接报错。7 列内容同构，高度自然一致。
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (var i = 0; i < bars.dates.length; i++)
            Expanded(
              child: _WeekColumn(
                dateKey: bars.dates[i],
                weekdayLabel: bars.weekdayLabels[i],
                kcal: bars.kcalByDay[i],
                isSelected: bars.dates[i] == _format(selected),
                isToday: bars.dates[i] == _format(today),
                isFuture: _parse(bars.dates[i]).isAfter(today),
                onTap: () => widget.onSelect(_parse(bars.dates[i])),
              ),
            ),
        ],
      ),
    );
  }

  static String _format(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  static DateTime _parse(String localDate) {
    final parts = localDate.split('-');
    return DateTime(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
  }
}

class _WeekColumn extends StatelessWidget {
  const _WeekColumn({
    required this.dateKey,
    required this.weekdayLabel,
    required this.kcal,
    required this.isSelected,
    required this.isToday,
    required this.isFuture,
    required this.onTap,
  });

  final String dateKey;
  final String weekdayLabel;

  /// 当日摄入（无记录日为 null）——短条高度与语义标签都用它。
  final double? kcal;
  final bool isSelected;
  final bool isToday;
  final bool isFuture;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final brightness = Theme.of(context).brightness;
    final dayNumber = dateKey.split('-').last.replaceFirst(RegExp(r'^0'), '');
    final intake = kcal;
    final barHeight = intake == null
        ? NutritionRecordWeekStrip.noRecordBarHeight
        : (intake / kTrendBaseKcal).clamp(
                NutritionRecordWeekStrip.barMinFraction,
                1.0,
              ) *
              NutritionRecordWeekStrip.barTrackHeight;
    final barColor = intake == null
        ? c.border
        : isSelected
        ? LfColors.mintText(brightness)
        : c.primary;

    return Semantics(
      // A 的 `aria-label`：`<date> 无记录` / `<date> N kcal`。
      label: intake == null
          ? '$dateKey 无记录'
          : '$dateKey ${withThousandsSeparator(intake.round())} kcal',
      button: true,
      selected: isSelected,
      enabled: !isFuture,
      child: InkWell(
        key: Key('meal-day-$dateKey'),
        borderRadius: BorderRadius.circular(
          NutritionRecordWeekStrip.cellRadius,
        ),
        onTap: isFuture ? null : onTap,
        child: Container(
          constraints: const BoxConstraints(
            minHeight: NutritionRecordWeekStrip.cellMinHeight,
          ),
          // A `.date-strip button{padding:8px 2px}`；内容顶对齐（`justify-content:
          // normal`），余量留在底部——靠 Column 默认的 `mainAxisAlignment.start`，
          // **不用** `Container.alignment`：那会让单元格撑满可用高度（单测实测
          // 600dp，A 的按钮不会长成整屏）。
          padding: const EdgeInsets.symmetric(
            vertical: LfDimens.spaceSmall,
            horizontal: 2,
          ),
          decoration: BoxDecoration(
            color: isSelected ? LfColors.brandSoft(brightness) : null,
            borderRadius: BorderRadius.circular(
              NutritionRecordWeekStrip.cellRadius,
            ),
            // 今天但未选中：单元格描边表达「今天在哪」，不靠颜色深浅猜。
            border: isToday && !isSelected
                ? Border.all(
                    color: c.primary,
                    width: NutritionRecordWeekStrip.todayRingWidth,
                  )
                : null,
          ),
          child: ExcludeSemantics(
            // 单元格对外只说一句真话（A 的 `aria-label` 同样**覆盖**按钮文字）：
            // 不加这一层，「一」「7」会被并进标签，读屏念成
            // 「2026-09-07 2,000 kcal 一 7」。
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // A：`.date-strip small{color:var(--muted)}`——选中日也不加深。
                Text(
                  weekdayLabel,
                  style: LfText.micro.copyWith(color: c.mutedForeground),
                ),
                const SizedBox(height: LfDimens.spaceXSmall),
                // 万一本列再窄（极端字号）也**不折行**：按需等比缩小，
                // 而不是把「10」竖排成两个数字。
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    dayNumber,
                    maxLines: 1,
                    softWrap: false,
                    style: LfText.title.copyWith(
                      color: isSelected
                          ? LfColors.mintText(brightness)
                          : isFuture
                          ? c.foreground.withValues(alpha: 0.5)
                          : c.foreground,
                    ),
                  ),
                ),
                const SizedBox(height: LfDimens.spaceXSmall),
                // 短条轨道：固定 5×24，条自底部向上长
                // （A 的 `align-items:flex-end`）。
                Container(
                  width: NutritionRecordWeekStrip.barWidth,
                  height: NutritionRecordWeekStrip.barTrackHeight,
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    width: NutritionRecordWeekStrip.barWidth,
                    height: barHeight,
                    decoration: BoxDecoration(
                      color: barColor,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
