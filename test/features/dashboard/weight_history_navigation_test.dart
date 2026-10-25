import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/lf_buttons.dart';
import 'package:localfit_ai/features/dashboard/presentation/sections/dashboard_weight_card.dart';
import 'package:localfit_ai/features/progress/domain/weight_measurement.dart';

/// 2026-10-22 用户三条新规格：
/// 1. 周视图横坐标 = 周一…周日，七天文字全部显示；
/// 2. 月视图点柱 → 顶部显示重量（既有浮窗）、底部显示**被点那一天**的日期，
///    其余日期标签先隐藏，被点日期颜色加深；
/// 3. 体重卡可切换不同周/不同月回看历史记录。
void main() {
  WeightMeasurement at(String date, double kg) => WeightMeasurement(
    id: date,
    profileId: 'p1',
    localDate: date,
    weightKg: kg,
    notes: null,
    source: 'manual',
    createdAt: DateTime.utc(2026, 10, 1),
    updatedAt: DateTime.utc(2026, 10, 1),
  );

  /// 10-22 是周四；本周 10-19(一)…10-25(日)。
  /// 另外给上一周（10-12…10-18）与上月（9 月）各一条，供导航断言用。
  WeightOverview overview() => WeightOverview(
    measurements: [
      at('2026-10-19', 70.2),
      at('2026-10-21', 69.8),
      at('2026-10-22', 69.4),
      at('2026-10-14', 71.0),
      at('2026-09-15', 72.5),
    ],
    latest: at('2026-10-22', 69.4),
    sevenDayAverageKg: 69.8,
    sampleDays: 3,
  );

  Future<void> pumpCard(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: DashboardWeightCard(
              overview: overview(),
              endLocalDate: '2026-10-22',
              onRecord: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('周视图横坐标是周一…周日，七天全部显示', (tester) async {
    await pumpCard(tester);
    const labels = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    for (final label in labels) {
      expect(
        find.text(label),
        findsOneWidget,
        reason: '周视图必须七格全标（用户 2026-10-22：文字全部显示）',
      );
    }
    // 具体日期不再挤在横轴：由周期行承担。
    expect(
      find.byKey(const Key('dashboard-weight-period-label')),
      findsOneWidget,
    );
    expect(find.textContaining('10/19'), findsOneWidget);
  });

  testWidgets('月视图点柱：只显示被点那天的日期，且颜色加深', (tester) async {
    await pumpCard(tester);
    await tester.tap(find.byKey(const Key('dashboard-weight-range-month')));
    await tester.pumpAndSettle();

    // 10-21 是周三：默认月视图只在周一（10/19、10/26）标日期。
    expect(find.text('10/21'), findsNothing);
    // 点 10-21 那根柱（10 月第 21 格，index 20）。
    await tester.tap(find.byKey(const Key('weight-bar-chart-slot-20')));
    await tester.pumpAndSettle();

    // 顶部浮窗：重量。
    expect(
      find.byKey(const Key('weight-bar-chart-tooltip-text')),
      findsOneWidget,
    );
    expect(find.text('69.8 kg'), findsOneWidget);
    // 底部：只显示被点日期，其余日期标签隐藏。
    expect(find.text('10/21'), findsOneWidget, reason: '被点那天的日期要显示');
    expect(find.text('10/19'), findsNothing, reason: '点柱后其他日期先隐藏');
    expect(find.text('10/26'), findsNothing, reason: '点柱后其他日期先隐藏');

    // 加深：被点标签用前景色，不是 muted。
    final label = tester.widget<Text>(find.text('10/21'));
    final c = AppTheme.light().extension<LfSemanticColors>()!;
    expect(label.style?.color, c.foreground);
    expect(label.style?.fontWeight, FontWeight.w600);
  });

  testWidgets('月视图再点一次同一根柱：浮窗收起、日期标签恢复', (tester) async {
    await pumpCard(tester);
    await tester.tap(find.byKey(const Key('dashboard-weight-range-month')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('weight-bar-chart-slot-20')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('weight-bar-chart-slot-20')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('weight-bar-chart-tooltip')), findsNothing);
    // 恢复默认稀疏标签（10-19 是周一）。
    expect(find.text('10/19'), findsOneWidget);
    expect(find.text('10/21'), findsNothing);
  });

  testWidgets('可以回看上一个月：周期行变化且图表用上月数据', (tester) async {
    await pumpCard(tester);
    await tester.tap(find.byKey(const Key('dashboard-weight-range-month')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Text>(find.byKey(const Key('dashboard-weight-period-label')))
          .data,
      contains('2026 年 10 月'),
    );

    await tester.tap(find.byKey(const Key('dashboard-weight-period-prev')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<Text>(find.byKey(const Key('dashboard-weight-period-label')))
          .data,
      contains('2026 年 9 月'),
    );
    // 9 月只有 15 日一条记录，且 9-15 不是周一 ⇒ 默认无日期标签，
    // 但柱必须存在（数据来自 9 月，不是拿 10 月冒充）。
    expect(
      find.byKey(const Key('weight-bar-chart-bar-14')),
      findsOneWidget,
      reason: '9/15 是 9 月第 15 格（index 14）',
    );
    // 回头再看：本月按钮重新可用。
    final next = tester.widget<LfIconButton>(
      find.byKey(const Key('dashboard-weight-period-next')),
    );
    expect(next.onPressed, isNotNull);
  });

  testWidgets('前进钮在「当前周期」禁用，回退一次后可用', (tester) async {
    await pumpCard(tester);
    var next = tester.widget<LfIconButton>(
      find.byKey(const Key('dashboard-weight-period-next')),
    );
    expect(next.onPressed, isNull, reason: '不许翻到未来');

    await tester.tap(find.byKey(const Key('dashboard-weight-period-prev')));
    await tester.pumpAndSettle();
    next = tester.widget<LfIconButton>(
      find.byKey(const Key('dashboard-weight-period-next')),
    );
    expect(next.onPressed, isNotNull);

    // 回到本周后再次禁用。
    await tester.tap(find.byKey(const Key('dashboard-weight-period-next')));
    await tester.pumpAndSettle();
    next = tester.widget<LfIconButton>(
      find.byKey(const Key('dashboard-weight-period-next')),
    );
    expect(next.onPressed, isNull);
  });

  testWidgets('周视图回退一周：周期行给日期范围，图上用上一周记录', (tester) async {
    await pumpCard(tester);
    final before = tester
        .widget<Text>(find.byKey(const Key('dashboard-weight-period-label')))
        .data!;
    expect(before, contains('本周'));

    await tester.tap(find.byKey(const Key('dashboard-weight-period-prev')));
    await tester.pumpAndSettle();
    final after = tester
        .widget<Text>(find.byKey(const Key('dashboard-weight-period-label')))
        .data!;
    expect(after, isNot(contains('本周')));
    expect(after, contains('10/12'), reason: '上一周从 10/12（周一）起');

    // 上一周只有 10-14（周三，index 2）一条记录。
    expect(
      find.byKey(const Key('weight-bar-chart-bar-2')),
      findsOneWidget,
      reason: '10-14 是上周第 3 格',
    );
    // 本周的记录不该出现在上周图里。
    expect(find.byKey(const Key('weight-bar-chart-bar-0')), findsNothing);
  });
}
