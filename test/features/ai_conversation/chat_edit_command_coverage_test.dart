import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_registry.dart';

/// **命令三处一致 + 全量覆盖**（2026-10-24）。
///
/// 用户要求「确保 ai 能正确合理的调用**所有**功能」。这句话对代码的要求是：
/// 注册表里有的命令，执行器必须能接、测试必须覆盖——三处少一处，那条命令
/// 就是「AI 说了但 App 不会做」，正是用户抱怨的「只回复不操作」。
///
/// 现有 `chat_edit_executor_test.dart` 已经覆盖 37 条，但**没有任何断言
/// 钉住这个覆盖面**——以后新增一条命令、忘了补执行分支或测试，门禁照样全绿。
/// 本文件把那份隐性契约变成显性断言。
void main() {
  final registry = ChatEditCommandRegistry();
  final actions = [for (final spec in registry.specs) spec.action]..sort();

  test('命令注册表本身没有重复 action', () {
    expect(
      actions.toSet(),
      hasLength(actions.length),
      reason: '同一个 action 注册两次会让 specOf 静默取后者',
    );
  });

  test('执行器为每一条命令都写了分支（漏一条 = AI 说了 App 不会做）', () {
    final source = File(
      'lib/features/ai_conversation/application/chat_edit_executor.dart',
    ).readAsStringSync();
    final missing = [
      for (final action in actions)
        if (!source.contains("case '$action':")) action,
    ];
    expect(
      missing,
      isEmpty,
      reason:
          '这些命令在注册表里有、执行器里没有 case：$missing\n'
          '（AI 会照协议发出它们，执行器落到 default 就是「不支持」）',
    );
  });

  test('执行器里的 case 没有多余项（不许有孤儿分支）', () {
    final source = File(
      'lib/features/ai_conversation/application/chat_edit_executor.dart',
    ).readAsStringSync();
    final declared = RegExp(r"case '([a-z][a-z.]+)':")
        .allMatches(source)
        .map((m) => m.group(1)!)
        .toSet();
    final orphans = declared.difference(actions.toSet());
    expect(orphans, isEmpty, reason: '这些 case 在注册表里没有对应命令：$orphans（死分支）');
  });

  test('每条命令都有测试覆盖（executor 测试里出现过 action 字面量）', () {
    final source = File(
      'test/features/ai_conversation/application/chat_edit_executor_test.dart',
    ).readAsStringSync();
    final missing = [
      for (final action in actions)
        if (!source.contains("'$action'")) action,
    ];
    expect(
      missing,
      isEmpty,
      reason:
          '这些命令没有出现在执行器测试里：$missing\n'
          '（新增命令时请补一条「能执行 + 失败分支」的用例）',
    );
  });

  test('协议里渲染了每一条命令（模型才知道它存在）', () {
    final proto = registry.renderProtocol();
    final missing = [
      for (final action in actions)
        if (!proto.contains('- $action（')) action,
    ];
    expect(
      missing,
      isEmpty,
      reason: '这些命令没被 renderProtocol 渲染出来：$missing（模型看不见就不会用）',
    );
  });
}
