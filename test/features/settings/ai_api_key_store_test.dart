import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/errors/app_failure.dart';
import 'package:localfit_ai/core/storage/secure_key_value_store.dart';
import 'package:localfit_ai/data/database/database_key_manager.dart';
import 'package:localfit_ai/features/settings/data/ai_api_key_store.dart';

void main() {
  test('saves, replaces, and clears only the AI API Key', () async {
    final store = _MemorySecureKeyValueStore()
      ..values[DatabaseKeyManager.storageKey] = 'database-key';
    final apiKeys = AiApiKeyStore(store: store);

    expect(await apiKeys.read(), isNull);
    await apiKeys.save('first-key');
    await apiKeys.save('replacement-key');
    expect(await apiKeys.read(), 'replacement-key');

    await apiKeys.clear();

    expect(await apiKeys.read(), isNull);
    expect(store.values[DatabaseKeyManager.storageKey], 'database-key');
  });

  test('leaves the generated database encryption key unchanged', () async {
    final store = _MemorySecureKeyValueStore();
    final databaseKeys = DatabaseKeyManager(store: store, random: Random(42));
    final apiKeys = AiApiKeyStore(store: store);
    final databaseKey = await databaseKeys.getOrCreate();

    await apiKeys.save('sample-key');
    await apiKeys.clear();

    expect(await databaseKeys.getOrCreate(), databaseKey);
  });

  test('does not include an API Key in secure storage failures', () async {
    const secret = 'this-key-must-never-be-displayed';
    final apiKeys = AiApiKeyStore(store: _FailingSecureKeyValueStore());

    await expectLater(
      apiKeys.save(secret),
      throwsA(
        predicate<Object>(
          (error) => error is StorageFailure && !error.message.contains(secret),
          'a safe storage failure',
        ),
      ),
    );
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

final class _FailingSecureKeyValueStore implements SecureKeyValueStore {
  @override
  Future<void> delete(String key) => throw StateError('storage failed');

  @override
  Future<String?> read(String key) => throw StateError('storage failed');

  @override
  Future<void> write(String key, String value) =>
      throw StateError('storage failed');
}
