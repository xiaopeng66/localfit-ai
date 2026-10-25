import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/features/training/application/training_stats.dart';
import 'package:localfit_ai/features/training/domain/exercise_record.dart';
import 'package:localfit_ai/features/training/domain/workout_plan.dart';
import 'package:localfit_ai/features/training/domain/workout_session.dart';

WorkoutSetRecord setRecord({
  required String exerciseId,
  required String exerciseName,
  required double weightKg,
  required int reps,
  DateTime? completedAt,
}) => WorkoutSetRecord(
  id: 'set-$exerciseId-$weightKg-$reps',
  sessionId: 'session-1',
  plannedExerciseId: null,
  exerciseId: exerciseId,
  exerciseName: exerciseName,
  equipment: Equipment.barbell,
  sortOrder: 0,
  weightKg: weightKg,
  reps: reps,
  rpe: null,
  completedAt: completedAt ?? DateTime.utc(2026, 9, 10, 18),
);

WorkoutSessionRecord sessionRecord({
  required String id,
  String? planId,
  required String localDate,
  String status = 'finished',
  required List<WorkoutSetRecord> sets,
}) => WorkoutSessionRecord(
  id: id,
  planId: planId,
  localDate: localDate,
  startedAt: DateTime.utc(2026, 9, 10, 17),
  finishedAt: status == 'finished' ? DateTime.utc(2026, 9, 10, 18) : null,
  status: status,
  sets: sets,
);

