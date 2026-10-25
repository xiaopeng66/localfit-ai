import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/food_scan/presentation/food_scan_page.dart';
import 'package:localfit_ai/features/progress/data/measurement_repository.dart';

/// 拍照页对话式指令的**页面级**接线（docs/21 §5.4 能力 1–2）。
///
/// 这一层锁的是「意图 → 实际发生了什么」：
/// - 体重：真的写进了 measurements 表（且日期按注入的 now 算）；
/// - 训练：真的调用了跳转回调；
/// - 认不出：回引导文案，且**一行都不写库**。
///
/// 只测分类器会漏掉「页面根本没接线」——这套代码刚发生过这种失效。
/// （食谱计划意图随「食谱 / 计划」整族下线，页面不再有对应回调。）
void main() {
  late AppDatabase database;
  late MeasurementRepository measurements;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await database
        .into(database.profiles)
        .insert(
          ProfilesCompanion.insert(
            id: 'profile-1',
            activityLevel: 'moderate',
            createdAt: DateTime.utc(2026, 1, 1),
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
        );
    measurements = MeasurementRepository(
      database: database,
      idGenerator: const _Ids(),
      clock: FixedAppClock(DateTime.utc(2026, 9, 23, 9)),
    );
  });

  tearDown(() => database.close());

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FoodScanPage(
          measurementRepository: measurements,
          now: DateTime(2026, 9, 23, 9),
          onOpenWorkoutPlan: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> send(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(const Key('scan-command-input')), text);
    await tester.tap(find.byKey(const Key('scan-command-send')));
    await tester.pumpAndSettle();
  }

  testWidgets('「记录今天体重 72.5kg」真的写进 measurements', (tester) async {
    await pumpPage(tester);
    await send(tester, '记录今天体重 72.5kg');

    final rows = await database.select(database.measurements).get();
    expect(rows, hasLength(1));
    expect(rows.single.weightKg, 72.5);
    // 日期按注入的 now 算，不取系统时钟（否则跨零点测试会飘）。
    expect(rows.single.localDate, '2026-09-23');
    expect(find.byKey(const Key('scan-chat-command-reply')), findsOneWidget);
  });

  testWidgets('体重写库后清空输入框', (tester) async {
    await pumpPage(tester);
    await send(tester, '记录今天体重 72.5kg');

    final field = tester.widget<TextField>(
      find.byKey(const Key('scan-command-input')),
    );
    expect(field.controller!.text, isEmpty);
  });

  testWidgets('「帮我制定今天的训练计划」走跳转回调，不写任何库', (tester) async {
    var opened = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: FoodScanPage(
          measurementRepository: measurements,
          now: DateTime(2026, 9, 23),
          onOpenWorkoutPlan: () => opened++,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await send(tester, '帮我制定今天的训练计划');

    expect(opened, 1);
    expect(await database.select(database.measurements).get(), isEmpty);
  });

  testWidgets('认不出的句子只回引导，不写库', (tester) async {
    await pumpPage(tester);
    await send(tester, '今天天气不错');

    expect(find.byKey(const Key('scan-chat-command-reply')), findsOneWidget);
    expect(await database.select(database.measurements).get(), isEmpty);
  });

  testWidgets('值域外的体重不写库，并保留输入让用户改', (tester) async {
    await pumpPage(tester);
    await send(tester, '记录今天体重 320kg');

    expect(await database.select(database.measurements).get(), isEmpty);
    final field = tester.widget<TextField>(
      find.byKey(const Key('scan-command-input')),
    );
    expect(field.controller!.text, '记录今天体重 320kg');
  });

  testWidgets('未接线体重仓储时回可行动文案，不抛异常', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: FoodScanPage(now: DateTime(2026, 9, 23))),
    );
    await tester.pumpAndSettle();
    await send(tester, '记录今天体重 72kg');

    expect(find.byKey(const Key('scan-chat-command-reply')), findsOneWidget);
    final reply = tester
        .widgetList<Text>(
          find.descendant(
            of: find.byKey(const Key('scan-chat-command-reply')),
            matching: find.byType(Text),
          ),
        )
        .map((widget) => widget.data)
        .whereType<String>()
        .join(' ');
    expect(reply, contains('尚未就绪'));
  });
}

final class _Ids implements IdGenerator {
  const _Ids();

  @override
  String next() => 'id-${_counter++}';
  static int _counter = 0;
}
