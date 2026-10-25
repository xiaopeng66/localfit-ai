import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_intent.dart';
import 'package:flutter_test/flutter_test.dart';

/// 「用户这句话是在要求我改数据吗」的本地判定（2026-10-16 用户要求：
/// 「对话只要涉及让你修改，就必须正确识别指令，而不是空回文字」）。
///
/// 这里钉的是**保守**口径：宁可漏判（少一次自动重试），也不要把提问/闲聊
/// 误判成修改、白白多发一次请求。
void main() {
  group('looksLikeModificationRequest', () {
    test('明确的修改请求：动词表覆盖的常见说法都要判真', () {
      const requests = [
        '添加鸡肉食材',
        '帮我加一个鸡蛋',
        '加上 250 毫升水',
        '记录今天的体重 72.5 公斤',
        '帮我记一笔饮水',
        '记一下早餐吃了两个鸡蛋',
        '我喝了 300 毫升水',
        '早餐吃了全麦吐司 80 克',
        '把刚才那条饮水记录删掉',
        '删除午饭那条记录',
        '去掉加餐',
        '把这条改成午餐',
        '换成 150 克',
        '重命名计划为「四天增肌」',
        '计划改名叫四天增肌',
        '把我的目标设为减脂',
        '更新一下步数目标为 12000',
        '调整饮水目标到 2500',
        '新建一个自定义食材：鸡肉',
        '建一个食堂地点叫三食堂',
        '把体重改成 71',
        '我想把目标体重设为 65 公斤',
      ];
      for (final text in requests) {
        expect(
          looksLikeModificationRequest(text),
          isTrue,
          reason: '「$text」是修改请求，必须判真（否则会空回文字）',
        );
      }
    });

    test('提问与闲聊一律判假（不许为它们多发一次请求）', () {
      const nonRequests = [
        '你好呀',
        '今天晚餐怎么搭配？',
        '我可以吃吗？',
        '我能吃鸡蛋吗',
        '这个面包热量高吗？',
        '为什么我的体重没变？',
        '我今天吃了什么？',
        '怎么记录体重？',
        '帮我看看最近的趋势',
        '谢谢你',
        '什么是蛋白质？',
        '有没有适合减脂的晚餐推荐？',
        '？',
        '',
        '   ',
      ];
      for (final text in nonRequests) {
        expect(
          looksLikeModificationRequest(text),
          isFalse,
          reason: '「$text」不是修改请求，判真会多发一次 AI 请求',
        );
      }
    });

    test('动词藏在疑问句里也判假：问句优先', () {
      for (final text in const [
        '我要不要记一下体重？',
        '可以帮我删除这条记录吗？',
        '能不能把目标改成减脂？',
        '记录体重在哪儿改？',
      ]) {
        expect(
          looksLikeModificationRequest(text),
          isFalse,
          reason: '「$text」在问「要不要/能不能/在哪儿」，先按提问处理',
        );
      }
    });

    test('陈述式约束：过敏 / 忌口 / 素食 / 不吃 —— 也是修改请求', () {
      // 2026-10-16 真实模型实测（docs/36 §7，控制矩阵 ⑦ 场景）：用户说
      // 「我忌口花生和海鲜，饮食上偏素食。」时，模型回了一段**散文 + 信封**
      // （"我来把这些写进你的饮食约束里" + JSON），而本地判定不认这类**陈述式**
      // 约束 ⇒ 不会催信封 ⇒ 解析失败后**什么都没写**，可回复却在说「已记下」。
      // 这是用户点名的「涉及修改必须识别」的漏洞，且后果是**假称已写入**。
      const statements = [
        '我忌口花生和海鲜，饮食上偏素食。',
        // 也顺带钉住「吃了…」这类记录陈述（它属于「我把这件事做了」那一族）。
        '今天吃了花生酱面包',
        '我对花生过敏',
        '我对虾过敏，以后别推荐',
        '我不吃香菜',
        '我吃素',
        '我是素食者',
        '我乳糖不耐',
        '别给我推荐内脏类',
        '以后别推荐含酒精的菜',
      ];
      for (final text in statements) {
        expect(
          looksLikeModificationRequest(text),
          isTrue,
          reason: '「$text」是在陈述需要落库的约束，必须判真（否则会假称已记下）',
        );
      }
    });

    test('陈述式约束的**否定面**：纯粹描述口味/提问不判真', () {
      for (final text in const [
        '我喜欢吃花生',
        '花生过敏是什么症状？',
        '素食有什么好处？',
        '我朋友对花生过敏',
      ]) {
        expect(
          looksLikeModificationRequest(text),
          isFalse,
          reason: '「$text」不是在给自己设约束（或是在提问），判真会白跑一次',
        );
      }
    });

    test('「我要/帮我/我想」+ 动词=判真；单独一个动词词根不算', () {
      expect(looksLikeModificationRequest('我要减脂'), isTrue);
      expect(looksLikeModificationRequest('我想增肌'), isTrue);
      expect(looksLikeModificationRequest('帮我改一下'), isTrue);
      // 只是描述状态、没有改的意图。
      expect(looksLikeModificationRequest('今天已经记过了'), isFalse);
      expect(looksLikeModificationRequest('记录很正常'), isFalse);
    });
  });
}
