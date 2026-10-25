import 'dart:convert';

import 'package:localfit_ai/features/backup/application/lfb_backup_codec.dart';
import 'package:localfit_ai/features/backup/application/restore_localfit_data.dart';
import 'package:localfit_ai/features/backup/data/backup_file_store.dart';
import 'package:localfit_ai/data/database/app_database.dart';

final class RestoredBackupSummary {
  const RestoredBackupSummary({
    required this.exportedAt,
    this.indexRebuildPending = false,
  });

  final String exportedAt;

  /// 数据已恢复，但派生索引重建任务没能入队（RV-P2-12）。
  final bool indexRebuildPending;
}

/// Restores a password-protected `.lfb` backup chosen by the user. The whole
/// replace runs in one transaction: a wrong password or a corrupted file
/// leaves the current data untouched.
final class RestoreEncryptedBackup {
  const RestoreEncryptedBackup({
    required this.database,
    required this.fileStore,
    this.codec = const LfbBackupCodec(),
    this.onRestored,
  });

  final AppDatabase database;
  final BackupFileStore fileStore;
  final LfbBackupCodec codec;

  /// 恢复成功后的回调（G14）：接线方在这里入队「重建派生索引」任务。
  /// null = 只做同步清空（`RestoreLocalFitData.restore` 已保证索引失效）。
  final Future<void> Function()? onRestored;

  Future<RestoredBackupSummary?> run({required String password}) async {
    final bytes = await fileStore.pickRestoreFile();
    if (bytes == null) return null;
    final String envelopeJson;
    try {
      envelopeJson = utf8.decode(bytes);
    } on FormatException {
      // 直接让 utf8.decode 的英文异常冒到 UI 会变成内部错误文案。
      throw const FormatException('文件不是有效的文本备份，请选择应用导出的 .lfb 文件。');
    }
    final payload = await codec.decode(
      envelopeJson: envelopeJson,
      password: password,
    );
    await RestoreLocalFitData(database).restore(payload);
    // G14：派生索引已随恢复清空；重建任务由接线方入队（可断点续跑）。
    // 2026-10-21 RV-P2-12：数据已经替换成功——重建/入队失败不能再报
    // 「恢复失败，当前数据未受影响」（那是假话），单独标记 degraded。
    var indexRebuildPending = false;
    try {
      await onRestored?.call();
    } on Object {
      indexRebuildPending = true;
    }
    final exportedAt = _readExportedAt(utf8.decode(payload));
    return RestoredBackupSummary(
      exportedAt: exportedAt ?? '未知时间',
      indexRebuildPending: indexRebuildPending,
    );
  }

  String? _readExportedAt(String payload) {
    try {
      final document = jsonDecode(payload);
      if (document is! Map<String, Object?>) return null;
      final value = document['exported_at'];
      return value is String ? value : null;
    } on FormatException {
      return null;
    }
  }
}
