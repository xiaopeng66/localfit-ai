import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/errors/app_failure.dart';
import 'package:localfit_ai/features/ai_conversation/application/conversation_controller.dart';
import 'package:localfit_ai/features/ai_conversation/domain/ai_conversation_service.dart';
import 'package:localfit_ai/features/ai_conversation/domain/ai_envelope_compiler.dart';
import 'package:localfit_ai/features/ai_conversation/application/chat_edit_coordinator.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_command.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_context_builder.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_executor.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_intent.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_repair.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_turn.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_image.dart';
import 'package:localfit_ai/features/ai_conversation/domain/conversation_message.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_reply_display.dart';
import 'package:localfit_ai/features/ai_conversation/domain/conversation_message_repository.dart';

/// Fake AI conversation service for testing.
class FakeConversationService implements AiConversationService {
  FakeConversationService({
    this.responses = const [],
    this.delay = Duration.zero,
    this.shouldThrow = false,
  });

  final List<String> responses;
  final Duration delay;
  final bool shouldThrow;
  int callCount = 0;

  /// 最近一次请求收到的 systemContext（docs/23 §3 注入验证用）。
  String? lastSystemContext;

  @override
  Stream<String> sendMessage({
    required List<ConversationMessage> messages,
    required void Function(String chunk) onProgress,
    Stream<void>? cancelToken,
    String? systemContext,
  }) {
    callCount++;
    lastSystemContext = systemContext;
    final controller = StreamController<String>();

    if (shouldThrow) {
      controller.addError(Exception('AI service error'));
      return controller.stream;
    }

    Future.delayed(delay, () {
      if (callCount - 1 < responses.length) {
        final response = responses[callCount - 1];
        final words = response.split(' ');
        for (var i = 0; i < words.length; i++) {
          final chunk = words[i];
          onProgress(chunk);
          controller.add(chunk);
          if (i < words.length - 1) {
            onProgress(' ');
            controller.add(' ');
          }
        }
        controller.close();
      } else {
        controller.close();
      }
    });

    return controller.stream;
  }
}

