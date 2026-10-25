import 'dart:convert';

import 'package:localfit_ai/features/ai/data/ai_json_object_salvage.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_command.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_proposal_audit.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_registry.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_repair.dart';

/// 编辑卡上单条命令的状态（docs/23 §5）。
enum ChatEditRowStatus { proposed, applying, applied, failed, dismissed }

/// 信封里一条编辑的解析结果：要么是已校验的命令，要么带解码失败原因。
///
/// **单条失败不连坐**（docs/23 §1）：模型一次提议里坏一条，其余照常成卡。
final class ChatEditTurnItem {
  const ChatEditTurnItem({
    required this.index,
    required this.raw,
    this.command,
    this.decodeError,
    this.status = ChatEditRowStatus.proposed,
    this.resultMessage,
    this.repair,
  });

  /// 在信封 `edits` 数组里的下标（结果回写与重启恢复都按它对位）。
  final int index;

  /// 模型原始的 `{"action":…,"args":…}`（落库回环用）。
  final Map<Object?, Object?> raw;

  final ChatEditCommand? command;
  final String? decodeError;
  final ChatEditRowStatus status;

  /// 应用结果或解码失败的人话说明；proposed/applying 时为 null。
  final String? resultMessage;

  /// 失败后的可点修复动作（见 [ChatEditRepair]）；没有就为 null。
  final ChatEditRepair? repair;

  ChatEditTurnItem copyWith({
    ChatEditRowStatus? status,
    String? resultMessage,
    ChatEditRepair? repair,
  }) {
    return ChatEditTurnItem(
      index: index,
      raw: raw,
      command: command,
      decodeError: decodeError,
      status: status ?? this.status,
      resultMessage: resultMessage ?? this.resultMessage,
      repair: repair ?? this.repair,
    );
  }
}

/// 一条「推荐按钮」（2026-10-16 用户：对话里遇到问题要推荐回答并弹出可点
/// 选按钮）：`label` 是按钮文案，`command` 是**已按注册表校验归一化**的命令
/// ——点按钮 = 应用这条命令，与编辑卡走同一个执行器、同一道确认语义之外的
/// 主动点击语义（用户点按钮本身就是确认）。
///
/// [status]/[resultMessage]：点过之后就地回写结果，让用户看到到底成没成。
/// 状态枚举复用 [ChatEditRowStatus]（同一套「待应用/应用中/已应用/失败」
/// 口径，不另造一套平行状态）。
final class ChatEditSuggestion {
  const ChatEditSuggestion({
    required this.label,
    required this.command,
    this.action,
    this.rawArgs = const {},
    this.needsMoreInfo = false,
    this.status = ChatEditRowStatus.proposed,
    this.resultMessage,
  });

  final String label;

  /// 可执行的命令；**null = 参数还不全**（`needsMoreInfo == true`）。
  ///
  /// 2026-10-24（`ai-live` 实测）：模型在「信息不全」时会给
  /// `{"action":"meal.delete","args":{}}` 这种**意图正确、目标待补**的建议。
  /// 旧实现把这类建议**静默丢弃** ⇒ `suggestions` 变空 ⇒ 整段信封被判无效
  /// ⇒ 用户看到的是「说了要改、卡片不弹」。现在保留成可点按钮（点了按既有
  /// 流程补问），不再连坐整段回复。
  final ChatEditCommand? command;

  /// 原始 action（`command == null` 时仍有值，供 UI/落库使用）。
  final String? action;

  /// 模型的原始 args（不一定通过校验；`needsMoreInfo` 时保留以便补问）。
  final Map<Object?, Object?> rawArgs;

  /// true = 该建议缺必填参数，点了需要先补齐（UI 据此说明「还差信息」）。
  final bool needsMoreInfo;

  final ChatEditRowStatus status;
  final String? resultMessage;

  /// 可用的 action 名（`command` 优先，其次保留的原始 action）。
  String? get effectiveAction => command?.action ?? action;

  ChatEditSuggestion copyWith({
    ChatEditRowStatus? status,
    String? resultMessage,
  }) {
    return ChatEditSuggestion(
      label: label,
      command: command,
      action: action,
      rawArgs: rawArgs,
      needsMoreInfo: needsMoreInfo,
      status: status ?? this.status,
      resultMessage: resultMessage ?? this.resultMessage,
    );
  }
}

/// 一次助手回复里的编辑提议整体（reply 文本 + 逐条行 + 推荐按钮）。
final class ChatEditTurn {
  const ChatEditTurn({
    required this.reply,
    required this.rows,
    this.suggestions = const [],
    this.warnings = const [],
  });

  final String reply;
  final List<ChatEditTurnItem> rows;

  /// 模型给的「下一步能做」按钮（0–3 条）。可以只有按钮、没有 edits。
  final List<ChatEditSuggestion> suggestions;

