import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:localfit_ai/core/errors/app_failure.dart';
import 'package:localfit_ai/features/ai/domain/ai_connectivity_monitor.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/features/ai_conversation/application/chat_edit_coordinator.dart';
import 'package:localfit_ai/features/ai_conversation/domain/ai_conversation_service.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_image.dart';
import 'package:localfit_ai/features/ai_conversation/domain/conversation_message.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_reply_display.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_context_builder.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_turn.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_intent.dart';
import 'package:localfit_ai/features/ai_conversation/domain/conversation_message_repository.dart';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';

/// AI 对话控制器状态。
@immutable
final class ConversationState {
  const ConversationState({
    this.messages = const [],
    this.status = ConversationStatus.idle,
    this.error,
    this.loadError,
    this.persistError,
  });

  final List<ConversationMessage> messages;
  final ConversationStatus status;
  final String? error;

  /// 历史载入失败（docs/21 §5.8.1：读取失败必须与「没有记录」可区分）。
  final String? loadError;

  /// 落库失败（消息已在屏幕上，但重启后会丢——必须如实告知）。
  final String? persistError;

  ConversationState copyWith({
    List<ConversationMessage>? messages,
    ConversationStatus? status,
    String? error,
    String? loadError,
    bool clearLoadError = false,
    String? persistError,
    bool clearPersistError = false,
  }) {
    return ConversationState(
      messages: messages ?? this.messages,
      status: status ?? this.status,
      error: error,
      loadError: clearLoadError ? null : (loadError ?? this.loadError),
      persistError: clearPersistError
          ? null
          : (persistError ?? this.persistError),
    );
  }
}

/// 对话控制器状态机：idle → sending → aiReply → done/error
enum ConversationStatus { idle, sending, aiReply, error }

/// 在一次请求里累积的流式回复。
final class _PendingReply {
  _PendingReply(this.id, {this.userMessageId, this.userText});

  final String id;
  final StringBuffer buffer = StringBuffer();

  /// 这条回复对应哪条用户消息、用户说了什么（信封重试用：判断「这是不是一次
  /// 修改请求」，以及重跑时取同一段历史）。
  final String? userMessageId;
  final String? userText;
}

/// AI 对话控制器。
///
/// 管理消息列表、发送流程、打字状态。使用 ChangeNotifier 保持
/// 状态可观察（docs/21 §5.4 对话式识别扩展 / §5.7 AI 对话页）。
///
/// [repository] 非 null 时聊天记录落库（docs/21 §5.7「新增域：聊天记录」）；
/// 未接线时对话仍是完整可用的，只是重启后不留历史。
class ConversationController extends ChangeNotifier {
  ConversationController(
    this._service, {
    this.repository,
    this.chatEdit,
    AppClock? clock,
    this.connectivity,
  }) : _clock = clock ?? const SystemAppClock();

  final AiConversationService? _service;

  /// 聊天记录仓储；null = 不落库（重启不留历史）。
  final ConversationMessageRepository? repository;

  /// 通用编辑协调器（docs/23）；null = 纯聊天，编辑卡相关路径全部不激活。
  final ChatEditCoordinator? chatEdit;

  final AppClock _clock;

  /// 断网证据（2026-10-21 裁决 D-2）：只记录「连接失败」，不新增依赖。
  final AiConnectivityMonitor? connectivity;

  final _uuid = const Uuid();

  ConversationState _state = const ConversationState();

  ConversationState get state => _state;

  /// 是否正在等待/接收 AI 回复（`sending` / `aiReply`）。
  ///
  /// **错误态不算进行中**：错误态必须允许用户直接发下一条或点重试，
  /// 否则一次上游报错就会把输入栏永久锁死。[_send] / [retryLast] 的闸门
  /// 都用它，不用「status != idle」。
  bool get isReplying =>
      _state.status == ConversationStatus.sending ||
      _state.status == ConversationStatus.aiReply;

  StreamSubscription<String>? _subscription;
  StreamController<void>? _cancelController;
  _PendingReply? _pending;
  bool _disposed = false;

  /// 正在应用编辑卡的消息 id（双击守卫）。
  final Set<String> _applyingEditIds = {};

  /// 已经为哪条用户消息**自动**催过信封（每轮最多一次，防打转）。
  final Set<String> _envelopeRetriedUserIds = {};

