// docs/66 §8.5：手动卡片 UI 实帧（capture 标签，用 `LF_ROUND7_CAPTURE_DIR`
// 输出到 tmp 后人工归档审看）。
//
// 帧：正常态（按钮）、生成中、空结果、失败重试、挂卡后、320dp×2.0×。
@Tags(['capture'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/features/ai_conversation/application/chat_edit_coordinator.dart';
import 'package:localfit_ai/features/ai_conversation/domain/ai_conversation_service.dart';
import 'package:localfit_ai/features/ai_conversation/domain/ai_envelope_compiler.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_command.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_context_builder.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_executor.dart';
import 'package:localfit_ai/features/ai_conversation/domain/conversation_message.dart';
import 'package:localfit_ai/features/ai_conversation/presentation/ai_conversation_page.dart';

import 'support/round7_render.dart';

/// 每次调用返回「一次发完即关」的流（与页面测试的手动驱动同一契约）。
final class _CaptureService
    implements AiConversationService, AiEnvelopeCompiler {
  _CaptureService(
    this.reply, {
    this.compileOutput,
    this.compileError,
    this.compileGate,
  });

  final String reply;
  final String? compileOutput;
  final Object? compileError;

  /// 非空时编译流先等这个门（帧②要停在「生成中」）。
  final Completer<void>? compileGate;

  @override
  Stream<String> sendMessage({
    required List<ConversationMessage> messages,
    required void Function(String chunk) onProgress,
    Stream<void>? cancelToken,
    String? systemContext,
  }) async* {
    // 控制器的显示缓冲走 onProgress（流事件本身不进气泡）。
    onProgress(reply);
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
  }) async* {
    if (compileGate != null) {
      await compileGate!.future;
    }
    if (compileError != null) {
      throw compileError!;
    }
    if (compileOutput != null) {
      onProgress(compileOutput!);
    }
  }
}

final class _FixedClock implements AppClock {
  _FixedClock(this.now);

  final DateTime now;

  @override
  DateTime nowUtc() => now;
}

class _StubBuilder implements ChatEditContextBuilder {
  @override
  Future<String> build({
    String? userMessage,
    PendingProposal? pendingProposal,
    String? foodQuery,
  }) async => '【当前可编辑数据快照】（帧捕获桩）';
}

class _StubExecutor implements ChatEditExecutor {
  @override
  Future<ChatEditApplyResult> apply(ChatEditCommand command) async =>
      const ChatEditApplyResult.ok('已完成。');
}

void main() {
  Future<void> pumpTree(
    WidgetTester tester,
    Widget page, {
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
          theme: round7CaptureTheme(AppTheme.light()),
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
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> shot(WidgetTester tester, String name) async {
    expect(tester.takeException(), isNull, reason: '$name：布局溢出');
    await captureRound7(tester, name);
  }

  testWidgets('手动卡片六帧', (tester) async {
    await tester.runAsync(loadRound7Fonts);

    const reply = '你今天喝了 250 毫升水，我准备帮你记上。';
    const waterEnvelope =
        '{"reply":"好的。","edits":'
        '[{"action":"water.add","args":{"amountMl":250}}]}';

    ChatEditCoordinator coordinator() => ChatEditCoordinator(
      contextBuilder: _StubBuilder(),
      executor: _StubExecutor(),
    );

    Future<void> sendReply(WidgetTester tester, String userText) async {
      await tester.enterText(
        find.byKey(const Key('ai-chat-text-input')),
        userText,
      );
      await tester.tap(find.byKey(const Key('btn-send')));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    // ①②③ 共用一页：编译流被 gate 拄住，三帧分别取 idle / generating / 挂卡。
    final compileGate = Completer<void>();
    final gateClock = DateTime.parse('2026-11-07T15:00:00+08:00');
    await pumpTree(
      tester,
      AiConversationPage(
        service: _CaptureService(
          reply,
          compileOutput: waterEnvelope,
          compileGate: compileGate,
        ),
        clock: _FixedClock(gateClock),
        chatEdit: coordinator(),
        manualCardGeneration: true,
      ),
      width: 390,
      height: 844,
      scale: 1.0,
    );
    // ① 正常态：内容卡右下角「生成应用卡片」。
    await sendReply(tester, '记 250ml 水');
    expect(find.byKey(const Key('ai-chat-generate-card-1')), findsOneWidget);
    await shot(tester, 'manual-card-idle-390-1.0');

    // ② 生成中（编译流被门拄住）。
    await tester.tap(find.byKey(const Key('ai-chat-generate-card-1')));
    for (var i = 0; i < 2; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(find.text('生成中…'), findsOneWidget);
    await shot(tester, 'manual-card-generating-390-1.0');

    // ③ 挂卡后：放行编译流 → 同一条消息下出卡，按钮消失。
    compileGate.complete();
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('生成中…'), findsNothing);
    await shot(tester, 'manual-card-attached-390-1.0');

    // ④ 失败 + 重试。
    await pumpTree(
      tester,
      AiConversationPage(
        service: _CaptureService(reply, compileError: Exception('network')),
        clock: _FixedClock(DateTime.parse('2026-11-07T15:00:00+08:00')),
        chatEdit: coordinator(),
        manualCardGeneration: true,
      ),
      width: 390,
      height: 844,
      scale: 1.0,
    );
    await sendReply(tester, '记 250ml 水');
    await tester.tap(find.byKey(const Key('ai-chat-generate-card-1')));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('生成失败，请重试。'), findsOneWidget);
    await shot(tester, 'manual-card-failed-390-1.0');

    // ⑤ 空结果（行内提示 + 重新检查）。
    await pumpTree(
      tester,
      AiConversationPage(
        service: _CaptureService(
          '今天想吃点什么？',
          compileOutput: '{"reply":"这条回复没有可直接记录的操作。","edits":[]}',
        ),
        clock: _FixedClock(DateTime.parse('2026-11-07T15:00:00+08:00')),
        chatEdit: coordinator(),
        manualCardGeneration: true,
      ),
      width: 390,
      height: 844,
      scale: 1.0,
    );
    await sendReply(tester, '今天吃什么好');
    await tester.tap(find.byKey(const Key('ai-chat-generate-card-1')));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('这条回复没有可直接记录的操作。'), findsOneWidget);
    await shot(tester, 'manual-card-empty-390-1.0');

    // ⑥ 320dp × 2.0×：按钮 + 原文不溢出。
    await pumpTree(
      tester,
      AiConversationPage(
        service: _CaptureService(reply, compileOutput: waterEnvelope),
        clock: _FixedClock(DateTime.parse('2026-11-07T15:00:00+08:00')),
        chatEdit: coordinator(),
        manualCardGeneration: true,
      ),
      width: 320,
      height: 700,
      scale: 2.0,
    );
    await sendReply(tester, '记 250ml 水');
    expect(find.byKey(const Key('ai-chat-generate-card-1')), findsOneWidget);
    await shot(tester, 'manual-card-320-2.0');

    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.view.resetPadding();
    tester.view.resetViewPadding();
  });
}
