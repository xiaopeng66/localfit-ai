import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/chart_semantics.dart';
import 'package:localfit_ai/features/progress/domain/weight_chart_points.dart';

/// 体重柱状图（Round7 A `.weight-chart` / `.weight-bar-space` /
/// `.weight-slot`，`refinement.css:6`）。
///
/// 周视图保持七格和 22dp 柱宽上限；月视图为本月逐日槽位，柱宽按
/// `clamp(格宽 - 2, 3, 8)` 计算。每个有值槽位可点击显示一位小数浮窗。
///
/// A 起的三处结构变化（阶段 2 迁移）：
///
/// 1. **去 `kg` 单位行**：数值行的 `kg` 由卡片 caption 承担（`weight-trend-value
///    small`），图内不再有一行孤立的单位（`weight-bar-chart-unit` 退场）。
/// 2. **标签行内嵌**：日期标签（`.weight-slot small{height:20px}`）住在柱区之下
///    25dp 里，网格线与刻度只铺柱区（`.weight-bar-space{height:calc(100% - 25px)}`
///    + `.chart-rules{inset:0 0 25px}`），整图总高 = 上内边距 12 + 柱区 113 + 标签 25。
/// 3. **柱色**：默认 `--weight`（亮 #C9A27E / 暗 #D4B08E，[LfSemanticColors.weight]），
///    **今天那一格** 用 `--brand`（[LfSemanticColors.primary]）；本轮无
///    「最新一格」概念（A 只区分今天），选中态保留高亮档（见下）。
class WeightBarChart extends StatefulWidget {
  const WeightBarChart({
    super.key,
    required this.points,
    required this.range,
    this.todayLocalDate,
  });

  final List<WeightChartPoint> points;
  final WeightRange range;

  /// 「今天」（`yyyy-MM-dd`）。与某一格日期相同的那一柱用 `--brand` 画
  /// （A `.weight-slot.current`）；null = 不高亮任何一格。
  final String? todayLocalDate;

  static const double axisPadRatio = 0.25;
  static const double singlePointHalfSpanKg = 0.5;
  static const double maxBarWidth = 22;
  static const double maxMonthBarWidth = 8;
  static const double minBarWidth = 3;
  static const double barSlotPadding = 8;
  static const int gridLineCount = 4;

  /// 轴范围外扩 25%，返回从上到下的 4 档刻度。
  static ({double min, double max, List<double> ticks}) axisFor(
    List<double> values,
  ) {
    assert(values.isNotEmpty, '没有数据就没有轴');
    final lo = values.reduce(math.min);
    final hi = values.reduce(math.max);
    late final double axisMin;
    late final double axisMax;
    if (hi - lo < 1e-9) {
      axisMin = lo - singlePointHalfSpanKg;
      axisMax = hi + singlePointHalfSpanKg;
    } else {
      final pad = (hi - lo) * axisPadRatio;
      axisMin = lo - pad;
      axisMax = hi + pad;
    }
    final span = axisMax - axisMin;
    return (
      min: axisMin,
      max: axisMax,
      ticks: [axisMax, axisMax - span / 3, axisMax - span * 2 / 3, axisMin],
    );
  }

  static String tickLabel(double value) => value.toStringAsFixed(1);

  @override
  State<WeightBarChart> createState() => _WeightBarChartState();
}

class _WeightBarChartState extends State<WeightBarChart> {
  int? _selectedIndex;

