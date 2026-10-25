import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/progress/data/measurement_repository.dart';
import 'package:localfit_ai/features/progress/presentation/weight_entry_dialog.dart';

/// docs/31 S2（需求 45/46）：**体脂率与肌肉量全删**。
///
/// 上一轮（docs/30 需求 2）删的是**展示**（体重卡不再统计这两项），
/// 数据层与录入弹层都还留着。本轮用户原话是「添加的弹窗卡片去掉体脂率和
/// 肌肉量」+「其他所有地方有关于这两个数据的都删掉」——所以这轮钉的是
/// **字段与数据一起没**。
///
/// 三条断言各防一件事：
///  * 字段不在 ⇒ 采集端不再产生这两个数（否则数据层删了列、UI 还在收集，
///    提交时会静默丢弃用户填的值）；
///  * `WeightEntryResult` 不带这两个属性 ⇒ **编译**就拦住未来有人再加回来
///    （字段一旦存在，弹层、页面接线、AI executor 会一起复活）；
///  * 日期回填只认体重与备注 ⇒ 回填语义随字段一起收窄，不是「留着旧代码
///    但没人调用」。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 10, 9, 12);
  const today = '2026-10-09';

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

  testWidgets('弹层只有三个字段：体重 / 备注 /（有日期时）日期', (tester) async {
    await tester.pumpWidget(
      host(
        WeightEntryDialog(
          todayLocalDate: today,
          initialLocalDate: today,
          initialWeightKg: 69.4,
          onSubmit: (_) async => null,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // ① 两个字段的 Key 与标签都不在。
    expect(find.byKey(const Key('weight-bodyfat-input')), findsNothing);
    expect(find.byKey(const Key('weight-muscle-input')), findsNothing);
    expect(find.textContaining('体脂'), findsNothing);
    expect(find.textContaining('肌肉'), findsNothing);

    // ② 反面：留下的字段一个都不许少（删的是两个，不是整个表单）。
    expect(find.byKey(const Key('weight-input')), findsOneWidget);
    expect(find.byKey(const Key('weight-notes')), findsOneWidget);
    expect(find.byKey(const Key('weight-entry-date')), findsOneWidget);
    expect(find.byKey(const Key('weight-save')), findsOneWidget);
  });

  testWidgets('删掉体成分后提交：结果只带体重/备注/日期', (tester) async {
    WeightEntryResult? submitted;
    await tester.pumpWidget(
      host(
        WeightEntryDialog(
          todayLocalDate: today,
          initialLocalDate: today,
          onSubmit: (result) async {
            submitted = result;
            return null;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('weight-input')), '69.4');
    await tester.enterText(find.byKey(const Key('weight-notes')), '早上称的');
    await tester.tap(find.byKey(const Key('weight-save')));
    await tester.pumpAndSettle();

    expect(submitted, isNotNull);
    expect(submitted!.weightKg, 69.4);
    expect(submitted!.notes, '早上称的');
    expect(submitted!.localDate, today);
  });

  testWidgets('日期回填只回填体重与备注（字段没了，回填也跟着收窄）', (tester) async {
    await repository.saveManualWeight(
      localDate: '2026-10-01',
      weightKg: 69.4,
      notes: '那天早上称的',
    );

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
          onSubmit: (result) async => null,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('weight-entry-date')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('date-picker-day-2026-10-01')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('weight-input')))
          .controller
          ?.text,
      '69.4',
    );
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('weight-notes')))
          .controller
          ?.text,
      '那天早上称的',
    );
  });

  test('数据层：measurements 表里没有体成分两列，写读照常', () async {
    // 这条查的是**真表结构**（不是 Dart 源码）：列真的不在了，
    // 而不是「代码里没人调用」。
    final columns = await database
        .customSelect('PRAGMA table_info(measurements)')
        .get();
    final names = columns.map((row) => row.data['name']).toList();
    expect(names, isNot(contains('body_fat_percent')));
    expect(names, isNot(contains('muscle_mass_kg')));
    expect(names, contains('weight_kg'), reason: '体重本身当然还在');

    final saved = await repository.saveManualWeight(
      localDate: today,
      weightKg: 69.4,
      notes: '早上称的',
    );
    expect(saved.weightKg, 69.4);
    expect(saved.notes, '早上称的');

    final readBack = await repository.findByDate(today);
    expect(readBack, isNotNull);
    expect(readBack!.weightKg, 69.4);
    expect(readBack.notes, '早上称的');
  });
}

class _Ids implements IdGenerator {
  int _next = 0;

  @override
  String next() => 'id-${_next++}';
}