void main() {
  group('ConversationController', () {
    test('initial state is idle with empty messages', () {
      final controller = ConversationController(null);

      expect(controller.state.status, ConversationStatus.idle);
      expect(controller.state.messages, isEmpty);
      expect(controller.state.error, isNull);
    });

    test('sendMessage with null service sets error state', () async {
      final controller = ConversationController(null);

      await controller.sendMessage('Hello');

      expect(controller.state.status, ConversationStatus.error);
      expect(controller.state.error, isNotNull);
      expect(controller.state.messages, isEmpty);
    });

    test('sendMessage with empty text does nothing', () async {
      final service = FakeConversationService(responses: ['Hi there']);
      final controller = ConversationController(service);

      await controller.sendMessage('   ');

      expect(controller.state.messages, isEmpty);
      expect(controller.state.status, ConversationStatus.idle);
    });

    test('sendMessage adds user message and streams AI response', () async {
      final service = FakeConversationService(responses: ['Hello world']);
      final controller = ConversationController(service);

      await controller.sendMessage('Hi');

      // Wait for the stream to complete.
      await Future.delayed(const Duration(milliseconds: 100));

      expect(controller.state.messages, hasLength(2));
      expect(controller.state.messages[0].role, ConversationRole.user);
      expect(controller.state.messages[0].text, 'Hi');
      expect(controller.state.messages[1].role, ConversationRole.assistant);
      expect(controller.state.messages[1].text, 'Hello world');
      expect(controller.state.status, ConversationStatus.idle);
    });

    test('sendMessage streams chunks progressively', () async {
      final service = _ManualService();
      final controller = ConversationController(service);
      final errors = <FlutterErrorDetails>[];
      final previousOnError = FlutterError.onError;
      FlutterError.onError = errors.add;
      try {
        final completer = Completer<void>();
        controller.addListener(() {
          if (!completer.isCompleted &&
              controller.state.messages.length == 2 &&
              controller.state.messages[1].text == 'Hello world') {
            completer.complete();
          }
        });

        await controller.sendMessage('Hi');
        final call = service.calls.single;
        call.emit('Hello');
        expect(controller.state.messages, hasLength(2));
        expect(controller.state.messages[1].text, 'Hello');
        expect(
          controller.state.messages[1].status,
          ConversationMessageStatus.sending,
        );
        expect(completer.isCompleted, isFalse);

        call.emit(' world');
        await completer.future;
        expect(controller.state.messages[1].text, 'Hello world');
        expect(
          controller.state.messages[1].status,
          ConversationMessageStatus.sending,
        );

        await call.finish();
        expect(controller.state.messages, hasLength(2));
        expect(controller.state.messages[1].text, 'Hello world');
        expect(
          controller.state.messages[1].status,
          ConversationMessageStatus.sent,
        );
        expect(controller.state.status, ConversationStatus.idle);
        expect(errors, isEmpty, reason: '分片与收尾通知都不能让测试监听器重复完成 Future');
      } finally {
        FlutterError.onError = previousOnError;
        controller.dispose();
      }
    });

    test('失败气泡要带**可行动的原因**，而不是异常类名', () async {
      // 2026-10-16 设备实测（AVD `LocalFit_API35`，供应商 ai.furry.vg）：
      // 断网那一下，对话里只画出「发送失败，点击重试。」——**没有原因**，
      // 而同一时刻设置页的「测试连通性」却原样写着「网络连接不可用，请检查
      // 网络后重试。」。根因是控制器 `onError` 把 `error.toString()` 塞进
      // state（`NetworkFailure: …` 带类名），而气泡文本只取**已生成的分片**
      // （失败时通常为空）⇒ 用户看到的是没有任何信息的失败。
      final service = _ManualService();
      final controller = ConversationController(service);
      unawaited(controller.sendMessage('记录今天的体重 72.5 公斤'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      service.calls.single.fail(const NetworkFailure('网络连接不可用，请检查网络后重试。'));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final bubble = controller.state.messages.last;
      expect(bubble.status, ConversationMessageStatus.error);
      expect(
        bubble.text,
        contains('网络连接不可用'),
        reason: '失败原因必须进气泡（否则用户只知道「失败了」）',
      );
      expect(
        bubble.text,
        isNot(contains('NetworkFailure')),
        reason: '不许把异常类名/栈信息甩给用户',
      );
      expect(controller.state.error, contains('网络连接不可用'));
    });

    test('sendMessage with throwing service sets error state', () async {
      final service = FakeConversationService(shouldThrow: true);
      final controller = ConversationController(service);

      await controller.sendMessage('Hi');
      await Future.delayed(const Duration(milliseconds: 100));

      expect(controller.state.status, ConversationStatus.error);
      // 2026-10-16 改口径（**更严**，不是放宽）：非 AppFailure 的原始异常
      // 不进界面——错误出口白名单化只放行 `AppFailure.message`，其它一律
      // 固定文案（原来的 `error.toString()` 会把 `Exception: AI service error`
      // 这类内部细节甩给用户）。
      expect(controller.state.error, '发送失败，请稍后重试。');
      expect(controller.state.error, isNot(contains('AI service error')));
      expect(controller.state.error, isNot(contains('Exception')));
    });

    test('sendMessage during sending state is ignored', () async {
      final service = FakeConversationService(
        responses: ['Response 1'],
        delay: const Duration(milliseconds: 50),
      );
      final controller = ConversationController(service);

      // Start first message (will be in sending/aiReply state).
      unawaited(controller.sendMessage('First'));
      await Future.delayed(const Duration(milliseconds: 10));

      // Try to send second message while first is in progress.
      await controller.sendMessage('Second');

      // Should only have 2 messages (user + assistant), not 4.
      expect(controller.state.messages.length, lessThan(4));
    });

    test('cancel stops the current request', () async {
      final service = FakeConversationService(
        responses: ['Long response'],
        delay: const Duration(milliseconds: 50),
      );
      final controller = ConversationController(service);

      await controller.sendMessage('Hi');
      await Future.delayed(const Duration(milliseconds: 10));
      await controller.cancel();

      // Controller should be disposed without errors.
      controller.dispose();
    });

    test('multiple messages accumulate in the list', () async {
      final service = FakeConversationService(
        responses: ['First response', 'Second response'],
      );
      final controller = ConversationController(service);

      await controller.sendMessage('First');
      await Future.delayed(const Duration(milliseconds: 100));
      await controller.sendMessage('Second');
      await Future.delayed(const Duration(milliseconds: 100));

      expect(controller.state.messages, hasLength(4));
      expect(controller.state.messages[0].text, 'First');
      expect(controller.state.messages[1].text, 'First response');
      expect(controller.state.messages[2].text, 'Second');
      expect(controller.state.messages[3].text, 'Second response');
    });
  });

  // 阶段 G 修的控制器缺陷回归：落库窗口、错误态闸门、取消语义。
  group('ConversationController · 落库 / 重试 / 取消', () {
    test('落库顺序：用户消息先存，助手回复定稿后存', () async {
      final service = _ManualService();
      final history = _RecordingHistory();
      final controller = ConversationController(service, repository: history);

      await controller.sendMessage('记录一下');
      expect(history.saved, hasLength(1));
      expect(history.saved.single.role, ConversationRole.user);
      expect(history.saved.single.text, '记录一下');

      service.calls.single.emit('好的');
      await service.calls.single.finish();
      await Future<void>.delayed(Duration.zero);

      expect(history.saved, hasLength(2));
      expect(history.saved.last.role, ConversationRole.assistant);
      expect(history.saved.last.text, '好的');
    });

    test('落库失败不吞对话：置 persistError，且只取一次', () async {
      final service = _ManualService();
      final controller = ConversationController(
        service,
        repository: _RecordingHistory(failSave: true),
      );

      await controller.sendMessage('存一下');

      expect(controller.state.messages, hasLength(2)); // 消息仍在屏幕上
      expect(controller.state.persistError, isNotNull);
      expect(controller.takePersistError(), isNotNull);
      expect(controller.takePersistError(), isNull);
    });

    test('上游报错后：重试可用，且就地复用错误气泡', () async {
      final service = _ManualService();
      final controller = ConversationController(service);

      await controller.sendMessage('你好');
      service.calls[0].fail(StateError('boom'));
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.status, ConversationStatus.error);
      expect(
        controller.state.messages.last.status,
        ConversationMessageStatus.error,
      );

      // 曾经被「status != idle」挡死（错误气泡上的重试是死按钮）。
      await controller.retryLast();

      expect(service.calls, hasLength(2));
      expect(service.calls[1].messages.single.text, '你好');
      service.calls[1].emit('又是我');
      await service.calls[1].finish();
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.messages, hasLength(2)); // 就地复用，不新增
      expect(controller.state.messages.last.text, '又是我');
      expect(controller.state.status, ConversationStatus.idle);
    });

    test('上游报错后直接发下一条也能发出去（错误态不是「进行中」）', () async {
      final service = _ManualService();
      final controller = ConversationController(service);

      await controller.sendMessage('第一条');
      service.calls[0].fail(StateError('boom'));
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.status, ConversationStatus.error);

      await controller.sendMessage('第二条');

      expect(service.calls, hasLength(2));
      expect(service.calls[1].messages.last.text, '第二条');
      expect(controller.state.status, ConversationStatus.sending);
    });

    test('落库窗口内取消：不发请求、移除占位、状态回 idle', () async {
      final service = _ManualService();
      final history = _SlowHistory();
      final controller = ConversationController(service, repository: history);

      final send = controller.sendMessage('在吗');
      // 此刻还在 await repository.save(...) 里（停止按钮已经可见）。
      expect(controller.state.messages, hasLength(2));
      expect(controller.isReplying, isTrue);

      await controller.cancel();

      expect(controller.state.status, ConversationStatus.idle);
      expect(controller.state.messages, hasLength(1));

      history.release();
      await send;
      expect(service.calls, isEmpty); // 取消后不再发起请求
    });

    test('取消：保留已生成的部分文本并落库，之后到达的分片丢弃', () async {
      final service = _ManualService();
      final history = _RecordingHistory();
      final controller = ConversationController(service, repository: history);

      await controller.sendMessage('讲个长故事');
      service.calls.single.emit('从前');
      await controller.cancel();

      final last = controller.state.messages.last;
      expect(last.text, '从前');
      expect(last.status, ConversationMessageStatus.sent);
      expect(controller.state.status, ConversationStatus.idle);
      expect(history.saved.last.text, '从前');

      // 取消后迟到的分片不能再改列表。
      service.calls.single.emit('有座山');
      expect(controller.state.messages.last.text, '从前');
    });

    test('取消：一个字都没生成时移除占位气泡', () async {
      final service = _ManualService();
      final controller = ConversationController(service);

      await controller.sendMessage('在吗');
      await controller.cancel();

      expect(controller.state.messages, hasLength(1));
      expect(controller.state.messages.single.role, ConversationRole.user);
      expect(controller.state.status, ConversationStatus.idle);
      expect(service.calls.single.cancelled, isTrue);
    });

    // 2026-10-16（S1，用户：「我的模型可以识图的」）：图片**随消息真的发出去**，
    // 请求文本不再写「图片未发送」——那句话现在是假的。
    test('请求上下文不含占位与失败气泡，图片消息如实带上图片说明', () async {
      final service = _ManualService();
      final controller = ConversationController(service);

      await controller.sendMessage('你好');
      service.calls[0].fail(StateError('boom'));
      await Future<void>.delayed(Duration.zero);

      await controller.sendMessage('再来');
      // 失败气泡不进上下文。
      expect(service.calls[1].messages, hasLength(2));
      expect(service.calls[1].messages.map((m) => m.text), ['你好', '再来']);

      service.calls[1].emit('好');
      await service.calls[1].finish();
      await Future<void>.delayed(Duration.zero);

      await controller.sendImageMessage(
        image: const ChatImage(
          path: '/docs/chat/photo_20261001_120000_ab12.jpg',
          fileName: 'photo_20261001_120000_ab12.jpg',
          width: 10,
          height: 10,
        ),
        caption: '这是午饭',
      );
      final turn = service.calls[2].messages.last;
      expect(turn.text, contains('附了一张图片'));
      expect(turn.text, isNot(contains('未发送')));
      expect(turn.text, contains('这是午饭'));
      expect(turn.kind, ConversationMessageKind.image);
      // 图本体跟着这条消息走（服务层据此读盘拼多模态块）。
      expect(turn.imagePath, isNotNull);
    });

    // 2026-10-31（用户：多张图片点击发送时要一起发送）：一次 sendImageBatch
    // 把 N 张图落成 N 条用户消息（schema 30 单图/条不动），但只有**一条** AI
    // 请求，且该请求带全部 N 张图——点一次发送全部出去，不再一张一张发。
    test('sendImageBatch：N 张图一次发送——N 条气泡、一条请求带全部图片', () async {
      final service = _ManualService();
      final controller = ConversationController(service);
      final images = [
        for (var i = 0; i < 3; i++)
          ChatImage(
            path: '/docs/chat/photo_$i.jpg',
            fileName: 'photo_$i.jpg',
            width: 10,
            height: 10,
          ),
      ];

      final sent = controller.sendImageBatch(
        images: images,
        caption: '这三张都是午饭',
      );
      await Future<void>.delayed(Duration.zero);

      // 一条请求，带全部三张图（各自的多模态块）。
      expect(service.calls, hasLength(1));
      final imageTurns = service.calls.single.messages
          .where((m) => m.kind == ConversationMessageKind.image)
          .toList();
      expect(imageTurns.map((m) => m.imagePath), [
        '/docs/chat/photo_0.jpg',
        '/docs/chat/photo_1.jpg',
        '/docs/chat/photo_2.jpg',
      ]);

      service.calls.single.emit('收到');
      await service.calls.single.finish();
      await sent;
      await Future<void>.delayed(Duration.zero);

      // 界面上 N 条用户气泡（每条一图），文字说明只挂第一条。
      final userBubbles = controller.state.messages
          .where((m) => m.role == ConversationRole.user)
          .toList();
      expect(userBubbles, hasLength(3));
      expect(userBubbles[0].text, '这三张都是午饭');
      expect(userBubbles[1].text, isEmpty);
      expect(userBubbles[2].text, isEmpty);
      for (var i = 0; i < 3; i++) {
        expect(userBubbles[i].kind, ConversationMessageKind.image);
        expect(userBubbles[i].imagePath, '/docs/chat/photo_$i.jpg');
      }
    });

    test('sendImageBatch：空列表不发请求、不动状态', () async {
      final service = _ManualService();
      final controller = ConversationController(service);
      await controller.sendImageBatch(images: const [], caption: 'x');
      expect(service.calls, isEmpty);
      expect(controller.state.messages, isEmpty);
      expect(controller.state.status, ConversationStatus.idle);
    });

    test('loadHistory：历史在前、本会话在后，同 id 不重复', () async {
      final service = _ManualService();
      final history = _RecordingHistory(
        initial: [
          _message('h1', '昨天晚饭'),
          _message('h2', '听起来不错', assistant: true),
        ],
      );
      final controller = ConversationController(service, repository: history);

      await controller.loadHistory();
      expect(controller.state.messages, hasLength(2));
      expect(controller.state.loadError, isNull);

      await controller.sendMessage('今天午饭');
      service.calls.single.emit('好的');
      await service.calls.single.finish();
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.messages, hasLength(4));

      // 再载一次：已在列表里的同 id 记录不能重复插入。
      await controller.loadHistory();

      expect(controller.state.messages, hasLength(4));
      expect(controller.state.messages.first.text, '昨天晚饭');
      expect(controller.state.messages.last.text, '好的');
    });

    test('loadHistory 失败：置 loadError，重试成功后清除', () async {
      final history = _RecordingHistory(failLoad: true);
      final controller = ConversationController(
        _ManualService(),
        repository: history,
      );

      await controller.loadHistory();
      expect(controller.state.loadError, isNotNull);
      expect(controller.state.messages, isEmpty);

      history.failLoad = false;
      history.initial = [_message('h1', '存档')];
      await controller.loadHistory();

      expect(controller.state.loadError, isNull);
      expect(controller.state.messages.single.text, '存档');
    });
  });

  // ── 通用编辑（docs/23）─────────────────────────────────────────────

  group('ConversationController · AI 对话通用编辑', () {
    final envelope =
        '{"reply":"好的，帮你记一笔。","edits":['
        '{"action":"water.add","args":{"amountMl":250}}]}';

    // 2026-10-24 多轮实测（RED→GREEN）：上一张卡还没点应用时，下一轮发送
    // 必须把「待应用提议」传给快照构建器。否则模型看不见那张卡，会对着
    // 用户说「等你先应用后我再改」——两轮才能做完一件事。
    test('有未应用卡片时，下一轮把 pendingProposal 传进快照', () async {
      final service = _ManualService();
      final builder = _FakeContextBuilder();
      final controller = ConversationController(
        service,
        chatEdit: ChatEditCoordinator(
          contextBuilder: builder,
          executor: _FakeExecutor(),
        ),
      );
      await controller.sendMessage('记 250ml 水');
      service.calls[0].emit(envelope);
      await service.calls[0].finish();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.messages[1].isEditProposal, isTrue);
      // 第一轮发送时还没有任何卡片。
      expect(builder.lastPendingProposal, isNull);

      await controller.sendMessage('改成 300 毫升');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      final pending = builder.lastPendingProposal;
      expect(pending, isNotNull, reason: '上一张卡还有待应用行，必须告诉模型（否则它会答「等你先应用」）');
      expect(pending!.commands.single.action, 'water.add');
      expect(pending.commands.single.args['amountMl'], 250.0);
      expect(pending.summary, '好的，帮你记一笔。');
    });

    test('卡片已全部应用后，下一轮不再传 pendingProposal', () async {
      final service = _ManualService();
      final builder = _FakeContextBuilder();
      final controller = ConversationController(
        service,
        chatEdit: ChatEditCoordinator(
          contextBuilder: builder,
          executor: _FakeExecutor(ok: true, message: '饮水已记录。'),
        ),
      );
      await controller.sendMessage('记 250ml 水');
      service.calls[0].emit(envelope);
      await service.calls[0].finish();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await controller.applyEdits(controller.state.messages[1].id);
      await Future<void>.delayed(Duration.zero);

      await controller.sendMessage('你好呀');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(
        builder.lastPendingProposal,
        isNull,
        reason: '没有待应用行了，就不该再提——否则模型会以为还有一张卡挂着',
      );
    });

    test('信封回复升格成编辑卡：text=reply，行可应用；纯文本不受影响', () async {
      final service = _ManualService();
      final coordinator = ChatEditCoordinator(
        contextBuilder: _FakeContextBuilder(),
        executor: _FakeExecutor(),
      );
      final controller = ConversationController(service, chatEdit: coordinator);
      await controller.sendMessage('记 250ml 水');
      service.calls[0].emit(envelope);
      await service.calls[0].finish();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.messages, hasLength(2));
      final editMessage = controller.state.messages[1];
      expect(editMessage.isEditProposal, isTrue);
      expect(editMessage.text, '好的，帮你记一笔。');
      expect(editMessage.editTurn!.rows.single.command!.action, 'water.add');

      await controller.sendMessage('你好呀');
      service.calls[1].emit('你好呀');
      await service.calls[1].finish();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.messages[3].isEditProposal, isFalse);
      expect(controller.state.messages[3].text, '你好呀');
    });

    test('applyEdits：逐条执行并回写结果，结果随消息落库', () async {
      final service = _ManualService();
      final executor = _FakeExecutor(ok: true, message: '饮水已记录。');
      final history = _RecordingHistory();
      final controller = ConversationController(
        service,
        repository: history,
        chatEdit: ChatEditCoordinator(
          contextBuilder: _FakeContextBuilder(),
          executor: executor,
        ),
      );
      await controller.sendMessage('记 250ml 水');
      service.calls[0].emit(envelope);
      await service.calls[0].finish();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      final messageId = controller.state.messages.last.id;

      await controller.applyEdits(messageId);

      expect(executor.received.single.action, 'water.add');
      final row = controller.state.messages.last.editTurn!.rows.single;
      expect(row.status, ChatEditRowStatus.applied);
      expect(row.resultMessage, '饮水已记录。');
      // 落库的是编码后的信封（含 outcomes），重启可还原
      expect(history.saved.last.editTurn, isNotNull);
    });

    test('选择卡重放：同名双库失败 → 改写引用后只重放该行', () async {
      final service = _ManualService();
      final executor = _ChooseCatalogExecutor();
      final controller = ConversationController(
        service,
        chatEdit: ChatEditCoordinator(
          contextBuilder: _FakeContextBuilder(),
          executor: executor,
        ),
      );
      const mealEnvelope =
          '{"reply":"帮你记午餐。","edits":[{"action":"meal.create",'
          '"args":{"slot":"午餐","items":[{"food":"米饭","grams":200}]}}]}';
      await controller.sendMessage('午餐吃了米饭');
      service.calls[0].emit(mealEnvelope);
      await service.calls[0].finish();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final messageId = controller.state.messages.last.id;
      await controller.applyEdits(messageId);
      final failed = controller.state.messages.last.editTurn!.rows.single;
      expect(failed.status, ChatEditRowStatus.failed);
      expect(failed.repair?.kind, ChatEditRepairKind.chooseCatalog);
      expect(executor.received, hasLength(1));
      expect(executor.received.single.args['items'], [
        {'food': '米饭', 'grams': 200.0},
      ]);

      await controller.retryEditRowWithReference(
        messageId: messageId,
        rowIndex: failed.index,
        originalReference: '米饭',
        newReference: '[dish:d1]',
      );

      expect(executor.received, hasLength(2), reason: '只重放这一行一次');
      final replayed = executor.received.last;
      expect(replayed.action, 'meal.create');
      expect(replayed.args['items'], [
        {'food': '[dish:d1]', 'grams': 200.0},
      ]);
      final row = controller.state.messages.last.editTurn!.rows.single;
      expect(row.status, ChatEditRowStatus.applied);
      expect(row.resultMessage, '已记录这一餐。');
    });

    test('applyEdits：执行失败逐条显示原因，不吞异常', () async {
      final service = _ManualService();
      final controller = ConversationController(
        service,
        chatEdit: ChatEditCoordinator(
          contextBuilder: _FakeContextBuilder(),
          executor: _FakeExecutor(ok: false, message: '目标不存在。'),
        ),
      );
      await controller.sendMessage('记 250ml 水');
      service.calls[0].emit(envelope);
      await service.calls[0].finish();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      await controller.applyEdits(controller.state.messages.last.id);
      final row = controller.state.messages.last.editTurn!.rows.single;
      expect(row.status, ChatEditRowStatus.failed);
      expect(row.resultMessage, '目标不存在。');
    });

    test('applyEdits 双击守卫：应用中再次点击不会重复执行', () async {
      final service = _ManualService();
      final executor = _SlowExecutor();
      final controller = ConversationController(
        service,
        chatEdit: ChatEditCoordinator(
          contextBuilder: _FakeContextBuilder(),
          executor: executor,
        ),
      );
      await controller.sendMessage('记 250ml 水');
      service.calls[0].emit(envelope);
      await service.calls[0].finish();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      final messageId = controller.state.messages.last.id;

      final first = controller.applyEdits(messageId);
      final second = controller.applyEdits(messageId);
      await Future.wait([first, second]);
      await Future<void>.delayed(Duration.zero);
      expect(executor.received, hasLength(1));
    });

    // 2026-10-16（用户：「对话中遇到问题要推荐回答并弹出可点选按钮」）。
    group('推荐按钮（suggestions）', () {
      const withSuggestion =
          '{"reply":"库里没有鸡肉，我可以先建它。","edits":['
          '{"action":"water.add","args":{"amountMl":250}}],'
          '"suggestions":[{"label":"创建食材「鸡肉」","action":"food.create",'
          '"args":{"name":"鸡肉","kcalPer100g":165,"proteinPer100g":31,'
          '"carbsPer100g":0,"fatPer100g":3.6}}]}';

      Future<ConversationController> open(
        ChatEditExecutor executor, {
        _RecordingHistory? history,
      }) async {
        final service = _ManualService();
        final controller = ConversationController(
          service,
          repository: history,
          chatEdit: ChatEditCoordinator(
            contextBuilder: _FakeContextBuilder(),
            executor: executor,
          ),
        );
        await controller.sendMessage('早餐吃个鸡蛋');
        service.calls[0].emit(withSuggestion);
        await service.calls[0].finish();
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        return controller;
      }

      test('点建议 = 应用那条命令；状态与结果就地回写并落库', () async {
        final history = _RecordingHistory();
        final executor = _FakeExecutor(ok: true, message: '食材已创建。');
        final controller = await open(executor, history: history);

        final turn = controller.state.messages.last.editTurn!;
        expect(turn.suggestions.single.label, '创建食材「鸡肉」');
        expect(turn.suggestions.single.status, ChatEditRowStatus.proposed);

        await controller.applySuggestion(controller.state.messages.last.id, 0);

        // 只跑被点的那一条（编辑卡上的 water.add 没被应用）。
        expect(executor.received.map((c) => c.action), ['food.create']);
        final after = controller.state.messages.last.editTurn!.suggestions;
        expect(after.single.status, ChatEditRowStatus.applied);
        expect(after.single.resultMessage, '食材已创建。');
        expect(
          history.saved.last.editTurn!.suggestions.single.status,
          ChatEditRowStatus.applied,
        );
      });

      test('点建议失败：状态失败 + 原因如实显示（不静默）', () async {
        final controller = await open(
          _FakeExecutor(ok: false, message: '同名食材已存在。'),
        );
        await controller.applySuggestion(controller.state.messages.last.id, 0);
        final suggestion =
            controller.state.messages.last.editTurn!.suggestions.single;
        expect(suggestion.status, ChatEditRowStatus.failed);
        expect(suggestion.resultMessage, '同名食材已存在。');
      });

      test('已应用的按钮再点不重复写（守卫）', () async {
        final executor = _FakeExecutor(ok: true, message: '食材已创建。');
        final controller = await open(executor);
        final messageId = controller.state.messages.last.id;
        await controller.applySuggestion(messageId, 0);
        await controller.applySuggestion(messageId, 0);
        // 只跑了一次：第二次点击被「已应用」挡下（不是双击守卫，是终态守卫）。
        expect(executor.received, hasLength(1));
      });

      test('applyEdits 之后建议仍在（重建轮次时不许丢）', () async {
        final controller = await open(_FakeExecutor());
        await controller.applyEdits(controller.state.messages.last.id);
        final turn = controller.state.messages.last.editTurn!;
        expect(turn.suggestions, hasLength(1));
        expect(turn.suggestions.single.label, '创建食材「鸡肉」');
      });

      test('执行失败带缺食材提示 → 行上挂「创建食材」修复动作', () async {
        const missing =
            '{"reply":"鸡肉不在库里。","edits":['
            '{"action":"meal.create","args":{"slot":"早餐","items":['
            '{"food":"鸡肉","grams":100}]}}]}';
        final service = _ManualService();
        final controller = ConversationController(
          service,
          chatEdit: ChatEditCoordinator(
            contextBuilder: _FakeContextBuilder(),
            executor: _RepairingExecutor(),
          ),
        );
        await controller.sendMessage('早餐吃了鸡肉');
        service.calls[0].emit(missing);
        await service.calls[0].finish();
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        await controller.applyEdits(controller.state.messages.last.id);
        final row = controller.state.messages.last.editTurn!.rows.single;
        expect(row.status, ChatEditRowStatus.failed);
        expect(row.repair?.name, '鸡肉');
      });
    });

    test('dismissEdits：全部提议置为已忽略并落库', () async {
      final service = _ManualService();
      final history = _RecordingHistory();
      final controller = ConversationController(
        service,
        repository: history,
        chatEdit: ChatEditCoordinator(
          contextBuilder: _FakeContextBuilder(),
          executor: _FakeExecutor(),
        ),
      );
      await controller.sendMessage('记 250ml 水');
      service.calls[0].emit(envelope);
      service.calls[0].finish();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      await controller.dismissEdits(controller.state.messages.last.id);
      final row = controller.state.messages.last.editTurn!.rows.single;
      expect(row.status, ChatEditRowStatus.dismissed);
      expect(history.saved.last.editTurn!.hasProposed, isFalse);
    });

    test('systemContext 每次发送都注入（协议+快照）', () async {
      final service = _ManualService();
      final controller = ConversationController(
        service,
        chatEdit: ChatEditCoordinator(
          contextBuilder: _FakeContextBuilder(payload: 'SNAPSHOT'),
          executor: _FakeExecutor(),
        ),
      );
      await controller.sendMessage('在吗');
      service.calls[0].emit('嗯');
      await service.calls[0].finish();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(service.lastSystemContext, contains('SNAPSHOT'));
      expect(service.lastSystemContext, contains('water.add'));
    });

    // ── 2026-10-16 用户要求：「对话只要涉及让你修改，就必须正确识别指令，
    // 而不是空回文字」——模型把修改请求当闲聊回文字时，App 要**催一次信封**。
    group('修改意图的自动补救（信封重试）', () {
      ConversationController build(
        AiConversationService service, {
        _FakeContextBuilder? builder,
        _RecordingHistory? history,
      }) => ConversationController(
        service,
        repository: history,
        chatEdit: ChatEditCoordinator(
          contextBuilder: builder ?? _FakeContextBuilder(payload: 'SNAPSHOT'),
          executor: _FakeExecutor(),
        ),
      );

      Future<void> settleTwo() async {
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
      }

      test('修改请求 + 模型只回文字 ⇒ 自动重跑一次并带上「必须出信封」提示', () async {
        final service = _ManualService();
        final controller = build(service);
        await controller.sendMessage('帮我加一个鸡蛋');
        expect(service.calls, hasLength(1));
        service.calls[0].emit('好的，我建议你早上吃个鸡蛋，营养不错。');
        await service.calls[0].finish();
        await settleTwo();

        // 第二次请求：同一段历史（不新增用户气泡）＋提示段。
        expect(service.calls, hasLength(2), reason: '修改请求没出信封要催一次');
        expect(service.calls[1].messages, hasLength(1), reason: '重跑不新增用户消息');
        expect(service.lastSystemContext, contains('修改数据的请求'));

        service.calls[1].emit(
          '{"reply":"帮你记一个鸡蛋。","edits":[{"action":"food.create",'
          '"args":{"name":"鸡蛋","kcalPer100g":144,"proteinPer100g":13.3,'
          '"carbsPer100g":2.8,"fatPer100g":8.8}}]}',
        );
        await service.calls[1].finish();
        await settleTwo();

        final messages = controller.state.messages;
        // 2026-11-06 用户：「补信封不要给我显示出来」。补跑拿到信封后把
        // 编辑卡并回首轮气泡，补跑气泡删除；屏幕上只有一条助手回复 + 卡。
        expect(messages, hasLength(2), reason: '用户 + 首轮（已并入编辑卡）');
        expect(messages[1].isEditProposal, isTrue, reason: '编辑卡并在首轮气泡上');
        expect(messages[1].text, '帮你记一个鸡蛋。');
        expect(
          controller.state.messages.where((m) => m.id != messages[1].id),
          hasLength(1),
          reason: '补跑气泡不能再出现在列表里',
        );
      });

      test('非修改请求（闲聊/提问）只跑一次，不催信封', () async {
        for (final text in const ['你好呀', '今天晚餐怎么搭配？', '我可以吃吗？']) {
          final service = _ManualService();
          final controller = build(service);
          await controller.sendMessage(text);
          service.calls[0].emit('随便聊聊就好。');
          await service.calls[0].finish();
          await settleTwo();
          expect(service.calls, hasLength(1), reason: '「$text」不该催信封');
        }
      });

      // 【2026-10-27 升级（用户：AI 对话经常不弹应用卡片，要更强制性的保证）】
      // 原来这条钉「每轮最多催一次」——第二次失败就把负担交还给用户（手点
      // 「让 AI 给出可应用的修改」）。升级后：第二次自动催**自动改用加强版
      // 提示**（引用模型上一条回复原文，设备实测最强的那把），仍失败才给
      // 残留手动词条。自动催总量有界：每条用户消息最多 2 次。
      test('重跑仍回散文 ⇒ 第二次自动催自动改用加强版提示；再失败才停（残留手动词条）', () async {
        final service = _ManualService();
        final controller = build(service);
        await controller.sendMessage('帮我记一笔饮水 250 毫升');
        service.calls[0].emit('好的呀。');
        await service.calls[0].finish();
        await settleTwo();
        service.calls[1].emit('我先看看你的目标。');
        await service.calls[1].finish();
        await settleTwo();

        // 第 2 次自动催：加强版提示自动发出（不用用户手点），并引用上一条回复。
        expect(service.calls, hasLength(3), reason: '第一次催失败要自动升级到加强版再催一次');
        expect(
          service.calls[2].systemContext,
          contains('让 AI 给出可应用的修改'),
          reason: '第 2 次自动催用加强版提示（原来只有手点才用）',
        );
        expect(
          service.calls[2].systemContext,
          contains('我先看看你的目标。'),
          reason: '加强版提示要引用模型上一条回复原文',
        );

        // 第 3 次仍是散文 ⇒ 停止自动催（有界），残留给手动词条。
        service.calls[2].emit('还是不太确定。');
        await service.calls[2].finish();
        await settleTwo();
        expect(service.calls, hasLength(3), reason: '有界：每条用户消息最多自动催 2 次');
        final assistant = controller.state.messages.last;
        // 补跑气泡全部丢弃：用户 + 首轮散文 = 2 条；首轮恢复手动词条。
        expect(controller.state.messages, hasLength(2), reason: '补信封不显示');
        expect(assistant.text, '好的呀。', reason: '只保留首轮回复，不展示两次补跑的文字');
        expect(assistant.isEditProposal, isFalse);
        expect(
          controller.needsEnvelopeRetry(assistant.id),
          isTrue,
          reason: '最终仍没信封：首轮挂手动词条，让用户自己决定要不要重试',
        );
      });

      test('回复声称改了数据却没信封（用户话没过保守门）⇒ 也自动升级催', () async {
        final service = _ManualService();
        final controller = build(service);
        // 「芒果」两个字不过「修改请求」保守门（宁漏勿误的既有口径不变）；
        // 但模型的散文**声称已经改了数据**却没带信封 —— docs/24 记录过的
        // 真实失败模式（「已在你的忌口清单里加入芒果」，其实什么都没写）。
        // 这是比用户措辞更精确的失败信号：回复侧也要触发升级催。
        await controller.sendMessage('芒果');
        expect(service.calls, hasLength(1));
        service.calls[0].emit('已把芒果加入你的忌口清单。');
        await service.calls[0].finish();
        await settleTwo();

        expect(service.calls, hasLength(2), reason: '声称改了数据却没信封 = 明确失败，自动升级催');
        expect(
          service.calls[1].systemContext,
          contains('让 AI 给出可应用的修改'),
          reason: '升级催直接用加强版提示（跳过标准提示那一档）',
        );
        expect(
          service.calls[1].systemContext,
          contains('已把芒果加入你的忌口清单。'),
          reason: '加强版提示引用模型上一条回复原文',
        );
      });

      test('纯问句/闲聊 + 老实的散文回复：不催（升级触发器不许误伤）', () async {
        for (final entry in const [
          ('我可以吃芒果吗？', '可以，芒果的热量不高。'),
          ('你好呀', '你好！今天想聊点什么？'),
          ('芒果', '芒果是热带水果，富含维生素 C。'),
        ]) {
          final service = _ManualService();
          final controller = build(service);
          await controller.sendMessage(entry.$1);
          service.calls[0].emit(entry.$2);
          await service.calls[0].finish();
          await settleTwo();
          expect(
            service.calls,
            hasLength(1),
            reason: '「${entry.$1}」+「${entry.$2}」不是失败，不许多花一次请求',
          );
        }
      });

      test('手动催（requestEnvelope）：再跑一次，并**引用上一条回复**要求逐条转会信封', () async {
        final service = _ManualService();
        final controller = build(service);
        // 用非修改请求隔离手动路径（不触发自动催，调用序列稳定）。
        await controller.sendMessage('你好');
        service.calls[0].emit('我先看看你的目标。');
        await service.calls[0].finish();
        await settleTwo();
        expect(service.calls, hasLength(1));

        final assistantId = controller.state.messages.last.id;
        await controller.requestEnvelope(assistantId);
        expect(service.calls, hasLength(2), reason: '手动催要真的再发一次');
        expect(
          service.lastSystemContext,
          contains('让 AI 给出可应用的修改'),
          reason: '手动催要说明这是用户点的',
        );
        expect(
          service.lastSystemContext,
          contains('我先看看你的目标。'),
          reason: '要把模型上一条回复原文引进去（对着自己的话更难再写散文）',
        );

        service.calls[1].emit(
          '{"reply":"记好了。","edits":[{"action":"water.add",'
          '"args":{"amountMl":250}}]}',
        );
        await service.calls[1].finish();
        await settleTwo();
        expect(controller.state.messages.last.isEditProposal, isTrue);
        expect(controller.needsEnvelopeRetry(assistantId), isFalse);
      });

      test('重启后仍能识别残留：最后一条纯文本 + 上面是修改请求 ⇒ 也给手动词条', () async {
        // 内存标记不落库，但「用户说了修改请求、助手只回文字」这两条消息
        // 本身在库里——重启后据此重算，用户不必再打一遍。
        final history = _RecordingHistory();
        final service = _ManualService();
        final controller = build(service, history: history);
        await controller.sendMessage('帮我加一个鸡蛋');
        service.calls[0].emit('早上吃个鸡蛋挺好的。');
        await service.calls[0].finish();
        await settleTwo();
        service.calls[1].emit('我还是先说个建议。');
        await service.calls[1].finish();
        await settleTwo();

        // 模拟重启：新控制器载入同一段历史（内存标记自然是空的）。
        // 假仓储的 `loadRecent` 返回的是 `initial`（它只记录写），所以把
        // 刚才落库的两条搬进 `initial` 来复现「重启后从库里读回来」。
        history.initial = List.of(history.saved);
        final restarted = _ManualService();
        final reopened = ConversationController(
          restarted,
          repository: history,
          chatEdit: ChatEditCoordinator(
            contextBuilder: _FakeContextBuilder(),
            executor: _FakeExecutor(),
          ),
        );
        await reopened.loadHistory();
        await settleTwo();
        final last = reopened.state.messages.last;
        expect(
          reopened.needsEnvelopeRetry(last.id),
          isTrue,
          reason: '重启后也要能识别「修改请求只拿到文字」的残留',
        );
        // 更早的纯文本消息不算残留（避免历史里到处是词条）。
        final first = reopened.state.messages.firstWhere(
          (m) => m.role == ConversationRole.user,
        );
        expect(reopened.needsEnvelopeRetry(first.id), isFalse);
      });

      test('未接线（chatEdit=null）时不催信封，行为与旧版一致', () async {
        final service = _ManualService();
        final controller = ConversationController(service);
        await controller.sendMessage('帮我加一个鸡蛋');
        service.calls[0].emit('好呀。');
        await service.calls[0].finish();
        await settleTwo();
        expect(service.calls, hasLength(1));
      });

      // 【2026-11-02 用户实机】AI 回复「点应用后才会保存」，屏幕上却根本没有
      // 编辑卡——模型把一张不存在的卡当成事实。旧逻辑只看「用户这句话像不像
      // 修改请求」；这条用户话是「点应用后记得告诉我保存好了」，不过保守门，
      // 于是残留态永远不出现，用户只看到一段让人去找卡的散文。
      test('回复引用「点应用」但对话里没有待应用卡 ⇒ 自动升级催 + 兜底卡', () async {
        final service = _ManualService();
        final controller = build(service);
        await controller.sendMessage('点应用后记得告诉我保存好了。');
        service.calls[0].emit('好的，收到。等你点了「应用」后，这条酸奶（每100g 74 kcal）就会正式保存到食物库。');
        await service.calls[0].finish();
        await settleTwo();

        expect(service.calls, hasLength(2), reason: '引用了不存在的「应用」卡 ⇒ 必须自动催一次信封');
        expect(
          service.calls[1].systemContext,
          contains('让 AI 给出可应用的修改'),
          reason: '幻影卡是回复侧信号，直接走加强版提示',
        );
        expect(
          service.calls[1].systemContext,
          contains('「应用」后'),
          reason: '加强版提示引用模型原话，让它把自己说的卡补出来',
        );

        // 重跑仍是散文 ⇒ 残留标在新气泡上，页面据此画兜底卡。
        service.calls[1].emit('这条已经保存好了。');
        await service.calls[1].finish();
        await settleTwo();
        final last = controller.state.messages.last;
        expect(last.isEditProposal, isFalse);
        expect(
          controller.needsEnvelopeRetry(last.id),
          isTrue,
          reason: '没有卡却让用户去点应用 ⇒ 必须给可恢复的兜底卡',
        );
      });

      test('对话里已有待应用卡时，回复提到「应用」不误催', () async {
        final service = _ManualService();
        final controller = build(service);
        await controller.sendMessage('帮我加一个鸡蛋');
        service.calls[0].emit(
          '{"reply":"准备记一个鸡蛋。","edits":[{"action":"food.create",'
          '"args":{"name":"鸡蛋","kcalPer100g":144,"proteinPer100g":13.3,'
          '"carbsPer100g":2.8,"fatPer100g":8.8}}]}',
        );
        await service.calls[0].finish();
        await settleTwo();
        expect(controller.state.messages.last.isEditProposal, isTrue);

        await controller.sendMessage('点应用后记得告诉我保存好了。');
        service.calls[1].emit('好的，点「应用」后我会告诉你结果。');
        await service.calls[1].finish();
        await settleTwo();
        expect(
          service.calls,
          hasLength(2),
          reason: '屏幕上确实有一张待应用卡时，这句话是正常对话，不许再催',
        );
      });

      // 【2026-11-02 用户实机】「AI 不给我生成应用卡片，而是一直在重复要不要
      // 生成的段落」。根因：计划类动词（生成/安排/制定/规划/配/排）不在修改
      // 动词表里 ⇒ 用户请求判 false ⇒ 永不催信封；模型一句「要不要我帮你生成」
      // 就能无限循环。
      test('计划类请求 + 模型反问「要不要生成」⇒ 识别为修改请求并专门催信封', () async {
        for (final userText in const [
          '帮我生成今天的饮食计划',
          '生成一份训练计划',
          '帮我安排今天的三餐',
          '制定一个减脂计划',
        ]) {
          expect(
            looksLikeModificationRequest(userText),
            isTrue,
            reason: '「$userText」是明确的计划请求，不能判成闲聊',
          );
        }

        final service = _ManualService();
        final controller = build(service);
        await controller.sendMessage('帮我生成今天的饮食计划');
        service.calls[0].emit('要不要我帮你生成一份今天的饮食计划？');
        await service.calls[0].finish();
        await settleTwo();

        expect(
          service.calls,
          hasLength(2),
          reason: '反问「要不要生成」必须触发催信封，而不是把问题抛回用户',
        );
        expect(
          service.calls[1].systemContext,
          contains('不要再问一遍'),
          reason: '这类失败要用专门的「不许反问」提示，而不是通用加强版',
        );
        expect(
          service.calls[1].systemContext,
          contains('要不要我帮你生成'),
          reason: '提示要引用模型原话',
        );

        service.calls[1].emit(
          '{"reply":"给你排好了今天的三餐。","edits":[{"action":"meal.create",'
          '"args":{"slot":"breakfast","items":[{"food":"鸡蛋","grams":50}]}}]}',
        );
        await service.calls[1].finish();
        await settleTwo();
        expect(
          controller.state.messages.last.isEditProposal,
          isTrue,
          reason: '重跑拿到信封 ⇒ 出应用卡',
        );
      });

      test('反问「要不要生成」但没有修改意图的闲聊不误催', () async {
        final service = _ManualService();
        final controller = build(service);
        await controller.sendMessage('你好呀');
        service.calls[0].emit('要不要我帮你生成一份饮食计划？');
        await service.calls[0].finish();
        await settleTwo();
        expect(
          service.calls,
          hasLength(2),
          reason: '「要不要生成」本身是明确的失败信号，即使前面是闲聊也值得催一次',
        );
      });

      // 【2026-11-02 用户实机】「过一会又会自动接着回复，一直不停；我自己
      // 暂停后就会出现 AI 说改好了、但没有给出可执行操作」。
      // 根因：自动催的每条重跑都是一条新助手气泡（首轮 + 两次催 = 屏幕三
      // 段重复文字），且用户点停止后 pending 被清空、残留标记留在最后一条
      // 气泡上 ⇒ 暂停反而弹出兜底卡。
      test('信封编译器：散文首轮 → 强制 JSON 编译 → 出卡，不再整轮重跑', () async {
        final service = _CompilingService();
        final controller = build(service);
        await controller.sendMessage('帮我记录这顿饭');
        // 故意不带克数清单：散文抢救不接管，必须走「强制 JSON 编译」。
        service.sendCalls[0].emit('我准备把这份记为今天的午餐，点应用后生效。');
        await service.sendCalls[0].finish();
        await settleTwo();

        expect(
          controller.state.messages,
          hasLength(3),
          reason: '应先出现一条隐藏的重跑气泡',
        );
        expect(service.compileCalls, hasLength(1), reason: '应走强制 JSON 编译');
        expect(service.compileCalls[0].userText, '帮我记录这顿饭');
        expect(
          service.compileCalls[0].assistantReply,
          contains('记为今天的午餐'),
          reason: '编译器输入必须是助手刚才的散文',
        );
        expect(
          service.compileCalls[0].systemContext,
          contains('meal.create'),
          reason: '编译请求仍带协议与快照',
        );

        service.compileCalls[0].emit(
          '{"reply":"记好了。","edits":[{"action":"meal.create",'
          '"args":{"slot":"lunch","items":[{"food":"红米饭","grams":150},'
          '{"food":"鸡胸肉","grams":120}]}}]}',
        );
        await service.compileCalls[0].finish();
        await settleTwo();

        final last = controller.state.messages.last;
        expect(last.isEditProposal, isTrue, reason: '编译出的信封要变成编辑卡');
        expect(service.sendCalls, hasLength(1), reason: '不许再整轮重跑');
      });

      test('模型只回「记餐提案」散文：本地抢救成编辑卡，不再催第二次', () async {
        final service = _ManualService();
        final controller = build(service);
        await controller.sendMessage('帮我记录这顿饭');
        service.calls[0].emit(
          '我准备把这份记为今天的午餐：红油豆腐粉（豆腐+金针菇+粉条）400g、'
          '白米饭（熟）150g，份量按这一碗的常见大小估算。点「应用」后生效，'
          '克数有出入告诉我再改。',
        );
        await service.calls[0].finish();
        await settleTwo();

        expect(
          service.calls,
          hasLength(1),
          reason: '散文已经能抢救成卡片，就不该再自动催一次（用户看到的是「自动接话」）',
        );
        final last = controller.state.messages.last;
        expect(last.isEditProposal, isTrue, reason: '必须弹出可应用的记餐卡');
        final command = last.editTurn!.rows.single.command!;
        expect(command.action, 'meal.create');
        expect(command.args['slot'], 'lunch');
        final items = command.args['items']! as List<Object>;
        expect(items, hasLength(2));
      });

      test('自动补跑不追加气泡；拿到信封后并回首轮，补跑气泡不显示', () async {
        final service = _ManualService();
        final history = _RecordingHistory();
        final controller = build(service, history: history);
        await controller.sendMessage('帮我记一笔饮水 250 毫升');
        service.calls[0].emit('好的呀。');
        await service.calls[0].finish();
        await settleTwo();
        expect(service.calls, hasLength(2));

        // 第 1 次催的中间气泡：已创建但页面应隐藏它。
        final middle = controller.state.messages.last;
        expect(
          controller.isHiddenRetryBubble(middle.id),
          isTrue,
          reason: '自动补跑的中间气泡必须隐藏',
        );
        expect(
          history.saved.where((m) => m.id == middle.id),
          isEmpty,
          reason: '中间气泡不许落库',
        );

        service.calls[1].emit(
          '{"reply":"记好了。","edits":[{"action":"water.add",'
          '"args":{"amountMl":250}}]}',
        );
        await service.calls[1].finish();
        await settleTwo();
        // 补跑气泡已删除，编辑卡并在首轮气泡上。
        expect(controller.state.messages, hasLength(2));
        final merged = controller.state.messages.last;
        expect(merged.id, isNot(middle.id));
        expect(merged.isEditProposal, isTrue);
        expect(merged.text, '记好了。');
        final saved = history.saved.where((m) => m.id == merged.id).toList();
        expect(saved, isNotEmpty, reason: '编辑卡要落库（并在首轮消息上）');
        expect(saved.last.isEditProposal, isTrue);
      });

      test('在自动催的中间气泡上按停止：气泡移除，不留半截回复', () async {
        final service = _ManualService();
        final controller = build(service);
        await controller.sendMessage('帮我加一个鸡蛋');
        service.calls[0].emit('好的呀。');
        await service.calls[0].finish();
        await settleTwo();
        expect(service.calls, hasLength(2));
        expect(controller.state.messages, hasLength(3)); // 用户 + 首轮 + 隐藏气泡
        service.calls[1].emit('我准备记为…');
        await settleTwo();
        await controller.cancel();
        await settleTwo();

        expect(
          controller.state.messages,
          hasLength(2),
          reason: '取消自动催的中间气泡 = 移除它，不能把半截文字露出来',
        );
        expect(controller.state.messages.last.text, '好的呀。');
        expect(
          controller.needsEnvelopeRetry(controller.state.messages.last.id),
          isFalse,
          reason: '用户主动停止不弹兜底卡',
        );
      });

      test('自动催重跑失败：错误气泡要露出来，不能静默消失', () async {
        final service = _ManualService();
        final controller = build(service);
        await controller.sendMessage('帮我加一个鸡蛋');
        service.calls[0].emit('好的呀。');
        await service.calls[0].finish();
        await settleTwo();
        expect(service.calls, hasLength(2));
        service.calls[1].fail(StateError('boom'));
        await settleTwo();

        final last = controller.state.messages.last;
        expect(
          controller.isHiddenRetryBubble(last.id),
          isFalse,
          reason: '重跑失败必须让用户看到错误，不能继续藏着',
        );
        expect(last.status, ConversationMessageStatus.error);
      });

      test('用户点停止后：不再自动催信封，也不弹「没有可执行操作」兜底卡', () async {
        final service = _ManualService();
        final controller = build(service);
        await controller.sendMessage('帮我加一个鸡蛋');
        service.calls[0].emit('我正在想…');
        await settleTwo();
        // 用户按停止（这一轮还在流式输出）。
        await controller.cancel();
        await settleTwo();

        expect(
          service.calls,
          hasLength(1),
          reason: '取消后不许再自动催信封（那是「自动接着回复」的来源）',
        );
        final last = controller.state.messages.last;
        expect(
          controller.needsEnvelopeRetry(last.id),
          isFalse,
          reason: '用户主动停止 ≠ AI 失败，不该弹兜底卡',
        );
      });
    });

    test('未接线（chatEdit=null）时不产生编辑卡，也不把 JSON 亮给用户', () async {
      final service = _ManualService();
      final controller = ConversationController(service);
      await controller.sendMessage('记 250ml 水');
      service.calls[0].emit(envelope);
      await service.calls[0].finish();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.messages.last.isEditProposal, isFalse);
      // 2026-10-24：原先是「信封原样显示」（用户实测看到的就是这串英文代码
      // 片段）。未接线时没有执行通道，所以不产卡；文本仍要给人话。
      expect(
        controller.state.messages.last.text,
        kMalformedEnvelopeNotice,
        reason: '未接线的信封残留必须换成人话，不把 JSON 当回复上屏',
      );
    });

    test('快照构建失败只降级本次发送，不炸对话', () async {
      final service = _ManualService();
      final controller = ConversationController(
        service,
        chatEdit: ChatEditCoordinator(
          contextBuilder: _FakeContextBuilder(throws: true),
          executor: _FakeExecutor(),
        ),
      );
      await controller.sendMessage('在吗');
      service.calls[0].emit('嗯');
      await service.calls[0].finish();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(service.lastSystemContext, isNull);
      expect(controller.state.status, ConversationStatus.idle);
    });
  });
}