  /// **提案审查**发现的问题（2026-10-24：餐次不符 / 重复食物 / 疑似遗漏）。
  ///
  /// 只用于**上屏提示**（用户点「应用」前看见），不参与执行、不阻断应用、
  /// **不进 wire、不落库**——它是 App 对模型提议的旁注，不是提议本身的一部分。
  /// 空列表 = 审查通过（绝大多数情况）。
  final List<ChatEditAuditWarning> warnings;

  /// 带上审查结果（返回新实例，原实例不变）。
  ChatEditTurn withWarnings(List<ChatEditAuditWarning> value) => ChatEditTurn(
    reply: reply,
    rows: rows,
    suggestions: suggestions,
    warnings: value,
  );

  bool get hasProposed =>
      rows.any((row) => row.status == ChatEditRowStatus.proposed);

  bool get isApplying =>
      rows.any((row) => row.status == ChatEditRowStatus.applying);

  bool get hasSuggested => suggestions.any(
    (suggestion) => suggestion.status == ChatEditRowStatus.proposed,
  );
}

/// 解析模型输出为编辑提议；**不是合法信封就返回 null**（调用方按纯文本渲染）。
///
/// 合法 = JSON 对象 + `reply` 是字符串 + `edits` 是可解析列表 + 条数不超限，
/// 且 **`edits` 与 `suggestions` 不能同时为空**（至少要有点东西可做，否则
/// 就是空气泡）。`suggestions` 缺省 = 无按钮（旧信封行为不变）。
/// 坏 JSON、缺键、超条数都当纯文本——宁可当闲聊，也不产生半可信的卡。
ChatEditTurn? parseChatEditTurn(
  String rawOutput,
  ChatEditCommandRegistry registry,
) {
  final trimmed = rawOutput.trim();
  // 第一路径：整段就是一个信封（协议要求的那种，逐字节不变）。
  final strict = _parseEnvelopeText(trimmed, registry);
  if (strict != null) return strict;
  // 第二路径（2026-10-16 补）：**抢救**。真实模型（供应商 ai.furry.vg /
  // `deepseek-ai/deepseek-v4.1-flash`）最常见的违规是「先用中文说一句，再贴
  // JSON」，而信封本身完全合法——协议里已经写了「整段只放这一个 JSON 对象」，
  // 实测仍然会犯（控制矩阵 ⑩⑭⑮ 三条都栽在这里）。原先只有「催一次重跑」的
  // 事后补救，本模型实测并不稳定。所以这里在整段解析失败后，再从文本里找
  // **恰好一个**能解析成合法信封的 JSON 对象：找不到、或有两个都能解析
  // （有歧义）都仍然返回 null —— 宁可当闲聊，也不替用户猜。
  return _salvageEnvelope(trimmed, registry);
}

/// 把「一段文本（期望整段就是一个 JSON 对象）」解析成信封；不满足即 null。
ChatEditTurn? _parseEnvelopeText(
  String text,
  ChatEditCommandRegistry registry,
) {
  final trimmed = text.trim();
  if (!trimmed.startsWith('{') || !trimmed.endsWith('}')) return null;
  final Object? decoded;
  try {
    decoded = jsonDecode(trimmed);
  } on FormatException {
    return null;
  }
  if (decoded is! Map) return null;
  final reply = decoded['reply'];
  if (reply is! String) return null;
  // `edits` **可选**：`ai-live` 实测（2026-10-24，M27）模型会给出
  // `{"reply":"…","suggestions":[…]}` —— 只给按钮、不带 edits。旧实现
  // `if (edits is! List) return null` 要求它必须存在 ⇒ 整段判纯文本 ⇒
  // 卡片不弹。`edits: null` 同理（模型常显式写 null）。
  // 但要防「两者都没有」的空气泡：由下面的 `edits.isEmpty && suggestions.isEmpty`
  // 兜住（那才是真的没内容）。
  final rawEdits = decoded['edits'];
  if (rawEdits != null && rawEdits is! List) return null;
  final edits = rawEdits == null ? const <Object?>[] : rawEdits as List;
  if (edits.length > ChatEditCommandRegistry.maxEditsPerReply) return null;

  final rawSuggestions = decoded['suggestions'];
  final suggestions = _parseSuggestions(rawSuggestions, registry);
  // 【空 edits / 空 suggestions 的判据（2026-10-24 用户：不要模棱两可的答案）】
  //
  // 规则 0 要求「动作执行不了也要给信封，但**不许偷换成别的命令**」——
  // 模型因此会回 `{"reply":"今天没有午餐可删。","edits":[]}`（两样都空）。
  // 这是**正确的空信封**：卡片要弹出来，让用户看见「我查过、确实没有」。
  // 旧实现一律返回 null ⇒ 卡片不弹 ⇒ 用户以为没反应。
  //
  // 唯一该拒的是**空气泡**：连 reply 都是空白（没有话可说、也没有动作）。
  if (edits.isEmpty && suggestions.isEmpty && reply.trim().isEmpty) {
    return null;
  }

  final rows = <ChatEditTurnItem>[];
  for (var index = 0; index < edits.length; index++) {
    rows.add(_parseRow(index, edits[index], registry, decoded['outcomes']));
  }
  return ChatEditTurn(reply: reply, rows: rows, suggestions: suggestions);
}

