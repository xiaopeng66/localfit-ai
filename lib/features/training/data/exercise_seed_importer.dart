import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/training/domain/exercise_record.dart';

/// 从 assets 导入版本化训练动作种子。
///
/// v3（yuhonas/free-exercise-db 派生，312 条，2026-10-04 起是唯一动作种子）：
/// 幂等键是 `source='seed-v3'`，不是「表里有没有行」。按 id
/// `insertOnConflictUpdate` 覆盖写——**v3 沿用了 v2 里 58 个动作的本地 id**
/// （见 `tool/exercise_seed/id_overrides.tsv`），所以老库里那些动作是被原地
/// 刷新（改名/补事实），不是插成第二条同名动作；用户自建行 `source='user'`
/// 不在被覆盖之列。
///
/// 另外做**一次性清理**（docs/28 §7.3.3）：v2 里有 5 条已登记的坏行，
/// 其中 3 条（`坐姿好早上`/`后 deltoid 飞鸟`/`俄罗斯转弯`）在 v3 里用**同一个 id
/// 写了正确名字**，导入即覆盖修正，不删（删了还得按同 id 插回来，白白丢引用）；
/// 剩下 2 条是重名重复行（都叫「绳索下压」/「哑铃颈后臂屈伸」），v3 不再收录，
/// 因此在这里删掉——但**只删没有被训练计划或训练组引用的行**，与食物库
/// `_purgeLegacySeeds` 同一条纪律：被引用的行删掉会让计划/历史指空。
final class ExerciseSeedImporter {
  const ExerciseSeedImporter({
    this.assetPath = 'assets/seed/exercises.v3.json',
  });

  final String assetPath;

  /// 当前种子的 source 标记。
  static const String seedSource = 'seed-v3';

  /// v2 里已登记的坏行：错译（`坐姿好早上` `后 deltoid 飞鸟` `俄罗斯转弯`）
  /// 与重名重复（两条「绳索下压」、两条「哑铃颈后臂屈伸」）。
  ///
  /// 名单是**声明**，真正删哪些由 `importIfNeeded` 按「v3 里有没有这个 id」算：
  /// 错译的 3 条在 v3 里被同 id 纠正，不该删；只有 v3 不再收录的重名行会被删。
  static const List<String> legacyBadIds = [
    'ex-seated-good-morning',
    'ex-rear-delt-fly',
    'ex-russian-twist',
    'ex-triceps-pushdown-rope',
    'ex-overhead-triceps-ext',
  ];

  Future<void> importIfNeeded(AppDatabase database) async {
    final existing =
        await (database.select(database.exercises)
              ..where((row) => row.source.equals(seedSource))
              ..limit(1))
            .getSingleOrNull();
    if (existing != null) return;

    final document = jsonDecode(await rootBundle.loadString(assetPath));
    if (document is! Map<String, dynamic> || document['version'] != 3) {
      throw const FormatException('Unsupported exercise seed version.');
    }
    final entries = document['exercises'];
    if (entries is! List) {
      throw const FormatException('Exercise seed entries are missing.');
    }
    final now = DateTime.now().toUtc();
    final seenIds = <String>{};
    final companions = entries
        .map((raw) {
          if (raw is! Map<String, dynamic>) {
            throw const FormatException('An exercise seed entry is invalid.');
          }
          final id = raw['id'];
          final name = raw['name'];
          final muscleGroup = raw['muscle_group'];
          final equipment = raw['equipment'];
          if (id is! String || id.isEmpty || name is! String || name.isEmpty) {
            throw const FormatException('Exercise seed identity is invalid.');
          }
          if (!seenIds.add(id)) {
            throw FormatException('Duplicate exercise seed id: $id');
          }
          if (muscleGroup is! String || equipment is! String) {
            throw const FormatException('Exercise seed facts are invalid.');
          }
          // 难度/常用度是可选的**标注**，不是必填事实：源里缺就写 null，
          // 让读取侧显示「未标注」。不在这里编默认值。
          final difficulty = raw['difficulty'];
          final popularity = raw['popularity'];
          if (difficulty != null && difficulty is! String) {
            throw const FormatException('Exercise seed difficulty is invalid.');
          }
          if (popularity != null && popularity is! int) {
            throw const FormatException('Exercise seed popularity is invalid.');
          }
          if (popularity is int && (popularity < 0 || popularity > 100)) {
            throw FormatException('Exercise popularity out of range: $id');
          }
          return ExercisesCompanion.insert(
            id: id,
            name: name,
            muscleGroup: MuscleGroup.fromStoredValue(muscleGroup).name,
            equipment: Equipment.fromStoredValue(equipment).name,
            source: seedSource,
            difficulty: Value(difficulty as String?),
            popularity: Value(popularity as int?),
            createdAt: now,
            updatedAt: now,
          );
        })
        .toList(growable: false);

    await database.transaction(() async {
      await _purgeBadLegacyRows(database, seenIds);
      for (final companion in companions) {
        await database
            .into(database.exercises)
            .insertOnConflictUpdate(companion);
      }
    });
  }

  /// 删掉「已登记为坏行、且 v3 不再收录、且没被计划/历史引用」的旧行。
  Future<void> _purgeBadLegacyRows(
    AppDatabase database,
    Set<String> seededIds,
  ) async {
    final stale = [
      for (final id in legacyBadIds)
        if (!seededIds.contains(id)) id,
    ];
    if (stale.isEmpty) return;
    final placeholders = List.filled(stale.length, '?').join(', ');
    await database.customStatement(
      'DELETE FROM exercises WHERE id IN ($placeholders)'
      ' AND id NOT IN (SELECT exercise_id FROM planned_exercises'
      ' UNION SELECT exercise_id FROM workout_sets)',
      stale,
    );
  }
}
