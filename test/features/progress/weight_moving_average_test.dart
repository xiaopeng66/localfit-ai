import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/features/progress/domain/weight_measurement.dart';

void main() {
  WeightMeasurement value(String date, double weight, {int revision = 0}) {
    return WeightMeasurement(
      id: '$date-$revision',
      profileId: 'profile',
      localDate: date,
      weightKg: weight,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1, 0, revision),
    );
  }

  test('calculates a complete seven-day window', () {
    final measurements = List.generate(
      7,
      (index) => value(
        '2026-09-${(3 + index).toString().padLeft(2, '0')}',
        70.0 + index,
      ),
    );
    final overview = calculateWeightOverview(
      measurements: measurements,
      endLocalDate: '2026-09-09',
    );
    expect(overview.sevenDayAverageKg, 73);
    expect(overview.sampleDays, 7);
    expect(overview.latest!.weightKg, 76);
  });

  test('uses sparse dates and excludes the eighth day', () {
    final overview = calculateWeightOverview(
      measurements: [
        value('2026-09-02', 90),
        value('2026-09-03', 70),
        value('2026-09-09', 74),
      ],
      endLocalDate: '2026-09-09',
    );
    expect(overview.sevenDayAverageKg, 72);
    expect(overview.sampleDays, 2);
  });

  test('uses latest updated value for duplicate local dates', () {
    final overview = calculateWeightOverview(
      measurements: [
        value('2026-09-09', 80),
        value('2026-09-09', 75, revision: 1),
      ],
      endLocalDate: '2026-09-09',
    );
    expect(overview.sevenDayAverageKg, 75);
    expect(overview.sampleDays, 1);
  });

  test('handles empty and cross-year windows', () {
    expect(
      calculateWeightOverview(
        measurements: const [],
        endLocalDate: '2026-01-01',
      ).sevenDayAverageKg,
      isNull,
    );
    final overview = calculateWeightOverview(
      measurements: [value('2025-12-31', 70), value('2026-01-01', 72)],
      endLocalDate: '2026-01-01',
    );
    expect(overview.sevenDayAverageKg, 71);
  });
}
