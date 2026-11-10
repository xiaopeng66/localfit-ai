import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_registry.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_prose_meal.dart';

void main() {
  final registry = ChatEditCommandRegistry();

  test('实机原话：图片识别后的散文提案 → 午餐 + 两条食物克数', () {
    final turn = parseProseMealProposal(
      '我准备把这份记为今天的午餐：红油豆腐粉（豆腐+金针菇+粉条）400g、'
      '白米饭（熟）150g，份量按这一碗的常见大小估算。点「应用」后生效，'
      '克数有出入告诉我再改。',
      registry,
    );
    expect(turn, isNotNull);
    expect(turn!.reply, contains('红油豆腐粉'));
    expect(turn.rows, hasLength(1));
    final command = turn.rows.single.command!;
    expect(command.action, 'meal.create');
    expect(command.args['slot'], 'lunch');
    final items = command.args['items']! as List<Object>;
    expect(items, hasLength(2));
    expect((items[0] as Map)['food'], '红油豆腐粉');
    expect((items[0] as Map)['grams'], 400.0);
    // 短修饰「熟」保留进食物名（库里常见「白米饭（熟）」）。
    expect((items[1] as Map)['food'], '白米饭（熟）');
    expect((items[1] as Map)['grams'], 150.0);
  });

  test('克数/毫升都认；中文逗号与顿号都当分隔符', () {
    final turn = parseProseMealProposal(
      '好的，记为晚餐：鸡胸肉 120 克，西兰花200g；豆浆300ml。点应用后生效。',
      registry,
    );
    expect(turn, isNotNull);
    final items = turn!.rows.single.command!.args['items']! as List<Object>;
    expect(items, hasLength(3));
    expect((items[2] as Map)['food'], '豆浆');
    expect((items[2] as Map)['grams'], 300.0);
  });

  test('没有「应用」口吻的普通回答不抢救', () {
    expect(parseProseMealProposal('午餐吃米饭150g和鸡胸肉120g比较合适。', registry), isNull);
  });

  test('餐次不唯一 / 没有餐次 / 没有克数清单都不抢救', () {
    expect(
      parseProseMealProposal('我准备记为早餐和午餐：米饭150g。点应用后生效。', registry),
      isNull,
    );
    expect(parseProseMealProposal('我准备记为这一餐：米饭150g。点应用后生效。', registry), isNull);
    expect(parseProseMealProposal('我准备记为午餐：米饭。点应用后生效。', registry), isNull);
  });

  test('条目里有一条读不懂就整体放弃（不猜、不丢条）', () {
    expect(
      parseProseMealProposal('我准备记为午餐：米饭150g、一些青菜。点应用后生效。', registry),
      isNull,
    );
  });
}
