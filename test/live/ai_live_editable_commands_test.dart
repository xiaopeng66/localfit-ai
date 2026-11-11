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
import 'package:localfit_ai/features/ai_conversation/data/chat_edit_context_loader.dart';
import 'package:localfit_ai/features/ai_conversation/data/open_ai_compatible_conversation_service.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_command.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_executor.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_intent.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_registry.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_turn.dart';
import 'package:localfit_ai/features/ai_conversation/domain/conversation_message.dart';
import 'package:localfit_ai/features/ai_memory/data/ai_memory_repository.dart';
import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart';
import 'package:localfit_ai/features/daily_plan/data/planning_constraints_repository.dart';
import 'package:localfit_ai/features/hydration/application/update_water_target_ml.dart';
import 'package:localfit_ai/features/hydration/data/water_repository.dart';
import 'package:localfit_ai/features/nutrition/application/food_catalog_service.dart';
import 'package:localfit_ai/features/nutrition/application/master_nutrition_sink_adapter.dart';
import 'package:localfit_ai/features/nutrition/data/dish_library_repository.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/nutrition/data/supply_catalog_repository.dart';
import 'package:localfit_ai/features/progress/data/measurement_repository.dart';
import 'package:localfit_ai/features/progress/data/steps_repository.dart';
import 'package:localfit_ai/features/settings/data/ai_api_key_store.dart';
import 'package:localfit_ai/features/settings/data/profile_identity_repository.dart';
import 'package:localfit_ai/features/settings/domain/ai_provider_protocol.dart';
import 'package:localfit_ai/features/settings/domain/ai_provider_settings.dart';
import 'package:localfit_ai/features/training/data/exercise_repository.dart';
import 'package:localfit_ai/features/training/data/workout_plan_repository.dart';
import 'package:localfit_ai/features/training/data/workout_session_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/nutrition_target_override.dart';
import 'package:localfit_ai/features/training/domain/exercise_record.dart';
import 'package:localfit_ai/features/training/domain/workout_plan.dart';

