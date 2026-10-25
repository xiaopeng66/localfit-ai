import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/utils/food_display.dart';

/// 食物营养值的显示口径（docs/29 D14）与**审核台同源**约束（docs/29 §P8b-1）。
///
/// 这个文件守两件事：
///
/// 1. **口径本身**——热量那一格是事实判断（`null`/`0` ⇒ 没有），宏量三格是显示
///    约定（`null`/`0`/负值都写 `0g`，三格恒占位）。两条口径并存不冲突，理由见
///    `docs/21 §3.11` 与 `docs/07 §5.8` 的数据事实。
/// 2. **`food_display.dart` 必须保持「不 import Flutter」**——食物库人工审核台
///    的上屏预览由 `dart run tool/food_seed/review/export_display_preview.dart`
///    离线产出，而 `dart run` 装不下 Flutter 的渲染库（实测：导入任何 widget
///    文件都会在 `dart:ui` 上编译失败）。一旦有人往这里加 Flutter import，导出
///    脚本会**先坏掉**，而审核台就会退回「用别处的规则算一遍」——那正是 P8b-1
///    点名禁止的漂移（人审的会是一张并不存在的卡片）。
void main() {
  group('克数显示', () {
    test('整数不拖小数点，非整数保留一位', () {
      expect(formatMacroGrams(0), '0');
      expect(formatMacroGrams(12), '12');
      expect(formatMacroGrams(12.34), '12.3');
      expect(formatMacroGrams(0.5), '0.5');
    });
  });

  group('热量：事实判断（null 与 0 都当没有）', () {
    test('null / 0 / 负值 ⇒ 没有这一项', () {
      expect(kcalOrMissing(null), isNull);
      expect(kcalOrMissing(0), isNull);
      expect(kcalOrMissing(-1), isNull);
    });

    test('有值原样返回', () {
      expect(kcalOrMissing(116), 116);
      expect(kcalOrMissing(0.4), 0.4);
    });
  });

  group('宏量：显示约定（缺值与 0 都写 0g）', () {
    test('null / 0 / 负值 都折成 0', () {
      expect(macroGramsOnScreen(null), 0);
      expect(macroGramsOnScreen(0), 0);
      expect(macroGramsOnScreen(-3), 0);
    });

    test('有值原样返回', () {
      expect(macroGramsOnScreen(12.3), 12.3);
    });
  });

  group('上屏字符串（审核台预览读的就是这一份）', () {
    test('完整条目：环写数字、口径写单位、三格写克数', () {
      final s = foodDisplayStrings(
        name: '红烧牛肉面',
        brand: '康师傅',
        kcalPer100g: 450,
        proteinPer100g: 9,
        carbsPer100g: 60.5,
        fatPer100g: 18,
      );
      expect(s.name, '红烧牛肉面');
      expect(s.brand, '康师傅');
      expect(s.kcalText, '450');
      expect(s.kcalLabel, 'kcal/100g');
      expect(s.proteinText, '9g');
      expect(s.carbsText, '60.5g');
      expect(s.fatText, '18g');
    });

    test('热量缺失：环写 —、口径写事实，三格仍写 0g（两套口径并存）', () {
      final s = foodDisplayStrings(
        name: '零卡果冻',
        kcalPer100g: 0,
        proteinPer100g: 0,
        carbsPer100g: null,
        fatPer100g: 0,
      );
      expect(s.kcalText, '—');
      expect(s.kcalLabel, '无热量数据');
      expect(s.proteinText, '0g');
      expect(s.carbsText, '0g');
      expect(s.fatText, '0g');
    });

    test('品牌空白 / 空串 ⇒ null（卡上不画空 chip）', () {
      expect(foodDisplayStrings(name: '米饭', brand: '   ').brand, isNull);
      expect(foodDisplayStrings(name: '米饭', brand: '').brand, isNull);
      expect(foodDisplayStrings(name: '米饭', brand: null).brand, isNull);
      expect(foodDisplayStrings(name: '米饭', brand: ' 家乐 ').brand, '家乐');
    });

    test('导出成 JSON 的键与审核台预览一致（字段漂了就要一起改）', () {
      final json = foodDisplayStrings(name: '米饭', kcalPer100g: 116).toJson();
      expect(json.keys.toSet(), {
        'name',
        'brand',
        'kcal_text',
        'kcal_label',
        'protein_text',
        'carbs_text',
        'fat_text',
      });
    });
  });

  group('审核台同源约束', () {
    test('food_display.dart 不 import Flutter（否则 dart run 导出脚本会坏）', () {
      final source = _read('lib/utils/food_display.dart');
      // 只查**导入行**：文件头的说明里本来就写着「不许 import package:flutter」
      // 这句话，直接搜子串会把文档本身当成违规（第一版就是这么假红的）。
      final flutterImports = source
          .split('\n')
          .where((line) => line.trimLeft().startsWith('import '))
          .where((line) => line.contains('package:flutter'))
          .toList();
      expect(
        flutterImports,
        isEmpty,
        reason:
            'food_display.dart 一旦引入 Flutter，审核台的离线导出'
            '（tool/food_seed/review/export_display_preview.dart，用 `dart run` 跑）'
            '就编译不过——见本文件头的说明。显示口径只能留纯 Dart。'
            '违规行：$flutterImports',
      );
    });

    test('食物卡转发导出这些口径（调用点不必改导入路径）', () {
      final source = _read(
        'lib/features/nutrition/presentation/sections/food_card.dart',
      );
      expect(
        source.contains("export 'package:localfit_ai/utils/food_display.dart'"),
        isTrue,
        reason: '卡片与详情弹层共用的口径函数要能从 food_card.dart 取到（历史导入点）',
      );
      // 转发之后卡内不许再留一份实现（两份实现必然漂移）。
      expect(
        source.contains('double? kcalOrMissing(double? value) {'),
        isFalse,
      );
      expect(
        source.contains('double macroGramsOnScreen(double? value) =>'),
        isFalse,
      );
    });

    test('导出脚本声明的函数名与实际上屏路径一致', () {
      final source = _read('tool/food_seed/review/export_display_preview.dart');
      // 断言的是**声明块本身**，不是「这三个名字在文件里出现过」——第一版就是
      // 后者：`foodDisplayStrings` 在调用点也出现，于是把它从 `source_functions`
      // 里删掉照样绿（变异电池实测 SURVIVED）。声明是给账本对账用的，删掉它等于
      // 同源声明失效，必须红。
      final declared = RegExp(
        r"'source_functions': <String>\[(.*?)\]",
        dotAll: true,
      ).firstMatch(source)?.group(1);
      expect(
        declared,
        isNotNull,
        reason: '导出脚本必须声明 source_functions（账本与审核台据此对账同源）',
      );
      final names = RegExp(r"'([A-Za-z]+)'")
          .allMatches(declared ?? '')
          .map((match) => match.group(1))
          .toList();
      expect(names, [
        'splitFoodName',
        'normalizeFoodName',
        'foodDisplayStrings',
      ]);
      // 声明不许是装饰：这三个函数必须真的被调用。
      for (final name in names) {
        expect(
          RegExp('$name\\(').hasMatch(source),
          isTrue,
          reason: '导出脚本应真的调用 $name',
        );
      }
    });
  });
}

String _read(String relative) {
  final file = File(relative);
  expect(file.existsSync(), isTrue, reason: '$relative 不存在（路径变了？）');
  return file.readAsStringSync();
}
