import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/errors/app_failure.dart';
import 'package:localfit_ai/features/ai_conversation/application/conversation_controller.dart';
import 'package:localfit_ai/features/ai_conversation/domain/ai_conversation_service.dart';
import 'package:localfit_ai/features/ai_conversation/application/chat_edit_coordinator.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_command.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_context_builder.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_executor.dart';
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
      final service = FakeConversationService(responses: ['Hello world']);
      final controller = ConversationController(service);

      final completer = Completer<void>();
      controller.addListener(() {
        if (controller.state.messages.length == 2 &&
            controller.state.messages[1].text == 'Hello world') {
          completer.complete();
        }
      });

      await controller.sendMessage('Hi');
      await completer.future;

      expect(controller.state.messages[1].text, 'Hello world');
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
        _ManualService service, {
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
        expect(messages, hasLength(2), reason: '用户气泡 + 助手气泡');
        expect(messages[1].isEditProposal, isTrue, reason: '重跑拿到了信封 ⇒ 出编辑卡');
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

      test('重跑仍只回文字：最多两次请求，文字如实上屏并标记「可手动催」', () async {
        final service = _ManualService();
        final controller = build(service);
        await controller.sendMessage('帮我记一笔饮水 250 毫升');
        service.calls[0].emit('好的呀。');
        await service.calls[0].finish();
        await settleTwo();
        service.calls[1].emit('我先看看你的目标。');
        await service.calls[1].finish();
        await settleTwo();

        expect(service.calls, hasLength(2), reason: '有界：每轮最多催一次');
        final assistant = controller.state.messages.last;
        expect(assistant.isEditProposal, isFalse);
        expect(assistant.text, '我先看看你的目标。');
        expect(
          controller.needsEnvelopeRetry(assistant.id),
          isTrue,
          reason: '残留要能在气泡上给一枚「让 AI 给出可应用的修改」',
        );
      });

      test('手动催（requestEnvelope）：再跑一次，并**引用上一条回复**要求逐条转会信封', () async {
        final service = _ManualService();
        final controller = build(service);
        await controller.sendMessage('帮我记一笔饮水 250 毫升');
        service.calls[0].emit('好的呀。');
        await service.calls[0].finish();
        await settleTwo();
        service.calls[1].emit('我先看看你的目标。');
        await service.calls[1].finish();
        await settleTwo();

        final assistantId = controller.state.messages.last.id;
        await controller.requestEnvelope(assistantId);
        expect(service.calls, hasLength(3), reason: '手动催要真的再发一次');
        // 2026-10-16 设备实测：标准提示对这个模型催不动（连着两次只回
        // 「我已记下…」的散文，还声称写过了）⇒ 手动这条路改发**加强版提示**：
        // 把模型上一条回复原文引进去，要它把承诺的改动逐条转成命令。
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

        service.calls[2].emit(
          '{"reply":"记好了。","edits":[{"action":"water.add",'
          '"args":{"amountMl":250}}]}',
        );
        await service.calls[2].finish();
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
    Stream<void>? cancelToken,
  }) {
    // 控制器取消时会关掉 cancelToken —— 这就是「请求被取消」的契约。
    cancelToken?.listen((_) {}, onDone: () => cancelled = true);
  }

  final List<ConversationMessage> messages;
  final void Function(String chunk) onProgress;
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
