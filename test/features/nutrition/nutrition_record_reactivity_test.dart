import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_router.dart';
import 'package:localfit_ai/app/design/widgets/app_number_field.dart';
import 'package:localfit_ai/app/localfit_app.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/nutrition_analysis_section.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/nutrition_record_energy_card.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/nutrition_record_week_strip.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/nutrition_trend_card.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/record_tab.dart';
import 'package:localfit_ai/features/progress/application/load_intake_trend.dart';
import 'package:localfit_ai/features/progress/application/trend_calculator.dart';

final _now = DateTime(2026, 9, 11, 12);
const _date = '2026-09-11';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'B05 meal save refreshes chart average and header from committed data',
    (tester) async {
      final h = await _Harness.create();
      try {
        await h.pumpApp(tester);
        _expectIntake(tester, consumed: 0, last: null, average: null);
        await tester.tap(find.byKey(const Key('nutrition-record-fab')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('meal-entry-by-food')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('meal-food-search')),
          'Regression Rice',
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byWidgetPredicate(
            (widget) => widget is Text && widget.data == 'Regression Rice',
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('meal-save')));
        await tester.pumpAndSettle();

        expect(
          (await h.meals.watchNutritionForDate(_date).first).consumed.kcal,
          100,
        );
        expect((await h.meals.watchForDate(_date).first).length, 1);
        _expectIntake(tester, consumed: 100, last: 100, average: 100);
      } finally {
        await _close(tester, h);
      }
    },
  );

  testWidgets(
    'B05 meal edit refreshes chart and average without changing tabs',
    (tester) async {
      final h = await _Harness.create();
      try {
        final id = await h.addMeal();
        await h.pumpApp(tester);
        _expectIntake(tester, consumed: 100, last: 100, average: 100);
        await tester.tap(find.byKey(Key('meal-$id')));
        await tester.pumpAndSettle();
        final grams = tester.widget<AppNumberField>(
          find.byWidgetPredicate(
            (widget) => widget is AppNumberField && widget.label == '克数',
          ),
        );
        await tester.enterText(find.byKey(grams.fieldKey), '200');
        await tester.tap(find.byKey(const Key('meal-save')));
        await tester.pumpAndSettle();

        expect((await h.meals.getById(id))!.nutrition.kcal, 200);
        _expectIntake(tester, consumed: 200, last: 200, average: 200);
      } finally {
        await _close(tester, h);
      }
    },
  );

  testWidgets('B05 single meal delete removes intake from chart and average', (
    tester,
  ) async {
    final h = await _Harness.create();
    try {
      final id = await h.addMeal();
      await h.pumpApp(tester);
      _expectIntake(tester, consumed: 100, last: 100, average: 100);
      await tester.tap(find.byKey(Key('meal-manage-$id')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('meal-delete-confirm')));
      await tester.pumpAndSettle();

      expect(await h.meals.getById(id), isNull);
      expect(find.byKey(Key('meal-$id')), findsNothing);
      _expectIntake(tester, consumed: 0, last: null, average: null);
    } finally {
      await _close(tester, h);
    }
  });

  testWidgets(
    'B05 bulk delete undo restores chart average and both meal rows',
    (tester) async {
      final h = await _Harness.create();
      try {
        final first = await h.addMeal();
        final second = await h.addMeal(grams: 50, slot: MealSlot.breakfast);
        await h.pumpApp(tester);
        _expectIntake(tester, consumed: 150, last: 150, average: 150);
        await tester.longPress(find.byKey(Key('meal-$first')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(Key('meal-$second')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('meals-bulk-delete')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('meals-bulk-delete-confirm')));
        await tester.pumpAndSettle();
        expect(await h.meals.watchForDate(_date).first, isEmpty);
        _expectIntake(tester, consumed: 0, last: null, average: null);

        await tester.tap(find.text('撤销'));
        await tester.pumpAndSettle();
        expect((await h.meals.getById(first))!.nutrition.kcal, 100);
        expect((await h.meals.getById(second))!.nutrition.kcal, 50);
        expect(find.byKey(Key('meal-$first')), findsOneWidget);
        expect(find.byKey(Key('meal-$second')), findsOneWidget);
        _expectIntake(tester, consumed: 150, last: 150, average: 150);
      } finally {
        await _close(tester, h);
      }
    },
  );

  testWidgets(
    'B05 direct meal item writes refresh chart and tracked-day averages',
    (tester) async {
      final h = await _Harness.create();
      try {
        final id = await h.addMeal();
        await h.addMeal(date: '2026-09-10', grams: 50);
        await h.pumpApp(tester);
        expect(_analysis(tester).trend.averageKcal, 75);
        await (h.db.update(
          h.db.mealItems,
        )..where((row) => row.mealId.equals(id))).write(
          const MealItemsCompanion(
            kcalSnapshot: Value(300),
            proteinSnapshot: Value(15),
          ),
        );
        await tester.pumpAndSettle();

        expect((await h.meals.getById(id))!.nutrition.kcal, 300);
        _expectIntake(tester, consumed: 300, last: 300, average: 175);
        expect(_analysis(tester).trend.averageMacros!.proteinGrams, 8.75);
        expect(_analysis(tester).trend.trackedDays, 2);
      } finally {
        await _close(tester, h);
      }
    },
  );

  testWidgets(
    'B05 direct meal date writes move chart intake without item writes',
    (tester) async {
      final h = await _Harness.create();
      try {
        final id = await h.addMeal();
        await h.pumpApp(tester);
        await (h.db.update(h.db.meals)..where((row) => row.id.equals(id)))
            .write(const MealsCompanion(localDate: Value('2026-09-10')));
        await tester.pumpAndSettle();

        expect((await h.meals.getById(id))!.localDate, '2026-09-10');
        _expectIntake(tester, consumed: 0, last: null, average: 100);
        expect(_chart(tester).bars.kcalByDay[5], 100);
        expect(_week(tester).selectedDate, DateTime(2026, 9, 11));
      } finally {
        await _close(tester, h);
      }
    },
  );

  testWidgets('B05 页面开着时新增餐食：达标天数从 0/7 变 1/7（不重启才更新）', (tester) async {
    final h = await _Harness.create();
    try {
      await h.seedTarget();
      await h.pumpApp(tester);
      // 有目标、无记录：0/7 是可复算的事实（不是占位）。
      expect(
        find.descendant(
          of: find.byKey(const Key('nutrition-record-analysis')),
          matching: find.text('0/7'),
        ),
        findsOneWidget,
      );

      await h.addMeal();
      await tester.pumpAndSettle();

      // 100 kcal 落在 80–200 区间内：今天必须计入达标天数。
      expect(
        find.descendant(
          of: find.byKey(const Key('nutrition-record-analysis')),
          matching: find.text('1/7'),
        ),
        findsOneWidget,
        reason: '页面开着时新增的餐食必须让分析卡立即重算，不能等重启',
      );
      expect(_chart(tester).bars.hitCount, 1);
    } finally {
      await _close(tester, h);
    }
  });

  testWidgets(
    'B05 daily target changes refresh goal line header and achievement',
    (tester) async {
      final h = await _Harness.create();
      try {
        await h.seedTarget();
        await h.addMeal();
        await h.pumpApp(tester);
        expect(_chart(tester).bars.hitCount, 1);
        expect(_hero(tester).target!.calorieMaxKcal, 200);
        await h.db
            .update(h.db.dailyTargets)
            .write(
              const DailyTargetsCompanion(
                calorieMinKcal: Value(150),
                calorieMaxKcal: Value(300),
              ),
            );
        await tester.pumpAndSettle();

        expect(
          (await h.db.select(h.db.dailyTargets).getSingle()).calorieMaxKcal,
          300,
        );
        expect(_hero(tester).target!.calorieMaxKcal, 300);
        expect(_chart(tester).targetKcal, 300);
        // 2026-10-23：达标按「未超上限」计——100 kcal 未超 300，仍计入。
        expect(_chart(tester).bars.hitCount, 1);
        expect(_analysis(tester).targetMinKcal, 150);
        expect(_analysis(tester).targetMaxKcal, 300);
        // 环心百分比也是 33%（100/300）——这里要钉的是**分析卡**的达成率，
        // 所以按卡范围限定，而不是全页找（D10 之后同一屏会出现两处同数字）。
        expect(
          find.descendant(
            of: find.byKey(const Key('nutrition-record-analysis')),
            matching: find.text('33%'),
          ),
          findsOneWidget,
        );
      } finally {
        await _close(tester, h);
      }
    },
  );

  testWidgets('B05 active goal writes invalidate the intake loader snapshot', (
    tester,
  ) async {
    final h = await _Harness.create();
    try {
      await h.seedTarget();
      await h.addMeal();
      await h.pumpApp(tester);
      expect(_analysis(tester).trend.goalDaysMet, 1);
      await h.db
          .update(h.db.goals)
          .write(
            const GoalsCompanion(
              calorieMinKcal: Value(150),
              calorieMaxKcal: Value(300),
            ),
          );
      await tester.pumpAndSettle();

      // 2026-10-23：达标按「未超上限」计——100 kcal 未超 300，仍计入。
      expect(_analysis(tester).trend.goalDaysMet, 1);
      _expectIntake(tester, consumed: 100, last: 100, average: 100);
    } finally {
      await _close(tester, h);
    }
  });

  testWidgets(
    'B06 selecting past Monday keeps Friday but excludes future meals and average',
    (tester) async {
      final h = await _Harness.create();
      try {
        await h.addMeal(grams: 300);
        await h.addMeal(date: '2026-09-07');
        await h.addMeal(date: '2026-09-02', grams: 40);
        await h.addMeal(date: '2026-09-12', grams: 900);
        await h.pumpApp(tester);
        expect(_week(tester).bars.kcalByDay[4], 300);
        await tester.tap(find.byKey(const Key('meal-day-2026-09-07')));
        await tester.pumpAndSettle();

        expect(
          (await h.meals.watchForDate(_date).first).single.nutrition.kcal,
          300,
        );
        expect(_week(tester).selectedDate, DateTime(2026, 9, 7));
        expect(_week(tester).bars.kcalByDay, [
          100,
          null,
          null,
          null,
          300,
          null,
          null,
        ]);
        expect(_chart(tester).bars.dates, [
          '2026-09-01',
          '2026-09-02',
          '2026-09-03',
          '2026-09-04',
          '2026-09-05',
          '2026-09-06',
          '2026-09-07',
        ]);
        _expectIntake(tester, consumed: 100, last: 100, average: 70);
        expect(_analysis(tester).trend.trackedDays, 2);
        expect(_analysis(tester).trend.averageMacros!.proteinGrams, 3.5);
        // 选中 09-07（周一）——页首的日期文案自 2B D10 起不在热量卡上，
        // 改由周条 `selectedDate` 这个渲染事实钉住（视觉落点见步骤 3）。
        expect(_week(tester).selectedDate, DateTime(2026, 9, 7));
      } finally {
        await _close(tester, h);
      }
    },
  );

  testWidgets(
    'B06 old-month week ends on Sunday and external writes preserve selected day',
    (tester) async {
      final h = await _Harness.create();
      try {
        await h.addMeal(date: '2026-07-27', grams: 80);
        final friday = await h.addMeal(date: '2026-07-31', grams: 240);
        await h.addMeal(date: '2026-08-02', grams: 160);
        await h.addMeal(date: '2026-08-03', grams: 900);
        final windows = <(int, DateTime)>[];
        await h.pumpRecord(
          tester,
          selected: DateTime(2026, 7, 27),
          loader: (days, end) {
            windows.add((days, end));
            return h.trend.run(days: days, endDate: end);
          },
        );

        expect(
          windows,
          [(7, DateTime(2026, 7, 27)), (6, DateTime(2026, 8, 2))],
          reason: 'Historical weeks must not scan the intervening months up to today.',
        );
        expect(_week(tester).bars.dates.last, '2026-08-02');
        expect(_week(tester).bars.kcalByDay, [
          80,
          null,
          null,
          null,
          240,
          null,
          160,
        ]);
        _expectIntake(tester, consumed: 80, last: 80, average: 80);
        await (h.db.update(h.db.mealItems)
              ..where((row) => row.mealId.equals(friday)))
            .write(const MealItemsCompanion(kcalSnapshot: Value(320)));
        await tester.pumpAndSettle();
        expect(_week(tester).selectedDate, DateTime(2026, 7, 27));
        expect(_week(tester).bars.kcalByDay, [
          80,
          null,
          null,
          null,
          320,
          null,
          160,
        ]);
        _expectIntake(tester, consumed: 80, last: 80, average: 80);
      } finally {
        await _close(tester, h);
      }
    },
  );

  testWidgets(
    'B05 late pre-write trend cannot overwrite a newer database snapshot',
    (tester) async {
      final h = await _Harness.create();
      final captured = Completer<void>();
      final release = Completer<void>();
      var loads = 0;
      try {
        final id = await h.addMeal();
        Future<IntakeTrend> load(int days, DateTime endDate) async {
          final first = ++loads == 1;
          final result = await h.trend.run(days: days, endDate: endDate);
          if (first) {
            captured.complete();
            await release.future;
          }
          return result;
        }

        await h.pumpRecord(tester, loader: load, settle: false);
        await captured.future;
        await (h.db.update(h.db.mealItems)
              ..where((row) => row.mealId.equals(id)))
            .write(const MealItemsCompanion(kcalSnapshot: Value(250)));
        for (var i = 0; i < 12; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(
          find.byType(NutritionTrendCard),
          findsOneWidget,
          reason: 'The committed write must launch a replacement for the held request.',
        );
        _expectIntake(tester, consumed: 250, last: 250, average: 250);
        release.complete();
        await tester.pumpAndSettle();
        _expectIntake(tester, consumed: 250, last: 250, average: 250);
        expect(
          loads,
          2,
          reason: 'One initial read and one table-change read; rebuilds must not loop.',
        );
      } finally {
        if (!release.isCompleted) release.complete();
        await _close(tester, h);
      }
    },
  );
}

void _viewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 3200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

NutritionTrendCard _chart(WidgetTester tester) =>
    tester.widget<NutritionTrendCard>(find.byType(NutritionTrendCard));
NutritionRecordEnergyCard _hero(WidgetTester tester) => tester
    .widget<NutritionRecordEnergyCard>(find.byType(NutritionRecordEnergyCard));
NutritionAnalysisSection _analysis(WidgetTester tester) => tester
    .widget<NutritionAnalysisSection>(find.byType(NutritionAnalysisSection));
NutritionRecordWeekStrip _week(WidgetTester tester) => tester
    .widget<NutritionRecordWeekStrip>(find.byType(NutritionRecordWeekStrip));

void _expectIntake(
  WidgetTester tester, {
  required double consumed,
  required double? last,
  required double? average,
}) {
  expect(
    {
      'header': _hero(tester).consumed.kcal,
      'chart': _chart(tester).bars.kcalByDay.last,
      'average': _analysis(tester).trend.averageKcal,
    },
    {'header': consumed, 'chart': last, 'average': average},
  );
  // 环心「已摄入」段：阶段 2B D10 起锚点挂在 `Text` 本身上（共享热量卡的
  // `keyPrefix`），不再像旧 hero 那样挂在外层 Column 上——直接取 `data` 断言，
  // 比 `descendant` 更强（值不等也红）。
  expect(
    tester
        .widget<Text>(find.byKey(const Key('nutrition-record-energy-consumed')))
        .data,
    consumed.round().toString(),
  );
  if (average != null) {
    expect(
      find.descendant(
        of: find.byKey(const Key('nutrition-record-analysis')),
        matching: find.text(average.round().toString()),
      ),
      findsOneWidget,
    );
  }
}

Future<void> _close(WidgetTester tester, _Harness h) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
  await h.db.close();
  await tester.pump(const Duration(milliseconds: 1));
}

