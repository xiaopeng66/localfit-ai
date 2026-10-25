@Tags(['interaction-gate'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// L4 · 可测性层门禁（`docs/58` §2.5）：可交互控件必须有稳定 Key。
///
/// 不要求一次补齐（会牵动大量测试），而是**冻结预算 + 只减不增**：新增交互
/// 控件必须带 Key，否则这条会红。
///
/// **计数口径（可复现，改口径前先改这份文档）**：
/// - 范围：`lib/features/**`（业务页面）；设计系统件与路由层不在内。
/// - 类型：Flutter 裸交互件 `TextButton` / `InkWell` / `IconButton` /
///   `GestureDetector` / `FilledButton` / `ElevatedButton` / `OutlinedButton`。
/// - 判定：**该次调用的实参列表里没有 `key:`** 即算「缺 Key」。外层 widget
///   上的 `Key('x')` 不算（测试点不到内层可点件，就还是测不了）。
///
/// 【与 `docs/58` §2.5 的差异，如实记录】计划里写「175 处裸控件 / 38 处缺
/// Key（TextButton 21 / InkWell 12 / IconButton 3 / GestureDetector 2）」。
/// 那个数字是把 `LfTextButton(` 之类的**设计系统件**也算成了裸 `TextButton(`
/// （子串匹配），而它们通过 `_innerKey` 本来就接 Key。按上面这个**更严格、
/// 可复现**的口径，落地时实测是 **9 处**（InkWell 8 / GestureDetector 1），
/// 预算按实测冻结——比 38 更紧，不是放宽。`docs/21` 会同步这个口径。
void main() {
  final repoRoot = Directory.current.path.replaceAll(r'\', '/');

  /// B1 落地实测：9 处（InkWell 8 / GestureDetector 1）。**只许往下改。**
  const unkeyedBudget = 9;

  const interactiveTypes = [
    'TextButton',
    'InkWell',
    'IconButton',
    'GestureDetector',
    'FilledButton',
    'ElevatedButton',
    'OutlinedButton',
  ];

  /// 从 `(` 起配平括号取实参文本（跳过字符串里的括号）。
  String argsOf(String text, int openParen) {
    var depth = 0;
    for (var i = openParen; i < text.length; i++) {
      final c = text[i];
      if (c == '(') {
        depth++;
      } else if (c == ')') {
        depth--;
        if (depth == 0) return text.substring(openParen + 1, i);
      } else if (c == "'" || c == '"') {
        final quote = c;
        i++;
        while (i < text.length && text[i] != quote) {
          if (text[i] == r'\') i++;
          i++;
        }
      }
    }
    return text.substring(openParen + 1);
  }

  /// `{ file: [行号…] }`，只收缺 Key 的实例。
  Map<String, List<int>> unkeyedInstances() {
    final found = <String, List<int>>{};
    for (final entity in Directory(
      '$repoRoot/lib/features',
    ).listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.endsWith('.g.dart')) continue;
      final text = entity.readAsStringSync();
      final relative = entity.path
          .replaceAll(r'\', '/')
          .replaceFirst('$repoRoot/', '');
      for (final type in interactiveTypes) {
        // 前置不能是标识符字符或 `.`：排除 `LfTextButton(` / `foo.TextButton(`。
        final pattern = RegExp(
          r'(?<![\w.])' + type + r'\s*\(',
          multiLine: true,
        );
        for (final match in pattern.allMatches(text)) {
          final args = argsOf(text, match.end - 1);
          if (RegExp(r'\bkey\s*:').hasMatch(args)) continue;
          final line = text.substring(0, match.start).split('\n').length;
          found.putIfAbsent(relative, () => []).add(line);
        }
      }
    }
    for (final lines in found.values) {
      lines.sort();
    }
    return found;
  }

  test('lib/features 下缺 Key 的可交互控件数只减不增（预算 $unkeyedBudget）', () {
    final actual = unkeyedInstances();
    final total = actual.values.fold<int>(
      0,
      (sum, lines) => sum + lines.length,
    );
    final detail = [
      for (final entry in actual.entries)
        '${entry.key}:${entry.value.join(',')}',
    ].join('\n');
    expect(
      total,
      lessThanOrEqualTo(unkeyedBudget),
      reason:
          '缺 Key 的可交互控件 $total 处 > 预算 $unkeyedBudget。'
          '新增/改动的交互控件必须带 Key（否则测试点不到）：\n$detail',
    );
  });

  test('本批必须有的稳定 Key 已落位（新增面清单）', () {
    // docs/58 §2.5：本批新增/改动的控件强制带 Key。训练页天数胶囊是循环生成
    // 的（`Key('plan-days-$d')`），所以只钉**模式存在**；逐枚 `plan-days-1..7`
    // 的实际在位由 L1（`control_state_changes_test.dart`）on-widget 断言，
    // 不在本层用字符串重复一遍（那样改了实现这一层会假绿）。
    final training = File(
      '$repoRoot/lib/features/training/presentation/workout_plan_create_page.dart',
    ).readAsStringSync();
    expect(
      training.contains(r"Key('plan-days-$d')"),
      isTrue,
      reason: '训练页天数胶囊必须有稳定 Key 模式 plan-days-<N>',
    );
    expect(
      training.contains('plan-goal-keyword-'),
      isTrue,
      reason: '目标关键词胶囊必须有 Key 前缀 plan-goal-keyword-',
    );
  });
}
