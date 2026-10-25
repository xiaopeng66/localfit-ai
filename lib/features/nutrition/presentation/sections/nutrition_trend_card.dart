import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/chart_semantics.dart';
import 'package:localfit_ai/app/design/widgets/design_card.dart';
import 'package:localfit_ai/features/nutrition/application/build_calorie_trend.dart';

/// 柱的语义色档（见 [trendBarTone]）。
enum TrendBarTone {
  /// 那天没有记录（灰短柱）。
  empty,

  /// 那天超过热量目标上限。
  over,

  /// 那天有记录且在目标内。
  track,
}

/// 一根柱的颜色档：A `.trend-bar` 的 `无记录 --border / 超目标 --protein /
/// 其余 --brand`。
///
/// 未设目标时没有「超目标」可言（一律 [TrendBarTone.track]）；恰好等于目标
/// 也不算超（A 用 `>` 判定）。
TrendBarTone trendBarTone({required double? kcal, double? targetKcal}) {
  if (kcal == null) return TrendBarTone.empty;
  if (targetKcal != null && kcal > targetKcal) return TrendBarTone.over;
  return TrendBarTone.track;
}

/// 一根柱的高度比例（0..1，分母 = [CalorieTrendBars.scaleMaxKcal]）。
///
/// A：无记录 `3%`、有记录 `max(2%, kcal / 纵轴上界)`——「记了 0 kcal」与
/// 「没记录」在柱高上必须能区分（前者 2% 实心条，后者 3% 灰短柱）。
double trendBarFraction(CalorieTrendBars bars, int index) {
  final kcal = bars.kcalByDay[index];
  if (kcal == null) return _noRecordFraction;
  return (kcal / bars.scaleMaxKcal).clamp(_minTrackedFraction, 1.0);
}

/// A `nutritionTrend()` 的实测几何（360dp 浏览器取整到 dp）。
const double _plotHeight = 101; // `.trend-plot` 高（含 1px 下边框）

/// 「目标 N」标签与柱区顶边的间隔（2026-10-16 用户要求标签移到柱区之上）。
const double _targetLabelAboveGap = 4;

/// 「目标 N」标签的字号（A `.target-line>span{font-size:9px}`）。
const double _targetLabelFontSize = 9;
const double _chartPadding = 22; // `.nutrition-bar-chart{padding:22px 0}`
const double _axisBaseWidth = 30; // `.trend-axis{width:30px}`
const double _chartGap = 8; // `.nutrition-bar-chart{gap:8px}`
const double _columnGap = 8; // `.trend-column` 之间的 gap
const double _dayLabelGap = 6; // 日号 `top:calc(100% + 6px)`
const double _hintGap = 9; // `.chart-hint{margin-top:9px}`
const double _emptyHeight = 80; // `.chart-empty{min-height:80px}`
const double _barMaxWidth = 24; // `.trend-bar{max-width:24px}`
const double _barWidthRatio = 0.6; // `.trend-bar{width:60%}`
const double _noRecordFraction = 0.03;
const double _minTrackedFraction = 0.02;

/// 轴宽占卡片内容宽的上限：A 的 `.trend-axis` 是定宽 30，但大字号下
/// 「2,200」放不进 30dp——轴按实测文字宽让位，上限 28%（剩余留给柱区）。
const double _axisMaxWidthRatio = 0.28;

/// 七日摄入趋势卡（docs/21 §5.2 `nutrition-record-trend-chart`）。
///
/// 视觉 = Round7 A `nutritionTrend()`：标题行「七日摄入趋势」+ 右侧
/// 「N 天有记录」；图区 = 纵轴两档 + 柱区（1px 下边框）+ 柱下 6dp 的日号；
/// 柱色分「无记录 / 超目标 / 在轨」三档；有目标时画 1px 虚线 + 右端
/// 「目标 N」标签。达标天数**不在这张卡上**（D13：分析卡承载，本卡不再有
/// 副标题与徽标）。
///
/// 柱高只是缩放图，逐日事实由 [_TrendSemantics] 的文字等价物给出。
class NutritionTrendCard extends StatelessWidget {
  const NutritionTrendCard({super.key, required this.bars, this.targetKcal});

  final CalorieTrendBars bars;

  /// 目标线的位置；null = 未设目标 → 不画虚线、不写标签、hint 少一句。
  final double? targetKcal;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final target = targetKcal;

