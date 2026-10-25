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

/// **记忆写入实测**（`ai-live`）：模型会不会在「该记的时候记、不该记的时候别乱记」。
///
/// 用户 2026-10-24：「优化 ai 记忆的机制，确保这个记忆系统，对我的使用真正有帮助」。
///
/// 召回侧（`memory_recall_effectiveness_test`）已经修好一处设计缺陷。本文件
/// 测**另一头**：模型有没有把该记的东西提出来（`memory.remember`），以及
/// 有没有把**结构化的东西**也塞进记忆（那是协议规则 11 明确禁止的——
/// 目标/身高/过敏都应该走各自的命令，写进记忆会造成同一事实两处不一致）。
///
/// 每条用例给一句自然语言 + 期望：
/// * `expectRemember: true` —— 该提议 `memory.remember`；
/// * `expectRemember: false` —— **不该**写记忆（要么是结构化事实，要么是闲聊）；
/// * `forbidActions` —— 这些命令出现即失败（防止用错命令顶替）。
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
      ? '未设置 LF_AI_LIVE_KEY / LF_AI_LIVE_BASE / LF_AI_LIVE_MODEL：记忆写入实测默认跳过'
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
    final foods = MealRepository(
      database: database,
      idGenerator: ids,
      clock: clock,
    );
    contextLoader = DriftChatEditContextLoader(
      database: database,
      clock: clock,
      mealRepository: foods,
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

  Future<ChatEditTurn?> oneShot(String text) async {
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
    final snapshot = await contextLoader.build(userMessage: text);
    final buffer = StringBuffer();
    await service
        .sendMessage(
          messages: [
            ConversationMessage(
              id: 'mem-${DateTime.now().microsecondsSinceEpoch}',
              role: ConversationRole.user,
              text: text,
              createdAt: today,
            ),
          ],
          onProgress: buffer.write,
          systemContext: [registry.renderProtocol(), snapshot].join('\n\n'),
        )
        .drain<void>();
    return parseChatEditTurn(buffer.toString(), registry);
  }

  final cases =
      <
        ({
          String id,
          String text,
          bool expectRemember,
          Set<String> forbid,
          String why,
          Set<String> allowStructured,
        })
      >[];

  void addCase({
    required String id,
    required String text,
    required bool expectRemember,
    required String why,
    Set<String> forbid = const {},
    Set<String> allowStructured = const {},
  }) {
    cases.add((
      id: id,
      text: text,
      expectRemember: expectRemember,
      forbid: forbid,
      why: why,
      allowStructured: allowStructured,
    ));
  }

  // ── 该记的（软信息：口味/习惯/作息/常去窗口/沟通偏好）────────────
  addCase(
    id: 'R01',
    text: '记住我喜欢清淡口味，不要太咸',
    expectRemember: true,
    why: '典型软偏好，正是记忆该收的',
  );
  // 【判据纠正，第一版写错了】原写「必须 memory.remember」。但协议规则 11
  // 明写「过敏/忌口/饮食标签用 `constraints.set`」——模型给
  // `constraints.set` 是**正确**的，我这条判据把对的行为判成了错。
  // 正确判据：**要么** structured（constraints.set），**要么** memory.remember
  // 都可以；真正不许的是「什么都不做」。
  addCase(
    id: 'R02',
    text: '记住我不吃香菜',
    expectRemember: true,
    why: '忌口要么走 constraints.set 要么走记忆，但不能什么都不做',
    allowStructured: {'constraints.set'},
  );
  addCase(id: 'R03', text: '记住我一般周三晚上练腿', expectRemember: true, why: '作息/训练习惯');
  addCase(id: 'R04', text: '记住我常去二食堂的川菜窗口', expectRemember: true, why: '常去窗口');
  addCase(
    id: 'R05',
    text: '记住回答我时简短一点，别啰嗦',
    expectRemember: true,
    why: '沟通偏好（协议明列可记）',
  );

  // ── 不该记的（结构化事实该走各自命令）──────────────────────────
  addCase(
    id: 'R06',
    text: '记住我目标是减脂',
    expectRemember: false,
    why: '目标是结构化字段，该用 profile.goal.update（规则 11 明令）',
    forbid: {'memory.remember'},
  );
  addCase(
    id: 'R07',
    text: '记住我身高 178，2000 年生的',
    expectRemember: false,
    why: '身高/出生年该用 profile.body.update',
    forbid: {'memory.remember'},
  );
  addCase(
    id: 'R08',
    text: '记住我对花生过敏',
    expectRemember: false,
    why: '过敏是硬约束，该用 constraints.set（写进记忆会两处不一致）',
    forbid: {'memory.remember'},
  );
  addCase(
    id: 'R09',
    text: '记住我的饮水目标是 2500 毫升',
    expectRemember: false,
    why: '目标该用 targets.update',
    forbid: {'memory.remember'},
  );

  // ── 不该记的（根本没有「记住」的意思）────────────────────────────
  addCase(
    id: 'R10',
    text: '今天天气不错',
    expectRemember: false,
    why: '闲聊不该写记忆',
    forbid: {'memory.remember'},
  );
  addCase(
    id: 'R11',
    text: '午饭吃了米饭',
    expectRemember: false,
    why: '记一餐是数据写入，不是记忆',
    forbid: {'memory.remember'},
  );

  Future<void> runCases() async {
    var pass = 0;
    var total = 0;
    final failures = <String, List<String>>{};

    for (final c in cases) {
      if (onlyCase.isNotEmpty && c.id != onlyCase) continue;
      for (var r = 0; r < rounds; r++) {
        total++;
        try {
          final turn = await oneShot(c.text);
          final actions = <String>{
            for (final row in turn?.rows ?? const <ChatEditTurnItem>[])
              if (row.command != null) row.command!.action,
            for (final s in turn?.suggestions ?? const <ChatEditSuggestion>[])
              if (s.effectiveAction != null) s.effectiveAction!,
          };
          final remembered = actions.contains('memory.remember');
          final problems = <String>[];
          if (c.expectRemember && !remembered) {
            final structured = actions.intersection(c.allowStructured);
            if (structured.isEmpty) {
              problems.add('该记的没记（给了：${actions.isEmpty ? "纯文本/空" : actions}）');
            }
          }
          if (!c.expectRemember && remembered) {
            problems.add('不该记的记了：${c.why}');
          }
          final forbidden = actions.intersection(c.forbid);
          if (forbidden.isNotEmpty) {
            problems.add('用了不该用的命令：$forbidden（${c.why}）');
          }
          if (problems.isEmpty) {
            pass++;
          } else {
            failures.putIfAbsent(c.id, () => []).addAll(problems);
          }
          debugPrint(
            '[mem] ${c.id} ${problems.isEmpty ? "OK" : "FAIL"} «${c.text}» ⇒ $actions',
          );
        } on Object catch (e) {
          failures.putIfAbsent(c.id, () => []).add('异常：$e');
          debugPrint('[mem] ${c.id} EXCEPTION $e');
        }
      }
    }

    final pct = total == 0 ? 0 : pass * 100 / total;
    debugPrint(
      '[mem] === $label 总计 $pass/$total = ${pct.toStringAsFixed(1)}% ===',
    );
    for (final entry in failures.entries) {
      debugPrint('[mem] 失败 ${entry.key}: ${entry.value.join(" | ")}');
    }
    final out = File('E:/AI/zcode/tmp/localfit-batch4/memory-$label.json');
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
      }),
      encoding: utf8,
    );
    expect(pass, total, reason: '记忆写入 $pass/$total；失败见 $out');
  }

  test('记忆写入：该记的记住 / 不该记的别记（11 条）', () async {
    await runCases();
  }, skip: skipReason);
}

final class _Config implements AiProviderConfigurationReader {
  const _Config(this._value);

  final AiProviderConfiguration _value;

  @override
  Future<AiProviderConfiguration?> loadConfiguration() async => _value;
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
  String next() => 'mem-id-${_n++}';
}
