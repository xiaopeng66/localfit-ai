import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/app/design/widgets/lf_progress_bar.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/dashboard/presentation/sections/dashboard_quick_stats_row.dart';
import 'package:localfit_ai/features/hydration/domain/water_intake.dart';
import 'package:localfit_ai/features/progress/data/steps_repository.dart';

/// 步数卡读「设置里的步数目标」（docs/32 §4 T9 / §3 D11 需求 64）。
///
/// 契约（逐条对应下面的断言）：
/// - 有数据态的数字、剩余步数、进度条都按设置里的目标算（不再恒 10,000）；
/// - **未授权态的隐形占位也用同一个目标值**（骨架与已授权态同高同构，
///   占位数字不进语义树）；
/// - 设置改了（`AppSettings` 落键）不重建页面也跟着变（订阅目标流）；
/// - 注入 `stepGoal` 时以注入值为准；未接线（无仓储）仍是既有诚实空态。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('localfit/steps');
  Object? readReply;

  setUp(() {
    readReply = <Object?, Object?>{'status': 'ok', 'counter': 8432, 'atMs': 1};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'read':
              return readReply;
            case 'requestPermission':
              return <Object?, Object?>{'status': 'denied'};
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

  Future<StepsRepository> makeRepository() async {
    // 步数按天落库由卡片自己发起（不在本文件断言），这里只保证库能打开。
    final database = AppDatabase(NativeDatabase.memory());
    return StepsRepository(
      database: database,
      channel: StepsChannel(),
      idGenerator: const UuidV7Generator(),
      clock: FixedAppClock(DateTime(2026, 10, 13, 9).toUtc()),
    );
  }

  /// 收尾：**先卸掉订阅再走一帧，最后才 close**（与
  /// `dashboard_steps_and_weight_test.dart` 同一约定）。次序反了会在
  /// 「树 dispose → drift 关流」链上留下一个零时长 timer，用例结束时的
  /// `!timersPending` 断言直接失败，并挂到 10 分钟超时。
  Future<void> drain(WidgetTester tester, StepsRepository repository) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await repository.database.close();
  }

  /// 把「今天已走 8,432 步」种成既有事实。
  ///
  /// 不能只 `syncToday` 一次：那天还没有基线时，首次同步是**以当前累计值
  /// 立基线、今日 0 步**（`resolveTodaySteps`），卡上就是「0 / 目标 步」。
  /// 所以先用累计值 0 立基线，再把读数抬到 8,432 —— 卡片挂载时自己那次
  /// 同步（`initState` → `_sync`）算出的差值正好 8,432，并 upsert 进当天行。
  Future<void> primeToday(StepsRepository repository) async {
    readReply = <Object?, Object?>{'status': 'ok', 'counter': 0, 'atMs': 1};
    await repository.syncToday('2026-10-13');
    readReply = <Object?, Object?>{'status': 'ok', 'counter': 8432, 'atMs': 2};
  }

  testWidgets('设置里的目标（12000）驱动数字 / 剩余步数 / 进度条', (tester) async {
    final repository = await makeRepository();
    await repository.updateDailyGoal(12000);
    await primeToday(repository);

    await tester.pumpWidget(
      host(
        DashboardQuickStatsRow(
          water: WaterSummary.empty,
          stepsRepository: repository,
          localDate: '2026-10-13',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('12,000'), findsWidgets);
    // 2026-10-16 用户：「步数卡片删除『还差 n 步』」——差额行整件下线，
    // 达成度由「达标 N%」徽标表达。
    expect(find.text('还差 3,568 步'), findsNothing);

    final bar = tester.widget<LfProgressBar>(
      find.descendant(
        of: find.byKey(const Key('dashboard-stat-steps')),
        matching: find.byType(LfProgressBar),
      ),
    );
    expect(
      bar.value,
      closeTo(8432 / 12000, 0.001),
      reason: '进度条按同一个目标算（不是按 10,000）',
    );

    await drain(tester, repository);
  });

  testWidgets('设置页改目标 ⇒ 卡片不重建也跟着变（订阅目标流）', (tester) async {
    final repository = await makeRepository();
    await primeToday(repository);

    await tester.pumpWidget(
      host(
        DashboardQuickStatsRow(
          water: WaterSummary.empty,
          stepsRepository: repository,
          localDate: '2026-10-13',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('10,000'), findsWidgets);

    await repository.updateDailyGoal(15000);
    await tester.pumpAndSettle();

    expect(find.textContaining('15,000'), findsWidgets);
    expect(find.text('还差 6,568 步'), findsNothing);

    await drain(tester, repository);
  });

  testWidgets('未授权：隐形占位也按设置里的目标（同高同构 + 不进语义树）', (tester) async {
    final repository = await makeRepository();
    await repository.updateDailyGoal(12000);
    readReply = <Object?, Object?>{'status': 'denied'};
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      host(
        DashboardQuickStatsRow(
          water: WaterSummary.empty,
          stepsRepository: repository,
          localDate: '2026-10-13',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('未授权'), findsOneWidget);
    // 隐形占位只有数值行里的目标段（「0」+「/ 12,000 步」——差额行已下线）。
    // `skipOffstage: false`：占位是 `Visibility(visible: false)` 藏起来但
    // 仍然布局的（同高同构就靠它），默认查找会跳过这棵子树。
    expect(find.textContaining('12,000', skipOffstage: false), findsExactly(1));
    expect(find.bySemanticsLabel(RegExp('12,000')), findsNothing);

    semantics.dispose();
    await drain(tester, repository);
  });

  testWidgets('注入 stepGoal：以注入值为准（无仓储也能画）', (tester) async {
    final repository = await makeRepository();
    await primeToday(repository);

    await tester.pumpWidget(
      host(
        DashboardQuickStatsRow(
          water: WaterSummary.empty,
          stepsRepository: repository,
          localDate: '2026-10-13',
          stepGoal: 20000,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('20,000'), findsWidgets);
    expect(find.textContaining('10,000'), findsNothing);

    await drain(tester, repository);
  });

  testWidgets('未接线（无仓储）：既有诚实空态不变，不画任何目标数字', (tester) async {
    await tester.pumpWidget(
      host(const DashboardQuickStatsRow(water: WaterSummary.empty)),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('dashboard-steps-empty')), findsOneWidget);
    expect(find.textContaining('10,000'), findsNothing);
    expect(find.textContaining('12,000'), findsNothing);
  });
}