// ── 替身 ───────────────────────────────────────────────────────────────

ConversationMessage _message(
  String id,
  String text, {
  bool assistant = false,
}) => ConversationMessage(
  id: id,
  role: assistant ? ConversationRole.assistant : ConversationRole.user,
  text: text,
  createdAt: DateTime.utc(2026, 9, 30, 12),
  status: ConversationMessageStatus.sent,
);

/// 手动驱动的服务：测试自己决定何时出分片、何时收尾。
final class _ManualService implements AiConversationService {
  final List<_ManualCall> calls = [];

  /// 最近一次请求的 systemContext（docs/23 §3 注入验证用）。
  String? lastSystemContext;

  @override
  Stream<String> sendMessage({
    required List<ConversationMessage> messages,
    required void Function(String chunk) onProgress,
    Stream<void>? cancelToken,
    String? systemContext,
  }) {
    lastSystemContext = systemContext;
    final call = _ManualCall(
      messages: messages,
      onProgress: onProgress,
      systemContext: systemContext,
      cancelToken: cancelToken,
    );
    calls.add(call);
    return call.stream;
  }
}

final class _ManualCall {
  _ManualCall({
    required this.messages,
    required this.onProgress,
    this.systemContext,
    Stream<void>? cancelToken,
  }) {
    // 控制器取消时会关掉 cancelToken —— 这就是「请求被取消」的契约。
    cancelToken?.listen((_) {}, onDone: () => cancelled = true);
  }

