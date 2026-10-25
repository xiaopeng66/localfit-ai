import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/features/food_scan/application/scan_conversation_intent.dart';

/// docs/21 §5.4「对话能力」1–3 的意图判别。
///
/// 这一层是纯函数，所以测试直接穷举输入，不需要 widget/数据库。
void main() {
  group('体重意图（能力 1）', () {
    test('解析「记录今天体重 72.5kg」', () {
      final intent = classifyScanIntent('记录今天体重 72.5kg');
      expect(intent, isA<LogWeightIntent>());
      expect((intent as LogWeightIntent).weightKg, 72.5);
    });

    test('支持公斤/千克与整数体重', () {
      expect((classifyScanIntent('体重 70 公斤') as LogWeightIntent).weightKg, 70);
      expect(
        (classifyScanIntent('帮我记录 68 千克') as LogWeightIntent).weightKg,
        68,
      );
      expect((classifyScanIntent('今天 75kg') as LogWeightIntent).weightKg, 75);
    });

    test('全角句点也能解析', () {
      expect(
        (classifyScanIntent('记录体重 72．5kg') as LogWeightIntent).weightKg,
        72.5,
      );
    });

    test('显式日期被识别，未说日期则为 null（不猜）', () {
      final withDate = classifyScanIntent('记录 2026-09-01 体重 72kg');
      expect((withDate as LogWeightIntent).localDate, '2026-09-01');
      final withoutDate = classifyScanIntent('记录今天体重 72kg');
      expect((withoutDate as LogWeightIntent).localDate, isNull);
    });

    test('值域外的数字不认体重意图（宁可不写库）', () {
      // 下方 35、上方 300 都是仓储的合法边界；越界必须落到 Unknown，
      // 而不是构造出一个稍后会被仓储拒绝的意图。
      expect(classifyScanIntent('体重 12kg'), isA<UnknownScanIntent>());
      expect(classifyScanIntent('体重 320kg'), isA<UnknownScanIntent>());
      expect(classifyScanIntent('体重 35kg'), isA<LogWeightIntent>());
      expect(classifyScanIntent('体重 300kg'), isA<LogWeightIntent>());
    });

    test('有 kg 但没有数字不认', () {
      expect(classifyScanIntent('记录体重 kg'), isA<UnknownScanIntent>());
    });
  });

  group('训练计划意图（能力 2）', () {
    test('「帮我制定今天的训练计划」', () {
      expect(classifyScanIntent('帮我制定今天的训练计划'), isA<CreateWorkoutPlanIntent>());
    });

    test('健身/锻炼同义', () {
      expect(classifyScanIntent('生成今天的健身计划'), isA<CreateWorkoutPlanIntent>());
      expect(classifyScanIntent('安排今天的锻炼计划'), isA<CreateWorkoutPlanIntent>());
    });

    test('只说训练没说要计划，不认（避免误触发）', () {
      expect(classifyScanIntent('我今天训练了'), isA<UnknownScanIntent>());
    });
  });

  group('食谱/计划句子（能力 3 已下线）', () {
    // `CreateRecipePlanIntent` 随「食谱 / 计划」整族下线（docs/28 §6.4）：
    // 这类句子现在落到 UnknownScanIntent，页面回引导文案，不再假装能打开
    // 一张不存在的界面。这些输入仍要钉住，防止将来又被误判成训练计划。
    test('「今天帮我制定早餐食谱」不再认成食谱意图', () {
      expect(classifyScanIntent('今天帮我制定早餐食谱'), isA<UnknownScanIntent>());
    });

    test('午/晚餐与加餐的食谱句子同样落到 Unknown', () {
      expect(classifyScanIntent('制定午餐食谱'), isA<UnknownScanIntent>());
      expect(classifyScanIntent('生成晚餐食谱'), isA<UnknownScanIntent>());
      expect(classifyScanIntent('安排加餐食谱'), isA<UnknownScanIntent>());
    });

    test('没说餐次的食谱句子也落到 Unknown', () {
      expect(classifyScanIntent('帮我制定今天的食谱'), isA<UnknownScanIntent>());
    });
  });

  group('判别优先级与兜底', () {
    test('同时含体重与「今天」时按体重处理', () {
      // 「今天」是通用词，若先匹配计划关键词会被误判——回归防线。
      expect(classifyScanIntent('今天记录体重 70kg'), isA<LogWeightIntent>());
    });

    test('同时提训练和食谱时优先训练', () {
      expect(classifyScanIntent('帮我制定训练计划和食谱'), isA<CreateWorkoutPlanIntent>());
    });

    test('空输入与闲聊都落到 Unknown', () {
      expect(classifyScanIntent(''), isA<UnknownScanIntent>());
      expect(classifyScanIntent('   '), isA<UnknownScanIntent>());
      expect(classifyScanIntent('今天天气不错'), isA<UnknownScanIntent>());
      expect(classifyScanIntent('晚点再说'), isA<UnknownScanIntent>());
    });
  });
}
