import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/backup/application/restore_encrypted_backup.dart';
import 'package:localfit_ai/features/backup/data/backup_file_store.dart';

final class _FakeBackupFileStore implements BackupFileStore {
  const _FakeBackupFileStore(this.bytes);

  final Uint8List? bytes;

  @override
  Future<Uint8List?> pickRestoreFile() async => bytes;

  @override
  Future<String?> saveExport({
    required String defaultFileName,
    required Uint8List bytes,
  }) async => null;
}

void main() {
  test('reports non-UTF8 restore files with a localized message', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final restore = RestoreEncryptedBackup(
      database: database,
      fileStore: _FakeBackupFileStore(
        Uint8List.fromList([0xFF, 0xFE, 0x62, 0x61]),
      ),
    );

    // 非 UTF-8 文件（如 UTF-16 编码的假备份）过去会把 utf8.decode 的英文
    // 内部错误直接抛到 UI。
    await expectLater(
      restore.run(password: '口令'),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('.lfb'),
        ),
      ),
    );
  });
}
