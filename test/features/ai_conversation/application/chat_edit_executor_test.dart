import 'dart:convert';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/ai_conversation/application/chat_edit_executor.dart';
import 'package:localfit_ai/features/ai_memory/data/ai_memory_repository.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_command.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_registry.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_repair.dart';
import 'package:localfit_ai/features/campus_menus/application/menu_snapshot_store.dart';
import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart';
import 'package:localfit_ai/features/daily_plan/data/planning_constraints_repository.dart';
import 'package:localfit_ai/features/hydration/application/update_water_target_ml.dart';
import 'package:localfit_ai/features/progress/data/steps_repository.dart';
import 'package:localfit_ai/features/hydration/data/water_repository.dart';
import 'package:localfit_ai/features/nutrition/data/dish_library_repository.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/progress/data/measurement_repository.dart';
import 'package:localfit_ai/features/settings/data/profile_identity_repository.dart';
import 'package:localfit_ai/features/training/data/workout_plan_repository.dart';
import 'package:localfit_ai/features/training/data/workout_session_repository.dart';
import 'package:localfit_ai/features/training/domain/workout_plan.dart';
import 'package:localfit_ai/features/training/data/exercise_repository.dart';

import '../../../support/food_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 本地正午（同一口径）：写入用的 localDate 按本地日算，UTC 巧合时刻在
  // 偏移 ≥ +12 的时区会漂到次日（2026-10-08 缺陷排查）。
  final now = DateTime(2026, 10, 2, 12).toUtc();
  final registry = ChatEditCommandRegistry();

  late AppDatabase database;
  late RepositoryChatEditExecutor executor;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await seedFoodFixture(database);
    executor = _buildExecutor(database, now);
  });

  tearDown(() => database.close());

  ChatEditCommand cmd(String action, Map<String, Object> args) {
    final spec = registry.specOf(action)!;
    return ChatEditCommand(spec: spec, args: validateChatEditArgs(spec, args));
  }

  group('批次 B：菜单快照发布（2026-10-15 docs/34 §7）', () {
    // 夹具里的 `price_minor` 是 **legacy 容忍键**：退役前模型发过它，
    // 解码器忽略、不落库（2026-10-16 用户删掉菜品价格；docs/36 §3 S8-b）。
    const menuJson =
        '{"schema_version":1,"source_date":"2026-10-02",'
        '"venue_name":"三食堂","services":['
        '{"service_name":"4 号窗口","open_time":"11:00","close_time":"13:30",'
        '"items":[{"display_name":"番茄牛腩","price_minor":1250},'
        '{"display_name":"清炒时蔬","price_minor":600}]},'
        '{"service_name":"5 号窗口","open_time":"17:00","close_time":"19:30",'
        '"items":[{"display_name":"鸡腿饭","price_minor":1500}]}]}';

    test('合法草案：解码 → 发布，地点/窗口/菜品三张表都真的有行', () async {
      // 发布要求库里有校园（首次经「新建食堂地点」建立，与真实动线一致）
      expect(
        (await executor.apply(
          cmd('canteen.venue.create', {'name': '三食堂', 'campus': '南校区'}),
        )).ok,
        isTrue,
      );
      final out = await executor.apply(
        cmd('menu.snapshot.publish', {'menuJson': menuJson}),
      );
      expect(out.ok, isTrue, reason: out.message);

      final venue = await (database.select(
        database.venues,
      )..where((row) => row.name.equals('三食堂'))).getSingleOrNull();
      expect(venue, isNotNull);

      // 发布写的是**导入快照**（menu_snapshots + menu_services + menu_items），
      // 与文件导入同源；窗口/菜品挂在它的 snapshotId 下。
      final venueId = venue!.id;
      final snapshot =
          await (database.select(database.menuSnapshots)..where(
                (row) =>
                    row.venueId.equals(venueId) &
                    row.businessDate.equals('2026-10-02') &
                    row.status.equals('active'),
              ))
              .getSingleOrNull();
      expect(snapshot, isNotNull, reason: '发布应留下一条 active 快照');
      final snapshotId = snapshot!.id;
      final windows = await (database.select(
        database.menuServices,
      )..where((row) => row.snapshotId.equals(snapshotId))).get();
      expect(windows, hasLength(2));
      final dishes = await (database.select(
        database.menuItems,
      )..where((row) => row.serviceId.equals(windows.first.id))).get();
      expect(dishes, hasLength(2));
      expect(dishes.map((d) => d.displayName), contains('番茄牛腩'));
      // 草案里带着 legacy `price_minor`，落库行里**没有这一列**。
      expect(
        dishes.where((d) => d.toColumns(false).containsKey('price_minor')),
        isEmpty,
      );

      // **用户看得见**的判据：菜单 tab 的「今日推荐」入口就是
      // `activeSnapshotFor(venue, businessDate)` —— 同一天发布的那份必须能取到。
      final visible = await MenuSnapshotStore(database: database)
          .activeSnapshotFor(venueId: venueId, businessDate: '2026-10-02');
      expect(visible, isNotNull, reason: '发布后菜单 tab 的当日入口必须能看到它');
      expect(visible!.id, snapshotId);
    });

    test('草案以 **JSON 对象**（非字符串）给出时也收：真模型就是这么发的', () async {
      // 2026-10-15 实时矩阵实测：GLM-5.3 把 `menuJson` 发成对象，被
      // 「要是文本」挡下 ⇒ `jsonObjectAllowed` 开档，对象/字符串两条都收。
      await executor.apply(
        cmd('canteen.venue.create', {'name': '三食堂', 'campus': '南校区'}),
      );
      final asObject = await executor.apply(
        cmd('menu.snapshot.publish', {
          'menuJson': {
            'schema_version': 1,
            'source_date': '2026-10-02',
            'venue_name': '三食堂',
            'services': [
              {
                'service_name': '4 号窗口',
                'open_time': '11:00',
                'close_time': '13:30',
                'items': [
                  // legacy 键，见上；对象形态也走同一套容忍。
                  {'display_name': '番茄牛腩', 'price_minor': 1250},
                ],
              },
            ],
          },
        }),
      );
      expect(asObject.ok, isTrue, reason: asObject.message);
      expect(await database.select(database.menuServices).get(), hasLength(1));
      expect(await database.select(database.menuItems).get(), hasLength(1));
    });

    test('同内容再发一次：按 skipIfHashMatches 如实报「跳过重复」', () async {
      await executor.apply(
        cmd('canteen.venue.create', {'name': '三食堂', 'campus': '南校区'}),
      );
      expect(
        (await executor.apply(
          cmd('menu.snapshot.publish', {'menuJson': menuJson}),
        )).ok,
        isTrue,
      );
      final again = await executor.apply(
        cmd('menu.snapshot.publish', {'menuJson': menuJson}),
      );
      expect(again.ok, isTrue);
      expect(again.message, contains('跳过'));
    });

    test('坏草案：schema 版本错 / 缺 display_name ⇒ 人话拒绝，且不写任何行', () async {
      await executor.apply(
        cmd('canteen.venue.create', {'name': '三食堂', 'campus': '南校区'}),
      );
      final badVersion = await executor.apply(
        cmd('menu.snapshot.publish', {
          'menuJson': menuJson.replaceFirst(
            '"schema_version":1',
            '"schema_version":9',
          ),
        }),
      );
      expect(badVersion.ok, isFalse);
      expect(badVersion.message, contains('菜单草案不合格'));

      final missingName = await executor.apply(
        cmd('menu.snapshot.publish', {
          'menuJson': menuJson.replaceFirst(
            '"display_name":"番茄牛腩"',
            '"station_name":"4 号窗口"',
          ),
        }),
      );
      expect(missingName.ok, isFalse);
      expect(missingName.message, contains('菜单草案不合格'));

      // 地点是前面显式建的（合法存在）；坏草案**不许写进任何窗口/菜品**。
      expect(await database.select(database.menuServices).get(), isEmpty);
      expect(await database.select(database.menuItems).get(), isEmpty);
    });
  });

  group('批次 C：自建食物与资料/目标（2026-10-15 docs/34 §5）', () {
    test('food.update / food.delete：只动自建行；内置行如实拒绝且不抛异常', () async {
      await _seedProfile(database);
      // 自建一条（food.create 走的就是「自建」标记）
      final created = await executor.apply(
        cmd('food.create', {
          'name': '测试燕麦饮',
          'kcalPer100g': 62,
          'proteinPer100g': 1.2,
          'carbsPer100g': 9,
          'fatPer100g': 2.1,
        }),
      );
      expect(created.ok, isTrue, reason: created.message);
      final row = (await database.select(database.foods).get()).firstWhere(
        (f) => f.name == '测试燕麦饮',
      );

      final updated = await executor.apply(
        cmd('food.update', {
          'foodId': row.id,
          'name': '测试燕麦饮（改）',
          'kcalPer100g': 70,
          'proteinPer100g': 2.0,
          'carbsPer100g': 10,
          'fatPer100g': 2.5,
        }),
      );
      expect(updated.ok, isTrue, reason: updated.message);
      final after = (await database.select(database.foods).get()).firstWhere(
        (f) => f.id == row.id,
      );
      expect(after.name, '测试燕麦饮（改）');
      expect(after.kcalPer100g, 70);
      expect(after.isUserCreated, isTrue, reason: '自建标记不能被改丢');

      // 内置行（夹具里的米饭）：必须如实拒绝，**且不能抛异常逃逸 apply**
      final seedId = (await database.select(database.foods).get())
          .firstWhere((f) => !f.isUserCreated)
          .id;
      final builtinUpdate = await executor.apply(
        cmd('food.update', {
          'foodId': seedId,
          'name': '不许改',
          'kcalPer100g': 1,
          'proteinPer100g': 1,
          'carbsPer100g': 1,
          'fatPer100g': 1,
        }),
      );
      expect(builtinUpdate.ok, isFalse);
      expect(builtinUpdate.message, contains('内置'));
      final builtinDelete = await executor.apply(
        cmd('food.delete', {'foodId': seedId}),
      );
      expect(builtinDelete.ok, isFalse);
      expect(builtinDelete.message, contains('内置'));

      final deleted = await executor.apply(
        cmd('food.delete', {'foodId': row.id}),
      );
      expect(deleted.ok, isTrue, reason: deleted.message);
      expect(
        (await database.select(database.foods).get()).any(
          (f) => f.id == row.id,
        ),
        isFalse,
      );
    });

    test('profile.body.update：只写给了的字段，其余保留原值', () async {
      await _seedProfile(database);
      // 先放一份已有资料
      await executor.apply(
        cmd('profile.body.update', {
          'heightCm': 170,
          'birthYear': 1998,
          'sex': 'male',
        }),
      );
      final first = (await database.select(database.profiles).get()).single;
      expect(first.heightCm, 170);
      expect(first.birthYear, 1998);
      expect(first.biologicalSex, 'male');

      // 只改身高 ⇒ 出生年与性别必须原样保留
      final heightOnly = await executor.apply(
        cmd('profile.body.update', {'heightCm': 172}),
      );
      expect(heightOnly.ok, isTrue, reason: heightOnly.message);
      final second = (await database.select(database.profiles).get()).single;
      expect(second.heightCm, 172);
      expect(second.birthYear, 1998);
      expect(second.biologicalSex, 'male');

      // 非法性别：如实拒绝（不写库）
      final badSex = await executor.apply(
        cmd('profile.body.update', {'sex': 'whatever'}),
      );
      expect(badSex.ok, isFalse);
      expect(
        (await database.select(database.profiles).get()).single.biologicalSex,
        'male',
      );
    });

    test('targets.update：水目标写入生效行，步目标写入仓储（越界如实拒绝）', () async {
      await _seedProfile(database);
      // 水目标写在**生效的每日目标行**上（建档时由 onboarding 建出来），
      // 而该行有外键指 goals ⇒ 先插一条目标（`_seedProfile` 只建档案）。
      await database
          .into(database.goals)
          .insert(
            GoalsCompanion.insert(
              id: 'goal-1',
              profileId: 'profile-1',
              type: 'maintain',
              calorieMinKcal: 1700,
              calorieMaxKcal: 1900,
              effectiveFrom: DateTime.utc(2026, 10, 2, 12),
              createdAt: DateTime.utc(2026, 10, 2, 12),
              updatedAt: DateTime.utc(2026, 10, 2, 12),
            ),
          );
      await database
          .into(database.dailyTargets)
          .insert(
            DailyTargetsCompanion.insert(
              id: 'dt-1',
              goalId: 'goal-1',
              effectiveDate: '2026-10-02',
              calorieMinKcal: 1700,
              calorieMaxKcal: 1900,
              proteinMinGrams: 90,
              proteinMaxGrams: 130,
              carbsMinGrams: 180,
              carbsMaxGrams: 260,
              fatMinGrams: 40,
              fatMaxGrams: 70,
              createdAt: DateTime.utc(2026, 10, 2, 12),
              updatedAt: DateTime.utc(2026, 10, 2, 12),
            ),
          );

      final ok = await executor.apply(
        cmd('targets.update', {'waterMl': 2500, 'steps': 9000}),
      );
      expect(ok.ok, isTrue, reason: ok.message);
      final target =
          (await database.select(database.dailyTargets).get()).single;
      expect(target.waterTargetMl, 2500);
      final goalRow = await StepsRepository(
        database: database,
        channel: StepsChannel(),
        idGenerator: IdsForTest(),
        clock: FixedAppClock(DateTime(2026, 10, 2, 12).toUtc()),
      ).readDailyGoal();
      expect(goalRow, 9000);

      // 越界在**解码期**就被拦下（命令规格比仓储下限更严：500–6000 / 1000–50000）
      expect(
        () => cmd('targets.update', {'waterMl': 100}),
        throwsA(isA<ChatEditArgsException>()),
      );
      expect(
        () => cmd('targets.update', {'steps': 100}),
        throwsA(isA<ChatEditArgsException>()),
      );
      // 两个都没给 ⇒ 执行器如实拒绝（不空转）
      final empty = await executor.apply(cmd('targets.update', {}));
      expect(empty.ok, isFalse);
      expect(empty.message, contains('要说清'));
    });
  });

  group('批次 A：训练域六命令（2026-10-15 docs/34 §5）', () {
    Future<String> seedPlan() async {
      await _insertExercise(database, id: 'ex-squat-a', name: '杠铃深蹲', now: now);
      await _insertExercise(database, id: 'ex-plank-a', name: '平板支撑', now: now);
      return WorkoutPlanRepository(
        database: database,
        idGenerator: IdsForTest(),
        clock: FixedAppClock(DateTime(2026, 10, 2, 12).toUtc()),
      ).create(
        const WorkoutPlanDraft(
          name: '批次A 计划',
          days: [
            WorkoutPlanDayDraft(
              weekday: 1,
              entries: [
                PlannedExerciseDraft(
                  exerciseId: 'ex-squat-a',
                  targetSets: 3,
                  targetReps: 8,
                ),
              ],
            ),
          ],
        ),
      );
    }

    test('session.start → set.log → session.finish：一条链路真的写进会话与组', () async {
      await _seedProfile(database);
      final planId = await seedPlan(); // seedPlan 内含两条动作，别重复插

      final started = await executor.apply(
        cmd('session.start', {'planId': 'wplan:$planId'}),
      );
      expect(started.ok, isTrue, reason: started.message);
      final session =
          (await database.select(database.workoutSessions).get()).single;
      expect(session.status, 'active');

      // 已有活跃会话 ⇒ 再开一次必须被拒（不覆盖）
      final again = await executor.apply(cmd('session.start', {}));
      expect(again.ok, isFalse);
      expect(again.message, contains('进行中'));

      final logged = await executor.apply(
        cmd('set.log', {
          'exercise': '杠铃深蹲',
          'weightKg': 60,
          'reps': 8,
          'rpe': 7,
        }),
      );
      expect(logged.ok, isTrue, reason: logged.message);
      final sets = await database.select(database.workoutSets).get();
      expect(sets, hasLength(1));
      expect(sets.single.weightKg, 60);
      expect(sets.single.reps, 8);
      expect(sets.single.rpe, 7);

      // 库外动作名 ⇒ 如实拒绝
      final badExercise = await executor.apply(
        cmd('set.log', {'exercise': '不存在的动作', 'weightKg': 10, 'reps': 5}),
      );
      expect(badExercise.ok, isFalse);
      expect(badExercise.message, contains('动作库'));

      final finished = await executor.apply(cmd('session.finish', {}));
      expect(finished.ok, isTrue, reason: finished.message);
      final after =
          (await database.select(database.workoutSessions).get()).single;
      expect(after.status, 'finished');

      // 结束后再记组 ⇒ 如实拒绝
      final late = await executor.apply(
        cmd('set.log', {'exercise': '杠铃深蹲', 'weightKg': 60, 'reps': 8}),
      );
      expect(late.ok, isFalse);
      expect(late.message, contains('进行中'));
    });

    test('plan.entry.add / remove / plan.rename：编排与改名都落到计划仓储', () async {
      final planId = await seedPlan();

      final added = await executor.apply(
        cmd('plan.entry.add', {
          'planId': planId,
          'weekday': 4,
          'exercise': '平板支撑',
          'sets': 3,
          'reps': 45,
        }),
      );
      expect(added.ok, isTrue, reason: added.message);
      final entries = await database.select(database.plannedExercises).get();
      expect(entries, hasLength(2));
      final newEntry = entries.firstWhere((e) => e.exerciseId == 'ex-plank-a');

      final renamed = await executor.apply(
        cmd('plan.rename', {'planId': planId, 'name': '改名后的计划'}),
      );
      expect(renamed.ok, isTrue, reason: renamed.message);
      expect(
        (await database.select(database.workoutPlans).get()).single.name,
        '改名后的计划',
      );

      final removed = await executor.apply(
        cmd('plan.entry.remove', {'entryId': newEntry.id}),
      );
      expect(removed.ok, isTrue, reason: removed.message);
      expect(
        await database.select(database.plannedExercises).get(),
        hasLength(1),
      );

      // 目标不存在：三条命令都要如实拒绝
      expect(
        (await executor.apply(
          cmd('plan.entry.add', {
            'planId': '不存在',
            'weekday': 2,
            'exercise': '平板支撑',
            'sets': 1,
            'reps': 1,
          }),
        )).ok,
        isFalse,
      );
      expect(
        (await executor.apply(cmd('plan.entry.remove', {'entryId': '不存在'}))).ok,
        isFalse,
      );
      expect(
        (await executor.apply(
          cmd('plan.rename', {'planId': '不存在', 'name': 'x'}),
        )).ok,
        isFalse,
      );
    });
  });

  group('多步编辑的 id 稳定性（2026-10-15 实时矩阵暴露的间歇失败）', () {
    // 现场：真模型按「建餐 → 改克数 → 删条目 → 改备注 → 删整餐」五步走，
    // 第 5 步偶尔报「餐记录 mx-2 不存在」。先在确定性层面钉住契约：
    // **条目编辑与备注编辑都不得换掉餐 id**（仓储是 UPDATE + 重建条目，
    // 餐行 id 不变）——若这条绿而现场仍失败，就是模型回填了过期 id。
    test('建餐 → 改克数 → 改备注：餐 id 全程稳定且仍可删', () async {
      await _seedProfile(database);
      // 夹具自带米饭；鸡蛋用新建（`food.create`）补齐，避免依赖夹具细节。

      final created = await executor.apply(
        cmd('meal.create', {
          'slot': 'breakfast',
          'items': [
            {'food': '米饭', 'grams': 150},
          ],
        }),
      );
      expect(created.ok, isTrue, reason: created.message);
      final mealId = (await database.select(database.meals).get()).single.id;

      final firstItem =
          (await database.select(database.mealItems).get()).single.id;
      final itemEdited = await executor.apply(
        cmd('meal.item.update', {'itemId': firstItem, 'grams': 200}),
      );
      expect(itemEdited.ok, isTrue, reason: itemEdited.message);
      expect(
        await database.select(database.meals).get(),
        hasLength(1),
        reason: '条目编辑不得换掉餐行（id 必须仍是 $mealId）',
      );
      expect(
        (await database.select(database.meals).get()).single.id,
        mealId,
        reason: '餐 id 在条目编辑后必须不变',
      );

      final noted = await executor.apply(
        cmd('meal.update', {'mealId': mealId, 'notes': '去公司路上吃的'}),
      );
      expect(noted.ok, isTrue, reason: noted.message);
      expect(
        (await database.select(database.meals).get()).single.id,
        mealId,
        reason: '餐 id 在备注编辑后必须不变',
      );

      final deleted = await executor.apply(
        cmd('meal.delete', {'mealId': mealId}),
      );
      expect(deleted.ok, isTrue, reason: deleted.message);
      expect(await database.select(database.meals).get(), isEmpty);
    });
  });

  group('目标 id 的快照前缀（2026-10-15 真实 AI 测得）', () {
    // 快照把行印成 `[water:mx-1]` / `[meal:mx-2]` / `[canteen-dish:mx-3]`
    // ——方括号里的整串都像 id，真实模型（deepseek-v4.1-flash、GLM-5.3-Flash
    // 都实测出现过）会原样回填。执行器必须剥掉这层**展示别名**再按 id 查，
    // 否则「删掉刚才那条」这类多步编辑会假报「不存在（可能已被删除）」。
    test('water.delete 接受 `water:<id>` 形状；真不存在的 id 仍如实报不存在', () async {
      await _seedProfile(database);
      expect(
        (await executor.apply(cmd('water.add', {'amountMl': 250}))).ok,
        isTrue,
      );
      final row = (await database.select(database.waterIntakes).get()).single;

      final prefixed = await executor.apply(
        cmd('water.delete', {'waterId': 'water:${row.id}'}),
      );
      expect(prefixed.ok, isTrue, reason: prefixed.message);
      expect(await database.select(database.waterIntakes).get(), isEmpty);

      final bogus = await executor.apply(
        cmd('water.delete', {'waterId': 'water:不存在-1'}),
      );
      expect(bogus.ok, isFalse);
      expect(bogus.message, contains('不存在'));
    });

    test('workout.plan.delete 接受 `wplan:<id>` 形状（快照的训练计划前缀）', () async {
      await _insertExercise(
        database,
        id: 'ex-alias-squat',
        name: '别名深蹲',
        now: now,
      );
      final planId =
          await WorkoutPlanRepository(
            database: database,
            idGenerator: IdsForTest(),
            clock: FixedAppClock(DateTime(2026, 10, 2, 12).toUtc()),
          ).create(
            const WorkoutPlanDraft(
              name: '别名测试计划',
              days: [
                WorkoutPlanDayDraft(
                  weekday: 1,
                  entries: [
                    PlannedExerciseDraft(
                      exerciseId: 'ex-alias-squat',
                      targetSets: 3,
                      targetReps: 45,
                    ),
                  ],
                ),
              ],
            ),
          );
      final deleted = await executor.apply(
        cmd('workout.plan.delete', {'planId': 'wplan:$planId'}),
      );
      expect(deleted.ok, isTrue, reason: deleted.message);
      expect(await database.select(database.workoutPlans).get(), isEmpty);
    });
  });

  group('体重与饮水', () {
    test('weight.log：无档案时给可行动的失败，建档案后成功写库', () async {
      final blocked = await executor.apply(
        cmd('weight.log', {'weightKg': 72.5, 'localDate': '2026-10-01'}),
      );
      expect(blocked.ok, isFalse);
      expect(blocked.message, contains('建档'));

      await _seedProfile(database);
      // 2026-10-09（docs/31 S2，需求 45/46）：`weight.log` 的 args 里不再有
      // bodyFatPercent / muscleMassKg（注册表已删这两个 spec）。这里连
      // `notes` 一起走一遍，确认去掉体成分之后**其余参数照常落库**。
      final ok = await executor.apply(
        cmd('weight.log', {
          'weightKg': 72.5,
          'localDate': '2026-10-01',
          'notes': '早上称的',
        }),
      );
      expect(ok.ok, isTrue);
      final rows = await database.select(database.measurements).get();
      expect(rows, hasLength(1));
      expect(rows.single.weightKg, 72.5);
      expect(rows.single.localDate, '2026-10-01');
      expect(rows.single.notes, '早上称的');
    });

    test('water.add 成功；water.delete 删除与「不存在」都如实反馈', () async {
      expect(
        (await executor.apply(cmd('water.add', {'amountMl': 250}))).ok,
        isTrue,
      );
      final rows = await database.select(database.waterIntakes).get();
      expect(rows.single.amountMl, 250);

      final missing = await executor.apply(
        cmd('water.delete', {'waterId': 'nope'}),
      );
      expect(missing.ok, isFalse);
      expect(missing.message, contains('不存在'));

      final removed = await executor.apply(
        cmd('water.delete', {'waterId': rows.single.id}),
      );
      expect(removed.ok, isTrue);
      expect(await database.select(database.waterIntakes).get(), isEmpty);
    });
  });

  group('餐记录', () {
    test('meal.create：食物按精确名解析，写主记录与条目', () async {
      final result = await executor.apply(
        cmd('meal.create', {
          'slot': '早餐',
          'items': [
            {'food': '米饭', 'grams': 200.0},
          ],
          'notes': 'AI 帮记',
        }),
      );
      expect(result.ok, isTrue, reason: result.message);

      final meals = await database.select(database.meals).get();
      expect(meals, hasLength(1));
      expect(meals.single.localDate, '2026-10-02');
      final items = await database.select(database.mealItems).get();
      expect(items.single.foodNameSnapshot, contains('米饭'));
      expect(items.single.grams, 200);
    });

    test('meal.create：食物名不存在时失败且不写任何行', () async {
      final result = await executor.apply(
        cmd('meal.create', {
          'slot': '午餐',
          'items': [
            {'food': '不存在的食物', 'grams': 100.0},
          ],
        }),
      );
      expect(result.ok, isFalse);
      expect(result.message, contains('不存在的食物'));
      // 2026-10-16（用户：缺食材要弹出「创建鸡蛋食材」按钮）：失败结果
      // 带上**结构化**缺实体提示，编辑卡据此渲染可点修复按钮——
      // 不靠从人话里正则抠名字。
      expect(result.missingFoodName, '不存在的食物');
      expect(await database.select(database.meals).get(), isEmpty);
    });

    test('meal.create：加午餐后再加晚餐，午餐食物不会重复计入两份', () async {
      // 先记午餐（米饭）。
      final first = await executor.apply(
        cmd('meal.create', {
          'slot': '午餐',
          'items': [
            {'food': '米饭', 'grams': 200.0},
          ],
        }),
      );
      expect(first.ok, isTrue, reason: first.message);

      // 模型把午餐的米饭又带进晚餐的提议里：晚餐只应新增鸡蛋。
      final second = await executor.apply(
        cmd('meal.create', {
          'slot': '晚餐',
          'items': [
            {'food': '米饭', 'grams': 200.0},
            {'food': '鸡蛋', 'grams': 50.0},
          ],
        }),
      );
      expect(second.ok, isTrue, reason: second.message);
      expect(second.message, contains('跳过 1 条'));

      final meals = await database.select(database.meals).get();
      expect(meals, hasLength(2), reason: '午餐 + 晚餐两条主记录');
      final items = await database.select(database.mealItems).get();
      expect(items, hasLength(2), reason: '米饭只算一份 + 鸡蛋一份');
      expect(
        items.where((row) => row.foodNameSnapshot.contains('米饭')),
        hasLength(1),
        reason: '米饭不得在午餐与晚餐各算一份',
      );

      // 同一餐次再来一次完全重复的提议：并入已有那一餐，不新增行。
      final third = await executor.apply(
        cmd('meal.create', {
          'slot': '午餐',
          'items': [
            {'food': '米饭', 'grams': 200.0},
          ],
        }),
      );
      expect(third.ok, isTrue);
      expect(third.message, contains('没有重复写入'));
      expect(await database.select(database.mealItems).get(), hasLength(2));
    });

    test('meal.update 改餐次与备注；meal.delete 删除与缺失', () async {
      await _seedProfile(database);
      await executor.apply(
        cmd('meal.create', {
          'slot': '早餐',
          'items': [
            {'food': '米饭', 'grams': 200.0},
          ],
        }),
      );
      final meal = await database.select(database.meals).getSingle();
      final item = await database.select(database.mealItems).getSingle();

      final updated = await executor.apply(
        cmd('meal.update', {'mealId': meal.id, 'slot': '午餐', 'notes': '改到午餐'}),
      );
      expect(updated.ok, isTrue);
      final after = await database.select(database.meals).getSingle();
      expect(after.slot, 'lunch');
      expect(after.notes, '改到午餐');

      final missing = await executor.apply(
        cmd('meal.delete', {'mealId': 'ghost'}),
      );
      expect(missing.ok, isFalse);

      final removed = await executor.apply(
        cmd('meal.delete', {'mealId': meal.id}),
      );
      expect(removed.ok, isTrue);
      expect(
        await (database.select(
          database.mealItems,
        )..where((row) => row.id.equals(item.id))).get(),
        isEmpty,
      );
    });

    test('meal.item.update 改克数并按比例重算营养；删到空餐被拦下', () async {
      await executor.apply(
        cmd('meal.create', {
          'slot': '晚餐',
          'items': [
            {'food': '米饭', 'grams': 100.0},
            {'food': '鸡蛋', 'grams': 50.0},
          ],
        }),
      );
      final items = await database.select(database.mealItems).get();
      final rice = items.firstWhere(
        (row) => row.foodNameSnapshot.contains('米饭'),
      );

      final scaled = await executor.apply(
        cmd('meal.item.update', {'itemId': rice.id, 'grams': 300.0}),
      );
      expect(scaled.ok, isTrue, reason: scaled.message);
      // MealRepository.update 的既有语义是「整餐条目重建」，条目 id 会换新，
      // 所以这里按名字找回（下一轮快照会把新 id 发给模型，docs/23 §4）。
      final after = await database.select(database.mealItems).get();
      final riceAfter = after.firstWhere(
        (row) => row.foodNameSnapshot.contains('米饭'),
      );
      expect(riceAfter.grams, 300);
      expect(riceAfter.id, isNot(rice.id));
      expect(riceAfter.kcalSnapshot, closeTo(rice.kcalSnapshot * 3, 0.01));

      final removed = await executor.apply(
        cmd('meal.item.delete', {'itemId': riceAfter.id}),
      );
      expect(removed.ok, isTrue, reason: removed.message);
      final left = await database.select(database.mealItems).get();
      expect(left, hasLength(1));

      final last = await executor.apply(
        cmd('meal.item.delete', {'itemId': left.single.id}),
      );
      expect(last.ok, isFalse);
      expect(last.message, contains('删整餐'));
    });
  });

  group('食材', () {
    test('food.create 成功；同名重复直接引用已有条目（不新建）', () async {
      final created = await executor.apply(
        cmd('food.create', {
          'name': '自定义蛋白粉',
          'kcalPer100g': 380.0,
          'proteinPer100g': 75.0,
          'carbsPer100g': 8.0,
          'fatPer100g': 5.0,
        }),
      );
      expect(created.ok, isTrue, reason: created.message);

      // 2026-10-23 用户：「应用前先查食物库」——已有同名食物时直接引用，
      // 不报错、不新建第二条。
      final duplicate = await executor.apply(
        cmd('food.create', {
          'name': '自定义蛋白粉',
          'kcalPer100g': 380.0,
          'proteinPer100g': 75.0,
          'carbsPer100g': 8.0,
          'fatPer100g': 5.0,
        }),
      );
      expect(duplicate.ok, isTrue);
      expect(duplicate.message, contains('已直接引用（未新建）'));
      final rows = await database.select(database.foods).get();
      expect(rows.where((row) => row.name.contains('自定义蛋白粉')), hasLength(1));
    });
  });

  group('饮食约束', () {
    test('constraints.set：中文标签解析进档案；两项都不给要被拒', () async {
      await _seedProfile(database);
      final ok = await executor.apply(
        cmd('constraints.set', {
          'dietaryLabels': <Object>['素食'],
          'allergenAvoidances': <Object>['花生', '甲壳类'],
        }),
      );
      expect(ok.ok, isTrue, reason: ok.message);
      final profile = await database.select(database.profiles).getSingle();
      expect(profile.dietaryPreferencesJson, contains('vegetarian'));
      // 2026-10-16：过敏原存储改为**用户原话的食材名**（不再压成 FoodAllergen
      // 枚举名），所以这里断言中文原文；引擎读侧本来就是自由字符串小写匹配。
      expect(profile.allergenAvoidancesJson, contains('花生'));

      final empty = await executor.apply(cmd('constraints.set', {}));
      expect(empty.ok, isFalse);
    });
  });

  group('资料（部分更新语义）', () {
    test('profile.body.update：先写身高、再写出生年/性别，**前面的字段不被清空**', () async {
      // 2026-10-16 口语弹药库 C07 实测暴露的疑点：用户分两句补资料
      // （「身高一米七五」→ 后来「出生年份 1998，生理性别男」），要确认后一次
      // 部分更新不会把前一次写的身高清成 null——本项目 weigh 字段是
      // `Value(x)` 直写，漏了「未给字段用现值回填」就会静默清空。
      await _seedProfile(database);
      final first = await executor.apply(
        cmd('profile.body.update', {'heightCm': 175.0}),
      );
      expect(first.ok, isTrue, reason: first.message);
      final second = await executor.apply(
        cmd('profile.body.update', {'birthYear': 1998, 'sex': 'male'}),
      );
      expect(second.ok, isTrue, reason: second.message);

      final row = await database.select(database.profiles).getSingle();
      expect(row.heightCm, 175, reason: '第二次部分更新不许清空身高');
      expect(row.birthYear, 1998);
      expect(row.biologicalSex, 'male');
    });
  });

  group('饮食约束（自由食材名）', () {
    test('constraints.set：白名单外的过敏原（如芒果）也照实落库', () async {
      // 2026-10-16 真实模型实测：用户说「我对芒果过敏」，模型给出
      // `allergenAvoidances: [芒果]`，但旧解析按 FoodAllergen 枚举白名单
      // 拒绝 ⇒ 约束落不了库（用户被告知「不是可识别的过敏原」）。存储与
      // 引擎读侧都是自由字符串 ⇒ 解析放开为「非空食材名照实落库」。
      await _seedProfile(database);
      final ok = await executor.apply(
        cmd('constraints.set', {
          'allergenAvoidances': <Object>['芒果'],
        }),
      );
      expect(ok.ok, isTrue, reason: ok.message);
      final profile = await database.select(database.profiles).getSingle();
      expect(profile.allergenAvoidancesJson, contains('芒果'));
    });

    test('constraints.set：空字符串项被过滤，不去重不落垃圾', () async {
      await _seedProfile(database);
      final ok = await executor.apply(
        cmd('constraints.set', {
          'allergenAvoidances': <Object>['芒果', '  ', ''],
        }),
      );
      expect(ok.ok, isTrue);
      final profile = await database.select(database.profiles).getSingle();
      expect(profile.allergenAvoidancesJson, contains('芒果'));
      final decoded =
          jsonDecode(profile.allergenAvoidancesJson) as List<Object?>;
      expect(decoded, hasLength(1), reason: '空白项应被过滤');
    });
  });

  group('长期记忆（S11，docs/38）', () {
    test('memory.remember：真的落库，kind/domain 中文归一', () async {
      final result = await executor.apply(
        cmd('memory.remember', {
          'text': '周三晚上练腿',
          'kind': '习惯',
          'domain': '训练',
          'tags': <Object>['腿', '周三'],
        }),
      );
      expect(result.ok, isTrue, reason: result.message);
      expect(result.message, contains('已记住'));

      final row = (await database.select(database.aiMemories).get()).single;
      expect(row.textContent, '周三晚上练腿');
      expect(row.kind, 'habit');
      expect(row.domain, 'training');
      expect(row.source, 'explicit');
    });

    test('memory.remember：重复记忆如实拒绝，不写第二条', () async {
      await executor.apply(cmd('memory.remember', {'text': '不吃香菜'}));
      final again = await executor.apply(
        cmd('memory.remember', {'text': '不吃香菜'}),
      );
      expect(again.ok, isFalse);
      expect(again.message, contains('已经有这条记忆'));
      expect(await database.select(database.aiMemories).get(), hasLength(1));
    });

    test('memory.forget：唯一命中真删；0 命中如实说没找到', () async {
      await executor.apply(cmd('memory.remember', {'text': '周三晚上练腿'}));

      final missing = await executor.apply(
        cmd('memory.forget', {'text': '完全无关'}),
      );
      expect(missing.ok, isFalse);
      expect(missing.message, contains('没有找到匹配的记忆'));

      final ok = await executor.apply(cmd('memory.forget', {'text': '练腿'}));
      expect(ok.ok, isTrue, reason: ok.message);
      expect(ok.message, contains('已忘掉'));
      expect(await database.select(database.aiMemories).get(), isEmpty);
    });

    test('memory.forget：多条命中列候选，不猜着删', () async {
      await executor.apply(cmd('memory.remember', {'text': '周三晚上练腿'}));
      await executor.apply(cmd('memory.remember', {'text': '周四晚上练腿'}));

      final ambiguous = await executor.apply(
        cmd('memory.forget', {'text': '练腿'}),
      );
      expect(ambiguous.ok, isFalse);
      expect(ambiguous.message, contains('请说得更具体'));
      expect(await database.select(database.aiMemories).get(), hasLength(2));
    });
  });

  group('菜品库', () {
    test('dish.upsert 同名是更新不是新增；dish.delete 与缺失', () async {
      final created = await executor.apply(
        cmd('dish.upsert', {
          'name': '麻婆豆腐',
          'slot': '晚餐',
          'kcal': 180.0,
          'protein': 12.0,
          'carbs': 8.0,
          'fat': 10.0,
        }),
      );
      expect(created.ok, isTrue, reason: created.message);
      final updated = await executor.apply(
        cmd('dish.upsert', {
          'name': '麻婆豆腐',
          'slot': '晚餐',
          'kcal': 200.0,
          'protein': 13.0,
          'carbs': 9.0,
          'fat': 11.0,
        }),
      );
      expect(updated.ok, isTrue);
      final rows = await database.select(database.dishLibrary).get();
      expect(rows, hasLength(1));
      expect(rows.single.kcal, 200);
      expect(rows.single.source, 'ai_chat');

      final missing = await executor.apply(
        cmd('dish.delete', {'dishId': 'ghost'}),
      );
      expect(missing.ok, isFalse);
      expect(
        (await executor.apply(cmd('dish.delete', {'dishId': rows.single.id})))
            .ok,
        isTrue,
      );
    });
  });

  group('食堂目录', () {
    test('地点/窗口/菜品 三级都能经对话建改删', () async {
      expect(
        (await executor.apply(
          cmd('canteen.venue.create', {'name': '一食堂', 'campus': '主校区'}),
        )).ok,
        isTrue,
      );
      final venue = await database.select(database.venues).getSingle();

      final renamed = await executor.apply(
        cmd('canteen.venue.rename', {'venueId': venue.id, 'name': '第一食堂'}),
      );
      expect(renamed.ok, isTrue, reason: renamed.message);

      final badWindow = await executor.apply(
        cmd('canteen.window.create', {
          'venue': '第一食堂',
          'name': '江浙窗口',
          'openTime': '13:00',
          'closeTime': '10:30',
        }),
      );
      expect(badWindow.ok, isFalse);
      expect(badWindow.message, contains('晚于'));

      final windowOk = await executor.apply(
        cmd('canteen.window.create', {
          'venue': '第一食堂',
          'name': '江浙窗口',
          'openTime': '10:30',
          'closeTime': '13:00',
        }),
      );
      expect(windowOk.ok, isTrue, reason: windowOk.message);
      final window = await database.select(database.menuServices).getSingle();

      final dish = await executor.apply(
        cmd('canteen.dish.create', {'window': '江浙窗口', 'name': '狮子头'}),
      );
      expect(dish.ok, isTrue, reason: dish.message);
      final menuItem = await database.select(database.menuItems).getSingle();
      expect(menuItem.displayName, '狮子头');
      // 价格退役（S8-b）：行里不该再出现那一列，改名是唯一可改字段。
      expect(menuItem.toColumns(false).containsKey('price_minor'), isFalse);

      final dishRenamed = await executor.apply(
        cmd('canteen.dish.update', {'dishId': menuItem.id, 'name': '蟹粉狮子头'}),
      );
      expect(dishRenamed.ok, isTrue, reason: dishRenamed.message);
      expect(
        (await database.select(database.menuItems).getSingle()).displayName,
        '蟹粉狮子头',
      );

      expect(
        (await executor.apply(
          cmd('canteen.dish.delete', {'dishId': menuItem.id}),
        )).ok,
        isTrue,
      );
      expect(
        (await executor.apply(
          cmd('canteen.window.delete', {'windowId': window.id}),
        )).ok,
        isTrue,
      );
      expect(
        (await executor.apply(
          cmd('canteen.venue.delete', {'venueId': venue.id}),
        )).ok,
        isTrue,
      );
    });
  });

  group('档案 / 训练计划', () {
    test('profile.goal.update：无目标行时失败，有目标行时更新', () async {
      await _seedProfile(database);
      final blocked = await executor.apply(
        cmd('profile.goal.update', {'goal': '增肌'}),
      );
      expect(blocked.ok, isFalse);
      expect(blocked.message, contains('建档'));

      await database
          .into(database.goals)
          .insert(
            GoalsCompanion.insert(
              id: 'goal-1',
              profileId: 'profile-1',
              type: 'maintain',
              calorieMinKcal: 1500,
              calorieMaxKcal: 2200,
              effectiveFrom: now,
              createdAt: now,
              updatedAt: now,
            ),
          );
      final ok = await executor.apply(
        cmd('profile.goal.update', {'goal': '减脂', 'targetWeightKg': 65.0}),
      );
      expect(ok.ok, isTrue, reason: ok.message);
      final goal = await database.select(database.goals).getSingle();
      expect(goal.type, 'loseFat');
      expect(goal.targetWeightKg, 65.0);
    });

    test('workout.plan.delete：存在则删，不存在如实报', () async {
      await database
          .into(database.workoutPlans)
          .insert(
            WorkoutPlansCompanion.insert(
              id: 'plan-1',
              name: '五分化',
              source: 'ai_draft',
              createdAt: now,
              updatedAt: now,
            ),
          );
      final missing = await executor.apply(
        cmd('workout.plan.delete', {'planId': 'ghost'}),
      );
      expect(missing.ok, isFalse);
      expect(
        (await executor.apply(cmd('workout.plan.delete', {'planId': 'plan-1'})))
            .ok,
        isTrue,
      );
      expect(await database.select(database.workoutPlans).get(), isEmpty);
    });

    // ── T6b（docs/32 §4 T6b）：workout.plan.create ──────────────────────
    // 安全属性（原任务管线退役后重钉到命令层）：动作名→库内**精确同名且唯一**；
    // 未知或歧义**整条拒绝**，不静默改名、不猜最近似。
    test('workout.plan.create：动作名精确命中则建计划（source=ai）', () async {
      await _insertExercise(database, id: 'ex-squat', name: '杠铃深蹲', now: now);
      final result = await executor.apply(
        cmd('workout.plan.create', {
          'name': '四天增肌',
          'days': [
            {
              'weekday': 1,
              'entries': [
                {'exercise': '杠铃深蹲', 'sets': 4, 'reps': 8, 'weightKg': 60},
              ],
            },
          ],
        }),
      );
      expect(result.ok, isTrue, reason: result.message);
      final plans = await database.select(database.workoutPlans).get();
      expect(plans, hasLength(1));
      expect(plans.single.name, '四天增肌');
      expect(plans.single.source, 'ai', reason: '对话创建的计划来源记 ai');
      final days = await database.select(database.workoutDays).get();
      expect(days, hasLength(1));
      expect(days.single.weekday, 1);
      final entries = await database.select(database.plannedExercises).get();
      expect(entries, hasLength(1));
      expect(entries.single.exerciseId, 'ex-squat');
      expect(entries.single.targetSets, 4);
      expect(entries.single.targetReps, 8);
      expect(entries.single.targetWeightKg, 60.0);
    });

    test('workout.plan.create：未知动作名整条拒绝，不落任何库', () async {
      final result = await executor.apply(
        cmd('workout.plan.create', {
          'name': '计划',
          'days': [
            {
              'weekday': 1,
              'entries': [
                {'exercise': '麒麟臂弯举', 'sets': 3, 'reps': 10},
              ],
            },
          ],
        }),
      );
      expect(result.ok, isFalse);
      expect(result.message, contains('麒麟臂弯举'));
      expect(await database.select(database.workoutPlans).get(), isEmpty);
    });

    test('workout.plan.create：同名歧义整条拒绝（要求先改名）', () async {
      await _insertExercise(database, id: 'ex-a', name: '深蹲', now: now);
      await _insertExercise(database, id: 'ex-b', name: '深蹲', now: now);
      final result = await executor.apply(
        cmd('workout.plan.create', {
          'name': '计划',
          'days': [
            {
              'weekday': 1,
              'entries': [
                {'exercise': '深蹲', 'sets': 3, 'reps': 10},
              ],
            },
          ],
        }),
      );
      expect(result.ok, isFalse);
      expect(result.message, contains('同名'));
      expect(await database.select(database.workoutPlans).get(), isEmpty);
    });

    test('workout.plan.create：自重动作 weightKg 省略（写 null）', () async {
      await _insertExercise(database, id: 'ex-pushup', name: '俯卧撑', now: now);
      final result = await executor.apply(
        cmd('workout.plan.create', {
          'name': '自重日',
          'days': [
            {
              'weekday': 3,
              'entries': [
                {'exercise': '俯卧撑', 'sets': 3, 'reps': 15},
              ],
            },
          ],
        }),
      );
      expect(result.ok, isTrue, reason: result.message);
      final entries = await database.select(database.plannedExercises).get();
      expect(entries.single.targetWeightKg, isNull);
    });
  });

  // 2026-10-16（N3，用户实测：「食堂菜品 AI 分析以后并没有在食堂目录里
  // 显示已分析和结果」）：根因是 `recordNutrition` 零调用方——分析结果从来
  // 没落库。这条命令把它接上，判据钉「真写进了证据表，且目录读侧认账」。
  test('canteen.dish.nutrition：写进证据表，目录读侧从「未分析」变「已分析」', () async {
    final canteen = CanteenRepository(
      database: database,
      idGenerator: IdsForTest(),
      clock: FixedAppClock(now),
    );
    final venueId = await canteen.createVenue(name: '第一食堂', campusName: '校本部');
    final windowId = await canteen.createWindow(
      venueId: venueId,
      name: '一号窗口',
      openTime: '10:00',
      closeTime: '13:00',
    );
    final dishId = await canteen.createDish(windowId: windowId, name: '番茄炒蛋');
    expect(
      (await canteen.listDishes(windowId)).single.hasNutrition,
      isFalse,
      reason: '分析前：未分析',
    );

    final result = await executor.apply(
      cmd('canteen.dish.nutrition', {
        'dishId': dishId,
        'kcalPer100g': 92.0,
        'proteinPer100g': 5.4,
        'carbsPer100g': 4.1,
        'fatPer100g': 6.2,
        'grade': 'c',
        'confidence': 0.4,
      }),
    );
    expect(result.ok, isTrue, reason: result.message);

    final after = (await canteen.listDishes(windowId)).single;
    expect(after.hasNutrition, isTrue, reason: '目录读侧要认账');
    expect(after.kcalPer100g, closeTo(92.0, 1e-9));
    expect(after.evidenceGrade, 'C', reason: '小写 c 归一成大写 C 后落库');
    final evidence = await database
        .select(database.menuItemNutritionEvidence)
        .get();
    expect(evidence, hasLength(1), reason: '证据表里真的有那一行');
    expect(evidence.single.menuItemId, dishId);
    expect(evidence.single.grade, 'C');
  });

  // 2026-10-16：修复建议扩到缺动作/缺地点/缺窗口（用户要求「1、2 都要」）。
  test('缺实体时都带得出结构化修复建议（动作 / 地点 / 窗口）', () async {
    // ① 缺动作：训练域按名字引用库里没有的动作。
    final exercise = await executor.apply(cmd('session.start', const {}));
    expect(exercise.ok, isTrue, reason: exercise.message);
    final missingExercise = await executor.apply(
      cmd('set.log', {'exercise': '绝对不存在的动作', 'weightKg': 20.0, 'reps': 10}),
    );
    expect(missingExercise.ok, isFalse);
    expect(missingExercise.repair?.kind, ChatEditRepairKind.createExercise);
    expect(missingExercise.repair?.name, '绝对不存在的动作');

    // ② 缺地点：食堂窗口建在一个库里没有的地点上。
    final missingVenue = await executor.apply(
      cmd('canteen.window.create', {
        'venue': '不存在的食堂',
        'name': '一号窗口',
        'openTime': '10:00',
        'closeTime': '13:00',
      }),
    );
    expect(missingVenue.ok, isFalse);
    expect(missingVenue.repair?.kind, ChatEditRepairKind.createVenue);
    expect(missingVenue.repair?.name, '不存在的食堂');

    // ③ 缺窗口：地点在、窗口不在（修复必须带上地点 id）。
    await executor.apply(
      cmd('canteen.venue.create', {'name': '第一食堂', 'campus': '校本部'}),
    );
    final missingWindow = await executor.apply(
      cmd('canteen.dish.create', {'window': '不存在的窗口', 'name': '狮子头'}),
    );
    expect(missingWindow.ok, isFalse);
    expect(missingWindow.repair?.kind, ChatEditRepairKind.createWindow);
    expect(missingWindow.repair?.name, '不存在的窗口');
    expect(missingWindow.repair?.venueId, isNotNull, reason: '窗口修复要知道它属于哪个地点');
  });
}

