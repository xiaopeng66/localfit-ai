import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_registry.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_repair.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_turn.dart';

void main() {
  final registry = ChatEditCommandRegistry();

  const envelope =
      '{"reply":"好的，我来帮你记录。","edits":['
      '{"action":"water.add","args":{"amountMl":250}},'
      '{"action":"weight.log","args":{"weightKg":72.5,"localDate":"2026-10-01"}}'
      ']}';

  group('parseChatEditTurn', () {
    test('合法信封：逐条命令被校验归一化，顺序与下标保持', () {
      final turn = parseChatEditTurn(envelope, registry);
      expect(turn, isNotNull);
      expect(turn!.reply, '好的，我来帮你记录。');
      expect(turn.rows, hasLength(2));
      expect(turn.rows[0].command?.action, 'water.add');
      expect(turn.rows[0].command!.args['amountMl'], 250.0);
      expect(turn.rows[1].command?.action, 'weight.log');
      expect(turn.rows[1].command!.args['localDate'], '2026-10-01');
      expect(
        turn.rows.every((row) => row.status == ChatEditRowStatus.proposed),
        isTrue,
      );
      expect(turn.hasProposed, isTrue);
    });

    // 【语义变更，不是删断言换绿】2026-10-24（`ai-live` 实测修「卡片不弹」）：
    // 末条「散文前缀 + 空 edits 信封」原判 null，现在**抢救成空信封**。规则 0 要求
    // 「动作执行不了也要给信封」，模型因此会回 `{"reply":"今天没有午餐可删。","edits":[]}`
    // ——判 null 就等于把这句「我查过、确实没有」吞掉，用户以为点了没反应。
    test('纯文本与坏 JSON 一律返回 null（当闲聊处理）', () {
      expect(parseChatEditTurn('今天多喝水哦。', registry), isNull);
      expect(parseChatEditTurn('{"reply": 坏掉的 json', registry), isNull);
      expect(parseChatEditTurn('[1,2,3]', registry), isNull);
      final emptyEnvelope = parseChatEditTurn(
        '前缀 {"reply":"x","edits":[]}',
        registry,
      );
      expect(
        emptyEnvelope,
        isNotNull,
        reason: '散文 + 完整空信封 → 抢救成空信封（语义变更：原先判 null）',
      );
      expect(emptyEnvelope!.rows, isEmpty);
      expect(emptyEnvelope.reply, 'x');
    });

    test('散文在前、信封在后：**抢救**出那一个信封（真实模型最常见的那种）', () {
      // 2026-10-16 用户授权后的真模型实测（供应商 ai.furry.vg /
      // `deepseek-ai/deepseek-v4.1-flash`）：控制矩阵 ⑩⑭⑮ 三条全部栽在
      // 「先用中文说一句，再贴 JSON」上——信封本身完全合法，只是前面多了一句
      // 白话。协议里已经写了「整段回复只放这一个 JSON 对象」，模型仍然会犯；
      // App 侧原来只有「催一次重跑」（售后补救，本模型实测也不稳定）。
      //
      // 这里补的是**解析侧兜底**：整段解析仍是第一路径；失败时才在文本里找
      // **恰好一个**能解析成合法信封的 JSON 对象。找不到、或有歧义（多于一个
      // 都能解析）都仍然返回 null —— 宁可当闲聊，也不猜。
      const proseThenEnvelope =
          '你的自由训练已经准备好了。  {"reply":"好的，现在为你开始一次自由训练。",'
          '"edits":[{"action":"session.start","args":{}}]}';
      final turn = parseChatEditTurn(proseThenEnvelope, registry);
      expect(turn, isNotNull, reason: '散文 + 合法信封必须能被抢救出来');
      expect(turn!.reply, '好的，现在为你开始一次自由训练。');
      expect(turn.rows.single.command?.action, 'session.start');
    });

    test('围栏代码块里的信封也能抢救（模型爱包 ```json）', () {
      const fenced =
          '当然可以，下面是修改：\n```json\n'
          '{"reply":"已备好修改。","edits":[{"action":"water.add","args":{"amountMl":300}}]}'
          '\n```';
      final turn = parseChatEditTurn(fenced, registry);
      expect(turn, isNotNull);
      expect(turn!.rows.single.command?.action, 'water.add');
    });

    test('抢救的边界：两个信封（歧义）/ 只有花括号的闲聊 都仍是 null', () {
      const twoEnvelopes =
          '先这样：{"reply":"A","edits":[{"action":"water.add","args":{"amountMl":100}}]}'
          ' 或者那样：{"reply":"B","edits":[{"action":"water.add","args":{"amountMl":200}}]}';
      expect(
        parseChatEditTurn(twoEnvelopes, registry),
        isNull,
        reason: '两个都能解析 ⇒ 有歧义，不许替用户选一个',
      );
      expect(parseChatEditTurn('在 JSON 里写 {} 表示空对象，就是这样。', registry), isNull);
      expect(parseChatEditTurn('这是一段普通回复，没有任何信封。', registry), isNull);
      // 【语义变更，不是删断言换绿】2026-10-24：`edits` 改**可选**（模型常给
      // `{"reply":"…","suggestions":[…]}` 或 `{"reply":"…","edits":null}`），
      // 所以「缺 edits」不再等于「结构不合格」——只要 reply 非空就是合法的空信封。
      // 真正仍然作废的是 reply 缺失/非字符串（见下一条测试）。
      expect(
        parseChatEditTurn('{"reply":"缺 edits"}', registry),
        isNotNull,
        reason: 'edits 可选（语义变更：原先当结构错误判 null）',
      );
    });

    // 【语义变更，不是删断言换绿】2026-10-24：`edits` 由「必须是 List」改为
    // 「可选、可为 null；给了就必须是 List」。缺 reply 仍然整包作废（没有话可说
    // 就没有卡片），`edits` 类型错也仍然整包作废（那是真坏 JSON）。
    // 空 `edits` 单独存在现在是**合法空信封**——规则 0 要求「执行不了也要给信封」。
    test('缺 reply / edits 非 List → null；edits 缺省或为空 → 合法空信封', () {
      expect(
        parseChatEditTurn(
          '{"edits":[{"action":"water.add","args":{}}]}',
          registry,
        ),
        isNull,
        reason: '没有 reply 就没有能给用户看的话',
      );
      expect(
        parseChatEditTurn('{"reply":"x","edits":"water.add"}', registry),
        isNull,
        reason: 'edits 类型不对仍然是坏结构',
      );
      final empty = parseChatEditTurn('{"reply":"x","edits":[]}', registry);
      expect(empty, isNotNull, reason: '语义变更：原先判 null');
      expect(empty!.rows, isEmpty);
      final missing = parseChatEditTurn('{"reply":"x"}', registry);
      expect(missing, isNotNull, reason: '语义变更：edits 缺省视为空');
      expect(missing!.rows, isEmpty);
    });

    test('超过 10 条 edits → 整包拒绝（docs/23 §1 防一次写一大片）', () {
      final edits = List.generate(
        11,
        (index) => '{"action":"water.add","args":{"amountMl":100}}',
      ).join(',');
      expect(
        parseChatEditTurn('{"reply":"x","edits":[$edits]}', registry),
        isNull,
      );
      final ten = List.generate(
        10,
        (index) => '{"action":"water.add","args":{"amountMl":100}}',
      ).join(',');
      expect(
        parseChatEditTurn('{"reply":"x","edits":[$ten]}', registry),
        isNotNull,
      );
    });

    test('未知 action 只废那一条，其余照常成卡', () {
      final turn = parseChatEditTurn(
        '{"reply":"x","edits":['
        '{"action":"settings.apiKey.update","args":{"key":"x"}},'
        '{"action":"water.add","args":{"amountMl":100}}'
        ']}',
        registry,
      );
      expect(turn, isNotNull);
      expect(turn!.rows[0].command, isNull);
      expect(turn.rows[0].status, ChatEditRowStatus.failed);
      expect(turn.rows[0].decodeError, contains('不支持的修改类型'));
      expect(turn.rows[1].command, isNotNull);
    });

    test('参数坏（缺必填/类型不对）→ 该行 failed 带人话原因', () {
      final turn = parseChatEditTurn(
        '{"reply":"x","edits":['
        '{"action":"weight.log","args":{"weightKg":"很重"}},'
        '{"action":"weight.log","args":{}}'
        ']}',
        registry,
      );
      expect(turn, isNotNull);
      expect(turn!.rows[0].status, ChatEditRowStatus.failed);
      expect(turn.rows[0].decodeError, contains('weightKg'));
      expect(turn.rows[1].status, ChatEditRowStatus.failed);
    });

    test('edit 不是 Map → failed，不抛异常', () {
      final turn = parseChatEditTurn(
        '{"reply":"x","edits":["water.add"]}',
        registry,
      );
      expect(turn, isNotNull);
      expect(turn!.rows.single.status, ChatEditRowStatus.failed);
    });
  });

  group('encodeChatEditTurn（落库回环）', () {
    test('编码后重新解析能还原 reply、提议与结果状态', () {
      final turn = parseChatEditTurn(envelope, registry)!;
      final applied = ChatEditTurn(
        reply: turn.reply,
        rows: [
          turn.rows[0].copyWith(
            status: ChatEditRowStatus.applied,
            resultMessage: '饮水已记录。',
          ),
          turn.rows[1].copyWith(
            status: ChatEditRowStatus.failed,
            resultMessage: '请先完成本地建档。',
          ),
        ],
      );
      final encoded = encodeChatEditTurn(applied);
      final restored = parseChatEditTurn(encoded, registry)!;
      expect(restored.reply, turn.reply);
      expect(restored.rows[0].status, ChatEditRowStatus.applied);
      expect(restored.rows[0].resultMessage, '饮水已记录。');
      expect(restored.rows[1].status, ChatEditRowStatus.failed);
      expect(restored.rows[1].resultMessage, '请先完成本地建档。');
      // 原始提议不能丢：重放/审计要看得见模型当时提了什么。
      expect((jsonDecode(encoded) as Map)['edits'], hasLength(2));
    });

    test('proposed 状态不写 outcomes（下次打开仍是待应用）', () {
      final turn = parseChatEditTurn(envelope, registry)!;
      final encoded = encodeChatEditTurn(turn);
      expect(jsonDecode(encoded), isNot(contains('outcomes')));
      final restored = parseChatEditTurn(encoded, registry)!;
      expect(restored.hasProposed, isTrue);
    });

    test('dismissed 行不进 outcomes（不占结果位）', () {
      final turn = parseChatEditTurn(envelope, registry)!;
      final encoded = encodeChatEditTurn(
        ChatEditTurn(
          reply: turn.reply,
          rows: [
            turn.rows[0].copyWith(status: ChatEditRowStatus.dismissed),
            turn.rows[1],
          ],
        ),
      );
      final outcomes = (jsonDecode(encoded) as Map)['outcomes'];
      expect(outcomes, isNull);
    });
  });

  // 2026-10-16（用户：「对话中遇到问题要推荐回答并弹出可点选按钮」）：
  // 信封新增**可选** `suggestions` 通道——一组「下一步能做」的按钮，
  // 点了就等于应用那条命令。旧信封（没有这个键）行为完全不变。
  group('suggestions（推荐按钮）', () {
    const createFoodArgs =
        '{"name":"鸡肉","kcalPer100g":165,"proteinPer100g":31,'
        '"carbsPer100g":0,"fatPer100g":3.6}';

    test('解析 suggestions：label + 已校验命令；缺省为空列表', () {
      final withSuggestions = parseChatEditTurn(
        '{"reply":"库里没有鸡肉，我可以先建它。","edits":['
        '{"action":"water.add","args":{"amountMl":250}}],'
        '"suggestions":[{"label":"创建食材「鸡肉」","action":"food.create",'
        '"args":$createFoodArgs}]}',
        registry,
      )!;
      expect(withSuggestions.suggestions, hasLength(1));
      final suggestion = withSuggestions.suggestions.single;
      expect(suggestion.label, '创建食材「鸡肉」');
      expect(suggestion.effectiveAction, 'food.create');
      expect(suggestion.command?.args['name'], '鸡肉');
      expect(suggestion.command?.args['kcalPer100g'], 165.0);
      expect(suggestion.status, ChatEditRowStatus.proposed);

      final plain = parseChatEditTurn(envelope, registry)!;
      expect(plain.suggestions, isEmpty);
    });

    // 【语义变更，不是删断言换绿】2026-10-24（`ai-live` 实测修「卡片不弹」）：
    // **参数不全 / 越界**的建议从「静默丢弃」改为「保留成待补信息的可点按钮」
    // （`needsMoreInfo`）。理由：模型在「库里没这条 / 信息不全」时会给
    // `{"action":"meal.delete","args":{}}`——意图正确、目标待补；旧实现把它
    // 丢掉 ⇒ suggestions 变空 ⇒ 整段信封判无效 ⇒ 用户看到「说了要改、卡片不弹」。
    //
    // 仍然必须丢的是**真幻觉**与**无标签**：未知 action（点不动）与空 label
    // （按钮没有字）。这两条判据一个字没放宽。
    test('坏建议只丢自己：未知 action / 空 label 仍丢；参数不全改为「待补信息」保留', () {
      final turn = parseChatEditTurn(
        '{"reply":"x","edits":[{"action":"water.add","args":{"amountMl":250}}],'
        '"suggestions":['
        '{"label":"假的命令","action":"settings.apiKey.update","args":{}},'
        '{"label":"  ","action":"water.add","args":{"amountMl":250}},'
        '{"label":"参数不对","action":"water.add","args":{"amountMl":0}},'
        '{"label":"对的","action":"water.add","args":{"amountMl":300}}'
        ']}',
        registry,
      )!;
      // 未知 action + 空 label 被丢；两条 water.add（一条越界、一条合法）都留。
      expect(turn.suggestions, hasLength(2));
      expect(turn.suggestions.map((s) => s.label), [
        '参数不对',
        '对的',
      ], reason: '未知 action 与空 label 必须丢（真幻觉 / 无字按钮）');
      expect(
        turn.suggestions.first.needsMoreInfo,
        isTrue,
        reason: '参数越界的建议保留但标「待补信息」（点了先补问，不假装能直接应用）',
      );
      expect(
        turn.suggestions.last.needsMoreInfo,
        isFalse,
        reason: '参数合法的建议照常可直接应用',
      );
    });

    test('建议最多 3 条（多出的丢弃，不报错）', () {
      final items = [
        for (var i = 1; i <= 5; i++)
          '{"label":"第 $i 条","action":"water.add","args":{"amountMl":${100 * i}}}',
      ].join(',');
      final turn = parseChatEditTurn(
        '{"reply":"x","edits":[{"action":"water.add","args":{"amountMl":250}}],'
        '"suggestions":[$items]}',
        registry,
      )!;
      expect(turn.suggestions, hasLength(3));
      expect(turn.suggestions.map((s) => s.label), ['第 1 条', '第 2 条', '第 3 条']);
    });

    test('只有 suggestions、没有 edits：合法（只有按钮，不写库）', () {
      final turn = parseChatEditTurn(
        '{"reply":"你想先记录哪一餐？","edits":[],"suggestions":['
        '{"label":"记一笔水","action":"water.add","args":{"amountMl":250}}]}',
        registry,
      )!;
      expect(turn.rows, isEmpty);
      expect(turn.suggestions, hasLength(1));
      expect(turn.hasProposed, isFalse);
    });

    // 【语义变更，不是删断言换绿】2026-10-24：空 edits + 空 suggestions **不再**
    // 判 null（前提是 reply 非空）。这是规则 0 的「执行不了也要给信封」：
    // `{"reply":"今天没有午餐可删。","edits":[]}` 必须上屏成一张卡，而不是被吞成
    // 纯文本。唯一仍拒的是**空气泡**：reply 空白且两样都空（见 `_parseEnvelopeText`）。
    test('edits 与 suggestions 都空 + reply 非空 → 空信封；reply 也空才是 null', () {
      final emptyBoth = parseChatEditTurn(
        '{"reply":"今天没有午餐可删。","edits":[],"suggestions":[]}',
        registry,
      );
      expect(emptyBoth, isNotNull, reason: '语义变更：原先判 null');
      expect(emptyBoth!.rows, isEmpty);
      expect(emptyBoth.suggestions, isEmpty);
      expect(emptyBoth.reply, '今天没有午餐可删。');

      final noEdits = parseChatEditTurn('{"reply":"x","edits":[]}', registry);
      expect(noEdits, isNotNull, reason: '语义变更：原先判 null');
      expect(noEdits!.rows, isEmpty);

      // 空气泡仍然拒：没有话、没有动作、没有按钮。
      expect(
        parseChatEditTurn('{"reply":"","edits":[],"suggestions":[]}', registry),
        isNull,
      );
      expect(parseChatEditTurn('{"reply":"   ","edits":[]}', registry), isNull);
    });

    // 2026-10-16：修复建议从「只有缺食材」扩到缺动作/地点/窗口（用户要求
    // 「1、2 都要」——2 就是兜底覆盖更多缺实体）。
    test('修复建议覆盖四类缺实体，且都带得回按钮文案', () {
      const repairs = [
        ChatEditRepair.createFood(name: '鸡肉'),
        ChatEditRepair.createExercise(name: '农夫行走'),
        ChatEditRepair.createVenue(name: '三食堂'),
        ChatEditRepair.createWindow(name: '四号窗口', venueId: 'venue-1'),
      ];
      expect(repairs[0].label, '创建食材「鸡肉」');
      expect(repairs[1].label, '新建动作「农夫行走」');
      expect(repairs[2].label, '新建地点「三食堂」');
      expect(repairs[3].label, '新建窗口「四号窗口」');
      expect(repairs[3].venueId, 'venue-1');
      expect(repairs[0].venueId, isNull);
    });

    test('往返：四类修复建议都能落库回环（含 window 的 venueId）', () {
      final turn = parseChatEditTurn(
        '{"reply":"x","edits":[{"action":"water.add","args":{"amountMl":250}}]}',
        registry,
      )!;
      final withRepairs = ChatEditTurn(
        reply: turn.reply,
        rows: [
          turn.rows.single.copyWith(
            status: ChatEditRowStatus.failed,
            resultMessage: '失败了。',
            repair: const ChatEditRepair.createWindow(
              name: '四号窗口',
              venueId: 'venue-9',
            ),
          ),
        ],
      );
      final restored = parseChatEditTurn(
        encodeChatEditTurn(withRepairs),
        registry,
      )!;
      final repair = restored.rows.single.repair!;
      expect(repair.kind, ChatEditRepairKind.createWindow);
      expect(repair.name, '四号窗口');
      expect(repair.venueId, 'venue-9');
    });

    test('往返：suggestions 与行级「修复建议」都能落库回环', () {
      final turn = parseChatEditTurn(
        '{"reply":"鸡肉不在库里。","edits":['
        '{"action":"meal.create","args":{"slot":"breakfast","items":['
        '{"food":"鸡肉","grams":100}]}}],'
        '"suggestions":[{"label":"记一笔水","action":"water.add",'
        '"args":{"amountMl":250}}]}',
        registry,
      )!;
      final repaired = ChatEditTurn(
        reply: turn.reply,
        rows: [
          turn.rows.single.copyWith(
            status: ChatEditRowStatus.failed,
            resultMessage: '找不到食材「鸡肉」。',
            repair: const ChatEditRepair.createFood(name: '鸡肉'),
          ),
        ],
        suggestions: [
          turn.suggestions.single,
          turn.suggestions.single.copyWith(
            status: ChatEditRowStatus.applied,
            resultMessage: '饮水已记录。',
          ),
        ],
      );
      final restored = parseChatEditTurn(
        encodeChatEditTurn(repaired),
        registry,
      )!;
      expect(restored.suggestions[0].label, '记一笔水');
      expect(restored.suggestions[0].effectiveAction!, 'water.add');
      // 点过的按钮重启后仍是「已应用」——否则同一个按钮能重复写第二条。
      expect(restored.suggestions[1].status, ChatEditRowStatus.applied);
      expect(restored.suggestions[1].resultMessage, '饮水已记录。');
      expect(restored.rows.single.repair?.name, '鸡肉');
      expect(restored.rows.single.status, ChatEditRowStatus.failed);
    });
  });
}
