import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:localfit_ai/app/design/widgets/lf_bottom_nav.dart';
import 'package:localfit_ai/features/ai/domain/ai_connectivity_monitor.dart';
import 'package:localfit_ai/features/campus_menus/application/food_reference_service.dart';
import 'package:localfit_ai/features/daily_plan/data/planning_constraints_repository.dart';
import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart';
import 'package:localfit_ai/features/training/presentation/exercise_library_page.dart';
import 'package:localfit_ai/features/campus_menus/presentation/menu_form_prompts.dart';
import 'package:localfit_ai/features/retrieval/presentation/retrieval_debug_route.dart';
import 'package:localfit_ai/features/ai_memory/application/memory_hygiene.dart';
import 'package:localfit_ai/features/ai_memory/application/memory_extraction_queue.dart';
import 'package:localfit_ai/features/jobs/data/background_job_repository.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/features/settings/presentation/profile_edit_page.dart';
import 'package:localfit_ai/features/nutrition/application/food_library_controller.dart';
import 'package:localfit_ai/features/nutrition/data/catalog_bootstrap.dart';
import 'package:localfit_ai/features/ai_workbench/presentation/ai_workbench_page.dart';
import 'package:localfit_ai/features/dashboard/presentation/dashboard_page.dart';
import 'package:localfit_ai/features/food_scan/application/load_meal_recognition_disclosure.dart';
import 'package:localfit_ai/features/food_scan/application/resolve_meal_scan_candidates.dart';
import 'package:localfit_ai/features/food_scan/application/prepare_meal_image.dart';
import 'package:localfit_ai/features/food_scan/domain/meal_image.dart';
import 'package:localfit_ai/features/food_scan/application/recognize_confirmed_meal_image.dart';
import 'package:localfit_ai/features/food_scan/presentation/food_scan_page.dart';
import 'package:localfit_ai/features/nutrition/application/add_dish_to_meal.dart';
import 'package:localfit_ai/features/nutrition/presentation/meal_record_launcher.dart';
import 'package:localfit_ai/features/nutrition/data/dish_library_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart'
    show formatLocalDate;
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/nutrition/presentation/nutrition_intents.dart';
import 'package:localfit_ai/features/ai_workbench/application/ai_starter.dart';
import 'package:localfit_ai/features/nutrition/presentation/nutrition_page.dart';
import 'package:localfit_ai/features/onboarding/domain/complete_onboarding.dart';
import 'package:localfit_ai/features/onboarding/domain/nutrition_target_calculator.dart';
import 'package:localfit_ai/features/onboarding/presentation/onboarding_page.dart';
import 'package:localfit_ai/features/progress/application/load_intake_trend.dart';
import 'package:localfit_ai/features/hydration/application/update_water_target_ml.dart';
import 'package:localfit_ai/features/hydration/data/water_repository.dart';
import 'package:localfit_ai/features/progress/data/measurement_repository.dart';
import 'package:localfit_ai/features/progress/application/scale_sync_controller.dart';
import 'package:localfit_ai/features/progress/data/steps_repository.dart';
import 'package:localfit_ai/features/settings/application/load_profile_overview.dart';
import 'package:localfit_ai/features/settings/data/app_settings_repository.dart';
import 'package:localfit_ai/features/nutrition/presentation/new_food_dialog.dart';
import 'package:localfit_ai/features/nutrition/presentation/food_data_flows.dart';

import 'package:localfit_ai/app/design/widgets/app_snack_bar.dart';
import 'package:localfit_ai/features/settings/data/profile_identity_repository.dart';
import 'package:localfit_ai/features/settings/data/pick_avatar.dart';
import 'package:localfit_ai/features/settings/data/ai_api_key_store.dart';
import 'package:localfit_ai/features/settings/domain/ai_endpoint_probe.dart';
import 'package:localfit_ai/features/settings/domain/ai_provider_settings.dart';
import 'package:localfit_ai/features/settings/presentation/settings_page.dart';
import 'package:localfit_ai/features/training/data/exercise_repository.dart';
import 'package:localfit_ai/features/training/data/workout_plan_repository.dart';
import 'package:localfit_ai/features/training/data/workout_session_repository.dart';
import 'package:localfit_ai/features/training/application/load_workout_plan_disclosure.dart';
import 'package:localfit_ai/features/backup/application/clear_all_local_data.dart';
import 'package:localfit_ai/features/nutrition/application/clear_builtin_foods.dart';
import 'package:localfit_ai/features/backup/application/create_encrypted_backup.dart';
import 'package:localfit_ai/features/backup/application/export_csv_files.dart';
import 'package:localfit_ai/features/backup/application/restore_encrypted_backup.dart';
import 'package:localfit_ai/features/training/domain/workout_plan.dart';
import 'package:localfit_ai/features/training/presentation/training_page.dart';
import 'package:localfit_ai/features/training/presentation/workout_plan_manual_page.dart';
import 'package:localfit_ai/features/ai_conversation/application/pick_chat_image.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_image.dart';
import 'package:localfit_ai/features/ai_conversation/domain/ai_conversation_service.dart';
import 'package:localfit_ai/features/ai_conversation/domain/conversation_message_repository.dart';
import 'package:localfit_ai/features/ai_conversation/application/chat_edit_coordinator.dart';
import 'package:localfit_ai/features/ai_conversation/presentation/ai_conversation_page.dart';
import 'package:localfit_ai/features/ai_memory/data/ai_memory_repository.dart';
import 'package:localfit_ai/features/ai_memory/presentation/ai_memory_page.dart';
import 'package:localfit_ai/features/retrieval/application/semantic_runtime.dart';
import 'package:localfit_ai/features/training/presentation/workout_plan_create_page.dart';

