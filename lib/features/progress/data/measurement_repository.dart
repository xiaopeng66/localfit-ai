import 'package:drift/drift.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/progress/domain/weight_measurement.dart';

final class MeasurementRepository {
  const MeasurementRepository({
    required this.database,
    required this.idGenerator,
    required this.clock,
  });

  final AppDatabase database;
  final IdGenerator idGenerator;
  final AppClock clock;

  /// 保存一次手动测量。
  ///
  /// schema 22（docs/31 S2，需求 45/46）起**不再接收体成分**：体脂率与肌肉量
  /// 两个形参随列一起删除。原先「传 null = 本次未测，写 null 而不是沿用旧值」
  /// 那条口径随字段消失而失效——现在压根没有第二个指标可以「沿用」。
  Future<WeightMeasurement> saveManualWeight({
    required String localDate,
    required double weightKg,
    String? notes,
  }) async {
    final parsedDate = parseLocalDate(localDate);
    // RV2-P3-01：日期选择器已经把未来日挡住（`lastDate: today`），但仓储层
    // 原先只校验格式 ⇒ AI 的 `weight.log` 与内部调用能写未来日期，之后
    // 「最近记录」会指向一个还没发生的日子。这里补上**唯一事实源**级别的
    // 守卫：晚于本机今天一律拒绝，且整笔不写。
    final nowLocal = clock.nowUtc().toLocal();
    final today = DateTime(nowLocal.year, nowLocal.month, nowLocal.day);
    if (parsedDate.isAfter(today)) {
      throw const FormatException('不能记录未来日期的体重。');
    }
    if (!weightKg.isFinite || weightKg < 35 || weightKg > 300) {
      throw const FormatException('体重必须在 35–300 kg 之间。');
    }
    final profile = await (database.select(
      database.profiles,
    )..limit(1)).getSingleOrNull();
    if (profile == null) throw StateError('请先完成本地建档。');
    final now = clock.nowUtc();
    final normalizedNotes = notes?.trim();
    late WeightMeasurement result;
    await database.transaction(() async {
      final existing =
          await (database.select(database.measurements)
                ..where(
                  (row) =>
                      row.profileId.equals(profile.id) &
                      row.localDate.equals(localDate),
                )
                ..orderBy([(row) => OrderingTerm.desc(row.updatedAt)])
                ..limit(1))
              .getSingleOrNull();
      if (existing == null) {
        final id = idGenerator.next();
        await database
            .into(database.measurements)
            .insert(
              MeasurementsCompanion.insert(
                id: id,
                profileId: profile.id,
                localDate: localDate,
                weightKg: weightKg,
                source: const Value('manual'),
                notes: Value(
                  normalizedNotes == null || normalizedNotes.isEmpty
                      ? null
                      : normalizedNotes,
                ),
                createdAt: now,
                updatedAt: now,
              ),
            );
        result = WeightMeasurement(
          id: id,
          profileId: profile.id,
          localDate: localDate,
          weightKg: weightKg,
          notes: normalizedNotes,
          source: 'manual',
          createdAt: now,
          updatedAt: now,
        );
      } else {
        await (database.update(
          database.measurements,
        )..where((row) => row.id.equals(existing.id))).write(
          MeasurementsCompanion(
            weightKg: Value(weightKg),
            source: const Value('manual'),
            notes: Value(
              normalizedNotes == null || normalizedNotes.isEmpty
                  ? null
                  : normalizedNotes,
            ),
            updatedAt: Value(now),
          ),
        );
        result = WeightMeasurement(
          id: existing.id,
          profileId: profile.id,
          localDate: localDate,
          weightKg: weightKg,
          notes: normalizedNotes,
          source: 'manual',
          createdAt: existing.createdAt,
          updatedAt: now,
        );
      }
    });
    return result;
  }

  /// 秤读数落地（docs/31 S6 需求 47 / D6 ③）：来源必须标 `ble_scale`，
  /// 且**默认不覆盖当天已有记录**——[overwriteSameDay] 为 false 且同日已有
  /// 记录时**一个字都不写**，把既有记录原样返回（`written: false`），
  /// 由界面让用户明确选择后再以 true 重调。同步绝不能静默毁掉手输值。
  Future<ScaleSaveResult> saveScaleWeight({
    required String localDate,
    required double weightKg,
    required bool overwriteSameDay,
  }) async {
    parseLocalDate(localDate);
    if (!weightKg.isFinite || weightKg < 35 || weightKg > 300) {
      throw const FormatException('体重必须在 35–300 kg 之间。');
    }
    final profile = await (database.select(
      database.profiles,
    )..limit(1)).getSingleOrNull();
    if (profile == null) throw StateError('请先完成本地建档。');
    final now = clock.nowUtc();
    late ScaleSaveResult result;
    await database.transaction(() async {
      final existing =
          await (database.select(database.measurements)
                ..where(
                  (row) =>
                      row.profileId.equals(profile.id) &
                      row.localDate.equals(localDate),
                )
                ..orderBy([(row) => OrderingTerm.desc(row.updatedAt)])
                ..limit(1))
              .getSingleOrNull();
      if (existing != null && !overwriteSameDay) {
        result = ScaleSaveResult(written: false, measurement: _map(existing));
        return;
      }
      if (existing == null) {
        final id = idGenerator.next();
        await database
            .into(database.measurements)
            .insert(
              MeasurementsCompanion.insert(
                id: id,
                profileId: profile.id,
                localDate: localDate,
                weightKg: weightKg,
                source: const Value('ble_scale'),
                createdAt: now,
                updatedAt: now,
              ),
            );
        result = ScaleSaveResult(
          written: true,
          measurement: WeightMeasurement(
            id: id,
            profileId: profile.id,
            localDate: localDate,
            weightKg: weightKg,
            source: 'ble_scale',
            createdAt: now,
            updatedAt: now,
          ),
        );
        return;
      }
      // 明确选择覆盖：只换体重与来源，**手输备注留着**（用户写的话不因
      // 同步而消失）。
      await (database.update(
        database.measurements,
      )..where((row) => row.id.equals(existing.id))).write(
        MeasurementsCompanion(
          weightKg: Value(weightKg),
          source: const Value('ble_scale'),
          updatedAt: Value(now),
        ),
      );
      result = ScaleSaveResult(
        written: true,
        measurement: WeightMeasurement(
          id: existing.id,
          profileId: profile.id,
          localDate: localDate,
          weightKg: weightKg,
          notes: existing.notes,
          source: 'ble_scale',
          createdAt: existing.createdAt,
          updatedAt: now,
        ),
      );
    });
    return result;
  }

