import 'package:drift/drift.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/domain/food_detail.dart';

/// 食物详情装载器（2.0-1j）——只读，页面零 SQL。
///
/// 目录分片导入时写入的份量 / 修订 / 证据三张表，在这里被读回成一个
/// [FoodDetail]。缺行不算错误：种子与用户自建条目本来就没有证据行，
/// 「没有」也是一条要如实告诉用户的信息。
final class FoodDetailRepository {
  const FoodDetailRepository({required this.database});

  final AppDatabase database;

  /// 找不到这个 food id 时返回 null（不返回一个空壳详情）。
  Future<FoodDetail?> load(String foodId) async {
    final food = await (database.select(
      database.foods,
    )..where((row) => row.id.equals(foodId))).getSingleOrNull();
    if (food == null) return null;

    final portions =
        await (database.select(database.foodPortions)
              ..where((row) => row.foodId.equals(foodId))
              ..orderBy([
                (row) => OrderingTerm.asc(row.grams),
                (row) => OrderingTerm.asc(row.name),
                (row) => OrderingTerm.asc(row.id),
              ]))
            .get();

    final revision =
        await (database.select(database.foodNutritionRevisions)
              ..where((row) => row.foodId.equals(foodId))
              // 同编号只该有一条（表上有 food_id + revision_number 唯一索引），
              // 真出现重复时按创建时间取最新的一条，读路径不因此抛错。
              ..orderBy([
                (row) => OrderingTerm.desc(row.revisionNumber),
                (row) => OrderingTerm.desc(row.createdAt),
                (row) => OrderingTerm.desc(row.id),
              ])
              ..limit(1))
            .getSingleOrNull();

    final evidenceId = revision?.sourceEvidenceId;
    final evidence = evidenceId == null
        ? null
        : await (database.select(
            database.foodEvidence,
          )..where((row) => row.id.equals(evidenceId))).getSingleOrNull();

    return FoodDetail(
      foodId: food.id,
      name: food.name,
      brand: food.brand,
      category: food.category,
      state: food.state,
      source: food.source,
      licenseStatus: food.licenseStatus,
      isUserCreated: food.isUserCreated,
      // 主库行（用户自建 / CSV 导入）四个数值是**必填**的（CSV 契约 + 表单
      // 校验）⇒「主库 = 营养完整」，与列表卡 `_fromMainRow` 的 `canJoinPlan:
      // true` 同一条规则（裁决 ①：详情与卡同一来源，不再由 `state` 里的来源值
      // `user_created` 误判）。
      canJoinPlan: true,
      kcalPer100g: food.kcalPer100g,
      proteinPer100g: food.proteinPer100g,
      carbsPer100g: food.carbsPer100g,
      fatPer100g: food.fatPer100g,
      defaultServingGrams: food.defaultServingGrams,
      portions: portions
          .map(
            (row) => FoodPortionOption(
              id: row.id,
              name: row.name,
              grams: row.grams,
              locale: row.locale,
              source: row.source,
            ),
          )
          .toList(growable: false),
      latestRevision: revision == null
          ? null
          : FoodRevisionRecord(
              id: revision.id,
              revisionNumber: revision.revisionNumber,
              kcalPer100g: revision.kcalPer100g,
              proteinGPer100g: revision.proteinGPer100g,
              carbsGPer100g: revision.carbsGPer100g,
              fatGPer100g: revision.fatGPer100g,
              sourceEvidenceId: revision.sourceEvidenceId,
              qualityStatus: revision.qualityStatus,
              validFrom: revision.validFrom?.toUtc(),
              createdAt: revision.createdAt.toUtc(),
            ),
      evidence: evidence == null
          ? null
          : FoodEvidenceRecord(
              id: evidence.id,
              sourceId: evidence.sourceId,
              license: evidence.license,
              attribution: evidence.attribution,
              // drift 的 DateTimeColumn 读回来是本地时间（底层存 UTC 微秒），
              // 读模型统一转 UTC：同一时刻在不同时区不该显示成两个日期。
              retrievedAt: evidence.retrievedAt.toUtc(),
              transformVersion: evidence.transformVersion,
              qualityStatus: evidence.qualityStatus,
              recordHash: evidence.recordHash,
            ),
    );
  }
}
