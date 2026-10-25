import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/app/design/widgets/lf_top_bar.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/progress/data/measurement_repository.dart';
import 'package:localfit_ai/features/progress/presentation/date_picker_sheet.dart';
import 'package:localfit_ai/features/progress/presentation/weight_entry_dialog.dart';

/// docs/29 §P9 需求 33：记录体重可选日期；回到哪一天就看那一天的记录
/// （回填），没有记录就清空——不许把今天的数字写到别的日子上。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 10, 7, 12);
  const today = '2026-10-07';

  late AppDatabase database;
  late MeasurementRepository repository;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    repository = MeasurementRepository(
      database: database,
      idGenerator: _Ids(),
      clock: FixedAppClock(now.toUtc()),
    );
    await database
        .into(database.profiles)
        .insert(
          ProfilesCompanion.insert(
            id: 'profile',
            activityLevel: 'lightlyActive',
            createdAt: now.toUtc(),
            updatedAt: now.toUtc(),
          ),
        );
  });

  tearDown(() => database.close());

  Widget host(Widget child) => MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(body: ListView(children: [child])),
  );

  group('MeasurementRepository.findByDate', () {
    test('取到那天最新一条（同日多次更新）', () async {
      await repository.saveManualWeight(localDate: '2026-10-01', weightKg: 70);
      await repository.saveManualWeight(localDate: '2026-10-01', weightKg: 69);
      final found = await repository.findByDate('2026-10-01');
      expect(found, isNotNull);
      expect(found!.weightKg, 69, reason: '同日多条时按 updatedAt 取最新');
    });

    test('那天没有记录 → null', () async {
      await repository.saveManualWeight(localDate: '2026-10-01', weightKg: 70);
      expect(await repository.findByDate('2026-10-02'), isNull);
    });

    test('窗口外也照常查（findByDate 不做 30 天窗口）', () async {
      await repository.saveManualWeight(localDate: '2025-01-01', weightKg: 80);
      final found = await repository.findByDate('2025-01-01');
      expect(found?.weightKg, 80);
    });
  });

  group('WeightEntryDialog 日期字段', () {
    testWidgets('默认今天；点开是日历弹层', (tester) async {
      await tester.pumpWidget(
        host(
          WeightEntryDialog(
            todayLocalDate: today,
            initialLocalDate: today,
            onSubmit: (result) async => null,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('weight-entry-date')), findsOneWidget);
      expect(find.byKey(const Key('weight-entry-date-value')), findsOneWidget);
      expect(find.text('今天 · 修改'), findsOneWidget);

      await tester.tap(find.byKey(const Key('weight-entry-date')));
      await tester.pumpAndSettle();

      // 日历弹层（手写月份日历，周一起始）。
      expect(find.byKey(const Key('date-picker-month')), findsOneWidget);
      expect(find.text('一'), findsOneWidget);
      expect(find.text('日'), findsOneWidget);
      // 今天可选。
      expect(find.byKey(const Key('date-picker-day-$today')), findsOneWidget);
      // 未来日渲染为置灰格子，但**没有回调**（点了不该有反应）。
      final tomorrow = tester.widget<InkWell>(
        find.byKey(const Key('date-picker-day-2026-10-08')),
      );
      expect(tomorrow.onTap, isNull);

      await tester.tap(find.byKey(const Key('date-picker-day-$today')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('date-picker-month')), findsNothing);
    });

    testWidgets('改日期到有记录的那天：四个字段回填那天的值', (tester) async {
      await repository.saveManualWeight(
        localDate: '2026-10-01',
        weightKg: 69.4,
      );

      var submitted = WeightEntryResult(weightKg: 0);
      await tester.pumpWidget(
        host(
          WeightEntryDialog(
            todayLocalDate: today,
            initialLocalDate: today,
            onDateChanged: (date) => repository
                .findByDate(date)
                .then(
                  (found) => found == null
                      ? null
                      : WeightEntryResult(
                          weightKg: found.weightKg,
                          notes: found.notes,
                        ),
                ),
            onSubmit: (result) async {
              submitted = result;
              return null;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 切到 10 月：初始月份就是 10 月（selected = 2026-10-07）。
      await tester.tap(find.byKey(const Key('weight-entry-date')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('date-picker-day-2026-10-01')));
      await tester.pumpAndSettle();

      // 回填：日期值 + 三个字段的 10 月 1 日值。
      expect(find.byKey(const Key('weight-entry-date-value')), findsOneWidget);
      final dateValue = tester.widget<Text>(
        find.byKey(const Key('weight-entry-date-value')),
      );
      expect(dateValue.data, '2026-10-01');
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('weight-input')))
            .controller
            ?.text,
        '69.4',
      );

      // 提交：localDate 带着选中的那天。
      await tester.tap(find.byKey(const Key('weight-save')));
      await tester.pumpAndSettle();
      expect(submitted.localDate, '2026-10-01');
      expect(submitted.weightKg, 69.4);
    });

    testWidgets('改日期到没记录的那天：字段清空（不是留着今天的数字）', (tester) async {
      await repository.saveManualWeight(localDate: today, weightKg: 71.2);

      await tester.pumpWidget(
        host(
          WeightEntryDialog(
            todayLocalDate: today,
            initialLocalDate: today,
            initialWeightKg: 71.2,
            onDateChanged: (date) => repository
                .findByDate(date)
                .then(
                  (found) => found == null
                      ? null
                      : WeightEntryResult(weightKg: found.weightKg),
                ),
            onSubmit: (result) async => null,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('weight-input')))
            .controller
            ?.text,
        '71.2',
      );

      // 改到 9 月 30 日（没有记录）：先翻到 9 月。
      await tester.tap(find.byKey(const Key('weight-entry-date')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('date-picker-prev-month')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('date-picker-day-2026-09-30')));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('weight-input')))
            .controller
            ?.text,
        '',
        reason: '那天没记录 ⇒ 清空；留着 71.2 会把今天的体重写到 9 月 30 日',
      );

      // 清空后直接保存：空体重必须被拦下（弹层还开着、错误内联），
      // 不许把「空」写去 9 月 30 日。
      await tester.tap(find.byKey(const Key('weight-save')));
      await tester.pump();
      expect(
        find.byKey(const Key('weight-entry-date')),
        findsOneWidget,
        reason: '空体重提交不许关窗',
      );
      expect(find.text('请输入有效体重'), findsOneWidget);
    });

    testWidgets('没给 todayLocalDate（旧调用点）：不显示日期字段', (tester) async {
      await tester.pumpWidget(
        host(
          WeightEntryDialog(
            initialWeightKg: 70,
            onSubmit: (result) async => null,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('weight-entry-date')), findsNothing);
      expect(find.byKey(const Key('weight-input')), findsOneWidget);
    });
  });

  group('DatePickerSheet 本体', () {
    testWidgets('周一起始的前置空格数正确（2026-10-05 是周一）', (tester) async {
      await tester.pumpWidget(
        host(
          DatePickerSheet(
            selected: today,
            firstDate: '2026-01-01',
            lastDate: today,
          ),
        ),
      );
      await tester.pumpAndSettle();
      // 2026-10-01 是周四：周一/二/三 = 3 个空格。
      expect(
        find.byKey(const Key('date-picker-day-2026-10-01')),
        findsOneWidget,
      );
      // 9 月 30 日不可选（firstDate = 2026-01-01 之后的 10 月窗口里它是
      // 上月，翻回去可见）——本用例只钉 10 月网格本身。
      expect(find.text('2026 年 10 月'), findsOneWidget);
    });

    testWidgets('不可选的日子没有回调（点了不该有反应）', (tester) async {
      // 窗口 [2026-10-03, 2026-10-07]：10-01/10-02 不可选。
      var popped = '';
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () async {
                    popped =
                        await showDatePickerSheet(
                          context,
                          selected: today,
                          firstDate: '2026-10-03',
                          lastDate: today,
                        ) ??
                        '';
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final disabled = find.byKey(const Key('date-picker-day-2026-10-02'));
      expect(disabled, findsOneWidget);
      await tester.tap(disabled, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(popped, '', reason: '不可选的日子不许作为结果弹出');
    });

    testWidgets('月份翻页有界（firstDate/lastDate 之外不可再翻）', (tester) async {
      await tester.pumpWidget(
        host(
          DatePickerSheet(
            selected: today,
            firstDate: '2026-10-01',
            lastDate: '2026-10-07',
          ),
        ),
      );
      await tester.pumpAndSettle();
      // 10 月只有 7 天窗口：下月不可去，上月不可去。
      expect(
        tester
            .widget<LfCircleIconButton>(
              find.byKey(const Key('date-picker-next-month')),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<LfCircleIconButton>(
              find.byKey(const Key('date-picker-prev-month')),
            )
            .onPressed,
        isNull,
      );
    });
  });
}

final class _Ids implements IdGenerator {
  int _v = 0;
  @override
  String next() => 'w-${_v++}';
}
