import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/campus_menus/application/food_reference_service.dart';
import 'package:localfit_ai/features/campus_menus/application/menu_item_matcher.dart';
import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart';
import 'package:localfit_ai/features/campus_menus/presentation/food_reference_coordinator.dart';
import 'package:localfit_ai/features/campus_menus/presentation/food_reference_sheet.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/food_record.dart';

/// 「引用食物库」= 建立**权威链接**（docs/67 §3.3）。
///
/// 旧实现把每 100g 复制进证据表（等于给供应存了第二套当前营养），而且
/// 一度连链接都没确认。现在只落实链接：营养从主食物生效修订派生，
/// 匹配表置 confirmed，两者同事务。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late CanteenRepository canteen;
  late FoodRepository foods;
  final now = DateTime.utc(2026, 11, 4, 12);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    canteen = CanteenRepository(
      database: db,
      idGenerator: _Ids('canteen'),
      clock: FixedAppClock(now),
    );
    foods = FoodRepository(
      database: db,
      idGenerator: _Ids('food'),
      clock: FixedAppClock(now),
    );
  });

  tearDown(() => db.close());

  test('引用后：营养写入 + 食物链接 confirmed（同事务）', () async {
    await foods.create(
      const NewFood(
        name: '番茄牛腩饭',
        kcalPer100g: 200,
        proteinPer100g: 10,
        carbsPer100g: 20,
        fatPer100g: 8,
      ),
    );
    final venueId = await canteen.createVenue(name: '东区食堂', campusName: '示范大学');
    final windowId = await canteen.createWindow(
      venueId: venueId,
      name: '一楼快餐',
      openTime: '11:00',
      closeTime: '13:30',
    );
    final dishId = await canteen.createDish(windowId: windowId, name: '番茄牛腩饭');

    final matcher = MenuItemMatcher(database: db, shardPaths: const []);
    final service = FoodReferenceService(database: db, matcher: matcher);
    final coordinator = FoodReferenceCoordinator(
      repository: canteen,
      service: service,
      loadDish: canteen.findDish,
      onAnalyze: null,
    );

    await coordinator.run(
      dishId: dishId,
      dishName: '番茄牛腩饭',
      showSnack: (_, {error = false}) {},
      showSheet: (name, candidates) async => FoodReferenceDecision(
        choice: FoodReferenceChoice.adopt,
        candidate: candidates.first,
      ),
      isMounted: () => true,
    );

    final dish = (await canteen.listDishes(windowId)).single;
    expect(dish.foodId, isNotNull, reason: '权威链接必须落实');
    expect(dish.hasNutrition, isTrue, reason: '营养从主食物派生');
    expect(dish.kcalPer100g, 200);
    expect(
      await db.select(db.menuItemNutritionEvidence).get(),
      isEmpty,
      reason: '引用不是复制：证据表不再写第二套当前值',
    );

    final matches = await db.select(db.menuItemFoodMatches).get();
    expect(matches, hasLength(1));
    expect(
      matches.single.matchStatus,
      'confirmed',
      reason: '引用必须确认链接，不能停在 suggested',
    );
  });
}

final class _Ids implements IdGenerator {
  _Ids(this.prefix);
  final String prefix;
  int value = 0;

  @override
  String next() => '$prefix-${value++}';
}
