import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/data/food_detail_repository.dart';

/// 2.0-1j：docs/07 §5.5 的三个实体（份量 / 修订 / 来源证据）在分片导入后必须
/// 能被应用读回来。这里只测读路径：详情装载器怎么取、取哪一条、缺数据时
/// 是否如实为空（而不是编一个默认份量出来）。
void main() {
  late AppDatabase database;
  late FoodDetailRepository repository;

  final now = DateTime.utc(2026, 9, 16, 8);

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = FoodDetailRepository(database: database);
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> insertFood(
    String id, {
    String name = '蒸米饭',
    String state = 'verified',
    String source = 'openfoodfacts',
    String licenseStatus = 'allowed',
    bool isUserCreated = false,
    String? category,
    double? defaultServingGrams,
  }) => database
      .into(database.foods)
      .insert(
        FoodsCompanion.insert(
          id: id,
          name: name,
          kcalPer100g: 116,
          proteinPer100g: 2.6,
          carbsPer100g: 25.9,
          fatPer100g: 0.3,
          source: source,
          state: Value(state),
          licenseStatus: Value(licenseStatus),
          isUserCreated: Value(isUserCreated),
          category: Value.absentIfNull(category),
          defaultServingGrams: Value.absentIfNull(defaultServingGrams),
          createdAt: now,
          updatedAt: now,
        ),
      );

  Future<void> insertPortion(
    String id,
    String foodId, {
    required String name,
    required double grams,
    String locale = 'zh-CN',
    String source = 'openfoodfacts',
  }) => database
      .into(database.foodPortions)
      .insert(
        FoodPortionsCompanion.insert(
          id: id,
          foodId: foodId,
          name: name,
          grams: grams,
          locale: Value(locale),
          source: source,
          createdAt: now,
        ),
      );

  Future<void> insertRevision(
    String id,
    String foodId, {
    int revisionNumber = 1,
    String? evidenceId,
    String qualityStatus = 'ok',
    DateTime? validFrom,
    DateTime? createdAt,
    double? kcal = 116,
    double? protein = 2.6,
    double? carbs = 25.9,
    double? fat = 0.3,
  }) => database
      .into(database.foodNutritionRevisions)
      .insert(
        FoodNutritionRevisionsCompanion.insert(
          id: id,
          foodId: foodId,
          revisionNumber: revisionNumber,
          kcalPer100g: Value.absentIfNull(kcal),
          proteinGPer100g: Value.absentIfNull(protein),
          carbsGPer100g: Value.absentIfNull(carbs),
          fatGPer100g: Value.absentIfNull(fat),
          sourceEvidenceId: Value.absentIfNull(evidenceId),
          qualityStatus: Value(qualityStatus),
          validFrom: Value.absentIfNull(validFrom),
          createdAt: createdAt ?? now,
        ),
      );

  Future<void> insertEvidence(
    String id, {
    String sourceId = 'openfoodfacts',
    String license = 'odbl-1.0',
    String? attribution = 'Open Food Facts, ODbL',
    DateTime? retrievedAt,
    String transformVersion = '2.0-1j',
    String qualityStatus = 'ok',
    String? recordHash,
  }) => database
      .into(database.foodEvidence)
      .insert(
        FoodEvidenceCompanion.insert(
          id: id,
          sourceId: sourceId,
          license: license,
          attribution: Value.absentIfNull(attribution),
          retrievedAt: retrievedAt ?? now,
          transformVersion: transformVersion,
          qualityStatus: qualityStatus,
          recordHash: recordHash ?? 'a' * 64,
          createdAt: now,
        ),
      );

  test(
    'loads portions ordered by grams, latest revision and its evidence',
    () async {
      await insertFood('off:1001', category: 'grain');
      await insertPortion(
        'off:1001:portion:2',
        'off:1001',
        name: '一碗',
        grams: 150,
      );
      await insertPortion(
        'off:1001:portion:1',
        'off:1001',
        name: '一勺',
        grams: 30,
      );
      await insertEvidence('off:1001:ev');
      await insertRevision(
        'off:1001:rev:2',
        'off:1001',
        revisionNumber: 2,
        evidenceId: 'off:1001:ev',
        kcal: 118,
      );
      await insertRevision(
        'off:1001:rev:1',
        'off:1001',
        revisionNumber: 1,
        evidenceId: 'off:1001:ev',
        kcal: 116,
      );

      final detail = await repository.load('off:1001');

      expect(detail, isNotNull);
      expect(detail!.name, '蒸米饭');
      expect(detail.foodId, 'off:1001');
      expect(detail.category, 'grain');
      expect(detail.kcalPer100g, 116);
      // 份量按克数升序——界面直接照序渲染，不在页面里排序。
      expect(detail.portions.map((portion) => portion.name).toList(), [
        '一勺',
        '一碗',
      ]);
      expect(detail.portions.first.grams, 30);
      expect(detail.portions.first.locale, 'zh-CN');
      // 修订取编号最大的那条，并且证据必须来自那条修订指回的 id。
      expect(detail.latestRevision, isNotNull);
      expect(detail.latestRevision!.revisionNumber, 2);
      expect(detail.latestRevision!.kcalPer100g, 118);
      expect(detail.latestRevision!.sourceEvidenceId, 'off:1001:ev');
      expect(detail.evidence, isNotNull);
      expect(detail.evidence!.license, 'odbl-1.0');
      expect(detail.evidence!.transformVersion, '2.0-1j');
    },
  );

  test(
    'ports of the same weight are ordered by name for a stable list',
    () async {
      await insertFood('off:1002');
      await insertPortion(
        'off:1002:portion:c',
        'off:1002',
        name: '一盒',
        grams: 100,
      );
      await insertPortion(
        'off:1002:portion:a',
        'off:1002',
        name: '一片',
        grams: 100,
      );
      await insertPortion(
        'off:1002:portion:b',
        'off:1002',
        name: '一块',
        grams: 100,
      );

      final detail = await repository.load('off:1002');

      expect(detail!.portions.map((portion) => portion.name).toList(), [
        '一块',
        '一片',
        '一盒',
      ]);
    },
  );

  test(
    'a food without ontology rows reports empty, not invented defaults',
    () async {
      await insertFood(
        'seed:2001',
        name: '米饭（自建）',
        source: 'user',
        isUserCreated: true,
        state: 'user_created',
      );

      final detail = await repository.load('seed:2001');

      expect(detail, isNotNull);
      expect(detail!.portions, isEmpty);
      expect(detail.latestRevision, isNull);
      expect(detail.evidence, isNull);
      expect(detail.hasPortions, isFalse);
      expect(detail.hasEvidence, isFalse);
      expect(detail.isUserCreated, isTrue);
    },
  );

  test('unknown food id returns null instead of an empty detail', () async {
    await insertFood('off:1003');

    expect(await repository.load('off:does-not-exist'), isNull);
  });

  test(
    'an incomplete revision stays incomplete (macros not filled in)',
    () async {
      await insertFood('off:1004', state: 'incomplete');
      await insertRevision(
        'off:1004:rev:1',
        'off:1004',
        qualityStatus: 'incomplete',
        kcal: null,
        protein: null,
        carbs: null,
        fat: null,
      );

      final detail = await repository.load('off:1004');

      expect(detail!.latestRevision, isNotNull);
      expect(detail.latestRevision!.isMacroComplete, isFalse);
      expect(detail.latestRevision!.kcalPer100g, isNull);
      expect(detail.latestRevision!.qualityStatus, 'incomplete');
      // 主表里的数字照原样读回，不在读路径上「替」它补全。
      expect(detail.kcalPer100g, 116);
    },
  );

  test(
    'a revision without evidence keeps evidence null (no dangling lookup)',
    () async {
      await insertFood('off:1005');
      await insertRevision('off:1005:rev:1', 'off:1005', evidenceId: null);

      final detail = await repository.load('off:1005');

      expect(detail!.latestRevision, isNotNull);
      expect(detail.latestRevision!.sourceEvidenceId, isNull);
      expect(detail.evidence, isNull);
    },
  );

  test(
    'timestamps come back as UTC and the hash is exposed short for display',
    () async {
      final retrievedLocal = DateTime(2026, 9, 16, 20, 45, 7);
      await insertFood('off:1006');
      await insertEvidence(
        'off:1006:ev',
        retrievedAt: retrievedLocal,
        recordHash: '0123456789abcdef${'0' * 48}',
      );
      await insertRevision(
        'off:1006:rev:1',
        'off:1006',
        evidenceId: 'off:1006:ev',
      );

      final detail = await repository.load('off:1006');

      // drift 的 DateTimeColumn 读回本地时间；读模型统一转 UTC，避免同一时刻
      // 在不同时区显示成不同日期。
      expect(detail!.evidence!.retrievedAt.isUtc, isTrue);
      expect(detail.evidence!.retrievedAt, retrievedLocal.toUtc());
      expect(detail.evidence!.recordHash, '0123456789abcdef${'0' * 48}');
      expect(detail.evidence!.recordHashShort, '0123456789ab…');
    },
  );

  test(
    'the default portion is the one matching the stored serving, else none',
    () async {
      await insertFood('off:1007', defaultServingGrams: 150);
      await insertPortion(
        'off:1007:portion:1',
        'off:1007',
        name: '一勺',
        grams: 30,
      );
      await insertPortion(
        'off:1007:portion:2',
        'off:1007',
        name: '一碗',
        grams: 150,
      );

      final detail = await repository.load('off:1007');

      // 主表存的默认份量（记餐时用的那个数）对得上的份量行，界面据此标「默认」；
      // 对不上就不标——不猜。
      expect(detail!.defaultPortion, isNotNull);
      expect(detail.defaultPortion!.name, '一碗');

      // 主表没有默认份量时不指认任何一行。
      await insertFood('off:1008');
      await insertPortion(
        'off:1008:portion:1',
        'off:1008',
        name: '一杯',
        grams: 200,
      );
      final noDefault = await repository.load('off:1008');
      expect(noDefault!.portions, hasLength(1));
      expect(noDefault.defaultServingGrams, isNull);
      expect(noDefault.defaultPortion, isNull);
    },
  );
}
