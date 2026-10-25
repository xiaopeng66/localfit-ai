import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/record_tab.dart';
import 'package:localfit_ai/features/progress/application/trend_calculator.dart';

/// 记录页的**页序与段间距**（阶段 2B 步骤 6）。
///
/// A 的 `nutritionRecords()`（`design/round7/app.js:171`）把页级区块按这个
/// 顺序拼出来：
///
/// ```text
/// dates(.date-strip) → .selected-date → energy() → sourceSummary()
///                    → nutritionTrend() → timeline(.meal-timeline)
/// ```
///
/// 而 A 的页级间距来自 `.page{padding:12px 16px 28px; gap:16px}`
/// （`refinement.css:3`）：页首元素距胶囊行 12dp、左右各 16dp、相邻区块
/// 净距 16dp；时间线内部另有 `.meal-timeline{gap:12px}`。
///
/// 本仓在 A 的顺序上插入了两张设计稿没画的卡（均按裁决 ② 收在既有位置）：
/// `leading`（下一餐入口，接在置信摘要之下）与分析卡（时间线之下，分析卡
/// 是 2B 之前就有的自足件，A 的 `nutritionRecords()` 没有它）。
///
/// 之所以单独立文件：改造期的记录页把**周条放在了趋势卡之后**（A 是页首），
/// 而热量卡沿用了旧全宽 hero 的装配——没有左右页边距、顶距 0（旧 hero 的
/// 渐变铺满整宽，内边距在渐变内部；换成共享白卡后这层装配就成了缺陷）。
/// 这些都不是任一组件自己的事，是**页级装配**的事，所以在页级钉住。
void main() {
  late AppDatabase database;
  late FoodRepository foods;
  late MealRepository meals;

  final now = DateTime(2026, 9, 9, 12);
  const today = '2026-09-09';
  const viewportWidth = 900.0;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    final ids = _IncrementingIdGenerator();
    foods = FoodRepository(
      database: database,
      idGenerator: ids,
      clock: FixedAppClock(now.toUtc()),
    );
    meals = MealRepository(
      database: database,
      idGenerator: ids,
      clock: FixedAppClock(now.toUtc()),
    );
  });

  tearDown(() => database.close());

  Future<void> seed() async {
    await database
        .into(database.foods)
        .insert(
          FoodsCompanion.insert(
            id: 'food-rice',
            name: '米饭',
            kcalPer100g: 116,
            proteinPer100g: 2.6,
            carbsPer100g: 25.9,
            fatPer100g: 0.3,
            source: 'seed',
            createdAt: now.toUtc(),
            updatedAt: now.toUtc(),
          ),
        );
    await database
        .into(database.profiles)
        .insert(
          ProfilesCompanion.insert(
            id: 'p1',
            activityLevel: 'moderate',
            createdAt: now.toUtc(),
            updatedAt: now.toUtc(),
          ),
        );
    await database
        .into(database.goals)
        .insert(
          GoalsCompanion.insert(
            id: 'g1',
            profileId: 'p1',
            type: 'loseFat',
            calorieMinKcal: 1500,
            calorieMaxKcal: 1800,
            effectiveFrom: now.toUtc(),
            createdAt: now.toUtc(),
            updatedAt: now.toUtc(),
          ),
        );
    await database
        .into(database.dailyTargets)
        .insert(
          DailyTargetsCompanion.insert(
            id: 't1',
            goalId: 'g1',
            effectiveDate: '2026-09-01',
            calorieMinKcal: 1500,
            calorieMaxKcal: 1800,
            proteinMinGrams: 50,
            proteinMaxGrams: 60,
            carbsMinGrams: 180,
            carbsMaxGrams: 200,
            fatMinGrams: 40,
            fatMaxGrams: 50,
            createdAt: now.toUtc(),
            updatedAt: now.toUtc(),
          ),
        );
    final rice = (await foods.search('米饭')).first;
    // 两条真餐食：置信摘要要有得数、槽位分组要有真卡。
    await meals.create(
      MealDraft(
        localDate: today,
        slot: MealSlot.breakfast,
        items: [MealItemDraft.fromFood(rice, 100)],
      ),
    );
    await meals.create(
      MealDraft(
        localDate: today,
        slot: MealSlot.lunch,
        items: [MealItemDraft.fromFood(rice, 150)],
      ),
      source: 'ai_scan',
    );
  }

  Future<void> pumpTab(WidgetTester tester) async {
    // 视口高到一屏装下整页（3600 > 内容高）：所有区块都在首帧构建，
    // 可以直接比矩形而不必滚动——滚动会让已建区块的位置整体平移，
    // 「谁在谁上面」会变得依赖滚动量。
    tester.view.physicalSize = const Size(viewportWidth, 3600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecordTab(
            mealRepository: meals,
            selectedDate: DateTime(2026, 9, 9),
            now: now,
            onSelectDate: (_) {},
            onEditMeal: (_) {},
            onDeleteMeal: (_) {},
            onAddToSlot: (_) {},
            loadTrend: (days, endDate) async =>
                const TrendCalculator().calculate(
                  records: const [
                    DailyIntakeRecord(
                      localDate: '2026-09-08',
                      kcal: 1200,
                      proteinGrams: 30,
                      carbsGrams: 120,
                      fatGrams: 40,
                    ),
                    DailyIntakeRecord(
                      localDate: today,
                      kcal: 1800,
                      proteinGrams: 46,
                      carbsGrams: 260,
                      fatGrams: 60,
                    ),
                  ],
                  goal: null,
                ),
            // 生产装配里这一格是「下一餐」入口（A 的页序里没有它，按裁决 ②
            // 接在置信摘要之下）；这里用等高的探针替身，只量页级间距。
            leading: const SizedBox(
              key: Key('order-leading-probe'),
              height: 40,
              width: double.infinity,
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

  final strip = find.byKey(const Key('nutrition-record-week-strip'));
  final selectedDate = find.byKey(const Key('nutrition-record-selected-date'));
  final energy = find.byKey(const Key('nutrition-record-energy'));
  final summary = find.byKey(const Key('confidence-summary'));
  final leading = find.byKey(const Key('order-leading-probe'));
  final trend = find.byKey(const Key('nutrition-record-trend-chart'));
  final breakfast = find.byKey(const Key('nutrition-record-slot-breakfast'));
  final snack = find.byKey(const Key('nutrition-record-slot-snack'));
  final analysis = find.byKey(const Key('nutrition-record-analysis'));

  testWidgets(
    '页序 = A nutritionRecords()：周条 → 日期行 → 热量卡 → 摘要 → 下一餐 → 趋势 → 时间线 → 分析',
    (tester) async {
      await seed();
      await pumpTab(tester);

      // A 自上而下的顺序。逐段比较 top：任一段插错位置都会在这里红。
      final order = <String, Finder>{
        '周条 .date-strip': strip,
        '日期行 .selected-date': selectedDate,
        '热量卡 energy()': energy,
        '置信摘要 .source-summary': summary,
        '下一餐入口（本仓件）': leading,
        '趋势卡 nutritionTrend()': trend,
        '时间线 .meal-timeline': breakfast,
        '分析卡（本仓件）': analysis,
      };
      var previousTop = -1.0;
      for (final entry in order.entries) {
        final rect = tester.getRect(entry.value);
        expect(
          rect.top,
          greaterThanOrEqualTo(previousTop),
          reason: '${entry.key} 必须排在前一段之下（A 的页序）',
        );
        previousTop = rect.top;
      }

      // 页首元素顶距 = A 的 `.page{padding-top:12px}`。旧装配把周条放在趋势
      // 卡之后，页首是热量卡且顶距 0（贴住胶囊行）。
      expect(tester.getRect(strip).top, 12, reason: 'A .page padding-top 12');

      await drainStream(tester);
    },
  );

  testWidgets('段间距 = A 的 `.page{gap:16px}`（含时间线内 12dp、分析卡之上 16dp）', (
    tester,
  ) async {
    await seed();
    await pumpTab(tester);

    double top(Finder finder) => tester.getRect(finder).top;
    double bottom(Finder finder) => tester.getRect(finder).bottom;

    // 周条 → 日期行 8dp：A 的 `.selected-date{margin-top:-8px}` 抵掉页间隙。
    expect(
      top(selectedDate) - bottom(strip),
      8,
      reason: 'A .selected-date{margin-top:-8px}（页间隙 16 − 8）',
    );
    // 日期行 → 热量卡 16dp。
    expect(
      top(energy) - bottom(selectedDate),
      LfDimens.pagePadding,
      reason: 'A .page{gap:16px}',
    );
    // 热量卡 → 摘要 20dp = 16 页间隙 + 摘要件自身的 4dp 内衬。
    expect(top(summary) - bottom(energy), 20, reason: '16 页间隙 + 摘要 4dp 内衬');
    // 摘要 → 下一餐 20dp（同上，摘要件下缘也有 4dp）。
    expect(top(leading) - bottom(summary), 20, reason: '摘要 4dp 内衬 + 16 页间隙');
    // 下一餐 → 趋势卡 16dp。
    expect(
      top(trend) - bottom(leading),
      LfDimens.pagePadding,
      reason: 'A .page{gap:16px}',
    );
    // 趋势卡 → 时间线 16dp：旧装配此处是「趋势 → 周条」12dp，周条搬走后
    // 时间线直接接趋势卡，间距按 A 的页间隙。
    expect(
      top(breakfast) - bottom(trend),
      LfDimens.pagePadding,
      reason: 'A .page{gap:16px}（趋势卡之后是时间线）',
    );
    // 时间线 → 分析卡 16dp：旧装配两卡边框相贴（0dp，审看发现的缺陷 ⑦）。
    expect(
      top(analysis) - bottom(snack),
      LfDimens.pagePadding,
      reason: 'A .page{gap:16px} 同源的页级间距',
    );

    await drainStream(tester);
  });

  testWidgets('左右页边距：页级区块一律 16dp（热量卡曾沿用旧全宽 hero 的装配）', (tester) async {
    await seed();
    await pumpTab(tester);

    // 日期行是**文本行**（宽度随字数收），只判左缘；其余是页级卡，左右都判。
    expect(tester.getRect(selectedDate).left, LfDimens.pagePadding);
    for (final entry in <String, Finder>{
      '周条': strip,
      '热量卡': energy,
      '置信摘要': summary,
      '趋势卡': trend,
      '槽位卡': breakfast,
      '分析卡': analysis,
    }.entries) {
      final rect = tester.getRect(entry.value);
      expect(
        rect.left,
        LfDimens.pagePadding,
        reason: '${entry.key} 左缘 = A 的 `.page{padding-left:16px}`',
      );
      expect(
        rect.right,
        viewportWidth - LfDimens.pagePadding,
        reason: '${entry.key} 右缘 = A 的 `.page{padding-right:16px}`',
      );
    }

    await drainStream(tester);
  });

  testWidgets('时间线内四张槽位卡竖直排、间距 12dp（A `.meal-timeline{gap:12px}`）', (
    tester,
  ) async {
    await seed();
    await pumpTab(tester);

    for (final entry in <String, Finder>{
      '早餐': breakfast,
      '午餐': find.byKey(const Key('nutrition-record-slot-lunch')),
      '晚餐': find.byKey(const Key('nutrition-record-slot-dinner')),
      '加餐': snack,
    }.entries) {
      expect(entry.value, findsOneWidget, reason: '${entry.key}卡必须在');
    }
    expect(
      tester.getRect(find.byKey(const Key('nutrition-record-slot-lunch'))).top -
          tester.getRect(breakfast).bottom,
      12,
      reason: 'A .meal-timeline{gap:12px}',
    );

    await drainStream(tester);
  });
}

class _IncrementingIdGenerator implements IdGenerator {
  var _next = 0;

  @override
  String next() => 'id-${_next++}';
}
