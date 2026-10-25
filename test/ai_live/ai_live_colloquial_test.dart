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
import 'package:localfit_ai/features/hydration/data/water_repository.dart';
import 'package:localfit_ai/features/nutrition/data/dish_library_repository.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';
import 'package:localfit_ai/features/progress/data/measurement_repository.dart';
import 'package:localfit_ai/features/progress/data/steps_repository.dart';
import 'package:localfit_ai/features/settings/data/ai_api_key_store.dart';
import 'package:localfit_ai/features/settings/data/profile_identity_repository.dart';
import 'package:localfit_ai/features/settings/domain/ai_provider_protocol.dart';
import 'package:localfit_ai/features/settings/domain/ai_provider_settings.dart';
import 'package:localfit_ai/features/training/data/exercise_repository.dart';
import 'package:localfit_ai/features/training/data/workout_plan_repository.dart';
import 'package:localfit_ai/features/training/domain/workout_plan.dart';
import 'package:localfit_ai/features/training/data/workout_session_repository.dart';

import '../support/food_fixture.dart';

/// **「通俗说法 → 识别 → 接口命令 → 任务选项/结果」专项实时弹药库**
/// （默认跳过；`LF_AI_LIVE_KEY/BASE/MODEL` 齐了才跑；超时用 `--timeout 300s`）。
///
/// 与 `ai_live_control_matrix_test.dart` 的分工：那份按**命令**逐条覆盖；
/// 这份按**用户嘴里的说法**覆盖 —— 单位/数字变体（半升、中文数字）、口语动词
/// （「不要了」「算晚餐」「收工」）、陈述式约束、编排口语、菜单口述。每条都走
/// App 的真实补救路径（第一趟没信封且本地判定为修改请求 ⇒ 带提示重跑一次），
/// 断言「动作正确 + 真的写库」；「任务选项」断言模型给的每条建议都是已注册命令。
///
/// 【来源】2026-10-16 用户：「主要是要能证明用户的通俗性语言表达，能被软件
/// 模型识别，并正确转化为接口命令，正确返回任务选项和结果。」
void main() {
  final env = Platform.environment;
  final apiKey = env['LF_AI_LIVE_KEY']?.trim() ?? '';
  final baseUrl = env['LF_AI_LIVE_BASE']?.trim() ?? '';
  final model = env['LF_AI_LIVE_MODEL']?.trim() ?? '';

  final today = DateTime(2026, 10, 15, 12).toUtc();
  final clock = FixedAppClock(today);
  final ids = _Ids();
  final skipReason = (apiKey.isEmpty || baseUrl.isEmpty || model.isEmpty)
      ? '未设置 LF_AI_LIVE_KEY / LF_AI_LIVE_BASE / LF_AI_LIVE_MODEL：口语弹药库默认跳过'
      : null;

  final registry = ChatEditCommandRegistry();

  late AppDatabase database;
  late FoodRepository foods;
  late MealRepository meals;
  late DishLibraryRepository dishes;
  late WaterRepository water;
  late CanteenRepository canteen;
  late WorkoutPlanRepository plans;
  late ExerciseRepository exercises;
  late MeasurementRepository measurements;
  late WorkoutSessionRepository sessions;
  late RepositoryChatEditExecutor executor;
  late DriftChatEditContextLoader contextLoader;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await seedFoodFixture(database);
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
    sessions = WorkoutSessionRepository(
      database: database,
      idGenerator: ids,
      clock: clock,
    );
    final stepsRepository = StepsRepository(
      database: database,
      channel: StepsChannel(),
      idGenerator: ids,
      clock: clock,
    );
    executor = RepositoryChatEditExecutor(
      ChatEditServices(
        database: database,
        clock: clock,
        idGenerator: ids,
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
        workoutSessionRepository: sessions,
        stepsRepository: stepsRepository,
        profileIdentityRepository: ProfileIdentityRepository(
          database: database,
        ),
        updateWaterTargetMl: UpdateWaterTargetMl(
          database: database,
          idGenerator: ids,
          clock: clock,
        ),
      ),
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

  Future<List<({ChatEditCommand command, ChatEditApplyResult result})>> ask(
    String request, {
    bool appNudge = true,
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
    final chunks = <String>[];
    final buffer = StringBuffer();
    await service
        .sendMessage(
          messages: [
            ConversationMessage(
              id: 'cq-${DateTime.now().microsecondsSinceEpoch}',
              role: ConversationRole.user,
              text: request,
              createdAt: today,
            ),
          ],
          onProgress: (chunk) {
            chunks.add(chunk);
            buffer.write(chunk);
          },
          systemContext: [registry.renderProtocol(), snapshot].join('\n\n'),
        )
        .drain<void>();
    var turn = parseChatEditTurn(buffer.toString(), registry);
    if (turn == null && appNudge && looksLikeModificationRequest(request)) {
      debugPrint('[cq] ↻ 第一趟无信封 ⇒ 按 App 的补救催一次');
      final retryChunks = <String>[];
      final retryBuffer = StringBuffer();
      await service
          .sendMessage(
            messages: [
              ConversationMessage(
                id: 'cqr-${DateTime.now().microsecondsSinceEpoch}',
                role: ConversationRole.user,
                text: request,
                createdAt: today,
              ),
            ],
            onProgress: (chunk) {
              retryChunks.add(chunk);
              retryBuffer.write(chunk);
            },
            systemContext: [
              registry.renderProtocol(),
              snapshot,
              chatEditEnvelopeNudge,
            ].join('\n\n'),
          )
          .drain<void>();
      turn = parseChatEditTurn(retryBuffer.toString(), registry);
      if (turn != null) {
        chunks.addAll(retryChunks);
        buffer.clear();
        buffer.write(retryBuffer.toString());
      }
    }
    if (turn == null) {
      debugPrint(
        '[cq] ✗ 无信封 · 请求「$request」· 回复头部：'
        '${_head(buffer.toString(), 160)}',
      );
      return const [];
    }
    final applied = <({ChatEditCommand command, ChatEditApplyResult result})>[];
    for (final row in turn.rows) {
      final command = row.command;
      if (command == null) {
        debugPrint('[cq] ✗ 解码失败：${row.decodeError}');
        continue;
      }
      final result = await executor.apply(command);
      applied.add((command: command, result: result));
      debugPrint(
        '[cq] ${result.ok ? '✓' : '✗'} ${command.action} '
        'args=${command.args} → ${result.ok ? '写库成功' : result.message}',
      );
    }
    // 任务选项（suggestions）：模型给的每条建议都必须是已注册命令。
    for (final suggestion in turn.suggestions) {
      expect(
        registry.specOf(suggestion.effectiveAction!),
        isNotNull,
        reason: '建议「${suggestion.effectiveAction}」必须已注册（点了就要能用）',
      );
    }
    return applied;
  }

  List<String> actionsOf(
    List<({ChatEditCommand command, ChatEditApplyResult result})> applied,
  ) => applied.map((entry) => entry.command.action).toList();

  group('通俗说法弹药库（说法 → 识别 → 命令 → 写库）', () {
    test(
      'C01 单位变体：「喝了半升水」= 500 毫升',
      () async {
        final out = await ask('刚才喝了半升水。');
        expect(actionsOf(out), contains('water.add'));
        final rows = await database.select(database.waterIntakes).get();
        expect(rows.fold<double>(0, (sum, row) => sum + row.amountMl), 500);
      },
      timeout: const Timeout(Duration(minutes: 3)),
      skip: skipReason,
    );

    test(
      'C02 中文数字：「六十八点五公斤」= 68.5',
      () async {
        final out = await ask('今天称了一下，六十八点五公斤。');
        expect(actionsOf(out), contains('weight.log'));
        final rows = await database.select(database.measurements).get();
        expect(rows.map((row) => row.weightKg), contains(68.5));
      },
      timeout: const Timeout(Duration(minutes: 3)),
      skip: skipReason,
    );

    test(
      'C03 口语列举：「午饭吃了一碗米饭和两个鸡蛋」→ 一餐两条目',
      () async {
        final out = await ask('午饭吃了一碗米饭和两个鸡蛋。');
        expect(actionsOf(out), contains('meal.create'));
        final items = await database.select(database.mealItems).get();
        expect(items, hasLength(2), reason: '两个食物各一条');
      },
      timeout: const Timeout(Duration(minutes: 3)),
      skip: skipReason,
    );

    test(
      'C04 口语否定：「早上那杯牛奶不要了」→ 删掉那个条目',
      () async {
        // 2026-10-16 首轮实测：只种一条时模型会正确地回「这餐只有这一条食物；
        // 要删整餐请说删掉这餐」（App 的防呆语义）⇒ 想测「删条目」就得给两条。
        final mealId = await meals.create(
          MealDraft(
            localDate: '2026-10-15',
            slot: MealSlot.breakfast,
            items: [
              MealItemDraft.fromFood((await foods.search('牛奶')).first, 250),
              MealItemDraft.fromFood((await foods.search('鸡蛋')).first, 100),
            ],
          ),
        );
        final out = await ask('早上那杯牛奶不要了，帮我删掉。');
        expect(actionsOf(out), contains('meal.item.delete'));
        final items = await database.select(database.mealItems).get();
        expect(
          items.where((row) => row.mealId == mealId),
          hasLength(1),
          reason: '只删牛奶那一条',
        );
        expect(
          items.single.foodNameSnapshot,
          isNot(contains('牛奶')),
          reason: '被删的应是牛奶那条',
        );
      },
      timeout: const Timeout(Duration(minutes: 3)),
      skip: skipReason,
    );

    test(
      'C05 餐次口语：「这顿算晚餐」→ 落到晚餐槽',
      () async {
        final out = await ask('这顿算晚餐：番茄炒蛋一份。');
        expect(actionsOf(out), contains('meal.create'));
        final rows = await database.select(database.meals).get();
        expect(rows.map((row) => row.slot), contains('dinner'));
      },
      timeout: const Timeout(Duration(minutes: 3)),
      skip: skipReason,
    );

    test(
      'C06 陈述式约束：「我对芒果过敏」→ constraints.set',
      () async {
        final out = await ask('我对芒果过敏，别给我安排含芒果的东西。');
        expect(actionsOf(out), contains('constraints.set'));
        final constraints = await PlanningConstraintsRepository(
          database: database,
          clock: clock,
        ).load();
        expect(
          constraints.allergenAvoidances.join(),
          contains('芒果'),
          reason: '忌口要真的落库',
        );
      },
      timeout: const Timeout(Duration(minutes: 3)),
      skip: skipReason,
    );

    test(
      'C07 身体资料口语：缺出生年份/性别时**反问**，补齐后真的落库',
      () async {
        // 2026-10-16 二轮实测：`profile.body.update` 需要出生年份与生理性别才能
        // 算热量公式，模型在缺这两项时会**反问**而不是硬写——这是合规行为
        // （协议：缺信息就在 reply 里说清楚还差什么）。断言分两段：先反问，
        // 补齐后真的落库。
        final out = await ask('我身高一米七五，体重七十公斤。');
        debugPrint('[cq] C07 首轮回复：${out.length}');
        expect(
          out,
          anyOf(isEmpty, isNot(contains('profile.body.update'))),
          reason: '缺出生年份/性别时不应硬写',
        );

        final out2 = await ask('出生年份 1998，生理性别男。');
        expect(actionsOf(out2), contains('profile.body.update'));
        final profileRow = await database.select(database.profiles).getSingle();
        expect(profileRow.heightCm, 175);
        final weight = await (database.select(
          database.measurements,
        )..limit(1)).getSingleOrNull();
        expect(weight, isNotNull, reason: '体重应真的落库');
        expect(weight!.weightKg, 70);
      },
      timeout: const Timeout(Duration(minutes: 3)),
      skip: skipReason,
    );

    test(
      'C08 目标口语：「饮水目标改成两升半」',
      () async {
        final out = await ask('饮水目标改成两升半。');
        expect(actionsOf(out), contains('targets.update'));
        expect(
          await UpdateWaterTargetMl(
            database: database,
            idGenerator: ids,
            clock: clock,
          ).readCurrentMl('2026-10-15'),
          2500,
        );
      },
      timeout: const Timeout(Duration(minutes: 3)),
      skip: skipReason,
    );

    test(
      'C09 编排口语：「周三加一个平板支撑」→ plan.entry.add',
      () async {
        final planId = await plans.create(
          const WorkoutPlanDraft(
            name: '口语编排计划',
            days: [
              WorkoutPlanDayDraft(
                weekday: 3,
                entries: [
                  PlannedExerciseDraft(
                    exerciseId: 'ex-bodyweight-squat',
                    targetSets: 3,
                    targetReps: 10,
                  ),
                ],
              ),
            ],
          ),
        );
        final out = await ask('口语编排计划周三再加一个平板支撑。');
        expect(actionsOf(out), contains('plan.entry.add'));
        final plan = await plans.getById(planId);
        final wednesday = plan!.days.single;
        expect(
          wednesday.entries.map((entry) => entry.exerciseName),
          contains('平板支撑'),
          reason: '新动作应真的编排进去',
        );
      },
      timeout: const Timeout(Duration(minutes: 3)),
      skip: skipReason,
    );

    test(
      'C10 编排口语：「周三那个深蹲去掉」→ plan.entry.remove',
      () async {
        final planId = await plans.create(
          const WorkoutPlanDraft(
            name: '口语删减计划',
            days: [
              WorkoutPlanDayDraft(
                weekday: 3,
                entries: [
                  PlannedExerciseDraft(
                    exerciseId: 'ex-bodyweight-squat',
                    targetSets: 3,
                    targetReps: 10,
                  ),
                ],
              ),
            ],
          ),
        );
        final out = await ask('口语删减计划周三的深蹲不要了，去掉。');
        expect(actionsOf(out), contains('plan.entry.remove'));
        final plan = await plans.getById(planId);
        // removeEntry 的既有语义：删掉最后一条编排时**训练日一并清掉**。
        final entriesLeft = plan!.days.fold<int>(
          0,
          (sum, day) => sum + day.entries.length,
        );
        expect(entriesLeft, 0, reason: '条目应真的被移除');
      },
      timeout: const Timeout(Duration(minutes: 3)),
      skip: skipReason,
    );

    test(
      'C11 改名口语：「计划改名叫周末特训」',
      () async {
        final planId = await plans.create(
          const WorkoutPlanDraft(
            name: '口语改名计划',
            days: [
              WorkoutPlanDayDraft(
                weekday: 6,
                entries: [
                  PlannedExerciseDraft(
                    exerciseId: 'ex-push-up',
                    targetSets: 3,
                    targetReps: 12,
                  ),
                ],
              ),
            ],
          ),
        );
        final out = await ask('把口语改名计划改名叫周末特训。');
        expect(actionsOf(out), contains('plan.rename'));
        expect((await plans.getById(planId))!.name, '周末特训');
      },
      timeout: const Timeout(Duration(minutes: 3)),
      skip: skipReason,
    );

    test(
      'C12 训练口语：「开始训练」→ session.start',
      () async {
        final out = await ask('开始一次自由训练。');
        expect(actionsOf(out), contains('session.start'));
        final session = await sessions.getActive();
        expect(session, isNotNull);
      },
      timeout: const Timeout(Duration(minutes: 3)),
      skip: skipReason,
    );

    test(
      'C13 收工口语：「练完了，收工」→ session.finish',
      () async {
        final sessionId = await sessions.start(localDate: '2026-10-15');
        final out = await ask('练完了，今天收工。');
        expect(actionsOf(out), contains('session.finish'));
        expect(await sessions.getActive(), isNull, reason: '会话应真的结束');
        expect(sessionId, isNotEmpty);
      },
      timeout: const Timeout(Duration(minutes: 3)),
      skip: skipReason,
    );

    test(
      'C14 食堂口语：「新开一个窗口卖牛肉面，早上六点到十点」',
      () async {
        await canteen.createVenue(name: '口语食堂', campusName: '示范校区');
        final out = await ask('口语食堂新开了一个窗口卖牛肉面，早上六点到十点营业，帮我记进去。');
        expect(
          actionsOf(out),
          anyOf(
            contains('canteen.window.create'),
            contains('canteen.venue.create'),
          ),
          reason: '至少要落一个窗口（地点已存在时只建窗口）',
        );
        final venues = await canteen.listVenues();
        final venue = venues.firstWhere((v) => v.name == '口语食堂');
        final windows = await canteen.listWindows(venue.id);
        expect(windows, isNotEmpty, reason: '窗口应真的建出来');
      },
      timeout: const Timeout(Duration(minutes: 3)),
      skip: skipReason,
    );

    test(
      'C15 删除口语：「牛肉面不卖了，删掉」→ canteen.dish.delete',
      () async {
        final venueId = await canteen.createVenue(
          name: '口语食堂二',
          campusName: '示范校区',
        );
        final windowId = await canteen.createWindow(
          venueId: venueId,
          name: '面档',
          openTime: '06:00',
          closeTime: '10:00',
        );
        await canteen.createDish(windowId: windowId, name: '牛肉面');
        final out = await ask('口语食堂二的牛肉面不卖了，帮我删掉。');
        expect(actionsOf(out), contains('canteen.dish.delete'));
        expect(await canteen.listDishes(windowId), isEmpty);
      },
      timeout: const Timeout(Duration(minutes: 3)),
      skip: skipReason,
    );

    test(
      'C16 估值口语：「给牛肉面估个营养」→ canteen.dish.nutrition 落库',
      () async {
        final venueId = await canteen.createVenue(
          name: '口语食堂三',
          campusName: '示范校区',
        );
        final windowId = await canteen.createWindow(
          venueId: venueId,
          name: '面档',
          openTime: '06:00',
          closeTime: '10:00',
        );
        final dishId = await canteen.createDish(
          windowId: windowId,
          name: '牛肉面',
        );
        final out = await ask('给口语食堂三面档的牛肉面估一下每 100 克的营养，等级按 C。');
        expect(actionsOf(out), contains('canteen.dish.nutrition'));
        final dish = (await canteen.listDishes(windowId))
            .firstWhere((d) => d.id == dishId);
        expect(dish.hasNutrition, isTrue, reason: '营养应真的落库（目录读侧可见）');
      },
      timeout: const Timeout(Duration(minutes: 3)),
      skip: skipReason,
    );

    test(
      'C17 菜单口述：「把今天食堂的菜单录进去」→ menu.snapshot.publish',
      () async {
        await canteen.createVenue(name: '口述食堂', campusName: '主校区');
        final out = await ask(
          '把今天口述食堂的菜单录进去：一楼窗口 10:30 到 14:00 卖 番茄炒蛋 和 清炒时蔬。',
        );
        // 2026-10-16 二轮实测：模型可能走 `menu.snapshot.publish`（快照路线），
        // 也可能走 `canteen.window.create` + `canteen.dish.create`（直接建目录）——
        // 两条都是已注册命令、都能把菜单录进去，**都算通过**；判定看落库结果。
        final actions = actionsOf(out);
        final viaSnapshot = actions.contains('menu.snapshot.publish');
        final viaDirect =
            actions.contains('canteen.window.create') &&
            actions.contains('canteen.dish.create');
        expect(
          viaSnapshot || viaDirect,
          isTrue,
          reason: '菜单应真的录进去（快照路线或直接建目录路线均可）',
        );
        if (viaSnapshot) {
          final snapshots = await database.select(database.menuSnapshots).get();
          expect(snapshots.where((row) => row.status == 'active'), isNotEmpty);
        } else {
          final venues = await canteen.listVenues();
          final venue = venues.firstWhere((v) => v.name == '口述食堂');
          final windows = await canteen.listWindows(venue.id);
          expect(windows, isNotEmpty);
          final dishesInWindow = await canteen.listDishes(windows.first.id);
          expect(
            dishesInWindow.map((d) => d.name),
            containsAll(['番茄炒蛋', '清炒时蔬']),
          );
        }
      },
      timeout: const Timeout(Duration(minutes: 3)),
      skip: skipReason,
    );

    test(
      'C18 收录口语：「把番茄炒蛋收录到菜品库（晚餐）」→ dish.upsert',
      () async {
        final out = await ask('把番茄炒蛋收录到菜品库，归到晚餐，每 100 克大概 120 千卡。');
        expect(actionsOf(out), contains('dish.upsert'));
        final rows = await database.select(database.dishLibrary).get();
        expect(rows.map((row) => row.name), contains('番茄炒蛋'));
      },
      timeout: const Timeout(Duration(minutes: 3)),
      skip: skipReason,
    );

    test(
      'C19 范围外口语：「今天走了一万步」→ 没有对应命令，如实回话不乱写',
      () async {
        // 计步数据来自传感器/系统，不走对话写入（注册表里没有这条命令）。
        // 模型该用纯文字回应（或建议手动记录），**绝不能编造一个动作写库**。
        final out = await ask('今天走了一万步。');
        final registered = actionsOf(out)
            .where((action) => registry.specOf(action) != null);
        expect(registered, isEmpty, reason: '没有计步写入命令，不该有任何写库动作');
      },
      timeout: const Timeout(Duration(minutes: 3)),
      skip: skipReason,
    );

    test(
      'C20 目标口语：「我要增肌」→ profile.goal.update',
      () async {
        final out = await ask('我要增肌。');
        expect(actionsOf(out), contains('profile.goal.update'));
        final goals = await database.select(database.goals).get();
        expect(goals.map((row) => row.type), contains('gainMuscle'));
      },
      timeout: const Timeout(Duration(minutes: 3)),
      skip: skipReason,
    );

    test(
      'C21 任务选项：信息不全时模型给**可点的建议**，且每条都已注册',
      () async {
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
        final buffer = StringBuffer();
        await service
            .sendMessage(
              messages: [
                ConversationMessage(
                  id: 'cq-sug-${DateTime.now().microsecondsSinceEpoch}',
                  role: ConversationRole.user,
                  text: '帮我加一个食材。',
                  createdAt: today,
                ),
              ],
              onProgress: buffer.write,
              systemContext: [registry.renderProtocol(), snapshot].join('\n\n'),
            )
            .drain<void>();
        final turn = parseChatEditTurn(buffer.toString(), registry);
        debugPrint(
          '[cq] 建议用例：parsed=${turn != null} '
          'suggestions=${turn?.suggestions.map((s) => s.effectiveAction!).toList()} '
          'head="${_head(buffer.toString(), 120)}"',
        );
        // 2026-10-16 二轮实测：模型**反问**「你要加的是什么食材？…」也是合规
        // 行为——协议允许「缺信息就在 reply 里说清楚还差什么」（不硬塞信封）。
        // 断言口径：要么给信封（含已注册的建议/命令），要么纯文字反问且说清
        // 了缺什么；**不许静默半死**（空回复）。
        expect(buffer.toString().trim(), isNotEmpty, reason: '不许空回复');
        if (turn != null) {
          for (final suggestion in turn.suggestions) {
            expect(
              registry.specOf(suggestion.effectiveAction!),
              isNotNull,
              reason: '建议「${suggestion.effectiveAction}」必须已注册（点了就要能用）',
            );
          }
        }
      },
      timeout: const Timeout(Duration(minutes: 4)),
      skip: skipReason,
    );
  });
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
  _Store(this.value);

  String? value;

  @override
  Future<String?> read(String key) async => value;

  @override
  Future<void> write(String key, String value) async => this.value = value;

  @override
  Future<void> delete(String key) async => value = null;
}

final class _Ids implements IdGenerator {
  var _n = 0;

  @override
  String next() => 'cq-${_n++}';
}
