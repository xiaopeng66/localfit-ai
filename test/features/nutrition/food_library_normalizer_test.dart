import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/data/food_library_normalizer.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/food_category.dart';
import 'package:localfit_ai/features/nutrition/domain/food_record.dart';
import 'package:localfit_ai/features/settings/data/app_settings_repository.dart';

/// 存量食物库的一次性归一化（ADR-037）。
///
/// 用**小型内联资产**钉行为：按旧身份改名/改分类、补别名、不覆盖已有别名、
/// 幂等、旧身份不存在时跳过。真实资产（23,919 行）由工具单测与审计报告覆盖。
void main() {
  const csv = '''
旧名称,旧品牌,新名称,新品牌,分类,别名
豆腐（北）,,豆腐（北）,,protein,北豆腐
鲫鱼-天津,,鲫鱼（天津）,,protein,天津
莲藕,,莲藕,,vegetable,藕
''';
  late AppDatabase database;
  late FoodRepository repository;
  late FoodLibraryNormalizer normalizer;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = FoodRepository(
      database: database,
      idGenerator: _SeqIds(),
      clock: FixedAppClock(DateTime.utc(2026, 10, 21, 10)),
    );
    normalizer = FoodLibraryNormalizer(
      database: database,
      idGenerator: _SeqIds(),
      clock: FixedAppClock(DateTime.utc(2026, 10, 21, 10)),
      loadAsset: (_) async => csv,
    );
  });

  tearDown(() => database.close());

  test('按旧身份改名、改分类、补别名（source=normalized / type=nickname）', () async {
    // 模拟升级上来的旧库：名称是原始写法、分类是源文件的「主食」。
    await database
        .into(database.foods)
        .insert(
          FoodsCompanion.insert(
            id: 'legacy-tofu',
            name: '豆腐（北）',
            kcalPer100g: 98,
            proteinPer100g: 12.2,
            carbsPer100g: 2,
            fatPer100g: 4.8,
            category: const Value('staple'),
            source: 'user',
            isUserCreated: const Value(true),
            createdAt: DateTime.utc(2026, 10, 1),
            updatedAt: DateTime.utc(2026, 10, 1),
          ),
        );

    final result = await normalizer.runIfNeeded();

    expect(result.alreadyDone, isFalse);
    expect(result.foodsUpdated, 1);
    expect(result.aliasesInserted, 1);
    final food = (await database.select(database.foods).get()).single;
    expect(food.category, 'protein', reason: '源文件把豆腐放进了谷物及主食，归一化纠正');
    final aliases = await database.select(database.foodAliases).get();
    expect(aliases.single.foodId, 'legacy-tofu');
    expect(aliases.single.normalizedText, '北豆腐');
    expect(aliases.single.aliasType, 'nickname');
    expect(aliases.single.source, 'normalized');
  });

  test('名称按固定格式改：鲫鱼-天津 → 鲫鱼（天津），旧身份仍能命中', () async {
    await database
        .into(database.foods)
        .insert(
          FoodsCompanion.insert(
            id: 'legacy-fish',
            name: '鲫鱼-天津',
            kcalPer100g: 108,
            proteinPer100g: 17.1,
            carbsPer100g: 3.8,
            fatPer100g: 2.7,
            source: 'user',
            isUserCreated: const Value(true),
            createdAt: DateTime.utc(2026, 10, 1),
            updatedAt: DateTime.utc(2026, 10, 1),
          ),
        );

    await normalizer.runIfNeeded();

    final food = (await database.select(database.foods).get()).single;
    expect(food.name, '鲫鱼（天津）');
    expect(
      (await database.select(database.foodAliases).get()).single.normalizedText,
      '天津',
    );
  });

  test('新装路径：库里已是新名称（导入期就归一化）→ 按新身份命中，分类/别名照补', () async {
    await database
        .into(database.foods)
        .insert(
          FoodsCompanion.insert(
            id: 'fresh-tofu',
            name: '豆腐（北）',
            kcalPer100g: 98,
            proteinPer100g: 12.2,
            carbsPer100g: 2,
            fatPer100g: 4.8,
            source: 'user',
            isUserCreated: const Value(true),
            createdAt: DateTime.utc(2026, 10, 21),
            updatedAt: DateTime.utc(2026, 10, 21),
          ),
        );

    final result = await normalizer.runIfNeeded();
    expect(result.aliasesInserted, 1);
    final food = (await database.select(database.foods).get()).single;
    expect(food.category, 'protein');
  });

  test('不覆盖已有别名（用户自己加的优先）', () async {
    final food = await repository.create(
      const NewFood(
        name: '莲藕',
        kcalPer100g: 47,
        proteinPer100g: 1.2,
        carbsPer100g: 11.5,
        fatPer100g: 0.2,
        category: FoodCategory.vegetable,
        aliases: ['莲菜'],
      ),
    );

    final result = await normalizer.runIfNeeded();

    expect(result.aliasesInserted, 0);
    expect(await repository.aliasesFor(food.id), ['莲菜']);
  });

  test('幂等：第二次跑直接短路（KV 打标）', () async {
    final first = await normalizer.runIfNeeded();
    final second = await normalizer.runIfNeeded();
    expect(first.alreadyDone, isFalse);
    expect(second.alreadyDone, isTrue);
    expect(
      await AppSettingsRepository(database: database)
          .getBool(kFoodLibraryNormalizedKey),
      isTrue,
    );
  });

  test('**重跑不重写**：无品牌 / 有品牌的行第二次都 0 更新（幂等）', () async {
    // 无品牌行（null 与 '' 的比较曾让每次重跑都重写 9,474 行——设备实测抓到的缺陷）
    await database
        .into(database.foods)
        .insert(
          FoodsCompanion.insert(
            id: 'no-brand',
            name: '豆腐（北）',
            kcalPer100g: 98,
            proteinPer100g: 12.2,
            carbsPer100g: 2,
            fatPer100g: 4.8,
            category: const Value('staple'),
            source: 'user',
            isUserCreated: const Value(true),
            createdAt: DateTime.utc(2026, 10, 10),
            updatedAt: DateTime.utc(2026, 10, 10),
          ),
        );
    // 有品牌行
    await database
        .into(database.foods)
        .insert(
          FoodsCompanion.insert(
            id: 'with-brand',
            name: '莲藕',
            brand: const Value('某牌'),
            kcalPer100g: 47,
            proteinPer100g: 1.2,
            carbsPer100g: 11.5,
            fatPer100g: 0.2,
            source: 'user',
            isUserCreated: const Value(true),
            createdAt: DateTime.utc(2026, 10, 10),
            updatedAt: DateTime.utc(2026, 10, 10),
          ),
        );

    final first = await normalizer.runIfNeeded();
    expect(first.foodsUpdated, 1, reason: '只有豆腐那条的类别要改；莲藕没改动');
    // 清掉打标，模拟「换 KV 键后再跑一次」
    await (database.delete(
      database.appSettings,
    )..where((row) => row.key.equals(kFoodLibraryNormalizedKey))).go();
    final second = await normalizer.runIfNeeded();
    expect(second.foodsUpdated, 0, reason: '第二次不应再写任何行');
    expect(second.aliasesInserted, 0, reason: '别名已在第一次写入，不重复');
  });

  test('旧身份库里没有：跳过并计数（用户手删过就跳过）', () async {
    final result = await normalizer.runIfNeeded();
    expect(result.foodsUpdated, 0);
    expect(result.skipped, 3);
    expect(await database.select(database.foodAliases).get(), isEmpty);
  });

  test('资产表头不对：抛 FormatException（不静默跳过）', () async {
    final broken = FoodLibraryNormalizer(
      database: database,
      idGenerator: _SeqIds(),
      clock: FixedAppClock(DateTime.utc(2026, 10, 21, 10)),
      loadAsset: (_) async => 'a,b,c\n1,2,3',
    );
    expect(broken.runIfNeeded(), throwsA(isA<FormatException>()));
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
