import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_router.dart';
import 'package:localfit_ai/app/design/widgets/design_card.dart';
import 'package:localfit_ai/app/design/widgets/lf_top_bar.dart';
import 'package:localfit_ai/app/localfit_app.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart';
import 'package:localfit_ai/features/nutrition/application/food_library_controller.dart';
import 'package:localfit_ai/features/nutrition/data/catalog_search_service.dart';
import 'package:localfit_ai/features/nutrition/data/dish_library_repository.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/settings/domain/ai_provider_settings.dart';
import 'package:localfit_ai/features/training/application/load_workout_plan_disclosure.dart';
import 'package:localfit_ai/features/training/data/exercise_repository.dart';
import 'package:localfit_ai/features/training/data/workout_plan_repository.dart';
import 'package:localfit_ai/features/training/data/workout_session_repository.dart';
import 'package:localfit_ai/features/training/domain/workout_plan.dart';
import 'package:localfit_ai/features/training/presentation/workout_plan_create_page.dart';
import 'package:localfit_ai/features/training/presentation/workout_plan_manual_page.dart';

/// 阶段 H 验收（docs/22 §3 阶段 H）：**二级入口可达性**。
///
/// 规范原文：「所有现有功能的**可达性**必须逐一验证（从新 UI 的某个入口点
/// 能到达），并在证据文档里列出"功能 → 入口路径"表。未达可达的功能视为
/// 迁移遗漏。」本文件把这张表变成断言：每条用例都从**新 UI 的真实入口控件**
/// 出发（`tester.tap` 真实 Key），落到目标页面/弹层的身份标记上。
///
/// 断言的是「到达了什么」而不是「有没有回调」——回调存在但指向错误目标
/// 同样是缺陷，只有落点身份能区分。落点身份优先取「目标页独有的类型/Key」，
/// 其次才是顶栏标题（标题可能与被覆盖页面的文案重名）。
///
/// 2026-10-01 审计抓到并修掉的三个缺口（本文件是它们的哨兵）：
/// 1. `cta-new-plan` 曾打开极简「计划名称」弹层，而 docs/21 §5.5 交互表写
///    的是「→ 现有计划新建页」`/workout-plan-create`（该页此前是孤儿路由，
///    没有任何入口能到达）；
/// 2. `training-ai-plan` 行的可见条件曾与页内 AI 流程的前提不一致
///    （少判 `exerciseRepository`，流程内却读 `exerciseRepository!`）；
///    **2026-10-23 该行整条退役**（用户：「删『AI 生成训练计划』按钮，
///    功能转移到 ➕」），哨兵改为钉「只能在 FAB 模式弹层里到达」；
/// 3. 「自建食物」「添加自定义食材」等入口控件没有 Key，
///    可达性无法用 Key 表达（本阶段补 Key 且不改变可见条件语义）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // 训练页的活动横幅呼吸点等是无限动画；按系统「减弱动画」跑
  // （docs/21 §2.9 装饰动效退化），否则 pumpAndSettle 永远等不完。
  TestWidgetsFlutterBinding
      .instance
      .platformDispatcher
      .accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
    disableAnimations: true,
  );

  late AppDatabase database;
  final now = DateTime(2026, 9, 17, 12);

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
  });
  tearDown(() => database.close());

  Future<void> tapKey(WidgetTester tester, String key, {String? reason}) async {
    final finder = find.byKey(Key(key));
    expect(finder, findsOneWidget, reason: reason ?? '入口控件 $key 不存在');
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  /// 收尾：显式卸载 widget 树并泵一帧。drift 的 `QueryStream` 取消会留一个
  /// `Duration.zero` 定时器（`StreamQueryStore.markAsClosed`），不手动卸载的话
  /// 它会在框架期末销毁树之后才挂起——`!timersPending` 断言会红。
  Future<void> unmountApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  /// 默认按「全接线」构造：饮食页 5 个 tab / 训练页 / 我的页的二级入口各有
  /// 前提依赖，缺一项入口就不渲染——「入口消失」本身是本文件要盯的缺陷，
  /// 所以除了被测的那个空位（[trainingRepos] / [aiPlanDeps]）以外都给全。
  ///
  /// 注意：`LocalFitApp` 的 State 把首个 router 缓存在 `late final` 字段里，
  /// 同类型同位置的 re-pump 不会换路由——一个用例只能有一个 app 实例，
  /// 「换依赖再 pump 一次」测不出第二个方向。
  Future<void> pumpApp(
    WidgetTester tester, {
    required String initialLocation,
    bool trainingRepos = true,
    bool aiPlanDeps = true,
  }) async {
    final ids = _Ids();
    final clock = FixedAppClock(now.toUtc());
    final food = FoodRepository(
      database: database,
      idGenerator: ids,
      clock: clock,
    );
    final meal = MealRepository(
      database: database,
      idGenerator: ids,
      clock: clock,
    );
    await tester.pumpWidget(
      LocalFitApp(
        initialLocation: initialLocation,
        foodRepository: food,
        // 食物库 tab 的搜索框只在控制器接线时渲染（`FoodLibraryView`）；
        // 生产路径一定接线（main.dart），所以这里对齐生产：空分片列表足够，
        // 断言的是入口形态不是目录数据。
        foodLibraryController: FoodLibraryController(
          repository: food,
          catalogSearch: CatalogSearchService(shardPaths: const []),
        ),
        mealRepository: meal,
        canteenRepository: CanteenRepository(
          database: database,
          idGenerator: ids,
          clock: clock,
        ),
        dishLibraryRepository: DishLibraryRepository(
          database: database,
          idGenerator: ids,
          clock: clock,
        ),
        exerciseRepository: trainingRepos
            ? ExerciseRepository(
                database: database,
                idGenerator: ids,
                clock: clock,
              )
            : null,
        workoutPlanRepository: trainingRepos
            ? WorkoutPlanRepository(
                database: database,
                idGenerator: ids,
                clock: clock,
              )
            : null,
        // 生产（main.dart）同时注入会话仓储；训练页的「训练达标」入口与
        // 会话类功能都以它为前提，fixture 缺它就测不到那条入口。
        workoutSessionRepository: trainingRepos
            ? WorkoutSessionRepository(
                database: database,
                idGenerator: ids,
                clock: clock,
              )
            : null,
        workoutPlanProvider: aiPlanDeps ? _FakeWorkoutPlanProvider() : null,
        loadWorkoutPlanDisclosure: aiPlanDeps
            ? LoadWorkoutPlanDisclosure(
                configurationReader: const _FakeConfigReader(),
              )
            : null,
        now: now,
      ),
    );
    await tester.pumpAndSettle();
  }

  // 「计划」「食谱」两个 tab 随食谱计划整族下线（docs/28 §6.1），
  // 饮食页由五项收敛为三项（记录 / 菜单 / 食物库）。
  group('饮食页：三个 tab 的二级入口', () {
    // 【测试退役】「记录 tab：下一餐详情入口 → 详情页」随 R4 整族退役删除
    // （`docs/56` R4 / `docs/58` §5 台账）。断言的**对象**（那个入口与二级页）
    // 已被产品删除；替代断言是**反向**的
    // `test/features/nutrition/record_tab_no_next_meal_entry_test.dart`
    // （入口与文案都不存在）。
    testWidgets('记录 tab：不再有「下一餐详情」入口（R4 反向）', (tester) async {
      _usePhoneViewport(tester);
      await pumpApp(tester, initialLocation: AppRoutes.nutrition);

      expect(
        find.byKey(const Key('nutrition-record-next-meal-entry')),
        findsNothing,
        reason: 'R4：入口整族退役',
      );
      await unmountApp(tester);
    });

    testWidgets('菜单 tab：管理食堂目录入口 → 食堂目录页', (tester) async {
      _usePhoneViewport(tester);
      await pumpApp(tester, initialLocation: AppRoutes.nutrition);

      await tapKey(tester, 'nutrition-tab-menu');
      await tapKey(tester, 'cta-manage-canteen');
      expect(
        find.text('食堂目录'),
        findsOneWidget,
        reason: 'docs/21 §5.3：菜单页 hero 右上角是食堂目录二级页的唯一入口',
      );
      await unmountApp(tester);
    });

    testWidgets('食物库 tab：搜索框在位、自建食物入口 → 新建食物弹层', (tester) async {
      _usePhoneViewport(tester);
      await pumpApp(tester, initialLocation: AppRoutes.nutrition);

      await tapKey(tester, 'nutrition-tab-foodlib');
      expect(
        find.byKey(const Key('food-library-search')),
        findsOneWidget,
        reason: '食物库 tab 必须带本地搜索框（docs/21 §5.2 §5.8.3）',
      );

      await tapKey(tester, 'cta-new-food');
      expect(
        find.byKey(const Key('new-food-name')),
        findsOneWidget,
        reason: '「自建食物」必须打开新建食物表单',
      );
      await unmountApp(tester);
    });

    testWidgets('顶栏动作是 §3.8 B4 的圆形图标钮（裸 IconButton 会把顶栏撑高）', (tester) async {
      _usePhoneViewport(tester);
      await pumpApp(tester, initialLocation: AppRoutes.nutrition);

      // 顶栏行高由这枚钮决定（视觉圆 36 / 触达 44）；退回裸 `IconButton`
      // 的 48 方框会让整条顶栏变高，而「点得到」的断言抓不住这一点。
      await tapKey(tester, 'nutrition-tab-foodlib');
      tester.widget<LfCircleIconButton>(find.byKey(const Key('cta-new-food')));
      await unmountApp(tester);
    });
  });

  group('训练页：计划新建与动作库', () {
    // 2026-10-08 docs/30 §2 D7 取代了旧契约：`cta-new-plan` 曾经**按依赖
    // 分叉**——齐全直跳 AI 页、缺失弹名称框。两个方向各只给一条路，用户
    // 永远看不到另一条（配置齐全的人根本不知道能手动建；没配 AI 的人只能
    // 建出空计划再进详情逐个加动作）。现在它**总是先问「怎么建」**，两条
    // 路都在那个弹层里，AI 行在依赖缺失时禁用但可见。
    testWidgets('cta-new-plan：总是先开模式弹层（两行都在）', (tester) async {
      _useTallViewport(tester);
      await pumpApp(tester, initialLocation: AppRoutes.training);

      await tapKey(tester, 'cta-new-plan');
      expect(
        find.byKey(const Key('plan-mode-ai')),
        findsOneWidget,
        reason: '依赖齐全时 AI 行在位（docs/30 §2 D7：入口先选模式）',
      );
      expect(
        find.byKey(const Key('plan-mode-manual')),
        findsOneWidget,
        reason: '依赖齐全时手动行也必须在位——这正是旧实现缺的那条路',
      );
      expect(
        find.byType(WorkoutPlanCreatePage),
        findsNothing,
        reason: '不再直跳 AI 页：先选模式',
      );
      await unmountApp(tester);
    });

    testWidgets('cta-new-plan：AI 依赖缺失 → 两行都在，AI 行禁用但说明去向', (tester) async {
      _useTallViewport(tester);
      await pumpApp(
        tester,
        initialLocation: AppRoutes.training,
        aiPlanDeps: false,
      );

      await tapKey(tester, 'cta-new-plan');
      // 禁用 ≠ 消失（docs/30 §2 D7）：AI 行留着并写明去哪配好它。
      final aiRow = find.byKey(const Key('plan-mode-ai'));
      expect(aiRow, findsOneWidget, reason: '未配置时 AI 行禁用但可见');
      expect(
        find.textContaining('未配置 AI（我的 → AI 模型）'),
        findsOneWidget,
        reason: '禁用行必须说明「去哪打开」，否则用户只看到一个灰块',
      );
      expect(
        tester.widget<DesignCard>(aiRow).onTap,
        isNull,
        reason: 'AI 依赖不齐时这一行点不动——不给点了没反应的按钮',
      );
      expect(
        find.byKey(const Key('plan-mode-manual')),
        findsOneWidget,
        reason: '手动创建只依赖动作库 + 计划仓储，AI 配没配都能用',
      );
      expect(
        find.text('训练计划尚未配置，请先在「我的」里完成 AI 服务。'),
        findsNothing,
        reason: '不能把用户送到「尚未配置」占位页',
      );
      await unmountApp(tester);
    });

    testWidgets('plan-mode-manual → 手动计划页（D7 新增路由）', (tester) async {
      _useTallViewport(tester);
      await pumpApp(
        tester,
        initialLocation: AppRoutes.training,
        aiPlanDeps: false,
      );

      await tapKey(tester, 'cta-new-plan');
      await tapKey(tester, 'plan-mode-manual');
      expect(
        find.byType(WorkoutPlanManualPage),
        findsOneWidget,
        reason: 'docs/30 §2 D7：手动创建走 /workout-plan-manual',
      );
      expect(
        find.byKey(const Key('manual-plan-name')),
        findsOneWidget,
        reason: '手动页必须带计划名称字段（保存校验的第一项）',
      );
      await unmountApp(tester);
    });

    testWidgets('plan-mode-ai → AI 计划新建页（依赖齐全时）', (tester) async {
      _useTallViewport(tester);
      await pumpApp(tester, initialLocation: AppRoutes.training);

      await tapKey(tester, 'cta-new-plan');
      await tapKey(tester, 'plan-mode-ai');
      expect(
        find.byType(WorkoutPlanCreatePage),
        findsOneWidget,
        reason: 'AI 行落到既有的 /workout-plan-create（不新造一页）',
      );
      await unmountApp(tester);
    });

    // 2026-10-23 用户：「删『AI 生成训练计划』按钮，功能转移到 ➕」——
    // 页内那一行退役，AI 入口只在 FAB 的模式弹层里（`plan-mode-ai`）。
    testWidgets('训练页 AI 入口只在 FAB 模式弹层里（training-ai-plan 行已退役）', (tester) async {
      _useTallViewport(tester);
      await pumpApp(tester, initialLocation: AppRoutes.training);
      expect(
        find.byKey(const Key('training-ai-plan')),
        findsNothing,
        reason: '页内不再有第二个 AI 入口',
      );

      await tapKey(tester, 'cta-new-plan');
      expect(
        find.byKey(const Key('plan-mode-ai')),
        findsOneWidget,
        reason: 'AI 生成走 FAB 的模式弹层',
      );
      await unmountApp(tester);
    });

    testWidgets('training-exercise-library → 动作库页', (tester) async {
      _useTallViewport(tester);
      await pumpApp(tester, initialLocation: AppRoutes.training);

      await tapKey(tester, 'training-exercise-library');
      expect(
        find.byKey(const Key('training-exercise-library-back')),
        findsOneWidget,
        reason: 'docs/21 §5.5：动作库是训练页的二级页（有独立返回语义）',
      );
      await unmountApp(tester);
    });

    testWidgets('training-target-progress → 训练达标弹层（阶段 I 补漏）', (tester) async {
      _useTallViewport(tester);
      await pumpApp(tester, initialLocation: AppRoutes.training);

      // 入口行在计划列表之下：懒加载列表不滚过去不会构建。
      await _scrollTo(tester, 'training-target-progress');
      await tapKey(tester, 'training-target-progress');
      expect(
        find.byKey(const Key('dashboard-training-targets')),
        findsOneWidget,
        reason:
            '训练达标（docs/21 §5.1 第 5 项）重建后一度无入口，'
            '必须能从训练页二级入口行到达',
      );
      // 无计划时给的是诚实空态，不编造 0/0 进度。
      expect(find.textContaining('还没有训练计划'), findsOneWidget);
      await unmountApp(tester);
    });
  });

  group('我的页：设置入口', () {
    testWidgets('添加食物数据 → 弹层「手动添加一种食物」→ 新建食物弹层', (tester) async {
      _useTallViewport(tester);
      await pumpApp(tester, initialLocation: AppRoutes.settings);

      // T8（docs/32 §3 D10）：「添加自定义食材」独立行已删，同一动作收进
      // 「添加食物数据」弹层——入口必须仍然两跳可达。
      await _scrollTo(tester, 'settings-food-data');
      await tapKey(tester, 'settings-food-data');
      await tapKey(tester, 'food-data-sheet-manual');
      expect(
        find.byKey(const Key('new-food-name')),
        findsOneWidget,
        reason: '「我的」的手动添加与食物库「自建食物」共用同一表单',
      );
      await unmountApp(tester);
    });

    testWidgets('关于组五个入口都可达', (tester) async {
      _useTallViewport(tester);
      await pumpApp(tester, initialLocation: AppRoutes.settings);

      await _scrollTo(tester, 'settings-version-row');
      for (final entry in const {
        'settings-version-row': '关于 LocalFit AI（版本）',
        'settings-check-update': '检查更新',
        // 「data-attribution」（数据来源与许可证）2026-10-24 按用户要求删除，
        // 故从可达性清单里移除；数据层归属仍由 privacy_statement_audit_test 守。
        'about-help': '帮助文档',
        'about-feedback': '反馈',
      }.entries) {
        expect(
          find.byKey(Key(entry.key)),
          findsOneWidget,
          reason: 'docs/21 §5.6 关于组：「${entry.value}」入口不可达',
        );
      }
      await unmountApp(tester);
    });
  });

  group('AI 工作台：宫格与 ?task= 直达', () {
    // 「recipe-plan」任务随食谱计划整族下线（docs/28 §6.4），余下 6 项。
    const taskIds = [
      'menu-normalize',
      'daily-menu-plan',
      'dish-guidance',
      'workout-plan',
      'meal-pairing',
      'dish-nutrition',
    ];

    // docs/32 §4 T6c：画廊渲染 `aiStarters`（不再注入 tasks）。

    testWidgets('/ai-workbench：宫格列出全部 6 个任务入口', (tester) async {
      _useTallViewport(tester);
      await tester.pumpWidget(
        LocalFitApp(
          router: createAppRouter(initialLocation: AppRoutes.aiWorkbench),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('ai-workbench-hub')), findsOneWidget);
      for (final id in taskIds) {
        expect(
          find.byKey(Key('ai-workbench-task-$id')),
          findsOneWidget,
          reason: '任务「$id」没有宫格入口（功能不可达）',
        );
      }
      await unmountApp(tester);
    });

    for (final id in const ['workout-plan', 'dish-nutrition']) {
      testWidgets('?task=$id：直达该卡的描述框（docs/32 T6c 后的新落点）', (tester) async {
        _useTallViewport(tester);
        await tester.pumpWidget(
          LocalFitApp(
            router: createAppRouter(
              initialLocation: '${AppRoutes.aiWorkbench}?task=$id',
            ),
          ),
        );
        await tester.pumpAndSettle();

        // T6c：旧详情页（`ai-workbench-list` / `AiTaskCard`）已退役，
        // 深链改为直接打开描述框——入口仍然「不白点」。
        expect(
          find.byKey(const Key('ai-starter-sheet')),
          findsOneWidget,
          reason: '`?task=` 必须直接打开该卡的描述框',
        );
        await unmountApp(tester);
      });
    }
  });

  testWidgets('/onboarding：建档页可直接到达并可提交', (tester) async {
    _useTallViewport(tester);
    await tester.pumpWidget(LocalFitApp(initialLocation: AppRoutes.onboarding));
    await tester.pumpAndSettle();

    expect(find.text('建立本地档案'), findsOneWidget);
    // docs/32 §4 T15：主行动移入固定底部行动区 ⇒ 不用先滚到底，
    // 首帧就该是可见可点的（比原来的「滚过去才找得到」更强）。
    expect(
      find.byKey(const Key('onboarding-submit')).hitTestable(),
      findsOneWidget,
      reason: '建档页的主行动必须首帧可达',
    );
    await unmountApp(tester);
  });
}

