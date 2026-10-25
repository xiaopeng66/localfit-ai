import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/ai_conversation/application/chat_edit_executor.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_command.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_registry.dart';
import 'package:localfit_ai/features/ai_memory/data/ai_memory_repository.dart';
import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart';
import 'package:localfit_ai/features/daily_plan/data/planning_constraints_repository.dart';
import 'package:localfit_ai/features/hydration/application/update_water_target_ml.dart';
import 'package:localfit_ai/features/hydration/data/water_repository.dart';
import 'package:localfit_ai/features/nutrition/data/dish_library_repository.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';
import 'package:localfit_ai/features/progress/data/measurement_repository.dart';
import 'package:localfit_ai/features/progress/data/steps_repository.dart';
import 'package:localfit_ai/features/settings/data/profile_identity_repository.dart';
import 'package:localfit_ai/features/training/data/exercise_repository.dart';
import 'package:localfit_ai/features/training/data/workout_plan_repository.dart';
import 'package:localfit_ai/features/training/data/workout_session_repository.dart';
import 'package:localfit_ai/features/training/domain/workout_plan.dart';

/// 37 条 AI 命令的**执行器级失败分支**补齐（docs/48 §2.1 的 11 条缺口）。
///
/// 判据：命令经 `RepositoryChatEditExecutor.apply` 返回 `ok=false` 且带人话，
/// **不抛异常**、不假成功。参数名与注册表一致。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 10, 21, 12).toUtc();
  final registry = ChatEditCommandRegistry();

  late AppDatabase database;
  late RepositoryChatEditExecutor executor;
  late MealRepository meals;
  late DishLibraryRepository dishes;
  late CanteenRepository canteen;
  late WorkoutPlanRepository plans;
  late ExerciseRepository exercises;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    final clock = FixedAppClock(now);
    final ids = _SeqIds();
    meals = MealRepository(database: database, idGenerator: ids, clock: clock);
    dishes = DishLibraryRepository(
      database: database,
      idGenerator: ids,
      clock: clock,
    );
    canteen = CanteenRepository(
      database: database,
      idGenerator: ids,
      clock: clock,
    );
    plans = WorkoutPlanRepository(
      database: database,
      idGenerator: ids,
      clock: clock,
    );
    exercises = ExerciseRepository(
      database: database,
      idGenerator: ids,
      clock: clock,
    );
    executor = RepositoryChatEditExecutor(
      ChatEditServices(
        database: database,
        clock: clock,
        foodRepository: FoodRepository(
          database: database,
          idGenerator: ids,
          clock: clock,
        ),
        aiMemoryRepository: AiMemoryRepository(
          database: database,
          clock: clock,
          idGenerator: ids,
        ),
        mealRepository: meals,
        dishLibraryRepository: dishes,
        waterRepository: WaterRepository(
          database: database,
          idGenerator: ids,
          clock: clock,
        ),
        measurementRepository: MeasurementRepository(
          database: database,
          idGenerator: ids,
          clock: clock,
        ),
        planningConstraintsRepository: PlanningConstraintsRepository(
          database: database,
          clock: clock,
        ),
        canteenRepository: canteen,
        workoutPlanRepository: plans,
        exerciseRepository: exercises,
        profileIdentityRepository: ProfileIdentityRepository(
          database: database,
        ),
        workoutSessionRepository: WorkoutSessionRepository(
          database: database,
          idGenerator: ids,
          clock: clock,
        ),
        updateWaterTargetMl: UpdateWaterTargetMl(
          database: database,
          idGenerator: ids,
          clock: clock,
        ),
        stepsRepository: StepsRepository(
          database: database,
          channel: StepsChannel(),
          idGenerator: ids,
          clock: clock,
        ),
        idGenerator: ids,
      ),
    );
    await database
        .into(database.profiles)
        .insert(
          ProfilesCompanion.insert(
            id: 'profile-1',
            activityLevel: 'moderate',
            createdAt: now,
            updatedAt: now,
          ),
        );
  });

  tearDown(() => database.close());

  ChatEditCommand cmd(String action, Map<String, Object> args) {
    final spec = registry.specOf(action)!;
    return ChatEditCommand(spec: spec, args: validateChatEditArgs(spec, args));
  }

  Future<void> expectFailure(
    String action,
    Map<String, Object> args, {
    String? contains,
  }) async {
    final out = await executor.apply(cmd(action, args));
    expect(out.ok, isFalse, reason: '$action 应如实失败：${out.message}');
    expect(out.message.trim(), isNotEmpty);
    if (contains != null) {
      expect(out.message, _contains(contains));
    }
  }

  Future<String> seedMealWithItems() async {
    return meals.create(
      MealDraft(
        localDate: '2026-10-21',
        slot: MealSlot.lunch,
        items: const [
          MealItemDraft(
            foodName: '米饭',
            grams: 150,
            nutrition: NutritionValues(
              kcal: 174,
              proteinGrams: 3.9,
              carbsGrams: 38.9,
              fatGrams: 0.5,
            ),
          ),
          MealItemDraft(
            foodName: '青菜',
            grams: 100,
            nutrition: NutritionValues(
              kcal: 30,
              proteinGrams: 2,
              carbsGrams: 4,
              fatGrams: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  test('meal.update：餐记录不存在 ⇒ 失败', () async {
    await expectFailure('meal.update', {
      'mealId': 'ghost-meal',
      'slot': '午餐',
    }, contains: '餐');
  });

  test('water.add：越界在解码期拒绝（1–5000ml）', () async {
    expect(
      () => cmd('water.add', {'amountMl': 6000.0}),
      throwsA(isA<ChatEditArgsException>()),
    );
    expect(
      () => cmd('water.add', {'amountMl': 0.0}),
      throwsA(isA<ChatEditArgsException>()),
    );
  });

  test('canteen.venue.create：空名在解码期拒绝（参数校验）', () async {
    expect(
      () => cmd('canteen.venue.create', {'name': '   ', 'campus': '南校区'}),
      throwsA(isA<ChatEditArgsException>()),
    );
  });

  test('meal.item.update：条目不存在 ⇒ 失败', () async {
    await seedMealWithItems();
    await expectFailure('meal.item.update', {
      'itemId': 'ghost-item',
      'grams': 120.0,
    }, contains: '餐条目');
  });

  test('meal.item.delete：删到空餐 ⇒ 明确拒绝', () async {
    final mealId = await meals.create(
      MealDraft(
        localDate: '2026-10-21',
        slot: MealSlot.lunch,
        items: const [
          MealItemDraft(
            foodName: '米饭',
            grams: 150,
            nutrition: NutritionValues(
              kcal: 174,
              proteinGrams: 3.9,
              carbsGrams: 38.9,
              fatGrams: 0.5,
            ),
          ),
        ],
      ),
    );
    final item = (await database.select(database.mealItems).get()).single;
    await expectFailure('meal.item.delete', {
      'itemId': item.id,
    }, contains: '要删整餐');
    expect((await meals.getById(mealId))!.items, hasLength(1));
  });

  test('dish.upsert：营养越界 ⇒ 失败且不落库', () async {
    await expectFailure('dish.upsert', {
      'name': '番茄牛腩饭',
      'slot': '午餐',
      'kcal': 950.0,
      'protein': 8.0,
      'carbs': 30.0,
      'fat': 5.0,
    });
    expect(await database.select(database.dishLibrary).get(), isEmpty);
  });

  test('canteen.venue.rename / delete：地点不存在 ⇒ 失败', () async {
    await expectFailure('canteen.venue.rename', {
      'venueId': 'ghost-venue',
      'name': '改名',
    }, contains: '地点');
    await expectFailure('canteen.venue.delete', {
      'venueId': 'ghost-venue',
    }, contains: '地点');
  });

  test('canteen.window.delete：窗口不存在 ⇒ 失败', () async {
    await expectFailure('canteen.window.delete', {
      'windowId': 'ghost-window',
    }, contains: '窗口');
  });

  test('canteen.dish.update / delete：菜品不存在 ⇒ 失败', () async {
    await expectFailure('canteen.dish.update', {
      'dishId': 'ghost-dish',
      'name': '改名',
    }, contains: '菜品');
    await expectFailure('canteen.dish.delete', {
      'dishId': 'ghost-dish',
    }, contains: '菜品');
  });

  test('canteen.dish.nutrition：菜品不存在 / 非法等级 ⇒ 失败', () async {
    await expectFailure('canteen.dish.nutrition', {
      'dishId': 'ghost-dish',
      'kcalPer100g': 200.0,
      'proteinPer100g': 8.0,
      'carbsPer100g': 30.0,
      'fatPer100g': 5.0,
    }, contains: '菜品');
    final venueId = await canteen.createVenue(name: '三食堂', campusName: '南校区');
    final windowId = await canteen.createWindow(
      venueId: venueId,
      name: '一楼',
      openTime: '08:00',
      closeTime: '20:00',
    );
    final dishId = await canteen.createDish(windowId: windowId, name: '番茄牛腩饭');
    await expectFailure('canteen.dish.nutrition', {
      'dishId': dishId,
      'kcalPer100g': 200.0,
      'proteinPer100g': 8.0,
      'carbsPer100g': 30.0,
      'fatPer100g': 5.0,
      'grade': 'Z',
    }, contains: '证据等级');
  });

  test('constraints.set：非法饮食标签 ⇒ 失败且不写库', () async {
    await expectFailure('constraints.set', {
      'dietaryLabels': ['生酮'],
    }, contains: '不是可用的饮食约束');
    final profile = (await database.select(database.profiles).get()).single;
    expect(profile.dietaryPreferencesJson, isNot(contains('生酮')));
  });

  test('session.start：计划不存在 ⇒ 失败', () async {
    await expectFailure('session.start', {
      'planId': 'ghost-plan',
    }, contains: '不存在');
  });

  test('session.finish：没有进行中的会话 ⇒ 失败', () async {
    await expectFailure('session.finish', const {}, contains: '没有进行中的训练');
  });

  test('plan.entry.add：动作不存在 ⇒ 失败且不写计划条目', () async {
    await database
        .into(database.exercises)
        .insert(
          ExercisesCompanion.insert(
            id: 'ex-1',
            name: '深蹲',
            muscleGroup: 'legs',
            equipment: 'barbell',
            source: 'user',
            createdAt: now,
            updatedAt: now,
          ),
        );
    final planId = await plans.create(
      const WorkoutPlanDraft(
        name: '下肢日',
        days: [
          WorkoutPlanDayDraft(
            weekday: 3,
            entries: [
              PlannedExerciseDraft(
                exerciseId: 'ex-1',
                targetSets: 3,
                targetReps: 10,
              ),
            ],
          ),
        ],
      ),
    );
    await expectFailure('plan.entry.add', {
      'planId': planId,
      'weekday': 3,
      'exercise': '不存在的动作',
      'sets': 3,
      'reps': 10,
    }, contains: '动作');
    // 计划里原本就有 1 条（建计划时给的）；失败不得再加一条。
    expect(
      await database.select(database.plannedExercises).get(),
      hasLength(1),
    );
  });

  test('food.update / delete：食物不存在 ⇒ 失败', () async {
    await expectFailure('food.update', {
      'foodId': 'ghost-food',
      'name': '米饭',
      'kcalPer100g': 116.0,
      'proteinPer100g': 2.6,
      'carbsPer100g': 25.9,
      'fatPer100g': 0.3,
    }, contains: '自建食物');
    await expectFailure('food.delete', {
      'foodId': 'ghost-food',
    }, contains: '自建食物');
  });
}

Matcher _contains(String value) => contains(value);

final class _SeqIds implements IdGenerator {
  int _n = 0;

  @override
  String next() => 'id-${_n++}';
}
