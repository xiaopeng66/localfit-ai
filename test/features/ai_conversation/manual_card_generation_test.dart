// docs/66「应用卡片按需生成」回归测试（批次 1：上下文拆分 + 正常路径去 JSON +
// manualCardGeneration 开关）。
//
// 原则（docs/66 §8.4）：旧测试全部保留（默认 false 继续验证旧路径）；
// 新路径的测试在**本文件**里，构造时显式 `manualCardGeneration: true`。
import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/data/database/app_database.dart' as db;
import 'package:localfit_ai/features/ai_conversation/data/drift_conversation_message_repository.dart';
import 'package:localfit_ai/core/errors/app_failure.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/features/ai_conversation/application/chat_edit_coordinator.dart';
import 'package:localfit_ai/features/ai_conversation/application/conversation_controller.dart';
import 'package:localfit_ai/features/ai_conversation/domain/ai_conversation_service.dart';
import 'package:localfit_ai/features/ai_conversation/domain/ai_envelope_compiler.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_command.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_registry.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_turn.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_context_builder.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_executor.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_repair.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_reply_display.dart';
import 'package:localfit_ai/features/ai_conversation/domain/conversation_message.dart';
import 'package:localfit_ai/features/ai_conversation/domain/conversation_message_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart'
    show formatLocalDate;

// ── 测试替身 ─────────────────────────────────────────────────────────────

/// 同时实现对话 / 强制 JSON / 信封编译三接口的手动驱动服务。
final class _DualService
    implements
        AiConversationService,
        JsonForcedConversationService,
        AiEnvelopeCompiler {
  final List<_Call> sendCalls = [];
  final List<_Call> forcedCalls = [];
  final List<_CompileCall> compileCalls = [];

  @override
  Stream<String> sendMessage({
    required List<ConversationMessage> messages,
    required void Function(String chunk) onProgress,
    Stream<void>? cancelToken,
    String? systemContext,
  }) {
    final call = _Call(
      onProgress: onProgress,
      cancelToken: cancelToken,
      systemContext: systemContext,
      messages: messages,
    );
    sendCalls.add(call);
    return call.stream;
  }

  @override
  Stream<String> sendMessageForcedJson({
    required List<ConversationMessage> messages,
    required void Function(String chunk) onProgress,
    Stream<void>? cancelToken,
    String? systemContext,
  }) {
    final call = _Call(
      onProgress: onProgress,
      cancelToken: cancelToken,
      systemContext: systemContext,
      messages: messages,
    );
    forcedCalls.add(call);
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
    required this.conversationContext,
    required this.targetLocalDate,
  }) {
    cancelToken?.listen((_) {}, onDone: () => cancelled = true);
  }

  final String userText;
  final String assistantReply;
  final String systemContext;
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

  void fail(Object error) => _controller.addError(error);

  Future<void> finish() => _controller.close();
}

final class _Call {
  _Call({
    required this.onProgress,
    required Stream<void>? cancelToken,
    required this.systemContext,
    required this.messages,
  }) {
    cancelToken?.listen((_) {}, onDone: () => cancelled = true);
  }

  final void Function(String chunk) onProgress;
  final String? systemContext;
  final List<ConversationMessage> messages;
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

/// 记录入参的快照构建器（可注入异常与固定文本）。
class _RecordingBuilder implements ChatEditContextBuilder {
  _RecordingBuilder({this.throws = false});

  static const String payload = '【当前可编辑数据快照】测试';
  final bool throws;

  String? lastUserMessage;
  String? lastFoodQuery;
  PendingProposal? lastPendingProposal;
  int calls = 0;

  @override
  Future<String> build({
    String? userMessage,
    PendingProposal? pendingProposal,
    String? foodQuery,
  }) async {
    calls++;
    if (throws) throw StateError('snapshot boom');
    lastUserMessage = userMessage;
    lastFoodQuery = foodQuery;
    lastPendingProposal = pendingProposal;
    return payload;
  }
}

class _FakeExecutor implements ChatEditExecutor {
  final List<ChatEditCommand> received = [];

  @override
  Future<ChatEditApplyResult> apply(ChatEditCommand command) async {
    received.add(command);
    return const ChatEditApplyResult.ok('已完成。');
  }
}

/// 内存仓储（落库回环用）。
final class _MemoryHistory implements ConversationMessageRepository {
  final List<ConversationMessage> saved = [];

  @override
  Future<int> clear({String sessionId = 'default'}) async {
    saved.clear();
    return 0;
  }

  @override
  Future<List<ConversationMessage>> loadRecent({
    String sessionId = 'default',
    int limit = 200,
  }) async => List.of(saved);

  @override
  Future<void> save(
    ConversationMessage message, {
    String sessionId = 'default',
  }) async => saved.add(message);
}

/// 让控制器发出去的用户消息落到一个固定「今天」；跨日用例可拨动时钟。
final class _MutableClock implements AppClock {
  _MutableClock(this.now);

  DateTime now;

