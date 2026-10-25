import 'package:drift/drift.dart';
import 'package:localfit_ai/data/database/app_database.dart';

/// 「清空内置食物」的结果：如实报数。界面文案要能说出「清了 N 条」，
/// 也要能把「一条都没清」（幂等重跑、或库本来就是空的）说成正常状态。
final class ClearBuiltinFoodsResult {
  const ClearBuiltinFoodsResult({
    required this.deletedFoods,
    required this.unlinkedMealItems,
    required this.droppedMenuMatches,
  });

  /// 删掉的内置食物行数。
  final int deletedFoods;

  /// 被断开链接的餐次条目数（**行本身没删**）。
  final int unlinkedMealItems;

  /// 被删掉的菜单匹配数（菜品行没删，菜单页会重新给建议）。
  final int droppedMenuMatches;
}

/// 只算不删的预览（设置页确认弹层与入口自门控用）。
///
/// 为什么弹层要现算而不是拿概览里的旧快照：概览是「加载那一刻」的数字，
/// 用户可能已经翻了几分钟；而确认框上的数字是**将要发生的事**，必须是此刻
/// 库里的真相。`call()` 与 `preview()` 的判据同源（同一个「内置行」子查询
/// 条件），测试里另有「预览三数 = 执行结果三数」的对账。
final class ClearBuiltinFoodsPreview {
  const ClearBuiltinFoodsPreview({
    required this.builtinFoods,
    required this.linkedMealItems,
    required this.menuMatches,
  });

  /// 库里（此刻）的内置食物行数。
  final int builtinFoods;

  /// 引用了内置食物的餐次条目数（清空后条目还在，`food_id` 置空）。
  final int linkedMealItems;

  /// 引用了内置食物的菜单匹配数（清空后这些派生行移除）。
  final int menuMatches;

  /// 没有内置行可清。
  bool get isEmpty => builtinFoods == 0;
}

/// 清空内置食物（docs/32 §4 T11 验收 1 / §3 D14）。
///
/// 与 `ClearAllLocalData` 的**边界**就是这个用例的全部内容：那个用例承诺
/// 「不留任何用户字节」（连 AI Key、图片、餐记录、设置一起清），这个用例
/// 只删 `foods` 表里 `is_user_created = 0` 的内置行——用户自建的食物、
/// 每一顿的记录、菜单匹配、设置、AI Key、图片一个都不碰。清食物不是清数据。
///
/// 删除顺序是外键要求，不是风格：`meal_items.food_id`（`tables.dart:381`）与
/// `menu_item_food_matches.food_id`（`:528`）都是**无级联**引用，而连接开了
/// `PRAGMA foreign_keys = ON`（`app_database.dart:476`）⇒ 必须先断开这两处，
/// 才删得掉食物行。派生表（别名 / 修订 / 份量）声明了 `onDelete: cascade`，
/// 跟着食物行一起走（测试里断言结果，顺带钉住级联真的生效）。
///
/// 幂等：没有内置行时是空操作（三条计数全 0），可以重复跑。
final class ClearBuiltinFoods {
  const ClearBuiltinFoods(this.database);

  final AppDatabase database;

  /// 内置行的判据（一次子查询），`preview()` 与 `call()` 共用同一个条件。
  JoinedSelectStatement<$FoodsTable, Food> get _builtinFoodIds =>
      database.selectOnly(database.foods)
        ..addColumns([database.foods.id])
        ..where(database.foods.isUserCreated.equals(false));

  /// 只算不删：确认弹层上要写的三组数字（此刻的真值）。
  Future<ClearBuiltinFoodsPreview> preview() async {
    final foodsCount = database.foods.id.count();
    final foodsQuery = database.selectOnly(database.foods)
      ..addColumns([foodsCount])
      ..where(database.foods.isUserCreated.equals(false));
    final mealItemsCount = database.mealItems.id.count();
    final mealItemsQuery = database.selectOnly(database.mealItems)
      ..addColumns([mealItemsCount])
      ..where(database.mealItems.foodId.isInQuery(_builtinFoodIds));
    final matchesCount = database.menuItemFoodMatches.id.count();
    final matchesQuery = database.selectOnly(database.menuItemFoodMatches)
      ..addColumns([matchesCount])
      ..where(database.menuItemFoodMatches.foodId.isInQuery(_builtinFoodIds));

    return ClearBuiltinFoodsPreview(
      builtinFoods: (await foodsQuery.getSingle()).read(foodsCount) ?? 0,
      linkedMealItems:
          (await mealItemsQuery.getSingle()).read(mealItemsCount) ?? 0,
      menuMatches: (await matchesQuery.getSingle()).read(matchesCount) ?? 0,
    );
  }

  Future<ClearBuiltinFoodsResult> call() {
    return database.transaction(() async {
      // 「内置行」用一次子查询表达，而不是先把四万多个 id 拉进 Dart 再回传
      // ——那正是这次要拆掉的量级。
      final builtinFoodIds = _builtinFoodIds;

      final unlinkedMealItems =
          await (database.update(database.mealItems)
                ..where((item) => item.foodId.isInQuery(builtinFoodIds)))
              .write(const MealItemsCompanion(foodId: Value(null)));
      final droppedMenuMatches = await (database.delete(
        database.menuItemFoodMatches,
      )..where((match) => match.foodId.isInQuery(builtinFoodIds))).go();
      final deletedFoods = await (database.delete(
        database.foods,
      )..where((food) => food.isUserCreated.equals(false))).go();

      return ClearBuiltinFoodsResult(
        deletedFoods: deletedFoods,
        unlinkedMealItems: unlinkedMealItems,
        droppedMenuMatches: droppedMenuMatches,
      );
    });
  }
}
