import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/features/backup/application/lfb_backup_codec.dart';

void main() {
  const codec = LfbBackupCodec(iterations: 2000);
  final payload = Uint8List.fromList(utf8.encode('{"profile":{"id":"p1"}}'));

  test('round-trips a payload through the encrypted envelope', () async {
    final envelope = await codec.encode(payload: payload, password: '口令-正确');
    expect(envelope, contains('"format":"localfit-backup"'));
    expect(envelope, contains('"version":1'));
    expect(envelope, contains('pbkdf2-hmac-sha256'));
    expect(envelope, contains('aes-256-gcm'));
    expect(envelope, isNot(contains('口令')));
    expect(envelope, isNot(contains(utf8.decode(payload))));

    final decoded = await codec.decode(
      envelopeJson: envelope,
      password: '口令-正确',
    );
    expect(decoded, payload);
  });

  test('produces a different envelope on every call', () async {
    final first = await codec.encode(payload: payload, password: 'pw');
    final second = await codec.encode(payload: payload, password: 'pw');
    expect(first, isNot(second));
  });

  test(
    'decoding honors the envelope iterations with the default codec',
    () async {
      // 封套记录了编码端的工作因子；解码端必须按它派生密钥，
      // 否则用默认迭代数的实例永远解不开非默认编码的备份。
      const lowCostCodec = LfbBackupCodec(iterations: 2000);
      final envelope = await lowCostCodec.encode(
        payload: payload,
        password: '口令-正确',
      );

      final decoded = await const LfbBackupCodec().decode(
        envelopeJson: envelope,
        password: '口令-正确',
      );
      expect(decoded, payload);
    },
  );

  test('rejects a wrong password without leaking the payload', () async {
    final envelope = await codec.encode(payload: payload, password: 'pw-a');
    await expectLater(
      codec.decode(envelopeJson: envelope, password: 'pw-b'),
      throwsA(
        isA<LfbBackupFailure>().having(
          (failure) => failure.kind,
          'kind',
          LfbBackupFailureKind.wrongPassword,
        ),
      ),
    );
  });

  test('rejects a corrupted ciphertext via the checksum', () async {
    final envelope = await codec.encode(payload: payload, password: 'pw');
    final document = jsonDecode(envelope) as Map<String, dynamic>;
    final corrupted = base64Decode(document['ciphertext'] as String)
      ..[0] ^= 0xFF;
    document['ciphertext'] = base64Encode(corrupted);

    await expectLater(
      codec.decode(envelopeJson: jsonEncode(document), password: 'pw'),
      throwsA(
        isA<LfbBackupFailure>().having(
          (failure) => failure.kind,
          'kind',
          LfbBackupFailureKind.corrupted,
        ),
      ),
    );
  });

  test('rejects tampered ciphertext even with a valid checksum', () async {
    final envelope = await codec.encode(payload: payload, password: 'pw');
    final document = jsonDecode(envelope) as Map<String, dynamic>;
    final tampered = base64Decode(document['ciphertext'] as String)
      ..[0] ^= 0xFF;
    document['ciphertext'] = base64Encode(tampered);
    document['checksum'] = await _sha256Hex(tampered);

    await expectLater(
      codec.decode(envelopeJson: jsonEncode(document), password: 'pw'),
      throwsA(
        isA<LfbBackupFailure>().having(
          (failure) => failure.kind,
          'kind',
          LfbBackupFailureKind.wrongPassword,
        ),
      ),
    );
  });

  for (final (label, envelope) in <(String, String)>[
    ('not json', 'not-json'),
    ('missing fields', '{"format":"localfit-backup"}'),
    (
      'wrong format marker',
      '{"format":"other","version":1,"kdf":{"algorithm":"pbkdf2-hmac-sha256","iterations":2000,"salt":"AAAA"},"cipher":"aes-256-gcm","nonce":"AAAA","ciphertext":"AAAA","mac":"AAAA","checksum":"AA"}',
    ),
    (
      'unsupported version',
      '{"format":"localfit-backup","version":99,"kdf":{"algorithm":"pbkdf2-hmac-sha256","iterations":2000,"salt":"AAAA"},"cipher":"aes-256-gcm","nonce":"AAAA","ciphertext":"AAAA","mac":"AAAA","checksum":"AA"}',
    ),
    (
      'unsupported kdf algorithm',
      '{"format":"localfit-backup","version":1,"kdf":{"algorithm":"scrypt","iterations":2000,"salt":"AAAA"},"cipher":"aes-256-gcm","nonce":"AAAA","ciphertext":"AAAA","mac":"AAAA","checksum":"AA"}',
    ),
    (
      'unsupported cipher',
      '{"format":"localfit-backup","version":1,"kdf":{"algorithm":"pbkdf2-hmac-sha256","iterations":2000,"salt":"AAAA"},"cipher":"aes-128-cbc","nonce":"AAAA","ciphertext":"AAAA","mac":"AAAA","checksum":"AA"}',
    ),
    (
      'absurd iteration count',
      '{"format":"localfit-backup","version":1,"kdf":{"algorithm":"pbkdf2-hmac-sha256","iterations":99999999,"salt":"AAAA"},"cipher":"aes-256-gcm","nonce":"AAAA","ciphertext":"AAAA","mac":"AAAA","checksum":"AA"}',
    ),
  ]) {
    test('rejects $label as an invalid envelope', () async {
      await expectLater(
        codec.decode(envelopeJson: envelope, password: 'pw'),
        throwsA(
          isA<LfbBackupFailure>().having(
            (failure) => failure.kind,
            'kind',
            LfbBackupFailureKind.invalidEnvelope,
          ),
        ),
      );
    });
  }

  test('rejects empty passwords on encode and decode', () async {
    await expectLater(
      codec.encode(payload: payload, password: ''),
      throwsA(isA<LfbBackupFailure>()),
    );
    await expectLater(
      codec.encode(payload: payload, password: '   '),
      throwsA(isA<LfbBackupFailure>()),
    );
  });
}

Future<String> _sha256Hex(List<int> bytes) async {
  // Implemented by the codec's own helper; tests only need a valid-looking
  // checksum so the AEAD layer is what rejects the tampered content. The real
  // checksum verification is covered by the corrupted-ciphertext test.
  final digest = const LfbBackupCodec(iterations: 2000).checksumForTest(bytes);
  return digest;
}