abstract final class AppRoutes {
  static const onboarding = '/onboarding';
  static const dashboard = '/today';
  static const nutrition = '/nutrition';
  static const foodScan = '/scan';
  static const training = '/training';
  static const settings = '/settings';
  static const aiWorkbench = '/ai-workbench';
  // 新增
  static const mealRecognition = '/meal-recognition';
  static const workoutPlanCreate = '/workout-plan-create';

  /// 手动创建训练计划（docs/30 §2 D7 / 需求 7）：完整表单，只依赖动作库 +
  /// 计划仓储 ⇒ AI 未配置的用户也能一次建出有内容的计划。
  static const workoutPlanManual = '/workout-plan-manual';

  /// 个人资料编辑（docs/21 §5.6 身份卡）：route-level，不放进底部导航。
  static const profileEdit = '/profile-edit';

  /// AI 记忆（docs/38 S11）：route-level，不放进底部导航。
  static const aiMemory = '/ai-memory';

  /// 搜索调试 / 模拟面板（docs/39 G21）：route-level，只读诊断面。
  static const retrievalDebug = '/retrieval-debug';

  /// AI 对话页面（docs/21 §5.4 对话式识别扩展）。
  static const aiChat = '/ai-chat';
}

GoRouter createAppRouter({
  String initialLocation = AppRoutes.dashboard,
  Future<NutritionTarget> Function(OnboardingInput input)? completeOnboarding,
  AiConversationService? conversationService,
  ConversationMessageRepository? conversationMessageRepository,
  PickChatImage? pickChatImage,
  ChatImageStore? chatImageStore,
  ChatEditCoordinator? chatEdit,
  FoodRepository? foodRepository,
  MealRepository? mealRepository,
  MeasurementRepository? measurementRepository,
  WaterRepository? waterRepository,
  StepsRepository? stepsRepository,
  UpdateWaterTargetMl? updateWaterTargetMl,
  ScaleSyncController? scaleSync,
  PrepareMealImage? prepareMealImage,
  RecognizeConfirmedMealImage? recognizeConfirmedMealImage,
  LoadMealRecognitionDisclosure? loadMealRecognitionDisclosure,
  ResolveMealScanCandidates? resolveMealScanCandidates,
  CanteenRepository? canteenRepository,
  FoodReferenceService? foodReferenceService,
  PlanningConstraintsRepository? planningConstraintsRepository,

  /// 菜品照片取图（docs/29 §P7 需求 16）。null＝菜品表单不渲染照片字段。
  Future<String?> Function(bool fromCamera)? pickDishImage,
  FoodLibraryController? foodLibraryController,
  ExerciseRepository? exerciseRepository,
  WorkoutPlanRepository? workoutPlanRepository,
  WorkoutSessionRepository? workoutSessionRepository,
  LoadIntakeTrend? loadIntakeTrend,
  DishLibraryRepository? dishLibraryRepository,

  /// 语义检索运行时（docs/39 §4–§5）：null＝未接线，调试面板如实显示不可用。
  SemanticRuntime? semanticRuntime,
  AiConnectivityMonitor? aiConnectivity,
  AddDishToMeal? addDishToMeal,

  WorkoutPlanProvider? workoutPlanProvider,
  LoadWorkoutPlanDisclosure? loadWorkoutPlanDisclosure,
  CreateEncryptedBackup? createEncryptedBackup,
  RestoreEncryptedBackup? restoreEncryptedBackup,
  ClearAllLocalData? clearAllLocalData,
  ClearBuiltinFoods? clearBuiltinFoods,
  ExportCsvFiles? exportCsvFiles,
  CatalogBootstrap? catalogBootstrap,
  AiProviderSettingsStore? aiProviderSettingsStore,

  /// 连通性测试/模型拉取 + 已存 Key 读取（docs/29 §P4）。null＝未接线，
  /// 探测按钮仍可用但只能用刚输入的 Key。
  AiEndpointProbe? endpointProbe,
  AiApiKeyStore? apiKeyStore,
  ProfileIdentityRepository? profileIdentityRepository,
  PickAvatar? pickAvatar,

  /// 长期记忆（docs/38 S11）。null＝未接线：设置页不渲染入口、路由给诚实提示。
  AiMemoryRepository? aiMemoryRepository,

  /// 后台任务队列（docs/43 B8）：会话结束提炼进「待确认」用它。
  BackgroundJobRepository? backgroundJobRepository,

  /// 我的页派生数据 + 本地键值设置（docs/21 §5.6）。
  LoadProfileOverview? profileOverviewLoader,
  AppSettingsRepository? appSettingsRepository,

  /// 应用版本号（docs/21 §5.6 📱 关于）。由 main 从 package_info 之类
  /// 读出来后注入；null＝不显示具体版本号，页面显示「版本未知」。
  String? appVersion,
  DateTime? now,
}) {
  // 「查看菜单」跨页请求（今日页决策卡 → 饮食页菜单 chip）：页面常驻
  // IndexedStack，用值通知跨页触发一次切换；与路由同生命周期。
  final menuTabRequest = ValueNotifier<int>(0);
  // 「打开餐食编辑」一次性意向（Round7 阶段 2 决策 D9）：今日页「记录饮食/
  // 记录晚餐」与记录页槽位卡头「+」→ 饮食页弹层。消费一次即清空，避免
  // 用户下次自己进饮食页时突然弹出一个空编辑框。
  final mealAddIntent = MealAddIntent();
  // 「AI 创作」卡的启动请求（docs/32 §4 T6b / §3 D5）：画廊页生成后写入
  // 拼好的启动提示词并切到对话分支；对话页消费一次即清空（冷启动不丢——
  // pending 挂在路由上，与 menuTabRequest 同生命周期）。
  //
  // `RV4-P2-03`（`docs/56` R14 / D5）：通道扩成 `(display, send)` 两段。
  // `send` 是发给模型的正文（带 `[canteen-dish:<id>]` 定位），`display` 是
  // 用户气泡里显示的那份（只有菜名）——**用户不该在气泡里看到机器 id**。
  final aiStarterRequest = ValueNotifier<({String display, String send})?>(
    null,
  );

  /// 「分析菜品」起手请求随附的**菜品照片**（2026-10-16，N2）：有照片就把它作为
  /// 待发图片挂进对话（用户要求「同步把照片发送到 ai」）。与 `aiStarterRequest`
  /// 同生命周期：都是「消费一次即清空」的跨页请求。
  final aiStarterImage = ValueNotifier<String?>(null);

  // 记忆治理（docs/43 B7/B8）：整理建议只读扫描；会话结束提炼进待确认队列。
  // 依赖未接线时两者为 null，页面不渲染对应入口（不给点了没反应的按钮）。
  final memoryHygiene = aiMemoryRepository == null
      ? null
      : MemoryHygiene(
          repository: aiMemoryRepository,
          clock: const SystemAppClock(),
          vectorIndex: semanticRuntime,
        );
  final memoryExtractionQueue =
      backgroundJobRepository == null ||
          aiMemoryRepository == null ||
          appSettingsRepository == null
      ? null
      : MemoryExtractionQueue(
          jobs: backgroundJobRepository,
          memoryRepository: aiMemoryRepository,
          settings: appSettingsRepository,
          clock: const SystemAppClock(),
          service: conversationService,
        );
  final identityStream = profileIdentityRepository?.watchIdentity();
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: AppRoutes.onboarding,
        builder: (context, state) => OnboardingPage(
          completeOnboarding:
              completeOnboarding ??
              (_) => Future.error(
                StateError('Onboarding persistence is not configured.'),
              ),
        ),
      ),
      // AI 创作工作台（2.0-6g）：route-level，不放进底部弹层/导航。
      // `?task=<id>` 直接打开指定任务详情（食堂页「AI 分析这些菜品」入口）。
      GoRoute(
        path: AppRoutes.aiWorkbench,
        builder: (context, state) => AiWorkbenchPage(
          initialTaskId: state.uri.queryParameters['task'],
          // docs/32 §3 D5：生成 → 写启动提示词到 pending → 切对话分支，
          // 由对话页自动发送（T6b）。
          onGenerate: (prompt) {
            // 纯文本启动卡：显示与发送同一份。
            aiStarterRequest.value = (display: prompt, send: prompt);
            GoRouter.of(context).go(AppRoutes.aiChat);
          },
        ),
      ),
      // 个人资料编辑（docs/21 §5.6 身份卡「编辑资料」）：route-level，
      // 惰性回退——仓库未接线时不注册路由，入口也不显示。
      GoRoute(
        path: AppRoutes.profileEdit,
        builder: (context, state) {
          final repository = profileIdentityRepository;
          if (repository == null) {
            return Scaffold(
              appBar: AppBar(title: const Text('编辑个人资料')),
              body: const Center(child: Text('本地档案尚未配置，无法编辑。')),
            );
          }
          return ProfileEditPage(
            repository: repository,
            currentGoal: state.uri.queryParameters['goal'] == null
                ? null
                : HealthGoal.values
                      .where(
                        (goal) =>
                            goal.name == state.uri.queryParameters['goal'],
                      )
                      .firstOrNull,
            onClose: () => GoRouter.of(context).pop(),
            now: now,
            // 「每日目标」两行（docs/32 §3 D11 / §4 T9 需求 64/72）：
            // 依赖未接线就整行不渲染（页面自己判定）。
            stepsRepository: stepsRepository,
            updateWaterTargetMl: updateWaterTargetMl,
            // 头像（2026-10-16，S6）：与设置页身份卡同一个选图器。
            pickAvatar: pickAvatar,
          );
        },
      ),
      // AI 记忆（docs/38 S11）：route-level，惰性回退——仓库未接线时
      // 入口不显示，直接深链进来给一句诚实的说明而不是白屏。
      GoRoute(
        path: AppRoutes.aiMemory,
        builder: (context, state) {
          final repository = aiMemoryRepository;
          if (repository == null) {
            return Scaffold(
              appBar: AppBar(title: const Text('AI 记忆')),
              body: const Center(child: Text('记忆存储尚未配置，无法使用。')),
            );
          }
          return AiMemoryPage(
            repository: repository,
            onClose: () => GoRouter.of(context).pop(),
            constraintsRepository: planningConstraintsRepository,
            hygiene: memoryHygiene,
            extractionQueue: memoryExtractionQueue,
          );
        },
      ),
      // 搜索调试面板（docs/39 G21）：只读诊断；仓储未接线时深链进来如实说明。
      GoRoute(
        path: AppRoutes.retrievalDebug,
        builder: (context, state) {
          final library = dishLibraryRepository;
          if (library == null) {
            return Scaffold(
              appBar: AppBar(title: const Text('搜索调试')),
              body: const Center(child: Text('菜品库尚未配置，无法调试检索。')),
            );
          }
          return RetrievalDebugRoute(
            dishLibraryRepository: library,
            canteenRepository: canteenRepository,
            semantic: semanticRuntime,
            onClose: () => GoRouter.of(context).pop(),
          );
        },
      ),
      // 拍照识餐旧 shell 分支已取消（docs/21 §4.1 裁决：中间槽改 AI 对话，
      // 拍照识餐降为推入式二级页）。保留路径重定向兼容旧 deep-link。
      GoRoute(
        path: AppRoutes.foodScan,
        redirect: (context, state) => AppRoutes.mealRecognition,
      ),
      // 餐食拍照识别（docs/21 §4 / §3.3）：route-level，惰性回退——
      // 拍照仓/识别服务未接线时入口仍保留但提示「尚未配置」。
      GoRoute(
        path: AppRoutes.mealRecognition,
        builder: (context, state) {
          // 不设依赖守卫：FoodScanPage 自行处理未接线的依赖（与旧 /scan
          // 分支行为一致，测试里大量以部分接线构造本页）。
          // P10（需求 37，拍照直通）：`extra` 携带一张已准备好的餐食图
          // （AI 对话的 cta-photo-scan 先开相机拍好再带图进来）⇒ 进页
          // 自动开始识别；不带 extra 的进入（深链/旧 foodScan 重定向）
          // 走页面自己的「拍摄照片」按钮。
          final directImage = state.extra is PreparedMealImage
              ? state.extra as PreparedMealImage
              : null;
          return FoodScanPage(
            initialImage: directImage,
            autoStartCamera: directImage != null,
            prepareMealImage: prepareMealImage,
            recognizeConfirmedMealImage: recognizeConfirmedMealImage,
            resolveMealScanCandidates: resolveMealScanCandidates,
            mealRepository: mealRepository,
            measurementRepository: measurementRepository,
            loadMealRecognitionDisclosure: loadMealRecognitionDisclosure,
            now: now,
            onBackToNutrition: () =>
                GoRouter.of(context).go(AppRoutes.nutrition),
            onOpenManualEntry: () =>
                GoRouter.of(context).go(AppRoutes.nutrition),
            onOpenSettings: () => GoRouter.of(context).go(AppRoutes.settings),
            onOpenWorkoutPlan: () =>
                GoRouter.of(context)
                    .push('${AppRoutes.aiWorkbench}?task=workout-plan'),
          );
        },
      ),
      // 训练计划创建（docs/21 §4 / §3.4）：route-level，惰性回退——
      // 仓库未接线时入口保留但提示「尚未配置」。
      GoRoute(
        path: AppRoutes.workoutPlanCreate,
        builder: (context, state) {
          if (workoutPlanRepository == null ||
              exerciseRepository == null ||
              workoutPlanProvider == null ||
              loadWorkoutPlanDisclosure == null) {
            return Scaffold(
              appBar: AppBar(title: const Text('训练计划')),
              body: const Center(child: Text('训练计划尚未配置，请先在「我的」里完成 AI 服务。')),
            );
          }
          return WorkoutPlanCreatePage(
            exerciseRepository: exerciseRepository,
            workoutPlanRepository: workoutPlanRepository,
            workoutPlanProvider: workoutPlanProvider,
            loadWorkoutPlanDisclosure: loadWorkoutPlanDisclosure,
            now: now,
          );
        },
      ),
      // 手动创建训练计划（docs/30 §2 D7）：与 AI 页**同级的独立路由**——
      // 两者的表单、阶段机与依赖完全不同（AI 页有披露/生成/预览四阶段，
      // 手动页只有一屏表单），塞进一页会让「AI 页」变成两种页面的拼盘。
      // 依赖只有动作库 + 计划仓储：未接线时入口本来就不会出现（训练页按
      // null 判定），这里仍给一条惰性回退说明，避免深链进来是白屏。
      GoRoute(
        path: AppRoutes.workoutPlanManual,
        builder: (context, state) {
          if (exerciseRepository == null || workoutPlanRepository == null) {
            return Scaffold(
              appBar: AppBar(title: const Text('手动创建计划')),
              body: const Center(child: Text('训练计划尚未配置。')),
            );
          }
          return WorkoutPlanManualPage(
            exerciseRepository: exerciseRepository,
            workoutPlanRepository: workoutPlanRepository,
            onCreated: () {
              if (context.mounted) GoRouter.of(context).pop();
            },
          );
        },
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          _branchBuilder(
            AppRoutes.dashboard,
            (context) => StreamBuilder<IdentityProfile?>(
              stream: identityStream,
              builder: (context, snapshot) => DashboardPage(
                identity: snapshot.hasError ? null : snapshot.data,
                mealRepository: mealRepository,
                measurementRepository: measurementRepository,
                waterRepository: waterRepository,
                stepsRepository: stepsRepository,
                onOpenAiWorkbench: () =>
                    GoRouter.of(context).push(AppRoutes.aiWorkbench),
                // 头像 → 「我的」（docs/21 §5.1 交互表）。
                onOpenSettings: () =>
                    GoRouter.of(context).go(AppRoutes.settings),
                // 快捷记录/决策卡动作：都只是入口跳转，不写任何事实。
                // 拍照识餐已改为推入式二级页（docs/21 §4.1）。
                onOpenRecord: () =>
                    GoRouter.of(context).go(AppRoutes.nutrition),
                // 「记录饮食 / 记录晚餐」：**在本页开抽屉**（`RV4-P1-04`）。
                //
                // 原实现是「写一次性意向 + `go(nutrition)`」——用户被带到饮食页
                // （而且停在食物库 tab），退出弹层自然回不到主页。入口拥有者
                // 选错了：抽屉归饮食页的动作层，但「切页 → 目标页开层」把导航
                // 和开层绑在了一起。
                //
                // 现在直接调 `openMealRecordSheet`（复用同一份
                // `chooseRecordEntry` 流程，不复制写逻辑），**不切页**；
                // `mealAddIntent` 只留给跨页的一次性入口（记录页槽位卡头的
                // 「+」仍走它）。
                onLogMeal: (slot) {
                  // 未接线（测试/裁剪构建）：不给点了没反应的入口——
                  // 回退到既有的「切页 + 意向」老路径，行为与修前一致。
                  final foods = foodRepository;
                  final meals = mealRepository;
                  if (foods == null || meals == null) {
                    mealAddIntent.request(slot: slot);
                    GoRouter.of(context).go(AppRoutes.nutrition);
                    return;
                  }
                  final library = dishLibraryRepository;
                  final add = addDishToMeal;
                  unawaited(
                    openMealRecordSheet(
                      context,
                      foods: foods,
                      meals: meals,
                      slot: slot,
                      dishes: library,
                      addDish: add == null || library == null
                          ? null
                          : (dish, {slotOverride}) => add.run(
                              dish: dish,
                              slotOverride: slotOverride,
                              localDate: formatLocalDate(now ?? DateTime.now()),
                            ),
                    ),
                  );
                },
                now: now,
              ),
            ),
          ),
          _branchBuilder(
            AppRoutes.nutrition,
            (context) => NutritionPage(
              repository: foodRepository,
              mealRepository: mealRepository,
              canteenRepository: canteenRepository,
              foodReferenceService: foodReferenceService,
              semanticRuntime: semanticRuntime,
              pickDishImage: pickDishImage,
              onAnalyzeDishes: (dishes) async {
                // docs/32 §4 T6c（D6）：旧任务管线退役——原先经任务控制器
                // 预填再打开任务详情；现在直接把菜名拼成启动提示词、写进
                // 对话 pending 并切到对话分支（生成与写库都在对话里）。
                // `RV4-P2-03`（D5）：显示与发送分离。
                //   send    = 带 `[canteen-dish:<id>]` 的正文（模型靠它定位）
                //   display = 只有菜名 + 一句任务（用户气泡里看不到机器 id）
                final sendLines = [
                  for (final dish in dishes)
                    '[canteen-dish:${dish.id}] ${dish.name}',
                ].join('\n');
                final displayNames = [for (final dish in dishes) dish.name];
                aiStarterRequest.value = (
                  display:
                      '估算这 ${dishes.length} 道菜每 100g 的营养：'
                      '${displayNames.join('、')}',
                  send:
                      '估算下面这几道菜每 100g 的营养，并**用可应用的修改**逐条收录'
                      '（每道菜一条 canteen.dish.nutrition，grade 按你的依据选 '
                      'A/B/C/D）：'
                      '\n'
                      '\n'
                      '$sendLines',
                );
                aiStarterImage.value = _firstDishPhotoPath(dishes);
                GoRouter.of(context).go(AppRoutes.aiChat);
              },
              // 「让 AI 重配整套」（2026-10-25 用户：「换一套…你要确认是不是
              // 走的我配置的AI服务」）：菜单页的「换一套」是**本地重排**
              // （快、不调 AI），AI 重配走这里——复用 AI 对话页
              // `daily-menu-plan` starter 的提示词与既有链路（产出可应用的
              // 编辑卡），**不新造第二条 AI 路径**。
              onAskAiForSet: () async {
                // 先查证「AI 到底配好没有」——**这是原实现缺的一步**：
                // 它不管配没配都弹「AI 未配置」（写死的），用户因此以为
                // 自己的配置没生效。判据：有 provider 配置（baseUrl+model）
                // **且**有 API Key。
                final config = await aiProviderSettingsStore
                    ?.loadConfiguration();
                final hasKey = await apiKeyStore?.hasKey() ?? false;
                if (config == null || !hasKey) return false;
                // await 之后先确认这个 context 还在树上（否则跳转会打到
                // 已失效的 router 上）。
                if (!context.mounted) return false;
                final starter = aiStarters.firstWhere(
                  (s) => s.id == 'daily-menu-plan',
                );
                final prompt = starter.promptBuilder('');
                aiStarterRequest.value = (display: prompt, send: prompt);
                GoRouter.of(context).go(AppRoutes.aiChat);
                return true;
              },
              foodLibraryController: foodLibraryController,
              menuTabRequest: menuTabRequest,
              mealAddRequest: mealAddIntent,
              loadIntakeTrend: loadIntakeTrend,
              dishLibraryRepository: dishLibraryRepository,
              onAddDishToMeal: addDishToMeal == null
                  ? null
                  : (dish, {slotOverride}) => addDishToMeal.run(
                      dish: dish,
                      slotOverride: slotOverride,
                      // 记到「今天」：菜单页的「添加」是当场决策，不是翻看
                      // 历史日期时的补录（补录走记录页的编辑入口）。
                      localDate: formatLocalDate(now ?? DateTime.now()),
                    ),
              now: now,
            ),
          ),
          // AI 对话（docs/21 §4.1 底栏中间槽，已裁决）：shell 分支。
          _branchBuilder(AppRoutes.aiChat, (context) {
            // 食堂两张表单（添加地点/窗口）的编排对象：只为编辑卡的修复按钮
            // 准备。`reload` 给空实现——AI 页没有食堂列表要刷新，真正落库后
            // 菜单页自己会因为数据流而更新。
            final canteenPrompts = canteenRepository == null
                ? null
                : MenuFormPrompts(
                    repository: canteenRepository,
                    reload: () async {},
                  );
            if (conversationService == null) {
              return Scaffold(
                appBar: AppBar(title: const Text('AI 助手')),
                body: const Center(
                  child: Text('AI 对话服务尚未配置，请先在「我的」里完成 AI 服务。'),
                ),
              );
            }
            return StreamBuilder<IdentityProfile?>(
              stream: identityStream,
              builder: (context, snapshot) => AiConversationPage(
                identity: snapshot.hasError ? null : snapshot.data,
                service: conversationService,
                // 2026-10-23 用户：「要 AI 聊天建议（用单独配置的模型理解当前
                // 输出，给 2–3 个建议气泡点击直接发送）」。这里复用对话服务
                // 实例；要换独立模型时把这一项换成另一个 service 即可
                // （页面只依赖 AiConversationService 接口）。
                suggestionService: conversationService,
                historyRepository: conversationMessageRepository,
                // `RV4-R16`（D6 方案 A）：两枚新 chip 的数据源。
                // 未接线时 chip 仍渲染但点了给如实提示（见页面）。
                mealRepository: mealRepository,
                foodRepository: foodRepository,
                dishLibraryRepository: dishLibraryRepository,
                onAddDishToMeal: addDishToMeal == null
                    ? null
                    : (dish, {slotOverride}) => addDishToMeal.run(
                        dish: dish,
                        slotOverride: slotOverride,
                        localDate: formatLocalDate(now ?? DateTime.now()),
                      ),
                // `RV4-P2-06`：清除聊天记录（破坏性操作，需二次确认）。
                conversationHistory: conversationMessageRepository,
                chatImageStore: chatImageStore,
                chatImagePicker: pickChatImage,
                chatEdit: chatEdit,
                aiConnectivity: aiConnectivity,
                // 提炼记忆（docs/38 v2）：未接线时顶栏不渲染按钮。
                aiMemoryRepository: aiMemoryRepository,
                // 「结束本次会话」→ 待确认队列（docs/43 B8，默认关）。
                memoryExtraction: memoryExtractionQueue,
                // 「AI 创作」卡生成的启动提示词（消费一次即清空）。
                pendingStarter: aiStarterRequest,
                pendingStarterImage: aiStarterImage,
                // 快捷 chip 的去处（docs/21 §5.7）：2026-10-23 用户
                // 「底部拍照识别删掉改『确认应用』」——第一枚 chip 现在应用
                // 当前待应用的 AI 提议（页面内动作，不跳路由）；
                // 「我可以吃吗」由页面预填问题。
                // 编辑卡的「创建食材「X」」按钮（2026-10-16）：走既有的
                // 新建食物弹层与 FoodRepository.create，只多带一个预填名。
                onOpenNewFoodWithName: foodRepository == null
                    ? null
                    : (name) => _addCustomFood(
                        context,
                        foodRepository,
                        prefillName: name,
                      ),
                // 2026-10-16：修复建议扩到缺动作/地点/窗口——三个入口都复用
                // 既有表单（动作库的「新建动作」已提成共享函数；食堂两张表
                // 单本来就是 MenuFormPrompts），只多带一个预填名。
                onOpenNewExerciseWithName: exerciseRepository == null
                    ? null
                    : (name) => showCreateExerciseSheet(
                        context,
                        repository: exerciseRepository,
                        prefillName: name,
                      ),
                onOpenNewVenueWithName: canteenPrompts == null
                    ? null
                    : (name) => canteenPrompts.promptAddVenue(
                        context,
                        prefillName: name,
                      ),
                onOpenNewWindowWithName: canteenPrompts == null
                    ? null
                    : (venueId, name) => canteenPrompts.promptAddWindow(
                        context,
                        venueId,
                        prefillName: name,
                      ),
                // Round7 逐页对账批次 2：A `app.js:207` 的第三条 quick chip
                // 「AI 创作」→ 起手画廊（与今日页 AI 入口卡同一路由）。
                onOpenAiCreate: () =>
                    GoRouter.of(context).push(AppRoutes.aiWorkbench),
                // docs/32 §3 D9：顶栏用户头像 → 我的。
                onOpenProfile: () =>
                    GoRouter.of(context).go(AppRoutes.settings),
                onBack: () => GoRouter.of(context).go(AppRoutes.dashboard),
              ),
            );
          }),
          _branchBuilder(
            AppRoutes.training,
            (context) => TrainingPage(
              exerciseRepository: exerciseRepository,
              workoutPlanRepository: workoutPlanRepository,
              workoutSessionRepository: workoutSessionRepository,
              workoutPlanProvider: workoutPlanProvider,
              loadWorkoutPlanDisclosure: loadWorkoutPlanDisclosure,
              // docs/21 §5.5：`cta-new-plan` → 现有计划新建页。四项依赖齐全
              // 时才给这个回调——不齐时该页只会渲染「尚未配置」占位，
              // TrainingPage 会退回极简名称弹层（它按 null 判定）。
              onOpenWorkoutPlanCreate:
                  exerciseRepository != null &&
                      workoutPlanRepository != null &&
                      workoutPlanProvider != null &&
                      loadWorkoutPlanDisclosure != null
                  ? () => GoRouter.of(context).push(AppRoutes.workoutPlanCreate)
                  : null,
              // 手动路只需要动作库 + 计划仓储（docs/30 §2 D7）：AI 没配置
              // 时它照常可用，这正是需求「可 AI 可手动」的落点。
              onOpenWorkoutPlanManual:
                  exerciseRepository != null && workoutPlanRepository != null
                  ? () => GoRouter.of(context).push(AppRoutes.workoutPlanManual)
                  : null,
              now: now,
            ),
          ),
          _branchBuilder(
            AppRoutes.settings,
            (context) => SettingsPage(
              settingsStore: aiProviderSettingsStore,
              endpointProbe: endpointProbe,
              apiKeyStore: apiKeyStore,
              createEncryptedBackup: createEncryptedBackup,
              restoreEncryptedBackup: restoreEncryptedBackup,
              clearAllLocalData: clearAllLocalData,
              clearBuiltinFoods: clearBuiltinFoods,
              exportCsvFiles: exportCsvFiles,
              catalogBootstrap: catalogBootstrap,
              profileOverviewLoader: profileOverviewLoader,
              appSettingsRepository: appSettingsRepository,
              onAddCustomFood: foodRepository == null
                  ? null
                  : () => _addCustomFood(context, foodRepository),
              // Round7 阶段 3 · 3-2c：CSV 导入通路提成共享件（食物库页尾
              // 也要接同一件事），设置页这里只是接线。
              onImportFoodCsv: foodRepository == null
                  ? null
                  : () => runFoodCsvImportFlow(context, foodRepository),
              profileIdentityRepository: profileIdentityRepository,
              // 步数授权行（docs/30 §2 D9 / 需求 3）：未接线时不渲染
              // `settings-steps-permission`，与体重秤行同约定。
              stepsRepository: stepsRepository,
              // Round7 裁决 R5：身份卡「当前体重」→ 只读「体重记录」弹层。
              measurementRepository: measurementRepository,
              // 电子体重秤（docs/31 S6，需求 47 / D6）：未接线时不渲染
              // `settings-scale-row`。
              scaleSync: scaleSync,
              // docs/21 §5.6 🏫：菜单来源（地点/窗口/菜品）的维护界面住在
              // 饮食页的「菜单」tab；这里只是入口，不再造第二份编辑 UI。
              // 复用既有 menuTabRequest 值通知，切 tab 后再跳过去。
              onOpenMenuSources: () {
                menuTabRequest.value++;
                GoRouter.of(context).go(AppRoutes.nutrition);
              },
              // 个人资料编辑（docs/21 §5.6 身份卡「编辑资料」）：route-level，
              // 惰性回退——仓库未接线时不注册路由，入口也不显示。
              //
              // 入口用 `push`（docs/29 §P1 / D2）：本页是推入式二级页，退出靠
              // `pop`（AppBar 关闭钮 / 保存成功）。用 `go` 会替换栈顶、返回栈里
              // 没有可弹出的层级，退出时 `pop` 抛
              // `GoError: There is nothing to pop`。
              onOpenProfileEdit: profileIdentityRepository == null
                  ? null
                  : () => GoRouter.of(context).push(AppRoutes.profileEdit),
              // AI 记忆（docs/38 S11）：未接线时不渲染 `settings-ai-memory-row`。
              onOpenAiMemory: aiMemoryRepository == null
                  ? null
                  : () => GoRouter.of(context).push(AppRoutes.aiMemory),
              // 搜索调试（docs/39 G21）：菜品库未接线时不渲染入口。
              onOpenRetrievalDebug: dishLibraryRepository == null
                  ? null
                  : () => GoRouter.of(context).push(AppRoutes.retrievalDebug),
              appVersion: appVersion,
              now: now,
            ),
          ),
        ],
      ),
    ],
  );
}

