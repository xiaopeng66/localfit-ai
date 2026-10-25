import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_router.dart';
import 'package:localfit_ai/app/localfit_app.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/progress/data/measurement_repository.dart';
import 'package:localfit_ai/features/settings/data/profile_identity_repository.dart';
import 'package:localfit_ai/features/training/data/exercise_repository.dart';
import 'package:localfit_ai/features/training/data/exercise_seed_importer.dart';
import 'package:localfit_ai/features/training/data/workout_plan_repository.dart';
import 'package:localfit_ai/features/training/data/workout_session_repository.dart';

import '../support/food_fixture.dart';

/// 大字（2.0× 系统字号）在 320dp 窄屏下的整页布局体检。
///
/// 与 `narrow_layout_audit_test.dart` 同一套溢出收集机制，只改两处驱动
/// 条件：视口固定 320×640、系统字号设 2.0。用户报告的问题正是「文字换行」，
/// 而旧巡检只跑 1.0，2.0 是实测盲区。Android 真机的 2.0 是非线性放大，
/// 本测试用线性的 2.0 作为**上界**压力：真机同项只会更宽松。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late FoodRepository foodRepository;
  late MealRepository mealRepository;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await seedFoodFixture(database);
    await const ExerciseSeedImporter().importIfNeeded(database);
    const ids = UuidV7Generator();
    const clock = SystemAppClock();
    foodRepository = FoodRepository(
      database: database,
      idGenerator: ids,
      clock: clock,
    );
    mealRepository = MealRepository(
      database: database,
      idGenerator: ids,
      clock: clock,
    );
  });

  tearDown(() => database.close());

  late List<String> overflows;
  final List<String> stepReports = <String>[];
  void Function(FlutterErrorDetails)? originalHandler;

  void startAudit() {
    overflows = <String>[];
    final previousHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      final message = details.exceptionAsString();
      if (message.contains('RenderFlex overflowed')) {
        overflows.add(message.split('\n').first);
        return;
      }
      previousHandler?.call(details);
    };
    originalHandler = previousHandler;
  }

  void finishAudit(String step) {
    for (var i = 0; i < overflows.length; i++) {
      overflows[i] = '[$step] ${overflows[i]}';
    }
    stepReports.addAll(overflows);
    overflows.clear();
  }

  Future<void> runAudit(
    WidgetTester tester,
    Future<void> Function() body,
  ) async {
    stepReports.clear();
    try {
      await body();
    } finally {
      FlutterError.onError = originalHandler;
    }
    expect(stepReports, isEmpty, reason: stepReports.join('\n'));
  }

  Widget app(String location) => LocalFitApp(
    initialLocation: location,
    foodRepository: foodRepository,
    mealRepository: mealRepository,
    measurementRepository: MeasurementRepository(
      database: database,
      idGenerator: const UuidV7Generator(),
      clock: const SystemAppClock(),
    ),
    exerciseRepository: ExerciseRepository(
      database: database,
      idGenerator: const UuidV7Generator(),
      clock: const SystemAppClock(),
    ),
    workoutPlanRepository: WorkoutPlanRepository(
      database: database,
      idGenerator: const UuidV7Generator(),
      clock: const SystemAppClock(),
    ),
    workoutSessionRepository: WorkoutSessionRepository(
      database: database,
      idGenerator: const UuidV7Generator(),
      clock: const SystemAppClock(),
    ),
    profileIdentityRepository: ProfileIdentityRepository(database: database),
    now: DateTime(2026, 9, 13),
  );

  /// 320dp 窄屏 + 2.0× 系统字号。
  void useLargeFontViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 15),
    );
  }

  Future<void> openChip(WidgetTester tester, String label) async {
    final chip = find.text(label);
    if (!tester.any(chip)) {
      fail('未找到 chip：$label');
    }
    final rect = tester.getRect(chip);
    if (rect.right > 320 || rect.left < 0) {
      final view = find.ancestor(
        of: find.text('记录'),
        matching: find.byWidgetPredicate(
          (widget) => widget is Scrollable && widget.axis == Axis.horizontal,
        ),
      );
      await tester.dragUntilVisible(chip, view, const Offset(-100, 0));
      await settle(tester);
    }
    await tester.tap(chip);
    await settle(tester);
  }

  Future<void> scrollThroughPage(WidgetTester tester) async {
    await tester.dragFrom(const Offset(160, 400), const Offset(0, -1500));
    await settle(tester);
    await tester.dragFrom(const Offset(160, 300), const Offset(0, -1500));
    await settle(tester);
    await tester.dragFrom(const Offset(160, 400), const Offset(0, 1500));
    await settle(tester);
  }

  Future<void> unmountApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('大字（2.0×）下四大主页与底栏在 320dp 无布局溢出', (tester) async {
    useLargeFontViewport(tester);
    startAudit();
    await runAudit(tester, () async {
      await tester.pumpWidget(app(AppRoutes.dashboard));
      await settle(tester);
      await scrollThroughPage(tester);
      finishAudit('今日');

      await tester.tap(find.text('训练'));
      await settle(tester);
      await scrollThroughPage(tester);
      finishAudit('训练');

      await tester.tap(find.byKey(const Key('nav-ai-workbench')));
      await settle(tester);
      await scrollThroughPage(tester);
      finishAudit('AI 对话');

      await tester.tap(find.text('我的'));
      await settle(tester);
      await scrollThroughPage(tester);
      finishAudit('我的');

      await tester.tap(find.text('饮食'));
      await settle(tester);
      await scrollThroughPage(tester);
      finishAudit('饮食·记录');

      // 「计划」「食谱」两个 tab 随食谱计划整族下线（docs/28 §6.1）。
      for (final chip in const ['菜单', '食物库']) {
        await openChip(tester, chip);
        await scrollThroughPage(tester);
        finishAudit('饮食·$chip');
      }
      await unmountApp(tester);
    });
  });

  testWidgets('大字（2.0×）下二级表单页在 320dp 无布局溢出', (tester) async {
    useLargeFontViewport(tester);
    startAudit();
    await runAudit(tester, () async {
      for (final route in const [
        AppRoutes.onboarding,
        AppRoutes.mealRecognition,
      ]) {
        await tester.pumpWidget(app(route));
        await settle(tester);
        await scrollThroughPage(tester);
        finishAudit(route);
      }
      await unmountApp(tester);
    });
  });
}