/// 插一条动作库记录（T6b 断言用；不依赖种子导入）。
Future<void> _insertExercise(
  AppDatabase database, {
  required String id,
  required String name,
  required DateTime now,
}) => database
    .into(database.exercises)
    .insert(
      ExercisesCompanion.insert(
        id: id,
        name: name,
        muscleGroup: 'legs',
        equipment: 'barbell',
        source: 'user',
        createdAt: now,
        updatedAt: now,
      ),
    );

RepositoryChatEditExecutor _buildExecutor(AppDatabase database, DateTime now) {
  final clock = FixedAppClock(now);
  final ids = IdsForTest();
  final foods = FoodRepository(
    database: database,
    idGenerator: ids,
    clock: clock,
  );
  return RepositoryChatEditExecutor(
    ChatEditServices(
      database: database,
      clock: clock,
      foodRepository: foods,
      aiMemoryRepository: AiMemoryRepository(
        database: database,
        clock: clock,
        idGenerator: ids,
      ),
      mealRepository: MealRepository(
        database: database,
        idGenerator: ids,
        clock: clock,
      ),
      dishLibraryRepository: DishLibraryRepository(
        database: database,
        idGenerator: ids,
        clock: clock,
      ),
      waterRepository: WaterRepository(
        database: database,
        idGenerator: ids,
        clock: clock,
      ),
      measurementRepository: MeasurementRepository(
        database: database,
        idGenerator: ids,
        clock: clock,
      ),
      planningConstraintsRepository: PlanningConstraintsRepository(
        database: database,
        clock: clock,
      ),
      canteenRepository: CanteenRepository(
        database: database,
        idGenerator: ids,
        clock: clock,
      ),
      workoutPlanRepository: WorkoutPlanRepository(
        database: database,
        idGenerator: ids,
        clock: clock,
      ),
      exerciseRepository: ExerciseRepository(
        database: database,
        idGenerator: ids,
        clock: clock,
      ),
      profileIdentityRepository: ProfileIdentityRepository(database: database),
      workoutSessionRepository: WorkoutSessionRepository(
        database: database,
        idGenerator: ids,
        clock: clock,
      ),
      updateWaterTargetMl: UpdateWaterTargetMl(
        database: database,
        idGenerator: ids,
        clock: clock,
      ),
      stepsRepository: StepsRepository(
        database: database,
        channel: StepsChannel(),
        idGenerator: ids,
        clock: clock,
      ),
      idGenerator: ids,
    ),
  );
}

Future<void> _seedProfile(AppDatabase database) async {
  final existing = await database.select(database.profiles).get();
  if (existing.isNotEmpty) return;
  await database
      .into(database.profiles)
      .insert(
        ProfilesCompanion.insert(
          id: 'profile-1',
          activityLevel: 'moderate',
          createdAt: FixedAppClock(DateTime.utc(2026, 10, 2, 12)).nowUtc(),
          updatedAt: FixedAppClock(DateTime.utc(2026, 10, 2, 12)).nowUtc(),
        ),
      );
}

/// 与 decoder 同一归一化路径的 id 生成器（餐记录测试也用它对齐行为）。
final class IdsForTest implements IdGenerator {
  int _value = 0;

  @override
  String next() => 'id-${_value++}';
}
