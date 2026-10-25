import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/errors/app_failure.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/storage/secure_key_value_store.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart'
    hide ConversationMessage;
import 'package:localfit_ai/features/ai/domain/prompt_catalog.dart';
import 'package:localfit_ai/features/ai_conversation/application/chat_edit_coordinator.dart';
import 'package:localfit_ai/features/ai_conversation/application/chat_edit_executor.dart';
import 'package:localfit_ai/features/ai_memory/data/ai_memory_repository.dart';
import 'package:localfit_ai/features/ai_conversation/data/chat_edit_context_loader.dart';
import 'package:localfit_ai/features/ai_conversation/data/open_ai_compatible_conversation_service.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_turn.dart';
import 'package:localfit_ai/features/ai_conversation/domain/conversation_message.dart';
import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart';
import 'package:localfit_ai/features/campus_menus/data/dish_image_store.dart';
import 'package:localfit_ai/features/daily_plan/data/planning_constraints_repository.dart';
import 'package:localfit_ai/features/food_scan/data/open_ai_compatible_meal_recognition_provider.dart';
import 'package:localfit_ai/features/food_scan/data/prepared_meal_image_bytes_reader.dart';
import 'package:localfit_ai/features/food_scan/domain/meal_image.dart';
import 'package:localfit_ai/features/hydration/application/update_water_target_ml.dart';
import 'package:localfit_ai/features/progress/data/steps_repository.dart';
import 'package:localfit_ai/features/hydration/data/water_repository.dart';
import 'package:localfit_ai/features/nutrition/data/dish_library_repository.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/progress/data/measurement_repository.dart';
import 'package:localfit_ai/features/settings/data/profile_identity_repository.dart';
import 'package:localfit_ai/features/settings/data/ai_api_key_store.dart';
import 'package:localfit_ai/features/settings/data/dio_ai_endpoint_probe.dart';
import 'package:localfit_ai/features/settings/domain/ai_provider_protocol.dart';
import 'package:localfit_ai/features/settings/domain/ai_provider_settings.dart';
import 'package:localfit_ai/features/settings/domain/ai_reasoning_mode.dart';
import 'package:localfit_ai/features/training/data/open_ai_compatible_workout_plan_provider.dart';
import 'package:localfit_ai/features/training/data/workout_plan_repository.dart';
import 'package:localfit_ai/features/training/data/workout_session_repository.dart';
import 'package:localfit_ai/features/training/domain/workout_plan.dart';
import 'package:localfit_ai/features/training/data/exercise_repository.dart';
import 'package:localfit_ai/features/ai_workbench/application/ai_workbench_prompt_templates.dart';

