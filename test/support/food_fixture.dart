// T13（docs/32 §4 T13 / §3 D13）之后测试用的食物夹具。
//
// 为什么不再导真种子：`FoodSeedImporter` 会在**每次全新安装的首启**解析 11 MB
// JSON 并插 49,444 行（2026-10-13 实测 842 ms；数据文件已归档到
// `../archive/food-seed-2026-10-13/`，不随包、不进仓库）。测试真正需要的只是
// 几条**确定的行**，所以这里给出六条**从真数据里原样取出**的行——id、名称、
// 四大指标逐字不差，既有断言（米饭 116 kcal / 蛋白 2.6g、鸡蛋 139 kcal、
// 搜「鸡」同时命中鸡胸肉与鸡蛋、内置行不可改删……）钉的还是同一批数字。
//
// 与退役导入器的口径一致：`source='seed-v5'`、`isUserCreated=false`（内置语义
// ⇒ 可搜、可被餐次引用、不可编辑删除），种类按 `FoodCategory.classify` 现算
// （与导入器当年写库的规则同源，不硬编码种类 id）。
//
// 忠实性记录：这六行的 id 就是它们在 v5 种子里的 id（米饭 `seed-fc-1`、
// 鸡蛋 `seed-fc-8769`、鸡胸肉 `seed-fc-8781`、豆腐 `seed-fc-13303`、
// 牛奶 `seed-fc-14545`、苹果 `seed-fc-14445`），所以「用户行与种子行 id 撞车」
// 这类断言仍能在同一 id 空间上成立。

import 'package:drift/drift.dart' show DoNothing, Value;
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/domain/food_category.dart';

/// 一条夹具食物（数值 = 真种子里那一行的 /100g 值）。
final class FoodFixtureRow {
  const FoodFixtureRow({
    required this.id,
    required this.name,
    required this.kcal,
    required this.protein,
    required this.carbs,
    required this.fat,
  });

  final String id;
  final String name;
  final double kcal;
  final double protein;
  final double carbs;
  final double fat;
}

/// 六条确定性夹具行（覆盖测试用到的全部名字与两个被断言过的热量）。
const List<FoodFixtureRow> kFoodFixtureRows = [
  FoodFixtureRow(
    id: 'seed-fc-1',
    name: '米饭',
    kcal: 116,
    protein: 2.6,
    carbs: 25.9,
    fat: 0.3,
  ),
  FoodFixtureRow(
    id: 'seed-fc-8769',
    name: '鸡蛋',
    kcal: 139,
    protein: 13.1,
    carbs: 2.4,
    fat: 8.6,
  ),
  FoodFixtureRow(
    id: 'seed-fc-8781',
    name: '鸡胸肉',
    kcal: 118,
    protein: 24.6,
    carbs: 0.6,
    fat: 1.9,
  ),
  FoodFixtureRow(
    id: 'seed-fc-13303',
    name: '豆腐',
    kcal: 84,
    protein: 6.6,
    carbs: 3.4,
    fat: 5.3,
  ),
  FoodFixtureRow(
    id: 'seed-fc-14545',
    name: '牛奶',
    kcal: 66,
    protein: 3.0,
    carbs: 5.0,
    fat: 3.8,
  ),
  FoodFixtureRow(
    id: 'seed-fc-14445',
    name: '苹果',
    kcal: 53,
    protein: 0.4,
    carbs: 13.7,
    fat: 0.2,
  ),
];

/// 把夹具行写进库（重复调用安全：撞 id 就跳过，旧导入器的幂等语义）。
Future<void> seedFoodFixture(AppDatabase database) async {
  final now = DateTime.utc(2026, 10, 13);
  await database.batch((batch) {
    for (final row in kFoodFixtureRows) {
      batch.insert(
        database.foods,
        FoodsCompanion.insert(
          id: row.id,
          name: row.name,
          defaultServingGrams: const Value(100),
          kcalPer100g: row.kcal,
          proteinPer100g: row.protein,
          carbsPer100g: row.carbs,
          fatPer100g: row.fat,
          category: Value(FoodCategory.classify(name: row.name).id),
          source: 'seed-v5',
          createdAt: now,
          updatedAt: now,
        ),
        onConflict: DoNothing(),
      );
    }
  });
}
