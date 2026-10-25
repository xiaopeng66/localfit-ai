import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/training/data/exercise_seed_importer.dart';
import 'package:localfit_ai/features/training/domain/exercise_record.dart';

import '../../support/food_fixture.dart';

/// 随包动作种子 v3 的导入测试（docs/28 §7.2/§7.3）。
///
/// v3（2026-10-04）把动作库从 60 条扩到 312 条并换了上游
/// （yuhonas/free-exercise-db，Unlicense）。这里钉住四类事：
///   1. **规模与分布**：312 条、7 肌群下限、6 档器械每档 ≥ 20、无拉丁字母名、
///      无重名、id 唯一、难度/常用度有值；
///   2. **v1/v2 续号**：v2 的 58 个动作换源后仍在（id 不变，只是被原地刷新），
///      2 条重名重复行不再收录；
///   3. **一次性清理**：坏行只在「v3 不再收录 + 没有被计划/历史引用」时才删；
///   4. **幂等**：第二次导入不写。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase database;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await seedFoodFixture(database);
  });

  tearDown(() => database.close());

  /// v2 种子里的 60 条 id（重名重复的那两条除外），换源后必须全部还在。
  const v2KeptIds = [
    'ex-barbell-bench-press',
    'ex-dumbbell-bench-press',
    'ex-push-up',
    'ex-machine-chest-fly',
    'ex-bb-incline-press',
    'ex-db-incline-press',
    'ex-decline-bb-press',
    'ex-decline-db-press',
    'ex-cable-crossover',
    'ex-chest-press-machine',
    'ex-wide-push-up',
    'ex-barbell-row',
    'ex-lat-pulldown',
    'ex-pull-up',
    'ex-seated-cable-row',
    'ex-underhand-pulldown',
    'ex-t-bar-row',
    'ex-seated-good-morning',
    'ex-shrugs',
    'ex-barbell-squat',
    'ex-leg-press',
    'ex-romanian-deadlift',
    'ex-dumbbell-lunge',
    'ex-leg-extension',
    'ex-leg-curl',
    'ex-seated-leg-curl',
    'ex-smith-squat',
    'ex-walking-lunge',
    'ex-barbell-overhead-press',
    'ex-lateral-raise',
    'ex-face-pull',
    'ex-db-shoulder-press',
    'ex-bb-shoulder-press',
    'ex-dumbbell-lateral-raise',
    'ex-rear-delt-fly',
    'ex-arnold-press',
    'ex-barbell-curl',
    'ex-dumbbell-curl',
    'ex-cable-triceps-pushdown',
    'ex-hammer-curl',
    'ex-preacher-curl',
    'ex-concentration-curl',
    'ex-triceps-kickback',
    'ex-close-grip-bench',
    'ex-close-grip-pushup',
    'ex-dumbbell-overhead-triceps-extension',
    'ex-plank',
    'ex-crunch',
    'ex-hanging-leg-raise',
    'ex-russian-twist',
    'ex-deadlift',
    // manual_rows.tsv：上游没有对应条目、事实沿用 v2 手写保留的 7 条。
    'ex-wide-grip-pullup',
    'ex-lunge',
    'ex-side-lunge',
    'ex-bulgarian-split-squat',
    'ex-calf-raise',
    'ex-front-raise',
    'ex-burpee',
  ];

  /// v2 里有、v3 不再收录的重名重复行（导入时按「未被引用」清理）。
  const v2DroppedIds = ['ex-triceps-pushdown-rope', 'ex-overhead-triceps-ext'];

  test('imports the expanded v3 exercise library once', () async {
    await const ExerciseSeedImporter().importIfNeeded(database);
    final first = await database.select(database.exercises).get();

    expect(first, hasLength(312));
    expect(first.every((row) => row.source == 'seed-v3'), isTrue);
    expect(first.every((row) => row.isUserCreated == false), isTrue);
    // docs/21 §5.5：v3 的每条都带难度与常用度标注。
    expect(first.every((row) => row.difficulty != null), isTrue);
    expect(first.every((row) => row.popularity != null), isTrue);
    expect(
      first.every((row) => row.popularity! >= 0 && row.popularity! <= 100),
      isTrue,
    );
    // id 唯一 + ex- 前缀；名称不重名（v2 的两条重名重复行已清掉）。
    expect(first.map((row) => row.id).toSet(), hasLength(312));
    expect(first.every((row) => row.id.startsWith('ex-')), isTrue);
    expect(first.map((row) => row.name).toSet(), hasLength(312));
    // 译名里不许混拉丁字母（构建脚本对缺译/含拉丁字母直接失败）。
    expect(
      first.where((row) => RegExp('[A-Za-z]').hasMatch(row.name)),
      isEmpty,
    );
    // 难度枚举与肌群/器械枚举都在受支持取值内（导入器用 fromStoredValue 解析，
    // 解析不过会直接抛，所以这里断言的是「值本身合法」）。
    expect(first.map((row) => row.difficulty).toSet(), {
      'beginner',
      'intermediate',
      'advanced',
    });
    expect(
      first.map((row) => row.muscleGroup).toSet(),
      MuscleGroup.values.map((group) => group.name).toSet(),
    );
    expect(
      first.map((row) => row.equipment).toSet(),
      Equipment.values.map((equipment) => equipment.name).toSet(),
    );

    await const ExerciseSeedImporter().importIfNeeded(database);
    expect(await database.select(database.exercises).get(), first);
  });

  test('meets the docs/28 §7.2 distribution floors', () async {
    await const ExerciseSeedImporter().importIfNeeded(database);
    final rows = await database.select(database.exercises).get();

    // 7 肌群条数下限（docs/28 §7.2 的目标 − 2 的容差）。
    const groupFloors = {
      'chest': 38,
      'back': 43,
      'legs': 53,
      'shoulders': 38,
      'arms': 43,
      'core': 43,
      'fullBody': 28,
    };
    final byGroup = <String, int>{};
    for (final row in rows) {
      byGroup[row.muscleGroup] = (byGroup[row.muscleGroup] ?? 0) + 1;
    }
    for (final entry in groupFloors.entries) {
      expect(
        byGroup[entry.key] ?? 0,
        greaterThanOrEqualTo(entry.value),
        reason: '肌群 ${entry.key} 的动作数不达标（实际 ${byGroup[entry.key] ?? 0}）',
      );
    }

    // 6 档器械每档 ≥ 20 条（docs/28 §7.2）。
    final byEquipment = <String, int>{};
    for (final row in rows) {
      byEquipment[row.equipment] = (byEquipment[row.equipment] ?? 0) + 1;
    }
    for (final equipment in Equipment.values) {
      expect(
        byEquipment[equipment.name] ?? 0,
        greaterThanOrEqualTo(20),
        reason:
            '器械 ${equipment.name} 的动作数不足 20（实际 ${byEquipment[equipment.name] ?? 0}）',
      );
    }

    // 每个肌群至少有一条高级动作（难度分档对用户可见）。
    final advanced = <String, int>{};
    for (final row in rows.where((row) => row.difficulty == 'advanced')) {
      advanced[row.muscleGroup] = (advanced[row.muscleGroup] ?? 0) + 1;
    }
    for (final group in MuscleGroup.values) {
      expect(
        advanced[group.name] ?? 0,
        greaterThanOrEqualTo(1),
        reason: '肌群 ${group.name} 没有任何高级动作',
      );
    }
  });

  test('keeps the whole v2 library (same ids, refreshed in place)', () async {
    await const ExerciseSeedImporter().importIfNeeded(database);
    final rows = await database.select(database.exercises).get();
    final ids = rows.map((row) => row.id).toSet();

    final missing = v2KeptIds.where((id) => !ids.contains(id)).toList();
    expect(missing, isEmpty, reason: '换源后这些老动作消失了：$missing');
    // 两条重名重复行不再收录（否则同一动作名在库里出现两条）。
    expect(ids.intersection(v2DroppedIds.toSet()), isEmpty);

    final byId = {for (final row in rows) row.id: row};
    // v2 的 3 条已登记错译在 v3 里用同一个 id 写了正确名字（不删、原地修正）。
    expect(byId['ex-seated-good-morning']!.name, '坐姿早安式');
    expect(byId['ex-rear-delt-fly']!.name, '绳索反向飞鸟');
    expect(byId['ex-russian-twist']!.name, '俄罗斯转体');
    // v1/v2 里的老动作实体（名字与事实）没有丢。
    expect(byId['ex-barbell-squat']!.name, '杠铃深蹲');
    expect(byId['ex-barbell-squat']!.muscleGroup, 'legs');
    expect(byId['ex-push-up']!.name, '俯卧撑');
    expect(byId['ex-plank']!.name, '平板支撑');
  });

  test('drops the two duplicate rows when nothing references them', () async {
    // 先假装库里是 v2：把两条重名重复行插进去（未被任何计划/历史引用）。
    final now = DateTime.utc(2026, 1, 1);
    await database.batch((batch) {
      batch.insertAll(database.exercises, [
        for (final id in v2DroppedIds)
          ExercisesCompanion.insert(
            id: id,
            name: '绳索下压',
            muscleGroup: 'arms',
            equipment: 'cable',
            source: 'seed-v2',
            createdAt: now,
            updatedAt: now,
          ),
      ]);
    });

    await const ExerciseSeedImporter().importIfNeeded(database);

    final rows = await database.select(database.exercises).get();
    expect(rows.where((row) => v2DroppedIds.contains(row.id)), isEmpty);
  });

  test('keeps a bad row that a workout still references', () async {
    // 同一个坏 id，但这次它被一份训练计划引用：删掉会让计划指空，必须留着。
    final now = DateTime.utc(2026, 1, 1);
    await database
        .into(database.exercises)
        .insert(
          ExercisesCompanion.insert(
            id: 'ex-triceps-pushdown-rope',
            name: '绳索下压',
            muscleGroup: 'arms',
            equipment: 'cable',
            source: 'seed-v2',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await database
        .into(database.workoutPlans)
        .insert(
          WorkoutPlansCompanion.insert(
            id: 'plan-1',
            name: '上肢日',
            source: 'user',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await database
        .into(database.workoutDays)
        .insert(
          WorkoutDaysCompanion.insert(
            id: 'day-1',
            planId: 'plan-1',
            weekday: 1,
            sortOrder: 0,
          ),
        );
    await database
        .into(database.plannedExercises)
        .insert(
          PlannedExercisesCompanion.insert(
            id: 'pe-1',
            dayId: 'day-1',
            exerciseId: 'ex-triceps-pushdown-rope',
            sortOrder: 0,
            targetSets: 3,
            targetReps: 10,
            createdAt: now,
            updatedAt: now,
          ),
        );

    await const ExerciseSeedImporter().importIfNeeded(database);

    final kept = await (database.select(
      database.exercises,
    )..where((row) => row.id.equals('ex-triceps-pushdown-rope'))).get();
    expect(kept, hasLength(1), reason: '被训练计划引用的旧行不能让计划指空');
  });

  test('v3 seed upgrades pre-existing v1 rows in place', () async {
    // 模拟「装过 v1 版应用的库」：已有 seed-v1 的 60 条、两列为 null。
    final now = DateTime.utc(2026, 1, 1);
    await database.batch((batch) {
      batch.insertAll(database.exercises, [
        for (var index = 0; index < 60; index++)
          ExercisesCompanion.insert(
            id: 'stale-$index',
            name: '旧动作 $index',
            muscleGroup: 'chest',
            equipment: 'barbell',
            source: 'seed-v1',
            createdAt: now,
            updatedAt: now,
          ),
      ]);
    });

    await const ExerciseSeedImporter().importIfNeeded(database);

    // 新种子的 312 条都在，且都标注了难度/常用度。
    final rows = await database.select(database.exercises).get();
    final seeded = rows.where((row) => row.source == 'seed-v3').toList();
    expect(seeded, hasLength(312));
    expect(seeded.every((row) => row.difficulty != null), isTrue);

    // 旧 v1 行不会被删——迁移只覆盖同 id 的行，不认识的 id 原样留着。
    expect(rows.where((row) => row.source == 'seed-v1'), hasLength(60));
  });

  test('rejects an unsupported seed document without writing', () async {
    // 用**随包且版本号不匹配**的文件喂错导入器：exercises.v1.json 是随包的旧动作
    // 种子（version 1），喂给要 version 3 的导入器必须直接拒绝，不能当种子写入。
    // （这个位置早先用 foods.v5.json——2026-10-13 起食物种子已退役、不再随包，
    // rootBundle 取不到就不再是版本拒绝了；见 docs/32 §4 T13。）
    await expectLater(
      const ExerciseSeedImporter(assetPath: 'assets/seed/exercises.v1.json')
          .importIfNeeded(database),
      throwsFormatException,
    );
    expect(await database.select(database.exercises).get(), isEmpty);
  });

  test(
    'rejects the v2 seed document (version 2 is not this importer)',
    () async {
      // v2/v3 的幂等键不同（seed-v2 / seed-v3），版本号也不同：把 v2 文件喂给
      // v3 导入器必须直接拒绝，不能把 60 条当成 312 条的一部分混进来。
      await expectLater(
        const ExerciseSeedImporter(assetPath: 'assets/seed/exercises.v2.json')
            .importIfNeeded(database),
        throwsFormatException,
      );
      expect(await database.select(database.exercises).get(), isEmpty);
    },
  );
}
