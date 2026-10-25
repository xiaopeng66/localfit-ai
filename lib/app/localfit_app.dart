import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:localfit_ai/app/app_router.dart';
import 'package:localfit_ai/features/ai/domain/ai_connectivity_monitor.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/features/campus_menus/application/food_reference_service.dart';
import 'package:localfit_ai/features/daily_plan/data/planning_constraints_repository.dart';
import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart';
import 'package:localfit_ai/features/nutrition/application/food_library_controller.dart';
import 'package:localfit_ai/features/nutrition/data/catalog_bootstrap.dart';
import 'package:localfit_ai/features/ai_conversation/domain/ai_conversation_service.dart';
import 'package:localfit_ai/features/ai_conversation/application/chat_edit_coordinator.dart';
import 'package:localfit_ai/features/ai_memory/data/ai_memory_repository.dart';
import 'package:localfit_ai/features/jobs/data/background_job_repository.dart';
import 'package:localfit_ai/features/ai_conversation/application/pick_chat_image.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_image.dart';
import 'package:localfit_ai/features/ai_conversation/domain/conversation_message_repository.dart';
import 'package:localfit_ai/features/ai_workbench/application/ai_workbench_task.dart';
import 'package:localfit_ai/features/food_scan/application/load_meal_recognition_disclosure.dart';
import 'package:localfit_ai/features/food_scan/application/resolve_meal_scan_candidates.dart';
import 'package:localfit_ai/features/food_scan/application/prepare_meal_image.dart';
import 'package:localfit_ai/features/food_scan/application/recognize_confirmed_meal_image.dart';
import 'package:localfit_ai/features/nutrition/application/add_dish_to_meal.dart';
import 'package:localfit_ai/features/nutrition/data/dish_library_repository.dart';
import 'package:localfit_ai/features/retrieval/application/semantic_runtime.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/progress/application/load_intake_trend.dart';
import 'package:localfit_ai/features/hydration/application/update_water_target_ml.dart';
import 'package:localfit_ai/features/hydration/data/water_repository.dart';
import 'package:localfit_ai/features/progress/data/measurement_repository.dart';
import 'package:localfit_ai/features/progress/application/scale_sync_controller.dart';
import 'package:localfit_ai/features/progress/data/steps_repository.dart';
import 'package:localfit_ai/features/settings/application/load_profile_overview.dart';
import 'package:localfit_ai/features/settings/data/app_settings_repository.dart';
import 'package:localfit_ai/features/settings/data/profile_identity_repository.dart';
import 'package:localfit_ai/features/settings/data/pick_avatar.dart';
import 'package:localfit_ai/features/settings/data/avatar_image_store.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/features/settings/data/ai_api_key_store.dart';
import 'package:localfit_ai/features/settings/domain/ai_endpoint_probe.dart';
import 'package:localfit_ai/features/settings/domain/ai_provider_settings.dart';
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
import 'package:localfit_ai/features/onboarding/domain/complete_onboarding.dart';
import 'package:localfit_ai/features/onboarding/domain/nutrition_target_calculator.dart';

class LocalFitApp extends StatefulWidget {
  /// 系统级文案的本地化委托（Material / Widgets / Cupertino 三件）。
  ///
  /// 抽成静态常量是为了让**测试**能用同一份配置渲染再断言菜单文案——
  /// 只断言「配置里有没有这几个 delegate」证明不了菜单是中文。
  static const List<LocalizationsDelegate<Object>> localizationsDelegates = [
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ];

  /// 支持的语言：简体中文优先，英文兜底。
  static const List<Locale> supportedLocales = [
    Locale('zh', 'CN'),
    Locale('en'),
  ];

  /// 固定 `zh-CN`（本项目只做中文界面）：系统语言是英文时也不切成英文，
  /// 免得界面一半中文一半英文。
  static const Locale preferredLocale = Locale('zh', 'CN');

