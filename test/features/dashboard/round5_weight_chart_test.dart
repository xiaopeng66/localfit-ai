import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/app/design/widgets/lf_segmented_toggle.dart';
import 'package:localfit_ai/app/design/widgets/weight_bar_chart.dart';
import 'package:localfit_ai/features/dashboard/presentation/sections/dashboard_weight_card.dart';
import 'package:localfit_ai/features/progress/domain/weight_chart_points.dart';
import 'package:localfit_ai/features/progress/domain/weight_measurement.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(body: child),
  );

  WeightMeasurement measurement(String date, double kg) => WeightMeasurement(
    id: date,
    profileId: 'p',
    localDate: date,
    weightKg: kg,
    notes: null,
    createdAt: DateTime.parse(date).toUtc(),
    updatedAt: DateTime.parse(date).toUtc(),
  );

  group('T1 月视图逐日槽位', () {
    test('月视图格数跟随 28/29/30/31 天，空天不伪造记录', () {
      final cases = <String, int>{
        '2026-02-10': 28,
        '2028-02-10': 29,
        '2026-04-10': 30,
        '2026-10-10': 31,
      };
      for (final entry in cases.entries) {
        final points = buildMonthChartPoints([
          measurement('${entry.key.substring(0, 8)}02', 65.0),
        ], endLocalDate: entry.key);
        expect(points, hasLength(entry.value), reason: entry.key);
        expect(points.where((point) => !point.isEmpty), hasLength(1));
        expect(points[0].isEmpty, isTrue, reason: '第 1 天没有记录');
        expect(points[1].isEmpty, isFalse, reason: '第 2 天有记录');
        expect(points[1].weightKg, 65.0);
        expect(points[1].label, '${DateTime.parse(entry.key).month}/2');
        // 2026-10-16 用户第二轮：「月视图你要标的是**每周一**对应的日期，
        // 而不是一堆日号」——横轴只标每周一；非周一即使有记录也不标。
        expect(
          points[0].visibleAxisLabel,
          isEmpty,
          reason: '${entry.key} 的 1 号不是周一 ⇒ 不标',
        );
        // 该月第一个周一必须标出来（2 月按 2026/2028 的日期算）。
        final firstMonday = points.firstWhere(
          (point) =>
              point.localDate != null &&
              DateTime.parse(point.localDate!).weekday == DateTime.monday,
          orElse: () => points.first,
        );
        expect(
          firstMonday.visibleAxisLabel,
          isNotEmpty,
          reason: '每月第一个周一必须有日期标签',
        );
      }
    });

    test('同一天多条记录只取最后更新的一条', () {
      final early = WeightMeasurement(
        id: 'early',
        profileId: 'p',
        localDate: '2026-10-02',
        weightKg: 65.0,
        notes: null,
        createdAt: DateTime.utc(2026, 10, 2),
        updatedAt: DateTime.utc(2026, 10, 2, 8),
      );
      final late = WeightMeasurement(
        id: 'late',
        profileId: 'p',
        localDate: '2026-10-02',
        weightKg: 66.0,
        notes: null,
        createdAt: DateTime.utc(2026, 10, 2),
        updatedAt: DateTime.utc(2026, 10, 2, 12),
      );
      final points = buildMonthChartPoints([
        late,
        early,
      ], endLocalDate: '2026-10-10');
      expect(points[1].weightKg, 66.0);
      expect(points[1].sampleDays, 1);
    });
  });

  group('T1 轴与柱交互', () {
    testWidgets('轴返回 4 档，位置从顶部到下方均分且虚线为 4 条', (tester) async {
      final axis = WeightBarChart.axisFor([64.0, 65.0, 66.0]);
      expect(axis.ticks, hasLength(4));
      expect(axis.ticks.first, axis.max);
      expect(axis.ticks.last, axis.min);
      expect(
        axis.ticks[1],
        closeTo(axis.max - (axis.max - axis.min) / 3, 1e-9),
      );
      expect(
        axis.ticks[2],
        closeTo(axis.max - (axis.max - axis.min) * 2 / 3, 1e-9),
      );
      await tester.pumpWidget(
        host(
          WeightBarChart(
            points: const [
              WeightChartPoint(weightKg: 64, label: '一', sampleDays: 1),
              WeightChartPoint(weightKg: 65, label: '二', sampleDays: 1),
              WeightChartPoint(weightKg: 66, label: '三', sampleDays: 1),
            ],
            range: WeightRange.week,
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (var i = 0; i < 4; i++) {
        expect(find.byKey(Key('weight-bar-chart-tick-$i')), findsOneWidget);
        expect(
          find.byKey(Key('weight-bar-chart-grid-line-$i')),
          findsOneWidget,
        );
      }
    });

    testWidgets('点击有值柱显示并再次点击隐藏数值浮窗', (tester) async {
      final points = [
        const WeightChartPoint.empty(label: '一'),
        const WeightChartPoint(weightKg: 65.2, label: '二', sampleDays: 1),
        const WeightChartPoint.empty(label: '三'),
        const WeightChartPoint(weightKg: 66.1, label: '四', sampleDays: 1),
        const WeightChartPoint.empty(label: '五'),
        const WeightChartPoint.empty(label: '六'),
        const WeightChartPoint.empty(label: '日'),
      ];
      await tester.pumpWidget(
        host(WeightBarChart(points: points, range: WeightRange.week)),
      );
      await tester.pumpAndSettle();

      final bar = find.byKey(const Key('weight-bar-chart-bar-1'));
      await tester.tap(bar);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('weight-bar-chart-tooltip')), findsOneWidget);
      expect(
        tester
            .widget<Text>(
              find.byKey(const Key('weight-bar-chart-tooltip-text')),
            )
            .data,
        '65.2 kg',
        reason: '浮窗报的是这一格的记录值（A `weight-tooltip`）',
      );

      await tester.tap(bar);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('weight-bar-chart-tooltip')), findsNothing);
    });

    testWidgets('点击空白关闭浮窗，点击空槽不改变选中态', (tester) async {
      final points = [
        const WeightChartPoint.empty(label: '一'),
        const WeightChartPoint(weightKg: 65.2, label: '二', sampleDays: 1),
        const WeightChartPoint.empty(label: '三'),
        const WeightChartPoint.empty(label: '四'),
        const WeightChartPoint.empty(label: '五'),
        const WeightChartPoint.empty(label: '六'),
        const WeightChartPoint.empty(label: '日'),
      ];
      await tester.pumpWidget(
        host(WeightBarChart(points: points, range: WeightRange.week)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('weight-bar-chart-bar-1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('weight-bar-chart-tooltip')), findsOneWidget);

      await tester.tap(find.byKey(const Key('weight-bar-chart-slot-0')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('weight-bar-chart-tooltip')), findsNothing);

      final plot = tester.getRect(
        find.byKey(const Key('weight-bar-chart-plot')),
      );
      await tester.tapAt(Offset(plot.left + 2, plot.top + 2));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('weight-bar-chart-tooltip')), findsNothing);
    });

    testWidgets('最后一根柱的浮窗钳制在绘图区内（360dp 窄屏也钳住）', (tester) async {
      // 必须在**用户机型宽度**下量：宽视口下末端气泡本来就不越界，
      // 删掉钳制代码也照样绿（第一版变异实测到的假绿）。
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final points = [
        for (var i = 0; i < 6; i++) const WeightChartPoint.empty(label: ''),
        const WeightChartPoint(weightKg: 65.2, label: '日', sampleDays: 1),
      ];
      await tester.pumpWidget(
        host(WeightBarChart(points: points, range: WeightRange.week)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('weight-bar-chart-bar-6')));
      await tester.pumpAndSettle();

      final tooltip = tester.getRect(
        find.byKey(const Key('weight-bar-chart-tooltip')),
      );
      final plot = tester.getRect(
        find.byKey(const Key('weight-bar-chart-plot')),
      );
      expect(
        tooltip.right,
        lessThanOrEqualTo(plot.right),
        reason:
            '末端柱的浮窗必须被钳在绘图区内（未钳制时会越出 ${(tooltip.right - plot.right).toStringAsFixed(1)}dp）',
      );
      expect(tooltip.left, greaterThanOrEqualTo(plot.left));
      // 钳制生效的**正向**证据：气泡右边缘应停在绘图区右界附近，
      // 而不是被挤回格心（那说明钳的是位置而不是边界）。
      final slot = plot.width / 7;
      final naturalCenter = plot.left + slot * 6.5;
      expect(
        tooltip.right,
        greaterThan(plot.right - 8),
        reason: '钳制后气泡应贴住右边界（自然中心 $naturalCenter vs 绘图区右界 ${plot.right}）',
      );
    });
  });

  group('浮窗对齐（2026-10-16 用户实测：柱子上的记录文字框有点歪）', () {
    testWidgets('浮窗定宽 64、中心对准柱格格心、文字在框内居中', (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final points = [
        for (var i = 0; i < 7; i++)
          WeightChartPoint(weightKg: 60.0 + i, label: '日', sampleDays: 1),
      ];
      await tester.pumpWidget(
        host(WeightBarChart(points: points, range: WeightRange.week)),
      );
      await tester.pumpAndSettle();

      // 中间那格：不受左右钳制影响，纯看对齐。
      await tester.tap(find.byKey(const Key('weight-bar-chart-bar-3')));
      await tester.pumpAndSettle();

      final tooltip = tester.getRect(
        find.byKey(const Key('weight-bar-chart-tooltip')),
      );
      final plot = tester.getRect(
        find.byKey(const Key('weight-bar-chart-plot')),
      );
      final slot = plot.width / 7;
      final slotCenter = plot.left + slot * 3.5;
      // 定宽而不是「至多 64」：宽度随文字长短变 ⇒ 左边缘定位会让它歪。
      expect(tooltip.width, 64);
      expect(tooltip.center.dx, closeTo(slotCenter, 0.5));
      // 框内文字也要居中（不是贴左）。
      final text = tester.getRect(
        find.byKey(const Key('weight-bar-chart-tooltip-text')),
      );
      expect(text.center.dx, closeTo(tooltip.center.dx, 1));
    });
  });

  group('T1 卡头控件几何', () {
    testWidgets('添加钮视觉 28dp、命中 44dp，切换轨道视觉 28dp', (tester) async {
      final only = WeightMeasurement(
        id: 'one',
        profileId: 'p',
        localDate: '2026-10-07',
        weightKg: 65.0,
        notes: null,
        createdAt: DateTime.utc(2026, 10, 7),
        updatedAt: DateTime.utc(2026, 10, 7),
      );
      await tester.pumpWidget(
        host(
          DashboardWeightCard(
            overview: WeightOverview(
              measurements: [only],
              latest: only,
              sevenDayAverageKg: null,
              sampleDays: 1,
            ),
            endLocalDate: '2026-10-07',
            onRecord: _noop,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final add = find.byKey(const Key('dashboard-weight-add'));
      expect(tester.getSize(add), const Size(44, 44));
      final circle = find.descendant(of: add, matching: find.byType(Material));
      expect(tester.getSize(circle.first), const Size(28, 28));
      final track = find.byKey(const Key('lf-segmented-track'));
      // Round7 A 有效值（`refinement.css:5` `.mini-tabs{height:36px}`）：轨道
      // 视觉高从 28 提升到 36，滑块 42×28，命中仍 44。
      expect(tester.getSize(track).height, 36);
      expect(find.byKey(const Key('lf-segmented-thumb')), findsOneWidget);
    });

    testWidgets('切换月视图会关闭已经打开的周视图浮窗', (tester) async {
      final only = WeightMeasurement(
        id: 'one',
        profileId: 'p',
        localDate: '2026-10-07',
        weightKg: 65.0,
        notes: null,
        createdAt: DateTime.utc(2026, 10, 7),
        updatedAt: DateTime.utc(2026, 10, 7),
      );
      await tester.pumpWidget(
        host(
          DashboardWeightCard(
            overview: WeightOverview(
              measurements: [only],
              latest: only,
              sevenDayAverageKg: null,
              sampleDays: 1,
            ),
            endLocalDate: '2026-10-07',
            onRecord: _noop,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('weight-bar-chart-bar-2')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('weight-bar-chart-tooltip')), findsOneWidget);

      await tester.tap(find.byKey(const Key('dashboard-weight-range-month')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('weight-bar-chart-tooltip')), findsNothing);
    });

    testWidgets('月视图柱宽随格宽收窄并限制在 3–8dp，周视图不回归 22dp 上限', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final measurements = [
        for (var day = 1; day <= 31; day++)
          WeightMeasurement(
            id: 'd$day',
            profileId: 'p',
            localDate: '2026-10-${day.toString().padLeft(2, '0')}',
            weightKg: 65.0 + day * 0.01,
            notes: null,
            createdAt: DateTime.utc(2026, 10, 31),
            updatedAt: DateTime.utc(2026, 10, 31),
          ),
      ];
      await tester.pumpWidget(
        host(
          DashboardWeightCard(
            overview: WeightOverview(
              measurements: measurements,
              latest: measurements.last,
              sevenDayAverageKg: null,
              sampleDays: measurements.length,
            ),
            endLocalDate: '2026-10-31',
            onRecord: _noop,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 周视图：柱宽仍是既有 22dp 上限（需求 40 不回归）。
      final weekBar = tester.getRect(
        find.byKey(const Key('weight-bar-chart-bar-3')),
      );
      expect(weekBar.width, closeTo(22, 1));

      await tester.tap(find.byKey(const Key('dashboard-weight-range-month')));
      await tester.pumpAndSettle();
      final plot = tester.getRect(
        find.byKey(const Key('weight-bar-chart-plot')),
      );
      final monthBar = tester.getRect(
        find.byKey(const Key('weight-bar-chart-bar-0')),
      );
      // 期望值按**实测格宽**推导：clamp(格宽−2, 3, 8)。
      final expected = (plot.width / 31 - 2).clamp(3.0, 8.0);
      expect(
        monthBar.width,
        closeTo(expected, 0.51),
        reason:
            '月柱宽 = clamp(格宽−2, 3, 8)（实测格宽 ${(plot.width / 31).toStringAsFixed(2)}dp）',
      );
      expect(monthBar.width, lessThanOrEqualTo(8));
      expect(monthBar.width, lessThan(weekBar.width), reason: '月柱必须比周柱细');
    });

    testWidgets('分段控件文字中心与滑块中心对齐（2dp 偏差修复）', (tester) async {
      await tester.pumpWidget(
        host(
          const Center(
            child: LfSegmentedToggle(
              segments: ['周', '月'],
              selectedIndex: 0,
              onChanged: _ignoreIndex,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final thumb = tester.getRect(find.byKey(const Key('lf-segmented-thumb')));
      final weekText = tester.getRect(find.text('周'));
      expect(
        weekText.center.dx,
        closeTo(thumb.center.dx, 0.5),
        reason: '选中段文字必须与滑块中心对齐（旧实现偏左 2dp）',
      );
    });
  });
}

void _noop() {}

void _ignoreIndex(int _) {}
