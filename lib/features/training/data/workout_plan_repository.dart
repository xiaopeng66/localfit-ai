import 'package:drift/drift.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/training/domain/exercise_record.dart';
import 'package:localfit_ai/features/training/domain/workout_plan.dart';

final class WorkoutPlanRepository {
  const WorkoutPlanRepository({
    required this.database,
    required this.idGenerator,
    required this.clock,
  });

  final AppDatabase database;
  final IdGenerator idGenerator;
  final AppClock clock;

  /// 训练页派生视图的失效信号：一次已提交事务只发一次，涵盖其他页面与
  /// 备份恢复的写入。不监听无关表，也不为通知本身执行查询。
  Stream<void> watchTrainingChanges() => database
      .tableUpdates(
        TableUpdateQuery.onAllTables([
          database.workoutPlans,
          database.workoutDays,
          database.plannedExercises,
          database.exercises,
          database.workoutSessions,
          database.workoutSets,
        ]),
      )
      .map((_) {});

  Future<List<WorkoutPlanSummary>> list() async {
    final rows =
        await (database.select(database.workoutPlans)..orderBy([
              (row) => OrderingTerm.desc(row.createdAt),
              (row) => OrderingTerm.desc(row.id),
            ]))
            .get();
    final countQuery = database.selectOnly(database.plannedExercises).join([
      innerJoin(
        database.workoutDays,
        database.workoutDays.id.equalsExp(database.plannedExercises.dayId),
      ),
    ]);
    countQuery.addColumns([database.workoutDays.planId, countAll()]);
    countQuery.groupBy([database.workoutDays.planId]);
    final counts = await countQuery.get();
    final entryCountByPlan = {
      for (final row in counts)
        row.read(database.workoutDays.planId)!: row.read(countAll()) ?? 0,
    };
    return rows
        .map(
          (row) => WorkoutPlanSummary(
            id: row.id,
            name: row.name,
            entryCount: entryCountByPlan[row.id] ?? 0,
            revision: row.revision,
          ),
        )
        .toList(growable: false);
  }

