import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/hydration/application/update_water_target_ml.dart';
import 'package:localfit_ai/features/hydration/data/water_repository.dart';
import 'package:localfit_ai/features/settings/application/load_profile_overview.dart';

/// 水分目标写入（docs/32 §4 T9 / §3 D11 需求 72）。
///
/// 契约（逐条对应下面的断言）：
/// - **版本化**：今日已有生效行 ⇒ 就地更新；否则复制其余列插一条新版本行
///   （`effectiveDate = 今天`），**今天之前的日期仍读它们各自生效的那条**；
/// - 其余列（热量/三大宏量）逐字复制，不拿 schema 默认值冒充目标；
/// - 越界（0.5–6.0 L）拒绝；没有可依附的生效行直接拒绝（不造行）；
/// - 今日页（`WaterRepository.watchDay`）与「我的」页（`LoadProfileOverview`）
///   读到的目标同步变化。
void main() {
  late AppDatabase database;
  late UpdateWaterTargetMl useCase;
  late _MutableClock clock;

  const yesterday = '2026-10-12';
  const today = '2026-10-13';

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    clock = _MutableClock(DateTime.utc(2026, 10, 13, 4));
    useCase = UpdateWaterTargetMl(
      database: database,
      idGenerator: const UuidV7Generator(),
      clock: clock,
    );
    await _seedGoalRow(database, effectiveDate: yesterday);
  });

  tearDown(() => database.close());

  test('昨日生效 2000：今日写入 ⇒ 插新版本行，今日读新值、历史读旧值', () async {
    await useCase.run(targetMl: 2500, today: today);

    final rows = await database.select(database.dailyTargets).get();
    expect(rows, hasLength(2), reason: '新版一行，旧版还在（历史口径不动）');
    final fresh = rows.singleWhere((row) => row.effectiveDate == today);
    expect(fresh.waterTargetMl, 2500);
    // 其余列逐字复制（种子行热量 1800–2200 / 蛋白 90–120…），
    // 不拿 schema 默认值冒充这一天的目标。
    expect(fresh.calorieMinKcal, 1800);
    expect(fresh.calorieMaxKcal, 2200);
    expect(fresh.proteinMinGrams, 90);
    expect(fresh.proteinMaxGrams, 120);
    expect(fresh.goalId, 'goal-1');

    expect(await useCase.readCurrentMl(today), 2500);
    expect(await useCase.readCurrentMl(yesterday), 2000, reason: '昨天仍是旧目标');
    expect(
      await useCase.readCurrentMl('2026-10-11'),
      isNull,
      reason: '生效日之前没有行',
    );
  });

  test('今日已有生效行 ⇒ 就地更新：行数不变、id 不变、updatedAt 刷新', () async {
    await _seedGoalRow(database, effectiveDate: today, id: 'target-today');
    final before = (await database.select(database.dailyTargets).get())
        .singleWhere((row) => row.id == 'target-today');
    clock.value = DateTime.utc(2026, 10, 13, 5);

    await useCase.run(targetMl: 3000, today: today);

    final rows = await database.select(database.dailyTargets).get();
    expect(rows, hasLength(2), reason: '就地更新不新增行（含种子的昨日行）');
    final updated = rows.singleWhere((row) => row.id == 'target-today');
    expect(updated.waterTargetMl, 3000);
    expect(updated.updatedAt.isAfter(before.updatedAt), isTrue);
    expect(await useCase.readCurrentMl(today), 3000);
    expect(await useCase.readCurrentMl(yesterday), 2000, reason: '昨天的行一个字没动');
  });

  test('今日页与「我的」页读到的目标同步变化（联动）', () async {
    final waterRepository = WaterRepository(
      database: database,
      idGenerator: const UuidV7Generator(),
      clock: clock,
    );
    final overview = LoadProfileOverview(database: database, clock: clock);

    expect((await waterRepository.watchDay(today).first).targetMl, 2000);
    expect((await overview.run()).waterTargetMl, 2000);

    await useCase.run(targetMl: 2500, today: today);

    final summary = await waterRepository.watchDay(today).first;
    expect(summary.targetMl, 2500, reason: '今日页饮水条按新目标算达标');
    expect((await overview.run()).waterTargetMl, 2500, reason: '「我的」页进度环同源');
  });

  test('越界拒绝：0.4 L / 6.1 L 抛 WaterTargetException，库里一动不动', () async {
    await expectLater(
      useCase.run(targetMl: 400, today: today),
      throwsA(isA<WaterTargetException>()),
    );
    await expectLater(
      useCase.run(targetMl: 6100, today: today),
      throwsA(isA<WaterTargetException>()),
    );
    final rows = await database.select(database.dailyTargets).get();
    expect(rows, hasLength(1), reason: '只有种子那一行');
    expect(rows.single.waterTargetMl, 2000);
  });

  test('边界值 500 / 6000 收下', () async {
    await useCase.run(targetMl: 500, today: today);
    expect(await useCase.readCurrentMl(today), 500);
    await useCase.run(targetMl: 6000, today: today);
    expect(await useCase.readCurrentMl(today), 6000);
  });

  test('没有生效行（未建档）⇒ 拒绝且不造行', () async {
    await database.delete(database.dailyTargets).go();
    await expectLater(
      useCase.run(targetMl: 2500, today: today),
      throwsA(isA<WaterTargetException>()),
    );
    expect(await database.select(database.dailyTargets).get(), isEmpty);
    expect(await useCase.readCurrentMl(today), isNull);
  });
}

/// 可推进的时钟（`FixedAppClock.value` 是 final）：用来证明「就地更新」确实
/// 刷新了 `updatedAt`，而不是原地不动。
class _MutableClock implements AppClock {
  _MutableClock(this.value);

  DateTime value;

  @override
  DateTime nowUtc() => value.toUtc();
}

/// 种一条「建档时」的每日目标行：水量 2000（列默认值口径）+ 一组可辨认的
/// 热量/宏量值，用来证明新版本行是**复制**这些列而不是重造。
///
/// 需要先把 `profiles` / `goals` 两条上游行种上：`daily_targets.goal_id`
/// 有外键，drift 默认开着 `PRAGMA foreign_keys`。
Future<void> _seedGoalRow(
  AppDatabase database, {
  required String effectiveDate,
  String id = 'target-1',
}) async {
  final now = DateTime.utc(2026, 10, 12, 4);
  await database
      .into(database.profiles)
      .insertOnConflictUpdate(
        ProfilesCompanion.insert(
          id: 'p-1',
          activityLevel: 'moderate',
          createdAt: now,
          updatedAt: now,
        ),
      );
  await database
      .into(database.goals)
      .insertOnConflictUpdate(
        GoalsCompanion.insert(
          id: 'goal-1',
          profileId: 'p-1',
          type: 'maintain',
          calorieMinKcal: 1800,
          calorieMaxKcal: 2200,
          effectiveFrom: now,
          createdAt: now,
          updatedAt: now,
        ),
      );
  await database
      .into(database.dailyTargets)
      .insert(
        DailyTargetsCompanion.insert(
          id: id,
          goalId: 'goal-1',
          effectiveDate: effectiveDate,
          calorieMinKcal: 1800,
          calorieMaxKcal: 2200,
          proteinMinGrams: 90,
          proteinMaxGrams: 120,
          carbsMinGrams: 200,
          carbsMaxGrams: 260,
          fatMinGrams: 50,
          fatMaxGrams: 70,
          waterTargetMl: const Value(2000),
          createdAt: now,
          updatedAt: now,
        ),
      );
}
