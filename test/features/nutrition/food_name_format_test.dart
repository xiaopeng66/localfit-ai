import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/features/nutrition/domain/food_name_format.dart';

/// 名称固定格式（ADR-037）的**语料判据**。
///
/// 语料由 `tool/food_catalog/normalize_food_library.py` 的 `normalize_name`
/// 生成（1,017 条：116 条真实需要改名的 + 900 条抽样 + 边界样例）——
/// 也就是说 Python 侧是规则的**单一事实源**，Dart 侧这个函数必须逐字复现它。
/// 两侧一旦漂移（改了一边没改另一边），这条测试先红。
void main() {
  test('格式函数与工具侧在同一套语料上逐字一致（1,017 条）', () {
    final cases = jsonDecode(
      File('test/fixtures/food_name_format_cases.json').readAsStringSync(),
    ) as List<dynamic>;
    expect(cases, hasLength(1017));
    final mismatches = <String>[];
    for (final entry in cases.cast<Map<String, dynamic>>()) {
      final raw = entry['raw'] as String;
      final expected = entry['expected'] as String;
      final actual = normalizeFoodNameFormat(raw);
      if (actual != expected) {
        mismatches.add('raw=「$raw」 expected=「$expected」 actual=「$actual」');
      }
    }
    expect(
      mismatches,
      isEmpty,
      reason: 'Dart 格式函数与 Python 工具的结果不一致：\n${mismatches.take(20).join('\n')}',
    );
  });

  test('固定格式的可读判据：括号在末尾、全角、备注用分号连接', () {
    expect(normalizeFoodNameFormat('鲫鱼-天津'), '鲫鱼（天津）');
    expect(
      normalizeFoodNameFormat('花生[落花生,长生果】14.10（鲜）'),
      '花生14.10（落花生；长生果；鲜）',
    );
    expect(normalizeFoodNameFormat('甲(乙)'), '甲（乙）');
    expect(normalizeFoodNameFormat('甲（乙）（丙）'), '甲（乙；丙）');
    expect(normalizeFoodNameFormat('红豆  薏米'), '红豆薏米');
    expect(normalizeFoodNameFormat('胡玉美"豆瓣酱'), '胡玉美豆瓣酱');
  });

  test('结构本来就坏的名称原样返回（不猜、不丢备注）', () {
    expect(normalizeFoodNameFormat('【咸烧白】（扣肉）'), '【咸烧白】（扣肉）');
    expect(normalizeFoodNameFormat('大巢菜野茗子,野豌豆】（鲜）'), '大巢菜野茗子,野豌豆】（鲜）');
    expect(normalizeFoodNameFormat('豆腐'), '豆腐');
    expect(normalizeFoodNameFormat(''), '');
  });

  test('已经是固定格式的名称幂等（重复归一化不再变化）', () {
    for (final name in [
      '豆腐（内酯豆腐）',
      '纯牛奶（全脂；广泽澳醇纯牛奶）',
      '苹果',
      '鲑鱼（三文鱼）',
      '莲藕（生）',
    ]) {
      // `RV4-P3-02`：`isNormalizedFoodName` 是死符号（生产零调用），
      // 随本批退役；判据（本身就是幂等）由 `normalizeFoodNameFormat` 直接钉住。
      expect(normalizeFoodNameFormat(name), name);
    }
  });
}
