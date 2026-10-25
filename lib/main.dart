import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:localfit_ai/app/app_router.dart';
import 'package:localfit_ai/app/localfit_app.dart';
import 'package:localfit_ai/features/campus_menus/application/food_reference_service.dart';
import 'package:localfit_ai/features/campus_menus/application/menu_item_matcher.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:localfit_ai/features/jobs/data/background_job_repository.dart';
import 'package:localfit_ai/features/jobs/application/job_scheduler.dart';
import 'package:localfit_ai/features/jobs/application/power_state_source.dart';
import 'package:localfit_ai/features/retrieval/application/food_data_maintenance.dart';
import 'package:localfit_ai/features/retrieval/application/index_coordinator.dart';
import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart';
import 'package:localfit_ai/features/campus_menus/data/file_menu_raw_content_store.dart';
import 'package:localfit_ai/features/campus_menus/domain/menu_raw_content_store.dart';
import 'package:localfit_ai/features/food_scan/domain/meal_image.dart';
import 'package:localfit_ai/features/ai/domain/ai_connectivity_monitor.dart';
import 'package:localfit_ai/features/ai/domain/prompt_catalog.dart';
import 'package:localfit_ai/features/ai_conversation/data/food_preview_search.dart';
import 'package:localfit_ai/features/ai_conversation/application/pick_chat_image.dart';
import 'package:localfit_ai/features/ai_conversation/data/drift_conversation_message_repository.dart';
import 'package:localfit_ai/features/ai_conversation/data/file_chat_image_store.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_image.dart';
import 'package:localfit_ai/features/ai_conversation/data/open_ai_compatible_conversation_service.dart';
import 'package:localfit_ai/features/ai_conversation/application/chat_edit_coordinator.dart';
import 'package:localfit_ai/features/ai_conversation/application/chat_edit_executor.dart';
import 'package:localfit_ai/features/ai_conversation/data/chat_edit_context_loader.dart';
import 'package:localfit_ai/features/ai_memory/data/ai_memory_repository.dart';
import 'package:localfit_ai/features/daily_plan/data/planning_constraints_repository.dart';
import 'package:localfit_ai/features/nutrition/application/food_library_controller.dart';
import 'package:localfit_ai/features/nutrition/data/bundled_user_food_importer.dart';
import 'package:localfit_ai/features/nutrition/data/catalog_bootstrap.dart';
import 'package:localfit_ai/features/nutrition/data/catalog_search_service.dart';
import 'package:localfit_ai/features/nutrition/data/catalog_shard_importer.dart';
import 'package:localfit_ai/features/nutrition/data/catalog_shard_source.dart';
import 'package:localfit_ai/features/nutrition/data/catalog_shard_detail_source.dart';
import 'package:localfit_ai/features/nutrition/data/food_detail_loader.dart';
import 'package:localfit_ai/features/nutrition/data/food_detail_repository.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/core/storage/secure_key_value_store.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/data/database/database_key_manager.dart';
import 'package:localfit_ai/features/food_scan/application/load_meal_recognition_disclosure.dart';
import 'package:localfit_ai/features/food_scan/application/resolve_meal_scan_candidates.dart';
import 'package:localfit_ai/features/food_scan/application/prepare_meal_image.dart';
import 'package:localfit_ai/features/food_scan/application/recognize_confirmed_meal_image.dart';
import 'package:localfit_ai/features/food_scan/data/image_picker_meal_image_picker.dart';
import 'package:localfit_ai/features/campus_menus/data/dish_image_store.dart';
import 'package:localfit_ai/features/campus_menus/data/pick_dish_image.dart';
import 'package:localfit_ai/features/food_scan/data/meal_image_processor.dart';
import 'package:localfit_ai/features/food_scan/data/open_ai_compatible_meal_recognition_provider.dart';
import 'package:localfit_ai/features/food_scan/data/prepared_meal_image_bytes_reader.dart';
import 'package:localfit_ai/features/food_scan/data/temporary_meal_image_store.dart';
import 'package:localfit_ai/features/settings/data/ai_api_key_store.dart';
import 'package:localfit_ai/features/settings/data/avatar_image_store.dart';
import 'package:localfit_ai/features/settings/data/dio_ai_endpoint_probe.dart';
import 'package:localfit_ai/features/settings/data/local_ai_provider_settings_store.dart';
import 'package:path_provider/path_provider.dart';
import 'package:localfit_ai/features/settings/application/load_profile_overview.dart';
import 'package:localfit_ai/features/settings/data/app_settings_repository.dart';
import 'package:localfit_ai/features/retrieval/application/semantic_runtime.dart';
import 'package:localfit_ai/features/retrieval/data/embedding_worker.dart';
import 'package:localfit_ai/features/settings/data/profile_identity_repository.dart';
import 'package:localfit_ai/features/nutrition/data/food_library_normalizer.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/nutrition/application/add_canteen_dishes_to_library.dart';
import 'package:localfit_ai/features/nutrition/application/add_dish_to_meal.dart';
import 'package:localfit_ai/features/nutrition/data/dish_library_repository.dart';
import 'package:localfit_ai/features/hydration/application/update_water_target_ml.dart';
import 'package:localfit_ai/features/hydration/data/water_repository.dart';
import 'package:localfit_ai/features/progress/application/scale_sync_controller.dart';
import 'package:localfit_ai/features/progress/data/measurement_repository.dart';
import 'package:localfit_ai/features/progress/data/standard_scale_reading_source.dart';
import 'package:localfit_ai/features/progress/data/steps_repository.dart';
import 'package:localfit_ai/features/onboarding/domain/complete_onboarding.dart';
import 'package:localfit_ai/features/training/data/exercise_repository.dart';
import 'package:localfit_ai/features/training/data/exercise_seed_importer.dart';
import 'package:localfit_ai/features/training/data/workout_plan_repository.dart';
import 'package:localfit_ai/features/training/data/workout_session_repository.dart';
import 'package:localfit_ai/features/training/data/open_ai_compatible_workout_plan_provider.dart';
import 'package:localfit_ai/features/training/domain/workout_plan.dart';
import 'package:localfit_ai/features/backup/application/clear_all_local_data.dart';
import 'package:localfit_ai/features/nutrition/application/clear_builtin_foods.dart';
import 'package:localfit_ai/features/progress/application/load_intake_trend.dart';
import 'package:localfit_ai/features/backup/application/export_csv_files.dart';
import 'package:localfit_ai/features/backup/application/create_encrypted_backup.dart';
import 'package:localfit_ai/features/backup/application/restore_encrypted_backup.dart';
import 'package:localfit_ai/features/backup/data/backup_file_store.dart';
import 'package:localfit_ai/features/training/application/load_workout_plan_disclosure.dart';
import 'package:localfit_ai/features/ai_workbench/application/ai_workbench_prompt_templates.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 主 isolate 也会直接 `sqlite3.open`（目录分片搜索与导入），必须先装上
  // 随包 SQLCipher 库的解析覆盖——只给后台数据库 isolate 装会导致真机上
  // 这两条路抛 ArgumentError（见 configureSqlCipherLibrary 的注释）。
  configureSqlCipherLibrary();

  final secureStore = PlatformSecureKeyValueStore();
  final keyManager = DatabaseKeyManager(store: secureStore);
  final database = await AppDatabase.open(key: await keyManager.getOrCreate());
  // 随包**食物**种子已于 2026-10-13 退役（docs/32 §4 T13 / §3 D13，需求 75）：
  // 它每次全新安装的首启都要解析 11 MB JSON、插 49,444 行（实测 842 ms），
  // 而用户要求清空这批内置食物、改用自己的新结构导入。真数据归档在
  // `E:/AI/Zcode/projects/localfit-ai/archive/food-seed-2026-10-13/`，
  // 仓库里不再留文件、pubspec 也不再声明（缺声明而文件在盘上会让打包静默缺文件）。
  // 动作库种子仍在随包发货，照旧导入。
  await const ExerciseSeedImporter().importIfNeeded(database);
  final exerciseRepository = ExerciseRepository(
    database: database,
    idGenerator: const UuidV7Generator(),
    clock: const SystemAppClock(),
  );
  final workoutPlanRepository = WorkoutPlanRepository(
    database: database,
    idGenerator: const UuidV7Generator(),
    clock: const SystemAppClock(),
  );
  final workoutSessionRepository = WorkoutSessionRepository(
    database: database,
    idGenerator: const UuidV7Generator(),
    clock: const SystemAppClock(),
  );
  final foodRepository = FoodRepository(
    database: database,
    idGenerator: const UuidV7Generator(),
    clock: const SystemAppClock(),
  );
  final mealRepository = MealRepository(
    database: database,
    idGenerator: const UuidV7Generator(),
    clock: const SystemAppClock(),
  );
  // 菜品库（docs/21 §5.3「菜单页唯一主来源」）：仓储给读，用例给写。
  final dishLibraryRepository = DishLibraryRepository(
    database: database,
    idGenerator: const UuidV7Generator(),
    clock: const SystemAppClock(),
  );
  final addDishToMeal = AddDishToMeal(
    mealRepository: mealRepository,
    clock: const SystemAppClock(),
  );
  final measurementRepository = MeasurementRepository(
    database: database,
    idGenerator: const UuidV7Generator(),
    clock: const SystemAppClock(),
  );
  final profileIdentityRepository = ProfileIdentityRepository(
    database: database,
  );
  // 我的页派生数据（体重/总记录/连续天数/BMI/BMR/成就，docs/21 §5.6）。
  final profileOverviewLoader = LoadProfileOverview(
    database: database,
    clock: const SystemAppClock(),
  );
  final appSettingsRepository = AppSettingsRepository(database: database);
  // 聊天记录域（schema 17，docs/21 §5.7）：对话落库 + 图片副本存应用文档目录。
  final conversationMessageRepository = DriftConversationMessageRepository(
    database: database,
  );
  const chatImageStore = FileChatImageStore(idGenerator: UuidV7Generator());
  final pickChatImage = PickChatImage(
    picker: ImagePickerMealImagePicker(),
    processor: const IsolateMealImageProcessor(),
    store: chatImageStore,
    clock: const SystemAppClock(),
  );
  // 饮水域（schema 17，docs/21 §5.1 今日页饮水卡）。
  final waterRepository = WaterRepository(
    database: database,
    idGenerator: const UuidV7Generator(),
    clock: const SystemAppClock(),
  );
  // 水分目标写入（docs/32 §3 D11 / §4 T9 需求 72）：「编辑资料」页以 L 输入、
  // 以 ml 落库；今日已有生效行就地更新，否则复制其余列插一条新版本行。
  final updateWaterTargetMl = UpdateWaterTargetMl(
    database: database,
    idGenerator: const UuidV7Generator(),
    clock: const SystemAppClock(),
  );
  // 步数域（docs/29 §P9 需求 34）：读本机计步传感器（本仓首个 MethodChannel）。
  // 表与迁移在 schema 21 已预置，这里只接通道 + 仓储。
  final stepsRepository = StepsRepository(
    database: database,
    channel: StepsChannel(),
    idGenerator: const UuidV7Generator(),
    clock: const SystemAppClock(),
  );
  // 电子体重秤（docs/31 §S6 需求 47）：标准 BLE 体重秤（0x181D/0x2A9D）；
  // 读数按「同日已有记录默认不写、覆盖需用户点选」落地。读数来源是抽象
  // （docs/32 D16）：标准协议只是 `parsers` 里注册的第一个（也是唯一一个）
  // 解析器，私有协议将来在这里注册条目。
  final scaleSync = ScaleSyncController(
    source: StandardScaleReadingSource(),
    repository: measurementRepository,
    clock: const SystemAppClock(),
  );
  final apiKeyStore = AiApiKeyStore(store: secureStore);
  final aiProviderSettingsStore = LocalAiProviderSettingsStore(
    database: database,
    apiKeyStore: apiKeyStore,
  );
  // 连通性测试 + 模型拉取（docs/29 §P4 需求 7）：与正式请求同一套
  // 端点规范化，只是 GET /models、5s 快检超时。
  final aiEndpointProbe = DioAiEndpointProbe(dio: Dio());
  // 全部 AI 出口的 prompt 目录（2.0-6h / docs/11 P3 单源）：四个工作台
  // 合同 + workout 一条 provider 直连链路的模板都注册在这里，
  // provider 渲染只认目录里的这份正文（不许再有内联副本）。
  //
  // 2026-10-04（docs/28 §6.4）：`recipe-plan` 那条合同随食谱计划整族下线，
  // 注册项与模板一并删除（工作台任务 5 → 4）。
  // 2026-10-24（`RV4-P1-08`）：`dailyMenuPlanPromptTemplate` **摘除注册**——
  // 它要求模型返回 `daily-menu-plan v1` JSON，而该契约的解码器已整族退役
  // （`RV2-P2-01`）。文件**保留**（egress 评测集还引用它的正文），但不进目录
  // ⇒ provider 不会再渲染这条已退役的形状。
  final promptCatalog = PromptCatalog()
    ..register(menuNormalizePromptTemplate)
    ..register(dishGuidancePromptTemplate)
    ..register(workoutPlanPromptTemplate)
    ..register(mealPairingPromptTemplate);
  final workoutPlanProvider = OpenAiCompatibleWorkoutPlanProvider(
    dio: Dio(),
    configurationReader: aiProviderSettingsStore,
    apiKeyStore: apiKeyStore,
    catalog: promptCatalog,
  );
  final aiConversationService = OpenAiCompatibleConversationService(
    dio: Dio(),
    configurationReader: aiProviderSettingsStore,
    apiKeyStore: apiKeyStore,
  );
  final loadWorkoutPlanDisclosure = LoadWorkoutPlanDisclosure(
    configurationReader: aiProviderSettingsStore,
  );
  const backupFileStore = FilePickerBackupFileStore();
  final createEncryptedBackup = CreateEncryptedBackup(
    database: database,
    fileStore: backupFileStore,
  );
  const temporaryMealImageStore = FileTemporaryMealImageStore(
    idGenerator: UuidV7Generator(),
  );
  // 菜单原文（2.0-7b）：写在应用私有目录 <supportDir>/menu_raw，数据库
  // 只存相对路径（docs/07 §6.1）；同一个实例也交给清除流程整目录删除。
  final supportDir = (await getApplicationSupportDirectory()).path;
  final menuRawContentStore = FileMenuRawContentStore(supportDir);
  // 食物目录（2.0-1i / docs/07 §5.6）：随包 core 分片装完即导入，其余分片等用户把
  // 文件放进 <supportDir>/catalog/ 后主动导入——应用不自动联网下载。
  final catalogBootstrap = CatalogBootstrap(
    source: CatalogShardSource(
      supportDir: supportDir,
      assetLoader: _loadBundledCatalogAsset,
    ),
    importer: CatalogShardImporter(database: database),
  );
  // prepare() 只把随包 core 分片落到磁盘：搜索链路是按目录列出 .sqlite 的
  // （_catalogShardPaths），必须赶在它之前完成。真正的写库导入放到 runApp
  // 之后（几万行，不能挡住首帧，见 docs/05 §3）。
  await catalogBootstrap.prepare();
  // 菜品照片（docs/29 §P7 需求 16）：选图后复制进应用文档目录
  // `localfit_ai/dish_images/`，库里只存路径。store 同时被仓库持有
  //（替换/删除菜品时清理旧文件），所以先建 store 再建仓库。
  const dishImageStore = DishImageStore(idGenerator: UuidV7Generator());
  final clearAllLocalData = createAppDataClearer(
    database,
    temporaryMealImageStore: temporaryMealImageStore,
    menuRawContentStore: menuRawContentStore,
    apiKeyStore: apiKeyStore,
    chatImageStore: chatImageStore,
    dishImageStore: dishImageStore,
  );
  // 「清空内置食物」（docs/32 §4 T11 需求 75）：只删内置行，与上面那条
  // 「清除所有数据」是两件事，所以是两个用例实例。
  final clearBuiltinFoods = ClearBuiltinFoods(database);
  final loadIntakeTrend = LoadIntakeTrend(
    database: database,
    mealRepository: mealRepository,
    clock: const SystemAppClock(),
  );
  final exportCsvFiles = ExportCsvFiles(
    database: database,
    fileStore: backupFileStore,
  );
  final hasProfile = await database.hasProfile();
  final completeOnboarding = CompleteOnboarding(
    database: database,
    idGenerator: const UuidV7Generator(),
    clock: const SystemAppClock(),
  );
  final prepareMealImage = PrepareMealImage(
    picker: ImagePickerMealImagePicker(),
    processor: const IsolateMealImageProcessor(),
    store: temporaryMealImageStore,
  );
  final recognizeConfirmedMealImage = RecognizeConfirmedMealImage(
    provider: OpenAiCompatibleMealRecognitionProvider(
      dio: Dio(),
      configurationReader: aiProviderSettingsStore,
      apiKeyStore: apiKeyStore,
      imageBytesReader: const FilePreparedMealImageBytesReader(),
    ),
  );
  final loadMealRecognitionDisclosure = LoadMealRecognitionDisclosure(
    configurationReader: aiProviderSettingsStore,
  );
  final resolveMealScanCandidates = ResolveMealScanCandidates(
    foodSearch: foodRepository,
    createFood: foodRepository.create,
  );
  // 饮食偏好 / 过敏原回避（docs/28 §6.4 落地记录）：唯一的写入者是对话命令
  // `constraints.set`，活跃读取者是 `DailyPlanEngine`，所以随 recipe_planning/
  // 删除后搬到 daily_plan/ 保留。
  final planningConstraintsRepository = PlanningConstraintsRepository(
    database: database,
    clock: const SystemAppClock(),
  );
  // 长期记忆（docs/38 S11）：与对话命令 `memory.remember/forget`、快照注入、
  // 「我的 → AI 记忆」页共用同一仓储；数据只在本机。
  // 向量索引在 semanticRuntime 构造后接上（见下）——判重与整理建议要用它。
  late final AiMemoryRepository aiMemoryRepository;
  // 食堂目录（3.0）：地点 → 窗口 → 菜品 三级自建结构。营养由 AI 分析后
  // 写证据表。
  final catalogShards = await _catalogShardPaths(supportDir);
  final pickDishImage = PickDishImage(
    store: dishImageStore,
    clock: const SystemAppClock(),
  );
  // 食堂目录 ⇄ 菜品库是**同一个库**（2026-10-24 用户：「加入菜品目录里不能
  // 自动加入菜品库吗…我希望他们就是一个库，不要分开，不要自己加入」）：
  // 菜品一写出营养就自动进菜品库，改名/改份量跟着更新，删菜/删窗口/删地点
  // 跟着删。钩子在组合根注入——数据层不认识 nutrition，分层门禁不破。
  // `late final` + 闭包向后引用：仓储先建、服务后建，钩子在**写入发生那一刻**
  // 才解引用（那时赋值已完成）。
  late final AddCanteenDishesToLibrary addCanteenDishesToLibrary;
  final canteenRepository = CanteenRepository(
    database: database,
    idGenerator: const UuidV7Generator(),
    clock: const SystemAppClock(),
    dishImageStore: dishImageStore,
    onDishUpserted: (dishId) => addCanteenDishesToLibrary.syncDish(dishId),
    onDishDeleted: (dishId) => addCanteenDishesToLibrary.removeDish(dishId),
  );

  // 索引协调器（docs/39 §5.2）：段级失效映射 + orphan sweep + 重建。
  final indexCoordinator = IndexCoordinator(database: database);
  // 端上语义检索（docs/39 §4–§5）：模型随包（`assets/models/`）、
  // 长驻单 worker、intra-op=1；**任何一步失败都降级**到关键词 + 标签。
  final semanticRuntime = SemanticRuntime(
    // **worker isolate**（docs/39 §4.3）：模型加载与推理都不在主 isolate——
    // 2026-10-19 实测主 isolate 加载 24MB 权重会把低内存设备界面拖死。
    // WorkerEmbeddingEngine 惰性 spawn；空闲预热见下方首帧之后。
    database: database,
    engineFactory: () async => WorkerEmbeddingEngine(),
    settings: AppSettingsRepository(database: database),
  );
  aiMemoryRepository = AiMemoryRepository(
    database: database,
    clock: const SystemAppClock(),
    idGenerator: const UuidV7Generator(),
    // 记忆向量（docs/43 B6）：写入判重 / 整理建议 / 恢复后重建。
    vectorIndex: semanticRuntime,
  );
  // 任务队列底座（G16）与整理工具（P4）：打标/合并建议/反馈/恢复后重建。
  final backgroundJobRepository = BackgroundJobRepository(
    database: database,
    clock: const SystemAppClock(),
    idGenerator: const UuidV7Generator(),
  );
  final foodDataMaintenance = FoodDataMaintenance(
    database: database,
    canteen: canteenRepository,
    jobs: backgroundJobRepository,
    semantic: semanticRuntime,
    memoryRepository: aiMemoryRepository,
  );
  // 索引调度接设备状态（docs/43 A3）：充电 + 空闲才跑队列，可暂停、断点续跑。
  // **2026-10-20 用户拍板 D1**：加 battery_plus（实现 A，默认装配）——
  // 真实充电判定；`isIdle` 仍是「应用在后台」。平台异常（无电池）按未充电
  // 处理，调试面板如实标注「已接线」。
  late final JobDispatchController jobDispatch;
  final jobScheduler = JobScheduler(
    repository: backgroundJobRepository,
    // 每次 tick/每条领取前现读：生命周期与充电状态会变，不能构造时缓存。
    conditions: () => jobDispatch.conditions,
    handlers: defaultJobHandlers(maintenance: foodDataMaintenance),
  );
  jobDispatch = JobDispatchController(
    scheduler: jobScheduler,
    power: BatteryPlusPowerStateSource(battery: Battery()),
  );
  final restoreEncryptedBackup = RestoreEncryptedBackup(
    database: database,
    fileStore: backupFileStore,
    // G14：恢复后派生索引已被清空，入队重建任务（幂等）。
    onRestored: () => foodDataMaintenance.enqueueIndexRebuildAfterRestore(),
  );
  // 食堂目录 → 菜品库（菜单页唯一主来源，docs/21 §5.3 写入路径 1）。
  // 2026-10-24 起它不再由用户点按钮触发，而是挂在 `canteenRepository` 的
  // 同步钩子上自动跑（见上面的 `onDishUpserted` / `onDishDeleted`）。
  addCanteenDishesToLibrary = AddCanteenDishesToLibrary(
    dishLibrary: dishLibraryRepository,
    canteen: canteenRepository,
  );
  // 2026-10-24 升级补齐：把**已经分析过**的食堂菜按来源键写进菜品库——老库里
  // 那些「分析过但没手动加入菜品库」的菜，更新后立刻出现在菜单页。幂等（按
  // 来源 upsert），KV 打标只跑一次；失败不打标，下次启动重试。
  unawaited(() async {
    try {
      if (await appSettingsRepository.getBool(kCanteenLibraryBackfillKey)) {
        return;
      }
      final result = await addCanteenDishesToLibrary.backfillAll();
      await appSettingsRepository.setBool(
        kCanteenLibraryBackfillKey,
        value: true,
      );
      debugPrint(
        '食堂菜→菜品库补齐：写入/更新 ${result.written} 道，'
        '跳过（未分析）${result.skipped} 道。',
      );
    } on Object catch (error) {
      debugPrint('食堂菜→菜品库补齐失败（下次启动重试）：$error');
    }
  }());

  // 食物库搜索（2.0-6f）：主库 LIKE + 分片 FTS5 合并（目录未就位时为空）。
  // 详情（2.0-1j）：主库条目读主库，未导入的目录条目读分片（份量/修订/证据）。
  final foodLibraryController = FoodLibraryController(
    repository: foodRepository,
    catalogSearch: CatalogSearchService(shardPaths: catalogShards),
    detailLoader: FoodDetailLoader(
      databaseDetails: FoodDetailRepository(database: database),
      shardDetails: CatalogShardDetailSource(shardPaths: catalogShards),
    ),
  );
  // 建食堂菜时的「参考食物库」匹配（docs/40 §3.1 / docs/41 §7）：本地确定性
  // 打分与菜单匹配 UI 同一套（MenuItemMatcher），只补上每 100g 数值。
  final foodReferenceService = FoodReferenceService(
    database: database,
    matcher: MenuItemMatcher(database: database, shardPaths: catalogShards),
  );
  // 2026-10-24（`docs/56` R4 / `docs/58` B6 R4-4b）：「下一餐」整族退役——
  // `NextMealDecisionController` + `DailyPlanEngine` 的装配一并删除。
  // `daily_plans` / `daily_plan_slots` / `daily_plan_candidates` 三张表**保留
  // 不删**（schema 冻结；文档写退役横幅，留将来复用/备份兼容）。
  // `PlanningConstraintsRepository` 与写入路径保留，当前无本地读取者。
  //
  // 断网证据（2026-10-21 裁决 D-2）：不加 connectivity 依赖，用真实的
  // 连接失败记录判「无网」；AI 对话页据此显示提示条。
  final aiConnectivity = AiConnectivityMonitor();
  // docs/32 §4 T6c（D6）：旧任务执行管线已退役——画廊不再构造
  // 「卡内生成/草案/确认写入」的执行体（生成改在 AI 对话里发生，
  // 写库统一走 chat-edit 命令层）。六张启动卡的展示规格集中在
  // `aiStarters`（ai_starter.dart）；prompt 模板已迁到
  // `ai_workbench_prompt_templates.dart`（正文逐字不动）。

  // 目录导入放到首帧之后：失败不影响启动（原因进 bootstrap.lastResult，
  // 设置页「食物目录」那节据此给出可行动提示与重试入口）。
  unawaited(catalogBootstrap.importAvailable());
  // 随包用户食物库（2026-10-20 用户拍板内置）：首帧后台幂等导入，
  // 失败不影响启动（用户可随时走「食物库 → 导入」手动补）。
  // 导入完成后接一次**存量归一化**（ADR-037）：按随包资产把名称格式、十档分类、
  // 别名补齐；顺序必须在这里——归一化按「旧身份」匹配，先入库才能对上。
  unawaited(
    importBundledUserFoods(
          database: database,
          idGenerator: const UuidV7Generator(),
          clock: const SystemAppClock(),
        )
        .then(
          (_) => FoodLibraryNormalizer(
            database: database,
            idGenerator: const UuidV7Generator(),
            clock: const SystemAppClock(),
          ).runIfNeeded(),
        )
        .then(
          (result) => debugPrint(
            '食物库归一化：更新 ${result.foodsUpdated} 条、别名 '
            '${result.aliasesInserted} 条（跳过 ${result.skipped}）。',
          ),
          onError: (Object error) {
            debugPrint('随包食物库导入/归一化失败（可手动导入）：$error');
          },
        ),
  );
  // 派生索引的启动自愈（docs/39 §5.2）：清掉指向已删除 owner 的索引行。
  // 首帧之后跑、失败不影响启动（派生数据烂掉是「慢慢变差」，不该挡住启动）。
  // 语义引擎**不在启动时预热**（2026-10-19 设备实测）：预热会把 24MB 权重与
  // ORT session 建在**主 isolate** 上，在低内存设备（2.5GB AVD，已用 swap）
  // 上直接把界面拖住——点击全部丢失，导航切不动。改成**首次使用时惰性加载**
  // （打开搜索调试面板或第一次发消息时），失败照旧降级为关键词 + 标签。
  //
  // 【已知偏差，如实登记】docs/39 §4.3 要求「长驻单 worker isolate」，当前
  // 实现仍在主 isolate；这是下一步要补的（isolate 化之后才谈得上真正的
  // 「空闲预热」）。风险与复现见 docs/evidence/2026-10-18-p1-p2-p3-delivery.md。
  // 语义 worker 的空闲预热（docs/39 §4.3）：首帧之后 spawn isolate 并加载模型。
  // 加载发生在 **worker isolate**，主线程零负担；失败只记日志——检索照常走
  // 关键词 + 标签（降级）。
  WidgetsBinding.instance.addPostFrameCallback((_) {
    // 索引队列调度（docs/43 A3）：首帧之后启动，前台不领取新任务；
    // 15 分钟兜底 tick。实现 B 不判断充电（见 power_state_source.dart）。
    jobDispatch.start();
    unawaited(
      semanticRuntime.warmUp().catchError((Object error) {
        debugPrint('语义 worker 预热失败（检索会降级为关键词+标签）：$error');
      }),
    );
  });
  unawaited(
    indexCoordinator
        .sweepOrphans()
        .then((swept) {
          if (swept > 0) {
            debugPrint('索引自愈：清理 $swept 条悬空索引行');
          }
        })
        .catchError((Object error) {
          debugPrint('索引自愈失败（不影响启动）：$error');
        }),
  );

  // AI 对话通用编辑（docs/23）：快照 + 协议 + 执行器都只聚合既有仓储，
  // 不新建任何写路径；用户点「应用」前不落任何库。
  final chatEditCoordinator = ChatEditCoordinator(
    contextBuilder: DriftChatEditContextLoader(
      database: database,
      clock: const SystemAppClock(),
      mealRepository: mealRepository,
      dishLibraryRepository: dishLibraryRepository,
      semantic: semanticRuntime,
      waterRepository: waterRepository,
      canteenRepository: canteenRepository,
      workoutPlanRepository: workoutPlanRepository,
      workoutSessionRepository: workoutSessionRepository,
      // 发送前食物库预检索（docs/40 §2.4）：top3 注入「食物库参考」段。
      foodPreviewSearch: FoodPreviewSearch(database: database),
      // 段级失效映射（docs/39 §5.2）：写一餐只重算餐记录段。
      indexCoordinator: indexCoordinator,
    ),
    executor: RepositoryChatEditExecutor(
      ChatEditServices(
        database: database,
        clock: const SystemAppClock(),
        foodRepository: foodRepository,
        mealRepository: mealRepository,
        dishLibraryRepository: dishLibraryRepository,
        waterRepository: waterRepository,
        measurementRepository: measurementRepository,
        planningConstraintsRepository: planningConstraintsRepository,
        canteenRepository: canteenRepository,
        workoutPlanRepository: workoutPlanRepository,
        workoutSessionRepository: workoutSessionRepository,
        exerciseRepository: exerciseRepository,
        profileIdentityRepository: profileIdentityRepository,
        updateWaterTargetMl: updateWaterTargetMl,
        stepsRepository: stepsRepository,
        aiMemoryRepository: aiMemoryRepository,
        idGenerator: const UuidV7Generator(),
        // `nutritionFrom='food'` 的本地匹配（docs/43 B10）。
        foodReferenceService: foodReferenceService,
      ),
    ),
  );

  runApp(
    ProviderScope(
      child: LocalFitApp(
        initialLocation: hasProfile
            ? AppRoutes.dashboard
            : AppRoutes.onboarding,
        completeOnboarding: completeOnboarding.call,
        foodRepository: foodRepository,
        mealRepository: mealRepository,
        canteenRepository: canteenRepository,
        foodReferenceService: foodReferenceService,
        planningConstraintsRepository: planningConstraintsRepository,
        pickDishImage: pickDishImage.pick,
        foodLibraryController: foodLibraryController,
        scaleSync: scaleSync,
        measurementRepository: measurementRepository,
        waterRepository: waterRepository,
        stepsRepository: stepsRepository,
        updateWaterTargetMl: updateWaterTargetMl,
        loadIntakeTrend: loadIntakeTrend,
        dishLibraryRepository: dishLibraryRepository,
        semanticRuntime: semanticRuntime,
        aiConnectivity: aiConnectivity,
        addDishToMeal: addDishToMeal,
        prepareMealImage: prepareMealImage,
        recognizeConfirmedMealImage: recognizeConfirmedMealImage,
        loadMealRecognitionDisclosure: loadMealRecognitionDisclosure,
        resolveMealScanCandidates: resolveMealScanCandidates,
        exerciseRepository: exerciseRepository,
        workoutPlanRepository: workoutPlanRepository,
        workoutPlanProvider: workoutPlanProvider,
        loadWorkoutPlanDisclosure: loadWorkoutPlanDisclosure,
        createEncryptedBackup: createEncryptedBackup,
        restoreEncryptedBackup: restoreEncryptedBackup,
        clearAllLocalData: clearAllLocalData,
        clearBuiltinFoods: clearBuiltinFoods,
        exportCsvFiles: exportCsvFiles,
        catalogBootstrap: catalogBootstrap,
        workoutSessionRepository: workoutSessionRepository,
        aiProviderSettingsStore: aiProviderSettingsStore,
        endpointProbe: aiEndpointProbe,
        apiKeyStore: apiKeyStore,
        profileIdentityRepository: profileIdentityRepository,
        profileOverviewLoader: profileOverviewLoader,
        appSettingsRepository: appSettingsRepository,
        aiMemoryRepository: aiMemoryRepository,
        backgroundJobRepository: backgroundJobRepository,
        conversationService: aiConversationService,
        chatEdit: chatEditCoordinator,
        conversationMessageRepository: conversationMessageRepository,
        pickChatImage: pickChatImage,
        chatImageStore: chatImageStore,
        appVersion: _appVersion,
      ),
    ),
  );
}

