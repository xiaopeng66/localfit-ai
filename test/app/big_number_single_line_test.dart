import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_router.dart';
import 'package:localfit_ai/app/localfit_app.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/hydration/data/water_repository.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/onboarding/domain/complete_onboarding.dart';
import 'package:localfit_ai/features/onboarding/domain/nutrition_target_calculator.dart';
import 'package:localfit_ai/features/progress/data/measurement_repository.dart';
import 'package:localfit_ai/features/progress/data/steps_repository.dart';
import 'package:localfit_ai/features/settings/data/profile_identity_repository.dart';
import 'package:localfit_ai/features/training/data/exercise_repository.dart';
import 'package:localfit_ai/features/training/data/exercise_seed_importer.dart';
import 'package:localfit_ai/features/training/data/workout_plan_repository.dart';
import 'package:localfit_ai/features/training/data/workout_session_repository.dart';

import '../support/food_fixture.dart';

/// E-3（docs/64 阶段 3）：**极端字号下「大数字」不折行**。
///
/// 四处「大数字 + 小单位」：热量（记录页能量卡 consumed）、饮水 / 步数
/// （今日页两卡）、宏量值（记录页宏量行）。判据：320dp × 2.0× 下
/// `RenderParagraph` 的高度 ≤ 1.5 × 字号（测试引擎行高系数 1.0 ⇒ 一行
/// = 1.0 × 字号；两行起就是 2.0 × 字号）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestWidgetsFlutterBinding
      .instance
      .platformDispatcher
      .accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
    disableAnimations: true,
  );

  late AppDatabase database;
  late FoodRepository foodRepository;
  late MealRepository mealRepository;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await seedFoodFixture(database);
    await const ExerciseSeedImporter().importIfNeeded(database);
    await CompleteOnboarding(
      database: database,
      idGenerator: const UuidV7Generator(),
      clock: const SystemAppClock(),
    )(
      const OnboardingInput(
        age: 30,
        biologicalSex: BiologicalSex.male,
        heightCm: 175,
        weightKg: 75,
        activityLevel: ActivityLevel.moderatelyActive,
        goal: HealthGoal.loseFat,
        targetWeightKg: 68,
      ),
    );
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
    // 给饮水/步数卡真实读数（有值才量得出「大数字」的行数）。
    await WaterRepository(
      database: database,
      idGenerator: ids,
      clock: clock,
    ).add(localDate: '2026-09-13', amountMl: 1250);
    await database
        .into(database.stepsDaily)
        .insert(
          StepsDailyCompanion.insert(
            id: 'steps-today',
            localDate: '2026-09-13',
            steps: 12345,
            source: 'manual',
            recordedAt: DateTime(2026, 9, 13, 9),
            createdAt: DateTime(2026, 9, 13, 9),
            updatedAt: DateTime(2026, 9, 13, 9),
          ),
        );
  });

  tearDown(() => database.close());

  void useExtremeViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearAllTestValues);
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 20),
    );
  }

  Future<void> pumpApp(WidgetTester tester, String location) async {
    useExtremeViewport(tester);
    await tester.pumpWidget(
      LocalFitApp(
        initialLocation: location,
        foodRepository: foodRepository,
        mealRepository: mealRepository,
        measurementRepository: MeasurementRepository(
          database: database,
          idGenerator: const UuidV7Generator(),
          clock: const SystemAppClock(),
        ),
        waterRepository: WaterRepository(
          database: database,
          idGenerator: const UuidV7Generator(),
          clock: const SystemAppClock(),
        ),
        stepsRepository: StepsRepository(
          database: database,
          channel: StepsChannel(),
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
        profileIdentityRepository: ProfileIdentityRepository(
          database: database,
        ),
        now: DateTime(2026, 9, 13),
      ),
    );
    await settle(tester);
  }

  /// 断言该 Key 的 Text 在当前布局下是单行（盒高 ≤ 1.5 × 字号）。
  void expectSingleLine(WidgetTester tester, Key key, String label) {
    final text = tester.widget<Text>(find.byKey(key));
    final renderObject = tester.renderObject<RenderParagraph>(find.byKey(key));
    final baseSize = text.style?.fontSize ?? 14.0;
    // text.style.fontSize 是未缩放的基准值；渲染盒用的是 textScaler 过的
    // 行高——阈值必须用**生效字号**算（2.0× 下一行 ≈ 2 × 基准行高）。
    final effective = renderObject.textScaler.scale(baseSize);
    expect(
      renderObject.size.height,
      lessThanOrEqualTo(effective * 1.5),
      reason:
          '$label 在 320dp × 2.0× 下折行了（盒高 '
          '${renderObject.size.height.toStringAsFixed(1)} > '
          '${(effective * 1.5).toStringAsFixed(1)}）——大数字必须单行，'
          '放不下交给 FittedBox 缩，不许换行。',
    );
  }

  testWidgets('E-3 · 今日页饮水 / 步数大数字不折行', (tester) async {
    await pumpApp(tester, AppRoutes.dashboard);
    // 两卡在首屏之下（320×2.0 的懒加载 ListView 不构建屏幕外的行）：
    // 滚到可见再量。
    Future<void> scrollTo(Key target) async {
      await tester.scrollUntilVisible(
        find.byKey(target),
        220,
        scrollable: find
            .byWidgetPredicate(
              (widget) => widget is Scrollable && widget.axis == Axis.vertical,
            )
            .first,
      );
      await settle(tester);
    }

    await scrollTo(const Key('dashboard-water-value'));
    expectSingleLine(tester, const Key('dashboard-water-value'), '饮水大数字');
    await scrollTo(const Key('dashboard-steps-value'));
    expectSingleLine(tester, const Key('dashboard-steps-value'), '步数大数字');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('E-3 · 记录页热量大数字与宏量值不折行', (tester) async {
    await pumpApp(tester, AppRoutes.nutrition);
    expect(
      find.byKey(const Key('nutrition-record-energy-consumed')),
      findsOneWidget,
    );
    expectSingleLine(
      tester,
      const Key('nutrition-record-energy-consumed'),
      '热量大数字',
    );
    // 宏量值的「大数字」是 MacroBar 里的 `Text.rich`（外层 FittedBox
    // scaleDown 兜底）。断言两层：FittedBox 在位 + 里面的段落在生效字号下
    // 仍是单行（FittedBox 只在放不下时整体缩小，不产生第二行）。
    final macroBar = find.byKey(const Key('nutrition-macro-protein'));
    expect(
      find.descendant(of: macroBar, matching: find.byType(FittedBox)),
      findsOneWidget,
      reason: '宏量值的缩放兜底不能拆',
    );
    final macroTexts = find.descendant(
      of: macroBar,
      matching: find.byType(Text),
    );
    final macroText = tester.widget<Text>(macroTexts.first);
    final macroParagraph = tester.renderObject<RenderParagraph>(
      macroTexts.first,
    );
    final macroBase = macroText.style?.fontSize ?? 14.0;
    final macroEffective = macroParagraph.textScaler.scale(macroBase);
    expect(
      macroParagraph.size.height,
      lessThanOrEqualTo(macroEffective * 1.5),
      reason: '蛋白质宏量值在 320dp × 2.0× 下折行了',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
