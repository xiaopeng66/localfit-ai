import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/ai_memory/data/ai_memory_repository.dart';
import 'package:localfit_ai/features/ai_memory/presentation/ai_memory_page.dart';

import '../ai_conversation/application/chat_edit_executor_test.dart'
    show IdsForTest;

/// S11（docs/38 §4.6）：记忆页的信任三件套——看得见、改得动、关得掉。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late AiMemoryRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = AiMemoryRepository(
      database: database,
      clock: FixedAppClock(DateTime.utc(2026, 10, 17, 12)),
      idGenerator: IdsForTest(),
    );
  });

  tearDown(() async {
    // 每个用例自己按 [disposePage] 的顺序收尾（先卸页面再关库）；这里只兜底
    // 失败路径，正常路径已经关过，不再重复 close。
  });

  /// drift 的流查询在取消订阅后会留一个 `Timer.run`（drift 源码原话：
  /// 「Flutter 测试里请 await Database.close()」）。顺序必须是：
  /// 卸掉页面（订阅取消）→ pump 一拍让计时器跑掉 → 关库；否则测试结束会报
  /// pending timer，而 tearDown 里的 close 会等这个计时器、把用例挂到超时。
  Future<void> disposePage(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    // 让 drift 的取消订阅计时器（`Timer.run`）真的跑掉：零时长 pump 不一定
    // 触发零延迟计时器，必须推进一点时间，否则 close() 会一直等它。
    await tester.pump(const Duration(seconds: 1));
    await database.close();
  }

  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: AiMemoryPage(repository: repository, onClose: () {}),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('添加 → 列表可见 → 开关落库 → 删除', (tester) async {
    await pumpPage(tester);
    expect(find.byKey(const Key('ai-memory-empty')), findsOneWidget);
    expect(find.byKey(const Key('ai-memory-close')), findsOneWidget);
    expect(find.byKey(const Key('ai-memory-search')), findsOneWidget);
    expect(find.byKey(const Key('ai-memory-copy-all')), findsOneWidget);

    await tester.tap(find.byKey(const Key('ai-memory-add')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ai-memory-editor-kind')), findsOneWidget);
    expect(find.byKey(const Key('ai-memory-editor-domain')), findsOneWidget);
    expect(find.byKey(const Key('ai-memory-editor-pinned')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('ai-memory-editor-text')),
      '周三晚上练腿',
    );
    await tester.tap(find.byKey(const Key('ai-memory-editor-save')));
    await tester.pumpAndSettle();

    expect(find.text('周三晚上练腿'), findsOneWidget);
    expect(find.byKey(const Key('ai-memory-list')), findsOneWidget);
    expect(
      find.byKey(const Key('ai-memory-row-id-0')),
      findsOneWidget,
      reason: '每行带稳定 key（id 来自注入的生成器）',
    );
    expect(
      (await database.select(database.aiMemories).get()).single.source,
      'manual',
      reason: '页面手写的记忆来源必须是 manual',
    );

    await tester.tap(find.byKey(const Key('ai-memory-injection-toggle')));
    await tester.pumpAndSettle();
    expect(await repository.injectionEnabled(), isFalse);

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ai-memory-delete-confirm')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ai-memory-empty')), findsOneWidget);
    expect(await database.select(database.aiMemories).get(), isEmpty);
    await disposePage(tester);
  });

  testWidgets('重复记忆在弹层里如实报错，弹层不关闭', (tester) async {
    await repository.remember(text: '不吃香菜');
    await pumpPage(tester);

    await tester.tap(find.byKey(const Key('ai-memory-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('ai-memory-editor-text')),
      '不吃香菜',
    );
    await tester.tap(find.byKey(const Key('ai-memory-editor-save')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('ai-memory-editor-error')),
      findsOneWidget,
      reason: '错误必须就地画在弹层里（弹层挡住页面时 SnackBar 看不见）',
    );
    expect(find.textContaining('已经有这条记忆'), findsOneWidget);
    expect(find.byKey(const Key('ai-memory-editor-text')), findsOneWidget);
    expect(await database.select(database.aiMemories).get(), hasLength(1));
    await disposePage(tester);
  });

  testWidgets('清空全部：确认后真的清空', (tester) async {
    await repository.remember(text: 'A');
    await repository.remember(text: 'B');
    await pumpPage(tester);

    await tester.tap(find.byKey(const Key('ai-memory-clear-all')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ai-memory-clear-confirm')));
    await tester.pumpAndSettle();

    expect(await database.select(database.aiMemories).get(), isEmpty);
    expect(find.byKey(const Key('ai-memory-empty')), findsOneWidget);
    await disposePage(tester);
  });
}
