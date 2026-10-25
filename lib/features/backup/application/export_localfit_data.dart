import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/backup/application/backup_table_registry.dart';

/// Dumps every logical table of the local database into a portable JSON
/// document. The export contains no secrets: the SQLCipher database key and
/// the AI API key live in secure storage and are never part of the payload.
final class ExportLocalFitData {
  const ExportLocalFitData(this.database);

  static const exportVersion = 1;

  final AppDatabase database;

  Future<Uint8List> exportJson() async {
    // 全部表必须在同一个事务里读取：分表读取期间发生写入会导出
    // 「子行存在而父行缺失」的混合快照，恢复时因外键失败整体失败。
    final document = await database.transaction(() async {
      final tables = <String, Object?>{};
      for (final spec in LocalFitBackupTables(database).all) {
        tables[spec.key] = await spec.read(database);
      }
      return {
        'export_version': exportVersion,
        'exported_at': DateTime.now().toUtc().toIso8601String(),
        'tables': tables,
      };
    });
    return Uint8List.fromList(utf8.encode(jsonEncode(document)));
  }
}
