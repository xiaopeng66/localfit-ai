import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/design_card.dart';
import 'package:localfit_ai/app/design/widgets/lf_buttons.dart';
import 'package:localfit_ai/app/design/widgets/lf_segmented_toggle.dart';
import 'package:localfit_ai/app/design/widgets/text_fit.dart';
import 'package:localfit_ai/app/design/widgets/weight_bar_chart.dart';
import 'package:localfit_ai/features/progress/domain/weight_chart_points.dart';
import 'package:localfit_ai/features/progress/domain/weight_measurement.dart';

/// 体重卡（docs/21 §5.1 WeightChartCard；docs/29 §P9 需求 31/32；
/// docs/30 §2 D3 需求 2；docs/31 §1 需求 38–44）。
///
/// 2026-10-08 用户走查四条（R2 已交付）：
///
/// 1. **「周/月切换的按钮太大了，上下宽度也很大，按钮不好看」** —— 当时把
///    `LfSegmentedToggle`（76×48 灰底 + 24dp 小白胶囊）换成两颗 `LfPillButton`。
/// 2. **「月视图的显示好像有问题」** —— 真缺陷（分箱每箱钉死 7 条 ⇒ 2–7 条
///    记录时只出 1 点 ⇒ 谎报「还没有体重记录」），分箱改自适应。
/// 3. **「数据做成柱状图，左边要有坐标」** —— `WeightBarChart`。
/// 4. **「下边的本周趋势三个小卡片不要了」** —— 整段删除。
///
/// 2026-10-09 用户走查七条（docs/31 §1）：
///
/// - **需求 38「体重卡片还是太丑」**：卡头收成一段式——标题块与右侧两件
///   同一条中心线、间距统一 8dp，不再是「文字按钮(62) + 胶囊(56) + 胶囊(56)」
///   三种宽度混排。
/// - **需求 39「周月切换需要我发的第二张图」**：改回**统一轨道 + 内嵌滑块**
///   （用户发的第二张图就是 R2 稿的「改造前」帧那副形态），但视觉高压到
///   28dp（R3 嫌的是尺寸不是形态）。见 [LfSegmentedToggle]。
/// - **需求 40「柱子太宽了」**：柱宽上限 40 → 22dp，格内边距 3 → 8dp。
/// - **需求 41「一周就直接横坐标七天都显示，没有数据的时间就空着」**：
///   周视图改**恒定七格**（见 `buildWeekChartPoints`），空槽不画柱。
/// - **需求 42「月视图标题写本月体重」**：标题「体重趋势」→「本月体重」，
///   并**把月视图口径从「近 30 天」改成真的本月**（否则标题与数据不是一件事）。
/// - **需求 43「下边不要写较月初」**：删那三字，保留 `↓ 1.2`。
/// - **需求 44「添加的按钮只要图标，不要添加两个字」**：新共享件
///   [LfIconButton]（36dp 视觉圆 / 44dp 命中盒 / 无文字 / 有语义标签）。
class DashboardWeightCard extends StatefulWidget {
  const DashboardWeightCard({
    super.key,
    required this.overview,
    required this.onRecord,
    required this.endLocalDate,
    this.onAdd,
  });

  final WeightOverview overview;

  /// 「今天」（或用户选中的日期）：周视图据它找本周周一起、月视图据它取年月。
  ///
  /// **必须由调用方给**，不从 [overview] 推：`WeightOverview` 里没有日期字段
  /// （它装的是 30 天窗口内的记录），照「最后一条的日期」推会在今天还没称时
  /// 锚到昨天，周二早上打开会看到上一周的七格。
  final String endLocalDate;

  /// 空态「记录第一条」的行动（沿用既有入口）。
  final VoidCallback onRecord;

  /// 右上角「添加」的行动。不给时退回 [onRecord]（兼容既有调用点与测试，
  /// 行为与旧版一致：都弹同一个记录弹层）。
  final VoidCallback? onAdd;

  @override
  State<DashboardWeightCard> createState() => _DashboardWeightCardState();
}

class _DashboardWeightCardState extends State<DashboardWeightCard> {
  WeightRange _range = WeightRange.week;

  /// 相对当前周期的偏移（0 = 本周 / 本月，1 = 上一周 / 上一月）。
  ///
  /// 2026-10-22 用户：「体重卡片添加不同周和不同月的切换，可以查询之前的记录」。
  /// 切换视图时归零——「往回退 3 个月」再切到周视图时退回 3 周是两种单位，
  /// 用户没有表达过这个意图，只会困惑。
  int _periodOffset = 0;

