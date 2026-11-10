import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/nutrition_record_slot_grouping.dart';

/// B-3（docs/64 阶段 4）：**过去日期也能补记** —— 用户 2026-10-27 裁决
/// 「30 天，继续」：可以补记，窗口 30 天（推翻「历史只读」这条旧设计）。
///
/// 写路径本来就按选中日（`NutritionActions.editMeal` 用
/// `formatLocalDate(selectedDate())`），所以本轮只做两件事：
/// ① 放开 UI 门禁（今天或近 30 天内画「+」）；② 非今天时给「补记」徽标，
/// 免得用户以为是今天；更早与未来**不画**，并在页面上如实说清楚。
void main() {
  late AppDatabase database;
  late MealRepository meals;

  final now = DateTime(2026, 10, 26, 12);
  const today = '2026-10-26';
  const yesterday = '2026-10-25';
  const thirtyDaysAgo = '2026-09-26'; // now - 30 天，窗口内边界
  const tooOld = '2026-09-25'; // now - 31 天，窗口外
  const tomorrow = '2026-10-27';

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    meals = MealRepository(
      database: database,
      idGenerator: const UuidV7Generator(),
      clock: FixedAppClock(now.toUtc()),
    );
  });

  tearDown(() => database.close());

  Future<String> addMeal(
    String localDate, {
    MealSlot slot = MealSlot.lunch,
  }) async {
    final id = await meals.create(
      MealDraft(
        localDate: localDate,
        slot: slot,
        items: const [
          MealItemDraft(
            foodName: '补记测试食物',
            grams: 100,
            nutrition: NutritionValues(
              kcal: 300,
              proteinGrams: 10,
              carbsGrams: 30,
              fatGrams: 10,
            ),
          ),
        ],
      ),
    );
    return id;
  }

  Future<void> pumpGrouping(
    WidgetTester tester, {
    required String localDate,
    ValueChanged<MealSlot>? onAddToSlot,
  }) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: NutritionRecordSlotGrouping(
              repository: meals,
              localDate: localDate,
              now: now,
              onAddToSlot: onAddToSlot,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> drainStream(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('选中昨天：槽位头有「+」，点了记到昨天（不是今天）', (tester) async {
    final taps = <MealSlot>[];
    await pumpGrouping(tester, localDate: yesterday, onAddToSlot: taps.add);

    final addKey = const Key('nutrition-record-slot-lunch-add');
    expect(find.byKey(addKey), findsOneWidget, reason: 'B-3：过去日期（窗口内）必须也能补记');
    await tester.tap(find.byKey(addKey));
    expect(taps, [MealSlot.lunch], reason: '点了要按**被点那一槽位**开记餐入口');

    // 「补记」徽标：非今天必须与今天区分开（免得用户以为是今天）。
    expect(
      find.byKey(const Key('nutrition-record-backfill-badge')),
      findsWidgets,
      reason: '非今天的槽位头要有「补记」徽标',
    );
    await drainStream(tester);
  });

  testWidgets('补记的行与今天的分开：昨天的合计只影响昨天', (tester) async {
    final yesterdayMeal = await addMeal(yesterday);
    final todayMeal = await addMeal(today);

    // 回看昨天：只出现昨天那条（补记的行不会串到别的日期）。
    await pumpGrouping(tester, localDate: yesterday, onAddToSlot: (_) {});
    expect(find.byKey(Key('meal-$yesterdayMeal')), findsOneWidget);
    expect(
      find.byKey(Key('meal-$todayMeal')),
      findsNothing,
      reason: '昨天的视图不许出现今天的记录',
    );
    expect(
      (await meals.watchForDate(yesterday).first).single.nutrition.kcal,
      300,
    );
    await drainStream(tester);

    // 看今天：只有今天那条，且**没有**补记徽标（今天不是补记）。
    await pumpGrouping(tester, localDate: today, onAddToSlot: (_) {});
    expect(find.byKey(Key('meal-$todayMeal')), findsOneWidget);
    expect(
      find.byKey(Key('meal-$yesterdayMeal')),
      findsNothing,
      reason: '今天的视图不许出现昨天的记录',
    );
    expect(
      find.byKey(const Key('nutrition-record-backfill-badge')),
      findsNothing,
      reason: '今天不是补记',
    );
    await drainStream(tester);
  });

  testWidgets('窗口边界：正好 30 天可补记；超过窗口不画「+」并如实说明', (tester) async {
    // 边界内：now - 30 天 → 有「+」。
    await pumpGrouping(tester, localDate: thirtyDaysAgo, onAddToSlot: (_) {});
    expect(
      find.byKey(const Key('nutrition-record-slot-lunch-add')),
      findsOneWidget,
      reason: '30 天整仍在补记窗口内',
    );
    await drainStream(tester);

    // 窗口外（31 天前）：不画「+」，并如实说窗口。
    await pumpGrouping(tester, localDate: tooOld, onAddToSlot: (_) {});
    expect(
      find.byKey(const Key('nutrition-record-slot-lunch-add')),
      findsNothing,
      reason: '超过 30 天不许补记（给了也会被当成误补）',
    );
    expect(
      find.byKey(const Key('nutrition-record-backfill-window-note')),
      findsOneWidget,
      reason: '窗口外要如实说「只支持补记近 30 天」，不能默默少一个按钮',
    );
    await drainStream(tester);
  });

  testWidgets('未来日期：不画「+」（仓储也拒绝）', (tester) async {
    await pumpGrouping(tester, localDate: tomorrow, onAddToSlot: (_) {});
    expect(
      find.byKey(const Key('nutrition-record-slot-lunch-add')),
      findsNothing,
      reason: '未来日期不许出现补记入口（B-2 仓储守卫也会拒）',
    );
    expect(
      find.byKey(const Key('nutrition-record-backfill-badge')),
      findsNothing,
    );
    await drainStream(tester);
  });
}
