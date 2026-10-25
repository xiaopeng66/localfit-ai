import 'package:drift/drift.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/training/domain/exercise_record.dart';

final class ExerciseRepository {
  const ExerciseRepository({
    required this.database,
    required this.idGenerator,
    required this.clock,
  });

  final AppDatabase database;
  final IdGenerator idGenerator;
  final AppClock clock;

  /// 动作库查询（docs/21 §5.5；docs/28 §7.4 提的是两件事）。
  ///
  /// [muscleGroup] 为 null＝不按肌群筛；[query] 同时匹配动作名**与**肌群
  /// 中文标签（规范写的是「搜索：动作名、肌群」，所以输「胸」要能筛出
  /// 胸肌动作，不能只 LIKE 名称）。
  ///
  /// [limit] 默认 500；完整选择器可显式传 null，不随动作库增长静默截断。
  /// 排序末尾补 `id ASC`：同名动作在有限查询下也保持确定顺序。
  /// 精确同名查询（**不受 [search] 的 500 条截断影响**）。
  ///
  /// AI 命令解析目标用它：动作库 >500 条时，`search(name)` 只返回前 500 条，
  /// 精确同名也会被判「不存在」（2026-10-21 RV-P2-03）。
  Future<List<ExerciseRecord>> findByExactName(String name) async {
    final normalized = name.trim();
    if (normalized.isEmpty) return const [];
    final rows =
        await (database.select(database.exercises)
              ..where((row) => row.name.equals(normalized))
              ..orderBy([(row) => OrderingTerm.asc(row.id)]))
            .get();
    return [for (final row in rows) _map(row)];
  }

  Future<List<ExerciseRecord>> search(
    String query, {
    MuscleGroup? muscleGroup,
    int? limit = 500,
  }) async {
    final normalized = query.trim();
    final statement = database.select(database.exercises)
      ..orderBy([
        (row) => OrderingTerm.desc(row.isUserCreated),
        (row) => OrderingTerm.asc(row.name),
        (row) => OrderingTerm.asc(row.id),
      ]);
    if (limit != null) statement.limit(limit);
    if (muscleGroup != null) {
      statement.where((row) => row.muscleGroup.equals(muscleGroup.name));
    }
    if (normalized.isNotEmpty) {
      final escaped = normalized
          .replaceAll(r'\', r'\\')
          .replaceAll('%', r'\%')
          .replaceAll('_', r'\_');
      // 肌群匹配走「标签→枚举名」反查，而不是把中文标签拼进 SQL：
      // 拼进去的话 `%胸%` 会命中「胸」也命中任何含「胸」的名字，
      // 语义就散了。这里要么整组命中，要么按名字 LIKE。
      final matchedGroups = [
        for (final group in MuscleGroup.values)
          if (group.label.contains(normalized)) group.name,
      ];
      // LIKE 需显式 ESCAPE，否则名称含 % / _ 时永远匹配不到。
      statement.where(
        (row) => matchedGroups.isEmpty
            ? row.name.like('%$escaped%', escapeChar: r'\')
            : row.name.like('%$escaped%', escapeChar: r'\') |
                  row.muscleGroup.isIn(matchedGroups),
      );
    }
    return (await statement.get()).map(_map).toList(growable: false);
  }

  Future<ExerciseRecord?> getById(String id) async {
    final row = await (database.select(
      database.exercises,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    return row == null ? null : _map(row);
  }

  Future<List<ExerciseRecord>> listAlternatives(
    String id, {
    int limit = 6,
  }) async {
    final current = await getById(id);
    if (current == null) return const [];
    final rows =
        await (database.select(database.exercises)
              ..where(
                (row) =>
                    row.muscleGroup.equals(current.muscleGroup.name) &
                    row.id.equals(id).not(),
              )
              ..orderBy([(row) => OrderingTerm.asc(row.name)])
              ..limit(limit))
            .get();
    return rows.map(_map).toList(growable: false);
  }

  Future<ExerciseRecord> create(NewExercise exercise) async {
    _validate(exercise);
    final now = clock.nowUtc();
    final row = Exercise(
      id: idGenerator.next(),
      name: exercise.name.trim(),
      muscleGroup: exercise.muscleGroup.name,
      equipment: exercise.equipment.name,
      source: 'user',
      // 用户自建动作不标难度/常用度：我们不知道，就不写。
      difficulty: null,
      popularity: null,
      isUserCreated: true,
      createdAt: now,
      updatedAt: now,
    );
    await database.into(database.exercises).insert(row);
    return _map(row);
  }

  void _validate(NewExercise exercise) {
    if (exercise.name.trim().isEmpty) {
      throw const FormatException('动作名称不能为空。');
    }
  }

  ExerciseRecord _map(Exercise row) => ExerciseRecord(
    id: row.id,
    name: row.name,
    muscleGroup: MuscleGroup.fromStoredValue(row.muscleGroup),
    equipment: Equipment.fromStoredValue(row.equipment),
    difficulty: ExerciseDifficulty.fromStoredValue(row.difficulty),
    popularity: row.popularity,
    isUserCreated: row.isUserCreated,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );
}
