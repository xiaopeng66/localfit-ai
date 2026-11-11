import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/ai_conversation/application/chat_edit_executor.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_command.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_registry.dart';
import 'package:localfit_ai/features/ai_memory/data/ai_memory_repository.dart';
import 'package:localfit_ai/features/campus_menus/application/food_reference_service.dart';
import 'package:localfit_ai/features/campus_menus/application/menu_item_matcher.dart';
import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart';
import 'package:localfit_ai/features/daily_plan/data/planning_constraints_repository.dart';
import 'package:localfit_ai/features/hydration/application/update_water_target_ml.dart';
import 'package:localfit_ai/features/hydration/data/water_repository.dart';
import 'package:localfit_ai/features/nutrition/application/food_catalog_service.dart';
import 'package:localfit_ai/features/nutrition/application/master_nutrition_sink_adapter.dart';
import 'package:localfit_ai/features/nutrition/data/dish_library_repository.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/nutrition_target_override.dart';
import 'package:localfit_ai/features/progress/data/measurement_repository.dart';
import 'package:localfit_ai/features/progress/data/steps_repository.dart';
import 'package:localfit_ai/features/settings/data/profile_identity_repository.dart';
import 'package:localfit_ai/features/training/data/exercise_repository.dart';
import 'package:localfit_ai/features/training/data/workout_plan_repository.dart';
import 'package:localfit_ai/features/training/data/workout_session_repository.dart';
import 'package:localfit_ai/features/training/domain/exercise_record.dart';
import 'package:localfit_ai/features/training/domain/workout_plan.dart';

