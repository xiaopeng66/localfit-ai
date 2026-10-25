import 'dart:convert';
import 'dart:typed_data';

import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/backup/application/backup_table_registry.dart';
import 'package:localfit_ai/features/backup/application/clear_all_local_data.dart';
import 'package:localfit_ai/features/retrieval/application/index_coordinator.dart';

/// Replaces the entire local database content with a previously exported
/// JSON backup. The whole restore runs inside one transaction: any validation
/// or write failure leaves the existing data untouched.
final class RestoreLocalFitData {
  RestoreLocalFitData(this.database, {IndexCoordinator? indexCoordinator})
    : clearAll = ClearAllLocalData(database),
      _index = indexCoordinator ?? IndexCoordinator(database: database);

  static const supportedVersion = 1;

  final AppDatabase database;
  final IndexCoordinator _index;

  Future<void> restore(Uint8List backupJson) async {
    final document = _parse(backupJson);
    final tables = document['tables'];
    if (tables is! Map<String, dynamic>) {
      throw const FormatException('备份缺少数据表内容。');
    }

    await database.transaction(() async {
      await clearAll.clearDatabaseRowsOnly();
      await _insertAll(tables);
    });
    // G14（docs/41 D7）：**向量不进备份**，恢复后派生索引必须重建——
    // 旧向量属于旧库的文本（`textHash` 对不上），留着就是错的。
    // 这里同步清空（恢复是用户等着的操作，重建不能让它悬着）；真正的
    // 重建任务由调用方入队（`indexRebuild`，见 FoodDataMaintenance）。
    await _index.rebuildAll();
  }

  final ClearAllLocalData clearAll;

  Map<String, Object?> _parse(Uint8List backupJson) {
    Map<String, Object?> document;
    try {
      final decoded = jsonDecode(utf8.decode(backupJson));
      if (decoded is! Map<String, Object?>) throw const FormatException();
      document = decoded;
    } on FormatException {
      throw const FormatException('备份文件无法解析。');
    }
    if (document['export_version'] != supportedVersion) {
      throw const FormatException('备份版本不受支持，请更新应用后再试。');
    }
    return document;
  }

  /// 按注册清单的父表在前顺序插入。缺失的表分两种：1.x 就有的表缺失 =
  /// 备份损坏（抛错并回滚）；2.0 新增的表缺失 = 旧备份，视为空表。
  ///
  /// 形状校验之后还有**字段值**校验（spec.validateRow）：读取侧会严格
  /// 解析的文本列（ISO 本地日）出现脏值时整单拒绝并回滚，绝不把「恢复
  /// 成功、进页面红屏」留给用户（docs/11 §3-F）。
  Future<void> _insertAll(Map<String, dynamic> tables) async {
    for (final spec in LocalFitBackupTables(database).all) {
      final rows = tables[spec.key];
      if (rows == null) {
        if (spec.optional) continue;
        throw FormatException('备份缺少数据表：${spec.key}。');
      }
      if (rows is! List) {
        throw FormatException('备份中的数据表 ${spec.key} 无法解析。');
      }
      for (var index = 0; index < rows.length; index++) {
        final row = rows[index];
        if (row is! Map<String, dynamic>) {
          throw FormatException('备份中的数据表 ${spec.key} 含有无效行。');
        }
        final validateRow = spec.validateRow;
        if (validateRow != null) {
          final violation = validateRow(row);
          if (violation != null) {
            throw FormatException(
              '备份中的数据表 ${spec.key} 第 ${index + 1} 行存在无效字段'
              '（$violation），备份可能已损坏。',
            );
          }
        }
        await spec.write(database, row);
      }
    }
  }
}
