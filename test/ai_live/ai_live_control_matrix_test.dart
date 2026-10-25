import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/storage/secure_key_value_store.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart'
    hide ConversationMessage;
import 'package:localfit_ai/features/ai_conversation/application/chat_edit_executor.dart';
import 'package:localfit_ai/features/ai_memory/data/ai_memory_repository.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_executor.dart';
import 'package:localfit_ai/features/ai_conversation/data/chat_edit_context_loader.dart';
import 'package:localfit_ai/features/ai_conversation/data/open_ai_compatible_conversation_service.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_command.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_intent.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_registry.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_turn.dart';
import 'package:localfit_ai/features/ai_conversation/domain/conversation_message.dart';
import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart';
import 'package:localfit_ai/features/daily_plan/data/planning_constraints_repository.dart';
import 'package:localfit_ai/features/hydration/application/update_water_target_ml.dart';
import 'package:localfit_ai/features/progress/data/steps_repository.dart';
import 'package:localfit_ai/features/hydration/data/water_repository.dart';
import 'package:localfit_ai/features/nutrition/data/dish_library_repository.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/progress/data/measurement_repository.dart';
import 'package:localfit_ai/features/settings/data/ai_api_key_store.dart';
import 'package:localfit_ai/features/settings/data/profile_identity_repository.dart';
import 'package:localfit_ai/features/settings/domain/ai_provider_protocol.dart';
import 'package:localfit_ai/features/settings/domain/ai_provider_settings.dart';
import 'package:localfit_ai/features/training/data/exercise_repository.dart';
import 'package:localfit_ai/features/training/data/workout_plan_repository.dart';
import 'package:localfit_ai/features/training/data/workout_session_repository.dart';
import 'package:localfit_ai/features/training/domain/workout_session.dart';

import '../support/food_fixture.dart';

