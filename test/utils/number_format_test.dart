import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/utils/number_format.dart';

void main() {
  group('formatGroupedInt', () {
    test('groups every three digits', () {
      expect(formatGroupedInt(0), '0');
      expect(formatGroupedInt(7), '7');
      expect(formatGroupedInt(99), '99');
      expect(formatGroupedInt(100), '100');
      expect(formatGroupedInt(999), '999');
      expect(formatGroupedInt(1000), '1,000');
      expect(formatGroupedInt(12345), '12,345');
      expect(formatGroupedInt(49464), '49,464');
      expect(formatGroupedInt(1234567), '1,234,567');
    });

    test('keeps the sign and never groups the sign itself', () {
      expect(formatGroupedInt(-1), '-1');
      expect(formatGroupedInt(-1000), '-1,000');
      expect(formatGroupedInt(-49464), '-49,464');
    });
  });
}
