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
import 'package:localfit_ai/features/ai_memory/domain/ai_memory.dart';
import 'package:localfit_ai/features/ai_memory/domain/memory_dedupe.dart';
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

/// RV-P1-02 / RV-P1-14：执行器必须把仓储异常翻成「失败 + 人话」，不逃逸。
///
/// 三个真实场景：
/// 1. `memory.remember` 撞上 0.88–0.96 的近重复 → 仓储抛
///    [AiMemoryMergeSuggested]（**不是** AiMemoryException 子类）；
/// 2. 没有 `daily_targets` 行时 `targets.update{waterMl}` 抛 WaterTargetException；
/// 3. `profile.goal.update` 省略 `targetWeightKg` 时不得清空既有目标体重。
class _NearDuplicateIndex implements MemoryVectorIndex {
  _NearDuplicateIndex(this.cosine);

  final double cosine;

  @override
  Future<Map<String, double>?> similarities(String text) async {
    final rows = _ids;
    return {for (final id in rows) id: cosine};
  }

  static List<String> _ids = const [];

  @override
  Future<void> upsertMemory(AiMemory memory) async {
    _ids = [..._ids, memory.id];
  }

  @override
  Future<void> deleteMemory(String id) async {
    _ids = _ids.where((item) => item != id).toList();
  }

  @override
  Future<int> rebuild(List<AiMemory> memories) async {
    _ids = [for (final memory in memories) memory.id];
    return memories.length;
  }

  @override
  Future<Map<String, List<double>>?> vectors() async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 10, 20, 12).toUtc();
  final registry = ChatEditCommandRegistry();

  late AppDatabase database;
  late _NearDuplicateIndex index;
  late RepositoryChatEditExecutor executor;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    index = _NearDuplicateIndex(0.90);
    executor = _buildExecutor(database, now, index);
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

  test('RV-P1-02 近重复记忆：返回失败与人话，不抛异常', () async {
    final first = await executor.apply(
      cmd('memory.remember', {'text': '周三晚上练腿'}),
    );
    expect(first.ok, isTrue, reason: first.message);

    // 第二次与第一条字符串互不包含（通过字符串判重），但向量余弦 0.90
    // ⇒ 仓储抛 AiMemoryMergeSuggested。
    final second = await executor.apply(
      cmd('memory.remember', {'text': '周三晚间练腿'}),
    );
    expect(second.ok, isFalse, reason: '近似重复必须如实失败');
    expect(second.message, contains('建议合并'), reason: second.message);
    expect(
      (await database.select(database.aiMemories).get()).length,
      1,
      reason: '被拒的那条不能落库',
    );
  });

  test('RV-P1-02 无每日目标行：targets.update 返回失败文案，不抛', () async {
    final out = await executor.apply(cmd('targets.update', {'waterMl': 2500}));
    expect(out.ok, isFalse, reason: '没有目标行时不能假装写入');
    expect(out.message, contains('尚未建立每日目标'), reason: out.message);
  });

  test('RV-P1-14 省略 targetWeightKg 不清空既有目标体重', () async {
    await database
        .into(database.goals)
        .insert(
          GoalsCompanion.insert(
            id: 'goal-1',
            profileId: 'profile-1',
            type: 'maintain',
            targetWeightKg: const Value(65),
            calorieMinKcal: 1700,
            calorieMaxKcal: 1900,
            effectiveFrom: now,
            createdAt: now,
            updatedAt: now,
          ),
        );

    final out = await executor.apply(
      cmd('profile.goal.update', {'goal': '减脂'}),
    );
    expect(out.ok, isTrue, reason: out.message);
    final goal = (await database.select(database.goals).get()).single;
    expect(goal.type, 'loseFat');
    expect(goal.targetWeightKg, 65, reason: '省略参数 = 不改，不是清空');

    final explicit = await executor.apply(
      cmd('profile.goal.update', {'goal': '增肌', 'targetWeightKg': 60.0}),
    );
    expect(explicit.ok, isTrue, reason: explicit.message);
    final updated = (await database.select(database.goals).get()).single;
    expect(updated.targetWeightKg, 60);
  });
}

RepositoryChatEditExecutor _buildExecutor(
  AppDatabase database,
  DateTime now,
  MemoryVectorIndex index,
) {
  final clock = FixedAppClock(now);
  final ids = IdsForTest();
  return RepositoryChatEditExecutor(
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
        vectorIndex: index,
      ),
      mealRepository: MealRepository(
        database: database,
        idGenerator: ids,
        clock: clock,
      ),
      dishLibraryRepository: DishLibraryRepository(
        database: database,
        idGenerator: ids,
        clock: clock,
      ),
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
      exerciseRepository: ExerciseRepository(
        database: database,
        idGenerator: ids,
        clock: clock,
      ),
      profileIdentityRepository: ProfileIdentityRepository(database: database),
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
}

final class IdsForTest implements IdGenerator {
  int _n = 0;

  @override
  String next() => 'id-${_n++}';
}
