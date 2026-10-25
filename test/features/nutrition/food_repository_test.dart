// 只取 Value：`drift/drift.dart` 也导出 `isNull`/`isNotNull`，与 matcher 撞名。
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/food_category.dart';
import 'package:localfit_ai/features/nutrition/domain/food_record.dart';
import 'package:localfit_ai/features/nutrition/domain/food_write_failure.dart';

import '../../support/food_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase database;
  late FoodRepository repository;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await seedFoodFixture(database);
    repository = FoodRepository(
      database: database,
      idGenerator: _FixedIdGenerator(),
      clock: FixedAppClock(DateTime.utc(2026, 9, 9)),
    );
  });

  tearDown(() => database.close());

  test('searches seed foods by local name', () async {
    final results = await repository.search('鸡');

    expect(results.map((food) => food.name), containsAll(['鸡胸肉', '鸡蛋']));
  });

  test('creates a user food and ranks it before seed results', () async {
    await repository.create(
      const NewFood(
        name: '我的鸡胸饭',
        defaultServingGrams: 250,
        kcalPer100g: 130,
        proteinPer100g: 12,
        carbsPer100g: 15,
        fatPer100g: 2,
      ),
    );

    final results = await repository.search('鸡');
    expect(results.first.name, '我的鸡胸饭');
    expect(results.first.isUserCreated, isTrue);
  });

  test('matches names containing LIKE wildcards as literal text', () async {
    // SQLite 的 LIKE 没有默认转义符，缺 ESCAPE 子句时含 % 的名称
    // 永远匹配不到（回归：搜「100%果汁」零结果）。
    await repository.create(
      const NewFood(
        name: '100%果汁',
        kcalPer100g: 45,
        proteinPer100g: 0.4,
        carbsPer100g: 10.6,
        fatPer100g: 0.1,
      ),
    );

    final percent = await repository.search('%果汁');
    expect(percent.map((food) => food.name), contains('100%果汁'));

    // 通配符不再代表「任意串」：搜 % 只命中名字里真有 % 的条目。
    final onlyPercent = await repository.search('%');
    expect(onlyPercent.map((food) => food.name), everyElement(contains('%')));
  });

  test('matches underscores in names as literal text', () async {
    await repository.create(
      const NewFood(
        name: '低GI_燕麦片',
        kcalPer100g: 370,
        proteinPer100g: 13,
        carbsPer100g: 60,
        fatPer100g: 7,
      ),
    );

    final underscore = await repository.search('GI_燕麦');
    expect(underscore.map((food) => food.name), contains('低GI_燕麦片'));
  });

  test('自建食物的品牌与四大指标照常落库（约束事实已随 schema 22 删除）', () async {
    // 2026-10-09（docs/31 S2，需求 50）改口径：原用例叫「persists declared
    // facts」，断的是饮食标签与过敏原落库。那三个列与 `FoodConstraintFacts`
    // 整体已删除 ⇒ 现在能断的是**剩下的字段照常往返**，以及
    // **「约束事实」这个概念在食物侧已经没有载体**（列不存在）。
    final created = await repository.create(
      const NewFood(
        name: '我的豆腐',
        brand: '本地作坊',
        kcalPer100g: 116,
        proteinPer100g: 12.2,
        carbsPer100g: 3,
        fatPer100g: 6.5,
      ),
    );

    final actual = (await repository.search('我的豆腐')).single;
    expect(created.id, actual.id);
    expect(actual.name, '我的豆腐');
    expect(actual.brand, '本地作坊');
    expect(actual.kcalPer100g, 116);
    expect(actual.proteinPer100g, 12.2);
    expect(actual.carbsPer100g, 3);
    expect(actual.fatPer100g, 6.5);
    expect(actual.isUserCreated, isTrue);

    // 三个约束列物理上不在表里 —— 这是「删干净」的机器判据。
    final columns = await database
        .customSelect('PRAGMA table_info(foods)')
        .get();
    final names = columns.map((row) => row.data['name']).toList();
    expect(names, isNot(contains('constraint_knowledge')));
    expect(names, isNot(contains('dietary_labels_json')));
    expect(names, isNot(contains('allergens_json')));
  });

  test('种类的落库与回读；种子行已按名字回填（docs/31 S5 需求 51/53）', () async {
    final created = await repository.create(
      const NewFood(
        name: '我的酸奶碗',
        kcalPer100g: 90,
        proteinPer100g: 3.2,
        carbsPer100g: 12,
        fatPer100g: 2.5,
        category: FoodCategory.dairy,
      ),
    );

    // 回读是枚举。
    final actual = await repository.getById(created.id);
    expect(actual?.category, FoodCategory.dairy);
    // 底层列是枚举 id 文本——大库/CSV 往返的载体。
    final row = await (database.select(
      database.foods,
    )..where((food) => food.id.equals(created.id))).getSingle();
    expect(row.category, 'dairy');

    // update 带种类一起写。
    final updated = await repository.update(
      created.id,
      const NewFood(
        name: '我的酸奶碗',
        kcalPer100g: 95,
        proteinPer100g: 3.4,
        carbsPer100g: 12.5,
        fatPer100g: 2.6,
        category: FoodCategory.snack,
      ),
    );
    expect(updated.category, FoodCategory.snack);

    // 种子行（setUp 里 importIfNeeded 导入 + 回填）能按名字归到枚举。
    final egg = (await repository.searchExact('鸡蛋')).first;
    expect(egg.category, FoodCategory.protein);
  });

  test('rejects impossible nutrition values', () async {
    await expectLater(
      repository.create(
        const NewFood(
          name: '无效食物',
          kcalPer100g: 1200,
          proteinPer100g: 0,
          carbsPer100g: 0,
          fatPer100g: 0,
        ),
      ),
      throwsFormatException,
    );
  });

  test('update 只改自建条目，内置条目给固定文案', () async {
    // 内置（随包种子）：控件层不给入口，数据层也要挡。
    final seed = (await repository.search('鸡蛋')).first;
    expect(seed.isUserCreated, isFalse);
    await expectLater(
      repository.update(
        seed.id,
        const NewFood(
          name: '鸡蛋',
          kcalPer100g: 150,
          proteinPer100g: 13,
          carbsPer100g: 1,
          fatPer100g: 10,
        ),
      ),
      throwsA(
        isA<FoodWriteFailure>().having(
          (failure) => failure.message,
          'message',
          '内置食物不能修改或删除。',
        ),
      ),
    );

    // 自建：改得动，且改完能读回来。
    final created = await repository.create(
      const NewFood(
        name: '我的豆腐',
        kcalPer100g: 116,
        proteinPer100g: 12.2,
        carbsPer100g: 3,
        fatPer100g: 6.5,
      ),
    );
    final updated = await repository.update(
      created.id,
      const NewFood(
        name: '(Beretta) 我的豆腐',
        brand: 'Beretta',
        kcalPer100g: 130,
        proteinPer100g: 14,
        carbsPer100g: 4,
        fatPer100g: 7,
      ),
    );
    // ADR-037：写入口统一名称格式——品牌前缀在括号里时移到名称末尾。
    expect(updated.name, '我的豆腐（Beretta）');
    expect(updated.brand, 'Beretta');
    expect(updated.kcalPer100g, 130);
    final reread = await repository.getById(created.id);
    expect(reread?.kcalPer100g, 130);
    expect(reread?.isUserCreated, isTrue);
  });

  test('update 不碰「默认份量」：编辑弹层不再收集它，旧值必须留着', () async {
    final created = await repository.create(
      const NewFood(
        name: '我的鸡胸饭',
        defaultServingGrams: 250,
        kcalPer100g: 130,
        proteinPer100g: 12,
        carbsPer100g: 15,
        fatPer100g: 2,
      ),
    );
    expect(created.defaultServingGrams, 250);

    // 表单这次没带份量（N9 之后弹层里根本没有这一格）——不能因此写 null。
    await repository.update(
      created.id,
      const NewFood(
        name: '我的鸡胸饭',
        kcalPer100g: 140,
        proteinPer100g: 13,
        carbsPer100g: 16,
        fatPer100g: 2,
      ),
    );
    final reread = await repository.getById(created.id);
    expect(reread?.kcalPer100g, 140);
    expect(reread?.defaultServingGrams, 250);
  });

  test('delete 拒绝内置条目，删掉自建条目后搜索不到', () async {
    final seed = (await repository.search('鸡蛋')).first;
    await expectLater(
      repository.delete(seed.id),
      throwsA(
        isA<FoodWriteFailure>().having(
          (failure) => failure.message,
          'message',
          '内置食物不能修改或删除。',
        ),
      ),
    );

    final created = await repository.create(
      const NewFood(
        name: '我的临时食物',
        kcalPer100g: 100,
        proteinPer100g: 1,
        carbsPer100g: 1,
        fatPer100g: 1,
      ),
    );
    await repository.delete(created.id);
    expect(await repository.getById(created.id), isNull);
    expect(
      (await repository.search('我的临时食物')).map((food) => food.id),
      isNot(contains(created.id)),
    );
  });

  test('delete 清掉餐次里的悬空外键，但不动当次记录的名称与热量快照', () async {
    final created = await repository.create(
      const NewFood(
        name: '我的鸡胸饭',
        kcalPer100g: 130,
        proteinPer100g: 12,
        carbsPer100g: 15,
        fatPer100g: 2,
      ),
    );
    final now = DateTime.utc(2026, 9, 9);
    final mealId = 'meal-1';
    await database
        .into(database.meals)
        .insert(
          MealsCompanion.insert(
            id: mealId,
            localDate: '2026-09-09',
            slot: 'lunch',
            eatenAt: now,
            source: 'user',
            createdAt: now,
            updatedAt: now,
          ),
        );
    final itemId = 'meal-item-1';
    await database
        .into(database.mealItems)
        .insert(
          MealItemsCompanion.insert(
            id: itemId,
            mealId: mealId,
            foodId: Value(created.id),
            foodNameSnapshot: '我的鸡胸饭',
            grams: 200,
            kcalSnapshot: 260,
            proteinSnapshot: 24,
            carbsSnapshot: 30,
            fatSnapshot: 4,
            createdAt: now,
            updatedAt: now,
          ),
        );

    await repository.delete(created.id);

    final row = await (database.select(
      database.mealItems,
    )..where((item) => item.id.equals(itemId))).getSingle();
    // 链接断了（外键置 NULL），但这一顿吃的是什么、多少热量照旧。
    expect(row.foodId, isNull);
    expect(row.foodNameSnapshot, '我的鸡胸饭');
    expect(row.kcalSnapshot, 260);
  });

  // T11 批量落库（docs/32 §4 T11 验收 2 / §3 D14 ③）：导入路径要能一次插
  // 几万行，但不能因此长出一条「绕过校验/绕过身份标记」的旁路。
  group('createMany', () {
    FoodRepository batchRepository() => FoodRepository(
      database: database,
      idGenerator: _SeqIdGenerator(),
      clock: FixedAppClock(DateTime.utc(2026, 9, 9)),
    );

    test('与 create 同一套校验；导入身份是内置（不是自建）', () async {
      final result = await batchRepository().createMany(const [
        NewFood(
          name: '批量一',
          kcalPer100g: 100,
          proteinPer100g: 1,
          carbsPer100g: 1,
          fatPer100g: 1,
          category: FoodCategory.staple,
        ),
        // 空名与超范围：create 会抛的两条，这里必须同样被拒。
        NewFood(
          name: '   ',
          kcalPer100g: 100,
          proteinPer100g: 1,
          carbsPer100g: 1,
          fatPer100g: 1,
        ),
        NewFood(
          name: '批量三',
          kcalPer100g: 2000,
          proteinPer100g: 1,
          carbsPer100g: 1,
          fatPer100g: 1,
        ),
      ]);

      expect(result.created, 1);
      expect(result.rejected, 2);
      final row = await (database.select(
        database.foods,
      )..where((food) => food.name.equals('批量一'))).getSingle();
      // 2026-10-23 用户：导入的食物都属内置，只有 App 内新建才是自建。
      expect(row.isUserCreated, isFalse, reason: '导入行一律内置，批量路径也不例外');
      expect(row.source, 'import');
      expect(row.state, 'verified');
      expect(row.category, FoodCategory.staple.id);
    });

    test('空列表是空操作（导入 0 条的边界）', () async {
      final result = await batchRepository().createMany(const []);

      expect(result.created, 0);
      expect(result.rejected, 0);
    });

    test('同批内 id 唯一：三行一次落库不互相撞主键', () async {
      final repository2 = batchRepository();

      final result = await repository2.createMany([
        for (var i = 0; i < 3; i++)
          NewFood(
            name: '同批-$i',
            kcalPer100g: 100,
            proteinPer100g: 1,
            carbsPer100g: 1,
            fatPer100g: 1,
          ),
      ]);

      expect(result.created, 3);
      expect(await repository2.count(), 9, reason: '夹具 6 条 + 本批 3 条');
    });
  });
}

final class _FixedIdGenerator implements IdGenerator {
  @override
  String next() => 'user-food-1';
}

final class _SeqIdGenerator implements IdGenerator {
  var _next = 0;

  @override
  String next() => 'batch-${_next++}';
}