/// 新增可编辑命令的**真实模型语句适用性**（2026-11-11）。
///
/// 与 `ai_live_control_matrix_test.dart` 的差别：
/// * 默认用 `appNudge: true` 复刻 App 的「本地判定为修改请求 ⇒ 催一次信封」，
///   因为 App 真实路径就是这么走的，只测第一趟会把模型偶发的空信封误判成
///   功能坏掉；
/// * 覆盖 v4144/v4145 新增的命令：食堂收录、按窗口+菜名补营养、改份量、
///   改组次/重量、新建动作、营养目标 set/reset；
/// * 三个「模型首轮空信封」历史用例（菜品收录、食物改热量、计划加动作）
///   在这里以带催办的方式复跑，用来区分「模型偶发」与「真不可用」。
///
/// 凭据只从环境变量读（`LF_AI_LIVE_KEY` / `LF_AI_LIVE_BASE` /
/// `LF_AI_LIVE_MODEL`），未设置整组跳过；不写日志文件、不打印密钥。
void main() {
  final env = Platform.environment;
  final apiKey = env['LF_AI_LIVE_KEY']?.trim() ?? '';
  final baseUrl = env['LF_AI_LIVE_BASE']?.trim() ?? '';
  final model = env['LF_AI_LIVE_MODEL']?.trim() ?? '';
  final skipReason = (apiKey.isEmpty || baseUrl.isEmpty || model.isEmpty)
      ? '未设置 LF_AI_LIVE_KEY / LF_AI_LIVE_BASE / LF_AI_LIVE_MODEL：语句矩阵默认跳过'
      : null;

  final today = DateTime(2026, 11, 11, 12).toUtc();
  final clock = FixedAppClock(today);
  final ids = _Ids();
  final registry = ChatEditCommandRegistry();

  late AppDatabase database;
  late CanteenRepository canteen;
  late SupplyCatalogRepository supplies;
  late ExerciseRepository exercises;
  late WorkoutPlanRepository plans;
  late MealRepository meals;
  late FoodRepository foods;
  late RepositoryChatEditExecutor executor;
  late DriftChatEditContextLoader contextLoader;
  late String venueId;
  late String windowId;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    foods = FoodRepository(database: database, idGenerator: ids, clock: clock);
    meals = MealRepository(database: database, idGenerator: ids, clock: clock);
    // 生产装配（main.dart）会给 canteen 接主库 sink：批准分析即建主食物并
    // 链接。这里必须同形装配，否则供应永远没有主链接、营养派生不出来。
    final catalog = FoodCatalogService(
      database: database,
      idGenerator: ids,
      clock: clock,
    );
    canteen = CanteenRepository(
      database: database,
      idGenerator: ids,
      clock: clock,
      masterNutritionSink: CatalogMasterNutritionSink(catalog),
    );
    supplies = SupplyCatalogRepository(database: database);
    exercises = ExerciseRepository(
      database: database,
      idGenerator: ids,
      clock: clock,
    );
    plans = WorkoutPlanRepository(
      database: database,
      idGenerator: ids,
      clock: clock,
    );
    executor = RepositoryChatEditExecutor(
      ChatEditServices(
        database: database,
        clock: clock,
        idGenerator: ids,
        foodRepository: foods,
        foodCatalog: catalog,
        mealRepository: meals,
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
        supplyCatalog: supplies,
        workoutPlanRepository: plans,
        workoutSessionRepository: WorkoutSessionRepository(
          database: database,
          idGenerator: ids,
          clock: clock,
        ),
        exerciseRepository: exercises,
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
        aiMemoryRepository: AiMemoryRepository(
          database: database,
          clock: clock,
          idGenerator: ids,
        ),
      ),
    );
    contextLoader = DriftChatEditContextLoader(
      database: database,
      mealRepository: meals,
      waterRepository: WaterRepository(
        database: database,
        idGenerator: ids,
        clock: clock,
      ),
      dishLibraryRepository: DishLibraryRepository(
        database: database,
        idGenerator: ids,
        clock: clock,
      ),
      canteenRepository: canteen,
      workoutPlanRepository: plans,
      workoutSessionRepository: WorkoutSessionRepository(
        database: database,
        idGenerator: ids,
        clock: clock,
      ),
      supplyCatalog: supplies,
      clock: clock,
    );
    venueId = await canteen.createVenue(name: '东苑', campusName: '校本部');
    windowId = await canteen.createWindow(
      venueId: venueId,
      name: '一楼快餐窗口',
      openTime: '10:00',
      closeTime: '13:00',
    );
    await canteen.createDish(windowId: windowId, name: '小炒黄牛肉');
    await exercises.create(
      const NewExercise(
        name: '杠铃深蹲',
        muscleGroup: MuscleGroup.legs,
        equipment: Equipment.barbell,
      ),
    );
    await plans.create(
      WorkoutPlanDraft(
        name: '增肌一周',
        days: [
          WorkoutPlanDayDraft(
            weekday: 1,
            entries: [
              PlannedExerciseDraft(
                exerciseId: (await exercises.findByExactName('杠铃深蹲')).single.id,
                targetSets: 3,
                targetReps: 10,
                targetWeightKg: 50,
              ),
            ],
          ),
        ],
      ),
    );
  });

  tearDown(() async => database.close());

  /// 发一次真实请求并执行返回的命令；`appNudge` 复刻 App 的催信封。
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
    final snapshot = await contextLoader.build(userMessage: request);
    final buffer = StringBuffer();
    Future<void> send(String systemContext) async {
      await service
          .sendMessage(
            messages: [
              ConversationMessage(
                id: 'editable-live-${DateTime.now().microsecondsSinceEpoch}',
                role: ConversationRole.user,
                text: request,
                createdAt: today,
              ),
            ],
            onProgress: buffer.write,
            systemContext: systemContext,
          )
          .drain<void>();
    }

    await send([registry.renderProtocol(), snapshot].join('\n\n'));
    var turn = parseChatEditTurn(buffer.toString(), registry);
    if ((turn == null || turn.rows.isEmpty) &&
        appNudge &&
        looksLikeModificationRequest(request)) {
      debugPrint('[editable] 首轮无可用信封 ⇒ 按 App 行为催一次');
      buffer.clear();
      await send(
        [
          registry.renderProtocol(),
          snapshot,
          chatEditEnvelopeNudge,
        ].join('\n\n'),
      );
      turn = parseChatEditTurn(buffer.toString(), registry);
    }
    if (turn == null) {
      debugPrint('[editable] ✗ 催办后仍无信封：${_head(buffer.toString())}');
      return const [];
    }
    if (turn.rows.isEmpty) {
      debugPrint('[editable] ✗ 信封零行：${_head(buffer.toString())}');
    }
    final applied = <({ChatEditCommand command, ChatEditApplyResult result})>[];
    for (final row in turn.rows) {
      final command = row.command;
      if (command == null) {
        debugPrint('[editable] ✗ 解码失败：${row.decodeError}');
        continue;
      }
      final result = await executor.apply(command);
      applied.add((command: command, result: result));
      debugPrint(
        '[editable] ${result.ok ? '✓' : '✗'} ${command.action} '
        'args=${command.args} → ${result.ok ? '写库成功' : result.message}',
      );
    }
    return applied;
  }

  group('新增可编辑命令 · 真实模型语句矩阵', () {
    test('A. 收录到食堂窗口（不记餐）', () async {
      // 用夹具里**没有**的菜名：夹具已有「小炒黄牛肉」，真实模型会正确回
      // 「已有，无需重复收录」（零编辑），那是对的，不能当失败。
      final out = await ask('把「蒜香排骨」收录到东苑一楼快餐窗口。');
      expect(out.map((e) => e.command.action), contains('canteen.dish.create'));
      expect(out.map((e) => e.command.action), isNot(contains('meal.create')));
      final windowDishes = await canteen.listDishes(windowId);
      expect(windowDishes.where((d) => d.name.contains('蒜香排骨')), hasLength(1));
      expect(await database.select(database.meals).get(), isEmpty);
    }, timeout: const Timeout(Duration(minutes: 4)));

    test('B. 建新菜并估算每 100g + 一份克数（同卡两条命令）', () async {
      final out = await ask(
        '在『东苑一楼快餐窗口』新增一道「藤椒鸡」，按常见食堂份量估算每 100 克的营养，'
        '并告诉我一份大约多少克。',
      );
      final actions = out.map((e) => e.command.action).toList();
      debugPrint('[editable] B 动作=$actions');
      expect(actions, contains('canteen.dish.create'));
      expect(actions, contains('canteen.dish.nutrition'));
      final dish = (await canteen.listDishes(windowId))
          .firstWhere((d) => d.name.contains('藤椒鸡'));
      final supply = (await supplies.getById(dish.id))!;
      expect(supply.hasCompleteNutrition, isTrue);
      expect(supply.servingGrams, isNotNull);
      expect(dish.foodId, isNotNull, reason: '分析批准应建主库并链接');
    }, timeout: const Timeout(Duration(minutes: 5)));

    test('C. 改食堂菜品份量', () async {
      final dish = (await canteen.listDishes(windowId)).single;
      final out = await ask('把小炒黄牛肉改成一份 280 克。');
      expect(out.map((e) => e.command.action), contains('canteen.dish.update'));
      final supply = (await supplies.getById(dish.id))!;
      expect(supply.servingGrams, closeTo(280, 1e-6));
      expect(supply.servingGramsStatus.storedValue, 'known');
    }, timeout: const Timeout(Duration(minutes: 4)));

    test('D. 改训练条目组次/重量', () async {
      final entry =
          (await database.select(database.plannedExercises).get()).single;
      final out = await ask('把增肌一周里周一的杠铃深蹲改成 5 组 8 次 60 公斤。');
      expect(out.map((e) => e.command.action), contains('plan.entry.update'));
      final after =
          (await database.select(database.plannedExercises).get()).single;
      expect(after.id, entry.id);
      expect(after.targetSets, 5);
      expect(after.targetReps, 8);
      expect(after.targetWeightKg, closeTo(60, 1e-6));
    }, timeout: const Timeout(Duration(minutes: 4)));

    test('E. 新建自定义动作（中文肌群/器械）', () async {
      final out = await ask('新建一个动作：保加利亚分腿蹲，练腿的，用哑铃。');
      expect(out.map((e) => e.command.action), contains('exercise.create'));
      final rows = await (database.select(
        database.exercises,
      )..where((row) => row.name.equals('保加利亚分腿蹲'))).get();
      expect(rows, hasLength(1));
      expect(rows.single.muscleGroup, 'legs');
      expect(rows.single.equipment, 'dumbbell');
    }, timeout: const Timeout(Duration(minutes: 4)));

    test('F. 改每日营养目标区间（已有目标时只改提到的项）', () async {
      await meals.saveManualTarget(
        NutritionTargetOverride(
          effectiveDate: '2026-11-11',
          calorieMinKcal: 1600,
          calorieMaxKcal: 1800,
          proteinMinGrams: 100,
          proteinMaxGrams: 130,
          carbsMinGrams: 150,
          carbsMaxGrams: 190,
          fatMinGrams: 45,
          fatMaxGrams: 60,
        ),
      );
      final out = await ask('把每日热量目标改成 1400 到 1500 千卡，蛋白质 90 到 120 克。');
      expect(
        out.map((e) => e.command.action),
        contains('nutrition.target.set'),
      );
      final manual = await meals.readManualTargetForDate('2026-11-11');
      expect(manual, isNotNull);
      expect(manual!.calorieMinKcal, closeTo(1400, 1e-6));
      expect(manual.calorieMaxKcal, closeTo(1500, 1e-6));
      expect(manual.proteinMinGrams, closeTo(90, 1e-6));
      expect(manual.proteinMaxGrams, closeTo(120, 1e-6));
      expect(manual.carbsMinGrams, closeTo(150, 1e-6), reason: '没提到的项沿用现有目标');
    }, timeout: const Timeout(Duration(minutes: 4)));

    test('G. 恢复按身体数据计算', () async {
      await meals.saveManualTarget(
        NutritionTargetOverride(
          effectiveDate: '2026-11-11',
          calorieMinKcal: 1400,
          calorieMaxKcal: 1500,
          proteinMinGrams: 90,
          proteinMaxGrams: 120,
          carbsMinGrams: 140,
          carbsMaxGrams: 180,
          fatMinGrams: 40,
          fatMaxGrams: 55,
        ),
      );
      final out = await ask('营养目标还是按身体数据算吧，不要手动值了。');
      expect(
        out.map((e) => e.command.action),
        contains('nutrition.target.reset'),
      );
      expect(await meals.readManualTargetForDate('2026-11-11'), isNull);
    }, timeout: const Timeout(Duration(minutes: 4)));

    test('H. 历史首轮空信封三例（带催办）', () async {
      // ① 菜品库收录：每份营养 + 没给克数 —— 允许执行器如实拒绝换算，
      //    但模型必须给出 dish.upsert 信封。
      final dishes = await ask(
        '把「番茄炒蛋」收录进菜品库：午餐，每份 120 千卡，蛋白质 7 克，碳水 5 克，脂肪 8 克。',
      );
      debugPrint(
        '[editable] H1=${dishes.map((e) => '${e.command.action}:${e.result.ok}').toList()}',
      );
      expect(dishes.map((e) => e.command.action), contains('dish.upsert'));

      // ② 改自建食物热量：必须给出 food.update 并真的改到 25。
      final created = await ask('新建自定义食材：测试气泡水，每 100 克 10 千卡，蛋白 0，碳水 2，脂肪 0。');
      expect(created.map((e) => e.command.action), contains('food.create'));
      final updated = await ask('把「测试气泡水」的热量改成每 100 克 25 千卡。');
      expect(updated.map((e) => e.command.action), contains('food.update'));
      final row = (await database.select(database.foods).get()).firstWhere(
        (f) => f.name.contains('测试气泡水'),
      );
      expect(row.kcalPer100g, closeTo(25, 1e-6));

      // ③ 计划加动作：必须给出 plan.entry.add 并真的落库。
      final plan = (await plans.list()).firstWhere(
        (p) => p.name.contains('增肌一周'),
      );
      final before = await database.select(database.plannedExercises).get();
      final added = await ask('在「增肌一周」的周一里再加一个动作：杠铃深蹲 4 组 8 次。');
      expect(added.map((e) => e.command.action), contains('plan.entry.add'));
      final after = await database.select(database.plannedExercises).get();
      expect(after.length, greaterThan(before.length));
      expect(plan.name, contains('增肌一周'));
    }, timeout: const Timeout(Duration(minutes: 8)));
  }, skip: skipReason);
}

String _head(String text) {
  final flat = text.replaceAll('\n', ' ');
  return flat.length <= 200 ? flat : '${flat.substring(0, 200)}…';
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
  String next() => 'editable-${_value++}';
}
