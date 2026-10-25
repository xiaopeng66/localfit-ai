import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_command.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_registry.dart';

void main() {
  group('ChatEditCommandRegistry', () {
    final registry = ChatEditCommandRegistry();

    test('v1 注册表共 34 条命令，action 全部唯一', () {
      // 2026-10-04（docs/28 §6.4/§6.7）：33 → 23。退役 10 条 ——
      // recipe.create/update/delete、plan.create/update/delete、
      // pantry.set/clear、price.set、planning.preferences.set。
      // `constraints.set` **保留**（写 profiles.allergenAvoidancesJson，
      // 仍被 DailyPlanEngine 读取）。
      // 2026-10-12（docs/32 §4 T6b）：23 → 24，新增 `workout.plan.create`
      // （AI 创作「训练计划」卡走对话落库；旧任务管线的安全断言重钉到命令层）。
      // 2026-10-15（docs/34 §7，用户指示补全）：23 → 33，训练域 6 条
      // （session.start / set.log / session.finish / plan.entry.add /
      // plan.entry.remove / plan.rename）+ 自建食物与资料/目标 4 条
      // （food.update / food.delete / profile.body.update / targets.update）
      // 再加 1 条 `menu.snapshot.publish`（批次 B：结构化菜单草案 JSON →
      // 解码 → 发布快照，与文件导入同源）。
      // 2026-10-16（Round9 N3，用户实测「食堂菜品 AI 分析后目录里没有显示
      // 结果」）：34 → 35，新增 `canteen.dish.nutrition`——`recordNutrition`
      // 此前**零调用方**，分析结果从来没落库。
      // 2026-10-13（docs/32 §4 T8 / §3 D10）：24 → 23，「手动到达时长」
      // 那条纵切连命令一起退役（docs/32 原写「23→22」是把 T6b 之前的
      // 数字当了基数，以代码事实为准，见证据文件）。
      // 2026-10-17（docs/38 S11）：35 → 37，新增 `memory.remember` /
      // `memory.forget`（长期记忆：显式记住、如实忘掉）。
      expect(registry.specs, hasLength(37));
      final actions = registry.specs.map((spec) => spec.action).toList();
      expect(actions.toSet(), hasLength(actions.length));
    });

    test('每条 spec 都有标题、参数声明与摘要函数，且摘要能跑', () {
      for (final spec in registry.specs) {
        expect(spec.title, isNotEmpty, reason: '${spec.action} 缺标题');
        expect(
          spec.summarize(_sampleArgs(spec)),
          isA<String>(),
          reason: '${spec.action} 的 summarize 应能对合法参数出摘要',
        );
        for (final arg in spec.args) {
          expect(arg.name, isNotEmpty, reason: '${spec.action} 有无名参数');
        }
      }
    });

    test('renderProtocol 包含全部命令名与信封格式要点', () {
      final protocol = registry.renderProtocol();
      for (final spec in registry.specs) {
        expect(
          protocol,
          contains(spec.action),
          reason: '${spec.action} 未出现在协议里',
        );
      }
      expect(protocol, contains('reply'));
      expect(protocol, contains('edits'));
      // 上限必须按字面数字出现在协议里：P12 变异（10→11）暴露过
      // `contains('10')` 被参数提示里的「10000」等误匹配（假钉）。
      // 字面 10 与 docs/23 §1「上限 10 条/回复」互为对照，钉的是合同本身，
      // 不能引用 maxEditsPerReply 常量（实现改了断言跟着改＝没钉）。
      expect(protocol, contains('每次回复最多 10 条'));
      // 2026-10-15 真实 AI 测得（deepseek-v4.1-flash）：模型「先写中文说明、
      // 再贴一段 JSON」——旧文案只说「输出 JSON 信封」，没说**整段回复只能
      // 是那一个 JSON 对象**，于是 App 的严格解析（必须 `{` 开头 `}` 结尾）
      // 把它当纯文本丢弃、编辑卡不出现。这条钉住新文案。
      expect(
        protocol,
        contains('整段回复只放这一个 JSON 对象'),
        reason: '协议必须写明「回复里除该 JSON 外不得有其他文字」',
      );
      // 2026-10-16（用户：说「添加鸡肉食材」只得到文字、没有应用按钮）：
      // 协议必须写明**口语=命令**，否则模型只按命令名的字面匹配。
      expect(protocol, contains('口语就是命令'), reason: '协议要说明日常说法直接翻译成命令，不要只做文字回复');
      expect(protocol, contains('添加鸡肉食材'));
      // 2026-10-16（用户：缺食材时要给可点按钮）：缺库食材要建，而不是只回「没有」。
      expect(protocol, contains('不要只回「库里没有」'));
      // 新的推荐按钮通道（上限按字面 3 出现在协议里，防常量改动漂走）。
      expect(protocol, contains('suggestions'));
      expect(protocol, contains('1–3 个'));
      // 2026-10-16（用户：「涉及修改就必须正确识别指令，而不是空回文字」）：
      // 协议必须把「修改请求不许只回文字」写成硬规则。
      expect(
        protocol,
        contains('禁止只回一句文字'),
        reason: '协议要写明：修改请求必须给信封或 suggestions',
      );
      expect(protocol, contains('用户这条是修改请求'));
      // 2026-10-17（docs/38 S11）：快照新增「饮食偏好与忌口」与「长期记忆」
      // 两段。协议必须把「硬约束 + 与当前说法冲突时以当前为准」与
      // 「记忆只收软信息、结构化字段用对应命令」写成规则。
      expect(protocol, contains('饮食偏好与忌口是硬约束'));
      expect(protocol, contains('以用户当前说法为准'));
      expect(protocol, contains('长期记忆只收「软信息」'));
      // v1.1（2026-10-17）：forget 命中多条时引导用 suggestions 给候选，
      // 让用户点选而不是重复描述。
      expect(protocol, contains('用 suggestions 给出每条候选项'));
      expect(protocol, contains('memory.remember'));
      expect(protocol, contains('memory.forget'));
    });

    test('specOf：已注册返回 spec，未注册返回 null', () {
      expect(registry.specOf('weight.log')?.title, '记录体重');
      expect(registry.specOf('settings.apiKey.update'), isNull);
    });

    test('参数校验：缺必填报中文错误、未知参数报错、区间越界报错', () {
      final spec = registry.specOf('weight.log')!;

      expect(
        () => validateChatEditArgs(spec, {}),
        throwsA(
          isA<ChatEditArgsException>().having(
            (error) => error.message,
            'message',
            contains('weightKg'),
          ),
        ),
      );

      expect(
        () => validateChatEditArgs(spec, {'weightKg': 70.0, 'unknownKey': 'x'}),
        throwsA(isA<ChatEditArgsException>()),
      );

      expect(
        () => validateChatEditArgs(spec, {'weightKg': 20.0}),
        throwsA(
          isA<ChatEditArgsException>().having(
            (error) => error.message,
            'message',
            contains('35'),
          ),
        ),
      );
    });

    // T8（docs/32 §3 D10）：注册表里最后一条整数型参数命令已退役——现在
    // 没有任何命令带 `ChatEditArgType.integer` 参数，归一化/拒绝口径改在
    // `number` 参数（water.add）上钉。
    test('数字归一化：整数写法接受、布尔不冒充数字、Infinity 拒绝', () {
      final water = registry.specOf('water.add')!;
      final args = validateChatEditArgs(water, {'amountMl': 250.0});
      expect(args['amountMl'], 250);

      expect(
        () => validateChatEditArgs(water, {'amountMl': true}),
        throwsA(isA<ChatEditArgsException>()),
      );
      expect(
        () => validateChatEditArgs(water, {'amountMl': double.infinity}),
        throwsA(isA<ChatEditArgsException>()),
      );
    });

    test('餐次宽容解析：中文与英文都认，乱写的报错', () {
      final meal = registry.specOf('meal.update')!;
      expect(
        validateChatEditArgs(meal, {'mealId': 'm1', 'slot': '早饭'})['slot'],
        'breakfast',
      );
      expect(
        () => validateChatEditArgs(meal, {'mealId': 'm1', 'slot': '夜宵'}),
        throwsA(isA<ChatEditArgsException>()),
      );
    });

    test('foodItems：缺 food/克数越界的用料报错', () {
      final meal = registry.specOf('meal.create')!;
      expect(
        () => validateChatEditArgs(meal, {
          'slot': '早餐',
          'items': [
            {'grams': 50.0},
          ],
        }),
        throwsA(
          isA<ChatEditArgsException>().having(
            (error) => error.message,
            'message',
            contains('食物名'),
          ),
        ),
      );
      expect(
        () => validateChatEditArgs(meal, {
          'slot': '早餐',
          'items': [
            {'food': '鸡蛋', 'grams': 9000},
          ],
        }),
        throwsA(isA<ChatEditArgsException>()),
      );
    });
  });
}

/// 给 summarize 冒烟用的最小合法参数（只保证不抛，不求语义正确）。
Map<String, Object> _sampleArgs(ChatEditCommandSpec spec) {
  final args = <String, Object>{};
  for (final arg in spec.args) {
    if (!arg.required) continue;
    args[arg.name] = switch (arg.type) {
      ChatEditArgType.string => '样本',
      ChatEditArgType.number => (arg.min ?? 1).toDouble(),
      ChatEditArgType.integer => (arg.min ?? 1).toInt(),
      ChatEditArgType.boolean => true,
      ChatEditArgType.stringList => <String>['素食'],
      ChatEditArgType.foodItems => <Object>[
        {'food': '米饭', 'grams': 100.0},
      ],
      ChatEditArgType.planDays => <Object>[
        {
          'weekday': 1,
          'entries': [
            {'exercise': '深蹲', 'sets': 3, 'reps': 10},
          ],
        },
      ],
      ChatEditArgType.mealSlot => 'breakfast',
      ChatEditArgType.localDate => '2026-10-02',
      ChatEditArgType.goal => 'loseFat',
      ChatEditArgType.time => '08:00',
    };
  }
  return args;
}
