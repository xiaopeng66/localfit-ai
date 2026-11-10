import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_command.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_registry.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_turn.dart';
import 'package:localfit_ai/features/ai_conversation/domain/conversation_message.dart';
import 'package:localfit_ai/features/ai_conversation/presentation/chat_edit_card.dart';

/// 需求 19（docs/60 §6.5）：**新建食材并入记一餐，不再是两个板块**。
///
/// 用户原话：「新建食材和新建菜品记录要合并，不要分开两个板块，如果已经有的
/// 食材，点击应用后即可计入，如果没有，我点击应用后就先新建再计入」。
///
/// 判据（用户任务书 §19 的四条）：
/// 1. 服务于本卡某餐的 `food.create` ⇒ **不再是独立板块**，而是那一餐的
///    子条目（带「新建」徽标，Key `chat-edit-subitem-new-<c>-<i>-<j>`）；
/// 2. 此时**不出现** `chat-edit-group-*-food` 组头；
/// 3. **纯新建食材**（没有任何餐引用它）⇒ 仍保留独立「新建食材」板块；
/// 4. 合并后点「应用本组」⇒ 食材创建 + 记餐一次完成（执行顺序由需求 6d
///    的协调器保证，见 `application/chat_edit_dependency_test.dart`）。
void main() {
  final registry = ChatEditCommandRegistry();

  ChatEditCommand cmd(String action, Map<String, Object> args) {
    final spec = registry.specOf(action)!;
    return ChatEditCommand(spec: spec, args: validateChatEditArgs(spec, args));
  }

  /// 用户原话的场景：早餐要记「米饭 + 鸡蛋水煮」，而「鸡蛋水煮」是同卡新建的。
  ChatEditTurn eggBreakfastTurn() => ChatEditTurn(
    reply: '我准备把早餐记下来，并新建食材鸡蛋水煮。',
    rows: [
      ChatEditTurnItem(
        index: 0,
        raw: const {'action': 'meal.create'},
        command: cmd('meal.create', {
          'slot': 'breakfast',
          'items': [
            {'food': '米饭', 'grams': 150.0},
            {'food': '鸡蛋水煮', 'grams': 100.0},
          ],
        }),
      ),
      ChatEditTurnItem(
        index: 1,
        raw: const {'action': 'food.create'},
        command: cmd('food.create', {
          'name': '鸡蛋水煮',
          'kcalPer100g': 155.0,
          'proteinPer100g': 13.0,
          'carbsPer100g': 1.1,
          'fatPer100g': 10.6,
        }),
      ),
    ],
  );

  /// 纯新建食材：用户只说「加一个叫麻辣烫的食材」，没有任何餐引用它。
  ChatEditTurn pureFoodTurn() => ChatEditTurn(
    reply: '好，给你加一个叫麻辣烫的食材。',
    rows: [
      ChatEditTurnItem(
        index: 0,
        raw: const {'action': 'food.create'},
        command: cmd('food.create', {
          'name': '麻辣烫',
          'kcalPer100g': 90.0,
          'proteinPer100g': 6.0,
          'carbsPer100g': 9.0,
          'fatPer100g': 3.0,
        }),
      ),
    ],
  );

  ConversationMessage messageWith(ChatEditTurn turn) => ConversationMessage(
    id: 'card-19',
    role: ConversationRole.assistant,
    text: turn.reply,
    kind: ConversationMessageKind.editProposal,
    editTurn: turn,
    createdAt: DateTime(2026, 10, 25, 12),
  );

  Future<void> pump(WidgetTester tester, ChatEditTurn turn) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: ChatEditCard(
              index: 0,
              message: messageWith(turn),
              onApply: () {},
              onApplyRows: (_) {},
              onDismiss: () {},
              onApplySuggestion: (_) {},
              onRepair: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('1+2：服务于本餐的新食材 ⇒ 不出现 food 组，且该食材行带「新建」徽标', (tester) async {
    await pump(tester, eggBreakfastTurn());

    expect(
      find.byKey(const Key('chat-edit-group-0-food')),
      findsNothing,
      reason: '需求 19：它服务于本卡某餐 ⇒ 不该再有独立的「新建食材」板块',
    );
    expect(
      find.byKey(const Key('chat-edit-group-0-meal')),
      findsOneWidget,
      reason: '它该并进「记一餐」板块',
    );
    // 卡片下标 0、记餐行下标 0、新建的那个食材是第 2 个子条目（下标 1）。
    expect(
      find.byKey(const Key('chat-edit-subitem-new-0-0-1')),
      findsOneWidget,
      reason: '该食材行要带「新建」徽标（用户看不出「这条要先建」就等于没合并）',
    );
  });

  testWidgets('3：纯新建食材仍保留独立「新建食材」板块（不许为合并把它吞掉）', (tester) async {
    await pump(tester, pureFoodTurn());
    // 【2026-11-07 去挤】整卡只有一条命令时不再画组头（卡头已写「1 条修改」，
    // 组头重复）。「板块」的存在性改由浅灰分块的 key 表达——它才是真正把
    // 这一组框起来的容器；组头只是它的标题行。
    expect(
      find.byKey(const Key('chat-edit-block-0-food')),
      findsOneWidget,
      reason: '没有任何餐引用它 ⇒ 仍是一个独立的「新建食材」板块',
    );
    expect(
      find.byKey(const Key('chat-edit-block-0-meal')),
      findsNothing,
      reason: '这张卡里本来就没有记餐',
    );
  });

  testWidgets('卡头结论行仍说清是哪一餐（合并后不该退回「N 条修改」）', (tester) async {
    await pump(tester, eggBreakfastTurn());
    final headline = tester.widget<Text>(
      find.byKey(const Key('chat-edit-card-headline-0')),
    );
    expect(headline.data, contains('早餐'), reason: '合并后「新建食材」是这一餐的一部分，餐次结论必须保住');
  });

  // ── 2026-10-26 看图复核抓到的两条（19 的「半条」）──────────────────────

  /// 【复核缺陷 1】卡头摘要把新食材说了**两遍**：先作为这一餐的食物
  /// （「米饭 150g、鸡蛋水煮 100g」），又被通用分支用 `summarize()` 报一次
  /// （「新建食材「鸡蛋水煮」：155.0 kcal/100g（P13.0/C1.1/F10.6）」）——
  /// 而那个 P/C/F 压缩写法正是 6c 明确否掉的样子（「挤在一起很丑」）。
  testWidgets('复核：卡头摘要只提新食材一次，且不带 P/C/F 压缩写法', (tester) async {
    await pump(tester, eggBreakfastTurn());
    final summary = tester
        .widget<Text>(find.byKey(const Key('chat-edit-card-summary-0')))
        .data!;
    expect(
      '鸡蛋水煮'.allMatches(summary).length,
      1,
      reason: '新食材只该出现一次（实测原文：$summary）',
    );
    expect(
      summary,
      isNot(contains('P13.0/C1.1/F10.6')),
      reason: '不能把 6c 否掉的 P/C/F 压缩写法又搬回来（原文：$summary）',
    );
    expect(summary, contains('新建'), reason: '这一次要说明它是「要新建的」（一句话说清）');
  });

  /// 【2026-11-06 用户复核】记餐里的新食材行与已有食物行必须同一种紧凑样式。
  ///
  /// 旧实现把 `food.create` 的每 100g 热量/三色点搬进记餐行，结果同一张卡里
  /// 「蔬菜馒头（已有食物）」只有名称+克数，「抹茶曲奇（新建）」却多出 480
  /// kcal 与宏量点——而且 480 是每 100g、不是这一份 30g 的热量，明显误导。
  /// 现在记餐行统一为「名称 · 克数 + 新建徽标」；每 100g 营养只留在独立的
  /// `food.create` 卡里。
  testWidgets('复核：合并进记餐的新食材行与已有食物同款紧凑样式', (tester) async {
    await pump(tester, eggBreakfastTurn());
    expect(
      find.textContaining('155'),
      findsNothing,
      reason: '记餐行不展示每 100g 热量，避免被当成这一份的热量',
    );
    expect(
      find.byKey(const Key('chat-edit-newfood-dot-0-0-1-0')),
      findsNothing,
      reason: '记餐行不再放三色点；营养细节属于独立 food.create 卡',
    );
    expect(
      find.byKey(const Key('chat-edit-subitem-new-0-0-1')),
      findsOneWidget,
      reason: '「新建」徽标仍要保留，用户要知道这条要先建',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const Key('chat-edit-subitem-title-0-0-0')))
          .data,
      '米饭',
      reason: '标题只放食物名；克数在第二行',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const Key('chat-edit-subitem-title-0-0-1')))
          .data,
      '鸡蛋水煮',
      reason: '新食材行与已有食物同款标题',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const Key('chat-edit-subitem-summary-0-0-0')),
          )
          .data,
      '早餐 · 150 g',
      reason: '克数跟在本行餐次后面',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const Key('chat-edit-subitem-summary-0-0-1')),
          )
          .data,
      '早餐 · 100 g',
      reason: '新食材的克数同样在第二行，不会被省略号吃掉',
    );
  });
}
