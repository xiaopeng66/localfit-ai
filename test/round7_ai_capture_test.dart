import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/features/ai_conversation/domain/ai_conversation_service.dart';
import 'package:localfit_ai/features/ai_conversation/domain/conversation_message.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_turn.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_command.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_registry.dart';

import 'package:localfit_ai/features/ai_conversation/domain/conversation_message_repository.dart';
import 'package:localfit_ai/features/ai_conversation/application/chat_edit_coordinator.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_context_builder.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_executor.dart';
import 'package:localfit_ai/features/ai_conversation/presentation/ai_conversation_page.dart';
import 'package:localfit_ai/features/ai_workbench/presentation/ai_workbench_page.dart';

import 'support/round7_render.dart';

/// Round7 阶段 5 的渲染矩阵（AI 创作画廊 + AI 对话）。
///
/// 8 帧：工作台画廊浅/深 360-1.0、画廊浅 320-2.0×、描述框弹层浅 360-1.0、
/// 对话欢迎态浅/深 360-1.0、对话流式/多消息浅 360-1.0、对话浅 320-2.0×。
///
/// A 的 AI 页事实：`aiPage()`（工作台 + 起手画廊）与 §5.7 的对话七种消息形态。
/// 本页有**无限循环动画**（输入中三点）⇒ 全部用 `pump`，不用 `pumpAndSettle`。
void main() {
  Future<void> pumpTree(
    WidgetTester tester,
    Widget page, {
    required bool dark,
    required double width,
    required double height,
    required double scale,
  }) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, height);
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
    tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
    await tester.pumpWidget(
      RepaintBoundary(
        key: round7Boundary,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: round7CaptureTheme(dark ? AppTheme.dark() : AppTheme.light()),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              disableAnimations: true,
            ),
            child: child!,
          ),
          home: page,
        ),
      ),
    );
    // 本批页面含无限动画 ⇒ 只推有限的几拍。
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> shot(WidgetTester tester, String name, Key sentinel) async {
    expect(tester.takeException(), isNull, reason: '$name：布局溢出');
    expect(find.byKey(sentinel), findsOneWidget, reason: '$name：关键件不在帧内');
    await captureRound7(tester, name);
  }

  testWidgets('AI 创作：画廊 + 描述框（4 帧）', (tester) async {
    await tester.runAsync(loadRound7Fonts);

    for (final (dark, width, height, scale, name) in [
      (false, 360.0, 900.0, 1.0, 'ai-gallery-light-360-1.0'),
      (true, 360.0, 900.0, 1.0, 'ai-gallery-dark-360-1.0'),
      (false, 320.0, 900.0, 2.0, 'ai-gallery-light-320-2.0'),
    ]) {
      await pumpTree(
        tester,
        const AiWorkbenchPage(),
        dark: dark,
        width: width,
        height: height,
        scale: scale,
      );
      await shot(tester, name, const Key('ai-workbench-hub'));
    }

    // 描述框弹层：点第一张启动卡
    await pumpTree(
      tester,
      const AiWorkbenchPage(),
      dark: false,
      width: 360,
      height: 900,
      scale: 1,
    );
    final card = find.byKey(const Key('ai-starter-meal-pairing'));
    if (card.evaluate().isNotEmpty) {
      await tester.tap(card);
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await shot(
        tester,
        'ai-starter-sheet-light-360-1.0',
        const Key('ai-starter-sheet'),
      );
    }

    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.view.resetPadding();
    tester.view.resetViewPadding();
  });

  testWidgets('AI 对话：逐项提案卡（proposed / 结果三态）（2 帧）', (tester) async {
    await tester.runAsync(loadRound7Fonts);
    final now = FixedAppClock(DateTime(2026, 10, 15, 10));

    // 一张提议中的编辑卡 + 一张已出结果的编辑卡（applied / failed / dismissed 混排，
    // 覆盖 docs/23 §5 的逐条状态与 §3.5「应用失败显示具体条目」）。
    // 命令按**注册表**造（与 `chat_edit_executor_test` 同一手法）。
    final registry = ChatEditCommandRegistry();
    ChatEditCommand cmd(String action, Map<String, Object> args) =>
        ChatEditCommand(spec: registry.specOf(action)!, args: args);

    final proposed = ChatEditTurn(
      reply: '我准备了 3 条修改，确认后才会写入本地：',
      rows: [
        ChatEditTurnItem(
          index: 0,
          raw: const {
            'action': 'weight.log',
            'args': {'weightKg': 72.5, 'localDate': '2026-10-15'},
          },
          command: cmd('weight.log', {
            'weightKg': 72.5,
            'localDate': '2026-10-15',
          }),
        ),
        ChatEditTurnItem(
          index: 1,
          raw: const {
            'action': 'water.add',
            'args': {'amountMl': 300, 'localDate': '2026-10-15'},
          },
          command: cmd('water.add', {
            'amountMl': 300,
            'localDate': '2026-10-15',
          }),
        ),
        ChatEditTurnItem(
          index: 2,
          raw: const {
            'action': 'profile.goal.update',
            'args': {'goal': 'cut', 'targetWeightKg': 68.0},
          },
          command: cmd('profile.goal.update', {
            'goal': 'cut',
            'targetWeightKg': 68.0,
          }),
        ),
      ],
    );
    final mixed = ChatEditTurn(
      reply: '上一轮的处理结果如下：',
      rows: [
        ChatEditTurnItem(
          index: 0,
          raw: const {
            'action': 'weight.log',
            'args': {'weightKg': 72.5, 'localDate': '2026-10-15'},
          },
          command: cmd('weight.log', {
            'weightKg': 72.5,
            'localDate': '2026-10-15',
          }),
          status: ChatEditRowStatus.applied,
          resultMessage: '已记录 72.5 kg。',
        ),
        ChatEditTurnItem(
          index: 1,
          raw: const {'action': 'unknown.action', 'args': <String, Object?>{}},
          decodeError: '这条指令尚不支持：unknown.action',
          status: ChatEditRowStatus.failed,
          resultMessage: '这条指令尚不支持：unknown.action',
        ),
        ChatEditTurnItem(
          index: 2,
          raw: const {
            'action': 'water.add',
            'args': {'amountMl': 300, 'localDate': '2026-10-15'},
          },
          command: cmd('water.add', {
            'amountMl': 300,
            'localDate': '2026-10-15',
          }),
          status: ChatEditRowStatus.dismissed,
        ),
      ],
    );

    final history = _MemoryHistory([
      _user('帮我把今天的午饭和体重记一下'),
      _assistantTurn('我准备了 3 条修改，确认后才会写入本地：', proposed),
      _user('刚才那条结果呢'),
      _assistantTurn('上一轮的处理结果如下：', mixed),
    ]);

    for (final (dark, name) in [
      (false, 'ai-chat-edit-card-light-360-1.0'),
      (true, 'ai-chat-edit-card-dark-360-1.0'),
    ]) {
      await pumpTree(
        tester,
        AiConversationPage(historyRepository: history, clock: now),
        dark: dark,
        width: 360,
        height: 1100,
        scale: 1,
      );
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await shot(tester, name, const Key('chat-edit-card-1'));
    }

    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.view.resetPadding();
    tester.view.resetViewPadding();
  });

  testWidgets('AI 对话：欢迎 / 流式 / 长列表（4 帧）', (tester) async {
    await tester.runAsync(loadRound7Fonts);
    final now = FixedAppClock(DateTime(2026, 10, 15, 10));

    // 欢迎态（无历史）
    for (final (dark, name) in [
      (false, 'ai-chat-welcome-light-360-1.0'),
      (true, 'ai-chat-welcome-dark-360-1.0'),
    ]) {
      await pumpTree(
        tester,
        AiConversationPage(clock: now),
        dark: dark,
        width: 360,
        height: 900,
        scale: 1,
      );
      await shot(tester, name, const Key('ai-chat-welcome'));
    }

    // 2026-10-16：修改请求只拿到文字 ⇒ 气泡下的「让 AI 给出可应用的修改」
    // 词条（用户要求「不许空回文字」的兜底入口）。
    {
      final retryHistory = _MemoryHistory([
        _user('帮我加一个鸡蛋'),
        _assistant('早上吃个鸡蛋挺好的，蛋白质也够。'),
      ]);
      await pumpTree(
        tester,
        AiConversationPage(
          historyRepository: retryHistory,
          clock: now,
          chatEdit: ChatEditCoordinator(
            contextBuilder: const _EmptyContext(),
            executor: const _NoopExecutor(),
          ),
        ),
        dark: false,
        width: 360,
        height: 900,
        scale: 1,
      );
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await shot(
        tester,
        'ai-chat-envelope-retry-light-360-1.0',
        const Key('ai-chat-request-envelope-1'),
      );
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.view.resetPadding();
      tester.view.resetViewPadding();
    }

    // 多消息 + 流式中（历史注入 + 手动服务）
    final history = _MemoryHistory([
      _user('今天练了卧推，帮我记一下'),
      _assistant('好的，已记住今天的卧推训练。需要我看看近期的容量趋势吗？'),
      _user('看看这周的饮食'),
      _assistant('这周共记录 12 餐，平均 1,860 kcal/天；蛋白质略低，建议加到 110g 左右。'),
    ]);
    final service = _ManualService();
    for (final (width, height, scale, name) in [
      (360.0, 900.0, 1.0, 'ai-chat-thread-light-360-1.0'),
      (320.0, 900.0, 2.0, 'ai-chat-thread-light-320-2.0'),
    ]) {
      await pumpTree(
        tester,
        AiConversationPage(
          service: service,
          historyRepository: history,
          clock: now,
        ),
        dark: false,
        width: width,
        height: height,
        scale: scale,
      );
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await shot(tester, name, const Key('ai-chat-text-input'));
    }

    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.view.resetPadding();
    tester.view.resetViewPadding();
  });
}