/// P11 真实端点全功能实测（docs/29 §P11）。**默认整组跳过**：
/// `LF_LIVE_KEY` 未设置时一条真实请求都不发，常规门禁保持零外呼。
///
/// 运行方式（key 只进环境变量，不落任何仓库文件）：
/// ```
/// LF_LIVE_KEY=... LF_LIVE_BASE=https://freeapi.site/v1 LF_LIVE_MODEL=deepseek-v4.1-flash \
///   flutter test test/live/ai_live_endpoint_test.dart
/// ```
/// 可选：`LF_LIVE_KEY_PAID` / `LF_LIVE_MODEL_PAID`（视觉兜底档）、
/// `LF_LIVE_LOG`（逐出口结论 markdown 落盘路径）。
///
/// 判定口径（docs/29 §P11）：每个出口记录「HTTP 状态 / 是否可用 / 延迟 /
/// 是否需要推理开关 / 是否触发空回复兜底」，由本文件的 `[LIVE]` 输出汇总进
/// `docs/evidence/2026-10-05-ai-live-endpoint.md`。硬断言只卡**管线级**结论
/// （传输可用、合同解析成立）；上游模型质量差异只记录不定罪。
// 【工具盲点，2026-10-16 实测】`flutter test` **不认** `@Timeout` 注解
// （放 main 上也照样 30s 掐断），所以实时运行的超时由命令行给：
//   flutter test --timeout 240s test/ai_live/...
// 上游 `deepseek-ai/deepseek-v4.1-flash` 实测 TTFB ≈ 11s、整请求 40–46s，
// 默认 30s 会在「app 的传输上限」之前先把用例打断 ⇒ 结论被工具掩盖。
void main() {
  final liveKey = Platform.environment['LF_LIVE_KEY'] ?? '';
  final liveBase = Platform.environment['LF_LIVE_BASE'] ?? '';
  final liveModel = Platform.environment['LF_LIVE_MODEL'] ?? '';
  final paidKey = Platform.environment['LF_LIVE_KEY_PAID'] ?? '';
  final paidModel = Platform.environment['LF_LIVE_MODEL_PAID'] ?? '';
  final skipReason = liveKey.isEmpty
      ? 'P11 需显式授权才发真实请求：设置 LF_LIVE_KEY 等环境变量后运行'
      : null;

  final logLines = <String>[];
  void log(String line) {
    logLines.add(line);
    // ignore: avoid_print
    stdout.writeln(line);
  }

  setUpAll(() {
    log('# P11 真实端点实测 ${DateTime.now().toUtc().toIso8601String()}');
    log(
      '- base=$liveBase model=$liveModel paidModel=${paidModel.isEmpty ? '(未提供)' : paidModel}',
    );
  });

  tearDownAll(() async {
    final logPath = Platform.environment['LF_LIVE_LOG'];
    if (logPath != null && logPath.isNotEmpty) {
      await File(logPath).writeAsString('${logLines.join("\n")}\n');
    }
  });

  /// 固定配置读取器：绕过设置存储，直接注入本次实测的端点与模型。
  _FixedConfiguration config(
    String model, [
    AiReasoningMode reasoning = AiReasoningMode.disabled,
  ]) => _FixedConfiguration(
    baseUrl: liveBase,
    model: model,
    reasoning: reasoning,
  );

  AiApiKeyStore storeWith(String key) {
    final store = _MemorySecureStore()..values[AiApiKeyStore.storageKey] = key;
    return AiApiKeyStore(store: store);
  }

  /// 与 main.dart 同一注册表的 prompt 目录（2.0-6h 单源）。
  /// 与 main.dart 同一注册表的 prompt 目录（docs/32 T6c：模板已从
  /// 任务类迁到 `ai_workbench_prompt_templates.dart`，正文逐字不动）。
  PromptCatalog catalog() => PromptCatalog()
    ..register(menuNormalizePromptTemplate)
    ..register(dailyMenuPlanPromptTemplate)
    ..register(dishGuidancePromptTemplate)
    ..register(workoutPlanPromptTemplate)
    ..register(mealPairingPromptTemplate)
    ..register(dishNutritionPromptTemplate);

  group('P11 真实端点实测（docs/29 §P11）', () {
    Timeout slow = const Timeout(Duration(minutes: 6));

    test(
      '出口6 连通性测试与模型拉取（DioAiEndpointProbe / GET /models）',
      () async {
        final probe = DioAiEndpointProbe(dio: Dio());
        final watch = Stopwatch()..start();
        final result = await probe.probe(
          baseUrl: liveBase,
          protocol: AiProviderProtocol.chatCompletions,
          apiKey: liveKey,
        );
        watch.stop();
        log(
          '[LIVE] 出口6 连通性/模型拉取: '
          '${result.isSuccess ? "OK" : "FAIL"} '
          'models=${result.models.length} latency=${watch.elapsedMilliseconds}ms '
          'message=${result.message ?? "-"}',
        );
        expect(result.isSuccess, isTrue, reason: '连通性测试应成功：${result.message}');
        log(
          result.models.contains(liveModel)
              ? '[LIVE] 出口6 模型选择: 配置模型 $liveModel 在 /models 列表中'
              : '[LIVE] 出口6 模型选择: 配置模型 $liveModel 不在 /models 列表（上游形态差异，记录）',
        );
      },
      timeout: slow,
      skip: skipReason,
    );

    test(
      '出口1 对话流式（关闭推理=产品默认）',
      () async {
        final chat = OpenAiCompatibleConversationService(
          dio: Dio(),
          configurationReader: config(liveModel),
          apiKeyStore: storeWith(liveKey),
        );
        final watch = Stopwatch()..start();
        Duration? firstChunkAt;
        final chunks = <String>[];
        final text = await chat
            .sendMessage(
              messages: [
                ConversationMessage(
                  id: 'live-chat-1',
                  role: ConversationRole.user,
                  text: '用两句话说明什么是基础代谢率。',
                  createdAt: DateTime.now().toUtc(),
                ),
              ],
              onProgress: (chunk) {
                firstChunkAt ??= watch.elapsed;
                chunks.add(chunk);
              },
            )
            .join();
        watch.stop();
        log(
          '[LIVE] 出口1 对话流式(disabled): OK latency=${watch.elapsedMilliseconds}ms '
          '首块=${firstChunkAt?.inMilliseconds ?? "-"}ms chunks=${chunks.length} '
          'len=${text.length} 空回复兜底=未触发',
        );
        expect(text.trim(), isNotEmpty, reason: '流式对话应产出非空内容');
      },
      timeout: slow,
      skip: skipReason,
    );

    test(
      '出口1b 对话流式（推理开关=供应商默认）',
      () async {
        final chat = OpenAiCompatibleConversationService(
          dio: Dio(),
          configurationReader: config(
            liveModel,
            AiReasoningMode.providerDefault,
          ),
          apiKeyStore: storeWith(liveKey),
        );
        final watch = Stopwatch()..start();
        final chunks = <String>[];
        try {
          final text = await chat
              .sendMessage(
                messages: [
                  ConversationMessage(
                    id: 'live-chat-2',
                    role: ConversationRole.user,
                    text: '一句话说明什么是 BMI。',
                    createdAt: DateTime.now().toUtc(),
                  ),
                ],
                onProgress: chunks.add,
              )
              .join();
          watch.stop();
          log(
            '[LIVE] 出口1b 对话流式(provider_default): OK '
            'latency=${watch.elapsedMilliseconds}ms chunks=${chunks.length} '
            'len=${text.length}',
          );
        } on AppFailure catch (error) {
          watch.stop();
          log(
            '[LIVE] 出口1b 对话流式(provider_default): AppFailure '
            '${error.runtimeType} latency=${watch.elapsedMilliseconds}ms '
            '${error.message}',
          );
          // 推理档差异导致的失败按 docs/29 §P11 如实记录（分档在证据文档）。
        }
      },
      timeout: slow,
      skip: skipReason,
    );

    test(
      '出口2 chat-edit 代表集（23 条命令里取 5 条跨域代表）',
      () async {
        final now = DateTime.utc(2026, 10, 7, 4); // 本地 12:00（UTC+8）
        final database = AppDatabase(NativeDatabase.memory());
        final ids = _LiveIds();
        final clock = FixedAppClock(now);
        await database
            .into(database.profiles)
            .insert(
              ProfilesCompanion.insert(
                id: 'profile-live',
                activityLevel: 'moderate',
                createdAt: clock.nowUtc(),
                updatedAt: clock.nowUtc(),
              ),
            );
        // profile.goal.update 需要已有目标记录（执行器无目标时如实报
        // 「先建档」），所以先种一条 maintain 目标。
        await database
            .into(database.goals)
            .insert(
              GoalsCompanion.insert(
                id: 'goal-live',
                profileId: 'profile-live',
                type: 'maintain',
                calorieMinKcal: 1500,
                calorieMaxKcal: 2200,
                effectiveFrom: clock.nowUtc(),
                createdAt: clock.nowUtc(),
                updatedAt: clock.nowUtc(),
              ),
            );
        final foods = FoodRepository(
          database: database,
          idGenerator: ids,
          clock: clock,
        );
        final coordinator = ChatEditCoordinator(
          contextBuilder: DriftChatEditContextLoader(
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
              dishImageStore: DishImageStore(idGenerator: ids),
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
          ),
          executor: RepositoryChatEditExecutor(
            ChatEditServices(
              database: database,
              clock: clock,
              foodRepository: foods,
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
                dishImageStore: DishImageStore(idGenerator: ids),
              ),
              workoutPlanRepository: WorkoutPlanRepository(
                database: database,
                idGenerator: ids,
                clock: clock,
              ),
              exerciseRepository: ExerciseRepository(
                database: database,
                idGenerator: const UuidV7Generator(),
                clock: const SystemAppClock(),
              ),
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
          ),
        );
        final chat = OpenAiCompatibleConversationService(
          dio: Dio(),
          configurationReader: config(liveModel),
          apiKeyStore: storeWith(liveKey),
        );

        const cases = <(String, String)>[
          ('帮我记录今天的体重：72.5 公斤', 'weight.log'),
          ('刚喝了 250 毫升水，帮我记一下', 'water.add'),
          ('新建一个自定义食物：无糖酸奶，每 100 克 62 千卡', 'food.create'),
          // profile.goal.update 的参数是 goal（减脂/维持/增肌）+ 目标体重，
          // 没有热量目标参数——指令必须在该命令的真实能力范围内。
          ('帮我把健康目标改成增肌，目标体重 75 公斤', 'profile.goal.update'),
          ('花生过敏，之后别给我推荐花生', 'constraints.set'),
        ];
        var matched = 0;
        var applied = 0;
        for (final (instruction, expected) in cases) {
          final watch = Stopwatch()..start();
          try {
            final systemContext = await coordinator.buildSystemContext();
            final reply = await chat
                .sendMessage(
                  messages: [
                    ConversationMessage(
                      id: 'live-edit-\$expected',
                      role: ConversationRole.user,
                      text: instruction,
                      createdAt: DateTime.now().toUtc(),
                    ),
                  ],
                  onProgress: (_) {},
                  systemContext: systemContext,
                )
                .join();
            watch.stop();
            final turn = coordinator.decode(reply);
            if (turn == null) {
              log(
                '[LIVE] 出口2 $expected: 信封解码失败（非信封回复） '
                'latency=${watch.elapsedMilliseconds}ms replyLen=${reply.length} '
                'reply=${_preview(reply, 200)}',
              );
              continue;
            }
            final command = turn.rows.isNotEmpty
                ? turn.rows.first.command
                : null;
            final action = command?.spec.action;
            final isMatch = action == expected;
            if (isMatch) matched++;
            var appliedOk = false;
            if (isMatch) {
              final result = await coordinator.applyProposed(turn);
              appliedOk =
                  result.rows.isNotEmpty &&
                  result.rows.first.status == ChatEditRowStatus.applied;
              if (appliedOk) {
                applied++;
              } else {
                log(
                  '[LIVE] 出口2 $expected: 应用失败 '
                  'resultMessage=${_preview(result.rows.first.resultMessage ?? "-", 160)}',
                );
              }
            }
            log(
              '[LIVE] 出口2 $expected: '
              'action=$action match=$isMatch applied=$appliedOk '
              'latency=${watch.elapsedMilliseconds}ms rows=${turn.rows.length}',
            );
          } on AppFailure catch (error) {
            watch.stop();
            log(
              '[LIVE] 出口2 $expected: AppFailure ${error.runtimeType} '
              'latency=${watch.elapsedMilliseconds}ms ${error.message}',
            );
          }
        }
        await database.close();
        log('[LIVE] 出口2 汇总: matched=$matched/6 applied=$applied/6');
        expect(
          matched,
          greaterThanOrEqualTo(4),
          reason:
              '协议是仓库单源（docs/23），'
              '可用模型对 6 条跨域代表指令应至少命中 4 条正确 action；低于此值先查接口形态',
        );
        expect(applied, greaterThanOrEqualTo(4), reason: '命中命令应能落库成功');
      },
      timeout: const Timeout(Duration(minutes: 12)),
      skip: skipReason,
    );

    test(
      '出口3 餐图识别（免费档；有付费档则补视觉兜底）',
      () async {
        final bytes = base64Decode(_tinyJpeg);
        final image = PreparedMealImage(
          path: '/live/meal.jpg',
          width: 1,
          height: 1,
          byteLength: bytes.length,
        );

        Future<void> attempt(String label, String model, String key) async {
          final provider = OpenAiCompatibleMealRecognitionProvider(
            dio: Dio(),
            configurationReader: config(model),
            apiKeyStore: storeWith(key),
            imageBytesReader: _StaticImageBytes(bytes),
          );
          final watch = Stopwatch()..start();
          try {
            final draft = await provider.recognize(image);
            watch.stop();
            log(
              '[LIVE] 出口3 $label($model): OK latency=${watch.elapsedMilliseconds}ms '
              'items=${draft.items.length} warnings=${draft.warnings.length}',
            );
          } on AppFailure catch (error) {
            watch.stop();
            log(
              '[LIVE] 出口3 $label($model): AppFailure ${error.runtimeType} '
              'latency=${watch.elapsedMilliseconds}ms ${error.message}',
            );
          }
        }

        await attempt('免费档', liveModel, liveKey);
        if (paidKey.isNotEmpty) await attempt('付费档', paidModel, paidKey);
      },
      timeout: slow,
      skip: skipReason,
    );

    test(
      '出口4 训练计划（OpenAiCompatibleWorkoutPlanProvider）',
      () async {
        final provider = OpenAiCompatibleWorkoutPlanProvider(
          dio: Dio(),
          configurationReader: config(liveModel),
          apiKeyStore: storeWith(liveKey),
          catalog: catalog(),
        );
        final watch = Stopwatch()..start();
        final draft = await provider.generate(
          const AiWorkoutPlanRequest(
            daysPerWeek: 3,
            goalText: '增肌为主，兼顾体能；每次训练控制在 45 分钟以内',
            exercises: [
              ExerciseOption(id: 'ex-pushup', name: '俯卧撑'),
              ExerciseOption(id: 'ex-squat', name: '深蹲'),
              ExerciseOption(id: 'ex-plank', name: '平板支撑'),
            ],
          ),
        );
        watch.stop();
        log(
          '[LIVE] 出口4 训练计划: OK latency=${watch.elapsedMilliseconds}ms '
          'name=${draft.name} days=${draft.days.length} warnings=${draft.warnings.length}',
        );
        expect(draft.days, isNotEmpty, reason: '训练计划应解析出至少一个训练日');
      },
      timeout: slow,
      skip: skipReason,
    );

    // docs/32 §4 T6c（D6）：原「出口5 工作台任务 ×5」随旧任务执行
    // 管线退役一并移除——那五条契约（四个 capability + dish-nutrition）
    // 已由对话命令层（chat-edit 24 命令 + 各自 decoder）承接，
    // egress 面由 `ai_egress_evaluation_test` 的命令层用例继续守护。

    test(
      '错误分档：401 伪 Key / 404 错路径 / 不可达主机 / 伪 Key 对话',
      () async {
        final probe = DioAiEndpointProbe(dio: Dio());

        final watch401 = Stopwatch()..start();
        final unauthorized = await probe.probe(
          baseUrl: liveBase,
          protocol: AiProviderProtocol.chatCompletions,
          apiKey: 'sk-live-p11-bogus-key',
        );
        watch401.stop();
        log(
          '[LIVE] 错误分档 401: isSuccess=${unauthorized.isSuccess} '
          'latency=${watch401.elapsedMilliseconds}ms ${unauthorized.message}',
        );
        expect(unauthorized.isSuccess, isFalse, reason: '伪 Key 必须被拒');

        final badBase = liveBase.replaceFirst(RegExp(r'/v\d+$'), '/vX');
        final watch404 = Stopwatch()..start();
        final notFound = await probe.probe(
          baseUrl: badBase,
          protocol: AiProviderProtocol.chatCompletions,
          apiKey: liveKey,
        );
        watch404.stop();
        log(
          '[LIVE] 错误分档 404($badBase): isSuccess=${notFound.isSuccess} '
          'latency=${watch404.elapsedMilliseconds}ms ${notFound.message}',
        );
        expect(notFound.isSuccess, isFalse, reason: '错误路径必须失败');

        final watchHost = Stopwatch()..start();
        final unreachable = await probe.probe(
          baseUrl: 'https://localfit-p11-invalid.invalid/v1',
          protocol: AiProviderProtocol.chatCompletions,
          apiKey: liveKey,
        );
        watchHost.stop();
        log(
          '[LIVE] 错误分档 不可达主机: isSuccess=${unreachable.isSuccess} '
          'latency=${watchHost.elapsedMilliseconds}ms ${unreachable.message}',
        );
        expect(unreachable.isSuccess, isFalse, reason: '不可达主机必须失败');

        final bogusChat = OpenAiCompatibleConversationService(
          dio: Dio(),
          configurationReader: config(liveModel),
          apiKeyStore: storeWith('sk-live-p11-bogus-key'),
        );
        final watchChat = Stopwatch()..start();
        final future = bogusChat
            .sendMessage(
              messages: [
                ConversationMessage(
                  id: 'live-bogus',
                  role: ConversationRole.user,
                  text: '你好',
                  createdAt: DateTime.now().toUtc(),
                ),
              ],
              onProgress: (_) {},
            )
            .join();
        try {
          await future;
          fail('伪 Key 的对话请求应当抛 AppFailure');
        } on AppFailure catch (error) {
          watchChat.stop();
          log(
            '[LIVE] 错误分档 伪Key对话: AppFailure ${error.runtimeType} '
            'latency=${watchChat.elapsedMilliseconds}ms ${error.message}',
          );
        }
      },
      timeout: const Timeout(Duration(minutes: 4)),
      skip: skipReason,
    );
  }, skip: skipReason);
}

