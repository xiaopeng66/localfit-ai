import 'package:localfit_ai/features/settings/domain/ai_provider_protocol.dart';
import 'package:localfit_ai/features/settings/domain/ai_reasoning_mode.dart';

final class AiProviderConfiguration {
  const AiProviderConfiguration({
    required this.baseUrl,
    required this.model,
    this.protocol = AiProviderProtocol.chatCompletions,
    this.reasoning = AiReasoningMode.disabled,
  });

  final String baseUrl;
  final String model;

  /// 该配置走哪种 wire 协议（docs/24）。默认 Chat Completions＝旧行为。
  final AiProviderProtocol protocol;

  /// 推理开关（docs/29 §P4）。默认关闭推理＝推理型模型的空回复修复。
  final AiReasoningMode reasoning;
}

final class AiProviderSettings {
  const AiProviderSettings({this.configuration, required this.hasApiKey});

  final AiProviderConfiguration? configuration;
  final bool hasApiKey;
}

final class AiProviderSettingsInput {
  const AiProviderSettingsInput({
    required this.baseUrl,
    required this.model,
    this.apiKey,
    this.protocol = AiProviderProtocol.chatCompletions,
    this.reasoning = AiReasoningMode.disabled,
  });

  final String baseUrl;
  final String model;
  final String? apiKey;
  final AiProviderProtocol protocol;
  final AiReasoningMode reasoning;
}

abstract interface class AiProviderConfigurationReader {
  Future<AiProviderConfiguration?> loadConfiguration();
}

abstract interface class AiProviderSettingsStore
    implements AiProviderConfigurationReader {
  Future<AiProviderSettings> load();
  Future<void> save(AiProviderSettingsInput input);
  Future<void> clearApiKey();
}
