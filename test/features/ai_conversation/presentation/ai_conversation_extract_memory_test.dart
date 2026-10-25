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
import 'package:localfit_ai/features/ai_memory/data/ai_memory_repository.dart';

import '../application/chat_edit_executor_test.dart' show IdsForTest;

/// v2「提炼记忆」（docs/38 §4.3）：顶栏按钮 → 模型给候选 → 用户点选才写。
///
/// 服务用假实现回放一段预设回复；对话历史用真仓储预填。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late AiMemoryRepository memoryRepository;
  late DriftConversationMessageRepository historyRepository;
  late _ReplayService service;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    memoryRepository = AiMemoryRepository(
      database: database,
      clock: FixedAppClock(DateTime.utc(2026, 10, 17, 12)),
      idGenerator: IdsForTest(),
    );
    historyRepository = DriftConversationMessageRepository(database: database);
    service = _ReplayService();
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AiConversationPage(
          service: service,
          historyRepository: historyRepository,
          aiMemoryRepository: memoryRepository,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  /// `RV4-P2-05` / D4：合并后的「结束本次对话」沿用「至少 6 条」的门槛
  /// （原来「提炼记忆」那枚按钮没有门槛）。测试按新门槛补齐到 6 条——
  /// 断言对象（候选弹层 / 落库 / 提示文案）一个字没改。
  Future<void> seedHistory() async {
    for (var i = 0; i < 4; i++) {
      await historyRepository.save(
        ConversationMessage(
          id: 'pad-$i',
          role: i.isEven ? ConversationRole.user : ConversationRole.assistant,
          text: '补充对话 $i',
          createdAt: DateTime.utc(2026, 10, 17, 9, i),
        ),
      );
    }
    await historyRepository.save(
      ConversationMessage(
        id: 'u1',
        role: ConversationRole.user,
        text: '我平时不吃香菜，周三晚上练腿。',
        createdAt: DateTime.utc(2026, 10, 17, 10),
      ),
    );
    await historyRepository.save(
      ConversationMessage(
        id: 'a1',
        role: ConversationRole.assistant,
        text: '好的，记下了。',
        createdAt: DateTime.utc(2026, 10, 17, 10, 1),
      ),
    );
  }

  testWidgets('提炼：候选弹层 → 点选保存 → 落库 source=extracted', (tester) async {
    await seedHistory();
    service.reply =
        '{"reply":"找到 1 条","candidates":[{"text":"不吃香菜",'
        '"kind":"preference","domain":"nutrition","tags":["香菜"]}]}';
    await pumpPage(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('ai-chat-end-session')));
    await tester.pumpAndSettle();

    // 弹层出现候选；默认全选。
    expect(find.byKey(const Key('ai-memory-candidate-0')), findsOneWidget);
    await tester.tap(find.byKey(const Key('ai-memory-candidate-save')));
    await tester.pumpAndSettle();

    final rows = await database.select(database.aiMemories).get();
    expect(rows, hasLength(1));
    expect(rows.single.textContent, '不吃香菜');
    expect(rows.single.source, 'extracted');
    expect(find.text('已保存 1 条记忆。'), findsOneWidget);
  });

  testWidgets('提炼：模型说没有 → 只有提示，不弹候选', (tester) async {
    await seedHistory();
    service.reply = '{"reply":"这段对话没有值得长期记住的内容。","candidates":[]}';
    await pumpPage(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('ai-chat-end-session')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ai-memory-candidate-save')), findsNothing);
    expect(await database.select(database.aiMemories).get(), isEmpty);
  });

  testWidgets('提炼：请求失败 → 如实提示「提炼失败」', (tester) async {
    await seedHistory();
    service.throwOnSend = true;
    await pumpPage(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('ai-chat-end-session')));
    await tester.pumpAndSettle();

    expect(find.text('提炼失败，请稍后重试。'), findsOneWidget);
    expect(await database.select(database.aiMemories).get(), isEmpty);
  });

  testWidgets('空历史：按钮点了给诚实提示', (tester) async {
    await pumpPage(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ai-chat-end-session')));
    await tester.pumpAndSettle();
    // D4 合并后：空历史先撞「至少 6 条」门槛（更准确的说法——原来那句
    // 「还没有可提炼的对话内容」是提炼入口的文案，合并后不再存在）。
    expect(find.textContaining('还太短'), findsOneWidget);
  });

  testWidgets('未接线：顶栏不出提炼按钮', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AiConversationPage(
          service: service,
          historyRepository: historyRepository,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('ai-chat-end-session')), findsNothing);
  });
}

/// 回放式假服务：sendMessage 忽略输入，流式吐出预设回复。
final class _ReplayService implements AiConversationService {
  String reply = '';
  bool throwOnSend = false;

  @override
  Stream<String> sendMessage({
    required List<ConversationMessage> messages,
    required void Function(String chunk) onProgress,
    Stream<void>? cancelToken,
    String? systemContext,
  }) async* {
    if (throwOnSend) {
      throw StateError('boom');
    }
    // 提炼请求的正文应含候选 JSON 的指令（提示词真的被发送）。
    final prompt = messages.single.text;
    expect(prompt, contains('candidates'));
    for (var index = 0; index < reply.length; index += 7) {
      final end = (index + 7).clamp(0, reply.length);
      final chunk = reply.substring(index, end);
      onProgress(chunk);
      yield chunk;
    }
  }
}
