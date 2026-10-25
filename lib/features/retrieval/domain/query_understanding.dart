/// 查询理解（docs/39 §6.3）：同义词/别名扩展 + 槽位，不额外调 LLM。
///
/// 目的不是「理解自然语言」，而是把**口语说法**映射到检索词与过滤条件：
/// 「想吃点清淡不辣的」→ 关键词 {清淡, 不辣} + 软偏好 {清淡}；
/// 「中午有什么面」→ 餐次槽位 {午餐} + 关键词 {面}。
library;

/// 一次查询的理解结果。
final class UnderstoodQuery {
  const UnderstoodQuery({
    required this.original,
    required this.keywords,
    required this.expanded,
    required this.slots,
    required this.negations,
  });

  final String original;

  /// 原文切出的关键词（bigram 之前的「词」级）。
  final List<String> keywords;

  /// 同义词/别名扩展出来的检索词（如「洋芋」→「土豆」）。
  final List<String> expanded;

  /// 餐次槽位（早餐/午餐/晚餐/加餐），空 = 未指定。
  final Set<String> slots;

  /// 否定词（「不辣」「不要香菜」）——只用于**软惩罚**，绝不用于硬过滤。
  final Set<String> negations;

  bool get isEmpty => keywords.isEmpty && expanded.isEmpty;
}

/// 同义词表（可用户扩展；docs/39 §6.3）。
const Map<String, List<String>> kSynonymTable = {
  '清淡': ['清蒸', '水煮', '少油', '少盐', '白灼', '清炒'],
  '辣': ['麻辣', '香辣', '剁椒', '辣子', '辣椒'],
  '面': ['面条', '拉面', '拌面', '刀削面', '米线'],
  '饭': ['米饭', '盖饭', '炒饭', '煲仔饭'],
  '汤': ['汤水', '羹', '例汤'],
  '土豆': ['洋芋', '马铃薯'],
  '西红柿': ['番茄'],
  '红薯': ['地瓜', '番薯'],
  '鸡蛋': ['蛋', '鸡子'],
  '豆腐': ['豆制品'],
  '素': ['素食', '素菜', '斋'],
  '油炸': ['炸', '油煎', '天妇罗'],
  '蒸': ['清蒸', '粉蒸'],
};

const Map<String, List<String>> _keywordToSlot = {
  '早餐': ['早', '早饭', '早上'],
  '午餐': ['中午', '午饭', '中饭'],
  '晚餐': ['晚上', '晚饭', '晚餐'],
  '加餐': ['宵夜', '夜宵', '加餐', '下午茶'],
};

/// 理解一条查询。
UnderstoodQuery understandQuery(String raw) {
  final text = raw.trim();
  if (text.isEmpty) {
    return const UnderstoodQuery(
      original: '',
      keywords: [],
      expanded: [],
      slots: {},
      negations: {},
    );
  }
  final negations = <String>{};
  // 否定：「不 X」「别 X」「不要 X」「不吃 X」。
  for (final match in RegExp(
    r'(?:不要|不吃|没有|别|不)([\u4e00-\u9fa5]{1,4})',
  ).allMatches(text)) {
    // 剥掉语气助词与程度修饰（「不辣的」「不要太辣」→「辣」）。
    final word = match
        .group(1)!
        .replaceAll(RegExp(r'^(?:太|很|那么|这么|特别|非常)+'), '')
        .replaceAll(RegExp(r'[的了吧呢啊哦嘛]+$'), '');
    if (word.isNotEmpty) negations.add(word);
  }
  final expanded = <String>{};
  for (final entry in kSynonymTable.entries) {
    final hit =
        text.contains(entry.key) ||
        entry.value.any((alias) => text.contains(alias));
    if (hit) {
      expanded.addAll(entry.value);
      expanded.add(entry.key);
    }
  }
  final slots = <String>{};
  for (final entry in _keywordToSlot.entries) {
    if (entry.value.any(text.contains)) slots.add(entry.key);
  }
  // 关键词：原文按标点/空白切开，丢掉语气词与否定词里的纯修饰。
  final keywords = <String>[
    for (final part in text.split(RegExp(r'[\s，。！？、；：,.!?;:（）()]+')))
      if (part.trim().isNotEmpty) part.trim(),
  ];
  // 扩展词从否定集合里剔除（「不辣」不应把「辣」加成正向检索词）。
  expanded.removeAll(negations);
  return UnderstoodQuery(
    original: text,
    keywords: keywords,
    expanded: expanded.toList(growable: false),
    slots: slots,
    negations: negations,
  );
}

/// 从一段文本生成中文 bigram 集合（单字也保留），关键词路的核心。
Set<String> bigramsOf(String text) {
  final value = text.trim();
  if (value.isEmpty) return const {};
  final out = <String>{value};
  for (var i = 0; i + 2 <= value.length; i++) {
    out.add(value.substring(i, i + 2));
  }
  return out;
}
