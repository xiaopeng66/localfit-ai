import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/features/backup/application/lfb_backup_codec.dart';
import 'package:localfit_ai/features/backup/data/backup_file_store.dart';
import 'package:localfit_ai/features/backup/domain/backup_limits.dart';

/// docs/25 §5 M2：恢复侧的两道大小判据（选文件之前、解析之前）。
///
/// 三处上限必须**同源**（[BackupLimits]）——只有 `encode` 有上限时，
/// 任意大的 `.lfb` 会被整份读进内存再解析，第一道校验之前就 OOM。
void main() {
  group('上限同源（BackupLimits 是单一事实源）', () {
    test('封套上限覆盖密文的 base64 膨胀', () {
      // 明文 → 密文（同尺寸）→ base64（4/3）。封套上限低于这个换算值时，
      // 「恰好达到明文上限的备份」会导得出、恢复不回来。
      expect(
        BackupLimits.maxEnvelopeBytes,
        greaterThanOrEqualTo(BackupLimits.maxPayloadBytes * 4 ~/ 3),
      );
    });

    test('codec 与选文件侧的默认上限就是 BackupLimits', () {
      const codec = LfbBackupCodec();
      const store = FilePickerBackupFileStore();
      expect(codec.maxEnvelopeChars, BackupLimits.maxEnvelopeBytes);
      expect(store.maxFileBytes, BackupLimits.maxEnvelopeBytes);
      expect(LfbBackupCodec.maxPayloadBytes, BackupLimits.maxPayloadBytes);
    });
  });

  group('LfbBackupCodec.decode 的封套长度判据', () {
    test('超长封套在解析之前就被拒绝', () async {
      // 阈值注入成小值：真上限 384 MiB 造不出来。
      const smallLimit = 256;
      final codec = const LfbBackupCodec(
        iterations: 2000,
        derivesInIsolate: false,
        maxEnvelopeChars: smallLimit,
      );
      final oversized = 'x' * (smallLimit + 1);

      await expectLater(
        codec.decode(envelopeJson: oversized, password: 'pw'),
        throwsA(
          isA<LfbBackupFailure>()
              .having(
                (failure) => failure.kind,
                'kind',
                LfbBackupFailureKind.invalidEnvelope,
              )
              .having(
                (failure) => failure.message,
                'message',
                contains('超出大小限制'),
              ),
        ),
      );
    });

    test('恰好等于上限的封套仍然按内容判定（不是一律拒绝）', () async {
      const smallLimit = 256;
      final codec = const LfbBackupCodec(
        iterations: 2000,
        derivesInIsolate: false,
        maxEnvelopeChars: smallLimit,
      );
      // 256 个 ×（非合法 JSON）：长度判据放行，随后按格式报错。若长度判据
      // 写成 `<` 或把阈值当上限排除，这条会以别的理由通过，所以同时钉住
      // 报错原因不是「超出大小限制」。
      final atLimit = 'y' * smallLimit;
      await expectLater(
        codec.decode(envelopeJson: atLimit, password: 'pw'),
        throwsA(
          isA<LfbBackupFailure>().having(
            (failure) => failure.message,
            'message',
            isNot(contains('超出大小限制')),
          ),
        ),
      );
    });
  });

  group('FilePickerBackupFileStore 的选文件判据', () {
    test('超限的文件被拒绝，且给出体积与上限', () {
      final violation = FilePickerBackupFileStore.sizeViolation(
        bytes: 2000,
        maxFileBytes: 1024,
      );
      expect(violation, isNotNull);
      expect(violation, contains('备份文件过大'));
      expect(violation, contains('上限 0 MiB'));
    });

    test('等于上限的文件放行（判据是「大于」不是「大于等于」）', () {
      expect(
        FilePickerBackupFileStore.sizeViolation(
          bytes: 1024,
          maxFileBytes: 1024,
        ),
        isNull,
      );
      expect(
        FilePickerBackupFileStore.sizeViolation(
          bytes: 1023,
          maxFileBytes: 1024,
        ),
        isNull,
      );
    });

    test('生产默认上限就是封套上限（不是随手一个巨值）', () {
      expect(
        FilePickerBackupFileStore.sizeViolation(
          bytes: BackupLimits.maxEnvelopeBytes + 1,
          maxFileBytes: BackupLimits.maxEnvelopeBytes,
        ),
        isNotNull,
      );
    });
  });
}