  @override
  void didUpdateWidget(covariant WeightBarChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.range != widget.range ||
        oldWidget.points.length != widget.points.length) {
      _selectedIndex = null;
    }
  }

  void _clearSelection() {
    if (_selectedIndex != null && mounted) {
      setState(() => _selectedIndex = null);
    }
  }

  /// 柱色（A `#todayPage` weightBlock）：默认 `--weight`，**今天那一格** `--brand`。
  ///
  /// 选中不改色（A 的机制是浮窗报值，柱本身不变色）：旧实现的
  /// 「选中 = mint-700 / 最新一根 = mint-600」两档随 A 退场——「最新一根」
  /// 这个身份在 A 里不存在（caption 已写「最近记录」），而选中态由
  /// `weight-bar-chart-tooltip` 承担，不再借颜色表达第二条数据事实。
  Color _barColor(bool current) =>
      current ? context.lf.primary : context.lf.weight;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final valued = [
      for (final p in widget.points)
        if (!p.isEmpty) p,
    ];
    final axis = WeightBarChart.axisFor(
      valued.isEmpty ? const [0.0] : [for (final p in valued) p.weightKg],
    );
    final span = axis.max - axis.min;

    final chart = Column(
      key: const Key('weight-bar-chart'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // A `.weight-chart{padding-top:12px}`。
        const SizedBox(height: LfDimens.weightChartTopPadding),
        SizedBox(
          // 柱区 + 标签行（A：150 − 12 上内边距）。
          height:
              LfDimens.weightChartHeight + LfDimens.weightChartLabelRowHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: LfDimens.weightChartAxisWidth,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // 刻度只铺柱区（A `.chart-axis{padding-bottom:25px}`），
                    // 标签行那 25dp 里不画刻度；每个刻度文字与网格线中心对齐
                    // （A 另有 `margin-top:-6px` 的整体上移，本仓不跟——
                    // 那会让四个刻度文字相对网格线统一偏上 6dp，见证据文件
                    // 阶段 2「记录在案的偏离」）。
                    for (var i = 0; i < axis.ticks.length; i++)
                      Positioned(
                        right: 0,
                        top: _tickTop(i, axis.ticks.length),
                        child: FractionalTranslation(
                          translation: const Offset(0, -0.5),
                          child: Text(
                            WeightBarChart.tickLabel(axis.ticks[i]),
                            key: Key('weight-bar-chart-tick-$i'),
                            style: LfText.micro.copyWith(
                              color: c.mutedForeground,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: LfDimens.spaceSmall),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final plotWidth = constraints.maxWidth;
                    final count = widget.points.length;
                    final slotWidth = count == 0
                        ? plotWidth
                        : plotWidth / count;
                    final barWidth = _barWidth(slotWidth);
                    final selected = _selectedIndex;
                    final selectedPoint =
                        selected == null ||
                            selected < 0 ||
                            selected >= widget.points.length
                        ? null
                        : widget.points[selected];
                    final selectedBarHeight =
                        selectedPoint == null || selectedPoint.isEmpty
                        ? 0.0
                        : _barHeight(selectedPoint.weightKg, axis, span);
                    // 左边缘 = 格心 − 半宽（半宽与下面的定宽同源，见
                    // `LfDimens.weightChartTooltipWidth`）；贴边时钳进绘图区。
                    const halfTooltip = LfDimens.weightChartTooltipWidth / 2;
                    final tooltipLeft = selected == null
                        ? 0.0
                        : (slotWidth * (selected + 0.5) - halfTooltip)
                              .clamp(
                                0.0,
                                math.max(
                                  0.0,
                                  plotWidth - LfDimens.weightChartTooltipWidth,
                                ),
                              )
                              .toDouble();

                    return Stack(
                      key: const Key('weight-bar-chart-plot'),
                      clipBehavior: Clip.none,
                      children: [
                        for (var i = 0; i < WeightBarChart.gridLineCount; i++)
                          Positioned(
                            key: Key('weight-bar-chart-grid-line-$i'),
                            left: 0,
                            right: 0,
                            top: _tickTop(i, WeightBarChart.gridLineCount),
                            child: SizedBox(
                              height: 1,
                              child: CustomPaint(
                                painter: _DashLinePainter(grid: c.border),
                              ),
                            ),
                          ),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (var i = 0; i < widget.points.length; i++)
                              Expanded(
                                child: _Slot(
                                  point: widget.points[i],
                                  index: i,
                                  barWidth: barWidth,
                                  barHeight: widget.points[i].isEmpty
                                      ? 0
                                      : _barHeight(
                                          widget.points[i].weightKg,
                                          axis,
                                          span,
                                        ),
                                  barColor: _barColor(
                                    widget.points[i].localDate != null &&
                                        widget.points[i].localDate ==
                                            widget.todayLocalDate,
                                  ),
                                  selected: i == selected,
                                  // 2026-10-22 用户：「月视图点柱时，横坐标原来
                                  // 存在的几个日期先隐藏，只显示被点那根柱子的
                                  // 日期、颜色深一点」——周视图七天标签保持不变
                                  // （用户要求「文字全部显示」）。
                                  hideLabel:
                                      widget.range == WeightRange.month &&
                                      selected != null &&
                                      i != selected,
                                  emphasizeLabel:
                                      widget.range == WeightRange.month &&
                                      selected == i,
                                  onTap: () => setState(
                                    () => _selectedIndex =
                                        widget.points[i].isEmpty
                                        ? null
                                        : (_selectedIndex == i ? null : i),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        if (selectedPoint != null && !selectedPoint.isEmpty)
                          Positioned(
                            key: const Key('weight-bar-chart-tooltip'),
                            left: tooltipLeft,
                            // `bottom` 从 **Stack 底** 量起，而柱区的底边在
                            // 标签行之上 25dp——漏掉这一截，浮窗会整体下沉
                            // 到柱身上（短柱时几乎盖满它），于是「再点一次
                            // 收起」的点击落进浮窗、根本碰不到柱子
                            // （round5 T1 实测：命中路径第一层就是浮窗文字）。
                            // A 的 `top=bar.y-26` 同样把浮窗摆在柱顶之上。
                            bottom:
                                LfDimens.weightChartLabelRowHeight +
                                selectedBarHeight +
                                4,
                            // **定宽 64**（不是「至多 64」）+ 框内居中：
                            // 2026-10-16 用户实测「柱子上边的记录文字框有点
                            // 歪」。左边缘按「格心 − 半宽」反推，而框宽随文字
                            // 长短变（'72.5 kg' ≈ 50dp）⇒ 框心偏左
                            // (64 − 宽)/2 ≈ 7dp。宽度钉死、文字居中后，
                            // 框心恒等于格心；左右钳制逻辑不变。
                            // 浮窗是纯展示件：**不吃点击**。
                            // 2026-10-22 新规格（月视图点柱只显示被点日期）落地时
                            // 暴露：短柱的浮窗会盖住本格的可点区域，第二次点击
                            // 落进浮窗、slot 收不到事件 ⇒「再点一次收起」失效。
                            // `IgnorePointer` 让点击穿透到柱子那一格，行为与
                            // 「浮窗只是读数」的定位一致。
                            child: IgnorePointer(
                              child: Container(
                                width: LfDimens.weightChartTooltipWidth,
                                alignment: Alignment.center,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: c.foreground,
                                  borderRadius: BorderRadius.circular(
                                    LfDimens.radiusSm,
                                  ),
                                ),
                                child: Text(
                                  '${selectedPoint.weightKg.toStringAsFixed(1)} kg',
                                  key: const Key(
                                    'weight-bar-chart-tooltip-text',
                                  ),
                                  maxLines: 1,
                                  textAlign: TextAlign.center,
                                  style: LfText.microStrong.copyWith(
                                    color: c.card,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        _clearSelection();
        return false;
      },
      child: ChartSemantics(summary: _summary(), child: chart),
    );
  }

  double _barWidth(double slotWidth) {
    if (widget.range == WeightRange.month) {
      return (slotWidth - 2)
          .clamp(WeightBarChart.minBarWidth, WeightBarChart.maxMonthBarWidth)
          .toDouble();
    }
    return (slotWidth - WeightBarChart.barSlotPadding * 2)
        .clamp(WeightBarChart.minBarWidth, WeightBarChart.maxBarWidth)
        .toDouble();
  }

  static double _barHeight(
    double value,
    ({double min, double max, List<double> ticks}) axis,
    double span,
  ) => math.max(
    4,
    (((value - axis.min) / span).clamp(0.0, 1.0)) * LfDimens.weightChartHeight,
  );

  /// 刻度/网格线在**柱区内**的位置（A `.chart-rules{inset:0 0 25px}`）。
  static double _tickTop(int index, int count) {
    if (count <= 1) return 0;
    return LfDimens.weightChartHeight * index / (count - 1);
  }

  String _summary() {
    final valued = [
      for (final p in widget.points)
        if (!p.isEmpty) p,
    ];
    if (valued.isEmpty) {
      return widget.range == WeightRange.month
          ? '体重图：本月还没有记录。'
          : '体重图：本周还没有记录。';
    }
    final scope = widget.range == WeightRange.month
        ? '本月 ${widget.points.length} 天里 ${valued.length} 天有记录'
        : '本周 ${widget.points.length} 天里 ${valued.length} 天有记录';
    final first = valued.first;
    final last = valued.last;
    final latest = '最新 ${last.weightKg.toStringAsFixed(1)} 公斤（${last.label}）';
    if (valued.length < 2) return '体重图：$scope，$latest，只有一条记录。';
    final delta = last.weightKg - first.weightKg;
    final direction = delta > 0 ? '上升' : (delta < 0 ? '下降' : '持平');
    return '体重图：$scope，$latest，'
        '比${first.label}的 ${first.weightKg.toStringAsFixed(1)} 公斤'
        '$direction ${delta.abs().toStringAsFixed(1)} 公斤。';
  }
}

/// 一格：柱区（`Align.bottomCenter` 柱）+ 标签行（A `.weight-slot`）。
///
/// 空槽只有标签（不画柱、不画点），点击不出浮窗。
class _Slot extends StatelessWidget {
  const _Slot({
    required this.point,
    required this.index,
    required this.barWidth,
    required this.barHeight,
    required this.barColor,
    required this.selected,
    required this.hideLabel,
    required this.emphasizeLabel,
    required this.onTap,
  });

  final WeightChartPoint point;
  final int index;
  final double barWidth;
  final double barHeight;
  final Color barColor;
  final bool selected;

  /// 月视图选中某柱时，**其余格子**的日期标签隐藏（用户 2026-10-22）。
  final bool hideLabel;

  /// 被点中的那一格：显示**完整日期**（`M/D`，不依赖它是不是周一）并用
  /// 前景色加深。
  final bool emphasizeLabel;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    // 强调态显示完整日期：月视图的 `axisLabel` 只在周一非空，直接用它会让
    // 「点周三那根柱」看不到日期，与用户要的「底部显示日期」相反。
    final label = emphasizeLabel ? point.label : point.visibleAxisLabel;
    return GestureDetector(
      key: Key('weight-bar-chart-slot-$index'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        children: [
          SizedBox(
            height: LfDimens.weightChartHeight,
            child: point.isEmpty
                ? const SizedBox.shrink()
                : Align(
                    alignment: Alignment.bottomCenter,
                    child: SizedBox(
                      width: barWidth,
                      height: barHeight,
                      child: DecoratedBox(
                        key: Key('weight-bar-chart-bar-$index'),
                        decoration: BoxDecoration(
                          color: barColor,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(LfDimens.radiusXs),
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
          SizedBox(
            height: LfDimens.weightChartLabelRowHeight,
            child: hideLabel
                ? const SizedBox.shrink()
                : Align(
                    alignment: Alignment.bottomCenter,
                    // 日期标签必须能**跨出自己那一格**居中：月视图一格的宽度是
                    // 绘图区/当月天数（360dp 下约 10dp），而「9/14」要 ~20dp ——
                    // 只给格宽时 `maxLines: 1` 会把文本压成「9」（2026-10-16 月视图
                    // 帧实看抓出；用户早前看到的「一堆 1」也是同一个截断：10/15/20
                    // 这些日号被压成首个字符「1」）。`OverflowBox` 只放宽**这一行
                    // 标签**的约束，条形与命中盒仍严格按格宽；月视图里相邻标签相隔
                    // 7 格（≈70dp）、周视图格宽 ≈40dp，都不会互相压字。
                    child: OverflowBox(
                      maxWidth: LfDimens.weightChartAxisLabelMaxWidth,
                      alignment: Alignment.center,
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        style: LfText.micro.copyWith(
                          color: emphasizeLabel
                              ? c.foreground
                              : point.isEmpty || label.isEmpty
                              ? c.border
                              : c.mutedForeground,
                          fontWeight: emphasizeLabel
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _DashLinePainter extends CustomPainter {
  const _DashLinePainter({required this.grid});

  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 7) {
      canvas.drawLine(
        Offset(x, 0.5),
        Offset(math.min(x + 3, size.width), 0.5),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DashLinePainter oldDelegate) => oldDelegate.grid != grid;
}