void _usePhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void _useTallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// 长列表页（我的页/建档页）的目标行在首屏以下：懒加载列表不滚过去就
/// 不会构建，`find.byKey` 找不到它——这属于测试脚手架问题，不写成断言。
Future<void> _scrollTo(WidgetTester tester, String key) async {
  await tester.scrollUntilVisible(
    find.byKey(Key(key)),
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

final class _Ids implements IdGenerator {
  int _value = 0;

  @override
  String next() => 'reach-${_value++}';
}

/// 假 provider：只用于「依赖齐全」这条接线，生成内容不参与断言。
final class _FakeWorkoutPlanProvider implements WorkoutPlanProvider {
  @override
  Future<AiWorkoutPlanDraft> generate(
    AiWorkoutPlanRequest request, {
    WorkoutPlanCancellationToken? cancellationToken,
  }) async {
    return AiWorkoutPlanDraft(
      name: request.goalText,
      warnings: const [],
      days: const [],
    );
  }
}

final class _FakeConfigReader implements AiProviderConfigurationReader {
  const _FakeConfigReader();

  @override
  Future<AiProviderConfiguration?> loadConfiguration() async {
    return const AiProviderConfiguration(
      baseUrl: 'https://example.com/v1',
      model: 'gpt-5',
    );
  }
}
