@Tags(['capture'])
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/features/daily_plan/data/planning_constraints_repository.dart';
import 'package:localfit_ai/features/hydration/data/water_repository.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/dashboard/presentation/sections/weight_records_sheet.dart';
import 'package:localfit_ai/features/daily_plan/presentation/dietary_constraints_sheet.dart';
import 'package:localfit_ai/features/hydration/presentation/water_records_sheet.dart';
import 'package:localfit_ai/features/progress/data/measurement_repository.dart';
import 'package:localfit_ai/features/settings/application/data_self_check.dart';
import 'package:localfit_ai/features/settings/presentation/data_self_check_page.dart';

import 'support/food_fixture.dart';
import 'support/round7_render.dart';

/// 复核 · 新增 UI 面「320dp × 2.0×」布局约束检查（用户：新加的按钮太丑，
/// 重新设计时必须考虑布局约束）。
///
/// 每个新面出两张帧：约束档（320×2.0）与正常档（412×1.0）对照。
/// 截图后逐张自己看，丑的/溢出的重设计。
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

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await seedFoodFixture(database);
    measurements = MeasurementRepository(
      database: database,
      idGenerator: const UuidV7Generator(),
      clock: FixedAppClock(now.toUtc()),
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

  Future<void> settle(WidgetTester tester, [int frames = 14]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  /// 约束档 = 320dp 宽 + 2.0× 字号（用户点名的布局约束）；对照档 = 412×1.0。
  Future<void> pumpSurface(
    WidgetTester tester,
    Widget child, {
    required String tag,
    double width = 320,
    double textScale = 2.0,
    double height = 1200,
  }) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = Size(width * 2, height * 2);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    // 每档从空树重建：pumpWidget 对同型树只做 update，弹层的 State
    // （行内确认态等）会跨档残留，第二档就找不到删除键。
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(
          size: Size(width, height),
          textScaler: TextScaler.linear(textScale),
        ),
        child: RepaintBoundary(
          key: round7Boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: round7CaptureTheme(AppTheme.light()),
            home: Scaffold(
              body: SingleChildScrollView(
                child: Padding(padding: const EdgeInsets.all(16), child: child),
              ),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
    expect(
      tester.takeException(),
      isNull,
      reason: '$tag（${width}dp × $textScale×）：布局溢出',
    );
  }

  Future<void> shot(WidgetTester tester, String name, Key? sentinel) async {
    if (sentinel != null) {
      expect(find.byKey(sentinel), findsOneWidget, reason: '$name：关键件不在帧内');
    }
    await captureRound7(tester, name);
  }

  testWidgets('水记录表 + 行内确认（320×2.0 与 412×1.0）', (tester) async {
    await tester.runAsync(loadRound7Fonts);
    final water = WaterRepository(
      database: database,
      idGenerator: const UuidV7Generator(),
      clock: FixedAppClock(now.toUtc()),
    );
    await water.add(localDate: '2026-10-26', amountMl: 250);
    await water.add(localDate: '2026-10-26', amountMl: 300);

    for (final (tag, w, ts) in const [
      ('320x2', 320.0, 2.0),
      ('412x1', 412.0, 1.0),
    ]) {
      await pumpSurface(
        tester,
        WaterRecordsSheet(repository: water, localDate: '2026-10-26'),
        tag: '水记录表 $tag',
        width: w,
        textScale: ts,
      );
      await tester.tap(find.byKey(const Key('water-record-delete-0')));
      await settle(tester, 4);
      await shot(
        tester,
        'review-water-sheet-$tag',
        const Key('water-record-sheet'),
      );
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('体重记录表（320×2.0 与 412×1.0）', (tester) async {
    await tester.runAsync(loadRound7Fonts);
    await measurements.saveManualWeight(localDate: '2026-10-25', weightKg: 70);
    await measurements.saveManualWeight(
      localDate: '2026-10-26',
      weightKg: 70.5,
    );

    for (final (tag, w, ts) in const [
      ('320x2', 320.0, 2.0),
      ('412x1', 412.0, 1.0),
    ]) {
      await pumpSurface(
        tester,
        WeightRecordsSheet(
          repository: measurements,
          measurements: [
            await measurements.saveManualWeight(
              localDate: '2026-10-26',
              weightKg: 70.5,
            ),
            await measurements.saveManualWeight(
              localDate: '2026-10-25',
              weightKg: 70,
            ),
          ],
        ),
        tag: '体重记录表 $tag',
        width: w,
        textScale: ts,
      );
      await shot(
        tester,
        'review-weight-sheet-$tag',
        const Key('weight-record-sheet'),
      );
      // 确认态也要出帧（2026-10-28 第二轮复核：这里曾是「按钮与数值同行」
      // 的旧形态，只有水表被修过）。
      await tester.tap(find.byKey(const Key('weight-record-delete-0')));
      await settle(tester, 4);
      await shot(
        tester,
        'review-weight-confirm-$tag',
        const Key('weight-record-confirm'),
      );
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('饮食约束弹层（选中 + 超限报错，320×2.0）', (tester) async {
    await tester.runAsync(loadRound7Fonts);
    final constraints = PlanningConstraintsRepository(
      database: database,
      clock: FixedAppClock(now.toUtc()),
    );
    await pumpSurface(
      tester,
      DietaryConstraintsSheet(repository: constraints),
      tag: '饮食约束 320x2',
    );
    await tester.tap(find.text('素食'));
    await tester.enterText(
      find.byKey(const Key('dietary-allergen-input')),
      '芒果',
    );
    await tester.tap(find.byKey(const Key('dietary-allergen-add')));
    await settle(tester, 4);
    await shot(
      tester,
      'review-constraints-320x2',
      const Key('dietary-constraints-sheet'),
    );

    // 超限：塞满 9 项后再加。
    for (var i = 0; i < 9; i++) {
      await tester.enterText(
        find.byKey(const Key('dietary-allergen-input')),
        '忌口$i',
      );
      await tester.tap(find.byKey(const Key('dietary-allergen-add')));
      await settle(tester, 2);
    }
    await shot(
      tester,
      'review-constraints-limit-320x2',
      const Key('dietary-constraints-error'),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('数据自检页（脏数据态，320×2.0 与 412×1.0）', (tester) async {
    await tester.runAsync(loadRound7Fonts);
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
    await database
        .into(database.appSettings)
        .insert(
          AppSettingsCompanion.insert(
            key: 'last_backup_at_ms',
            value: '${now.millisecondsSinceEpoch}',
          ),
        );
    final dirty = DataSelfCheck(
      database: database,
      clock: FixedAppClock(now.toUtc()),
    );

    for (final (tag, w, ts) in const [
      ('320x2', 320.0, 2.0),
      ('412x1', 412.0, 1.0),
    ]) {
      await pumpSurface(
        tester,
        DataSelfCheckPage(selfCheck: dirty),
        tag: '数据自检 $tag',
        width: w,
        textScale: ts,
      );
      await settle(tester, 20);
      await shot(
        tester,
        'review-self-check-$tag',
        const Key('data-self-check-sheet'),
      );
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