  final List<ConversationMessage> messages;
  final void Function(String chunk) onProgress;

  /// 这一次请求收到的 systemContext（信封升级梯子要逐次对比提示档位）。
  final String? systemContext;
  final StreamController<String> _controller = StreamController<String>();
  bool cancelled = false;

  Stream<String> get stream => _controller.stream;

  void emit(String chunk) {
    onProgress(chunk);
    _controller.add(chunk);
  }

  void fail(Object error) => _controller.addError(error);

  Future<void> finish() => _controller.close();
}

/// 同时实现对话与信封编译的服务：用于验证「强制 JSON 编译」路径。
final class _CompilingService
    implements AiConversationService, AiEnvelopeCompiler {
  final List<_ManualCall> sendCalls = [];
  final List<_CompileCall> compileCalls = [];

  @override
  Stream<String> sendMessage({
    required List<ConversationMessage> messages,
    required void Function(String chunk) onProgress,
    Stream<void>? cancelToken,
    String? systemContext,
  }) {
    final call = _ManualCall(
      messages: messages,
      onProgress: onProgress,
      systemContext: systemContext,
      cancelToken: cancelToken,
    );
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
    final call = _CompileCall(
      userText: userText,
      assistantReply: assistantReply,
      systemContext: systemContext,
      onProgress: onProgress,
      cancelToken: cancelToken,
      conversationContext: conversationContext,
      targetLocalDate: targetLocalDate,
    );
    compileCalls.add(call);
    return call.stream;
  }
}

