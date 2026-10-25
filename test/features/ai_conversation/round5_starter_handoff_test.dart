import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/features/ai_conversation/domain/ai_conversation_service.dart';
import 'package:localfit_ai/features/ai_conversation/domain/conversation_message.dart';
import 'package:localfit_ai/features/ai_conversation/presentation/ai_conversation_page.dart';

/// T6b（docs/32 §4 T6b / §3 D5）：AI 创作卡 → 对话分支的**预填 + 自动发送**。
///
/// 四条验收语句：
///  ① 画廊卡生成 → 落在对话分支且消息**已自动发送**；
///  ② `isReplying` 时不自动发送（只预填 + 提示）；
///  ③ 冷启动（对话分支此前未建）pending 不丢；
///  ④ pending **只消费一次**。
void main() {
  Widget host(Widget child) =>
      MaterialApp(theme: AppTheme.light(), home: child);

  final sent = <String>[];

  testWidgets('① 画廊卡生成 → 对话分支的输入被自动发送', (tester) async {
    sent.clear();
    final notifier = ValueNotifier<({String display, String send})?>(null);
    addTearDown(notifier.dispose);
    await tester.pumpWidget(
      host(
        AiConversationPage(
          service: _FakeConversationService(onSend: sent.add),
          pendingStarter: notifier,
        ),
      ),
    );
    await tester.pumpAndSettle();

    notifier.value = (
      display: '按我描述的目标生成训练计划并保存：\n\n一周 4 练，增肌',
      send: '按我描述的目标生成训练计划并保存：\n\n一周 4 练，增肌',
    );
    await tester.pumpAndSettle();

    expect(sent, hasLength(1), reason: '空闲时应自动发送一次');
    expect(sent.single, contains('一周 4 练，增肌'));
    expect(notifier.value, isNull, reason: 'pending 消费即清空');
  });

  testWidgets('③ 冷启动：pending 先于页面创建，仍自动发送', (tester) async {
    sent.clear();
    const coldText = '按我的目标和今天已吃的，帮我搭配今天剩下几餐：\n\n随便';
    final notifier = ValueNotifier<({String display, String send})?>((
      display: coldText,
      send: coldText,
    ));
    addTearDown(notifier.dispose);
    await tester.pumpWidget(
      host(
        AiConversationPage(
          service: _FakeConversationService(onSend: sent.add),
          pendingStarter: notifier,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(sent, hasLength(1), reason: '冷启动时 pending 不丢');
    expect(sent.single, contains('帮我搭配今天剩下几餐'));
    expect(notifier.value, isNull, reason: '消费即清空');
  });

  testWidgets('④ 清空 pending 不触发发送（只消费一次）', (tester) async {
    sent.clear();
    final notifier = ValueNotifier<({String display, String send})?>(null);
    addTearDown(notifier.dispose);
    await tester.pumpWidget(
      host(
        AiConversationPage(
          service: _FakeConversationService(onSend: sent.add),
          pendingStarter: notifier,
        ),
      ),
    );
    await tester.pumpAndSettle();

    notifier.value = (display: '第一次请求', send: '第一次请求');
    await tester.pumpAndSettle();
    expect(sent, hasLength(1));

    // 消费后页面已清空：不重发。
    await tester.pumpAndSettle();
    expect(sent, hasLength(1), reason: '清空不应触发发送');
  });

  testWidgets('② isReplying 时只预填不发送（守卫）', (tester) async {
    sent.clear();
    final notifier = ValueNotifier<({String display, String send})?>(null);
    addTearDown(notifier.dispose);
    final gate = Completer<void>();
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    await tester.pumpWidget(
      host(
        AiConversationPage(
          service: _FakeConversationService(
            onSend: sent.add,
            gate: gate.future,
          ),
          pendingStarter: notifier,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 第一条：进入回复中（流被 gate 挂起）。
    notifier.value = (display: '第一条请求', send: '第一条请求');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(sent, hasLength(1));

    // 回复中再来一条：只预填。回复挂起 ⇒ 用定次数 pump（不能用 settle）。
    notifier.value = (display: '第二条请求（回复中到达）', send: '第二条请求（回复中到达）');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(sent, hasLength(1), reason: 'isReplying 时不得自动发送（避免打断进行中的回复）');
    final fields = tester.widgetList<TextField>(find.byType(TextField));
    expect(
      fields.any((f) => f.controller?.text == '第二条请求（回复中到达）'),
      isTrue,
      reason: '守卫路径应把内容填进输入框交给用户',
    );

    gate.complete();
    await tester.pumpAndSettle();
  });
}

/// 假服务（按真实 [AiConversationService] 接口）：记录发出的用户文本，
/// 并可用 [gate] 挂起流式回复（模拟 isReplying）。
class _FakeConversationService implements AiConversationService {
  _FakeConversationService({required this.onSend, this.gate});

  final void Function(String) onSend;
  final Future<void>? gate;

  @override
  Stream<String> sendMessage({
    required List<ConversationMessage> messages,
    required void Function(String chunk) onProgress,
    Stream<void>? cancelToken,
    String? systemContext,
  }) async* {
    final last = messages.lastWhere(
      (m) => m.role == ConversationRole.user,
      orElse: () => messages.last,
    );
    onSend(last.text);
    if (gate != null) await gate;
    onProgress('收到。');
    yield '收到。';
  }
}
