import 'dart:convert';
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
import 'package:localfit_ai/features/ai_conversation/data/chat_edit_context_loader.dart';
import 'package:localfit_ai/features/ai_conversation/data/open_ai_compatible_conversation_service.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_command.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_context_builder.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_registry.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_turn.dart';
import 'package:localfit_ai/features/ai_conversation/domain/conversation_message.dart';
import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart';
import 'package:localfit_ai/features/hydration/data/water_repository.dart';
import 'package:localfit_ai/features/nutrition/data/dish_library_repository.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/food_record.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';
import 'package:localfit_ai/features/settings/data/ai_api_key_store.dart';
import 'package:localfit_ai/features/settings/domain/ai_provider_protocol.dart';
import 'package:localfit_ai/features/settings/domain/ai_provider_settings.dart';
import 'package:localfit_ai/features/training/data/workout_plan_repository.dart';
import 'package:localfit_ai/features/training/data/workout_session_repository.dart';

import '../support/food_fixture.dart';

/// **多轮对话实测**（`ai-live`）。
///
/// 用户 2026-10-24：「你要从多方位实测，保证 AI 对我的语言的理解能够正确转发
/// 给软件接口、调用软件功能，而不是只回复不操作」。
///
/// 单轮语料（`ai_live_edit_card_rate_test.dart`）量的是「一句话能不能出信封」。
/// 本文件量的是**对话真正的样子**：用户说完一句、看到卡片、然后接着改口——
/// 而多轮里模型最容易犯的两类错，单轮永远测不出来：
///
/// 1. **忘记自己刚提议过什么**（历史里只剩 reply 纯文本，信封 JSON 被剥离）；
/// 2. **把「补一句话」当成新的一次记录**（「改成 200 克」被记成第二顿饭）。
///
/// 每个剧本给完整的多轮历史，断言**最后一轮**的输出。历史里的助手消息按
/// App 真实落库形态构造（`kind: editProposal` + `editTurn`），因此本测试同时
/// 验证「历史回放给模型看到的东西对不对」。
///
/// 默认跳过；设了 `LF_AI_LIVE_KEY` / `LF_AI_LIVE_BASE` / `LF_AI_LIVE_MODEL`
/// 才真跑。**凭据零入库**：只读环境变量。
void main() {
  final env = Platform.environment;
  final apiKey = env['LF_AI_LIVE_KEY']?.trim() ?? '';
  final baseUrl = env['LF_AI_LIVE_BASE']?.trim() ?? '';
  final model = env['LF_AI_LIVE_MODEL']?.trim() ?? '';
  final label = env['LF_AI_LIVE_LABEL']?.trim() ?? 'baseline';
  final onlyCase = env['LF_AI_LIVE_ONLY']?.trim() ?? '';
  final rounds = int.tryParse(env['LF_AI_LIVE_ROUNDS'] ?? '') ?? 2;

  final today = DateTime(2026, 10, 24, 12).toUtc();
  final clock = FixedAppClock(today);
  final ids = _Ids();
  final String? skipReason =
      (apiKey.isEmpty || baseUrl.isEmpty || model.isEmpty)
      ? '未设置 LF_AI_LIVE_KEY / LF_AI_LIVE_BASE / LF_AI_LIVE_MODEL：多轮实测默认跳过'
      : null;

  final registry = ChatEditCommandRegistry();

  late AppDatabase database;
  late DriftChatEditContextLoader contextLoader;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await seedFoodFixture(database);
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

    final canteen = CanteenRepository(
      database: database,
      idGenerator: ids,
      clock: clock,
    );
    final meals = MealRepository(
      database: database,
      idGenerator: ids,
      clock: clock,
    );
    final dishes = DishLibraryRepository(
      database: database,
      idGenerator: ids,
      clock: clock,
    );
    final water = WaterRepository(
      database: database,
      idGenerator: ids,
      clock: clock,
    );
    final plans = WorkoutPlanRepository(
      database: database,
      idGenerator: ids,
      clock: clock,
    );
    final sessions = WorkoutSessionRepository(
      database: database,
      idGenerator: ids,
      clock: clock,
    );
    await dishes.create(
      DishDraft(
        name: '番茄炒蛋',
        mealSlot: 'lunch',
        kcal: 220,
        proteinG: 12,
        carbsG: 8,
        fatG: 15,
        source: 'manual',
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

  /// 发一轮多轮对话：`history` 是按时间排好的历史，`last` 是这一轮的用户话。
  ///
  /// [withPendingProposal] 决定是否把「上一张卡还没应用」告诉模型——这是
  /// 2026-10-24 新增快照段的效果开关，也是本测试的第二个对照轴。
  Future<({String raw, ChatEditTurn? turn})> sendTurn({
    required List<ConversationMessage> history,
    required String last,
    PendingProposal? pendingProposal,
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
    final snapshot = await contextLoader.build(
      pendingProposal: pendingProposal,
    );
    final buffer = StringBuffer();
    var seq = 0;
    await service
        .sendMessage(
          messages: [
            ...history,
            ConversationMessage(
              id: 'mt-${DateTime.now().microsecondsSinceEpoch}-${seq++}',
              role: ConversationRole.user,
              text: last,
              createdAt: today,
            ),
          ],
          onProgress: buffer.write,
          systemContext: [registry.renderProtocol(), snapshot].join('\n\n'),
        )
        .drain<void>();
    final raw = buffer.toString();
    return (raw: raw, turn: parseChatEditTurn(raw, registry));
  }

  /// 从历史里找**最后一张还有待应用行**的编辑卡（App 真实逻辑的等价实现）。
  PendingProposal? pendingFromHistory(List<ConversationMessage> history) {
    for (final message in history.reversed) {
      final turn = message.editTurn;
      if (turn == null) continue;
      final pending = [
        for (final row in turn.rows)
          if (row.status == ChatEditRowStatus.proposed && row.command != null)
            (action: row.command!.action, args: row.command!.args),
      ];
      if (pending.isEmpty) continue;
      return PendingProposal(summary: turn.reply.trim(), commands: pending);
    }
    return null;
  }

  /// 构造一条**助手编辑卡消息**（与 App 真实落库形态一致）。
  ///
  /// 两种历史形态，由 `asAppPersists` 控制：
  /// * `true`（**App 现状**）：`text` = reply 纯文本，`editTurn` 有值但
  ///   `_forRequest` 不会把它塞进 wire —— 模型看不到自己当初提议的命令参数；
  /// * `false`（**对照：把命令写进文本**）：文本里追加当初那批命令的 JSON。
  ///
  /// 【第一版假设已被实测推翻，如实记录】原以为「现状」会因为模型忘记自己
  /// 提议过什么而变差。实测 `m2` 恰恰相反：**现状全部通过，写进文本反而偶发
  /// 失败**（T06/理想 一次）。原因是模型把自己的历史输出当成「我已经说过这
  /// 些内容了」，于是只回一句总结、不再出信封。也就是说：**把命令回灌进历史
  /// 不是修复方向**，保留 reply 纯文本反而让模型每轮重新按当前快照生成。
  ConversationMessage assistantCard({
    required String reply,
    required List<(String action, Map<String, Object?> args)> edits,
    bool asAppPersists = true,
  }) {
    final items = <ChatEditTurnItem>[];
    for (var i = 0; i < edits.length; i++) {
      final action = edits[i].$1;
      final spec = registry.specOf(action);
      // 借真实校验器把参数归一化（与 decoder 同一口径），构造不出就是剧本写错。
      final normalized = validateChatEditArgs(spec!, {
        for (final e in edits[i].$2.entries)
          if (e.value != null) e.key: e.value,
      });
      items.add(
        ChatEditTurnItem(
          index: i,
          raw: {'action': action, 'args': edits[i].$2},
          command: ChatEditCommand(spec: spec, args: normalized),
          status: ChatEditRowStatus.proposed,
        ),
      );
    }
    final turn = ChatEditTurn(reply: reply, rows: items);
    final wire = asAppPersists
        ? reply
        : '$reply\n（上面这条提议对应的命令：${jsonEncode([
            for (final edit in edits) {'action': edit.$1, 'args': edit.$2},
          ])}）';
    return ConversationMessage(
      id: 'mt-a-${DateTime.now().microsecondsSinceEpoch}',
      role: ConversationRole.assistant,
      text: wire,
      kind: ConversationMessageKind.editProposal,
      editTurn: turn,
      createdAt: today,
    );
  }

  ConversationMessage userSays(String text) => ConversationMessage(
    id: 'mt-u-${DateTime.now().microsecondsSinceEpoch}',
    role: ConversationRole.user,
    text: text,
    createdAt: today,
  );

  /// 剧本：多轮历史 + 这一轮该干什么。
  ///
  /// 判定口径与单轮一致（信封 + 精确命中 + 不夹带），另加：
  /// * `mustNotDuplicate`：这一轮**不许**把「再加」当成新的一餐（多条 meal.create）；
  /// * `seedMeals`：跑之前先往数据库里写一餐（模拟「上一轮已经应用了」）。
  ///   **必须写**：`_renderMeals` 读的是**数据库实时状态**，只把历史消息里
  ///   标成 `applied` 而不落库，模型看到的快照仍是「今天没有记录」——
  ///   那是测试环境的错，不是产品的错（第一版就栽在这里，T03 假失败）。
  /// * `expectEnvelope: false`：这一轮**本就不该出信封**（用户取消/纯提问）。
  final scripts =
      <
        ({
          String id,
          String desc,
          List<ConversationMessage> Function(bool asAppPersists) history,
          String last,
          String? expect,
          Set<String> allowed,
          bool mustNotDuplicate,
          bool expectEnvelope,
          Future<void> Function()? seedMeals,
        })
      >[];

  void addScript({
    required String id,
    required String desc,
    required List<ConversationMessage> Function(bool asAppPersists) history,
    required String last,
    required String? expect,
    required Set<String> allowed,
    bool mustNotDuplicate = false,
    bool expectEnvelope = true,
    Future<void> Function()? seedMeals,
  }) {
    scripts.add((
      id: id,
      desc: desc,
      history: history,
      last: last,
      expect: expect,
      allowed: allowed,
      mustNotDuplicate: mustNotDuplicate,
      expectEnvelope: expectEnvelope,
      seedMeals: seedMeals,
    ));
  }

  // ── T1 改口：同一条提议追加食物 ────────────────────────────────
  addScript(
    id: 'T01',
    desc: '先提议记午餐，用户补一句「再加个鸡蛋」→ 应并入同一条 meal.create',
    history: (asApp) => [
      userSays('我中午吃了米饭和鸡胸肉'),
      assistantCard(
        reply: '我准备把午餐记为米饭 150g、鸡胸肉 150g，确认后应用。',
        edits: [
          (
            'meal.create',
            {
              'slot': 'lunch',
              'items': [
                {'food': '米饭', 'grams': 150},
                {'food': '鸡胸肉', 'grams': 150},
              ],
            },
          ),
        ],
        asAppPersists: asApp,
      ),
    ],
    last: '再加一个鸡蛋',
    expect: 'meal.create',
    allowed: {'meal.create', 'food.create'},
    mustNotDuplicate: true,
  );

  // ── T2 改量：指代上一轮那条 ────────────────────────────────────
  addScript(
    id: 'T02',
    desc: '用户说「米饭改成 100 克」→ 应改克数，而不是再记一餐',
    history: (asApp) => [
      userSays('我中午吃了米饭和鸡胸肉'),
      assistantCard(
        reply: '我准备把午餐记为米饭 150g、鸡胸肉 150g，确认后应用。',
        edits: [
          (
            'meal.create',
            {
              'slot': 'lunch',
              'items': [
                {'food': '米饭', 'grams': 150},
                {'food': '鸡胸肉', 'grams': 150},
              ],
            },
          ),
        ],
        asAppPersists: asApp,
      ),
    ],
    last: '米饭改成 100 克',
    expect: null,
    allowed: {'meal.create', 'meal.item.update', 'meal.update'},
    mustNotDuplicate: true,
  );

  // ── T3 已应用之后：再说「不对，是晚餐」 ────────────────────────
  // 关键：模型定位「刚才那顿」靠的是**快照里的餐记录 id**，所以必须真把
  // 那一餐写进数据库。第一版只改了历史消息的 status、库是空的 ⇒ 模型只能
  // 重新记一餐 ⇒ **假失败**（测试环境问题，不是产品缺陷）。
  addScript(
    id: 'T03',
    desc: '库里真有一餐，用户说「刚才那顿算晚餐」→ 应 meal.update 改餐次',
    history: (asApp) => [
      userSays('我中午吃了米饭和鸡胸肉'),
      () {
        final card = assistantCard(
          reply: '午餐已记录：米饭 150g、鸡胸肉 150g。',
          edits: [
            (
              'meal.create',
              {
                'slot': 'lunch',
                'items': [
                  {'food': '米饭', 'grams': 150},
                  {'food': '鸡胸肉', 'grams': 150},
                ],
              },
            ),
          ],
          asAppPersists: asApp,
        );
        return card.copyWith(
          editTurn: ChatEditTurn(
            reply: card.editTurn!.reply,
            rows: [
              for (final row in card.editTurn!.rows)
                row.copyWith(status: ChatEditRowStatus.applied),
            ],
          ),
        );
      }(),
    ],
    last: '刚才那顿算晚餐',
    expect: 'meal.update',
    allowed: const {'meal.update'},
    seedMeals: () async {
      final mealRepo = MealRepository(
        database: database,
        idGenerator: ids,
        clock: clock,
      );
      final foodRepo = FoodRepository(
        database: database,
        idGenerator: ids,
        clock: clock,
      );
      final rice = await _foodByName(foodRepo, '米饭');
      final chicken = await _foodByName(foodRepo, '鸡胸肉');
      await mealRepo.saveManualMeal(
        ManualMealDraft(
          localDate: '2026-10-24',
          slot: MealSlot.lunch,
          items: [
            ManualMealItemDraft(food: rice, grams: 150),
            ManualMealItemDraft(food: chicken, grams: 150),
          ],
        ),
      );
    },
  );

  // ── T4 否定：先说要记，然后说「算了不记了」 ────────────────────
  // 【判据纠正，第一版写错了】原判据是「必须出信封」⇒ 4 次全红，但模型回
  // 「好的，那这次就不记了」是**正确**行为：用户取消了，本就不该写库、也没
  // 东西可应用。强行要求弹一张应用卡反而是错的。
  // 正确判据 = **不许出现任何写库命令**（纯文本或空信封都算合格）。
  addScript(
    id: 'T04',
    desc: '用户改主意「算了不记了」→ 不该给任何写库命令',
    history: (asApp) => [
      userSays('我中午吃了米饭和鸡胸肉'),
      assistantCard(
        reply: '我准备把午餐记为米饭 150g、鸡胸肉 150g。',
        edits: [
          (
            'meal.create',
            {
              'slot': 'lunch',
              'items': [
                {'food': '米饭', 'grams': 150},
                {'food': '鸡胸肉', 'grams': 150},
              ],
            },
          ),
        ],
        asAppPersists: asApp,
      ),
    ],
    last: '算了不记了',
    expect: null,
    allowed: const {},
    mustNotDuplicate: true,
    expectEnvelope: false,
  );

  // ── T5 跨话题：从记餐切到喝水 ──────────────────────────────────
  addScript(
    id: 'T05',
    desc: '上一个话题是记午餐（未应用），用户切话题「刚喝了 300 毫升水」→ 应记水，不掺和午餐',
    history: (asApp) => [
      userSays('我中午吃了米饭和鸡胸肉'),
      assistantCard(
        reply: '我准备把午餐记为米饭 150g、鸡胸肉 150g。',
        edits: [
          (
            'meal.create',
            {
              'slot': 'lunch',
              'items': [
                {'food': '米饭', 'grams': 150},
                {'food': '鸡胸肉', 'grams': 150},
              ],
            },
          ),
        ],
        asAppPersists: asApp,
      ),
    ],
    last: '刚喝了 300 毫升水',
    expect: 'water.add',
    allowed: {'water.add'},
  );

  // ── T6 三轮：连着补两次 ───────────────────────────────────────
  addScript(
    id: 'T06',
    desc: '三轮：记晚餐 → 再加牛奶 → 再加个苹果，最后一轮仍应出信封',
    history: (asApp) => [
      userSays('晚饭吃了米饭和鸡胸肉'),
      assistantCard(
        reply: '我准备把晚餐记为米饭 150g、鸡胸肉 150g。',
        edits: [
          (
            'meal.create',
            {
              'slot': 'dinner',
              'items': [
                {'food': '米饭', 'grams': 150},
                {'food': '鸡胸肉', 'grams': 150},
              ],
            },
          ),
        ],
        asAppPersists: asApp,
      ),
      userSays('再加一杯牛奶'),
      assistantCard(
        reply: '好，再加牛奶 200ml，一共三条。',
        edits: [
          (
            'meal.create',
            {
              'slot': 'dinner',
              'items': [
                {'food': '米饭', 'grams': 150},
                {'food': '鸡胸肉', 'grams': 150},
                {'food': '牛奶', 'grams': 200},
              ],
            },
          ),
        ],
        asAppPersists: asApp,
      ),
    ],
    last: '再加一个苹果',
    expect: 'meal.create',
    allowed: {'meal.create', 'food.create'},
    mustNotDuplicate: true,
  );

  // ══════════════ 第二组维度：真实口语里最容易崩的几种 ══════════════

  // ── T07 极短碎片：只有一个名词 ────────────────────────────────
  addScript(
    id: 'T07',
    desc: '上个话题是早餐燕麦，用户只回两个字「鸡蛋」→ 仍应出信封（按上下文补进早餐）',
    history: (asApp) => [
      userSays('早餐吃了燕麦粥'),
      assistantCard(
        reply: '我准备把早餐记为燕麦粥 250g。',
        edits: [
          (
            'meal.create',
            {
              'slot': 'breakfast',
              'items': [
                {'food': '燕麦粥', 'grams': 250},
              ],
            },
          ),
        ],
        asAppPersists: asApp,
      ),
    ],
    last: '鸡蛋',
    expect: 'meal.create',
    allowed: {'meal.create', 'food.create'},
  );

  // ── T08 否定式纠正：不是这个 ─────────────────────────────────
  addScript(
    id: 'T08',
    desc: '用户否认「不是鸡胸肉，是鸡蛋」→ 应给改后的命令，不是照抄旧提议',
    history: (asApp) => [
      userSays('我中午吃了米饭和鸡胸肉'),
      assistantCard(
        reply: '我准备把午餐记为米饭 150g、鸡胸肉 150g。',
        edits: [
          (
            'meal.create',
            {
              'slot': 'lunch',
              'items': [
                {'food': '米饭', 'grams': 150},
                {'food': '鸡胸肉', 'grams': 150},
              ],
            },
          ),
        ],
        asAppPersists: asApp,
      ),
    ],
    last: '不是鸡胸肉，是鸡蛋',
    expect: 'meal.create',
    allowed: {'meal.create', 'food.create'},
    mustNotDuplicate: true,
  );

  // ── T09 跨域：餐 → 训练 ──────────────────────────────────────
  addScript(
    id: 'T09',
    desc: '上个话题是记午餐，用户切到训练「刚做完 3 组深蹲」→ 应记训练组，不掺和饮食',
    history: (asApp) => [
      userSays('我中午吃了米饭和鸡胸肉'),
      assistantCard(
        reply: '我准备把午餐记为米饭 150g、鸡胸肉 150g。',
        edits: [
          (
            'meal.create',
            {
              'slot': 'lunch',
              'items': [
                {'food': '米饭', 'grams': 150},
                {'food': '鸡胸肉', 'grams': 150},
              ],
            },
          ),
        ],
        asAppPersists: asApp,
      ),
    ],
    last: '刚做完 3 组深蹲，每组 12 个',
    expect: null,
    allowed: {'set.log', 'session.start'},
  );

  // ── T10 已应用后改量：库里真有那一餐 ─────────────────────────
  addScript(
    id: 'T10',
    desc: '库里真有一餐，用户说「鸡胸肉记多了，改成 100 克」→ 应 meal.item.update，不是重新记',
    history: (asApp) => [
      userSays('我中午吃了米饭和鸡胸肉'),
      assistantCard(
        reply: '午餐已记录：米饭 150g、鸡胸肉 150g。',
        edits: [
          (
            'meal.create',
            {
              'slot': 'lunch',
              'items': [
                {'food': '米饭', 'grams': 150},
                {'food': '鸡胸肉', 'grams': 150},
              ],
            },
          ),
        ],
        asAppPersists: asApp,
      ),
    ],
    last: '鸡胸肉记多了，改成 100 克',
    expect: 'meal.item.update',
    allowed: {'meal.item.update'},
    seedMeals: () async {
      final mealRepo = MealRepository(
        database: database,
        idGenerator: ids,
        clock: clock,
      );
      final foodRepo = FoodRepository(
        database: database,
        idGenerator: ids,
        clock: clock,
      );
      final rice = await _foodByName(foodRepo, '米饭');
      final chicken = await _foodByName(foodRepo, '鸡胸肉');
      await mealRepo.saveManualMeal(
        ManualMealDraft(
          localDate: '2026-10-24',
          slot: MealSlot.lunch,
          items: [
            ManualMealItemDraft(food: rice, grams: 150),
            ManualMealItemDraft(food: chicken, grams: 150),
          ],
        ),
      );
    },
  );

  // ── T11 反问澄清：用户回答 AI 的追问 ─────────────────────────
  addScript(
    id: 'T11',
    desc: 'AI 上一轮追问「哪一餐？」，用户答「午饭」→ 应出完整信封而不是再问一遍',
    history: (asApp) => [
      userSays('我吃了番茄炒蛋'),
      assistantCard(
        reply: '番茄炒蛋菜品库里有（220 kcal/份）。你想记到哪一餐？',
        edits: const [],
        asAppPersists: asApp,
      ),
    ],
    last: '午饭',
    expect: 'meal.create',
    allowed: {'meal.create'},
  );

  // ── T12 连续否定两次后给正解 ─────────────────────────────────
  addScript(
    id: 'T12',
    desc: '用户说「不对，午餐改成晚餐」→ 应改餐次（meal.update 或重新 meal.create 到 dinner）',
    history: (asApp) => [
      userSays('我中午吃了米饭和鸡胸肉'),
      assistantCard(
        reply: '午餐已记录：米饭 150g、鸡胸肉 150g。',
        edits: [
          (
            'meal.create',
            {
              'slot': 'lunch',
              'items': [
                {'food': '米饭', 'grams': 150},
                {'food': '鸡胸肉', 'grams': 150},
              ],
            },
          ),
        ],
        asAppPersists: asApp,
      ),
    ],
    last: '不对，午餐改成晚餐',
    expect: 'meal.update',
    allowed: {'meal.update'},
    seedMeals: () async {
      final mealRepo = MealRepository(
        database: database,
        idGenerator: ids,
        clock: clock,
      );
      final foodRepo = FoodRepository(
        database: database,
        idGenerator: ids,
        clock: clock,
      );
      final rice = await _foodByName(foodRepo, '米饭');
      final chicken = await _foodByName(foodRepo, '鸡胸肉');
      await mealRepo.saveManualMeal(
        ManualMealDraft(
          localDate: '2026-10-24',
          slot: MealSlot.lunch,
          items: [
            ManualMealItemDraft(food: rice, grams: 150),
            ManualMealItemDraft(food: chicken, grams: 150),
          ],
        ),
      );
    },
  );

  Future<void> runScripts() async {
    var pass = 0;
    var total = 0;
    final failures = <String, List<String>>{};

    for (final s in scripts) {
      if (onlyCase.isNotEmpty && s.id != onlyCase) continue;
      // 两个对照轴：
      //   A/B = 历史里是否回灌命令（已验证：回灌不是修复方向，A 更好）；
      //   +pending = 是否启用本轮新增的「尚未应用的提议」快照段。
      // 只跑 A 轴 + pending 开关，避免组合爆炸（B 轴已证明无益）。
      for (final withPending in [false, true]) {
        for (var r = 0; r < rounds; r++) {
          total++;
          const asAppPersists = true;
          final mode = withPending ? '待应用提议ON' : '待应用提议OFF';
          try {
            // 每个组合都是干净的库状态：先删掉上一次种下的餐，再按需重种。
            await _clearMeals(database);
            if (s.seedMeals != null) await s.seedMeals!();
            final history = s.history(asAppPersists);
            final result = await sendTurn(
              history: history,
              last: s.last,
              pendingProposal: withPending ? pendingFromHistory(history) : null,
            );
            final turn = result.turn;
            final offered = <String>{
              for (final row in turn?.rows ?? const <ChatEditTurnItem>[])
                if (row.command != null) row.command!.action,
              for (final sg
                  in turn?.suggestions ?? const <ChatEditSuggestion>[])
                if (sg.effectiveAction != null) sg.effectiveAction!,
            };
            final problems = <String>[];
            if (!s.expectEnvelope) {
              // 反向用例：不许有任何写库命令。
              final writes = offered.where((a) => !s.allowed.contains(a));
              if (writes.isNotEmpty) {
                problems.add('不该写库却给了命令：${writes.toList()}');
              }
            } else if (turn == null) {
              problems.add(
                '无信封；原文前 140 字：'
                '${result.raw.replaceAll('\n', ' ').substring(0, result.raw.length.clamp(0, 140))}',
              );
            } else {
              // 【堵漏洞】空信封（`{}` 或 edits 空、suggestions 空）在单轮里是
              // 合法的（「执行不了也要给信封」），但在多轮的**改口场景**里它
              // 等于「听懂了却什么都没做」——T02「米饭改成 100 克」返回 `{}`
              // 被上一版判成 OK，是判据漏洞。这里要求：只要期望出信封，就
              // 必须至少给出一条命令。
              if (offered.isEmpty) {
                problems.add(
                  '空信封 = 什么都没做（reply：'
                  '${turn.reply.replaceAll('\n', ' ').substring(0, turn.reply.length.clamp(0, 80))}）',
                );
              }
              if (s.expect != null && !offered.contains(s.expect!)) {
                problems.add('命令错误：期望 ${s.expect}，实际 $offered');
              }
              final extra = offered.where((a) => !s.allowed.contains(a));
              if (extra.isNotEmpty) {
                problems.add('夹带用户没要求的命令：$extra（只允许 ${s.allowed}）');
              }
              if (s.mustNotDuplicate) {
                final creates = turn.rows
                    .where((row) => row.command?.action == 'meal.create')
                    .length;
                if (creates > 1) {
                  problems.add('把「再加」当成新的一餐：本轮给了 $creates 条 meal.create');
                }
              }
            }
            if (problems.isEmpty) {
              pass++;
            } else {
              failures.putIfAbsent('${s.id}/$mode', () => []).addAll(problems);
            }
            debugPrint(
              '[multi] ${s.id}/$mode ${problems.isEmpty ? "OK" : "FAIL"} '
              '«${s.last}» ⇒ $offered',
            );
          } on Object catch (e) {
            failures.putIfAbsent('${s.id}/$mode', () => []).add('异常：$e');
            debugPrint('[multi] ${s.id}/$mode EXCEPTION $e');
          }
        }
      }
    }

    final pct = total == 0 ? 0 : pass * 100 / total;
    debugPrint(
      '[multi] === $label 总计 $pass/$total = ${pct.toStringAsFixed(1)}% ===',
    );
    for (final entry in failures.entries) {
      debugPrint('[multi] 失败 ${entry.key}: ${entry.value.join(" | ")}');
    }
    final out = File('E:/AI/zcode/tmp/localfit-batch4/multi-$label.json');
    out.parent.createSync(recursive: true);
    out.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'label': label,
        'model': model,
        'rounds': rounds,
        'total': total,
        'passed': pass,
        'percent': pct,
        'failures': failures,
        'cases': [
          for (final s in scripts) {'id': s.id, 'desc': s.desc},
        ],
      }),
      encoding: utf8,
    );
    expect(pass, total, reason: '多轮剧本 $pass/$total；失败见 $out');
  }

  test('多轮对话：改口 / 指代 / 已应用后续 / 否定 / 跨话题', () async {
    await runScripts();
  }, skip: skipReason);
}