void main() {
  const calculator = TrainingStatsCalculator();

  test('sums weekly training volume across finished sessions', () {
    final sessions = [
      sessionRecord(
        id: 's1',
        localDate: '2026-09-07',
        sets: [
          setRecord(
            exerciseId: 'ex-a',
            exerciseName: '深蹲',
            weightKg: 60,
            reps: 8,
          ),
        ],
      ),
      sessionRecord(
        id: 's2',
        localDate: '2026-09-09',
        sets: [
          setRecord(
            exerciseId: 'ex-a',
            exerciseName: '深蹲',
            weightKg: 70,
            reps: 5,
          ),
          setRecord(
            exerciseId: 'ex-b',
            exerciseName: '卧推',
            weightKg: 40,
            reps: 10,
          ),
        ],
      ),
      sessionRecord(
        id: 's3',
        localDate: '2026-09-08',
        status: 'active',
        sets: [
          setRecord(
            exerciseId: 'ex-a',
            exerciseName: '深蹲',
            weightKg: 100,
            reps: 10,
          ),
        ],
      ),
    ];

    expect(calculator.weeklyVolumeKg(sessions), 60 * 8 + 70 * 5 + 40 * 10);
  });

  test('keeps the heaviest set per exercise as the personal record', () {
    final sessions = [
      sessionRecord(
        id: 's1',
        localDate: '2026-09-07',
        sets: [
          setRecord(
            exerciseId: 'ex-a',
            exerciseName: '深蹲',
            weightKg: 80,
            reps: 5,
          ),
          setRecord(
            exerciseId: 'ex-b',
            exerciseName: '卧推',
            weightKg: 50,
            reps: 8,
          ),
        ],
      ),
      sessionRecord(
        id: 's2',
        localDate: '2026-09-09',
        sets: [
          setRecord(
            exerciseId: 'ex-a',
            exerciseName: '深蹲',
            weightKg: 80,
            reps: 6,
          ),
          setRecord(
            exerciseId: 'ex-a',
            exerciseName: '深蹲',
            weightKg: 70,
            reps: 10,
          ),
        ],
      ),
      sessionRecord(
        id: 's3',
        localDate: '2026-09-09',
        status: 'active',
        sets: [
          setRecord(
            exerciseId: 'ex-b',
            exerciseName: '卧推',
            weightKg: 999,
            reps: 1,
          ),
        ],
      ),
    ];

    final records = calculator.personalRecords(sessions);
    expect(records, hasLength(2));
    final squat = records.firstWhere((record) => record.exerciseId == 'ex-a');
    expect(squat.weightKg, 80);
    expect(squat.reps, 6);
    final bench = records.firstWhere((record) => record.exerciseId == 'ex-b');
    expect(bench.weightKg, 50);
    expect(records.first.exerciseId, 'ex-a');
  });

  test('computes weekly completion from scheduled weekdays and sessions', () {
    WorkoutPlanDraft(
      name: '三分化',
      days: [
        WorkoutPlanDayDraft(weekday: 1, entries: []),
        WorkoutPlanDayDraft(weekday: 3, entries: []),
        WorkoutPlanDayDraft(weekday: 5, entries: []),
      ],
    );
    // Week of 2026-09-07 (Monday) .. 2026-09-13 (Sunday). Today is Thursday.
    final sessions = [
      sessionRecord(
        id: 's1',
        planId: 'plan-1',
        localDate: '2026-09-07',
        sets: const [],
      ),
      sessionRecord(
        id: 's2',
        planId: 'plan-1',
        localDate: '2026-09-09',
        sets: const [],
      ),
      sessionRecord(
        id: 's3',
        planId: 'plan-2',
        localDate: '2026-09-11',
        sets: const [],
      ),
    ];

    final rate = calculator.weeklyCompletion(
      planId: 'plan-1',
      planWeekdays: const [1, 3, 5],
      weekStart: DateTime(2026, 9, 7),
      today: DateTime(2026, 9, 10),
      finishedSessions: sessions,
    );

    expect(rate, isNotNull);
    expect(rate!.scheduledDays, 2);
    expect(rate.completedDays, 2);
    expect(rate.ratio, 1);

    final withMissed = calculator.weeklyCompletion(
      planId: 'plan-1',
      planWeekdays: const [1, 3, 5],
      weekStart: DateTime(2026, 9, 7),
      today: DateTime(2026, 9, 12),
      finishedSessions: sessions,
    );
    expect(withMissed!.scheduledDays, 3);
    expect(withMissed.completedDays, 2);
    expect(withMissed.ratio, closeTo(2 / 3, 0.0001));
  });

  test('returns no completion when nothing is scheduled yet', () {
    final rate = calculator.weeklyCompletion(
      planId: 'plan-1',
      planWeekdays: const [1, 3],
      weekStart: DateTime(2026, 9, 14),
      today: DateTime(2026, 9, 12),
      finishedSessions: const [],
    );
    expect(rate, isNull);
  });

  test('存库日期不可解析时跳过该会话，不让整页崩掉', () {
    // docs/11 §3-F：`localDate` 是未加约束的 TextColumn，恢复备份时不校验
    // 字段值（`restore_localfit_data.dart` 只校验 JSON 形状），畸形日期可以
    // 落库。读取侧不能裸 `int.parse`——那样会让训练页在 build 里抛
    // FormatException（红屏），且每次进页都复现。
    final sessions = [
      sessionRecord(
        id: 'bad',
        planId: 'plan-1',
        localDate: 'not-a-date',
        sets: const [],
      ),
      sessionRecord(
        id: 'good',
        planId: 'plan-1',
        localDate: '2026-09-07',
        sets: const [],
      ),
    ];

    final rate = calculator.weeklyCompletion(
      planId: 'plan-1',
      planWeekdays: const [1],
      weekStart: DateTime(2026, 9, 7),
      today: DateTime(2026, 9, 7),
      finishedSessions: sessions,
    );

    expect(rate, isNotNull);
    expect(rate!.scheduledDays, 1);
    // 只有可解析的那条计入完成；坏日期那条既不计入也不抛异常。
    expect(rate.completedDays, 1);
  });

  // 训练趋势 (training trend) tests
  test('trainingTrendWeeklyVolume returns empty list when no sessions', () {
    final sessions = const <WorkoutSessionRecord>[];
    final today = DateTime(
      2026,
      9,
      13,
    ); // Wednesday of week 37? (assuming week 37)
    final trend = calculator.trainingTrendWeeklyVolume(
      sessions: sessions,
      endOfLatestWeek: today,
      weeks: 4,
    );
    expect(trend, equals([0.0, 0.0, 0.0, 0.0]));
  });

  test(
    'trainingTrendWeeklyVolume aggregates volume by ISO week (Monday start)',
    () {
      final session1 = sessionRecord(
        id: 's1',
        localDate: '2026-09-07', // Monday of week 36
        sets: [
          setRecord(
            exerciseId: 'ex-squat',
            exerciseName: '深蹲',
            weightKg: 100,
            reps: 5,
          ),
          setRecord(
            exerciseId: 'ex-bench',
            exerciseName: '卧推',
            weightKg: 50,
            reps: 8,
          ),
        ],
      );
      final session2 = sessionRecord(
        id: 's2',
        localDate: '2026-09-14', // Monday of week 37 (one week later)
        sets: [
          setRecord(
            exerciseId: 'ex-squat',
            exerciseName: '深蹲',
            weightKg: 80,
            reps: 6,
          ),
        ],
      );
      final session3 = sessionRecord(
        id: 's3',
        localDate: '2026-09-10', // Friday of week 36
        sets: [
          setRecord(
            exerciseId: 'ex-deadlift',
            exerciseName: '硬拉',
            weightKg: 120,
            reps: 3,
          ),
        ],
      );

      final today = DateTime(2026, 9, 14); // Monday of week 37
      final trend = calculator.trainingTrendWeeklyVolume(
        sessions: [session1, session2, session3],
        endOfLatestWeek: today,
        weeks: 5,
      );
      // 返回**时间升序**：index 0 = 最早那周，末位 = 本周（趋势图从左到右读）。
      // 5 周窗口 = 第 33、34、35、36、37 周。
      // 第 36 周：(100*5)+(50*8)+(120*3) = 500+400+360 = 1260
      // 第 37 周：80*6 = 480
      expect(trend, equals([0.0, 0.0, 0.0, 1260.0, 480.0]));
    },
  );

  test('trainingTrendWeeklyVolume 跨年不产生断崖', () {
    // ISO 周号实现的经典失效：跨年后第 1 周会排到第 52 周前面，图上出现
    // 断崖。这里锚定「按日期差分桶」：2025-12-29 与 2026-01-05 都是周一，
    // 必须落在相邻两格。
    final beforeNewYear = sessionRecord(
      id: 'ny-1',
      localDate: '2025-12-29',
      sets: [
        setRecord(
          exerciseId: 'ex-squat',
          exerciseName: '深蹲',
          weightKg: 100,
          reps: 5,
        ),
      ],
    );
    final afterNewYear = sessionRecord(
      id: 'ny-2',
      localDate: '2026-01-05',
      sets: [
        setRecord(
          exerciseId: 'ex-squat',
          exerciseName: '深蹲',
          weightKg: 100,
          reps: 10,
        ),
      ],
    );

    final trend = calculator.trainingTrendWeeklyVolume(
      sessions: [beforeNewYear, afterNewYear],
      endOfLatestWeek: DateTime(2026, 1, 5),
      weeks: 2,
    );
    expect(trend, equals([500.0, 1000.0]));
  });

  test('muscleGroupDistribution aggregates volume per muscle group', () {
    final exerciseA = ExerciseRecord(
      id: 'ex-a',
      name: '深蹲',
      muscleGroup: MuscleGroup.legs,
      equipment: Equipment.barbell,
      difficulty: ExerciseDifficulty.beginner,
      popularity: 10,
      isUserCreated: false,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );
    final exerciseB = ExerciseRecord(
      id: 'ex-b',
      name: '卧推',
      muscleGroup: MuscleGroup.chest,
      equipment: Equipment.barbell,
      difficulty: ExerciseDifficulty.intermediate,
      popularity: 20,
      isUserCreated: false,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );
    final sessions = [
      sessionRecord(
        id: 's1',
        localDate: '2026-09-07',
        sets: [
          setRecord(
            exerciseId: 'ex-a',
            exerciseName: '深蹲',
            weightKg: 60,
            reps: 8,
          ),
          setRecord(
            exerciseId: 'ex-b',
            exerciseName: '卧推',
            weightKg: 40,
            reps: 10,
          ),
        ],
      ),
    ];

    final distribution = calculator.muscleGroupDistribution(
      sessions: sessions,
      exercises: [exerciseA, exerciseB],
    );
    expect(distribution[MuscleGroup.legs], closeTo(60 * 8, 0.01));
    expect(distribution[MuscleGroup.chest], closeTo(40 * 10, 0.01));
    // Other muscle groups should not be present or should be zero.
    expect(distribution[MuscleGroup.back], isNull);
  });

  test('muscleGroupDistribution handles missing exercise references', () {
    final sessions = [
      sessionRecord(
        id: 's1',
        localDate: '2026-09-07',
        sets: [
          setRecord(
            exerciseId: 'missing',
            exerciseName: '未知',
            weightKg: 10,
            reps: 5,
          ),
        ],
      ),
    ];
    final distribution = calculator.muscleGroupDistribution(
      sessions: sessions,
      exercises: const <ExerciseRecord>[],
    );
    expect(distribution, isEmpty);
  });

  test('mostUsedExercises returns top N by set count', () {
    final sessions = [
      sessionRecord(
        id: 's1',
        localDate: '2026-09-07',
        sets: [
          setRecord(
            exerciseId: 'ex-a',
            exerciseName: '深蹲',
            weightKg: 60,
            reps: 8,
          ),
          setRecord(
            exerciseId: 'ex-a',
            exerciseName: '深蹲',
            weightKg: 70,
            reps: 5,
          ),
          setRecord(
            exerciseId: 'ex-b',
            exerciseName: '卧推',
            weightKg: 40,
            reps: 10,
          ),
          setRecord(
            exerciseId: 'ex-c',
            exerciseName: '硬拉',
            weightKg: 100,
            reps: 3,
          ),
          setRecord(
            exerciseId: 'ex-c',
            exerciseName: '硬拉',
            weightKg: 90,
            reps: 4,
          ),
          setRecord(
            exerciseId: 'ex-c',
            exerciseName: '硬拉',
            weightKg: 80,
            reps: 5,
          ),
        ],
      ),
    ];

    final mostUsed = calculator.mostUsedExercises(sessions: sessions, limit: 2);
    expect(mostUsed, hasLength(2));
    expect(mostUsed[0].exerciseId, 'ex-c');
    expect(mostUsed[0].setCount, 3);
    expect(mostUsed[0].volume, 100 * 3 + 90 * 4 + 80 * 5);
    expect(mostUsed[1].exerciseId, 'ex-a');
    expect(mostUsed[1].setCount, 2);
  });

  test('mostUsedExercises returns empty list when limit is zero', () {
    final sessions = [
      sessionRecord(id: 's1', localDate: '2026-09-07', sets: const []),
    ];
    final mostUsed = calculator.mostUsedExercises(sessions: sessions, limit: 0);
    expect(mostUsed, isEmpty);
  });

  test(
    'mostUsedExercises returns empty list when there are no finished sessions',
    () {
      final sessions = [
        sessionRecord(
          id: 's1',
          localDate: '2026-09-07',
          status: 'active',
          sets: const [],
        ),
      ];
      final mostUsed = calculator.mostUsedExercises(
        sessions: sessions,
        limit: 5,
      );
      expect(mostUsed, isEmpty);
    },
  );
}
