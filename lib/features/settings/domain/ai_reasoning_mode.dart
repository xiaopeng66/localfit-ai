/// 推理开关（docs/29 §P4）。按 provider 配置，作用于**全部 AI 出口**
/// （对话 / 工作台任务 / 餐图识别 / 训练计划）——出口共享同一份配置，
/// 开关也只在设置里这一处。
///
/// 实测背景（2026-10-05，docs/29 §P4 表）：推理型模型会把 token 花在
/// `reasoning_content` 上，`content` 为空或很短，小 `max_tokens` 下客户端
/// 只会渲染出空回复。对 Chat Completions 协议发
/// `thinking: {"type": "disabled"}` 是实测可行的三种写法里语义最直白的
/// 一种；顶层 `enable_thinking: false` 实测 400，不可用。
///
/// 默认档是 [disabled]（关闭推理）：读取侧对 NULL（从未选过）回落到它，
/// 与 protocol 列「null → Chat Completions」的回落口径一致。
enum AiReasoningMode {
  /// 关闭推理（更快）：chat 协议发 `thinking: {"type": "disabled"}`。
  disabled('disabled', '关闭推理（更快）'),

  /// 供应商默认：不发任何推理字段，由上游模型自身配置决定。
  /// Responses / Anthropic 两协议**始终**不发该字段（尚未实测，docs/29 §6）。
  providerDefault('provider_default', '默认（由上游决定）');

  const AiReasoningMode(this.storageValue, this.label);

  /// 落库值（`AiProviderConfigs.reasoning` 文本列）。
  final String storageValue;

  /// 设置界面显示名。
  final String label;

  /// NULL＝从未选过 → 默认档「关闭推理」。
  static AiReasoningMode fromStorage(String? value) =>
      value == providerDefault.storageValue
      ? providerDefault
      : AiReasoningMode.disabled;
}
