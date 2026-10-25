import 'package:drift/drift.dart';
import 'package:localfit_ai/data/database/app_database.dart' as db;
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_registry.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_turn.dart';
import 'package:localfit_ai/features/ai_conversation/domain/conversation_message.dart';
import 'package:localfit_ai/features/ai_conversation/domain/conversation_message_repository.dart';

/// 聊天记录的 Drift 实现（表 `ConversationMessages`，docs/21 §7.2）。
///
/// 形态映射（表里没有 kind 列，用既有列推导，不新增 schema）：
///  * `imagePath != null` → 图片；
///  * `audioPath != null` 或 `durationMs != null` → 语音（P10 需求 36 后
///    **只读不写**：语音输入已删，这两列只为历史库里的旧语音消息保留——
///    没有这条推导，老消息重启后会退化成纯文本）；
///  * 助手消息的 textContent 能解析成 chat-edit 信封 → 编辑卡（docs/23 §1），
///    落库时整体编码进 textContent（提议 + 逐条结果都在里面），重启可还原；
///  * 否则 → 文本。
final class DriftConversationMessageRepository
    implements ConversationMessageRepository {
  DriftConversationMessageRepository({
    required this.database,
    ChatEditCommandRegistry? editRegistry,
  }) : _editRegistry = editRegistry ?? ChatEditCommandRegistry();

  final db.AppDatabase database;
  final ChatEditCommandRegistry _editRegistry;

  @override
  Future<List<ConversationMessage>> loadRecent({
    String sessionId = ConversationMessageRepository.defaultSessionId,
    int limit = 200,
  }) async {
    if (limit <= 0) return const [];
    // 时间列按秒存（drift 默认），同一秒内的「用户消息 + 助手回复」会并列，
    // 所以用 rowid 兜底排序：它精确等于插入顺序，不受时间精度影响。
    final query = database.select(database.conversationMessages)
      ..where((row) => row.sessionId.equals(sessionId))
      ..orderBy([
        (row) => OrderingTerm.desc(const CustomExpression<int>('rowid')),
      ])
      ..limit(limit);
    final rows = await query.get();
    return [for (final row in rows.reversed) _map(row)];
  }

  @override
  Future<int> clear({
    String sessionId = ConversationMessageRepository.defaultSessionId,
  }) async {
    // 真删（不是软删）：用户要求的是「清除历史」，软删等于把字节留在库里。
    return (database.delete(
      database.conversationMessages,
    )..where((row) => row.sessionId.equals(sessionId))).go();
  }

  @override
  Future<void> save(
    ConversationMessage message, {
    String sessionId = ConversationMessageRepository.defaultSessionId,
  }) async {
    await database
        .into(database.conversationMessages)
        .insertOnConflictUpdate(
          db.ConversationMessagesCompanion.insert(
            id: message.id,
            sessionId: sessionId,
            role: message.role == ConversationRole.user ? 'user' : 'assistant',
            textContent: _textContentOf(message),
            createdAt: message.createdAt,
            imagePath: Value(
              message.kind == ConversationMessageKind.image
                  ? message.imagePath
                  : null,
            ),
            durationMs: Value(
              message.kind == ConversationMessageKind.voice
                  ? message.durationMs
                  : null,
            ),
            status: switch (message.status) {
              ConversationMessageStatus.sending => 'sending',
              ConversationMessageStatus.sent => 'sent',
              ConversationMessageStatus.error => 'failed',
            },
          ),
        );
  }

  /// 编辑卡消息落库的不是 reply 文本，而是完整信封（含逐条结果），
  /// 这样重启后 [parseChatEditTurn] 能原样还原卡片状态（docs/23 §1）。
  String _textContentOf(ConversationMessage message) {
    final turn = message.editTurn;
    if (turn == null) return message.text;
    return encodeChatEditTurn(turn);
  }

  ConversationMessage _map(db.ConversationMessage row) {
    // 编辑卡只可能是助手消息：用户消息里就算贴了形似信封的 JSON 也按
    // 纯文本处理，绝不被当成编辑卡（防伪造 + 防误解）。
    if (row.role == 'assistant' && row.imagePath == null) {
      final turn = parseChatEditTurn(row.textContent, _editRegistry);
      if (turn != null) {
        return ConversationMessage(
          id: row.id,
          role: ConversationRole.assistant,
          text: turn.reply,
          createdAt: row.createdAt,
          status: switch (row.status) {
            'sending' => ConversationMessageStatus.sending,
            'failed' => ConversationMessageStatus.error,
            _ => ConversationMessageStatus.sent,
          },
          kind: ConversationMessageKind.editProposal,
          editTurn: turn,
        );
      }
    }
    return ConversationMessage(
      id: row.id,
      role: row.role == 'user'
          ? ConversationRole.user
          : ConversationRole.assistant,
      text: row.textContent,
      createdAt: row.createdAt,
      status: switch (row.status) {
        'sending' => ConversationMessageStatus.sending,
        'failed' => ConversationMessageStatus.error,
        _ => ConversationMessageStatus.sent,
      },
      kind: _kindOf(row),
      imagePath: row.imagePath,
      durationMs: row.durationMs,
    );
  }

  ConversationMessageKind _kindOf(db.ConversationMessage row) {
    if (row.imagePath != null) return ConversationMessageKind.image;
    if (row.audioPath != null || row.durationMs != null) {
      return ConversationMessageKind.voice;
    }
    return ConversationMessageKind.text;
  }
}
