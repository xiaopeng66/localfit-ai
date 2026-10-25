/// 食物名称的**固定格式**（ADR-037）：
///
/// ```
/// 主名（备注；备注2）
/// ```
///
/// 规则（与 `tool/food_catalog/normalize_food_library.py` 的
/// `normalize_name` **同一套**，由测试用 1000 条语料逐字钉住）：
///
/// 1. 括号统一：`[]【】〔〕「」『』《》〈〉` → `（）`，散引号 `" ' " " ' '` 丢弃；
///    **结构本来就坏**（右括号出现在左括号之前）→ 原样返回，不猜；
/// 2. 括号内的备注全部摘出来，主名保留在括号外；
/// 3. 主名开头若有一段**原样重复两次**（`逍遥老杨家逍遥老杨家`），收成一次；
/// 4. 主名末尾的规格（`300克` / `52g`）搬进备注；
/// 5. 主名末尾的短横线后缀（`鲫鱼-天津`）搬进备注；
/// 6. 主名去掉所有空白、首尾标点；
/// 7. 备注按出现顺序用 `；` 连接、去重，统一放在名称末尾；
/// 8. 主名为空（整名都在括号里）→ 原样返回，不把括号内容搬两遍。
///
/// **不删任何备注文字**：只搬家（进括号/合并），不改写、不翻译、不补全。
String normalizeFoodNameFormat(String raw) {
  final unified = _unifyBrackets(raw);
  if (identical(unified, null)) return raw; // 结构坏：原样返回
  var s = unified.trim();

  final notes = <String>[];
  var main = s.replaceAllMapped(RegExp(r'（([^）]*)）'), (match) {
    notes.addAll(_splitNotes(match.group(1)!));
    return '';
  });

  main = _collapseRepeatedPrefix(main);

  // 尾规格（52g / 300克）→ 备注
  final spec = RegExp(
    r'(\d+(?:\.\d+)?\s*(?:kg|g|mg|ml|l|克|千克|公斤|毫升|升|袋|包|瓶|盒|罐|片|粒|支|条|份|斤|两|只|个|串|块|枚|听|杯|碗))\s*$',
    caseSensitive: false,
  ).firstMatch(main);
  if (spec != null && main.length > spec.group(1)!.length) {
    notes.add(spec.group(1)!.trim());
    main = main.substring(0, spec.start).trim();
  }

  // 短横线后缀（鲫鱼-天津）→ 备注
  final suffix = RegExp(r'^(.+?)[-—]\s*([\u4e00-\u9fffA-Za-z]{2,6})$')
      .firstMatch(main);
  if (suffix != null) {
    notes.add(suffix.group(2)!);
    main = suffix.group(1)!.trim();
  }

  if (main.contains(' ')) {
    main = main.replaceAll(RegExp(r'\s+'), '');
  }
  main = _trimPunctuation(main);
  // 主名为空：整名都在括号里（`【咸烧白】（扣肉）`）——原样返回，别搬两遍。
  if (main.isEmpty) return raw;

  final cleanNotes = <String>[];
  for (final note in notes) {
    final cleaned = _trimPunctuation(note.replaceAll(RegExp(r'\s+'), ''));
    if (cleaned.isNotEmpty && !cleanNotes.contains(cleaned)) {
      cleanNotes.add(cleaned);
    }
  }
  final newName = cleanNotes.isEmpty ? main : '$main（${cleanNotes.join('；')}）';
  return newName;
}

const Map<String, String> _bracketMap = {
  '(': '（',
  '[': '（',
  '【': '（',
  '〔': '（',
  '「': '（',
  '『': '（',
  '《': '（',
  '〈': '（',
  ')': '）',
  ']': '）',
  '】': '）',
  '〕': '）',
  '」': '）',
  '』': '）',
  '》': '）',
  '〉': '）',
};
const Set<String> _strayQuotes = {'"', "'", '“', '”', '‘', '’'};

/// 括号统一；结构坏（`）` 先于 `（`）时返回 null，由调用方原样保留。
String? _unifyBrackets(String name) {
  final buffer = StringBuffer();
  for (final rune in name.runes) {
    final ch = String.fromCharCode(rune);
    if (_bracketMap.containsKey(ch)) {
      buffer.write(_bracketMap[ch]);
    } else if (_strayQuotes.contains(ch)) {
      continue;
    } else {
      buffer.write(ch);
    }
  }
  var s = buffer.toString();
  final firstOpen = s.indexOf('（');
  final firstClose = s.indexOf('）');
  if (firstClose != -1 && (firstOpen == -1 || firstClose < firstOpen)) {
    return null;
  }
  while ('（'.allMatches(s).length > '）'.allMatches(s).length) {
    s += '）';
  }
  var extraCloses = '）'.allMatches(s).length - '（'.allMatches(s).length;
  while (extraCloses > 0) {
    final idx = s.lastIndexOf('）');
    if (idx < 0) break;
    s = s.substring(0, idx) + s.substring(idx + 1);
    extraCloses -= 1;
  }
  return s;
}

List<String> _splitNotes(String note) => note
    .split(RegExp(r'[；;、,，]'))
    .map((segment) => segment.trim())
    .where((segment) => segment.isNotEmpty)
    .toList();

/// 主名开头的「同一片段重复两遍」收成一遍（2–8 字，先试短的）。
String _collapseRepeatedPrefix(String main) {
  for (var length = 2; length <= 8 && length * 2 <= main.length; length += 1) {
    final head = main.substring(0, length);
    if (main.startsWith(head, length)) {
      return head + main.substring(length * 2);
    }
  }
  return main;
}

String _trimPunctuation(String value) {
  const chars = ' 、，；,;';
  var start = 0;
  var end = value.length;
  while (start < end && chars.contains(value[start])) {
    start += 1;
  }
  while (end > start && chars.contains(value[end - 1])) {
    end -= 1;
  }
  return value.substring(start, end);
}
