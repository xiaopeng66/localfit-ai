import 'package:drift/drift.dart';

// 索引策略（Phase 6 性能切片）：只给代码审查确认的高频查询 where 列建索引；
// 主键列（id）自带唯一索引，不再重复。迁移 v10 为既有库补建这些索引。
// 命名约定：`idx_<表>_<列>`。

class AiProviderConfigs extends Table {
  TextColumn get id => text()();
  TextColumn get baseUrl => text()();
  TextColumn get model => text()();

  /// 用户显式选择的供应商协议（docs/24 §2）。**可空**：v17 及以前的库没有
  /// 这一列，那些行是「从未选过协议」而不是「选过 chat」——读取侧一律按
  /// `AiProviderProtocol.fromStorage` 回落到 Chat Completions（旧行为），
  /// 不把「不知道」伪装成一次显式选择。
  TextColumn get protocol => text().nullable()();

  /// 推理开关（docs/29 §P4）。**可空**：v19 及以前的库没有这一列，那些行
  /// 是「从未选过」而不是「选过某档」——读取侧按
  /// `AiReasoningMode.fromStorage` 回落到「关闭推理」（产品默认档）。
  TextColumn get reasoning => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Profiles extends Table {
  TextColumn get id => text()();
  IntColumn get birthYear => integer().nullable()();
  TextColumn get biologicalSex => text().nullable()();
  RealColumn get heightCm => real().nullable()();
  TextColumn get activityLevel => text()();
  TextColumn get dietaryPreferencesJson =>
      text().withDefault(const Constant('[]'))();
  TextColumn get allergenAvoidancesJson =>
      text().withDefault(const Constant('[]'))();
  IntColumn get planningBudgetMinorUnits => integer().nullable()();
  TextColumn get planningBudgetCurrency => text().nullable()();
  IntColumn get maximumDraftDeclaredMinutes => integer().nullable()();
  BoolColumn get pantryCoverageEnabled =>
      boolean().withDefault(const Constant(false))();

  /// 昵称（docs/32 §3 D9，schema 23）：用户在身份卡里自填，1–20 字符，
  /// null = 没填过（界面回退「Fit」，**不编造名字**）。
  TextColumn get displayName => text().nullable()();

  /// 头像文件路径（docs/32 §3 D9，schema 23）：指向应用文档目录 `avatar/`
  /// 下的副本。**只存路径，图片字节不进 `.lfb`**——恢复后若文件不存在，
  /// 界面回退首字母（如实限制，见 D9）。
  TextColumn get avatarPath => text().nullable()();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Goals extends Table {
  TextColumn get id => text()();
  TextColumn get profileId => text().references(Profiles, #id)();
  TextColumn get type => text()();
  RealColumn get targetWeightKg => real().nullable()();
  RealColumn get calorieMinKcal => real()();
  RealColumn get calorieMaxKcal => real()();
  DateTimeColumn get effectiveFrom => dateTime()();
  TextColumn get status => text().withDefault(const Constant('active'))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class DailyTargets extends Table {
  TextColumn get id => text()();
  TextColumn get goalId => text().references(Goals, #id)();
  TextColumn get effectiveDate => text()();
  RealColumn get calorieMinKcal => real()();
  RealColumn get calorieMaxKcal => real()();
  RealColumn get proteinMinGrams => real()();
  RealColumn get proteinMaxGrams => real()();
  RealColumn get carbsMinGrams => real()();
  RealColumn get carbsMaxGrams => real()();
  RealColumn get fatMinGrams => real()();
  RealColumn get fatMaxGrams => real()();
  RealColumn get waterTargetMl => real().withDefault(const Constant(2000))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

// watchWeightOverview 按 localDate 过滤 + 排序。
@TableIndex(name: 'idx_measurements_local_date', columns: {#localDate})
class Measurements extends Table {
  TextColumn get id => text()();
  TextColumn get profileId => text().references(Profiles, #id)();
  TextColumn get localDate => text()();
  RealColumn get weightKg => real()();

  // schema 22（docs/31 S2，需求 45/46）删掉了 bodyFatPercent 与 muscleMassKg
  // 两列。它们由 schema 17 加入（docs/21 §7.2「体成分不单独建表」），
  // 2026-10-09 用户原话「添加的弹窗卡片去掉体脂率和肌肉量」+「其他所有地方
  // 有关于这两个数据的都删掉」⇒ 连数据一起删。
  // **旧 `.lfb` 包里的这两个键在恢复时被静默忽略**（drift `fromJson` 只读
  // 认得的列，无列级版本门）——这是删数据的事实，已钉在
  // `app_database_v22_migration_test.dart` 里。
  TextColumn get source => text().withDefault(const Constant('manual'))();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Foods extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get brand => text().nullable()();
  RealColumn get defaultServingGrams => real().nullable()();
  RealColumn get kcalPer100g => real()();
  RealColumn get proteinPer100g => real()();
  RealColumn get carbsPer100g => real()();
  RealColumn get fatPer100g => real()();
  TextColumn get source => text()();
  BoolColumn get isUserCreated =>
      boolean().withDefault(const Constant(false))();
  // schema 22（docs/31 S2，需求 50）删掉了 constraintKnowledge /
  // dietaryLabelsJson / allergensJson 三列（schema 5 加入）。用户原话
  // 「过敏原与饮食标签这个删掉」。**profiles 侧的过敏回避仍在**
  // （`Profiles.allergenAvoidancesJson` 未动，见 docs/31 §2 D5）；
  // 代价是每日计划 solver 的 `allergen_conflict` 从此没有食物侧输入源。
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  // 2.0-1 目录分层增量列：v11 起 canonical food 携带数据状态与来源许可。
  // state: verified | estimated | incomplete | user_created | stale。
  // 旧行（种子与用户自建）在迁移 v11 中按 isUserCreated 回填。
  TextColumn get state => text().withDefault(const Constant('verified'))();
  TextColumn get locale => text().nullable()();
  TextColumn get category => text().nullable()();
  IntColumn get sourceVersion => integer().nullable()();
  TextColumn get licenseStatus =>
      text().withDefault(const Constant('unknown'))();

  // 2026-10-21（ADR-036，用户「存储格式定死」）：21 列契约的 15 列与
  // categoryGroup/categorySub 两列已由 schema 30 DROP——分类是唯一指标
  // （category 10 枚举），导入期翻译见 FoodCategory._libraryGroups。

  @override
  Set<Column<Object>> get primaryKey => {id};
}

// 搜索与菜单匹配别名；alias 不计入 canonical 数量。
@TableIndex(name: 'idx_food_aliases_food_id', columns: {#foodId})
class FoodAliases extends Table {
  TextColumn get id => text()();
  TextColumn get foodId =>
      text().references(Foods, #id, onDelete: KeyAction.cascade)();
  // 规范化（去空白、统一全半角、小写）后的可搜索文本。
  TextColumn get normalizedText => text()();
  TextColumn get language => text().withDefault(const Constant('zh-CN'))();
  // alias type: translation | nickname | pinyin | brand | category | manual。
  TextColumn get aliasType => text()();
  TextColumn get source => text()();
  RealColumn get confidence => real().withDefault(const Constant(1))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

// 同一食物不同来源/时间的营养修订；严格营养计算只接受四项齐全的 revision。
@TableIndex(
  name: 'idx_food_nutrition_revisions_food_id',
  columns: {#foodId, #revisionNumber},
  unique: true,
)
class FoodNutritionRevisions extends Table {
  TextColumn get id => text()();
  TextColumn get foodId =>
      text().references(Foods, #id, onDelete: KeyAction.cascade)();
  IntColumn get revisionNumber => integer()();
  // 四项均可空：incomplete 条目可入库但不得参与严格营养计算。
  RealColumn get kcalPer100g => real().nullable()();
  RealColumn get proteinGPer100g => real().nullable()();
  RealColumn get carbsGPer100g => real().nullable()();
  RealColumn get fatGPer100g => real().nullable()();
  TextColumn get sourceEvidenceId => text().nullable()();
  TextColumn get qualityStatus => text().withDefault(const Constant('ok'))();
  DateTimeColumn get validFrom => dateTime().nullable()();
  DateTimeColumn get validTo => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

// 个、碗、勺、袋等份量换算。
@TableIndex(name: 'idx_food_portions_food_id', columns: {#foodId})
class FoodPortions extends Table {
  TextColumn get id => text()();
  TextColumn get foodId =>
      text().references(Foods, #id, onDelete: KeyAction.cascade)();
  TextColumn get name => text()();
  RealColumn get grams => real()();
  TextColumn get locale => text().withDefault(const Constant('zh-CN'))();
  TextColumn get source => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

// 目录级来源证据：许可证、采集时间、转换版本与原始记录哈希。
class FoodEvidence extends Table {
  TextColumn get id => text()();
  TextColumn get sourceId => text()();
  TextColumn get license => text()();
  TextColumn get attribution => text().nullable()();
  DateTimeColumn get retrievedAt => dateTime()();
  TextColumn get transformVersion => text()();
  TextColumn get qualityStatus => text()();
  TextColumn get recordHash => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

// 目录分片导入任务；校验失败/中断必须保留旧目录并可回滚。
@TableIndex(name: 'idx_food_import_jobs_status', columns: {#status})
class FoodImportJobs extends Table {
  TextColumn get id => text()();
  IntColumn get catalogVersion => integer()();
  // status: pending | validating | importing | completed | failed | rolled_back。
  TextColumn get status => text()();
  IntColumn get totalShards => integer()();
  IntColumn get importedShards => integer().withDefault(const Constant(0))();
  IntColumn get errorCount => integer().withDefault(const Constant(0))();
  TextColumn get manifestHash => text()();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get finishedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Exercises extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get muscleGroup => text()();
  TextColumn get equipment => text()();
  TextColumn get source => text()();

  /// 难度（docs/21 §5.5「难度」）。旧行保持 null＝未标注，读取侧
  /// 显示「难度未知」，绝不拿默认值冒充事实。
  TextColumn get difficulty => text().nullable()();

  /// 常用度 0–100（docs/21 §5.5「常用度」）。null 同上＝未标注。
  IntColumn get popularity => integer().nullable()();
  BoolColumn get isUserCreated =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class WorkoutPlans extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get status => text().withDefault(const Constant('active'))();
  TextColumn get source => text()();
  IntColumn get revision => integer().withDefault(const Constant(1))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class WorkoutDays extends Table {
  TextColumn get id => text()();
  TextColumn get planId =>
      text().references(WorkoutPlans, #id, onDelete: KeyAction.cascade)();
  IntColumn get weekday => integer()();
  IntColumn get sortOrder => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class PlannedExercises extends Table {
  TextColumn get id => text()();
  TextColumn get dayId =>
      text().references(WorkoutDays, #id, onDelete: KeyAction.cascade)();
  TextColumn get exerciseId => text().references(Exercises, #id)();
  IntColumn get sortOrder => integer()();
  IntColumn get targetSets => integer()();
  IntColumn get targetReps => integer()();
  RealColumn get targetWeightKg => real().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

// 训练历史按 status + localDate 过滤（趋势关联、容量统计）。
@TableIndex(
  name: 'idx_workout_sessions_status_local_date',
  columns: {#status, #localDate},
)
class WorkoutSessions extends Table {
  TextColumn get id => text()();
  TextColumn get planId => text().nullable().references(
    WorkoutPlans,
    #id,
    onDelete: KeyAction.setNull,
  )();
  TextColumn get localDate => text()();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get finishedAt => dateTime().nullable()();
  TextColumn get status => text().withDefault(const Constant('active'))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

// 会话详情按 sessionId 装载组数。
@TableIndex(name: 'idx_workout_sets_session_id', columns: {#sessionId})
class WorkoutSets extends Table {
  TextColumn get id => text()();
  TextColumn get sessionId =>
      text().references(WorkoutSessions, #id, onDelete: KeyAction.cascade)();
  TextColumn get plannedExerciseId => text().nullable().references(
    PlannedExercises,
    #id,
    onDelete: KeyAction.setNull,
  )();
  TextColumn get exerciseId => text().references(Exercises, #id)();
  IntColumn get sortOrder => integer()();
  RealColumn get weightKg => real()();
  IntColumn get reps => integer()();
  RealColumn get rpe => real().nullable()();
  DateTimeColumn get completedAt => dateTime()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

// 今日页 watchForDate / 趋势与汇总按 localDate 过滤。
@TableIndex(name: 'idx_meals_local_date', columns: {#localDate})
class Meals extends Table {
  TextColumn get id => text()();
  TextColumn get localDate => text()();
  TextColumn get slot => text()();
  DateTimeColumn get eatenAt => dateTime()();
  TextColumn get notes => text().nullable()();
  TextColumn get source => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

// 餐食装载条目与今日营养汇总子查询按 mealId 过滤。
@TableIndex(name: 'idx_meal_items_meal_id', columns: {#mealId})
class MealItems extends Table {
  TextColumn get id => text()();
  TextColumn get mealId =>
      text().references(Meals, #id, onDelete: KeyAction.cascade)();
  TextColumn get foodId => text().nullable().references(Foods, #id)();
  TextColumn get foodNameSnapshot => text()();
  RealColumn get grams => real()();
  RealColumn get kcalSnapshot => real()();
  RealColumn get proteinSnapshot => real()();
  RealColumn get carbsSnapshot => real()();
  RealColumn get fatSnapshot => real()();
  TextColumn get cookingMethod => text().nullable()();
  RealColumn get estimateMinGrams => real().nullable()();
  RealColumn get estimateMaxGrams => real().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  // ── schema 28（docs/40 §2.1 / §3，纯加法）─────────────────────────────
  /// `food` | `dish` | `menu_item` | `scan` | `manual`（历史回填：foodId
  /// 非空 → food，否则 manual）。
  TextColumn get sourceType => text().withDefault(const Constant('manual'))();

  /// foods.id / dish_library.id / menu_items.id；无来源时 null。
  TextColumn get sourceId => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

// ---------------------------------------------------------------------------
// 2.0-3 Menu v1（规范第 6/8 节）：校园菜单分层。菜单快照是来源内容，
// 不能直接变成 foods 或 meals；原文与规范化实体分开。
// ---------------------------------------------------------------------------

/// 用户命名的学校/园区；不保存精确坐标。
class CampusProfiles extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get timezone =>
      text().withDefault(const Constant('Asia/Shanghai'))();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// 食堂/餐厅。
@TableIndex(name: 'idx_venues_campus_id', columns: {#campusId})
class Venues extends Table {
  TextColumn get id => text()();
  TextColumn get campusId =>
      text().references(CampusProfiles, #id, onDelete: KeyAction.cascade)();
  TextColumn get name => text()();
  TextColumn get aliasesJson => text().withDefault(const Constant('[]'))();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// 菜单来源：类型、用户输入的 URL/文件引用、许可证、是否允许保存原文。
/// sourceType: manual | pasted_text | file_txt_csv_json | pdf | image_ocr | url
class MenuSources extends Table {
  TextColumn get id => text()();
  TextColumn get venueId =>
      text().references(Venues, #id, onDelete: KeyAction.cascade)();
  TextColumn get sourceType => text()();
  TextColumn get reference => text().nullable()();
  TextColumn get license => text().nullable()();
  BoolColumn get allowRawContent =>
      boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// 不可变菜单快照版本。status: active | superseded | expired。
@TableIndex(
  name: 'idx_menu_snapshots_venue_date',
  columns: {#venueId, #businessDate},
)
class MenuSnapshots extends Table {
  TextColumn get id => text()();
  TextColumn get sourceId =>
      text().references(MenuSources, #id, onDelete: KeyAction.cascade)();
  TextColumn get venueId => text().references(Venues, #id)();
  TextColumn get businessDate => text()();
  TextColumn get contentHash => text()();
  // 原文存应用私有目录；此处只保存相对路径与摘要（docs/07 §6.1）。
  TextColumn get rawContentPath => text().nullable()();
  TextColumn get rawContentHash => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('active'))();
  DateTimeColumn get importedAt => dateTime()();
  DateTimeColumn get expiresAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// 窗口/档口与营业时段（星期规则：0=周日 … 6=周六）。
@TableIndex(name: 'idx_menu_services_snapshot_id', columns: {#snapshotId})
class MenuServices extends Table {
  TextColumn get id => text()();
  TextColumn get snapshotId =>
      text().references(MenuSnapshots, #id, onDelete: KeyAction.cascade)();
  TextColumn get name => text()();
  TextColumn get openTime => text()();
  TextColumn get closeTime => text()();
  // 逗号分隔星期集合，如 "1,2,3,4,5"；空 = 每日。
  TextColumn get weekdays => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// 菜品。evidenceGrade: A|B|C|D（docs/07 §6.4）。
/// itemStatus: matched | estimated | unresolved | expired | closed。
///
/// `imagePath`（docs/29 §P7 需求 16，schema 21 迁移补列）：菜品照片的本地
/// 路径，存的是**应用文档目录** `localfit_ai/dish_images/` 里的私有副本
/// （选图后复制再存路径，FileChatImageStore 同款）；旧行保持 null＝无照片，
/// 读取侧按「无图」渲染序号圆，不伪造占位照片。
@TableIndex(name: 'idx_menu_items_service_id', columns: {#serviceId})
class MenuItems extends Table {
  TextColumn get id => text()();
  TextColumn get serviceId =>
      text().references(MenuServices, #id, onDelete: KeyAction.cascade)();
  TextColumn get displayName => text()();
  TextColumn get stationName => text().nullable()();
  // 2026-10-16（用户：「把食堂菜品添加的时候的价格删掉（包括其他所有关于这个
  // 食堂菜品的价格分析和功能，没有用了）」）：`price_minor` 整列退役，v26
  // 迁移里 DROP。菜单项的其它事实（名称/档口/照片/营养/状态）不受影响。
  TextColumn get rawText => text().nullable()();
  TextColumn get imagePath => text().nullable()();
  TextColumn get evidenceGrade => text().withDefault(const Constant('D'))();
  TextColumn get itemStatus =>
      text().withDefault(const Constant('unresolved'))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  // ── schema 28（docs/40 §2.1 / §2.5，纯加法）───────────────────────────
  /// 这个窗口一份大概多少克（可空；分析时估或用户填）。
  RealColumn get servingGrams => real().nullable()();

  /// 结构化标签 JSON（清淡/辣/汤/面/油炸/餐次…，docs/39 §8）。
  TextColumn get tagsJson => text().withDefault(const Constant('[]'))();

  /// 配料 JSON：`[{name, source, confidence}]`，source = user|ai|dictionary。
  /// **过敏原不单独存，由食材推导**（docs/40 §2.5）。
  TextColumn get ingredientsJson => text().withDefault(const Constant('[]'))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// 菜单项 ↔ 本地 food 匹配候选与确认状态。
/// matchStatus: suggested | confirmed | rejected。
@TableIndex(name: 'idx_menu_item_matches_item_id', columns: {#menuItemId})
class MenuItemFoodMatches extends Table {
  TextColumn get id => text()();
  TextColumn get menuItemId =>
      text().references(MenuItems, #id, onDelete: KeyAction.cascade)();
  TextColumn get foodId => text().references(Foods, #id)();
  RealColumn get confidence => real().withDefault(const Constant(0.5))();
  TextColumn get matchStatus =>
      text().withDefault(const Constant('suggested'))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// 菜单项营养证据（标签、来源、估算范围、原文、置信度）。
///
/// 区间与代表值分开存：kcalMin/kcalMax 是分析给出的估算范围（可为空），
/// kcalPer100g 等四项是**每 100g 的代表值**，推荐与展示只用后者。
/// 只有区间的历史行（v15 之前写入）代表值留空，读取侧按「无营养」处理，
/// 不拿区间中点冒充事实。
@TableIndex(name: 'idx_menu_item_evidence_item_id', columns: {#menuItemId})
class MenuItemNutritionEvidence extends Table {
  TextColumn get id => text()();
  TextColumn get menuItemId =>
      text().references(MenuItems, #id, onDelete: KeyAction.cascade)();
  TextColumn get grade => text()();
  TextColumn get origin => text()();
  RealColumn get kcalMin => real().nullable()();
  RealColumn get kcalMax => real().nullable()();
  RealColumn get kcalPer100g => real().nullable()();
  RealColumn get proteinPer100g => real().nullable()();
  RealColumn get carbsPer100g => real().nullable()();
  RealColumn get fatPer100g => real().nullable()();
  TextColumn get sourceText => text().nullable()();
  RealColumn get confidence => real().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// 菜单导入任务。status: pending | parsing | validating | completed | failed | rolled_back。
@TableIndex(name: 'idx_menu_import_jobs_status', columns: {#status})
class MenuImportJobs extends Table {
  TextColumn get id => text()();
  TextColumn get sourceId =>
      text().references(MenuSources, #id, onDelete: KeyAction.cascade)();
  TextColumn get status => text()();
  IntColumn get parsedItemCount => integer().withDefault(const Constant(0))();
  IntColumn get parseErrorCount => integer().withDefault(const Constant(0))();
  IntColumn get manualFixCount => integer().withDefault(const Constant(0))();
  TextColumn get snapshotId => text().nullable()();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get finishedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

// ── 2.0-4 Planning v1（docs/07 §6/8：availability、daily plans）──────────
// 推荐由本地确定性 solver 产出；daily_plans 是推荐/安排层，不进营养
// 统计；确认加入计划才写 confirmed，记录已吃必须走 meals 流程。

/// 用户手动填写的可去餐时段 / 课程活动阻塞（docs/07 §7.2）。不自动读取
/// 日历；localDate 空 + weekdays 非空 = 每周重复块。
@TableIndex(name: 'idx_availability_windows_date', columns: {#localDate})
class AvailabilityWindows extends Table {
  TextColumn get id => text()();
  // 空字符串 = 适用于所有校区。
  TextColumn get campusId => text().withDefault(const Constant(''))();
  TextColumn get localDate => text().nullable()();
  // 逗号分隔星期集合（0=周日…6=周六）；localDate 为空时生效。
  TextColumn get weekdays => text().withDefault(const Constant(''))();
  // 当日分钟数（0..1440）。
  IntColumn get startMinute => integer()();
  IntColumn get endMinute => integer()();
  // kind: dining | blocked。
  TextColumn get kind => text()();
  TextColumn get label => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// 一天的计划（推荐/安排层）。status: draft | confirmed。
@TableIndex(name: 'idx_daily_plans_date', columns: {#localDate})
class DailyPlans extends Table {
  TextColumn get id => text()();
  TextColumn get localDate => text()();
  TextColumn get status => text().withDefault(const Constant('draft'))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// 计划内餐次行。targetArrivalMinute = 用户目标到达时刻（可空）。
@TableIndex(name: 'idx_daily_plan_slots_plan_id', columns: {#planId})
class DailyPlanSlots extends Table {
  TextColumn get id => text()();
  TextColumn get planId =>
      text().references(DailyPlans, #id, onDelete: KeyAction.cascade)();
  // slot: breakfast | lunch | dinner | snack。
  TextColumn get slot => text()();
  IntColumn get targetArrivalMinute => integer().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// 候选行：菜单项/食物统一 contract（kind+refId）。营养是本地
/// 匹配结果的估算快照，不读模型自报数字。
/// candidateStatus: suggested | confirmed | rejected。
@TableIndex(name: 'idx_daily_plan_candidates_slot_id', columns: {#slotId})
class DailyPlanCandidates extends Table {
  TextColumn get id => text()();
  TextColumn get slotId =>
      text().references(DailyPlanSlots, #id, onDelete: KeyAction.cascade)();
  // kind: menu_item | food。老库可能仍有 `recipe` 行（食谱整族已于 docs/28
  // W4 下线），列本身是自由文本，读取侧兼容即可。
  TextColumn get kind => text()();
  TextColumn get refId => text()();
  TextColumn get displayName => text()();
  TextColumn get venueId => text().nullable()();
  RealColumn get estimatedKcal => real().nullable()();
  RealColumn get estimatedProteinG => real().nullable()();
  RealColumn get estimatedCarbsG => real().nullable()();
  RealColumn get estimatedFatG => real().nullable()();
  TextColumn get evidenceGrade => text().nullable()();
  RealColumn get confidence => real().withDefault(const Constant(0.5))();
  // 本地 solver 归一化总分（0..1，越高越优）。
  RealColumn get score => real().withDefault(const Constant(0))();
  // 硬约束原因码 JSON 数组，如 ["snapshot_expired","allergen_conflict"]。
  TextColumn get reasonCodesJson => text().withDefault(const Constant('[]'))();
  // 无解/未过约束时的原因（可空 = 通过全部硬约束）。
  TextColumn get unsatisfiedReason => text().nullable()();
  TextColumn get candidateStatus =>
      text().withDefault(const Constant('suggested'))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

// ── schema 17 新增域（docs/21 §7.2）──────────────────────────────────────
// 迁移只增不改不删；旧行语义见各列注释。

/// 饮水摄入（今日页饮水卡）。`localDate` 建索引（§7.2 明示）。
@TableIndex(name: 'idx_water_intakes_local_date', columns: {#localDate})
class WaterIntakes extends Table {
  TextColumn get id => text()();
  TextColumn get localDate => text()();
  // 毫升（正数；一次记录一杯/一瓶的量）。
  RealColumn get amountMl => real()();
  DateTimeColumn get recordedAt => dateTime()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

// ── schema 21 预置（docs/29 §P7，功能在 P9 接线）────────────────────────

/// 每日本机步数：一天一行，`localDate` 唯一（当日重复同步按行覆盖）。
///
/// schema 21 随菜品图片一次迁移建表（docs/29 §P7 原文写 19→20，被 P4 的
/// reasoning 列占用后顺延为 20→21）；写入侧在 P9（MethodChannel
/// `localfit/steps`）。`source` 让「健康平台聚合」与「本机传感器累计」
/// 可区分，P9 的统计口径不混；`steps` 非负由写入侧保证。
@DataClassName('StepsDailyEntry')
@TableIndex(name: 'idx_steps_daily_local_date', columns: {#localDate})
class StepsDaily extends Table {
  TextColumn get id => text()();
  TextColumn get localDate => text().unique()();
  IntColumn get steps => integer()();
  TextColumn get source => text()();
  DateTimeColumn get recordedAt => dateTime()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// 成就与解锁态（我的页成就区）。
///
/// `key` 唯一；解锁条件与进度口径见 docs/21 §7.2 的四行定义表
/// （streak-7 / nutrition-master / workout-athlete / healthy-diet），
/// 实施时不得再发明。`unlockedAt` 一经写入不可回退（成就是对历史
/// 事实的确认，不是当前状态的镜像）。
class Achievements extends Table {
  TextColumn get id => text()();
  TextColumn get key => text().unique()();
  DateTimeColumn get unlockedAt => dateTime().nullable()();

  /// 0..1；未解锁时按进度展示，解锁后恒为 1。
  RealColumn get progress => real().withDefault(const Constant(0.0))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// 菜品库（菜单页数据源）：含微量营养素与营养师点评。
/// 图片占位渐变按 mealSlot/营养构成稳定映射（docs/21 §2.5），无照片时
/// 绝不伪造菜品照片（§6.1）。
@DataClassName('DishLibraryEntry')
class DishLibrary extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get imagePath => text().nullable()();

  /// 早餐 / 午餐 / 晚餐 / 加餐（设计稿 mealSlot）。
  TextColumn get mealSlot => text()();

  /// 供应时段（校园窗口语义，如 06:30-09:30）；非食堂菜可空。
  TextColumn get servingWindow => text().nullable()();
  BoolColumn get isHot => boolean().withDefault(const Constant(false))();
  RealColumn get kcal => real()();
  RealColumn get proteinG => real()();
  RealColumn get carbsG => real()();
  RealColumn get fatG => real()();
  RealColumn get fiberG => real().nullable()();
  RealColumn get sodiumMg => real().nullable()();
  RealColumn get vitaminDMcg => real().nullable()();
  TextColumn get source => text()();
  TextColumn get comment => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  // ── schema 28（docs/40 §2.1 / docs/41 §11，纯加法）────────────────────
  /// 一份多少克。「每份」四个营养值是 `per100g × servingGrams / 100` 的
  /// 结果（nutritionBasis 记录口径）；历史行回填 100 且 basisAssumed=1。
  RealColumn get servingGrams => real().nullable()();

  /// `perServing` | `per100g`（历史行回填 `perServing`）。
  TextColumn get nutritionBasis =>
      text().withDefault(const Constant('perServing'))();

  /// 份量是否是假设值（UI 显示「按 100g 估算」，不假装知道份量）。
  BoolColumn get basisAssumed => boolean().withDefault(const Constant(false))();

  /// `canteen` | `food` | `manual` | `imported`；null = 历史行未知。
  TextColumn get sourceType => text().nullable()();

  /// menuItemId / foodId（**不加外键**，允许来源删除后悬空）。
  TextColumn get sourceId => text().nullable()();

  /// 来源最后一次营养变更时间（用于「食堂营养有更新」提示）。
  DateTimeColumn get sourceUpdatedAt => dateTime().nullable()();

  /// 用户改过营养/份量：同步时只提示、不覆盖。
  BoolColumn get userEdited => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// 心血管处方（docs/21 §7.2：与力量组次不同型，单独建表而非塞进
/// PlannedExercises 的数值列）。一条处方一个 kind：配速 / 阻力 / 时长。
class CardioPrescriptions extends Table {
  TextColumn get id => text()();
  TextColumn get plannedExerciseId =>
      text().references(PlannedExercises, #id)();

  /// pace | resistance | duration。
  TextColumn get kind => text()();
  RealColumn get value => real()();
  TextColumn get unit => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// 拍照识别结果快照（拍照页历史与 AI 对话引用）。
/// ingredients/macro 为 JSON 字符串（数组/对象），由读取侧严格解析。
class RecognitionResults extends Table {
  TextColumn get id => text()();
  TextColumn get mealId => text().nullable().references(Meals, #id)();
  DateTimeColumn get capturedAt => dateTime()();
  TextColumn get dishName => text()();

  /// 0..1 模型置信度；UI 层按证据分级展示，不直接裸露数值。
  RealColumn get confidence => real()();
  TextColumn get imagePath => text()();
  RealColumn get estimatedKcal => real()();
  TextColumn get advice => text().nullable()();
  TextColumn get ingredientsJson => text()();
  TextColumn get macroJson => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// AI 聊天记录（AI 对话页，docs/21 §5.7）。
@TableIndex(name: 'idx_conversation_messages_session_id', columns: {#sessionId})
class ConversationMessages extends Table {
  TextColumn get id => text()();
  TextColumn get sessionId => text()();

  /// user | assistant。
  TextColumn get role => text()();

  /// 文本正文。列名按 §7.2 契约存为 `text`（`text` 是 drift 保留方法名，
  /// Dart 侧 getter 用 textContent）。
  TextColumn get textContent => text().named('text')();
  DateTimeColumn get createdAt => dateTime()();
  TextColumn get imagePath => text().nullable()();

  /// 语音列**已停用但保留**（P10 需求 36 / 裁决 D8，2026-10-07）：语音输入
  /// 整族删除，但历史库里可能已有语音消息——删列会丢老数据，读回逻辑仍靠
  /// `durationMs` 推导 `kind=voice`（见仓储层）。**不再有新代码写入它们**。
  TextColumn get audioPath => text().nullable()();
  IntColumn get durationMs => integer().nullable()();

  /// sending | sent | failed（乐观 UI 状态，docs/21 §5.8.1）。
  TextColumn get status => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// 键值设置（「自动本地备份」开关等，docs/21 §7.2 末行）。
class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

/// AI 长期记忆（schema 27，docs/38 §4）：一句话一条，跨会话注入。
///
/// * `text` 是列名（`text` 是 drift 的保留方法名，Dart 侧 getter 用
///   `textContent`，与 `ConversationMessages` 同一写法）。
/// * `kind`/`domain` 存枚举名（`preference`/`nutrition`…），渲染时翻成中文。
/// * `status` 的 `archived` 预留给后续老化（v1 只写 `active`、页面只做硬删）。
/// * 与结构化事实的分工见 `ai_memory.dart` 顶部注释与协议规则 11：
///   **能落结构化字段的（过敏/目标/身体资料/计划）一律不进这张表。**
@DataClassName('AiMemoryRow')
@TableIndex(name: 'idx_ai_memories_status', columns: {#status})
class AiMemories extends Table {
  TextColumn get id => text()();
  TextColumn get textContent => text().named('text')();
  TextColumn get kind => text()();
  TextColumn get domain => text()();
  TextColumn get tagsJson => text().withDefault(const Constant('[]'))();
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();
  TextColumn get source => text()();
  TextColumn get status => text().withDefault(const Constant('active'))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  // ── schema 28（docs/41 §11，2026-10-18 纯加法）─────────────────────────
  // 治理与注入排序用：重要性（0–100，默认 50）、最近使用、使用次数。
  IntColumn get importance => integer().withDefault(const Constant(50))();
  DateTimeColumn get lastUsedAt => dateTime().nullable()();
  IntColumn get useCount => integer().withDefault(const Constant(0))();

  /// 改口留痕：旧条指向新条（检索只看 `active`；页面可看历史/撤销）。
  TextColumn get supersededById => text().nullable()();

  /// `kind=context` 的临时近况（默认 30 天）；到期**提议**归档，不自动删。
  DateTimeColumn get expiresAt => dateTime().nullable()();

  /// 来源消息（`memory.remember` 从哪条对话来）——来源追溯用。
  TextColumn get sourceMessageId => text().nullable()();

  /// 实体链接（docs/41 G19）：`dish` | `food` | `venue`，让「不吃香菜」
  /// 能 join 到食材/菜品；没有对应实体时为 null。
  TextColumn get linkedEntityType => text().nullable()();
  TextColumn get linkedEntityId => text().nullable()();

  /// 一跳关系（可选，JSON 字符串数组）；v1 只存不用。
  TextColumn get relatedIds => text().nullable()();

  // ── schema 29（S14，2026-10-19 用户授权）─────────────────────────────
  /// 时间语义（G23）：这条从何时成立。
  ///
  /// 历史行在迁移 29 里回填成 `created_at`（不凭空造「现在」）；新写入取
  /// 写入时刻。null 只可能出现在迁移未跑到的极旧库。
  DateTimeColumn get validFrom => dateTime().nullable()();

  /// 这条到何时不再成立（改口时闭合）；null = 仍然有效。
  ///
  /// 与 `supersededById` 同时写：`supersededById` 说明「被谁取代」，
  /// `validTo` 说明「从哪一刻起不再成立」——「当时是什么」查询只读后者。
  DateTimeColumn get validTo => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

// ---------------------------------------------------------------------------
// schema 28（docs/39 §5.1 / docs/41 §11，2026-10-18）：检索索引与任务队列。
// ---------------------------------------------------------------------------

/// 派生向量索引（**不进备份**：恢复后后台重建）。
///
/// 一行 = 一个 owner（记忆/菜品/食物/食堂菜）在当前 `modelId` 下的向量。
/// `textHash` 用于跳过未变更文本；`modelId` 变 ⇒ 全量重建（向量空间不可混用）。
/// 主键 `(ownerType, ownerId)`：同一 owner 只保留当前 profile 的一份向量。
@TableIndex(name: 'idx_embedding_model', columns: {#modelId})
class EmbeddingIndex extends Table {
  /// `memory` | `menuItem` | `dish` | `food`。
  TextColumn get ownerType => text()();
  TextColumn get ownerId => text()();

  /// 例如 `bge-small-zh-v1.5-int8-v1`；带版本，换模型即全量重建。
  TextColumn get modelId => text()();

  /// 向量维度（bge-small-zh 为 512）。
  IntColumn get dim => integer()();

  /// `f32` | `i8` | `b1`（量化档；读取侧按它解释 BLOB）。
  TextColumn get encoding => text()();

  /// sha256(索引文本)：文本没变就不重算。
  TextColumn get textHash => text()();

  /// 向量本体（按 [encoding] 解释）。
  BlobColumn get vector => blob()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {ownerType, ownerId};
}

/// 通用后台任务队列（docs/41 G16，服务菜品分析/配料打标/会话结束提炼/索引重建）。
///
/// 状态机：`pending` → `processing` →（成功删除 / 失败 `failed` 可重试）。
/// `attempts` 与 `lastError` 让失败可见；`payload` 是任务自己的 JSON。
/// **断点续跑**靠「重新把 failed/pending 视作可跑」+ `updatedAt` 记录心跳。
/// **不进备份**（派生状态）。
@TableIndex(name: 'idx_background_jobs_state_type', columns: {#state, #type})
class BackgroundJobs extends Table {
  TextColumn get id => text()();

  /// `dishAnalysis` | `ingredientTagging` | `sessionExtract` | `indexRebuild` …
  TextColumn get type => text()();

  /// `pending` | `processing` | `failed`。
  TextColumn get state => text().withDefault(const Constant('pending'))();

  IntColumn get attempts => integer().withDefault(const Constant(0))();

  TextColumn get lastError => text().nullable()();

  /// 任务参数（JSON）。
  TextColumn get payloadJson => text().withDefault(const Constant('{}'))();

  /// 幂等键（如 `dishAnalysis:<menuItemId>`）：同键不重复入队。
  TextColumn get dedupeKey => text().nullable()();

  /// 进度 0–100（可空＝未知）。
  IntColumn get progress => integer().nullable()();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
