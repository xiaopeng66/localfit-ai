import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/core/validation/entity_name.dart';
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
import 'package:localfit_ai/features/nutrition/domain/food_record.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/progress/data/measurement_repository.dart';
import 'package:localfit_ai/features/progress/data/steps_repository.dart';
import 'package:localfit_ai/features/settings/data/profile_identity_repository.dart';
import 'package:localfit_ai/features/training/data/exercise_repository.dart';
import 'package:localfit_ai/features/training/data/workout_plan_repository.dart';
import 'package:localfit_ai/features/training/data/workout_session_repository.dart';

/// P2 批次 A/B 的判据（2026-10-21）：每条对应 docs/48 §4.3 的一个 ID。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 10, 21, 12).toUtc();
  final registry = ChatEditCommandRegistry();

  late AppDatabase database;
  late RepositoryChatEditExecutor executor;
  late FoodRepository foods;
  late DishLibraryRepository dishes;
  late ExerciseRepository exercises;
  late AiMemoryRepository memories;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    final clock = FixedAppClock(now);
    final ids = _SeqIds();
    foods = FoodRepository(database: database, idGenerator: ids, clock: clock);
    dishes = DishLibraryRepository(
      database: database,
      idGenerator: ids,
      clock: clock,
    );
    exercises = ExerciseRepository(
      database: database,
      idGenerator: ids,
      clock: clock,
    );
    memories = AiMemoryRepository(
      database: database,
      clock: clock,
      idGenerator: ids,
    );
    executor = RepositoryChatEditExecutor(
      ChatEditServices(
        database: database,
        clock: clock,
        foodRepository: foods,
        aiMemoryRepository: memories,
        mealRepository: MealRepository(
          database: database,
          idGenerator: ids,
          clock: clock,
        ),
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
        canteenRepository: CanteenRepository(
          database: database,
          idGenerator: ids,
          clock: clock,
        ),
        workoutPlanRepository: WorkoutPlanRepository(
          database: database,
          idGenerator: ids,
          clock: clock,
        ),
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

  test('RV-P2-02 food.update 的 servingGrams 真的写库', () async {
    final created = await foods.create(
      const NewFood(
        name: '米饭',
        kcalPer100g: 116,
        proteinPer100g: 2.6,
        carbsPer100g: 25.9,
        fatPer100g: 0.3,
      ),
    );
    final id = created.id;
    final out = await executor.apply(
      cmd('food.update', {
        'foodId': id,
        'name': '米饭',
        'kcalPer100g': 116.0,
        'proteinPer100g': 2.6,
        'carbsPer100g': 25.9,
        'fatPer100g': 0.3,
        'servingGrams': 250.0,
      }),
    );
    expect(out.ok, isTrue, reason: out.message);
    expect((await foods.getById(id))!.defaultServingGrams, 250);

    // 省略时不覆盖旧值。
    final second = await executor.apply(
      cmd('food.update', {
        'foodId': id,
        'name': '米饭',
        'kcalPer100g': 116.0,
        'proteinPer100g': 2.6,
        'carbsPer100g': 25.9,
        'fatPer100g': 0.3,
      }),
    );
    expect(second.ok, isTrue, reason: second.message);
    expect((await foods.getById(id))!.defaultServingGrams, 250);
  });

  test('RV-P2-03 动作 >500 条时精确同名仍能找到', () async {
    for (var i = 0; i < 520; i++) {
      await database
          .into(database.exercises)
          .insert(
            ExercisesCompanion.insert(
              id: 'ex-$i',
              name: '动作$i',
              muscleGroup: 'legs',
              equipment: 'barbell',
              source: 'user',
              createdAt: now,
              updatedAt: now,
            ),
          );
    }
    // 名字排序在 500 之外的条目：'动作000' 排在 '动作0' 之前，靠 id 兜底。
    await database
        .into(database.exercises)
        .insert(
          ExercisesCompanion.insert(
            id: 'ex-target',
            name: '深蹲',
            muscleGroup: 'legs',
            equipment: 'barbell',
            source: 'user',
            createdAt: now,
            updatedAt: now,
          ),
        );
    final found = await exercises.findByExactName('深蹲');
    expect(found, hasLength(1));
    expect(found.single.id, 'ex-target');
  });

  test('RV-P2-05 同名菜品更新也走数值校验', () async {
    await dishes.create(
      DishDraft(
        name: '番茄牛腩饭',
        mealSlot: '午餐',
        kcal: 200,
        proteinG: 8,
        carbsG: 30,
        fatG: 5,
        source: 'manual',
      ),
    );
    await expectLater(
      executor.apply(
        cmd('dish.upsert', {
          'name': '番茄牛腩饭',
          'slot': '午餐',
          'kcal': 950.0,
          'protein': 8.0,
          'carbs': 30.0,
          'fat': 5.0,
        }),
      ),
      completion(
        isA<Object>().having((r) => (r as dynamic).ok as bool, 'ok', isFalse),
      ),
    );
    expect((await dishes.watchAll().first).single.kcal, 200);
  });

  test('RV-P2-06 记忆页订阅不包含已改口条目', () async {
    final first = await memories.remember(text: '周三晚上练腿');
    // 字符串判重会拒绝「包含」关系，这里用完全不同措辞（同域两条事实）。
    final second = await memories.remember(text: '周末上午游泳');
    await memories.supersede(oldId: first.id, newId: second.id);
    final active = await memories.watchActive().first;
    expect(active.map((m) => m.id), isNot(contains(first.id)));
    expect(active.map((m) => m.id), contains(second.id));
  });

  test('RV-P2-08 未来日期被拒绝（记录语义）', () async {
    final out = await executor.apply(
      cmd('weight.log', {'weightKg': 70.0, 'localDate': '2099-01-01'}),
    );
    expect(out.ok, isFalse);
    expect(out.message, contains('未来日期'));
  });

  test('RV-P2-16 名称上限：仓储层拒绝超长名称', () async {
    expect(
      () => validatedEntityName('x' * (kMaxEntityNameLength + 1), label: '菜名'),
      throwsA(isA<FormatException>()),
    );
    await expectLater(
      foods.create(
        NewFood(
          name: 'x' * (kMaxEntityNameLength + 1),
          kcalPer100g: 100,
          proteinPer100g: 1,
          carbsPer100g: 1,
          fatPer100g: 1,
        ),
      ),
      throwsA(isA<FormatException>()),
    );
  });
}

final class _SeqIds implements IdGenerator {
  int _n = 0;

  @override
  String next() => 'id-${_n++}';
}
