@Tags(['interaction-gate'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// L2 · 重建层门禁（`docs/58` §2.3）：`ValueNotifier` 必须有监听者。
///
/// 直接防线是 `RV4-P1-02`：训练计划天数 `_days` 是 `ValueNotifier`，界面只读
/// `.value` 没有任何监听 —— 点「4 天」值变了、界面不重建，用户看到的仍是
/// 3 天选中，而请求按 4 天发。**值层测试（L1）抓不到这一层**，所以单列一条
/// 静态结构门禁。
///
/// 规则（每个 `ValueNotifier` 字段）：
/// 1. 存在 `ValueListenableBuilder` / `ListenableBuilder(listenable: …)` 指向它，
///    或 `.addListener(`；
/// 2. 至少有一处读 `.value`（只声明不读 = 死字段，同样不可接受）；
/// 3. 允许两跳别名：**同文件局部变量** `final x = notifier`，以及**构造器实参**
///    `param: notifier` → 目标文件里的 `this.param` 字段/形参。
///    别名解析**按文件限定**，不做全局名字匹配（否则 `days` 这类常用词会把
///    任何监听都算到它头上——首版就是这么误报的）。
///
/// 豁免：字段声明行加 `// interaction-gate: allow-unlistened <理由>`，
/// 且**豁免数冻结**（只减不增）。白名单不是第一选择——先把别名解析做对，
/// 只有真正无法静态判定时才登记。
void main() {
  final repoRoot = Directory.current.path.replaceAll(r'\', '/');
  final libFiles = <File>[
    for (final entity in Directory('$repoRoot/lib').listSync(recursive: true))
      if (entity is File &&
          entity.path.endsWith('.dart') &&
          !entity.path.endsWith('.g.dart'))
        entity,
  ];

  final texts = <String, String>{
    for (final file in libFiles)
      file.path.replaceAll(r'\', '/'): file.readAsStringSync(),
  };

  String relative(String path) => path.replaceFirst('$repoRoot/', '');

  /// 允许 `widget.` / `this.` 前缀与 `?` / `!` 后缀。
  /// **必须带尾部词边界**：否则 `days` 会命中 `daysPerWeek`（首版误报的第二个
  /// 来源，另一个是全局名字匹配）。
  String qualified(String name) =>
      r'(?:(?:widget|this)\s*\.\s*)?'
      '${RegExp.escape(name)}'
      r'\s*[?!]?(?![A-Za-z0-9_])';

  bool hasAddListener(String text, String name) => RegExp(
    r'\b'
    '${qualified(name)}'
    r'\s*\.\s*addListener\s*\(',
  ).hasMatch(text);

  bool hasBuilderReference(String text, String name) => RegExp(
    // 允许 `bootstrap.lastResult` 这类「持有者.字段」跨文件消费。
    r'(?:valueListenable|listenable)\s*:\s*[^,\n]*\b(?:[a-z_]\w*\s*\.\s*)?'
    '${qualified(name)}',
  ).hasMatch(text);

  bool hasValueRead(String text, String name) => RegExp(
    r'\b'
    '${qualified(name)}'
    r'\s*\.\s*value\b',
  ).hasMatch(text);

  bool listenedIn(String? file, String name) {
    final text = file == null ? null : texts[file];
    if (text == null) return false;
    return hasAddListener(text, name) || hasBuilderReference(text, name);
  }

  /// 公开字段（无 `_` 前缀）允许被其它文件以 `holder.name` 消费
  /// （`valueListenable: bootstrap.lastResult` 是文档里点名的正常跨文件用例）。
  bool listenedCrossFile(String name) {
    if (name.startsWith('_')) return false;
    final pattern = RegExp(
      r'(?:valueListenable|listenable)\s*:\s*[^,\n]*\b[a-z_]\w*\s*\.\s*'
      '${qualified(name)}',
    );
    return texts.values.any(pattern.hasMatch);
  }

  bool readIn(String? file, String name) {
    final text = file == null ? null : texts[file];
    if (text == null) return false;
    return hasValueRead(text, name);
  }

  /// 同文件局部别名：`final x = name;` / `final x = widget.name;`。
  Set<String> localAliases(String file, String name) {
    final text = texts[file];
    if (text == null) return const {};
    return RegExp(
      r'(?:final|var)\s+([A-Za-z_]\w*)\s*=\s*(?:(?:widget|this)\s*\.\s*)?'
      '${RegExp.escape(name)}'
      r'\b',
    ).allMatches(text).map((m) => m.group(1)!).toSet();
  }

  /// 构造器实参绑定：`param: name` → 目标文件里必须真有 `this.param`
  /// （说明 `param` 是该文件某个 widget 的构造器参数，而不是同名局部变量）。
  Set<(String, String)> constructorBindings(String file, String name) {
    final out = <(String, String)>{};
    final pattern = RegExp(
      r'\b([A-Za-z_]\w*)\s*:\s*(?:widget\s*\.\s*)?'
      '${RegExp.escape(name)}'
      r'\b',
    );
    for (final entry in texts.entries) {
      final targetFile = entry.key;
      final text = entry.value;
      for (final match in pattern.allMatches(text)) {
        final param = match.group(1)!;
        if (param == name) continue;
        // 目标文件（实参所在文件）必须把 param 声明成 `this.param`。
        if (!RegExp(
          r'\bthis\s*\.\s*'
          '${RegExp.escape(param)}'
          r'\b',
        ).hasMatch(text)) {
          continue;
        }
        out.add((targetFile, param));
      }
    }
    return out;
  }

  /// 广度优先遍历「字段 → 别名」图，任一节点被监听即算通过。
  bool reachableListener(String file, String name) {
    if (listenedCrossFile(name)) return true;
    final pending = <(String, String)>[(file, name)];
    final seen = <(String, String)>{(file, name)};
    while (pending.isNotEmpty) {
      final node = pending.removeLast();
      if (listenedIn(node.$1, node.$2)) return true;
      for (final alias in localAliases(node.$1, node.$2)) {
        if (seen.add((node.$1, alias))) pending.add((node.$1, alias));
      }
      for (final binding in constructorBindings(node.$1, node.$2)) {
        if (seen.add(binding)) pending.add(binding);
      }
    }
    return false;
  }

  bool reachableValueRead(String file, String name) {
    final pending = <(String, String)>[(file, name)];
    final seen = <(String, String)>{(file, name)};
    while (pending.isNotEmpty) {
      final node = pending.removeLast();
      if (readIn(node.$1, node.$2)) return true;
      for (final alias in localAliases(node.$1, node.$2)) {
        if (seen.add((node.$1, alias))) pending.add((node.$1, alias));
      }
      for (final binding in constructorBindings(node.$1, node.$2)) {
        if (seen.add(binding)) pending.add(binding);
      }
    }
    return false;
  }

  /// 字段声明：`late final ValueNotifier<T> name` / `final ValueNotifier<T>? name =`。
  final fieldPattern = RegExp(
    r'^\s*(?:late\s+)?final\s+Value(?:Notifier|Listenable)<[^;\n]*?>\??\s+([A-Za-z_]\w*)\s*[;=]',
    multiLine: true,
  );

  /// 只审**在本文件里被构造**的 notifier（`= ValueNotifier(...)`，或
  /// `late final` 后在 `initState` 里 `name = ValueNotifier(...)`）。
  /// 纯注入字段（`final ValueNotifier<int> days;` 由上层传入）不单独报——
  /// 它和上游是同一个对象，报了就是同一处缺陷算两次。
  bool constructedHere(String text, String name) => RegExp(
    r'(?:\b'
    '${RegExp.escape(name)}'
    r'\s*=\s*|\b'
    '${RegExp.escape(name)}'
    r'\s*;\s*\n[^;]*?)'
    r'ValueNotifier(?:<[^>]*>)?\s*\(',
  ).hasMatch(text);

  final offenders = <String>[];
  final allowlist = <String>[];

  for (final entry in texts.entries) {
    final file = entry.key;
    final lines = entry.value.split('\n');
    for (final match in fieldPattern.allMatches(entry.value)) {
      final name = match.group(1)!;
      final lineIndex =
          entry.value.substring(0, match.start).split('\n').length - 1;
      if (lines[lineIndex].contains('interaction-gate: allow-unlistened')) {
        allowlist.add('${relative(file)}:$name');
        continue;
      }
      if (!constructedHere(entry.value, name)) continue;
      final listened = reachableListener(file, name);
      final readsValue = reachableValueRead(file, name);
      if (!listened || !readsValue) {
        offenders.add(
          '${relative(file)}:$name'
          '（监听=${listened ? '有' : '无'}，读 value=${readsValue ? '有' : '无'}）',
        );
      }
    }
  }

  test('每个 ValueNotifier 都有监听者且至少读一次 .value（L2 重建层）', () {
    expect(
      offenders,
      isEmpty,
      reason:
          '这些 ValueNotifier 没有监听者（或从未读 .value）：\n'
          '${offenders.join('\n')}\n'
          '修法：同文件包 ValueListenableBuilder/ListenableBuilder，或让使用方 '
          'addListener；不要用 skip/反向断言绕过。',
    );
  });

  test('L2 豁免白名单只减不增（当前冻结 2 条）', () {
    // docs/58 §2.3：首次落地只允许两条「正常但静态不可判」的登记。
    expect(
      allowlist.length,
      lessThanOrEqualTo(2),
      reason: 'L2 豁免必须逐条写明理由且只减不增：${allowlist.join('、')}',
    );
  });
}
