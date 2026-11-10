import 'package:drift/drift.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';

/// 数据自检（D-1/D-2，docs/64 阶段 3）：**只查与数，不改数**——修复动作
/// 单独给方法，且只做安全的那两个（见 [fixOrphanFoodIds] /
/// [removeStaleManualStepRows]）；日期格式异常**只报不修**（改写或删行都会
/// 丢记录）。
final class DataSelfCheck {
  DataSelfCheck({required this.database, required this.clock});

  final AppDatabase database;
  final AppClock clock;

  /// 步数手动行的「残留」口径：超过 7 天仍标 `manual`（用户忘了恢复自动读取）。
  static const int staleManualStepDays = 7;

  Future<DataSelfCheckReport> run() async {
    final orphans = await database
        .customSelect(
          'SELECT COUNT(*) AS c FROM meal_items '
          'WHERE food_id IS NOT NULL AND '
          "food_id NOT IN (SELECT id FROM foods WHERE id IS NOT NULL)",
        )
        .getSingle();

    // 日期格式异常按表扫（历史数据可能带进来；写入侧的校验管不了存量）。
    final badDates = <String, int>{};
    for (final entry in const {
      'meals': 'meals',
      'water_intakes': 'water_intakes',
      'measurements': 'measurements',
      'steps_daily': 'steps_daily',
    }.entries) {
      final row = await database
          .customSelect(
            'SELECT COUNT(*) AS c FROM ${entry.value} '
            "WHERE local_date NOT GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'",
          )
          .getSingle();
      final count = row.read<int>('c');
      if (count > 0) badDates[entry.key] = count;
    }

    final nowLocal = clock.nowUtc().toLocal();
    final today = DateTime(nowLocal.year, nowLocal.month, nowLocal.day);
    final cutoff = _formatLocalDate(
      today.subtract(const Duration(days: staleManualStepDays)),
    );
    final staleSteps = await database
        .customSelect(
          "SELECT COUNT(*) AS c FROM steps_daily "
          "WHERE source = 'manual' AND local_date < ?",
          variables: [Variable.withString(cutoff)],
        )
        .getSingle();

    return DataSelfCheckReport(
      orphanFoodItems: orphans.read<int>('c'),
      badDateRows: badDates,
      staleManualStepRows: staleSteps.read<int>('c'),
      lastBackupAt: await _readLastBackupAt(),
    );
  }

  // 最近一次修复的现场（撤销用）。只保留一份——连续两次修复，撤销只还原
  // 最后一次，这与「SnackBar 撤销」的全局语义一致。
  List<(String, String)> _lastOrphanPairs = const [];
  List<StepsDailyEntry> _lastStaleStepRows = const [];

  /// 修复孤儿引用：`meal_items.food_id` 指向已删食物的行置空引用。
  ///
  /// 安全的理由：条目的名称/克数/营养四值都是**快照列**，置空引用不丢任何
  /// 展示内容——只是不再宣称「这条来自食物库里的某一行」。置空前的
  /// (条目, 食物) 对留作撤销现场（[undoFixOrphanFoodIds]）。
  Future<int> fixOrphanFoodIds() async {
    final rows = await database
        .customSelect(
          'SELECT id, food_id FROM meal_items '
          'WHERE food_id IS NOT NULL AND '
          "food_id NOT IN (SELECT id FROM foods WHERE id IS NOT NULL)",
        )
        .get();
    _lastOrphanPairs = [
      for (final row in rows)
        (row.read<String>('id'), row.read<String>('food_id')),
    ];
    if (_lastOrphanPairs.isEmpty) return 0;
    await database.customStatement(
      'UPDATE meal_items SET food_id = NULL '
      'WHERE food_id IS NOT NULL AND '
      "food_id NOT IN (SELECT id FROM foods WHERE id IS NOT NULL)",
    );
    return _lastOrphanPairs.length;
  }

