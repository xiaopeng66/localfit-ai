import 'dart:async';

import 'package:drift/drift.dart';

import 'package:localfit_ai/data/database/app_database.dart';

/// 索引协调器（docs/39 §5.2 / docs/41 P3）：派生数据的**唯一生命周期owner**。
///
/// 它管三件事，都与「向量是否启用」无关（P0 结论是向量暂不上线，但索引
/// 表、一致性规则与脏段映射仍然成立——将来打开向量时不必重写调用方）：
///
/// 1. **脏段映射（段级失效）**：把「哪张表变了」映射到「快照哪些段要重算」。
///    之前 loader 是「任何表变了 ⇒ 全部段重算」（正确但浪费）；有了映射，
///    写一餐只重算餐记录/分析段，其余段继续复用缓存。
/// 2. **orphan sweep**：`embedding_index` 里指向已删除 owner 的行必须清掉
///    （派生索引最容易悄悄烂掉——docs/39 §13 的既有风险条目）。
/// 3. **重建**：`modelId` 变更/恢复备份后清空并重建（**不入备份**，D7）。
final class IndexCoordinator {
  IndexCoordinator({required this.database});

  final AppDatabase database;

  /// 表 → 受影响的快照段名集合（段名与 loader 的 `jobs` 键一致）。
  ///
  /// 刻意**保守**：拿不准的表映射到它自己所属的那一段，绝不映射到「全部」；
  /// 段级缓存只保证「脏了必重算」，漏标只会多算一次，不会出错值。
  static const Map<String, Set<String>> tableToSections = {
    // 餐记录：条目表变更会连带影响分析段（同一批聚合）。
    'meals': {'今日与昨日的餐记录'},
    'meal_items': {'今日与昨日的餐记录'},
    // 目标/资料：目标段 + 约束段（资料上的饮食偏好与忌口）。
    'goals': {'当前目标'},
    'daily_targets': {'当前目标'},
    'profiles': {'饮食偏好与忌口'},
    // 记忆与开关：记忆段（开关也在 app_settings 里）。
    'ai_memories': {'关于用户的长期记忆'},
    'app_settings': {'关于用户的长期记忆'},
    // 菜品库/食堂目录：三段各自独立。
    'dish_library': {'菜品库'},
    'venues': {'食堂目录'},
    'menu_services': {'食堂目录'},
    'menu_items': {'食堂目录'},
    'menu_item_nutrition_evidence': {'食堂目录'},
    // 饮水/体重/训练。
    'water_intakes': {'今日饮水'},
    'measurements': {'最近体重'},
    'workout_plans': {'训练计划'},
    'workout_days': {'训练计划'},
    'planned_exercises': {'训练计划'},
    'workout_sessions': {'训练计划', '本周训练统计', '进行中的训练'},
    'workout_sets': {'训练计划', '本周训练统计', '进行中的训练'},
    // 食物库：自建食物段 + 食物库参考段（预检索读 foods/food_aliases）。
    'foods': {'自建食物', '食物库参考'},
    'food_aliases': {'食物库参考'},
  };

  /// 给定变更的表名集合，算出要标脏的段名集合。
  static Set<String> sectionsForTables(Iterable<String> tableNames) => {
    for (final name in tableNames) ...?tableToSections[name],
  };

  /// 订阅表变更并回调「哪些段脏了」。
  ///
  /// 返回订阅（调用方负责取消）。表名用 drift 的 `actualTableName`，与
  /// [tableToSections] 的键同源。
  StreamSubscription<void> watchDirtySections(
    void Function(Set<String> sections) onDirty,
  ) => database
      .tableUpdates(
        TableUpdateQuery.onAllTables([
          database.meals,
          database.mealItems,
          database.dailyTargets,
          database.goals,
          database.profiles,
          database.aiMemories,
          database.appSettings,
          database.dishLibrary,
          database.venues,
          database.menuServices,
          database.menuItems,
          database.menuItemNutritionEvidence,
          // 饮水：旧 loader 这里写的是 `database.waterRecords`（**不存在
          // 的表**），于是饮水段永远不会失效——写一杯水后快照仍显示旧值。
          // 2026-10-18 段级失效接线时抓到并改正。
          database.waterIntakes,
          database.measurements,
          database.workoutPlans,
          database.workoutDays,
          database.plannedExercises,
          database.workoutSessions,
          database.workoutSets,
          database.foods,
          database.foodAliases,
        ]),
      )
      .listen((update) {
        // drift 的 `tableUpdates` 回调给 `Set<TableUpdate>`，每项带表名。
        final names = [for (final entity in update) entity.table];
        final sections = sectionsForTables(names);
        // 表名不在映射里（例如新加的表还没登记）⇒ **保守兜底**：回调空集
        // 会让调用方无从判断；这里回调「全部段」由调用方按需处理。
        onDirty(sections.isEmpty ? const {'*'} : sections);
      });

  /// 清掉指向已删除 owner 的索引行。返回清理条数。
  ///
  /// owner 存在性按类型分别查（`memory` / `dish` / `food` / `menuItem`），
  /// 一次只查一次表（不做逐行查询）。
  Future<int> sweepOrphans() async {
    final rows = await database.select(database.embeddingIndex).get();
    if (rows.isEmpty) return 0;
    final existing = <String, Set<String>>{};
    Future<Set<String>> idsOf(String type) async {
      return existing[type] ??= switch (type) {
        'memory' => {
          for (final row in await database.select(database.aiMemories).get())
            row.id,
        },
        'dish' => {
          for (final row in await database.select(database.dishLibrary).get())
            row.id,
        },
        'food' => {
          for (final row in await database.select(database.foods).get()) row.id,
        },
        'menuItem' => {
          for (final row in await database.select(database.menuItems).get())
            row.id,
        },
        _ => const <String>{},
      };
    }

    final orphans = <EmbeddingIndexData>[];
    for (final row in rows) {
      final ids = await idsOf(row.ownerType);
      if (ids.isEmpty || !ids.contains(row.ownerId)) orphans.add(row);
    }
    if (orphans.isEmpty) return 0;
    await database.transaction(() async {
      for (final orphan in orphans) {
        await (database.delete(database.embeddingIndex)..where(
              (row) =>
                  row.ownerType.equals(orphan.ownerType) &
                  row.ownerId.equals(orphan.ownerId),
            ))
            .go();
      }
    });
    return orphans.length;
  }

  /// 重建：清空全部索引行（`modelId` 变更 / 恢复备份后调用）。
  ///
  /// 恢复备份后**必须**重建：备份里不含向量（D7），且旧向量属于旧库的
  /// 文本（`textHash` 对不上）——留着就是错的。
  Future<int> rebuildAll() => database.delete(database.embeddingIndex).go();

  /// 当前索引规模（调试面板/进度用）。
  Future<int> indexedCount({String? modelId}) async {
    final query = database.selectOnly(database.embeddingIndex)
      ..addColumns([database.embeddingIndex.ownerId.count()]);
    if (modelId != null) {
      query.where(database.embeddingIndex.modelId.equals(modelId));
    }
    final row = await query.getSingle();
    return row.read(database.embeddingIndex.ownerId.count()) ?? 0;
  }
}