/// 可编辑面 ↔ AI 命令的对接矩阵（2026-11-11 用户：「软件里所有可编辑内容
/// 都要对接 AI」）。UI 与 AI 的完整映射由
/// `test/app/ai_ui_capability_matrix_test.dart` 钉住；这里把**本轮补上的
/// 四个缺口**各跑一遍完整执行链：
///
/// * 食堂菜品改份量（`canteen.dish.update` 的 servingGrams）
/// * 训练条目改组次/重量（`plan.entry.update`，仓储新增 updateEntry）
/// * 动作库新建自定义动作（`exercise.create`，中文标签归一）
/// * 手动营养目标（`nutrition.target.set` / `.reset`，与现有目标合并）
void main() {
  final now = DateTime.utc(2026, 11, 11, 4);
  final registry = ChatEditCommandRegistry();

  late AppDatabase db;
  late RepositoryChatEditExecutor executor;
  late CanteenRepository canteen;
  late ExerciseRepository exercises;
  late WorkoutPlanRepository plans;
  late MealRepository meals;
  late String windowId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final ids = _SeqIds();
    final clock = FixedAppClock(now);
    final catalog = FoodCatalogService(
      database: db,
      idGenerator: ids,
      clock: clock,
    );
    canteen = CanteenRepository(
      database: db,
      idGenerator: ids,
      clock: clock,
      masterNutritionSink: CatalogMasterNutritionSink(catalog),
    );
    exercises = ExerciseRepository(
      database: db,
      idGenerator: ids,
      clock: clock,
    );
    plans = WorkoutPlanRepository(database: db, idGenerator: ids, clock: clock);
    meals = MealRepository(database: db, idGenerator: ids, clock: clock);
    final venueId = await canteen.createVenue(name: '东苑', campusName: '校本部');
    windowId = await canteen.createWindow(
      venueId: venueId,
      name: '一楼快餐窗口',
      openTime: '10:00',
      closeTime: '13:00',
    );
    executor = RepositoryChatEditExecutor(
      ChatEditServices(
        database: db,
        clock: clock,
        idGenerator: ids,
        foodRepository: FoodRepository(
          database: db,
          idGenerator: ids,
          clock: clock,
        ),
        foodCatalog: catalog,
        mealRepository: meals,
        dishLibraryRepository: DishLibraryRepository(
          database: db,
          idGenerator: ids,
          clock: clock,
        ),
        waterRepository: WaterRepository(
          database: db,
          idGenerator: ids,
          clock: clock,
        ),
        measurementRepository: MeasurementRepository(
          database: db,
          idGenerator: ids,
          clock: clock,
        ),
        planningConstraintsRepository: PlanningConstraintsRepository(
          database: db,
          clock: clock,
        ),
        canteenRepository: canteen,
        workoutPlanRepository: plans,
        workoutSessionRepository: WorkoutSessionRepository(
          database: db,
          idGenerator: ids,
          clock: clock,
        ),
        exerciseRepository: exercises,
        profileIdentityRepository: ProfileIdentityRepository(database: db),
        updateWaterTargetMl: UpdateWaterTargetMl(
          database: db,
          idGenerator: ids,
          clock: clock,
        ),
        stepsRepository: StepsRepository(
          database: db,
          channel: StepsChannel(),
          idGenerator: ids,
          clock: clock,
        ),
        aiMemoryRepository: AiMemoryRepository(
          database: db,
          clock: clock,
          idGenerator: ids,
        ),
        foodReferenceService: FoodReferenceService(
          database: db,
          matcher: MenuItemMatcher(database: db, shardPaths: const []),
        ),
      ),
    );
  });

  tearDown(() async => db.close());

  ChatEditCommand cmd(String action, Map<String, Object> args) {
    final spec = registry.specOf(action)!;
    return ChatEditCommand(spec: spec, args: validateChatEditArgs(spec, args));
  }

  test('「把小炒黄牛肉改成一份300g」→ 份量落成 known/user_input', () async {
    final dishId = await canteen.createDish(windowId: windowId, name: '小炒黄牛肉');
    final out = await executor.apply(
      cmd('canteen.dish.update', {'dishId': dishId, 'servingGrams': 300.0}),
    );
    expect(out.ok, isTrue, reason: out.message);
    expect(out.message, contains('一份 300g'));
    final row = await (db.select(
      db.menuItems,
    )..where((item) => item.id.equals(dishId))).getSingle();
    expect(row.servingGrams, closeTo(300, 1e-9));
    expect(row.servingGramsStatus, 'known');
    expect(row.servingGramsSource, 'user_input');
  });

  test('「把周一深蹲改成5组8次60kg」→ plan.entry.update 改一条', () async {
    final exercise = await exercises.create(
      const NewExercise(
        name: '杠铃深蹲',
        muscleGroup: MuscleGroup.legs,
        equipment: Equipment.barbell,
      ),
    );
    await plans.create(
      WorkoutPlanDraft(
        name: '增肌一周',
        days: [
          WorkoutPlanDayDraft(
            weekday: 1,
            entries: [
              PlannedExerciseDraft(
                exerciseId: exercise.id,
                targetSets: 3,
                targetReps: 10,
                targetWeightKg: 50,
              ),
            ],
          ),
        ],
      ),
    );
    final entry = (await db.select(db.plannedExercises).get()).single;

    final out = await executor.apply(
      cmd('plan.entry.update', {
        'entryId': entry.id,
        'sets': 5,
        'reps': 8,
        'weightKg': 60.0,
      }),
    );
    expect(out.ok, isTrue, reason: out.message);
    final after = (await db.select(db.plannedExercises).get()).single;
    expect(after.targetSets, 5);
    expect(after.targetReps, 8);
    expect(after.targetWeightKg, closeTo(60, 1e-9));
  });

  test('plan.entry.update：组数/次数/重量一个都不给 → 明确拒绝', () async {
    final exercise = await exercises.create(
      const NewExercise(
        name: '卧推',
        muscleGroup: MuscleGroup.chest,
        equipment: Equipment.barbell,
      ),
    );
    final planId = await plans.create(
      WorkoutPlanDraft(
        name: '推日',
        days: [
          WorkoutPlanDayDraft(
            weekday: 2,
            entries: [
              PlannedExerciseDraft(
                exerciseId: exercise.id,
                targetSets: 3,
                targetReps: 10,
              ),
            ],
          ),
        ],
      ),
    );
    final entry = (await db.select(db.plannedExercises).get()).single;
    final out = await executor.apply(
      cmd('plan.entry.update', {'entryId': entry.id}),
    );
    expect(out.ok, isFalse);
    expect(out.message, contains('至少要给一个'));
    expect(await plans.getById(planId), isNotNull, reason: '拒绝时计划原样保留');
  });

  test('「新建一个动作：保加利亚分腿蹲，腿，哑铃」→ 中文标签归一', () async {
    final out = await executor.apply(
      cmd('exercise.create', {
        'name': '保加利亚分腿蹲',
        'muscleGroup': '腿',
        'equipment': '哑铃',
      }),
    );
    expect(out.ok, isTrue, reason: out.message);
    final row = (await db.select(db.exercises).get()).last;
    expect(row.name, '保加利亚分腿蹲');
    expect(row.muscleGroup, 'legs');
    expect(row.equipment, 'dumbbell');
    expect(row.isUserCreated, isTrue);
  });

  test('exercise.create：肌群写错如实拒绝并列出可选值', () async {
    final out = await executor.apply(
      cmd('exercise.create', {
        'name': '神秘动作',
        'muscleGroup': '小腿',
        'equipment': '杠铃',
      }),
    );
    expect(out.ok, isFalse);
    expect(out.message, contains('胸/背/腿/肩/手臂/核心/全身'));
  });

  test('nutrition.target.set：第一次必须给全（fail-closed）', () async {
    final out = await executor.apply(
      cmd('nutrition.target.set', {'calorieMaxKcal': 1500.0}),
    );
    expect(out.ok, isFalse);
    expect(out.message, contains('一次给全'));
  });

  test('nutrition.target.set：给全后落手动目标；再次只改一项与现有值合并', () async {
    final full = await executor.apply(
      cmd('nutrition.target.set', {
        'calorieMinKcal': 1400.0,
        'calorieMaxKcal': 1560.0,
        'proteinMinGrams': 90.0,
        'proteinMaxGrams': 120.0,
        'carbsMinGrams': 140.0,
        'carbsMaxGrams': 180.0,
        'fatMinGrams': 40.0,
        'fatMaxGrams': 55.0,
      }),
    );
    expect(full.ok, isTrue, reason: full.message);
    final manual = await meals.readManualTargetForDate('2026-11-11');
    expect(manual!.calorieMaxKcal, closeTo(1560, 1e-9));

    final partial = await executor.apply(
      cmd('nutrition.target.set', {'calorieMaxKcal': 1500.0}),
    );
    expect(partial.ok, isTrue, reason: partial.message);
    final merged = await meals.readManualTargetForDate('2026-11-11');
    expect(merged!.calorieMaxKcal, closeTo(1500, 1e-9));
    expect(merged.calorieMinKcal, closeTo(1400, 1e-9), reason: '未给项沿用现有值');
    expect(merged.proteinMaxGrams, closeTo(120, 1e-9));
  });

  test('nutrition.target.set：下限大于上限如实拒绝且不落库', () async {
    final out = await executor.apply(
      cmd('nutrition.target.set', {
        'calorieMinKcal': 2000.0,
        'calorieMaxKcal': 1500.0,
        'proteinMinGrams': 90.0,
        'proteinMaxGrams': 120.0,
        'carbsMinGrams': 140.0,
        'carbsMaxGrams': 180.0,
        'fatMinGrams': 40.0,
        'fatMaxGrams': 55.0,
      }),
    );
    expect(out.ok, isFalse);
    expect(out.message, contains('下限不能大于上限'));
    expect(await meals.readManualTargetForDate('2026-11-11'), isNull);
  });

  // ---- 2026-11-11 复核：同名供应带来的三条静默写错风险 ----

  test('同窗口重名菜：建菜拒绝（否则按名定位会选中任意一条）', () async {
    await canteen.createDish(windowId: windowId, name: '番茄炒蛋');
    final out = await executor.apply(
      cmd('canteen.dish.create', {'window': windowId, 'name': '番茄炒蛋'}),
    );
    // AI 路径先按名去重，会「直接引用」——不允许再建第二行。
    expect(out.ok, isTrue, reason: out.message);
    expect(out.message, contains('已直接引用'));
    expect(await db.select(db.menuItems).get(), hasLength(1));
  });

  test('改名撞上同窗口已有名字：拒绝并说明（不造出两行同名）', () async {
    final first = await canteen.createDish(windowId: windowId, name: '土豆丝');
    await canteen.createDish(windowId: windowId, name: '醋溜土豆丝');
    final out = await executor.apply(
      cmd('canteen.dish.update', {'dishId': first, 'name': '醋溜土豆丝'}),
    );
    expect(out.ok, isFalse, reason: out.message);
    expect(out.message, contains('已有同名菜品'));
    final row = await (db.select(
      db.menuItems,
    )..where((item) => item.id.equals(first))).getSingle();
    expect(row.displayName, '土豆丝', reason: '拒绝时原名不变');
  });

  test('历史重名数据：按窗口+菜名写营养时拒绝，不静默选一条', () async {
    final a = await canteen.createDish(windowId: windowId, name: '红烧肉');
    // 直接插一行同名（模拟历史数据 / 旧版本留下的重复）。
    await db
        .into(db.menuItems)
        .insert(
          MenuItemsCompanion.insert(
            id: 'legacy-dup',
            serviceId: windowId,
            displayName: '红烧肉',
            createdAt: now,
            updatedAt: now,
          ),
        );
    final out = await executor.apply(
      cmd('canteen.dish.nutrition', {
        'window': windowId,
        'name': '红烧肉',
        'kcalPer100g': 300.0,
        'proteinPer100g': 15.0,
        'carbsPer100g': 5.0,
        'fatPer100g': 25.0,
      }),
    );
    expect(out.ok, isFalse, reason: out.message);
    expect(out.message, contains('同名菜品'));
    final untouched = await (db.select(
      db.menuItems,
    )..where((item) => item.id.equals(a))).getSingle();
    // 建菜时 evidenceGrade 本来就记 'C'（用户输入的事实），所以判据是
    // 「证据表没有任何一行、份量也没被写」。
    expect(untouched.servingGrams, isNull);
    expect(
      await db.select(db.menuItemNutritionEvidence).get(),
      isEmpty,
      reason: '拒绝时两条同名菜都不写',
    );
  });

  // ---- 2026-11-11 复核：两个底层逻辑缺陷的探针（先红后绿）----

  test('exercise.create：同名动作不能重复建（否则按名解析永久歧义）', () async {
    final first = await executor.apply(
      cmd('exercise.create', {
        'name': '卧推',
        'muscleGroup': '胸',
        'equipment': '杠铃',
      }),
    );
    expect(first.ok, isTrue, reason: first.message);
    final second = await executor.apply(
      cmd('exercise.create', {
        'name': '卧推',
        'muscleGroup': '胸',
        'equipment': '杠铃',
      }),
    );
    // 同名多行会让 _resolveExerciseByName 走「有多条同名记录，请先改名」
    // 分支——之后 set.log / 计划里的「卧推」全部失效。必须拒绝建重名。
    expect(second.ok, isFalse, reason: second.message);
    expect(second.message, contains('已有同名动作'));
    final rows = await (db.select(
      db.exercises,
    )..where((row) => row.name.equals('卧推'))).get();
    expect(rows, hasLength(1));
  });

  test('营养回执：份量状态 known 但克数缺失时不崩（脏数据防御）', () async {
    final dishId = await canteen.createDish(
      windowId: windowId,
      name: '脏数据菜',
      servingGrams: 200,
    );
    // 构造历史/异常数据：状态说 known，数值却是 null。
    await (db.update(db.menuItems)..where((row) => row.id.equals(dishId)))
        .write(const MenuItemsCompanion(servingGrams: Value(null)));
    final out = await executor.apply(
      cmd('canteen.dish.nutrition', {
        'dishId': dishId,
        'kcalPer100g': 100.0,
        'proteinPer100g': 5.0,
        'carbsPer100g': 10.0,
        'fatPer100g': 3.0,
        'servingGrams': 250.0,
      }),
    );
    expect(out.ok, isTrue, reason: out.message);
    final row = await (db.select(
      db.menuItems,
    )..where((item) => item.id.equals(dishId))).getSingle();
    expect(
      row.servingGrams,
      closeTo(250, 1e-9),
      reason: '无数值的 known 不算可信，应写入估算',
    );
  });

  test('nutrition.target.reset：清手动值', () async {
    await meals.saveManualTarget(
      NutritionTargetOverride(
        effectiveDate: '2026-11-11',
        calorieMinKcal: 1400,
        calorieMaxKcal: 1560,
        proteinMinGrams: 90,
        proteinMaxGrams: 120,
        carbsMinGrams: 140,
        carbsMaxGrams: 180,
        fatMinGrams: 40,
        fatMaxGrams: 55,
      ),
    );
    final out = await executor.apply(cmd('nutrition.target.reset', {}));
    expect(out.ok, isTrue, reason: out.message);
    expect(await meals.readManualTargetForDate('2026-11-11'), isNull);
  });
}

class _SeqIds implements IdGenerator {
  int _next = 0;

  @override
  String next() => 'id-${_next++}';
}
