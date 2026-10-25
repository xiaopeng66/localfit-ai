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

/// RV-P1-04：`canteen.dish.create + nutritionFrom=food` 未命中时，
/// 菜品**已经**落库；命令不能回报「失败」（用户会重试 → 同名重复菜）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 10, 20, 12).toUtc();
  final registry = ChatEditCommandRegistry();

  late AppDatabase database;
  late CanteenRepository canteen;
  late RepositoryChatEditExecutor executor;
  late String windowId;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    final clock = FixedAppClock(now);
    final ids = _SeqIds();
    canteen = CanteenRepository(
      database: database,
      idGenerator: ids,
      clock: clock,
    );
    final venueId = await canteen.createVenue(name: '三食堂', campusName: '南校区');
    windowId = await canteen.createWindow(
      venueId: venueId,
      name: '一楼快餐',
      openTime: '08:00',
      closeTime: '20:00',
    );
    // 食物库匹配**未接线** = 「食物库没有这道菜」的最保守形态。
    executor = _executor(database, clock, ids, canteen);
  });

  tearDown(() => database.close());

  ChatEditCommand cmd(String action, Map<String, Object> args) {
    final spec = registry.specOf(action)!;
    return ChatEditCommand(spec: spec, args: validateChatEditArgs(spec, args));
  }

  test('食物库未命中：菜已建 ⇒ 如实返回部分成功，不报「失败」', () async {
    final out = await executor.apply(
      cmd('canteen.dish.create', {
        'window': windowId,
        'name': '宫保鸡丁',
        'nutritionFrom': 'food',
      }),
    );

    final dishes = await database.select(database.menuItems).get();
    expect(dishes.length, 1, reason: '菜已经建了（这是事实，不能假装没建）');
    expect(out.ok, isTrue, reason: '菜已建 ⇒ 结果不能是失败（会诱导重试重复建）');
    expect(out.message, contains('营养未填写'), reason: out.message);

    // 再执行一次同样的命令：这是**用户重试**的语义；当前行为会产生第二道同名菜，
    // 这里只钉住第一次的回报不再撒谎（去重是 P2 登记项）。
    expect(dishes.single.displayName, '宫保鸡丁');
  });
}

RepositoryChatEditExecutor _executor(
  AppDatabase database,
  FixedAppClock clock,
  IdGenerator ids,
  CanteenRepository canteen,
) {
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
      canteenRepository: canteen,
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

final class _SeqIds implements IdGenerator {
  int _n = 0;

  @override
  String next() => 'id-${_n++}';
}
