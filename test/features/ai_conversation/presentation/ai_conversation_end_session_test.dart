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

import '../application/chat_edit_executor_test.dart' show IdsForTest;

/// 「结束本次对话」（`RV4-P2-05` / D4 合并后的唯一入口）：入口存在；
/// 消息不足 6 条时如实拒绝；足够消息时把候选送进「待确认」，**不写
/// ai_memories**。
///
/// 【语义变更，按 D4 裁决】原来这里还有「自动提炼开关关闭则不执行」的用例。
/// 裁决明确：**显式动作不受开关约束**（开关只管后台自动跑）。所以那条用例
/// 被下面的「不设开关也执行」替代，强度不降（仍然断言「不写记忆」）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late AiMemoryRepository memories;
  late DriftConversationMessageRepository history;
  late BackgroundJobRepository jobs;
  late AppSettingsRepository settings;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    final clock = FixedAppClock(DateTime.utc(2026, 10, 20, 9));
    memories = AiMemoryRepository(
      database: database,
      clock: clock,
      idGenerator: IdsForTest(),
    );
    history = DriftConversationMessageRepository(database: database);
    jobs = BackgroundJobRepository(
      database: database,
      clock: clock,
      idGenerator: IdsForTest(),
    );
    settings = AppSettingsRepository(database: database);
  });

  tearDown(() async {
    await database.close();
  });

  MemoryExtractionQueue queue() => MemoryExtractionQueue(
    jobs: jobs,
    memoryRepository: memories,
    settings: settings,
    clock: FixedAppClock(DateTime.utc(2026, 10, 20, 9)),
    service: const _ReplayService(),
  );

  Future<void> seedHistory(int count) async {
    for (var i = 0; i < count; i++) {
      await history.save(
        ConversationMessage(
          id: 'm-$i',
          role: i.isEven ? ConversationRole.user : ConversationRole.assistant,
          text: '第 $i 条对话内容',
          createdAt: DateTime.utc(2026, 10, 20, 9, i),
        ),
      );
    }
  }

  /// `RV4-P2-05` / D4：合并后「结束本次对话」**优先**走同步候选层（有记忆
  /// 仓储时）；只有没接记忆仓储（只有队列）时才入队。本文件测的是**队列**
  /// 分支，所以不接 `aiMemoryRepository`。
  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AiConversationPage(
          service: const _ReplayService(),
          historyRepository: history,
          memoryExtraction: queue(),
        ),
      ),
    );
    // 历史是异步加载的：泵几帧（不 pumpAndSettle——页面有常驻动画）。
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  testWidgets('入口存在；消息不足 6 条 → 如实拒绝，不入队', (tester) async {
    await seedHistory(4);
    await pumpPage(tester);

    final button = find.byKey(const Key('ai-chat-end-session'));
    expect(button, findsOneWidget, reason: '接线后顶栏必须有这个入口');

    await tester.tap(button);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(find.textContaining('还太短'), findsOneWidget);
    expect(await jobs.count(), 0);
  });

  testWidgets('8 条消息（不设开关）→ 候选进待确认，不写记忆', (tester) async {
    // 不调 setBool：D4 之后显式「结束本次对话」不看开关。
    await seedHistory(8);
    await pumpPage(tester);

    await tester.tap(find.byKey(const Key('ai-chat-end-session')));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(await memories.listActive(), isEmpty, reason: '确认才写');
    expect(await jobs.count(type: kMemoryExtractionJobType), 1);
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
