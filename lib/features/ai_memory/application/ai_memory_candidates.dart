import 'dart:convert';

import 'package:localfit_ai/features/ai_memory/domain/ai_memory.dart';

/// 从模型回复里解析「记忆候选」（docs/38 §4.3 v2 / docs/38 §11 未做项）。
///
/// wire 形状（与 chat-edit 信封同风格，但**独立**于 chat-edit——候选不是
/// 要执行的命令，点选后走 `AiMemoryRepository.remember`）：
/// ```json
/// {"reply":"我找到了 2 条值得记住的","candidates":[{"text":"…","kind":"preference","domain":"nutrition","tags":["…"]}]}
/// ```
/// 解析纪律与 `salvageSingleJsonObject` 同源（只认恰好一个配平对象），
/// 但这里用 Dart 自带的「从头扫描」版本，不依赖对话域的内部件。
///
/// 校验口径（宁缺毋滥）：
/// * `text` 必填、≤[kAiMemoryMaxTextLength] 字；超过的整条丢弃（不是截断——
///   截断会把一句话变成半句话，用户看着一条残缺记忆点「保存」）。
/// * `kind`/`domain` 无法识别时**回落缺省**（偏好/其他），不丢条——
///   分类是给页面分组用的，不值得为它丢掉内容。
/// * `tags` 去空白、去重、≤[kAiMemoryMaxTags] 个、每个 ≤[kAiMemoryMaxTagLength]。
/// * 单条候选内部字段类型不对（text 不是字符串等）丢弃该条，不影响其余。
final class AiMemoryCandidate {
  const AiMemoryCandidate({
    required this.text,
    required this.kind,
    required this.domain,
    required this.tags,
  });

  final String text;
  final AiMemoryKind kind;
  final AiMemoryDomain domain;
  final List<String> tags;
}

/// 解析结果：`reply` 是给用户看的说明（可能为空）；`candidates` 是合法候选。
final class AiMemoryCandidateParse {
  const AiMemoryCandidateParse({required this.reply, required this.candidates});

  final String reply;
  final List<AiMemoryCandidate> candidates;

  bool get isEmpty => reply.isEmpty && candidates.isEmpty;
}

AiMemoryCandidateParse parseAiMemoryCandidates(String raw) {
  final text = raw.trim();
  if (text.isEmpty) {
    return const AiMemoryCandidateParse(reply: '', candidates: []);
  }
  final json = _singleJsonObject(text);
  // ignore: prefer_const_constructors
  if (json == null) return AiMemoryCandidateParse(reply: text, candidates: []);
  final reply = json['reply'];
  final rawCandidates = json['candidates'];
  if (rawCandidates is! List) {
    return AiMemoryCandidateParse(
      reply: reply is String ? reply : '',
      candidates: const [],
    );
  }
  final candidates = <AiMemoryCandidate>[];
  for (final entry in rawCandidates) {
    final candidate = parseAiMemoryCandidate(entry);
    if (candidate != null) candidates.add(candidate);
    if (candidates.length >= 3) break;
  }
  return AiMemoryCandidateParse(
    reply: reply is String ? reply.trim() : '',
    candidates: candidates,
  );
}

/// 解析**单条**候选（待确认队列从 `background_jobs.payload` 还原时复用）。
AiMemoryCandidate? parseAiMemoryCandidate(Object? entry) {
  if (entry is! Map) return null;
  final text = entry['text'];
  if (text is! String) return null;
  final trimmed = text.trim();
  if (trimmed.isEmpty || trimmed.length > kAiMemoryMaxTextLength) return null;
  final tags = <String>[];
  final rawTags = entry['tags'];
  if (rawTags is List) {
    for (final tag in rawTags) {
      if (tag is! String) continue;
      final value = tag.trim();
      if (value.isEmpty ||
          value.length > kAiMemoryMaxTagLength ||
          tags.contains(value)) {
        continue;
      }
      tags.add(value);
      if (tags.length >= kAiMemoryMaxTags) break;
    }
  }
  return AiMemoryCandidate(
    text: trimmed,
    kind: AiMemoryKind.tryParse(entry['kind']) ?? AiMemoryKind.preference,
    domain: AiMemoryDomain.tryParse(entry['domain']) ?? AiMemoryDomain.general,
    tags: tags,
  );
}

/// 从可能带散文的回复里提取**恰好一个**配平的顶层 JSON 对象。
///
/// 与对话域的 `salvageSingleJsonObject` 同一口径：字符串感知（花括号在
/// 字符串里不算）、多于一个 ⇒ null（不替用户猜）。
Map<String, Object?>? _singleJsonObject(String text) {
  Map<String, Object?>? found;
  var depth = 0;
  var start = -1;
  var inString = false;
  var escaped = false;
  for (var index = 0; index < text.length; index++) {
    final char = text[index];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (char == r'\') {
        escaped = true;
      } else if (char == '"') {
        inString = false;
      }
      continue;
    }
    if (char == '"') {
      inString = true;
    } else if (char == '{') {
      if (depth == 0) start = index;
      depth++;
    } else if (char == '}') {
      if (depth == 0) continue;
      depth--;
      if (depth == 0 && start >= 0) {
        if (found != null) return null;
        try {
          final decoded = jsonDecode(text.substring(start, index + 1));
          if (decoded is Map<String, Object?>) found = decoded;
        } on FormatException {
          return null;
        }
        start = -1;
      }
    }
  }
  return found;
}

/// 提炼记忆的提示词（发给模型；随消息一起走既有通道）。
String aiMemoryExtractPrompt(String transcript) =>
    '''
以下是这段对话的记录（逐条，U=用户 A=AI）：

$transcript

请从中找出**值得长期记住**的用户信息（口味与偏好、作息与日程习惯、器械/厨房条件、常去的食堂窗口、沟通偏好、近况），输出一个 JSON 对象：
{"reply":"给用户看的一句中文说明","candidates":[{"text":"一句话，不超过 140 字","kind":"preference|habit|fact|context","domain":"nutrition|training|schedule|canteen|general","tags":["关键词"]}]}
规则：
- 最多 3 条；没有值得记的就给空数组（candidates: []），并在 reply 里说明。
- **能落到结构化字段的不要收**：过敏/忌口/饮食标签（用约束命令）、目标、身高体重出生年、每日目标、训练计划——这些 App 已有专门的管理处，写进记忆会造成两处不一致。
- 不要收一次性事实（「今天吃了鸡腿」）、不要收敏感信息（证件/银行/移民类）、不要编造没说过的事。
- 整段回复只放这一个 JSON 对象，不要加任何解释或代码围栏。
'''
        .trim();
