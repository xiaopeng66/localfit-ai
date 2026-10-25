import 'package:localfit_ai/features/nutrition/domain/food_record.dart';

enum MealSlot {
  breakfast('breakfast', '早餐'),
  lunch('lunch', '午餐'),
  dinner('dinner', '晚餐'),
  snack('snack', '加餐');

  const MealSlot(this.storedValue, this.label);

  final String storedValue;
  final String label;

  static MealSlot fromStoredValue(String value) => MealSlot.values.firstWhere(
    (slot) => slot.storedValue == value,
    orElse: () => MealSlot.snack,
  );
}

final class MealItemDraft {
  const MealItemDraft({
    required this.foodName,
    required this.grams,
    required this.nutrition,
    this.foodId,
    this.sourceType = 'manual',
    this.sourceId,
  });

  factory MealItemDraft.fromFood(FoodRecord food, double grams) {
    return MealItemDraft(
      foodId: food.id,
      foodName: food.name,
      grams: grams,
      nutrition: NutritionValues(
        kcal: food.kcalPer100g * grams / 100,
        proteinGrams: food.proteinPer100g * grams / 100,
        carbsGrams: food.carbsPer100g * grams / 100,
        fatGrams: food.fatPer100g * grams / 100,
      ),
    );
  }

  final String? foodId;
  final String foodName;
  final double grams;
  final NutritionValues nutrition;

  /// `food` | `dish` | `menu_item` | `scan` | `manual`（schema 28，
  /// docs/40 §3 写入路径矩阵）；只影响记账来源，不影响营养数值。
  final String sourceType;

  /// 来源实体 id（foods/dish_library/menu_items）；无来源时 null。
  final String? sourceId;
}

final class MealDraft {
  const MealDraft({
    required this.localDate,
    required this.slot,
    required this.items,
    this.notes,
  });

  final String localDate;
  final MealSlot slot;
  final List<MealItemDraft> items;
  final String? notes;

  NutritionValues get nutrition =>
      items.fold(NutritionValues.zero, (total, item) => total + item.nutrition);
}

final class MealItemRecord {
  const MealItemRecord({
    required this.id,
    required this.foodName,
    required this.grams,
    required this.nutrition,
    required this.createdAt,
    required this.updatedAt,
    this.foodId,
    this.sourceType = 'manual',
    this.sourceId,
  });

  final String id;
  final String? foodId;
  final String foodName;
  final double grams;
  final NutritionValues nutrition;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// 来源类型（schema 28）：`food` | `dish` | `menu_item` | `scan` | `manual`。
  final String sourceType;

  /// 来源实体 id（可空；来源删除后仍保留快照）。
  final String? sourceId;

  MealItemDraft scaledTo(double newGrams) {
    final factor = newGrams / grams;
    return MealItemDraft(
      foodId: foodId,
      foodName: foodName,
      grams: newGrams,
      nutrition: NutritionValues(
        kcal: nutrition.kcal * factor,
        proteinGrams: nutrition.proteinGrams * factor,
        carbsGrams: nutrition.carbsGrams * factor,
        fatGrams: nutrition.fatGrams * factor,
      ),
    );
  }
}

final class MealRecord {
  const MealRecord({
    required this.id,
    required this.localDate,
    required this.slot,
    required this.eatenAt,
    required this.source,
    required this.createdAt,
    required this.updatedAt,
    required this.items,
    this.notes,
  });

  final String id;
  final String localDate;
  final MealSlot slot;
  final DateTime eatenAt;
  final String? notes;
  final String source;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<MealItemRecord> items;

  NutritionValues get nutrition =>
      items.fold(NutritionValues.zero, (total, item) => total + item.nutrition);

  MealDraft toDraft() => MealDraft(
    localDate: localDate,
    slot: slot,
    notes: notes,
    items: items.map((item) => item.scaledTo(item.grams)).toList(),
  );
}

final class ManualMealItemDraft {
  const ManualMealItemDraft({required this.food, required this.grams});

  final FoodRecord food;
  final double grams;

  NutritionValues get nutrition => NutritionValues(
    kcal: food.kcalPer100g * grams / 100,
    proteinGrams: food.proteinPer100g * grams / 100,
    carbsGrams: food.carbsPer100g * grams / 100,
    fatGrams: food.fatPer100g * grams / 100,
  );
}

final class ManualMealDraft {
  const ManualMealDraft({
    required this.localDate,
    required this.slot,
    required this.items,
  });

  final String localDate;
  final MealSlot slot;
  final List<ManualMealItemDraft> items;

  MealDraft toMealDraft({String? notes}) => MealDraft(
    localDate: localDate,
    slot: slot,
    notes: notes,
    items: items
        .map((item) => MealItemDraft.fromFood(item.food, item.grams))
        .toList(growable: false),
  );

  NutritionValues get nutrition =>
      items.fold(NutritionValues.zero, (total, item) => total + item.nutrition);
}

final class NutritionValues {
  const NutritionValues({
    required this.kcal,
    required this.proteinGrams,
    required this.carbsGrams,
    required this.fatGrams,
  });

  static const zero = NutritionValues(
    kcal: 0,
    proteinGrams: 0,
    carbsGrams: 0,
    fatGrams: 0,
  );

  final double kcal;
  final double proteinGrams;
  final double carbsGrams;
  final double fatGrams;

  NutritionValues operator +(NutritionValues other) => NutritionValues(
    kcal: kcal + other.kcal,
    proteinGrams: proteinGrams + other.proteinGrams,
    carbsGrams: carbsGrams + other.carbsGrams,
    fatGrams: fatGrams + other.fatGrams,
  );
}

final class DailyNutritionTarget {
  const DailyNutritionTarget({
    required this.calorieMinKcal,
    required this.calorieMaxKcal,
    required this.proteinMinGrams,
    required this.proteinMaxGrams,
    required this.carbsMinGrams,
    required this.carbsMaxGrams,
    required this.fatMinGrams,
    required this.fatMaxGrams,
  });

  final double calorieMinKcal;
  final double calorieMaxKcal;
  final double proteinMinGrams;
  final double proteinMaxGrams;
  final double carbsMinGrams;
  final double carbsMaxGrams;
  final double fatMinGrams;
  final double fatMaxGrams;
}

final class DailyNutritionSummary {
  const DailyNutritionSummary({required this.consumed, this.target});

  final NutritionValues consumed;
  final DailyNutritionTarget? target;
}

final class DailyNutritionRecord {
  const DailyNutritionRecord({
    required this.localDate,
    required this.nutrition,
  });

  final String localDate;
  final NutritionValues nutrition;
}

String formatLocalDate(DateTime value) {
  final local = value.toLocal();
  String twoDigits(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${twoDigits(local.month)}-${twoDigits(local.day)}';
}
