// 重复可见化（2123）：应用前「今天已有相同记录」的提示。
//
// 两层：纯判断函数（文案与条件）+ 协调器接线（把提示挂到对应行）。
// 探针本身查库（ExistingFactProbe），用真实仓储的集成行为由
// `test/features/ai_conversation/application/existing_fact_probe_test.dart`
// 覆盖；这里只测不依赖数据库的确定性部分。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/features/ai_conversation/application/chat_edit_coordinator.dart';
import 'package:localfit_ai/features/ai_conversation/application/existing_fact_probe.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_command.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_context_builder.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_executor.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_registry.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_turn.dart';
import 'package:localfit_ai/features/ai_conversation/domain/conversation_message.dart';
import 'package:localfit_ai/features/ai_conversation/presentation/chat_edit_card.dart';

class _StubBuilder implements ChatEditContextBuilder {
  @override
  Future<String> build({
    String? userMessage,
    PendingProposal? pendingProposal,
    String? foodQuery,
  }) async => '（快照）';
}

class _NoopExecutor implements ChatEditExecutor {
  @override
  Future<ChatEditApplyResult> apply(ChatEditCommand command) async =>
      const ChatEditApplyResult.ok('已完成。');
}

void main() {
  group('duplicateHintFor（纯判断）', () {
    test('记餐：已有同名食物 ⇒ 明说「不会重复写入」', () {
      expect(
        duplicateHintFor(action: 'meal.create', existingFoodNames: {'米饭'}),
        '今天已经记过米饭，应用时不会重复写入',
      );
      expect(
        duplicateHintFor(action: 'meal.create', existingFoodNames: const {}),
        isNull,
      );
    });

    test('饮水：已有相同容量 ⇒ 报次数并问要不要再记', () {
      expect(
        duplicateHintFor(
          action: 'water.add',
          existingWaterMl: const [250, 250],
          draftAmountMl: 250,
        ),
        '今天已有 2 次 250ml 的饮水，确认要再记一次吗',
      );
      // 不同容量不算重复。
      expect(
        duplicateHintFor(
          action: 'water.add',
          existingWaterMl: const [250],
          draftAmountMl: 300,
        ),
        isNull,
      );
      expect(duplicateHintFor(action: 'water.add', draftAmountMl: 250), isNull);
    });

    test('体重：今天已有 ⇒ 明说会覆盖', () {
      expect(
        duplicateHintFor(action: 'weight.log', existingWeightKg: 72.5),
        '今天已记过体重 72.5 kg，应用会覆盖为这次的值',
      );
      expect(duplicateHintFor(action: 'weight.log'), isNull);
    });

    test('其它命令没有「重复」语义 ⇒ 不给提示', () {
      expect(
        duplicateHintFor(action: 'meal.delete', existingFoodNames: {'米饭'}),
        isNull,
      );
      expect(
        duplicateHintFor(action: 'dish.upsert', existingFoodNames: {'红烧肉'}),
        isNull,
      );
    });
  });

  group('ChatEditCoordinator.annotateDuplicates', () {
    final registry = ChatEditCommandRegistry();
    ChatEditCommand cmd(String action, Map<String, Object> args) {
      final spec = registry.specOf(action)!;
      return ChatEditCommand(
        spec: spec,
        args: validateChatEditArgs(spec, args),
      );
    }

    ChatEditTurn turnOf(List<ChatEditTurnItem> rows) =>
        ChatEditTurn(reply: '记一下', rows: rows);

    ChatEditTurnItem row(int index, String action, Map<String, Object> args) =>
        ChatEditTurnItem(
          index: index,
          raw: {'action': action, 'args': args},
          command: cmd(action, args),
        );

    test('探针给的提示挂到对应行；没给的行保持原样', () async {
      final coordinator = ChatEditCoordinator(
        contextBuilder: _StubBuilder(),
        executor: _NoopExecutor(),
        duplicateProbe: (turn) async => {0: '今天已经记过米饭，应用时不会重复写入'},
      );
      final annotated = await coordinator.annotateDuplicates(
        turnOf([
          row(0, 'meal.create', {
            'slot': '午餐',
            'items': [
              {'food': '米饭', 'grams': 150.0},
            ],
          }),
          row(1, 'water.add', {'amountMl': 250.0}),
        ]),
      );
      expect(annotated.rows[0].duplicateHint, contains('米饭'));
      expect(annotated.rows[1].duplicateHint, isNull);
      // 命令与 reply 不受影响（提示只是旁注）。
      expect(annotated.reply, '记一下');
      expect(annotated.rows[0].command!.action, 'meal.create');
    });

    test('探针未接线 / 抛异常 ⇒ 原样返回（提示绝不挡住卡片）', () async {
      final noProbe = ChatEditCoordinator(
        contextBuilder: _StubBuilder(),
        executor: _NoopExecutor(),
      );
      final original = turnOf([
        row(0, 'water.add', {'amountMl': 250.0}),
      ]);
      final untouched = await noProbe.annotateDuplicates(original);
      expect(untouched.rows.single.duplicateHint, isNull);

      final throwing = ChatEditCoordinator(
        contextBuilder: _StubBuilder(),
        executor: _NoopExecutor(),
        duplicateProbe: (turn) async => throw StateError('db down'),
      );
      final survived = await throwing.annotateDuplicates(original);
      expect(survived.rows.single.duplicateHint, isNull);
      expect(survived.reply, '记一下');
    });
  });

  group('卡片渲染', () {
    testWidgets('重复提示显示在主行下面，多食物只显示一次', (tester) async {
      final registry = ChatEditCommandRegistry();
      final spec = registry.specOf('meal.create')!;
      final command = ChatEditCommand(
        spec: spec,
        args: validateChatEditArgs(spec, {
          'slot': '午餐',
          'items': [
            {'food': '米饭', 'grams': 150.0},
            {'food': '鸡蛋', 'grams': 50.0},
          ],
        }),
      );
      const hint = '今天已经记过米饭，应用时不会重复写入';
      final turn = ChatEditTurn(
        reply: '记午餐',
        rows: [
          ChatEditTurnItem(
            index: 0,
            raw: const {'action': 'meal.create'},
            command: command,
            duplicateHint: hint,
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: ChatEditCard(
                index: 0,
                message: ConversationMessage(
                  id: 'dup-card',
                  role: ConversationRole.assistant,
                  text: turn.reply,
                  kind: ConversationMessageKind.editProposal,
                  editTurn: turn,
                  createdAt: DateTime(2026, 11, 7, 12),
                ),
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

      expect(find.text(hint), findsOneWidget, reason: '两样食物共用一句，只显示一次');
      expect(find.byKey(const Key('chat-edit-row-hint-0-0-0')), findsOneWidget);
      expect(find.byKey(const Key('chat-edit-row-hint-0-0-1')), findsNothing);
    });
  });
}
