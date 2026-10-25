import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show OrderingTerm;
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/backup/application/csv_exporters.dart';
import 'package:localfit_ai/features/backup/data/backup_file_store.dart';

/// Exports diet and training CSV files through the user-facing file store.
final class ExportCsvFiles {
  const ExportCsvFiles({
    required this.database,
    required this.fileStore,
    this.exporters = const CsvExporters(),
  });

  final AppDatabase database;
  final BackupFileStore fileStore;
  final CsvExporters exporters;

  Future<String?> mealsCsv() async {
    final tables = await _collect();
    return _save('localfit-meals-${_stamp()}.csv', exporters.mealsCsv(tables));
  }

  Future<String?> trainingCsv() async {
    final tables = await _collect();
    return _save(
      'localfit-training-${_stamp()}.csv',
      exporters.trainingCsv(tables),
    );
  }

  /// 食物库全量导出（docs/31 S5 需求 54）。**不进 [CsvExportTables]**：
  /// 那 >4 万行的种子表只有导食物库这一条路用得上，塞进 `_collect` 会让
  /// 每次导餐次/训练 CSV 都白扫一遍全库。排序按名称，导出的文件人能直接读。
  Future<String?> foodsCsv() async {
    final foods =
        await (database.select(database.foods)..orderBy([
              (row) => OrderingTerm.asc(row.name),
              (row) => OrderingTerm.asc(row.id),
            ]))
            .get();
    // 别名一次查全、按 food_id 分组（ADR-037）：避免每行一次查询。
    final aliasRows = await database.select(database.foodAliases).get();
    final aliases = <String, List<String>>{};
    for (final row in aliasRows) {
      aliases.putIfAbsent(row.foodId, () => <String>[]).add(row.normalizedText);
    }
    return _save(
      'localfit-foods-${_stamp()}.csv',
      exporters.foodsCsv(foods, aliases: aliases),
    );
  }

  Future<CsvExportTables> _collect() async => CsvExportTables(
    meals: await database.select(database.meals).get(),
    mealItems: await database.select(database.mealItems).get(),
    workoutSessions: await database.select(database.workoutSessions).get(),
    workoutSets: await database.select(database.workoutSets).get(),
    exercises: await database.select(database.exercises).get(),
  );

  Future<String?> _save(String fileName, String csv) => fileStore.saveExport(
    defaultFileName: fileName,
    bytes: Uint8List.fromList(utf8.encode('\uFEFF$csv')),
  );

  String _stamp() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}'
        '-'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}';
  }
}