  Future<WorkoutPlanRecord?> getById(String id) async {
    final row = await (database.select(
      database.workoutPlans,
    )..where((plan) => plan.id.equals(id))).getSingleOrNull();
    if (row == null) return null;
    final dayRows =
        await (database.select(database.workoutDays)
              ..where((day) => day.planId.equals(id))
              ..orderBy([(day) => OrderingTerm.asc(day.weekday)]))
            .get();
    final days = <WorkoutPlanDayRecord>[];
    for (final dayRow in dayRows) {
      // 2026-10-16 修复：`Selectable.where()` 在 join 查询上**不生效**
      // （drift 的 join 查询要用 `where` 于表达式上或直接把条件放进
      // `join` 的过滤），导致 dayId 过滤被静默忽略 ⇒ `getById` 把**所有
      // 计划的所有条目**都挂到每一天上（2026-10-16 真机实测：口语弹药库
      // C10 里 `plan.entry.remove` 写库成功但 `getById` 读回的条目仍在）。
      // 修正 = 用 `join` 的 `where` 参数（drift 官方 join 过滤入口）。
      final entryQuery =
          database.select(database.plannedExercises).join([
              innerJoin(
                database.exercises,
                database.exercises.id.equalsExp(
                  database.plannedExercises.exerciseId,
                ),
              ),
            ])
            ..where(database.plannedExercises.dayId.equals(dayRow.id))
            ..orderBy([OrderingTerm.asc(database.plannedExercises.sortOrder)]);
      final entryRows = await entryQuery.get();
      days.add(
        WorkoutPlanDayRecord(
          id: dayRow.id,
          weekday: dayRow.weekday,
          entries: entryRows
              .map(
                (row) => PlannedExerciseRecord(
                  id: row.readTable(database.plannedExercises).id,
                  exerciseId: row
                      .readTable(database.plannedExercises)
                      .exerciseId,
                  exerciseName: row.readTable(database.exercises).name,
                  equipment: Equipment.fromStoredValue(
                    row.readTable(database.exercises).equipment,
                  ),
                  sortOrder: row.readTable(database.plannedExercises).sortOrder,
                  targetSets: row
                      .readTable(database.plannedExercises)
                      .targetSets,
                  targetReps: row
                      .readTable(database.plannedExercises)
                      .targetReps,
                  targetWeightKg: row
                      .readTable(database.plannedExercises)
                      .targetWeightKg,
                ),
              )
              .toList(growable: false),
        ),
      );
    }
    return WorkoutPlanRecord(
      id: row.id,
      name: row.name,
      status: row.status,
      source: row.source,
      revision: row.revision,
      days: List.unmodifiable(days),
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }

  Future<String> create(
    WorkoutPlanDraft draft, {
    String source = 'manual',
  }) async {
    if (source != 'manual' && source != 'ai') {
      throw const FormatException('计划来源无效。');
    }
    _validateDraft(draft);
    final now = clock.nowUtc();
    return database.transaction(() async {
      final planId = idGenerator.next();
      await database
          .into(database.workoutPlans)
          .insert(
            WorkoutPlansCompanion.insert(
              id: planId,
              name: draft.name.trim(),
              source: source,
              createdAt: now,
              updatedAt: now,
            ),
          );
      for (final day in draft.days) {
        await _insertDay(planId: planId, draft: day, now: now);
      }
      return planId;
    });
  }

  Future<void> addEntry(
    String planId,
    int weekday,
    PlannedExerciseDraft entry,
  ) async {
    _validateWeekday(weekday);
    _validateEntry(entry);
    final now = clock.nowUtc();
    await database.transaction(() async {
      final plan = await (database.select(
        database.workoutPlans,
      )..where((row) => row.id.equals(planId))).getSingleOrNull();
      if (plan == null) throw StateError('训练计划不存在或已被删除。');
      await _requireExercise(entry.exerciseId);
      var day =
          await (database.select(database.workoutDays)
                ..where(
                  (row) =>
                      row.planId.equals(planId) & row.weekday.equals(weekday),
                )
                ..limit(1))
              .getSingleOrNull();
      if (day == null) {
        final dayId = idGenerator.next();
        await database
            .into(database.workoutDays)
            .insert(
              WorkoutDaysCompanion.insert(
                id: dayId,
                planId: planId,
                weekday: weekday,
                sortOrder: weekday,
              ),
            );
        day = WorkoutDay(
          id: dayId,
          planId: planId,
          weekday: weekday,
          sortOrder: weekday,
        );
      }
      final maxOrder = await _maxSortOrder(day.id);
      await database
          .into(database.plannedExercises)
          .insert(
            _entryCompanion(
              dayId: day.id,
              entry: entry,
              sortOrder: maxOrder + 1,
              now: now,
            ),
          );
      await _bumpRevision(planId, plan.revision, now);
    });
  }

  Future<bool> removeEntry(String entryId) async {
    final now = clock.nowUtc();
    return database.transaction(() async {
      final entry = await (database.select(
        database.plannedExercises,
      )..where((row) => row.id.equals(entryId))).getSingleOrNull();
      if (entry == null) return false;
      final day = await (database.select(
        database.workoutDays,
      )..where((row) => row.id.equals(entry.dayId))).getSingle();
      await (database.delete(
        database.plannedExercises,
      )..where((row) => row.id.equals(entryId))).go();
      final remaining = await (database.select(
        database.plannedExercises,
      )..where((row) => row.dayId.equals(entry.dayId))).get();
      if (remaining.isEmpty) {
        await (database.delete(
          database.workoutDays,
        )..where((row) => row.id.equals(entry.dayId))).go();
      }
      final plan = await (database.select(
        database.workoutPlans,
      )..where((row) => row.id.equals(day.planId))).getSingleOrNull();
      if (plan != null) {
        await _bumpRevision(plan.id, plan.revision, now);
      }
      return true;
    });
  }

  /// 改计划名（2026-10-15 批次 A：AI 控制面补全）。
  ///
  /// 只改名字：**不动训练日与动作编排**（那两件事分别走
  /// [addEntry]/[removeEntry]）。名字校验与 [create] 同一口径（非空、
  /// trim 后 ≤ 60 字），返回 false = 计划不存在（调用方翻人话）。
  Future<bool> renamePlan(String id, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw const FormatException('计划名称不能为空。');
    if (trimmed.length > 60) {
      throw const FormatException('计划名称最多 60 个字符。');
    }
    final changed =
        await (database.update(
          database.workoutPlans,
        )..where((row) => row.id.equals(id))).write(
          WorkoutPlansCompanion(
            name: Value(trimmed),
            updatedAt: Value(clock.nowUtc()),
          ),
        );
    return changed == 1;
  }

  Future<bool> removePlan(String id) async {
    final deleted = await (database.delete(
      database.workoutPlans,
    )..where((row) => row.id.equals(id))).go();
    return deleted == 1;
  }

  void _validateDraft(WorkoutPlanDraft draft) {
    if (draft.name.trim().isEmpty) {
      throw const FormatException('计划名称不能为空。');
    }
    final weekdays = <int>{};
    for (final day in draft.days) {
      _validateWeekday(day.weekday);
      if (!weekdays.add(day.weekday)) {
        throw const FormatException('计划的每个星期只能出现一次。');
      }
      if (day.entries.isEmpty) {
        throw FormatException(
          '星期${workoutWeekdayLabel(day.weekday)}至少需要安排一个动作。',
        );
      }
      for (final entry in day.entries) {
        _validateEntry(entry);
      }
    }
  }

  void _validateWeekday(int weekday) {
    if (weekday < 1 || weekday > 7) {
      throw const FormatException('训练日必须是 1 到 7 的星期。');
    }
  }

  void _validateEntry(PlannedExerciseDraft entry) {
    if (entry.targetSets < 1 || entry.targetReps < 1) {
      throw const FormatException('组次目标必须是正整数。');
    }
    final weight = entry.targetWeightKg;
    if (weight != null && (!weight.isFinite || weight < 0)) {
      throw const FormatException('目标重量必须是非负数。');
    }
  }

  Future<void> _insertDay({
    required String planId,
    required WorkoutPlanDayDraft draft,
    required DateTime now,
  }) async {
    final dayId = idGenerator.next();
    await database
        .into(database.workoutDays)
        .insert(
          WorkoutDaysCompanion.insert(
            id: dayId,
            planId: planId,
            weekday: draft.weekday,
            sortOrder: draft.weekday,
          ),
        );
    var sortOrder = 0;
    for (final entry in draft.entries) {
      await _requireExercise(entry.exerciseId);
      await database
          .into(database.plannedExercises)
          .insert(
            _entryCompanion(
              dayId: dayId,
              entry: entry,
              sortOrder: sortOrder++,
              now: now,
            ),
          );
    }
  }

  Future<void> _requireExercise(String exerciseId) async {
    final exercise = await (database.select(
      database.exercises,
    )..where((row) => row.id.equals(exerciseId))).getSingleOrNull();
    if (exercise == null) {
      throw const FormatException('动作不存在于本地动作库。');
    }
  }

  Future<int> _maxSortOrder(String dayId) async {
    final query = database.selectOnly(database.plannedExercises)
      ..addColumns([database.plannedExercises.sortOrder.max()])
      ..where(database.plannedExercises.dayId.equals(dayId));
    final row = await query.getSingle();
    return row.read(database.plannedExercises.sortOrder.max()) ?? -1;
  }

  PlannedExercisesCompanion _entryCompanion({
    required String dayId,
    required PlannedExerciseDraft entry,
    required int sortOrder,
    required DateTime now,
  }) => PlannedExercisesCompanion.insert(
    id: idGenerator.next(),
    dayId: dayId,
    exerciseId: entry.exerciseId,
    sortOrder: sortOrder,
    targetSets: entry.targetSets,
    targetReps: entry.targetReps,
    targetWeightKg: Value(entry.targetWeightKg),
    createdAt: now,
    updatedAt: now,
  );

  Future<void> _bumpRevision(
    String planId,
    int currentRevision,
    DateTime now,
  ) async {
    await (database.update(
      database.workoutPlans,
    )..where((row) => row.id.equals(planId))).write(
      WorkoutPlansCompanion(
        revision: Value(currentRevision + 1),
        updatedAt: Value(now),
      ),
    );
  }
}
