import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/storage/secure_key_value_store.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart';
import 'package:localfit_ai/features/nutrition/application/clear_builtin_foods.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/food_record.dart';
import 'package:localfit_ai/features/settings/data/ai_api_key_store.dart';

import '../../support/food_fixture.dart';

/// 「清空内置食物」（docs/32 §4 T11 验收 1 / §3 D14）。
///
/// 与 `ClearAllLocalData` 的**边界**是本文件的主角：那个用例承诺「不留任何
/// 用户字节」（连 AI Key、图片、餐记录一起清），这个用例只删 `foods` 里的
/// **内置行**——用户自建的食物、每一顿的记录、菜单匹配、设置、AI Key 一个都
/// 不许动。断言按这条边界排：越界删一点东西，这里就该红。
///
/// 两条被清的内置食物的**引用**（`meal_items.food_id` 无级联、
/// `menu_item_food_matches.food_id` 无级联）必须**先断开**才删行，
/// 否则 `PRAGMA foreign_keys = ON` 会直接拒绝（这也是「先置空/先删匹配，
/// 再删食物」的顺序在测试里能被钉住的原因）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase database;
  late FoodRepository repository;
  late CanteenRepository canteens;
  late _MemorySecureStore secureStore;
  late String userFoodId;
  late String userMatchId;
  late DateTime ts;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await seedFoodFixture(database);
    ts = DateTime.utc(2026, 10, 13, 9);
    repository = FoodRepository(
      database: database,
      idGenerator: _SeqIdGenerator(),
      clock: FixedAppClock(ts),
    );
    canteens = CanteenRepository(
      database: database,
      idGenerator: const UuidV7Generator(),
      clock: FixedAppClock(ts),
    );
    secureStore = _MemorySecureStore();
    userFoodId = (await repository.create(
      const NewFood(
        name: '我的鸡胸饭',
        kcalPer100g: 130,
        proteinPer100g: 12,
        carbsPer100g: 15,
        fatPer100g: 2,
      ),
    )).id;

    // 派生表（别名 / 修订 / 份量）：内置行与自建行各一份。
    for (final foodId in ['seed-fc-1', userFoodId]) {
      await database
          .into(database.foodAliases)
          .insert(
            FoodAliasesCompanion.insert(
              id: 'alias-$foodId',
              foodId: foodId,
              normalizedText: 'alias',
              aliasType: 'manual',
              source: 'test',
              createdAt: ts,
            ),
          );
      await database
          .into(database.foodNutritionRevisions)
          .insert(
            FoodNutritionRevisionsCompanion.insert(
              id: 'revision-$foodId',
              foodId: foodId,
              revisionNumber: 1,
              createdAt: ts,
            ),
          );
      await database
          .into(database.foodPortions)
          .insert(
            FoodPortionsCompanion.insert(
              id: 'portion-$foodId',
              foodId: foodId,
              name: '一碗',
              grams: 150,
              source: 'test',
              createdAt: ts,
            ),
          );
    }

    // 一顿饭两条：一条指向内置（米饭），一条指向自建。
    await database
        .into(database.meals)
        .insert(
          MealsCompanion.insert(
            id: 'meal-1',
            localDate: '2026-10-13',
            slot: 'lunch',
            eatenAt: ts,
            source: 'manual',
            createdAt: ts,
            updatedAt: ts,
          ),
        );
    for (final (itemId, foodId, name, kcal) in [
      ('item-builtin', 'seed-fc-1', '米饭', 232.0),
      ('item-user', userFoodId, '我的鸡胸饭', 260.0),
    ]) {
      await database
          .into(database.mealItems)
          .insert(
            MealItemsCompanion.insert(
              id: itemId,
              mealId: 'meal-1',
              foodId: Value(foodId),
              foodNameSnapshot: name,
              grams: 200,
              kcalSnapshot: kcal,
              proteinSnapshot: 10,
              carbsSnapshot: 30,
              fatSnapshot: 3,
              createdAt: ts,
              updatedAt: ts,
            ),
          );
    }

    // 一处菜单匹配链（地点 → 窗口 → 菜品）：两条匹配，内置一条、自建一条。
    await database
        .into(database.campusProfiles)
        .insert(
          CampusProfilesCompanion.insert(
            id: 'campus-1',
            name: '示范大学',
            createdAt: ts,
            updatedAt: ts,
          ),
        );
    await database
        .into(database.venues)
        .insert(
          VenuesCompanion.insert(
            id: 'venue-1',
            campusId: 'campus-1',
            name: '东区食堂',
            createdAt: ts,
            updatedAt: ts,
          ),
        );
    final windowId = await canteens.createWindow(
      venueId: 'venue-1',
      name: '一楼窗口',
      openTime: '10:30',
      closeTime: '13:30',
    );
    final dishId = await canteens.createDish(windowId: windowId, name: '鸡胸肉饭');
    for (final (matchId, foodId) in [
      ('match-builtin', 'seed-fc-1'),
      ('match-user', userFoodId),
    ]) {
      await database
          .into(database.menuItemFoodMatches)
          .insert(
            MenuItemFoodMatchesCompanion.insert(
              id: matchId,
              menuItemId: dishId,
              foodId: foodId,
              createdAt: ts,
              updatedAt: ts,
            ),
          );
    }
    userMatchId = 'match-user';

    // 与清空无关但必须活下来的两样：应用设置与 AI Key。
    await database
        .into(database.appSettings)
        .insert(AppSettingsCompanion.insert(key: 'theme', value: 'dark'));
    await AiApiKeyStore(store: secureStore).save('secret-key');
  });

  tearDown(() => database.close());

  test('只删内置行：六条内置没了，自建食物一条不少，账目如实', () async {
    final result = await ClearBuiltinFoods(database).call();

    expect(result.deletedFoods, 6, reason: '夹具里的六条内置行应全部清掉');
    expect(result.unlinkedMealItems, 1, reason: '只有指向内置食物那一条餐次条目要断链');
    expect(result.droppedMenuMatches, 1, reason: '只有指向内置食物那一条匹配要删');
    final rows = await database.select(database.foods).get();
    expect(rows.map((row) => row.isUserCreated), everyElement(isTrue));
    expect(rows.map((row) => row.name), ['我的鸡胸饭']);
  });

  test('引用置空但记录完整：餐次条目与菜单匹配的载体都还在', () async {
    await ClearBuiltinFoods(database).call();

    final items = await database.select(database.mealItems).get();
    expect(items, hasLength(2), reason: '清食物不是清餐记录');
    final builtin = items.singleWhere((item) => item.id == 'item-builtin');
    // 「这一顿吃了什么」全靠快照：链接可以断，名称与热量一个都不许变。
    expect(builtin.foodId, isNull);
    expect(builtin.foodNameSnapshot, '米饭');
    expect(builtin.grams, 200);
    expect(builtin.kcalSnapshot, 232);
    expect(
      builtin.createdAt.isAtSameMomentAs(ts),
      isTrue,
      reason: '快照行的时间戳也没动（按瞬间比，不纠结 UTC/本地表示）',
    );
    final userItem = items.singleWhere((item) => item.id == 'item-user');
    expect(userItem.foodId, userFoodId, reason: '指向自建食物的链接不该被动');

    final meals = await database.select(database.meals).get();
    expect(meals.single.id, 'meal-1');

    final matches = await database.select(database.menuItemFoodMatches).get();
    expect(matches.map((row) => row.id), [userMatchId]);
    final menuItems = await database.select(database.menuItems).get();
    expect(menuItems, hasLength(1), reason: '菜品行不属于被清范围');
  });

  test('级联表跟着内置行走：别名/修订/份量清掉，自建的留着', () async {
    await ClearBuiltinFoods(database).call();

    for (final ids in [
      (await database.select(database.foodAliases).get()).map((row) => row.id),
      (await database.select(database.foodNutritionRevisions).get()).map(
        (row) => row.id,
      ),
      (await database.select(database.foodPortions).get()).map((row) => row.id),
    ]) {
      expect(ids, everyElement(endsWith(userFoodId)));
      expect(ids, hasLength(1));
    }
  });

  test('幂等：连跑两次不抛，第二次全 0，自建行原样', () async {
    await ClearBuiltinFoods(database).call();
    final second = await ClearBuiltinFoods(database).call();

    expect(second.deletedFoods, 0);
    expect(second.unlinkedMealItems, 0);
    expect(second.droppedMenuMatches, 0);
    expect((await database.select(database.foods).get()).map((row) => row.id), [
      userFoodId,
    ]);
  });

  test('不碰 AI Key 与其它表：与 ClearAllLocalData 的差别是结构性的', () async {
    // 快照**除被清的那六张表之外**的所有表行数；一张表少一行都算越界。
    const touched = {
      'foods',
      'food_aliases',
      'food_nutrition_revisions',
      'food_portions',
      'meal_items',
      'menu_item_food_matches',
    };
    final before = await _rowCounts(database);

    await ClearBuiltinFoods(database).call();

    final after = await _rowCounts(database);
    for (final entry in after.entries) {
      if (touched.contains(entry.key)) continue;
      expect(
        entry.value,
        before[entry.key],
        reason: '「${entry.key}」不该被清空内置食物碰到',
      );
    }
    expect(before['app_settings'], 1, reason: '夹具确实写了一条设置，断言才有意义');
    expect(
      (await database.select(database.appSettings).get()).single.value,
      'dark',
    );
    // AI Key 在安全存储里，不在库里：这个用例面里根本没有它的入口，
    // 所以「清完还在」是结构性的，不是巧合。
    expect(await AiApiKeyStore(store: secureStore).read(), 'secret-key');
  });

  test('preview 只算不删：三组计数与库现状一致，且与执行结果逐条相等', () async {
    final before = await _rowCounts(database);
    final preview = await ClearBuiltinFoods(database).preview();

    expect(preview.builtinFoods, 6, reason: '夹具里六条内置行');
    expect(preview.linkedMealItems, 1, reason: '一条餐次条目指向内置食物');
    expect(preview.menuMatches, 1, reason: '一条菜单匹配指向内置食物');
    expect(preview.isEmpty, isFalse, reason: '有内置行就不是空预览');
    expect(
      await _rowCounts(database),
      before,
      reason: 'preview 是只读的：跑完一张表的行数都不许变',
    );

    // 与真正执行的结果对账：弹层上的数字就是将要发生的事，不是另一套口径。
    final result = await ClearBuiltinFoods(database).call();
    expect(result.deletedFoods, preview.builtinFoods);
    expect(result.unlinkedMealItems, preview.linkedMealItems);
    expect(result.droppedMenuMatches, preview.menuMatches);
  });

  test('清空后 preview 为空（isEmpty），设置页据此不再渲染入口', () async {
    await ClearBuiltinFoods(database).call();

    final preview = await ClearBuiltinFoods(database).preview();

    expect(preview.builtinFoods, 0);
    expect(preview.linkedMealItems, 0);
    expect(preview.menuMatches, 0);
    expect(preview.isEmpty, isTrue);
  });
}

/// 每张表的行数（按表名）。用来把「没碰别的表」变成可执行断言。
Future<Map<String, int>> _rowCounts(AppDatabase database) async {
  final counts = <String, int>{};
  for (final table in database.allTables) {
    final row = await database
        .customSelect('SELECT COUNT(*) AS c FROM ${table.actualTableName}')
        .getSingle();
    counts[table.actualTableName] = row.read<int>('c');
  }
  return counts;
}

final class _SeqIdGenerator implements IdGenerator {
  var _next = 0;

  @override
  String next() => 'user-${_next++}';
}

final class _MemorySecureStore implements SecureKeyValueStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}
