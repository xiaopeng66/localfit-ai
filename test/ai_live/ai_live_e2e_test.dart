import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/storage/secure_key_value_store.dart';
import 'package:localfit_ai/features/ai_conversation/data/open_ai_compatible_conversation_service.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_registry.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_turn.dart';
import 'package:localfit_ai/features/ai_conversation/domain/conversation_message.dart';
import 'package:localfit_ai/features/settings/data/ai_api_key_store.dart';
import 'package:localfit_ai/features/settings/data/dio_ai_endpoint_probe.dart';
import 'package:localfit_ai/features/settings/domain/ai_provider_protocol.dart';
import 'package:localfit_ai/features/settings/domain/ai_provider_settings.dart';
import 'package:localfit_ai/features/training/data/open_ai_compatible_workout_plan_provider.dart';
import 'package:localfit_ai/features/training/domain/workout_plan.dart';

/// **真实 AI 端到端（可选、默认跳过；2026-10-15 用户明确授权）**。
///
/// 打的是**真**供应商（OpenAI 兼容 chat 协议），走的是 **App 自己的客户端栈**：
/// 同 `DioAiEndpointProbe` / `OpenAiCompatibleConversationService` /
/// `OpenAiCompatibleWorkoutPlanProvider` / `parseChatEditTurn`——即
/// 「AI 对软件的控制接口」这一层，而不是另写一套 HTTP。
///
/// **凭据不入库**：API Key 只从环境变量读，仓库里只有端点与模型名（非秘密）：
///
/// ```text
/// LF_AI_LIVE_KEY=sk-...  （必需；未设置 ⇒ 整组跳过）
/// LF_AI_LIVE_BASE=https://api.xiaopangno1.dpdns.org/v1  （可选）
/// LF_AI_LIVE_MODEL=deepseek-v4.1-flash                  （可选）
/// ```
///
/// 断言口径：**模型给什么就报什么**——解析不出来就是失败（那正是
/// 「模型输出能不能被 App 的控制接口接受」的真实信号），不静默放过。
// 【工具盲点，2026-10-16 实测】`flutter test` **不认** `@Timeout` 注解
// （放 main 上也照样 30s 掐断），所以实时运行的超时由命令行给：
//   flutter test --timeout 240s test/ai_live/...
// 上游 `deepseek-ai/deepseek-v4.1-flash` 实测 TTFB ≈ 11s、整请求 40–46s，
// 默认 30s 会在「app 的传输上限」之前先把用例打断 ⇒ 结论被工具掩盖。
void main() {
  final env = Platform.environment;
  final apiKey = env['LF_AI_LIVE_KEY']?.trim() ?? '';
  final baseUrl =
      env['LF_AI_LIVE_BASE']?.trim() ?? 'https://api.xiaopangno1.dpdns.org/v1';
  // 该供应商 /v1/models 实测只挂 `deepseek-v4.1-flash`；用户给的
  // `glm-5.3-flash` 在它那儿是 503 model_not_found（见证据记录）。
  final model = env['LF_AI_LIVE_MODEL']?.trim() ?? 'deepseek-v4.1-flash';
  final skipReason = apiKey.isEmpty
      ? '未设置 LF_AI_LIVE_KEY：真实 AI 测试默认跳过（不打印、不落盘任何凭据）'
      : null;

  final configuration = AiProviderConfiguration(
    baseUrl: baseUrl,
    model: model,
    protocol: AiProviderProtocol.chatCompletions,
  );

  final dio = Dio();
  final keyStore = AiApiKeyStore(store: _MemoryStore()..put(apiKey));

  group('真实 AI 端到端（App 客户端栈 → 真供应商）', () {
    test('① 连通性探针：GET /models 成功且模型列表非空', () async {
      final result = await DioAiEndpointProbe(dio: Dio()).probe(
        baseUrl: baseUrl,
        protocol: AiProviderProtocol.chatCompletions,
        apiKey: apiKey,
      );
      // 逐项打印（脱敏：不含任何凭据）便于入档。
      debugPrint(
        '[live] probe ok=${result.isSuccess} models=${result.models} '
        'msg=${result.message}',
      );
      expect(result.isSuccess, isTrue, reason: result.message);
      expect(result.models, isNotEmpty);
      expect(result.models, contains(model));
    });

    test('② 对话流式：真回复非空、chunk 可见', () async {
      final service = OpenAiCompatibleConversationService(
        dio: dio,
        configurationReader: _Configuration(configuration),
        apiKeyStore: keyStore,
      );
      final chunks = <String>[];
      final buffer = StringBuffer();
      final stream = service.sendMessage(
        messages: [
          ConversationMessage(
            id: 'live-1',
            role: ConversationRole.user,
            text: '用一句话说明今天适合做的三个自重动作，不要列表以外的解释。',
            createdAt: DateTime.utc(2026, 10, 15, 12),
          ),
        ],
        onProgress: (chunk) {
          chunks.add(chunk);
          buffer.write(chunk);
        },
      );
      await stream.drain<void>();
      final reply = buffer.toString();
      debugPrint(
        '[live] chat chunks=${chunks.length} reply=${reply.length} chars '
        'head="${_head(reply, 120)}"',
      );
      expect(reply.trim(), isNotEmpty);
      expect(chunks.length, greaterThan(1), reason: '应是流式分片，不是一次整包');
    });

    test('③ 控制接口·编辑信封：模型提议的 workout.plan.create 能被 App 解析', () async {
      final service = OpenAiCompatibleConversationService(
        dio: dio,
        configurationReader: _Configuration(configuration),
        apiKeyStore: keyStore,
      );
      // system 段 = App 自己的协议渲染（与对话里注入的是同一个来源）。
      final registry = ChatEditCommandRegistry();
      final protocol = registry.renderProtocol();
      final chunks = <String>[];
      final buffer = StringBuffer();
      await service
          .sendMessage(
            messages: [
              ConversationMessage(
                id: 'live-2',
                role: ConversationRole.user,
                text:
                    '帮我创建一个 3 天/周的自重训练计划：周一、周四、周六，'
                    '动作只用给定的本地动作库（就地取材）。',
                createdAt: DateTime.utc(2026, 10, 15, 12, 5),
              ),
            ],
            onProgress: (chunk) {
              chunks.add(chunk);
              buffer.write(chunk);
            },
            systemContext:
                '$protocol\n\n可用本地动作 id：ex-plank（平板支撑）、'
                'ex-push-up（俯卧撑）、ex-barbell-squat（杠铃深蹲）。',
          )
          .drain<void>();
      final reply = buffer.toString();
      final turn = parseChatEditTurn(reply, registry);
      debugPrint(
        '[live] edit-turn parsed=${turn != null} '
        'rows=${turn?.rows.length ?? 0} chars=${reply.length} '
        'head="${_head(reply, 200)}"',
      );
      if (turn == null) {
        // 解析失败时把**尾部**也打出来：截断（finish_reason=length）与
        // 「散文在前」在头部看不出区别，尾部一看便知（2026-10-16 实测排查加）。
        debugPrint(
          '[live] edit-turn tail="${_head(reply.length <= 260 ? '' : reply.substring(reply.length - 260), 260)}"',
        );
      }
      expect(turn, isNotNull, reason: '整段回复里应含 App 的编辑信封');
      final commands = [
        for (final row in turn!.rows)
          if (row.command != null) row.command!,
      ];
      for (final c in commands) {
        debugPrint('[live] command ${c.action} args=${jsonEncode(c.args)}');
      }
      expect(
        commands.map((c) => c.action),
        contains('workout.plan.create'),
        reason: '真实模型应给出创建计划命令（写入由 chat_edit_executor_test 覆盖）',
      );
      final create = commands.firstWhere(
        (c) => c.action == 'workout.plan.create',
      );
      final days = create.args['days'];
      expect(days, isA<List<Object?>>());
      expect((days! as List<Object?>), isNotEmpty);
    });

    test('④ 控制接口·计划草案流：App 的 plan provider 能解出一份可用草案', () async {
      final provider = OpenAiCompatibleWorkoutPlanProvider(
        dio: Dio(),
        configurationReader: _Configuration(configuration),
        apiKeyStore: keyStore,
      );
      final draft = await provider.generate(
        const AiWorkoutPlanRequest(
          daysPerWeek: 2,
          goalText: '以自重为主，先把动作做标准',
          exercises: [
            ExerciseOption(id: 'ex-plank', name: '平板支撑'),
            ExerciseOption(id: 'ex-push-up', name: '俯卧撑'),
          ],
        ),
      );
      debugPrint(
        '[live] plan name="${draft.name}" days=${draft.days.length} '
        'entries=${draft.days.fold<int>(0, (n, d) => n + d.entries.length)}',
      );
      expect(draft.name.trim(), isNotEmpty);
      expect(draft.days, isNotEmpty);
      final ids = {
        for (final day in draft.days)
          for (final entry in day.entries) entry.exerciseId,
      };
      // 真实 ID 约束：草案里的动作 id 必须来自我们给的动作库（不是模型编的）。
      expect(ids, isNotEmpty);
      expect(
        ids.every((id) => id == 'ex-plank' || id == 'ex-push-up'),
        isTrue,
        reason: '模型不得引入库外动作 id：$ids',
      );
    });
  }, skip: skipReason);
}

String _head(String value, int max) {
  final flat = value.replaceAll('\n', ' ');
  return flat.length <= max ? flat : '${flat.substring(0, max)}…';
}

final class _Configuration implements AiProviderConfigurationReader {
  const _Configuration(this._value);

  final AiProviderConfiguration _value;

  @override
  Future<AiProviderConfiguration?> loadConfiguration() async => _value;
}

final class _MemoryStore implements SecureKeyValueStore {
  final _values = <String, String>{};

  void put(String value) => _values['localfit.ai.api_key.v1'] = value;

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);
}