StatefulShellBranch _branchBuilder(String path, WidgetBuilder builder) {
  return StatefulShellBranch(
    routes: [
      GoRoute(path: path, builder: (context, state) => builder(context)),
    ],
  );
}

class AppShell extends StatelessWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 新底栏（docs/21 §3.6/§4.1）：贴底 64dp 直角栏 + 中央 AI 凸起圆。
      // extendBody：页面内容延伸到栏下方（毛玻璃才有内容可透）。
      extendBody: true,
      body: navigationShell,
      bottomNavigationBar: LfBottomNav(
        currentIndex: navigationShell.currentIndex,
        onTap: (index) => navigationShell.goBranch(
          index,
          initialLocation: navigationShell.currentIndex == index,
        ),
      ),
    );
  }
}

/// 「添加自定义食材」（docs/21 §5.6 食材库组）：复用饮食页既有的
/// NewFoodDialog 与 FoodRepository.create，不在设置页造第二份创建流程。
Future<void> _addCustomFood(
  BuildContext context,
  FoodRepository repository, {
  String? prefillName,
}) async {
  await NewFoodDialog.show(
    context,
    prefillName: prefillName,
    onSubmit: (food) async {
      try {
        await repository.create(food);
        if (context.mounted) {
          AppSnackBar.show(context, '已添加到食材库。', icon: AppSnackBar.successIcon);
        }
        return null;
      } on FormatException catch (error) {
        return error.message;
      } catch (_) {
        return '食物创建失败，请重试。';
      }
    },
  );
}

/// 这批待分析菜品里第一张存在的照片（N2）：一次请求只带一张图（对话输入区
/// 一个槽位一张），其余菜品仍以文字列出。
String? _firstDishPhotoPath(List<CanteenDish> dishes) {
  for (final dish in dishes) {
    final path = dish.imagePath;
    if (path != null && path.isNotEmpty) return path;
  }
  return null;
}
