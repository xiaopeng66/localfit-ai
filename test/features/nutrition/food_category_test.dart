import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/features/nutrition/domain/food_category.dart';

void main() {
  test(
    'classifies catalog and uncategorized foods into stable display groups',
    () {
      const cases = <({String name, String? raw, FoodCategory expected})>[
        (name: '蒸米饭', raw: null, expected: FoodCategory.staple),
        (name: '鸡胸肉', raw: null, expected: FoodCategory.protein),
        (
          name: '三文鱼',
          raw: 'Produits de la mer',
          expected: FoodCategory.protein,
        ),
        (name: '西兰花', raw: null, expected: FoodCategory.vegetable),
        (name: '苹果', raw: null, expected: FoodCategory.fruit),
        (name: '原味酸奶', raw: 'Dairies', expected: FoodCategory.dairy),
        (name: '无糖可乐', raw: 'Beverages', expected: FoodCategory.beverage),
        (name: '海盐薯片', raw: 'Snacks', expected: FoodCategory.snack),
        (name: '低盐酱油', raw: 'Condiments', expected: FoodCategory.condiment),
        (name: '速冻披萨', raw: 'Plats préparés', expected: FoodCategory.prepared),
        // 2026-10-22（隔离变异 M02 抓到）：上面那条走的是**名称**关键词
        //（'Plats préparés' 匹配不到 'plat préparé'，单复数不同），
        // 所以分类关键词里的 prepared 分支一直没被覆盖。补一条真正命中
        // `_preparedCategoryKeywords` 的用例。
        (name: '冷冻什锦', raw: 'Frozen foods', expected: FoodCategory.prepared),
        (name: '火腿三明治', raw: 'Sandwiches', expected: FoodCategory.prepared),
        (name: '神秘配方', raw: null, expected: FoodCategory.other),
      ];

      for (final entry in cases) {
        expect(
          FoodCategory.classify(name: entry.name, rawCategory: entry.raw),
          entry.expected,
          reason: '${entry.name} / ${entry.raw}',
        );
      }
    },
  );

  test('every category exposes a local SVG asset and a visible label', () {
    for (final category in FoodCategory.values) {
      expect(category.label.trim(), isNotEmpty);
      expect(category.assetPath, startsWith('assets/icons/food_categories/'));
      expect(category.assetPath, endsWith('.svg'));
    }
  });
}
