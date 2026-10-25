/// 「模型把 JSON 包在散文/围栏里」的**统一抢救**（2026-10-16 真机实测补）。
///
/// 三处 AI 出口都踩过同一个坑（供应商 `ai.furry.vg` /
/// `deepseek-ai/deepseek-v4.1-flash`）：
///   * 对话信封（`parseChatEditTurn`）：先写「好的，已记下…」再贴 JSON；
///   * 训练计划（`OpenAiCompatibleWorkoutPlanProvider`）：同样先说明再贴 JSON；
///   * 拍照识餐（`OpenAiCompatibleMealRecognitionProvider`）：同一习惯。
/// 协议/提示词里都写了「只放一个 JSON 对象、不要散文与代码围栏」，模型仍会犯；
/// 全靠提示词是**不稳定**的（实测时好时坏），所以解析侧补一层确定性兜底。
///
/// 口径（宁缺勿猜）：
///   * 只认**顶层**花括号对（嵌套的花括号属于外层对象本身）；
///   * 跳过 JSON 字符串内部的花括号（含转义），否则 `reply` 里写个「{」就把
///     配对算歪；
///   * 结果**多于一个** ⇒ 有歧义，返回 null（不替用户挑一个）；
///   * 返回的是**文本片段**，调用方仍走各自原有的严格解码器 —— 兜底只负责
///     「把 JSON 抠出来」，结构校验一条都不放松。
library;

/// 抠出**恰好一个**完整 JSON 对象；没有或多于一个都返回 null。
String? salvageSingleJsonObject(String text) {
  final matches = _topLevelJsonObjects(text);
  return matches.length == 1 ? matches.single : null;
}

/// 顶层、配对的花括号片段（跳过字符串与转义）。
List<String> _topLevelJsonObjects(String text) {
  final out = <String>[];
  var depth = 0;
  var start = -1;
  var inString = false;
  var escaped = false;
  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (ch == r'\') {
        escaped = true;
      } else if (ch == '"') {
        inString = false;
      }
      continue;
    }
    if (ch == '"') {
      inString = true;
      continue;
    }
    if (ch == '{') {
      if (depth == 0) start = i;
      depth++;
      continue;
    }
    if (ch == '}') {
      if (depth == 0) continue; // 多余的右括号：忽略
      depth--;
      if (depth == 0 && start >= 0) {
        out.add(text.substring(start, i + 1));
        start = -1;
      }
    }
  }
  return out;
}

/// 给「整段应是一个 JSON 对象」的出口用：整段已经是它就直接用，否则抢救一次；
/// 救不出来就原样返回（让各自的解码器抛它们自己的格式错）。
String normalizeJsonEnvelopeContent(String raw) {
  final trimmed = raw.trim();
  if (trimmed.startsWith('{') && trimmed.endsWith('}')) return trimmed;
  return salvageSingleJsonObject(trimmed) ?? trimmed;
}
