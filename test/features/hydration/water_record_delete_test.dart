import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/app/design/number_format.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/dashboard/presentation/dashboard_page.dart';
import 'package:localfit_ai/features/hydration/data/water_repository.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/progress/data/measurement_repository.dart';

/// A-1（docs/64）：饮水记录**可看可删可撤销**。
///
/// 现状是「只能加」：仓储早有 `delete`/`restore`（water_repository.dart:82/96），
/// 但 presentation 下没有任何调用点 ⇒ 记错了只能靠 AI 聊天里的 `water.delete`。
///
/// 形态（阶段 1 统一）：长按饮水卡 → 弹层列出当天每条 → 删除（就地确认）→
/// 弹层关闭 → 页面 SnackBar「撤销」→ 走 `restore` 回写同一条（不是重新 add）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 10, 26, 9);
  const localDate = '2026-10-26';
  late AppDatabase database;
  late MealRepository mealRepository;
  late MeasurementRepository measurementRepository;
  late WaterRepository waterRepository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    final clock = FixedAppClock(now.toUtc());
    mealRepository = MealRepository(
      database: database,
      idGenerator: const UuidV7Generator(),
      clock: clock,
    );
    measurementRepository = MeasurementRepository(
      database: database,
      idGenerator: const UuidV7Generator(),
      clock: clock,
    );
    waterRepository = WaterRepository(
      database: database,
      idGenerator: const UuidV7Generator(),
      clock: clock,
    );
  });

  tearDown(() => database.close());

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        // 生产里今日页挂在 shell 的 Scaffold 下；测试也套一层，否则
        // ScaffoldMessenger 没有可挂的 Scaffold（SnackBar 断言会抛）。
        home: Scaffold(
          body: DashboardPage(
            mealRepository: mealRepository,
            measurementRepository: measurementRepository,
            waterRepository: waterRepository,
            onOpenAiWorkbench: () {},
            onOpenRecord: () {},
            onLogMeal: (_) {},
            now: now,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 挂载型用例的统一收尾（drift 查询流取消时会排一个 0ms 定时器）。
  void dashboardTest(
    String description,
    Future<void> Function(WidgetTester) body,
  ) {
    testWidgets(description, (tester) async {
      await body(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    });
  }

  String cardValue(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const Key('dashboard-water-value'))).data!;

  dashboardTest('长按饮水卡 → 列出今天的记录 → 删一条 → 卡上合计减少 + 弹「撤销」', (tester) async {
    await waterRepository.add(localDate: localDate, amountMl: 250);
    await waterRepository.add(localDate: localDate, amountMl: 300);
    await pump(tester);
    expect(cardValue(tester), withThousandsSeparator(550));

    await tester.longPress(find.byKey(const Key('dashboard-stat-water')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('water-record-sheet')), findsOneWidget);
    expect(find.byKey(const Key('water-record-0')), findsOneWidget);
    expect(find.byKey(const Key('water-record-1')), findsOneWidget);

    await tester.tap(find.byKey(const Key('water-record-delete-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('water-record-confirm')));
    await tester.pumpAndSettle();

    final remaining = await waterRepository.watchDay(localDate).first;
    expect(remaining.records, hasLength(1));
    expect(remaining.consumedMl, 300, reason: '删的是 250 那条，剩下的合计必须是 300');
    expect(
      cardValue(tester),
      withThousandsSeparator(300),
      reason: '卡上合计由流自动刷新',
    );
    expect(find.textContaining('撤销'), findsOneWidget);
  });

  dashboardTest('撤销 → 记录回来（走 restore，id 不变、不是重新 add）', (tester) async {
    await waterRepository.add(localDate: localDate, amountMl: 250);
    await waterRepository.add(localDate: localDate, amountMl: 300);
    final before = await waterRepository.watchDay(localDate).first;
    final deletedId = before.records.first.id;
    await pump(tester);

    await tester.longPress(find.byKey(const Key('dashboard-stat-water')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('water-record-delete-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('water-record-confirm')));
    await tester.pumpAndSettle();
    expect(
      (await waterRepository.watchDay(localDate).first).records,
      hasLength(1),
    );

    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();

    final restored = await waterRepository.watchDay(localDate).first;
    expect(restored.records, hasLength(2));
    expect(restored.consumedMl, 550);
    expect(
      restored.records.map((record) => record.id),
      contains(deletedId),
      reason: '撤销必须走 restore 回写原 id；接成 add 会生成新 id（变异点）',
    );
    expect(cardValue(tester), withThousandsSeparator(550));
  });

  dashboardTest('空记录：长按不弹空列表，给「还没有饮水记录」', (tester) async {
    await pump(tester);
    await tester.longPress(find.byKey(const Key('dashboard-stat-water')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('water-record-sheet')), findsNothing);
    expect(find.textContaining('还没有饮水记录'), findsOneWidget);
  });
}