  /// 用户在修改请求下只拿到纯文本、且自动催过一次的助手消息 id。
  ///
  /// 只为「残留」那一步给气泡渲染一枚「让 AI 给出可应用的修改」用；**内存态**
  /// （不落库）：重启后这枚入口消失，文字仍在，用户可以直接再说一遍——比往
  /// 消息表加列（schema 变更，禁区）划算。
  final Set<String> _envelopeRetryOffers = {};

  /// 这条助手消息是否处在「修改请求却没拿到信封」的残留态（页面据此给手动词条）。
  ///
  /// 两条来源：① 本会话里自动催过仍失败（内存标记）；② **从落库的消息本身
  /// 重算**——「最后一条助手回复是纯文本，而它对应的用户消息是修改请求」。
  /// ② 让这个入口**扛得住重启**（内存标记不落库，但两条消息都在库里），
  /// 且只对**对话末尾**生效：历史消息不给词条（否则翻旧账时到处是按钮）。
  bool needsEnvelopeRetry(String messageId) {
    if (_envelopeRetryOffers.contains(messageId)) return true;
    if (chatEdit == null) return false;
    final messages = _state.messages;
    if (messages.isEmpty) return false;
    final last = messages.last;
    if (last.id != messageId) return false;
    if (last.role != ConversationRole.assistant || last.isEditProposal) {
      return false;
    }
    if (last.status != ConversationMessageStatus.sent) return false;
    final userIndex = messages.lastIndexWhere(
      (m) => m.role == ConversationRole.user,
    );
    if (userIndex == -1) return false;
    return looksLikeModificationRequest(messages[userIndex].text);
  }

  void _updateState(ConversationState newState) {
    if (_disposed) return;
    _state = newState;
    notifyListeners();
  }

  /// 载入历史（页面初始化时调用一次）。失败时只置 [ConversationState.loadError]。
  /// 清空聊天历史（`RV4-P2-06`）：先停流、清内存、再真删库，返回删除条数。
  ///
  /// **破坏性操作**：UI 必须二次确认并如实报数。图片副本不在这里清
  /// （那是 `ChatImageStore.clearAll`，由页面一并做）。
  Future<int> clearHistory() async {
    final repository = this.repository;
    if (isReplying) await cancel();
    _updateState(_state.copyWith(messages: const [], clearLoadError: true));
    if (repository == null) return 0;
    try {
      return await repository.clear();
    } on Object {
      if (!_disposed) {
        _updateState(_state.copyWith(loadError: '聊天记录清除失败，请重试。'));
      }
      return 0;
    }
  }

  Future<void> loadHistory() async {
    final repository = this.repository;
    if (repository == null) return;
    try {
      final loaded = await repository.loadRecent();
      if (_disposed) return;
      // 载入期间用户可能已经开了新对话：历史在前，本会话在后。
      final currentIds = {for (final m in _state.messages) m.id};
      _updateState(
        _state.copyWith(
          messages: [
            for (final m in loaded)
              if (!currentIds.contains(m.id)) m,
            ..._state.messages,
          ],
          clearLoadError: true,
        ),
      );
    } on Object {
      if (_disposed) return;
      _updateState(_state.copyWith(loadError: '聊天记录读取失败，请重试。'));
    }
  }

  /// 发送一条文本消息。
  Future<void> sendMessage(String text) => sendMessageWithWire(text);

