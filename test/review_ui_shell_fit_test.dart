import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/daily_plan/data/planning_constraints_repository.dart';
import 'package:localfit_ai/features/daily_plan/domain/planning_constraints.dart';
import 'package:localfit_ai/features/daily_plan/presentation/dietary_constraints_sheet.dart';
import 'package:localfit_ai/features/dashboard/presentation/sections/weight_records_sheet.dart';
import 'package:localfit_ai/features/hydration/data/water_repository.dart';
import 'package:localfit_ai/features/hydration/presentation/water_records_sheet.dart';
import 'package:localfit_ai/features/progress/data/measurement_repository.dart';
import 'package:localfit_ai/features/settings/application/data_self_check.dart';
import 'package:localfit_ai/features/settings/presentation/data_self_check_page.dart';

/// 复核第二轮（2026-10-28）：**真实弹层壳**下的纵向适配。
///
/// 取帧器（`review_ui_320_capture_test`）自带 `SingleChildScrollView` 且给了
/// 1200dp 高，只能证明「内容横不横溢」，**证明不了真实弹层**（`AppSheet.showCustom`
/// 无滚动层，高度上限 = 屏幕 90%）在 320dp × 2.0× 下内容放不放得下。
/// 本组用例走真实入口（`showXxx` → `showModalBottomSheet` → 90% 上限），
/// 屏高取悲观的 640dp（320×640×2.0 → 上限 576dp）：
/// 任何 RenderFlex 溢出都会被 `takeException` 抓到。
///
/// RED 记录：本文件第一次运行时，菜品编辑 / 饮食约束 / 数据自检 三处
/// 报 `A RenderFlex overflowed by ... pixels on the bottom`；补水
/// `SingleChildScrollView` 后转绿。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestWidgetsFlutterBinding
      .instance
      .platformDispatcher
      .accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
    disableAnimations: true,
  );

  final now = DateTime(2026, 10, 26, 12);
  late AppDatabase database;
  late MeasurementRepository measurements;
  late WaterRepository water;
  late PlanningConstraintsRepository constraints;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    const ids = UuidV7Generator();
    final clock = FixedAppClock(now.toUtc());
    measurements = MeasurementRepository(
      database: database,
      idGenerator: ids,
      clock: clock,
    );
    water = WaterRepository(database: database, idGenerator: ids, clock: clock);
    constraints = PlanningConstraintsRepository(
      database: database,
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

  Future<void> openSheet(
    WidgetTester tester,
    void Function(BuildContext context) open, {
    required Key sentinel,
  }) async {
    tester.view.physicalSize = const Size(640, 1280); // 320×640 @ 2x
    tester.view.devicePixelRatio = 2;
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => open(context),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    for (var i = 0; i < 14; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    expect(find.byKey(sentinel), findsOneWidget, reason: '弹层没挂出来');
    // 任何布局溢出都在这里落红（RenderFlex 溢出在测试里就是异常）。
    expect(
      tester.takeException(),
      isNull,
      reason: '真实弹层壳（90% 屏高）下 320×640 × 2.0× 内容溢出',
    );
  }

  testWidgets('饮水记录弹层（真实壳，320×640 × 2.0×）', (tester) async {
    await water.add(localDate: '2026-10-26', amountMl: 250);
    await water.add(localDate: '2026-10-26', amountMl: 300);
    await openSheet(
      tester,
      (context) => showWaterRecordsSheet(
        context,
        repository: water,
        localDate: '2026-10-26',
      ),
      sentinel: const Key('water-record-sheet'),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('体重记录弹层（真实壳，320×640 × 2.0×）', (tester) async {
    final first = await measurements.saveManualWeight(
      localDate: '2026-10-25',
      weightKg: 70,
    );
    final second = await measurements.saveManualWeight(
      localDate: '2026-10-26',
      weightKg: 70.5,
    );
    await openSheet(
      tester,
      (context) => showWeightRecordsSheet(
        context,
        repository: measurements,
        measurements: [second, first],
      ),
      sentinel: const Key('weight-record-sheet'),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('体重确认态（320×2.0 全同屏）', (tester) async {
    final first = await measurements.saveManualWeight(
      localDate: '2026-10-25',
      weightKg: 70,
    );
    final second = await measurements.saveManualWeight(
      localDate: '2026-10-26',
      weightKg: 70.5,
    );
    await openSheet(
      tester,
      (context) => showWeightRecordsSheet(
        context,
        repository: measurements,
        measurements: [second, first],
      ),
      sentinel: const Key('weight-record-sheet'),
    );
    await tester.tap(find.byKey(const Key('weight-record-delete-0')));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    // 确认态：确认语独占整行 + 两钮在其下（与饮水表同一形态）。
    expect(find.byKey(const Key('weight-record-confirm')), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const Key('weight-record-confirm'))).dy,
      greaterThan(
        tester.getBottomLeft(find.textContaining('删除 2026-10-26')).dy,
      ),
      reason: '确认钮必须在确认语下方（不再与文字同行挤宽度）',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('饮食约束弹层（真实壳，320×640 × 2.0×，9 项塞满）', (tester) async {
    await constraints.save(
      PlanningConstraints(
        dietaryLabels: DietaryLabel.values,
        allergenAvoidances: const [
          '蛋类',
          '乳制品',
          '大豆',
          '麸质',
          '花生',
          '树坚果',
          '鱼类',
          '甲壳类',
          '芝麻',
        ],
      ),
    );
    await openSheet(
      tester,
      (context) =>
          showDietaryConstraintsSheet(context, repository: constraints),
      sentinel: const Key('dietary-constraints-sheet'),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('数据自检弹层（真实壳，320×640 × 2.0×，三类问题）', (tester) async {
    await database.customStatement('PRAGMA foreign_keys = OFF');
    await database
        .into(database.meals)
        .insert(
          MealsCompanion.insert(
            id: 'meal-orphan',
            localDate: '2026-10-20',
            slot: 'lunch',
            source: 'manual',
            eatenAt: now,
            createdAt: now,
            updatedAt: now,
          ),
        );
    await database
        .into(database.mealItems)
        .insert(
          MealItemsCompanion.insert(
            id: 'item-orphan',
            mealId: 'meal-orphan',
            foodId: const Value('deleted-food'),
            foodNameSnapshot: '某种食物',
            grams: 100,
            kcalSnapshot: 100,
            proteinSnapshot: 5,
            carbsSnapshot: 20,
            fatSnapshot: 2,
            createdAt: now,
            updatedAt: now,
          ),
        );
    await database.customStatement('PRAGMA foreign_keys = ON');
    await database
        .into(database.meals)
        .insert(
          MealsCompanion.insert(
            id: 'meal-bad-date',
            localDate: '2026/10/01',
            slot: 'lunch',
            source: 'manual',
            eatenAt: now,
            createdAt: now,
            updatedAt: now,
          ),
        );
    await database
        .into(database.stepsDaily)
        .insert(
          StepsDailyCompanion.insert(
            id: 'steps-old',
            localDate: '2026-09-01',
            steps: 3000,
            source: 'manual',
            recordedAt: now,
            createdAt: now,
            updatedAt: now,
          ),
        );
    final selfCheck = DataSelfCheck(
      database: database,
      clock: FixedAppClock(now.toUtc()),
    );
    await openSheet(
      tester,
      (context) => showDataSelfCheckSheet(context, selfCheck: selfCheck),
      sentinel: const Key('data-self-check-sheet'),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
