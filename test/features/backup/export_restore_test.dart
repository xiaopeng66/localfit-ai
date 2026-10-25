import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/backup/application/backup_table_registry.dart';
import 'package:localfit_ai/features/backup/application/clear_all_local_data.dart';
import 'package:localfit_ai/features/backup/application/export_localfit_data.dart';
import 'package:localfit_ai/features/backup/application/lfb_backup_codec.dart';
import 'package:localfit_ai/features/backup/application/restore_localfit_data.dart';
import 'package:localfit_ai/features/training/data/exercise_seed_importer.dart';

import '../../support/food_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase database;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await seedFoodFixture(database);
    await const ExerciseSeedImporter().importIfNeeded(database);
  });

  tearDown(() => database.close());

  Future<void> seedSampleData() async {
    final now = DateTime.utc(2026, 9, 12, 10);
    await database
        .into(database.profiles)
        .insert(
          ProfilesCompanion.insert(
            id: 'profile-1',
            activityLevel: 'moderate',
            createdAt: now,
            updatedAt: now,
            // docs/32 §3 D9：身份列进备份往返（`.lfb` 只带**路径**不带图片字节）。
            displayName: const Value('李雷'),
            avatarPath: const Value('/data/docs/localfit_ai/avatar/a.jpg'),
          ),
        );
    await database
        .into(database.meals)
        .insert(
          MealsCompanion.insert(
            id: 'meal-1',
            localDate: '2026-09-12',
            slot: 'lunch',
            eatenAt: now,
            source: 'manual',
            createdAt: now,
            updatedAt: now,
          ),
        );
    final squat = await (database.select(
      database.exercises,
    )..where((row) => row.id.equals('ex-barbell-squat'))).getSingle();
    await database
        .into(database.workoutPlans)
        .insert(
          WorkoutPlansCompanion.insert(
            id: 'plan-1',
            name: '下肢日',
            source: 'manual',
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
            weekday: 6,
            sortOrder: 6,
          ),
        );
    await database
        .into(database.plannedExercises)
        .insert(
          PlannedExercisesCompanion.insert(
            id: 'planned-1',
            dayId: 'day-1',
            exerciseId: squat.id,
            sortOrder: 0,
            targetSets: 4,
            targetReps: 8,
            targetWeightKg: const Value(60),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await database
        .into(database.workoutSessions)
        .insert(
          WorkoutSessionsCompanion.insert(
            id: 'session-1',
            localDate: '2026-09-12',
            startedAt: now,
            createdAt: now,
            updatedAt: now,
          ),
        );
    await database
        .into(database.workoutSets)
        .insert(
          WorkoutSetsCompanion.insert(
            id: 'set-1',
            sessionId: 'session-1',
            exerciseId: squat.id,
            sortOrder: 0,
            weightKg: 60,
            reps: 8,
            completedAt: now,
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  /// 2.0 新表种子：校园菜单链、可用窗口、每日计划链、目录分层。
  Future<void> seedTwoPointZeroData() async {
    final now = DateTime.utc(2026, 9, 15, 10);
    await database
        .into(database.foods)
        .insert(
          FoodsCompanion.insert(
            id: 'alias-food',
            name: '鸡蛋（50g）',
            kcalPer100g: 144,
            proteinPer100g: 13.3,
            carbsPer100g: 2.8,
            fatPer100g: 8.8,
            source: 'seed',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await database
        .into(database.foodAliases)
        .insert(
          FoodAliasesCompanion.insert(
            id: 'alias-1',
            foodId: 'alias-food',
            normalizedText: 'jidan',
            aliasType: 'pinyin',
            source: 'manual',
            createdAt: now,
          ),
        );
    await database
        .into(database.foodNutritionRevisions)
        .insert(
          FoodNutritionRevisionsCompanion.insert(
            id: 'rev-1',
            foodId: 'alias-food',
            revisionNumber: 2,
            kcalPer100g: const Value(150),
            qualityStatus: const Value('ok'),
            createdAt: now,
          ),
        );
    await database
        .into(database.foodPortions)
        .insert(
          FoodPortionsCompanion.insert(
            id: 'portion-1',
            foodId: 'alias-food',
            name: '个',
            grams: 50,
            source: 'manual',
            createdAt: now,
          ),
        );
    await database
        .into(database.foodEvidence)
        .insert(
          FoodEvidenceCompanion.insert(
            id: 'evidence-1',
            sourceId: 'cfct-2018',
            license: 'ODbL',
            retrievedAt: now,
            transformVersion: '1.0.0',
            qualityStatus: 'ok',
            recordHash: 'a' * 64,
            createdAt: now,
          ),
        );
    await database
        .into(database.foodImportJobs)
        .insert(
          FoodImportJobsCompanion.insert(
            id: 'job-food-1',
            catalogVersion: 1,
            status: 'completed',
            totalShards: 3,
            manifestHash: 'b' * 64,
            startedAt: now,
            finishedAt: Value(now),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await database
        .into(database.campusProfiles)
        .insert(
          CampusProfilesCompanion.insert(
            id: 'campus-1',
            name: '示范大学',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await database
        .into(database.venues)
        .insert(
          VenuesCompanion.insert(
            id: 'venue-1',
            campusId: 'campus-1',
            name: '东区食堂',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await database
        .into(database.menuSources)
        .insert(
          MenuSourcesCompanion.insert(
            id: 'source-1',
            venueId: 'venue-1',
            sourceType: 'paste_text',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await database
        .into(database.menuSnapshots)
        .insert(
          MenuSnapshotsCompanion.insert(
            id: 'snap-1',
            sourceId: 'source-1',
            venueId: 'venue-1',
            businessDate: '2026-09-15',
            contentHash: 'c' * 64,
            importedAt: now,
            createdAt: now,
            updatedAt: now,
          ),
        );
    await database
        .into(database.menuServices)
        .insert(
          MenuServicesCompanion.insert(
            id: 'svc-1',
            snapshotId: 'snap-1',
            name: '一楼窗口',
            openTime: '10:30',
            closeTime: '13:30',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await database
        .into(database.menuItems)
        .insert(
          MenuItemsCompanion.insert(
            id: 'item-1',
            serviceId: 'svc-1',
            displayName: '鸡蛋炒饭',
            itemStatus: const Value('matched'),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await database
        .into(database.menuItemFoodMatches)
        .insert(
          MenuItemFoodMatchesCompanion.insert(
            id: 'match-1',
            menuItemId: 'item-1',
            foodId: 'alias-food',
            matchStatus: const Value('confirmed'),
            confidence: const Value(0.95),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await database
        .into(database.menuItemNutritionEvidence)
        .insert(
          MenuItemNutritionEvidenceCompanion.insert(
            id: 'item-evidence-1',
            menuItemId: 'item-1',
            grade: 'A',
            origin: 'label',
            kcalMin: const Value(400),
            kcalMax: const Value(500),
            confidence: const Value(0.9),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await database
        .into(database.menuImportJobs)
        .insert(
          MenuImportJobsCompanion.insert(
            id: 'job-menu-1',
            sourceId: 'source-1',
            status: 'completed',
            snapshotId: const Value('snap-1'),
            startedAt: now,
            createdAt: now,
            updatedAt: now,
          ),
        );
    await database
        .into(database.availabilityWindows)
        .insert(
          AvailabilityWindowsCompanion.insert(
            id: 'window-1',
            startMinute: 10 * 60 + 30,
            endMinute: 13 * 60 + 30,
            kind: 'dining',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await database
        .into(database.dailyPlans)
        .insert(
          DailyPlansCompanion.insert(
            id: 'plan-1',
            localDate: '2026-09-15',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await database
        .into(database.dailyPlanSlots)
        .insert(
          DailyPlanSlotsCompanion.insert(
            id: 'slot-1',
            planId: 'plan-1',
            slot: 'lunch',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await database
        .into(database.dailyPlanCandidates)
        .insert(
          DailyPlanCandidatesCompanion.insert(
            id: 'candidate-1',
            slotId: 'slot-1',
            kind: 'menu_item',
            refId: 'item-1',
            displayName: '鸡蛋炒饭',
            venueId: const Value('venue-1'),
            estimatedKcal: const Value(450),
            estimatedProteinG: const Value(20),
            evidenceGrade: const Value('A'),
            score: const Value(0.7),
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  test('exports every logical table with a version header', () async {
    await seedSampleData();

    final bytes = await ExportLocalFitData(database).exportJson();
    final document = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;

    expect(document['export_version'], 1);
    expect(document['exported_at'], isA<String>());
    final tables = document['tables'] as Map<String, dynamic>;
    expect(
      tables.keys,
      containsAll([
        'profiles',
        'goals',
        'daily_targets',
        'measurements',
        'foods',
        'meals',
        'meal_items',
        'exercises',
        'workout_plans',
        'workout_days',
        'planned_exercises',
        'workout_sessions',
        'workout_sets',
        'ai_provider_configs',
      ]),
    );
    expect((tables['workout_sets'] as List).single['id'], 'set-1');
    // 被 docs/28 的 W4 删掉的那五张表不再出现在备份里（清单是单一事实源）。
    for (final gone in [
      'recipes',
      'recipe_items',
      'meal_plan_entries',
      'food_price_facts',
      'pantry_stocks',
    ]) {
      expect(tables.containsKey(gone), isFalse, reason: '$gone 已随 W4 整族下线');
    }
  });

  test('restores a full backup into an empty database', () async {
    await seedSampleData();
    final bytes = await ExportLocalFitData(database).exportJson();

    final restored = AppDatabase(NativeDatabase.memory());
    addTearDown(restored.close);
    await RestoreLocalFitData(restored).restore(bytes);

    final restoredProfile =
        (await restored.select(restored.profiles).get()).single;
    expect(restoredProfile.id, 'profile-1');
    // docs/32 §3 D9：昵称/头像路径随备份往返（图片字节不在包内 —— 如实限制）。
    expect(restoredProfile.displayName, '李雷');
    expect(restoredProfile.avatarPath, '/data/docs/localfit_ai/avatar/a.jpg');
    expect(await restored.select(restored.meals).get(), hasLength(1));
    expect(
      (await restored.select(restored.workoutPlans).get()).single.name,
      '下肢日',
    );
    expect(
      (await restored.select(restored.workoutSets).get()).single.weightKg,
      60,
    );
    expect(await restored.select(restored.foods).get(), isNotEmpty);
    expect(await restored.select(restored.exercises).get(), hasLength(312));
  });

  test('covers every table in the schema, not just the 1.x set', () async {
    // docs/03 §12：新增表必须同步 JSON 导出 / .lfb 恢复 / 清除。这条断言
    // 把「备份清单 = schema 的全部逻辑表」钉死，避免以后加表又漏掉备份。
    //
    // 2026-10-18（docs/41 §11 D7）：**派生状态不进备份**是已裁决的例外——
    // `embedding_index`（向量，恢复后后台重建）与 `background_jobs`（任务
    // 队列）。例外在这里**显式列出**，不是放宽断言：schema 里再多出第三张
    // 未登记表仍然会红。
    const derivedTablesNotBackedUp = {'embedding_index', 'background_jobs'};
    final bytes = await ExportLocalFitData(database).exportJson();
    final document = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    final exported = (document['tables'] as Map<String, dynamic>).keys.toSet();
    final schemaTables = database.allTables
        .map((table) => table.actualTableName)
        .toSet();

    expect(
      schemaTables.difference(exported),
      derivedTablesNotBackedUp,
      reason: '未入备份的表必须恰好是登记的派生表',
    );
    expect(exported.difference(schemaTables), isEmpty);
    expect(
      exported.intersection(derivedTablesNotBackedUp),
      isEmpty,
      reason: '派生表不得被悄悄写进备份',
    );
  });

  test('round-trips the 2.0 tables through export and restore', () async {
    await seedSampleData();
    await seedTwoPointZeroData();
    final bytes = await ExportLocalFitData(database).exportJson();

    final restored = AppDatabase(NativeDatabase.memory());
    addTearDown(restored.close);
    await RestoreLocalFitData(restored).restore(bytes);

    // 校园菜单链：校区 → 食堂 → 来源 → 快照 → 服务 → 条目 → 匹配/证据。
    expect(
      (await restored.select(restored.campusProfiles).get()).single.name,
      '示范大学',
    );
    expect(await restored.select(restored.venues).get(), hasLength(1));
    expect(await restored.select(restored.menuSources).get(), hasLength(1));
    expect(await restored.select(restored.menuSnapshots).get(), hasLength(1));
    expect(await restored.select(restored.menuServices).get(), hasLength(1));
    expect(await restored.select(restored.menuItems).get(), hasLength(1));
    expect(
      (await restored.select(restored.menuItemFoodMatches).get()).single.foodId,
      'alias-food',
    );
    expect(
      await restored.select(restored.menuItemNutritionEvidence).get(),
      hasLength(1),
    );
    expect(await restored.select(restored.menuImportJobs).get(), hasLength(1));
    // 可用窗口与每日计划链。
    expect(
      await restored.select(restored.availabilityWindows).get(),
      hasLength(1),
    );
    expect(
      (await restored.select(restored.dailyPlans).get()).single.status,
      'draft',
    );
    expect(await restored.select(restored.dailyPlanSlots).get(), hasLength(1));
    expect(
      (await restored.select(restored.dailyPlanCandidates).get()).single.score,
      closeTo(0.7, 1e-9),
    );
    // 目录分层。
    expect(
      (await restored.select(restored.foodAliases).get()).single.normalizedText,
      'jidan',
    );
    expect(
      await restored.select(restored.foodNutritionRevisions).get(),
      hasLength(1),
    );
    expect(await restored.select(restored.foodPortions).get(), hasLength(1));
    expect(await restored.select(restored.foodEvidence).get(), hasLength(1));
    expect(await restored.select(restored.foodImportJobs).get(), hasLength(1));
  });

  test('round-trips AI memories (S11)', () async {
    await seedSampleData();
    final stamp = DateTime.utc(2026, 10, 17, 12);
    await database
        .into(database.aiMemories)
        .insert(
          AiMemoriesCompanion.insert(
            id: 'memory-1',
            textContent: '周三晚上练腿',
            kind: 'habit',
            domain: 'training',
            source: 'explicit',
            createdAt: stamp,
            updatedAt: stamp,
          ),
        );

    final bytes = await ExportLocalFitData(database).exportJson();
    final restored = AppDatabase(NativeDatabase.memory());
    addTearDown(restored.close);
    await RestoreLocalFitData(restored).restore(bytes);

    final row = (await restored.select(restored.aiMemories).get()).single;
    expect(row.textContent, '周三晚上练腿');
    expect(row.kind, 'habit');
    expect(row.domain, 'training');
    expect(row.source, 'explicit');
  });

  test(
    'old backups without ai_memories still restore (optional table)',
    () async {
      // docs/03 §12：旧包必须还能恢复。记忆表标了 optional ⇒ 缺键读作空表，
      // 不是「备份损坏」。
      await seedSampleData();
      final bytes = await ExportLocalFitData(database).exportJson();
      final decoded = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
      final tables = decoded['tables'] as Map<String, Object?>;
      expect(tables.remove('ai_memories'), isNotNull);

      final restored = AppDatabase(NativeDatabase.memory());
      addTearDown(restored.close);
      await RestoreLocalFitData(restored)
          .restore(Uint8List.fromList(utf8.encode(jsonEncode(decoded))));

      expect(await restored.select(restored.aiMemories).get(), isEmpty);
      // 其余表照常恢复（用一条最基础的行作哨兵）。
      expect(await restored.select(restored.profiles).get(), isNotEmpty);
    },
  );

  test('restores a pre-2.0 backup that lacks the new tables', () async {
    // 旧 `.lfb`（只有 1.x 的 19 张表）必须还能恢复：新表在旧包里不存在
    // 是正常的，不能当成「备份损坏」。
    await seedSampleData();
    final bytes = await ExportLocalFitData(database).exportJson();
    final document = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    final tables = document['tables'] as Map<String, dynamic>;
    const newTables = [
      'food_aliases',
      'food_nutrition_revisions',
      'food_portions',
      'food_evidence',
      'food_import_jobs',
      'campus_profiles',
      'venues',
      'menu_sources',
      'menu_snapshots',
      'menu_services',
      'menu_items',
      'menu_item_food_matches',
      'menu_item_nutrition_evidence',
      'menu_import_jobs',
      'availability_windows',
      'daily_plans',
      'daily_plan_slots',
      'daily_plan_candidates',
    ];
    for (final name in newTables) {
      tables.remove(name);
    }
    final legacy = Uint8List.fromList(utf8.encode(jsonEncode(document)));

    final restored = AppDatabase(NativeDatabase.memory());
    addTearDown(restored.close);
    await RestoreLocalFitData(restored).restore(legacy);

    expect(
      (await restored.select(restored.profiles).get()).single.id,
      'profile-1',
    );
    expect(await restored.select(restored.meals).get(), hasLength(1));
    expect(await restored.select(restored.campusProfiles).get(), isEmpty);
    expect(await restored.select(restored.dailyPlans).get(), isEmpty);
    expect(await restored.select(restored.foodAliases).get(), isEmpty);
  });

  test('replacing an existing database keeps it intact on failure', () async {
    await seedSampleData();
    final bytes = await ExportLocalFitData(database).exportJson();

    final restored = AppDatabase(NativeDatabase.memory());
    addTearDown(restored.close);
    await restored
        .into(restored.profiles)
        .insert(
          ProfilesCompanion.insert(
            id: 'sentinel',
            activityLevel: 'active',
            createdAt: DateTime.utc(2026, 1, 1),
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
        );

    final corrupted = Uint8List.fromList([
      ...bytes.sublist(0, bytes.length - 8),
      ...List.filled(8, 0x20),
    ]);

    await expectLater(
      RestoreLocalFitData(restored).restore(corrupted),
      throwsA(isA<FormatException>()),
    );
    expect(
      (await restored.select(restored.profiles).get()).single.id,
      'sentinel',
    );
  });

  test('restores idempotently by replacing prior content', () async {
    await seedSampleData();
    final bytes = await ExportLocalFitData(database).exportJson();

    final restored = AppDatabase(NativeDatabase.memory());
    addTearDown(restored.close);
    final restore = RestoreLocalFitData(restored);
    await restore.restore(bytes);
    await restore.restore(bytes);

    expect(await restored.select(restored.profiles).get(), hasLength(1));
    expect(await restored.select(restored.meals).get(), hasLength(1));
    expect(await restored.select(restored.workoutSets).get(), hasLength(1));
  });

  test('v18 时代的备份恢复到 v19 应用：其余表还原、不抛错、已删表不被写入', () async {
    // docs/28 §6.6 的三向行为之一（旧备份 → 新版应用）：`.lfb` 的恢复遍历的是
    // **registry**，所以 v18 时代备份里多出来的那五个键**被静默忽略**——
    // 不报错、不写库，其余表照常逐表还原。这不是 bug，是删表的既定后果。
    await seedSampleData();
    final bytes = await ExportLocalFitData(database).exportJson();

    final document = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    final tables = document['tables'] as Map<String, dynamic>;
    // 还原一份 v18 时代的文档：registry 里当年有、现在没有的五个键各带一行。
    const stamp = 1780000000000;
    tables['recipes'] = [
      {
        'id': 'recipe-legacy',
        'name': '旧食谱',
        'servings': 1,
        'finishedWeightGrams': 100,
        'revision': 1,
        'createdAt': stamp,
        'updatedAt': stamp,
      },
    ];
    tables['recipe_items'] = [
      {
        'id': 'recipe-item-legacy',
        'recipeId': 'recipe-legacy',
        'foodId': 'food-legacy',
        'grams': 100,
        'createdAt': stamp,
        'updatedAt': stamp,
      },
    ];
    tables['meal_plan_entries'] = [
      {
        'id': 'plan-legacy',
        'localDate': '2026-09-12',
        'recipeId': 'recipe-legacy',
        'createdAt': stamp,
        'updatedAt': stamp,
      },
    ];
    tables['food_price_facts'] = [
      {'foodId': 'food-legacy', 'minorUnitsPer100g': 850, 'currency': 'CNY'},
    ];
    tables['pantry_stocks'] = [
      {'foodId': 'food-legacy', 'availableGrams': 250},
    ];

    final restored = AppDatabase(NativeDatabase.memory());
    addTearDown(restored.close);
    await RestoreLocalFitData(restored)
        .restore(Uint8List.fromList(utf8.encode(jsonEncode(document))));

    // ① 其余表逐表还原（不抛错即已证明"多出来的键"没被当成损坏备份）。
    expect(
      (await restored.select(restored.profiles).get()).single.id,
      'profile-1',
    );
    expect(await restored.select(restored.meals).get(), hasLength(1));
    expect(await restored.select(restored.workoutSets).get(), hasLength(1));
    // ② 那五张表在 v19 的 schema 里根本不存在 ⇒ 数据没有被写进来。
    final ghostTables = await restored
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN "
          "('recipes', 'recipe_items', 'meal_plan_entries', "
          "'food_price_facts', 'pantry_stocks')",
        )
        .get();
    expect(ghostTables, isEmpty);
  });

  test(
    'rejects unsupported export versions without touching the database',
    () async {
      final badBytes = Uint8List.fromList(
        utf8.encode(jsonEncode({'export_version': 99, 'tables': {}})),
      );

      await expectLater(
        RestoreLocalFitData(database).restore(badBytes),
        throwsFormatException,
      );
      expect(await database.select(database.profiles).get(), isEmpty);
    },
  );

  test('字段值校验：畸形 local_date 的备份整单拒绝并回滚（docs/11 §3-F）', () async {
    // 恢复侧原先只校验 JSON 形状不校验字段值：`2026-02-31` 这类 DateTime
    // 会悄悄滚进 3 月的假日期、或任意脏文本都能干净落库，读取侧 build 里
    // 一解析就整页红屏（BUG-15 的根本条件）。现在读取侧会严格解析的
    // 日期列在写库前逐行校验，脏值整单拒绝。
    await seedSampleData();
    final bytes = await ExportLocalFitData(database).exportJson();
    final document = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    final tables = document['tables']! as Map<String, dynamic>;
    final meals = (tables['meals']! as List).cast<Map<String, dynamic>>();
    meals.first['localDate'] = '2026-02-31';
    final tampered = Uint8List.fromList(utf8.encode(jsonEncode(document)));

    final restored = AppDatabase(NativeDatabase.memory());
    addTearDown(restored.close);
    await restored
        .into(restored.profiles)
        .insert(
          ProfilesCompanion.insert(
            id: 'sentinel',
            activityLevel: 'active',
            createdAt: DateTime.utc(2026, 1, 1),
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
        );

    await expectLater(
      RestoreLocalFitData(restored).restore(tampered),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          allOf(contains('meals'), contains('无效字段')),
        ),
      ),
    );
    // 整单回滚：哨兵行还在，脏日期没有落库。
    expect(
      (await restored.select(restored.profiles).get()).single.id,
      'sentinel',
    );
    expect(await restored.select(restored.meals).get(), isEmpty);
  });

  test('字段值校验：聊天图片路径不得含回退段（docs/25 §5 L2）', () async {
    await seedSampleData();
    final now = DateTime.utc(2026, 10, 2, 9);
    await database
        .into(database.conversationMessages)
        .insert(
          ConversationMessagesCompanion.insert(
            id: 'msg-1',
            sessionId: 'sess-1',
            role: 'user',
            textContent: '看这张照片',
            createdAt: now,
            status: 'sent',
            imagePath: const Value(
              '/data/user/0/com.localfit.ai/files/chat/1.png',
            ),
          ),
        );
    final bytes = await ExportLocalFitData(database).exportJson();
    final document = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    final tables = document['tables']! as Map<String, dynamic>;
    final messages = (tables['conversation_messages']! as List)
        .cast<Map<String, dynamic>>();

    // 先证明夹具真的把这一列导出来了：否则下面的拒绝可能因为列缺失而
    // 「通过」，测的就不是路径判据。
    expect(messages.single['imagePath'], isNotNull);

    // 干净的绝对路径能正常恢复（判据只针对回退段，不针对绝对路径）。
    final clean = AppDatabase(NativeDatabase.memory());
    addTearDown(clean.close);
    await RestoreLocalFitData(clean)
        .restore(Uint8List.fromList(utf8.encode(jsonEncode(document))));
    expect(
      (await clean.select(clean.conversationMessages).get()).single.imagePath,
      '/data/user/0/com.localfit.ai/files/chat/1.png',
    );

    // 篡改成回退路径：整单拒绝并回滚。
    messages.single['imagePath'] = '../../databases/localfit.sqlite';
    final tampered = Uint8List.fromList(utf8.encode(jsonEncode(document)));
    await expectLater(
      RestoreLocalFitData(clean).restore(tampered),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          allOf(contains('conversation_messages'), contains('无效字段')),
        ),
      ),
    );
  });

  test('字段值校验同样覆盖 2.0 表（menu_snapshots.businessDate）', () async {
    await seedSampleData();
    await seedTwoPointZeroData();
    final bytes = await ExportLocalFitData(database).exportJson();
    final document = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    final tables = document['tables']! as Map<String, dynamic>;
    final snapshots = (tables['menu_snapshots']! as List)
        .cast<Map<String, dynamic>>();
    snapshots.first['businessDate'] = 'not-a-date';
    final tampered = Uint8List.fromList(utf8.encode(jsonEncode(document)));

    await expectLater(
      RestoreLocalFitData(database).restore(tampered),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('无效字段'),
        ),
      ),
    );
    // 整单回滚：库中原有内容原封不动（快照还是原来那条干净数据，
    // 篡改的脏日期从未落库）。
    final snapshotsAfter = await database.select(database.menuSnapshots).get();
    expect(snapshotsAfter, hasLength(1));
    expect(snapshotsAfter.single.businessDate, '2026-09-15');
  });

  test('round-trips through the encrypted .lfb envelope', () async {
    final codec = const LfbBackupCodec(iterations: 2000);
    await seedSampleData();
    final bytes = await ExportLocalFitData(database).exportJson();

    final envelope = await codec.encode(payload: bytes, password: '口令');
    final decoded = await codec.decode(envelopeJson: envelope, password: '口令');

    final restored = AppDatabase(NativeDatabase.memory());
    addTearDown(restored.close);
    await RestoreLocalFitData(restored).restore(decoded);
    expect(
      (await restored.select(restored.profiles).get()).single.id,
      'profile-1',
    );
  });

  test('导出→清除→恢复→再清除：39 张表逐表行数对账', () async {
    // docs/11 §3-A 的往返对账：不只看「恢复后 profile 还在」，而是把每张表
    // 的行数钉死——备份少写一张表、恢复漏插一张表、清除留下残留，都会在这里
    // 变成具体表名 + 数字差异。同时验证清单的外键顺序（父表在前）在真实
    // PRAGMA foreign_keys = ON 下能插得进去。
    await seedSampleData();
    await seedTwoPointZeroData();
    Future<Map<String, int>> rowCounts(AppDatabase db) async => {
      for (final spec in LocalFitBackupTables(db).all)
        spec.key:
            (await db
                    .customSelect('SELECT COUNT(*) AS c FROM ${spec.tableName}')
                    .getSingle())
                .read<int>('c'),
    };

    final before = await rowCounts(database);
    expect(
      before.values.where((count) => count > 0).length,
      greaterThanOrEqualTo(20),
      reason: '样本数据要覆盖足够多的表，对账才有意义',
    );

    final bytes = await ExportLocalFitData(database).exportJson();
    await ClearAllLocalData(database).clear();
    final cleared = await rowCounts(database);
    // 2026-10-23 用户：内置食物（含导入）活过「清除所有数据」；食物五表是
    // 显式例外，其余表仍必须清零。
    const preservedFoodTables = {
      'foods',
      'food_aliases',
      'food_nutrition_revisions',
      'food_portions',
      'food_evidence',
    };
    final leftover = {
      for (final entry in cleared.entries)
        if (!preservedFoodTables.contains(entry.key)) entry.key: entry.value,
    };
    expect(
      leftover.values.every((count) => count == 0),
      isTrue,
      reason: '全清后不允许有任何残留行（内置食物表除外）：$leftover',
    );
    expect(cleared['foods'], greaterThan(0), reason: '内置食物必须保留');

    await RestoreLocalFitData(database).restore(bytes);
    final restored = await rowCounts(database);
    expect(restored, before, reason: '恢复必须逐表还原到清除前的行数');

    await ClearAllLocalData(database).clear();
    final clearedAgain = await rowCounts(database);
    final leftoverAgain = {
      for (final entry in clearedAgain.entries)
        if (!preservedFoodTables.contains(entry.key)) entry.key: entry.value,
    };
    expect(
      leftoverAgain.values.every((count) => count == 0),
      isTrue,
      reason: '恢复之后再清除同样不能留残留（内置食物表除外）：$leftoverAgain',
    );
  });

  // ── T7（docs/32 §4 T7 / §3 D9）：身份列的备份兼容 ──────────────────
  test('旧 .lfb（无新键、含已退役键）恢复不崩：新列 null，旧键丢弃', () async {
    await seedSampleData();
    final bytes = await ExportLocalFitData(database).exportJson();
    final document = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    final tables = (document['tables'] as Map<String, dynamic>);
    final profiles = (tables['profiles'] as List).cast<Map<String, dynamic>>();
    // 模拟「旧版应用导出的包」：删掉 D9 新增的两个键、塞回一条已退役的
    // `manualCommuteMinutes`（schema 22 时代存在、schema 23→24 将删）。
    // 键名是 **drift `toJson()` 的驼峰**（`displayName`），不是列名蛇形 ——
    // 导出走 `row.toJson()`（见 `LocalFitBackupTables._table`）。
    for (final row in profiles) {
      row.remove('displayName');
      row.remove('avatarPath');
      row['manualCommuteMinutes'] = 25;
    }
    final legacyBytes = utf8.encode(jsonEncode(document));

    final restored = AppDatabase(NativeDatabase.memory());
    addTearDown(restored.close);
    await RestoreLocalFitData(restored).restore(legacyBytes);

    final row = (await restored.select(restored.profiles).get()).single;
    expect(row.id, 'profile-1');
    expect(row.displayName, isNull, reason: '旧包没有昵称 → null，不编造');
    expect(row.avatarPath, isNull, reason: '旧包没有头像 → null，不编造');
    expect(row.activityLevel, 'moderate', reason: '旧包其余列照常恢复（丢的只是新列与退役键）');
    // T8（schema 23→24）：退役键不只是「被忽略」——它连列都不能让库重新长
    // 出来。恢复遍历的是 registry 的现存表列，旧键不该有复活能力。
    final columns = await restored
        .customSelect('PRAGMA table_info(profiles)')
        .get();
    final names = columns.map((column) => column.data['name']).toList();
    expect(
      names,
      isNot(contains('manual_commute_minutes')),
      reason: '带退役驼峰键的旧包恢复后，profiles 不该重新长出该列',
    );
  });

  test('新 .lfb 往返：昵称与头像路径逐字回来', () async {
    await seedSampleData();
    final bytes = await ExportLocalFitData(database).exportJson();
    final document = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    final profiles =
        ((document['tables'] as Map<String, dynamic>)['profiles'] as List)
            .cast<Map<String, dynamic>>();
    expect(profiles.single['displayName'], '李雷');
    expect(
      profiles.single['avatarPath'],
      '/data/docs/localfit_ai/avatar/a.jpg',
    );

    final restored = AppDatabase(NativeDatabase.memory());
    addTearDown(restored.close);
    await RestoreLocalFitData(restored).restore(bytes);
    final row = (await restored.select(restored.profiles).get()).single;
    expect(row.displayName, '李雷');
    expect(row.avatarPath, '/data/docs/localfit_ai/avatar/a.jpg');
  });
}
