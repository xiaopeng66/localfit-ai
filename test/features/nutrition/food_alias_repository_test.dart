import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/text/search_text.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/food_category.dart';
import 'package:localfit_ai/features/nutrition/domain/food_record.dart';

/// 别名的写入/读取（ADR-037）：CSV 导入、手动新建、编辑三处共用同一套落库口径。
void main() {
  late AppDatabase database;
  late FoodRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = FoodRepository(
      database: database,
      idGenerator: _SeqIds(),
      clock: FixedAppClock(DateTime.utc(2026, 10, 21, 9)),
    );
  });

  tearDown(() => database.close());

  test('新建带别名：落库为归一化形态，读回按创建序', () async {
    final food = await repository.create(
      const NewFood(
        name: '西红柿',
        kcalPer100g: 20,
        proteinPer100g: 1,
        carbsPer100g: 4,
        fatPer100g: 0.2,
        category: FoodCategory.vegetable,
        aliases: ['番茄', ' 洋 柿子 ', '番茄'],
      ),
    );

    final aliases = await repository.aliasesFor(food.id);
    expect(aliases, ['番茄', '洋柿子'], reason: '归一化（去空白）+ 去重 + 保序');
    final rows = await database.select(database.foodAliases).get();
    expect(rows.every((row) => row.aliasType == 'manual'), isTrue);
    expect(rows.every((row) => row.source == 'user'), isTrue);
    expect(rows.every((row) => row.confidence == 1), isTrue);
  });

  test('别名与名称相同/为空：不落库（永远命中不了的别名不写）', () async {
    final food = await repository.create(
      const NewFood(
        name: '苹果',
        kcalPer100g: 53,
        proteinPer100g: 0.4,
        carbsPer100g: 14,
        fatPer100g: 0.2,
        category: FoodCategory.fruit,
        aliases: ['', '  ', '苹果'],
      ),
    );
    expect(await repository.aliasesFor(food.id), isEmpty);
  });

  test('编辑语义：null = 不动，[] = 清空，非空 = 替换', () async {
    final food = await repository.create(
      const NewFood(
        name: '土豆',
        kcalPer100g: 81,
        proteinPer100g: 2,
        carbsPer100g: 18,
        fatPer100g: 0.2,
        category: FoodCategory.staple,
        aliases: ['马铃薯'],
      ),
    );

    // null：只改营养，别名原样保留（AI 的 food.update 走这条）。
    await repository.update(
      food.id,
      const NewFood(
        name: '土豆',
        kcalPer100g: 82,
        proteinPer100g: 2,
        carbsPer100g: 18,
        fatPer100g: 0.2,
        category: FoodCategory.staple,
      ),
    );
    expect(await repository.aliasesFor(food.id), ['马铃薯']);

    // 非空：替换。
    await repository.update(
      food.id,
      const NewFood(
        name: '土豆',
        kcalPer100g: 82,
        proteinPer100g: 2,
        carbsPer100g: 18,
        fatPer100g: 0.2,
        category: FoodCategory.staple,
        aliases: ['洋芋'],
      ),
    );
    expect(await repository.aliasesFor(food.id), ['洋芋']);

    // 空列表：清空。
    await repository.update(
      food.id,
      const NewFood(
        name: '土豆',
        kcalPer100g: 82,
        proteinPer100g: 2,
        carbsPer100g: 18,
        fatPer100g: 0.2,
        category: FoodCategory.staple,
        aliases: [],
      ),
    );
    expect(await repository.aliasesFor(food.id), isEmpty);
  });

  test('删食物：别名随外键级联清掉（不留悬空别名）', () async {
    final food = await repository.create(
      const NewFood(
        name: '洋葱',
        kcalPer100g: 40,
        proteinPer100g: 1.1,
        carbsPer100g: 9,
        fatPer100g: 0.1,
        category: FoodCategory.vegetable,
        aliases: ['圆葱'],
      ),
    );
    expect(await repository.aliasesFor(food.id), ['圆葱']);
    await repository.delete(food.id);
    expect(await database.select(database.foodAliases).get(), isEmpty);
  });

  test('aliasesByFood：一次查询按 food 分组（导出用）', () async {
    final a = await repository.create(
      const NewFood(
        name: '红薯',
        kcalPer100g: 86,
        proteinPer100g: 1.6,
        carbsPer100g: 20,
        fatPer100g: 0.1,
        category: FoodCategory.staple,
        aliases: ['地瓜', '番薯'],
      ),
    );
    final b = await repository.create(
      const NewFood(
        name: '番茄',
        kcalPer100g: 20,
        proteinPer100g: 1,
        carbsPer100g: 4,
        fatPer100g: 0.2,
        category: FoodCategory.vegetable,
        aliases: ['西红柿'],
      ),
    );
    final grouped = await repository.aliasesByFood();
    expect(grouped[a.id], ['地瓜', '番薯']);
    expect(grouped[b.id], ['西红柿']);
  });

  test('归一化口径与检索侧同一函数（别名落库形状可直接命中）', () async {
    final food = await repository.create(
      const NewFood(
        name: 'ＡＢＣ酸奶',
        kcalPer100g: 60,
        proteinPer100g: 3,
        carbsPer100g: 8,
        fatPer100g: 2,
        category: FoodCategory.dairy,
        aliases: ['ＡＢＣ 优格'],
      ),
    );
    final aliases = await repository.aliasesFor(food.id);
    expect(aliases.single, normalizeSearchText('ABC 优格'));
    expect(aliases.single, 'abc优格');
  });
}

final class _SeqIds implements IdGenerator {
  var _next = 0;

  @override
  String next() {
    _next += 1;
    return 'id-$_next';
  }
}
