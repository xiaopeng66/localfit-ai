import 'dart:async';

/// 「信封编译器」：把一段已经生成的助手回复转成 chat-edit JSON 信封。
///
/// 【为什么单列一个能力，而不是继续在对话流上打补丁】
/// 2026-11-03 用户：「AI 对话不按协议输出 JSON 信封，有没有根治的办法，
/// 一直打补丁没啥用」。根因不是提示词不够狠，而是**同一次生成既要像人
/// 一样说话、又要严格输出 JSON**——视觉/小参模型经常前者成功、后者失败
/// （看懂了图、写出了完整提案，就是不输出 JSON）。
///
/// 根治办法是把两件事拆开：
/// 1. 对话流照常生成自然语言（用户看到的是人话）；
/// 2. 只有当回复里**可能含有可执行操作**时，再发一次**纯文字、强制 JSON**
///    的编译请求：输入 = 用户请求 + 助手刚才的回复 + 协议/快照，输出 =
///    信封。chat-completions 走 `response_format: json_object`，
///    Responses 走 `text.format`；供应商不支持时由实现方自动降级一次。
///
/// 这样「JSON 合规」由供应商的解码约束保证，而不是靠再写一条提示词。
/// 编译器拿不到/失败时，调用方仍回落到原有的整轮重跑与散文抢救。
abstract interface class AiEnvelopeCompiler {
  /// 编译一封 chat-edit 信封；流式返回原始输出（由调用方解码）。
  ///
  /// [userText] 用户这轮的请求（图片轮可能是空串）；
  /// [assistantReply] 助手刚才已经展示给用户的回复；
  /// [systemContext] 协议 + 可编辑数据快照（与对话同一份）；
  /// [onProgress] 流式增量（编译输出通常很短，仍按流处理以复用取消）。
  ///
  /// 【docs/66 §5.2】手动编译的输入扩展：
  /// * [conversationContext] 目标回复**之前**的最近对话（≤6 条、单条 ≤600
  ///   字、总 ≤3000 字；图片用「[图片]」占位）——只用于理解「刚才那份/第二
  ///   项」这类指代，不是新的请求；自动补跑路径不传（旧调用行为不变）。
  /// * [targetLocalDate] 被点击那条助手消息的本地日期（`yyyy-MM-dd`）——
  ///   编译 prompt 写明它，避免「今晚」被解析成错误日期；空 = 旧调用行为。
  Stream<String> compileEnvelope({
    required String userText,
    required String assistantReply,
    required String systemContext,
    required void Function(String chunk) onProgress,
    Stream<void>? cancelToken,
    String conversationContext,
    String targetLocalDate,
  });
}
