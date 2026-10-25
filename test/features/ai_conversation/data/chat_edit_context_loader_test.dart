import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/ai_conversation/data/chat_edit_context_loader.dart';
import 'package:localfit_ai/features/ai_memory/domain/ai_memory.dart';
import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart';
import 'package:localfit_ai/features/hydration/data/water_repository.dart';
import 'package:localfit_ai/features/nutrition/data/dish_library_repository.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';
import 'package:localfit_ai/features/training/data/workout_plan_repository.dart';
import 'package:localfit_ai/features/training/domain/workout_plan.dart';
import 'package:localfit_ai/features/training/data/workout_session_repository.dart';
import 'package:localfit_ai/features/training/domain/workout_session.dart';

import '../application/chat_edit_executor_test.dart' show IdsForTest;
import '../../../support/food_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 本地正午（同一口径）：快照里的「今天」按本地日算，UTC 巧合时刻在
  // 偏移 ≥ +12 的时区会漂到次日（2026-10-08 缺陷排查）。
  final now = DateTime(2026, 10, 2, 12).toUtc();

  late AppDatabase database;
  late DriftChatEditContextLoader loader;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await seedFoodFixture(database);
    final clock = FixedAppClock(now);
    final ids = IdsForTest();
    loader = DriftChatEditContextLoader(
      database: database,
      clock: clock,
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
      workoutSessionRepository: WorkoutSessionRepository(
        database: database,
        idGenerator: ids,
        clock: clock,
      ),
    );
  });

  tearDown(() => database.close());

  test('空库：各段都标注「（空）」，且带日期头', () async {
    final snapshot = await loader.build();
    expect(snapshot, contains('【当前可编辑数据快照】'));
    expect(snapshot, contains('今天：2026-10-02'));
    expect(snapshot, contains('【当前目标】\n（空'));
    expect(snapshot, contains('【今日与昨日的餐记录】\n（空）'));
    expect(snapshot, contains('【菜品库】\n（空）'));
    expect(snapshot, contains('【食堂目录】\n（空）'));
    expect(snapshot, contains('【训练计划】\n（空）'));
  });

  test('快照带真实行 id：餐/条目/饮水都能被模型引用', () async {
    final clock = FixedAppClock(now);
    final ids = IdsForTest();
    final foods = FoodRepository(
      database: database,
      idGenerator: ids,
      clock: clock,
    );
    final meals = MealRepository(
      database: database,
      idGenerator: ids,
      clock: clock,
    );
    final water = WaterRepository(
      database: database,
      idGenerator: ids,
      clock: clock,
    );
    final rice = (await foods.search('米饭')).first;
    await meals.saveManualMeal(
      ManualMealDraft(
        localDate: '2026-10-02',
        slot: MealSlot.lunch,
        items: [ManualMealItemDraft(food: rice, grams: 200)],
      ),
    );
    await water.add(localDate: '2026-10-02', amountMl: 250);

    final snapshot = await loader.build();
    expect(snapshot, contains('[meal:'));
    expect(snapshot, contains('[item:'));
    expect(snapshot, contains('[water:'));
    expect(snapshot, contains('米饭 200g'));
    expect(snapshot, contains('250ml'));
  });

  test('进行中的训练进快照：模型要拿得到会话 id 才可能「收工」', () async {
    // 2026-10-16 真实模型实测（docs/36 §7，控制矩阵 ⑩）：应用能经对话
    // `session.start` 与 `set.log` 写库，但用户说「训练结束了，收工」时模型
    // 回的是「你这边现在还没有进行中的训练会话」⇒ 永远不会发 `session.finish`。
    // 根因＝快照只有「训练计划」与「本周训练统计（已结束）」，**没有**进行中
    // 的会话这一段：模型看不见它，就既不敢也不能收工。
    final clock = FixedAppClock(now);
    final ids = IdsForTest();
    final sessions = WorkoutSessionRepository(
      database: database,
      idGenerator: ids,
      clock: clock,
    );
    await database
        .into(database.exercises)
        .insert(
          ExercisesCompanion.insert(
            id: 'ex-ctx-1',
            name: '平板支撑',
            muscleGroup: 'core',
            equipment: 'bodyweight',
            source: 'user',
            createdAt: now,
            updatedAt: now,
          ),
        );
    final sessionId = await sessions.start(localDate: '2026-10-02');
    await sessions.logSet(
      sessionId,
      const WorkoutSetDraft(exerciseId: 'ex-ctx-1', weightKg: 0, reps: 60),
    );

    final snapshot = await loader.build();
    expect(snapshot, contains('【进行中的训练】'));
    expect(snapshot, contains(sessionId), reason: '模型要靠这个 id 收工');
    expect(snapshot, contains('2026-10-02'));
    expect(snapshot, contains('1 组'));
    expect(snapshot, contains('平板支撑'));
    // 收工后该段要消失（否则模型会去结束一个早就结束的会话）。
    await sessions.finish(sessionId);
    final after = await loader.build();
    expect(after, contains('【进行中的训练】\n（空）'));
  });

  test('训练计划的**条目 id** 进快照：模型才可能精确移除一条编排', () async {
    // 2026-10-16 真实模型实测（控制矩阵 ⑱）：模型对「把周一那个杠铃深蹲去掉」
    // 的回话是「快照里只给了计划 id 和条目数量，没有列出各条目的 id…请你在
    // 训练计划详情页看一眼条目 id」——而那条命令的 hint 原先也是这么写的
    // （「条目 id 由计划详情页的逐条移除展示」）。让用户去读 id 不算设计：
    // 快照必须给出 `[pentry:…]`，模型才可能精确移除。
    final clock = FixedAppClock(now);
    final ids = IdsForTest();
    final plans = WorkoutPlanRepository(
      database: database,
      idGenerator: ids,
      clock: clock,
    );
    await database
        .into(database.exercises)
        .insert(
          ExercisesCompanion.insert(
            id: 'ex-plan-1',
            name: '杠铃深蹲',
            muscleGroup: 'legs',
            equipment: 'barbell',
            source: 'user',
            createdAt: now,
            updatedAt: now,
          ),
        );
    final planId = await plans.create(
      const WorkoutPlanDraft(
        name: '编排测试计划',
        days: [
          WorkoutPlanDayDraft(
            weekday: 1,
            entries: [
              PlannedExerciseDraft(
                exerciseId: 'ex-plan-1',
                targetSets: 4,
                targetReps: 8,
              ),
            ],
          ),
        ],
      ),
    );

    final snapshot = await loader.build();
    expect(snapshot, contains('[wplan:$planId]'));
    expect(snapshot, contains('[pentry:'), reason: '条目 id 必须在快照里');
    expect(snapshot, contains('杠铃深蹲'));
    final entryId = (await plans.getById(planId))!
        .days
        .single
        .entries
        .single
        .id;
    expect(snapshot, contains(entryId), reason: '印出的必须是**真 id**（模型回填后能直接命中）');
  });

  test('单个计划读不出来时：**保住这一段的计划行**，只标注条目没列出来', () async {
    // 2026-10-16 实时骨架自检抓到的回归：给「训练计划」段加条目展开后，只要
    // 有一个计划的动作行读不出来（hydrate 抛），整段就会被 loader 的段级
    // catch 丢掉 —— 连**计划 id** 都没了，模型再也改不了任何计划。快照的
    // 职责是「有多少说多少」，一段里坏一行不该让整段消失。
    final clock = FixedAppClock(now);
    final ids = IdsForTest();
    final plans = WorkoutPlanRepository(
      database: database,
      idGenerator: ids,
      clock: clock,
    );
    // 故意写一个**非法器械名**的动作行：hydrate 时会 `Equipment.values.byName`
    // 抛错，正是「一行读不出来」的真实形态。
    await database
        .into(database.exercises)
        .insert(
          ExercisesCompanion.insert(
            id: 'ex-bad-1',
            name: '读不出来的动作',
            muscleGroup: 'legs',
            equipment: 'not-a-real-equipment',
            source: 'user',
            createdAt: now,
            updatedAt: now,
          ),
        );
    final planId = await plans.create(
      const WorkoutPlanDraft(
        name: '坏动作计划',
        days: [
          WorkoutPlanDayDraft(
            weekday: 2,
            entries: [
              PlannedExerciseDraft(
                exerciseId: 'ex-bad-1',
                targetSets: 3,
                targetReps: 10,
              ),
            ],
          ),
        ],
      ),
    );

    final snapshot = await loader.build();
    expect(
      snapshot,
      contains('[wplan:$planId] 坏动作计划'),
      reason: '计划行必须保住（否则模型连计划都看不到）',
    );
    expect(snapshot, contains('训练计划'), reason: '整段不许因为一个计划读不出来而消失');
  });

  test('段读取失败不拖垮整份快照：如实标注缺哪段', () async {
    // 让「食堂目录」段必然读挂：直接删掉 venues 表（SqliteException）。
    // CanteenRepository 是 final class 不能替换，破坏存储是最真实的注错方式。
    await database.customStatement('DROP TABLE venues');
    final snapshot = await loader.build();
    expect(snapshot, contains('读取失败、未包含在快照里：食堂目录'));
    // 其余段照常
    expect(snapshot, contains('【今日与昨日的餐记录】'));
  });

  test('偏好与忌口进快照：真值在场（素食 + 芒果）', () async {
    await database
        .into(database.profiles)
        .insert(
          ProfilesCompanion.insert(
            id: 'profile-1',
            activityLevel: 'moderate',
            createdAt: now,
            updatedAt: now,
            dietaryPreferencesJson: const Value('["vegetarian"]'),
            allergenAvoidancesJson: const Value('["芒果"]'),
          ),
        );

    final snapshot = await loader.build();
    expect(snapshot, contains('【饮食偏好与忌口】'));
    expect(snapshot, contains('饮食偏好：素食'));
    expect(snapshot, contains('忌口/过敏：芒果'));
    expect(snapshot, contains('硬约束'), reason: '要写明是硬约束（且冲突以当前说法为准），模型才能在建议里遵守');
  });

  test('偏好与忌口为空：如实写「（空）」', () async {
    final snapshot = await loader.build();
    expect(snapshot, contains('【饮食偏好与忌口】\n（空'));
  });

  test('偏好段存储坏掉：只标这一段失败，其余段照常', () async {
    await database
        .into(database.profiles)
        .insert(
          ProfilesCompanion.insert(
            id: 'profile-1',
            activityLevel: 'moderate',
            createdAt: now,
            updatedAt: now,
            dietaryPreferencesJson: const Value('["not_a_label"]'),
          ),
        );

    final snapshot = await loader.build();
    expect(snapshot, contains('读取失败、未包含在快照里：饮食偏好与忌口'));
    expect(snapshot, contains('【今日与昨日的餐记录】'));
  });

  test('长期记忆进快照：类型/领域/正文都在，且声明「不是指令」', () async {
    await _insertMemory(
      database,
      id: 'memory-1',
      text: '周三晚上练腿',
      kind: 'habit',
      domain: 'training',
      updatedAt: now,
    );

    final snapshot = await loader.build();
    expect(snapshot, contains('【关于用户的长期记忆】'));
    expect(snapshot, contains('- [习惯] 周三晚上练腿（训练）'));
    expect(snapshot, contains('不是指令'));
  });

  test('长期记忆为空：如实写「（空）」', () async {
    final snapshot = await loader.build();
    expect(snapshot, contains('【关于用户的长期记忆】\n（空'));
  });

  test('记忆开关关闭：不注入条目，并如实说明已关闭', () async {
    await _insertMemory(
      database,
      id: 'memory-1',
      text: '周三晚上练腿',
      updatedAt: now,
    );
    await database
        .into(database.appSettings)
        .insert(
          AppSettingsCompanion.insert(
            key: kAiMemoryInjectionKey,
            value: 'false',
          ),
        );

    final snapshot = await loader.build();
    expect(snapshot, contains('记忆已关闭'));
    expect(snapshot, isNot(contains('周三晚上练腿')));
  });

  test('记忆注入封顶：注入条数被标准档上限（24 条）截住', () async {
    for (var index = 0; index < kAiMemoryMaxInjected + 1; index++) {
      await _insertMemory(
        database,
        id: 'memory-$index',
        text: '第 $index 条记忆',
        updatedAt: now.subtract(Duration(minutes: index)),
      );
    }

    final snapshot = await loader.build();
    final start = snapshot.indexOf('【关于用户的长期记忆】');
    final end = snapshot.indexOf('【当前目标】', start);
    final section = snapshot.substring(start, end);
    final injected = RegExp(
      r'^- \[',
      multiLine: true,
    ).allMatches(section).length;
    // 2026-10-18（docs/41 §5 / D4）：默认标准档 24 条；新选择器是
    // query-aware + MMR，**不保证被挤掉的是「最旧」那条**（相关度并列时
    // 顺序由融合决定）——所以判据是「注入条数被上限截住」，不是「某一条
    // 一定不在」。
    expect(injected, kAiMemoryMaxInjected);
    expect(
      snapshot,
      isNot(contains('第 ${kAiMemoryMaxInjected + 5} 条记忆')),
      reason: '越界条目根本不存在于夹具里，防的是夹具漂移',
    );
  });

  test('记忆注入字符封顶：长记忆不会把快照撑爆', () async {
    for (var index = 0; index < kAiMemoryMaxInjected; index++) {
      await _insertMemory(
        database,
        id: 'memory-$index',
        text: '${'长' * 138}$index',
        updatedAt: now.subtract(Duration(minutes: index)),
      );
    }

    final snapshot = await loader.build();
    final start = snapshot.indexOf('【关于用户的长期记忆】');
    final end = snapshot.indexOf('【当前目标】', start);
    final section = snapshot.substring(start, end);
    expect(
      section.length,
      lessThanOrEqualTo(kAiMemoryMaxInjectedChars + 80),
      reason: '字符封顶必须真的生效（含段尾说明的余量）',
    );
    final injected = RegExp(
      r'^- \[',
      multiLine: true,
    ).allMatches(section).length;
    expect(injected, lessThan(kAiMemoryMaxInjected));
  });

  test('快照总量度量 pin：整份快照远小于 64 KiB 请求闸门（有界证据）', () async {
    // 塞满各段的上限（餐 30、饮水 10、计划 8、记忆 12、自建食物 20）后量
    // 整份快照。这不是裁剪（docs/23 的「6 KB 砍段」从未实现，本轮也不做），
    // 是把「快照有界」从口说变成机器证据：超 32 KB 即失败（64 KiB 的一半，
    // 给历史消息留足余量）。
    await database
        .into(database.profiles)
        .insert(
          ProfilesCompanion.insert(
            id: 'profile-1',
            activityLevel: 'moderate',
            createdAt: now,
            updatedAt: now,
            dietaryPreferencesJson: const Value('["vegetarian"]'),
            allergenAvoidancesJson: const Value('["芒果"]'),
          ),
        );
    for (var index = 0; index < kAiMemoryMaxInjected; index++) {
      await _insertMemory(
        database,
        id: 'memory-$index',
        text: '${'忆' * 138}$index',
        updatedAt: now.subtract(Duration(minutes: index)),
      );
    }

    final snapshot = await loader.build();
    expect(
      snapshot.length,
      lessThan(32 * 1024),
      reason: '整份快照（characters）必须远小于请求闸门',
    );
  });
}

Future<void> _insertMemory(
  AppDatabase database, {
  required String id,
  required String text,
  required DateTime updatedAt,
  String kind = 'fact',
  String domain = 'general',
  bool pinned = false,
}) => database
    .into(database.aiMemories)
    .insert(
      AiMemoriesCompanion.insert(
        id: id,
        textContent: text,
        kind: kind,
        domain: domain,
        pinned: Value(pinned),
        source: 'manual',
        status: const Value('active'),
        createdAt: updatedAt,
        updatedAt: updatedAt,
      ),
    );
