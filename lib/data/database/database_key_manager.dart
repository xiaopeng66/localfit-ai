import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:localfit_ai/core/storage/secure_key_value_store.dart';

final class DatabaseKeyManager {
  DatabaseKeyManager({required this.store, Random? random})
    : random = random ?? Random.secure();

  static const storageKey = 'localfit.database.key.v1';
  static const keyLengthBytes = 32;

  final SecureKeyValueStore store;
  final Random random;

  Future<Uint8List> getOrCreate() async {
    final existing = await store.read(storageKey);
    if (existing != null) {
      return _decode(existing);
    }

    final key = Uint8List.fromList(
      List.generate(keyLengthBytes, (_) => random.nextInt(256)),
    );
    await store.write(storageKey, base64UrlEncode(key));
    return key;
  }

  Future<void> delete() => store.delete(storageKey);

  Uint8List _decode(String encoded) {
    try {
      final key = base64Url.decode(encoded);
      if (key.length != keyLengthBytes) {
        throw const FormatException('Unexpected database key length.');
      }
      return Uint8List.fromList(key);
    } on FormatException catch (error) {
      throw FormatException('Stored database key is invalid.', error);
    }
  }
}
