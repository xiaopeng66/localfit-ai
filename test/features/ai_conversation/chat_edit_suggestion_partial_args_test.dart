import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_registry.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_turn.dart';

/// **「该弹卡却不弹」的真根因：合法信封被解析器拒收**（`ai-live` 实测抓到）。
///
/// 2026-10-24 用 `deepseek-v4.1-flash` 实测，模型对「把那条记录去掉」回了：
///
/// ```json
/// {"reply":"我这边没看到任何可删的记录…你想删的是哪一类？",
///  "edits":[],
///  "suggestions":[
///    {"label":"删除今日饮水记录","action":"water.delete","args":{}},
///    {"label":"删除一餐记录","action":"meal.delete","args":{}},
///    {"label":"删除菜品","action":"dish.delete","args":{}}]}
/// ```
///
/// 这**完全符合协议**（规则 1：「edits 不能是空数组（除非同时给了 suggestions）」；
/// 规则 0：「信息不全 → edits 空 + suggestions 候选」）。但 App 显示纯文本、
/// 不弹卡 —— 因为 `_parseSuggestions` 对每个建议跑
/// `validateChatEditArgs`，`meal.delete` 的必填参数（哪一餐）缺了就
/// `continue` **静默丢弃**；三条全丢 ⇒ `suggestions.isEmpty` ⇒
/// `edits.isEmpty && suggestions.isEmpty` ⇒ 整个信封被判 null ⇒ 降级纯文本。
///
/// 同一批实测里还有「把今天的午餐删了」给出
/// `{"action":"meal.create","args":{"slot":"lunch","items":[]}}`——`items` 是
/// 必填且不能为空，同样被丢。
///
/// **正确口径**：这类建议不是「坏建议」，而是**待补参数的可点入口**——
/// 用户的意图（删一餐 / 记一餐）是真实且正确的，只是还差目标。应当保留成
/// 可点按钮（点了再由 App 按既有流程补问），而不是把整段答复降级成散文。
void main() {
  final registry = ChatEditCommandRegistry();

  ChatEditTurn? parse(String json) => parseChatEditTurn(json, registry);

  group('参数不全的 suggestion 不能被静默丢弃', () {
    test('edits 空 + 三条「缺参数」建议 → 仍然是信封（卡要弹）', () {
      final turn = parse(
        jsonEncode({
          'reply': '你想删哪一类记录？',
          'edits': <Object>[],
          'suggestions': [
            {'label': '删除今日饮水记录', 'action': 'water.delete', 'args': {}},
            {'label': '删除一餐记录', 'action': 'meal.delete', 'args': {}},
            {'label': '删除菜品', 'action': 'dish.delete', 'args': {}},
          ],
        }),
      );
      expect(
        turn,
        isNotNull,
        reason:
            '这是**合法信封**（协议规则 1 明确允许 edits 空 + suggestions），'
            '解析器不得因「建议缺参数」把整段判成纯文本——那正是用户看到的'
            '「说了要改、卡片却不弹」。',
      );
      expect(
        turn!.suggestions,
        hasLength(3),
        reason: '三条建议都应保留成可点按钮（它们是待补参数的入口）',
      );
      expect(turn.suggestions.first.action, 'water.delete');
    });

    test('单个建议缺必填参数：保留，且标记为「待补信息」', () {
      final turn = parse(
        jsonEncode({
          'reply': '要记到哪一餐？',
          'edits': <Object>[],
          'suggestions': [
            {
              'label': '记录今天的午餐',
              'action': 'meal.create',
              'args': {'slot': 'lunch', 'items': <Object>[]},
            },
          ],
        }),
      );
      expect(turn, isNotNull);
      final suggestion = turn!.suggestions.single;
      expect(suggestion.label, '记录今天的午餐');
      expect(suggestion.action, 'meal.create');
      expect(
        suggestion.needsMoreInfo,
        isTrue,
        reason: '参数不全的建议要如实标记（UI 据此说「还差信息」，不假装能直接应用）',
      );
    });

    test('参数完整的建议仍可正常应用（needsMoreInfo = false）', () {
      final turn = parse(
        jsonEncode({
          'reply': '记一笔水',
          'edits': <Object>[],
          'suggestions': [
            {
              'label': '记录 250ml 水',
              'action': 'water.add',
              'args': {'amountMl': 250},
            },
          ],
        }),
      );
      expect(turn, isNotNull);
      final suggestion = turn!.suggestions.single;
      expect(suggestion.needsMoreInfo, isFalse);
      expect(suggestion.action, 'water.add');
    });

    test('未知 action 的建议仍然丢弃（幻觉不伪装成按钮）', () {
      final turn = parse(
        jsonEncode({
          'reply': '记一笔水',
          'edits': <Object>[],
          'suggestions': [
            {
              'label': '记录 250ml 水',
              'action': 'water.add',
              'args': {'amountMl': 250},
            },
            {'label': '不存在的命令', 'action': 'nope.doIt', 'args': {}},
          ],
        }),
      );
      expect(turn, isNotNull);
      expect(
        turn!.suggestions,
        hasLength(1),
        reason: '未注册 action 是模型幻觉，必须丢（不许给用户一个点不动的按钮）',
      );
    });

    test('省略 edits 键、只给 suggestions → 仍是信封（卡要弹）', () {
      // `ai-live` 实测的最后一条缺口（M27）：模型给出
      // `{"reply":"…","suggestions":[…]}` —— **没有 `edits` 键**。
      // `edits` 是可选的（协议规则 8 把它写成「可选字段 suggestions」的兄弟），
      // 但旧解析器 `if (edits is! List) return null` 要求它必须存在 ⇒ 整段
      // 被判纯文本 ⇒ 卡片不弹。这是真实用户会撞上的形态。
      final turn = parse(
        jsonEncode({
          'reply': '还没看到你说的那顿的记录，我可以帮你补记晚餐。',
          'suggestions': [
            {
              'label': '记晚餐：番茄炒蛋 250g',
              'action': 'meal.create',
              'args': {'slot': 'dinner', 'items': []},
            },
          ],
        }),
      );
      expect(
        turn,
        isNotNull,
        reason: '缺 `edits` 键是合法的（可以把 edits 当空数组）——不得因此不弹卡',
      );
      expect(turn!.rows, isEmpty);
      expect(turn.suggestions, hasLength(1));
    });

    test('`edits: null` 同样视为空（模型常见的显式 null）', () {
      final turn = parse(
        jsonEncode({
          'reply': '要记哪一餐？',
          'edits': null,
          'suggestions': [
            {'label': '记午餐', 'action': 'meal.create', 'args': {}},
          ],
        }),
      );
      expect(turn, isNotNull);
      expect(turn!.rows, isEmpty);
      expect(turn.suggestions, hasLength(1));
    });

    test('动作执行不了：空 edits + 空 suggestions + 说明 → 仍是信封（卡片要弹）', () {
      // 2026-10-24 用户：「不要给我模棱两可的答案，也不要推荐错误的答案」。
      // 规则 0 要求「动作执行不了也要给信封、但**不许偷换成别的命令**」——
      // 所以模型会回 `{"reply":"今天没有午餐可删。","edits":[]}`（两样都空）。
      // 旧解析器 `edits.isEmpty && suggestions.isEmpty → null` 把这种**正确的
      // 空信封**判成纯文本 ⇒ 卡片不弹、用户看不到「我查过了，确实没有」。
      // 判据：有**非空 reply** 就算合法信封（空气泡仍由 reply 为空挡掉）。
      final turn = parse(
        jsonEncode({'reply': '今天还没有任何餐记录，所以没有午餐可删。', 'edits': <Object>[]}),
      );
      expect(turn, isNotNull, reason: '空 edits 是「执行不了」的正确形态（规则 0），不得判纯文本');
      expect(turn!.rows, isEmpty);
      expect(turn.suggestions, isEmpty);
      expect(turn.reply, contains('没有午餐可删'));
    });

    test('reply 也空的空气泡仍然拒绝（不能给用户一张空卡）', () {
      expect(
        parse(jsonEncode({'reply': '', 'edits': <Object>[]})),
        isNull,
        reason: 'reply 空 + 没有 edits/建议 = 空气泡，必须拒绝',
      );
      expect(
        parse(jsonEncode({'reply': '   ', 'edits': <Object>[]})),
        isNull,
        reason: '纯空白 reply 同样是空气泡',
      );
    });

    test('有合法 edits + 缺参数建议 → 两样都在（互不影响）', () {
      final turn = parse(
        jsonEncode({
          'reply': '记了水，要不要再记一餐？',
          'edits': [
            {
              'action': 'water.add',
              'args': {'amountMl': 300},
            },
          ],
          'suggestions': [
            {'label': '记一餐', 'action': 'meal.create', 'args': {}},
          ],
        }),
      );
      expect(turn, isNotNull);
      expect(turn!.rows, hasLength(1));
      expect(turn.rows.single.command?.action, 'water.add');
      expect(turn.suggestions, hasLength(1));
      expect(turn.suggestions.single.needsMoreInfo, isTrue);
    });
  });
}
