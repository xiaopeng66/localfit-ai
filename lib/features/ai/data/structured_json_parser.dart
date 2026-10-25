/// 三层 JSON 解析 fallback（docs/07 §10 的 2.0-2 阶段）。
///
/// 层 1：原生 `response_format=json_schema` → content 是纯 JSON。
/// 层 2：Markdown fence / 散文包裹 → 提取最外层 JSON 对象。
/// 层 3：strict JSON 修复（尾逗号、智能引号、单引号）后重试。
///
/// 只接受 JSON object 结果；数组/标量/不可解析一律抛错，由上层把
/// 失败映射为可恢复 UI 状态，绝不把半解析数据写进正式事实。
library;

import 'dart:convert';

/// 解析 AI 文本响应为 JSON object。
///
/// 抛 [ArgumentError]（空内容/非 object）或 [FormatException]
/// （三层 fallback 均失败）。
Map<String, dynamic> parseStructuredJson(String content) {
  final trimmed = content.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError('AI content is empty');
  }

  Map<String, dynamic>? tryParse(String text) {
    try {
      final decoded = const JsonDecoder().convert(text);
      if (decoded is Map<String, dynamic>) return decoded;
      // 可解析但不是对象（数组/标量）——明确拒绝。
      throw ArgumentError(
        'AI content is a JSON ${decoded.runtimeType}, '
        'not an object',
      );
    } on FormatException {
      return null;
    }
  }

  // 层 1：直接解析。
  final direct = tryParse(trimmed);
  if (direct != null) return direct;

  // 层 2：提取最外层平衡的 JSON 对象。
  final extracted = _extractObject(trimmed);
  if (extracted != null) {
    final decoded = tryParse(extracted);
    if (decoded != null) return decoded;
    // 层 3：对提取结果做修复后重试。
    final repaired = tryParse(_repairStrictJson(extracted));
    if (repaired != null) return repaired;
  }

  // 层 3 兜底：整段修复。
  final repairedWhole = tryParse(_repairStrictJson(trimmed));
  if (repairedWhole != null) return repairedWhole;

  throw const FormatException(
    'AI content contained no JSON object after three-layer fallback',
  );
}

/// strict JSON 常见修复：智能引号、尾逗号、单引号键/值。
String _repairStrictJson(String text) {
  var repaired = text
      .replaceAll('\u{201C}', '"')
      .replaceAll('\u{201D}', '"')
      .replaceAll('\u{2018}', "'")
      .replaceAll('\u{2019}', "'");
  // 尾逗号：`[1,2,]` / `{...,"a":1,}`。
  repaired = repaired.replaceAllMapped(RegExp(r',\s*([\]}])'), (m) => m[1]!);
  // 单引号键：`{'key':` / `,'key':` → `"key":`。
  repaired = repaired.replaceAllMapped(
    RegExp(r"([{,]\s*)'([^']*?)'(\s*:)"),
    (m) => '${m[1]}"${m[2]}"${m[3]}',
  );
  // 单引号值：`: 'value'` → `: "value"`。
  repaired = repaired.replaceAllMapped(
    RegExp(r"(:\s*)'([^']*?)'([,}\]])"),
    (m) => '${m[1]}"${m[2]}"${m[3]}',
  );
  return repaired;
}

/// 扫描第一个 `{` 起的平衡对象（字符串内花括号不计数）。
String? _extractObject(String text) {
  final start = text.indexOf('{');
  if (start < 0) return null;
  var depth = 0;
  var inString = false;
  var escaped = false;
  for (var i = start; i < text.length; i++) {
    final char = text[i];
    if (escaped) {
      escaped = false;
      continue;
    }
    if (char == r'\') {
      if (inString) escaped = true;
      continue;
    }
    if (char == '"') {
      inString = !inString;
      continue;
    }
    if (inString) continue;
    if (char == '{') depth++;
    if (char == '}') {
      depth--;
      if (depth == 0) {
        return text.substring(start, i + 1);
      }
    }
  }
  return null;
}
