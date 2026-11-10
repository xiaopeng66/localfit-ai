import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:localfit_ai/core/errors/app_failure.dart';
import 'package:localfit_ai/features/ai/domain/ai_connectivity_monitor.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/features/ai_conversation/application/chat_edit_coordinator.dart';
import 'package:localfit_ai/features/ai_conversation/domain/ai_conversation_service.dart';
import 'package:localfit_ai/features/ai_conversation/domain/ai_envelope_compiler.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_image.dart';
import 'package:localfit_ai/features/ai_conversation/domain/conversation_message.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_reply_display.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_context_builder.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_command.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_turn.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_intent.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_number_grounding.dart';
import 'package:localfit_ai/features/nutrition/application/catalog_resolver.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart'
    show formatLocalDate;
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

/// 【docs/66 §3.4】手动生成应用卡片的**单条消息**状态机。
///
/// `attached` 不是枚举值：卡片挂上（`message.isEditProposal`）后按钮消失，
/// 状态条目整体删除。状态是**内存态**，不落库：重启后没有卡的旧消息回到
/// idle，按钮重新出现。
enum CardGenerationPhase { idle, generating, empty, failed }

/// 手动生成的状态快照：[message] 是给人话的说明（空结果原因 / 失败原因）；
/// [retryable] 为 false 时这类失败重试也不会变（原文太长 / 跨天），
/// UI 不显示重试按钮。
@immutable
final class CardGenerationState {
  const CardGenerationState(this.phase, {this.message, this.retryable = true});