    return DesignCard(
      key: const Key('nutrition-record-trend-chart'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '七日摄入趋势',
                  style: LfText.title.copyWith(color: c.cardForeground),
                ),
              ),
              Text(
                '${bars.trackedDays} 天有记录',
                key: const Key('nutrition-record-trend-tracked'),
                style: LfText.caption.copyWith(color: c.mutedForeground),
              ),
            ],
          ),
          if (bars.trackedDays == 0)
            // 窗口内一条记录都没有：画 7 根空柱会让人以为「连续 7 天没吃」，
            // 直接给一句话更诚实（A `.chart-empty`）。空态不需要坐标轴——轴、
            // 日号与 hint 都不渲染。
            SizedBox(
              key: const Key('nutrition-record-trend-empty'),
              height: _emptyHeight,
              child: Center(
                child: Text(
                  '近 7 日还没有记录。',
                  style: LfText.caption.copyWith(color: c.mutedForeground),
                ),
              ),
            )
          else ...[
            const SizedBox(height: LfDimens.spaceSmall), // A `margin-top:8px`
            // 图表的文字等价物（docs/21 §3 / §5.8.3：图形本身排除语义，
            // 读屏读到的是完整句子而不是散落的数字）。
            ChartSemantics(
              summary: _trendSummary(bars: bars, targetKcal: target),
              child: _TrendChartArea(bars: bars, targetKcal: target),
            ),
            Padding(
              padding: const EdgeInsets.only(top: _hintGap),
              child: Text(
                target == null
                    ? '单位 kcal · 灰色短柱为无记录'
                    : '单位 kcal · 灰色短柱为无记录 · 虚线为每日目标',
                style: LfText.micro.copyWith(color: c.mutedForeground),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 逐日事实的读屏摘要：「七日摄入趋势：周一 2000 kcal，…；目标 1800 kcal」。
String _trendSummary({required CalorieTrendBars bars, double? targetKcal}) {
  final parts = <String>[
    for (var i = 0; i < bars.dates.length; i++)
      '周${bars.weekdayLabels[i]} '
          '${bars.kcalByDay[i] == null ? '无记录' : '${bars.kcalByDay[i]!.round()} kcal'}',
  ];
  return '七日摄入趋势：${parts.join('，')}'
      '${targetKcal == null ? '' : '；目标 ${targetKcal.round()} kcal'}';
}

/// 图区：纵轴 + 柱区 + 目标虚线 + 柱下日号。
///
/// 高度按「上下 22 内边距 + 柱区 101」取，A 的 145 就是这两段之和；日号落在
/// 下内边距里（`top:calc(100% + 6px)` 是溢出定位），大字号下日号变高时整段
/// 跟着长高——图区不裁字、不缩字号。
class _TrendChartArea extends StatelessWidget {
  const _TrendChartArea({required this.bars, required this.targetKcal});

  final CalorieTrendBars bars;
  final double? targetKcal;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final labelStyle = LfText.micro.copyWith(color: c.mutedForeground);
    // 日号文字盒的高度（`fontSize × height` 再乘系统字号），与渲染一致。
    final scaler = MediaQuery.textScalerOf(context);
    final labelBoxHeight =
        scaler.scale(labelStyle.fontSize!) * (labelStyle.height ?? 1);
    // A 的 145 = 上下内边距 22×2 + 柱区 101；日号（`top:calc(100%+6px)`）
    // 就落在下内边距里。大字号的日号变高时，下内边距先被吃掉、不够再长高——
    // 所以取「A 的 145」与「上内边距 + 柱区 + gap + 日号盒」的大者。
    // 顶部内边距除 A 的 22 外，还要容得下「目标 N」标签（2026-10-16 起它
    // 画在柱区之上）：大字号下标签盒变高时先长上内边距，不盖住柱区。
    final targetLabelBoxHeight =
        scaler.scale(_targetLabelFontSize) * (LfText.micro.height ?? 1.2);
    final hasTarget = targetKcal != null;
    final topInset = hasTarget
        ? math.max(
            _chartPadding,
            targetLabelBoxHeight + _targetLabelAboveGap + 1,
          )
        : _chartPadding;
    final chartHeight = math.max(
      topInset + _chartPadding + _plotHeight,
      topInset + _plotHeight + _dayLabelGap + labelBoxHeight,
    );

    return Container(
      key: const Key('nutrition-record-trend-chart-area'),
      height: chartHeight,
      padding: EdgeInsets.only(top: topInset, bottom: _chartPadding),
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 轴不再整体上移（旧 A `translateY(-5px)` 已退场）：2026-10-22
            // 用户报「纵坐标高度有点偏移」——上移 5dp 会让顶档刻度与柱区上缘
            // 错开 5dp。改用绝对定位把四档刻度**钉在网格线上**（0/⅓/⅔/1），
            // 每个 `FractionalTranslation(0,-0.5)` 让文字中心对齐刻度线，
            // `_axisLift` 常量保留给既有断言引用（值已不被消费）。
            ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: _axisBaseWidth,
                maxWidth: math.max(
                  _axisBaseWidth,
                  constraints.maxWidth * _axisMaxWidthRatio,
                ),
              ),
              child: IntrinsicWidth(
                // IntrinsicWidth 必须量到**刻度文字**才能让位：Stack 只把
                // 约束传下去，宽度由 Positioned 的文字实测决定（left:0 起排，
                // 不设宽度 ⇒ 收敛到文字本宽）。IntrinsicWidth 会走 child 的
                // computeMaxIntrinsicWidth，Stack 会聚合所有 Positioned 子女
                // 的横向需求，所以「2,200」这种宽档能把轴撑到 >30。
                child: SizedBox(
                  key: const Key('nutrition-record-trend-axis'),
                  height: _plotHeight,
                  // 2026-10-22 用户：「纵轴值有点少，就收尾两个，增加为 4 个
                  // 点」——四档刻度 = 上界 / ⅔ 上界 / ⅓ 上界 / 0。绝对定位
                  // （Stack + Positioned）与体重图 `weight-bar-chart` 同做法：
                  // 刻度直接钉在网格线位置（0/⅓/⅔/1），且不参与 flex ⇒
                  // 2.0× 大字号下不会 RenderFlex overflow（加四档时暴露）。
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // 尺寸锚：Stack 的内在宽不含 Positioned 子女，用一个
                      // 不可见的**最宽档文本**把 IntrinsicWidth 撑起来
                      // （轴让位判据「>30」依赖它）。
                      Opacity(
                        opacity: 0,
                        child: Text(
                          _tickLabel(bars.scaleMaxKcal, 0),
                          maxLines: 1,
                          style: labelStyle,
                        ),
                      ),
                      for (var i = 0; i < 4; i++)
                        Positioned(
                          key: Key('nutrition-record-trend-tick-$i'),
                          left: 0,
                          top: _plotHeight * i / 3,
                          child: FractionalTranslation(
                            translation: const Offset(0, -0.5),
                            child: Text(
                              _tickLabel(bars.scaleMaxKcal, i),
                              maxLines: 1,
                              style: labelStyle,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: _chartGap),
            Expanded(
              child: _TrendPlot(bars: bars, targetKcal: targetKcal),
            ),
          ],
        ),
      ),
    );
  }
}

/// 柱区：1px 下边框的柱区 + 柱下 6dp 的日号 + 目标虚线与其标签。
///
/// 日号与虚线都用 `Stack` 的溢出定位（`Clip.none`）——它们在 A 里是
/// `position:absolute` 地画进图区内边距的，占位会让柱区不再是 101。
class _TrendPlot extends StatelessWidget {
  const _TrendPlot({required this.bars, required this.targetKcal});

  final CalorieTrendBars bars;
  final double? targetKcal;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final target = targetKcal;
    final labelStyle = LfText.micro.copyWith(color: c.mutedForeground);
    // 目标线在柱区里的高度（与 D17 的上界同分母）。
    final targetLineY = target == null
        ? 0.0
        : (_plotHeight * (target / bars.scaleMaxKcal)).clamp(0.0, _plotHeight);

    return SizedBox(
      height: _plotHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Container(
              key: const Key('nutrition-record-trend-plot'),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: c.border)),
              ),
              child: CustomPaint(
                painter: _TrendBarPainter(
                  bars: bars,
                  targetKcal: target,
                  emptyColor: c.border,
                  overColor: c.protein,
                  trackColor: c.primary,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
          if (target != null) ...[
            // 目标虚线：位置 = 目标 / 上界 × 柱区高，与柱同坐标系。
            Positioned(
              left: 0,
              right: 0,
              top: _plotHeight - targetLineY,
              child: CustomPaint(
                painter: _DashedLinePainter(color: c.mutedForeground),
                child: const SizedBox(height: 1, width: double.infinity),
              ),
            ),
            // 「目标 N」标签：**在柱区之外（上方）**、右端与柱区齐平。
            // 2026-10-16 用户：「目标标签能不能放在柱状图界外（往上移）」
            // ——原先贴在虚线右端（压在柱身与网格上，也和柱子抢视线）。
            // 虚线本身留在原处（「目标在哪」的事实仍由它表达）。
            Positioned(
              right: 0,
              bottom: _plotHeight + _targetLabelAboveGap,
              child: Container(
                color: c.card,
                padding: const EdgeInsets.only(left: LfDimens.spaceXSmall),
                child: Text(
                  '目标 ${_groupedKcal(target)}',
                  style: LfText.micro.copyWith(
                    fontSize: _targetLabelFontSize,
                    color: c.mutedForeground,
                  ),
                ),
              ),
            ),
          ],
          // 日号：柱下 6dp，与柱共用同一份列划分（含列间 8dp）。
          //
          // 每格 `FittedBox(scaleDown)` + `softWrap: false`：320dp×2.0× 时每格
          // 只剩 ~20dp，「10」这样的两位日号会折成两行——而日号画在 `Stack`
          // 的溢出定位里（`Clip.none`），折出的第二行直接压到卡片下方的 hint
          // 上（320dp×2.0× 帧里「单位 kcal · 灰色短柱为无记录」被数字盖住的
          // 就是这一处，同一行里还有一格单行日号被邻居撑高的行盒顶下去）。
          // 日号是事实性短标签，宁可等比缩小也不折行、不省略（与
          // `LfStatTile`/`LfCalorieRing` 同一处理）。
          Positioned(
            left: 0,
            right: 0,
            top: _plotHeight + _dayLabelGap,
            child: Row(
              children: [
                for (var i = 0; i < bars.dates.length; i++) ...[
                  if (i > 0) const SizedBox(width: _columnGap),
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        _dayLabel(bars.dates[i]),
                        maxLines: 1,
                        softWrap: false,
                        textAlign: TextAlign.center,
                        style: labelStyle,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// `yyyy-MM-dd` → 日号（去前导零，设计稿形态 7/8/…/13）。
String _dayLabel(String localDate) =>
    localDate.split('-').last.replaceFirst(RegExp(r'^0'), '');

/// 纵轴刻度与目标标签的千分位整数（2,200 / 目标 1,800）。
/// 纵轴第 `index` 档（0=顶，3=0）的刻度文字；沿用千分位口径。
String _tickLabel(double scaleMax, int index) {
  assert(index >= 0 && index <= 3);
  return _groupedKcal(scaleMax * (3 - index) / 3);
}

String _groupedKcal(double value) {
  final text = value.round().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    if (i > 0 && (text.length - i) % 3 == 0) buffer.write(',');
    buffer.write(text[i]);
  }
  return buffer.toString();
}

/// 手绘 7 柱（docs/21 §3.2：新图表一律 `CustomPainter`，不引 fl_chart）。
class _TrendBarPainter extends CustomPainter {
  const _TrendBarPainter({
    required this.bars,
    required this.targetKcal,
    required this.emptyColor,
    required this.overColor,
    required this.trackColor,
  });

  final CalorieTrendBars bars;
  final double? targetKcal;
  final Color emptyColor;
  final Color overColor;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final count = bars.dates.length;
    if (count == 0) return;
    final column = (size.width - _columnGap * (count - 1)) / count;
    final barWidth = math.min(_barMaxWidth, column * _barWidthRatio);
    final radius = Radius.circular(LfDimens.radiusXs);

    for (var i = 0; i < count; i++) {
      final color = switch (trendBarTone(
        kcal: bars.kcalByDay[i],
        targetKcal: targetKcal,
      )) {
        TrendBarTone.empty => emptyColor,
        TrendBarTone.over => overColor,
        TrendBarTone.track => trackColor,
      };
      final drawn = trendBarFraction(bars, i) * size.height;
      final left = i * (column + _columnGap) + (column - barWidth) / 2;
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTRB(
            left,
            size.height - drawn,
            left + barWidth,
            size.height,
          ),
          topLeft: radius,
          topRight: radius,
        ),
        Paint()
          ..style = PaintingStyle.fill
          ..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_TrendBarPainter oldDelegate) =>
      oldDelegate.bars != bars ||
      oldDelegate.targetKcal != targetKcal ||
      oldDelegate.emptyColor != emptyColor ||
      oldDelegate.overColor != overColor ||
      oldDelegate.trackColor != trackColor;
}

/// 1px 虚线（dash 4 / gap 4），用于目标线。
class _DashedLinePainter extends CustomPainter {
  const _DashedLinePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 8) {
      canvas.drawLine(
        Offset(x, 0.5),
        Offset(math.min(x + 4, size.width), 0.5),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DashedLinePainter oldDelegate) =>
      oldDelegate.color != color;
}
