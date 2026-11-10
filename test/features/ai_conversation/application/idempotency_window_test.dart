// 命令级短时窗幂等（2124）：同一动作在 15 秒内重复执行 ⇒ 跳过并如实说明。
//
// 目标场景：模型在一张卡里给了两条相同命令、用户连点两次「应用」、或分组后
// 整卡再点一次。窗口内相同指纹只写一次；超过窗口（你真想再记一杯水）照常写。
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
import 'package:localfit_ai/features/progress/data/measurement_repository.dart';
import 'package:localfit_ai/features/progress/data/steps_repository.dart';
import 'package:localfit_ai/features/settings/data/profile_identity_repository.dart';
import 'package:localfit_ai/features/training/data/exercise_repository.dart';
import 'package:localfit_ai/features/training/data/workout_plan_repository.dart';
import 'package:localfit_ai/features/training/data/workout_session_repository.dart';

import '../../../support/food_fixture.dart';

final _base = DateTime(2026, 11, 7, 12);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final registry = ChatEditCommandRegistry();

  late AppDatabase database;
  late _MutableClock clock;
  late RepositoryChatEditExecutor executor;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await seedFoodFixture(database);
    clock = _MutableClock(_base.toUtc());
    executor = _build(database, clock);
  });

  tearDown(() => database.close());

  ChatEditCommand cmd(String action, Map<String, Object> args) {
    final spec = registry.specOf(action)!;
    return ChatEditCommand(spec: spec, args: validateChatEditArgs(spec, args));
  }

  Future<int> waterCount() async =>
      (await database.select(database.waterIntakes).get()).length;

  test('窗口内相同 water.add 只写一次，第二次如实说明「刚才已经记过」', () async {
    final first = await executor.apply(cmd('water.add', {'amountMl': 250.0}));
    expect(first.ok, isTrue);
    final second = await executor.apply(cmd('water.add', {'amountMl': 250.0}));
    expect(second.ok, isTrue, reason: '这条提议已经生效过，不算失败');
    expect(second.message, contains('刚才已经记过'), reason: second.message);
    expect(await waterCount(), 1);
  });

  test('超过窗口（15 秒）后相同 water.add 照常写入（你真想再喝一杯）', () async {
    await executor.apply(cmd('water.add', {'amountMl': 250.0}));
    clock.advance(const Duration(seconds: 16));
    final second = await executor.apply(cmd('water.add', {'amountMl': 250.0}));
    expect(second.ok, isTrue);
    expect(second.message, isNot(contains('刚才已经记过')));
    expect(await waterCount(), 2);
  });

  test('不同容量 / 不同日期不互拦', () async {
    await executor.apply(cmd('water.add', {'amountMl': 250.0}));
    await executor.apply(cmd('water.add', {'amountMl': 300.0}));
    await executor.apply(
      cmd('water.add', {'amountMl': 250.0, 'localDate': '2026-11-06'}),
    );
    expect(await waterCount(), 3);
  });

  test('并发重复（双击）也只写一次', () async {
    final results = await Future.wait([
      executor.apply(cmd('water.add', {'amountMl': 250.0})),
      executor.apply(cmd('water.add', {'amountMl': 250.0})),
    ]);
    expect(results.every((r) => r.ok), isTrue);
    expect(await waterCount(), 1);
  });

  test('更新/删除类不参与幂等（该报的错照报）', () async {
    final missing = await executor.apply(
      cmd('water.delete', {'waterId': 'nope'}),
    );
    expect(missing.ok, isFalse);
    expect(missing.message, contains('不存在'));
    // 第二次仍是同样的如实失败（不是「刚才已经记过」）。
    final again = await executor.apply(
      cmd('water.delete', {'waterId': 'nope'}),
    );
    expect(again.ok, isFalse);
    expect(again.message, contains('不存在'));
  });

  test('失败的动作不进幂等窗口：第二次仍真跑（不能报「刚才已执行」）', () async {
    // 没有进行中的训练会话 ⇒ set.log 必然失败；它属于幂等集合，但失败不记忆。
    final first = await executor.apply(
      cmd('set.log', {'exercise': '杠铃深蹲', 'weightKg': 60.0, 'reps': 5}),
    );
    expect(first.ok, isFalse, reason: '没有进行中的会话');
    final second = await executor.apply(
      cmd('set.log', {'exercise': '杠铃深蹲', 'weightKg': 60.0, 'reps': 5}),
    );
    expect(second.ok, isFalse);
    expect(second.message, isNot(contains('刚才已经执行过')), reason: '第一次没成功，窗口不该记它');
  });

  test('记餐不参与窗口幂等：仍按业务的全天去重说明，只落一餐', () async {
    final meal = cmd('meal.create', {
      'slot': '午餐',
      'items': [
        {'food': '米饭', 'grams': 150.0},
      ],
    });
    final first = await executor.apply(meal);
    expect(first.ok, isTrue, reason: first.message);
    final second = await executor.apply(meal);
    expect(second.ok, isTrue);
    expect(
      second.message,
      contains('都已经记过'),
      reason: '餐食有自己的全天去重文案（比「刚才已经执行过」更具体）',
    );
    expect((await database.select(database.meals).get()).length, 1);
  });
}

RepositoryChatEditExecutor _build(AppDatabase database, AppClock clock) {
  final ids = _SeqIds();
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

final class _MutableClock implements AppClock {
  _MutableClock(this._now);
  DateTime _now;

  void advance(Duration delta) => _now = _now.add(delta);

  @override
  DateTime nowUtc() => _now;
}

final class _SeqIds implements IdGenerator {
  int _n = 0;

  @override
  String next() => 'id-${_n++}';
}

// 幂等只记录**成功**：失败的动作不进窗口，否则用户第二次点会被误判成
// 「刚才已经执行过」，明明什么都没写进去。
