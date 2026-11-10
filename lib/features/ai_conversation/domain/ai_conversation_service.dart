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

/// 支持首轮就强制 JSON 模式的会话服务（可选能力，不强制所有测试桩实现）。
///
/// 修改请求如果只在“补信封重跑”时才强制 JSON，首轮会先吐一段散文，用户会
/// 看到两条几乎相同的回复。实现方把同一套流式装配复用到 `forceJson=true`，
/// 控制器可在首轮直接走强约束，减少补跑。
abstract interface class JsonForcedConversationService {
  Stream<String> sendMessageForcedJson({
    required List<ConversationMessage> messages,
    required void Function(String chunk) onProgress,
    Stream<void>? cancelToken,
    String? systemContext,
  });
}
