import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_reply_display.dart';

/// 助手回复的展示清洗（2026-10-24 用户：「食堂菜品 AI 分析会转发英文代码片段」
/// 「AI 对接很多次推不了应用卡片」）。
void main() {
  test('剥掉内部引用：snapshot 坐标不上屏，正文原样保留', () {
    expect(
      stripInternalRefs('已帮你加了[meal:mx-3]这一餐，蛋白质 12g。'),
      '已帮你加了这一餐，蛋白质 12g。',
    );
    expect(
      stripInternalRefs('看了[canteen-dish:abc-1]、[dish:dish-9]，建议补充蛋白质。'),
      '看了、，建议补充蛋白质。',
    );
  });

  test('正常中文回复不被误伤（没有方括号引用时逐字不变）', () {
    const text = '今天的午餐建议清蒸鱼配青菜（约 520 kcal）。';
    expect(stripInternalRefs(text), text);
    // 方括号里没有 `token:` 形状的内容也不动。
    expect(stripInternalRefs('备注[重要]'), '备注[重要]');
  });

  test('半截信封 → 人话，不把 JSON 亮给用户', () {
    const broken = '{"reply":"帮你记","edits":[{"action":"meal.create",';
    expect(looksLikeEnvelopeText(broken), isTrue);
    expect(replyTextForDisplay(broken), kMalformedEnvelopeNotice);
    expect(replyTextForDisplay(broken), isNot(contains('action')));
  });

  test('正常回复走清洗而不是人话兜底', () {
    expect(replyTextForDisplay('好的，[food:rice]已记录。'), '好的，已记录。');
  });
}
