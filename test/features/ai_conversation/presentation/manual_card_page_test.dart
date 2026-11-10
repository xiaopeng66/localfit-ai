// docs/66 §8.3：手动卡片 UI 测试（页面层）。
//
// 覆盖：按钮出现规则、生成中/取消、成功挂卡（同一条消息）、失败/空结果、
// 尚未写入提示、旧兜底卡不出现、长按复制不互扰、320×2.0 不溢出、
// 应用前日期确认。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/features/ai_conversation/application/chat_edit_coordinator.dart';
import 'package:localfit_ai/features/ai_conversation/domain/ai_conversation_service.dart';
import 'package:localfit_ai/features/ai_conversation/domain/ai_envelope_compiler.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_command.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_context_builder.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_executor.dart';
import 'package:localfit_ai/features/ai_conversation/domain/conversation_message.dart';
import 'package:localfit_ai/features/ai_conversation/presentation/ai_conversation_page.dart';

// ── 测试替身 ─────────────────────────────────────────────────────────────

final class _PageService implements AiConversationService, AiEnvelopeCompiler {
  final List<_SendCall> sendCalls = [];
  final List<_CompileCall> compileCalls = [];

  @override
  Stream<String> sendMessage({
    required List<ConversationMessage> messages,
    required void Function(String chunk) onProgress,
    Stream<void>? cancelToken,
    String? systemContext,
  }) {
    final call = _SendCall(onProgress, cancelToken);
    sendCalls.add(call);
    return call.stream;
  }

  @override
  Stream<String> compileEnvelope({
    required String userText,
    required String assistantReply,
    required String systemContext,
    required void Function(String chunk) onProgress,
    Stream<void>? cancelToken,
    String conversationContext = '',
    String targetLocalDate = '',
  }) {
    final call = _CompileCall(onProgress, cancelToken);
    compileCalls.add(call);
    return call.stream;
  }
}

final class _SendCall {
  _SendCall(this.onProgress, Stream<void>? cancelToken) {
    cancelToken?.listen((_) {}, onDone: () => cancelled = true);
  }

  final void Function(String chunk) onProgress;
  final StreamController<String> _controller = StreamController<String>();
  bool cancelled = false;

  void emit(String chunk) {
    onProgress(chunk);
    _controller.add(chunk);
  }

  void fail(Object error) => _controller.addError(error);

  Stream<String> get stream => _controller.stream;

  Future<void> finish() => _controller.close();
}

final class _CompileCall {
  _CompileCall(this.onProgress, Stream<void>? cancelToken) {
    cancelToken?.listen((_) {}, onDone: () => cancelled = true);
  }

  final void Function(String chunk) onProgress;
  final StreamController<String> _controller = StreamController<String>();
  bool cancelled = false;

  void emit(String chunk) {
    onProgress(chunk);
    _controller.add(chunk);
  }

  void fail(Object error) => _controller.addError(error);

  Stream<String> get stream => _controller.stream;

  Future<void> finish() => _controller.close();
}

class _StubBuilder implements ChatEditContextBuilder {
  @override
  Future<String> build({
    String? userMessage,
    PendingProposal? pendingProposal,
    String? foodQuery,
  }) async => '【当前可编辑数据快照】测试';
}

class _RecordingExecutor implements ChatEditExecutor {
  final List<ChatEditCommand> received = [];

  @override
  Future<ChatEditApplyResult> apply(ChatEditCommand command) async {
    received.add(command);
    return const ChatEditApplyResult.ok('已完成。');
  }
}

final class _MutableClock implements AppClock {
  _MutableClock(this.now);

  DateTime now;

  @override
  DateTime nowUtc() => now;
}