  /// 某一天已有的体重记录（docs/29 §P9 需求 33：改日期时回填那天填过的值）。
  ///
  /// **不套 `watchWeightOverview` 的 30 天窗口**：日期选择能回到一年前，
  /// 用窗口查会漏掉更早的记录——用户改到那天会看到空字段，以为那天没记过，
  /// 一保存就把那天的记录覆盖成空体成分。同 `(profileId, localDate)` 有多行
  /// 时取 `updatedAt` 最新的一条，与 [saveManualWeight]「改哪一行」判据同源
  /// （**连 profile 条件也要一样**，否则回填的是另一个档案的行、保存却写进
  /// 本档案的新行）。
  Future<WeightMeasurement?> findByDate(String localDate) async {
    parseLocalDate(localDate);
    final profile = await (database.select(
      database.profiles,
    )..limit(1)).getSingleOrNull();
    if (profile == null) return null;
    final row =
        await (database.select(database.measurements)
              ..where(
                (row) =>
                    row.profileId.equals(profile.id) &
                    row.localDate.equals(localDate),
              )
              ..orderBy([(row) => OrderingTerm.desc(row.updatedAt)])
              ..limit(1))
            .getSingleOrNull();
    return row == null ? null : _map(row);
  }

  /// 全部体重记录（**只读**，按日期倒序；同日多行时 `updatedAt` 新的在前）。
  ///
  /// Round7 裁决 R5：设置页「体重记录」只读弹层用它。与
  /// [watchWeightOverview] 的差别只有一条——**不套 30 天窗口**：
  /// 那是趋势卡的窗口，历史列表要看到全部（同 [findByDate] 不套窗口的理由）。
  Stream<List<WeightMeasurement>> watchAllMeasurements() {
    final query = database.select(database.measurements)
      ..orderBy([
        (row) => OrderingTerm.desc(row.localDate),
        (row) => OrderingTerm.desc(row.updatedAt),
      ]);
    return query.watch().map((rows) => rows.map(_map).toList(growable: false));
  }

  /// 体重卡「回看历史」的窗口上限（天）。
  ///
  /// 2026-10-22 用户要求体重卡能切不同周/不同月查历史。`latest` 与
  /// `sevenDayAverageKg` 仍由 `calculateWeightOverview` 在**自己那 7 天窗口**
  /// 内算（语义不变）；这里只放宽**返回给卡片的记录列表**，否则退到上个月
  /// 时表里没有数据、图永远是空的。
  static const int historyWindowDays = 366;

  Stream<WeightOverview> watchWeightOverview({required String endLocalDate}) {
    final end = parseLocalDate(endLocalDate);
    final start = end.subtract(const Duration(days: historyWindowDays - 1));
    String format(DateTime value) =>
        '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';
    final query = database.select(database.measurements)
      ..where((row) => row.localDate.isSmallerOrEqualValue(endLocalDate))
      ..orderBy([
        (row) => OrderingTerm.desc(row.localDate),
        (row) => OrderingTerm.desc(row.updatedAt),
      ]);
    return query.watch().map((rows) {
      final mapped = rows.map(_map).toList(growable: false);
      final overview = calculateWeightOverview(
        measurements: mapped,
        endLocalDate: endLocalDate,
      );
      return WeightOverview(
        measurements: mapped
            .where((item) => item.localDate.compareTo(format(start)) >= 0)
            .toList(growable: false),
        latest: overview.latest,
        sevenDayAverageKg: overview.sevenDayAverageKg,
        sampleDays: overview.sampleDays,
      );
    });
  }

  WeightMeasurement _map(Measurement row) => WeightMeasurement(
    id: row.id,
    profileId: row.profileId,
    localDate: row.localDate,
    weightKg: row.weightKg,
    notes: row.notes,
    source: row.source,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );
}

/// [MeasurementRepository.saveScaleWeight] 的结果（docs/31 S6 D6 ③）。
final class ScaleSaveResult {
  const ScaleSaveResult({required this.written, required this.measurement});

  /// false = 同日已有记录且未明确选覆盖：**什么都没写**，[measurement] 是
  /// 保留的原记录（界面据此把「保留原记录」作为默认）。
  final bool written;

  final WeightMeasurement measurement;
}
