// 编辑卡「各种条件 × 输入输出样式」的实帧矩阵（2126 复核）。
//
// 一卡一条件，逐张渲染后人工审看：待应用（单条/多条/多组）、已应用结果、
// 失败+修复、全部失败、重复提示、审查警告、推荐按钮、320dp×2.0、深色。
@Tags(['capture'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_command.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_proposal_audit.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_registry.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_repair.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_turn.dart';
import 'package:localfit_ai/features/ai_conversation/domain/conversation_message.dart';
import 'package:localfit_ai/features/ai_conversation/presentation/chat_edit_card.dart';

import 'support/round7_render.dart';

void main() {
  final registry = ChatEditCommandRegistry();

  ChatEditCommand cmd(String action, Map<String, Object> args) {
    final spec = registry.specOf(action)!;
    return ChatEditCommand(spec: spec, args: validateChatEditArgs(spec, args));
  }

  ChatEditTurnItem row(
    int index,
    String action,
    Map<String, Object> args, {
    ChatEditRowStatus status = ChatEditRowStatus.proposed,
    String? resultMessage,
    Map<String, String> itemNotes = const {},
    ChatEditRepair? repair,
    String? duplicateHint,
  }) => ChatEditTurnItem(
    index: index,
    raw: {'action': action, 'args': args},
    command: cmd(action, args),
    status: status,
    resultMessage: resultMessage,
    itemNotes: itemNotes,
    repair: repair,
    duplicateHint: duplicateHint,
  );

  Future<void> pumpCard(
    WidgetTester tester,
    ChatEditTurn turn, {
    bool dark = false,
    double width = 390,
    double height = 700,
    double scale = 1.0,
  }) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, height);
    tester.view.padding = const FakeViewPadding(top: 12, bottom: 12);
    tester.view.viewPadding = const FakeViewPadding(top: 12, bottom: 12);
    await tester.pumpWidget(
      RepaintBoundary(
        key: round7Boundary,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: round7CaptureTheme(dark ? AppTheme.dark() : AppTheme.light()),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              disableAnimations: true,
            ),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: ChatEditCard(
                index: 0,
                message: ConversationMessage(
                  id: 'frame',
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
      ),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> shot(WidgetTester tester, String name) async {
    expect(tester.takeException(), isNull, reason: '$name：布局溢出');
    await captureRound7(tester, name);
  }

  testWidgets('编辑卡状态矩阵', (tester) async {
    await tester.runAsync(loadRound7Fonts);

    // ① 单条命令待应用（最简单的一卡）。
    await pumpCard(
      tester,
      ChatEditTurn(
        reply: '我准备记一笔饮水。',
        rows: [
          row(0, 'water.add', {'amountMl': 250.0}),
        ],
      ),
    );
    await shot(tester, 'state-01-single-proposed');

    // ② 多命令多组待应用（记餐 + 新建食材 + 记忆）。
    await pumpCard(
      tester,
      ChatEditTurn(
        reply: '午餐记两样，另外把曲奇加进食材库，再记一条偏好。',
        rows: [
          row(0, 'meal.create', {
            'slot': '午餐',
            'items': [
              {'food': '米饭', 'grams': 150.0},
              {'food': '鸡胸肉', 'grams': 150.0},
            ],
          }),
          row(1, 'food.create', {
            'name': '抹茶曲奇（梅花形）',
            'kcalPer100g': 480.0,
            'proteinPer100g': 5.0,
            'carbsPer100g': 60.0,
            'fatPer100g': 25.0,
          }),
          row(2, 'memory.remember', {'text': '周三晚上练腿', 'kind': '习惯'}),
        ],
      ),
      height: 900,
    );
    await shot(tester, 'state-02-multi-group-proposed');

    // ③ 已应用 + 每行结果（含重复跳过）。
    await pumpCard(
      tester,
      ChatEditTurn(
        reply: '两餐都记好了。',
        rows: [
          row(
            0,
            'meal.create',
            {
              'slot': '早餐',
              'items': [
                {'food': '蔬菜馒头', 'grams': 30.0},
                {'food': '抹茶曲奇（梅花形）', 'grams': 30.0},
              ],
            },
            status: ChatEditRowStatus.applied,
            resultMessage: '已记录早餐，共 2 样。',
            itemNotes: const {'蔬菜馒头': '已记入今天的早餐', '抹茶曲奇（梅花形）': '已记入今天的早餐'},
          ),
          row(
            1,
            'meal.create',
            {
              'slot': '午餐',
              'items': [
                {'food': '鸡胸肉', 'grams': 150.0},
                {'food': '牛奶', 'grams': 200.0},
              ],
            },
            status: ChatEditRowStatus.applied,
            resultMessage: '这餐记到了今天已有的午餐里：新记 1 样，1 样今天已记过。',
            itemNotes: const {'鸡胸肉': '今天已记过，没有重复算', '牛奶': '已记入今天的午餐'},
          ),
        ],
      ),
      height: 900,
    );
    await shot(tester, 'state-03-applied-results');

    // ④ 失败 + 修复按钮（缺食材）。
    await pumpCard(
      tester,
      ChatEditTurn(
        reply: '这餐还差一个食材。',
        rows: [
          row(
            0,
            'meal.create',
            {
              'slot': '晚餐',
              'items': [
                {'food': '鸡蛋水煮', 'grams': 50.0},
              ],
            },
            status: ChatEditRowStatus.failed,
            resultMessage: '食物库里没有「鸡蛋水煮」；可以先创建它，或换一个已有食材。',
            repair: ChatEditRepair.createFood(name: '鸡蛋水煮'),
          ),
        ],
      ),
    );
    await shot(tester, 'state-04-failed-with-repair');

    // ⑤ 全部失败（无待应用行）⇒ 卡头「未应用」。
    await pumpCard(
      tester,
      ChatEditTurn(
        reply: '这两条都没成。',
        rows: [
          row(
            0,
            'water.add',
            {'amountMl': 250.0},
            status: ChatEditRowStatus.failed,
            resultMessage: '这条写入失败，请重试。',
          ),
          row(
            1,
            'weight.log',
            {'weightKg': 72.5},
            status: ChatEditRowStatus.failed,
            resultMessage: '请先完成本地建档。',
          ),
        ],
      ),
    );
    await shot(tester, 'state-05-all-failed');

    // ⑥ 应用前「今天已有」提示（重复可见化）。
    await pumpCard(
      tester,
      ChatEditTurn(
        reply: '再记一次午餐？',
        rows: [
          row(0, 'meal.create', {
            'slot': '午餐',
            'items': [
              {'food': '米饭', 'grams': 150.0},
            ],
          }, duplicateHint: '今天已经记过米饭，应用时不会重复写入'),
          row(1, 'water.add', {
            'amountMl': 250.0,
          }, duplicateHint: '今天已有 2 次 250ml 的饮水，确认要再记一次吗'),
        ],
      ),
      height: 760,
    );
    await shot(tester, 'state-06-duplicate-hints');

    // ⑦ 审查警告（餐次不符 + 疑似遗漏）。
    await pumpCard(
      tester,
      ChatEditTurn(
        reply: '按你说的晚餐记。',
        rows: [
          row(0, 'meal.create', {
            'slot': '晚餐',
            'items': [
              {'food': '米饭', 'grams': 150.0},
            ],
          }),
        ],
        warnings: const [
          ChatEditAuditWarning(
            kind: ChatEditAuditKind.slotMismatch,
            message: '你说的是午餐，提议记到了晚餐。',
          ),
          ChatEditAuditWarning(
            kind: ChatEditAuditKind.missingFood,
            message: '你提到的「鸡胸肉」没有出现在这一餐里。',
          ),
        ],
      ),
      height: 760,
    );
    await shot(tester, 'state-07-warnings');

    // ⑧ 推荐按钮（旧卡 suggestions）。
    await pumpCard(
      tester,
      ChatEditTurn(
        reply: '库里没有鸡肉，我可以先建它。',
        rows: [
          row(0, 'water.add', {'amountMl': 250.0}),
        ],
        suggestions: [
          ChatEditSuggestion(
            label: '创建食材「鸡肉」',
            action: 'food.create',
            command: cmd('food.create', {
              'name': '鸡肉',
              'kcalPer100g': 165,
              'proteinPer100g': 31,
              'carbsPer100g': 0,
              'fatPer100g': 3.6,
            }),
          ),
        ],
      ),
      height: 760,
    );
    await shot(tester, 'state-08-suggestions');

    // ⑨ 窄屏 × 2.0 字号（待应用，最长的一份）。
    await pumpCard(
      tester,
      ChatEditTurn(
        reply: '午餐记两样。',
        rows: [
          row(0, 'meal.create', {
            'slot': '午餐',
            'items': [
              {'food': '抹茶曲奇（梅花形）', 'grams': 30.0},
              {'food': '鸡胸肉（香煎）', 'grams': 150.0},
            ],
          }),
        ],
      ),
      width: 320,
      height: 900,
      scale: 2.0,
    );
    await shot(tester, 'state-09-320-2.0');

    // ⑩ 深色模式（已应用 + 结果）。
    await pumpCard(
      tester,
      ChatEditTurn(
        reply: '记好了。',
        rows: [
          row(
            0,
            'meal.create',
            {
              'slot': '加餐',
              'items': [
                {'food': '抹茶曲奇（梅花形）', 'grams': 40.0},
              ],
            },
            status: ChatEditRowStatus.applied,
            resultMessage: '已记录加餐，共 1 样。',
            itemNotes: const {'抹茶曲奇（梅花形）': '已记入今天的加餐'},
          ),
        ],
      ),
      dark: true,
      height: 700,
    );
    await shot(tester, 'state-10-dark-applied');

    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.view.resetPadding();
    tester.view.resetViewPadding();
  });
}
