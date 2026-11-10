// docs/66 §5.2.1：数字接地闸门的单元测试（纯函数）。
//
// 覆盖测试矩阵 §8.1 #18/#20：全部数值写入字段的接地策略、数字边界匹配
// （150 不误匹配 1500）、对象锚点邻近、weekday 语义别名、food.create
// 营养例外，以及「新增数值字段没有策略 ⇒ fail-closed」的注册表覆盖断言。
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_command.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_number_grounding.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_registry.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_turn.dart';

ChatEditCommand _command(String action, Map<String, Object> args) {
  final registry = ChatEditCommandRegistry();
  final spec = registry.specOf(action)!;
  return ChatEditCommand(spec: spec, args: args);
}

ChatEditTurn _turnOf(ChatEditCommand command) => ChatEditTurn(
  reply: 'r',
  rows: [ChatEditTurnItem(index: 0, raw: const {}, command: command)],
);

void main() {
  group('数字接地 · 覆盖面（fail-closed）', () {
    test('注册表全部数值/整数参数都有接地策略（或属于 food.create 营养例外）', () {
      const exempt = {
        'kcalPer100g',
        'proteinPer100g',
        'carbsPer100g',
        'fatPer100g',
      };
      final problems = <String>[];
      for (final spec in ChatEditCommandRegistry.defaultSpecs) {
        for (final arg in spec.args) {
          final isNumeric =
              arg.type == ChatEditArgType.number ||
              arg.type == ChatEditArgType.integer;
          if (!isNumeric) continue;
          if (spec.action == 'food.create' && exempt.contains(arg.name)) {
            continue;
          }
          // 用「值不在文本里」探测：没策略的字段会报「没有接地策略」；
          // 有策略的字段报「找不到依据」。两者都算被闸门覆盖。
          final problem = validateManualCardGrounding(
            _turnOf(_command(spec.action, {arg.name: 1})),
            userText: '无数字文本',
            assistantReply: '无数字文本',
          );
          if (problem == null) {
            problems.add('${spec.action}.${arg.name} 没有闸门拦住');
          } else if (problem.contains('没有接地策略')) {
            problems.add('${spec.action}.${arg.name} 缺少接地策略：$problem');
          }
        }
      }
      expect(problems, isEmpty, reason: problems.join('\n'));
    });

    test('嵌套载荷（items[].grams / plan days）也在闸门内', () {
      // items 克数无依据 → 拒绝
      final meal = _turnOf(
        _command('meal.create', {
          'slot': 'lunch',
          'items': [
            {'food': '米饭', 'grams': 150.0},
          ],
        }),
      );
      expect(
        validateManualCardGrounding(meal, userText: '吃米饭', assistantReply: '好'),
        isNotNull,
      );
      // 计划条目 sets 无依据 → 拒绝
      final plan = _turnOf(
        _command('workout.plan.create', {
          'name': '计划',
          'days': [
            {
              'weekday': 1,
              'entries': [
                {'exercise': '深蹲', 'sets': 5, 'reps': 5},
              ],
            },
          ],
        }),
      );
      expect(
        validateManualCardGrounding(
          plan,
          userText: '周一练深蹲',
          assistantReply: '好',
        ),
        isNotNull,
        reason: '周一给了 weekday 依据，但 sets=5 没有依据',
      );
    });
  });

  group('数字接地 · 数字边界', () {
    test('150 命中 150g / 150 克 / 150.0；不命中 1500', () {
      String? ok(String text) => validateManualCardGrounding(
        _turnOf(_command('water.add', {'amountMl': 150})),
        userText: text,
        assistantReply: '',
      );
      expect(ok('喝 150g 水'), isNull);
      expect(ok('喝 150 克水'), isNull);
      expect(ok('喝了 150.0 毫升'), isNull);
      expect(ok('一共 1500 克'), isNotNull);
      expect(ok('1150 毫升'), isNotNull);
    });

    test('小数与整数形态互认（52.5 / 52.50）', () {
      String? ok(num v, String text) => validateManualCardGrounding(
        _turnOf(_command('weight.log', {'weightKg': v})),
        userText: text,
        assistantReply: '',
      );
      expect(ok(52.5, '体重 52.5kg'), isNull);
      expect(ok(52.5, '体重 52.50kg'), isNull);
      expect(ok(53, '体重 53kg'), isNull);
      expect(ok(53, '体重 530kg'), isNotNull);
    });
  });

  group('数字接地 · 对象锚点', () {
    ChatEditTurn meal(String food, num grams) => _turnOf(
      _command('meal.create', {
        'slot': 'lunch',
        'items': [
          {'food': food, 'grams': grams},
        ],
      }),
    );

    test('数字挂在相关食材旁 → 通过', () {
      expect(
        validateManualCardGrounding(
          meal('米饭', 150),
          userText: '午餐吃了米饭 150g 和一点青菜',
          assistantReply: '好的',
        ),
        isNull,
      );
    });

    test('数字在原文出现 ⇒ 放行（对象配对交给卡片核对，2026-11-07 取舍）', () {
      // 【口径变更】原先这里断「数字挂在别的食物旁 ⇒ 拒绝」。真机两次反馈
      // 证明这条判定会误杀中文自然表述（「白米饭（熟）这一小碗约 150g」
      // 「豆腐+肉片+青菜的麻辣煲…估算 400g」），导致用户点了生成只拿到
      // 「有数值没法核对」。现在硬门只保证「数字不是编的」；对象是否配对
      // 由编辑卡逐行显示（食物名 + 克数）供用户核对。
      final problem = validateManualCardGrounding(
        meal('鸡胸肉', 150),
        userText: '米饭 150g，还想吃点别的',
        assistantReply: '鸡胸肉也不错',
      );
      expect(problem, isNull, reason: '150 出现在原文里，不是编造的数值');
    });

    test('数字在原文根本没出现 ⇒ 仍然拒绝（防造数硬门）', () {
      final problem = validateManualCardGrounding(
        meal('鸡胸肉', 327),
        userText: '米饭 150g，还想吃点别的',
        assistantReply: '鸡胸肉也不错',
      );
      expect(problem, isNotNull);
      expect(problem, contains('327'));
    });

    test('锚点是快照引用（不在原文）时退回全局范围匹配', () {
      final turn = _turnOf(
        _command('meal.create', {
          'slot': 'lunch',
          'items': [
            {'food': '[dish:d1]', 'grams': 300.0},
          ],
        }),
      );
      expect(
        validateManualCardGrounding(
          turn,
          userText: '那份菜 300 克',
          assistantReply: '',
        ),
        isNull,
      );
    });
  });

  group('数字接地 · 语义别名', () {
    test('weekday=1 由「周一」接地；纯数字 1 不算依据', () {
      ChatEditTurn plan(String text) => _turnOf(
        _command('plan.entry.add', {
          'planId': '[plan:p1]',
          'weekday': 1,
          'exercise': '深蹲',
          'sets': 3,
          'reps': 8,
        }),
      );
      // sets=3/reps=8 也要在文本里（本用例只验证 weekday 维度，数值一并列出）。
      expect(
        validateManualCardGrounding(
          plan('x'),
          userText: '周一加深蹲 3 组 8 次',
          assistantReply: '',
        ),
        isNull,
      );
      expect(
        validateManualCardGrounding(
          plan('x'),
          userText: '星期一加 3×8 深蹲',
          assistantReply: '',
        ),
        isNull,
      );
      expect(
        validateManualCardGrounding(
          plan('x'),
          userText: '周 1 加深蹲 3 组 8 次',
          assistantReply: '',
        ),
        isNull,
      );
      expect(
        validateManualCardGrounding(
          plan('x'),
          userText: '1 加深蹲 3 组 8 次',
          assistantReply: '',
        ),
        isNotNull,
        reason: '「1」不是明确的星期别名',
      );
    });
  });

  // 2026-11-07 真机实测（用户第二次反馈）：照片识别轮点生成被接地闸门拦下
  // ——回复是「白米饭（熟）这一小碗约 150g」这种中文自然表述，食物名与数字
  // 之间隔了 10+ 字，6 字窗口判失败、整卡拒绝。真实回复里还有大量营养数字
  // （112/480/175/650 kcal），不该影响"份量"的接地判定。
  group('数字接地 · 中文自然表述（真机 fixture）', () {
    const reply =
        '第一张：抹茶曲奇。自建食物库里正好有它：450 kcal/100g。'
        '看包装大小，这块大约 40g，约 180 kcal。和昨天加餐记的是同款，可以直接复用。'
        '第二张：麻辣豆腐肉片煲 + 白米饭 '
        '豆腐+肉片+青菜的麻辣煲，汤色偏红油，估算 400g 左右，'
        '按类似红油豆腐粉 112 kcal/100g（含肉片再略高一点）估，约 480 kcal '
        '白米饭（熟）这一小碗约 150g，116 kcal/100g，约 175 kcal '
        '这餐合计大约 650 kcal，加上曲奇全天余量还在减脂区间（1412 – 1560 kcal）内可控。';

    ChatEditTurn mealTurn(List<Map<String, Object>> items) =>
        _turnOf(_command('meal.create', {'slot': '午餐', 'items': items}));

    test('「食物名…约 150g」这种隔了十几个字的表述要能接地', () {
      expect(
        validateManualCardGrounding(
          mealTurn([
            {'food': '白米饭', 'grams': 150.0},
          ]),
          userText: '把这三张记上',
          assistantReply: reply,
        ),
        isNull,
        reason: '「白米饭（熟）这一小碗约 150g」是同一分句里的份量说明',
      );
    });

    test('一顿两样食物各自份量都能接地（400g + 150g）', () {
      expect(
        validateManualCardGrounding(
          mealTurn([
            {'food': '豆腐肉片煲', 'grams': 400.0},
            {'food': '白米饭', 'grams': 150.0},
          ]),
          userText: '',
          assistantReply: reply,
        ),
        isNull,
      );
    });

    test('三种食物（含曲奇 40g）一起也能接地', () {
      expect(
        validateManualCardGrounding(
          mealTurn([
            {'food': '抹茶曲奇', 'grams': 40.0},
            {'food': '豆腐肉片煲', 'grams': 400.0},
            {'food': '白米饭', 'grams': 150.0},
          ]),
          userText: '',
          assistantReply: reply,
        ),
        isNull,
      );
    });

    test('回复里根本没有这个数字 ⇒ 仍然拒绝（防造数不放松）', () {
      final problem = validateManualCardGrounding(
        mealTurn([
          {'food': '白米饭', 'grams': 275.0},
        ]),
        userText: '',
        assistantReply: reply,
      );
      expect(problem, isNotNull, reason: '275g 在回复里没出现过');
      // 失败提示要点名具体食物与数值（用户才知道怎么办）。
      expect(problem, contains('白米饭'));
      expect(problem, contains('275'));
    });

    test('数字只在原文以别的量级出现 ⇒ 拒绝（边界匹配不受大数影响）', () {
      // 1412 确实出现在「减脂区间（1412 – 1560 kcal）」里——按新口径
      // （只要数字在原文出现过就算接地）**会放行**；这里改用边界不匹配的
      // 场景守住硬门：1490 在原文里没有出现。
      final problem = validateManualCardGrounding(
        mealTurn([
          {'food': '白米饭', 'grams': 1490.0},
        ]),
        userText: '',
        assistantReply: reply,
      );
      expect(problem, isNotNull);
      expect(problem, contains('1490'));
    });

    test('大数不会被小数误匹配（150 不等于 1500）', () {
      final problem = validateManualCardGrounding(
        mealTurn([
          {'food': '白米饭', 'grams': 1500.0},
        ]),
        userText: '',
        assistantReply: reply,
      );
      expect(problem, isNotNull, reason: 'reply 里只有 150g，没有 1500');
    });
  });

  group('数字接地 · 菜品 confidence 默认元数据', () {
    ChatEditTurn nutrition({num? confidence, num protein = 12}) => _turnOf(
      _command('canteen.dish.nutrition', {
        'dishId': '[canteen-dish:d1]',
        'kcalPer100g': 180.0,
        'proteinPer100g': protein,
        'carbsPer100g': 8.0,
        'fatPer100g': 7.0,
        'confidence': ?confidence,
      }),
    );
    const reply = '这道菜每 100g：180 kcal，蛋白质 12g，碳水 8g，脂肪 7g。';

    test('省略与显式 confidence=0.5 等价，不要求原文写出默认元数据', () {
      for (final confidence in <num?>[null, 0.5]) {
        expect(
          validateManualCardGrounding(
            nutrition(confidence: confidence),
            userText: '分析这道菜',
            assistantReply: reply,
          ),
          isNull,
          reason: 'confidence=$confidence 只是既有缺省元数据，不是补营养值',
        );
      }
    });

    test('非默认 confidence 仍须接地；有明确数字时允许', () {
      expect(
        validateManualCardGrounding(
          nutrition(confidence: 0.8),
          userText: '分析这道菜',
          assistantReply: reply,
        ),
        contains('confidence'),
      );
      expect(
        validateManualCardGrounding(
          nutrition(confidence: 0.8),
          userText: '分析这道菜，置信度 0.8',
          assistantReply: reply,
        ),
        isNull,
      );
    });

    test('默认 confidence 不豁免营养数值和克数', () {
      expect(
        validateManualCardGrounding(
          nutrition(confidence: 0.5, protein: 13),
          userText: '分析这道菜',
          assistantReply: reply,
        ),
        contains('proteinPer100g'),
      );
      expect(
        validateManualCardGrounding(
          _turnOf(
            _command('meal.create', {
              'slot': 'lunch',
              'items': [
                {'food': '米饭', 'grams': 0.5},
              ],
            }),
          ),
          userText: '记米饭',
          assistantReply: '好',
        ),
        isNotNull,
      );
    });

    test('新增的可选数值字段即使值为 0.5 也必须有显式策略', () {
      final original = ChatEditCommandRegistry().specOf(
        'canteen.dish.nutrition',
      )!;
      final extended = ChatEditCommandSpec(
        action: original.action,
        title: original.title,
        danger: original.danger,
        args: [
          ...original.args,
          const ChatEditArgSpec(
            name: 'unreviewedScore',
            type: ChatEditArgType.number,
            required: false,
          ),
        ],
        summarize: original.summarize,
      );
      expect(
        validateManualCardGrounding(
          _turnOf(
            ChatEditCommand(
              spec: extended,
              args: {
                ...nutrition().rows.single.command!.args,
                'unreviewedScore': 0.5,
              },
            ),
          ),
          userText: '分析这道菜',
          assistantReply: reply,
        ),
        contains('没有接地策略'),
      );
    });
  });

  group('数字接地 · food.create 例外', () {
    test('每 100g 营养字段免接地；servingGrams 仍须接地', () {
      final turn = _turnOf(
        _command('food.create', {
          'name': '自制蛋糕',
          'kcalPer100g': 350,
          'proteinPer100g': 6,
          'carbsPer100g': 40,
          'fatPer100g': 18,
          'servingGrams': 100,
        }),
      );
      // 营养值不在文本里也放行；servingGrams=100 找不到 → 拒绝。
      expect(
        validateManualCardGrounding(
          turn,
          userText: '建一个自制蛋糕',
          assistantReply: '',
        ),
        isNotNull,
        reason: 'servingGrams=100 无依据',
      );
      final ok = validateManualCardGrounding(
        _turnOf(
          _command('food.create', {
            'name': '自制蛋糕',
            'kcalPer100g': 350,
            'proteinPer100g': 6,
            'carbsPer100g': 40,
            'fatPer100g': 18,
          }),
        ),
        userText: '建一个自制蛋糕',
        assistantReply: '',
      );
      expect(ok, isNull, reason: '每 100g 营养字段是唯一例外（编辑卡会完整显示）');
    });
  });
}
