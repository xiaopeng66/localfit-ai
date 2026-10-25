import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/features/ai_memory/application/ai_memory_candidates.dart';
import 'package:localfit_ai/features/ai_memory/domain/ai_memory.dart';

/// 记忆候选解析器（v2「提炼记忆」的解析面，docs/38 §4.3）。
void main() {
  group('parseAiMemoryCandidates', () {
    test('严格 JSON：reply + 候选全字段', () {
      final parse = parseAiMemoryCandidates(
        '{"reply":"找到 1 条","candidates":[{"text":"不吃香菜",'
        '"kind":"preference","domain":"nutrition","tags":["香菜","挑食"]}]}',
      );
      expect(parse.reply, '找到 1 条');
      expect(parse.candidates, hasLength(1));
      expect(parse.candidates.single.text, '不吃香菜');
      expect(parse.candidates.single.kind, AiMemoryKind.preference);
      expect(parse.candidates.single.domain, AiMemoryDomain.nutrition);
      expect(parse.candidates.single.tags, ['香菜', '挑食']);
    });

    test('散文 + JSON（模型常见形态）：提取唯一对象', () {
      final parse = parseAiMemoryCandidates(
        '好的，我从我们的对话里找到了这些：\n'
        '{"reply":"找到 2 条","candidates":['
        '{"text":"周三晚上练腿","kind":"habit","domain":"training"},'
        '{"text":"常去二食堂","kind":"fact","domain":"canteen"}]}',
      );
      expect(parse.candidates, hasLength(2));
      expect(parse.candidates.first.text, '周三晚上练腿');
      expect(parse.candidates.first.kind, AiMemoryKind.habit);
      expect(parse.candidates.last.domain, AiMemoryDomain.canteen);
    });

    test('kind/domain 乱写：回落缺省（偏好/其他），不丢条', () {
      final parse = parseAiMemoryCandidates(
        '{"candidates":[{"text":"喜欢晨跑","kind":"banana","domain":"未知"}]}',
      );
      expect(parse.candidates.single.kind, AiMemoryKind.preference);
      expect(parse.candidates.single.domain, AiMemoryDomain.general);
    });

    test('缺 tags / tags 里混非字符串：照常解析', () {
      final parse = parseAiMemoryCandidates(
        '{"candidates":[{"text":"不吃香菜","tags":["香菜",42,null,"香菜"]}]}',
      );
      expect(parse.candidates.single.tags, ['香菜'], reason: '去重且滤非字符串');
    });

    test('超长 text 整条丢弃（不截断成半句话）；非法条目不影响其余', () {
      final parse = parseAiMemoryCandidates(
        '{"candidates":['
        '{"text":"${'长' * 141}"},'
        '{"text":"好的这条在"}]}',
      );
      expect(parse.candidates, hasLength(1));
      expect(parse.candidates.single.text, '好的这条在');
    });

    test('多于 3 条：只收前 3 条', () {
      final parse = parseAiMemoryCandidates(
        '{"candidates":['
        '{"text":"一"},{"text":"二"},{"text":"三"},{"text":"四"}]}',
      );
      expect(parse.candidates, hasLength(3));
    });

    test('纯散文（无 JSON）：整段当 reply，零候选', () {
      final parse = parseAiMemoryCandidates('这段对话没什么值得记的。');
      expect(parse.reply, '这段对话没什么值得记的。');
      expect(parse.candidates, isEmpty);
    });

    test('两个 JSON 对象：拒绝猜测，整段当散文', () {
      final parse = parseAiMemoryCandidates(
        '{"candidates":[{"text":"一"}]} 中间 {"candidates":[{"text":"二"}]}',
      );
      expect(parse.candidates, isEmpty);
    });

    test('空 candidates + reply：合法（没有值得记的）', () {
      final parse = parseAiMemoryCandidates(
        '{"reply":"这段对话没有值得长期记住的内容。","candidates":[]}',
      );
      expect(parse.reply, contains('没有'));
      expect(parse.candidates, isEmpty);
    });

    test('空输入：空结果', () {
      expect(parseAiMemoryCandidates('').isEmpty, isTrue);
      expect(parseAiMemoryCandidates('   ').isEmpty, isTrue);
    });
  });

  test('aiMemoryExtractPrompt：带转录文本与结构要求', () {
    final prompt = aiMemoryExtractPrompt('U: 我不吃香菜\nA: 好的');
    expect(prompt, contains('U: 我不吃香菜'));
    expect(prompt, contains('candidates'));
    expect(prompt, contains('140'));
  });
}
