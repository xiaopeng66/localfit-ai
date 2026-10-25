import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart'
    hide ConversationMessage;
import 'package:localfit_ai/features/ai_conversation/data/drift_conversation_message_repository.dart';
import 'package:localfit_ai/features/ai_conversation/domain/ai_conversation_service.dart';
import 'package:localfit_ai/features/ai_conversation/domain/conversation_message.dart';
import 'package:localfit_ai/features/ai_conversation/presentation/ai_conversation_page.dart';
import 'package:localfit_ai/features/ai_memory/application/memory_extraction_queue.dart';
import 'package:localfit_ai/features/ai_memory/data/ai_memory_repository.dart';
import 'package:localfit_ai/features/jobs/data/background_job_repository.dart';
import 'package:localfit_ai/features/settings/data/app_settings_repository.dart';

import 'package:localfit_ai/core/ids/id_generator.dart';

final class _Ids implements IdGenerator {
  int _v = 0;

  @override
  String next() => 'id-${_v++}';
}

/// `RV4-P2-04` / `RV4-P2-05` / `RV4-P2-06`（`docs/57` §3 / `docs/56` R11 / D4）。
///
/// 三件事都落在「会话生命周期」这一层：
/// * **P2-04** 点提炼后界面**没有任何进行中提示**；
/// * **P2-05** 「结束本次会话」点了**没有可见变化**；
/// * **P2-06** 历史**无法清除**。
///
/// D4 裁决：两枚按钮合并为「结束本次对话」，**显式动作不受自动提炼开关约束**。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late AiMemoryRepository memories;
  late DriftConversationMessageRepository history;
  late BackgroundJobRepository jobs;
  late AppSettingsRepository settings;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    final clock = FixedAppClock(DateTime.utc(2026, 10, 24, 2));
    memories = AiMemoryRepository(
      database: database,
      clock: clock,
      idGenerator: _Ids(),
    );
    history = DriftConversationMessageRepository(database: database);
    jobs = BackgroundJobRepository(
      database: database,
      clock: clock,
      idGenerator: _Ids(),
    );
    settings = AppSettingsRepository(database: database);
  });

  tearDown(() async {
    await database.close();
  });

  MemoryExtractionQueue queue(AiConversationService service) =>
      MemoryExtractionQueue(
        jobs: jobs,
        memoryRepository: memories,
        settings: settings,
        clock: FixedAppClock(DateTime.utc(2026, 10, 24, 2)),
        service: service,
      );

  Future<void> seedHistory(int count) async {
    for (var i = 0; i < count; i++) {
      await history.save(
        ConversationMessage(
          id: 'm-$i',
          role: i.isEven ? ConversationRole.user : ConversationRole.assistant,
          text: '第 $i 条对话内容',
          createdAt: DateTime.utc(2026, 10, 24, 2, i),
        ),
      );
    }
  }

  Future<void> pumpPage(
    WidgetTester tester, {
    AiConversationService? service,
    bool withQueue = true,
    bool withMemory = true,
  }) async {
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final svc = service ?? const _ReplayService();
    await tester.pumpWidget(
      MaterialApp(
        home: AiConversationPage(
          service: svc,
          historyRepository: history,
          // 不给记忆仓储时走「只入队」分支（不弹候选层）——P2-05 的可见
          // 变化判据不该被候选弹层挡住。
          aiMemoryRepository: withMemory ? memories : null,
          memoryExtraction: withQueue ? queue(svc) : null,
          conversationHistory: history,
        ),
      ),
    );
    for (var i = 0; i < 25; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  group('P2-05 · 结束本次对话有可见变化且幂等', () {
    testWidgets('消息 ≥6 后点结束 → 分隔线 + hint 变化；再点只提示', (tester) async {
      await seedHistory(8);
      await pumpPage(tester, withMemory: false);

      expect(find.byKey(const Key('ai-chat-session-ended')), findsNothing);

      await tester.tap(find.byKey(const Key('ai-chat-end-session')));
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      expect(
        find.byKey(const Key('ai-chat-session-ended')),
        findsOneWidget,
        reason: '结束后消息尾部要有分隔线（P2-05 的可见变化）',
      );
      expect(find.textContaining('本次对话已结束'), findsOneWidget);
      final field = tester.widget<TextField>(
        find.byKey(const Key('ai-chat-text-input')),
      );
      expect(field.decoration?.hintText, '开始新对话…');

      await tester.tap(find.byKey(const Key('ai-chat-end-session')));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(
        find.byKey(const Key('ai-chat-session-ended')),
        findsOneWidget,
        reason: '幂等：只画一条分隔线',
      );
      await unmount(tester);
    });

    // 【2026-10-25 缺陷修复的回归钉子】用户实测：「点击结束本次对话以后…
    // 也无法新开对话，下边一直显示一个分割线，本次对话已结束」。
    //
    // 根因：`_sessionEnded` 只在「清空聊天记录」里重置，发送时从不重置。
    // 修法：一发送就开新会话（清边界标记）。
    testWidgets('结束后再发一条：分隔线消失、hint 复位（真的能新开对话）', (tester) async {
      await seedHistory(8);
      await pumpPage(tester, withMemory: false);

      await tester.tap(find.byKey(const Key('ai-chat-end-session')));
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(find.byKey(const Key('ai-chat-session-ended')), findsOneWidget);

      // 在输入框里打字并发送（走用户真实路径：`_sendCurrent`）。
      await tester.enterText(
        find.byKey(const Key('ai-chat-text-input')),
        '新的对话',
      );
      await tester.pump();
      // 发送走**回车**（`onSubmitted` 与发送按钮同一个回调 `onSendText`）。
      //
      // 为什么不点按钮：8 条历史 + 分隔线之后，发送按钮所在位置
      // `hitTestable == 0`（被消息层遮挡，实测 pos=(344,1848) 在视口内
      // 但仍点不中）。回车是用户同样会用的真实路径，且不受遮挡影响
      // ——**只改触发方式，断言一字未动**。
      await tester.testTextInput.receiveAction(TextInputAction.done);
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      expect(
        find.byKey(const Key('ai-chat-session-ended')),
        findsNothing,
        reason: '发送即开新会话：分隔线必须消失（用户原来卡在这里）',
      );
      final field = tester.widget<TextField>(
        find.byKey(const Key('ai-chat-text-input')),
      );
      expect(
        field.decoration?.hintText,
        isNot('开始新对话…'),
        reason: 'hint 要复位成正常占位——「开始新对话…」留着就等于一直没开成',
      );
      await unmount(tester);
    });

    testWidgets('消息不足 6 条：如实提示、不画分隔线', (tester) async {
      await seedHistory(3);
      await pumpPage(tester, withMemory: false);

      await tester.tap(find.byKey(const Key('ai-chat-end-session')));
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      expect(find.textContaining('还太短'), findsOneWidget);
      expect(find.byKey(const Key('ai-chat-session-ended')), findsNothing);
      await unmount(tester);
    });
  });

  group('P2-06 · 清空历史（二次确认 + 报数 + 取消不删）', () {
    testWidgets('确认后清空：DB 0 行、界面回欢迎区', (tester) async {
      await seedHistory(4);
      await pumpPage(tester, withQueue: false);

      await tester.tap(find.byKey(const Key('ai-chat-clear-history')));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(
        find.byKey(const Key('ai-chat-clear-history-confirm')),
        findsOneWidget,
        reason: '破坏性操作必须二次确认',
      );
      await tester.tap(
        find.byKey(const Key('ai-chat-clear-history-confirm-ok')),
      );
      for (var i = 0; i < 25; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      expect(await history.loadRecent(), isEmpty, reason: '库里的消息真的删了');
      expect(
        await database.select(database.conversationMessages).get(),
        isEmpty,
      );
      expect(find.byKey(const Key('ai-chat-welcome')), findsOneWidget);
      expect(find.textContaining('已清除'), findsOneWidget, reason: '如实报数');
      await unmount(tester);
    });

    testWidgets('取消：一条不少', (tester) async {
      await seedHistory(2);
      await pumpPage(tester, withQueue: false);

      await tester.tap(find.byKey(const Key('ai-chat-clear-history')));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.tap(find.byKey(const Key('ai-chat-clear-history-cancel')));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      expect(await history.loadRecent(), hasLength(2));
      await unmount(tester);
    });
  });

  group('P2-04 · 提炼忙态行', () {
    testWidgets('点提炼后出现 ai-chat-extracting，service 完成后消失', (tester) async {
      await seedHistory(8);
      final gate = Completer<void>();
      await pumpPage(tester, service: _GatedService(gate));

      await tester.tap(find.byKey(const Key('ai-chat-end-session')));
      // 推几帧：请求已发出但还没回来。
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      expect(
        find.byKey(const Key('ai-chat-extracting')),
        findsOneWidget,
        reason: '提炼进行中必须有可见忙态（P2-04：原来只有标志位、不上屏）',
      );

      gate.complete();
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(
        find.byKey(const Key('ai-chat-extracting')),
        findsNothing,
        reason: '完成后忙态消失',
      );
      await unmount(tester);
    });
  });
}

class _ReplayService implements AiConversationService {
  const _ReplayService();

  @override
  Stream<String> sendMessage({
    required List<ConversationMessage> messages,
    required void Function(String chunk) onProgress,
    Stream<void>? cancelToken,
    String? systemContext,
  }) async* {
    const reply =
        '{"reply":"找到 1 条","candidates":[{"text":"喜欢清淡","kind":"preference","domain":"nutrition"}]}';
    onProgress(reply);
    yield reply;
  }
}

final class _GatedService implements AiConversationService {
  _GatedService(this.gate);

  final Completer<void> gate;

  @override
  Stream<String> sendMessage({
    required List<ConversationMessage> messages,
    required void Function(String chunk) onProgress,
    Stream<void>? cancelToken,
    String? systemContext,
  }) async* {
    await gate.future;
    const reply = '{"reply":"没有","candidates":[]}';
    onProgress(reply);
    yield reply;
  }
}