final class _CompileCall {
  _CompileCall({
    required this.userText,
    required this.assistantReply,
    required this.systemContext,
    required this.onProgress,
    Stream<void>? cancelToken,
    this.conversationContext = '',
    this.targetLocalDate = '',
  }) {
    cancelToken?.listen((_) {}, onDone: () => cancelled = true);
  }

  final String userText;
  final String assistantReply;
  final String systemContext;

  /// docs/66 §5.2：手动编译传进的最近对话与目标日期（旧路径恒为空串）。
  final String conversationContext;
  final String targetLocalDate;
  final void Function(String chunk) onProgress;
  final StreamController<String> _controller = StreamController<String>();
  bool cancelled = false;

  Stream<String> get stream => _controller.stream;

  void emit(String chunk) {
    onProgress(chunk);
    _controller.add(chunk);
  }

  Future<void> finish() => _controller.close();
}

/// 内存聊天记录：可控制读/写失败，记录每一次保存。
final class _RecordingHistory implements ConversationMessageRepository {
  _RecordingHistory({
    this.initial = const [],
    this.failLoad = false,
    this.failSave = false,
  });

  List<ConversationMessage> initial;
  bool failLoad;
  bool failSave;
  final List<ConversationMessage> saved = [];

  @override
  Future<List<ConversationMessage>> loadRecent({
    String sessionId = ConversationMessageRepository.defaultSessionId,
    int limit = 200,
  }) async {
    if (failLoad) throw StateError('history unavailable');
    return initial;
  }