  const LocalFitApp({
    super.key,
    this.router,
    this.initialLocation = AppRoutes.dashboard,
    this.completeOnboarding,
    this.foodRepository,
    this.mealRepository,
    this.measurementRepository,
    this.waterRepository,
    this.stepsRepository,
    this.updateWaterTargetMl,
    this.scaleSync,
    this.prepareMealImage,
    this.recognizeConfirmedMealImage,
    this.loadMealRecognitionDisclosure,
    this.resolveMealScanCandidates,
    this.canteenRepository,
    this.foodReferenceService,
    this.planningConstraintsRepository,
    this.pickDishImage,
    this.dishNutritionPrefill,
    this.foodLibraryController,
    this.aiWorkbenchTasks,
    this.exerciseRepository,
    this.workoutPlanRepository,
    this.workoutSessionRepository,
    this.loadIntakeTrend,
    this.dishLibraryRepository,
    this.semanticRuntime,
    this.aiConnectivity,
    this.addDishToMeal,
    this.workoutPlanProvider,
    this.loadWorkoutPlanDisclosure,
    this.createEncryptedBackup,
    this.restoreEncryptedBackup,
    this.clearAllLocalData,
    this.clearBuiltinFoods,
    this.exportCsvFiles,
    this.catalogBootstrap,
    this.aiProviderSettingsStore,
    this.endpointProbe,
    this.apiKeyStore,
    this.profileIdentityRepository,
    this.pickAvatar,
    this.profileOverviewLoader,
    this.appSettingsRepository,
    this.aiMemoryRepository,
    this.backgroundJobRepository,
    this.conversationService,
    this.conversationMessageRepository,
    this.pickChatImage,
    this.chatImageStore,
    this.chatEdit,
    this.appVersion,
    this.now,
  });

  final GoRouter? router;
  final String initialLocation;
  final Future<NutritionTarget> Function(OnboardingInput input)?
  completeOnboarding;
  final FoodRepository? foodRepository;
  final MealRepository? mealRepository;
  final MeasurementRepository? measurementRepository;

  /// 饮水仓储（docs/21 §5.1 今日页饮水卡，schema 17 新增域）。
  final WaterRepository? waterRepository;

  /// 步数仓储（docs/29 §P9 需求 34）。未接线时步数卡走既有诚实空态。
  final StepsRepository? stepsRepository;

  /// 水分目标写入（docs/32 §3 D11 / §4 T9 需求 72）。未接线时
  /// 「编辑资料」页不渲染水分目标行。
  final UpdateWaterTargetMl? updateWaterTargetMl;

  /// 电子体重秤同步编排（docs/31 S6，需求 47 / D6）。未接线时设置页
  /// 不渲染秤行。
  final ScaleSyncController? scaleSync;
  final PrepareMealImage? prepareMealImage;
  final RecognizeConfirmedMealImage? recognizeConfirmedMealImage;
  final LoadMealRecognitionDisclosure? loadMealRecognitionDisclosure;
  final ResolveMealScanCandidates? resolveMealScanCandidates;

  /// 菜单 tab 控制器（2.0-6c；main 按应用私有目录构造）。
  final CanteenRepository? canteenRepository;
  final FoodReferenceService? foodReferenceService;
  final PlanningConstraintsRepository? planningConstraintsRepository;

  /// 菜品照片取图（docs/29 §P7 需求 16）；null＝菜品表单不渲染照片字段。
  final Future<String?> Function(bool fromCamera)? pickDishImage;

  /// 把待分析菜品预填进「分析菜品营养」任务（见 app_router 同名参数）。
  final void Function({
    required List<String> dishNames,
    required List<String> dishIds,
  })?
  dishNutritionPrefill;

  /// 食物库搜索控制器（2.0-6f；main 按应用支持目录 catalog 分片构造）。
  final FoodLibraryController? foodLibraryController;

  /// 下一餐决策主卡控制器（2.0-6i；本地 solver，无网无 AI）。

