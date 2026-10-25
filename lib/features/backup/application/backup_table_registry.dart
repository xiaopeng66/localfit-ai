import 'package:drift/drift.dart';
import 'package:localfit_ai/core/time/local_date.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/ai_memory/domain/ai_memory.dart';

/// 备份里的一张逻辑表：JSON key、drift 表名（与 schema 对账用）、
/// 行读取与写入闭包。
///
/// [BackupTableSpec.validateRow] 是**字段值**校验：JSON 形状之外的第二道
/// 闸。读取侧会严格解析的文本列（ISO 本地日）在写库前逐行校验，脏值
/// 整单拒绝（事务回滚）——否则恢复「成功」后进页面就是红屏
/// （docs/11 §3-F BUG-15 的根本条件）。
final class BackupTableSpec {
  const BackupTableSpec({
    required this.key,
    required this.tableName,
    required this.read,
    required this.write,
    required this.optional,
    this.validateRow,
  });

  /// 备份文档里的表名（1.x 起沿用的 snake_case key）。
  final String key;

  /// drift 的实际表名（`TableInfo.actualTableName`）。备份覆盖测试用它
  /// 与 schema 的全部逻辑表对账，新增表漏进清单会被这条断言挡住。
  final String tableName;

  final Future<List<Map<String, dynamic>>> Function(AppDatabase database) read;
  final Future<void> Function(AppDatabase database, Map<String, Object?> row)
  write;

  /// 1.x 的备份包没有这张表（2.0 起新增）。恢复时缺失视为空表——旧
  /// `.lfb` 必须还能恢复；1.x 就有的表缺失才是真的损坏备份。
  final bool optional;

  /// 逐行字段值校验（null = 该表没有需要值校验的列）；返回违规描述，
  /// null = 本行通过。
  final String? Function(Map<String, Object?> row)? validateRow;
}

/// 校验给定 JSON 键都是有效的 ISO 本地日（yyyy-MM-dd、真实日历日期）。
///
/// [nullable] 为 true 时缺列/空值放行（对应 `.nullable()` 的列）。
/// 判据来自共享的 [isValidIsoLocalDate]，与读取侧的解析判据同源。
String? Function(Map<String, Object?> row) _isoDateFields(
  Set<String> jsonKeys, {
  bool nullable = false,
}) => (row) {
  for (final key in jsonKeys) {
    final value = row[key];
    if (value == null) {
      if (nullable) continue;
      return '$key 缺失';
    }
    if (value is! String || !isValidIsoLocalDate(value)) {
      return '$key 不是有效的本地日期（yyyy-MM-dd）';
    }
  }
  return null;
};

/// 校验给定 JSON 键都是「不逃出应用私有目录」的本地路径。
///
/// 这些列存的是聊天图片/语音与菜单原文的本地路径，读取侧直接 `File(path)`。
/// 备份包是用户从文件系统里挑的——一个被篡改的包塞进 `../../…` 就能让恢复
/// 之后的应用去读私有目录之外的位置（文件布局属实现细节，恢复侧不该因此
/// 信任这一列）。判据：非空、不含 `..` 段、不含 NUL；绝对与相对路径都合法
/// （2.0-7b 之前的行按绝对路径入库，见 FileMenuRawContentStore.resolve）。
String? Function(Map<String, Object?> row) _pathFields(
  Set<String> jsonKeys, {
  bool nullable = false,
}) => (row) {
  for (final key in jsonKeys) {
    final value = row[key];
    if (value == null) {
      if (nullable) continue;
      return '$key 缺失';
    }
    if (value is! String) return '$key 不是文本路径';
    if (value.isEmpty) return '$key 为空路径';
    if (value.contains('\u0000')) return '$key 含有非法字符';
    if (value.split(RegExp(r'[\\/]')).contains('..')) {
      return '$key 含路径回退段（..）';
    }
  }
  return null;
};

/// 组合多个逐行校验器：返回第一个非空违规描述。
String? Function(Map<String, Object?> row) _all(
  List<String? Function(Map<String, Object?> row)> validators,
) => (row) {
  for (final validate in validators) {
    final violation = validate(row);
    if (violation != null) return violation;
  }
  return null;
};

/// 备份清单的**单一事实源**：JSON 导出与 `.lfb` 恢复共用同一份顺序，
/// 两边不再各自维护手写清单而漏掉新表（docs/03 §12 的要求）。
///
/// 顺序必须外键安全（父表在前）：恢复是「清空 + 逐表插入」，任何子行
/// 早于父行都会撞外键。新增表时只改这里，并在 `export_restore_test.dart`
/// 的往返用例里补断言。
final class LocalFitBackupTables {
  const LocalFitBackupTables(this.database);

  final AppDatabase database;

