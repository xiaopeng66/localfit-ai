import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:localfit_ai/features/backup/domain/backup_limits.dart';

/// Failure kinds for the encrypted `.lfb` backup envelope.
enum LfbBackupFailureKind { invalidEnvelope, wrongPassword, corrupted }

final class LfbBackupFailure implements Exception {
  const LfbBackupFailure(this.kind, this.message);

  final LfbBackupFailureKind kind;
  final String message;

  @override
  String toString() => message;
}

/// Pure-Dart codec for the password-encrypted `.lfb` backup envelope (v1):
///
/// ```json
/// {
///   "format": "localfit-backup",
///   "version": 1,
///   "kdf": {"algorithm": "pbkdf2-hmac-sha256", "iterations": N, "salt": "<b64>"},
///   "cipher": "aes-256-gcm",
///   "nonce": "<b64>",
///   "ciphertext": "<b64>",
///   "mac": "<b64>",
///   "checksum": "<sha256 hex of ciphertext>"
/// }
/// ```
///
/// The envelope contains no secrets: the key is derived from the user's
/// password with PBKDF2-HMAC-SHA256 and never enters the file. Integrity is
/// enforced twice: a SHA-256 checksum over the ciphertext fails fast on
/// corruption, and AES-GCM authentication rejects tampering or wrong keys.
final class LfbBackupCodec {
  const LfbBackupCodec({
    this.iterations = 600000,
    this.random = defaultRandomBytes,
    this.derivesInIsolate = true,
    this.maxEnvelopeChars = BackupLimits.maxEnvelopeBytes,
  });

  static const formatMarker = 'localfit-backup';
  static const version = 1;
  static const minIterations = 1000;
  static const maxIterations = 5000000;

  /// 明文上限，与导出/恢复/选文件三处同源（见 [BackupLimits]）。
  static const maxPayloadBytes = BackupLimits.maxPayloadBytes;

  /// Production work factor (OWASP PBKDF2-HMAC-SHA256 guidance).
  final int iterations;
  final Uint8List Function(int length) random;

  /// 密钥派生放到后台 isolate（UI 不卡顿）。widget 测试跑在 FakeAsync
  /// 区里，真实 isolate 的 Future 永远等不到，测试需关掉。
  final bool derivesInIsolate;

  /// 封套 JSON 的字符数上限。以前只有 [encode] 校验明文大小，[decode]
  /// 什么都不校验：任意大的封套会先走完 base64 解码与解析。base64 是
  /// ASCII，字符数≈字节数。可注入是为了测试（真上限 384 MiB 造不出来）。
  final int maxEnvelopeChars;

