import 'package:drift/drift.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/core/time/local_date.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/training/domain/exercise_record.dart';
import 'package:localfit_ai/features/training/domain/workout_session.dart';

final class WorkoutSessionRepository {
  const WorkoutSessionRepository({
    required this.database,
    required this.idGenerator,
    required this.clock,
  });

  final AppDatabase database;
  final IdGenerator idGenerator;
  final AppClock clock;

  Future<WorkoutSessionRecord?> getActive() async {
    final row =
        await (database.select(database.workoutSessions)
              ..where((session) => session.status.equals('active'))
              ..orderBy([(session) => OrderingTerm.desc(session.startedAt)])
              ..limit(1))
            .getSingleOrNull();
    if (row == null) return null;
    return _hydrate(row);
  }

  Future<WorkoutSessionRecord?> getById(String id) async {
    final row = await (database.select(
      database.workoutSessions,
    )..where((session) => session.id.equals(id))).getSingleOrNull();
    if (row == null) return null;
    return _hydrate(row);
  }

  Future<String> start({required String localDate, String? planId}) async {
    // 与兄弟仓库的日期口径对齐（parseLocalDate/isValidIsoLocalDate）：
    // 「非空即可」会放行 `2026-2-3`、`not-a-date` 之类的脏文本直接落库，
    // 读取侧（周统计）随后要为它兜底（docs/11 P3）。
    if (!isValidIsoLocalDate(localDate.trim())) {
      throw const FormatException('训练日期无效。');
    }
    if (planId != null) {
      final plan = await (database.select(
        database.workoutPlans,
      )..where((row) => row.id.equals(planId))).getSingleOrNull();
      if (plan == null) {
        throw const FormatException('训练计划不存在于本地。');
      }
    }
    // 检查与插入必须同事务：drift 单后台写入器会串行化事务，
    // 事务内复查可挡住并发 start() 各自插出一条 active 会话的竞态。
    return database.transaction(() async {
      final active = await getActive();
      if (active != null) {
        throw StateError('已有一个进行中的训练会话，请先结束或继续它。');
      }
      final now = clock.nowUtc();
      final sessionId = idGenerator.next();
      await database
          .into(database.workoutSessions)
          .insert(
            WorkoutSessionsCompanion.insert(
              id: sessionId,
              planId: Value(planId),
              localDate: localDate,
              startedAt: now,
              createdAt: now,
              updatedAt: now,
            ),
          );
      return sessionId;
    });
  }

  Future<String> logSet(String sessionId, WorkoutSetDraft draft) async {
    _validateDraft(draft);
    final now = clock.nowUtc();
    return database.transaction(() async {
      final session = await (database.select(
        database.workoutSessions,
      )..where((row) => row.id.equals(sessionId))).getSingleOrNull();
      if (session == null) {
        throw StateError('训练会话不存在或已被删除。');
      }
      if (session.status != 'active') {
        throw StateError('训练会话已结束，不能再记录组次。');
      }
      if (draft.plannedExerciseId != null) {
        final planned =
            await (database.select(database.plannedExercises)
                  ..where((row) => row.id.equals(draft.plannedExerciseId!)))
                .getSingleOrNull();
        if (planned == null) {
          throw const FormatException('计划动作不存在，请直接记录自由组次。');
        }
      }
      final exercise = await (database.select(
        database.exercises,
      )..where((row) => row.id.equals(draft.exerciseId))).getSingleOrNull();
      if (exercise == null) {
        throw const FormatException('动作不存在于本地动作库。');
      }
      final maxOrder =
          await (database.selectOnly(database.workoutSets)
                ..addColumns([database.workoutSets.sortOrder.max()])
                ..where(database.workoutSets.sessionId.equals(sessionId)))
              .get()
              .then(
                (row) => row.single.read(database.workoutSets.sortOrder.max()),
              );
      final setId = idGenerator.next();
      await database
          .into(database.workoutSets)
          .insert(
            WorkoutSetsCompanion.insert(
              id: setId,
              sessionId: sessionId,
              plannedExerciseId: Value(draft.plannedExerciseId),
              exerciseId: draft.exerciseId,
              sortOrder: (maxOrder ?? -1) + 1,
              weightKg: draft.weightKg,
              reps: draft.reps,
              rpe: Value(draft.rpe),
              completedAt: now,
              createdAt: now,
              updatedAt: now,
            ),
          );
      await (database.update(database.workoutSessions)
            ..where((row) => row.id.equals(sessionId)))
          .write(WorkoutSessionsCompanion(updatedAt: Value(now)));
      return setId;
    });
  }

  Future<List<WorkoutSessionRecord>> listAllFinished() async {
    final rows =
        await (database.select(database.workoutSessions)
              ..where((session) => session.status.equals('finished'))
              ..orderBy([(session) => OrderingTerm.asc(session.startedAt)]))
            .get();
    return _hydrateAll(rows);
  }

