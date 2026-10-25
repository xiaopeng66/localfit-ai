import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// docs/21 §5 的「测试 Key」是**可测试性契约**：规范写了、页面上却没有，
/// 视觉断言就无处落地；页面加了、规范没记，契约就悄悄腐烂。这份测试把
/// 「doc §5 Key 表 ⇄ lib ⇄ test」三方做成**机械对账**，不再靠人工记。
///
/// 与 Python 版对账脚本（tmp/i4_key_audit3.py）同口径：
/// - doc 取两类行：① 含「测试 Key」的罗列行（§5 与附录 D10 的批量行）；
///   ② **附录 D 表格的 Key 列**（首个单元格以反引号开头）——2026-10-22 补：
///   此前只认「测试 Key」字样，D1–D9 的表格行整段漏扫，导致 6 个 Key
///   长期有 UI 无断言（`docs/52` RV2-P2-07）。
/// - 跳过引用块（`>`）与命名约定说明行。
/// - lib/test 两侧收集 `Key('x')` / `ValueKey('x')`、插值字面量的字面前后缀
///   （`Key('$prefix-a')` / `Key('a-$index')`），以及 kebab-case 纯字符串常量。
/// - doc 里的占位 Key（`nutrition-menu-dish-card-<n>`、`meal-grams-item-N`）只要
///   有一例具体编号（`card-5`）或前缀拼接命中即算覆盖。
/// - Key 列里的简写（`-archive-<id>` / `-keyword`）按同一单元格内最长连字符
///   前缀补全；`a/b/c` 合并写法按前缀补全后逐个入账。
///
/// 防「空转绿」：对账读不到文档、或解析出的 Key 数掉到阈值以下，直接判失败
/// ——正则写坏导致 0 个 Key 时，缺口列表也是空的，必须另有哨兵钉住这一点。
void main() {
  final repoRoot = Directory.current.path.replaceAll(r'\', '/');
  final docPath = '$repoRoot/docs/21-ui-redesign-spec.md';

  /// 本文件自身会引入 Key 字面量（正则模式串），扫描 test/ 时要跳过，
  /// 否则「doc → test」这条缺口会被自己的模式串填平。
  const selfFileName = 'ui_spec_key_sync_test.dart';

  test('docs/21 §5 + 附录 D Key 表与 lib/test 三方对账无缺口', () {
    final docFile = File(docPath);
    expect(
      docFile.existsSync(),
      isTrue,
      reason: '找不到规范文档：$docPath（路径变更或文档被删要有明确失败）',
    );

    final lines = docFile.readAsLinesSync();
    final docKeys = _docKeys(lines);
    // 哨兵：此刻 §5 + 附录 D 记了 200+ 个 Key。解析器退化（例如文档改成
    // 表格、正则失配）会让 Key 数骤降甚至归零，而缺口列表照样是空的——
    // 必须显式钉住量级。
    expect(
      docKeys.length,
      greaterThan(150),
      reason: 'docs/21 只解析出 ${docKeys.length} 个 Key，疑为解析器失配',
    );
    // 附录 D 表格必须真的被扫到：这几条只出现在 D 表格的 Key 列里。
    for (final anchor in const [
      'meal-entry-chooser',
      'canteen-dish-manual-nutrition',
      'ai-memory-promote-delete',
      'retrieval-debug-close',
      'training-retry',
    ]) {
      expect(
        docKeys,
        contains(anchor),
        reason: '附录 D 表格未被扫描（缺 $anchor）：Key 列解析器退化',
      );
    }

    final libPool = _scanDirectory(Directory('$repoRoot/lib'));
    final testPool = _scanDirectory(
      Directory('$repoRoot/test'),
      skipFileName: selfFileName,
    );

    final missingInLib = docKeys.where((k) => !_matches(k, libPool)).toList();
    final missingInTest = docKeys
        .where((k) => _matches(k, libPool) && !_matches(k, testPool))
        .toList();

    expect(
      missingInLib,
      isEmpty,
      reason: 'docs/21 点名但 lib 里找不到的 Key：${missingInLib.join('、')}',
    );
    expect(
      missingInTest,
      isEmpty,
      reason:
          'docs/21 有、lib 有、但没有任何测试断言的 Key：'
          '${missingInTest.join('、')}',
    );
  });
}

/// Key 形状：小写 kebab（≥1 个连字符）；任意段可以是 `<占位>`；
/// `-N` 归一化为 `-<n>`。
final _keyShape = RegExp(r'^[a-z][a-z0-9]*(?:-[a-z0-9]+|<\w+>)+$');

/// doc 侧：§5/D10 的「测试 Key」罗列行 + 附录 D 表格的 Key 列。
List<String> _docKeys(List<String> lines) {
  final out = <String>[];
  final seen = <String>{};
  final pattern = RegExp(r'`([a-z0-9][a-z0-9<>\-${}.\[\]]*)`');

  void add(String key) {
    if (seen.add(key)) out.add(key);
  }

  var inAppendix = false;
  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.startsWith('## ')) {
      inAppendix = trimmed.startsWith('## 附录 D');
    }
    if (trimmed.startsWith('>') || trimmed.startsWith('**Key 命名约定**')) {
      continue;
    }

    if (line.contains('测试 Key')) {
      for (final m in pattern.allMatches(line)) {
        final key = m.group(1)!;
        if (key == 'testWidgets') continue;
        add(key);
      }
      continue;
    }

    // 附录 D 的表格：只认**首个单元格**（Key 列）。表头 `| Key | … |`
    // 没有反引号，天然跳过；行为列里的类名/方法名/字面量一律不入账。
    if (inAppendix && trimmed.startsWith('|')) {
      final firstCell = trimmed.split('|')[1];
      if (!firstCell.contains('`')) continue;
      for (final key in _cellKeys(firstCell)) {
        add(key);
      }
    }
  }
  return out;
}

