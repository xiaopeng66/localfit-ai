import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/storage/secure_key_value_store.dart';
import 'package:localfit_ai/data/database/database_key_manager.dart';

void main() {
  test('creates and reuses a 256-bit database key', () async {
    final store = MemorySecureKeyValueStore();
    final manager = DatabaseKeyManager(store: store, random: Random(42));

    final first = await manager.getOrCreate();
    final second = await manager.getOrCreate();

    expect(first, hasLength(DatabaseKeyManager.keyLengthBytes));
    expect(second, first);
    expect(store.values, hasLength(1));
  });

  test('rejects a malformed key instead of silently replacing it', () async {
    final store = MemorySecureKeyValueStore()
      ..values[DatabaseKeyManager.storageKey] = 'not-base64!';
    final manager = DatabaseKeyManager(store: store);

    await expectLater(manager.getOrCreate(), throwsFormatException);
  });
}

final class MemorySecureKeyValueStore implements SecureKeyValueStore {
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
