import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/settings/application/data_self_check.dart';
import 'package:localfit_ai/features/settings/presentation/data_self_check_page.dart';

/// D-1/D-2（docs/64 阶段 3）：**数据自检**——三类可检问题各给计数与安全修复，
/// 顶部一行「最近一次备份」。
///
/// 三类问题（docs/64 D-1 现状证据）：
/// 1. 孤儿引用：`meal_items.food_id` 指向已删食物 → 安全修复 = 置空 `food_id`
///    （餐记录的名称/营养快照列都在，置空不丢内容）；
/// 2. 日期格式异常：`local_date` 不符合 `yyyy-MM-dd`（历史脏数据）→ **只报不修**
///    （改写日期或删行都会丢记录，不自动动）；
/// 3. 步数手动行残留：`steps_daily.source='manual'` 且超过 7 天 → 修复 = 删除，
///    但删除前先整行取出、删后给「撤销」（真删了用户手输的历史值就不安全了）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 10, 26, 12);
  const today = '2026-10-26';
  late AppDatabase database;
  late DataSelfCheck selfCheck;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    selfCheck = DataSelfCheck(
      database: database,
      clock: FixedAppClock(now.toUtc()),
    );
    await database
        .into(database.profiles)
        .insert(
          ProfilesCompanion.insert(
            id: 'profile-1',
            activityLevel: 'moderate',
            createdAt: now.toUtc(),
            updatedAt: now.toUtc(),
          ),
        );
  });

  tearDown(() => database.close());

  Future<void> seedMeal({String? foodId, String date = '2026-10-20'}) async {
    // 直插孤儿引用需要临时关掉 FK（pragma 在 beforeOpen 里开着）：这正是
    // 「历史脏数据」的成因——加固前的写路径 / 恢复的旧备份不受今天的约束。
    if (foodId != null) {
      await database.customStatement('PRAGMA foreign_keys = OFF');
    }
    final mealId = 'meal-${foodId ?? 'x'}-$date';
    await database
        .into(database.meals)
        .insert(
          MealsCompanion.insert(
            id: mealId,
            localDate: date,
            slot: 'lunch',
            source: 'manual',
            eatenAt: now,
            createdAt: now,
            updatedAt: now,
          ),
        );
    await database
        .into(database.mealItems)
        .insert(
          MealItemsCompanion.insert(
            id: 'item-$mealId',
            mealId: mealId,
            foodId: Value(foodId),
            foodNameSnapshot: '某种食物',
            grams: 100,
            kcalSnapshot: 100,
            proteinSnapshot: 5,
            carbsSnapshot: 20,
            fatSnapshot: 2,
            createdAt: now,
            updatedAt: now,
          ),
        );
    if (foodId != null) {
      await database.customStatement('PRAGMA foreign_keys = ON');
    }
  }

  Future<void> seedManualSteps({
    required String date,
    required int steps,
  }) async {
    await database
        .into(database.stepsDaily)
        .insert(
          StepsDailyCompanion.insert(
            id: 'steps-$date',
            localDate: date,
            steps: steps,
            source: 'manual',
            recordedAt: now,
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  test('三类问题各造一条脏数据 → 都能被检出（计数正确）', () async {
    await seedMeal(foodId: 'deleted-food');
    // 日期格式异常：直插一条坏日期的餐（B-2 的写守卫只拦 create，直插仍可能）。
    await database
        .into(database.meals)
        .insert(
          MealsCompanion.insert(
            id: 'meal-bad-date',
            localDate: '2026/10/01',
            slot: 'lunch',
            source: 'manual',
            eatenAt: now,
            createdAt: now,
            updatedAt: now,
          ),
        );
    await seedManualSteps(date: '2026-09-01', steps: 3000);
    await seedManualSteps(date: today, steps: 500);

    final report = await selfCheck.run();
    expect(report.orphanFoodItems, 1);
    expect(report.badDateRows['meals'], 1);
    expect(report.staleManualStepRows, 1, reason: '今天的手动行不算残留');
    expect(report.hasIssues, isTrue);
  });

  test('修复孤儿引用：food_id 置空、餐记录内容不变、计数归零', () async {
    await seedMeal(foodId: 'deleted-food');
    final fixed = await selfCheck.fixOrphanFoodIds();
    expect(fixed, 1);

    final item = await (database.select(
      database.mealItems,
    )..limit(1)).getSingle();
    expect(item.foodId, isNull, reason: '只置空引用');
    expect(item.foodNameSnapshot, '某种食物', reason: '快照列原样保留');
    expect(item.kcalSnapshot, 100);

    final report = await selfCheck.run();
    expect(report.orphanFoodItems, 0);
  });

  test('清理过期手动步数行：删掉超 7 天的，今天的不动', () async {
    await seedManualSteps(date: '2026-09-01', steps: 3000);
    await seedManualSteps(date: today, steps: 500);
    final removed = await selfCheck.removeStaleManualStepRows();
    expect(removed, 1);
    final rows = await database.select(database.stepsDaily).get();
    expect(rows.map((row) => row.localDate), [today]);
  });

  testWidgets('自检页：三类计数上屏 + 修复孤儿引用后归零', (tester) async {
    await seedMeal(foodId: 'deleted-food');
    await database
        .into(database.meals)
        .insert(
          MealsCompanion.insert(
            id: 'meal-bad-date',
            localDate: '2026/10/01',
            slot: 'lunch',
            source: 'manual',
            eatenAt: now,
            createdAt: now,
            updatedAt: now,
          ),
        );
    await seedManualSteps(date: '2026-09-01', steps: 3000);
    await database
        .into(database.appSettings)
        .insert(
          AppSettingsCompanion.insert(
            key: 'last_backup_at_ms',
            value: '${now.millisecondsSinceEpoch}',
          ),
        );

    tester.view.physicalSize = const Size(390, 844 * 2);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DataSelfCheckPage(selfCheck: selfCheck)),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    expect(find.byKey(const Key('data-self-check-sheet')), findsOneWidget);
    // 三类各检出 1 条（卡片头：问题名单独一行 + 「N 条」计数徽章）。
    expect(find.text('孤儿的食物引用'), findsOneWidget);
    expect(find.text('日期格式异常'), findsOneWidget);
    expect(find.text('过期手动步数行'), findsOneWidget);
    expect(find.text('1 条'), findsNWidgets(3));
    expect(find.textContaining('最近一次备份'), findsOneWidget);

    await tester.tap(find.byKey(const Key('data-self-check-fix-orphans')));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    final report = await selfCheck.run();
    expect(report.orphanFoodItems, 0, reason: '修复后孤儿计数归零');
    expect(find.text('撤销'), findsOneWidget, reason: '破坏性修复给撤销（SnackBar 动作键）');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('D-2：没有备份记录时如实说「还没有备份过」（不编时间）', (tester) async {
    tester.view.physicalSize = const Size(390, 844 * 2);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DataSelfCheckPage(selfCheck: selfCheck)),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    expect(find.textContaining('还没有备份过'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('没有问题时如实说「没有发现问题」（不编一个 0 计数列表）', (tester) async {
    tester.view.physicalSize = const Size(390, 844 * 2);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DataSelfCheckPage(selfCheck: selfCheck)),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    expect(find.textContaining('没有发现问题'), findsOneWidget);
    expect(find.byKey(const Key('data-self-check-fix-orphans')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