  DateTime get _anchorDate {
    final base = parseLocalDate(widget.endLocalDate);
    if (_periodOffset == 0) return base;
    if (_range == WeightRange.week) {
      return base.subtract(Duration(days: 7 * _periodOffset));
    }
    final month = DateTime(base.year, base.month - _periodOffset, 1);
    // 历史月份取该月最后一天：月视图本来就是逐日格，锚在月末才装得下整月。
    return DateTime(month.year, month.month + 1, 0);
  }

  String get _anchorLocalDate => formatIsoLocalDate(_anchorDate);

  /// 周期说明（导航行中间那一段）：本周/本月带前缀，历史周期只给范围。
  String get _periodLabel {
    if (_range == WeightRange.week) {
      final monday = _anchorDate.subtract(
        Duration(days: _anchorDate.weekday - DateTime.monday),
      );
      final sunday = monday.add(const Duration(days: 6));
      final span =
          '${monday.month}/${monday.day}–${sunday.month}/${sunday.day}';
      return _periodOffset == 0 ? '本周 $span' : span;
    }
    final month = '${_anchorDate.year} 年 ${_anchorDate.month} 月';
    return _periodOffset == 0 ? '本月 · $month' : month;
  }

  void _stepPeriod(int delta) {
    setState(() {
      final next = _periodOffset + delta;
      // 不许翻到未来：上一周期按钮只回到 0。
      _periodOffset = next < 0 ? 0 : next;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    // 显式按日期升序，**不依赖入参顺序**：`watchWeightOverview` 用
    // `localDate DESC` 排序（见 measurement_repository），照「末条即最新」
    // 直接取会拿到最旧的一条、图也会整个倒过来（上一版 weight_card 踩过）。
    final ordered = [...widget.overview.measurements]
      ..sort((a, b) => a.localDate.compareTo(b.localDate));
    final points = buildWeightChartPoints(
      ordered,
      _range,
      endLocalDate: _anchorLocalDate,
    );
    final latest = widget.overview.latest;
    // 增减量：只算**有值的格子**的首末差（空槽不是 0）。
    final change = _spanChange(points);
    final monthView = _range == WeightRange.month;
    // Round7 A：标题恒为「体重趋势」（`app.js:131`），周/月之别由 mini-tabs
    // 的选中态 + 读屏标签两处表达。旧稿按分段改标题（「本周体重」/「本月体重」）。
    // **2026-10-16 用户**：「体重趋势卡不要『本周:周一至周日』这类描述
    // （周/月视图都不要）」——caption 的周期注整件下线（原为 A 的第三处表达）。
    const title = '体重趋势';

    return DesignCard(
      key: const Key('dashboard-weight-chart'),
      // 需求 32：**不再整卡可点**（旧版 `onTap: onRecord` + semanticLabel
      // 「点击记录体重」把整张卡变成隐形按钮，滑趋势必误触）。
      // 语义标签改成事实描述，不再宣称可点。
      semanticLabel: monthView ? '本月体重，近一个月' : '本周体重',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: LfText.title.copyWith(color: c.cardForeground),
                ),
              ),
              // A `.weight-tools`：先 mini-tabs，后「添加」图标钮。
              // 需求 39：统一轨道 + 内嵌滑块（形态照用户第二张图）。
              // Key 全保留（`dashboard-weight-range` 落在整组上、
              // `-week`/`-month` 落在各自那一段上），既有断言因此不必改写。
              LfSegmentedToggle(
                key: const Key('dashboard-weight-range'),
                segments: const [
                  WeightRange.week,
                  WeightRange.month,
                ].map((r) => r.label).toList(),
                segmentKeys: const [
                  Key('dashboard-weight-range-week'),
                  Key('dashboard-weight-range-month'),
                ],
                selectedIndex: _range.index,
                onChanged: (i) => setState(() {
                  _range = WeightRange.values[i];
                  _periodOffset = 0;
                }),
                semanticLabel: '体重图范围',
              ),
              const SizedBox(width: LfDimens.spaceSmall),
              // 需求 44：纯图标（36dp 视觉圆 / 44dp 命中盒）。
              // 语义标签仍是「添加体重」——读屏不因视觉精简而失语。
              LfIconButton(
                key: const Key('dashboard-weight-add'),
                icon: Icons.add,
                semanticLabel: '添加体重',
                onPressed: widget.onAdd ?? widget.onRecord,
              ),
            ],
          ),
          const SizedBox(height: LfDimens.spaceTiny),
          // A `.weight-caption`：左「值 26 + kg」；右「最近记录（+ 增减量）」
          // 与一行周期注（11px / 注 10px）。增减量（`_spanChange`，需求 43
          // 保留的「↓ 1.2」）挂在它语义上最近的「最近记录」之后——A 的
          // caption 没有这一格，但它是既有可见事实，按 docs/33 §1.1 不删。
          //
          // 并排与否沿用本页两张卡同一套 [fitsRow] 预算口径（docs/27 §6）：
          // 大字号下**值本身就要一整行**（2.0× / 320dp 实测值 245dp + 间隔
          // 12dp > 卡内 252dp，round7 2A 溢 0.99px，要夹具喂了数据才暴露）
          // ⇒ 值独占一行、注挪到下一行，两段事实都留、不裁也不缩。
          LayoutBuilder(
            builder: (context, constraints) {
              final valueText = Text.rich(
                key: const Key('dashboard-weight-trend-value'),
                TextSpan(
                  children: [
                    TextSpan(
                      text: latest == null
                          ? '—'
                          : latest.weightKg.toStringAsFixed(1),
                      style: LfText.displayLarge.copyWith(
                        color: c.cardForeground,
                      ),
                    ),
                    TextSpan(
                      text: ' kg',
                      style: LfText.caption.copyWith(color: c.mutedForeground),
                    ),
                  ],
                ),
                maxLines: 1,
              );
              final note = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '最近记录',
                          style: LfText.label.copyWith(
                            color: c.mutedForeground,
                          ),
                        ),
                        if (change != null)
                          TextSpan(
                            text:
                                ' ${_changeArrow(change)}'
                                ' ${change.abs().toStringAsFixed(1)}',
                            style: LfText.label.copyWith(
                              color: LfColors.mintText(
                                Theme.of(context).brightness,
                              ),
                            ),
                          ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              );
              if (!fitsRow(
                context,
                available: constraints.maxWidth,
                baseNeed: LfRowBudgets.weightCaption,
              )) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    valueText,
                    const SizedBox(height: LfDimens.spaceSmall),
                    note,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  valueText,
                  const SizedBox(width: LfDimens.spaceSmallPlus),
                  Expanded(child: note),
                ],
              );
            },
          ),
          const SizedBox(height: LfDimens.spaceMedium),
          // 2026-10-22 用户：「体重卡片添加不同周和不同月的切换，可以查询之前的
          // 记录，你看看怎么设计按钮位置和样式」。
          //
          // 设计决定：**不塞进卡头**。卡头已经有「周/月分段 + 添加」两件，再加
          // 前后箭头在 320dp / 2.0× 下必然挤成两行或压字；改为在图表正上方
          // 单独一行 `‹  本周 10/20–10/26  ›`：左边回退、右边前进、中间是当前
          // 周期（这句同时承担「我在看哪一段」），并把「不许翻到未来」表达为
          // 前进钮置灰。空态也保留这一行——否则退到没有记录的历史周期就退不回来。
          Row(
            key: const Key('dashboard-weight-period-nav'),
            children: [
              LfIconButton(
                key: const Key('dashboard-weight-period-prev'),
                icon: Icons.chevron_left,
                semanticLabel: _range == WeightRange.week ? '查看上一周' : '查看上个月',
                onPressed: () => _stepPeriod(1),
              ),
              Expanded(
                child: Text(
                  _periodLabel,
                  key: const Key('dashboard-weight-period-label'),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LfText.micro.copyWith(color: c.mutedForeground),
                ),
              ),
              LfIconButton(
                key: const Key('dashboard-weight-period-next'),
                icon: Icons.chevron_right,
                semanticLabel: _range == WeightRange.week ? '查看下一周' : '查看下个月',
                onPressed: _periodOffset == 0 ? null : () => _stepPeriod(-1),
              ),
            ],
          ),
          // 空态判据：**这一档视图里一个值都没有**。周视图七格里全空、
          // 月视图本月全空，都算空态；反过来「只有 1 条记录」不空（柱图
          // 天然支持单柱，旧口径「2–7 条月视图谎报没有记录」已在 R2 修掉）。
          //
          // 【为什么不能只看 `ordered.isEmpty`】月视图只含**本月**，30 天窗口
          // 里的上月记录会让 `ordered` 非空，但本月七格/五箱其实一个值都没有
          // ——那时画一张空图比说「本月还没有记录」更糟。
          if (points.every((p) => p.isEmpty))
            _EmptyChart(
              onRecord: widget.onRecord,
              title: switch ((_range, _periodOffset > 0)) {
                (WeightRange.week, false) => '本周还没有记录',
                (WeightRange.week, true) => '这一周还没有记录',
                (WeightRange.month, false) => '本月还没有记录',
                (WeightRange.month, true) => '这个月还没有记录',
              },
            )
          else ...[
            WeightBarChart(
              points: points,
              range: _range,
              // 只有停在当前周期时才高亮「今天」那一柱：退到历史周期还点亮
              // 一格会把回看当成现状。
              todayLocalDate: _periodOffset == 0 ? widget.endLocalDate : null,
            ),
            // A `.chart-hint{font-size:10px;margin-top:9px}`：有柱时才画
            // （空态自己已经把「没有记录」说全，不重复第二遍）。
            Padding(
              padding: const EdgeInsets.only(top: LfDimens.chartHintMarginTop),
              child: Text(
                '点击柱条看记录，空白日期未记录',
                key: const Key('dashboard-weight-hint'),
                style: LfText.micro.copyWith(color: c.mutedForeground),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 首末差值；**只算有值的格子**，不足 2 个返回 null（不伪造趋势）。
  ///
  /// 空槽的 `weightKg` 是 0（哨兵值，见 [WeightChartPoint.empty]），
  /// 直接 `points.last / points.first` 会让「周一空、周二 65、周三 66」
  /// 算出 66 − 0 = 66kg 的荒唐增减量。
  static double? _spanChange(List<WeightChartPoint> points) {
    final valued = [
      for (final p in points)
        if (!p.isEmpty) p,
    ];
    if (valued.length < 2) return null;
    return valued.last.weightKg - valued.first.weightKg;
  }

  static String _changeArrow(double delta) {
    if (delta > 0) return '↑';
    if (delta < 0) return '↓';
    return '→';
  }
}

/// 这一档视图里一条记录都没有时的诚实空态 + 记录入口。
///
/// 与柱图**同一套骨架**（左侧轴列 + 三条与刻度对齐的虚线），在其上内嵌一句
/// 说明与紧凑记录钮 —— 整卡与有数据时的形态一致，不会「从图突然变成一句话」。
/// 虚线位置沿用 [WeightBarChart] 的默认轴（0 / 50% / 100%），与柱图的网格
/// 同一条口径。
class _EmptyChart extends StatelessWidget {
  const _EmptyChart({required this.onRecord, required this.title});

  final VoidCallback onRecord;

  /// 空态标题：周视图/月视图各说各的（「本周还没有记录」/「本月还没有记录」）。
  /// 月视图曾一律写「还没有体重记录」，但用户是在**本月**这一档里看不到柱
  /// ——说清楚是哪一档没有，比一句笼统的「没有记录」有用。
  final String title;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    return SizedBox(
      // 与柱图同高：上内边距 + 柱区 + 标签行（A `.weight-chart{height:150px}`）。
      height:
          LfDimens.weightChartTopPadding +
          LfDimens.weightChartHeight +
          LfDimens.weightChartLabelRowHeight,
      child: Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.only(
                left: LfDimens.weightChartAxisWidth + LfDimens.spaceXSmall,
              ),
              child: CustomPaint(painter: _EmptyGridPainter(grid: c.border)),
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 文案带卡片色衬底：网格虚线不该从字中间穿过（设计稿渲染
                // 时看着脏，2026-10-09 v2 稿实测）。
                DecoratedBox(
                  decoration: BoxDecoration(color: c.card),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: LfDimens.spaceSmallPlus,
                    ),
                    child: Text(
                      title,
                      key: const Key('dashboard-weight-empty'),
                      textAlign: TextAlign.center,
                      style: LfText.caption.copyWith(color: c.mutedForeground),
                    ),
                  ),
                ),
                const SizedBox(height: LfDimens.spaceXSmall),
                // 空态行动一律 B6 文字按钮（§3.8 硬规则）。原先是
                // `FilledButton.tonal` 且没设颜色——走回落链 `secondaryContainer
                // ?? secondary`，与实心主按钮同色的 mint-600，正是用户
                // 2026-10-03 点名的那颗。
                LfTextButton(
                  key: const Key('dashboard-weight-record'),
                  label: '记录第一条',
                  onPressed: onRecord,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 空态网格：与 [WeightBarChart] 同款三条水平虚线（0 / 50% / 100%）。
class _EmptyGridPainter extends CustomPainter {
  const _EmptyGridPainter({required this.grid});

  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = grid
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final t in const [0.0, 0.5, 1.0]) {
      final y = t == 0 ? 0.5 : (t == 1.0 ? size.height - 0.5 : size.height * t);
      final path = Path()
        ..moveTo(0, y)
        ..lineTo(size.width, y);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_EmptyGridPainter oldDelegate) => oldDelegate.grid != grid;
}