  /// 发送一条消息，允许**显示文本与发送文本不同**（`RV4-P2-03` / D5）。
  ///
  /// [wireText] 为 null 时两者相同。食堂「AI 分析」把 `[canteen-dish:<id>]`
  /// 只放进 wireText：用户气泡只显示菜名，模型仍拿到定位 id（`canteen.
  /// dish.nutrition` 要它）。**不落库**（见 `ConversationMessage.wireText`）。
  Future<void> sendMessageWithWire(String text, {String? wireText}) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return Future<void>.value();
    final wire = wireText?.trim();
    return _send(
      kind: ConversationMessageKind.text,
      displayText: trimmed,
      turnText: (wire == null || wire.isEmpty) ? trimmed : wire,
      wireText: (wire == null || wire.isEmpty) ? null : wire,
    );
  }

  /// 发送一条图片消息。
  ///
  /// **图片本体随这条消息真的发出去**（2026-10-16，S1）：请求体按供应商协议
  /// 拼成多模态块（服务层读 [ChatImage.path] 的字节）。模型看不看得懂图由
  /// 供应商自己决定并如实报错——App 既不假装「已看到」，也不再说「没发送」
  /// （那句话正是本轮修掉的缺陷：图其实能发，却被 App 挡在本地）。
  Future<void> sendImageMessage({required ChatImage image, String? caption}) {
    final trimmedCaption = caption?.trim() ?? '';
    final note = '（附了一张图片《${image.fileName}》）';
    return _send(
      kind: ConversationMessageKind.image,
      displayText: trimmedCaption,
      turnText: trimmedCaption.isEmpty ? note : '$note $trimmedCaption',
      imagePath: image.path,
    );
  }

  Future<void> _send({
    required ConversationMessageKind kind,
    required String displayText,
    required String turnText,
    String? imagePath,
    String? wireText,
  }) async {
    final service = _service;
    if (service == null) {
      _updateState(
        _state.copyWith(
          status: ConversationStatus.error,
          error: 'AI 服务尚未配置，请在「设置」中完成 AI 提供方与 API Key。',
        ),
      );
      return;
    }
    // 上一轮还没结束就不接受新消息：不做无确认的并发请求。
    if (isReplying) return;

    final userMessage = ConversationMessage(
      id: _uuid.v4(),
      role: ConversationRole.user,
      text: displayText,
      createdAt: _clock.nowUtc(),
      status: ConversationMessageStatus.sent,
      kind: kind,
      imagePath: imagePath,
      // `turnText` 是给模型的正文（见 `sendMessageWithWire`）；它与显示文本
      // 不同时记进 `wireText`，请求侧读 `textForRequest`。
      wireText: (wireText == null || wireText == displayText) ? null : wireText,
    );
    final assistantMessage = ConversationMessage(
      id: _uuid.v4(),
      role: ConversationRole.assistant,
      text: '',
      createdAt: _clock.nowUtc(),
      status: ConversationMessageStatus.sending,
    );

    // 请求上下文 = 已完成的对话 + 本条用户消息；占位与失败气泡都不进上下文。
    final history = [
      for (final m in _state.messages)
        if (m.status == ConversationMessageStatus.sent) _forRequest(m),
      _forRequest(userMessage),
    ];

    _updateState(
      _state.copyWith(
        messages: [..._state.messages, userMessage, assistantMessage],
        status: ConversationStatus.sending,
        error: null,
      ),
    );

    // 「待回」标记必须在落库之前立起来：drift 写盘是真异步，这段窗口里
    // 停止按钮已经可见，用户可能就在这段时间点了停止。晚立标记会让那次
    // 停止被静默丢掉、占位气泡永远留在列表里（阶段 G 页面测试抓到的缺陷）。
    final pending = _PendingReply(
      assistantMessage.id,
      userMessageId: userMessage.id,
      userText: userMessage.text,
    );
    _pending = pending;
    await _persist(userMessage);
    if (_pending != pending) return; // 落库窗口内被取消
    // 快照在落库窗口之后构建：拿到的状态越接近发送时刻越准；构建失败
    // 返回 null，对话照常（docs/23 §3 绝不为快照挡住对话）。
    // 用户消息一并传入：快照构建器做消息相关的食物库预检索（docs/40 §2.4）。
    // 待应用的上一张卡也一并传入（2026-10-24 多轮实测）：否则用户对着那张
    // 卡改口时，模型只看得见数据库里「还没有这条记录」，会把用户打发去
    // 「先应用、再说一遍」。
    final systemContext = await chatEdit?.buildSystemContext(
      userMessage: userMessage.text,
      pendingProposal: _latestPendingProposal(),
    );
    if (_pending != pending) return; // 快照窗口内被取消
    _runRequest(
      service,
      pending: pending,
      history: history,
      systemContext: systemContext,
    );
  }

  /// 重试最后一条失败的助手回复：**就地复用**那个气泡（不新增一条），
  /// 上下文取它对应的那条用户消息及其之前的已完成消息。
  Future<void> retryLast() async {
    final service = _service;
    if (service == null) {
      _updateState(
        _state.copyWith(
          status: ConversationStatus.error,
          error: 'AI 服务尚未配置，请在「设置」中完成 AI 提供方与 API Key。',
        ),
      );
      return;
    }
    // 错误态不是「进行中」：重试必须能跑（否则错误气泡上的重试是死按钮）。
    if (isReplying) return;

    final messages = _state.messages;
    final assistantIndex = messages.lastIndexWhere(
      (m) =>
          m.role == ConversationRole.assistant &&
          m.status == ConversationMessageStatus.error,
    );
    if (assistantIndex == -1) return;
    final userIndex = messages.lastIndexWhere(
      (m) => m.role == ConversationRole.user,
      assistantIndex,
    );
    if (userIndex == -1) return;

    final assistantId = messages[assistantIndex].id;
    final history = [
      for (final m in messages.take(userIndex + 1))
        if (m.status == ConversationMessageStatus.sent) _forRequest(m),
    ];

    _updateState(
      _state.copyWith(
        messages: [
          for (final m in messages)
            if (m.id == assistantId)
              m.copyWith(text: '', status: ConversationMessageStatus.sending)
            else
              m,
        ],
        status: ConversationStatus.sending,
        error: null,
      ),
    );

    // 重试同一条请求：预检索用重试的那条用户消息（历史里最后一条用户发言）。
    final systemContext = await chatEdit?.buildSystemContext(
      userMessage: messages[userIndex].text,
    );
    if (_pending != null) return; // 快照窗口内来了新请求，让位
    _runRequest(
      service,
      pending: _PendingReply(assistantId),
      history: history,
      systemContext: systemContext,
    );
  }

  /// 最近一条**还挂着待应用行**的编辑卡（2026-10-24 多轮实测）。
  ///
  /// 只看最后几条助手消息：用户可能已经翻过很多轮，太久以前的卡片再告诉
  /// 模型只会干扰它。找不到就返回 null（快照不出该段，行为与改动前一致）。
  PendingProposal? _latestPendingProposal() {
    for (final message in _state.messages.reversed) {
      final turn = message.editTurn;
      if (turn == null) continue;
      final pending = [
        for (final row in turn.rows)
          if (row.status == ChatEditRowStatus.proposed && row.command != null)
            (action: row.command!.action, args: row.command!.args),
      ];
      if (pending.isEmpty) continue;
      return PendingProposal(summary: turn.reply.trim(), commands: pending);
    }
    return null;
  }

  /// 请求里发出去的文本：图片消息把「附了一张图片」如实写进正文（图本体由
  /// 服务层按协议拼成多模态块）。
  ConversationMessage _forRequest(ConversationMessage message) {
    // `RV4-P2-03`：显示/发送分离——请求侧一律读 `textForRequest`。
    if (message.role == ConversationRole.user &&
        message.wireText != null &&
        message.wireText!.trim().isNotEmpty) {
      return message.copyWith(text: message.wireText!.trim());
    }
    if (message.kind != ConversationMessageKind.image ||
        message.role != ConversationRole.user) {
      return message;
    }
    final imagePath = message.imagePath;
    final name = imagePath == null ? '图片' : path.basename(imagePath);
    final note = '（附了一张图片《$name》）';
    final caption = message.text.trim();
    return message.copyWith(text: caption.isEmpty ? note : '$note $caption');
  }

  void _runRequest(
    AiConversationService service, {
    required _PendingReply pending,
    required List<ConversationMessage> history,
    String? systemContext,
  }) {
    final assistantId = pending.id;
    _pending = pending;
    _cancelController = StreamController<void>();
    _subscription = service
        .sendMessage(
          messages: history,
          onProgress: (chunk) {
            // 已取消/已收尾的请求不再改列表（取消后到达的分片必须丢弃）。
            if (_pending?.id != assistantId || _disposed) return;
            pending.buffer.write(chunk);
            _updateAssistantMessage(assistantId, pending.buffer.toString());
          },
          cancelToken: _cancelController?.stream,
          systemContext: systemContext,
        )
        .listen(
          (_) {},
          onDone: () => _completeReply(assistantId),
          // 传**原始错误对象**：翻译成用户话术是控制器的事（`safeFailureText`
          // 只认 AppFailure 的 message；其它一律回落固定文案）——直接
          // `toString()` 会把 `NetworkFailure: …` 这样的类名甩到界面上。
          onError: (Object error) =>
              _completeReply(assistantId, failure: error),
        );
  }

  void _completeReply(String assistantId, {Object? failure}) {
    final pending = _pending;
    if (pending == null || pending.id != assistantId) return;
    _pending = null;
    final text = pending.buffer.toString();
    if (failure == null) _promoteEditTurn(assistantId, text);
    // 2026-10-16 设备实测缺陷：失败时气泡只写「发送失败，点击重试。」——
    // 因为气泡文本取的只是**已生成的分片**（失败那一刻通常是空串），而原因
    // 被塞进 state.error 且没人渲染。用户因此只知道「失败了」，不知道是断网、
    // 超时还是 Key 不对（同一时刻设置页的探针却写着「网络连接不可用…」）。
    // 现在：失败原因经 `safeFailureText` 翻成人话，**并进气泡文本**；分片非空
    // 时保留分片（不覆盖已经生成的内容），原因另起一段交给页面渲染。
    // 断网证据：失败时记一笔、成功时清掉（恢复网络后提示要自己消失）。
    if (failure == null) {
      connectivity?.recordSuccess();
    } else {
      connectivity?.record(failure);
    }
    final reason = failure == null
        ? null
        : safeFailureText(failure, fallback: '发送失败，请稍后重试。');
    final display = _displayOf(assistantId) ?? text;
    // 2026-10-24 用户：「食堂菜品 AI 分析会转发英文代码片段」「很多次推不了
    // 应用卡片」——模型把信封写坏时原始 JSON 会以纯文本回退上屏；这里在**上屏
    // 前**清洗：半截信封换成人话（并保留手动重来的入口），正常回复剥掉
    // `[canteen-dish:…]` 这类内部引用。
    final shown = display.trim().isEmpty && reason != null ? reason : display;
    _finalizeAssistantMessage(
      assistantId,
      replyTextForDisplay(shown),
      error: reason,
    );
    final finalized = _messageById(assistantId);
    if (finalized != null) unawaited(_persist(finalized));
    // 2026-10-16（用户：「涉及修改就必须正确识别指令，而不是空回文字」）：
    // 用户这条是修改请求、模型却只回了文字 ⇒ **自动催一次**信封。
    if (failure == null) {
      unawaited(_maybeRetryForEnvelope(assistantId, pending));
    }
  }

  /// 修改请求只拿到纯文本时，自动带「必须出信封」提示重跑一次（每轮一次）。
  Future<void> _maybeRetryForEnvelope(
    String assistantId,
    _PendingReply pending,
  ) async {
    final coordinator = chatEdit;
    if (coordinator == null || _disposed) return;
    final message = _messageById(assistantId);
    if (message == null || message.isEditProposal) return; // 已经是信封
    final userText = pending.userText;
    final userId = pending.userMessageId;
    if (userText == null || userId == null) return;
    if (!looksLikeModificationRequest(userText)) return;
    if (!_envelopeRetriedUserIds.add(userId)) return;
    // 残留态先记账（催完还是文字时，气泡上给手动词条）。
    _envelopeRetryOffers.add(assistantId);
    notifyListeners();
    await _rerunForEnvelope(assistantId);
  }

  /// 带提示重跑一次并复用同一个助手气泡（不新增用户消息）。
  ///
  /// 「用户这条是修改请求」写进 system 段而不是插一条假的用户消息：后者会
  /// 污染对话历史（历史是用户自己说过的话的账本）。
  Future<void> _rerunForEnvelope(
    String assistantId, {
    String? overrideNudge,
  }) async {
    final service = _service;
    if (service == null || _disposed || isReplying) return;
    final messages = _state.messages;
    final assistantIndex = messages.indexWhere((m) => m.id == assistantId);
    if (assistantIndex == -1) return;
    final userIndex = messages.lastIndexWhere(
      (m) => m.role == ConversationRole.user,
      assistantIndex,
    );
    if (userIndex == -1) return;
    final history = [
      for (final m in messages.take(userIndex + 1))
        if (m.status == ConversationMessageStatus.sent) _forRequest(m),
    ];
    // 重跑同样带上该条用户消息（预检索与新发送同口径）。
    final context = await chatEdit?.buildSystemContext(
      userMessage: messages[userIndex].text,
    );
    if (_disposed || isReplying) return;
    _updateState(
      _state.copyWith(
        messages: [
          for (final m in messages)
            if (m.id == assistantId)
              m.copyWith(text: '', status: ConversationMessageStatus.sending)
            else
              m,
        ],
        status: ConversationStatus.sending,
        error: null,
      ),
    );
    _runRequest(
      service,
      pending: _PendingReply(assistantId),
      history: history,
      systemContext: [
        ?context,
        overrideNudge ?? chatEditEnvelopeNudge,
      ].join('\n\n'),
    );
  }

  /// 用户手动点「让 AI 给出可应用的修改」：再催一次（不受「每轮一次」限制，
  /// 因为这是用户自己按的）。
  Future<void> requestEnvelope(String messageId) async {
    if (_disposed) return;
    final message = _messageById(messageId);
    if (message == null || message.role != ConversationRole.assistant) return;
    await _rerunForEnvelope(
      messageId,
      overrideNudge: chatEditEnvelopeNudgeQuoting(message.text),
    );
  }

  /// 回复完成时尝试把信封升格成编辑卡（docs/23 §1）：成功则气泡文本换成
  /// reply、挂上 [ChatEditTurn]；失败/纯文本则原样保留。
  void _promoteEditTurn(String assistantId, String rawOutput) {
    final coordinator = chatEdit;
    if (coordinator == null) return;
    final turn = coordinator.decode(rawOutput);
    if (turn == null) return;
    // 拿到信封就不再是「残留态」：气泡上的手动词条随之撤下。
    _envelopeRetryOffers.remove(assistantId);
    _updateState(
      _state.copyWith(
        messages: [
          for (final msg in _state.messages)
            if (msg.id == assistantId)
              msg.copyWith(
                text: stripInternalRefs(turn.reply),
                kind: ConversationMessageKind.editProposal,
                editTurn: turn,
              )
            else
              msg,
        ],
      ),
    );
    // 再审查（2026-10-24 用户：「要有自己的去重和检测遗漏的机制」）。
    // 结果只往上贴警告，**不阻断应用、不改数据**。
    unawaited(_auditProposal(assistantId, turn));
  }

  /// 审查这条提议（餐次不符 / 重复食物 / 疑似遗漏），把警告贴到消息上。
  ///
  /// 失败一律**静默忽略**：审查是旁注，不值得为它挡住对话，更不能因为审查
  /// 报错让卡片用不了（与快照段级失败同一哲学）。
  Future<void> _auditProposal(String assistantId, ChatEditTurn turn) async {
    final auditor = chatEdit?.auditor;
    if (auditor == null) return;
    if (!turn.rows.any((row) => row.command?.action == 'meal.create')) return;
    final userText = _lastUserTextBefore(assistantId);
    if (userText == null || userText.trim().isEmpty) return;
    try {
      final warnings = await auditor.audit(
        userText: userText,
        commands: [
          for (final row in turn.rows)
            if (row.status == ChatEditRowStatus.proposed && row.command != null)
              row.command!,
        ],
      );
      if (warnings.isEmpty) return;
      // 这里**不需要**额外的 `_disposed` 守卫：`_updateState` 内部第一行就是
      // `if (_disposed) return;`。2026-10-25 审计时一度以为漏了，加了守卫
      // 并写测试，但变异验证证明那条测试抓不到任何东西（去掉守卫照样绿）
      // ——因为销毁保护本来就在 `_updateState` 里。已撤回，不留假防御。
      _updateState(
        _state.copyWith(
          messages: [
            for (final msg in _state.messages)
              if (msg.id == assistantId && msg.editTurn != null)
                msg.copyWith(editTurn: msg.editTurn!.withWarnings(warnings))
              else
                msg,
          ],
        ),
      );
    } on Object {
      // 审查是旁注，失败不影响对话与卡片。
    }
  }

  /// 找 [assistantId] 这条助手消息**之前**最近的一条用户消息文本。
  String? _lastUserTextBefore(String assistantId) {
    final messages = _state.messages;
    final index = messages.indexWhere((m) => m.id == assistantId);
    final start = index < 0 ? messages.length - 1 : index - 1;
    for (var i = start; i >= 0; i--) {
      final message = messages[i];
      if (message.role == ConversationRole.user) {
        return message.wireText ?? message.text;
      }
    }
    return null;
  }

  /// 编辑卡消息的展示文本是 reply（信封 JSON 绝不上屏）。
  String? _displayOf(String assistantId) {
    for (final msg in _state.messages) {
      if (msg.id == assistantId && msg.isEditProposal) return msg.text;
    }
    return null;
  }

  void _updateAssistantMessage(String id, String text) {
    _updateState(
      _state.copyWith(
        messages: [
          for (final msg in _state.messages)
            if (msg.id == id)
              msg.copyWith(
                text: text,
                status: ConversationMessageStatus.sending,
              )
            else
              msg,
        ],
      ),
    );
  }

  void _finalizeAssistantMessage(String id, String text, {String? error}) {
    _updateState(
      _state.copyWith(
        messages: [
          for (final msg in _state.messages)
            if (msg.id == id)
              msg.copyWith(
                text: text,
                status: error == null
                    ? ConversationMessageStatus.sent
                    : ConversationMessageStatus.error,
              )
            else
              msg,
        ],
        status: error == null
            ? ConversationStatus.idle
            : ConversationStatus.error,
        error: error,
      ),
    );
  }

  /// 取消当前请求：保留已生成的部分文本，并且**必须回到 idle**——否则
  /// 输入栏会永远停在「停止」态，用户再也发不出下一条消息。
  Future<void> cancel() async {
    final pending = _pending;
    _pending = null;
    // **先落状态、后取消传输**：`Subscription.cancel()` 的完成时机由流实现
    // 决定（可能要等对端断开、甚至不完成），界面绝不能等它——否则用户点
    // 「停止」看起来毫无反应，占位气泡与停止按钮会一直挂着
    // （阶段 G 页面测试实测：await 它时状态更新要等到测试收尾才发生）。
    final cancelController = _cancelController;
    _cancelController = null;
    final subscription = _subscription;
    _subscription = null;
    cancelController?.close();
    unawaited(subscription?.cancel());

    if (pending == null) {
      // 没有在飞的请求也要保证不在「回复中」态（防御：任何残留的
      // sending/aiReply 都会让输入栏的停止按钮换不回来）。
      if (_state.status != ConversationStatus.idle) {
        _updateState(
          _state.copyWith(status: ConversationStatus.idle, error: null),
        );
      }
      return;
    }

    final text = pending.buffer.toString();
    if (text.trim().isEmpty) {
      // 一个字都没生成：移除占位气泡，不留空气泡。
      _updateState(
        _state.copyWith(
          messages: [
            for (final msg in _state.messages)
              if (msg.id != pending.id) msg,
          ],
          status: ConversationStatus.idle,
          error: null,
        ),
      );
      return;
    }
    _finalizeAssistantMessage(pending.id, text);
    final finalized = _messageById(pending.id);
    if (finalized != null) await _persist(finalized);
  }

  /// 应用一条编辑卡上的提议（docs/23 §5）：逐条执行、逐条回写结果。
  ///
  /// [rowIndexes] 非空 = 只应用这些行（编辑卡按类分组的「应用本组」）；
  /// null = 全部应用。未选中的行保持 proposed，之后仍可单独应用。
  ///
  /// 守卫：只有「存在 proposed 行且当前不在应用中」的卡才能进；双击/并发
  /// 由 [_applyingEditIds] 挡住——executor 每条都是真写库，重复应用就是
  /// 重复数据。
  Future<void> applyEdits(String messageId, {Set<int>? rowIndexes}) async {
    final coordinator = chatEdit;
    if (coordinator == null || _disposed) return;
    if (_applyingEditIds.contains(messageId)) return;
    final message = _messageById(messageId);
    final turn = message?.editTurn;
    if (message == null || turn == null || !turn.hasProposed) return;
    final selected = rowIndexes == null
        ? null
        : {
            for (final row in turn.rows)
              if (row.status == ChatEditRowStatus.proposed) row.index,
          }.intersection(rowIndexes);
    if (selected != null && selected.isEmpty) return;

    _applyingEditIds.add(messageId);
    _updateTurn(
      messageId,
      turn,
      rows: [
        for (final row in turn.rows)
          if (row.status == ChatEditRowStatus.proposed &&
              row.command != null &&
              (selected == null || selected.contains(row.index)))
            row.copyWith(status: ChatEditRowStatus.applying)
          else
            row,
      ],
    );
    try {
      final applied = await coordinator.applyProposed(
        _messageById(messageId)?.editTurn ?? turn,
        onlyIndexes: selected,
      );
      if (_disposed) return;
      _updateTurn(messageId, applied);
      final finalized = _messageById(messageId);
      if (finalized != null) await _persist(finalized);
    } finally {
      _applyingEditIds.remove(messageId);
    }
  }

  /// 忽略一条编辑卡：全部 proposed 行置为 dismissed，结果随卡落库。
  Future<void> dismissEdits(String messageId) async {
    if (_disposed) return;
    final message = _messageById(messageId);
    final turn = message?.editTurn;
    if (message == null || turn == null || !turn.hasProposed) return;
    if (_applyingEditIds.contains(messageId)) return;
    _updateTurn(
      messageId,
      turn,
      rows: [
        for (final row in turn.rows)
          row.status == ChatEditRowStatus.proposed
              ? row.copyWith(status: ChatEditRowStatus.dismissed)
              : row,
      ],
    );
    final finalized = _messageById(messageId);
    if (finalized != null) await _persist(finalized);
  }

  /// 应用一条「推荐按钮」（2026-10-16 用户：对话里遇到问题要弹可点按钮）。
  ///
  /// 点了就等于应用这条命令——与编辑卡同一个执行器、同一条「只有用户主动
  /// 点才写库」的硬规则（点按钮本身就是那次主动）。守卫与 `applyEdits`
  /// 同源：同一条消息在应用中时不重入；已应用/已失败/已忽略的按钮不再可点。
  Future<void> applySuggestion(String messageId, int suggestionIndex) async {
    final coordinator = chatEdit;
    if (coordinator == null || _disposed) return;
    if (_applyingEditIds.contains(messageId)) return;
    final message = _messageById(messageId);
    final turn = message?.editTurn;
    if (turn == null) return;
    if (suggestionIndex < 0 || suggestionIndex >= turn.suggestions.length) {
      return;
    }
    final suggestion = turn.suggestions[suggestionIndex];
    if (suggestion.status != ChatEditRowStatus.proposed) return;
    // `ai-live` 实测（2026-10-24）：参数不全的建议是「待补信息的入口」，
    // 不是可直接执行的命令——点了不能让用户觉得「按了没反应」，也不能
    // 拿空参数去写库。这里如实标成失败并给出原因（UI 会把 message 显示出来）。
    final command = suggestion.command;
    if (command == null) {
      _updateSuggestion(
        messageId,
        suggestionIndex,
        ChatEditRowStatus.failed,
        resultMessage: '这个操作还差信息（例如具体哪一餐 / 哪一条），先补一句我再执行。',
      );
      final partial = _messageById(messageId);
      if (partial != null) await _persist(partial);
      return;
    }

    _applyingEditIds.add(messageId);
    _updateSuggestion(messageId, suggestionIndex, ChatEditRowStatus.applying);
    try {
      final result = await coordinator.applyOne(command);
      if (_disposed) return;
      _updateSuggestion(
        messageId,
        suggestionIndex,
        result.ok ? ChatEditRowStatus.applied : ChatEditRowStatus.failed,
        resultMessage: result.message,
      );
      final finalized = _messageById(messageId);
      if (finalized != null) await _persist(finalized);
    } finally {
      _applyingEditIds.remove(messageId);
    }
  }

  /// 就地改一条推荐按钮的状态（其余行/按钮原样保留）。
  void _updateSuggestion(
    String messageId,
    int suggestionIndex,
    ChatEditRowStatus status, {
    String? resultMessage,
  }) {
    final message = _messageById(messageId);
    final turn = message?.editTurn;
    if (turn == null) return;
    final updated = ChatEditTurn(
      reply: turn.reply,
      rows: turn.rows,
      suggestions: [
        for (var i = 0; i < turn.suggestions.length; i++)
          if (i == suggestionIndex)
            turn.suggestions[i].copyWith(
              status: status,
              resultMessage: resultMessage,
            )
          else
            turn.suggestions[i],
      ],
    );
    _updateState(
      _state.copyWith(
        messages: [
          for (final msg in _state.messages)
            if (msg.id == messageId)
              msg.copyWith(text: updated.reply, editTurn: updated)
            else
              msg,
        ],
      ),
    );
  }

  void _updateTurn(
    String messageId,
    ChatEditTurn turn, {
    List<ChatEditTurnItem>? rows,
  }) {
    final message = _messageById(messageId);
    if (message == null) return;
    final updated = rows == null
        ? turn
        : ChatEditTurn(
            reply: turn.reply,
            rows: rows,
            // 推荐按钮与行状态是两条独立通道：重建行时不许顺手丢掉按钮。
            suggestions: turn.suggestions,
          );
    _updateState(
      _state.copyWith(
        messages: [
          for (final msg in _state.messages)
            if (msg.id == messageId)
              msg.copyWith(text: updated.reply, editTurn: updated)
            else
              msg,
        ],
      ),
    );
  }

  /// 取走并清空落库错误（一次性提示，避免重建时重复弹 SnackBar）。
  ///
  /// **不通知监听者**：调用点就在监听回调里，再 notify 会重入。
  String? takePersistError() {
    final current = _state.persistError;
    if (current == null) return null;
    _state = _state.copyWith(clearPersistError: true);
    return current;
  }

  Future<void> _persist(ConversationMessage message) async {
    final repository = this.repository;
    if (repository == null) return;
    try {
      await repository.save(message);
    } on Object {
      if (_disposed) return;
      _updateState(_state.copyWith(persistError: '聊天记录保存失败，重启后本次对话可能不完整。'));
    }
  }

  ConversationMessage? _messageById(String id) {
    for (final message in _state.messages) {
      if (message.id == id) return message;
    }
    return null;
  }

  @override
  void dispose() {
    _disposed = true;
    _subscription?.cancel();
    _cancelController?.close();
    super.dispose();
  }
}