  static Uint8List defaultRandomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }

  Future<String> encode({
    required Uint8List payload,
    required String password,
  }) async {
    _validatePassword(password);
    if (payload.isEmpty || payload.length > maxPayloadBytes) {
      throw const LfbBackupFailure(
        LfbBackupFailureKind.invalidEnvelope,
        '备份内容为空或超出大小限制。',
      );
    }
    final salt = random(16);
    final nonce = random(12);
    final key = await _deriveKey(password: password, salt: salt);
    final aesGcm = AesGcm.with256bits();
    final secretBox = await aesGcm.encrypt(
      payload,
      secretKey: SecretKey(key),
      nonce: nonce,
    );
    final envelope = {
      'format': formatMarker,
      'version': version,
      'kdf': {
        'algorithm': 'pbkdf2-hmac-sha256',
        'iterations': iterations,
        'salt': base64Encode(salt),
      },
      'cipher': 'aes-256-gcm',
      'nonce': base64Encode(nonce),
      'ciphertext': base64Encode(secretBox.cipherText),
      'mac': base64Encode(secretBox.mac.bytes),
      'checksum': await _checksum(secretBox.cipherText),
    };
    return jsonEncode(envelope);
  }

  Future<Uint8List> decode({
    required String envelopeJson,
    required String password,
  }) async {
    _validatePassword(password);
    // 先按长度拒绝，再解析：封套的 base64 解码与 jsonDecode 都会按输入
    // 大小分配内存，检查必须发生在它们之前。
    if (envelopeJson.length > maxEnvelopeChars) {
      throw const LfbBackupFailure(
        LfbBackupFailureKind.invalidEnvelope,
        '备份包超出大小限制，请确认选择的是应用导出的 .lfb 文件。',
      );
    }
    final document = _parseEnvelope(envelopeJson);
    final ciphertext = _base64Field(document, 'ciphertext');
    final expectedChecksum = document['checksum'];
    if (expectedChecksum is! String ||
        expectedChecksum != await _checksum(ciphertext)) {
      throw const LfbBackupFailure(
        LfbBackupFailureKind.corrupted,
        '备份包已损坏，校验和不一致。',
      );
    }
    // 恢复必须使用封套里记录的迭代次数派生密钥——编码端可配置不同
    // 工作因子，忽略该值会让正确密码也解不出（被误报为密码错误）。
    final kdf = document['kdf'] as Map<String, Object?>;
    final key = await _deriveKey(
      password: password,
      salt: _base64Field(kdf, 'salt'),
      iterations: kdf['iterations'] as int,
    );
    final aesGcm = AesGcm.with256bits();
    final Uint8List plain;
    try {
      final secretBox = SecretBox(
        ciphertext,
        nonce: _base64Field(document, 'nonce'),
        mac: Mac(_base64Field(document, 'mac')),
      );
      plain = Uint8List.fromList(
        await aesGcm.decrypt(secretBox, secretKey: SecretKey(key)),
      );
    } on SecretBoxAuthenticationError {
      throw const LfbBackupFailure(
        LfbBackupFailureKind.wrongPassword,
        '密码错误或备份包已被篡改。',
      );
    }
    return plain;
  }

  /// Exposed for tests to craft valid-looking checksums.
  Future<String> checksumForTest(List<int> bytes) => _checksum(bytes);

  Map<String, Object?> _parseEnvelope(String envelopeJson) {
    Map<String, Object?> document;
    try {
      final decoded = jsonDecode(envelopeJson);
      if (decoded is! Map<String, Object?>) throw const FormatException();
      document = decoded;
    } on FormatException {
      throw const LfbBackupFailure(
        LfbBackupFailureKind.invalidEnvelope,
        '备份包格式无法识别。',
      );
    }
    if (document['format'] != formatMarker) {
      throw const LfbBackupFailure(
        LfbBackupFailureKind.invalidEnvelope,
        '这不是 LocalFit AI 备份文件。',
      );
    }
    if (document['version'] != version) {
      throw const LfbBackupFailure(
        LfbBackupFailureKind.invalidEnvelope,
        '备份包版本不受支持，请更新应用后再试。',
      );
    }
    final cipher = document['cipher'];
    if (cipher is! String || cipher != 'aes-256-gcm') {
      throw const LfbBackupFailure(
        LfbBackupFailureKind.invalidEnvelope,
        '备份包加密方式不受支持。',
      );
    }
    final kdf = document['kdf'];
    if (kdf is! Map<String, Object?>) {
      throw const LfbBackupFailure(
        LfbBackupFailureKind.invalidEnvelope,
        '备份包格式无法识别。',
      );
    }
    if (kdf['algorithm'] != 'pbkdf2-hmac-sha256') {
      throw const LfbBackupFailure(
        LfbBackupFailureKind.invalidEnvelope,
        '备份包密钥派生方式不受支持。',
      );
    }
    final iterations = kdf['iterations'];
    if (iterations is! int ||
        iterations < minIterations ||
        iterations > maxIterations) {
      throw const LfbBackupFailure(
        LfbBackupFailureKind.invalidEnvelope,
        '备份包密钥派生参数无效。',
      );
    }
    // Structural presence of base64 fields; content validity is enforced by
    // the checksum and AEAD layers.
    _base64Field(document, 'nonce');
    _base64Field(document, 'mac');
    _base64Field(kdf, 'salt');
    if (document['checksum'] is! String) {
      throw const LfbBackupFailure(
        LfbBackupFailureKind.invalidEnvelope,
        '备份包格式无法识别。',
      );
    }
    return document;
  }

  Uint8List _base64Field(Map<String, Object?> document, String field) {
    final value = document[field];
    if (value is! String) {
      throw const LfbBackupFailure(
        LfbBackupFailureKind.invalidEnvelope,
        '备份包格式无法识别。',
      );
    }
    try {
      final decoded = base64Decode(value);
      if (decoded.isEmpty) throw const FormatException();
      return Uint8List.fromList(decoded);
    } on FormatException {
      throw const LfbBackupFailure(
        LfbBackupFailureKind.invalidEnvelope,
        '备份包格式无法识别。',
      );
    }
  }

  Future<Uint8List> _deriveKey({
    required String password,
    required Uint8List salt,
    int? iterations,
  }) async {
    final workFactor = iterations ?? this.iterations;
    Future<Uint8List> derive() async {
      final pbkdf2 = Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: workFactor,
        bits: 256,
      );
      final key = await pbkdf2.deriveKey(
        secretKey: SecretKey(utf8.encode(password)),
        nonce: salt,
      );
      return Uint8List.fromList(await key.extractBytes());
    }

    // 60 万次纯 Dart PBKDF2 即便每 2000 轮让出一次事件循环，也会显著拖慢
    // 弹层动画；整个派生挪到后台 isolate，导出/恢复期间 UI 保持流畅。
    if (!derivesInIsolate) return derive();
    return Isolate.run(derive);
  }

  Future<String> _checksum(List<int> bytes) async {
    final hash = await Sha256().hash(bytes);
    return hash.bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  void _validatePassword(String password) {
    if (password.trim().isEmpty) {
      throw const LfbBackupFailure(
        LfbBackupFailureKind.invalidEnvelope,
        '备份密码不能为空。',
      );
    }
  }
}
