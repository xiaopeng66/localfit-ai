import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/ai_conversation/application/chat_edit_executor.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_command.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_registry.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_repair.dart';
import 'package:localfit_ai/features/ai_memory/data/ai_memory_repository.dart';
import 'package:localfit_ai/features/campus_menus/application/food_reference_service.dart';
import 'package:localfit_ai/features/campus_menus/application/menu_item_matcher.dart';
import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart';
import 'package:localfit_ai/features/daily_plan/data/planning_constraints_repository.dart';
import 'package:localfit_ai/features/hydration/application/update_water_target_ml.dart';
import 'package:localfit_ai/features/hydration/data/water_repository.dart';
import 'package:localfit_ai/features/nutrition/application/food_catalog_service.dart';
import 'package:localfit_ai/features/nutrition/application/master_nutrition_sink_adapter.dart';
import 'package:localfit_ai/features/nutrition/application/supply_dish_candidates.dart';
import 'package:localfit_ai/features/nutrition/data/dish_library_repository.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/nutrition/data/supply_catalog_repository.dart';
import 'package:localfit_ai/features/progress/data/measurement_repository.dart';
import 'package:localfit_ai/features/progress/data/steps_repository.dart';
import 'package:localfit_ai/features/settings/data/profile_identity_repository.dart';
import 'package:localfit_ai/features/training/data/exercise_repository.dart';
import 'package:localfit_ai/features/training/data/workout_plan_repository.dart';
import 'package:localfit_ai/features/training/data/workout_session_repository.dart';

