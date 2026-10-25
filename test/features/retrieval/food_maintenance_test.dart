import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart';
import 'package:localfit_ai/features/campus_menus/domain/ingredients.dart';
import 'package:localfit_ai/features/jobs/data/background_job_repository.dart';
import 'package:localfit_ai/features/backup/application/export_localfit_data.dart';
import 'package:localfit_ai/features/backup/application/restore_localfit_data.dart';
import 'package:localfit_ai/features/retrieval/application/feedback_store.dart';
import 'package:localfit_ai/features/retrieval/application/index_coordinator.dart';
import 'package:localfit_ai/features/retrieval/application/food_data_maintenance.dart';

/// P4 整理工具：离线批量打标、重复合并建议、恢复后重建任务、反馈落库。
void main() {
  late AppDatabase db;
  late CanteenRepository canteen;
  late BackgroundJobRepository jobs;
  late FoodDataMaintenance maintenance;
  final now = DateTime.utc(2026, 10, 18);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    canteen = CanteenRepository(
      database: db,
      idGenerator: const _SeqIds(),
      clock: FixedAppClock(now),
    );
    jobs = BackgroundJobRepository(
      database: db,
      clock: FixedAppClock(now),
      idGenerator: const _SeqIds(),
    );
    maintenance = FoodDataMaintenance(
      database: db,
      canteen: canteen,
      jobs: jobs,
    );
    await db
        .into(db.campusProfiles)
        .insert(
          CampusProfilesCompanion.insert(
            id: 'c1',
            name: '示范大学',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db
        .into(db.venues)
        .insert(
          VenuesCompanion.insert(
            id: 'v1',
            campusId: 'c1',
            name: '东区食堂',
            createdAt: now,
            updatedAt: now,
          ),
        );
  });
  tearDown(() => db.close());

  Future<String> addWindowWithDish(String dishName) async {
    final windowId = await canteen.createWindow(
      venueId: 'v1',
      name: '一楼',
      openTime: '11:00',
      closeTime: '13:30',
    );
    await canteen.createDish(windowId: windowId, name: dishName);
    return windowId;
  }

  test('离线词典批量打标：只处理无配料的菜，猜测标 dictionary', () async {
    final windowId = await addWindowWithDish('番茄炒蛋');
    await canteen.createDish(windowId: windowId, name: '清炒时蔬');
    final result = await maintenance.tagCanteenDishesWithDictionary();
    expect(result.tagged, greaterThan(0));
    final dishes = await canteen.listDishes(windowId);
    final tomatoes = dishes.firstWhere((d) => d.name == '番茄炒蛋');
    expect(tomatoes.ingredients.entries, isNotEmpty);
    expect(
      tomatoes.ingredients.entries.every(
        (entry) => entry.source == IngredientSource.dictionary,
      ),
      isTrue,
    );
  });

  test('用户确认过的配料不被再次覆盖（跳过）', () async {
    final windowId = await addWindowWithDish('番茄炒蛋');
    final dish = (await canteen.listDishes(windowId)).single;
    await canteen.updateDishTagsAndIngredients(
      dishId: dish.id,
      tags: const ['午餐'],
      ingredients: const CanteenIngredientInfo(
        entries: [
          IngredientEntry(
            name: '番茄',
            source: IngredientSource.user,
            confidence: 1,
          ),
        ],
      ),
    );
    await maintenance.tagCanteenDishesWithDictionary();
    final after = (await canteen.listDishes(windowId)).single;
    expect(after.ingredients.entries, hasLength(1));
    expect(
      after.ingredients.entries.single.source,
      IngredientSource.user,
      reason: '用户条目不得被词典覆盖',
    );
  });

  test('打标任务幂等入队（重复点不堆任务）', () async {
    final first = await maintenance.enqueueDictionaryTagging();
    final second = await maintenance.enqueueDictionaryTagging();
    expect(second, first);
    expect(await jobs.count(), 1);
  });

  test('恢复后重建：入队 + 清空派生索引（向量未启用）', () async {
    // 先塞一条派生索引（模拟旧库恢复前的残留）。
    await db
        .into(db.embeddingIndex)
        .insert(
          EmbeddingIndexCompanion.insert(
            ownerType: 'dish',
            ownerId: 'dish-1',
            modelId: 'bge-small-zh-v1.5-int8-v1',
            dim: 512,
            encoding: 'i8',
            textHash: 'hash',
            vector: Uint8List(4),
            updatedAt: now,
          ),
        );
    expect(await db.select(db.embeddingIndex).get(), hasLength(1));

    final jobId = await maintenance.enqueueIndexRebuildAfterRestore();
    final job = await jobs.claimNext(type: 'indexRebuild');
    expect(job!.id, jobId);
    final handlers = defaultJobHandlers(maintenance: maintenance);
    final ok = await handlers['indexRebuild']!(job);
    expect(ok, isTrue);
    expect(await db.select(db.embeddingIndex).get(), isEmpty);
  });

  group('索引协调器（docs/39 §5.2 / G14）', () {
    test('段级失效映射：写一餐只脏餐记录段，不脏其余段', () {
      final sections = IndexCoordinator.sectionsForTables(['meals']);
      expect(sections, contains('今日与昨日的餐记录'));
      expect(sections, isNot(contains('菜品库')));
      expect(sections, isNot(contains('今日饮水')));
      // 未登记的表名 ⇒ 空集（调用方按保守兜底处理）。
      expect(IndexCoordinator.sectionsForTables(['unknown_table']), isEmpty);
    });

    test('orphan sweep：owner 已删除的索引行被清掉，存在的保留', () async {
      final coordinator = IndexCoordinator(database: db);
      await db
          .into(db.embeddingIndex)
          .insert(
            EmbeddingIndexCompanion.insert(
              ownerType: 'dish',
              ownerId: 'gone-dish',
              modelId: 'bge-small-zh-v1.5-int8-v1',
              dim: 512,
              encoding: 'i8',
              textHash: 'h1',
              vector: Uint8List(4),
              updatedAt: now,
            ),
          );
      // 一条存在的 owner。
      await db
          .into(db.dishLibrary)
          .insert(
            DishLibraryCompanion.insert(
              id: 'live-dish',
              name: '在册菜',
              mealSlot: '午餐',
              kcal: 300,
              proteinG: 10,
              carbsG: 30,
              fatG: 10,
              source: 'manual',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db
          .into(db.embeddingIndex)
          .insert(
            EmbeddingIndexCompanion.insert(
              ownerType: 'dish',
              ownerId: 'live-dish',
              modelId: 'bge-small-zh-v1.5-int8-v1',
              dim: 512,
              encoding: 'i8',
              textHash: 'h2',
              vector: Uint8List(4),
              updatedAt: now,
            ),
          );

      final swept = await coordinator.sweepOrphans();
      expect(swept, 1);
      final remaining = await db.select(db.embeddingIndex).get();
      expect(remaining.map((row) => row.ownerId), ['live-dish']);
      expect(await coordinator.indexedCount(), 1);
    });

    test('恢复备份 ⇒ 派生索引被清空（向量不进备份）', () async {
      await db
          .into(db.embeddingIndex)
          .insert(
            EmbeddingIndexCompanion.insert(
              ownerType: 'memory',
              ownerId: 'mem-1',
              modelId: 'bge-small-zh-v1.5-int8-v1',
              dim: 512,
              encoding: 'f32',
              textHash: 'h',
              vector: Uint8List(4),
              updatedAt: now,
            ),
          );
      final restore = RestoreLocalFitData(db);
      final bytes = await ExportLocalFitData(db).exportJson();
      await restore.restore(bytes);
      expect(await db.select(db.embeddingIndex).get(), isEmpty);
    });
  });

  test('反馈落库到 app_settings（不新增表）', () async {
    final store = await maintenance.recordFeedback('红烧肉', FeedbackVote.dislike);
    expect(store.entries, isNotEmpty);
    final rows = await db.select(db.appSettings).get();
    expect(rows.map((row) => row.key), contains(kFeedbackStoreKey));
    final reloaded = FeedbackStore.decode(rows.first.value);
    expect(reloaded.entries, isNotEmpty);
  });
}

class _SeqIds implements IdGenerator {
  const _SeqIds();
  @override
  String next() => 'id-${_counter++}';
}

int _counter = 0;