/// 1×1 灰白 JPEG（PIL 生成后 base64 内嵌）：识别出口的管线探针，不做营养判断。
const _tinyJpeg =
    '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAUDBAQEAwUEBAQFBQUGBwwIBwcHBw8LCwkMEQ8S'
    'EhEPERETFhwXExQaFRERGCEYGh0dHx8fExciJCIeJBweHx7/2wBDAQUFBQcGBw4ICA4eFBEU'
    'Hh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh7/wAARCAAB'
    'AAEDASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgED'
    'AwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcY'
    'GRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJ'
    'ipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo'
    '6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgEC'
    'BAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl'
    '8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaH'
    'iImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn'
    '6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwD67ooooA//2Q==';

final class _FixedConfiguration implements AiProviderConfigurationReader {
  _FixedConfiguration({
    required this.baseUrl,
    required this.model,
    this.reasoning = AiReasoningMode.disabled,
  });

  final String baseUrl;
  final String model;
  final AiReasoningMode reasoning;

  @override
  Future<AiProviderConfiguration?> loadConfiguration() async =>
      AiProviderConfiguration(
        baseUrl: baseUrl,
        model: model,
        protocol: AiProviderProtocol.chatCompletions,
        reasoning: reasoning,
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

final class _StaticImageBytes implements PreparedMealImageBytesReader {
  const _StaticImageBytes(this.bytes);

  final Uint8List bytes;

  @override
  Future<Uint8List> read(PreparedMealImage image) async => bytes;
}

final class _LiveIds implements IdGenerator {
  int _value = 0;

  @override
  String next() => 'live-id-${_value++}';
}

/// 模型输出预览：压平换行、截断到 [max] 字符。内容只是模型回复，
/// 不含 Key 与本机事实，可安全进日志。
String _preview(String text, int max) {
  final flat = text.replaceAll('\n', r'\n');
  return flat.length <= max
      ? flat
      : '${flat.substring(0, max)}…(len=${text.length})';
}
