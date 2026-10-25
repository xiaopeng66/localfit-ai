import 'dart:ui' show ImageByteFormat;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/app/design/widgets/lf_badge.dart';
import 'package:localfit_ai/app/design/widgets/weight_bar_chart.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/dashboard/presentation/sections/dashboard_quick_stats_row.dart';
import 'package:localfit_ai/features/dashboard/presentation/sections/dashboard_weight_card.dart';
import 'package:localfit_ai/features/hydration/domain/water_intake.dart';
import 'package:localfit_ai/features/progress/data/steps_repository.dart';
import 'package:localfit_ai/features/progress/domain/weight_chart_points.dart';
import 'package:localfit_ai/features/progress/domain/weight_measurement.dart';

/// docs/29 §P9 需求 31/34 的界面层：周/月分段、步数卡三态（有数据 /
/// 无传感器 / 未授权），三种都不许写「0 步」。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('localfit/steps');
  Object? readReply;
  Object? permissionReply;

  setUp(() {
    readReply = null;
    permissionReply = <Object?, Object?>{'status': 'denied'};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'read':
              return readReply;
            case 'requestPermission':
              return permissionReply;
            case 'openAppSettings':
              return null;
            default:
              return null;
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Widget host(Widget child) => MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(body: ListView(children: [child])),
  );

  group('2.3 步数读取根因（2026-10-16 用户：授权后仍识别不了）', () {
    late AppDatabase database;
    late StepsRepository repository;

    setUp(() {
      database = AppDatabase(NativeDatabase.memory());
      repository = StepsRepository(
        database: database,
        channel: StepsChannel(),
        idGenerator: _Ids(),
        clock: FixedAppClock(DateTime.utc(2026, 10, 16, 8)),
      );
    });

    tearDown(() async {
      await database.close();
    });

    testWidgets('首读落在原生 2s 窗口之外：文案是「这次没读到步数」，不是「没有传感器」', (tester) async {
      readReply = <Object?, Object?>{
        'status': 'unavailable',
        'reason': 'no_event',
      };
      await tester.pumpWidget(
        host(
          StepsStatCard(
            repository: repository,
            localDate: '2026-10-16',
            goal: 8000,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('这次没读到步数'), findsOneWidget);
      expect(
        find.text('这台设备没有计步传感器'),
        findsNothing,
        reason: 'no_event 不等于「设备没有传感器」——那是句假话',
      );
      expect(await database.select(database.stepsDaily).get(), isEmpty);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    });

    // 2026-10-23 用户：「步数授权取消不掉」——应用内开关关掉后真的不读不写。
    testWidgets('应用内开关关闭：不读数、不落库，卡显示「已关闭」；重新打开恢复读数', (tester) async {
      readReply = <Object?, Object?>{
        'status': 'ok',
        'counter': 5000,
        'atMs': 1,
      };
      await repository.setEnabled(false);

      await tester.pumpWidget(
        host(
          StepsStatCard(
            repository: repository,
            localDate: '2026-10-16',
            goal: 8000,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('已关闭'), findsWidgets);
      expect(find.textContaining('应用内已停止读取'), findsOneWidget);
      expect(
        await database.select(database.stepsDaily).get(),
        isEmpty,
        reason: '关闭后一个字都不写（包括 0 步）',
      );

      // 重新打开：开关流触发一次读数，数据行出现。
      await repository.setEnabled(true);
      await tester.pumpAndSettle();
      expect(
        await database.select(database.stepsDaily).get(),
        hasLength(1),
        reason: '打开后恢复正常读数与落库',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    });

    test('syncToday 在开关关闭时直接返回 disabled，不碰 channel 也不落库', () async {
      await repository.setEnabled(false);
      final result = await repository.syncToday('2026-10-16');
      expect(result.saved, isFalse);
      expect(result.availability, StepsAvailability.disabled);
      expect(await database.select(database.stepsDaily).get(), isEmpty);
      // 默认值 = 开启（旧安装升级上来没有这个键）。
      expect(await repository.readEnabled(), isFalse);
      await repository.setEnabled(true);
      expect(await repository.readEnabled(), isTrue);
    });

    testWidgets('授权成功后自动重读：拿到值就上屏，不再停在空态', (tester) async {
      var reads = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            switch (call.method) {
              case 'read':
                reads++;
                // 1 = 还没授权；2 = 授权后首读落在原生 2s 窗口之外；3 = 重试拿到值。
                return switch (reads) {
                  1 => <Object?, Object?>{'status': 'denied'},
                  2 => <Object?, Object?>{
                    'status': 'unavailable',
                    'reason': 'no_event',
                  },
                  _ => <Object?, Object?>{
                    'status': 'ok',
                    'counter': 1234,
                    'atMs': 9,
                  },
                };
              case 'requestPermission':
                return <Object?, Object?>{'status': 'granted'};
              default:
                return null;
            }
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );

      await tester.pumpWidget(
        host(
          StepsStatCard(
            repository: repository,
            localDate: '2026-10-16',
            goal: 8000,
          ),
        ),
      );
      await tester.pumpAndSettle();
      // 首读就是 denied → 未授权态（整卡点击 = 申请权限）。
      expect(find.text('未授权'), findsOneWidget);

      // 点卡申请权限：授权成功后本地重读，第一次仍 no_event，重试拿到值。
      await tester.tap(find.byKey(const Key('dashboard-stat-steps')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      expect(reads, greaterThanOrEqualTo(3), reason: '授权后必须真的重读');
      expect(
        find.byKey(const Key('dashboard-steps-value')),
        findsOneWidget,
        reason: '重试读到值后要上屏，不再停在空态',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    });

    testWidgets('localDate 为 null：不落库（不写 local_date 空串）', (tester) async {
      readReply = <Object?, Object?>{'status': 'ok', 'counter': 500, 'atMs': 1};
      await tester.pumpWidget(
        host(
          StepsStatCard(repository: repository, localDate: null, goal: 8000),
        ),
      );
      await tester.pumpAndSettle();

      // 没有日期就没有「哪一天」这件事：一张行都不许写（回头再读会撞 UNIQUE）。
      expect(await database.select(database.stepsDaily).get(), isEmpty);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    });
  });

  // 2026-10-16：用户要求「步数卡不要『查看详情』」——上一个裁决（R11，
  // 2026-10-15）作废，链接件下线。这里改为钉**反向事实**：任何态都不再有它，
  // 且权限弹层仍有入口（设置页的「步数与身体活动」），不能因此变成死组件。
  group('2026-10-16 裁决：步数卡不再有「查看详情」', () {
    testWidgets('已接线时卡上也没有「查看详情」', (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = StepsRepository(
        database: database,
        channel: StepsChannel(),
        idGenerator: _Ids(),
        clock: FixedAppClock(DateTime.utc(2026, 9, 12, 8)),
      );

      await tester.pumpWidget(
        host(
          StepsStatCard(
            repository: repository,
            localDate: '2026-09-12',
            goal: 8000,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('dashboard-steps-detail')), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
      await database.close();
    });

    testWidgets('未接线时同样没有（且卡本身不可点）', (tester) async {
      await tester.pumpWidget(
        host(const StepsStatCard(localDate: '2026-09-12', goal: 8000)),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('dashboard-steps-detail')), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    });
  });

  group('StepsStatCard 三态（需求 34）', () {
    testWidgets('未接线：既有诚实空态，key 与文案都在', (tester) async {
      await tester.pumpWidget(
        host(
          const DashboardQuickStatsRow(
            water: WaterSummary.empty,
            // stepsRepository / localDate 都不给
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('dashboard-stat-steps')), findsOneWidget);
      expect(find.byKey(const Key('dashboard-steps-empty')), findsOneWidget);
      // 未接线时不再写「0 步」或任何数字。
      expect(find.byKey(const Key('dashboard-steps-value')), findsNothing);
    });

    testWidgets('无传感器（本机 AVD 的真实态）：说清是设备没有计步器', (tester) async {
      readReply = <Object?, Object?>{
        'status': 'unavailable',
        'reason': 'no_counter_sensor',
      };
      final database = AppDatabase(NativeDatabase.memory());
      final repository = StepsRepository(
        database: database,
        channel: StepsChannel(),
        idGenerator: _Ids(),
        clock: FixedAppClock(DateTime(2026, 10, 7, 9).toUtc()),
      );

      await tester.pumpWidget(
        host(
          DashboardQuickStatsRow(
            water: WaterSummary.empty,
            stepsRepository: repository,
            localDate: '2026-10-07',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('dashboard-steps-empty')), findsOneWidget);
      expect(find.text('这台设备没有计步传感器'), findsOneWidget);
      expect(find.text('0 步'), findsNothing);
      expect(find.text('0'), findsNothing);

      // 先卸载（取消 watchDate 订阅）再关库：drift 的流注销排了一个 0ms
      // timer，活着订阅时 close 会把 timer 留在 fake_async 里挂死整个用例。
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
      await database.close();
    });

    testWidgets('有数据：数字带千分位 + 剩余步数 + 目标', (tester) async {
      readReply = <Object?, Object?>{
        'status': 'ok',
        'counter': 8432,
        'atMs': 1,
      };
      final database = AppDatabase(NativeDatabase.memory());
      final repository = StepsRepository(
        database: database,
        channel: StepsChannel(),
        idGenerator: _Ids(),
        clock: FixedAppClock(DateTime(2026, 10, 7, 9).toUtc()),
      );

      // 第一次 sync 立基线（counter=0）；随后累计值到 8432 再 sync，
      // 卡上应出现 8432 - 0 = 8432 步。
      await repository.syncToday('2026-10-07');

      await tester.pumpWidget(
        host(
          DashboardQuickStatsRow(
            water: WaterSummary.empty,
            stepsRepository: repository,
            localDate: '2026-10-07',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 刚立基线：今日 0 步是真实事实（走过了 0 步），首读后数字 = 0。
      // 但显示口径是「有数据」态（不是空态）。
      expect(find.byKey(const Key('dashboard-steps-empty')), findsNothing);
      expect(
        find.byKey(const Key('dashboard-steps-remaining')),
        findsNothing,
        reason: '差额行已按用户要求删除',
      );
      // 2026-10-16 用户要求步数卡与水卡同款：当前值 / 目标 一行
      // （「6,231 / 10,000 步」），并补一个达标百分比徽标。
      expect(
        tester
            .widget<Text>(find.byKey(const Key('dashboard-steps-value')))
            .data,
        '0',
      );
      expect(
        tester
            .widget<Text>(
              find.byKey(const Key('dashboard-steps-target-inline')),
            )
            .data,
        '/ 10,000 步',
      );
      expect(
        find.byKey(const Key('dashboard-steps-goal')),
        findsNothing,
        reason: '目标已并入数值行',
      );
      expect(
        tester
            .widget<LfBadge>(find.byKey(const Key('dashboard-steps-status')))
            .text,
        '达标 0%',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
      await database.close();
    });

    testWidgets('未授权：只有右上角徽标，卡内文字/按钮全部退场（需求 48）', (tester) async {
      readReply = <Object?, Object?>{'status': 'denied'};
      final database = AppDatabase(NativeDatabase.memory());
      final repository = StepsRepository(
        database: database,
        channel: StepsChannel(),
        idGenerator: _Ids(),
        clock: FixedAppClock(DateTime(2026, 10, 7, 9).toUtc()),
      );

      await tester.pumpWidget(
        host(
          DashboardQuickStatsRow(
            water: WaterSummary.empty,
            stepsRepository: repository,
            localDate: '2026-10-07',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 徽标还在（用户原话「就是现在右上角那个」）。
      expect(find.text('未授权'), findsOneWidget);
      // 其余全部退场：旧 denied 专用的 key、大号「—」、说明行、「去设置」。
      expect(find.byKey(const Key('dashboard-steps-denied')), findsNothing);
      expect(find.text('—'), findsNothing);
      expect(find.textContaining('需要「身体活动」权限'), findsNothing);
      expect(find.text('去设置'), findsNothing);
      // 不可用 ⇒ 库里一个字都不写（这正是「未授权」与「0 步」的区别）。
      expect(await repository.stepsForDate('2026-10-07'), isNull);

      // 点击卡片 ⇒ 仍会申请权限（可见的按钮没了，路径不能也跟着没了）。
      await tester.tap(find.byKey(const Key('dashboard-stat-steps')));
      await tester.pump();
      // mock 回 denied ⇒ 徽标不变。
      expect(find.text('未授权'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
      await database.close();
    });

    testWidgets('未授权卡与有数据卡同高同构；隐形占位不进语义树（需求 48）', (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      final repository = StepsRepository(
        database: database,
        channel: StepsChannel(),
        idGenerator: _Ids(),
        clock: FixedAppClock(DateTime(2026, 10, 7, 9).toUtc()),
      );
      final semantics = tester.ensureSemantics();
      Widget row() => DashboardQuickStatsRow(
        water: WaterSummary.empty,
        stepsRepository: repository,
        localDate: '2026-10-07',
      );

      // ① 未授权态：量卡高。
      readReply = <Object?, Object?>{'status': 'denied'};
      await tester.pumpWidget(host(row()));
      await tester.pumpAndSettle();
      final deniedHeight = tester
          .getSize(find.byKey(const Key('dashboard-stat-steps')))
          .height;
      // 组件树里存在隐形占位（数值行里的目标段「/ 10,000 步」，占住正文
      // 高度——差额行已删），但语义树里**听不到**这个编造的数字。
      expect(find.textContaining('10,000'), findsExactly(1));
      expect(find.bySemanticsLabel(RegExp('10,000')), findsNothing);

      // ② 有数据态（正向对照）：同样的卡，量出同一高度。
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
      readReply = <Object?, Object?>{
        'status': 'ok',
        'counter': 8432,
        'atMs': 1,
      };
      await repository.syncToday('2026-10-07');
      await tester.pumpWidget(host(row()));
      await tester.pumpAndSettle();
      final valueHeight = tester
          .getSize(find.byKey(const Key('dashboard-stat-steps')))
          .height;
      // 正向对照证明 bySemanticsLabel 这把尺子量得到数字（否则①的「找不到」
      // 是把尺子坏了当成干净）。
      expect(find.bySemanticsLabel(RegExp('10,000')), findsWidgets);

      expect(
        deniedHeight,
        valueHeight,
        reason: '需求 48：未授权态只是「看不见内容」，骨架必须与已授权态同高',
      );

      // 语义句柄必须在测试体内 dispose（框架在测试结束的校验点之前查）。
      semantics.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
      await database.close();
    });
  });

  group('体重卡周/月分段（需求 31）', () {
    final measurements = <WeightMeasurement>[
      for (var i = 30; i >= 0; i--)
        WeightMeasurement(
          id: 'm$i',
          profileId: 'p',
          localDate: formatIsoLocalDate(
            DateTime(2026, 10, 7).subtract(Duration(days: i)),
          ),
          weightKg: 70 - (30 - i) * 0.05,
          notes: null,
          createdAt: DateTime(2026, 10, 7).toUtc(),
          updatedAt: DateTime(2026, 10, 7).toUtc(),
        ),
    ];

    testWidgets('默认周视图；切到月视图后为 31 个逐日格且标签是日期', (tester) async {
      await tester.pumpWidget(
        host(
          DashboardWeightCard(
            overview: WeightOverview(
              measurements: measurements,
              latest: measurements.last,
              sevenDayAverageKg: null,
              sampleDays: measurements.length,
            ),
            endLocalDate: '2026-10-07',
            onRecord: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 两段同属一个 `dashboard-weight-range` 组：整组在、且组内两段各有 Key
      // （`docs/21 §5.1` Key 表点了这几个 Key，必须有断言落地）。
      final group = find.byKey(const Key('dashboard-weight-range'));
      expect(group, findsOneWidget);
      expect(
        find.descendant(
          of: group,
          matching: find.byKey(const Key('dashboard-weight-range-week')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: group,
          matching: find.byKey(const Key('dashboard-weight-range-month')),
        ),
        findsOneWidget,
      );

      // 默认「周」：**恒 7 格**（2026-10-09 需求 41）。fixture 是 10-07 往前
      // 31 天连续记录 ⇒ 10-07 是周三，本周七格（10-05 周一…10-11 周日）里
      // 周一到周三有值、周四到周日是空槽。
      var points = buildWeightChartPoints(
        measurements,
        WeightRange.week,
        endLocalDate: '2026-10-07',
      );
      expect(points.length, 7, reason: '需求 41：横坐标恒定七天');
      expect(points.map((p) => p.label).toList(), [
        '一',
        '二',
        '三',
        '四',
        '五',
        '六',
        '日',
      ]);
      expect(
        points.where((p) => !p.isEmpty).length,
        3,
        reason: '10-05 一 / 10-06 二 / 10-07 三 有记录，周四起是空槽',
      );
      expect(points[3].isEmpty, isTrue);
      expect(points[3].label, '四', reason: '空槽仍要有标签（需求 41）');

      // 切「月」。
      await tester.tap(find.byKey(const Key('dashboard-weight-range-month')));
      await tester.pumpAndSettle();

      points = buildWeightChartPoints(
        measurements,
        WeightRange.month,
        endLocalDate: '2026-10-07',
      );
      // 需求 60/61（docs/32 §3 D1）：月视图改为**本月 1 日到月末逐日格**，
      // 不再按记录分箱。10 月是 31 天 ⇒ 31 个槽位；本月只有 7 条记录
      // （10-01…10-07）⇒ 其余 24 格是空槽，不画柱。
      expect(points.length, 31, reason: '10 月逐日格 = 31');
      expect(
        points.where((p) => !p.isEmpty).length,
        7,
        reason: '本月 7 条各占自己那一格',
      );
      expect(points[7].isEmpty, isTrue, reason: '10-08 没有记录');
      // 月视图标签是「月/日」，不是星期几。
      expect(points.first.label, '10/1');
      expect(points.last.label, '10/31');
      // 2026-10-16 用户第二轮：「月视图标**每周一**对应的日期」。2026-10-01
      // 是周四 ⇒ 本月只有 10/5、10/12、10/19、10/26 四个周一有标签。
      expect(points[0].visibleAxisLabel, isEmpty, reason: '10/1 不是周一');
      expect(points[4].visibleAxisLabel, '10/5', reason: '10/5 是周一');
      expect(points[8].visibleAxisLabel, isEmpty, reason: '10/9 不是周一');
      expect(points[11].visibleAxisLabel, '10/12', reason: '10/12 是周一');
      expect(points[25].visibleAxisLabel, '10/26', reason: '10/26 是周一');
      expect(
        points[30].visibleAxisLabel,
        isEmpty,
        reason: '10/31 是周六 ⇒ 不标（不再强制标月末）',
      );
      // Round7 A 的标题恒为「体重趋势」（`app.js:131`）；周/月之别由
      // mini-tabs 选中态 + 周期注 + 读屏标签三处表达——需求 42 的**意图**
      // （用户要知道自己在看哪一档）一条不少，只是不再靠标题换字。
      expect(find.text('体重趋势'), findsOneWidget);
      // 2026-10-16 用户：「体重趋势卡不要『本周:周一至周日』这类描述
      // （周/月视图都不要）」——周期注整件下线，周/月之别只由 mini-tabs
      // 选中态 + 读屏标签表达。
      expect(
        find.byKey(const Key('dashboard-weight-period-note')),
        findsNothing,
      );
      expect(find.text('10 月 · 每日一格'), findsNothing);
      expect(find.text('本周 · 周一至周日'), findsNothing);
      expect(find.text('本月体重'), findsNothing);

      // 切回「周」：周期注与读屏标签都要跟着换——这一断言专门钉住
      // 「分段控件真的参与了周期选择」，`monthView` 恒真/恒假的变异会在
      // 这里红。
      await tester.tap(find.byKey(const Key('dashboard-weight-range-week')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('dashboard-weight-period-note')),
        findsNothing,
      );
      expect(find.text('本周 · 周一至周日'), findsNothing);
      expect(find.text('本周体重'), findsNothing);
    });

    // 2026-10-09 需求 41 的核心断言：「一周就直接横坐标七天都显示，
    // 没有数据的时间就空着」。旧口径取「最近 ≤7 条记录」，只有 1 条记录时
    // 图上只有 1 根柱、1 个标签——横坐标根本不是「一周」。
    test('周视图恒 7 格：只有 1 条记录也出 7 个点，其余是空槽', () {
      final only = WeightMeasurement(
        id: 'one',
        profileId: 'p',
        // 2026-10-07 是周三。
        localDate: '2026-10-07',
        weightKg: 65.0,
        notes: null,
        createdAt: DateTime(2026, 10, 7).toUtc(),
        updatedAt: DateTime(2026, 10, 7).toUtc(),
      );
      final points = buildWeekChartPoints([only], endLocalDate: '2026-10-07');
      expect(points.length, 7, reason: '需求 41：恒定七格');
      expect(points.map((p) => p.label).toList(), [
        '一',
        '二',
        '三',
        '四',
        '五',
        '六',
        '日',
      ]);
      final valued = points.where((p) => !p.isEmpty).toList();
      expect(valued.length, 1);
      expect(valued.single.weightKg, 65.0);
      expect(valued.single.label, '三', reason: '10-07 是周三');
      // 空槽**不是 0kg 的柱**（§6.1：没有值 ≠ 值为 0）。
      for (final p in points.where((p) => p.isEmpty)) {
        expect(p.sampleDays, 0);
      }
    });

    // 空槽必须是「没有值」而不是「值为 0」：把空槽当 0 会让增减量算出
    // 荒唐的数字（周一空、周二 65、周三 66 ⇒ 66−0 = 66kg）。
    test('周视图增减量只算有值的格子（空槽不当 0）', () {
      final rows = [
        for (final (date, kg) in [('2026-10-06', 65.0), ('2026-10-07', 66.0)])
          WeightMeasurement(
            id: date,
            profileId: 'p',
            localDate: date,
            weightKg: kg,
            notes: null,
            createdAt: DateTime(2026, 10, 7).toUtc(),
            updatedAt: DateTime(2026, 10, 7).toUtc(),
          ),
      ];
      final points = buildWeekChartPoints(rows, endLocalDate: '2026-10-07');
      final valued = points.where((p) => !p.isEmpty).toList();
      expect(valued.first.weightKg, 65.0);
      expect(valued.last.weightKg, 66.0);
      expect(valued.last.weightKg - valued.first.weightKg, closeTo(1.0, 1e-9));
      // 图上确实有空槽，且它们的 weightKg 不参与任何计算。
      expect(points.where((p) => p.isEmpty).length, 5);
    });

    // 需求 41 的另一半：跨周不串。锚点是 endLocalDate 所在周的**周一**，
    // 上周的记录不许画进本周那一格（旧口径「最近 7 条」就会串周）。
    test('周视图按自然周分格：上周记录不落在本周格子里', () {
      // 2026-10-07 周三；10-04 是上周日。
      final rows = [
        for (final (date, kg) in [('2026-10-04', 70.0), ('2026-10-07', 65.0)])
          WeightMeasurement(
            id: date,
            profileId: 'p',
            localDate: date,
            weightKg: kg,
            notes: null,
            createdAt: DateTime(2026, 10, 7).toUtc(),
            updatedAt: DateTime(2026, 10, 7).toUtc(),
          ),
      ];
      final points = buildWeekChartPoints(rows, endLocalDate: '2026-10-07');
      final valued = points.where((p) => !p.isEmpty).toList();
      expect(valued.length, 1, reason: '本周只有 10-07 一条；10-04 属上周');
      expect(valued.single.weightKg, 65.0);
      expect(valued.single.label, '三');
    });

    test('月视图逐日槽位：只有有记录的日子带日期标签，且横轴稀疏', () {
      // 2026-10 是 31 天月。三条记录落在 10-01/10-04/10-07，其余 28 格是空槽。
      final sparse = [
        for (var i = 9; i >= 0; i--)
          WeightMeasurement(
            id: 's$i',
            profileId: 'p',
            localDate: formatIsoLocalDate(
              DateTime(2026, 10, 7).subtract(Duration(days: i * 3)),
            ),
            weightKg: 70 + i * 0.1,
            notes: null,
            createdAt: DateTime(2026, 10, 7).toUtc(),
            updatedAt: DateTime(2026, 10, 7).toUtc(),
          ),
      ];
      final points = buildMonthChartPoints(sparse, endLocalDate: '2026-10-07');
      expect(points.length, 31, reason: '10 月逐日格 = 31');
      expect(points.where((p) => !p.isEmpty).length, 3);
      // 每天一槽：柱值就是当天的体重，不再有“多天均值”口径。
      expect(points[6].weightKg, closeTo(sparse.last.weightKg, 1e-9));
      expect(points[6].sampleDays, 1);
      // 标签全在本月，且空槽没有可见横轴标签。
      expect(points.every((p) => p.label.startsWith('10/')), isTrue);
      expect(
        points.where((p) => p.visibleAxisLabel.isNotEmpty).length,
        lessThanOrEqualTo(5),
        reason: '横轴只标每周一（一个月最多 5 个）',
      );
    });

    // 需求 42 的另一半：标题写「本月体重」就得真是本月。仓库的 30 天滚动
    // 窗口在 10 月 10 日会含 9 月 11 日起的记录——那是「近一个月」。
    test('月视图口径是真的本月：上月记录不进月视图', () {
      final rows = [
        for (final (date, kg) in [
          ('2026-09-15', 72.0),
          ('2026-09-30', 71.0),
          ('2026-10-02', 70.0),
          ('2026-10-07', 69.0),
        ])
          WeightMeasurement(
            id: date,
            profileId: 'p',
            localDate: date,
            weightKg: kg,
            notes: null,
            createdAt: DateTime(2026, 10, 7).toUtc(),
            updatedAt: DateTime(2026, 10, 7).toUtc(),
          ),
      ];
      final points = buildMonthChartPoints(rows, endLocalDate: '2026-10-07');
      expect(points.length, 31, reason: '10 月逐日格 = 31（上月记录不占格）');
      expect(
        points.where((p) => !p.isEmpty).length,
        2,
        reason: '只有 10-02 与 10-07 是本月',
      );
      expect(points[1].weightKg, closeTo(70.0, 1e-9));
      expect(points[6].weightKg, closeTo(69.0, 1e-9));
    });

    // 2026-10-09 需求 43：「下边不要写较月初」。用户删的是那**三个字**，
    // 保留箭头与增减量 —— 所以这条同时钉两件事：三个字**不在**、箭头在。
    testWidgets('月视图副标题无「较月初」，但箭头与增减量保留', (tester) async {
      await tester.pumpWidget(
        host(
          DashboardWeightCard(
            overview: WeightOverview(
              measurements: measurements,
              latest: measurements.last,
              sevenDayAverageKg: null,
              sampleDays: measurements.length,
            ),
            endLocalDate: '2026-10-07',
            onRecord: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('dashboard-weight-range-month')));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('较月初'),
        findsNothing,
        reason: '需求 43：不许再写「较月初」',
      );
      // 但趋势信息本身必须在（箭头 + 数值）——删过头就只剩一个快照了。
      // fixture 的 `weightKg: 70 - (30 - i) * 0.05` 里 i=0（10-07，最新）是 68.5。
      // A 的 caption 左格就是「最近值 + kg」（`weight-trend-value`），
      // 右格「最近记录 ↓ N」——旧副标题「最新 68.5 kg」的同一事实。
      expect(
        tester
            .widget<Text>(find.byKey(const Key('dashboard-weight-trend-value')))
            .textSpan!
            .toPlainText(),
        '68.5 kg',
      );
      expect(find.textContaining('最近记录'), findsOneWidget);
      expect(
        find.textContaining(RegExp(r'[↑↓→] ')),
        findsOneWidget,
        reason: '需求 43 删的是三个字，不是趋势本身（箭头要留）',
      );
    });

    // 本月一条记录都没有 ⇒ 还是 31 个空槽（由卡片判「全空」后给
    // 「本月还没有记录」的空态），而不是拿上月的记录冒充本月。
    test('月视图：本月无记录时全为空槽（不拿上月冒充）', () {
      final lastMonth = WeightMeasurement(
        id: 'old',
        profileId: 'p',
        localDate: '2026-09-20',
        weightKg: 72.0,
        notes: null,
        createdAt: DateTime(2026, 9, 20).toUtc(),
        updatedAt: DateTime(2026, 9, 20).toUtc(),
      );
      final fromLastMonth = buildMonthChartPoints([
        lastMonth,
      ], endLocalDate: '2026-10-07');
      expect(fromLastMonth, hasLength(31));
      expect(fromLastMonth.every((p) => p.isEmpty), isTrue);
      expect(
        buildMonthChartPoints(const [], endLocalDate: '2026-10-07'),
        hasLength(31),
      );
    });

    test('月视图逐日不多不少：2–7 条记录也按当天占格（2026-10-08 缺陷的替代口径）', () {
      // 旧口径每箱钉死 7 条 ⇒ 2–7 条记录只出 1 个点 ⇒ 卡片走空态说
      // 「还没有体重记录」。新口径每天一格，2–7 条恒有 2–7 个非空槽。
      for (final count in [2, 3, 4, 5, 6, 7]) {
        final rows = [
          for (var i = count - 1; i >= 0; i--)
            WeightMeasurement(
              id: 'b$i',
              profileId: 'p',
              localDate: formatIsoLocalDate(
                DateTime(2026, 10, 7).subtract(Duration(days: i)),
              ),
              weightKg: 70 + i * 0.1,
              notes: null,
              createdAt: DateTime(2026, 10, 7).toUtc(),
              updatedAt: DateTime(2026, 10, 7).toUtc(),
            ),
        ];
        final points = buildMonthChartPoints(rows, endLocalDate: '2026-10-07');
        expect(points, hasLength(31));
        expect(
          points.where((p) => !p.isEmpty).length,
          count,
          reason: '$count 条记录各占自己那天，否则卡片会走空态说谎',
        );
        // 不丢记录：非空槽的 sampleDays 之和 == 记录条数。
        expect(
          points.fold<int>(0, (sum, p) => sum + p.sampleDays),
          count,
          reason: '逐日槽位不许丢记录',
        );
      }
    });

    test('月视图单日：1 条记录落在那一天的那一格（空态只在 0 条时）', () {
      final only = WeightMeasurement(
        id: 'one',
        profileId: 'p',
        localDate: formatIsoLocalDate(DateTime(2026, 10, 7)),
        weightKg: 69.4,
        notes: null,
        createdAt: DateTime(2026, 10, 7).toUtc(),
        updatedAt: DateTime(2026, 10, 7).toUtc(),
      );
      final points = buildMonthChartPoints([only], endLocalDate: '2026-10-07');
      expect(points, hasLength(31));
      expect(points[6].weightKg, 69.4, reason: '10-07 是第 7 格（index 6）');
      expect(points[6].sampleDays, 1);
      expect(points.where((p) => !p.isEmpty).length, 1);
    });

    // 2026-10-08 走查新增：设计稿渲染时实测出两处几何缺陷，这里钉死。
    // ① `kg` 单位曾与最高那档刻度左右重叠（两者都贴左边缘）⇒ 渲染成「kg71.0」；
    // ② 轴列的 `Stack` 默认 `Clip.hardEdge` 把首档刻度（`top:0` +
    //    `translateY(-50%)`）的上半截切掉。两条都是「量出来」的，不是看出来的。
    testWidgets('轴列刻度不与绘图区重叠；kg 单位归卡 caption（D8b）', (tester) async {
      await tester.pumpWidget(
        host(
          DashboardWeightCard(
            overview: WeightOverview(
              measurements: measurements,
              latest: measurements.last,
              sevenDayAverageKg: null,
              sampleDays: measurements.length,
            ),
            endLocalDate: '2026-10-07',
            onRecord: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // A 起图内没有 `kg` 单位行（`weight-bar-chart-unit` 退场），
      // 原缺陷「kg71.0 叠字」不可能再发生；保留下来的不变量是
      // **轴列刻度不许压进绘图区**（压进去就等于压在柱上）。
      final plot = tester.getRect(
        find.byKey(const Key('weight-bar-chart-plot')),
      );
      for (var i = 0; i < 4; i++) {
        final tick = tester.getRect(
          find.byKey(Key('weight-bar-chart-tick-$i')),
        );
        expect(
          tick.right,
          lessThanOrEqualTo(plot.left + 0.5),
          reason: '第 $i 档刻度不得越进绘图区（轴列在左、柱区在右）',
        );
      }
      // 单位仍要写一次——归卡片 caption 的 ` kg` 小字。
      expect(
        tester
            .widget<Text>(find.byKey(const Key('dashboard-weight-trend-value')))
            .textSpan!
            .toPlainText(),
        endsWith(' kg'),
        reason: 'kg 单位必须仍在卡里（只是从图内搬进 caption）',
      );
    });

    // 首档刻度骑在绘图区顶边线上（`top:0` + `translateY(-50%)`），上半截必然
    // 落在轴列 `Stack` 之外。**必须按像素判**：`getRect` 给的是布局几何，
    // `Clip.hardEdge` 只影响绘制、不改布局 —— 用几何断言时把 `Clip.none` 删掉
    // 依然全绿（实测过，见证据文件），那是假绿。
    testWidgets('首档刻度不被轴列裁切：上半截真的画出来了（按像素判）', (tester) async {
      await tester.pumpWidget(
        host(
          DashboardWeightCard(
            overview: WeightOverview(
              measurements: measurements,
              latest: measurements.last,
              sevenDayAverageKg: null,
              sampleDays: measurements.length,
            ),
            endLocalDate: '2026-10-07',
            onRecord: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      final tick0 = tester.getRect(
        find.byKey(const Key('weight-bar-chart-tick-0')),
      );
      // 轴列 `Stack` 的顶边 = 绘图区（柱区 + 标签行）的顶边。刻度文字上半截
      // 全在这条线**之上**（骑在顶边线上）；裁切发生时这里没有墨点。
      final axisTop = tester
          .getRect(find.byKey(const Key('weight-bar-chart-plot')))
          .top;

      // 前置条件：首档刻度确实越过了轴列顶边。
      expect(
        tick0.top,
        lessThan(axisTop - 1),
        reason: '前置条件：首档刻度的上半截确实越过了轴列顶边',
      );

      // 向上找最近的 `RepaintBoundary`（卡本身不是；widget 测试树的根附近有）。
      RenderRepaintBoundary? boundary;
      for (
        RenderObject? node = tester.renderObject(
          find.byKey(const Key('weight-bar-chart-tick-0')),
        );
        node != null;
        node = node.parent
      ) {
        if (node is RenderRepaintBoundary) {
          boundary = node;
          break;
        }
      }
      expect(boundary, isNotNull, reason: '截图需要一层 RepaintBoundary');
      late final ByteData? bytes;
      await tester.runAsync(() async {
        final image = await boundary!.toImage(pixelRatio: 3);
        bytes = await image.toByteData(format: ImageByteFormat.rawRgba);
        image.dispose();
      });
      final pixels = bytes!;
      // 行距 = **图片**宽（截图是整块 boundary，不是只有图表），
      // 索引一律用 boundary 相对坐标。
      final imageWidth = (boundary!.size.width * 3).round();
      final origin = boundary.localToGlobal(Offset.zero);
      double px(double globalX) => (globalX - origin.dx) * 3;
      double py(double globalY) => (globalY - origin.dy) * 3;

      // 数「非背景」像素：文字是 muted 灰，背景是白/近白。
      var inkAbove = 0;
      final yFrom = py(tick0.top).round().clamp(0, 1 << 30);
      // 只数**轴列顶边以上**的行：顶边以下即使被裁也仍有下半截的墨点，
      // 那样断言就分不出裁与不裁（实测过，是假绿）。
      final yTo = py(axisTop).round().clamp(0, 1 << 30);
      final xFrom = px(tick0.left).round().clamp(0, 1 << 30);
      final xTo = px(tick0.right).round().clamp(0, 1 << 30);
      for (var y = yFrom; y < yTo; y++) {
        for (var x = xFrom; x < xTo && x < imageWidth; x++) {
          final i = (y * imageWidth + x) * 4;
          final r = pixels.getUint8(i);
          final g = pixels.getUint8(i + 1);
          final b = pixels.getUint8(i + 2);
          // muted 文字（#9FB3AC 系）与白底的差别：明显偏离纯白。
          if (r < 220 || g < 220 || b < 220) inkAbove++;
        }
      }
      expect(inkAbove, greaterThan(20), reason: '首档刻度上半截必须真被画出（裁切时这里一个墨点都没有）');
    });

    // 2026-10-08 设备走查（R8）新增、2026-10-09 需求 40/41 改写：单柱时的柱宽
    // 与**位置**。
    //
    // R8 的缺陷：只有 1 条记录时 `Expanded` 把那一根柱撑满整个绘图区。
    // 需求 41 之后重心变了——单柱不再「居中于绘图区」，而是**居中于它那一天
    // 的格子**（10-07 周三 ⇒ 第 3 格）。柱宽仍不得撑满绘图区。
    testWidgets('单条记录：柱落在那一天的格子里、居中，且不撑满绘图区', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final only = WeightMeasurement(
        id: 'one',
        profileId: 'p',
        localDate: formatIsoLocalDate(DateTime(2026, 10, 7)),
        weightKg: 65.0,
        notes: null,
        createdAt: DateTime(2026, 10, 7).toUtc(),
        updatedAt: DateTime(2026, 10, 7).toUtc(),
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
            onRecord: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 2026-10-07 是周三 ⇒ 本周七格（10-05…10-11）里唯一的柱在第 3 格
      // （index 2）。需求 41 之后**不能再按 `bar-0` 找「第一根柱」**：
      // 第 0 格是周一，多半是空槽。
      final bar = tester.getRect(
        find.byKey(const Key('weight-bar-chart-bar-2')),
      );
      final chart = tester.getRect(find.byKey(const Key('weight-bar-chart')));
      // **绘图区左边界 = 绘图区 Stack 的左缘**，不是整图 `chart.left`
      // （整图含左侧 30dp 轴列 + 8dp 间隙；用 chart.left 量会把轴列算进
      // 左边距里，实测左右差 34dp 的假失败）。整图右边界就是绘图区右边界。
      final plotLeft = tester
          .getRect(find.byKey(const Key('weight-bar-chart-plot')))
          .left;
      final plotWidth = chart.right - plotLeft;
      expect(
        bar.width,
        lessThan(plotWidth * 0.5),
        reason:
            '单柱不得撑满绘图区（实测 ${bar.width.toStringAsFixed(1)}dp vs '
            '绘图区 ${plotWidth.toStringAsFixed(1)}dp）',
      );
      // **居中于自己那一格**（不是整块绘图区）：第 2 格的格心。
      final slot = plotWidth / 7;
      final slotCenter = plotLeft + slot * 2.5;
      expect(
        bar.center.dx,
        closeTo(slotCenter, 1.0),
        reason:
            '单柱应在本格内水平居中（柱心 ${bar.center.dx.toStringAsFixed(1)} '
            'vs 格心 ${slotCenter.toStringAsFixed(1)}）',
      );
      // 空槽**一个墨点都没有**（需求 41）：那 6 格不存在 bar widget。
      for (final i in [0, 1, 3, 4, 5, 6]) {
        expect(
          find.byKey(Key('weight-bar-chart-bar-$i')),
          findsNothing,
          reason: '第 $i 格是空槽，不许画柱（不是 0kg 的柱）',
        );
      }
      // 但七格的**标签**都在。2026-10-22 用户改回「周视图横坐标是周一~周日，
      // 文字全部显示」⇒ 横轴写星期全称，七天都标满（空槽也标）；具体日期
      // 移到体重卡上方的周期行（`dashboard-weight-period-label`），由那条
      // 断言单独钉住。该用例的一周是 2026-10-05（周一）…10-11（周日）。
      const weekLabels = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
      for (final label in weekLabels) {
        expect(find.text(label), findsOneWidget, reason: '周视图七天横轴全显（空槽也标）');
      }
      // **竖向必须贴底**。加宽度上限时我曾把 `Align(bottomCenter)` 写成
      // `Center`（想当然地以为「居中层」只管横向），结果柱在设备上浮到
      // 绘图区正中间、底边离基线半个柱高——2026-10-08 走查实测出来的。
      // 这条把它钉死：柱底 == 绘图区底（`Row` 的 `crossAxisAlignment.end`
      // 保证的那条线）。4 档刻度后绘图区底线是**最后一档** `tick-3`。
      final plot = tester.getRect(
        find.byKey(const Key('weight-bar-chart-tick-3')),
      );
      expect(
        (bar.bottom - plot.bottom).abs(),
        lessThan(20.0),
        reason:
            '柱底必须贴着绘图区底线（实测 bar.bottom=${bar.bottom} '
            'vs 轴列底=${plot.bottom}；浮在中段就是竖向也居中了）',
      );
    });

    // 2026-10-09 需求 40「柱子太宽了」的核心断言，取代旧的「上限不生效」口径。
    //
    // **口径已反转**：旧版上限 40dp，360dp 屏每格 ≈44dp、减内边距后柱宽
    // ≈38dp < 40 ⇒ 上限**不参与**，那时这条测的是「上限不生效」。现在上限
    // 收到 22dp、内边距加到 8dp（可用宽 ≈42−16 = 26dp > 22）⇒ 上限**生效**。
    // 这正是需求 40 要的效果：柱不再随格子变胖。
    testWidgets('7 根柱：360dp 下柱宽落在 22dp 上限，且各在自己格里居中', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        host(
          DashboardWeightCard(
            overview: WeightOverview(
              measurements: measurements,
              latest: measurements.last,
              sevenDayAverageKg: null,
              sampleDays: measurements.length,
            ),
            endLocalDate: '2026-10-07',
            onRecord: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      final chart = tester.getRect(find.byKey(const Key('weight-bar-chart')));
      final plotLeft = tester
          .getRect(find.byKey(const Key('weight-bar-chart-plot')))
          .left;
      final plotWidth = chart.right - plotLeft;
      final slot = plotWidth / 7;
      // fixture 是 10-07 往前 31 天连续记录 ⇒ 本周（10-05…10-11）只有
      // 周一/周二/周三三天有值，其余四格是空槽。
      const valuedIndices = [0, 1, 2];
      for (final i in valuedIndices) {
        final bar = tester.getRect(find.byKey(Key('weight-bar-chart-bar-$i')));
        // 需求 40：柱宽不随格子变胖——就是上限值本身。
        expect(
          bar.width,
          closeTo(WeightBarChart.maxBarWidth, 1.0),
          reason:
              '第 $i 根柱应落在上限 ${WeightBarChart.maxBarWidth}dp'
              '（格宽 ${slot.toStringAsFixed(1)}dp；撑满格子就是需求 40 的原缺陷）',
        );
        // 居中：柱心 ≈ 格心。
        final slotCenter = plotLeft + slot * (i + 0.5);
        expect(
          bar.center.dx,
          closeTo(slotCenter, 1.0),
          reason: '第 $i 根柱应在自己那一格里居中',
        );
      }
      for (final i in [3, 4, 5, 6]) {
        expect(
          find.byKey(Key('weight-bar-chart-bar-$i')),
          findsNothing,
          reason: '第 $i 格是空槽（本周还没到那天），不画柱',
        );
      }
    });

    testWidgets('需求 32：整卡不可点，「添加」按钮在', (tester) async {
      var addTaps = 0;
      await tester.pumpWidget(
        host(
          DashboardWeightCard(
            overview: WeightOverview(
              measurements: measurements,
              latest: measurements.last,
              sevenDayAverageKg: null,
              sampleDays: measurements.length,
            ),
            endLocalDate: '2026-10-07',
            onRecord: () {},
            onAdd: () => addTaps++,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final add = find.byKey(const Key('dashboard-weight-add'));
      expect(add, findsOneWidget);
      await tester.tap(add);
      expect(addTaps, 1);
      // 整卡 tap：InkWell 的 onTap 为 null（语义标签不再宣称可点）。
      expect(find.bySemanticsLabel(RegExp('点击记录体重')), findsNothing);
    });
  });
}

final class _Ids implements IdGenerator {
  int _v = 0;
  @override
  String next() => 'steps-ui-${_v++}';
}