/// 应用全清组合：头像与默认选图落在同一私有目录，不能只删除档案行。
ClearAllLocalData createAppDataClearer(
  AppDatabase database, {
  required TemporaryMealImageStore temporaryMealImageStore,
  required MenuRawContentStore menuRawContentStore,
  required AiApiKeyStoreRef apiKeyStore,
  required ChatImageStore chatImageStore,
  // 2026-10-20 审查 RV-P1-08：**required** 而不是可选——可选参数漏传正是
  // 上一轮「全清后菜品照片还在」的根因；让编译器守住装配。
  required DishImageStoreRef dishImageStore,
  // 单测注入用：默认仍是真实实现（头像目录走 path_provider）。
  AvatarImageStoreRef? avatarImageStore,
}) => ClearAllLocalData(
  database,
  temporaryMealImageStore: temporaryMealImageStore,
  menuRawContentStore: menuRawContentStore,
  apiKeyStore: apiKeyStore,
  chatImageStore: chatImageStore,
  dishImageStore: dishImageStore,
  avatarImageStore:
      avatarImageStore ??
      const AvatarImageStore(idGenerator: UuidV7Generator()),
);

/// 应用版本号（docs/21 §5.6 📱 关于）。
///
/// 不引 package_info 插件：那要走平台通道，为了一行版本文字多一个原生依赖
/// 不划算。改成构建期注入 `--dart-define=APP_VERSION=`；未注入时返回 null，
/// 设置页会如实显示「版本未知」而不是编一个号冒充事实。
const String _appVersionDefine = String.fromEnvironment('APP_VERSION');
const String? _appVersion = _appVersionDefine == '' ? null : _appVersionDefine;

/// 读取随包目录资产。
///
/// 分片不是全部随包（docs/07 §5.6：只有 core 分片装进包里），所以「这个键不存在」
/// 是正常返回值而不是异常——探到 null 就说明这一片属于按需分发的那批。
Future<Uint8List?> _loadBundledCatalogAsset(String key) async {
  try {
    final data = await rootBundle.load(key);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } on FlutterError {
    return null;
  }
}

/// 应用支持目录下 `catalog/` 中的只读分片文件（ETL 产物，按文件名排序）。
/// 目录不存在或无 .sqlite 文件时返回空列表（目录未就位 → 仅主库搜索）。
Future<List<String>> _catalogShardPaths(String supportDir) async {
  final dir = Directory('$supportDir${Platform.pathSeparator}catalog');
  if (!await dir.exists()) return const [];
  final entries = await dir.list().where((e) => e is File).toList();
  final paths =
      entries.map((e) => e.path).where((p) => p.endsWith('.sqlite')).toList()
        ..sort();
  return paths;
}
