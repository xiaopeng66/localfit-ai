import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/ai_conversation/application/chat_edit_executor.dart';
import 'package:localfit_ai/features/ai_conversation/data/chat_edit_context_loader.dart';
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
import 'package:localfit_ai/features/progress/data/measurement_repository.dart';
import 'package:localfit_ai/features/progress/data/steps_repository.dart';
import 'package:localfit_ai/features/settings/data/profile_identity_repository.dart';
import 'package:localfit_ai/features/training/data/exercise_repository.dart';
import 'package:localfit_ai/features/training/data/workout_plan_repository.dart';
import 'package:localfit_ai/features/training/data/workout_session_repository.dart';
import 'package:localfit_ai/features/training/domain/workout_plan.dart';

/// 快照新鲜度（2026-11-11 复核）。
///
/// 真实模型实测：`plan.rename` 成功后，**紧接着**的下一轮请求里模型仍说
/// 「找不到「编排测试计划 v2」，当前只有「编排测试计划」」，于是给了零行
/// 信封。根因是快照段缓存靠 drift `tableUpdates` **异步**标脏；AI 写完
/// 立刻 build 下一轮时事件还没送达，读到的是旧缓存。
///
/// 修法：执行器成功写入后同步回调 `onMutated`（生产接到 loader 的
/// `invalidateAll`）。本用例只等一轮事件循环之外的立即读取，确保修复不
/// 依赖时序运气。
void main() {
  final now = DateTime.utc(2026, 11, 11, 4).toUtc();
  final clock = FixedAppClock(now);
  final registry = ChatEditCommandRegistry();

  late AppDatabase db;
  late WorkoutPlanRepository plans;
  late DriftChatEditContextLoader loader;
  late RepositoryChatEditExecutor executor;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final ids = _Ids();
    plans = WorkoutPlanRepository(database: db, idGenerator: ids, clock: clock);
    loader = DriftChatEditContextLoader(
      database: db,
      clock: clock,
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
      canteenRepository: CanteenRepository(
        database: db,
        idGenerator: ids,
        clock: clock,
      ),
      workoutPlanRepository: plans,
      workoutSessionRepository: WorkoutSessionRepository(
        database: db,
        idGenerator: ids,
        clock: clock,
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
        canteenRepository: CanteenRepository(
          database: db,
          idGenerator: ids,
          clock: clock,
        ),
        workoutPlanRepository: plans,
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
        // 生产装配（main.dart）就是这样接的：成功写入后同步失效快照。
        onMutated: loader.invalidateAll,
      ),
    );
  });

  tearDown(() async => db.close());

  ChatEditCommand cmd(String action, Map<String, Object> args) {
    final spec = registry.specOf(action)!;
    return ChatEditCommand(spec: spec, args: validateChatEditArgs(spec, args));
  }

  test('改名成功后，紧接着的快照必须已经是新名字（不依赖异步事件）', () async {
    final planId = await plans.create(
      const WorkoutPlanDraft(name: '增肌一周', days: []),
    );
    final before = await loader.build();
    expect(before, contains('增肌一周'));

    final renamed = await executor.apply(
      cmd('plan.rename', {'planId': planId, 'name': '增肌一周 v2'}),
    );
    expect(renamed.ok, isTrue, reason: renamed.message);

    // 关键：**立即**再构建，不 pump、不 delay。修复前这里仍是旧名字。
    final after = await loader.build();
    expect(after, contains('增肌一周 v2'), reason: '快照必须立刻看到新名字');
    expect(after, isNot(contains('[wplan:$planId] 增肌一周（')));
  });

  test('写入失败不触发失效（缓存原样可继续用）', () async {
    await plans.create(const WorkoutPlanDraft(name: '保留计划', days: []));
    final before = await loader.build();
    final failed = await executor.apply(
      cmd('plan.rename', {'planId': '不存在的计划', 'name': '新名字'}),
    );
    expect(failed.ok, isFalse);
    final after = await loader.build();
    expect(after, contains('保留计划'));
    expect(before, isNotEmpty);
  });
}

final class _Ids implements IdGenerator {
  int _value = 0;
  @override
  String next() => 'fresh-${_value++}';
}