/// 一个 Key 单元格里的全部 Key：处理 `/` 合并写法与 `-xxx` 简写补全。
List<String> _cellKeys(String cell) {
  final raw = [
    for (final m in RegExp(r'`([^`]+)`').allMatches(cell)) m.group(1)!,
  ];
  final normalized = <String>[];
  for (final token in raw) {
    for (var part in token.split('/')) {
      part = part.trim();
      if (part.isEmpty) continue;
      // `manual-nutrition-kcal/protein/carbs/fat`：后续裸词继承前缀。
      if (!part.contains('-')) {
        final first = normalized.isEmpty ? null : normalized.first;
        if (first != null) {
          final cut = first.lastIndexOf('-');
          if (cut > 0) part = '${first.substring(0, cut)}-$part';
        }
      }
      normalized.add(part);
    }
  }
  // `-archive-<id>` 这类简写按本单元格推导出的前缀补全。
  final full = [
    for (final token in normalized)
      if (!token.startsWith('-')) token,
  ];
  final prefix = _shorthandBase(full);
  final out = <String>[];
  for (final token in normalized) {
    var key = token.startsWith('-') && prefix != null ? '$prefix$token' : token;
    // `meal-grams-item-N` ⇒ `meal-grams-item-<n>`（N 是编号占位）。
    key = key.replaceFirst(RegExp(r'-N$'), '-<n>');
    if (_keyShape.hasMatch(key)) out.add(key);
  }
  return out;
}

/// 多个 Key 的「简写依附前缀」：
/// - 有两个以上完整 Key ⇒ 它们的**最长连字符公共前缀**；
/// - 只有一个完整 Key ⇒ 去掉它最后一段（`ai-memory-hygiene-merge-<id>`
///   ⇒ `ai-memory-hygiene`，于是 `-archive-<id>` 读作 archive 那一支）；
/// - 没有完整 Key ⇒ null（宁可漏也不猜）。
String? _shorthandBase(List<String> keys) {
  if (keys.isEmpty) return null;
  if (keys.length == 1) {
    final segments = keys.single.split('-');
    if (segments.length < 3) return null;
    return segments.take(segments.length - 1).join('-');
  }
  final segments = [for (final key in keys) key.split('-')];
  final first = segments.first;
  var end = 0;
  outer:
  for (var i = 0; i < first.length - 1; i++) {
    for (final s in segments.skip(1)) {
      if (i >= s.length - 1 || s[i] != first[i]) break outer;
    }
    end = i + 1;
  }
  return end == 0 ? null : first.take(end).join('-');
}

class _Pool {
  _Pool(this.exact, this.prefixes, this.suffixes);

  final Set<String> exact;
  final Set<String> prefixes;
  final Set<String> suffixes;
}

_Pool _scanDirectory(Directory root, {String? skipFileName}) {
  final exact = <String>{};
  final prefixes = <String>{};
  final suffixes = <String>{};
  final keyCall = RegExp(r"(?:Key|ValueKey)\(\s*'([^']*)'");
  final dynVar = RegExp(r'\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?');
  final kebab = RegExp(r"'([a-z][a-z0-9]*(?:-[a-z0-9]+)+)'");

  for (final entity in root.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    if (skipFileName != null && entity.uri.pathSegments.last == skipFileName) {
      continue;
    }
    final text = entity.readAsStringSync();

    for (final m in keyCall.allMatches(text)) {
      final literal = m.group(1)!;
      if (!literal.contains(r'$')) {
        exact.add(literal);
        continue;
      }
      final dynamicVar = dynVar.firstMatch(literal);
      if (dynamicVar == null) {
        final pre = literal.split(r'$').first;
        if (pre.isNotEmpty) prefixes.add(pre);
        continue;
      }
      final pre = literal.substring(0, dynamicVar.start);
      final suf = literal.substring(dynamicVar.end);
      if (pre.isNotEmpty) prefixes.add(pre);
      if (suf.isNotEmpty) suffixes.add(suf);
    }
    for (final m in kebab.allMatches(text)) {
      exact.add(m.group(1)!);
    }
  }
  return _Pool(exact, prefixes, suffixes);
}

bool _matches(String key, _Pool pool) {
  if (pool.exact.contains(key)) return true;
  if (key.contains('<')) {
    final base = key.split('<').first;
    return pool.exact.any((e) => e.startsWith(base)) ||
        pool.prefixes.any((p) => p.startsWith(base) || base.startsWith(p));
  }
  return pool.prefixes.any(key.startsWith) || pool.suffixes.any(key.endsWith);
}