  @override
  DateTime nowUtc() => now;
}

// ── 常量 ────────────────────────────────────────────────────────────────

const _waterEnvelope =
    '{"reply":"好的，帮你记一笔。","edits":['
    '{"action":"water.add","args":{"amountMl":250}}]}';

Future<void> pump2() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

ConversationController _newController(
  _DualService service, {
  required bool manual,
  ChatEditCoordinator? chatEdit,
  ConversationMessageRepository? repository,
  AppClock? clock,
}) => ConversationController(
  service,
  chatEdit: chatEdit,
  manualCardGeneration: manual,
  repository: repository,
  clock: clock,
);

void main() {
  group('批次1 · 新模式（manualCardGeneration: true）', () {
    test('修改请求完成不自动挂卡，消息仍是纯文本', () async {
      final service = _DualService();
      final controller = _newController(
        service,
        manual: true,
        chatEdit: ChatEditCoordinator(
          contextBuilder: _RecordingBuilder(),
          executor: _FakeExecutor(),
        ),
      );
      await controller.sendMessage('记 250ml 水');
      service.sendCalls.single.emit('你今天喝了 250 毫升水，我准备帮你记上。');
      await service.sendCalls.single.finish();
      await pump2();

      expect(controller.state.messages, hasLength(2));
      final reply = controller.state.messages.last;
      expect(reply.isEditProposal, isFalse);
      expect(reply.editTurn, isNull);
      expect(reply.text, '你今天喝了 250 毫升水，我准备帮你记上。');
    });

    test('照片批量请求不强制 JSON、不自动挂卡', () async {
      final service = _DualService();
      final controller = _newController(
        service,
        manual: true,
        chatEdit: ChatEditCoordinator(
          contextBuilder: _RecordingBuilder(),
          executor: _FakeExecutor(),
        ),
      );
      await controller.sendMessage('帮我看看这餐吃了什么 记录一下');
      service.sendCalls.single.emit('这餐有米饭和鸡胸肉。');
      await service.sendCalls.single.finish();
      await pump2();

      expect(service.forcedCalls, isEmpty, reason: '新模式不再走 forcedJson 首轮');
      expect(controller.state.messages.last.isEditProposal, isFalse);
    });

    test('needsEnvelopeRetry 恒为 false（不出现旧兜底卡）', () async {
      final service = _DualService();
      final controller = _newController(
        service,
        manual: true,
        chatEdit: ChatEditCoordinator(
          contextBuilder: _RecordingBuilder(),
          executor: _FakeExecutor(),
        ),
      );
      await controller.sendMessage('记 250ml 水');
      service.sendCalls.single.emit('我准备帮你记上，点应用后生效。');
      await service.sendCalls.single.finish();
      await pump2();
      final messageId = controller.state.messages.last.id;
      expect(controller.needsEnvelopeRetry(messageId), isFalse);
    });

    test('普通发送 systemContext 含内容纪律+能力边界+快照，不含命令清单', () async {
      final service = _DualService();
      final builder = _RecordingBuilder();
      final controller = _newController(
        service,
        manual: true,
        chatEdit: ChatEditCoordinator(
          contextBuilder: builder,
          executor: _FakeExecutor(),
        ),
      );
      await controller.sendMessage('今天吃什么好');
      await pump2();
      service.sendCalls.single.emit('可以吃点清淡的。');
      await service.sendCalls.single.finish();
      await pump2();

      final context = service.sendCalls.single.systemContext;
      expect(context, isNotNull);
      // 内容纪律关键短语（docs/66 §5.1 八条压成的段落）。
      expect(context, contains('不要输出 JSON 信封'));
      expect(context, contains('不谎报'));
      expect(context, contains('按常见份量估算'));
      expect(context, contains('步数是系统读的'));
      expect(context, contains('忌口'));
      // 能力边界。
      expect(context, contains('能力边界'));
      // 快照仍在。
      expect(context, contains('【当前可编辑数据快照】测试'));
      // 协议不得整段带回来。
      expect(context, isNot(contains('meal.create')));
      expect(context, isNot(contains('"edits"')));
    });

    test('快照构建失败时普通发送仍有内容纪律（不返回 null）', () async {
      final service = _DualService();
      final controller = _newController(
        service,
        manual: true,
        chatEdit: ChatEditCoordinator(
          contextBuilder: _RecordingBuilder(throws: true),
          executor: _FakeExecutor(),
        ),
      );
      await controller.sendMessage('今天吃什么好');
      await pump2();
      service.sendCalls.single.emit('好的。');
      await service.sendCalls.single.finish();
      await pump2();

      final context = service.sendCalls.single.systemContext;
      expect(context, isNotNull, reason: '快照失败不该把内容纪律一起丢掉');
      expect(context, contains('按常见份量估算'));
    });

    test('普通发送仍注入 pendingProposal（上一张待应用卡）', () async {
      final service = _DualService();
      final builder = _RecordingBuilder();
      final history = _MemoryHistory();
      final controller = _newController(
        service,
        manual: true,
        repository: history,
        chatEdit: ChatEditCoordinator(
          contextBuilder: builder,
          executor: _FakeExecutor(),
        ),
      );
      // 新模式不会自动出卡：直接从仓储载入一张旧卡（重启后的常态）。
      history.saved.add(
        ConversationMessage(
          id: 'seed-card',
          role: ConversationRole.assistant,
          text: '好的，帮你记一笔。',
          createdAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
          kind: ConversationMessageKind.editProposal,
          editTurn: parseChatEditTurn(
            '{"reply":"好的，帮你记一笔。","edits":['
            '{"action":"water.add","args":{"amountMl":250}}]}',
            ChatEditCommandRegistry(),
          ),
        ),
      );
      await controller.loadHistory();
      await pump2();

      await controller.sendMessage('米饭改成 100 克');
      await pump2();
      expect(builder.lastPendingProposal, isNotNull);
      expect(builder.lastPendingProposal!.commands.single.action, 'water.add');
    });

    test('意外合法信封：只取 reply 显示、不挂卡、落库为纯文本', () async {
      final service = _DualService();
      final history = _MemoryHistory();
      final controller = _newController(
        service,
        manual: true,
        repository: history,
        chatEdit: ChatEditCoordinator(
          contextBuilder: _RecordingBuilder(),
          executor: _FakeExecutor(),
        ),
      );
      await controller.sendMessage('记 250ml 水');
      // 模型没听协议，直接回了一份信封。
      service.sendCalls.single.emit(_waterEnvelope);
      await service.sendCalls.single.finish();
      await pump2();

      final reply = controller.state.messages.last;
      expect(reply.isEditProposal, isFalse, reason: '新模式绝不自动挂卡');
      expect(reply.text, '好的，帮你记一笔。', reason: '只取 reply，不把 JSON 上屏');
      expect(history.saved.last.editTurn, isNull, reason: '落库的是纯文本，重启不会诈尸出卡');
      expect(history.saved.last.text, '好的，帮你记一笔。');
    });

    test('意外坏 JSON：新模式人话文案，原始 JSON 不上屏不落库', () async {
      final service = _DualService();
      final history = _MemoryHistory();
      final controller = _newController(
        service,
        manual: true,
        repository: history,
        chatEdit: ChatEditCoordinator(
          contextBuilder: _RecordingBuilder(),
          executor: _FakeExecutor(),
        ),
      );
      await controller.sendMessage('记 250ml 水');
      service.sendCalls.single.emit('{"reply":"半截信封…');
      await service.sendCalls.single.finish();
      await pump2();

      final reply = controller.state.messages.last;
      expect(reply.text, kMalformedEnvelopeNoticeManualCard);
      expect(reply.text, isNot(contains('{')));
      expect(history.saved.last.text, kMalformedEnvelopeNoticeManualCard);
    });
  });

  group('批次1 · 旧路径回滚冒烟（manualCardGeneration 默认 false）', () {
    test('修改请求仍首轮强制 JSON 并自动挂卡（2115 行为不变）', () async {
      final service = _DualService();
      final controller = ConversationController(
        service,
        chatEdit: ChatEditCoordinator(
          contextBuilder: _RecordingBuilder(),
          executor: _FakeExecutor(),
        ),
      );
      await controller.sendMessage('帮我记 250ml 水');
      expect(service.forcedCalls, hasLength(1), reason: '旧路径保持首轮强制 JSON');
      service.forcedCalls.single.emit(_waterEnvelope);
      await service.forcedCalls.single.finish();
      await pump2();
      expect(controller.state.messages.last.isEditProposal, isTrue);
    });
  });

  group('批次1 · 展示清洗', () {
    test('replyTextForDisplay(manualCardMode: true) 用新模式文案', () {
      expect(
        replyTextForDisplay('{"reply":"x"}', manualCardMode: true),
        kMalformedEnvelopeNoticeManualCard,
      );
      // 旧调用点行为不变。
      expect(replyTextForDisplay('{"reply":"x"}'), kMalformedEnvelopeNotice);
      expect(
        replyTextForDisplay('普通回复 [food:abc]', manualCardMode: true),
        '普通回复 ',
      );
    });
  });

  // ── 批次 2：手动生成链路（docs/66 §5.2–§5.4、§5.10）─────────────────────
  //
  // 测试矩阵 §8.1 的核心用例。链路：发送（纯文本）→ 点生成 → 编译 →
  // 接地/钉日/挂卡（同一条消息）→ 落库。
  group('批次2 · 手动生成链路', () {
    final now = DateTime.parse('2026-11-07T15:00:00+08:00');
    const waterReply = '你今天喝了 250 毫升水，我准备帮你记上。';
    const waterEnvelope =
        '{"reply":"好的，帮你记一笔。","edits":['
        '{"action":"water.add","args":{"amountMl":250}}]}';

    Future<(_DualService, _MutableClock, ConversationController, String)>
    seedProseRound({
      List<String> priorTurns = const [],
      _RecordingBuilder? builder,
      ConversationMessageRepository? repository,
      ChatEditDependencyConfirm? editDependencyConfirm,
      ConfirmEditDates? confirmEditDates,
    }) async {
      final clock = _MutableClock(now);
      final service = _DualService();
      final controller = ConversationController(
        service,
        chatEdit: ChatEditCoordinator(
          contextBuilder: builder ?? _RecordingBuilder(),
          executor: _RecordingExecutor(),
        ),
        manualCardGeneration: true,
        clock: clock,
        repository: repository,
        editDependencyConfirm: editDependencyConfirm,
        confirmEditDates: confirmEditDates,
      );
      // 先铺历史轮次（每轮一段散文）。
      for (final (index, turn) in priorTurns.indexed) {
        await controller.sendMessage('历史消息 $index');
        service.sendCalls.last.emit(turn);
        await service.sendCalls.last.finish();
        await pump2();
      }
      await controller.sendMessage('记 250ml 水');
      service.sendCalls.last.emit(waterReply);
      await service.sendCalls.last.finish();
      await pump2();
      final replyId = controller.state.messages.last.id;
      return (service, clock, controller, replyId);
    }

    test('点生成调用编译器一次：参数含目标回复+用户请求+最近对话+完整协议+日期', () async {
      final (service, _, controller, replyId) = await seedProseRound(
        priorTurns: ['早上喝了 200 毫升。'],
      );
      await controller.generateEditCard(replyId);
      await pump2();

      final call = service.compileCalls.single;
      expect(call.assistantReply, waterReply);
      expect(call.userText, '记 250ml 水');
      // 最近对话：上一轮的散文在、目标回复本身不在。
      expect(call.conversationContext, contains('早上喝了 200 毫升。'));
      expect(call.conversationContext, isNot(contains(waterReply)));
      // 完整协议（命令清单）+ 编译变体的显式规则。
      // 【2026-11-07 用户裁决】点击「生成应用卡片」= 明确要求记入：
      // 编译上下文不再问「是否提议」，直接按点击意图提取。
      expect(call.systemContext, contains('meal.create'));
      expect(call.systemContext, contains('信封编译器'));
      expect(call.systemContext, contains('记入 App'));
      expect(call.systemContext, isNot(contains('已经明确提出')));
      // 编译协议变体不含估算/suggestions 对话规则。
      expect(call.systemContext, isNot(contains('按常见份量估算')));
      // 目标回复的本地日期写进了编译 prompt 参数。
      expect(call.targetLocalDate, formatLocalDate(now));
    });

    test('编译返回两条 edits：挂到原消息，messages.length 不变，原文逐字一致', () async {
      final (service, _, controller, replyId) = await seedProseRound();
      final before = controller.state.messages;
      await controller.generateEditCard(replyId);
      service.compileCalls.single.emit(
        '{"reply":"两条都要。","edits":['
        '{"action":"water.add","args":{"amountMl":250}},'
        '{"action":"meal.create","args":{"slot":"午餐","items":'
        '[{"food":"水煮蛋","grams":250}]}}]}',
      );
      await service.compileCalls.single.finish();
      await pump2();

      final after = controller.state.messages;
      expect(after.length, before.length, reason: '不新增气泡');
      final target = after.firstWhere((m) => m.id == replyId);
      expect(target.isEditProposal, isTrue);
      expect(target.text, waterReply, reason: '原文逐字不变');
      expect(target.editTurn!.rows, hasLength(2));
      expect(target.editTurn!.reply, waterReply, reason: 'turn.reply = 原文');
      expect(
        controller.cardGenerationOf(replyId).phase,
        CardGenerationPhase.idle,
      );
    });

    test('新编译结果精确去重后连续编号，选择应用与真实落库重载对位', () async {
      final database = db.AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = DriftConversationMessageRepository(database: database);
      final (service, _, controller, replyId) = await seedProseRound(
        repository: repository,
      );
      addTearDown(controller.dispose);
      await controller.generateEditCard(replyId);
      service.compileCalls.single.emit(
        '{"reply":"记。","edits":['
        '{"action":"weight.log","args":{"weightKg":250,"notes":"第一次"}},'
        '{"action":"weight.log","args":{"notes":"第一次","weightKg":250.0}},'
        '{"action":"water.delete","args":{"waterId":"w1"}},'
        '{"action":"water.delete","args":{"waterId":"w2"}}]}',
      );
      await service.compileCalls.single.finish();
      await pump2();
      final rows = controller.state.messages.last.editTurn!.rows;
      expect(rows, hasLength(3), reason: '只去掉 action+全部参数相同的命令');
      expect(rows.map((row) => row.index), [0, 1, 2]);
      expect(rows.first.command!.args['localDate'], formatLocalDate(now));
      expect(
        (rows.first.raw['args'] as Map)['localDate'],
        formatLocalDate(now),
      );

      await controller.applyEdits(replyId, rowIndexes: {1});
      final loaded = await repository.loadRecent();
      expect(loaded, hasLength(2), reason: '原助手消息覆盖，不新建重复气泡');
      final restored = loaded.singleWhere((m) => m.id == replyId).editTurn!;
      expect(restored.rows.map((row) => row.index), [0, 1, 2]);
      expect(restored.rows.map((row) => row.status), [
        ChatEditRowStatus.proposed,
        ChatEditRowStatus.applied,
        ChatEditRowStatus.proposed,
      ]);
      expect(restored.rows[1].command!.args['waterId'], 'w1');
      expect(restored.rows[2].command!.args['waterId'], 'w2');
      expect(
        (restored.rows.first.raw['args'] as Map)['localDate'],
        formatLocalDate(now),
      );

      await controller.dismissEdits(replyId);
      final again = (await repository.loadRecent()).last.editTurn!;
      expect(again.rows.map((row) => row.status), [
        ChatEditRowStatus.dismissed,
        ChatEditRowStatus.applied,
        ChatEditRowStatus.dismissed,
      ]);
    });

    test('精确去重不合并不同参数、不同动作和含错误的编译行', () async {
      final (service, _, controller, replyId) = await seedProseRound();
      addTearDown(controller.dispose);
      await controller.generateEditCard(replyId);
      service.compileCalls.single.emit(
        '{"reply":"记。","edits":['
        '{"action":"water.add","args":{"amountMl":250}},'
        '{"action":"water.add","args":{"amountMl":250}},'
        '{"action":"weight.log","args":{"weightKg":250,"notes":"另一次"}},'
        '{"action":"weight.log","args":{"weightKg":250}},'
        '{"action":"water.add","args":{"amountMl":"坏值"}},'
        '{"action":"water.add","args":{"amountMl":"坏值"}}]}',
      );
      await service.compileCalls.single.finish();
      await pump2();
      final rows = controller.state.messages.last.editTurn!.rows;
      expect(rows, hasLength(5));
      expect(rows.map((row) => row.index), [0, 1, 2, 3, 4]);
      expect(rows[1].command!.args['notes'], '另一次');
      expect(rows[2].command!.action, 'weight.log');
      expect(rows.skip(3).map((row) => row.status), [
        ChatEditRowStatus.failed,
        ChatEditRowStatus.failed,
      ]);
    });

    test('精确去重比较嵌套参数，保留用料顺序和不同来源实体', () async {
      final (service, _, controller, replyId) = await seedProseRound();
      addTearDown(controller.dispose);
      await controller.generateEditCard(replyId);
      service.compileCalls.single.emit(
        '{"reply":"记。","edits":['
        '{"action":"meal.create","args":{"slot":"午餐","items":['
        '{"food":"[food:f1]","grams":250},{"food":"[food:f2]","grams":250}]}},'
        '{"action":"meal.create","args":{"items":['
        '{"grams":250.0,"food":"[food:f1]"},{"grams":250,"food":"[food:f2]"}],"slot":"lunch"}},'
        '{"action":"meal.create","args":{"slot":"午餐","items":['
        '{"food":"[food:f2]","grams":250},{"food":"[food:f1]","grams":250}]}},'
        '{"action":"meal.create","args":{"slot":"午餐","items":['
        '{"food":"[dish:f1]","grams":250},{"food":"[food:f2]","grams":250}]}}]}',
      );
      await service.compileCalls.single.finish();
      await pump2();
      final rows = controller.state.messages.last.editTurn!.rows;
      expect(rows, hasLength(3));
      expect(rows.map((row) => row.index), [0, 1, 2]);
      final firstFoods = rows.map(
        (row) => ((row.command!.args['items'] as List).first as Map)['food'],
      );
      expect(firstFoods, ['[food:f1]', '[food:f2]', '[dish:f1]']);
    });

    test('纯卡片管理请求从上一回复编译，不再新发聊天或新增气泡', () async {
      final (service, _, controller, replyId) = await seedProseRound();
      addTearDown(controller.dispose);
      await controller.sendMessage('生成应用卡片');
      expect(controller.state.messages, hasLength(2));
      expect(service.sendCalls, hasLength(1));
      expect(service.compileCalls, hasLength(1));
      expect(service.compileCalls.single.assistantReply, waterReply);
      await controller.sendMessage('生成应用卡片');
      expect(controller.state.messages, hasLength(2));
      expect(service.sendCalls, hasLength(1));
      expect(service.compileCalls, hasLength(1), reason: '编译中也复用同一目标');
      service.compileCalls.single.emit(waterEnvelope);
      await service.compileCalls.single.finish();
      await pump2();
      expect(controller.state.messages.last.id, replyId);
      expect(controller.state.messages.last.text, waterReply);
      expect(controller.state.messages.last.editTurn!.rows, hasLength(1));
    });

    test('纯卡片管理请求复用已有卡，已应用行不重置也不重新编译', () async {
      final (service, _, controller, replyId) = await seedProseRound();
      addTearDown(controller.dispose);
      await controller.generateEditCard(replyId);
      service.compileCalls.single.emit(waterEnvelope);
      await service.compileCalls.single.finish();
      await pump2();
      await controller.applyEdits(replyId);
      expect(
        controller.state.messages.last.editTurn!.rows.single.status,
        ChatEditRowStatus.applied,
      );
      for (final request in ['生成应用卡片', '请帮我生成应用卡片！', '生成卡片']) {
        await controller.sendMessage(request);
        expect(controller.state.messages, hasLength(2));
        expect(controller.state.messages.last.id, replyId);
        expect(
          controller.state.messages.last.editTurn!.rows.single.status,
          ChatEditRowStatus.applied,
        );
      }
      expect(service.sendCalls, hasLength(1));
      expect(service.compileCalls, hasLength(1));
    });

    test('纯卡片管理请求复用部分应用卡，逐行结果与落库状态不重置', () async {
      final database = db.AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = DriftConversationMessageRepository(database: database);
      final (service, _, controller, replyId) = await seedProseRound(
        repository: repository,
      );
      addTearDown(controller.dispose);
      await controller.generateEditCard(replyId);
      service.compileCalls.single.emit(
        '{"reply":"记。","edits":['
        '{"action":"water.add","args":{"amountMl":250}},'
        '{"action":"weight.log","args":{"weightKg":250}}]}',
      );
      await service.compileCalls.single.finish();
      await pump2();
      await controller.applyEdits(replyId, rowIndexes: {0});

      await controller.sendMessage('生成应用卡片');
      expect(controller.state.messages, hasLength(2));
      expect(service.sendCalls, hasLength(1));
      expect(service.compileCalls, hasLength(1));
      final current = controller.state.messages.last.editTurn!;
      expect(current.rows.map((row) => row.status), [
        ChatEditRowStatus.applied,
        ChatEditRowStatus.proposed,
      ]);
      expect(current.rows.map((row) => row.resultMessage), ['已完成。', null]);
      final loaded = await repository.loadRecent();
      expect(loaded, hasLength(2));
      final restored = loaded.singleWhere((m) => m.id == replyId).editTurn!;
      expect(restored.rows.map((row) => row.index), [0, 1]);
      expect(restored.rows.map((row) => row.status), [
        ChatEditRowStatus.applied,
        ChatEditRowStatus.proposed,
      ]);
      expect(restored.rows.map((row) => row.resultMessage), ['已完成。', null]);
    });

    test('纯卡片管理只处理最新回复，不向前复用更旧卡片', () async {
      final (service, _, controller, replyId) = await seedProseRound();
      addTearDown(controller.dispose);
      await controller.generateEditCard(replyId);
      service.compileCalls.single.emit(waterEnvelope);
      await service.compileCalls.single.finish();
      await pump2();
      await controller.sendMessage('谢谢');
      service.sendCalls.last.emit('随时可以继续。');
      await service.sendCalls.last.finish();
      await pump2();
      final latestId = controller.state.messages.last.id;

      await controller.sendMessage('生成应用卡片');
      expect(controller.state.messages, hasLength(4));
      expect(service.sendCalls, hasLength(2));
      expect(service.compileCalls, hasLength(2));
      expect(service.compileCalls.last.assistantReply, '随时可以继续。');
      expect(service.compileCalls.last.userText, '谢谢');
      expect(controller.state.messages.last.id, latestId);
      expect(controller.state.messages[1].id, replyId);
      expect(controller.state.messages[1].isEditProposal, isTrue);
      service.compileCalls.last.emit('{"reply":"无需记录。","edits":[]}');
      await service.compileCalls.last.finish();
      await pump2();
    });

    test('纯卡片管理路由在非手动模式不生效，仍发送正常聊天', () async {
      final service = _DualService();
      final history = _MemoryHistory()
        ..saved.addAll([
          ConversationMessage(
            id: 'legacy-user',
            role: ConversationRole.user,
            text: '记 250ml 水',
            createdAt: now,
          ),
          ConversationMessage(
            id: 'legacy-reply',
            role: ConversationRole.assistant,
            text: waterReply,
            createdAt: now,
          ),
        ]);
      final controller = ConversationController(
        service,
        chatEdit: ChatEditCoordinator(
          contextBuilder: _RecordingBuilder(),
          executor: _RecordingExecutor(),
        ),
        clock: _MutableClock(now),
        repository: history,
      );
      addTearDown(controller.dispose);
      await controller.loadHistory();
      await controller.sendMessage('生成应用卡片');
      expect(controller.state.messages, hasLength(4));
      expect(service.compileCalls, isEmpty);
      final call = [...service.sendCalls, ...service.forcedCalls].single;
      expect(call.messages.last.textForRequest, '生成应用卡片');
      call.emit(waterEnvelope);
      await call.finish();
      await pump2();
    });

    test('重新记一次、更改和混合请求仍发聊天，wireText 业务载荷不被截断', () async {
      for (final request in [
        '重新记一次',
        '再记一次 250ml 水，生成应用卡片',
        '把饮水改成 300ml，再生成应用卡片',
        '生成应用卡片，另外记 250ml 水',
      ]) {
        final (service, _, controller, _) = await seedProseRound();
        addTearDown(controller.dispose);
        await controller.sendMessage(request);
        expect(service.sendCalls, hasLength(2), reason: request);
        expect(service.compileCalls, isEmpty, reason: request);
        expect(controller.state.messages, hasLength(4));
        service.sendCalls.last.emit('请核对这次记录。');
        await service.sendCalls.last.finish();
      }
      final (service, _, controller, _) = await seedProseRound();
      addTearDown(controller.dispose);
      await controller.sendMessageWithWire(
        '生成应用卡片',
        wireText: '分析这道菜 [canteen-dish:d1]',
      );
      expect(service.sendCalls, hasLength(2));
      expect(service.compileCalls, isEmpty);
      expect(
        service.sendCalls.last.messages.last.textForRequest,
        '分析这道菜 [canteen-dish:d1]',
      );
      service.sendCalls.last.emit('分析结果。');
      await service.sendCalls.last.finish();
    });

    test('挂卡后落库：saved 里是编辑卡，重载后原文+卡片都在', () async {
      final history = _MemoryHistory();
      final (service, _, controller, replyId) = await seedProseRound(
        repository: history,
      );
      await controller.generateEditCard(replyId);
      service.compileCalls.single.emit(waterEnvelope);
      await service.compileCalls.single.finish();
      await pump2();

      final saved = history.saved.last;
      expect(saved.editTurn, isNotNull);
      expect(saved.text, waterReply);
      final reloaded = await history.loadRecent();
      final restored = reloaded.last;
      expect(restored.text, waterReply);
      expect(restored.isEditProposal, isTrue);
      // 已有卡片的消息不再给按钮。
      expect(controller.canGenerateCard(replyId), isFalse);
    });

    test('空信封 → empty 状态（含编译器原因），不挂卡', () async {
      final (service, _, controller, replyId) = await seedProseRound();
      await controller.generateEditCard(replyId);
      service.compileCalls.single.emit(
        '{"reply":"这条回复没有可直接记录的操作。","edits":[]}',
      );
      await service.compileCalls.single.finish();
      await pump2();

      final state = controller.cardGenerationOf(replyId);
      expect(state.phase, CardGenerationPhase.empty);
      expect(state.message, '这条回复没有可直接记录的操作。');
      expect(controller.state.messages.last.isEditProposal, isFalse);
    });

    test('编译器抛网络错 → failed（人话），原文不变，可重试', () async {
      final (service, _, controller, replyId) = await seedProseRound();
      await controller.generateEditCard(replyId);
      service.compileCalls.single.fail(const NetworkFailure('网络连接不可用'));
      await service.compileCalls.single.finish();
      await pump2();

      final state = controller.cardGenerationOf(replyId);
      expect(state.phase, CardGenerationPhase.failed);
      expect(state.retryable, isTrue);
      expect(state.message, contains('网络'));
      expect(controller.state.messages.last.text, waterReply);
      // 可重试：再点一次编译器再次被调用。
      await controller.generateEditCard(replyId);
      expect(service.compileCalls, hasLength(2));
    });

    test('编译请求体超闸门（ValidationFailure）→ failed 且是服务的人话原因', () async {
      final (service, _, controller, replyId) = await seedProseRound();
      await controller.generateEditCard(replyId);
      // 服务侧对**最终 UTF-8 JSON body**（含协议/snapshot/转义）执行 64 KiB
      // 闸门；超限抛 ValidationFailure，控制器必须原样翻成人话（不说「未知错误」）。
      service.compileCalls.single.fail(
        const ValidationFailure('对话内容过长，请精简后重试。'),
      );
      await service.compileCalls.single.finish();
      await pump2();

      final state = controller.cardGenerationOf(replyId);
      expect(state.phase, CardGenerationPhase.failed);
      expect(state.message, '对话内容过长，请精简后重试。');
      expect(
        controller.state.messages.last.isEditProposal,
        isFalse,
        reason: '超限就是不挂卡，不是挂一张空卡',
      );
    });

    test('流先报错再收尾：迟到的 onDone 不能把 failed 变成挂卡', () async {
      final (service, _, controller, replyId) = await seedProseRound();
      await controller.generateEditCard(replyId);
      final call = service.compileCalls.single;
      // 缓冲区已经攒够一个**合法信封**，随后网络报错。
      call.emit(_waterEnvelope);
      call.fail(const NetworkFailure('网络连接不可用'));
      // 迟到的收尾（真实 SSE 流的结束事件）——必须被丢弃。
      await call.finish();
      await pump2();

      final state = controller.cardGenerationOf(replyId);
      expect(state.phase, CardGenerationPhase.failed, reason: '错误就是错误，不能被收尾覆盖');
      expect(
        controller.state.messages.last.isEditProposal,
        isFalse,
        reason: '报错后迟到 onDone 不得挂卡（否则用户会看到一场已失败的卡的卡）',
      );
    });

    test('非法 JSON → failed，不显示 JSON', () async {
      final (service, _, controller, replyId) = await seedProseRound();
      await controller.generateEditCard(replyId);
      service.compileCalls.single.emit('{"reply":"半截…');
      await service.compileCalls.single.finish();
      await pump2();

      final state = controller.cardGenerationOf(replyId);
      expect(state.phase, CardGenerationPhase.failed);
      expect(state.message, '生成失败，请重试。');
      expect(controller.state.messages.last.text, waterReply);
    });

    test('双击生成只调用一次编译器', () async {
      final (service, _, controller, replyId) = await seedProseRound();
      await controller.generateEditCard(replyId);
      await controller.generateEditCard(replyId);
      expect(service.compileCalls, hasLength(1));
    });

    test('canGenerateCard 的六道门（非卡片/流式中/错误/非今天/无前置用户/开关）', () async {
      final clock = _MutableClock(now);
      final service = _DualService();
      final controller = ConversationController(
        service,
        chatEdit: ChatEditCoordinator(
          contextBuilder: _RecordingBuilder(),
          executor: _RecordingExecutor(),
        ),
        manualCardGeneration: true,
        clock: clock,
      );
      final yesterday = now.subtract(const Duration(days: 1));
      // 真实状态里的编辑卡：载入一张 seed 卡再断言（已是卡片 ⇒ false）。
      final history = _MemoryHistory()
        ..saved.add(
          ConversationMessage(
            id: 'seed-card',
            role: ConversationRole.assistant,
            text: '卡',
            createdAt: now,
            kind: ConversationMessageKind.editProposal,
            editTurn: ChatEditTurn(
              reply: '卡',
              rows: [
                ChatEditTurnItem(
                  index: 0,
                  raw: const {
                    'action': 'water.add',
                    'args': {'amountMl': 250},
                  },
                  command: _waterCommand(250),
                ),
              ],
            ),
          ),
        );
      final seedController = ConversationController(
        service,
        chatEdit: ChatEditCoordinator(
          contextBuilder: _RecordingBuilder(),
          executor: _RecordingExecutor(),
        ),
        manualCardGeneration: true,
        clock: clock,
        repository: history,
      );
      await seedController.loadHistory();
      await pump2();
      expect(seedController.canGenerateCard('seed-card'), isFalse);
      // 不在列表里的 id 一律 false（流式中/错误等状态位门控由同一守卫拦截）。
      expect(controller.canGenerateCard('nonexistent'), isFalse);
      // 无前置用户消息（开场白）：只有一条助手消息的会话。
      final greetingHistory = _MemoryHistory()
        ..saved.add(
          ConversationMessage(
            id: 'greeting',
            role: ConversationRole.assistant,
            text: '你好',
            createdAt: now,
          ),
        );
      final withGreetingOnly = ConversationController(
        service,
        chatEdit: ChatEditCoordinator(
          contextBuilder: _RecordingBuilder(),
          executor: _RecordingExecutor(),
        ),
        manualCardGeneration: true,
        clock: clock,
        repository: greetingHistory,
      );
      await withGreetingOnly.loadHistory();
      await pump2();
      expect(withGreetingOnly.canGenerateCard('greeting'), isFalse);
      // 非今天的助手消息（注入仓库后断言）。
      final oldHistory = _MemoryHistory()
        ..saved.addAll([
          ConversationMessage(
            id: 'old-user',
            role: ConversationRole.user,
            text: '问',
            createdAt: yesterday,
          ),
          ConversationMessage(
            id: 'old-reply',
            role: ConversationRole.assistant,
            text: '答',
            createdAt: yesterday,
          ),
        ]);
      final withOld = ConversationController(
        service,
        chatEdit: ChatEditCoordinator(
          contextBuilder: _RecordingBuilder(),
          executor: _RecordingExecutor(),
        ),
        manualCardGeneration: true,
        clock: clock,
        repository: oldHistory,
      );
      await withOld.loadHistory();
      await pump2();
      expect(withOld.canGenerateCard('old-reply'), isFalse);
      // 开关关闭。
      final legacy = ConversationController(
        service,
        chatEdit: ChatEditCoordinator(
          contextBuilder: _RecordingBuilder(),
          executor: _RecordingExecutor(),
        ),
        clock: clock,
      );
      expect(legacy.canGenerateCard('anything'), isFalse);
      // 未实现编译器的服务。
      final plain = ConversationController(
        _ManualOnlyService(),
        chatEdit: ChatEditCoordinator(
          contextBuilder: _RecordingBuilder(),
          executor: _RecordingExecutor(),
        ),
        manualCardGeneration: true,
        clock: clock,
      );
      expect(plain.canGenerateCard('anything'), isFalse);
      // 服务为空。
      final noService = ConversationController(
        null,
        manualCardGeneration: true,
        clock: clock,
      );
      expect(noService.canGenerateCard('anything'), isFalse);
    });

    test('超长原文（>6000 字）直接 failed（retryable:false），不发编译请求', () async {
      final clock = _MutableClock(now);
      final service = _DualService();
      final controller = ConversationController(
        service,
        chatEdit: ChatEditCoordinator(
          contextBuilder: _RecordingBuilder(),
          executor: _RecordingExecutor(),
        ),
        manualCardGeneration: true,
        clock: clock,
      );
      final longText =
          '长' * (ConversationController.kMaxManualTargetReplyChars + 1);
      await controller.sendMessage('说一段长的');
      service.sendCalls.last.emit(longText);
      await service.sendCalls.last.finish();
      await pump2();
      final longReplyId = controller.state.messages.last.id;

      await controller.generateEditCard(longReplyId);
      await pump2();
      expect(service.compileCalls, isEmpty, reason: '不发编译请求');
      final state = controller.cardGenerationOf(longReplyId);
      expect(state.phase, CardGenerationPhase.failed);
      expect(state.retryable, isFalse);
      expect(state.message, contains('太长'));
    });

    test('PendingProposal 摘要 ≤240 字、压平空白（§5.9）', () async {
      final builder = _RecordingBuilder();
      final history = _MemoryHistory();
      final clock = _MutableClock(now);
      final service = _DualService();
      final controller = ConversationController(
        service,
        chatEdit: ChatEditCoordinator(
          contextBuilder: builder,
          executor: _RecordingExecutor(),
        ),
        manualCardGeneration: true,
        clock: clock,
        repository: history,
      );
      final longReply = '这是一段很长的待应用卡摘要。${'内容 ' * 120}';
      history.saved.add(
        ConversationMessage(
          id: 'seed',
          role: ConversationRole.assistant,
          text: longReply,
          createdAt: now,
          kind: ConversationMessageKind.editProposal,
          editTurn: ChatEditTurn(
            reply: longReply,
            rows: [
              ChatEditTurnItem(
                index: 0,
                raw: const {
                  'action': 'water.add',
                  'args': {'amountMl': 250},
                },
                command: _waterCommand(250),
              ),
            ],
          ),
        ),
      );
      await controller.loadHistory();
      await pump2();
      await controller.sendMessage('下一句');
      await pump2();
      final summary = builder.lastPendingProposal!.summary;
      expect(summary.length, lessThanOrEqualTo(241));
      expect(summary.endsWith('…'), isTrue);
      expect(summary, isNot(contains('\n')));
    });

    test('点击时今天、编译完成时已跨日 → failed（retryable:false），不挂卡', () async {
      final (service, clock, controller, replyId) = await seedProseRound();
      await controller.generateEditCard(replyId);
      clock.now = now.add(const Duration(days: 1));
      service.compileCalls.single.emit(waterEnvelope);
      await service.compileCalls.single.finish();
      await pump2();

      final state = controller.cardGenerationOf(replyId);
      expect(state.phase, CardGenerationPhase.failed);
      expect(state.retryable, isFalse);
      expect(state.message, contains('跨天'));
      expect(controller.state.messages.last.isEditProposal, isFalse);
    });

    test('生成中点取消：token 收到取消事件、epoch 失效，迟到的信封不挂卡不落库', () async {
      final history = _MemoryHistory();
      final (service, _, controller, replyId) = await seedProseRound(
        repository: history,
      );
      await controller.generateEditCard(replyId);
      controller.cancelCardGeneration(replyId);
      // 取消事件经流传递（add → 监听器 → close → onDone），要给一轮事件循环。
      await pump2();
      expect(service.compileCalls.single.cancelled, isTrue);
      expect(
        controller.cardGenerationOf(replyId).phase,
        CardGenerationPhase.idle,
      );
      // 迟到的完整信封：epoch 已失效 ⇒ 不挂卡、不落库。
      service.compileCalls.single.emit(waterEnvelope);
      await service.compileCalls.single.finish();
      await pump2();
      expect(controller.state.messages.last.isEditProposal, isFalse);
      expect(history.saved.where((m) => m.isEditProposal), isEmpty);
      // 之后可以重新生成，而且**这次能正常挂卡**（旧 epoch 不干扰新请求）。
      await controller.generateEditCard(replyId);
      expect(service.compileCalls, hasLength(2));
      service.compileCalls[1].emit(waterEnvelope);
      await service.compileCalls[1].finish();
      await pump2();
      final reread = controller.state.messages.firstWhere(
        (m) => m.id == replyId,
      );
      expect(reread.isEditProposal, isTrue, reason: '取消过的那条仍能重新生成成功');
      expect(reread.text, waterReply, reason: '原文依然不变');
    });

    test('生成期间发新消息：新回复正常，旧目标不被覆盖，卡片仍能完成', () async {
      final (service, _, controller, replyId) = await seedProseRound();
      await controller.generateEditCard(replyId);
      await pump2();
      // 生成中继续聊天（编译流尚未收尾）。
      await controller.sendMessage('帮我看看今天还剩多少');
      service.sendCalls.last.emit('还剩很多。');
      await service.sendCalls.last.finish();
      await pump2();
      // 编译流此刻才完成。
      service.compileCalls.single.emit(waterEnvelope);
      await service.compileCalls.single.finish();
      await pump2();

      final messages = controller.state.messages;
      expect(messages.length, 4, reason: '种子 2 条 + 新 2 条');
      final newReply = messages.last;
      expect(newReply.text, '还剩很多。');
      expect(newReply.isEditProposal, isFalse, reason: '新回复不挂卡');
      final target = messages.firstWhere((m) => m.id == replyId);
      expect(target.text, waterReply, reason: '旧目标不被 JSON 覆盖');
      expect(target.isEditProposal, isTrue, reason: '卡片仍能完成');
    });

    test('编辑卡一律不进最近对话（防重复计入）；待应用卡改走快照结构化段', () async {
      final clock = _MutableClock(now);
      final service = _DualService();
      final history = _MemoryHistory();
      final registry = ChatEditCommandRegistry();

      ChatEditTurn cardTurn(
        List<Map<String, Object>> items,
        ChatEditRowStatus status,
      ) => ChatEditTurn(
        reply: '',
        rows: [
          for (var i = 0; i < items.length; i++)
            ChatEditTurnItem(
              index: i,
              raw: {
                'action': 'meal.create',
                'args': {
                  'slot': '午餐',
                  'items': [items[i]],
                },
              },
              command: ChatEditCommand(
                spec: registry.specOf('meal.create')!,
                args: {
                  'slot': 'lunch',
                  'items': [items[i]],
                },
              ),
              status: status,
            ),
        ],
      );

      // ① 已全部应用过的卡：内容已经写库，不该再进最近对话。
      history.saved.add(
        ConversationMessage(
          id: 'applied-card',
          role: ConversationRole.assistant,
          text: '我准备记为午餐：米饭 150g。',
          createdAt: now.subtract(const Duration(minutes: 10)),
          kind: ConversationMessageKind.editProposal,
          editTurn: cardTurn([
            {'food': '米饭', 'grams': 150.0},
          ], ChatEditRowStatus.applied),
        ),
      );
      // ② 还挂着待应用行的卡：是有效上下文（用户可能说「刚才那份改一下」）。
      history.saved.add(
        ConversationMessage(
          id: 'pending-card',
          role: ConversationRole.assistant,
          text: '我准备记为晚餐：鸡胸肉 200g。',
          createdAt: now.subtract(const Duration(minutes: 5)),
          kind: ConversationMessageKind.editProposal,
          editTurn: cardTurn([
            {'food': '鸡胸肉', 'grams': 200.0},
          ], ChatEditRowStatus.proposed),
        ),
      );

      final builder = _RecordingBuilder();
      final controller = ConversationController(
        service,
        chatEdit: ChatEditCoordinator(
          contextBuilder: builder,
          executor: _RecordingExecutor(),
        ),
        manualCardGeneration: true,
        clock: clock,
        repository: history,
      );
      await controller.loadHistory();
      await pump2();
      await controller.sendMessage('记 250ml 水');
      service.sendCalls.last.emit('你今天喝了 250 毫升水，我准备帮你记上。');
      await service.sendCalls.last.finish();
      await pump2();

      await controller.generateEditCard(controller.state.messages.last.id);
      await pump2();
      final context = service.compileCalls.single.conversationContext;
      expect(
        context,
        isNot(contains('米饭')),
        reason: '已应用的卡已经写库，再喂给编译器只会让它重复生成',
      );
      expect(
        context,
        isNot(contains('鸡胸肉')),
        reason: '待应用卡也不再塞进对话文本——避免与快照的「尚未应用的提议」段重复',
      );
      // 待应用卡改由**结构化段**注入：编译器仍看得见「刚才那份」是什么。
      final pending = builder.lastPendingProposal;
      expect(pending, isNotNull, reason: '待应用提议必须以结构化段给到编译上下文');
      expect(pending!.commands.single.action, 'meal.create');
      expect(
        (pending.commands.single.args['items'] as List).single,
        containsPair('food', '鸡胸肉'),
      );
    });

    test('最近对话封顶：最多 6 条、单条 ≤600 字、总 ≤3000 字、图片占位', () async {
      final clock = _MutableClock(now);
      final service = _DualService();
      final controller = ConversationController(
        service,
        chatEdit: ChatEditCoordinator(
          contextBuilder: _RecordingBuilder(),
          executor: _RecordingExecutor(),
        ),
        manualCardGeneration: true,
        clock: clock,
      );
      // 铺 8 轮长历史（每条 700 字）+ 一条失败消息。
      for (var i = 0; i < 8; i++) {
        await controller.sendMessage('历史 $i');
        service.sendCalls.last.emit('回' * 700);
        await service.sendCalls.last.finish();
        await pump2();
      }
      final replyId = controller.state.messages.last.id;

      await controller.generateEditCard(replyId);
      await pump2();
      final call = service.compileCalls.single;
      final lines = call.conversationContext.split('\n');
      expect(lines.length, 6, reason: '最多 6 条');
      for (final line in lines) {
        expect(
          line.length,
          lessThanOrEqualTo(600 + '助手：'.length + 1),
          reason: '单条 ≤600 字',
        );
      }
      expect(
        call.conversationContext.length,
        lessThanOrEqualTo(3000 + 6 * 3 + 6),
        reason: '总 ≤3000 字',
      );
      // 最新的 6 条在（更早的 2 条被裁掉）。
      expect(call.conversationContext, contains('历史 7'));
      expect(call.conversationContext, isNot(contains('历史 0')));
    });

    test('编译流已结束、重复探针仍在查询时点取消：迟到的结果不得挂卡', () async {
      // 2026-11-09 全量审查实测洞：`_completeManualCompile` 在
      // `await annotateDuplicates(...)` 之后没有再校验 epoch。真实链路里
      // 探针要查库（几毫秒到几十毫秒），用户完全可能在这个窗口点「取消」
      // ——取消后界面会闪出一张卡，违反 docs/66 §5「迟到事件不得挂卡」。
      final gate = Completer<Map<int, String>>();
      final clock = _MutableClock(now);
      final service = _DualService();
      final history = _MemoryHistory();
      final controller = ConversationController(
        service,
        chatEdit: ChatEditCoordinator(
          contextBuilder: _RecordingBuilder(),
          executor: _RecordingExecutor(),
          duplicateProbe: (turn) => gate.future,
        ),
        manualCardGeneration: true,
        clock: clock,
        repository: history,
      );
      await controller.sendMessage('记 250ml 水');
      service.sendCalls.last.emit(waterReply);
      await service.sendCalls.last.finish();
      await pump2();
      final replyId = controller.state.messages.last.id;

      await controller.generateEditCard(replyId);
      await pump2();
      service.compileCalls.single.emit(waterEnvelope);
      await service.compileCalls.single.finish();
      await pump2();
      // 此刻编译流已收尾，`_completeManualCompile` 卡在探针查询上。
      expect(
        controller.cardGenerationOf(replyId).phase,
        CardGenerationPhase.generating,
        reason: '探针未返回前仍在生成中',
      );

      controller.cancelCardGeneration(replyId);
      expect(
        controller.cardGenerationOf(replyId).phase,
        CardGenerationPhase.idle,
      );

      gate.complete(const {});
      await pump2();
      final after = controller.state.messages.firstWhere(
        (m) => m.id == replyId,
      );
      expect(after.isEditProposal, isFalse, reason: '取消后迟到的编译结果不得挂卡');
      expect(after.text, waterReply, reason: '原文不变');
      expect(history.saved.where((m) => m.isEditProposal), isEmpty);
    });

    test('清空历史时正在生成：取消，完成后不把已删消息写回', () async {
      final history = _MemoryHistory();
      final (service, _, controller, replyId) = await seedProseRound(
        repository: history,
      );
      await controller.generateEditCard(replyId);
      await controller.clearHistory();
      service.compileCalls.single.emit(waterEnvelope);
      await service.compileCalls.single.finish();
      await pump2();

      expect(controller.state.messages, isEmpty);
      expect(
        controller.cardGenerationOf(replyId).phase,
        CardGenerationPhase.idle,
      );
      // 清空后的迟到事件不能把消息写回库。
      final afterClear = history.saved.length;
      await pump2();
      expect(history.saved.length, afterClear);
    });
  });

  // ── 批次 2 · 日期钉定与确认守卫（docs/66 §4.3 #7–8、§5.10、§6.5）────────
  group('批次2 · 日期钉定与确认守卫', () {
    final now = DateTime.parse('2026-11-07T15:00:00+08:00');
    final today = formatLocalDate(now);
    final yesterday = formatLocalDate(now.subtract(const Duration(days: 1)));
    const userText =
        '记 250ml 水、体重 72.5 公斤，水目标 2000 毫升，步数目标 8000，'
        '午餐米饭 150g，另外昨天喝了 100 毫升';
    const prose =
        '我准备帮你记上：250 毫升水、体重 72.5 公斤、'
        '水目标 2000 毫升、步数目标 8000、午餐米饭 150g、昨天 100 毫升。';

    Future<
      (
        _DualService,
        _MutableClock,
        ConversationController,
        String,
        _MemoryHistory,
      )
    >
    seedForPinning({ConfirmEditDates? confirmEditDates}) async {
      final clock = _MutableClock(now);
      final service = _DualService();
      final history = _MemoryHistory();
      final controller = ConversationController(
        service,
        chatEdit: ChatEditCoordinator(
          contextBuilder: _RecordingBuilder(),
          executor: _RecordingExecutor(),
        ),
        manualCardGeneration: true,
        clock: clock,
        repository: history,
        confirmEditDates: confirmEditDates,
      );
      await controller.sendMessage(userText);
      service.sendCalls.last.emit(prose);
      await service.sendCalls.last.finish();
      await pump2();
      return (
        service,
        clock,
        controller,
        controller.state.messages.last.id,
        history,
      );
    }

    test('挂卡时缺省日期钉到目标日（args 与 raw 同步）；steps 保持全局；显式日期保留', () async {
      // $yesterday 内插在 const 里不可用：运行时拼一次。
      final envelope =
          '{"reply":"逐条记。","edits":['
          '{"action":"water.add","args":{"amountMl":250}},'
          '{"action":"weight.log","args":{"weightKg":72.5}},'
          '{"action":"targets.update","args":{"waterMl":2000}},'
          '{"action":"targets.update","args":{"steps":8000}},'
          '{"action":"meal.create","args":{"slot":"午餐",'
          '"items":[{"food":"米饭","grams":150}]}},'
          '{"action":"water.add","args":{"amountMl":100,"localDate":"$yesterday"}}'
          ']}';
      final (service, _, controller, replyId, _) = await seedForPinning();
      await controller.generateEditCard(replyId);
      service.compileCalls.single.emit(envelope);
      await service.compileCalls.single.finish();
      await pump2();

      final turn = controller.state.messages.last.editTurn!;
      expect(turn.rows, hasLength(6));
      String? argDate(int i) =>
          turn.rows[i].command?.args['localDate'] as String?;
      Object? rawDate(int i) {
        final rawArgs = turn.rows[i].raw['args'];
        return rawArgs is Map ? rawArgs['localDate'] : null;
      }

      for (final i in [0, 1, 2, 4]) {
        expect(argDate(i), today, reason: 'row $i 的 command 缺省日期应钉到今天');
        expect(rawDate(i), today, reason: 'row $i 的 raw 必须同步（落库读 raw）');
      }
      // steps-only 的 targets.update：全局语义，不钉日期。
      expect(turn.rows[3].command!.args.containsKey('localDate'), isFalse);
      expect(rawDate(3), isNull);
      // 显式日期保留（用户说「昨天」）。
      expect(argDate(5), yesterday);
      expect(rawDate(5), yesterday);
    });

    test('23:59 生成、次日应用：经确认后仍写生成当天（executor 收到 raw 里的日期）', () async {
      final envelope =
          '{"reply":"记。","edits":['
          '{"action":"water.add","args":{"amountMl":250}},'
          '{"action":"weight.log","args":{"weightKg":72.5}}]}';
      var confirmations = <Set<String>>[];
      final (
        service,
        clock,
        controller,
        replyId,
        history,
      ) = await seedForPinning(
        confirmEditDates: (dates) async {
          confirmations.add(dates);
          return true;
        },
      );
      await controller.generateEditCard(replyId);
      service.compileCalls.single.emit(envelope);
      await service.compileCalls.single.finish();
      await pump2();
      clock.now = now.add(const Duration(days: 1));

      await controller.applyEdits(replyId);
      final executor =
          (controller.chatEdit as ChatEditCoordinator).executor
              as _RecordingExecutor;
      expect(executor.received, hasLength(2));
      expect(
        executor.received[0].args['localDate'],
        today,
        reason: '执行器收到的是生成当天的日期（不漂移到次日）',
      );
      expect(executor.received[1].args['localDate'], today);
      expect(confirmations, hasLength(1), reason: '跨天后应用要确认一次');
      // raw 同步：落库后重载，日期仍来自 raw。
      final saved = history.saved.last;
      final rawArgs = saved.editTurn!.rows.first.raw['args'];
      expect((rawArgs as Map)['localDate'], today);
    });

    test('拒绝 / 未接确认回调：不写库，卡片原样保留', () async {
      final envelope =
          '{"reply":"记昨天。","edits":['
          '{"action":"water.add","args":{"amountMl":100,"localDate":"$yesterday"}}]}';
      // 拒绝。
      final declined = await seedForPinning(
        confirmEditDates: (_) async => false,
      );
      final declinedService = declined.$1;
      final declinedController = declined.$3;
      final declinedReplyId = declined.$4;
      await declinedController.generateEditCard(declinedReplyId);
      declinedService.compileCalls.single.emit(envelope);
      await declinedService.compileCalls.single.finish();
      await pump2();
      await declinedController.applyEdits(declinedReplyId);
      final declinedExecutor =
          (declinedController.chatEdit as ChatEditCoordinator).executor
              as _RecordingExecutor;
      expect(declinedExecutor.received, isEmpty, reason: '拒绝后不写库');
      expect(
        declinedController.state.messages.last.editTurn!.rows.single.status,
        ChatEditRowStatus.proposed,
        reason: '卡片原样保留',
      );

      // 未接线（confirmEditDates = null）：新模式下默认拒绝。
      final unwired = await seedForPinning();
      final unwiredService = unwired.$1;
      final unwiredController = unwired.$3;
      final unwiredReplyId = unwired.$4;
      await unwiredController.generateEditCard(unwiredReplyId);
      unwiredService.compileCalls.single.emit(envelope);
      await unwiredService.compileCalls.single.finish();
      await pump2();
      await unwiredController.applyEdits(unwiredReplyId);
      final unwiredExecutor =
          (unwiredController.chatEdit as ChatEditCoordinator).executor
              as _RecordingExecutor;
      expect(unwiredExecutor.received, isEmpty, reason: '未接线默认拒绝');
    });

    test('旧卡 suggestion 执行前也经日期确认（拒绝/未接线不写库）', () async {
      final clock = _MutableClock(now);
      final service = _DualService();
      final history = _MemoryHistory();
      final confirmCalls = <Set<String>>[];
      final controller = ConversationController(
        service,
        chatEdit: ChatEditCoordinator(
          contextBuilder: _RecordingBuilder(),
          executor: _RecordingExecutor(),
        ),
        manualCardGeneration: true,
        clock: clock,
        repository: history,
        confirmEditDates: (dates) async {
          confirmCalls.add(dates);
          return false; // 拒绝
        },
      );
      final registry = ChatEditCommandRegistry();
      final spec = registry.specOf('water.add')!;
      history.saved.add(
        ConversationMessage(
          id: 'old-card',
          role: ConversationRole.assistant,
          text: '建议',
          createdAt: now,
          kind: ConversationMessageKind.editProposal,
          editTurn: ChatEditTurn(
            reply: '建议',
            rows: const [],
            suggestions: [
              ChatEditSuggestion(
                label: '补记昨天的水',
                command: ChatEditCommand(
                  spec: spec,
                  args: {'amountMl': 100.0, 'localDate': yesterday},
                ),
              ),
            ],
          ),
        ),
      );
      await controller.loadHistory();
      await pump2();

      await controller.applySuggestion('old-card', 0);
      await pump2();
      expect(confirmCalls, hasLength(1));
      expect(confirmCalls.single, {yesterday});
      final executor =
          (controller.chatEdit as ChatEditCoordinator).executor
              as _RecordingExecutor;
      expect(executor.received, isEmpty, reason: '拒绝后 suggestion 不执行');
      final suggestion =
          controller.state.messages.last.editTurn!.suggestions.single;
      expect(suggestion.status, ChatEditRowStatus.proposed);
    });

    test('日期确认回调抛异常 ⇒ 拒绝执行（不写库、卡片原样）', () async {
      final envelope =
          '{"reply":"记昨天。","edits":['
          '{"action":"water.add","args":{"amountMl":100,"localDate":"$yesterday"}}]}';
      final seed = await seedForPinning(
        confirmEditDates: (_) async => throw StateError('dialog disposed'),
      );
      final service = seed.$1;
      final controller = seed.$3;
      final replyId = seed.$4;
      await controller.generateEditCard(replyId);
      service.compileCalls.single.emit(envelope);
      await service.compileCalls.single.finish();
      await pump2();

      await controller.applyEdits(replyId);
      final executor =
          (controller.chatEdit as ChatEditCoordinator).executor
              as _RecordingExecutor;
      expect(executor.received, isEmpty, reason: '确认弹层炸了不等于用户同意');
      expect(
        controller.state.messages.last.editTurn!.rows.single.status,
        ChatEditRowStatus.proposed,
      );
    });

    test('选卡重放：确认一次（重放链路内复用），raw 与 command 同步新引用', () async {
      final clock = _MutableClock(now);
      final service = _DualService();
      final history = _MemoryHistory();
      final confirmCalls = <Set<String>>[];
      final executor = _RecordingExecutor();
      final controller = ConversationController(
        service,
        chatEdit: ChatEditCoordinator(
          contextBuilder: _RecordingBuilder(),
          executor: executor,
        ),
        manualCardGeneration: true,
        clock: clock,
        repository: history,
        confirmEditDates: (dates) async {
          confirmCalls.add(dates);
          return true;
        },
      );
      final registry = ChatEditCommandRegistry();
      final mealEnvelope =
          '{"reply":"帮你记午餐。","edits":[{"action":"meal.create",'
          '"args":{"slot":"午餐","localDate":"$yesterday",'
          '"items":[{"food":"米饭","grams":200}]}}]}';
      final turn = parseChatEditTurn(mealEnvelope, registry)!;
      final row = turn.rows.single;
      final repairedRow = row.copyWith(
        status: ChatEditRowStatus.failed,
        resultMessage: '「米饭」在食物库和菜品库都有；请说明按食物还是按菜品记。',
        repair: ChatEditRepair.chooseCatalog(name: '米饭'),
      );
      history.saved.add(
        ConversationMessage(
          id: 'replay-card',
          role: ConversationRole.assistant,
          text: turn.reply,
          createdAt: now,
          kind: ConversationMessageKind.editProposal,
          editTurn: ChatEditTurn(reply: turn.reply, rows: [repairedRow]),
        ),
      );
      await controller.loadHistory();
      await pump2();

      await controller.retryEditRowWithReference(
        messageId: 'replay-card',
        rowIndex: repairedRow.index,
        originalReference: '米饭',
        newReference: '[dish:d1]',
      );
      await pump2();
      expect(confirmCalls, hasLength(1), reason: '重放链路只确认一次');
      expect(executor.received, hasLength(1), reason: '重放执行一次');
      expect(executor.received.last.args['items'], [
        {'food': '[dish:d1]', 'grams': 200.0},
      ]);
      // 显式日期在重写后保留（重写只换引用）。
      expect(executor.received.last.args['localDate'], yesterday);
      // raw 与 command 都是新引用（落库读 raw）。
      final savedRow = history.saved.last.editTurn!.rows.single;
      final rawItems = (savedRow.raw['args'] as Map)['items'] as List;
      expect((rawItems.single as Map)['food'], '[dish:d1]');
    });

    test('忽略卡片 → 落库 → 重载：仍是 dismissed，不复活成 proposed（§8.1 #26）', () async {
      final (service, _, controller, replyId, history) = await seedForPinning();
      final envelope =
          '{"reply":"记。","edits":['
          '{"action":"water.add","args":{"amountMl":250}}]}';
      await controller.generateEditCard(replyId);
      service.compileCalls.single.emit(envelope);
      await service.compileCalls.single.finish();
      await pump2();
      await controller.dismissEdits(replyId);

      final reloaded = await history.loadRecent();
      expect(
        reloaded.last.editTurn!.rows.single.status,
        ChatEditRowStatus.dismissed,
      );
    });

    test('接地失败：状态行点名具体食物与数值（不是笼统文案）', () async {
      final (service, _, controller, replyId, _) = await seedForPinning();
      await controller.generateEditCard(replyId);
      // 目标回复里只有「250 毫升水」，命令却要记「米饭 987g」——987 无依据。
      service.compileCalls.single.emit(
        '{"reply":"记午餐。","edits":[{"action":"meal.create","args":{'
        '"slot":"午餐","items":[{"food":"米饭","grams":987}]}}]}',
      );
      await service.compileCalls.single.finish();
      await pump2();

      final state = controller.cardGenerationOf(replyId);
      expect(state.phase, CardGenerationPhase.empty);
      expect(state.message, contains('米饭'));
      expect(state.message, contains('987'));
      expect(state.message, isNot(contains('有数值没法核对')), reason: '不再用笼统文案');
      expect(controller.state.messages.last.isEditProposal, isFalse);
    });

    test('suggestions 在手动结果里被丢弃：有行时不出 chip；只有 suggestions 时按 empty', () async {
      // 有 rows + suggestions ⇒ rows 挂卡，suggestions 丢弃。
      final (service, _, controller, replyId, _) = await seedForPinning();
      await controller.generateEditCard(replyId);
      service.compileCalls.single.emit(
        '{"reply":"记水。","edits":[{"action":"water.add","args":{"amountMl":250}}],'
        '"suggestions":[{"label":"记 999ml","action":"water.add",'
        '"args":{"amountMl":999}}]}',
      );
      await service.compileCalls.single.finish();
      await pump2();
      final turn = controller.state.messages.last.editTurn!;
      expect(turn.rows, hasLength(1));
      expect(turn.suggestions, isEmpty, reason: '手动结果丢弃 suggestions');

      // 只有 suggestions ⇒ empty（不出现可一键写库的 chip）。
      final second = await seedForPinning();
      await second.$3.generateEditCard(second.$4);
      second.$1.compileCalls.single.emit(
        '{"reply":"缺克数。","edits":[],"suggestions":[{"label":"记 999ml",'
        '"action":"water.add","args":{"amountMl":999}}]}',
      );
      await second.$1.compileCalls.single.finish();
      await pump2();
      final state = second.$3.cardGenerationOf(second.$4);
      expect(state.phase, CardGenerationPhase.empty);
      expect(second.$3.state.messages.last.isEditProposal, isFalse);
    });
  });
}

// ── 批次 2 专用替身 ──────────────────────────────────────────────────────

/// 只实现对话服务的最小替身（未实现编译器 ⇒ canGenerateCard 必须为 false）。
final class _ManualOnlyService implements AiConversationService {
  @override
  Stream<String> sendMessage({
    required List<ConversationMessage> messages,
    required void Function(String chunk) onProgress,
    Stream<void>? cancelToken,
    String? systemContext,
  }) async* {}
}

/// 记录收到的命令的执行器（日期钉定/确认守卫断言用）。
final class _RecordingExecutor implements ChatEditExecutor {
  final List<ChatEditCommand> received = [];

  @override
  Future<ChatEditApplyResult> apply(ChatEditCommand command) async {
    received.add(command);
    return const ChatEditApplyResult.ok('已完成。');
  }
}

ChatEditCommand _waterCommand(num amountMl) {
  final registry = ChatEditCommandRegistry();
  final spec = registry.specOf('water.add')!;
  return ChatEditCommand(spec: spec, args: {'amountMl': amountMl.toDouble()});
}
