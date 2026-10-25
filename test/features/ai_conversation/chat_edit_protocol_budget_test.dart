import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_registry.dart';

/// **编辑卡「不弹卡」的结构性根因（`ai-live` 实测 + 提示词预算）。**
///
/// 2026-10-24 用 `deepseek-v4.1-flash` 实测 27 条自然语言：**81.5%（22/27）**
/// 第一趟拿到信封。失败的 4 条共同点不是「模型听不懂」，而是**它退回了散文**：
/// - 「把今天的午餐删了」→ 回「没有午餐可删」
/// - 「把那条记录去掉」→ 回「看不出你指哪一条」
/// - 「晚上不吃碳水」→ 回「这是原则还是具体一餐？」
/// - 「刚才那顿算晚餐」→ 回「你还没记录这顿晚餐吃了什么」
///
/// 全部**违反协议规则 5**（「修改请求禁止只回一句文字……真缺信息时也要给信封：
/// edits 可以空、用 suggestions 给可点候选」）。
///
/// 为什么规则写了还是不遵守 —— 实测的**结构性原因**是提示词太长：
///
/// | 量 | 实测 |
/// |---|---|
/// | `renderProtocol()` 长度 | **6,596 字** |
/// | 规则 5 在其中的位置 | **第 4,159 字（63% 处）** |
///
/// 小参数模型对长指令**中段**的依从性显著下降（「lost in the middle」）。
/// 规则 1（信封格式）在最前、规则 12 在最后，都被遵守；夹在中间的三条
/// 「必须给信封」被稀释。
///
/// 本文件把「别再把关键规则埋在 63% 处」变成可测判据：
/// 1. 协议**开头**（前 1,200 字内）必须出现「只回文字不行 / 缺信息也要给信封」
///    这条硬约束；
/// 2. 单条命令的说明里，**缺信息时的兜底**（给 suggestions 而不是只回文字）
///    必须在协议前半段出现；
/// 3. 协议总长不得超过预算（防止以后又加规则把它撑长）。
void main() {
  final proto = ChatEditCommandRegistry().renderProtocol();

  group('提示词预算与关键规则的可见位置', () {
    test('协议开头 1200 字内必须写明「缺信息也要给信封」', () {
      final head = proto.length <= 1200 ? proto : proto.substring(0, 1200);
      final mentionsEnvelopeFallback =
          (head.contains('缺') || head.contains('信息不全')) &&
          (head.contains('suggestions') || head.contains('信封'));
      expect(
        mentionsEnvelopeFallback,
        isTrue,
        reason:
            '协议的**前 1200 字**里必须交代「信息不全时也要给信封 + suggestions」。'
            '实测 `deepseek-v4.1-flash` 在 27 条自然语言里有 4 条退回散文，'
            '全部违反这条规则——而规则原文写在 63% 处（第 4159 字）。'
            '开头 1200 字现状：${proto.length <= 1200 ? proto : proto.substring(0, 1200)}',
      );
    });

    test('「必须给信封」的硬约束位于协议前半段（≤25%）', () {
      // 判据不是「某句话原文在哪」，而是**等效的强制表述**必须前置：
      // 允许把「禁止只回一句文字」的措辞改写成规则 0，但位置要早。
      final head = proto.substring(0, (proto.length * 0.25).round());
      final hasMandate = head.contains('必须给出信封') || head.contains('仍然要给信封');
      expect(
        hasMandate,
        isTrue,
        reason:
            '协议前 25%（约 ${(proto.length * 0.25).round()} 字）里必须有'
            '「必须给出信封 / 仍然要给信封」的硬约束。'
            '现状前 25% 开头：${head.substring(0, head.length.clamp(0, 300))}',
      );
      // 原规则 5 的正文仍必须存在（语义不得因重排而丢失）。
      expect(
        proto.contains('修改请求禁止只回一句文字'),
        isTrue,
        reason: '原规则 5 的正文必须保留（重排只改位置/措辞，不删语义）',
      );
    });

    test('协议总长 ≤ 7500 字（防止继续膨胀）', () {
      expect(
        proto.length,
        lessThanOrEqualTo(7500),
        reason:
            '协议 ${proto.length} 字已偏长；再加规则请先合并旧规则。'
            '（基线实测 6596 字，本批为「缺信息兜底」前置化会略增，预算留到 7500）',
      );
    });

    test('不允许出现「先追问再决定」式的含糊表述（会诱导模型只回文字）', () {
      // 规则 4 原文有「拿不准怎么改时才用纯文本提问」——这句被实测里 4 条失败
      // 直接引用成了「我只回文字」的许可证。要求它必须带**兜底条款**。
      final rule4Start = proto.indexOf('4. ');
      expect(rule4Start, greaterThanOrEqualTo(0));
      final rule4End = proto.indexOf('5. ', rule4Start);
      final rule4 = proto.substring(
        rule4Start,
        rule4End < 0 ? proto.length : rule4End,
      );
      final hasFallback =
          rule4.contains('信封') &&
          (rule4.contains('suggestions') || rule4.contains('仍要'));
      expect(
        hasFallback,
        isTrue,
        reason:
            '规则 4 允许「拿不准时用纯文本提问」，但没有同句给出兜底（仍要出信封 + '
            'suggestions）——实测 4 条失败都引用了这句当许可证。原文：$rule4',
      );
    });

    // 【RED→GREEN，2026-10-24 严格口径实测抓到的两条「错误答案」】
    //
    // 用户原话：「我要更加准确……也不要给我推荐错误的答案。」
    //
    // 严格口径（信封 + 精确命中 + 不夹带）实测 73/75 = 97.3%，两条失败都不是
    // 「卡片不弹」，而是**协议自己留了两个口子**：
    //
    // | 用例 | 自然语言 | 模型实际给的 | 错在哪 |
    // |---|---|---|---|
    // | M02 | 我中午吃了米饭和鸡胸肉 | `meal.create` **+ `meal.item.update`** | 用户没要求改克数，模型自己附送 |
    // | M22 | 加一道番茄炒蛋当晚饭 | `meal.create` + `items: []`，reply 却说「**已把**番茄炒蛋**记进**晚餐」 | 空壳命令必失败 + 谎报已执行 |
    //
    // 两处都是规则里**没写死**的空白：规则 0 只说「只给正确的」，没说
    // 「不许顺手多给一条」；规则 1 只说 `edits` 不能为空数组，没说**单条
    // 命令的参数也必须完整**，也没禁止 reply 谎报「已记录」。
    test('协议必须禁止「顺手多给一条」：一条回复只做用户这句话要求的事', () {
      final hasOnlyAsked =
          proto.contains('只做用户') ||
          (proto.contains('不要附带') &&
              (proto.contains('顺手') || proto.contains('额外')));
      expect(
        hasOnlyAsked,
        isTrue,
        reason:
            '实测 M02「我中午吃了米饭和鸡胸肉」⇒ 模型给 meal.create + '
            'meal.item.update（用户没要求改克数）。协议必须显式禁止「顺手附送」'
            '一条用户没提的命令——这正是用户点名的「推荐错误的答案」。',
      );
    });

    test('协议必须禁止空壳命令 + 禁止谎报「已记录」', () {
      // 参数不完整的命令发出来必然 failed（`items: []` 过不了 foodItems 校验），
      // 而模型同时会在 reply 里写「已记进晚餐」——用户看到的是假成功。
      final forbidsEmptyShell =
          (proto.contains('参数完整') ||
              proto.contains('空壳') ||
              proto.contains('不能为空数组') ||
              proto.contains('至少要有一条')) &&
          proto.contains('items');
      expect(
        forbidsEmptyShell,
        isTrue,
        reason:
            '实测 M22「加一道番茄炒蛋当晚饭」⇒ 模型给 meal.create + items:[]，'
            '这条进执行器必然失败。协议必须要求「每条 edits 参数完整可执行，'
            '写不全就不要发这条」。',
      );
      final forbidsFalseDone =
          proto.contains('还没有生效') ||
          proto.contains('不要写「已') ||
          proto.contains('不许说「已') ||
          proto.contains('你只是提议');
      expect(
        forbidsFalseDone,
        isTrue,
        reason:
            '同一轮 M22 的 reply 写的是「已把番茄炒蛋记进晚餐」——而卡片还等着'
            '用户点「应用」。协议必须写明「你只是提议，还没生效」。',
      );
    });

    // 【RED→GREEN，2026-10-24 第二轮实测（`ai-live-accurate6`，67/75 = 89.3%）】
    //
    // 收紧上面两条之后，M22 从 2/3 提到 3/3，但**同一句「信息不全」被模型拿去
    // 当成了偷懒许可证**：4 条失败全部是「用户没说克数/营养值」⇒ 模型回
    // `{"reply":"…还得先补上克数…","edits":[]}`（空信封、零按钮），或者干脆
    // 退回散文反问。典型原文：
    //   M02「我中午吃了米饭和鸡胸肉」→「还得先补上克数（各吃了多少克）」
    //   M09「早上两个包子」→「食物库里还没有包子…请确认包子的类型和每个大约多少克」
    //   M17「早上吃了燕麦粥」→「燕麦粥的克数我还不清楚」
    //   M08「加一个叫麻辣烫的食材」→「还差营养数据：每 100g 的热量…」
    //
    // 但 App 的既定口径（规则 7）本来就是**让模型按常见值估算**，且执行器
    // 对 `items` 只要求克数在 0.1–5000 之间——「没说克数」根本不是缺信息，
    // 它是**该估的量**。把可估的量推回给用户，正是用户说的「模棱两可的答案」。
    test('协议必须写明「克数/份量/营养值没说 ⇒ 按常见值估算」，不许当缺信息反问', () {
      // 判据写成「同一句里同时出现『估算』和『克数/份量』」——第一版只要求
      // 全篇各出现一次，结果被规则 0 的「直接给 edits」+ 参数表里的「新克数」
      // 意外满足（假绿）。这里收紧成**相邻表述**。
      final estimateClauses = RegExp(
        r'[^\n。；]{0,60}(估算|按常见值|按常见份量)[^\n。；]{0,60}(克数|份量|营养值)'
        r'|(克数|份量|营养值)[^\n。；]{0,60}(估算|按常见值|按常见份量)',
      );
      final hasEstimateMandate = estimateClauses.hasMatch(proto);
      expect(
        hasEstimateMandate,
        isTrue,
        reason:
            '实测 4 条失败（M02 米饭+鸡胸肉 / M09 两个包子 / M17 燕麦粥 / '
            'M08 麻辣烫食材）全部把「没说克数或营养值」当成缺信息，回空信封反问。'
            '协议必须明写：这类量**按常见份量估算并直接给 edits**，'
            '在 reply 里说明估了多少即可。',
      );
      // 还必须有「不要因此反问」这种禁止性表述，否则模型仍会估完再问。
      final forbidsAsking =
          proto.contains('不要反问') ||
          proto.contains('不许反问') ||
          proto.contains('不要问用户') ||
          proto.contains('不必再问') ||
          proto.contains('不要因此') ||
          proto.contains('不要为这个问');
      expect(
        forbidsAsking,
        isTrue,
        reason:
            '只写「可以估算」不够——实测模型会估完再问「要我按这组值建吗」。'
            '必须明写不许把这类量当缺信息反问。',
      );
    });

    test('协议必须写明「估算值不必征求同意」（否则又会退化成反问）', () {
      // 模型即使愿意估，也会写成「要我按这组估算值建吗？」——仍然是问句、
      // 仍然没有卡片。必须明确：估算后**直接给命令**，把选择权留给
      // 「应用/不应用」那一步（界面本来就有确认步）。
      final hasDirectiveTone =
          (proto.contains('不必征求') ||
              proto.contains('不用征求') ||
              proto.contains('不要征求') ||
              proto.contains('不必再确认') ||
              proto.contains('直接给')) &&
          proto.contains('估算');
      expect(
        hasDirectiveTone,
        isTrue,
        reason:
            'M08 实测原文：「要我按这组估算值建吗？」——估了却仍不落成命令。'
            '协议必须说清：估算完直接出 edits，「应用/不应用」由用户点按钮决定。',
      );
    });

    // 【RED→GREEN，2026-10-24 内容正确性实测（`accuracy-a1`，17/18）】
    //
    // 用户原话：「确保 ai 能正确合理的调用所有功能，而且不会出错，比如我要
    // 晚餐，给我午餐，漏掉食物或者重复食物等，**要有自己的去重和检测遗漏的
    // 机制**」。
    //
    // 实测 S08「午饭吃了米饭和米饭」：模型照抄成两条米饭（1/2 次）。用户
    // 自己口误/赘述时，应该记**一条**，不是两条。协议现有规则 13 只讲
    // 「跨轮/跨餐次不要重复记」，**没讲同一句话内部的重复**。这条补那个空白。
    test('协议必须写明「同一条 items 里不许出现同名食物」', () {
      final hasNoDupRule = RegExp(
        r'(同名|同一个食物|重复)[^\n。；]{0,40}(只记|合并|去重|一条|一次)'
        r'|(只记|合并|去重)[^\n。；]{0,40}(同名|重复)',
      ).hasMatch(proto);
      expect(
        hasNoDupRule,
        isTrue,
        reason:
            '实测 S08「午饭吃了米饭和米饭」⇒ 模型给两条米饭。协议必须明确：'
            '同一餐的 items 里同名食物只能出现一次（用户自己说重复也要合并成一条）。',
      );
    });

    // 用户原话「我要晚餐，给我午餐」正是这类错误。实测这一轮 6/6 全对，
    // 但协议里**没有**一条硬约束说「按用户说的餐次」——「今天做对了」不等于
    // 「以后不会错」。这条把既有正确行为钉住（防回归，不是修 bug）。
    test('协议必须写明「用户说了餐次就按用户说的，不许自己改」', () {
      final hasSlotRule = RegExp(
        r'(餐次|早餐|午餐|晚餐|加餐)[^\n。；]{0,50}(按用户|用户说的|用户明确|照用户)'
        r'|(按用户|用户说的|用户明确|照用户)[^\n。；]{0,50}(餐次|早餐|午餐|晚餐)',
      ).hasMatch(proto);
      expect(
        hasSlotRule,
        isTrue,
        reason:
            '「我要晚餐，给我午餐」这种错，协议里必须有一条硬约束挡住：'
            '用户明确说了餐次就照用户说的，不许自己换一餐。',
      );
    });
  });
}
