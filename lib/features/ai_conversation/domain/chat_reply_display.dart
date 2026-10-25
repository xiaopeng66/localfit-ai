/// 助手回复的**展示清洗**（2026-10-24 用户：「食堂菜品 AI 分析会转发英文代码
/// 片段」「AI 对接很多次推不了应用卡片」）。
///
/// 两件事，都是「别把内部东西当人话发给用户」：
/// 1. **内部引用**：`[canteen-dish:mx-3]` / `[dish:…]` / `[food:…]` /
///    `[meal:…]` 这类方括号坐标是给模型看的快照 id，用来定位要改哪一条。
///    模型有时会照抄进 reply 里——那是英文代码片段，气泡里不该出现；
/// 2. **半截信封**：模型把 JSON 信封写坏（解析失败）时，原始输出会以纯文本
///    回退上屏，用户看到的是 `{"action":"meal.create","args":…`。宁可给一句
///    人话 + 保留「让 AI 给出可应用的修改」入口，也不把代码片段亮出来。
library;

/// 内部引用（`[token:id]`）的正则：小写拉丁 token + 冒号 + 不含 `]` 与换行的
/// 内容。中文正文几乎不可能命中这个形状，所以清洗是**保守**的。
final RegExp _internalRef = RegExp(r'\[[a-z][a-z0-9_-]{0,24}:[^\]\n]{0,80}\]');

/// 剥掉内部引用与它们留下的多余空白（行内双空格折成一个）。
String stripInternalRefs(String text) {
  if (!text.contains('[')) return text;
  return text
      .replaceAll(_internalRef, '')
      .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
      .replaceAll(RegExp(r'[ \t]+\n'), '\n');
}

/// 回复是否像 chat-edit 信封（首个非空白字符是 `{`）。
///
/// 与流式期间的隐藏判据同源（`_looksLikeEnvelope`）：那时候藏原始 JSON，
/// 这里管「藏不掉了怎么收尾」。
bool looksLikeEnvelopeText(String text) => text.trimLeft().startsWith('{');

/// 半截信封的替代文案：说清「没成」，并给出两条可执行的路。
const String kMalformedEnvelopeNotice =
    '这次没能整理成可应用的修改。可以再点「让 AI 给出可应用的修改」重来一次，'
    '或把要求说得更具体一点。';

/// 上屏用的回复文本：信封残留 → 人话；否则剥掉内部引用。
String replyTextForDisplay(String text) => looksLikeEnvelopeText(text)
    ? kMalformedEnvelopeNotice
    : stripInternalRefs(text);