  @override
  Future<void> save(
    ConversationMessage message, {
    String sessionId = ConversationMessageRepository.defaultSessionId,
  }) async {
    if (failSave) throw StateError('disk full');
    saved.add(message);
  }

  @override
  Future<int> clear({
    String sessionId = ConversationMessageRepository.defaultSessionId,
  }) async {
    final before = initial.length;
    initial = [];
    saved.clear();
    return before;
  }
}

/// 保存挂起的仓储：用来把测试停在「落库窗口」里。
final class _SlowHistory implements ConversationMessageRepository {
  final Completer<void> _gate = Completer<void>();
  final List<ConversationMessage> saved = [];

  void release() {
    if (!_gate.isCompleted) _gate.complete();
  }

  @override
  Future<List<ConversationMessage>> loadRecent({
    String sessionId = ConversationMessageRepository.defaultSessionId,
    int limit = 200,
  }) async => const [];

  @override
  Future<void> save(
    ConversationMessage message, {
    String sessionId = ConversationMessageRepository.defaultSessionId,
  }) async {
    await _gate.future;
    saved.add(message);
  }

  @override
  Future<int> clear({
    String sessionId = ConversationMessageRepository.defaultSessionId,
  }) async {
    final before = saved.length;
    saved.clear();
    return before;
  }
}

