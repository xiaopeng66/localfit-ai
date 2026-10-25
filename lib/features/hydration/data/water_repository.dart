import 'package:drift/drift.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/hydration/domain/water_intake.dart';

/// 饮水仓储（docs/21 §7.2 `WaterIntakes`）。
///
/// 目标毫升数来自 `DailyTargets.waterTargetMl`——它已经存在且默认 2000，
/// 所以这里只读不写目标；缺目标时 [WaterSummary.targetMl] 为 null，界面
/// 显示占位而不是编一个默认值当事实。
final class WaterRepository {
  const WaterRepository({
    required this.database,
    required this.idGenerator,
    required this.clock,
  });

  final AppDatabase database;
  final IdGenerator idGenerator;
  final AppClock clock;

  /// 监听某一天的饮水汇总（记录增删都会推送）。
  Stream<WaterSummary> watchDay(String localDate) {
    validateWaterLocalDate(localDate);
    final query = database.select(database.waterIntakes)
      ..where((row) => row.localDate.equals(localDate))
      ..orderBy([(row) => OrderingTerm.asc(row.recordedAt)]);
    return query.watch().asyncMap((rows) async {
      final records = rows.map(_map).toList(growable: false);
      return WaterSummary(
        consumedMl: records.fold<double>(0, (sum, r) => sum + r.amountMl),
        targetMl: await _targetMlForDate(localDate),
        records: records,
      );
    });
  }

  /// 读取某一天最新一条每日目标的饮水目标（可空＝未设定）。
  Future<double?> _targetMlForDate(String localDate) async {
    final row =
        await (database.select(database.dailyTargets)
              ..where((r) => r.effectiveDate.isSmallerOrEqualValue(localDate))
              ..orderBy([(r) => OrderingTerm.desc(r.effectiveDate)])
              ..limit(1))
            .getSingleOrNull();
    return row?.waterTargetMl;
  }

  /// 追加一次饮水记录，写入成功返回落库后的记录。
  Future<WaterIntakeRecord> add({
    required String localDate,
    required double amountMl,
  }) async {
    validateWaterLocalDate(localDate);
    final amount = validateWaterAmountMl(amountMl);
    final now = clock.nowUtc();
    final id = idGenerator.next();
    await database
        .into(database.waterIntakes)
        .insert(
          WaterIntakesCompanion.insert(
            id: id,
            localDate: localDate,
            amountMl: amount,
            recordedAt: now,
            createdAt: now,
            updatedAt: now,
          ),
        );
    return WaterIntakeRecord(
      id: id,
      localDate: localDate,
      amountMl: amount,
      recordedAt: now,
      createdAt: now,
      updatedAt: now,
    );
  }

  /// 删除一条记录（撤销误加）。返回被删掉的记录，不存在时返回 null。
  Future<WaterIntakeRecord?> delete(String id) async {
    final row =
        await (database.select(database.waterIntakes)
              ..where((r) => r.id.equals(id))
              ..limit(1))
            .getSingleOrNull();
    if (row == null) return null;
    await (database.delete(
      database.waterIntakes,
    )..where((r) => r.id.equals(id))).go();
    return _map(row);
  }

  /// 回写一条记录（撤销删除用）。
  Future<void> restore(WaterIntakeRecord record) async {
    await database
        .into(database.waterIntakes)
        .insertOnConflictUpdate(
          WaterIntakesCompanion.insert(
            id: record.id,
            localDate: record.localDate,
            amountMl: record.amountMl,
            recordedAt: record.recordedAt,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt,
          ),
        );
  }

  WaterIntakeRecord _map(WaterIntake row) => WaterIntakeRecord(
    id: row.id,
    localDate: row.localDate,
    amountMl: row.amountMl,
    recordedAt: row.recordedAt,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );
}
