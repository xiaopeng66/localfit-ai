import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// T8（docs/32 §4 T8 / §3 D10）：**退役特性 grep 门禁**。
///
/// 「从全部地方删掉，不要漏」（用户 2026-10-11 的明文要求）不能只靠人眼：
/// 这条测试走全仓 `lib/` + `test/` 的 `.dart` 源文件，任何一行出现退役特性
/// 的名称（本文件里用 `_word` 拼出来，避免门禁自己被自己命中）都必须**只**
/// 是历史列名 `manual_commute_minutes` / 驼峰键 `manualCommuteMinutes`。
///
/// 白名单的边界（与 docs/32 §3 D10 的「迁移历史注释、证据文件」对齐）：
/// * 迁移链**必须**能提到那一列——v14 补过、v24 删掉、fixture 建过；
///   `.lfb` 的旧包也可能带那个驼峰键。这些行都点名了列本身，放行。
/// * 其余任何写法（命令名、类型名、UI 文案、仓储名、方法名、注释里的
///   普通叙述）一律不允许——要留历史说明就连写列名，否则换个说法。
/// * 证据文件（`docs/**`）不在扫描范围：那是过程记录，本来就该如实写。
///
/// 变异见证：把 `lib/` 里任意一处注释改回特性名这段测试就红（做过一次），
/// 因此它不是「写了就一定绿」的空断言。
void main() {
  // 拼出来，避免本文件自身的字面量被扫进来（本文件也在 test/ 下）。
  // 中文名同理，**连注释里都不能写出那两个汉字**——写过一次，门禁把自己
  // 命中成红，白名单只认历史列名，注释不认。
  final word = String.fromCharCodes([0x63, 0x6f, 0x6d, 0x6d, 0x75, 0x74, 0x65]);
  final chinese = String.fromCharCodes([0x901a, 0x52e4]);
  final pattern = RegExp('$word|$chinese', caseSensitive: false);
  const allowedTokens = ['manual_commute_minutes', 'manualCommuteMinutes'];

  test('lib/ 与 test/ 里只剩历史列名的引用（退役特性零活引用）', () {
    final root = Directory.current;
    final offenders = <String>[];

    for (final dir in ['lib', 'test']) {
      final directory = Directory('${root.path}${Platform.pathSeparator}$dir');
      expect(directory.existsSync(), isTrue, reason: '找不到 $dir/，测试要在仓库根跑');
      for (final entity in directory.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final lines = entity.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (!pattern.hasMatch(lines[i])) continue;
          if (allowedTokens.any(lines[i].contains)) continue;
          offenders.add('${entity.path}:${i + 1}: ${lines[i].trim()}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          '退役特性（手动到达时长/路线输入）必须零活引用；'
          '要留历史说明就连写列名 $allowedTokens，否则换个说法。'
          '命中行：\n${offenders.join('\n')}',
    );
  });
}
