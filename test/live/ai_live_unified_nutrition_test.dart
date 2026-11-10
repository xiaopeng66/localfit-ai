import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/storage/secure_key_value_store.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart'
    hide ConversationMessage;
import 'package:localfit_ai/features/ai_conversation/application/chat_edit_coordinator.dart';
import 'package:localfit_ai/features/ai_conversation/application/chat_edit_executor.dart';
import 'package:localfit_ai/features/ai_conversation/data/chat_edit_context_loader.dart';
import 'package:localfit_ai/features/ai_conversation/data/open_ai_compatible_conversation_service.dart';
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
import 'package:localfit_ai/features/settings/domain/ai_reasoning_mode.dart';
import 'package:localfit_ai/features/training/data/exercise_repository.dart';
import 'package:localfit_ai/features/training/data/workout_plan_repository.dart';
import 'package:localfit_ai/features/training/data/workout_session_repository.dart';

/// **真实模型**冒烟：统一营养主库三意图（docs/67 §6.2）。
///
/// 默认整组跳过——没有凭据时一条请求都不发，常规门禁保持零外呼。
/// 有凭据时，这里问模型要一个信封，然后用**生产同一条链**
/// （registry 严格校验 → 执行器 → 数据库）落库并断言结果。
///
/// 运行方式（key 只进环境变量，不落任何仓库文件）：
/// ```
/// LF_LIVE_KEY=... LF_LIVE_BASE=https://your-proxy/v1 LF_LIVE_MODEL=deepseek-v4.1-flash \
///   flutter test --timeout 240s test/live/ai_live_unified_nutrition_test.dart
/// ```
/// 也支持从 cc-switch 的 provider 导出里现取（便于本机自测，仍不落盘）：
/// ```
/// LF_LIVE_CC_SWITCH=E:/AI/Zcode/backups/providers-export.json \
///   flutter test --timeout 240s test/live/ai_live_unified_nutrition_test.dart
/// ```
/// 可选：`LF_LIVE_PROTOCOL=anthropic_messages|responses|chat_completions`。
///
/// 判定口径：**只卡管线级**结论（模型是否按契约给了可解析、可落库的信封，
/// 数值是否与库内事实一致）；模型措辞与风格差异只记录不定罪。
void main() {
  final env = Platform.environment;
  final resolved = _resolveCredentials(env);
  final skipReason = resolved == null
      ? '未提供真实 AI 凭据（LF_LIVE_KEY / LF_LIVE_CC_SWITCH），本组按约定跳过'
      : null;

  final logLines = <String>[];
  void log(String line) {
    logLines.add(line);
    // ignore: avoid_print
    stdout.writeln(line);
  }

  setUpAll(() {
    final creds = resolved;
    log('# 统一营养主库 · 真实模型冒烟 ${DateTime.now().toUtc().toIso8601String()}');
    if (creds == null) {
      log('- 凭据：未提供（跳过）');
    } else {
      log(
        '- base=${creds.baseUrl} model=${creds.model} '
        'protocol=${creds.protocol.storageValue} '
        'key=<set len=${creds.apiKey.length}>',
      );
    }
  });

  tearDownAll(() async {
    final path = env['LF_LIVE_LOG'];
    if (path != null && path.isNotEmpty) {
      // 日志只写 base/model/结论，绝不写 key。
      await File(path).writeAsString('${logLines.join("\n")}\n');
    }
  });

  group('真实模型 · 三意图', () {
    late AppDatabase db;
    late FoodCatalogService catalog;
    late CanteenRepository canteen;
    late SupplyCatalogRepository supplies;
    late MealRepository meals;
    late RepositoryChatEditExecutor executor;
    late DriftChatEditContextLoader contextLoader;
    late String windowId;
    final now = DateTime.utc(2026, 11, 10, 12);

    setUp(() async {
      final creds = resolved;
      if (creds == null) return;
      db = AppDatabase(NativeDatabase.memory());
      final ids = _Ids();
      final clock = FixedAppClock(now);
      catalog = FoodCatalogService(
        database: db,
        idGenerator: ids,
        clock: clock,
      );
      canteen = CanteenRepository(
        database: db,
        idGenerator: ids,
        clock: clock,
        masterNutritionSink: CatalogMasterNutritionSink(catalog),
      );
      supplies = SupplyCatalogRepository(database: db);
      meals = MealRepository(database: db, idGenerator: ids, clock: clock);
      final dishes = DishLibraryRepository(
        database: db,
        idGenerator: ids,
        clock: clock,
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
          foodCatalog: catalog,
          supplyCatalog: supplies,
          mealRepository: meals,
          dishLibraryRepository: dishes,
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
          canteenRepository: canteen,
          workoutPlanRepository: WorkoutPlanRepository(
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
          workoutSessionRepository: WorkoutSessionRepository(
            database: db,
            idGenerator: ids,
            clock: clock,
          ),
          updateWaterTargetMl: UpdateWaterTargetMl(
            database: db,
            idGenerator: ids,
            clock: clock,
          ),
          stepsRepository: StepsRepository(
            database: db,
            idGenerator: ids,
            channel: StepsChannel(),
            clock: clock,
          ),
          aiMemoryRepository: AiMemoryRepository(
            database: db,
            clock: clock,
            idGenerator: ids,
          ),
        ),
      );
      contextLoader = DriftChatEditContextLoader(
        database: db,
        clock: clock,
        mealRepository: meals,
        dishLibraryRepository: dishes,
        waterRepository: WaterRepository(
          database: db,
          idGenerator: ids,
          clock: clock,
        ),
        canteenRepository: canteen,
        supplyCatalog: supplies,
        workoutPlanRepository: WorkoutPlanRepository(
          database: db,
          idGenerator: ids,
          clock: clock,
        ),
        workoutSessionRepository: WorkoutSessionRepository(
          database: db,
          idGenerator: ids,
          clock: clock,
        ),
      );
      final venueId = await canteen.createVenue(
        name: '三食堂',
        campusName: '示范大学',
      );
      windowId = await canteen.createWindow(
        venueId: venueId,
        name: '一楼快餐',
        openTime: '11:00',
        closeTime: '13:30',
      );
    });

    tearDown(() async {
      if (resolved != null) await db.close();
    });

    /// 用真实服务问一轮，返回解析后的信封（含失败原因）。
    Future<({ChatEditTurn? turn, String raw})> ask(String userText) async {
      final creds = resolved!;
      final service = OpenAiCompatibleConversationService(
        dio: Dio(),
        configurationReader: _FixedConfiguration(
          baseUrl: creds.baseUrl,
          model: creds.model,
          protocol: creds.protocol,
        ),
        apiKeyStore: AiApiKeyStore(
          store: _MemorySecureStore()
            ..values[AiApiKeyStore.storageKey] = creds.apiKey,
        ),
      );
      final snapshot = await contextLoader.build(userMessage: userText);
      final protocol = ChatEditCommandRegistry().renderProtocol();
      final buffer = StringBuffer();
      await service
          .sendMessage(
            messages: [
              ConversationMessage(
                id: 'live-${DateTime.now().microsecondsSinceEpoch}',
                role: ConversationRole.user,
                text: userText,
                createdAt: now,
              ),
            ],
            onProgress: buffer.write,
            systemContext: '$protocol\n\n$snapshot',
          )
          .drain<void>();
      final raw = buffer.toString();
      final turn = parseChatEditTurn(raw, ChatEditCommandRegistry());
      return (turn: turn, raw: raw);
    }

    test(
      '端点诊断：模型列表 + 一次最小请求的真实状态码',
      () async {
        final creds = resolved!;
        final dio = Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 20),
            receiveTimeout: const Duration(seconds: 30),
            validateStatus: (_) => true,
          ),
        );
        final headers = creds.protocol == AiProviderProtocol.anthropicMessages
            ? {
                'x-api-key': creds.apiKey,
                'authorization': 'Bearer ${creds.apiKey}',
                'anthropic-version': '2023-06-01',
                'content-type': 'application/json',
              }
            : {
                'authorization': 'Bearer ${creds.apiKey}',
                'content-type': 'application/json',
              };
        final base = creds.baseUrl.endsWith('/')
            ? creds.baseUrl.substring(0, creds.baseUrl.length - 1)
            : creds.baseUrl;
        try {
          final list = await dio.get<dynamic>(
            '$base/models',
            options: Options(headers: headers),
          );
          final data = list.data;
          final ids = <String>[];
          if (data is Map && data['data'] is List) {
            for (final item in data['data'] as List) {
              if (item is Map && item['id'] is String) {
                ids.add(item['id'] as String);
              }
            }
          }
          log('[LIVE] GET models -> ${list.statusCode} count=${ids.length}');
          final interesting = ids
              .where(
                (id) =>
                    id.toLowerCase().contains('deepseek') ||
                    id.toLowerCase().contains('glm') ||
                    id.toLowerCase().contains('qwen') ||
                    id.toLowerCase().contains('gpt-5') ||
                    id.toLowerCase().contains('claude'),
              )
              .toList(growable: false);
          log('[LIVE] 候选模型：${interesting.take(60).join(', ')}');
          if (ids.isNotEmpty && !ids.contains(creds.model)) {
            log('[LIVE] 注意：配置模型 ${creds.model} 不在列表里');
          }
        } on Object catch (error) {
          log('[LIVE] GET models -> 失败 ${error.runtimeType}');
        }
        // 配置里的模型名不一定在供应商的可用渠道里：逐个探一次，找出能用的。
        const candidates = <String>[
          'deepseek-v4.1-flash',
          'GLM-5.3-Flash',
          'claude-sonnet-4-5-20250929',
          'claude-sonnet-4-5',
          'claude-sonnet-4-20250514',
          'claude-3-7-sonnet-20250219',
          'claude-3-5-sonnet-20241022',
          'claude-3-5-haiku-20241022',
          'claude-opus-4-1-20250805',
          'claude-haiku-4-5-20251001',
          'gpt-5.6',
          'glm-5.3-flash',
        ];
        for (final candidate in candidates) {
          try {
            final response = await dio.post<dynamic>(
              creds.protocol == AiProviderProtocol.anthropicMessages
                  ? '$base/messages'
                  : '$base/chat/completions',
              options: Options(headers: headers),
              data: {
                'model': candidate,
                'max_tokens': 16,
                'messages': [
                  {'role': 'user', 'content': 'ping'},
                ],
              },
            );
            log('[LIVE] 候选 $candidate -> ${response.statusCode}');
            if (response.statusCode == 200) {
              log('[LIVE] 可用模型：$candidate');
              break;
            }
          } on Object catch (error) {
            log('[LIVE] 候选 $candidate -> 失败 ${error.runtimeType}');
          }
        }
        try {
          final response = await dio.post<dynamic>(
            creds.protocol == AiProviderProtocol.anthropicMessages
                ? '$base/messages'
                : '$base/chat/completions',
            options: Options(headers: headers),
            data: creds.protocol == AiProviderProtocol.anthropicMessages
                ? {
                    'model': creds.model,
                    'max_tokens': 16,
                    'messages': [
                      {'role': 'user', 'content': 'ping'},
                    ],
                  }
                : {
                    'model': creds.model,
                    'max_tokens': 16,
                    'messages': [
                      {'role': 'user', 'content': 'ping'},
                    ],
                  },
          );
          final body = response.data is String
              ? response.data as String
              : jsonEncode(response.data);
          log(
            '[LIVE] POST 最小请求 -> ${response.statusCode} '
            'body=${body.substring(0, body.length > 220 ? 220 : body.length)}',
          );
        } on Object catch (error) {
          log('[LIVE] POST 最小请求 -> 失败 ${error.runtimeType}: $error');
        }
      },
      skip: skipReason != null,
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test('重跑守卫：没有凭据时一条请求都不发', () async {
      if (resolved != null) return;
      expect(skipReason, isNotNull);
    }, skip: skipReason == null);

    test(
      'AI 存库：主食物 + 生效修订，不挂窗不记餐',
      () async {
        final reply = await (() async {
          final asked = await ask(
            '帮我把「宫保鸡丁」存到食物库：每 100g 热量 180 千卡、蛋白质 12g、'
            '碳水 8g、脂肪 11g。只存库，不要加到窗口，也不要记餐。',
          );
          expect(
            asked.turn,
            isNotNull,
            reason: '模型输出必须能解析成信封。原始输出：${asked.raw}',
          );
          final applied = await ChatEditCoordinator(
            contextBuilder: contextLoader,
            executor: executor,
          ).applyProposed(asked.turn!, confirmDependencies: (_) async => true);
          final labels = <String, String>{
            for (final row in applied.rows) ...row.itemLabels,
          };
          final rows = [
            for (final row in applied.rows)
              '${row.status.name}:${row.resultMessage ?? row.decodeError ?? ''}',
          ];
          // 用户可见文本里不许出现机器引用/裸 id（v4132 的教训）。
          for (final text in [...rows, ...labels.values]) {
            expect(
              text.contains('[food:') ||
                  text.contains('[canteen-dish:') ||
                  RegExp(
                    r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
                    r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}',
                  ).hasMatch(text),
              isFalse,
              reason: '用户可见文本里出现了 id：$text',
            );
          }
          return rows;
        })();
        final rows = reply;
        log('[LIVE] 存库：${rows.join(' | ')}');
        expect(rows.any((row) => row.startsWith('applied')), isTrue);

        final foods = await db.select(db.foods).get();
        expect(foods, isNotEmpty, reason: '应有一条主食物');
        final food = foods.firstWhere((row) => row.name.contains('宫保'));
        expect(food.currentRevisionId, isNotNull, reason: '必须带生效修订');
        expect(await db.select(db.menuItems).get(), isEmpty, reason: '不许擅自挂窗');
        expect(await db.select(db.meals).get(), isEmpty, reason: '不许擅自记餐');
      },
      skip: skipReason != null,
      timeout: const Timeout(Duration(minutes: 6)),
    );

    test(
      'AI 挂窗：带主引用与每份克数，不记餐',
      () async {
        final foodId = await catalog.createMasterFood(
          name: '宫保鸡丁',
          kcalPer100g: 180,
          proteinPer100g: 12,
          carbsPer100g: 8,
          fatPer100g: 11,
        );
        final reply = await (() async {
          final asked = await ask(
            '把食物库里的宫保鸡丁（id=$foodId）加到窗口 $windowId，'
            '一份 200 克。只上架，不要记餐。',
          );
          expect(
            asked.turn,
            isNotNull,
            reason: '模型输出必须能解析成信封。原始输出：${asked.raw}',
          );
          final applied = await ChatEditCoordinator(
            contextBuilder: contextLoader,
            executor: executor,
          ).applyProposed(asked.turn!, confirmDependencies: (_) async => true);
          final rows = applied.rows
              .map(
                (row) =>
                    '${row.status.name}:'
                    '${row.resultMessage ?? row.decodeError ?? ''}',
              )
              .toList(growable: false);
          if (rows.any((row) => row.startsWith('failed'))) {
            final raw = asked.raw.split('\n').join(' ').split('\r').join(' ');
            log(
              '[LIVE] 原始输出(前 600 字)：'
              '${raw.substring(0, raw.length > 600 ? 600 : raw.length)}',
            );
          }
          // 用户可见文本里不许出现机器引用/裸 id（v4132 的教训）。
          for (final text in [
            ...rows,
            for (final row in applied.rows) ...row.itemLabels.values,
          ]) {
            expect(
              text.contains('[food:') ||
                  text.contains('[canteen-dish:') ||
                  RegExp(
                    r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
                    r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}',
                  ).hasMatch(text),
              isFalse,
              reason: '用户可见文本里出现了 id：$text',
            );
          }
          return rows;
        })();
        log('[LIVE] 挂窗：${reply.join(' | ')}');

        final suppliesInDb = await db.select(db.menuItems).get();
        expect(suppliesInDb, isNotEmpty, reason: '应有一条供应');
        final supply = suppliesInDb.first;
        expect(supply.foodId, foodId, reason: '必须链接到主食物');
        expect(supply.servingGrams, 200, reason: '每份克数要落库');
        expect(supply.servingGramsStatus, 'known');
        expect(await db.select(db.meals).get(), isEmpty, reason: '不许擅自记餐');
      },
      skip: skipReason != null,
      timeout: const Timeout(Duration(minutes: 6)),
    );

    test(
      '品牌饮料（库里没有）：要么先建库再记、要么说清为什么没记',
      () async {
        final reply = await (() async {
          final asked = await ask('我刚喝了一杯蜜雪冰城的无糖茶，500ml，记到今天的加餐。');
          expect(
            asked.turn,
            isNotNull,
            reason: '模型输出必须能解析成信封。原始输出：${asked.raw}',
          );
          final labels = <String, String>{};
          for (final row in asked.turn!.rows) {
            labels.addAll(row.itemLabels);
          }
          final applied = await ChatEditCoordinator(
            contextBuilder: contextLoader,
            executor: executor,
          ).applyProposed(asked.turn!, confirmDependencies: (_) async => true);
          final rows = [
            for (final row in applied.rows)
              '${row.status.name}:${row.resultMessage ?? row.decodeError ?? ''}',
          ];
          // 用户可见字符串里**不许出现机器 id**（卡片标题/报错同理）。
          for (final text in [...rows, ...labels.values]) {
            expect(
              text.contains('[food:') || text.contains('[canteen-dish:'),
              isFalse,
              reason: '用户可见文本里出现了 id：$text',
            );
          }
          return (rows: rows, labels: labels);
        })();
        log('[LIVE] 品牌饮料：${reply.rows.join(' | ')}');
        final mealItems = await db.select(db.mealItems).get();
        if (mealItems.isNotEmpty) {
          // 记进去了：克数要跟用户说的 500ml 对得上（按 1ml≈1g），不能是 100g。
          expect(
            mealItems.single.grams,
            closeTo(500, 1e-9),
            reason: '回复里说 500ml，记餐克数必须一致',
          );
        } else {
          // 没记成餐也可以接受：零卡饮料被记成"饮水"是合理结果，被拒也行。
          // 唯一不许发生的是 decode 失败或空回执（说不清做了什么）。
          expect(
            reply.rows.every(
              (row) =>
                  row.startsWith('applied') ||
                  row.startsWith('failed') ||
                  row.startsWith('applying'),
            ),
            isTrue,
            reason: '每行都要有可读结果：${reply.rows}',
          );
          log('[LIVE] 品牌饮料没有记为餐（按回执接受）：${reply.rows.join(' | ')}');
        }
      },
      skip: skipReason != null,
      timeout: const Timeout(Duration(minutes: 6)),
    );

    test(
      'AI 记一餐：用供应 id 记 100g → 180 千卡且快照完整',
      () async {
        final foodId = await catalog.createMasterFood(
          name: '宫保鸡丁',
          kcalPer100g: 180,
          proteinPer100g: 12,
          carbsPer100g: 8,
          fatPer100g: 11,
        );
        final dishId = await canteen.createDish(
          windowId: windowId,
          name: '宫保鸡丁',
          foodId: foodId,
          servingGrams: 200,
        );
        final reply = await (() async {
          final asked = await ask(
            '我今天午餐吃了一食堂供应 [canteen-dish:$dishId] 100 克，'
            '帮我记进 2026-11-10 的午餐。',
          );
          expect(
            asked.turn,
            isNotNull,
            reason: '模型输出必须能解析成信封。原始输出：${asked.raw}',
          );
          final applied = await ChatEditCoordinator(
            contextBuilder: contextLoader,
            executor: executor,
          ).applyProposed(asked.turn!, confirmDependencies: (_) async => true);
          final rows = applied.rows
              .map(
                (row) =>
                    '${row.status.name}:'
                    '${row.resultMessage ?? row.decodeError ?? ''}',
              )
              .toList(growable: false);
          if (rows.any((row) => row.startsWith('failed'))) {
            final raw = asked.raw.split('\n').join(' ').split('\r').join(' ');
            log(
              '[LIVE] 原始输出(前 600 字)：'
              '${raw.substring(0, raw.length > 600 ? 600 : raw.length)}',
            );
          }
          // 用户可见文本里不许出现机器引用/裸 id（v4132 的教训）。
          for (final text in [
            ...rows,
            for (final row in applied.rows) ...row.itemLabels.values,
          ]) {
            expect(
              text.contains('[food:') ||
                  text.contains('[canteen-dish:') ||
                  RegExp(
                    r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
                    r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}',
                  ).hasMatch(text),
              isFalse,
              reason: '用户可见文本里出现了 id：$text',
            );
          }
          return rows;
        })();
        log('[LIVE] 记餐：${reply.join(' | ')}');
        expect(reply.any((row) => row.startsWith('applied')), isTrue);

        final items = await db.select(db.mealItems).get();
        expect(items, hasLength(1));
        final item = items.single;
        expect(item.grams, 100);
        expect(item.supplyId, dishId, reason: '必须记下供应来源');
        expect(item.sourceType, 'menu_item');
        expect(item.kcalSnapshot, closeTo(180, 1e-9));
        expect(item.nutritionRevisionId, isNotNull);
      },
      skip: skipReason != null,
      timeout: const Timeout(Duration(minutes: 6)),
    );
  });
}