  Future<List<WorkoutSessionRecord>> listFinishedBetween(
    String startLocalDate,
    String endLocalDate,
  ) async {
    final rows =
        await (database.select(database.workoutSessions)
              ..where(
                (session) =>
                    session.status.equals('finished') &
                    session.localDate.isBiggerOrEqualValue(startLocalDate) &
                    session.localDate.isSmallerOrEqualValue(endLocalDate),
              )
              ..orderBy([(session) => OrderingTerm.asc(session.startedAt)]))
            .get();
    return _hydrateAll(rows);
  }

  Future<void> finish(String sessionId) async {
    final now = clock.nowUtc();
    await database.transaction(() async {
      final session = await (database.select(
        database.workoutSessions,
      )..where((row) => row.id.equals(sessionId))).getSingleOrNull();
      if (session == null) {
        throw StateError('训练会话不存在或已被删除。');
      }
      if (session.status != 'active') {
        throw StateError('训练会话已经结束。');
      }
      await (database.update(
        database.workoutSessions,
      )..where((row) => row.id.equals(sessionId))).write(
        WorkoutSessionsCompanion(
          status: const Value('finished'),
          finishedAt: Value(now),
          updatedAt: Value(now),
        ),
      );
    });
  }

  void _validateDraft(WorkoutSetDraft draft) {
    final weight = draft.weightKg;
    if (!weight.isFinite || weight < 0) {
      throw const FormatException('重量必须是非负数。');
    }
    if (draft.reps < 1) {
      throw const FormatException('次数必须是正整数。');
    }
    final rpe = draft.rpe;
    if (rpe != null && (!rpe.isFinite || rpe < 1 || rpe > 10)) {
      throw const FormatException('RPE 必须在 1 到 10 之间。');
    }
  }

  /// 一条 join 查询批量装载所有会话的组数，避免每会话单独查询（N+1）。
  /// 全局按 sortOrder 升序取回，按 sessionId 分组后每会话内顺序不变。
  Future<List<WorkoutSessionRecord>> _hydrateAll(
    List<WorkoutSession> rows,
  ) async {
    if (rows.isEmpty) return const [];
    final setQuery = database.select(database.workoutSets).join([
      innerJoin(
        database.exercises,
        database.exercises.id.equalsExp(database.workoutSets.exerciseId),
      ),
    ]);
    setQuery.where(
      database.workoutSets.sessionId.isIn(rows.map((row) => row.id)),
    );
    setQuery.orderBy([OrderingTerm.asc(database.workoutSets.sortOrder)]);
    final setRows = await setQuery.get();
    final setsBySession = <String, List<TypedResult>>{};
    for (final joined in setRows) {
      setsBySession
          .putIfAbsent(
            joined.readTable(database.workoutSets).sessionId,
            () => [],
          )
          .add(joined);
    }
    return [
      for (final row in rows)
        _recordFromRow(row, setsBySession[row.id] ?? const []),
    ];
  }

  WorkoutSessionRecord _recordFromRow(
    WorkoutSession row,
    List<TypedResult> setRows,
  ) => WorkoutSessionRecord(
    id: row.id,
    planId: row.planId,
    localDate: row.localDate,
    startedAt: row.startedAt,
    finishedAt: row.finishedAt,
    status: row.status,
    sets: setRows
        .map(
          (joined) => WorkoutSetRecord(
            id: joined.readTable(database.workoutSets).id,
            sessionId: joined.readTable(database.workoutSets).sessionId,
            plannedExerciseId: joined
                .readTable(database.workoutSets)
                .plannedExerciseId,
            exerciseId: joined.readTable(database.workoutSets).exerciseId,
            exerciseName: joined.readTable(database.exercises).name,
            equipment: Equipment.fromStoredValue(
              joined.readTable(database.exercises).equipment,
            ),
            sortOrder: joined.readTable(database.workoutSets).sortOrder,
            weightKg: joined.readTable(database.workoutSets).weightKg,
            reps: joined.readTable(database.workoutSets).reps,
            rpe: joined.readTable(database.workoutSets).rpe,
            completedAt: joined.readTable(database.workoutSets).completedAt,
          ),
        )
        .toList(growable: false),
  );

  Future<WorkoutSessionRecord> _hydrate(WorkoutSession row) async {
    final setQuery = database.select(database.workoutSets).join([
      innerJoin(
        database.exercises,
        database.exercises.id.equalsExp(database.workoutSets.exerciseId),
      ),
    ]);
    setQuery.where(database.workoutSets.sessionId.equals(row.id));
    setQuery.orderBy([OrderingTerm.asc(database.workoutSets.sortOrder)]);
    final setRows = await setQuery.get();
    return _recordFromRow(row, setRows);
  }
}
