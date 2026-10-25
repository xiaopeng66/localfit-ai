import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/application/build_daily_meal_recommendation.dart';
import 'package:localfit_ai/features/nutrition/data/dish_library_repository.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/dish_record.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/menu_dish_list.dart';

/// 菜单页整套推荐（docs/28 §4.1）：段头 + 一张「今日三餐推荐」整套卡。
///
/// 2026-10-22 用户：「根据食堂菜品，直接给出从早餐到晚餐的一整套推荐，而不是
/// 分开」——早/午/晚从三张独立卡收进同一张卡；「其他已分析菜品」整块退场。
///
/// 断言全部锚在 Key 与几何上，不锚在「按钮文字」上：这一轮的返工里有两条
/// 缺陷正是「文案改了、按钮悄悄没了」（docs/28 §4.3 的 `MealEmptyAction`
/// 就是为此把文案判据换成了枚举）。
void main() {
  late AppDatabase database;
  late DishLibraryRepository dishes;
  late MealRepository meals;

  final now = DateTime(2026, 9, 15, 9); // 09:00：三餐时段都还没过
  final localDate = '2026-09-15';

  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    // 三餐块每块都揣着一张完整菜品卡（≈700dp）：默认 800 高的测试面里
    // 后面的块根本不会被构建，断言会「找不到控件」而不是「真的没有」。
    view.physicalSize = const Size(480, 6000);
    view.devicePixelRatio = 1;

    database = AppDatabase(NativeDatabase.memory());
    final clock = FixedAppClock(DateTime.utc(2026, 9, 15, 1));
    dishes = DishLibraryRepository(
      database: database,
      idGenerator: _Ids(),
      clock: clock,
    );
    meals = MealRepository(
      database: database,
      idGenerator: _Ids(),
      clock: clock,
    );
  });

  tearDown(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
    return database.close();
  });

  Future<DishRecord> addDish({
    required String name,
    required String mealSlot,
    required double kcal,
    String? servingWindow,
    String source = 'manual',
  }) => dishes.create(
    DishDraft(
      name: name,
      mealSlot: mealSlot,
      kcal: kcal,
      proteinG: 10,
      carbsG: 20,
      fatG: 5,
      source: source,
      servingWindow: servingWindow,
    ),
  );

  /// 当日目标 2000 kcal（三餐预算 600/800/600）。
  Future<void> seedTarget() async {
    final nowUtc = DateTime.utc(2026, 9, 15, 1);
    await database
        .into(database.profiles)
        .insert(
          ProfilesCompanion.insert(
            id: 'profile-1',
            activityLevel: 'moderate',
            createdAt: nowUtc,
            updatedAt: nowUtc,
          ),
        );
    await database
        .into(database.goals)
        .insert(
          GoalsCompanion.insert(
            id: 'goal-1',
            profileId: 'profile-1',
            type: 'maintain',
            calorieMinKcal: 1800,
            calorieMaxKcal: 2000,
            effectiveFrom: nowUtc,
            createdAt: nowUtc,
            updatedAt: nowUtc,
          ),
        );
    await database
        .into(database.dailyTargets)
        .insert(
          DailyTargetsCompanion.insert(
            id: 'target-1',
            goalId: 'goal-1',
            effectiveDate: localDate,
            calorieMinKcal: 1800,
            calorieMaxKcal: 2000,
            proteinMinGrams: 100,
            proteinMaxGrams: 140,
            carbsMinGrams: 200,
            carbsMaxGrams: 260,
            fatMinGrams: 50,
            fatMaxGrams: 70,
            createdAt: nowUtc,
            updatedAt: nowUtc,
          ),
        );
  }

  /// 小米粥(早 300) / 豆浆(早 100) / 鸡胸肉饭(午 600) / 番茄炒蛋(晚 200) /
  /// 酸奶(加餐 120)。加餐不进推荐位（2026-10-22 起「其他已分析菜品」整块退场，
  /// 它只是不出现在推荐里，不再单列一块）。
  Future<void> seedFiveDishes() async {
    await addDish(name: '小米粥', mealSlot: 'breakfast', kcal: 300);
    await addDish(name: '豆浆', mealSlot: 'breakfast', kcal: 100);
    await addDish(name: '鸡胸肉饭', mealSlot: 'lunch', kcal: 600);
    await addDish(name: '番茄炒蛋', mealSlot: 'dinner', kcal: 200);
    await addDish(name: '酸奶', mealSlot: 'snack', kcal: 120);
  }

  Widget host({
    VoidCallback? onOpenCanteen,
    Future<void> Function(DishRecord dish)? onAddToMeal,
    MealRepository? mealRepository,
    DishLibraryRepository? repository,
    DateTime? clockNow,
  }) => MaterialApp(
    home: Scaffold(
      body: MenuDishList(
        repository: repository ?? dishes,
        mealRepository: mealRepository ?? meals,
        now: clockNow ?? now,
        onAddToMeal: onAddToMeal,
        onOpenCanteen: onOpenCanteen,
      ),
    ),
  );

  /// drift 的流在取消时会排一个 0 时长的 Timer（`markAsClosed`）：测试树拆掉
  /// 之后它还在，`!timersPending` 断言就会把用例判红。拆树后 pump 一帧让
  /// 那个 Timer 跑掉——这是本仓既有的收尾写法（stress_ui / 2.0 巡检同款）。
  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  group('三餐块（docs/28 §4.1）', () {
    testWidgets('早/午/晚各一块，块头有时段与状态徽章', (tester) async {
      await seedTarget();
      await seedFiveDishes();
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      for (final slot in mealRecommendationSlots) {
        final key = 'nutrition-menu-meal-${slot.storedValue}';
        expect(find.byKey(Key(key)), findsOneWidget, reason: '$slot 有独立块');
        expect(find.byKey(Key('$key-badge')), findsOneWidget);
        // 状态必须由文字表达（docs/07 §9.3）：三块都有主推 → 都是「已推荐」。
        expect(find.text('已推荐'), findsNWidgets(3));
        // 块头带该餐的时段带，用户不用去别的页面查。
        expect(find.text(mealBandLabels[slot]!), findsOneWidget);
      }
      // 加餐不是一顿饭：没有第四个块。
      expect(find.byKey(const Key('nutrition-menu-meal-snack')), findsNothing);
      await drain(tester);
    });

    testWidgets('已记录的那一餐不插嘴：徽章「已记录」，且不渲染菜品卡', (tester) async {
      await seedTarget();
      await seedFiveDishes();
      await meals.create(
        MealDraft(
          localDate: localDate,
          slot: MealSlot.lunch,
          items: const [
            MealItemDraft(
              foodName: '鸡胸肉饭',
              grams: 300,
              nutrition: NutritionValues(
                kcal: 520,
                proteinGrams: 40,
                carbsGrams: 60,
                fatGrams: 12,
              ),
            ),
          ],
        ),
      );
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('nutrition-menu-meal-lunch-badge')),
        findsOneWidget,
      );
      expect(find.text('已记录'), findsOneWidget);
      // 午餐块不再推荐：没有菜品卡，只留一句成因。
      expect(find.byKey(const Key('nutrition-menu-dish-card-1')), findsNothing);
      expect(
        find.byKey(const Key('nutrition-menu-meal-lunch-reason')),
        findsOneWidget,
      );
      // 其他两餐照常推荐。
      expect(
        find.byKey(const Key('nutrition-menu-dish-card-0')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('nutrition-menu-dish-card-2')),
        findsOneWidget,
      );
      await drain(tester);
    });

    testWidgets('给不出推荐的一餐：一句成因 + 「去维护食堂目录」', (tester) async {
      var opened = 0;
      await seedTarget();
      // 只有午/晚/加餐，早餐一个候选都没有。
      await addDish(name: '鸡胸肉饭', mealSlot: 'lunch', kcal: 600);
      await addDish(name: '番茄炒蛋', mealSlot: 'dinner', kcal: 200);
      await tester.pumpWidget(host(onOpenCanteen: () => opened++));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('nutrition-menu-meal-breakfast-badge')),
        findsOneWidget,
      );
      expect(find.text('暂无推荐'), findsOneWidget);
      expect(find.byKey(const Key('nutrition-menu-dish-card-0')), findsNothing);

      final action = find.byKey(
        const Key('nutrition-menu-meal-breakfast-action'),
      );
      expect(action, findsOneWidget, reason: '空态必须给一个可执行的出口');
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(opened, 1);
      await drain(tester);
    });

    testWidgets('时段已经过了：给成因但不给按钮（没有可执行的动作）', (tester) async {
      await seedTarget();
      await seedFiveDishes();
      // 15:00：早（≤09:30）与午（≤14:00）都过了，只剩晚餐。
      //
      // **必须接线 `onOpenCanteen`**：不接线时按钮本来就画不出来，
      // 「没有按钮」这条断言就成了空断言（变异 M5 实测存活过一次）。
      await tester.pumpWidget(
        host(clockNow: DateTime(2026, 9, 15, 15), onOpenCanteen: () {}),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('nutrition-menu-meal-breakfast-badge')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('nutrition-menu-meal-breakfast-action')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('nutrition-menu-meal-lunch-action')),
        findsNothing,
      );
      // 成因还在（用户要知道为什么这一格是空的）。
      expect(
        find.byKey(const Key('nutrition-menu-meal-breakfast-reason')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('nutrition-menu-dish-card-2')),
        findsOneWidget,
      );
      await drain(tester);
    });

    testWidgets('加入按钮说的是菜品自己的餐次（写入落在 dish.mealSlot）', (tester) async {
      await seedTarget();
      // 窗口 11:00–14:00 横跨午餐时段带，但这道菜自己的标签是「加餐」；
      // `AddDishToMeal.run` 记到 `dish.mealSlot`，所以按钮必须说「加入加餐」
      // ——写成块头的「加入午餐」会让用户以为记进了午餐。
      await addDish(
        name: '窗口小食',
        mealSlot: 'snack',
        kcal: 300,
        servingWindow: '11:00-14:00',
      );
      // 必须接线 `onAddToMeal`：没接线时菜品卡不画加入按钮（降级不画假按钮），
      // 那样这条断言测的就不是「按钮写了什么」而是「有没有按钮」。
      await tester.pumpWidget(host(onAddToMeal: (dish) async {}));
      await tester.pumpAndSettle();
      expect(find.text('加入加餐'), findsOneWidget);
      expect(find.text('加入午餐'), findsNothing);
      await drain(tester);
    });

    testWidgets('段头汇总行：给三餐推荐数与总热量', (tester) async {
      await seedTarget();
      await seedFiveDishes();
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      // 2026-10-14（3-1 D25）：hero 卡退场，两枚统计改由段头汇总行的两段文字
      // 承接（Key 不变，件变了）：`-hero-planned` / `-hero-kcal` 现在是那两个
      // `Text` 自己，不再是被包在 Column 里的整块统计。
      expect(
        tester
            .widget<Text>(find.byKey(const Key('nutrition-menu-hero-planned')))
            .data,
        '已安排 3 餐',
      );
      // 300（粥）+ 600（鸡胸肉饭）+ 200（番茄炒蛋）= 1100
      expect(
        tester
            .widget<Text>(find.byKey(const Key('nutrition-menu-hero-kcal')))
            .data,
        '预计 1100 kcal',
      );
      await drain(tester);
    });
  });

  group('整套推荐（2026-10-22：一整套，不是分开）', () {
    testWidgets('早/午/晚在同一张卡里，且不再有「其他已分析菜品」', (tester) async {
      await seedTarget();
      await seedFiveDishes();
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      final setCard = find.byKey(const Key('nutrition-menu-daily-set'));
      expect(setCard, findsOneWidget, reason: '三餐是同一张卡里的三段');
      expect(
        find.byKey(const Key('nutrition-menu-daily-set-title')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('nutrition-menu-daily-set-badge')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('nutrition-menu-daily-set-intro')),
        findsOneWidget,
      );
      expect(find.text('今日三餐推荐'), findsOneWidget);
      expect(
        find.textContaining('早餐 → 午餐 → 晚餐 一次排出 · 同一道菜不跨餐重复'),
        findsOneWidget,
      );

      for (final slot in mealRecommendationSlots) {
        expect(
          find.descendant(
            of: setCard,
            matching: find.byKey(
              Key('nutrition-menu-meal-${slot.storedValue}'),
            ),
          ),
          findsOneWidget,
          reason: '${slot.label}段在整套卡内',
        );
      }

      // 2026-10-22 用户：「菜单界面不要显示其他已分析菜品」。
      expect(find.byKey(const Key('nutrition-menu-others')), findsNothing);
      expect(
        find.byKey(const Key('nutrition-menu-others-header')),
        findsNothing,
      );
      expect(find.text('其他已分析菜品'), findsNothing);
      await drain(tester);
    });

    // 【测试退役】「换一个只换这一餐」随 `RV4-P2-08`（单格「换一个」退役）
    // 删除——父决策 D3 就是「不要单格换，要整套换」。替代断言见
    // `daily_set_repick_test.dart`（整套重排 + 三枚 `-swap` 都不存在 +
    // 候选链仍在）。候选榜那条用例保留（选择能力没删）。

    testWidgets('候选榜：列出全部候选并标出当前展示的那一道', (tester) async {
      await seedTarget();
      await seedFiveDishes();
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('nutrition-menu-meal-breakfast-candidates')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('nutrition-menu-candidate-0')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('nutrition-menu-candidate-1')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('nutrition-menu-candidate-2')), findsNothing);

      // 点第二道 → 直接跳到那一道（不是「再换一格」）。
      await tester.tap(find.byKey(const Key('nutrition-menu-candidate-1')));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const Key('nutrition-menu-meal-breakfast')),
          matching: find.text('豆浆'),
        ),
        findsOneWidget,
      );
      await drain(tester);
    });
  });

  group('空态', () {
    testWidgets('菜品库为空：hero 仍在，给一句可照做的空态，不画三个空块', (tester) async {
      await seedTarget();
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('nutrition-menu-hero')), findsOneWidget);
      expect(find.text('菜品库还是空的。'), findsOneWidget);
      expect(find.text('在食堂目录里自建菜品，或让 AI 生成今日菜单。'), findsOneWidget);
      expect(
        find.byKey(const Key('nutrition-menu-meal-breakfast')),
        findsNothing,
      );
      // 没有推荐时不写 0 kcal（0 的意思是「今天不吃」）。
      expect(
        tester
            .widget<Text>(find.byKey(const Key('nutrition-menu-hero-kcal')))
            .data,
        '预计 —',
      );
      await drain(tester);
    });

    testWidgets('未接线：只说「尚未配置」，不拿别的表冒充菜品', (tester) async {
      // 直接搭这一个 widget（`host()` 会把 null 当成「用默认仓库」——
      // 那正好绕开本用例要测的分支）。
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MenuDishList(repository: null, now: now)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('菜品库尚未配置。'), findsOneWidget);
      expect(find.byKey(const Key('nutrition-menu-hero')), findsOneWidget);
      expect(
        find.byKey(const Key('nutrition-menu-meal-breakfast')),
        findsNothing,
      );
      await drain(tester);
    });
  });
}

final class _Ids implements IdGenerator {
  int _value = 0;

  @override
  String next() => 'id-${_value++}';
}