  /// AI 工作台任务清单（2.0-6g；main 未注入真实能力时为 null → 空态）。
  final List<AiWorkbenchTask>? aiWorkbenchTasks;
  final ExerciseRepository? exerciseRepository;
  final WorkoutPlanRepository? workoutPlanRepository;
  final WorkoutSessionRepository? workoutSessionRepository;
  final LoadIntakeTrend? loadIntakeTrend;
  final DishLibraryRepository? dishLibraryRepository;

  /// 语义检索运行时（docs/39 §4–§5）：null＝语义路不参与（关键词 + 标签）。
  final SemanticRuntime? semanticRuntime;
  final AiConnectivityMonitor? aiConnectivity;
  final AddDishToMeal? addDishToMeal;

  final WorkoutPlanProvider? workoutPlanProvider;
  final LoadWorkoutPlanDisclosure? loadWorkoutPlanDisclosure;
  final CreateEncryptedBackup? createEncryptedBackup;
  final RestoreEncryptedBackup? restoreEncryptedBackup;
  final ClearAllLocalData? clearAllLocalData;

  /// 「清空内置食物」（docs/32 §4 T11 需求 75）：透传给设置页的食材库组。
  final ClearBuiltinFoods? clearBuiltinFoods;
  final ExportCsvFiles? exportCsvFiles;
  final CatalogBootstrap? catalogBootstrap;
  final AiProviderSettingsStore? aiProviderSettingsStore;

  /// 连通性测试/模型拉取 + 已存 Key 读取（docs/29 §P4）。
  final AiEndpointProbe? endpointProbe;
  final AiApiKeyStore? apiKeyStore;
  final ProfileIdentityRepository? profileIdentityRepository;
  final PickAvatar? pickAvatar;

  /// 我的页派生数据 + 本地键值设置（docs/21 §5.6）。
  final LoadProfileOverview? profileOverviewLoader;
  final AppSettingsRepository? appSettingsRepository;

  /// AI 长期记忆（docs/38 S11）。null＝设置页不渲染入口。
  final AiMemoryRepository? aiMemoryRepository;

  /// 后台任务队列（docs/43 B8）：会话结束提炼进「待确认」用它。
  final BackgroundJobRepository? backgroundJobRepository;

  /// AI 对话服务（docs/21 §5.4 对话式识别扩展）。null＝未接线。
  final AiConversationService? conversationService;

  /// 录音器与语音转写（docs/22 A11）。**两者都非 null 才出现麦克风按钮**；
  /// 任一缺失时语音入口整体隐藏，文字输入与拍照不受影响。

  /// 聊天记录仓储（docs/21 §5.7 新增域「聊天记录」）。null＝不落库。
  final ConversationMessageRepository? conversationMessageRepository;

  /// 相册选图（docs/21 §5.7 图片消息）。null＝加号按钮提示未配置。
  final PickChatImage? pickChatImage;

  /// 聊天图片副本存储（`RV4-P2-06` 清除历史时一并清）。null = 未接线时
  /// 「清除聊天记录」只清文本，并在确认框里说明。
  final ChatImageStore? chatImageStore;

  /// 通用编辑协调器（docs/23）。null＝纯聊天。
  final ChatEditCoordinator? chatEdit;

  /// 应用版本号（docs/21 §5.6 📱 关于）。null＝页面显示「版本未知」。
  final String? appVersion;
  final DateTime? now;

  @override
  State<LocalFitApp> createState() => _LocalFitAppState();
}

