@Tags(['capture'])
library;

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
import 'package:localfit_ai/features/training/data/exercise_repository.dart';
import 'package:localfit_ai/features/training/data/exercise_seed_importer.dart';
import 'package:localfit_ai/features/training/data/workout_plan_repository.dart';
import 'package:localfit_ai/features/training/data/workout_session_repository.dart';
import 'package:localfit_ai/features/training/domain/workout_session.dart';
import 'package:localfit_ai/features/training/presentation/training_page.dart';

import 'support/food_fixture.dart';
import 'support/round7_render.dart';

/// 阶段 1（docs/64 A-1…A-4）的取帧件：四类「删错了修不回来」的入口实帧。
/// `LF_ROUND7_CAPTURE_DIR` 指到 tmp 后由证据脚本拷进 docs/evidence/。
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

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await seedFoodFixture(database);
  });

  tearDown(() => database.close());

  Future<void> settle(WidgetTester tester, [int frames = 14]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  Future<void> shot(WidgetTester tester, String name, Key sentinel) async {
    expect(tester.takeException(), isNull, reason: '$name：布局溢出');
    expect(find.byKey(sentinel), findsOneWidget, reason: '$name：关键件不在帧内');
    await captureRound7(tester, name);
  }

  Future<void> pumpSurface(
    WidgetTester tester,
    Widget child, {
    double width = 412,
    double height = 950,
    bool wrapScaffold = true,
    bool scrollable = true,
  }) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = Size(width * 2, height * 2);
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(size: Size(width, height)),
        child: RepaintBoundary(
          key: round7Boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: round7CaptureTheme(AppTheme.light()),
            // 页面自带滚动时直接进 Scaffold（再嵌 SingleChildScrollView 会给
            // 无界高度）；SnackBar 需要 Scaffold 才有落点。
            home: Scaffold(
              body: wrapScaffold && scrollable
                  ? SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: child,
                    )
                  : child,
            ),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  testWidgets('A-1 饮水：记录列表弹层 + 删除后的撤销条', (tester) async {
    await tester.runAsync(loadRound7Fonts);
    final clock = FixedAppClock(now.toUtc());
    final water = WaterRepository(
      database: database,
      idGenerator: const UuidV7Generator(),
      clock: clock,
    );
    await water.add(localDate: '2026-10-26', amountMl: 250);
    await water.add(localDate: '2026-10-26', amountMl: 300);
    final dashboard = DashboardPage(
      mealRepository: MealRepository(
        database: database,
        idGenerator: const UuidV7Generator(),
        clock: clock,
      ),
      measurementRepository: MeasurementRepository(
        database: database,
        idGenerator: const UuidV7Generator(),
        clock: clock,
      ),
      waterRepository: water,
      onOpenAiWorkbench: () {},
      onOpenRecord: () {},
      onLogMeal: (_) {},
      now: now,
    );
    await pumpSurface(
      tester,
      dashboard,
      wrapScaffold: false,
      scrollable: false,
    );

    await tester.longPress(find.byKey(const Key('dashboard-stat-water')));
    await settle(tester);
    await shot(
      tester,
      'fix2-water-records-sheet',
      const Key('water-record-sheet'),
    );

    await tester.tap(find.byKey(const Key('water-record-delete-0')));
    await settle(tester, 4);
    await tester.tap(find.byKey(const Key('water-record-confirm')));
    await settle(tester);
    await shot(
      tester,
      'fix2-water-records-undo',
      const Key('dashboard-water-value'),
    );
    await unmount(tester);
  });

  testWidgets('A-2 体重：记录列表弹层', (tester) async {
    await tester.runAsync(loadRound7Fonts);
    final clock = FixedAppClock(now.toUtc());
    final measurements = MeasurementRepository(
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
    await measurements.saveManualWeight(localDate: '2026-10-25', weightKg: 70);
    await measurements.saveManualWeight(
      localDate: '2026-10-26',
      weightKg: 70.5,
    );
    final dashboard = DashboardPage(
      mealRepository: MealRepository(
        database: database,
        idGenerator: const UuidV7Generator(),
        clock: clock,
      ),
      measurementRepository: measurements,
      waterRepository: WaterRepository(
        database: database,
        idGenerator: const UuidV7Generator(),
        clock: clock,
      ),
      onOpenAiWorkbench: () {},
      onOpenRecord: () {},
      onLogMeal: (_) {},
      now: now,
    );
    await pumpSurface(
      tester,
      dashboard,
      wrapScaffold: false,
      scrollable: false,
      height: 1200,
    );

    await tester.tap(find.byKey(const Key('weight-records-menu')));
    await settle(tester);
    await shot(
      tester,
      'fix2-weight-records-sheet',
      const Key('weight-record-sheet'),
    );
    await unmount(tester);
  });

  testWidgets('A-4 训练回顾：删除这次训练', (tester) async {
    await tester.runAsync(loadRound7Fonts);
    await tester.runAsync(
      () => const ExerciseSeedImporter().importIfNeeded(database),
    );
    final clock = FixedAppClock(now.toUtc());
    final sessions = WorkoutSessionRepository(
      database: database,
      idGenerator: const UuidV7Generator(),
      clock: clock,
    );
    final sessionId = await sessions.start(localDate: '2026-10-26');
    await sessions.logSet(
      sessionId,
      const WorkoutSetDraft(
        exerciseId: 'ex-barbell-squat',
        weightKg: 60,
        reps: 8,
      ),
    );
    await sessions.finish(sessionId);
    await pumpSurface(
      tester,
      TrainingPage(
        exerciseRepository: ExerciseRepository(
          database: database,
          idGenerator: const UuidV7Generator(),
          clock: clock,
        ),
        workoutPlanRepository: WorkoutPlanRepository(
          database: database,
          idGenerator: const UuidV7Generator(),
          clock: clock,
        ),
        workoutSessionRepository: sessions,
        now: now,
      ),
      wrapScaffold: false,
      scrollable: false,
      height: 1200,
    );

    await tester.tap(find.byKey(const Key('training-segment-history')));
    await settle(tester);
    await tester.tap(find.byKey(Key('training-history-$sessionId')));
    await settle(tester);
    await shot(
      tester,
      'fix2-session-review-delete',
      const Key('training-review-sheet'),
    );
    await unmount(tester);
  });
}