/// 凭据来源：环境变量优先；否则从 cc-switch 导出里现取（不落盘、不打印）。
_Credentials? _resolveCredentials(Map<String, String> env) {
  final protocolName = env['LF_LIVE_PROTOCOL'] ?? '';
  AiProviderProtocol? explicitProtocol;
  if (protocolName.isNotEmpty) {
    for (final value in AiProviderProtocol.values) {
      if (value.storageValue == protocolName) explicitProtocol = value;
    }
  }

  // ① 环境变量直接给全（key 只走环境，不落盘）。
  var key = env['LF_LIVE_KEY'] ?? '';
  var baseUrl = env['LF_LIVE_BASE'] ?? '';
  var model = env['LF_LIVE_MODEL'] ?? '';
  var derivedProtocol = AiProviderProtocol.chatCompletions;

  // ② 缺的部分从 cc-switch 的 provider 导出里现取（便于本机自测）。
  final exportPath = env['LF_LIVE_CC_SWITCH'] ?? '';
  if ((key.isEmpty || baseUrl.isEmpty) && exportPath.isNotEmpty) {
    final file = File(exportPath);
    if (file.existsSync()) {
      Object? decoded;
      try {
        decoded = jsonDecode(file.readAsStringSync());
      } on FormatException {
        decoded = null;
      }
      final providers = decoded is Map ? decoded['providers'] : null;
      if (providers is List) {
        for (final entry in providers) {
          if (entry is! Map) continue;
          final raw = entry['settings_config'];
          Object? cfg;
          try {
            cfg = raw is String ? jsonDecode(raw) : raw;
          } on FormatException {
            continue;
          }
          if (cfg is! Map) continue;
          final providerEnv = cfg['env'];
          if (providerEnv is! Map) continue;
          String? read(String name) {
            final value = providerEnv[name];
            return value is String && value.trim().isNotEmpty
                ? value.trim()
                : null;
          }

          final token =
              read('ANTHROPIC_AUTH_TOKEN') ??
              read('ANTHROPIC_API_KEY') ??
              read('OPENAI_API_KEY');
          final providerBase =
              read('OPENAI_BASE_URL') ?? read('ANTHROPIC_BASE_URL');
          if (token == null || providerBase == null) continue;
          key = key.isEmpty ? token : key;
          baseUrl = baseUrl.isEmpty ? providerBase : baseUrl;
          final hasOpenAiBase = read('OPENAI_BASE_URL') != null;
          derivedProtocol = hasOpenAiBase
              ? AiProviderProtocol.chatCompletions
              : AiProviderProtocol.anthropicMessages;
          if (model.isEmpty) {
            model =
                read('OPENAI_MODEL') ??
                read('ANTHROPIC_MODEL') ??
                read('ANTHROPIC_DEFAULT_SONNET_MODEL') ??
                'claude-sonnet-4-5';
          }
          break;
        }
      }
    }
  }

  if (key.isEmpty || baseUrl.isEmpty || model.isEmpty) return null;
  return _Credentials(
    baseUrl: baseUrl,
    apiKey: key,
    model: model,
    protocol: explicitProtocol ?? derivedProtocol,
  );
}

final class _Credentials {
  const _Credentials({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    required this.protocol,
  });

  final String baseUrl;
  final String apiKey;
  final String model;
  final AiProviderProtocol protocol;
}

final class _FixedConfiguration implements AiProviderConfigurationReader {
  const _FixedConfiguration({
    required this.baseUrl,
    required this.model,
    this.protocol = AiProviderProtocol.chatCompletions,
  });

  final String baseUrl;
  final String model;
  final AiProviderProtocol protocol;

  @override
  Future<AiProviderConfiguration?> loadConfiguration() async =>
      AiProviderConfiguration(
        baseUrl: baseUrl,
        model: model,
        protocol: protocol,
        reasoning: AiReasoningMode.disabled,
      );
}

final class _MemorySecureStore implements SecureKeyValueStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

final class _Ids implements IdGenerator {
  int _value = 0;

  @override
  String next() => 'live-${_value++}';
}