/// 配置读取桩（与服务真实构造方式一致）。
final class _Config implements AiProviderConfigurationReader {
  const _Config(this._value);

  final AiProviderConfiguration _value;

  @override
  Future<AiProviderConfiguration?> loadConfiguration() async => _value;
}

/// 按名字取食物（种餐用；fixture 里这六条一定存在）。
Future<FoodRecord> _foodByName(FoodRepository repo, String name) async {
  final hits = await repo.searchExact(name);
  final exact = hits.where((f) => f.name == name).toList();
  if (exact.isEmpty) {
    throw StateError('fixture 里没有食物「$name」——剧本写错了');
  }
  return exact.first;
}

/// 清掉餐记录（每个剧本组合都从干净状态开始，避免上一轮种的数据串味）。
Future<void> _clearMeals(AppDatabase database) async {
  await database.delete(database.mealItems).go();
  await database.delete(database.meals).go();
}

class _Store implements SecureKeyValueStore {
  _Store(this.value);
  final String value;

  @override
  Future<String?> read(String key) async => value;

  @override
  Future<void> write(String key, String value) async {}

  @override
  Future<void> delete(String key) async {}
}

class _Ids implements IdGenerator {
  var _n = 0;

  @override
  String next() => 'mt-id-${_n++}';
}