class _Harness {
  _Harness(this.db, this.foods, this.meals);
  final AppDatabase db;
  final FoodRepository foods;
  final MealRepository meals;
  LoadIntakeTrend get trend => LoadIntakeTrend(
    database: db,
    mealRepository: meals,
    clock: FixedAppClock(_now.toUtc()),
  );

  static Future<_Harness> create() async {
    final db = AppDatabase(NativeDatabase.memory());
    final ids = _Ids();
    final clock = FixedAppClock(_now.toUtc());
    await db
        .into(db.foods)
        .insert(
          FoodsCompanion.insert(
            id: 'regression-rice',
            name: 'Regression Rice',
            kcalPer100g: 100,
            proteinPer100g: 5,
            carbsPer100g: 20,
            fatPer100g: 0,
            source: 'manual',
            isUserCreated: const Value(true),
            createdAt: _now.toUtc(),
            updatedAt: _now.toUtc(),
          ),
        );
    return _Harness(
      db,
      FoodRepository(database: db, idGenerator: ids, clock: clock),
      MealRepository(database: db, idGenerator: ids, clock: clock),
    );
  }

  Future<String> addMeal({
    String date = _date,
    double grams = 100,
    MealSlot slot = MealSlot.lunch,
  }) async {
    final food = (await foods.search('Regression Rice')).single;
    return meals.create(
      MealDraft(
        localDate: date,
        slot: slot,
        items: [MealItemDraft.fromFood(food, grams)],
      ),
    );
  }

