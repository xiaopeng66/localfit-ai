import 'dart:async';

import 'package:localfit_ai/features/ai_conversation/domain/conversation_message.dart';

/// AI 对话服务抽象接口。
///
/// 实现方负责把对话历史发到模型并流式返回助手回复。调用方负责：
/// - 构造含 system prompt 的完整消息上下文
/// - 展示流式文本
/// - 错误分类与用户提示
abstract interface class AiConversationService {
  /// 向模型发送消息并流式返回助手回复。
  ///
  /// [messages] 完整上下文（含 system prompt + 历史 + 当前用户消息）；
  /// [systemContext] 额外的 system 段（chat-edit 协议 + 可编辑数据快照，
  /// docs/23 §3），null = 本次不注入；[onProgress] 在流式 chunk 到达时回调，
  /// 可 null（即非流式）；cancelToken 取消时抛异常。
  Stream<String> sendMessage({
    required List<ConversationMessage> messages,
    required void Function(String chunk) onProgress,
    Stream<void>? cancelToken,
    String? systemContext,
  });
}
