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
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_proposal_audit.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_registry.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_turn.dart';
import 'package:localfit_ai/features/ai_conversation/domain/conversation_message.dart';
import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart';
import 'package:localfit_ai/features/hydration/data/water_repository.dart';
import 'package:localfit_ai/features/nutrition/data/dish_library_repository.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/settings/data/ai_api_key_store.dart';
import 'package:localfit_ai/features/settings/domain/ai_provider_protocol.dart';
import 'package:localfit_ai/features/settings/domain/ai_provider_settings.dart';
import 'package:localfit_ai/features/training/data/workout_plan_repository.dart';
import 'package:localfit_ai/features/training/data/workout_session_repository.dart';

import '../support/food_fixture.dart';

/// **内容正确性实测**（`ai-live`）。
///
/// 用户 2026-10-24：「确保 ai 能正确合理的调用所有功能，而且不会出错，比如
/// 我要晚餐，给我午餐，漏掉食物或者重复食物等」。
///
/// 跟另外两个实测集的分工：
/// * `ai_live_edit_card_rate_test` —— 单轮「卡弹不弹、命令对不对」；
/// * `ai_live_multi_turn_test` —— 多轮「改口/指代/跨话题」；
/// * **本文件** —— **内容**维度：餐次对不对、该记的都记了没、有没有重复。
///
/// 每条用例同时用**两个**判据（这是本文件的价值）：
/// 1. **关键词子串判据**（本文件自建，不依赖审查器）——机械、不会自证；
/// 2. **提案审查器**（`ChatEditProposalAudit`）——被验证的对象。
///
/// 两条必须一致：审查器说「没问题」而关键词说「有问题」= 审查器漏报；
/// 审查器报错而关键词没问题 = 误报。两种都算失败，且分开记录。
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
      ? '未设置 LF_AI_LIVE_KEY / LF_AI_LIVE_BASE / LF_AI_LIVE_MODEL：内容正确性实测默认跳过'
      : null;

  final registry = ChatEditCommandRegistry();

  late AppDatabase database;
  late DriftChatEditContextLoader contextLoader;
  late ChatEditProposalAudit auditor;

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
    final canteen = CanteenRepository(
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
    // 「番茄炒蛋」在菜品库里（S04 用得到）：不建的话模型只能拆成番茄+鸡蛋，
    // 那是对的（不会编造菜品），但会把「漏了番茄炒蛋」误判成模型的问题。
    // 第一版就漏了这一步——**测试环境问题，不是产品缺陷**。
    await dishes.create(
      DishDraft(
        name: '番茄炒蛋',
        mealSlot: 'dinner',
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
    auditor = ChatEditProposalAudit(
      userText: '',
      commands: const [],
      foodRepository: foods,
      mealRepository: meals,
      clock: clock,
    );
  });

  tearDown(() => database.close());

  Future<({String raw, ChatEditTurn? turn})> oneShot(String text) async {
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
              id: 'acc-${DateTime.now().microsecondsSinceEpoch}',
              role: ConversationRole.user,
              text: text,
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

  /// 用例：一句话 + 期望（关键词判据，**不经过审查器**）。
  ///
  /// `expectSlot`：期望的餐次（meal.create 的 slot）；null = 不判。
  /// `mustInclude`：必须出现在 items 里的食物名。
  /// `mustNotDuplicate`：items 里不许同名出现两次。
  final cases =
      <
        ({
          String id,
          String text,
          String? expectSlot,
          List<String> mustInclude,
          bool mustNotDuplicate,
        })
      >[];

  void addCase({
    required String id,
    required String text,
    String? expectSlot,
    List<String> mustInclude = const [],
    bool mustNotDuplicate = true,
  }) {
    cases.add((
      id: id,
      text: text,
      expectSlot: expectSlot,
      mustInclude: mustInclude,
      mustNotDuplicate: mustNotDuplicate,
    ));
  }

  // ── 餐次：用户明确说了哪一餐 ──────────────────────────────────
  addCase(
    id: 'S01',
    text: '晚饭吃了米饭和鸡胸肉',
    expectSlot: 'dinner',
    mustInclude: ['米饭', '鸡胸肉'],
  );
  addCase(
    id: 'S02',
    text: '午餐吃的米饭、鸡蛋',
    expectSlot: 'lunch',
    mustInclude: ['米饭', '鸡蛋'],
  );
  addCase(
    id: 'S03',
    text: '早餐两个鸡蛋一杯牛奶',
    expectSlot: 'breakfast',
    mustInclude: ['鸡蛋', '牛奶'],
  );
  addCase(
    id: 'S04',
    text: '晚上那顿吃了番茄炒蛋',
    expectSlot: 'dinner',
    mustInclude: ['番茄炒蛋'],
  );
  addCase(
    id: 'S05',
    text: '中午吃了一碗米饭',
    expectSlot: 'lunch',
    mustInclude: ['米饭'],
  );

  // ── 多项不漏 ────────────────────────────────────────────────
  addCase(
    id: 'S06',
    text: '晚饭吃了米饭、鸡胸肉、牛奶，还有一个苹果',
    expectSlot: 'dinner',
    mustInclude: ['米饭', '鸡胸肉', '牛奶', '苹果'],
  );
  addCase(
    id: 'S07',
    text: '早餐吃了鸡蛋、牛奶和苹果',
    expectSlot: 'breakfast',
    mustInclude: ['鸡蛋', '牛奶', '苹果'],
  );

  // ── 不该重复 ────────────────────────────────────────────────
  addCase(
    id: 'S08',
    text: '午饭吃了米饭和米饭',
    expectSlot: 'lunch',
    mustInclude: ['米饭'],
  );
  addCase(
    id: 'S09',
    text: '晚餐吃了米饭，还有米饭',
    expectSlot: 'dinner',
    mustInclude: ['米饭'],
  );

  Future<void> runCases() async {
    var pass = 0;
    var total = 0;
    final failures = <String, List<String>>{};
    final auditorDisagreements = <String>[];

    for (final c in cases) {
      if (onlyCase.isNotEmpty && c.id != onlyCase) continue;
      for (var r = 0; r < rounds; r++) {
        total++;
        try {
          final result = await oneShot(c.text);
          final turn = result.turn;
          final problems = <String>[];

          if (turn == null) {
            problems.add(
              '无信封；原文前 140 字：'
              '${result.raw.replaceAll('\n', ' ').substring(0, result.raw.length.clamp(0, 140))}',
            );
          } else {
            final creates = [
              for (final row in turn.rows)
                if (row.command?.action == 'meal.create') row.command!,
            ];
            if (creates.isEmpty) {
              problems.add(
                '没有 meal.create（给了：'
                '${turn.rows.map((r) => r.command?.action).toList()}）',
              );
            } else {
              // ① 餐次
              if (c.expectSlot != null) {
                final slots = {
                  for (final command in creates)
                    command.args['slot'] as String? ?? '',
                };
                if (!slots.contains(c.expectSlot)) {
                  problems.add('餐次错：期望 ${c.expectSlot}，实际 $slots');
                }
                if (slots.length > 1) {
                  problems.add('同一次记录给了多个餐次：$slots');
                }
              }
              // ② 不漏（关键词子串，**不依赖审查器**）
              final names = <String>[];
              final duplicates = <String>[];
              for (final command in creates) {
                final items = command.args['items'];
                if (items is! List) continue;
                for (final item in items) {
                  if (item is! Map) continue;
                  final name = (item['food'] as String? ?? '').trim();
                  if (name.isEmpty) continue;
                  if (names.contains(name)) duplicates.add(name);
                  names.add(name);
                }
              }
              for (final required in c.mustInclude) {
                if (!names.any((n) => n.contains(required))) {
                  problems.add('漏了「$required」（实际：$names）');
                }
              }
              // ③ 不重复
              if (c.mustNotDuplicate && duplicates.isNotEmpty) {
                problems.add('有重复食物：$duplicates');
              }

              // ④ 审查器一致性（被验证对象）
              final warnings = await auditor.audit(
                userText: c.text,
                commands: creates,
              );
              final auditKinds = warnings.map((w) => w.kind).toSet();
              if (problems.isEmpty && auditKinds.isNotEmpty) {
                auditorDisagreements.add(
                  '${c.id}: 关键词判据通过但审查器报了 $auditKinds'
                  '（${warnings.map((w) => w.message).join(' / ')}）',
                );
              }
              if (problems.isNotEmpty &&
                  !problems.any(
                    (p) =>
                        p.contains('餐次') ||
                        p.contains('重复') ||
                        p.contains('漏了'),
                  )) {
                // 问题只出在「没信封 / 没 meal.create」这类形态上：审查器
                // 无从判断，不算它漏报。
              } else if (problems.isNotEmpty && auditKinds.isEmpty) {
                auditorDisagreements.add(
                  '${c.id}: 关键词判据发现问题（${problems.join('；')}）但审查器没报',
                );
              }
            }
          }

          if (problems.isEmpty) {
            pass++;
          } else {
            failures.putIfAbsent(c.id, () => []).addAll(problems);
          }
          debugPrint(
            '[acc] ${c.id} ${problems.isEmpty ? "OK" : "FAIL"} «${c.text}»'
            '${problems.isEmpty ? "" : " ⇒ ${problems.join("；")}"}',
          );
        } on Object catch (e) {
          failures.putIfAbsent(c.id, () => []).add('异常：$e');
          debugPrint('[acc] ${c.id} EXCEPTION $e');
        }
      }
    }

    final pct = total == 0 ? 0 : pass * 100 / total;
    debugPrint(
      '[acc] === $label 总计 $pass/$total = ${pct.toStringAsFixed(1)}% ===',
    );
    for (final entry in failures.entries) {
      debugPrint('[acc] 失败 ${entry.key}: ${entry.value.join(" | ")}');
    }
    for (final note in auditorDisagreements) {
      debugPrint('[acc] 审查器分歧：$note');
    }
    final out = File('E:/AI/zcode/tmp/localfit-batch4/accuracy-$label.json');
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
        'auditorDisagreements': auditorDisagreements,
        'cases': [
          for (final c in cases)
            {
              'id': c.id,
              'text': c.text,
              'expectSlot': c.expectSlot,
              'mustInclude': c.mustInclude,
            },
        ],
      }),
      encoding: utf8,
    );
    expect(pass, total, reason: '内容正确性 $pass/$total；失败见 $out');
  }

  test('内容正确性：餐次 / 不漏 / 不重复（9 条口语）', () async {
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
  String next() => 'acc-id-${_n++}';
}
