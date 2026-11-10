import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/dashboard/presentation/dashboard_page.dart';
import 'package:localfit_ai/features/hydration/data/water_repository.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/progress/data/measurement_repository.dart';

/// A-2（docs/64）：体重**可删一条**（现在只能同日覆盖）。
///
/// 现状证据：`MeasurementRepository` 只有 `saveManualWeight`（按 localDate
/// upsert），全文件 `grep -n "delete"` = 0；体重卡只有「添加」，卡面不可点
/// （需求 32 明确去掉过整卡可点）。
///
/// 形态与 A-1 一致：卡头 ⋮（`weight-records-menu`）→ 弹层列表 → 删除（确认）
/// → 弹层关闭 → SnackBar「撤销」（走 `restore`）。
///
/// 测试手法（docs/64 附录 E）：本页有体重柱图 + 弹层 + 6 秒撤销条，
/// `pumpAndSettle` 在「先 await 真实异步再开弹层」的时序下会挂住，
/// 因此统一用**有界 pump**（[settle]），真实异步断言走 `tester.runAsync`。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 10, 26, 9);
  const localDate = '2026-10-26';
  late AppDatabase database;
  late MealRepository mealRepository;
  late MeasurementRepository measurementRepository;
  late WaterRepository waterRepository;

  setUp(() async {
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
    await database
        .into(database.profiles)
        .insert(
          ProfilesCompanion.insert(
            id: 'profile-1',
            activityLevel: 'moderate',
            createdAt: now.toUtc(),
            updatedAt: now.toUtc(),
          ),
        );
  });

  tearDown(() => database.close());

  /// 有界泵帧：比 `pumpAndSettle` 可靠（见文件头注释），足够走完弹层动效。
  Future<void> settle(WidgetTester tester, {int frames = 12}) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
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
    await settle(tester);
  }

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

  String latestValue(WidgetTester tester) => tester
      .widget<Text>(find.byKey(const Key('dashboard-weight-trend-value')))
      .textSpan!
      .toPlainText();

  test('仓储：delete 删掉那一行；不存在的 id 返回 null', () async {
    final today = await measurementRepository.saveManualWeight(
      localDate: localDate,
      weightKg: 70.5,
    );
    await measurementRepository.saveManualWeight(
      localDate: '2026-10-25',
      weightKg: 70,
    );

    final deleted = await measurementRepository.delete(today.id);
    expect(deleted, isNotNull);
    expect(deleted!.id, today.id);
    expect(deleted.weightKg, 70.5);

    final rows = await database.select(database.measurements).get();
    expect(rows.map((row) => row.localDate), ['2026-10-25']);

    expect(await measurementRepository.delete(today.id), isNull);
  });

  dashboardTest('体重卡 ⋮ → 列出现有记录 → 删今天那条 → 最新体重回退到前一天', (tester) async {
    await measurementRepository.saveManualWeight(
      localDate: '2026-10-25',
      weightKg: 70,
    );
    await measurementRepository.saveManualWeight(
      localDate: localDate,
      weightKg: 70.5,
    );
    await pump(tester);
    expect(latestValue(tester), '70.5 kg');

    await tester.tap(find.byKey(const Key('weight-records-menu')));
    await settle(tester);
    expect(find.byKey(const Key('weight-record-sheet')), findsOneWidget);
    // 列表按日期倒序：第 0 条是今天那条。
    expect(find.byKey(const Key('weight-record-0')), findsOneWidget);
    expect(find.byKey(const Key('weight-record-1')), findsOneWidget);

    await tester.tap(find.byKey(const Key('weight-record-delete-0')));
    await settle(tester, frames: 4);
    await tester.tap(find.byKey(const Key('weight-record-confirm')));
    await settle(tester);

    final overview = await tester.runAsync(
      () => measurementRepository
          .watchWeightOverview(endLocalDate: localDate)
          .first,
    );
    expect(overview!.latest!.localDate, '2026-10-25');
    expect(latestValue(tester), '70.0 kg', reason: '删完必须重读 overview，卡片跟着回退');
    expect(find.textContaining('撤销'), findsOneWidget);
  });

  dashboardTest('撤销：删完点撤销 → 记录回来（restore，id 不变）', (tester) async {
    await measurementRepository.saveManualWeight(
      localDate: '2026-10-25',
      weightKg: 70,
    );
    final today = await measurementRepository.saveManualWeight(
      localDate: localDate,
      weightKg: 70.5,
    );
    await pump(tester);

    await tester.tap(find.byKey(const Key('weight-records-menu')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('weight-record-delete-0')));
    await settle(tester, frames: 4);
    await tester.tap(find.byKey(const Key('weight-record-confirm')));
    await settle(tester);
    expect(latestValue(tester), '70.0 kg');

    await tester.tap(find.text('撤销'));
    await settle(tester);

    final rows = await tester.runAsync(
      () => database.select(database.measurements).get(),
    );
    expect(rows, hasLength(2));
    expect(rows!.map((row) => row.id), contains(today.id));
    expect(latestValue(tester), '70.5 kg');
  });
}