class _FakeContextBuilder implements ChatEditContextBuilder {
  _FakeContextBuilder({this.payload = '【当前可编辑数据快照】测试', this.throws = false});

  final String payload;
  final bool throws;

  /// 最近一次收到的待应用提议（2026-10-24：钉「控制器真的把它传下去了」）。
  PendingProposal? lastPendingProposal;

  @override
  Future<String> build({
    String? userMessage,
    PendingProposal? pendingProposal,
    String? foodQuery,
  }) async {
    if (throws) throw StateError('boom');
    lastPendingProposal = pendingProposal;
    return payload;
  }
}

class _FakeExecutor implements ChatEditExecutor {
  _FakeExecutor({this.ok = true, this.message = '已完成'});

  final bool ok;
  final String message;
  final List<ChatEditCommand> received = [];

  @override
  Future<ChatEditApplyResult> apply(ChatEditCommand command) async {
    received.add(command);
    return ok
        ? ChatEditApplyResult.ok(message)
        : ChatEditApplyResult.failure(message);
  }
}

/// 第一次报「同名双库」并带选择修复，第二次（用户选完后）成功。
class _ChooseCatalogExecutor implements ChatEditExecutor {
  final List<ChatEditCommand> received = [];

  @override
  Future<ChatEditApplyResult> apply(ChatEditCommand command) async {
    received.add(command);
    if (received.length == 1) {
      return const ChatEditApplyResult.failure(
        '「米饭」在食物库和菜品库都有；请说明按食物还是按菜品记。',
        repair: ChatEditRepair.chooseCatalog(name: '米饭'),
      );
    }
    return const ChatEditApplyResult.ok('已记录这一餐。');
  }
}

/// 带「缺食材」修复提示的执行器（1.5 的行级修复动作测试用）。
class _RepairingExecutor implements ChatEditExecutor {
  final List<ChatEditCommand> received = [];

  @override
  Future<ChatEditApplyResult> apply(ChatEditCommand command) async {
    received.add(command);
    return ChatEditApplyResult.failure(
      '找不到食材「鸡肉」。',
      repair: const ChatEditRepair.createFood(name: '鸡肉'),
    );
  }
}

/// 应用挂起的执行器：双击守卫测试用。
class _SlowExecutor implements ChatEditExecutor {
  final List<ChatEditCommand> received = [];

  @override
  Future<ChatEditApplyResult> apply(ChatEditCommand command) async {
    received.add(command);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    return ChatEditApplyResult.ok('ok');
  }
}
