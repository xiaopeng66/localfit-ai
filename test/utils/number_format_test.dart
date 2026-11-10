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

  group('formatMegabytes', () {
    test('formats megabytes with one decimal', () {
      expect(formatMegabytes(41_000_000), '39.1 MB');
      expect(formatMegabytes(1024 * 1024), '1.0 MB');
      expect(formatMegabytes(1024 * 1024 * 10), '10.0 MB');
      expect(formatMegabytes(1024 * 1024 * 100), '100.0 MB');
    });

    test('falls back to KB below one megabyte', () {
      expect(formatMegabytes(1024), '1.0 KB');
      expect(formatMegabytes(1024 * 500), '500 KB');
      expect(formatMegabytes(0), '0.0 KB');
    });

    test('treats negative byte counts as zero', () {
      // 服务器没给 content-length 时上游会传 -1：不许把它算成「-1 MB」。
      expect(formatMegabytes(-1), '0.0 KB');
    });
  });
}