void main() {
  const today = '2026-11-07';
  final now = DateTime.parse('${today}T15:00:00+08:00');

  /// 让状态落地（页面有无限动画，不能 pumpAndSettle）。
  Future<void> settle(WidgetTester tester) async {
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);
  }

  Future<void> pumpPage(
    WidgetTester tester,
    Widget page, {
    Size size = const Size(390, 844),
    double textScale = 1.0,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    if (textScale != 1.0) {
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: const EdgeInsets.only(bottom: 0),
            viewInsets: EdgeInsets.zero,
          ),
          child: child!,
        ),
        home: page,
      ),
    );
    await settle(tester);
  }

  _PageService? serviceOf(WidgetTester tester) =>
      tester.widget<AiConversationPage>(find.byType(AiConversationPage)).service
          as _PageService?;

  AiConversationPage page(
    _PageService service, {
    _MutableClock? clock,
    ChatEditCoordinator? chatEdit,
  }) => AiConversationPage(
    service: service,
    clock: clock,
    chatEdit: chatEdit,
    manualCardGeneration: true,
  );

  Future<void> completeReply(
    WidgetTester tester,
    String userText,
    String reply,
  ) async {
    final service = serviceOf(tester)!;
    await tester.enterText(
      find.byKey(const Key('ai-chat-text-input')),
      userText,
    );
    await tester.tap(find.byKey(const Key('btn-send')));
    await settle(tester);
    service.sendCalls.last.emit(reply);
    await service.sendCalls.last.finish();
    await settle(tester);
  }

  testWidgets('完成的助手文本下出现生成按钮；点击 → 生成中 → 同一条消息下出卡', (tester) async {
    final service = _PageService();
    final clock = _MutableClock(now);
    final executor = _RecordingExecutor();
    await pumpPage(
      tester,
      page(
        service,
        clock: clock,
        chatEdit: ChatEditCoordinator(
          contextBuilder: _StubBuilder(),
          executor: executor,
        ),
      ),
    );
    await completeReply(tester, '记 250ml 水', '你喝了 250 毫升水。');

    expect(find.byKey(const Key('ai-chat-generate-card-1')), findsOneWidget);

    await tester.tap(find.byKey(const Key('ai-chat-generate-card-1')));
    await settle(tester);
    // busy：状态行出现，按钮换成生成中 + 取消。
    expect(
      find.byKey(const Key('ai-chat-card-generation-status-1')),
      findsOneWidget,
    );
    expect(find.text('生成中…'), findsOneWidget);
    expect(
      find.byKey(const Key('ai-chat-generate-card-1-cancel')),
      findsOneWidget,
    );

    service.compileCalls.single.emit(
      '{"reply":"好的。","edits":[{"action":"water.add","args":{"amountMl":250}}]}',
    );
    await service.compileCalls.single.finish();
    await settle(tester);

    // 同一条消息（index 1）挂卡：气泡仍在、卡在其下、不新增气泡。
    expect(find.text('你喝了 250 毫升水。'), findsOneWidget);
    expect(find.byKey(const Key('ai-chat-message-1')), findsOneWidget);
    // 日期钉定：摘要带目标日（2026-11-07）。
    expect(
      find.text('饮水 250.0ml（2026-11-07）'),
      findsWidgets,
      reason: '编辑卡行摘要出现（卡头与子条目各一份）',
    );
    expect(find.text('生成中…'), findsNothing, reason: '按钮消失');
    expect(executor.received, isEmpty, reason: '点应用之前不写库');
  });

  testWidgets('失败 → 行内错误 + 重试；空结果 → 行内提示；都可重新生成', (tester) async {
    final service = _PageService();
    final clock = _MutableClock(now);
    await pumpPage(
      tester,
      page(
        service,
        clock: clock,
        chatEdit: ChatEditCoordinator(
          contextBuilder: _StubBuilder(),
          executor: _RecordingExecutor(),
        ),
      ),
    );
    await completeReply(tester, '记 250ml 水', '你喝了 250 毫升水。');

    // 失败（网络错）。
    await tester.tap(find.byKey(const Key('ai-chat-generate-card-1')));
    await settle(tester);
    service.compileCalls.single.fail(Exception('boom'));
    await service.compileCalls.single.finish();
    await settle(tester);
    expect(
      find.byKey(const Key('ai-chat-card-generation-status-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('ai-chat-generate-card-1')),
      findsOneWidget,
      reason: '重试按钮复用同一个 key',
    );
    expect(find.text('生成失败，请重试。'), findsOneWidget);

    // 重试 → 空信封 → 行内提示（不挂卡）。
    await tester.tap(find.byKey(const Key('ai-chat-generate-card-1')));
    await settle(tester);
    expect(service.compileCalls, hasLength(2));
    service.compileCalls[1].emit('{"reply":"这里没有可直接记录的操作。","edits":[]}');
    await service.compileCalls[1].finish();
    await settle(tester);
    expect(find.text('这里没有可直接记录的操作。'), findsOneWidget);
    expect(find.text('重新检查'), findsOneWidget);
    expect(find.text('你喝了 250 毫升水。'), findsOneWidget);
  });

  testWidgets('生成中点「取消」→ 回 idle，原文不变，之后可重新生成', (tester) async {
    final service = _PageService();
    final clock = _MutableClock(now);
    await pumpPage(
      tester,
      page(
        service,
        clock: clock,
        chatEdit: ChatEditCoordinator(
          contextBuilder: _StubBuilder(),
          executor: _RecordingExecutor(),
        ),
      ),
    );
    await completeReply(tester, '记 250ml 水', '你喝了 250 毫升水。');
    await tester.tap(find.byKey(const Key('ai-chat-generate-card-1')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('ai-chat-generate-card-1-cancel')));
    await settle(tester);

    expect(find.text('生成中…'), findsNothing);
    expect(find.byKey(const Key('ai-chat-generate-card-1')), findsOneWidget);
    expect(find.text('你喝了 250 毫升水。'), findsOneWidget);
    // ignore: avoid_print
    // 迟到的流事件不挂卡：取消后到达的完整信封被 epoch 丢弃。
    // （这里的流已随取消终结；不再 close——单订阅流在订阅取消后 close 的
    // done future 在 FakeAsync 里不会完成，与被测行为无关。）
    service.compileCalls.single.emit(
      '{"reply":"好的。","edits":[{"action":"water.add","args":{"amountMl":250}}]}',
    );
    await settle(tester);
    expect(find.text('饮水 250.0ml（2026-11-07）'), findsNothing);
    expect(find.text('你喝了 250 毫升水。'), findsOneWidget);
  });

  testWidgets('修改请求 + 回复声称已记录但无卡 → 按钮旁出现「尚未写入」', (tester) async {
    final service = _PageService();
    final clock = _MutableClock(now);
    await pumpPage(
      tester,
      page(
        service,
        clock: clock,
        chatEdit: ChatEditCoordinator(
          contextBuilder: _StubBuilder(),
          executor: _RecordingExecutor(),
        ),
      ),
    );
    await completeReply(tester, '帮我记 250ml 水', '已记录你喝的 250 毫升水。');

    expect(find.byKey(const Key('ai-chat-not-written-1')), findsOneWidget);
    expect(find.text('尚未写入'), findsOneWidget);
    // 不自动挂卡、不自动补跑：只有发送这一次调用。
    expect(service.sendCalls, hasLength(1));
    expect(service.compileCalls, isEmpty);
  });

  testWidgets('新模式下旧兜底卡不出现（不能与生成按钮同时显示）', (tester) async {
    final service = _PageService();
    final clock = _MutableClock(now);
    await pumpPage(
      tester,
      page(
        service,
        clock: clock,
        chatEdit: ChatEditCoordinator(
          contextBuilder: _StubBuilder(),
          executor: _RecordingExecutor(),
        ),
      ),
    );
    // 典型残留态：修改请求 + 声称改好 + 提「点应用」。
    await completeReply(tester, '记 250ml 水', '已记录你喝的 250 毫升水，点「应用」后才会保存。');
    await settle(tester);
    expect(find.text('重新生成可应用指令'), findsNothing);
    expect(find.byKey(const Key('ai-chat-generate-card-1')), findsOneWidget);
  });

  testWidgets('昨天/更早的助手消息没有按钮', (tester) async {
    final service = _PageService();
    final clock = _MutableClock(now);
    await pumpPage(
      tester,
      page(
        service,
        clock: clock,
        chatEdit: ChatEditCoordinator(
          contextBuilder: _StubBuilder(),
          executor: _RecordingExecutor(),
        ),
      ),
    );
    // 今天回合一轮（有按钮）。
    await completeReply(tester, '记 250ml 水', '你喝了 250 毫升水。');
    expect(find.byKey(const Key('ai-chat-generate-card-1')), findsOneWidget);
    // 时钟跨天再发一轮：昨天的那条不再有按钮（新条是今天的有）。
    clock.now = now.add(const Duration(days: 1));
    await completeReply(tester, '再记一杯', '好的，再记一杯。');
    expect(
      find.byKey(const Key('ai-chat-generate-card-1')),
      findsNothing,
      reason: '昨天创建的内容卡没有入口',
    );
    expect(find.byKey(const Key('ai-chat-generate-card-3')), findsOneWidget);
  });

  testWidgets('在历史中间生成今天更早的卡片：不跳到会话底部（滚动隔离）', (tester) async {
    final service = _PageService();
    final clock = _MutableClock(now);
    await pumpPage(
      tester,
      page(
        service,
        clock: clock,
        chatEdit: ChatEditCoordinator(
          contextBuilder: _StubBuilder(),
          executor: _RecordingExecutor(),
        ),
      ),
    );
    // 三轮对话，铺出历史。
    for (var i = 0; i < 3; i++) {
      await completeReply(tester, '第 $i 句', '这是第 $i 句的回复，内容比较长一点。');
    }
    // 滚到顶部（翻历史），记录 offset。
    await tester.drag(find.byType(ListView).first, const Offset(0, 400));
    await settle(tester);
    final scrollable = find
        .descendant(
          of: find.byType(ListView).first,
          matching: find.byType(Scrollable),
        )
        .first;
    final position = tester.state<ScrollableState>(scrollable).position;
    final before = position.pixels;

    // 点第一条回复的生成按钮（今天更早的消息）。
    await tester.tap(find.byKey(const Key('ai-chat-generate-card-1')));
    await settle(tester);
    service.compileCalls.single.emit(
      '{"reply":"好的。","edits":[{"action":"water.add","args":{"amountMl":250}}]}',
    );
    await service.compileCalls.single.finish();
    await settle(tester);

    // 生成状态/挂卡不把用户拽到底部：offset 不增加（允许因卡片撑高而
    // 产生的必要最小滚动，但绝不是跳到 maxScrollExtent）。
    final after = position.pixels;
    expect(after, lessThan(position.maxScrollExtent), reason: '不跳到会话底部');
    expect(after, lessThanOrEqualTo(before + 1), reason: '视口基本不动（最小滚动）');
  });

  testWidgets('长按复制与按钮点击互不干扰', (tester) async {
    final service = _PageService();
    final clock = _MutableClock(now);
    await pumpPage(
      tester,
      page(
        service,
        clock: clock,
        chatEdit: ChatEditCoordinator(
          contextBuilder: _StubBuilder(),
          executor: _RecordingExecutor(),
        ),
      ),
    );
    await completeReply(tester, '记 250ml 水', '你喝了 250 毫升水。');

    // 长按气泡 → 复制提示（剪贴板通道打桩，测试环境没有平台回复）。
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.longPress(find.text('你喝了 250 毫升水。'));
    await settle(tester);
    expect(find.text('已复制'), findsOneWidget);

    // 点按钮 → 生成（长按手势没有吞掉点击）。
    await tester.tap(find.byKey(const Key('ai-chat-generate-card-1')));
    await settle(tester);
    expect(service.compileCalls, hasLength(1));
  });

  testWidgets('320dp × 2.0× 下按钮与状态不溢出', (tester) async {
    final service = _PageService();
    final clock = _MutableClock(now);
    await pumpPage(
      tester,
      page(
        service,
        clock: clock,
        chatEdit: ChatEditCoordinator(
          contextBuilder: _StubBuilder(),
          executor: _RecordingExecutor(),
        ),
      ),
      size: const Size(320, 640),
      textScale: 2.0,
    );
    await completeReply(tester, '记 250ml 水', '你喝了 250 毫升水，这是一段比较长的回复内容。');
    await tester.tap(find.byKey(const Key('ai-chat-generate-card-1')));
    await settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('生成中…'), findsOneWidget);
  });

  // 2026-11-09 全量审查实测：这条组合此前没有任何测试覆盖——旧用例的回复
  // 不含「已记录」类完成态，因此从不显示「尚未写入」提示，也就绕开了这一行。
  // 审查探针在 360dp×2.0 溢出 39px、320dp×2.0 溢出 79px（RenderFlex）。
  // 每个尺寸单独立一条：同一 test 里重复 pumpWidget 会复用 State（controller
  // 仍指向旧 service），测不到新尺寸。
  for (final size in [
    const Size(390, 844),
    const Size(360, 800),
    const Size(320, 700),
  ]) {
    testWidgets('「尚未写入」+「生成应用卡片」同排 $size × 2.0× 不溢出', (tester) async {
      final service = _PageService();
      final clock = _MutableClock(now);
      await pumpPage(
        tester,
        page(
          service,
          clock: clock,
          chatEdit: ChatEditCoordinator(
            contextBuilder: _StubBuilder(),
            executor: _RecordingExecutor(),
          ),
        ),
        size: size,
        textScale: 2.0,
      );
      await completeReply(tester, '帮我加上 250ml 饮水', '已经帮你记录到今天的饮水里了。');
      expect(
        find.byKey(const Key('ai-chat-not-written-1')),
        findsOneWidget,
        reason: '$size：诚实性提示必须出现（否则这条用例没测到目标布局）',
      );
      expect(find.byKey(const Key('ai-chat-generate-card-1')), findsOneWidget);
      expect(tester.takeException(), isNull, reason: '$size × 2.0：不得布局溢出');
    });
  }

  testWidgets('卡片含非今天日期：整卡应用先弹日期确认；拒绝不写库', (tester) async {
    final service = _PageService();
    final clock = _MutableClock(now);
    final executor = _RecordingExecutor();
    await pumpPage(
      tester,
      page(
        service,
        clock: clock,
        chatEdit: ChatEditCoordinator(
          contextBuilder: _StubBuilder(),
          executor: executor,
        ),
      ),
    );
    await completeReply(tester, '昨天喝了 100 毫升水，帮我记一下', '好的，100 毫升，我准备记到昨天。');
    await tester.tap(find.byKey(const Key('ai-chat-generate-card-1')));
    await settle(tester);
    service.compileCalls.single.emit(
      '{"reply":"好的。","edits":[{"action":"water.add",'
      '"args":{"amountMl":100,"localDate":"2026-11-06"}}]}',
    );
    await service.compileCalls.single.finish();
    await settle(tester);
    expect(executor.received, isEmpty);

    // 点「全部应用」→ 弹日期确认。
    await tester.tap(find.byKey(const Key('chat-edit-apply-1')));
    await settle(tester);
    expect(find.byKey(const Key('chat-edit-date-confirm')), findsOneWidget);
    // 拒绝 → 不写库。
    await tester.tap(find.byKey(const Key('chat-edit-date-confirm-cancel')));
    await settle(tester);
    expect(executor.received, isEmpty);
    expect(find.text('饮水 100.0ml（2026-11-06）'), findsWidgets, reason: '卡片原样保留');

    // 再应用 → 确认 → 写库。
    await tester.tap(find.byKey(const Key('chat-edit-apply-1')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('chat-edit-date-confirm-ok')));
    await settle(tester);
    expect(executor.received, hasLength(1));
    expect(executor.received.single.args['localDate'], '2026-11-06');
  });
}
