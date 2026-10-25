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
import 'package:localfit_ai/features/nutrition/data/dish_library_repository.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/progress/data/measurement_repository.dart';
import 'package:localfit_ai/features/progress/data/steps_repository.dart';
import 'package:localfit_ai/features/settings/data/profile_identity_repository.dart';
import 'package:localfit_ai/features/training/data/exercise_repository.dart';
import 'package:localfit_ai/features/training/data/workout_plan_repository.dart';
import 'package:localfit_ai/features/training/data/workout_session_repository.dart';

/// 食物来源路由（docs/43 B10 / docs/40 §5 / §3.1）。
void main() {
  final now = DateTime.utc(2026, 10, 19, 4);
  final registry = ChatEditCommandRegistry();

  late AppDatabase db;
  late RepositoryChatEditExecutor executor;
  late String windowId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final ids = _SeqIds();
    final clock = FixedAppClock(now);
    final canteen = CanteenRepository(
      database: db,
      idGenerator: ids,
      clock: clock,
    );
    // 校园 → 地点 → 窗口。
    await canteen.createVenue(name: '三食堂', campusName: '南校区');
    final venue = (await canteen.listVenues()).single;
    windowId = await canteen.createWindow(
      venueId: venue.id,
      name: '4 号窗口',
      openTime: '11:00',
      closeTime: '13:30',
    );
    // 食物库精确同名条目。
    await db
        .into(db.foods)
        .insert(
          FoodsCompanion.insert(
            id: 'food-fanqie',
            name: '番茄炒蛋',
            kcalPer100g: 140,
            proteinPer100g: 6,
            carbsPer100g: 10,
            fatPer100g: 8,
            source: 'catalog',
            state: const Value('verified'),
            createdAt: now,
            updatedAt: now,
          ),
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

  test('注册表接受三值，缺省行为不变', () {
    for (final action in ['canteen.dish.create', 'canteen.dish.nutrition']) {
      final spec = registry.specOf(action)!;
      final arg = spec.args.firstWhere((item) => item.name == 'nutritionFrom');
      expect(arg.required, isFalse, reason: '$action 的 nutritionFrom 必须是可选');
    }
  });

  test('协议段含「食物来源优先级」四条', () {
    final protocol = registry.renderProtocol();
    expect(protocol, contains('食物来源优先级'));
    expect(protocol, contains('食堂菜'));
    expect(protocol, contains('菜品库'));
    expect(protocol, contains('食物库'));
    expect(protocol, contains('food.create'));
    expect(protocol, contains('nutritionFrom'));
  });

  test('canteen.dish.create + nutritionFrom=food 命中 → origin=food_library、grade 沿用、链接 confirmed', () async {
    final out = await executor.apply(
      cmd('canteen.dish.create', {
        'window': windowId,
        'name': '番茄炒蛋',
        'nutritionFrom': 'food',
      }),
    );
    expect(out.ok, isTrue, reason: out.message);
    final dish = (await db.select(db.menuItems).get()).single;
    final evidence =
        (await db.select(db.menuItemNutritionEvidence).get()).single;
    expect(evidence.origin, 'food_library');
    expect(evidence.grade, 'A', reason: 'verified 食物沿用 A');
    expect(evidence.kcalPer100g, closeTo(140, 0.001));
    final link = (await db.select(db.menuItemFoodMatches).get()).single;
    expect(link.matchStatus, 'confirmed');
    expect(link.foodId, 'food-fanqie');
    expect(dish.id, isNotEmpty);
  });

  test('canteen.dish.create + nutritionFrom=food 未命中 → 菜已建，如实说营养未填', () async {
    final out = await executor.apply(
      cmd('canteen.dish.create', {
        'window': windowId,
        'name': '宫保鸡丁',
        'nutritionFrom': 'food',
      }),
    );
    // RV-P1-04（2026-10-20）：菜**已经**落库，回报不能是「失败」
    // （否则用户重试 → 同名重复菜）。如实报部分成功。
    expect(out.ok, isTrue, reason: out.message);
    expect(out.message, contains('营养未填写'));
    expect(out.message, contains('食物库没有'));
    expect(out.message, contains('AI 分析或手动填写'));
    expect(await db.select(db.menuItemNutritionEvidence).get(), isEmpty);
    expect(await db.select(db.menuItems).get(), hasLength(1));
  });

  test('旧 payload（不带 nutritionFrom）行为不变：建菜不写营养', () async {
    final out = await executor.apply(
      cmd('canteen.dish.create', {'window': windowId, 'name': '番茄炒蛋'}),
    );
    expect(out.ok, isTrue);
    expect(await db.select(db.menuItemNutritionEvidence).get(), isEmpty);
  });

  test('canteen.dish.nutrition + nutritionFrom=food → 引食物库（忽略命令数值）', () async {
    await executor.apply(
      cmd('canteen.dish.create', {'window': windowId, 'name': '番茄炒蛋'}),
    );
    final dishId = (await db.select(db.menuItems).get()).single.id;
    final out = await executor.apply(
      cmd('canteen.dish.nutrition', {
        'dishId': dishId,
        'kcalPer100g': 880.0,
        'proteinPer100g': 1.0,
        'carbsPer100g': 1.0,
        'fatPer100g': 1.0,
        'nutritionFrom': 'food',
      }),
    );
    expect(out.ok, isTrue, reason: out.message);
    final evidence =
        (await db.select(db.menuItemNutritionEvidence).get()).single;
    expect(evidence.origin, 'food_library');
    expect(evidence.kcalPer100g, closeTo(140, 0.001));
  });

  test('canteen.dish.nutrition + nutritionFrom=none → 不写', () async {
    await executor.apply(
      cmd('canteen.dish.create', {'window': windowId, 'name': '番茄炒蛋'}),
    );
    final dishId = (await db.select(db.menuItems).get()).single.id;
    final out = await executor.apply(
      cmd('canteen.dish.nutrition', {
        'dishId': dishId,
        'kcalPer100g': 120.0,
        'proteinPer100g': 5.0,
        'carbsPer100g': 9.0,
        'fatPer100g': 7.0,
        'nutritionFrom': 'none',
      }),
    );
    expect(out.ok, isTrue);
    expect(await db.select(db.menuItemNutritionEvidence).get(), isEmpty);
  });

  test('非法取值 → 中文错误', () async {
    final out = await executor.apply(
      cmd('canteen.dish.create', {
        'window': windowId,
        'name': '番茄炒蛋',
        'nutritionFrom': 'database',
      }),
    );
    expect(out.ok, isFalse);
    expect(out.message, contains('只能是 food / ai / none'));
  });
}

class _SeqIds implements IdGenerator {
  int _n = 0;
  @override
  String next() => 'id-${_n++}';
}