  /// 撤销上一次孤儿修复：把置空的 `food_id` 写回原值。
  Future<void> undoFixOrphanFoodIds() async {
    for (final (itemId, foodId) in _lastOrphanPairs) {
      await (database.update(database.mealItems)
            ..where((row) => row.id.equals(itemId)))
          .write(MealItemsCompanion(foodId: Value(foodId)));
    }
    _lastOrphanPairs = const [];
  }

  /// 清理超过 7 天的步数手动行。删除前把整行存作撤销现场——真把用户手输的
  /// 历史值删没了就不叫安全修复（[undoRemoveStaleManualStepRows]）。
  Future<int> removeStaleManualStepRows() async {
    final stale = await staleManualStepRows();
    _lastStaleStepRows = stale;
    if (stale.isEmpty) return 0;
    final nowLocal = clock.nowUtc().toLocal();
    final today = DateTime(nowLocal.year, nowLocal.month, nowLocal.day);
    final cutoff = _formatLocalDate(
      today.subtract(const Duration(days: staleManualStepDays)),
    );
    final affected =
        await (database.delete(database.stepsDaily)..where(
              (row) =>
                  row.source.equals('manual') &
                  row.localDate.isSmallerThanValue(cutoff),
            ))
            .go();
    return affected;
  }

  /// 撤销上一次手动步数行清理：原样写回（id / 来源 / 数值 / 时间戳都不变）。
  Future<void> undoRemoveStaleManualStepRows() async {
    for (final row in _lastStaleStepRows) {
      await database
          .into(database.stepsDaily)
          .insertOnConflictUpdate(
            StepsDailyCompanion.insert(
              id: row.id,
              localDate: row.localDate,
              steps: row.steps,
              source: row.source,
              recordedAt: row.recordedAt,
              createdAt: row.createdAt,
              updatedAt: row.updatedAt,
            ),
          );
    }
    _lastStaleStepRows = const [];
  }

  /// 「残留」的手动步数行整行取出（撤销回写用）。
  Future<List<StepsDailyEntry>> staleManualStepRows() {
    final nowLocal = clock.nowUtc().toLocal();
    final today = DateTime(nowLocal.year, nowLocal.month, nowLocal.day);
    final cutoff = _formatLocalDate(
      today.subtract(const Duration(days: staleManualStepDays)),
    );
    return (database.select(database.stepsDaily)..where(
          (row) =>
              row.source.equals('manual') &
              row.localDate.isSmallerThanValue(cutoff),
        ))
        .get();
  }

  Future<DateTime?> _readLastBackupAt() async {
    final row = await (database.select(
      database.appSettings,
    )..where((row) => row.key.equals('last_backup_at_ms'))).getSingleOrNull();
    final raw = row?.value;
    if (raw == null) return null;
    final millis = int.tryParse(raw);
    if (millis == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(millis);
  }
}

/// `yyyy-MM-dd`（本文件自用，避免为三行格式化去拉 nutrition 的域工具）。
String _formatLocalDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

/// 一次自检的结果。计数为 0 的项**也如实列出**（0 就是 0），由界面决定
/// 「没有问题时说没有问题」。
final class DataSelfCheckReport {
  const DataSelfCheckReport({
    required this.orphanFoodItems,
    required this.badDateRows,
    required this.staleManualStepRows,
    required this.lastBackupAt,
  });

  /// `meal_items.food_id` 指向已删食物的条数。
  final int orphanFoodItems;

  /// 日期格式异常：表名 → 行数（只列有问题的表）。
  final Map<String, int> badDateRows;

  /// 超过 7 天的手动步数行数。
  final int staleManualStepRows;

  /// 最近一次备份（D-2）；null = 还没有备份过。
  final DateTime? lastBackupAt;

  int get badDateTotal =>
      badDateRows.values.fold(0, (sum, value) => sum + value);

  bool get hasIssues =>
      orphanFoodItems > 0 || badDateTotal > 0 || staleManualStepRows > 0;
}
