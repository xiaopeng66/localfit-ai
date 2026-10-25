import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/time/daily_rollover.dart';

class _Host extends StatefulWidget {
  const _Host();

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> with DailyRollover {
  DateTime? rolledFrom;

  @override
  void onNewDay(DateTime previousDay) {
    setState(() => rolledFrom = previousDay);
  }

  @override
  Widget build(BuildContext context) =>
      Text(observedToday.toIso8601String(), textDirection: TextDirection.ltr);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('fires onNewDay with the previous day after rollover', (
    tester,
  ) async {
    await tester.pumpWidget(const _Host());
    final state = tester.state<_HostState>(find.byType(_Host));
    expect(state.rolledFrom, isNull);

    final previous = DateTime.now().subtract(const Duration(days: 1));
    state.debugRollover(DateTime(previous.year, previous.month, previous.day));
    await tester.pump();

    expect(
      state.rolledFrom,
      DateTime(previous.year, previous.month, previous.day),
    );
  });

  testWidgets('no-op when the observed day is unchanged', (tester) async {
    await tester.pumpWidget(const _Host());
    final state = tester.state<_HostState>(find.byType(_Host));
    state.debugRollover(DateTime.now());
    await tester.pump();

    expect(state.rolledFrom, isNull);
  });
}