  Future<void> pumpApp(WidgetTester tester) async {
    _viewport(tester);
    await tester.pumpWidget(
      LocalFitApp(
        initialLocation: AppRoutes.nutrition,
        foodRepository: foods,
        mealRepository: meals,
        now: _now,
        loadIntakeTrend: trend,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpRecord(
    WidgetTester tester, {
    DateTime? selected,
    Future<IntakeTrend> Function(int, DateTime)? loader,
    bool settle = true,
  }) async {
    _viewport(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecordTab(
            mealRepository: meals,
            selectedDate: selected ?? DateTime(2026, 9, 11),
            now: _now,
            onSelectDate: (_) {},
            onEditMeal: (_) {},
            onDeleteMeal: (_) {},
            loadTrend:
                loader ?? (days, end) => trend.run(days: days, endDate: end),
          ),
        ),
      ),
    );
    if (settle) await tester.pumpAndSettle();
  }

  Future<void> seedTarget() async {
    await db
        .into(db.profiles)
        .insert(
          ProfilesCompanion.insert(
            id: 'nutrition-profile',
            activityLevel: 'moderate',
            createdAt: _now,
            updatedAt: _now,
          ),
        );
    await db
        .into(db.goals)
        .insert(
          GoalsCompanion.insert(
            id: 'nutrition-goal',
            profileId: 'nutrition-profile',
            type: 'maintain',
            calorieMinKcal: 80,
            calorieMaxKcal: 200,
            effectiveFrom: _now,
            createdAt: _now,
            updatedAt: _now,
          ),
        );
    await db
        .into(db.dailyTargets)
        .insert(
          DailyTargetsCompanion.insert(
            id: 'nutrition-target',
            goalId: 'nutrition-goal',
            effectiveDate: '2026-09-01',
            calorieMinKcal: 80,
            calorieMaxKcal: 200,
            proteinMinGrams: 10,
            proteinMaxGrams: 50,
            carbsMinGrams: 10,
            carbsMaxGrams: 100,
            fatMinGrams: 10,
            fatMaxGrams: 50,
            createdAt: _now,
            updatedAt: _now,
          ),
        );
  }
}

class _Ids implements IdGenerator {
  int value = 0;
  @override
  String next() => 'nutrition-regression-${value++}';
}
