import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_command.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_registry.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_turn.dart';

/// 把「模型只回了散文、但内容已经是一份可执行的记餐提案」抢救成编辑卡。
///
/// 【为什么需要】2026-11-03 用户实机：拍照后模型回
/// 「我准备把这份记为今天的午餐：红油豆腐粉（豆腐+金针菇+粉条）400g、
/// 白米饭（熟）150g…点「应用」后生效」——信息完整、结构清楚，但它就是不
/// 输出 JSON 信封。自动催两次仍回同样的散文，最后只能给兜底卡。
/// 对视觉模型（或小参模型）来说，「看懂了图」与「按协议输出 JSON」是两件
/// 事；前者已经做到时，再把后者失败直接判成「没有可应用的操作」太亏。
///
/// 这里只做**极保守**的解析：必须同时满足
/// 1. 回复在讲「应用」（提案口吻，而不是普通聊天）；
/// 2. 能唯一确定餐次（早餐/午餐/晚餐/加餐，出现两个就放弃）；
/// 3. 「：」后面是一串 `食物 数字 g` 条目，且每个条目都能解析。
/// 任何一条不满足就返回 null，仍走原来的「纯文本 + 兜底卡」路径。
///
/// 解析出来的是一张**待用户点「应用」的卡**，不是直接写库；食物名在库里
/// 不存在时，既有执行器会给出「创建食材」修复按钮——不静默编营养值。
ChatEditTurn? parseProseMealProposal(
  String rawOutput,
  ChatEditCommandRegistry registry,
) {
  final text = rawOutput.trim();
  if (text.isEmpty || text.startsWith('{')) return null;
  // 必须是提案口吻：用户实机里模型写的是「点「应用」后生效」。
  if (!text.contains('应用')) return null;
  if (!RegExp(r'记(为|成|到|一下|一笔|录)').hasMatch(text) && !text.contains('记录')) {
    return null;
  }

  final slot = _parseSlot(text);
  if (slot == null) return null;

  final colon = text.indexOf(RegExp(r'[：:]'));
  if (colon < 0) return null;
  var itemsPart = text.substring(colon + 1);
  for (final cut in const ['点「应用」', '点“应用”', '点应用', '应用后', '。']) {
    final index = itemsPart.indexOf(cut);
    if (index >= 0) itemsPart = itemsPart.substring(0, index);
  }
  // 「，份量按…」是估算说明，不是食物条目。
  for (final cut in const ['，份量', ',份量', '，按', ',按']) {
    final index = itemsPart.indexOf(cut);
    if (index >= 0) itemsPart = itemsPart.substring(0, index);
  }
  itemsPart = itemsPart.trim();
  if (itemsPart.isEmpty) return null;

  final tokens = itemsPart
      .split(RegExp(r'[、，,；;]'))
      .map((token) => token.trim())
      .where((token) => token.isNotEmpty)
      .toList();
  if (tokens.isEmpty || tokens.length > 10) return null;

  final items = <Map<String, Object>>[];
  for (final token in tokens) {
    final item = _parseItem(token);
    if (item == null) return null; // 有一条读不懂就整体放弃，不猜。
    items.add(item);
  }
  if (items.isEmpty) return null;

  final spec = registry.specOf('meal.create');
  if (spec == null) return null;
  final rawArgs = <String, Object>{'slot': slot, 'items': items};
  final Map<String, Object> args;
  try {
    args = validateChatEditArgs(spec, rawArgs);
  } on ChatEditArgsException {
    return null;
  }
  return ChatEditTurn(
    reply: text,
    rows: [
      ChatEditTurnItem(
        index: 0,
        raw: {'action': 'meal.create', 'args': rawArgs},
        command: ChatEditCommand(spec: spec, args: args),
      ),
    ],
  );
}

/// 唯一餐次；出现两个及以上就返回 null（「早餐和午餐」不该硬塞进一餐）。
String? _parseSlot(String text) {
  final hits = <String>{};
  if (text.contains('早餐') || text.contains('早饭')) hits.add('breakfast');
  if (text.contains('午餐') || text.contains('午饭') || text.contains('中饭')) {
    hits.add('lunch');
  }
  if (text.contains('晚餐') || text.contains('晚饭')) hits.add('dinner');
  if (text.contains('加餐') ||
      text.contains('夜宵') ||
      text.contains('零食') ||
      text.contains('下午茶')) {
    hits.add('snack');
  }
  return hits.length == 1 ? hits.single : null;
}

/// 解析 `食物名（说明）400g` / `食物名 400 克` / `豆浆300ml`。
///
/// 括号里如果是「熟」「大碗」这类**短修饰**，保留进食物名（库里常见
/// 「白米饭（熟）」）；如果是「豆腐+金针菇+粉条」这类配料清单，则只取
/// 括号前的菜名（库里的菜名不会把配料全写进去）。
Map<String, Object>? _parseItem(String token) {
  final match = RegExp(
    r'^(.+?)\s*(?:[（(]([^）)]*)[）)])?\s*(\d+(?:\.\d+)?)\s*(?:g|克|ml|毫升)$',
    caseSensitive: false,
  ).firstMatch(token);
  if (match == null) return null;
  var name = match.group(1)!.trim();
  final note = match.group(2)?.trim();
  final grams = double.tryParse(match.group(3)!);
  if (grams == null || grams <= 0 || grams > 5000) return null;
  if (note != null &&
      note.isNotEmpty &&
      note.length <= 4 &&
      !note.contains(RegExp(r'[+、,，]'))) {
    name = '$name（$note）';
  }
  name = name.replaceFirst(RegExp(r'^(还有|以及|一份|一碗|半份|大约|约)'), '').trim();
  if (name.isEmpty) return null;
  return {'food': name, 'grams': grams};
}
