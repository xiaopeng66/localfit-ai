import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/data/dish_library_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/dish_record.dart';

/// 菜品库的数据契约（2026-11-04 用户：「彻底解决食物库/菜品库/食堂目录」）。
///
/// 食堂目录不是第三个库：它是菜品库的 `canteen` 来源。这份用例钉住三件事：
/// 1. 按名更新（AI `dish.upsert`）不能把食堂来源清掉；
/// 2. 食堂同步不能把用户填的点评/微量/照片清空；
/// 3. 食堂来源菜不能在菜品库直接删（否则下次同步又复活）。
void main() {
  late AppDatabase database;
  late DishLibraryRepository dishes;
  final now = DateTime.utc(2026, 11, 4, 12);

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    dishes = DishLibraryRepository(
      database: database,
      idGenerator: _Ids(),
      clock: FixedAppClock(now),
    );
  });

  tearDown(() => database.close());

  DishDraft draft({
    String name = '番茄炒蛋',
    double kcal = 142,
    String source = 'ai_estimate',
    String? comment,
    double? fiberG,
    double? sodiumMg,
    double? vitaminDMcg,
    String? imagePath,
    String? sourceType,
    String? sourceId,
    bool userEdited = false,
    double? servingGrams,
  }) => DishDraft(
    name: name,
    mealSlot: 'lunch',
    kcal: kcal,
    proteinG: 8.4,
    carbsG: 6.2,
    fatG: 9.1,
    source: source,
    comment: comment,
    fiberG: fiberG,
    sodiumMg: sodiumMg,
    vitaminDMcg: vitaminDMcg,
    imagePath: imagePath,
    sourceType: sourceType,
    sourceId: sourceId,
    userEdited: userEdited,
    servingGrams: servingGrams,
  );

  test('按名更新不带份量时保留原份量（不被打回「按100g估算」）', () async {
    await dishes.upsertByName(draft(servingGrams: 300));

    // 普通改名/改营养的草稿不带 servingGrams：不能把份量清掉。
    final updated = await dishes.upsertByName(draft(kcal: 200));

    expect(updated.servingGrams, 300);
    expect(updated.basisAssumed, isFalse);
  });

  test('searchByName：归一化包含匹配、空白可检索、limit 生效', () async {
    await dishes.create(draft(name: '番茄炒蛋'));
    await dishes.create(draft(name: '番茄牛腩', kcal: 300));
    await dishes.create(draft(name: '清炒时蔬'));

    expect((await dishes.searchByName(' 番茄 ')).map((d) => d.name).toSet(), {
      '番茄炒蛋',
      '番茄牛腩',
    }, reason: '首尾空白要 trim，与记餐弹层同一口径');
    expect(await dishes.searchByName(''), isEmpty);
    expect(
      (await dishes.searchByName('番茄', limit: 1)),
      hasLength(1),
      reason: 'limit 生效（不再 watchAll 全量无界）',
    );
  });

  test('按名更新不清掉食堂来源（AI dish.upsert 不拆来源链接）', () async {
    final created = await dishes.upsertBySource(
      sourceType: kCanteenSourceType,
      sourceId: 'menu-1',
      draft: draft(sourceType: kCanteenSourceType, sourceId: 'menu-1'),
    );

    final updated = await dishes.upsertByName(
      draft(name: '番茄炒蛋', kcal: 200, source: 'ai_chat'),
    );

    expect(updated.id, created.id, reason: '同名还是同一行');
    expect(updated.kcal, 200, reason: '按名更新仍要写营养');
    expect(updated.sourceType, kCanteenSourceType, reason: '来源键不能被空草稿清掉');
    expect(updated.sourceId, 'menu-1');
  });

  test('食堂同步不清空点评与微量（照片跟随来源，另有用例）', () async {
    final created = await dishes.upsertBySource(
      sourceType: kCanteenSourceType,
      sourceId: 'menu-1',
      draft: draft(
        sourceType: kCanteenSourceType,
        sourceId: 'menu-1',
        comment: '蛋白质偏少，建议搭配豆制品。',
        fiberG: 1.4,
        sodiumMg: 620,
        vitaminDMcg: 1.2,
      ),
    );

    // 食堂侧重新分析：草稿只带来源营养，不带点评/微量。
    final synced = await dishes.upsertBySource(
      sourceType: kCanteenSourceType,
      sourceId: 'menu-1',
      draft: draft(
        kcal: 150,
        sourceType: kCanteenSourceType,
        sourceId: 'menu-1',
      ),
    );

    expect(synced.id, created.id);
    expect(synced.kcal, 150, reason: '来源营养要更新');
    expect(synced.comment, '蛋白质偏少，建议搭配豆制品。');
    expect(synced.fiberG, 1.4);
    expect(synced.sodiumMg, 620);
    expect(synced.vitaminDMcg, 1.2);
  });

  test('食堂来源菜不能在菜品库直接删（要去食堂目录删来源）', () async {
    final created = await dishes.upsertBySource(
      sourceType: kCanteenSourceType,
      sourceId: 'menu-1',
      draft: draft(sourceType: kCanteenSourceType, sourceId: 'menu-1'),
    );

    await expectLater(
      dishes.delete(created.id),
      throwsA(isA<FormatException>()),
      reason: '直接删会复活；必须引导用户去食堂目录删来源菜',
    );
    expect(await dishes.watchAll().first, hasLength(1));
  });

  test('同来源历史重复行：findBySource 取第一条，不抛异常', () async {
    for (final id in ['dish-a', 'dish-b']) {
      await database
          .into(database.dishLibrary)
          .insert(
            DishLibraryCompanion.insert(
              id: id,
              name: '番茄炒蛋',
              mealSlot: 'lunch',
              kcal: 142,
              proteinG: 8.4,
              carbsG: 6.2,
              fatG: 9.1,
              source: 'ai_estimate',
              sourceType: const drift.Value(kCanteenSourceType),
              sourceId: const drift.Value('menu-1'),
              createdAt: now,
              updatedAt: now,
            ),
          );
    }

    final found = await dishes.findBySource(
      sourceType: kCanteenSourceType,
      sourceId: 'menu-1',
    );
    expect(found, isNotNull, reason: '历史重复不能让 find 抛 StateError');
  });

  test('能量口径：无份量的食堂菜标 /100g，手工菜标按100g估，有份量标 /份', () {
    DishRecord make({
      String? sourceType,
      double? servingGrams,
      bool basisAssumed = false,
    }) => DishRecord(
      id: 'dish-x',
      name: '番茄炒蛋',
      mealSlot: 'lunch',
      kcal: 268,
      proteinG: 8,
      carbsG: 32,
      fatG: 12,
      source: 'manual',
      createdAt: now,
      updatedAt: now,
      servingGrams: servingGrams,
      basisAssumed: basisAssumed,
      sourceType: sourceType,
    );

    expect(
      make(sourceType: kCanteenSourceType, basisAssumed: true).energyLabel,
      '268 kcal/100g',
      reason: '食堂来源没份量时，四值就是每 100g，不能冒充 /份',
    );
    expect(
      make(basisAssumed: true).energyLabel,
      '268 kcal/份（按100g估）',
      reason: '手工菜没份量时，值是一份但份量是假设的，必须说出来',
    );
    expect(
      make(servingGrams: 300).energyLabel,
      '268 kcal/份',
      reason: '份量已知才写 /份',
    );
  });
}

final class _Ids implements IdGenerator {
  int value = 0;

  @override
  String next() => 'dish-${value++}';
}
