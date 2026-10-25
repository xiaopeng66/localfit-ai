import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/progress/data/measurement_repository.dart';

/// RV2-P3-01（`docs/52`）：日期选择器已经把未来日挡住（`lastDate: today`），
/// 但**仓储层只校验格式**——AI 的 `weight.log` 与任何内部调用都能写未来日期，
/// 之后趋势图的「最近记录」会指向一个尚未发生的日子。
///
/// 判据：`saveManualWeight` 拒绝晚于**本机今天**的 `localDate`，且不写入任何行；
/// 今天与过去照常接受（不能因为加固把正常记录挡掉）。
void main() {
  late AppDatabase database;
  late MeasurementRepository repository;
  final now = DateTime.utc(2026, 10, 22, 9);

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    repository = MeasurementRepository(
      database: database,
      idGenerator: _SeqIds(),
      clock: FixedAppClock(now),
    );
    await database
        .into(database.profiles)
        .insert(
          ProfilesCompanion.insert(
            id: 'profile-1',
            activityLevel: 'moderate',
            createdAt: now,
            updatedAt: now,
          ),
        );
  });

  tearDown(() async {
    await database.close();
  });

  test('未来日期被拒绝，且一行都不写', () async {
    await expectLater(
      repository.saveManualWeight(localDate: '2026-10-23', weightKg: 70),
      throwsA(isA<FormatException>()),
    );
    final rows = await database.select(database.measurements).get();
    expect(rows, isEmpty, reason: '拒绝必须是「整笔不写」，不是写一半');
  });

  test('今天与过去照常接受', () async {
    await repository.saveManualWeight(localDate: '2026-10-22', weightKg: 70);
    await repository.saveManualWeight(localDate: '2026-10-21', weightKg: 70.5);
    final rows = await database.select(database.measurements).get();
    expect(rows.map((row) => row.localDate).toSet(), {
      '2026-10-22',
      '2026-10-21',
    });
  });

  test('未来日期不改写已有记录（同一天已有值时也不许「提前」落库）', () async {
    await repository.saveManualWeight(localDate: '2026-10-21', weightKg: 70);
    await expectLater(
      repository.saveManualWeight(localDate: '2026-11-01', weightKg: 68),
      throwsA(isA<FormatException>()),
    );
    final rows = await database.select(database.measurements).get();
    expect(rows, hasLength(1));
    expect(rows.single.localDate, '2026-10-21');
  });
}

final class _SeqIds implements IdGenerator {
  int _n = 0;

  @override
  String next() => 'id-${_n++}';
}
