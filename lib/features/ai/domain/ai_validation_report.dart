/// 本地校验报告与草案拒绝异常（docs/07 §4.4「本地校验报告」）。
///
/// 报告会**原样渲染到任务卡**，所以 `errors` 的每一条都必须是本地撰写的
/// 可行动文案（decoder 的固定指引、面向用户的失败归类），绝不能带模型
/// 原文、URL、路径、SQL——原始异常的文本只允许落成固定文案后再进报告
/// （docs/11 §3-B 隐私红线）。
library;

/// 本地校验报告（decoder 违规、未知 ID、越界数字等）。
class AiValidationReport {
  const AiValidationReport({required this.kind, required this.errors});

  /// 失败类别：`draft_format`（decoder 拒绝）、`unexpected_error` 等；
  /// 任务卡的错误分类 chip 据此落「超时/网络/格式/其他」。
  final String kind;
  final List<String> errors;
}

/// decoder 违规明细的统一入口。
///
/// 有的 decoder 抛 `FormatException`（单条 message），有的抛带违规清单的
/// 自定义异常（如 `MenuNormalizeFormatException`）——后者实现本接口后，
/// 能力层就能把 `violations` 收进 [AiValidationReport]，两种形状都可达
/// 生产上屏（docs/11 BUG-5），不必在能力层认识每个 decoder 的类型。
abstract interface class AiDecoderViolations {
  /// 本地撰写的违规明细（每条都是可上屏的固定文案）。
  List<String> get violations;
}

/// decoder/本地校验拒绝草案：携带可上屏的明细。
///
/// 严格 decoder 失败时抛出（原先是收成一句通用「供应商返回格式无法识别」
/// ——明细在生产路径上不可达，docs/11 BUG-5）。
///
/// 【docs/32 §4 T6c】原先的捕获方 `AiDraftController` 随旧任务执行管线退役；
/// 该异常现在由对话侧的严格 decoder/执行器路径消费（命令层与各 JSON
/// decoder 仍按「格式」分类上屏 [AiValidationReport]）。
