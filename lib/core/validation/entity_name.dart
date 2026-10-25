/// 实体名称的统一长度上限（2026-10-21 审查 RV-P2-16）。
///
/// 食物 / 菜品 / 食堂地点 / 窗口 / 动作名都会进列表、快照与 AI 上下文；
/// 无上限的名称会把列表撑爆、把快照预算吃光，也会在备份里制造巨行。
/// 120 字远大于真实菜名（最长约 20 字），只拦异常输入。
const int kMaxEntityNameLength = 120;

/// 校验并返回 trim 后的名称；空/超长抛中文 [FormatException]。
String validatedEntityName(String raw, {required String label}) {
  final name = raw.trim();
  if (name.isEmpty) {
    throw FormatException('$label不能为空。');
  }
  if (name.length > kMaxEntityNameLength) {
    throw FormatException('$label最多 $kMaxEntityNameLength 个字。');
  }
  return name;
}