// ── 夹具 ────────────────────────────────────────────────────────────────

ConversationMessage _user(String text) => ConversationMessage(
  id: 'u-${text.hashCode}',
  role: ConversationRole.user,
  text: text,
  createdAt: DateTime.utc(2026, 10, 15, 9),
);

ConversationMessage _assistantTurn(String text, ChatEditTurn turn) =>
    ConversationMessage(
      id: 'a-turn-${text.hashCode}',
      role: ConversationRole.assistant,
      text: text,
      createdAt: DateTime.utc(2026, 10, 15, 9, 2),
      kind: ConversationMessageKind.editProposal,
      editTurn: turn,
    );

ConversationMessage _assistant(String text) => ConversationMessage(
  id: 'a-${text.hashCode}',
  role: ConversationRole.assistant,
  text: text,
  createdAt: DateTime.utc(2026, 10, 15, 9, 1),
);

final class _MemoryHistory implements ConversationMessageRepository {
  _MemoryHistory(this.messages);

  final List<ConversationMessage> messages;

  @override
  Future<List<ConversationMessage>> loadRecent({
    String sessionId = ConversationMessageRepository.defaultSessionId,
    int limit = 200,
  }) async => messages;

  @override
  Future<void> save(
    ConversationMessage message, {
    String sessionId = ConversationMessageRepository.defaultSessionId,
  }) async {
    messages.removeWhere((row) => row.id == message.id);
    messages.add(message);
  }

  @override
  Future<int> clear({
    String sessionId = ConversationMessageRepository.defaultSessionId,
  }) async {
    final before = messages.length;
    messages.clear();
    return before;
  }
}

final class _ManualService implements AiConversationService {
  @override
  Stream<String> sendMessage({
    required List<ConversationMessage> messages,
    required void Function(String chunk) onProgress,
    Stream<void>? cancelToken,
    String? systemContext,
  }) async* {
    onProgress('（本帧只渲染历史，不实际调用模型）');
  }
}

/// 帧用空快照（不连库）。
final class _EmptyContext implements ChatEditContextBuilder {
  const _EmptyContext();

  @override
  Future<String> build({
    String? userMessage,
    PendingProposal? pendingProposal,
  }) async => '（快照为空）';
}

/// 帧用不写库的执行器（这一帧不点应用）。
final class _NoopExecutor implements ChatEditExecutor {
  const _NoopExecutor();

  @override
  Future<ChatEditApplyResult> apply(ChatEditCommand command) async =>
      const ChatEditApplyResult.ok('（帧：未执行）');
}