/// 从整段文本里找出**恰好一个**能解析成合法信封的 JSON 对象。
///
/// 扫描规则：只看**顶层**的花括号对（嵌套的花括号属于外层对象本身），
/// 并且跳过 JSON 字符串内部的花括号（含转义）——否则 `reply` 里写个「{」
/// 就会把配对算歪。能解析的对象多于一个 ⇒ 有歧义，返回 null。
ChatEditTurn? _salvageEnvelope(String text, ChatEditCommandRegistry registry) {
  // 扫描与配对在共享件里（`ai_json_object_salvage.dart`）：计划、识餐两条
  // 出口用的是同一套「抠出恰好一个 JSON 对象」的口径，三处不许各写一份。
  final candidate = salvageSingleJsonObject(text);
  if (candidate == null) return null;
  return _parseEnvelopeText(candidate, registry);
}

/// 解析 `suggestions`（可选通道）。**坏建议只丢自己**：未知 action、空
/// label、参数不合法都不上屏——它们是按钮，给不出可执行命令就不该出现；
/// 但绝不因此把整段回复降级（与「单条 edit 失败不连坐」同一口径）。
/// 上限 [ChatEditCommandRegistry.maxSuggestionsPerReply] 条，多出的丢弃。
List<ChatEditSuggestion> _parseSuggestions(
  Object? raw,
  ChatEditCommandRegistry registry,
) {
  if (raw is! List) return const [];
  final out = <ChatEditSuggestion>[];
  for (final entry in raw) {
    if (out.length >= ChatEditCommandRegistry.maxSuggestionsPerReply) break;
    if (entry is! Map) continue;
    final label = entry['label'];
    if (label is! String || label.trim().isEmpty || label.trim().length > 40) {
      continue;
    }
    final action = entry['action'];
    if (action is! String) continue;
    final spec = registry.specOf(action);
    if (spec == null) continue;
    final args = entry['args'];
    if (args is! Map) continue;
    // 点过的按钮带状态回环（只认终态：已应用 / 失败）。
    var status = ChatEditRowStatus.proposed;
    final rawStatus = entry['status'];
    if (rawStatus == ChatEditRowStatus.applied.name) {
      status = ChatEditRowStatus.applied;
    } else if (rawStatus == ChatEditRowStatus.failed.name) {
      status = ChatEditRowStatus.failed;
    }
    final message = entry['message'];
    try {
      out.add(
        ChatEditSuggestion(
          label: label.trim(),
          action: spec.action,
          rawArgs: args,
          command: ChatEditCommand(
            spec: spec,
            args: validateChatEditArgs(spec, args),
          ),
          status: status,
          resultMessage: message is String && message.isNotEmpty
              ? message
              : null,
        ),
      );
    } on ChatEditArgsException {
      // `ai-live` 实测（2026-10-24）：模型在「信息不全」时会给
      // `{"action":"meal.delete","args":{}}` —— 意图对、目标待补。
      // 过去这里 `continue` 静默丢弃，三条全丢 ⇒ suggestions 空 ⇒ 整段
      // 信封被判无效 ⇒ 用户看到「说了要改、卡片却不弹」。
      // 现在**保留成待补信息的可点按钮**：它有合法 action，就不该被当成
      // 幻觉（未注册 action 在上面的 `specOf == null` 处已被丢弃）。
      out.add(
        ChatEditSuggestion(
          label: label.trim(),
          // 参数不全 ⇒ 没有可执行命令，但保留 action 供 UI 显示与补问。
          command: null,
          action: spec.action,
          rawArgs: args,
          needsMoreInfo: true,
          status: status,
          resultMessage: message is String && message.isNotEmpty
              ? message
              : null,
        ),
      );
    }
  }
  return List.unmodifiable(out);
}

