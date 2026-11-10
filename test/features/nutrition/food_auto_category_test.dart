import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/food_category.dart';
import 'package:localfit_ai/features/nutrition/domain/food_record.dart';

/// 【2026-10-31 用户：「自定义食材自动加入食物库时也自动分类，不提示用户；
/// AI 生成的食物也要自动分类」】
///
/// 缺口的形状：`FoodRepository._row` 原来把 `category` 直接写成
/// `food.category?.id`——**调用方不传就留空**。手动新建食物的表单只有一个
/// 名称 + 四值，它不传种类；AI 生成食物走 `NewFood(name: ...)` 也不传种类。
/// 于是这两条最常用的写入口在食物库里全是「无分类」，用户按分类翻页时
/// 它们凭空消失。
///
/// 增补口径（不是新发明）：与 CSV 导入**同一张** `FoodCategory.classify`
/// 关键词表、**同一个**调用点（`food_csv_importer.dart:255`）。导入行早就
/// 是自动归类的，现在新建行与导入行对齐——同名食物不管从哪条路进来，
/// 落在同一类。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late FoodRepository foods;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    foods = FoodRepository(
      database: database,
      idGenerator: _Ids(),
      clock: FixedAppClock(DateTime.utc(2026, 10, 31, 9)),
    );
  });

  tearDown(() => database.close());

  NewFood food(String name, {FoodCategory? category}) => NewFood(
    name: name,
    kcalPer100g: 100,
    proteinPer100g: 1,
    carbsPer100g: 1,
    fatPer100g: 1,
    category: category,
  );

  test('手动新建（不传种类）：按名称自动落分类，不留空', () async {
    final rice = await foods.create(food('白米饭'));
    final chicken = await foods.create(food('鸡胸肉'));
    final apple = await foods.create(food('苹果'));

    expect(rice.category, FoodCategory.staple);
    expect(chicken.category, FoodCategory.protein);
    expect(apple.category, FoodCategory.fruit);
  });

  test('AI 生成的食物（同样不传种类）：也自动分类，与导入同口径', () async {
    // AI 建食物走的就是 `create(NewFood(...))`，没有单独的写入路径。
    final ai = await foods.create(food('清蒸鲈鱼'));
    expect(ai.category, FoodCategory.protein);

    // 同口径的证据：CSV 导入那条路对同名行给出的也是这一类。
    expect(
      FoodCategory.classify(name: '清蒸鲈鱼'),
      ai.category,
      reason: '新建与导入必须是同一张分类表，否则同名食物会落在两页里',
    );
  });

  test('调用方明确给了种类：原样尊重，不被名称归类覆盖', () async {
    final created = await foods.create(
      food('白米饭', category: FoodCategory.other),
    );
    expect(created.category, FoodCategory.other);
  });

  test('分类页能查到自动归类的自建食物（不再是「无分类」）', () async {
    await foods.create(food('白米饭'));
    final staples = await foods.page(
      offset: 0,
      limit: 50,
      category: FoodCategory.staple,
    );
    expect(staples.map((row) => row.name), contains('白米饭'));
  });
}

final class _Ids implements IdGenerator {
  int _value = 0;

  @override
  String next() => 'food-auto-${_value++}';
}
