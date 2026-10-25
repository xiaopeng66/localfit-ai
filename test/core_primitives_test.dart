import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';

void main() {
  test('fixed clock always returns the configured UTC instant', () {
    final value = DateTime.parse('2026-09-09T08:30:00+08:00');
    final clock = FixedAppClock(value);

    expect(clock.nowUtc(), DateTime.parse('2026-09-09T00:30:00Z'));
  });

  test('UUID v7 generator returns unique valid identifiers', () {
    const generator = UuidV7Generator();

    final first = generator.next();
    final second = generator.next();

    expect(first, isNot(second));
    expect(
      first,
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
  });
}