ChatEditTurnItem _parseRow(
  int index,
  Object raw,
  ChatEditCommandRegistry registry,
  Object? rawOutcomes,
) {
  if (raw is! Map) {
    return ChatEditTurnItem(
      index: index,
      raw: const {},
      decodeError: '这条修改不是 {"action":…,"args":…} 形状，已忽略。',
      status: ChatEditRowStatus.failed,
    );
  }
  final action = raw['action'];
  final args = raw['args'];
  if (action is! String) {
    return ChatEditTurnItem(
      index: index,
      raw: raw,
      decodeError: '缺少修改类型（action），已忽略。',
      status: ChatEditRowStatus.failed,
    );
  }
  final spec = registry.specOf(action);
  if (spec == null) {
    return ChatEditTurnItem(
      index: index,
      raw: raw,
      decodeError: '不支持的修改类型「$action」。当前版本能改的范围见命令清单。',
      status: ChatEditRowStatus.failed,
    );
  }
  if (args is! Map) {
    return ChatEditTurnItem(
      index: index,
      raw: raw,
      decodeError: '修改「${spec.title}」缺少参数。',
      status: ChatEditRowStatus.failed,
    );
  }
  ChatEditTurnItem item = ChatEditTurnItem(index: index, raw: raw);
  try {
    item = ChatEditTurnItem(
      index: index,
      raw: raw,
      command: ChatEditCommand(
        spec: spec,
        args: validateChatEditArgs(spec, args),
      ),
    );
  } on ChatEditArgsException catch (error) {
    item = ChatEditTurnItem(
      index: index,
      raw: raw,
      decodeError: error.message,
      status: ChatEditRowStatus.failed,
    );
  }
  return _applyOutcome(item, index, rawOutcomes);
}

/// 把落库时并进信封的 `outcomes`（[encodeChatEditTurn] 写的）按 index 对位还原。
ChatEditTurnItem _applyOutcome(
  ChatEditTurnItem item,
  int index,
  Object? rawOutcomes,
) {
  if (rawOutcomes is! List) return item;
  for (final entry in rawOutcomes) {
    if (entry is! Map || entry['index'] != index) continue;
    final ok = entry['ok'];
    if (ok is! bool) continue;
    final message = entry['message'];
    final parsedRepair = _parseRepair(entry['repair']);
    return item.copyWith(
      status: ok ? ChatEditRowStatus.applied : ChatEditRowStatus.failed,
      resultMessage: message is String && message.isNotEmpty ? message : null,
      repair: parsedRepair,
    );
  }
  return item;
}

/// 解析 `outcomes[].repair`（四类缺实体；形状不认识就当作没有）。
ChatEditRepair? _parseRepair(Object? raw) {
  if (raw is! Map) return null;
  final name = raw['name'];
  if (name is! String || name.trim().isEmpty) return null;
  final trimmed = name.trim();
  return switch (raw['kind']) {
    'createFood' => ChatEditRepair.createFood(name: trimmed),
    'createExercise' => ChatEditRepair.createExercise(name: trimmed),
    'createVenue' => ChatEditRepair.createVenue(name: trimmed),
    'createWindow' =>
      raw['venueId'] is String
          ? ChatEditRepair.createWindow(
              name: trimmed,
              venueId: raw['venueId']! as String,
            )
          : null,
    _ => null,
  };
}

/// 把一条推荐按钮编码回可落库的形状（[parseChatEditTurn] 的逆）。
///
/// 点过的按钮带 `status`/`message` 一起落库：重启后仍是「已应用」，
/// 否则同一个按钮能重复写第二条。
Map<String, Object?> encodeSuggestion(ChatEditSuggestion suggestion) => {
  'label': suggestion.label,
  'action': suggestion.effectiveAction,
  'args': suggestion.command?.args ?? suggestion.rawArgs,
  if (suggestion.needsMoreInfo) 'needsMoreInfo': true,
  if (suggestion.status != ChatEditRowStatus.proposed)
    'status': suggestion.status.name,
  if (suggestion.resultMessage != null) 'message': suggestion.resultMessage,
};

/// 把编辑提议编码回可落库的文本（与 [parseChatEditTurn] 互逆）：
/// `{"reply":…,"edits":[原始提议…],"suggestions":[…],"outcomes":[…]}`。
String encodeChatEditTurn(ChatEditTurn turn) {
  final outcomes = [
    for (final row in turn.rows)
      if (row.status == ChatEditRowStatus.applied ||
          row.status == ChatEditRowStatus.failed)
        {
          'index': row.index,
          'ok': row.status == ChatEditRowStatus.applied,
          if (row.resultMessage != null) 'message': row.resultMessage,
          if (row.decodeError != null && row.resultMessage == null)
            'message': row.decodeError,
          if (row.repair != null)
            'repair': {
              'kind': row.repair!.kind.name,
              'name': row.repair!.name,
              if (row.repair!.venueId != null) 'venueId': row.repair!.venueId,
            },
        },
  ];
  return jsonEncode({
    'reply': turn.reply,
    'edits': [for (final row in turn.rows) row.raw],
    if (turn.suggestions.isNotEmpty)
      'suggestions': [
        for (final suggestion in turn.suggestions) encodeSuggestion(suggestion),
      ],
    if (outcomes.isNotEmpty) 'outcomes': outcomes,
  });
}
