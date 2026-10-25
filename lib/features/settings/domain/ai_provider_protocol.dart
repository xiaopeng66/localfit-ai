/// AI 供应商协议（docs/24 §2）。
///
/// 三种 wire 协议共用同一套本地约束（HTTPS、Key 只在头、不发照片之外的
/// 数据），区别只在**请求路径、请求体形状、认证头、SSE 事件形状**四件事。
/// 本枚举是「用户选了哪一种」的唯一事实源：endpoint、请求构建、流解析、
/// 设置页文案全部从这里派生，禁止各处再写字符串字面量。
///
/// 新增协议时必须同时补齐四处，缺一处会在编译期或测试里暴露：
/// requestPath、requestHeaders、请求体构建、SSE 解析分支
/// （见 `ai_protocol_wire.dart` 的 `AiProtocolWire`）。
enum AiProviderProtocol {
  /// OpenAI Chat Completions（默认，兼容绝大多数中转站）。
  chatCompletions,

  /// OpenAI Responses（`/v1/responses`，Codex 与新端点使用）。
  responses,

  /// Anthropic Messages（`/v1/messages`，Claude 官方与兼容网关）。
  anthropicMessages;

  /// 存储值与设置页下拉共用；旧库（v17 及以前）没有这一列，读取侧必须
  /// 把 null/未知值一律回落到 [chatCompletions]，绝不猜别的协议。
  String get storageValue => switch (this) {
    AiProviderProtocol.chatCompletions => 'chat_completions',
    AiProviderProtocol.responses => 'responses',
    AiProviderProtocol.anthropicMessages => 'anthropic_messages',
  };

  /// 设置页展示名。
  String get label => switch (this) {
    AiProviderProtocol.chatCompletions => 'Chat Completions（OpenAI 兼容）',
    AiProviderProtocol.responses => 'Responses（OpenAI /v1/responses）',
    AiProviderProtocol.anthropicMessages => 'Messages（Anthropic /v1/messages）',
  };

  /// 相对 base url 的请求路径。baseUrl 已保证以 `/` 结尾
  /// （[OpenAiCompatibleEndpoint]），故这里不带前导斜杠。
  String get requestPath => switch (this) {
    AiProviderProtocol.chatCompletions => 'chat/completions',
    AiProviderProtocol.responses => 'responses',
    AiProviderProtocol.anthropicMessages => 'messages',
  };

  /// 解析存储值。null、空串、未知字符串一律回落 [chatCompletions]：
  /// 这一列的语义是「用户显式选择过什么」，读不懂就等于没选过。
  static AiProviderProtocol fromStorage(String? value) {
    for (final protocol in AiProviderProtocol.values) {
      if (protocol.storageValue == value) return protocol;
    }
    return AiProviderProtocol.chatCompletions;
  }
}
