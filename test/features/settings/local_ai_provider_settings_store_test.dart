import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/errors/app_failure.dart';
import 'package:localfit_ai/core/storage/secure_key_value_store.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/settings/data/ai_api_key_store.dart';
import 'package:localfit_ai/features/settings/data/local_ai_provider_settings_store.dart';
import 'package:localfit_ai/features/settings/domain/ai_provider_protocol.dart';
import 'package:localfit_ai/features/settings/domain/ai_provider_settings.dart';
import 'package:localfit_ai/features/settings/domain/ai_reasoning_mode.dart';

void main() {
  late AppDatabase database;
  late _MemorySecureKeyValueStore secureStore;
  late LocalAiProviderSettingsStore settings;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    secureStore = _MemorySecureKeyValueStore();
    settings = LocalAiProviderSettingsStore(
      database: database,
      apiKeyStore: AiApiKeyStore(store: secureStore),
    );
  });

  tearDown(() => database.close());

  test('persists only non-sensitive configuration in Drift', () async {
    await settings.save(
      const AiProviderSettingsInput(
        baseUrl: 'https://api.example.com/v1',
        model: 'vision-model',
        apiKey: 'secret-key',
      ),
    );

    final loaded = await settings.load();
    final rows = await database.select(database.aiProviderConfigs).get();

    expect(loaded.configuration?.baseUrl, 'https://api.example.com/v1/');
    expect(loaded.configuration?.model, 'vision-model');
    expect(loaded.hasApiKey, isTrue);
    expect(rows, hasLength(1));
    expect(rows.single.id, LocalAiProviderSettingsStore.configurationId);
    expect(rows.single.baseUrl, 'https://api.example.com/v1/');
    expect(rows.single.model, 'vision-model');
    expect(rows.single.toJson().toString(), isNot(contains('secret-key')));
    expect(secureStore.values[AiApiKeyStore.storageKey], 'secret-key');
  });

  test(
    'updates singleton configuration without requiring a replacement key',
    () async {
      await settings.save(
        const AiProviderSettingsInput(
          baseUrl: 'https://api.example.com/v1',
          model: 'first-model',
          apiKey: 'secret-key',
        ),
      );
      await settings.save(
        const AiProviderSettingsInput(
          baseUrl: 'https://api.example.com/v2',
          model: 'second-model',
        ),
      );

      final rows = await database.select(database.aiProviderConfigs).get();
      expect(rows, hasLength(1));
      expect(rows.single.baseUrl, 'https://api.example.com/v2/');
      expect(rows.single.model, 'second-model');
      expect(secureStore.values[AiApiKeyStore.storageKey], 'secret-key');
    },
  );

  test('persists the selected protocol and reads it back', () async {
    await settings.save(
      const AiProviderSettingsInput(
        baseUrl: 'https://api.example.com/v1',
        model: 'claude-model',
        protocol: AiProviderProtocol.anthropicMessages,
        apiKey: 'secret-key',
      ),
    );

    final loaded = await settings.load();
    final row =
        (await database.select(database.aiProviderConfigs).get()).single;

    // 协议落库为稳定的存储值（不是 enum 索引——顺序变了不能改语义）。
    expect(row.protocol, 'anthropic_messages');
    expect(
      loaded.configuration?.protocol,
      AiProviderProtocol.anthropicMessages,
    );
  });

  test('persists the reasoning mode and reads it back（docs/29 §P4）', () async {
    // 显式选「默认（由上游决定）」→ 原样落库、原样读回。
    await settings.save(
      const AiProviderSettingsInput(
        baseUrl: 'https://api.example.com/v1',
        model: 'm',
        apiKey: 'secret-key',
        reasoning: AiReasoningMode.providerDefault,
      ),
    );
    final row =
        (await database.select(database.aiProviderConfigs).get()).single;
    expect(row.reasoning, 'provider_default');
    var loaded = await settings.load();
    expect(loaded.configuration?.reasoning, AiReasoningMode.providerDefault);

    // 切回「关闭推理」→ 覆盖写。
    await settings.save(
      const AiProviderSettingsInput(
        baseUrl: 'https://api.example.com/v1',
        model: 'm',
        reasoning: AiReasoningMode.disabled,
      ),
    );
    loaded = await settings.load();
    expect(loaded.configuration?.reasoning, AiReasoningMode.disabled);
  });

  test('defaults to Chat Completions when nothing was ever chosen', () async {
    await settings.save(
      const AiProviderSettingsInput(
        baseUrl: 'https://api.example.com/v1',
        model: 'm',
        apiKey: 'secret-key',
      ),
    );

    final loaded = await settings.load();

    // 不传 protocol 就是默认＝旧行为。
    expect(loaded.configuration?.protocol, AiProviderProtocol.chatCompletions);
  });

  test(
    'an unknown stored protocol value falls back to Chat Completions',
    () async {
      await settings.save(
        const AiProviderSettingsInput(
          baseUrl: 'https://api.example.com/v1',
          model: 'm',
          protocol: AiProviderProtocol.responses,
          apiKey: 'secret-key',
        ),
      );
      // 模拟「库来自更新版本」：写入一个本版本读不懂的值。
      await (database.update(database.aiProviderConfigs)..where(
            (row) =>
                row.id.equals(LocalAiProviderSettingsStore.configurationId),
          ))
          .write(
            const AiProviderConfigsCompanion(
              protocol: Value('future-protocol'),
            ),
          );

      final loaded = await settings.load();

      // 读不懂 ≠ 崩；回落默认并保证请求仍能发出。
      expect(
        loaded.configuration?.protocol,
        AiProviderProtocol.chatCompletions,
      );
    },
  );

  test('switching protocol does not require re-entering the API key', () async {
    await settings.save(
      const AiProviderSettingsInput(
        baseUrl: 'https://api.example.com/v1',
        model: 'm',
        apiKey: 'secret-key',
      ),
    );
    await settings.save(
      const AiProviderSettingsInput(
        baseUrl: 'https://api.example.com/v1',
        model: 'm',
        protocol: AiProviderProtocol.responses,
      ),
    );

    final loaded = await settings.load();
    expect(loaded.configuration?.protocol, AiProviderProtocol.responses);
    expect(loaded.hasApiKey, isTrue);
    expect(secureStore.values[AiApiKeyStore.storageKey], 'secret-key');
  });

  test('协议存储值是稳定字符串而非 enum 索引', () async {
    // 存储值一旦上线就是数据契约：enum 顺序调整不许改语义。
    expect(AiProviderProtocol.chatCompletions.storageValue, 'chat_completions');
    expect(AiProviderProtocol.responses.storageValue, 'responses');
    expect(
      AiProviderProtocol.anthropicMessages.storageValue,
      'anthropic_messages',
    );
    // 往返：写进存储再读出来是同一个协议。
    for (final protocol in AiProviderProtocol.values) {
      expect(AiProviderProtocol.fromStorage(protocol.storageValue), protocol);
    }
    // 请求路径也在这里钉一次（协议身份的对外表现）。
    expect(AiProviderProtocol.chatCompletions.requestPath, 'chat/completions');
    expect(AiProviderProtocol.responses.requestPath, 'responses');
    expect(AiProviderProtocol.anthropicMessages.requestPath, 'messages');
  });

  test('rejects invalid local configuration before persistence', () async {
    for (final input in const [
      AiProviderSettingsInput(
        baseUrl: 'http://api.example.com/v1',
        model: 'model',
        apiKey: 'secret-key',
      ),
      AiProviderSettingsInput(
        baseUrl: 'https://api.example.com/v1?key=secret',
        model: 'model',
        apiKey: 'secret-key',
      ),
      AiProviderSettingsInput(
        baseUrl: 'https://api.example.com/v1',
        model: '',
        apiKey: 'secret-key',
      ),
    ]) {
      await expectLater(
        settings.save(input),
        throwsA(isA<ValidationFailure>()),
      );
    }
    expect(await database.select(database.aiProviderConfigs).get(), isEmpty);
    expect(secureStore.values, isEmpty);
  });
}

final class _MemorySecureKeyValueStore implements SecureKeyValueStore {
  final values = <String, String>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}
