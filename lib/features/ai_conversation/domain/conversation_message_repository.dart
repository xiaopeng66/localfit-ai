import 'package:localfit_ai/features/ai_conversation/domain/conversation_message.dart';

/// 聊天记录持久化契约（docs/21 §5.7 数据来源「新增域：聊天记录」）。
///
/// 只保存对话文本与形态元数据；**不保存音频**（录音在转写后即删除，
/// docs/08 麦克风行），语音形态由 [ConversationMessage.durationMs] 记忆。
/// 图片消息保存的是聊天自己的副本路径，随「清除全部本地数据」删除。
abstract interface class ConversationMessageRepository {
  /// 当前只有一条默认会话（docs/21 §5.7 未画会话列表）。
  static const String defaultSessionId = 'default';

  /// 取最近 [limit] 条，按发生顺序（旧 → 新）返回。
  Future<List<ConversationMessage>> loadRecent({
    String sessionId = defaultSessionId,
    int limit = 200,
  });

  /// 写入或按 id 覆盖一条消息（乐观 UI：状态从 sending → sent/failed 会重写）。
  Future<void> save(
    ConversationMessage message, {
    String sessionId = defaultSessionId,
  });

  /// 清空一个会话的全部消息，返回**实际删除条数**（`RV4-P2-06`，破坏性操作）。
  ///
  /// 返回条数是为了**如实报数**（「已清除 N 条」），不是「删了就说删了」。
  /// 聊天图片副本不在本仓储里（见 `ChatImageStore.clearAll`）——调用方要
  /// 两件事一起做才算真的清干净。
  Future<int> clear({String sessionId = defaultSessionId});
}