class _LocalFitAppState extends State<LocalFitApp> {
  late final GoRouter _router =
      widget.router ??
      createAppRouter(
        initialLocation: widget.initialLocation,
        completeOnboarding: widget.completeOnboarding,
        foodRepository: widget.foodRepository,
        mealRepository: widget.mealRepository,
        measurementRepository: widget.measurementRepository,
        waterRepository: widget.waterRepository,
        stepsRepository: widget.stepsRepository,
        updateWaterTargetMl: widget.updateWaterTargetMl,
        scaleSync: widget.scaleSync,
        prepareMealImage: widget.prepareMealImage,
        recognizeConfirmedMealImage: widget.recognizeConfirmedMealImage,
        loadMealRecognitionDisclosure: widget.loadMealRecognitionDisclosure,
        resolveMealScanCandidates: widget.resolveMealScanCandidates,
        canteenRepository: widget.canteenRepository,
        foodReferenceService: widget.foodReferenceService,
        planningConstraintsRepository: widget.planningConstraintsRepository,
        pickDishImage: widget.pickDishImage,
        foodLibraryController: widget.foodLibraryController,
        exerciseRepository: widget.exerciseRepository,
        workoutPlanRepository: widget.workoutPlanRepository,
        workoutSessionRepository: widget.workoutSessionRepository,
        loadIntakeTrend: widget.loadIntakeTrend,
        dishLibraryRepository: widget.dishLibraryRepository,
        semanticRuntime: widget.semanticRuntime,
        aiConnectivity: widget.aiConnectivity,
        addDishToMeal: widget.addDishToMeal,
        workoutPlanProvider: widget.workoutPlanProvider,
        loadWorkoutPlanDisclosure: widget.loadWorkoutPlanDisclosure,
        createEncryptedBackup: widget.createEncryptedBackup,
        restoreEncryptedBackup: widget.restoreEncryptedBackup,
        clearAllLocalData: widget.clearAllLocalData,
        clearBuiltinFoods: widget.clearBuiltinFoods,
        exportCsvFiles: widget.exportCsvFiles,
        catalogBootstrap: widget.catalogBootstrap,
        aiProviderSettingsStore: widget.aiProviderSettingsStore,
        endpointProbe: widget.endpointProbe,
        apiKeyStore: widget.apiKeyStore,
        profileIdentityRepository: widget.profileIdentityRepository,
        pickAvatar:
            widget.pickAvatar ??
            (widget.profileIdentityRepository == null
                ? null
                : PickAvatar(
                    store: const AvatarImageStore(
                      idGenerator: UuidV7Generator(),
                    ),
                  )),
        profileOverviewLoader: widget.profileOverviewLoader,
        appSettingsRepository: widget.appSettingsRepository,
        aiMemoryRepository: widget.aiMemoryRepository,
        backgroundJobRepository: widget.backgroundJobRepository,
        conversationService: widget.conversationService,
        chatEdit: widget.chatEdit,
        conversationMessageRepository: widget.conversationMessageRepository,
        pickChatImage: widget.pickChatImage,
        chatImageStore: widget.chatImageStore,
        appVersion: widget.appVersion,
        now: widget.now,
      );

  @override
  void dispose() {
    if (widget.router == null) {
      _router.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'LocalFit AI',
      debugShowCheckedModeBanner: false,
      // 系统级文案跟着语言走（2026-10-24 用户：「输入框选中文字后进行复制/
      // 剪切/粘贴，系统提示是英文的 copy/cut/paste」）。
      //
      // 这三件事都靠本地化：文本选择菜单（`copy`/`cut`/`paste`/`selectAll`）、
      // 日期时间选择器、以及 Material 的默认无障碍朗读文案。不配置时 Flutter
      // 回落到 `DefaultMaterialLocalizations`（纯英文，且**无中文回退**）。
      //
      // `zh` 在前 = 首选简体中文；`en` 保留给系统语言为其它地区时的兜底。
      localizationsDelegates: LocalFitApp.localizationsDelegates,
      supportedLocales: LocalFitApp.supportedLocales,
      locale: LocalFitApp.preferredLocale,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      // 高对比（docs/21 §2.8）：系统开启时自动切到高对比档。
      highContrastTheme: AppTheme.light(highContrast: true),
      highContrastDarkTheme: AppTheme.dark(highContrast: true),
      // 【2026-10-25 用户：「软件删除夜间模式，白天晚上都是一个样式」】
      // 固定亮色：不管系统是否开深色，界面都是同一套。深色主题的 token
      // 仍保留在 `AppTheme.dark()`（测试要用），只是不再随系统切换。
      themeMode: ThemeMode.light,
      routerConfig: _router,
    );
  }
}
