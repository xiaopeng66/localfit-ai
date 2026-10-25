import 'package:drift/drift.dart' show Value;
import 'package:localfit_ai/core/errors/app_failure.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/settings/data/ai_api_key_store.dart';
import 'package:localfit_ai/features/settings/domain/ai_provider_protocol.dart';
import 'package:localfit_ai/features/settings/domain/ai_provider_settings.dart';
import 'package:localfit_ai/features/settings/domain/ai_reasoning_mode.dart';
import 'package:localfit_ai/features/settings/domain/open_ai_compatible_endpoint.dart';

final class LocalAiProviderSettingsStore implements AiProviderSettingsStore {
  LocalAiProviderSettingsStore({
    required this.database,
    required this.apiKeyStore,
  });

  static const configurationId = 'default';
  static const maxBaseUrlLength = 2048;
  static const maxModelLength = 256;

  final AppDatabase database;
  final AiApiKeyStore apiKeyStore;

  @override
  Future<AiProviderSettings> load() async {
    try {
      final configuration = await loadConfiguration();
      final hasApiKey = await apiKeyStore.hasKey();
      return AiProviderSettings(
        configuration: configuration,
        hasApiKey: hasApiKey,
      );
    } on AppFailure {
      rethrow;
    } catch (error) {
      throw StorageFailure('无法读取 AI 配置。', cause: error);
    }
  }

  @override
  Future<AiProviderConfiguration?> loadConfiguration() async {
    try {
      final row =
          await (database.select(database.aiProviderConfigs)
                ..where((config) => config.id.equals(configurationId)))
              .getSingleOrNull();
      return row == null
          ? null
          : AiProviderConfiguration(
              baseUrl: row.baseUrl,
              model: row.model,
              // 旧行 protocol 为 null＝从未选过协议 → Chat Completions。
              protocol: AiProviderProtocol.fromStorage(row.protocol),
              // 旧行 reasoning 为 null＝从未选过 → 「关闭推理」（产品默认档）。
              reasoning: AiReasoningMode.fromStorage(row.reasoning),
            );
    } catch (error) {
      throw StorageFailure('无法读取 AI 配置。', cause: error);
    }
  }

  @override
  Future<void> save(AiProviderSettingsInput input) async {
    final configuration = _validatedConfiguration(input);
    final apiKey = input.apiKey?.trim();
    final hasNewApiKey = apiKey != null && apiKey.isNotEmpty;
    if (!hasNewApiKey && !await apiKeyStore.hasKey()) {
      throw const ValidationFailure('首次保存时必须填写 API Key。');
    }

    try {
      await database
          .into(database.aiProviderConfigs)
          .insertOnConflictUpdate(
            AiProviderConfigsCompanion.insert(
              id: configurationId,
              baseUrl: configuration.baseUrl,
              model: configuration.model,
              protocol: Value(configuration.protocol.storageValue),
              reasoning: Value(configuration.reasoning.storageValue),
            ),
          );
    } catch (error) {
      throw StorageFailure('无法保存 AI 配置。', cause: error);
    }

    if (hasNewApiKey) await apiKeyStore.save(apiKey);
  }

  @override
  Future<void> clearApiKey() => apiKeyStore.clear();

  AiProviderConfiguration _validatedConfiguration(
    AiProviderSettingsInput input,
  ) {
    final baseUrl = input.baseUrl.trim();
    final model = input.model.trim();
    if (baseUrl.isEmpty || baseUrl.length > maxBaseUrlLength) {
      throw const ValidationFailure('请输入有效的 HTTPS Base URL。');
    }
    if (model.isEmpty || model.length > maxModelLength) {
      throw const ValidationFailure('模型名称不能为空且不能过长。');
    }

    final endpoint = OpenAiCompatibleEndpoint.tryParse(
      baseUrl,
      protocol: input.protocol,
    );
    if (endpoint == null) {
      throw const ValidationFailure('请输入有效的 HTTPS Base URL。');
    }
    return AiProviderConfiguration(
      baseUrl: endpoint.baseUrl,
      model: model,
      protocol: input.protocol,
      reasoning: input.reasoning,
    );
  }
}
