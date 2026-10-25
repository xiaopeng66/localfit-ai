import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart';
import 'package:localfit_ai/features/nutrition/application/add_canteen_dishes_to_library.dart';
import 'package:localfit_ai/features/nutrition/data/dish_library_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_evidence.dart';

/// RV-P1-07：食堂菜 → 菜品库时，`source` 必须跟随**营养证据的来源**。
///
/// 手填营养（`origin=user_input`）被硬编码成 `ai_estimate`，菜品卡就会把
/// 用户自己填的数标成「AI 估算」（设备帧 41）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime.utc(2026, 10, 20, 4);
  late AppDatabase database;
  late CanteenRepository canteen;
  late DishLibraryRepository library;
  late AddCanteenDishesToLibrary importer;
  late String windowId;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    final ids = _SeqIds();
    final clock = FixedAppClock(now);
    canteen = CanteenRepository(
      database: database,
      idGenerator: ids,
      clock: clock,
    );
    library = DishLibraryRepository(
      database: database,
      idGenerator: ids,
      clock: clock,
    );
    importer = AddCanteenDishesToLibrary(
      dishLibrary: library,
      canteen: canteen,
    );
    final venueId = await canteen.createVenue(name: '三食堂', campusName: '南校区');
    windowId = await canteen.createWindow(
      venueId: venueId,
      name: '一楼快餐',
      openTime: '08:00',
      closeTime: '20:00',
    );
  });

  tearDown(() => database.close());

  Future<String> dishWith(String name, String origin, String grade) async {
    final id = await canteen.createDish(windowId: windowId, name: name);
    await canteen.recordNutrition(
      dishId: id,
      kcalPer100g: 200,
      proteinPer100g: 8,
      carbsPer100g: 30,
      fatPer100g: 5,
      grade: grade,
      confidence: 1,
      origin: origin,
    );
    return id;
  }

  test('user_input → 菜品库 source=manual（已确认）', () async {
    final id = await dishWith('番茄牛腩饭', 'user_input', 'D');
    final dish = (await canteen.listDishes(windowId))
        .firstWhere((item) => item.id == id);
    await importer.run(windowId: windowId, dishes: [dish]);

    final record = (await library.watchAll().first).single;
    expect(record.source, 'manual', reason: '手填不是 AI 估算');
    expect(evidenceGradeForSource(record.source).name, 'confirmed');
  });

  test('food_library → 菜品库 source=food_library（已确认）', () async {
    final id = await dishWith('番茄牛腩饭', 'food_library', 'A');
    final dish = (await canteen.listDishes(windowId))
        .firstWhere((item) => item.id == id);
    await importer.run(windowId: windowId, dishes: [dish]);

    final record = (await library.watchAll().first).single;
    expect(record.source, 'food_library');
    expect(evidenceGradeForSource(record.source).name, 'confirmed');
  });

  test('ai_estimate → 菜品库 source=ai_estimate（估算）', () async {
    final id = await dishWith('番茄牛腩饭', 'ai_estimate', 'C');
    final dish = (await canteen.listDishes(windowId))
        .firstWhere((item) => item.id == id);
    await importer.run(windowId: windowId, dishes: [dish]);

    final record = (await library.watchAll().first).single;
    expect(record.source, 'ai_estimate');
    expect(evidenceGradeForSource(record.source).name, 'estimated');
  });
}

final class _SeqIds implements IdGenerator {
  int _n = 0;

  @override
  String next() => 'id-${_n++}';
}