/// 食堂目录的 AI 接口语句适用性矩阵（2026-11-11 用户：「让 AI 对话加入食堂
/// 目录，也无法实现」）。
///
/// 口语 → 命令的映射由模型按协议完成；这里把**编译结果**按用户可能的说法
/// 逐条跑完整执行链，钉死每一句都能落到食堂目录上（而不是被静默吞掉或
/// 退化成记餐）：
///
/// * 「把X加入/收录到（某窗口）」→ `canteen.dish.create`（窗口按 id 或唯一名）
/// * 「建新菜+估算营养」→ create + nutrition 同卡，nutrition 用 window+name
///   定位新菜（新菜没有 id）
/// * 窗口重名 → 给「地点·窗口」候选清单；窗口不存在 → 带建窗修复
/// * `nutritionFrom=ai` 在建菜命令上不再静默无操作；v2 只挡「AI 估营养」，
///   不再误伤 `nutritionFrom=food`
void main() {
  final now = DateTime.utc(2026, 11, 11, 4);
  final registry = ChatEditCommandRegistry();

  late AppDatabase db;
  late RepositoryChatEditExecutor executor;
  late CanteenRepository canteen;
  late SupplyCatalogRepository supplies;
  late String venueId;
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
    supplies = SupplyCatalogRepository(database: db);
    venueId = await canteen.createVenue(name: '东苑', campusName: '校本部');
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
        mealRepository: MealRepository(
          database: db,
          idGenerator: ids,
          clock: clock,
        ),
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
        workoutPlanRepository: WorkoutPlanRepository(
          database: db,
          idGenerator: ids,
          clock: clock,
        ),
        workoutSessionRepository: WorkoutSessionRepository(
          database: db,
          idGenerator: ids,
          clock: clock,
        ),
        exerciseRepository: ExerciseRepository(
          database: db,
          idGenerator: ids,
          clock: clock,
        ),
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

  test('协议写明「加进食堂目录 ≠ 记餐」与「先建菜再写营养」的用法', () {
    final protocol = registry.renderProtocol();
    expect(protocol, contains('「加进食堂目录/窗口」≠ 记餐'));
    expect(protocol, contains('收录菜品用 `canteen.dish.create`'));
    expect(protocol, contains('nutrition 用 window+name 定位'));
  });

  test('「把小炒黄牛肉加入东苑一楼快餐窗口」→ 按窗口唯一名建菜（不记餐）', () async {
    final out = await executor.apply(
      cmd('canteen.dish.create', {'window': '一楼快餐窗口', 'name': '小炒黄牛肉'}),
    );
    expect(out.ok, isTrue, reason: out.message);
    expect(out.message, contains('已新增菜品'));
    expect(out.message, contains('未记餐'), reason: '收录目录不是记餐');
    expect(out.message, contains('份量未知'));
    final supply = (await supplies.getById(
      (await canteen.listDishes(windowId)).single.id,
    ))!;
    expect(supply.displayName, '小炒黄牛肉');
    expect(supply.state, SupplyNutritionState.needsAnalysis);
  });

  test('「建新菜+按照片估算营养」→ create + nutrition 同卡（window+name 定位新菜）', () async {
    final created = await executor.apply(
      cmd('canteen.dish.create', {'window': '一楼快餐窗口', 'name': '小炒黄牛肉'}),
    );
    expect(created.ok, isTrue, reason: created.message);
    final nutrition = await executor.apply(
      cmd('canteen.dish.nutrition', {
        'window': '一楼快餐窗口',
        'name': '小炒黄牛肉',
        'kcalPer100g': 180.0,
        'proteinPer100g': 16.0,
        'carbsPer100g': 4.0,
        'fatPer100g': 11.0,
        'grade': 'C',
        'servingGrams': 250.0,
      }),
    );
    expect(nutrition.ok, isTrue, reason: nutrition.message);
    expect(nutrition.message, contains('一份约 250g'));
    final dish = (await canteen.listDishes(windowId)).single;
    final supply = (await supplies.getById(dish.id))!;
    expect(supply.hasCompleteNutrition, isTrue);
    expect(supply.servingGrams, closeTo(250, 1e-9));
    expect(supply.state, SupplyNutritionState.servingEstimated);
    expect(dish.foodId, isNotNull, reason: '批准分析即建主库并链接');

    // 池边界：进本地每日推荐（宽松），不进 AI 自动换一套（严格）。
    final relaxed = supplyDishCandidates(
      await supplies.listAll(),
      now: now,
      strict: false,
    );
    final strict = supplyDishCandidates(
      await supplies.listAll(),
      now: now,
      strict: true,
    );
    expect(relaxed.map((dish) => dish.id), contains(dish.id));
    expect(strict.map((dish) => dish.id), isNot(contains(dish.id)));
  });

  test('已有供应补营养：window+name 一样能定位，不建重复菜', () async {
    final dishId = await canteen.createDish(windowId: windowId, name: '番茄炒蛋');
    final out = await executor.apply(
      cmd('canteen.dish.nutrition', {
        'window': windowId,
        'name': '番茄炒蛋',
        'kcalPer100g': 92.0,
        'proteinPer100g': 5.4,
        'carbsPer100g': 4.1,
        'fatPer100g': 6.2,
      }),
    );
    expect(out.ok, isTrue, reason: out.message);
    expect(await db.select(db.menuItems).get(), hasLength(1));
    expect((await supplies.getById(dishId))!.hasCompleteNutrition, isTrue);
  });

  test('窗口重名：报「地点·窗口」候选清单，不瞎选', () async {
    final venue2 = await canteen.createVenue(name: '西苑', campusName: '校本部');
    await canteen.createWindow(
      venueId: venue2,
      name: '一楼快餐窗口',
      openTime: '10:00',
      closeTime: '13:00',
    );
    final out = await executor.apply(
      cmd('canteen.dish.create', {'window': '一楼快餐窗口', 'name': '蛋炒饭'}),
    );
    expect(out.ok, isFalse);
    expect(out.message, contains('2 个同名窗口'));
    expect(out.message, contains('东苑·一楼快餐窗口'));
    expect(out.message, contains('西苑·一楼快餐窗口'));
    expect(await db.select(db.menuItems).get(), isEmpty);
  });

  test('窗口不存在：带「新建窗口」修复按钮（归属到已有地点）', () async {
    final out = await executor.apply(
      cmd('canteen.dish.create', {'window': '二楼面食窗口', 'name': '牛肉面'}),
    );
    expect(out.ok, isFalse);
    expect(out.repair?.kind, ChatEditRepairKind.createWindow);
    expect(out.repair?.name, '二楼面食窗口');
  });

  test('营养命令既没 dishId 也没 window+name：明确拒绝，不瞎猜', () async {
    final out = await executor.apply(
      cmd('canteen.dish.nutrition', {
        'kcalPer100g': 100.0,
        'proteinPer100g': 5.0,
        'carbsPer100g': 10.0,
        'fatPer100g': 3.0,
      }),
    );
    expect(out.ok, isFalse);
    expect(out.message, contains('给 dishId，或 window+name'));
  });

  test('营养命令指到不存在的窗口+菜名：给出可行动的说法', () async {
    final out = await executor.apply(
      cmd('canteen.dish.nutrition', {
        'window': '一楼快餐窗口',
        'name': '还不存在的菜',
        'kcalPer100g': 100.0,
        'proteinPer100g': 5.0,
        'carbsPer100g': 10.0,
        'fatPer100g': 3.0,
      }),
    );
    expect(out.ok, isFalse);
    expect(out.message, contains('先 `canteen.dish.create` 再写营养'));
  });

  test('v1/v2 建菜 + nutritionFrom=ai：明确失败（旧行为是静默无操作）', () async {
    for (final contract in ['v1', 'v2']) {
      final out = await executor.apply(
        cmd('canteen.dish.create', {
          'window': windowId,
          'name': '测试菜$contract',
          'nutritionFrom': 'ai',
          if (contract == 'v2') 'contract': 'v2',
        }),
      );
      expect(out.ok, isFalse, reason: '[$contract] ${out.message}');
      expect(
        out.message,
        contains('canteen.dish.nutrition'),
        reason: '[$contract]',
      );
    }
    expect(await db.select(db.menuItems).get(), isEmpty, reason: '失败不建菜');
  });

  test('v2 + nutritionFrom=food：不再被误伤（本地匹配决定）', () async {
    final out = await executor.apply(
      cmd('canteen.dish.create', {
        'window': windowId,
        'name': '没有任何匹配的菜',
        'nutritionFrom': 'food',
        'contract': 'v2',
      }),
    );
    // 本地匹配未接线命中时如实「部分成功」；关键是不能再报 v2 契约错误。
    expect(out.message, isNot(contains('v2 契约')), reason: out.message);
  });

  test('同一窗口同名再收录：直接引用已有供应，不堆重复菜', () async {
    final first = await executor.apply(
      cmd('canteen.dish.create', {'window': windowId, 'name': '白米饭'}),
    );
    expect(first.ok, isTrue, reason: first.message);
    final second = await executor.apply(
      cmd('canteen.dish.create', {'window': windowId, 'name': '白米饭'}),
    );
    expect(second.ok, isTrue, reason: second.message);
    expect(second.message, contains('已直接引用'));
    expect(await db.select(db.menuItems).get(), hasLength(1));
  });
}

class _SeqIds implements IdGenerator {
  int _next = 0;

  @override
  String next() => 'id-${_next++}';
}
