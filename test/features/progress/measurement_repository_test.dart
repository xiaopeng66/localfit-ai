import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/progress/data/measurement_repository.dart';

void main() {
  late AppDatabase database;
  late MeasurementRepository repository;
  final now = DateTime.utc(2026, 9, 9, 12);

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    repository = MeasurementRepository(
      database: database,
      idGenerator: _Ids(),
      clock: FixedAppClock(now),
    );
  });

  tearDown(() => database.close());

  Future<void> addProfile() async {
    await database
        .into(database.profiles)
        .insert(
          ProfilesCompanion.insert(
            id: 'profile',
            activityLevel: 'lightlyActive',
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  test('reads initial weight and updates the same day', () async {
    await addProfile();
    await database
        .into(database.measurements)
        .insert(
          MeasurementsCompanion.insert(
            id: 'initial',
            profileId: 'profile',
            localDate: '2026-09-09',
            weightKg: 75,
            createdAt: now.subtract(const Duration(hours: 1)),
            updatedAt: now.subtract(const Duration(hours: 1)),
          ),
        );
    expect(
      (await repository.watchWeightOverview(endLocalDate: '2026-09-09').first)
          .latest!
          .weightKg,
      75,
    );

    final saved = await repository.saveManualWeight(
      localDate: '2026-09-09',
      weightKg: 74.5,
    );
    expect(saved.id, 'initial');
    expect(await database.select(database.measurements).get(), hasLength(1));
    expect(
      (await repository.watchWeightOverview(endLocalDate: '2026-09-09').first)
          .latest!
          .weightKg,
      74.5,
    );
  });

  test('inserts different days and refreshes the overview stream', () async {
    await addProfile();
    final emissions = <double?>[];
    final subscription = repository
        .watchWeightOverview(endLocalDate: '2026-09-09')
        .listen((value) => emissions.add(value.sevenDayAverageKg));
    await Future<void>.delayed(Duration.zero);
    await repository.saveManualWeight(localDate: '2026-09-08', weightKg: 70);
    await repository.saveManualWeight(localDate: '2026-09-09', weightKg: 72);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await subscription.cancel();

    expect(await database.select(database.measurements).get(), hasLength(2));
    expect(emissions.last, 71);
  });

  test('rejects missing profile, invalid dates and unsafe weights', () async {
    await expectLater(
      repository.saveManualWeight(localDate: '2026-09-09', weightKg: 70),
      throwsStateError,
    );
    await addProfile();
    for (final weight in [34.9, 300.1, double.nan, double.infinity]) {
      await expectLater(
        repository.saveManualWeight(localDate: '2026-09-09', weightKg: weight),
        throwsFormatException,
      );
    }
    await expectLater(
      repository.saveManualWeight(localDate: '2026-02-30', weightKg: 70),
      throwsFormatException,
    );
    expect(await database.select(database.measurements).get(), isEmpty);
  });

  group('秤读数落地 saveScaleWeight（docs/31 S6，需求 47 / D6 ③）', () {
    test('当天无记录：插入新行，source = ble_scale', () async {
      await addProfile();
      final result = await repository.saveScaleWeight(
        localDate: '2026-09-09',
        weightKg: 62.4,
        overwriteSameDay: false,
      );

      expect(result.written, isTrue);
      expect(result.measurement.source, 'ble_scale');
      final row = await (database.select(
        database.measurements,
      )..limit(1)).getSingle();
      expect(row.source, 'ble_scale');
      expect(row.weightKg, closeTo(62.4, 1e-9));
    });

    test('同日已有记录且未明确覆盖：什么都不写，原记录原样返回', () async {
      await addProfile();
      await repository.saveManualWeight(
        localDate: '2026-09-09',
        weightKg: 62.8,
        notes: '晨重',
      );
      final before = await (database.select(
        database.measurements,
      )..limit(1)).getSingle();

      final result = await repository.saveScaleWeight(
        localDate: '2026-09-09',
        weightKg: 62.4,
        overwriteSameDay: false,
      );

      expect(result.written, isFalse);
      expect(result.measurement.weightKg, closeTo(62.8, 1e-9));
      final after = await (database.select(
        database.measurements,
      )..limit(1)).getSingle();
      // 逐列比对：不覆盖是「一个字都不写」，不是「写了再改回」。
      expect(after.weightKg, before.weightKg);
      expect(after.source, before.source);
      expect(after.updatedAt, before.updatedAt);
      expect(after.notes, '晨重');
    });

    test('明确覆盖：体重与来源换成秤读数，手输备注保留', () async {
      await addProfile();
      await repository.saveManualWeight(
        localDate: '2026-09-09',
        weightKg: 62.8,
        notes: '晨重',
      );

      final result = await repository.saveScaleWeight(
        localDate: '2026-09-09',
        weightKg: 62.4,
        overwriteSameDay: true,
      );

      expect(result.written, isTrue);
      expect(result.measurement.source, 'ble_scale');
      expect(result.measurement.notes, '晨重');
      final row = await (database.select(
        database.measurements,
      )..limit(1)).getSingle();
      expect(row.weightKg, closeTo(62.4, 1e-9));
      expect(row.source, 'ble_scale');
      expect(row.notes, '晨重');
    });

    test('范围口径与手输一致（35–300 kg），出界抛 FormatException', () async {
      await addProfile();
      await expectLater(
        repository.saveScaleWeight(
          localDate: '2026-09-09',
          weightKg: 34.9,
          overwriteSameDay: false,
        ),
        throwsFormatException,
      );
      await expectLater(
        repository.saveScaleWeight(
          localDate: '2026-09-09',
          weightKg: 300.1,
          overwriteSameDay: false,
        ),
        throwsFormatException,
      );
      expect(await database.select(database.measurements).get(), isEmpty);
    });
  });
}

final class _Ids implements IdGenerator {
  int value = 0;

  @override
  String next() => 'measurement-${value++}';
}
