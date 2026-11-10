import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_registry.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_turn.dart';

/// C-4（docs/64 阶段 2，标注「可延后」）的**静态可验部分**（2026-10-27 复核补做）。
///
/// C-4 的完整形态（建议按钮与 UI 入口共享一份「动作名 → 回调」映射）是一次重构，
/// 本仓的关键路径不依赖它；但它的**安全前提**可以钉死，而且值得钉死：
///
/// > **建议按钮能执行的动作 ⊆ 注册表命令 ⊆ 能力矩阵声明集合（C-1）**
///
/// 三段链条各有证据：
/// 1. 建议动作 ∈ 注册表：`_parseSuggestions` 对 `registry.specOf(action) == null`
///    的建议**直接丢弃**（本文件用例 1 钉住它——运行时数据没法静态穷举，
///    所以钉「解析层会不会放行未知动作」）；
/// 2. 注册表 ⊆ 能力矩阵：`ai_ui_capability_matrix_test.dart` 的判据 1
///    （本文件用例 2 用文本扫描把两侧接起来，防止有人只改一边）；
/// 3. UI 入口与建议执行**走同一条命令通道**：建议用的 `ChatEditCommand` 由
///    `chat_edit_coordinator.applyOne` 执行（UI 上的「应用」按钮同样走它）。
void main() {
  final registry = ChatEditCommandRegistry();

  test('建议里的未知 action 被解析层丢弃（不会变成可点按钮）', () {
    const envelope = '''
{
  "reply": "可以删掉那条记录，或者去看看食堂。",
  "suggestions": [
    {"label": "删除午餐", "action": "meal.delete", "args": {"mealId": "m-1"}},
    {"label": "不存在的命令", "action": "bogus.command", "args": {}}
  ]
}
''';
    final turn = parseChatEditTurn(envelope, registry);
    expect(turn, isNotNull);
    expect(turn!.suggestions, hasLength(1), reason: '未知 action 的建议必须被丢掉');
    expect(turn.suggestions.single.effectiveAction, 'meal.delete');
  });

  test('建议动作 ⊆ 注册表 ⊆ 能力矩阵声明集合（两侧文本扫描接起来）', () {
    // ① 注册表里的全部 action（与 C-1 用同一条字面量口径）。
    final registrySource = File(
      'lib/features/ai_conversation/domain/chat_edit/chat_edit_registry.dart',
    ).readAsStringSync();
    final registered = RegExp(r"action: '([a-zA-Z.]+)'")
        .allMatches(registrySource)
        .map((match) => match.group(1)!)
        .toSet();
    expect(registered, isNotEmpty, reason: '扫描前提：注册表扫得到 action');

    // ② C-1 能力矩阵的声明表（同一个仓库、同一个文件口径）。
    final matrixSource = File('test/app/ai_ui_capability_matrix_test.dart')
        .readAsStringSync();
    final declared = RegExp(r"'([a-zA-Z.]+)': Capability\.")
        .allMatches(matrixSource)
        .map((match) => match.group(1)!)
        .toSet();
    expect(declared, isNotEmpty, reason: '扫描前提：矩阵扫得到声明');

    // ③ 链条：每一条注册表命令都必须被矩阵声明过（否则 C-1 判据 1 也会红，
    //    这里额外把「建议通道」这一侧显式接上，改一边漏一边立刻可见）。
    final missing = registered.where((action) => !declared.contains(action));
    expect(
      missing,
      isEmpty,
      reason:
          '这些命令在注册表里、却不在能力矩阵声明集合里：${missing.join('、')}'
          '——建议按钮可能执行到一条「没人声明过 UI/ai-only 状态」的命令。',
    );
  });
}