  final CardGenerationPhase phase;
  final String? message;
  final bool retryable;
}

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
    this.editDependencyConfirm,
    this.manualCardGeneration = false,
    this.confirmEditDates,
  }) : _clock = clock ?? const SystemAppClock();

  final AiConversationService? _service;

  /// 聊天记录仓储；null = 不落库（重启不留历史）。
  final ConversationMessageRepository? repository;

  /// 通用编辑协调器（docs/23）；null = 纯聊天，编辑卡相关路径全部不激活。
  final ChatEditCoordinator? chatEdit;

  final AppClock _clock;

  /// 断网证据（2026-10-21 裁决 D-2）：只记录「连接失败」，不新增依赖。
  final AiConnectivityMonitor? connectivity;

  /// 需求 6d：应用记餐前发现「缺食材 + 同卡有创建」时问一次。
  ///
  /// 由页面注入（弹层需要 `BuildContext`，控制器不持有 UI）；null = 不串联
  /// （沿用旧行为：记餐行按执行器的失败文案报「找不到食材」）。
  final ChatEditDependencyConfirm? editDependencyConfirm;

  /// 【docs/66】**按需生成应用卡片**（v2 方案）。
  ///
  /// true = 新路径：正常对话（含图片轮）不再强制 JSON、不自动挂卡、不自动
  /// 补信封；用户点内容卡右下角的「生成应用卡片」才走手动编译链路
  /// （[generateEditCard]）。
  ///
  /// false（默认）= 2115 的自动弹卡/补跑行为原样保留——构造参数默认值就是
  /// 回滚开关：路由入口显式传 true，测试与未接线嵌入点行为完全不变。
  final bool manualCardGeneration;

  /// 【docs/66 §6.5】应用前**日期确认**回调：本次要执行的命令里有非今天的
  /// `localDate` 时，由页面弹一次确认（「这张卡记录的是 YYYY-MM-DD…」）。
  /// null = 新模式下非今天日期的写入**默认拒绝**（不静默放行）；旧模式
  /// 回滚维持旧行为（不确认直接执行）。
  final ConfirmEditDates? confirmEditDates;

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

  /// 信封自动催的次数账本（按用户消息 id）。
  ///
  /// 升级梯子（2026-10-27，用户：AI 对话经常不弹应用卡片，要更强制性的保证）：
  /// 每条用户消息最多自动催 2 次——第 1 次用标准提示，第 2 次自动改用
  /// **加强版提示**（引用模型上一条回复原文，原来只有用户手点才用）。
  /// 两次都失败 ⇒ 停止自动催，残留态给「让 AI 给出可应用的修改」手动词条
  /// （用户手点的没有次数上限）。
  final Map<String, int> _envelopeRetryAttempts = {};

  /// 每条用户消息允许的自动催上限。
  static const int _maxEnvelopeAutoRetries = 2;

  /// 用户在修改请求下只拿到纯文本、且自动催过一次的助手消息 id。
  ///
  /// 【2026-10-29（R-7）】残留态的可视入口从「让 AI 给出可应用的修改」词条
  /// 升级为**兜底卡**（`_EnvelopeFallbackCard`：说明 + 「重新生成可应用指令」
  /// + 「知道了」）；本集合语义不变（仍为「该气泡处于残留态」），**内存态**
  /// （不落库）：重启后由 `needsEnvelopeRetry` 的②号来源重算。
  final Set<String> _envelopeRetryOffers = {};

  /// 用户在兜底卡上点过「知道了」的消息 id（同内存态；防重启后②号来源复活）。
  final Set<String> _envelopeRetryDismissed = {};

  /// 自动催信封产生的**中间回复气泡**（只属于本次会话的内存态）。
  ///
  /// 【2026-11-02 用户实机：发一张图后 AI 回复一段，过一会又自动接着回复，
  /// 一直不停】每次自动催都会新增一条助手气泡（2026-10-29 用户要求首轮
  /// 不收回），于是 2 次自动催 = 屏幕上多出 2 段重复的「我准备记…」。
  /// 现在中间的催生气泡**不渲染**：页面通过 [isHiddenRetryBubble] 跳过；
  /// 最终拿到信封（编辑卡）或最后一次失败（残留兜底卡）时才露出。
  final Set<String> _hiddenRetryBubbles = {};

  /// 自动补信封气泡 → 首轮气泡 id。补跑拿到信封后把编辑卡并回首轮，
  /// 补跑气泡删除（用户要求：补信封不要显示出来）。
  final Map<String, String> _retryBubbleOrigin = {};

  /// 这条助手气泡是否是「自动催的中间产物」（页面据此不渲染）。
  bool isHiddenRetryBubble(String messageId) =>
      _hiddenRetryBubbles.contains(messageId);

  /// 把最后一条中间气泡露出来（自动催结束、最终仍失败时调用）。
  void _revealRetryBubble(String messageId) {
    if (!_hiddenRetryBubbles.remove(messageId)) return;
    _retryBubbleOrigin.remove(messageId);
    notifyListeners();
    // 露出来之后它就是最终回复，补一次落库（隐藏期间刻意没写）。
    final message = _messageById(messageId);
    if (message != null) unawaited(_persist(message));
  }

  /// 沿补跑链找到最初那条助手气泡。
  String _retryRoot(String messageId) {
    var current = messageId;
    final seen = <String>{};
    while (_retryBubbleOrigin.containsKey(current) && seen.add(current)) {
      current = _retryBubbleOrigin[current]!;
    }
    return current;
  }

  /// 属于同一首轮气泡的所有隐藏补跑气泡。
  Set<String> _hiddenChainFor(String root) => {
    for (final entry in _retryBubbleOrigin.entries)
      if (entry.value == root) entry.key,
  };

  /// 自动补信封最终仍没拿到信封：删掉补跑气泡，首轮气泡保留并恢复手动词条。
  /// 用户明确要求「补信封不要给我显示出来」，所以这里不露出补跑内容。
  void _discardHiddenRetry(String messageId) {
    final origin = _retryBubbleOrigin.remove(messageId);
    // 同一轮可能有多次自动补跑；最终失败时把整条隐藏链一起删掉。
    final stale = <String>{messageId};
    if (origin != null) {
      for (final entry in _retryBubbleOrigin.entries.toList()) {
        if (entry.value == origin) {
          stale.add(entry.key);
          _retryBubbleOrigin.remove(entry.key);
        }
      }
    }
    _hiddenRetryBubbles.removeAll(stale);
    _envelopeRetryOffers.removeAll(stale);
    if (origin != null) _envelopeRetryOffers.add(origin);
    _updateState(
      _state.copyWith(
        messages: [
          for (final msg in _state.messages)
            if (!stale.contains(msg.id)) msg,
        ],
      ),
    );
    notifyListeners();
  }

  /// 取消后的助手消息 id：用户主动按了「停止」，这一轮不能再被判定为
  /// 「AI 没给出可执行操作」的残留（2026-11-02 用户实机：暂停后反而弹出
  /// 「AI 说改好了，但没有给出可执行的操作」）。
  final Set<String> _cancelledReplies = {};

  /// 这条助手消息是否处在「修改请求却没拿到信封」的残留态（页面据此给手动词条）。
  ///
  /// 两条来源：① 本会话里自动催过仍失败（内存标记）；② **从落库的消息本身
  /// 重算**——「最后一条助手回复是纯文本，而它对应的用户消息是修改请求」。
  /// ② 让这个入口**扛得住重启**（内存标记不落库，但两条消息都在库里），
  /// 且只对**对话末尾**生效：历史消息不给词条（否则翻旧账时到处是按钮）。
  bool needsEnvelopeRetry(String messageId) {
    // 【docs/66】新模式下没有自动补信封机制，这个入口必须恒为 false——
    // 否则会和「生成应用卡片」按钮同时出现两套入口（§9.1 红线 2）。
    if (manualCardGeneration) return false;
    if (_envelopeRetryDismissed.contains(messageId)) return false;
    // 用户按「停止」结束的那一轮不算残留：不是 AI 失败，是用户主动收手。
    if (_cancelledReplies.contains(messageId)) return false;
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
    // ③ 回复在讲「点应用」，但整段对话根本没有编辑卡：模型把不存在的卡
    // 当成事实（2026-11-02 用户实机截图）。重启后也按同一条口径重算。
    if (replyMentionsApplyCard(last.text) && !_hasPendingEditProposal()) {
      return true;
    }
    // ④ 回复在反问「要不要生成/安排」而不是给信封：协议禁止只回提问，
    // 这也是一种「没给出可执行操作」的残留（用户实机：一直重复要不要生成）。
    if (replyAsksToProceed(last.text) && !_hasPendingEditProposal()) {
      return true;
    }
    return looksLikeModificationRequest(messages[userIndex].text);
  }

  /// 用户点兜底卡上的「知道了」：撤掉这条消息的残留标记。
  ///
  /// 【2026-10-29（R-7 兜底卡）】残留态的可视入口从词条升级成卡片后，「忽略」
  /// 需要真的撤卡——只清内存标记；重启后由 `needsEnvelopeRetry` 的②号来源
  /// 重算（那条口径含「最后一条助手回复 + 用户是修改请求」，用户已明确不想要
  /// 卡 ⇒ 这里同时记入已忽略集合，防止重算复活）。
  void dismissEnvelopeRetry(String messageId) {
    if (_disposed) return;
    _envelopeRetryOffers.remove(messageId);
    _envelopeRetryDismissed.add(messageId);
    notifyListeners();
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
    // 正在生成的手动卡片一并取消（§8.1 #30）：完成后不得把已删消息写回。
    cancelAllCardGenerations();
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
    // 纯卡片管理不再交给聊天模型重说一遍。同一目标已有卡/正在编译时
    // 直接复用；业务 wireText 与显示文本不同则不能当作管理指令吞掉。
    if (wire == null || wire.isEmpty || wire == trimmed) {
      final target = _manualCardRequestTarget(trimmed);
      if (target != null) {
        if (target.isEditProposal || _generatingCardIds.contains(target.id)) {
          return Future<void>.value();
        }
        return generateEditCard(target.id);
      }
    }
    return _send(
      kind: ConversationMessageKind.text,
      displayText: trimmed,
      turnText: (wire == null || wire.isEmpty) ? trimmed : wire,
      wireText: (wire == null || wire.isEmpty) ? null : wire,
    );
  }

  /// 只识别没有业务修改内容的完整管理短句；不越过最新消息猜旧目标。
  ConversationMessage? _manualCardRequestTarget(String text) {
    if (!manualCardGeneration ||
        chatEdit == null ||
        _service is! AiEnvelopeCompiler ||
        isReplying ||
        _disposed) {
      return null;
    }
    final request = text.replaceAll(RegExp(r'\s+'), '');
    if (!RegExp(r'^(?:请)?(?:帮我)?生成(?:应用)?卡片[。！!？?]?$').hasMatch(request)) {
      return null;
    }
    if (_state.messages.length < 2) return null;
    final target = _state.messages.last;
    if (target.role != ConversationRole.assistant ||
        target.status != ConversationMessageStatus.sent ||
        target.text.trim().isEmpty) {
      return null;
    }
    return target.isEditProposal ||
            _generatingCardIds.contains(target.id) ||
            canGenerateCard(target.id)
        ? target
        : null;
  }

  /// 发送一条图片消息。
  ///
  /// **图片本体随这条消息真的发出去**（2026-10-16，S1）：请求体按供应商协议
  /// 拼成多模态块（服务层读 [ChatImage.path] 的字节）。模型看不看得懂图由
  /// 供应商自己决定并如实报错——App 既不假装「已看到」，也不再说「没发送」
  /// （那句话正是本轮修掉的缺陷：图其实能发，却被 App 挡在本地）。
  ///
  /// [wireText] 与 `sendMessageWithWire` 同一用途（`RV4-P2-03` / D5）：食堂
  /// 「AI 分析」带图时给模型的正文里要保留 `[canteen-dish:<id>]` 定位引用，
  /// 而用户气泡里只该看到菜名。为 null 时两者相同（既有行为不变）。
  Future<void> sendImageMessage({
    required ChatImage image,
    String? caption,
    String? wireText,
  }) {
    final trimmedCaption = caption?.trim() ?? '';
    final note = '（附了一张图片《${image.fileName}》）';
    final trimmedWire = wireText?.trim() ?? '';
    final turnText = trimmedWire.isNotEmpty
        ? '$note $trimmedWire'
        : (trimmedCaption.isEmpty ? note : '$note $trimmedCaption');
    return _send(
      kind: ConversationMessageKind.image,
      displayText: trimmedCaption,
      turnText: turnText,
      imagePath: image.path,
      // `textForRequest` 读的就是它；note 已拼进 turnText，模型才看得到「附了图」。
      wireText: trimmedWire.isEmpty ? null : turnText,
    );
  }

  /// 【2026-10-31 用户：多张图片点击发送时要一起发送】批量图片消息：
  /// 一次发送把 N 张图各自落成一条用户消息（schema 30 单图/条不变），
  /// **一条 AI 请求**带全部 N 张（每条用户消息各自的多模态块）——
  /// 用户点一次发送，全部图片都出去，而不是「一条一条发」。
  ///
  /// [caption] 只挂在第一条气泡上（用户打的字不重复 N 遍）。
  Future<void> sendImageBatch({
    required List<ChatImage> images,
    String? caption,
  }) async {
    if (images.isEmpty) return;
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
    if (isReplying) return;

    final trimmedCaption = caption?.trim() ?? '';
    final userMessages = <ConversationMessage>[
      for (var i = 0; i < images.length; i++)
        ConversationMessage(
          id: _uuid.v4(),
          role: ConversationRole.user,
          // 文字说明只挂第一条；其余气泡只带图。
          text: i == 0 ? trimmedCaption : '',
          createdAt: _clock.nowUtc().add(Duration(milliseconds: i)),
          status: ConversationMessageStatus.sent,
          kind: ConversationMessageKind.image,
          imagePath: images[i].path,
          wireText: null,
        ),
    ];
    final assistantMessage = ConversationMessage(
      id: _uuid.v4(),
      role: ConversationRole.assistant,
      text: '',
      createdAt: _clock.nowUtc(),
      status: ConversationMessageStatus.sending,
    );

    final history = [
      for (final m in _state.messages)
        if (m.status == ConversationMessageStatus.sent) _forRequest(m),
      for (final m in userMessages) _forRequest(m),
    ];

    _updateState(
      _state.copyWith(
        messages: [..._state.messages, ...userMessages, assistantMessage],
        status: ConversationStatus.sending,
        error: null,
      ),
    );

    final pending = _PendingReply(
      assistantMessage.id,
      userMessageId: userMessages.last.id,
      userText: trimmedCaption,
    );
    _pending = pending;
    for (final message in userMessages) {
      await _persist(message);
      if (_pending != pending) return;
    }
    // docs/66 §5.1：照片轮同样走拆分后的聊天上下文（新模式不强制 JSON）。
    final systemContext = await _chatSystemContext(trimmedCaption);
    if (_pending != pending) return;
    _runRequest(
      service,
      pending: pending,
      history: history,
      systemContext: systemContext,
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
    final systemContext = await _chatSystemContext(userMessage.text);
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
    final systemContext = await _chatSystemContext(messages[userIndex].text);
    if (_pending != null) return; // 快照窗口内来了新请求，让位
    // 失败重跑也要带上用户消息信息：重跑若仍只回散文，升级梯子要能接着评估。
    _runRequest(
      service,
      pending: _PendingReply(
        assistantId,
        userMessageId: messages[userIndex].id,
        userText: messages[userIndex].text,
      ),
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
      // docs/66 §5.9：手动卡的 reply 是**整段原文**——不截断就会把长文带进
      // 后续每轮请求。摘要统一走截断函数（任何新代码不得拿 turn.reply 当
      // 短摘要用）。
      return PendingProposal(
        summary: pendingProposalSummaryOf(turn.reply),
        commands: pending,
      );
    }
    return null;
  }

  /// 普通发送用的系统上下文（docs/66 §5.1）：
  /// * 新模式 → `buildChatContext`（内容纪律 + 能力边界 + 快照，**不含**
  ///   命令协议——聊天上下文与编译上下文分离）；
  /// * 旧模式 → `buildSystemContext`（完整协议 + 快照，2115 行为不变）。
  /// 失败语义：新模式下 `buildChatContext` 始终返回纪律段；旧模式维持
  /// 「整段失败就 null」的原口径。
  Future<String?> _chatSystemContext(String? userMessage) async {
    final coordinator = chatEdit;
    if (coordinator == null) return null;
    if (manualCardGeneration) {
      return coordinator.buildChatContext(
        userMessage: userMessage,
        pendingProposal: _latestPendingProposal(),
      );
    }
    return coordinator.buildSystemContext(
      userMessage: userMessage,
      pendingProposal: _latestPendingProposal(),
    );
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
    // 修改请求/照片记餐：首轮就强制 JSON，不再“先散文、再补信封”。补跑
    // 只作为供应商不支持 response_format 时的兜底；补跑气泡见 _promoteEditTurn
    // 会并回首轮，不再多显示一条。
    //
    // 【docs/66】新模式（manualCardGeneration）下**永不强制 JSON**：正常
    // 对话只说人话；可执行信封由用户点「生成应用卡片」后的手动编译链路出。
    // 这里不改 hasImage / looksLikeModificationRequest 本身——旧路径回滚
    // 时行为逐字节不变。
    final hasImage = history.any(
      (m) =>
          m.role == ConversationRole.user &&
          m.id == pending.userMessageId &&
          m.kind == ConversationMessageKind.image,
    );
    final forceJson =
        !manualCardGeneration &&
        chatEdit != null &&
        (hasImage || looksLikeModificationRequest(pending.userText ?? ''));
    final stream = forceJson && service is JsonForcedConversationService
        ? (service as JsonForcedConversationService).sendMessageForcedJson(
            messages: history,
            onProgress: (chunk) {
              if (_pending?.id != assistantId || _disposed) return;
              pending.buffer.write(chunk);
              _updateAssistantMessage(assistantId, pending.buffer.toString());
            },
            cancelToken: _cancelController?.stream,
            systemContext: systemContext,
          )
        : service.sendMessage(
            messages: history,
            onProgress: (chunk) {
              // 已取消/已收尾的请求不再改列表（取消后到达的分片必须丢弃）。
              if (_pending?.id != assistantId || _disposed) return;
              pending.buffer.write(chunk);
              _updateAssistantMessage(assistantId, pending.buffer.toString());
            },
            cancelToken: _cancelController?.stream,
            systemContext: systemContext,
          );
    _subscription = stream.listen(
      (_) {},
      onDone: () => _completeReply(assistantId),
      // 传**原始错误对象**：翻译成用户话术是控制器的事（`safeFailureText`
      // 只认 AppFailure 的 message；其它一律回落固定文案）——直接
      // `toString()` 会把 `NetworkFailure: …` 这样的类名甩到界面上。
      onError: (Object error) => _completeReply(assistantId, failure: error),
    );
  }

  void _completeReply(String assistantId, {Object? failure}) {
    final pending = _pending;
    if (pending == null || pending.id != assistantId) return;
    _pending = null;
    final text = pending.buffer.toString();
    // 新模式：**永不自动挂卡**。但要做两道防守（docs/66 §5.5）：
    // ① 模型意外回了合法信封 → 只取 turn.reply 作气泡文本（在 finalize /
    //    persist **之前**定稿，否则 DB 里仍是原始 JSON，重启后 repository
    //    会把它解析成编辑卡，用户没点生成却“长出”一张卡）；
    // ② 像信封但解析失败 → 新模式人话文案（不引用已不存在的入口）。
    // 结果记进 [envelopeClean]：非空 = 本轮的最终展示文本（原 JSON 绝不上屏
    // 、绝不落库）。旧路径仍走 `_promoteEditTurn`（合法信封照常升格成卡）。
    String? envelopeClean;
    if (failure == null && manualCardGeneration) {
      final coordinator = chatEdit;
      final turn = coordinator?.decode(text);
      if (turn != null) {
        final replyText = stripInternalRefs(turn.reply).trim();
        envelopeClean = replyText.isEmpty
            ? kMalformedEnvelopeNoticeManualCard
            : replyText;
      } else if (looksLikeEnvelopeText(text)) {
        envelopeClean = kMalformedEnvelopeNoticeManualCard;
      }
    } else if (failure == null) {
      _promoteEditTurn(assistantId, text);
    }
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
    // 新模式的防守清洗结果优先；旧路径维持 `_displayOf`（编辑卡消息取 reply）
    // + `replyTextForDisplay`（半截信封换人话）的既有口径。
    final display = envelopeClean ?? _displayOf(assistantId) ?? text;
    // 2026-10-24 用户：「食堂菜品 AI 分析会转发英文代码片段」「很多次推不了
    // 应用卡片」——模型把信封写坏时原始 JSON 会以纯文本回退上屏；这里在**上屏
    // 前**清洗：半截信封换成人话（并保留手动重来的入口），正常回复剥掉
    // `[canteen-dish:…]` 这类内部引用。
    final shown = display.trim().isEmpty && reason != null ? reason : display;
    _finalizeAssistantMessage(
      assistantId,
      envelopeClean ??
          replyTextForDisplay(shown, manualCardMode: manualCardGeneration),
      error: reason,
    );
    final finalized = _messageById(assistantId);
    // 自动催的中间气泡**不落库**：它只是本轮的临时重跑，若写进历史，重启后
    // 会在对话里重新冒出几段重复回复（2026-11-03 用户实机「一直自动接话」的
    // 另一半根因）。拿到信封时 `_promoteEditTurn` 已先移除隐藏标记，所以
    // 编辑卡照常落库。
    if (finalized != null && !_hiddenRetryBubbles.contains(assistantId)) {
      unawaited(_persist(finalized));
    }
    if (failure != null) {
      // 重跑失败不能悄悄藏起来：让用户看到错误气泡（否则屏幕上毫无反应）。
      _revealRetryBubble(assistantId);
    } else if (_hiddenRetryBubbles.contains(assistantId) &&
        text.trim().isEmpty) {
      // 重跑返回空文本：移除这条空气泡，残留兜底卡由首轮回复重算。
      _updateState(
        _state.copyWith(
          messages: [
            for (final msg in _state.messages)
              if (msg.id != assistantId) msg,
          ],
        ),
      );
      _hiddenRetryBubbles.remove(assistantId);
      _envelopeRetryOffers.remove(assistantId);
      notifyListeners();
    }
    // 2026-10-16（用户：「涉及修改就必须正确识别指令，而不是空回文字」）：
    // 用户这条是修改请求、模型却只回了文字 ⇒ **自动催一次**信封。
    // 【docs/66】新模式下整条自动催链路关闭——补卡由用户点「生成应用卡片」。
    if (failure == null && !manualCardGeneration) {
      unawaited(
        _maybeRetryForEnvelope(assistantId, pending).then((retried) {
          // 自动补跑最终没拿到信封：删掉补跑气泡（用户要求不显示补信封），
          // 首轮保留并恢复手动词条。
          if (!retried && !_disposed) {
            if (_retryBubbleOrigin.containsKey(assistantId)) {
              _discardHiddenRetry(assistantId);
            } else {
              _revealRetryBubble(assistantId);
            }
          }
        }),
      );
    }
  }

  /// 这段对话里有没有**还等着用户点「应用」的编辑卡**。
  ///
  /// 「点应用」这三个字只有在存在待应用卡片时才是正常对话；没有卡片还这么说，
  /// 就是模型把不存在的卡当成事实（见 `replyMentionsApplyCard`）。已应用完的
  /// 卡不算——用户这时同样找不到可点的「应用」。
  bool _hasPendingEditProposal() {
    for (final message in _state.messages) {
      if (message.role == ConversationRole.assistant &&
          message.isEditProposal &&
          (message.editTurn?.hasProposed ?? false)) {
        return true;
      }
    }
    return false;
  }

  /// 修改请求只拿到纯文本时，自动带「必须出信封」提示重跑一次（每轮一次）。
  Future<bool> _maybeRetryForEnvelope(
    String assistantId,
    _PendingReply pending,
  ) async {
    final coordinator = chatEdit;
    if (coordinator == null || _disposed) return false;
    final message = _messageById(assistantId);
    if (message == null || message.isEditProposal) return false; // 已经是信封
    final userText = pending.userText;
    final userId = pending.userMessageId;
    if (userText == null || userId == null) return false;
    final attempts = _envelopeRetryAttempts[userId] ?? 0;
    if (attempts >= _maxEnvelopeAutoRetries) return false;

    // 触发器三把尺：① 用户这句话像修改请求（保守门，宁漏勿误的既有口径）；
    // ② 模型的散文回复**声称已经改了数据**却没带信封（回复侧信号，比用户
    // 措辞更精确——docs/24 记录过的「已加入忌口清单，其实什么都没写」）；
    // ③ 回复在讲「点应用」这件事、而这段对话里**根本没有编辑卡**——模型把
    // 一张不存在的卡当成事实（2026-11-02 用户实机：「AI 说改好了但没有给出
    // 可执行的操作」下方却写着「点应用后才会保存」）。
    final lastReply = _messageById(assistantId)?.text ?? '';
    final claims = replyClaimsChanges(lastReply);
    final looks = looksLikeModificationRequest(userText);
    final phantomCard =
        !_hasPendingEditProposal() && replyMentionsApplyCard(lastReply);
    // ④ 模型在反问「要不要生成/安排」而不是直接给信封（2026-11-02 用户：
    // 「AI 不给我生成应用卡片，而是一直在重复要不要生成的段落」）。协议规则
    // 0/4 明确禁止只回提问；命中它时按失败催一次，别让用户跟模型互相问下去。
    final asksToProceed = replyAsksToProceed(lastReply);
    if (!looks && !claims && !phantomCard && !asksToProceed) return false;

    // 催促次数先记账（残留态在重跑后标到**新气泡**上，见 _rerunForEnvelope）。
    _envelopeRetryAttempts[userId] = attempts + 1;
    // 提示档位：第 1 次催用标准提示（与旧行为逐字节一致）；但**回复侧信号**
    // （模型自己声称已改 / 引用了不存在的卡 / 反问要不要生成）直接跳到加强版。
    final nudge = asksToProceed
        ? chatEditEnvelopeNudgeNoAsking(lastReply)
        : (attempts == 0 && !claims && !phantomCard)
        ? null // null = 用默认标准提示
        : chatEditEnvelopeNudgeQuoting(lastReply);
    final rerunId = await _rerunForEnvelope(
      assistantId,
      overrideNudge: nudge,
      hidden: true,
    );
    if (rerunId == null) return false;
    // 残留态跟着**最新的重跑气泡**走：旧气泡的词条撤下（它已定稿为普通
    // 回复），失败残留标在新气泡上。
    _envelopeRetryOffers
      ..remove(assistantId)
      ..add(rerunId);
    notifyListeners();
    return true;
  }

  /// 带提示**追加**一条新助手气泡重跑（不新增用户消息）。
  ///
  /// 【2026-10-29（用户：生成一段话后又收回重新生成）】旧实现把已渲染的
  /// 首轮回复 `copyWith(text: '')` 清空后复用同一气泡重跑——用户看到的就是
  /// 「内容莫名其妙被收回」。现在**首轮保留**（它是模型的原始回答，用户可以
  /// 读），重跑作为一条**新气泡**流式追加；信封拿到后旧词条撤下，新失败残留
  /// 也标在新气泡上。重跑的历史组装不含首轮散文（与旧行为一致，take 到
  /// 用户消息为止），上下文不因此变长。
  Future<String?> _rerunForEnvelope(
    String assistantId, {
    String? overrideNudge,
    bool hidden = false,
  }) async {
    final service = _service;
    if (service == null || _disposed || isReplying) return null;
    final messages = _state.messages;
    final assistantIndex = messages.indexWhere((m) => m.id == assistantId);
    if (assistantIndex == -1) return null;
    final userIndex = messages.lastIndexWhere(
      (m) => m.role == ConversationRole.user,
      assistantIndex,
    );
    if (userIndex == -1) return null;
    final history = [
      for (final m in messages.take(userIndex + 1))
        if (m.status == ConversationMessageStatus.sent) _forRequest(m),
    ];
    // 重跑同样带上该条用户消息（预检索与新发送同口径）。
    final context = await chatEdit?.buildSystemContext(
      userMessage: messages[userIndex].text,
    );
    if (_disposed || isReplying) return null;
    final rerunMessage = ConversationMessage(
      id: _uuid.v4(),
      role: ConversationRole.assistant,
      text: '',
      createdAt: _clock.nowUtc(),
      status: ConversationMessageStatus.sending,
    );
    _updateState(
      _state.copyWith(
        messages: [...messages, rerunMessage],
        status: ConversationStatus.sending,
        error: null,
      ),
    );
    // 残留态跟着**最新的重跑气泡**走（自动催与手动催共用这一条路径）：
    // 旧气泡的兜底卡撤下（它已定稿为普通回复），失败残留标在新气泡上；
    // 新气泡拿到信封时 `_promoteEditTurn` 会把新 id 一并移除。
    _envelopeRetryOffers
      ..remove(assistantId)
      ..add(rerunMessage.id);
    // 自动催的中间气泡先藏起来：屏幕上只留首轮回复，最终信封/兜底卡出来时
    // 再决定露不露。手动催不藏——那是用户自己点的，要立刻看得到反应。
    if (hidden) {
      _hiddenRetryBubbles.add(rerunMessage.id);
      _retryBubbleOrigin[rerunMessage.id] =
          _retryBubbleOrigin[assistantId] ?? assistantId;
    }
    notifyListeners();
    final pending = _PendingReply(
      rerunMessage.id,
      userMessageId: messages[userIndex].id,
      userText: messages[userIndex].text,
    );
    // 【2026-11-03 根治】有信封编译器就不要再把整段对话（含图片）重发一遍：
    // 改发一次**纯文字、强制 JSON** 的编译请求，输入是用户请求 + 助手刚才
    // 的散文。这样「说人话」与「出 JSON」解耦，JSON 合规由供应商的
    // response_format 保证，而不是靠再写一条提示词。
    final compiler = service is AiEnvelopeCompiler
        ? service as AiEnvelopeCompiler
        : null;
    final replyText = _messageById(assistantId)?.text.trim() ?? '';
    if (compiler != null && replyText.isNotEmpty) {
      _runCompiler(
        compiler,
        pending: pending,
        userText: messages[userIndex].wireText ?? messages[userIndex].text,
        assistantReply: replyText,
        systemContext: context ?? '',
      );
      return rerunMessage.id;
    }
    // 重跑的占位气泡要带上同一条用户消息（升级梯子的第 2 次自动催要在
    // 它失败后还能拿到 userText / userMessageId 再评估一次）。
    _runRequest(
      service,
      pending: pending,
      history: history,
      systemContext: [
        ?context,
        overrideNudge ?? chatEditEnvelopeNudge,
      ].join('\n\n'),
    );
    return rerunMessage.id;
  }

  /// 信封编译请求（纯文字、强制 JSON）。与 [_runRequest] 同一套 pending /
  /// 取消 / 完成语义，只是数据源换成 [AiEnvelopeCompiler]。
  void _runCompiler(
    AiEnvelopeCompiler compiler, {
    required _PendingReply pending,
    required String userText,
    required String assistantReply,
    required String systemContext,
  }) {
    final assistantId = pending.id;
    _pending = pending;
    _cancelController = StreamController<void>();
    _subscription = compiler
        .compileEnvelope(
          userText: userText,
          assistantReply: assistantReply,
          systemContext: systemContext,
          onProgress: (chunk) {
            if (_pending?.id != assistantId || _disposed) return;
            pending.buffer.write(chunk);
            _updateAssistantMessage(assistantId, pending.buffer.toString());
          },
          cancelToken: _cancelController?.stream,
        )
        .listen(
          (_) {},
          onDone: () => _completeReply(assistantId),
          onError: (Object error) =>
              _completeReply(assistantId, failure: error),
        );
  }

  /// 用户手动点「让 AI 给出可应用的修改」：再催一次（不受「每轮一次」限制，
  /// 因为这是用户自己按的）。
  Future<void> requestEnvelope(String messageId) async {
    if (_disposed) return;
    // 点在隐藏补跑气泡上也归到首轮：否则手动重试会从一条用户看不到的
    // 中间回复继续，成功后状态里还可能留下旧补跑气泡。
    final target = _retryRoot(messageId);
    final message = _messageById(target);
    if (message == null || message.role != ConversationRole.assistant) return;
    final hidden = _hiddenChainFor(target)..remove(target);
    _hiddenRetryBubbles.removeAll(hidden);
    _retryBubbleOrigin.removeWhere((key, _) => hidden.contains(key));
    if (hidden.isNotEmpty) {
      _updateState(
        _state.copyWith(
          messages: [
            for (final msg in _state.messages)
              if (!hidden.contains(msg.id)) msg,
          ],
        ),
      );
    }
    await _rerunForEnvelope(
      target,
      overrideNudge: chatEditEnvelopeNudgeQuoting(message.text),
    );
  }

  /// 回复完成时尝试把信封升格成编辑卡（docs/23 §1）：成功则气泡文本换成
  /// reply、挂上 [ChatEditTurn]；失败/纯文本则原样保留。
  void _promoteEditTurn(String assistantId, String rawOutput) {
    final coordinator = chatEdit;
    if (coordinator == null) return;
    // 【2026-11-03 用户：发图后还是不弹应用卡片】视觉模型经常把「看懂了」
    // 与「按协议输出 JSON」分开失败：内容已经是一份完整的记餐提案，却只回
    // 散文（「我准备记为午餐：…400g、…150g，点应用后生效」）。信封解析失败
    // 后再做一次**极保守**的散文抢救（餐次唯一 + 每条都有克数），
    // 救不回来才落到原来的纯文本/兜底卡路径。
    final turn =
        coordinator.decode(rawOutput) ??
        coordinator.decodeProseMealFallback(rawOutput);
    if (turn == null) return;
    // 拿到信封就不再是「残留态」：气泡上的手动词条随之撤下。
    _envelopeRetryOffers.remove(assistantId);
    // 手动催时目标新气泡的前一条助手就是原残留气泡：它的词条也撤下。
    final targetIndex = _state.messages.indexWhere((m) => m.id == assistantId);
    if (targetIndex > 0) {
      for (var i = targetIndex - 1; i >= 0; i--) {
        final msg = _state.messages[i];
        if (msg.role == ConversationRole.assistant) {
          _envelopeRetryOffers.remove(msg.id);
          break;
        }
      }
    }
    _hiddenRetryBubbles.remove(assistantId);
    final originId = _retryBubbleOrigin.remove(assistantId);
    final targetId = originId ?? assistantId;
    final stale = _hiddenChainFor(targetId)
      ..remove(targetId)
      ..add(assistantId);
    _hiddenRetryBubbles.removeAll(stale);
    _retryBubbleOrigin.removeWhere((key, _) => stale.contains(key));
    _updateState(
      _state.copyWith(
        messages: [
          for (final msg in _state.messages)
            if (msg.id == targetId)
              msg.copyWith(
                text: stripInternalRefs(turn.reply),
                kind: ConversationMessageKind.editProposal,
                editTurn: turn,
              )
            else if (!stale.contains(msg.id))
              msg,
        ],
      ),
    );
    // 补跑气泡的内容并回首轮后要把首轮落库；补跑气泡本身不落库。
    if (originId != null) {
      final original = _messageById(originId);
      if (original != null) unawaited(_persist(original));
    }
    // 再审查（2026-10-24 用户：「要有自己的去重和检测遗漏的机制」）。
    // 结果只往上贴警告，**不阻断应用、不改数据**。
    unawaited(_auditProposal(targetId, turn));
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

  /// 同上，但返回消息 id（取消时把该轮的自动催额度记为用尽）。
  String? _lastUserMessageIdBefore(String assistantId) {
    final messages = _state.messages;
    final index = messages.indexWhere((m) => m.id == assistantId);
    final start = index < 0 ? messages.length - 1 : index - 1;
    for (var i = start; i >= 0; i--) {
      final message = messages[i];
      if (message.role == ConversationRole.user) return message.id;
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
    // 取消的是一条**自动催的隐藏气泡**：它本来就不该出现在对话里，直接移除
    // （也不落库），用户看到的仍是首轮回复。
    if (_hiddenRetryBubbles.contains(pending.id)) {
      _retryBubbleOrigin.remove(pending.id);
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
      _markCancelled(pending.id);
      return;
    }
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
      _markCancelled(pending.id);
      return;
    }
    _finalizeAssistantMessage(pending.id, text);
    final finalized = _messageById(pending.id);
    if (finalized != null) await _persist(finalized);
    _markCancelled(pending.id);
  }

  /// 用户按「停止」后的收尾：这一轮不许再自动催、不弹兜底卡、把之前藏着的
  /// 自动催中间气泡一并从消息列表里删掉（用户要的是「停」，不是继续看模型
  /// 自说自话；只清隐藏标记会让半截气泡突然露出来）。
  void _markCancelled(String assistantId) {
    final userId = _lastUserMessageIdBefore(assistantId);
    if (userId != null) {
      _envelopeRetryAttempts[userId] = _maxEnvelopeAutoRetries;
    }
    _envelopeRetryOffers.remove(assistantId);
    _hiddenRetryBubbles.remove(assistantId);
    _cancelledReplies.add(assistantId);
    // 若取消的是隐藏的重跑气泡，它前面那条**首轮回复**才是用户看到的气泡：
    // 一并标记为「用户主动停止」，否则 needsEnvelopeRetry 会把它当残留。
    final messages = _state.messages;
    final index = messages.indexWhere((m) => m.id == assistantId);
    for (var i = index < 0 ? messages.length - 1 : index - 1; i >= 0; i--) {
      final message = messages[i];
      if (message.role == ConversationRole.user) break;
      if (message.role == ConversationRole.assistant &&
          !_hiddenRetryBubbles.contains(message.id)) {
        _cancelledReplies.add(message.id);
        break;
      }
    }
    if (_hiddenRetryBubbles.isNotEmpty) {
      final hidden = Set<String>.of(_hiddenRetryBubbles);
      _hiddenRetryBubbles.clear();
      _updateState(
        _state.copyWith(
          messages: [
            for (final msg in _state.messages)
              if (!hidden.contains(msg.id)) msg,
          ],
        ),
      );
    }
    notifyListeners();
  }

  /// 应用一条编辑卡上的提议（docs/23 §5）：逐条执行、逐条回写结果。
  ///
  /// [rowIndexes] 非空 = 只应用这些行（编辑卡按类分组的「应用本组」）；
  /// null = 全部应用。未选中的行保持 proposed，之后仍可单独应用。
  ///
  /// [confirmDates]（docs/66 §6.5）：本次要执行的命令先经**日期确认
  /// preflight**——选卡重放链路已自行确认过时传 false 复用结论，避免同一
  /// 次重放弹两次。旧模式（manualCardGeneration=false）下 preflight 直接
  /// 放行，行为与改动前一致。
  ///
  /// 守卫：只有「存在 proposed 行且当前不在应用中」的卡才能进；双击/并发
  /// 由 [_applyingEditIds] 挡住——executor 每条都是真写库，重复应用就是
  /// 重复数据。
  Future<void> applyEdits(
    String messageId, {
    Set<int>? rowIndexes,
    bool confirmDates = true,
  }) async {
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

    // 双击守卫必须在**任何 await 之前**立起来：日期确认是真异步，若在确认
    // 之后再上锁，两次并发的 applyEdits 都能穿过守卫、重复执行。
    _applyingEditIds.add(messageId);
    try {
      // 日期确认（docs/66 §6.5）：**先确认、后改状态**。拒绝 / 未接线 /
      // 回调异常时不写库，卡片原样保留（可再忽略）。覆盖整卡与分组。
      if (confirmDates) {
        final commands = [
          for (final row in turn.rows)
            if (row.status == ChatEditRowStatus.proposed &&
                row.command != null &&
                (selected == null || selected.contains(row.index)))
              row.command!,
        ];
        if (!await _confirmDatesFor(commands)) return;
      }

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
      final applied = await coordinator.applyProposed(
        _messageById(messageId)?.editTurn ?? turn,
        onlyIndexes: selected,
        // 需求 6d：确认框由页面画（控制器没有 BuildContext）；未接线时
        // 协调器不会走确认分支，行为与改动前一致。
        confirmDependencies: editDependencyConfirm,
      );
      if (_disposed) return;
      _updateTurn(messageId, applied);
      final finalized = _messageById(messageId);
      if (finalized != null) await _persist(finalized);
    } finally {
      _applyingEditIds.remove(messageId);
    }
  }

  /// 同名双库的候选清单（选择卡数据源）。未接线/非歧义返回 null。
  Future<CatalogCandidates?> resolveCatalogCandidates(String reference) async {
    final coordinator = chatEdit;
    if (coordinator == null || _disposed) return null;
    return coordinator.resolveCatalogCandidates(reference);
  }

  /// 「选择卡」的重放：用户在候选弹层里挑了按食物或按菜品记，把该行
  /// `meal.create` 里所有同名引用改写成带 id 的精确引用，行状态回到
  /// proposed，然后**只重放这一行**。
  ///
  /// 守卫与 [applyEdits] 同源：卡片在应用中时不重入；只接受 failed 行
  /// （失败是终态，改写是用户对那次失败的明确回应）。
  Future<void> retryEditRowWithReference({
    required String messageId,
    required int rowIndex,
    required String originalReference,
    required String newReference,
  }) async {
    final coordinator = chatEdit;
    if (coordinator == null || _disposed) return;
    if (_applyingEditIds.contains(messageId)) return;
    final turn = _messageById(messageId)?.editTurn;
    if (turn == null) return;
    ChatEditTurnItem? target;
    for (final row in turn.rows) {
      if (row.index == rowIndex) target = row;
    }
    final row = target;
    if (row == null) return;
    if (row.status != ChatEditRowStatus.failed) return;
    final command = row.command;
    if (command == null || command.action != 'meal.create') return;
    final items = command.args['items'];
    if (items is! List) return;

    final original = originalReference.trim();
    if (original.isEmpty) return;
    var replaced = 0;
    final rewritten = [
      for (final entry in items)
        if (entry is Map && entry['food'] == original)
          // 保留其它键（grams 等），只把引用替换成带 id 的精确形式。
          {...entry, 'food': newReference}
        else
          entry,
    ];
    for (final entry in items) {
      if (entry is Map && entry['food'] == original) replaced++;
    }
    if (replaced == 0) return;

    final newCommand = ChatEditCommand(
      spec: command.spec,
      args: {...command.args, 'items': rewritten},
    );
    // docs/66 §6.5：选卡重放必须**先对重写后的 candidate command**做日期
    // 确认（引用改写不改日期，但守卫要覆盖整条重放链路）；确认结果在本次
    // 重放内复用（下面的 applyEdits 传 confirmDates: false，不弹第二次）。
    // 拒绝时原失败行与数据均不变。
    if (!await _confirmDatesFor([newCommand])) return;
    final updatedTurn = ChatEditTurn(
      reply: turn.reply,
      rows: [
        for (final row in turn.rows)
          row.index == rowIndex
              ? row.copyWith(
                  command: newCommand,
                  // 引用改写同步进 raw：落库读 raw，只改 command 重启会回退
                  // 到旧引用（docs/66 §5.8 同源问题）。
                  raw: _rewriteRowRawReference(row, original, newReference),
                  status: ChatEditRowStatus.proposed,
                  clearResultMessage: true,
                  clearRepair: true,
                )
              : row,
      ],
      suggestions: turn.suggestions,
    );
    _updateTurn(messageId, updatedTurn);
    final finalized = _messageById(messageId);
    if (finalized != null) await _persist(finalized);
    await applyEdits(messageId, rowIndexes: {rowIndex}, confirmDates: false);
  }

  /// 把行 `raw` 里 `items[].food` 的旧引用改写成新引用（与 command 同步，
  /// docs/66 §5.8）。
  Map<Object?, Object?> _rewriteRowRawReference(
    ChatEditTurnItem row,
    String originalReference,
    String newReference,
  ) {
    final rawArgs = row.raw['args'];
    final items = rawArgs is Map ? rawArgs['items'] : null;
    if (rawArgs is! Map || items is! List) return row.raw;
    final rewrittenItems = [
      for (final entry in items)
        if (entry is Map && entry['food'] == originalReference)
          {...entry, 'food': newReference}
        else
          entry,
    ];
    return {
      ...row.raw,
      'args': {...Map<Object?, Object?>.of(rawArgs), 'items': rewrittenItems},
    };
  }

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
    // docs/66 §6.5：旧卡 suggestion 的执行同样经过统一的日期确认 preflight
    //（拒绝/未接线不写库）；旧模式维持旧行为。
    if (!await _confirmDatesFor([command])) {
      _applyingEditIds.remove(messageId);
      return;
    }
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

  // ── 手动生成应用卡片（docs/66 §5.2–§5.4、§5.10）──────────────────────

  /// 目标回复的字符上限（**控制器只做这一层保守保护**，不自己估字节数；
  /// 请求体 64 KiB 闸门由服务层对最终 UTF-8 JSON body 兜底——见 §5.2）。
  /// 超过 ⇒ 直接 `failed(retryable: false)`，不发编译请求。
  static const int kMaxManualTargetReplyChars = 6000;

  /// 编译上下文的最近对话条数与字节预算（docs/66 §5.2 / §11：最近 6 条，
  /// 单条 ≤600 字、总 ≤3000 字）。
  static const int _maxRecentContextMessages = 6;
  static const int _maxRecentContextCharsPerMessage = 600;
  static const int _maxRecentContextCharsTotal = 3000;

  /// 手动生成状态（内存态，copy-on-write——`ValueNotifier` 靠 `==` 判等，
  /// 原地改 Map 不会通知）。页面只监听它画按钮（`ValueListenableBuilder(
  /// valueListenable: controller.cardGeneration)`），**不走主
  /// `notifyListeners()`**——否则「控制器一响就滚到底」会把正在翻旧消息的
  /// 用户拽走（§6.4）。公开字段：页面跨文件消费，见
  /// `notifier_listeners_gate_test` 的门禁规则。
  final ValueNotifier<Map<String, CardGenerationState>> cardGeneration =
      ValueNotifier(const {});

  // 挂卡成功不再用独立 notifier：页面在主状态变化里对比编辑卡集合的增量
  // （同一条消息挂卡）自行 `Scrollable.ensureVisible`，见 §6.4。

  /// 双击守卫：同一消息同一时刻只允许一个编译请求。
  final Set<String> _generatingCardIds = {};

  /// 每条消息的编译 epoch：取消/重试/dispose 使旧 epoch 失效，迟到的流事件
  /// （onDone/onError）一律丢弃（§5.3 取消语义）。
  final Map<String, int> _cardCompileEpochs = {};
  final Map<String, StreamController<void>> _cardCancelTokens = {};
  final Map<String, StreamSubscription<String>> _cardSubscriptions = {};

  /// 这条消息能不能点「生成应用卡片」——**唯一判据**（页面不自己拼条件）。
  ///
  /// 同时检查：角色、`sent`、非空、非卡片、本地日期 = 今天、前面有用户消息、
  /// `manualCardGeneration`、`chatEdit != null`、服务实现 `AiEnvelopeCompiler`、
  /// 当前未在生成。
  bool canGenerateCard(String messageId) {
    if (!manualCardGeneration) return false;
    if (chatEdit == null) return false;
    if (_service is! AiEnvelopeCompiler) return false;
    if (_generatingCardIds.contains(messageId)) return false;
    final messages = _state.messages;
    final index = messages.indexWhere((m) => m.id == messageId);
    // index <= 0 = 找不到消息 / 前面没有用户消息（开场白不显示按钮）。
    if (index <= 0) return false;
    final message = messages[index];
    if (message.role != ConversationRole.assistant) return false;
    if (message.status != ConversationMessageStatus.sent) return false;
    if (message.text.trim().isEmpty) return false;
    if (message.isEditProposal) return false;
    // 只给**今天**的内容卡入口（§5.10：不能用 UTC 日期，晚上 8 点后会错）。
    if (formatLocalDate(message.createdAt) !=
        formatLocalDate(_clock.nowUtc())) {
      return false;
    }
    return true;
  }

  /// 单条消息的当前生成状态（没有条目 = idle）。
  CardGenerationState cardGenerationOf(String messageId) =>
      cardGeneration.value[messageId] ??
      const CardGenerationState(CardGenerationPhase.idle);

  void _setCardGeneration(String messageId, CardGenerationState state) {
    if (_disposed) return;
    final next = Map<String, CardGenerationState>.of(cardGeneration.value);
    next[messageId] = state;
    cardGeneration.value = next;
  }

  void _clearCardGeneration(String messageId) {
    if (_disposed) return;
    final next = Map<String, CardGenerationState>.of(cardGeneration.value);
    next.remove(messageId);
    cardGeneration.value = next;
  }

  /// 点击「生成应用卡片」：手动编译链路（**不复用 `_runCompiler`**——那会
  /// 写 `_pending`、逐片改写目标消息原文，且生成中发新消息会覆盖 `_pending`）。
  Future<void> generateEditCard(String messageId) async {
    if (_disposed) return;
    final coordinator = chatEdit;
    final service = _service;
    // `AiEnvelopeCompiler` 不是 `AiConversationService` 的子类型（服务实现
    // 两个接口），is 之后仍要显式 cast。
    AiEnvelopeCompiler? compiler;
    if (service is AiEnvelopeCompiler) {
      compiler = service as AiEnvelopeCompiler;
    }
    if (coordinator == null || compiler == null) return;
    if (_generatingCardIds.contains(messageId)) return;
    final messages = _state.messages;
    final index = messages.indexWhere((m) => m.id == messageId);
    final message = index == -1 ? null : messages[index];
    if (message == null) return;
    // §5.10：页面可见性可能跨零点滞后——入口必须重新校验日期，不合法时
    // 如实写 `failed`，不能静默无反应。
    final targetLocalDate = formatLocalDate(message.createdAt);
    final today = formatLocalDate(_clock.nowUtc());
    if (targetLocalDate != today) {
      _setCardGeneration(
        messageId,
        const CardGenerationState(
          CardGenerationPhase.failed,
          message: '已跨天，请重新发起。',
          retryable: false,
        ),
      );
      return;
    }
    if (!canGenerateCard(messageId)) return;
    // 目标回复超预算：直接失败（retryable: false），不发编译请求。
    if (message.text.length > kMaxManualTargetReplyChars) {
      _setCardGeneration(
        messageId,
        const CardGenerationState(
          CardGenerationPhase.failed,
          message: '这条回复太长，无法生成卡片，请精简后重试。',
          retryable: false,
        ),
      );
      return;
    }

    final userText = _lastUserTextBefore(messageId) ?? '';
    _generatingCardIds.add(messageId);
    final epoch = (_cardCompileEpochs[messageId] ?? 0) + 1;
    _cardCompileEpochs[messageId] = epoch;
    _setCardGeneration(
      messageId,
      const CardGenerationState(CardGenerationPhase.generating),
    );

    // 编译请求在**点击时现场构建** editContext（完整协议变体 + 当前快照），
    // 不用发送时的旧快照；foodQuery = 用户请求 + 目标回复（截断）——只喂
    // 食物库预览，菜品推荐门控与记忆检索仍按真实用户请求（§5.2）。
    final editContext = await coordinator.buildEditContext(
      userMessage: userText,
      foodQuery: _foodQueryFor(userText, message.text),
      // 「上一张还没应用的卡」以结构化段注入（不是塞进对话文本）：
      // 用户可能正对着那张卡说「刚才那份改成 100g」，编译器需要看见它。
      pendingProposal: _latestPendingProposal(),
    );
    // 快照窗口内被取消 / 重试 / 清空历史 ⇒ 让位。
    if (_disposed || _cardCompileEpochs[messageId] != epoch) {
      _releaseManualCompile(messageId);
      return;
    }
    if (_messageById(messageId) == null) {
      _releaseManualCompile(messageId);
      return;
    }

    final cancelToken = StreamController<void>();
    _cardCancelTokens[messageId] = cancelToken;
    final buffer = StringBuffer();
    late final StreamSubscription<String> subscription;
    subscription = compiler
        .compileEnvelope(
          userText: userText,
          assistantReply: message.text,
          conversationContext: _recentConversationFor(index),
          targetLocalDate: targetLocalDate,
          systemContext: editContext,
          onProgress: buffer.write,
          cancelToken: cancelToken.stream,
        )
        .listen(
          (_) {},
          onDone: () => unawaited(
            _completeManualCompile(
              messageId,
              epoch: epoch,
              targetLocalDate: targetLocalDate,
              buffer: buffer,
            ),
          ),
          onError: (Object error) =>
              _failManualCompile(messageId, epoch, failure: error),
        );
    _cardSubscriptions[messageId] = subscription;
  }

  /// 「foodQuery」= 用户请求 + 目标回复（截断到 800 字，防长文把请求撑爆；
  /// 目标回复的超长保护另有字符上限）。只用于食物库预览检索。
  String _foodQueryFor(String userText, String reply) {
    final clippedReply = reply.length > 800 ? reply.substring(0, 800) : reply;
    return '$userText\n$clippedReply';
  }

  /// 目标消息**之前**的最近对话（§5.2）：只取 `status == sent` 的消息；图片
  /// 消息用「[图片]」占位（不重发图片字节）；不把目标回复本身放进去；
  /// 最多 6 条、单条 ≤600 字、总 ≤3000 字——超长先裁更早的（不静默截断
  /// 目标回复，它由调用方单独守护）。
  String _recentConversationFor(int targetIndex) {
    final items = <String>[];
    var total = 0;
    for (
      var i = targetIndex - 1;
      i >= 0 && items.length < _maxRecentContextMessages;
      i--
    ) {
      final message = _state.messages[i];
      if (message.status != ConversationMessageStatus.sent) continue;
      // 【2026-11-07 防重复计入·结构化分离】编辑卡**一律不进最近对话**：
      // 卡的 reply 就是「米饭 150g、鸡胸肉 150g」，喂给编译器等于把内容
      // 当成新素材——已应用的会被重复生成（饮水/体重没有全天去重，会真记
      // 两条），待应用的则与快照里的「尚未应用的提议」段重复。
      //
      // 「今天已经记了什么」只由**数据快照**这一个权威来源提供；「上一张
      // 待应用卡」改由 `pendingProposal` 结构化段注入（生成卡片时传）。
      // 这样编译器不再需要从自由文本里重建已经发生过的事实。
      if (message.isEditProposal) continue;
      var text = message.textForRequest.trim();
      if (message.kind == ConversationMessageKind.image) {
        text = text.isEmpty ? '[图片]' : '[图片] $text';
      }
      if (text.isEmpty) continue;
      if (text.length > _maxRecentContextCharsPerMessage) {
        text = text.substring(0, _maxRecentContextCharsPerMessage);
      }
      if (total + text.length > _maxRecentContextCharsTotal) break;
      total += text.length;
      items.add('${message.role == ConversationRole.user ? '用户' : '助手'}：$text');
    }
    // 从旧到新拼接（上文顺序）。
    return items.reversed.join('\n');
  }

  /// 编译流结束（成功路径）。先校验 epoch 与「消息仍在列表」，晚到的
  /// onDone 一律丢弃；然后按 decoder → suggestions 丢弃 → 空结果 → 数字
  /// 接地 → 日期钉死 → 跨日检查 → 挂卡 → 落库 → 审查的顺序收尾。
  Future<void> _completeManualCompile(
    String messageId, {
    required int epoch,
    required String targetLocalDate,
    required StringBuffer buffer,
  }) async {
    if (_disposed) return;
    if (_cardCompileEpochs[messageId] != epoch) return; // 取消/重试后迟到
    final coordinator = chatEdit;
    if (coordinator == null) return;
    if (_messageById(messageId) == null) {
      _releaseManualCompile(messageId);
      return;
    }

    void fail(String text, {bool retryable = true}) {
      _finishManualCompile(
        messageId,
        CardGenerationState(
          CardGenerationPhase.failed,
          message: text,
          retryable: retryable,
        ),
      );
    }

    if (_cardCompileEpochs[messageId] != epoch) return; // 订阅窗口内被取消
    final decoded = coordinator.decode(buffer.toString());
    if (decoded == null) {
      fail('生成失败，请重试。');
      return;
    }
    // 卡片与接地报错都要说人话：把 `[food:id]` 解析成食物名（只读查询）。
    // 未接线/解析失败时原样返回，不挡卡。
    final turn = await coordinator.annotateItemLabels(decoded);
    if (_disposed || _cardCompileEpochs[messageId] != epoch) return;
    // 手动结果**丢弃 suggestions**（§5.2.1）：args 完整的建议是可直接执行
    // 的命令，chip 只显示 label，用户看不到参数——不能再引入无预览写库。
    // rows 为空 + 有 suggestions ⇒ 同样按 empty 处理。
    if (turn.rows.isEmpty) {
      final reason = replyTextForDisplay(turn.reply).trim();
      // 空结果原因要一眼读完：编译 prompt 已要求一句话，这里再兜底截到
      // 120 字（2026-11-07 真机：200 字的大段灰字读不下去）。
      final clipped = reason.length > 120 ? reason.substring(0, 120) : reason;
      _finishManualCompile(
        messageId,
        CardGenerationState(
          CardGenerationPhase.empty,
          message: clipped.isEmpty ? '这条回复没有可应用的操作' : clipped,
        ),
      );
      return;
    }
    // 数字接地闸门（§5.2.1 P0）：任一数值缺依据 ⇒ 整张卡拒绝。
    final groundingProblem = validateManualCardGrounding(
      turn,
      userText: _lastUserTextBefore(messageId) ?? '',
      assistantReply: _messageById(messageId)?.text ?? '',
    );
    if (groundingProblem != null) {
      // 用**具体**原因（哪个食物、哪个数值），不用笼统的「有数值没法核对」
      // ——用户 2026-11-07 两次反馈「我看不懂你要表达什么」。
      final detail = groundingProblem.replaceAll(RegExp(r'\s+'), ' ').trim();
      _finishManualCompile(
        messageId,
        CardGenerationState(
          CardGenerationPhase.empty,
          message: detail.length > 140
              ? '${detail.substring(0, 140)}…'
              : '$detail（回复里没写这个数，点重试让 AI 说清）',
        ),
      );
      return;
    }
    // 日期钉死（§4.3 #7）：缺省 localDate 的日期型命令用目标消息本地日期
    // 补上，**同时改 row.raw**（落库编码读的是 raw）；显式给了别的日期保留
    // （应用前由日期确认守卫）。steps 目标保持全局语义。
    final pinned = _pinRowDates(
      _deduplicateManualCompileRows(turn),
      targetLocalDate,
    );
    // 重复可见化（2026-11-07 下一版）：对照「今天已有」给每行挂一句提示
    // （只提示、不阻断；探针未接线/失败时原样返回）。
    final annotated = await coordinator.annotateDuplicates(pinned);
    // 【2026-11-09 审查修复】探针要查库（几毫秒到几十毫秒），用户完全可能
    // 在这个窗口点「取消」或重试。`onDone` 那次 epoch 校验发生在 await
    // **之前**，回来必须再核一遍——否则迟到的结果会把卡挂上，违反 §5.3。
    if (_disposed || _cardCompileEpochs[messageId] != epoch) return;
    // 跨零点：编译完成时目标日期已不是今天 ⇒ 不挂卡（§5.10）。
    if (targetLocalDate != formatLocalDate(_clock.nowUtc())) {
      fail('跨天了，请重新发起。', retryable: false);
      return;
    }
    // 挂到**同一条消息**：不新增气泡、原文不变、reply 用原文（§4.3 不变式）。
    final message = _messageById(messageId);
    if (message == null) {
      _releaseManualCompile(messageId);
      return;
    }
    final attached = ChatEditTurn(
      reply: message.text,
      rows: annotated.rows,
      suggestions: const [],
      warnings: annotated.warnings,
    );
    _updateState(
      _state.copyWith(
        messages: [
          for (final msg in _state.messages)
            if (msg.id == messageId)
              msg.copyWith(
                // 文本保持原文；只把形态换成编辑卡。
                kind: ConversationMessageKind.editProposal,
                editTurn: attached,
              )
            else
              msg,
        ],
      ),
    );
    _releaseManualCompile(messageId);
    _clearCardGeneration(messageId);
    final finalized = _messageById(messageId);
    if (finalized != null) await _persist(finalized);
    // 审查失败静默（旁注语义）。页面对主状态变化做编辑卡集合增量对比后
    // 自行 ensureVisible（§6.4）。
    unawaited(_auditProposal(messageId, attached));
  }

  /// 编译流失败：failed + 人话；不挂卡；原文不变（§5.4）。
  void _failManualCompile(
    String messageId,
    int epoch, {
    required Object failure,
  }) {
    if (_disposed) return;
    if (_cardCompileEpochs[messageId] != epoch) return; // 取消后迟到
    // **先让 epoch 失效**：真实 SSE 流在 addError 之后还会补一个 done 事件，
    // 若那时取消订阅尚未生效，迟到的 onDone 会进 `_completeManualCompile`
    // 并把失败覆盖成挂卡（缓冲区里可能已经攒了半个合法信封）。取消订阅是
    // 主防线，这里再上一道锁。
    _cardCompileEpochs[messageId] = epoch + 1;
    _finishManualCompile(
      messageId,
      CardGenerationState(
        CardGenerationPhase.failed,
        message: safeFailureText(failure, fallback: '生成失败，请重试。'),
      ),
    );
  }

  /// 收尾为终态（failed / empty）：释放编译资源、终态写进状态条目。
  void _finishManualCompile(String messageId, CardGenerationState state) {
    _releaseManualCompile(messageId);
    _setCardGeneration(messageId, state);
  }

  /// 释放该消息的编译资源（订阅 / 取消令牌 / 双击守卫）。**不**发取消事件
  /// （那只在 [cancelCardGeneration] 里做），也不改状态条目。
  void _releaseManualCompile(String messageId) {
    final subscription = _cardSubscriptions.remove(messageId);
    final token = _cardCancelTokens.remove(messageId);
    token?.close();
    unawaited(subscription?.cancel());
    _generatingCardIds.remove(messageId);
  }

  /// 用户点「取消」（§5.3 取消语义，顺序是钉死的）：
  /// **先使 epoch 失效**，再向 token 发取消事件、取消订阅、关闭 token，
  /// 最后显式回 `idle`。迟到的流事件因 epoch 失效不会挂卡或写库。
  void cancelCardGeneration(String messageId) {
    if (!_generatingCardIds.contains(messageId)) return;
    _cardCompileEpochs[messageId] = (_cardCompileEpochs[messageId] ?? 0) + 1;
    final token = _cardCancelTokens.remove(messageId);
    final subscription = _cardSubscriptions.remove(messageId);
    token?.add(null);
    unawaited(subscription?.cancel());
    token?.close();
    _generatingCardIds.remove(messageId);
    _setCardGeneration(
      messageId,
      const CardGenerationState(CardGenerationPhase.idle),
    );
  }

  /// 只压缩新手动编译结果中的相同命令。历史 parser 不去重，避免已有
  /// outcomes 与 edits 下标错位；新结果连续编号后再挂卡、落库。
  ChatEditTurn _deduplicateManualCompileRows(ChatEditTurn turn) {
    final rows = <ChatEditTurnItem>[];
    for (final row in turn.rows) {
      final command = row.command;
      if (command != null &&
          rows.any((accepted) {
            final previous = accepted.command;
            return previous != null &&
                previous.action == command.action &&
                _sameCompileValue(previous.args, command.args);
          })) {
        continue;
      }
      rows.add(row.copyWith(index: rows.length));
    }
    return ChatEditTurn(
      reply: turn.reply,
      rows: rows,
      suggestions: turn.suggestions,
      warnings: turn.warnings,
    );
  }

  /// Map 键顺序无关；List 顺序和所有参数值均参与比较。
  bool _sameCompileValue(Object? left, Object? right) {
    if (left is Map && right is Map) {
      return left.length == right.length &&
          left.keys.every(
            (key) =>
                right.containsKey(key) &&
                _sameCompileValue(left[key], right[key]),
          );
    }
    if (left is List && right is List) {
      if (left.length != right.length) return false;
      for (var i = 0; i < left.length; i++) {
        if (!_sameCompileValue(left[i], right[i])) return false;
      }
      return true;
    }
    return left == right;
  }

  /// 把缺省日期的日期型命令钉到 [targetLocalDate]（§4.3 #7 / §5.10）。
  ///
  /// * `weight.log` / `water.add` / `meal.create` / `session.start`：args 没有
  ///   `localDate` 就补上，并**同步改 row.raw**（落库编码读 raw）。
  /// * `targets.update`：只在水目标（`waterMl` 非空）时钉；`steps` 全局语义。
  /// * 模型显式给了日期 ⇒ 保留（应用前的日期确认守卫负责核对）。
  ChatEditTurn _pinRowDates(ChatEditTurn turn, String targetLocalDate) {
    return ChatEditTurn(
      reply: turn.reply,
      warnings: turn.warnings,
      suggestions: const [],
      rows: [for (final row in turn.rows) _pinRowDate(row, targetLocalDate)],
    );
  }

  ChatEditTurnItem _pinRowDate(ChatEditTurnItem row, String targetLocalDate) {
    final command = row.command;
    if (command == null) return row;
    if (command.spec.specOf('localDate') == null) return row;
    if (command.action == 'targets.update' && command.args['waterMl'] == null) {
      return row; // steps 目标保持全局语义
    }
    if (command.args.containsKey('localDate')) return row; // 显式日期保留
    final newArgs = {...command.args, 'localDate': targetLocalDate};
    final rawArgs = row.raw['args'];
    final newRaw = <Object?, Object?>{
      ...row.raw,
      'args': <Object?, Object?>{
        ...(rawArgs is Map ? Map<Object?, Object?>.of(rawArgs) : const {}),
        'localDate': targetLocalDate,
      },
    };
    return row.copyWith(
      command: ChatEditCommand(spec: command.spec, args: newArgs),
      raw: newRaw,
    );
  }

  /// 收集一组命令里**非今天**的显式 `localDate`（日期确认守卫用）。
  Set<String> _nonTodayDatesOf(Iterable<ChatEditCommand?> commands) {
    final today = formatLocalDate(_clock.nowUtc());
    final dates = <String>{};
    for (final command in commands) {
      if (command == null) continue;
      final date = command.args['localDate'];
      if (date is String && date.isNotEmpty && date != today) dates.add(date);
    }
    return dates;
  }

  /// 【docs/66 §6.5】应用前**日期确认**（统一 preflight）：本次实际要执行的
  /// 命令里有非今天 `localDate` 时，先经页面回调确认。
  ///
  /// * 旧模式（`manualCardGeneration=false`）维持旧行为：不确认直接执行；
  /// * 新模式：全部是今天（或无日期参数）⇒ 直接放行；有非今天日期 ⇒ 调
  ///   [confirmEditDates]；**回调缺失 / 返回 false / 抛异常都拒绝**（不写库）。
  Future<bool> _confirmDatesFor(List<ChatEditCommand> commands) async {
    if (!manualCardGeneration) return true;
    final dates = _nonTodayDatesOf(commands);
    if (dates.isEmpty) return true;
    final callback = confirmEditDates;
    if (callback == null) return false;
    try {
      return await callback(dates);
    } on Object {
      return false;
    }
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

  /// 取消全部进行中的手动编译（清空历史 / dispose 用）：逐条走
  /// [cancelCardGeneration] 的钉死顺序，epoch 失效后迟到的流事件不再写库。
  void cancelAllCardGenerations() {
    for (final messageId in List<String>.of(_generatingCardIds)) {
      cancelCardGeneration(messageId);
    }
    cardGeneration.value = const {};
  }

  @override
  void dispose() {
    _disposed = true;
    _subscription?.cancel();
    _cancelController?.close();
    // 手动编译资源：先使全部 epoch 失效（dispose 后迟到事件必须被丢弃），
    // 再取消订阅、关闭取消令牌，最后释放 notifier。
    for (final messageId in _cardCompileEpochs.keys) {
      _cardCompileEpochs[messageId] = (_cardCompileEpochs[messageId] ?? 0) + 1;
    }
    for (final subscription in _cardSubscriptions.values) {
      unawaited(subscription.cancel());
    }
    _cardSubscriptions.clear();
    for (final token in _cardCancelTokens.values) {
      token.close();
    }
    _cardCancelTokens.clear();
    _generatingCardIds.clear();
    cardGeneration.dispose();
    super.dispose();
  }
}
