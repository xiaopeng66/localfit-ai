import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/app/design/widgets/lf_top_bar.dart';
import 'package:localfit_ai/app/design/widgets/setting_row.dart';
import 'package:localfit_ai/app/design/widgets/week_strip.dart';
import 'package:localfit_ai/features/nutrition/application/build_calorie_trend.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/nutrition_record_week_strip.dart';

Widget _app(Widget child, {double scale = 1}) => MaterialApp(
  theme: AppTheme.light(),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: Scaffold(
    body: Align(alignment: Alignment.topLeft, child: child),
  ),
);

void _viewport(WidgetTester tester, double width) {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

List<Rect> _textBoxes(WidgetTester tester, Finder finder) {
  final paragraph = tester.renderObject<RenderParagraph>(finder);
  final length = paragraph.text.toPlainText().length;
  return paragraph
      .getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: length))
      .map((box) => box.toRect())
      .toList();
}

void main() {
  testWidgets(
    'long model value does not squeeze the settings title or overflow',
    (tester) async {
      _viewport(tester, 320);
      const model = 'provider/gpt-long-model-with-reasoning-2026';
      await tester.pumpWidget(
        _app(
          const SettingRow(
            icon: Icons.psychology_outlined,
            title: 'AI 模型',
            value: model,
            showChevron: true,
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      final title = tester.getRect(find.text('AI 模型'));
      final value = tester.getRect(find.text(model));
      expect(title.width, greaterThan(60));
      expect(value.top, greaterThanOrEqualTo(title.bottom));
      expect(value.right, lessThanOrEqualTo(304));
      expect(
        tester
            .renderObject<RenderParagraph>(find.text(model))
            .didExceedMaxLines,
        isFalse,
      );
    },
  );

  testWidgets('large-font API key row keeps label readable and input usable', (
    tester,
  ) async {
    _viewport(tester, 320);
    await tester.pumpWidget(
      _app(
        const SettingRow(
          icon: Icons.key,
          title: 'API Key',
          trailing: SizedBox(
            width: 150,
            child: TextField(key: Key('key-field'), obscureText: true),
          ),
        ),
        scale: 2,
      ),
    );
    expect(tester.takeException(), isNull);
    final label = tester.getRect(find.text('API Key'));
    final input = tester.getRect(find.byKey(const Key('key-field')));
    expect(
      _textBoxes(tester, find.text('API Key')).map((box) => box.top).toSet(),
      hasLength(1),
    );
    expect(input.top, greaterThanOrEqualTo(label.bottom));
    expect(input.width, greaterThanOrEqualTo(150));
    await tester.tap(find.byKey(const Key('key-field')));
    await tester.enterText(find.byKey(const Key('key-field')), 'fake-key');
    expect(
      tester
              .widget<TextField>(find.byKey(const Key('key-field')))
              .controller
              ?.text ??
          tester
              .widget<EditableText>(find.byType(EditableText))
              .controller
              .text,
      'fake-key',
    );
  });

  testWidgets('short settings values stay aligned on one row when space fits', (
    tester,
  ) async {
    _viewport(tester, 390);
    await tester.pumpWidget(
      _app(
        const SettingRow(
          icon: Icons.info_outline,
          title: '版本',
          value: 'v0.1.0',
          showChevron: true,
        ),
      ),
    );
    final title = tester.getRect(find.text('版本'));
    final value = tester.getRect(find.text('v0.1.0'));
    expect(value.center.dy, closeTo(title.center.dy, 0.5));
    expect(value.left, greaterThan(title.right));
  });

  testWidgets(
    'top bar icon responds throughout its 44dp target including outside the visual circle',
    (tester) async {
      _viewport(tester, 320);
      var calls = 0;
      await tester.pumpWidget(
        _app(
          LfCircleIconButton(
            key: const Key('circle'),
            icon: Icons.chevron_left,
            tooltip: '返回',
            onPressed: () => calls++,
          ),
        ),
      );
      final rect = tester.getRect(find.byKey(const Key('circle')));
      expect(rect.size, const Size(44, 44));
      await tester.tapAt(Offset(rect.left + 1, rect.center.dy));
      await tester.pump();
      expect(calls, 1);
      await tester.tapAt(Offset(rect.center.dx, rect.top + 1));
      await tester.pump();
      expect(calls, 2);
    },
  );

  testWidgets(
    'settings toggle provides a 44dp high target above and below the visual pill',
    (tester) async {
      var value = false;
      await tester.pumpWidget(
        _app(
          SettingToggle(
            key: const Key('toggle'),
            value: false,
            semanticLabel: '自动本地备份',
            onChanged: (next) => value = next,
          ),
        ),
      );
      final rect = tester.getRect(find.byKey(const Key('toggle')));
      expect(rect.height, greaterThanOrEqualTo(44));
      await tester.tapAt(Offset(rect.center.dx, rect.top + 1));
      expect(value, isTrue);
    },
  );

  testWidgets(
    'two-digit week dates remain on one line inside their circle at large font',
    (tester) async {
      _viewport(tester, 320);
      await tester.pumpWidget(
        _app(
          WeekStrip(
            days: List.generate(
              7,
              (index) => WeekDay(
                weekdayLabel: ['一', '二', '三', '四', '五', '六', '日'][index],
                label: '${24 + index}',
              ),
            ),
            todayIndex: 6,
          ),
          scale: 2,
        ),
      );
      for (var date = 24; date <= 30; date++) {
        final finder = find.text('$date');
        final boxes = _textBoxes(tester, finder);
        expect(boxes, isNotEmpty);
        expect(
          boxes.map((box) => box.top).toSet(),
          hasLength(1),
          reason: 'date $date must not split into stacked digits',
        );
        final paragraph = tester.renderObject<RenderParagraph>(finder);
        final textRect = tester.getRect(finder);
        for (final box in boxes) {
          final start = paragraph.localToGlobal(box.topLeft);
          final end = paragraph.localToGlobal(box.bottomRight);
          expect(start.dy, greaterThanOrEqualTo(textRect.top - 0.5));
          expect(end.dy, lessThanOrEqualTo(textRect.bottom + 0.5));
        }
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'record week strip keeps the selected day visible at large font on 320dp',
    (tester) async {
      _viewport(tester, 320);
      final bars = buildCalorieTrendBars(
        records: const [],
        endDate: DateTime(2026, 9, 13),
        targetMaxKcal: 2000,
      );
      await tester.pumpWidget(
        _app(
          NutritionRecordWeekStrip(
            bars: bars,
            selectedDate: DateTime(2026, 9, 10),
            now: DateTime(2026, 9, 10),
            onSelect: (_) {},
          ),
          scale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
      final selected = find.byKey(const Key('meal-day-2026-09-10'));
      expect(selected, findsOneWidget);
      final rect = tester.getRect(selected);
      expect(rect.left, greaterThanOrEqualTo(-0.5));
      expect(rect.right, lessThanOrEqualTo(320.5));
      for (var day = 7; day <= 13; day++) {
        final label = day.toString().replaceFirst(RegExp(r'^0'), '');
        final column = find.byKey(
          Key('meal-day-2026-09-${day.toString().padLeft(2, '0')}'),
        );
        final text = find.descendant(of: column, matching: find.text(label));
        if (!tester.any(text)) continue;
        expect(
          _textBoxes(tester, text).map((box) => box.top).toSet(),
          hasLength(1),
          reason: 'record day $label must not split into stacked digits',
        );
        final circle = tester.getRect(
          find.descendant(of: column, matching: find.byType(Container)).first,
        );
        final textRect = tester.getRect(text);
        expect(
          textRect.width,
          lessThanOrEqualTo(circle.width + 0.5),
          reason:
              'record day $label text must fit inside its ${circle.width}dp circle',
        );
        expect(textRect.height, lessThanOrEqualTo(circle.height + 0.5));
      }
      expect(tester.takeException(), isNull);
    },
  );
}
