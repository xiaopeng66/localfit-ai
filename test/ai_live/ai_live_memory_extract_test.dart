import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/storage/secure_key_value_store.dart';
import 'package:localfit_ai/features/ai_conversation/data/open_ai_compatible_conversation_service.dart';
import 'package:localfit_ai/features/ai_conversation/domain/conversation_message.dart';
import 'package:localfit_ai/features/ai_memory/application/ai_memory_candidates.dart';
import 'package:localfit_ai/features/ai_memory/domain/ai_memory.dart';
import 'package:localfit_ai/features/settings/data/ai_api_key_store.dart';
import 'package:localfit_ai/features/settings/domain/ai_provider_protocol.dart';
import 'package:localfit_ai/features/settings/domain/ai_provider_settings.dart';

/// v2「提炼记忆」真实模型实测（默认跳过）。
///
/// 只钉一件事：**真模型对我们这条提示词给出的回复必须能被解析器吃下**
/// （不是「模型一定要提炼出什么」——那是模型判断力，不是 App 契约）。
void main() {
  final env = Platform.environment;
  final apiKey = env['LF_AI_LIVE_KEY']?.trim() ?? '';
  final baseUrl = env['LF_AI_LIVE_BASE']?.trim() ?? '';
  final model = env['LF_AI_LIVE_MODEL']?.trim() ?? '';
  final skipReason = (apiKey.isEmpty || baseUrl.isEmpty || model.isEmpty)
      ? '未设置 LF_AI_LIVE_KEY / LF_AI_LIVE_BASE / LF_AI_LIVE_MODEL：提炼实测默认跳过'
      : null;

  test(
    '提炼记忆：真模型输出可解析的候选 JSON（含结构化字段的排除纪律）',
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
      const transcript = '''
U: 我平时不吃香菜，另外我对芒果过敏。
A: 好的，我记下了。
U: 我周三晚上一般去健身房练腿，器械区人少的时候先练深蹲。
A: 明白，那周三的安排就按练腿来。
U: 今天中午吃了 200 克鸡胸肉。
''';
      final buffer = StringBuffer();
      await service
          .sendMessage(
            messages: [
              ConversationMessage(
                id: 'live-extract-1',
                role: ConversationRole.user,
                text: aiMemoryExtractPrompt(transcript),
                createdAt: DateTime.utc(2026, 10, 17, 12),
              ),
            ],
            onProgress: buffer.write,
            systemContext: null,
          )
          .drain<void>();

      final parse = parseAiMemoryCandidates(buffer.toString());
      debugPrint(
        '[live-extract] reply=${parse.reply} '
        'candidates=${parse.candidates.map((c) => '${c.text}[${c.kind.name}/${c.domain.name}]').join(' | ')}',
      );
      expect(
        parse.candidates,
        isNotEmpty,
        reason: '转录里有「不吃香菜」「周三练腿」这类明显该记的软信息',
      );
      // 结构化字段纪律：过敏属于 constraints.set，不该被收进记忆。
      final texts = parse.candidates.map((c) => c.text).join('；');
      expect(
        texts,
        isNot(contains('芒果')),
        reason: '过敏/忌口是结构化字段，规则 11 明确要求不进记忆',
      );
      for (final candidate in parse.candidates) {
        expect(
          candidate.text.length,
          lessThanOrEqualTo(kAiMemoryMaxTextLength),
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 4)),
    skip: skipReason,
  );
}

final class _Config implements AiProviderConfigurationReader {
  const _Config(this.configuration);

  final AiProviderConfiguration configuration;

  @override
  Future<AiProviderConfiguration?> loadConfiguration() async => configuration;
}

final class _Store implements SecureKeyValueStore {
  const _Store(this.value);

  final String value;

  @override
  Future<String?> read(String key) async => value;

  @override
  Future<void> write(String key, String value) async {}

  @override
  Future<void> delete(String key) async {}
}
