import 'dart:convert';
import 'dart:typed_data';

import 'package:localfit_ai/features/backup/application/export_localfit_data.dart';
import 'package:localfit_ai/features/backup/application/lfb_backup_codec.dart';
import 'package:localfit_ai/features/backup/data/backup_file_store.dart';
import 'package:localfit_ai/data/database/app_database.dart';

/// Exports the whole local database as a password-encrypted `.lfb` file.
/// The password never leaves this device and is not stored anywhere.
final class CreateEncryptedBackup {
  const CreateEncryptedBackup({
    required this.database,
    required this.fileStore,
    this.codec = const LfbBackupCodec(),
  });

  final AppDatabase database;
  final BackupFileStore fileStore;
  final LfbBackupCodec codec;

  Future<String?> run({required String password}) async {
    final payload = await ExportLocalFitData(database).exportJson();
    final envelope = await codec.encode(payload: payload, password: password);
    final now = DateTime.now();
    final fileName =
        'localfit-'
        '${now.year.toString().padLeft(4, '0')}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}-'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}.${LfbBackupFileNaming.extension}';
    return fileStore.saveExport(
      defaultFileName: fileName,
      bytes: Uint8List.fromList(utf8.encode(envelope)),
    );
  }
}

abstract final class LfbBackupFileNaming {
  static const extension = 'lfb';
}
