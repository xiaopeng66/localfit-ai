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
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_registry.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_turn.dart';
import 'package:localfit_ai/features/ai_conversation/domain/conversation_message.dart';
import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart';
import 'package:localfit_ai/features/hydration/data/water_repository.dart';
import 'package:localfit_ai/features/nutrition/data/dish_library_repository.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/settings/data/ai_api_key_store.dart';
import 'package:localfit_ai/features/settings/domain/ai_provider_protocol.dart';
import 'package:localfit_ai/features/settings/domain/ai_provider_settings.dart';
import 'package:localfit_ai/features/training/data/workout_plan_repository.dart';
import 'package:localfit_ai/features/training/data/workout_session_repository.dart';

import '../support/food_fixture.dart';

/// **编辑卡识别率实测**（`ai-live`）。
///
/// 用户 2026-10-24：「你再检查一下 AI 对话功能是否能每次都正确弹出应用卡片，
/// 我实测很多次都不弹出」。本文件把「不弹出」变成一个**可量化**的数字：
/// N 条自然语言 × 每条 R 次，统计**第一趟就有信封**（编辑卡会弹）的比率。
///
/// 与既有 live 测试的分工：`ai_live_colloquial_test.dart` 走 App 的真实补救
/// 路径（第一趟失败会带 nudge 重跑）并断言「写库正确」；本文件**故意关掉
/// 重跑**，量的是「模型第一趟愿不愿意给信封」——那道坎才是用户看到
/// 「卡片不弹」的地方。
///
/// 默认跳过；设了 `LF_AI_LIVE_KEY` / `LF_AI_LIVE_BASE` / `LF_AI_LIVE_MODEL`
/// 才真跑（`--timeout 900s`）。**凭据零入库**：只读环境变量。
void main() {
  final env = Platform.environment;
  final apiKey = env['LF_AI_LIVE_KEY']?.trim() ?? '';
  final baseUrl = env['LF_AI_LIVE_BASE']?.trim() ?? '';
  final model = env['LF_AI_LIVE_MODEL']?.trim() ?? '';
  final rounds = int.tryParse(env['LF_AI_LIVE_ROUNDS'] ?? '') ?? 2;
  final onlyCase = env['LF_AI_LIVE_ONLY']?.trim() ?? '';

  final today = DateTime(2026, 10, 24, 12).toUtc();
  final clock = FixedAppClock(today);
  final ids = _Ids();
  final String? skipReason =
      (apiKey.isEmpty || baseUrl.isEmpty || model.isEmpty)
      ? '未设置 LF_AI_LIVE_KEY / LF_AI_LIVE_BASE / LF_AI_LIVE_MODEL：识别率实测默认跳过'
      : null;

  final registry = ChatEditCommandRegistry();

  late AppDatabase database;
  late MealRepository meals;
  late DishLibraryRepository dishes;
  late WaterRepository water;
  late CanteenRepository canteen;
  late WorkoutPlanRepository plans;
  late WorkoutSessionRepository sessions;
  late DriftChatEditContextLoader contextLoader;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await seedFoodFixture(database);
    for (final (id, name, group, equipment) in const [
      ('ex-push-up', '俯卧撑', 'chest', 'bodyweight'),
      ('ex-plank', '平板支撑', 'core', 'bodyweight'),
      ('ex-barbell-squat', '杠铃深蹲', 'legs', 'barbell'),
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

    // 食堂菜一条（供「食堂吃」这类说法定位）+ 菜品库一条。
    canteen = CanteenRepository(
      database: database,
      idGenerator: ids,
      clock: clock,
    );
    final venue = await canteen.createVenue(name: '第一食堂', campusName: '示范大学');
    meals = MealRepository(database: database, idGenerator: ids, clock: clock);
    dishes = DishLibraryRepository(
      database: database,
      idGenerator: ids,
      clock: clock,
    );
    water = WaterRepository(database: database, idGenerator: ids, clock: clock);
    plans = WorkoutPlanRepository(
      database: database,
      idGenerator: ids,
      clock: clock,
    );
    sessions = WorkoutSessionRepository(
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
    expect(venue, isNotEmpty);
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

  /// 跑一趟（**不重跑**）：返回原始输出 + 解析出的信封。
  Future<({String raw, ChatEditTurn? turn})> oneShot(String request) async {
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
              id: 'rate-${DateTime.now().microsecondsSinceEpoch}',
              role: ConversationRole.user,
              text: request,
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

  /// 语料：**必须弹卡**的修改请求（覆盖 37 条命令的主要落点 + 用户口语变体）。
  ///
  /// 每条带期望的 action 前缀（`null` = 只要求「有信封、任意合法命令」）。
  /// 语料分两类（**判据不同，不能一起算**）：
  /// * `expectEnvelope: true` —— 必弹卡（修改请求，含「信息不全」的兜底）；
  /// * `expectEnvelope: false` —— **必须不弹卡**（纯提问 / 闲聊 / 协议明文
  ///   规定只能用纯文本的场景，例如规则 9 的「步数当天事实」）。
  ///
  /// 上一版把 M23（「今天走了两万步」）算成必弹卡是**语料定错**：协议规则 9
  /// 明写步数由系统读取、只能用纯文本如实说明。这里改判为反向用例。
  /// 语料：**必须弹卡且命令正确**的修改请求（覆盖主要落点 + 用户口语变体）。
  ///
  /// 每条：
  /// * `expect` —— 期望的 action；`null` = 只要信封成立，任意合法命令。
  /// * `expectEnvelope: false` —— 反向用例（必须**不**弹卡）。
  /// * `exclusive + allowed` —— **不许夹带**：给的所有命令都必须落在 `allowed`
  ///   里。用来钉「用户说删午餐，模型不许推荐记午餐」这类**错误推荐**。
  const cases =
      <
        ({
          String id,
          String text,
          String? expect,
          bool expectEnvelope,
          bool exclusive,
          Set<String>? allowed,
        })
      >[
        // ── 记一餐族 ────────────────────────────────────────────────
        (
          id: 'M01',
          text: '早餐一个鸡蛋一杯牛奶',
          expect: 'meal.create',
          expectEnvelope: true,
          exclusive: true,
          allowed: {'meal.create', 'food.create'},
        ),
        (
          id: 'M02',
          text: '我中午吃了米饭和鸡胸肉',
          expect: 'meal.create',
          expectEnvelope: true,
          exclusive: true,
          allowed: {'meal.create', 'food.create'},
        ),
        (
          id: 'M09',
          text: '早上两个包子',
          expect: 'meal.create',
          expectEnvelope: true,
          exclusive: true,
          allowed: {'meal.create', 'food.create'},
        ),
        (
          id: 'M17',
          text: '早上吃了燕麦粥',
          expect: 'meal.create',
          expectEnvelope: true,
          exclusive: true,
          allowed: {'meal.create', 'food.create'},
        ),
        (
          id: 'M24',
          text: '帮我记录早餐：两个鸡蛋，200毫升牛奶',
          expect: 'meal.create',
          expectEnvelope: true,
          exclusive: true,
          allowed: {'meal.create', 'food.create'},
        ),
        (
          id: 'M22',
          text: '加一道番茄炒蛋当晚饭',
          expect: 'meal.create',
          expectEnvelope: true,
          exclusive: true,
          allowed: {'meal.create', 'dish.upsert', 'food.create'},
        ),
        (
          id: 'M05',
          text: '晚上吃了一碗番茄炒蛋',
          expect: 'meal.create',
          expectEnvelope: true,
          exclusive: true,
          allowed: {'meal.create', 'dish.upsert', 'food.create'},
        ),

        // ── 饮水 / 体重族 ──────────────────────────────────────────
        (
          id: 'M03',
          text: '刚喝了 300 毫升水',
          expect: 'water.add',
          expectEnvelope: true,
          exclusive: true,
          allowed: {'water.add'},
        ),
        (
          id: 'M07',
          text: '我喝了半升水',
          expect: 'water.add',
          expectEnvelope: true,
          exclusive: true,
          allowed: {'water.add'},
        ),
        (
          id: 'M14',
          text: '记一笔 500 毫升水',
          expect: 'water.add',
          expectEnvelope: true,
          exclusive: true,
          allowed: {'water.add'},
        ),
        (
          id: 'M04',
          text: '帮我记一下今天体重 70.5 公斤',
          expect: 'weight.log',
          expectEnvelope: true,
          exclusive: true,
          allowed: {'weight.log'},
        ),
        (
          id: 'M19',
          text: '体重 68.2kg',
          expect: 'weight.log',
          expectEnvelope: true,
          exclusive: true,
          allowed: {'weight.log'},
        ),

        // ── 新建食材 ──────────────────────────────────────────────
        (
          id: 'M08',
          text: '加一个叫「麻辣烫」的食材',
          expect: 'food.create',
          expectEnvelope: true,
          exclusive: true,
          allowed: {'food.create'},
        ),

        // ── 约束 / 目标（结构化事实，不许写进记忆）─────────────────
        (
          id: 'M10',
          text: '我乳糖不耐受',
          expect: 'constraints.set',
          expectEnvelope: true,
          exclusive: true,
          allowed: {'constraints.set'},
        ),
        (
          id: 'M11',
          text: '我不吃香菜了',
          expect: 'constraints.set',
          expectEnvelope: true,
          exclusive: true,
          allowed: {'constraints.set'},
        ),
        (
          id: 'M12',
          text: '我目标是减脂',
          expect: 'profile.goal.update',
          expectEnvelope: true,
          exclusive: true,
          allowed: {'profile.goal.update'},
        ),
        (
          id: 'M13',
          text: '饮水目标改成 2500 毫升',
          expect: 'targets.update',
          expectEnvelope: true,
          exclusive: true,
          allowed: {'targets.update'},
        ),

        // ── 训练 ──────────────────────────────────────────────────
        // 用户说「练了深蹲 3 组」= 已经练了，要落成组次记录；
        // `session.start` 开新会话也合理（组次记录的前置），除此之外都算推荐错。
        (
          id: 'M16',
          text: '我今天下午练了深蹲 3 组',
          expect: null,
          expectEnvelope: true,
          exclusive: true,
          allowed: {'set.log', 'session.start', 'session.finish'},
        ),

        // ── 记忆（软信息）─────────────────────────────────────────
        (
          id: 'M20',
          text: '记住了我喜欢清淡口味',
          expect: 'memory.remember',
          expectEnvelope: true,
          exclusive: true,
          allowed: {'memory.remember'},
        ),

        // ── 「有明确目标、库里没有」：给空 edits 说明，不许推荐别的 ──
        // 用户说「把今天的午餐删了」而今天没记录 ⇒ 期望 `meal.delete` 精确命中；
        // 库里没有就该**什么都不给**、只说明——推荐「记午餐」是错误答案。
        (
          id: 'M06',
          text: '把今天的午餐删了',
          expect: null,
          expectEnvelope: true,
          exclusive: true,
          allowed: {'meal.delete'},
        ),

        // ── 「指代不明」：给候选可以，但候选必须都指向用户说的那件事 ──
        (
          id: 'M18',
          text: '把那条记录去掉',
          expect: null,
          expectEnvelope: true,
          exclusive: true,
          allowed: {'meal.delete', 'water.delete', 'weight.log', 'dish.delete'},
        ),
        (
          id: 'M27',
          text: '刚才那顿算晚餐',
          expect: null,
          expectEnvelope: true,
          exclusive: true,
          allowed: {'meal.update', 'meal.create'},
        ),
        (
          id: 'M15',
          text: '午餐改成了鸡胸肉饭',
          expect: null,
          expectEnvelope: true,
          exclusive: true,
          allowed: {'meal.update', 'meal.create'},
        ),
        (
          id: 'M25',
          text: '鸡胸肉 150 克',
          expect: null,
          expectEnvelope: true,
          exclusive: true,
          allowed: {'meal.create', 'food.create'},
        ),
        (
          id: 'M21',
          text: '午餐 600 大卡左右',
          expect: null,
          expectEnvelope: true,
          exclusive: true,
          allowed: {'meal.create', 'meal.update'},
        ),
      ];

  Future<void> runRates({required String label}) async {
    final total = <String, ({int ok, int n})>{};
    final firstFailures = <String, List<String>>{};
    final actionMismatch = <String>[];
    var okAll = 0;
    var nAll = 0;

    for (final c in cases) {
      if (onlyCase.isNotEmpty && c.id != onlyCase) continue;
      var ok = 0;
      var n = 0;
      for (var r = 0; r < rounds; r++) {
        n++;
        nAll++;
        final result = await oneShot(c.text);
        final turn = result.turn;
        final hasEnvelope = turn != null;
        // 【两个轴，分开量】
        //
        // ① **弹卡率**（本比率）：信封成立没有 —— 这就是用户看到「卡片弹不弹」。
        // ② **命令准确性**（`actionMismatch`）：信封里的 action 是不是期望那条。
        //
        // 为什么必须拆开：模型在「库里没有这条」时给
        // `{"edits":[],"suggestions":[…]}` 是**协议允许的正确形态**（规则 0），
        // 卡片照样弹、按钮照样可点。把它算成「没弹卡」会把产品行为判错
        // （上一版就是这么把 94% 压到 81.5% 附近的）。
        // 【判据（2026-10-24 用户：不要模棱两可、不要推荐错误答案）】
        //
        // 一条用例**通过**必须同时满足：
        // 1. 弹卡（信封成立）；
        // 2. 命令**精确命中**期望 action —— 只出现在 edits 或 suggestions 里都算；
        // 3. **不夹带**任何期望之外的「替代 / 补充」命令。
        //
        // 第 2、3 条是这轮加的：上一版把「给了别的命令」记成 `actionMismatch`
        // 不算失败，于是「用户说删午餐、模型推荐记午餐」被当成合格——那正是
        // 用户点名的「推荐错误的答案」。现在它直接判红。
        final bool countedOk;
        final offered = <String>{
          for (final row in turn?.rows ?? const <ChatEditTurnItem>[])
            if (row.command != null) row.command!.action,
          for (final s in turn?.suggestions ?? const <ChatEditSuggestion>[])
            if (s.effectiveAction != null) s.effectiveAction!,
        };
        if (!c.expectEnvelope) {
          countedOk = !hasEnvelope; // 反向用例：不该出信封
        } else if (!hasEnvelope) {
          countedOk = false;
          firstFailures
              .putIfAbsent(c.id, () => [])
              .add(
                '无信封（卡片没弹）；原文前 120 字：'
                '${result.raw.replaceAll('\n', ' ').substring(0, result.raw.length.clamp(0, 120))}',
              );
        } else if (c.expect == null) {
          countedOk = true;
        } else if (!offered.contains(c.expect)) {
          countedOk = false;
          firstFailures
              .putIfAbsent(c.id, () => [])
              .add('命令错误：期望 ${c.expect}，实际给的是 $offered');
        } else if (c.exclusive &&
            offered.any((action) => !c.allowed!.contains(action))) {
          // 精确命中还不够：不许夹带用户没要求的替代命令。
          countedOk = false;
          final extra = offered
              .where((action) => !c.allowed!.contains(action))
              .toList();
          firstFailures
              .putIfAbsent(c.id, () => [])
              .add('夹带了用户没要求的命令：$extra（只允许 ${c.allowed}）');
        } else {
          countedOk = true;
        }
        if (countedOk) {
          ok++;
          okAll++;
        } else if (!c.expectEnvelope) {
          firstFailures
              .putIfAbsent(c.id, () => [])
              .add(
                '不该出信封却出了：${turn?.rows.map((r) => r.command?.action).toList()}',
              );
        }
        // 其余失败分支在上面各自记录了**具体**原因（无信封 / 命令错误 /
        // 夹带命令）。2026-10-24 修：这里原先无条件再追加一条「无信封」，
        // 导致 M09 这类同时有两种失败原因的用例在证据里显示成两条「无信封」，
        // 掩盖了「命令错误」这一条。
      }
      total[c.id] = (ok: ok, n: n);
      debugPrint('[rate] ${c.id} $ok/$n  «${c.text}»');
    }

    final pct = nAll == 0 ? 0 : (okAll * 100 / nAll);
    debugPrint(
      '[rate] === $label 总计 $okAll/$nAll = ${pct.toStringAsFixed(1)}% ===',
    );
    for (final entry in firstFailures.entries) {
      debugPrint('[rate] 失败 ${entry.key}: ${entry.value.join(' | ')}');
    }
    for (final m in actionMismatch) {
      debugPrint('[rate] 命令不符（不影响弹卡率） $m');
    }
    // 落盘给证据用（`tmp/` 内，不进仓库）。
    final out = File('E:/AI/zcode/tmp/localfit-batch4/live-rate-$label.json');
    out.parent.createSync(recursive: true);
    out.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'label': label,
        'model': model,
        'rounds': rounds,
        'total': nAll,
        'passed': okAll,
        'percent': double.parse(pct.toStringAsFixed(1)),
        'perCase': {
          for (final e in total.entries) e.key: '${e.value.ok}/${e.value.n}',
        },
        'failures': firstFailures,
        'actionMismatch': actionMismatch,
      }),
      encoding: utf8,
    );
    // 不设硬阈值：这一跑是**测量**，不是门禁（数字进证据，修复后再对比）。
    expect(nAll, greaterThan(0));
  }

  test(
    '编辑卡识别率（第一趟，不重跑）',
    () async {
      await runRates(label: 'baseline');
    },
    // `test()` 的 `skip` 接受 `String?`（写明为什么跳过）。
    skip: skipReason,
    timeout: const Timeout(Duration(minutes: 20)),
  );
}

final class _Ids implements IdGenerator {
  int _v = 0;

  @override
  String next() => 'id-${_v++}';
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
