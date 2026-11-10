import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/backup/application/export_localfit_data.dart';
import 'package:localfit_ai/features/backup/application/lfb_backup_codec.dart';
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

  test('媒体边界如实上报：库里有路径、本机没文件 ⇒ missingMediaCount', () async {
    // 造一个只引用不存在图片路径的包（`.lfb` 只带路径，不带字节）。
    final source = AppDatabase(NativeDatabase.memory());
    addTearDown(source.close);
    final stamp = DateTime.utc(2026, 11, 10);
    await source
        .into(source.dishLibrary)
        .insert(
          DishLibraryCompanion.insert(
            id: 'dish-1',
            name: '旧菜',
            imagePath: const Value('/definitely/missing/dish.jpg'),
            mealSlot: 'lunch',
            kcal: 300,
            proteinG: 10,
            carbsG: 40,
            fatG: 8,
            source: 'manual',
            createdAt: stamp,
            updatedAt: stamp,
          ),
        );
    await source
        .into(source.profiles)
        .insert(
          ProfilesCompanion.insert(
            id: 'profile-1',
            activityLevel: 'moderate',
            createdAt: stamp,
            updatedAt: stamp,
            avatarPath: const Value('/definitely/missing/avatar.jpg'),
          ),
        );
    final payload = await ExportLocalFitData(source).exportJson();
    final envelope = await const LfbBackupCodec(iterations: 2000)
        .encode(payload: payload, password: '口令');

    final target = AppDatabase(NativeDatabase.memory());
    addTearDown(target.close);
    final summary = await RestoreEncryptedBackup(
      database: target,
      fileStore: _FakeBackupFileStore(
        Uint8List.fromList(utf8.encode(envelope)),
      ),
    ).run(password: '口令');

    expect(summary, isNotNull);
    expect(summary!.missingMediaCount, 2, reason: '菜品图 + 头像都只存在于备份路径里，本机没有字节');
  });
}
