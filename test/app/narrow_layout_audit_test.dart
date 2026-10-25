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
import 'package:localfit_ai/features/onboarding/domain/complete_onboarding.dart';
import 'package:localfit_ai/features/onboarding/domain/nutrition_target_calculator.dart';
import 'package:localfit_ai/features/progress/data/measurement_repository.dart';
import 'package:localfit_ai/features/settings/data/profile_identity_repository.dart';
import 'package:localfit_ai/features/training/data/exercise_repository.dart';
import 'package:localfit_ai/features/training/data/exercise_seed_importer.dart';
import 'package:localfit_ai/features/training/data/workout_plan_repository.dart';
import 'package:localfit_ai/features/training/data/workout_session_repository.dart';

import '../support/food_fixture.dart';

/// 窄屏（320dp）整体布局体检。
///
/// 用 `RenderFlex overflowed` 异常作为「文字挤在一块/换行覆盖」的机器可测
/// 信号：巡检各页面与弹层，全程只记录溢出，测试末尾统一断言，一次拿到
/// 完整的溢出清单而不是停在第一个问题。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late FoodRepository foodRepository;
  late MealRepository mealRepository;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await seedFoodFixture(database);
    await const ExerciseSeedImporter().importIfNeeded(database);
    // 建档：体重与餐食落库都要求存在本地档案（`MeasurementRepository.
    // saveManualWeight` / 餐食写入缺档案时走失败分支）。缺档案时弹层的
    // 「保存失败不关窗」（docs/28 §3.5 N7）会把弹层留在屏上，后续巡检步骤
    // 就点不到目标——而且「餐食历史行」这一步会在空历史上下断言，属假绿。
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
  });

  tearDown(() => database.close());

  late List<String> overflows;
  final List<String> stepReports = <String>[];
  void Function(FlutterErrorDetails)? originalHandler;

  /// 安装溢出收集 handler。测试体必须用 [runAudit] 包裹以保证
  /// finally 中还原 handler——不还原会让绑定断言失败并挂死整个测试。
  void startAudit() {
    overflows = <String>[];
    final previousHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      final message = details.exceptionAsString();
      if (message.contains('RenderFlex overflowed')) {
        // 只记录首行；具体 widget 位置由测试框架的完整 dump（含 creator
        // 链与源文件行号）在控制台输出。
        overflows.add(message.split('\n').first);
        return;
      }
      previousHandler?.call(details);
    };
    originalHandler = previousHandler;
  }

  /// 标记步骤边界：把累积溢出归到当前步骤名下。
  void finishAudit(String step) {
    for (var i = 0; i < overflows.length; i++) {
      overflows[i] = '[$step] ${overflows[i]}';
    }
    stepReports.addAll(overflows);
    overflows.clear();
  }

  /// 执行巡检主体并在 finally 中还原 handler；返回步骤溢出报告。
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
    // 断言必须在 handler 还原之后：binding 要求 expect 前恢复原始状态。
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

  void useNarrowViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  /// pumpAndSettle 带超时兜底：持续动画（骨架屏转圈等）不再挂死整个测试。
  Future<void> settle(WidgetTester tester) async {
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 15),
    );
  }

  /// 饮食页 chips 是横向 ListView；窄屏下把目标 chip 拖进视口后点击。
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
    await tester.dragFrom(const Offset(160, 400), const Offset(0, -1200));
    await settle(tester);
    await tester.dragFrom(const Offset(160, 400), const Offset(0, 1200));
    await settle(tester);
  }

  /// 卸载 widget 树并冲掉 drift 查询流取消时排下的零时长 Timer，
  /// 避免测试结束时误报 pending timers。
  /// 悬浮 SnackBar 在测试环境可能永不退出并遮挡弹层底部按钮行，保存后立即移除。
  void dismissSnackBar(WidgetTester tester) {
    final messenger = tester.state<ScaffoldMessengerState>(
      find.byType(ScaffoldMessenger).first,
    );
    messenger.removeCurrentSnackBar();
    messenger.clearSnackBars();
  }

  Future<void> unmountApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('新手引导首步在 320dp 宽度无布局溢出', (tester) async {
    useNarrowViewport(tester);
    startAudit();
    await runAudit(tester, () async {
      await tester.pumpWidget(
        LocalFitApp(initialLocation: AppRoutes.onboarding),
      );
      await settle(tester);
      await scrollThroughPage(tester);
      await unmountApp(tester);
      finishAudit('新手引导');
    });
  });

  testWidgets('四大主页与饮食 chips 在 320dp 宽度无布局溢出', (tester) async {
    useNarrowViewport(tester);
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

      // docs/21 §4.1：底栏中间槽 = AI 对话；拍照识餐是推入式二级页，
      // 以初始位置直开审计（等价于从 AI 对话 chip / 饮食 FAB 推入）。
      await tester.tap(find.byKey(const Key('nav-ai-workbench')));
      await settle(tester);
      await scrollThroughPage(tester);
      finishAudit('AI 对话');

      await tester.pumpWidget(app(AppRoutes.mealRecognition));
      await settle(tester);
      await scrollThroughPage(tester);
      finishAudit('拍照');

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

  testWidgets('主要弹层在 320dp 宽度无文字挤压重叠', (tester) async {
    useNarrowViewport(tester);
    startAudit();
    await runAudit(tester, () async {
      await tester.pumpWidget(app(AppRoutes.dashboard));
      await settle(tester);

      dismissSnackBar(tester);
      // 1) 记录体重弹层：填写并保存。体重卡在 320dp 首屏下方，先滚动露出。
      await tester.dragFrom(const Offset(160, 400), const Offset(0, -600));
      await settle(tester);
      // 测试环境的悬浮层会截获体重入口的命中链，直接调用回调绕过该夹具限制。
      // 今日页体重卡空态入口 `dashboard-weight-record`（2026-10-03 起为
      // docs/21 §3.8 的 B6 文字按钮 `LfTextButton`，内部是原生 `TextButton`；
      // 这里只取回调，与按钮类型无关——按新结构重新定位）。
      final weightEntryButton =
          find
                  .byKey(const Key('dashboard-weight-record'))
                  .evaluate()
                  .single
                  .widget
              as TextButton;
      weightEntryButton.onPressed!();
      await settle(tester);
      await tester.ensureVisible(find.byKey(const Key('weight-input')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('weight-input')), '62.5');
      await settle(tester);
      // 体重保存后的 SnackBar 在测试中不会自动消失，直接调用按钮回调绕过
      // 被浮层遮挡的命中链；这与下方餐食保存的测试处理一致。
      final weightSaveButton =
          find.byKey(const Key('weight-save')).evaluate().single.widget
              as FilledButton;
      weightSaveButton.onPressed!();
      await settle(tester);
      dismissSnackBar(tester);
      finishAudit('弹层·记录体重');

      // 2) 记录一餐弹层：添加两种食物（覆盖克数输入行），保存后巡检历史行。
      await tester.tap(find.text('饮食'));
      await settle(tester);
      await tester.tap(find.byTooltip('记录一餐'));
      await settle(tester);
      await tester.tap(find.byKey(const Key('meal-entry-by-food')));
      await settle(tester);
      await tester.enterText(find.byKey(const Key('meal-food-search')), '米饭');
      await settle(tester);
      await tester.tap(find.text('米饭').last);
      await settle(tester);
      await tester.enterText(find.byKey(const Key('meal-food-search')), '鸡蛋');
      await settle(tester);
      await tester.tap(find.text('鸡蛋').last);
      await settle(tester);
      await tester.enterText(find.byKey(const Key('meal-grams-item-1')), '180');
      await settle(tester);
      finishAudit('弹层·记录一餐（食物行）');
      // 第 1 步体重保存的悬浮 SnackBar 在测试环境永不退出，会盖住弹层底部
      // 按钮行（hit 链被 SnackBar 结构截胡），直调 onPressed 绕过 hit test。
      final saveButton =
          find.byKey(const Key('meal-save')).evaluate().single.widget
              as FilledButton;
      saveButton.onPressed!();
      await settle(tester);
      dismissSnackBar(tester);
      await scrollThroughPage(tester);
      finishAudit('饮食·餐食历史行');

      // 3) 新建食物弹层（表单字段密集）。
      await openChip(tester, '食物库');
      await tester.tap(find.byTooltip('自建食物'));
      await settle(tester);
      await scrollThroughPage(tester);
      finishAudit('弹层·新建食物');
      await tester.tap(find.text('取消'));
      await settle(tester);

      // 「新建食谱弹层」步骤随食谱整族下线一并删除（docs/28 §6.1）。

      // 4) 训练·新建动作弹层（名称 + 两组选项 chips）。
      // 动作库已收进二级入口（docs/22 裁决 ②）：训练页默认落在计划分段，
      // 「动作库」行在分段底部；320×640 下它远在懒列表折叠线以下，先拖进
      // 视口再点。
      await tester.tap(find.text('训练'));
      await settle(tester);
      // 分段文案按 Round7 A（app.js:216）：计划 → 我的计划。
      await tester.tap(find.text('我的计划'));
      await settle(tester);
      final libraryEntry = find.text('动作库');
      if (!tester.any(libraryEntry)) {
        await tester.dragUntilVisible(
          libraryEntry,
          find.byType(Scrollable).first,
          const Offset(0, -160),
        );
        await settle(tester);
      }
      await tester.tap(libraryEntry);
      await settle(tester);
      await tester.tap(find.byTooltip('新建动作'));
      await settle(tester);
      await scrollThroughPage(tester);
      finishAudit('弹层·新建动作');
      await tester.tap(find.text('取消'));
      await settle(tester);
      await unmountApp(tester);
    });
  });
}
