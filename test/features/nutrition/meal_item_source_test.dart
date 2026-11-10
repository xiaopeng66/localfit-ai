import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/food_scan/application/meal_scan_candidate.dart';
import 'package:localfit_ai/features/food_scan/domain/meal_estimate.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/food_record.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';

/// 餐条目来源契约（docs/40 §3 写入路径矩阵）。
///
/// 用户看到的只是「这一餐吃了什么」，但来源决定以后能不能回答「这是食物库、
/// 菜品库还是食堂菜」。来源一旦在编辑克数 / 撤销删除 / 扫码时丢失，就再也
/// 追不回来。这份用例把三条最容易丢来源的路径钉死。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase database;
  late MealRepository meals;
  final now = DateTime.utc(2026, 9, 10, 12);

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    meals = MealRepository(
      database: database,
      idGenerator: _Ids(),
      clock: FixedAppClock(now),
    );
  });

  tearDown(() => database.close());

  const food = FoodRecord(
    id: 'food-rice',
    name: '白米饭',
    kcalPer100g: 116,
    proteinPer100g: 2.6,
    carbsPer100g: 25.9,
    fatPer100g: 0.3,
    isUserCreated: false,
  );

  test('fromFood：食物条目带 food 来源与 foodId', () {
    final draft = MealItemDraft.fromFood(food, 150);
    expect(draft.sourceType, 'food');
    expect(draft.sourceId, 'food-rice');
    expect(draft.foodId, 'food-rice');
  });

  test('扫码 AI 估算条目带 scan 来源', () {
    const candidate = MealScanCandidate(
      estimate: MealEstimateItem(
        name: '扬州炒饭',
        estimatedGrams: 300,
        gramsRange: GramRange(min: 250, max: 350),
        confidence: 0.8,
        ingredients: [],
        needsConfirmation: false,
        questions: [],
        cookingMethod: null,
        nutrition: MealEstimateNutrition(
          kcal: 500,
          proteinGrams: 15,
          carbsGrams: 70,
          fatGrams: 15,
        ),
      ),
      grams: 300,
      match: LocalFoodMatch(
        status: LocalFoodMatchStatus.unmatched,
        suggestions: [],
      ),
    );

    final draft = candidate.aiNutrition;
    expect(draft, isNotNull);
    expect(draft!.sourceType, 'scan');
  });

  test('scaledTo：改克数不把来源打回 manual', () {
    final record = MealItemRecord(
      id: 'item-1',
      foodName: '红油豆腐粉',
      grams: 300,
      nutrition: const NutritionValues(
        kcal: 268,
        proteinGrams: 8,
        carbsGrams: 32,
        fatGrams: 12,
      ),
      createdAt: now,
      updatedAt: now,
      sourceType: 'dish',
      sourceId: 'dish-hg',
    );

    final draft = record.scaledTo(150);
    expect(draft.sourceType, 'dish');
    expect(draft.sourceId, 'dish-hg');
    expect(draft.nutrition.kcal, 134);
  });

  test('删除整餐后撤销：条目来源仍在（不被 restore 抹成 manual）', () async {
    final id = await meals.create(
      MealDraft(
        localDate: '2026-09-10',
        slot: MealSlot.lunch,
        items: [
          const MealItemDraft(
            foodName: '红油豆腐粉',
            grams: 300,
            nutrition: NutritionValues(
              kcal: 268,
              proteinGrams: 8,
              carbsGrams: 32,
              fatGrams: 12,
            ),
            sourceType: 'dish',
            sourceId: 'dish-hg',
          ),
        ],
      ),
      source: 'dish_library',
    );

    final removed = await meals.delete(id);
    expect(removed, isNotNull);
    await meals.restore(removed!);

    final restored = await meals.getById(id);
    expect(restored, isNotNull);
    expect(restored!.items.single.sourceType, 'dish');
    expect(restored.items.single.sourceId, 'dish-hg');
  });
}

final class _Ids implements IdGenerator {
  int value = 0;

  @override
  String next() => 'id-${value++}';
}
