import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/app/design/widgets/lf_select_field.dart';

void main() {
  // The unchecked `selected as T` used to throw before either empty or
  // nonempty lists could be opened when no value had been chosen yet.
  for (final options in [
    <String>[],
    ['squat-id', 'bench-id'],
  ]) {
    testWidgets(
      'null selection opens ${options.length} options and cancellation never calls onChanged',
      (tester) async {
        final changes = <String>[];
        await tester.pumpWidget(
          _host(
            LfSelectField<String>(
              fieldKey: const Key('null-select'),
              label: '动作',
              value: null,
              options: options,
              optionLabel: (id) => id,
              onChanged: changes.add,
            ),
          ),
        );
        await tester.tap(find.byKey(const Key('null-select')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('lf-select-sheet-title')), findsOneWidget);
        expect(find.byKey(const Key('lf-select-options')), findsOneWidget);
        expect(
          find.byKey(const Key('lf-select-option-0')),
          options.isEmpty ? findsNothing : findsOneWidget,
        );
        expect(
          changes,
          isEmpty,
          reason: 'Opening a null field must not implicitly select the first option.',
        );
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('lf-select-options')), findsNothing);
        expect(changes, isEmpty);
        expect(find.text('请选择'), findsOneWidget);
      },
    );
  }

  testWidgets(
    'choosing from a null field returns the actual option, not its index',
    (tester) async {
      int? selected;
      final changes = <int>[];
      await tester.pumpWidget(
        _host(
          StatefulBuilder(
            builder: (_, setState) => LfSelectField<int>(
              fieldKey: const Key('null-select'),
              label: '训练选项',
              value: selected,
              options: const [17, 42],
              optionLabel: (value) => '选项 $value',
              onChanged: (value) {
                changes.add(value);
                setState(() => selected = value);
              },
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('null-select')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('lf-select-option-1')));
      await tester.pumpAndSettle();
      expect(changes, [42]);
      expect(selected, 42);
      expect(find.text('选项 42'), findsOneWidget);
      expect(find.byKey(const Key('lf-select-options')), findsNothing);
    },
  );
}

Widget _host(Widget child) => MaterialApp(
  theme: AppTheme.light(),
  home: Scaffold(
    body: Padding(padding: const EdgeInsets.all(16), child: child),
  ),
);