/// **「AI 能控制软件到什么程度」的实时控制矩阵**（可选、默认跳过）。
///
/// 与 `ai_live_e2e_test.dart` 的区别：那份测**单点**（探针/流式/信封/草案）；
/// 这份把**每一条已注册的编辑命令**都真跑一遍：
///
///   真模型（自然语言请求）→ App 协议提示 → 真模型输出信封
///     → `parseChatEditTurn`（App 解析）→ `RepositoryChatEditExecutor`（App 执行器）
///     → 真 Drift 写库（内存库）→ 断言库里真的变了
///
/// 其中**快照**用 App 自己的 `DriftChatEditContextLoader`、协议用
/// `ChatEditCommandRegistry.renderProtocol()`——除网络与数据库是"真的"以外，
/// 全链路都是 App 生产代码，没有替身。
///
/// 凭据只从环境变量读（`LF_AI_LIVE_KEY` / `LF_AI_LIVE_BASE` /
/// `LF_AI_LIVE_MODEL`），**未设置整组跳过**，仓库里只有端点与模型名。
// 【工具盲点，2026-10-16 实测】`flutter test` **不认** `@Timeout` 注解
// （放 main 上也照样 30s 掐断），所以实时运行的超时由命令行给：
//   flutter test --timeout 240s test/ai_live/...
// 上游 `deepseek-ai/deepseek-v4.1-flash` 实测 TTFB ≈ 11s、整请求 40–46s，
// 默认 30s 会在「app 的传输上限」之前先把用例打断 ⇒ 结论被工具掩盖。
void main() {
  final env = Platform.environment;
  final apiKey = env['LF_AI_LIVE_KEY']?.trim() ?? '';
  final baseUrl = env['LF_AI_LIVE_BASE']?.trim() ?? '';
  final model = env['LF_AI_LIVE_MODEL']?.trim() ?? '';
  final skipReason = (apiKey.isEmpty || baseUrl.isEmpty || model.isEmpty)
      ? '未设置 LF_AI_LIVE_KEY / LF_AI_LIVE_BASE / LF_AI_LIVE_MODEL：实时控制矩阵默认跳过'
      : null;

  final today = DateTime(2026, 10, 15, 12).toUtc();
  final clock = FixedAppClock(today);
  final ids = _Ids();

  late AppDatabase database;
  late FoodRepository foods;
  late MealRepository meals;
  late DishLibraryRepository dishes;
  late WaterRepository water;
  late CanteenRepository canteen;
  late WorkoutPlanRepository plans;
  late ExerciseRepository exercises;
  late MeasurementRepository measurements;
  late RepositoryChatEditExecutor executor;
  late WorkoutSessionRepository sessions;
  late DriftChatEditContextLoader contextLoader;
  final registry = ChatEditCommandRegistry();

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await seedFoodFixture(database);
    // 训练计划命令按名字解析动作 ⇒ 库里必须真的有动作。
    // **不**用 `ExerciseSeedImporter`：它读 asset bundle，要 `TestWidgetsFlutterBinding`，
    // 而那个 binding 会把所有真实 HTTP 拦成 400（实测），与"打真模型"冲突。
    // 这里直接插与模型说法一致的最小动作集（生产安装即带 312 条，语义等价）。
    for (final (id, name, group, equipment) in const [
      ('ex-push-up', '俯卧撑', 'chest', 'bodyweight'),
      ('ex-plank', '平板支撑', 'core', 'bodyweight'),
      ('ex-barbell-squat', '杠铃深蹲', 'legs', 'barbell'),
      ('ex-bodyweight-squat', '深蹲', 'legs', 'bodyweight'),
    ]) {
      await database
          .into(database.exercises)
          .insert(
            ExercisesCompanion.insert(
              id: id,
              name: name,
              muscleGroup: group,
              equipment: equipment,
              source: 'test',
              createdAt: today,
              updatedAt: today,
            ),
          );
    }
    await database
        .into(database.profiles)
        .insert(
          ProfilesCompanion.insert(
            id: 'profile-1',
            activityLevel: 'moderate',
            createdAt: today,
            updatedAt: today,
          ),
        );
    await database
        .into(database.goals)
        .insert(
          GoalsCompanion.insert(
            id: 'goal-1',
            profileId: 'profile-1',
            type: 'maintain',
            calorieMinKcal: 1700,
            calorieMaxKcal: 1900,
            effectiveFrom: today,
            createdAt: today,
            updatedAt: today,
          ),
        );
    // 每日目标生效行（建档产物）：`targets.update` 写水目标的前置。
    await database
        .into(database.dailyTargets)
        .insert(
          DailyTargetsCompanion.insert(
            id: 'dt-1',
            goalId: 'goal-1',
            effectiveDate: '2026-10-01',
            calorieMinKcal: 1700,
            calorieMaxKcal: 1900,
            proteinMinGrams: 90,
            proteinMaxGrams: 130,
            carbsMinGrams: 180,
            carbsMaxGrams: 260,
            fatMinGrams: 40,
            fatMaxGrams: 70,
            createdAt: today,
            updatedAt: today,
          ),
        );
    foods = FoodRepository(database: database, idGenerator: ids, clock: clock);
    meals = MealRepository(database: database, idGenerator: ids, clock: clock);
    dishes = DishLibraryRepository(
      database: database,
      idGenerator: ids,
      clock: clock,
    );
    water = WaterRepository(database: database, idGenerator: ids, clock: clock);
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
    measurements = MeasurementRepository(
      database: database,
      idGenerator: ids,
      clock: clock,
    );
    executor = RepositoryChatEditExecutor(
      ChatEditServices(
        database: database,
        clock: clock,
        foodRepository: foods,
        aiMemoryRepository: AiMemoryRepository(
          database: database,
          clock: clock,
          idGenerator: ids,
        ),
        mealRepository: meals,
        dishLibraryRepository: dishes,
        waterRepository: water,
        measurementRepository: measurements,
        planningConstraintsRepository: PlanningConstraintsRepository(
          database: database,
          clock: clock,
        ),
        canteenRepository: canteen,
        workoutPlanRepository: plans,
        exerciseRepository: exercises,
        workoutSessionRepository: WorkoutSessionRepository(
          database: database,
          idGenerator: ids,
          clock: clock,
        ),
        profileIdentityRepository: ProfileIdentityRepository(
          database: database,
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
    sessions = WorkoutSessionRepository(
      database: database,
      idGenerator: ids,
      clock: clock,
    );
    contextLoader = DriftChatEditContextLoader(
      database: database,
      clock: clock,
      mealRepository: meals,
      dishLibraryRepository: dishes,
      waterRepository: water,
      canteenRepository: canteen,
      workoutPlanRepository: plans,
      workoutSessionRepository: sessions,
    );
  });

  tearDown(() => database.close());

  /// 走一遍真实链路：请求 → 真模型 → 解析 → 执行；返回（命令, 执行结果）。
  Future<List<({ChatEditCommand command, ChatEditApplyResult result})>> ask(
    String request, {

    /// 追加到 system 段的提示（「催信封」用；等价于 App 的自动补救）。
    String? extraContext,

    /// 复刻 App 的**自动补救**：第一趟没信封、而本地判定这句话是修改请求时，
    /// 带 `chatEditEnvelopeNudge` 重跑一次（与 `ConversationController` 的
    /// 行为同序：先原样问，再催一次，最多一次）。
    bool appNudge = false,
  }) async {
    final service = OpenAiCompatibleConversationService(
      dio: Dio(),
      configurationReader: _Config(
        AiProviderConfiguration(
          baseUrl: baseUrl,
          model: model,
          protocol: AiProviderProtocol.chatCompletions,
        ),
      ),
      apiKeyStore: AiApiKeyStore(store: _Store(apiKey)),
    );
    final snapshot = await contextLoader.build();
    if (Platform.environment['LF_MX_SNAPSHOT'] == '1') {
      debugPrint('[mx-snapshot-begin]');
      debugPrint(snapshot);
      debugPrint('[mx-snapshot-end]');
    }
    final chunks = <String>[];
    final buffer = StringBuffer();
    await service
        .sendMessage(
          messages: [
            ConversationMessage(
              id: 'mx-${DateTime.now().microsecondsSinceEpoch}',
              role: ConversationRole.user,
              text: request,
              createdAt: today,
            ),
          ],
          onProgress: (chunk) {
            chunks.add(chunk);
            buffer.write(chunk);
          },
          systemContext: [
            registry.renderProtocol(),
            snapshot,
            ?extraContext,
          ].join('\n\n'),
        )
        .drain<void>();
    var turn = parseChatEditTurn(buffer.toString(), registry);
    if (turn == null && appNudge && looksLikeModificationRequest(request)) {
      debugPrint('[mx] ↻ 无信封且本地判定为修改请求 ⇒ 按 App 的补救催一次');
      return ask(
        request,
        extraContext: [?extraContext, chatEditEnvelopeNudge].join('\n'),
      );
    }
    if (turn == null) {
      debugPrint(
        '[mx] ✗ 无信封 · 请求「$request」· 回复头部：'
        '${_head(buffer.toString(), 160)}',
      );
      return const [];
    }
    final applied = <({ChatEditCommand command, ChatEditApplyResult result})>[];
    for (final row in turn.rows) {
      final command = row.command;
      if (command == null) {
        debugPrint('[mx] ✗ 命令解码失败：${row.decodeError}');
        continue;
      }
      final result = await executor.apply(command);
      applied.add((command: command, result: result));
      debugPrint(
        '[mx] ${result.ok ? '✓' : '✗'} ${command.action} '
        'args=${command.args} → ${result.ok ? '写库成功' : result.message}',
      );
    }
    return applied;
  }

  group('AI 控制矩阵（真模型 → App 解析 → App 执行器 → 真库）', () {
    test('① 体重：记录一条今天的体重', () async {
      final out = await ask('记录今天的体重 72.5 公斤，备注「早上称的」。');
      expect(out.map((e) => e.command.action), contains('weight.log'));
      final rows = await database.select(database.measurements).get();
      debugPrint('[mx] measurements=$rows');
      expect(rows, hasLength(1));
      expect(rows.single.weightKg, closeTo(72.5, 0.001));
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('② 饮水：先记一笔，再按快照里的 id 删掉它', () async {
      final add = await ask('我喝了 250 毫升水，记一笔。');
      expect(add.map((e) => e.command.action), contains('water.add'));
      final rows = await database.select(database.waterIntakes).get();
      expect(rows, hasLength(1), reason: 'water.add 应真的落库');
      expect(rows.single.amountMl, 250);

      final del = await ask('把刚才那条 250 毫升的饮水记录删掉。');
      expect(del.map((e) => e.command.action), contains('water.delete'));
      expect(await database.select(database.waterIntakes).get(), isEmpty);
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('③ 餐食：建一餐 → 改条目克数 → 删条目 → 改备注 → 删整餐', () async {
      final created = await ask('帮我记早餐：鸡蛋 2 个（约 100 克）和米饭 150 克，用食物库里的食物。');
      expect(created.map((e) => e.command.action), contains('meal.create'));
      final mealRows = await database.select(database.meals).get();
      expect(mealRows, hasLength(1), reason: 'meal.create 应真的落库');
      final items = await database.select(database.mealItems).get();
      expect(items, isNotEmpty);
      debugPrint(
        '[mx] meal=${mealRows.single.localDate}/${mealRows.single.slot} '
        'items=${items.map((i) => '${i.foodNameSnapshot}:${i.grams}g').toList()}',
      );

      final updated = await ask('把这一餐里鸡蛋的克数改成 150 克。');
      expect(
        updated.map((e) => e.command.action),
        contains('meal.item.update'),
      );
      final afterUpdate = await database.select(database.mealItems).get();
      expect(
        afterUpdate.any((i) => (i.grams - 150).abs() < 0.001),
        isTrue,
        reason: 'meal.item.update 应真的改库：$afterUpdate',
      );

      final removed = await ask('把这一餐里的米饭删掉。');
      expect(
        removed.map((e) => e.command.action),
        contains('meal.item.delete'),
      );
      final afterDelete = await database.select(database.mealItems).get();
      expect(afterDelete.length, lessThan(afterUpdate.length));

      final noted = await ask('给这一餐加个备注：去公司路上吃的。');
      expect(noted.map((e) => e.command.action), contains('meal.update'));
      final mealAfter = await database.select(database.meals).get();
      expect(mealAfter.single.notes, isNotNull);

      final dropped = await ask('把这一餐整个删掉。');
      expect(dropped.map((e) => e.command.action), contains('meal.delete'));
      expect(await database.select(database.meals).get(), isEmpty);
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('④ 自建食物：新建一个自定义食材', () async {
      final out = await ask(
        '新建一个自定义食材：燕麦拿铁，每 100 克 62 千卡，蛋白质 1.2 克，'
        '碳水 9 克，脂肪 2.1 克。',
      );
      expect(out.map((e) => e.command.action), contains('food.create'));
      final rows = await database.select(database.foods).get();
      final created = rows.where((f) => f.name.contains('燕麦拿铁')).toList();
      expect(created, hasLength(1), reason: 'food.create 应真的落库');
      expect(created.single.kcalPer100g, closeTo(62, 0.001));
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('⑤ 菜品：收录一道菜 → 再删掉它', () async {
      final out = await ask(
        '把「番茄炒蛋」收录进菜品库：午餐，每份 120 千卡，蛋白质 7 克，'
        '碳水 5 克，脂肪 8 克。',
      );
      expect(out.map((e) => e.command.action), contains('dish.upsert'));
      final rows = await database.select(database.dishLibrary).get();
      expect(rows.any((d) => d.name.contains('番茄炒蛋')), isTrue);

      final del = await ask('把菜品库里那道「番茄炒蛋」删掉。');
      expect(del.map((e) => e.command.action), contains('dish.delete'));
      final after = await database.select(database.dishLibrary).get();
      expect(after.any((d) => d.name.contains('番茄炒蛋')), isFalse);
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('⑥ 食堂目录：建地点 → 建窗口 → 加菜品 → 改名 → 改价 → 删菜品 → 删窗口 → 删地点', () async {
      final created = await ask(
        '食堂目录里加一个地点「三食堂」，南校区；再给它加一个窗口'
        '「4 号窗口」，11:00 到 13:30；这个窗口新增菜品「番茄牛腩」12.5 元。',
      );
      final actions = created.map((e) => e.command.action).toList();
      debugPrint('[mx] 食堂建立动作=$actions');
      expect(actions, contains('canteen.venue.create'));
      expect(
        (await canteen.listVenues()).any((v) => v.name.contains('三食堂')),
        isTrue,
      );

      // 依赖 id 的后续操作只在模型把前置步骤真的建出来后再跑。
      final venues = await canteen.listVenues();
      final venue = venues.firstWhere((v) => v.name.contains('三食堂'));
      final windows = await canteen.listWindows(venue.id);
      if (windows.isEmpty) {
        debugPrint('[mx] 窗口未建立（模型未给 window.create）——如实记录');
      } else {
        final win = windows.first;
        final dish = win.dishes.isEmpty ? null : win.dishes.first;
        final renamed = await ask('把食堂地点「三食堂」改名成「第三食堂」。');
        expect(
          renamed.map((e) => e.command.action),
          contains('canteen.venue.rename'),
        );
        expect(
          (await canteen.listVenues()).any((v) => v.name.contains('第三食堂')),
          isTrue,
        );
        if (dish != null) {
          final repriced = await ask('把食堂菜品「番茄牛腩」的价格改成 14 元。');
          debugPrint('[mx] 改价动作=${repriced.map((e) => e.command.action)}');
        }
        final windowDeleted = await ask('把「第三食堂」下的窗口「4 号窗口」删掉（连带里面的菜品）。');
        debugPrint('[mx] 删窗口动作=${windowDeleted.map((e) => e.command.action)}');
      }
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('⑦ 健康目标与约束：改目标、设忌口', () async {
      final goal = await ask('把我的健康目标改成减脂，目标体重 65 公斤。');
      expect(
        goal.map((e) => e.command.action),
        contains('profile.goal.update'),
      );
      final goals = await database.select(database.goals).get();
      debugPrint(
        '[mx] goals=${goals.map((g) => '${g.type}/${g.targetWeightKg}').toList()}',
      );
      expect(goals.any((g) => g.type == 'cut' || g.type == 'loseFat'), isTrue);

      final constraints = await ask('我忌口花生和海鲜，饮食上偏素食。');
      expect(
        constraints.map((e) => e.command.action),
        contains('constraints.set'),
      );
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('⑧ 训练计划：建一份 → 删掉它', () async {
      final created = await ask(
        '用本地动作库创建一份训练计划：名字叫「AI 控制测试计划」，'
        '周一和周四各练一天，动作从平板支撑、俯卧撑里选。',
      );
      expect(
        created.map((e) => e.command.action),
        contains('workout.plan.create'),
      );
      final rows = await plans.list();
      expect(rows.any((p) => p.name.contains('AI 控制测试计划')), isTrue);
      final days = await database.select(database.workoutDays).get();
      final entries = await database.select(database.plannedExercises).get();
      debugPrint('[mx] plan days=${days.length} entries=${entries.length}');

      final deleted = await ask('把「AI 控制测试计划」这份训练计划删掉。');
      expect(
        deleted.map((e) => e.command.action),
        contains('workout.plan.delete'),
      );
      expect(
        (await plans.list()).any((p) => p.name.contains('AI 控制测试计划')),
        isFalse,
      );
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('⑩ 训练域（批次 A）：开始 → 记组 → 结束，真的落进会话与组', () async {
      final started = await ask('开始一次自由训练。');
      expect(started.map((e) => e.command.action), contains('session.start'));
      final session =
          (await database.select(database.workoutSessions).get()).single;
      expect(session.status, 'active');

      final logged = await ask('刚做了 3 组平板支撑，每组 60 次。');
      debugPrint('[mx] 记组动作=${logged.map((e) => e.command.action).toList()}');
      final sets = await database.select(database.workoutSets).get();
      debugPrint('[mx] sets=${sets.map((s) => '${s.reps}次').toList()}');
      expect(logged.map((e) => e.command.action), contains('set.log'));
      expect(sets, isNotEmpty, reason: 'set.log 应真的落库');

      final finished = await ask('训练结束了，收工。');
      expect(finished.map((e) => e.command.action), contains('session.finish'));
      final after =
          (await database.select(database.workoutSessions).get()).single;
      expect(after.status, 'finished');
      expect(after.finishedAt, isNotNull);
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('⑯ 陈述式约束（App 兜底路径）：模型先散文后 JSON 时靠催信封救回来', () async {
      // 2026-10-16 实测：用户说「我忌口花生和海鲜，饮食上偏素食。」时模型会
      // 写成「好的，已记下…」+ 信封（散文在前）⇒ 严格解析丢掉 ⇒ **什么都没写**。
      // App 的补救＝本地判定「这是修改请求」+ 带提示重跑（本用例复刻同序）。
      // 本地判定曾经漏掉这类**陈述式**约束，已按新事实补齐（见
      // `chat_edit_intent.dart` 的 `_constraintPatterns`）。
      final out = await ask('我忌口花生和海鲜，饮食上偏素食。', appNudge: true);
      debugPrint('[mx] 约束动作=${out.map((e) => e.command.action).toList()}');
      expect(
        out.map((e) => e.command.action),
        contains('constraints.set'),
        reason: 'App 催过一次后必须拿到可应用约束信封（否则用户看到「已记下」却没写）',
      );
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('⑰ 进行中的训练进快照后，模型真的能「收工」', () async {
      // 2026-10-16 实测：快照里没有进行中的会话时，模型回「你这边现在还没有
      // 进行中的训练会话」⇒ 永远不发 session.finish。补了快照段之后，
      // 这句口语必须能落成 session.finish 并真的把会话结束掉。
      final sessionId = await sessions.start(localDate: '2026-10-15');
      await sessions.logSet(
        sessionId,
        const WorkoutSetDraft(exerciseId: 'ex-plank', weightKg: 0, reps: 60),
      );
      final snapshot = await contextLoader.build();
      expect(snapshot, contains('【进行中的训练】'), reason: '快照必须带上这一段');

      final finished = await ask('训练结束了，收工。', appNudge: true);
      debugPrint('[mx] 收工动作=${finished.map((e) => e.command.action).toList()}');
      expect(finished.map((e) => e.command.action), contains('session.finish'));
      final active = await sessions.getActive();
      expect(active, isNull, reason: '会话应真的结束（status=finished）');
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('⑱ 计划编排三连：改名 → 加动作 → 去动作', () async {
      final created = await ask(
        '用本地动作库创建一份训练计划：名字叫「编排测试计划」，周一练一天，'
        '动作从平板支撑、俯卧撑里选。',
      );
      expect(
        created.map((e) => e.command.action),
        contains('workout.plan.create'),
      );
      final plan = (await plans.list()).firstWhere(
        (p) => p.name.contains('编排测试计划'),
      );

      final renamed = await ask('把「编排测试计划」改名为「编排测试计划 v2」。');
      debugPrint('[mx] 改名动作=${renamed.map((e) => e.command.action).toList()}');
      expect(renamed.map((e) => e.command.action), contains('plan.rename'));

      final added = await ask('在「编排测试计划 v2」的周一里再加一个动作：杠铃深蹲 4 组 8 次。');
      debugPrint('[mx] 加动作=${added.map((e) => e.command.action).toList()}');
      expect(added.map((e) => e.command.action), contains('plan.entry.add'));
      final entriesAfterAdd = await database
          .select(database.plannedExercises)
          .get();
      expect(entriesAfterAdd.length, greaterThanOrEqualTo(1));

      final removed = await ask('把「编排测试计划 v2」里周一那个杠铃深蹲去掉。');
      debugPrint('[mx] 去动作=${removed.map((e) => e.command.action).toList()}');
      expect(
        removed.map((e) => e.command.action),
        contains('plan.entry.remove'),
      );
      final remaining = await database.select(database.plannedExercises).get();
      expect(
        remaining.where((row) => row.id == entriesAfterAdd.last.id).isEmpty,
        isTrue,
        reason: '指定的那条编排应真的被删掉',
      );
      await plans.removePlan(plan.id);
    }, timeout: const Timeout(Duration(minutes: 4)));

    test('⑲ 食堂：删地点 + 给菜品估营养（N3 落库口）', () async {
      final venueId = await canteen.createVenue(
        name: '待删食堂',
        campusName: '南校区',
      );
      final windowId = await canteen.createWindow(
        venueId: venueId,
        name: '一楼窗口',
        openTime: '08:00',
        closeTime: '13:30',
      );
      final dishId = await canteen.createDish(
        windowId: windowId,
        name: '番茄牛腩饭',
      );

      final nutrition = await ask(
        '给 [canteen-dish:$dishId] 番茄牛腩饭估算每 100 克营养：'
        '热量、蛋白质、碳水、脂肪都给一个值，证据等级按 C，别问我。',
      );
      debugPrint(
        '[mx] 营养动作=${nutrition.map((e) => e.command.action).toList()}',
      );
      expect(
        nutrition.map((e) => e.command.action),
        contains('canteen.dish.nutrition'),
      );
      final dish = await canteen.listDishes(windowId);
      final analyzed = dish.firstWhere((d) => d.id == dishId);
      expect(
        analyzed.hasNutrition,
        isTrue,
        reason: '目录读侧必须从「未分析」变成「已分析」（N3 的正面判据）',
      );

      final deleted = await ask('「待删食堂」这个地点不要了，删掉。');
      debugPrint('[mx] 删地点=${deleted.map((e) => e.command.action).toList()}');
      expect(
        deleted.map((e) => e.command.action),
        contains('canteen.venue.delete'),
      );
      expect((await canteen.listVenues()).any((v) => v.id == venueId), isFalse);
    }, timeout: const Timeout(Duration(minutes: 4)));

    test('⑳ 长期记忆：记住 → 快照带上 → 忘掉（S11）', () async {
      final remembered = await ask('记住：我周三晚上练腿。这是习惯，归到训练。', appNudge: true);
      debugPrint(
        '[mx] 记忆动作=${remembered.map((e) => e.command.action).toList()}',
      );
      expect(
        remembered.map((e) => e.command.action),
        contains('memory.remember'),
      );
      final rows = await database.select(database.aiMemories).get();
      expect(rows, hasLength(1));
      expect(rows.single.textContent, contains('练腿'));

      // 确定性判据：下一趟的 system 段（快照）必须带上这条记忆——这才是
      // 「跨会话记得」的证据（模型回复是行为判据，受措辞影响）。
      final snapshot = await contextLoader.build();
      expect(snapshot, contains('【关于用户的长期记忆】'));
      expect(snapshot, contains('练腿'));

      final forgotten = await ask('别记这个了：周三晚上练腿。', appNudge: true);
      debugPrint(
        '[mx] 遗忘动作=${forgotten.map((e) => e.command.action).toList()}',
      );
      expect(forgotten.map((e) => e.command.action), contains('memory.forget'));
      expect(await database.select(database.aiMemories).get(), isEmpty);
    }, timeout: const Timeout(Duration(minutes: 4)));

    test('⑪ 自建食物（批次 C）：建 → 用快照 id 改热量 → 删掉', () async {
      final created = await ask('新建自定义食材：测试气泡水，每 100 克 10 千卡，蛋白 0，碳水 2，脂肪 0。');
      expect(created.map((e) => e.command.action), contains('food.create'));
      final row = (await database.select(database.foods).get()).firstWhere(
        (f) => f.name.contains('测试气泡水'),
      );

      final updated = await ask('把「测试气泡水」的热量改成每 100 克 25 千卡。');
      debugPrint('[mx] 改食物动作=${updated.map((e) => e.command.action).toList()}');
      expect(updated.map((e) => e.command.action), contains('food.update'));
      final after = (await database.select(database.foods).get()).firstWhere(
        (f) => f.id == row.id,
      );
      expect(after.kcalPer100g, closeTo(25, 0.001));

      final deleted = await ask('把「测试气泡水」从食物库删掉。');
      expect(deleted.map((e) => e.command.action), contains('food.delete'));
      expect(
        (await database.select(database.foods).get()).any(
          (f) => f.id == row.id,
        ),
        isFalse,
      );
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('⑬ 菜单快照发布（批次 B）：真模型出结构化草案 → 发布 → 菜单 tab 当日入口可见', () async {
      // 发布要求库里有校园 ⇒ 按真实动线：先让 AI 建地点，再发布菜单。
      final venue = await ask('在菜单里加一个食堂地点「三食堂」，南校区。');
      expect(
        venue.map((e) => e.command.action),
        contains('canteen.venue.create'),
      );
      final out = await ask(
        '把这条菜单整理发布：地点「三食堂」，窗口「4 号窗口」11:00–13:30，'
        '菜：番茄牛腩 12.5 元、清炒时蔬 6 元。',
      );
      debugPrint('[mx] 菜单发布动作=${out.map((e) => e.command.action).toList()}');
      if (!out.any((e) => e.command.action == 'menu.snapshot.publish')) {
        debugPrint(
          '[mx] 模型未给出 menu.snapshot.publish —— 如实记录（命令本身由 mock '
          '27/27 覆盖）',
        );
        return;
      }
      final published = out.firstWhere(
        (e) => e.command.action == 'menu.snapshot.publish',
      );
      expect(published.result.ok, isTrue, reason: published.result.message);
      final snapshots = await (database.select(
        database.menuSnapshots,
      )..where((row) => row.status.equals('active'))).get();
      debugPrint(
        '[mx] active snapshots=${snapshots.length} '
        'services=${(await database.select(database.menuServices).get()).length} '
        'items=${(await database.select(database.menuItems).get()).length}',
      );
      expect(snapshots, isNotEmpty, reason: '发布应留下 active 快照');
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('⑫ 资料与目标（批次 C）：身高/出生年/性别 + 饮水与步数目标', () async {
      final body = await ask('我身高 172 厘米，1998 年出生，生理性别男。');
      expect(
        body.map((e) => e.command.action),
        contains('profile.body.update'),
      );
      final profile = (await database.select(database.profiles).get()).single;
      debugPrint(
        '[mx] profile=${profile.heightCm}/${profile.birthYear}/'
        '${profile.biologicalSex}',
      );
      expect(profile.heightCm, closeTo(172, 0.001));
      expect(profile.biologicalSex, 'male');

      final targets = await ask('把每日饮水目标改成 2.5 升，步数目标 9000 步。');
      expect(targets.map((e) => e.command.action), contains('targets.update'));
      // 水目标写的是「从今天起生效的**新一行**」（保留历史，与资料编辑同一
      // 用例语义）⇒ 按用例自己的读接口取当前生效值，不臆测只有一行。
      final currentMl = await UpdateWaterTargetMl(
        database: database,
        idGenerator: ids,
        clock: clock,
      ).readCurrentMl('2026-10-15');
      debugPrint('[mx] water=$currentMl');
      expect(currentMl, closeTo(2500, 0.001));
    }, timeout: const Timeout(Duration(minutes: 3)));

    // 2026-10-16 新增两条（对应本轮用户实测的两个缺陷）。
    test('⑭ 口语请求要出信封（口语=命令）且缺食材时给可点修复建议', () async {
      // 用户原话的场景：「说『添加鸡肉食材』只有回复、没有应用按钮」。
      // 库里没有「鸡肉」（体检夹具里没有自建食物），所以正确行为是：
      // 模型按 food.create 建它（口语→命令），或者给出 suggestions。
      final out = await ask('添加鸡肉食材。');
      debugPrint('[mx] 口语请求动作=${out.map((e) => e.command.action).toList()}');
      expect(out, isNotEmpty, reason: '口语请求必须产出信封（旧版只回文字，没有应用按钮）');
      expect(
        out.map((e) => e.command.action),
        anyElement(anyOf(equals('food.create'), equals('meal.create'))),
        reason: '「添加鸡肉食材」应翻译成建食材或记一餐，而不是只回一句话',
      );

      // 缺食材兜底：meal.create 引用库里没有的名字 ⇒ 失败结果带结构化 repair。
      final missing = await executor.apply(
        ChatEditCommand(
          spec: registry.specOf('meal.create')!,
          args: validateChatEditArgs(registry.specOf('meal.create')!, {
            'slot': '午餐',
            'items': [
              {
                'food': '库里绝对没有的食物-${DateTime.now().microsecondsSinceEpoch}',
                'grams': 100.0,
              },
            ],
          }),
        ),
      );
      expect(missing.ok, isFalse);
      expect(
        missing.missingFoodName,
        isNotNull,
        reason: '缺食材必须带结构化修复提示（App 据此渲染「创建食材」按钮）',
      );
      debugPrint(
        '[mx] repair=${missing.missingFoodName} 文案=${missing.message}',
      );
    }, timeout: const Timeout(Duration(minutes: 3)));

    // 2026-10-16（用户：「涉及修改就必须正确识别指令，而不是空回文字」）：
    // App 侧的自动补救＝「带提示重跑一次」。这里实证它**真的救得回来**：
    // 同一句含糊的修改请求，第一次可能只拿到文字；带上提示再问必须有信封
    // （信封里可以是 suggestions：减脂/维持/增肌 三个可点选项）。
    // 2026-10-16（用户：「涉及修改就必须正确识别指令，而不是空回文字」）：
    // App 侧的自动补救＝「带提示重跑一次」，目标正是**模型先写说明再贴 JSON
    // 被严格解析丢掉**这一族（r8-mx-full2 里 ⑦/⑩/⑫ 三条就是它）。
    // 这里实证：同一条请求，带提示重跑能拿到可应用信封。
    test('⑮ 「先说明再贴 JSON」的场景：带提示重跑必须给出可应用信封', () async {
      const request = '把我的健康目标改成减脂，热量区间 1400–1600 kcal。';
      final plain = await ask(request);
      debugPrint(
        '[mx] 不带提示：动作=${plain.map((e) => e.command.action).toList()}'
        '（模型自律性不同，这一趟出不出信封不做断言）',
      );

      final nudged = await ask(request, extraContext: chatEditEnvelopeNudge);
      debugPrint(
        '[mx] 催信封后：动作=${nudged.map((e) => e.command.action).toList()}',
      );
      expect(
        nudged,
        isNotEmpty,
        reason:
            '带上「整段只放一个 JSON、禁止解释」的提示后必须能解析出信封——'
            '这正是 App 自动补救要救的场景',
      );
      expect(
        nudged.map((e) => e.command.action),
        anyElement(
          anyOf(equals('profile.goal.update'), equals('targets.update')),
        ),
        reason: '健康目标可由 profile.goal.update / targets.update 表达',
      );
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('⑨ 越界请求应被拒（快照里没有的 id / 未注册的命令）', () async {
      final out = await ask('把食堂地点 [venue:不存在的id] 删掉；再把我的 API Key 改成 abc。');
      debugPrint(
        '[mx] 越界请求动作=${out.map((e) => e.command.action).toList()} '
        '结果=${out.map((e) => e.result.ok).toList()}',
      );
      // 不注册设置类命令：即便模型硬给，也必须是解码失败或执行失败，
      // 绝不能真的动到凭据面。
      for (final row in out) {
        expect(row.command.action, isNot(contains('apiKey')));
      }
    }, timeout: const Timeout(Duration(minutes: 3)));
  }, skip: skipReason);
}

String _head(String value, int max) {
  final flat = value.replaceAll('\n', ' ');
  return flat.length <= max ? flat : '${flat.substring(0, max)}…';
}

final class _Config implements AiProviderConfigurationReader {
  const _Config(this._value);
  final AiProviderConfiguration _value;
  @override
  Future<AiProviderConfiguration?> loadConfiguration() async => _value;
}

final class _Store implements SecureKeyValueStore {
  _Store(this._value);
  final String _value;
  @override
  Future<String?> read(String key) async => _value;
  @override
  Future<void> write(String key, String value) async {}
  @override
  Future<void> delete(String key) async {}
}

final class _Ids implements IdGenerator {
  int _value = 0;
  @override
  String next() => 'mx-${_value++}';
}
