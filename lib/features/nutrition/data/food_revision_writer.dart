import 'package:drift/drift.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/nutrition/nutrition_units.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/domain/food_record.dart';

/// 主食物营养修订的**唯一写入助手**（docs/67 §3.2）。
///
/// 主表四项是"当前生效修订"的投影。这个类存在的意义是把
/// 「追加修订 → 切换指针 → 同步投影」三件事绑在一条语句序列里，
/// 让任何调用点都不可能只改一半。
final class FoodRevisionWriter {
  const FoodRevisionWriter({
    required this.database,
    required this.idGenerator,
    required this.clock,
  });

  final AppDatabase database;
  final IdGenerator idGenerator;
  final AppClock clock;

  /// 给一条刚建好的食物写第一条生效修订。
  Future<String> appendBaseline({
    required String foodId,
    required NewFood food,
    required String origin,
    bool isEstimated = false,
    DateTime? now,
  }) async {
    final at = now ?? clock.nowUtc();
    // id 由食物 id 派生：修订的主键天然唯一（每食物每版一条），也不消耗
    // 生成器序列——否则批量导入/测试里的 id 顺序会被修订行挤乱。
    final revisionId = '$foodId-rev-1';
    await database
        .into(database.foodNutritionRevisions)
        .insert(
          baselineCompanion(
            revisionId: revisionId,
            foodId: foodId,
            food: food,
            origin: origin,
            isEstimated: isEstimated,
            now: at,
          ),
        );
    await (database.update(database.foods)..where((t) => t.id.equals(foodId)))
        .write(FoodsCompanion(currentRevisionId: Value(revisionId)));
    return revisionId;
  }

  /// 批量导入用：只产出修订行，不自己发语句（由调用方拼进同一个 batch）。
  static FoodNutritionRevisionsCompanion baselineCompanion({
    required String revisionId,
    required String foodId,
    required NewFood food,
    required String origin,
    required DateTime now,
    bool isEstimated = false,
    int revisionNumber = 1,
  }) => FoodNutritionRevisionsCompanion.insert(
    id: revisionId,
    foodId: foodId,
    revisionNumber: revisionNumber,
    kcalPer100g: Value(food.kcalPer100g),
    proteinGPer100g: Value(food.proteinPer100g),
    carbsGPer100g: Value(food.carbsPer100g),
    fatGPer100g: Value(food.fatPer100g),
    createdAt: now,
    nutritionBasis: Value(NutritionBasis.per100g.storedValue),
    basisAssumed: const Value(false),
    origin: Value(origin),
    isEstimated: Value(isEstimated),
    conversionVersion: Value('food-write-v1'),
  );
}