  List<BackupTableSpec> get all => [
    // ── 1.x 表：1.x 的备份包必须全部存在 ───────────────────────────
    _table(key: 'profiles', table: database.profiles, from: Profile.fromJson),
    _table(key: 'goals', table: database.goals, from: Goal.fromJson),
    _table(
      key: 'daily_targets',
      table: database.dailyTargets,
      from: DailyTarget.fromJson,
      validateRow: _isoDateFields({'effectiveDate'}),
    ),
    _table(
      key: 'measurements',
      table: database.measurements,
      from: Measurement.fromJson,
      validateRow: _isoDateFields({'localDate'}),
    ),
    _table(key: 'foods', table: database.foods, from: Food.fromJson),
    _table(
      key: 'meals',
      table: database.meals,
      from: Meal.fromJson,
      validateRow: _isoDateFields({'localDate'}),
    ),
    _table(
      key: 'meal_items',
      table: database.mealItems,
      from: MealItem.fromJson,
      // schema 28 新增（非空）：旧包没有这一列；旧行的语义就是「手动记的」。
      defaults: const {'sourceType': 'manual'},
    ),
    _table(
      key: 'exercises',
      table: database.exercises,
      from: Exercise.fromJson,
    ),
    _table(
      key: 'workout_plans',
      table: database.workoutPlans,
      from: WorkoutPlan.fromJson,
    ),
    _table(
      key: 'workout_days',
      table: database.workoutDays,
      from: WorkoutDay.fromJson,
    ),
    _table(
      key: 'planned_exercises',
      table: database.plannedExercises,
      from: PlannedExercise.fromJson,
    ),
    _table(
      key: 'workout_sessions',
      table: database.workoutSessions,
      from: WorkoutSession.fromJson,
      validateRow: _isoDateFields({'localDate'}),
    ),
    _table(
      key: 'workout_sets',
      table: database.workoutSets,
      from: WorkoutSet.fromJson,
    ),
    _table(
      key: 'ai_provider_configs',
      table: database.aiProviderConfigs,
      from: AiProviderConfig.fromJson,
    ),
    // ── 2.0 食物目录分层（schema v11）：foods 之后 ──────────────────
    _table(
      key: 'food_aliases',
      table: database.foodAliases,
      from: FoodAliase.fromJson,
      optional: true,
    ),
    _table(
      key: 'food_nutrition_revisions',
      table: database.foodNutritionRevisions,
      from: FoodNutritionRevision.fromJson,
      optional: true,
    ),
    _table(
      key: 'food_portions',
      table: database.foodPortions,
      from: FoodPortion.fromJson,
      optional: true,
    ),
    _table(
      key: 'food_evidence',
      table: database.foodEvidence,
      from: FoodEvidenceData.fromJson,
      optional: true,
    ),
    _table(
      key: 'food_import_jobs',
      table: database.foodImportJobs,
      from: FoodImportJob.fromJson,
      optional: true,
    ),
    // ── 2.0 校园菜单（schema v12）：campus → item 顺序 ──────────────
    _table(
      key: 'campus_profiles',
      table: database.campusProfiles,
      from: CampusProfile.fromJson,
      optional: true,
    ),
    _table(
      key: 'venues',
      table: database.venues,
      from: Venue.fromJson,
      optional: true,
    ),
    _table(
      key: 'menu_sources',
      table: database.menuSources,
      from: MenuSource.fromJson,
      optional: true,
    ),
    _table(
      key: 'menu_snapshots',
      table: database.menuSnapshots,
      from: MenuSnapshot.fromJson,
      optional: true,
      validateRow: _all([
        _isoDateFields({'businessDate'}),
        // 原文路径读取侧直接开文件（FileMenuRawContentStore.resolve）。
        _pathFields({'rawContentPath'}, nullable: true),
      ]),
    ),
    _table(
      key: 'menu_services',
      table: database.menuServices,
      from: MenuService.fromJson,
      optional: true,
    ),
    _table(
      key: 'menu_items',
      table: database.menuItems,
      from: MenuItem.fromJson,
      optional: true,
      // imagePath（docs/29 §P7，schema 21）与 dish_library 同款：存的是
      // 应用文档目录里的私有副本路径，读取侧直接 File(path)。
      validateRow: _pathFields({'imagePath'}, nullable: true),
    ),
    _table(
      key: 'menu_item_food_matches',
      table: database.menuItemFoodMatches,
      from: MenuItemFoodMatche.fromJson,
      optional: true,
    ),
    _table(
      key: 'menu_item_nutrition_evidence',
      table: database.menuItemNutritionEvidence,
      from: MenuItemNutritionEvidenceData.fromJson,
      optional: true,
    ),
    _table(
      key: 'menu_import_jobs',
      table: database.menuImportJobs,
      from: MenuImportJob.fromJson,
      optional: true,
    ),
    // ── 2.0 每日计划（schema v13）：计划 → 餐次 → 候选 ──────────────
    _table(
      key: 'availability_windows',
      table: database.availabilityWindows,
      from: AvailabilityWindow.fromJson,
      optional: true,
      // localDate 是可空列（为空时按 weekdays 生效）。
      validateRow: _isoDateFields({'localDate'}, nullable: true),
    ),
    _table(
      key: 'daily_plans',
      table: database.dailyPlans,
      from: DailyPlan.fromJson,
      optional: true,
      validateRow: _isoDateFields({'localDate'}),
    ),
    _table(
      key: 'daily_plan_slots',
      table: database.dailyPlanSlots,
      from: DailyPlanSlot.fromJson,
      optional: true,
    ),
    _table(
      key: 'daily_plan_candidates',
      table: database.dailyPlanCandidates,
      from: DailyPlanCandidate.fromJson,
      optional: true,
    ),
    // ── schema 17 新增域（docs/21 §7.2）─────────────────────────────────
    _table(
      key: 'water_intakes',
      table: database.waterIntakes,
      from: WaterIntake.fromJson,
      optional: true,
      validateRow: _isoDateFields({'localDate'}),
    ),
    // ── schema 21 预置（docs/29 §P7）：每日本机步数，P9 接功能 ──────────
    _table(
      key: 'steps_daily',
      table: database.stepsDaily,
      from: StepsDailyEntry.fromJson,
      optional: true,
      validateRow: _isoDateFields({'localDate'}),
    ),
    // ── schema 27（docs/38 S11）：AI 长期记忆 ──────────────────────
    // `optional: true`：旧备份没有这个键 ⇒ 恢复成空表，旧包照常可用；
    // 新包里的记忆在旧版本上被忽略（恢复侧对未知键本就静默跳过）。
    _table(
      key: 'ai_memories',
      table: database.aiMemories,
      from: AiMemoryRow.fromJson,
      optional: true,
      // 2026-10-21 RV-P2-18：恢复是另一条写 ai_memories 的路——敏感红线
      // 必须同样生效（否则改过的 .lfb 能把身份证号写进会注入 prompt 的表）。
      validateRow: (row) {
        final text = row['textContent'];
        if (text is! String) return 'textContent 不是文本';
        final reason = aiMemorySensitiveReason(text);
        return reason == null ? null : '疑似敏感信息（$reason）';
      },
      // schema 27/28 新增（非空）：重要性默认 50、使用次数 0。
      defaults: const {'importance': 50, 'useCount': 0},
    ),
    _table(
      key: 'achievements',
      table: database.achievements,
      from: Achievement.fromJson,
      optional: true,
    ),
    _table(
      key: 'dish_library',
      table: database.dishLibrary,
      from: DishLibraryEntry.fromJson,
      optional: true,
      validateRow: _pathFields({'imagePath'}, nullable: true),
      // schema 28 新增（非空）：旧行没有份量口径 ⇒ perServing + 假设值。
      defaults: const {
        'nutritionBasis': 'perServing',
        'basisAssumed': true,
        'userEdited': false,
      },
    ),
    _table(
      key: 'cardio_prescriptions',
      table: database.cardioPrescriptions,
      from: CardioPrescription.fromJson,
      optional: true,
    ),
    _table(
      key: 'recognition_results',
      table: database.recognitionResults,
      from: RecognitionResult.fromJson,
      optional: true,
      validateRow: _pathFields({'imagePath'}),
    ),
    _table(
      key: 'conversation_messages',
      table: database.conversationMessages,
      from: ConversationMessage.fromJson,
      optional: true,
      // 图片是本地文件路径；audioPath 是 P10 前旧语音消息的遗留列
      // （D8 只读兼容），备份/恢复必须照常往返，聊天页读不到就给占位。
      validateRow: _pathFields({'imagePath', 'audioPath'}, nullable: true),
    ),
    _table(
      key: 'app_settings',
      table: database.appSettings,
      from: AppSetting.fromJson,
      optional: true,
    ),
  ];

  BackupTableSpec _table<T extends Table, R extends DataClass>({
    required String key,
    required TableInfo<T, R> table,
    required R Function(Map<String, Object?>) from,
    bool optional = false,
    String? Function(Map<String, Object?> row)? validateRow,

    /// 后加的非空列在旧包里不存在；这里给默认值（RV-P1-01）。
    ///
    /// **为什么在注册表而不是生成的 `fromJson`**：`fromJson` 是
    /// build_runner 产物，下一次生成会被覆盖；备份兼容性属于恢复语义，
    /// 必须留在手写代码里。
    Map<String, Object?> defaults = const {},
  }) => BackupTableSpec(
    key: key,
    tableName: table.actualTableName,
    read: (database) async => [
      for (final row in await database.select(table).get()) row.toJson(),
    ],
    // drift 2.30 的 `DataClass` 不带类型参数，而 `insert` 收 `Insertable<R>`：
    // 生成的每张表的行类都实现 `Insertable<自己>`，所以这个下转型是
    // 有检查且必定成功的（不是 `dynamic` 逃逸）。
    write: (database, row) => database
        .into(table)
        .insert(from({...defaults, ...row}) as Insertable<R>),
    optional: optional,
    validateRow: validateRow,
  );
}
