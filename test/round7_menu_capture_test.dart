import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_router.dart';
import 'package:localfit_ai/app/localfit_app.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart';
import 'package:localfit_ai/features/nutrition/application/add_dish_to_meal.dart';
import 'package:localfit_ai/features/nutrition/data/dish_library_repository.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';
import 'package:localfit_ai/features/onboarding/domain/complete_onboarding.dart';
import 'package:localfit_ai/features/onboarding/domain/nutrition_target_calculator.dart';

import 'support/food_fixture.dart';
import 'support/round7_render.dart';

/// Round7 阶段 3 步骤 1 **菜单页整页渲染矩阵**（真装配 + 真数据）：3-1（D25–D30）
/// 把菜单 tab 改成 A `nutritionMenus()` 的骨架后，菜单页此前**没有任何渲染帧**
/// （阶段 2A 的矩阵只覆盖今日页与记录页），所以「改完长什么样」当时只能靠读码。
///
/// 与 `round7_page_capture_test.dart` 同一套口径：`LF_ROUND7_CAPTURE_DIR` 指向
/// 工作区 tmp 时才落盘，未设置时**仍会跑完并断言无异常**——所以它同时是
/// 「菜单页在各档宽度/字号下不溢出、且 A 的骨架件真的在」的回归面。
///
/// 数据是真装配算出来的：建档（真算法目标）→ 当日已有一餐（早餐 08:10 手动，
/// 让早餐槽呈现「已记录·不插嘴」；11 点后的午餐与晚餐仍是「已推荐」）→ 6 道菜
/// （覆盖早/午/晚/加餐四个餐次、照片占位渐变、
/// 热门、点评、微量营养素、供应时段）。菜品照片一律为空：**不伪造菜品照片**，
/// 帧里出现的只能是渐变占位（docs/21 §2.5）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const localDate = '2026-09-13';
  final now = DateTime(2026, 9, 13, 12);

  late AppDatabase database;
  late FoodRepository foodRepository;
  late MealRepository mealRepository;
  late DishLibraryRepository dishLibraryRepository;
  late CanteenRepository canteenRepository;
  late AddDishToMeal addDishToMeal;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await seedFoodFixture(database);
    const ids = UuidV7Generator();
    final clock = FixedAppClock(now);
    await CompleteOnboarding(
      database: database,
      idGenerator: ids,
      clock: clock,
    )(
      const OnboardingInput(
        age: 30,
        biologicalSex: BiologicalSex.male,
        heightCm: 175,
        weightKg: 72,
        activityLevel: ActivityLevel.moderatelyActive,
        goal: HealthGoal.loseFat,
        targetWeightKg: 66,
      ),
    );
    foodRepository = FoodRepository(
      database: database,
      idGenerator: ids,
      clock: clock,
    );
    mealRepository = MealRepository(
      database: database,
      idGenerator: ids,
      clock: clock,
    );
    dishLibraryRepository = DishLibraryRepository(
      database: database,
      idGenerator: ids,
      clock: clock,
    );
    canteenRepository = CanteenRepository(
      database: database,
      idGenerator: ids,
      clock: clock,
    );
    addDishToMeal = AddDishToMeal(mealRepository: mealRepository, clock: clock);

    // 当日只有早餐真的吃过（08:10，手动已确认）。**不写午餐**：整页矩阵
    // 的钟是 12:00，午餐（≤14:00 时段带）与晚餐都还没过 ⇒ 这两格是「已推荐」
    // 带卡片与动作行，早餐是「已记录·不插嘴」——一帧里同时看到两种状态，
    // 而不是把每个槽都摆成一样。
    //
    // 菜单页的三餐预算 = 剩余目标按 30/40/30 分给「还没吃、还没过」的餐位，
    // 所以这一餐必须真的落库，帧里的「本餐预算」与状态徽标才是事实。
    Future<void> seedMeal(
      DateTime at,
      MealSlot slot,
      List<MealItemDraft> items, {
      String source = 'manual',
    }) =>
        MealRepository(
          database: database,
          idGenerator: ids,
          clock: FixedAppClock(at.toUtc()),
        ).create(
          MealDraft(localDate: localDate, slot: slot, items: items),
          source: source,
        );

    await seedMeal(DateTime(2026, 9, 13, 8, 10), MealSlot.breakfast, const [
      MealItemDraft(
        foodName: '全麦吐司',
        grams: 80,
        nutrition: NutritionValues(
          kcal: 208,
          proteinGrams: 8.2,
          carbsGrams: 36.4,
          fatGrams: 3.1,
        ),
      ),
    ]);

    // 菜品库：6 道菜，其中早餐两道（候选 >1 ⇒「换一个」与「查看候选」都要画）。
    Future<void> seedDish({
      required String name,
      required String mealSlot,
      required double kcal,
      required double protein,
      required double carbs,
      required double fat,
      String source = 'manual',
      String? servingWindow,
      bool isHot = false,
      double? fiberG,
      double? sodiumMg,
      double? vitaminDMcg,
      String? comment,
    }) => dishLibraryRepository.create(
      DishDraft(
        name: name,
        mealSlot: mealSlot,
        kcal: kcal,
        proteinG: protein,
        carbsG: carbs,
        fatG: fat,
        source: source,
        servingWindow: servingWindow,
        isHot: isHot,
        fiberG: fiberG,
        sodiumMg: sodiumMg,
        vitaminDMcg: vitaminDMcg,
        comment: comment,
      ),
    );

    await seedDish(
      name: '小米粥',
      mealSlot: 'breakfast',
      kcal: 300,
      protein: 6.4,
      carbs: 62,
      fat: 2.1,
      servingWindow: '06:30-09:30',
      fiberG: 1.2,
      sodiumMg: 12,
      comment: '升糖慢，配一枚水煮蛋更稳。',
    );
    await seedDish(
      name: '鲜蔬蒸蛋',
      mealSlot: 'breakfast',
      kcal: 214,
      protein: 14.6,
      carbs: 3.1,
      fat: 15.4,
      servingWindow: '06:30-09:30',
      source: 'ai_estimate',
      vitaminDMcg: 2.4,
    );
    await seedDish(
      name: '鸡胸肉饭',
      mealSlot: 'lunch',
      kcal: 620,
      protein: 42.5,
      carbs: 68.2,
      fat: 16.8,
      servingWindow: '11:00-13:30',
      isHot: true,
      fiberG: 4.6,
      sodiumMg: 780,
      comment: '蛋白质够量，蔬菜偏少，配一份清炒时蔬。',
    );
    await seedDish(
      name: '番茄牛腩煲',
      mealSlot: 'lunch',
      kcal: 412,
      protein: 28.6,
      carbs: 18.2,
      fat: 24.8,
      servingWindow: '11:00-13:30',
      source: 'ai_estimate',
      sodiumMg: 920,
    );
    await seedDish(
      name: '西兰花炒鸡丁',
      mealSlot: 'dinner',
      kcal: 318,
      protein: 26.4,
      carbs: 12.6,
      fat: 18.2,
      servingWindow: '16:30-19:00',
      fiberG: 3.4,
    );
    await seedDish(
      name: '番茄烧豆腐',
      mealSlot: 'dinner',
      kcal: 292,
      protein: 18.4,
      carbs: 21.6,
      fat: 14.2,
      servingWindow: '16:30-19:00',
      source: 'ai_estimate',
      sodiumMg: 640,
    );
    await seedDish(
      name: '酸奶',
      mealSlot: 'snack',
      kcal: 120,
      protein: 4.2,
      carbs: 16.8,
      fat: 3.6,
      source: 'ai_estimate',
    );
  });

  tearDown(() async {
    await database.close();
  });

  Widget app({Key? key}) => LocalFitApp(
    key: key,
    initialLocation: AppRoutes.nutrition,
    foodRepository: foodRepository,
    mealRepository: mealRepository,
    dishLibraryRepository: dishLibraryRepository,
    canteenRepository: canteenRepository,
    addDishToMeal: addDishToMeal,
    now: now,
  );

  testWidgets('菜单页整页矩阵（2 主题 × 3 字号 × 4 宽度）', (tester) async {
    await tester.runAsync(loadRound7Fonts);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    /// 竖轴滚动余量（= 这一帧还装不下的部分，dp），与整页矩阵同口径。
    double scrollRemainder() {
      var worst = 0.0;
      for (final element in find.byType(Scrollable).evaluate()) {
        final state = (element as StatefulElement).state as ScrollableState;
        final position = state.position;
        if (position.axis != Axis.vertical) continue;
        final remaining = position.maxScrollExtent - position.pixels;
        if (remaining > worst) worst = remaining;
      }
      return worst;
    }

    for (final dark in [false, true]) {
      for (final scale in [1.0, 1.5, 2.0]) {
        for (final width in [320.0, 360.0, 390.0, 430.0]) {
          tester.view.devicePixelRatio = 1;
          var height = 2600 * scale;
          tester.view.physicalSize = Size(width, height);
          tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
          tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          tester.platformDispatcher.platformBrightnessTestValue = dark
              ? Brightness.dark
              : Brightness.light;
          // `UniqueKey` 强制每帧一个新 State：`LocalFitApp._router` 是
          // `late final`，复用同一棵树会继续渲染上一帧的页面（整页矩阵的
          // 2A 首轮踩过这个坑）。
          await tester.pumpWidget(
            RepaintBoundary(
              key: round7Boundary,
              child: app(key: UniqueKey()),
            ),
          );
          await tester.pumpAndSettle();
          // 菜单 tab 不是默认 tab：先切过去（有界推进——菜单页的骨架屏动画
          // 会让 `pumpAndSettle` 永不返回）。
          await tester.tap(find.text('菜单').first);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          await tester.pump(const Duration(seconds: 2));

          var missing = scrollRemainder();
          if (missing > 1) {
            height += missing;
            tester.view.physicalSize = Size(width, height);
            await tester.pumpAndSettle();
            missing = scrollRemainder();
          }
          expect(
            missing,
            lessThanOrEqualTo(1),
            reason:
                'menu ${dark ? 'dark' : 'light'} ${width.toInt()}x$scale '
                '加高后仍差 ${missing.toStringAsFixed(1)}dp——这一帧装不下整页',
          );

          // 帧必须是菜单页，且 A 的骨架件真的在：装了帧却渲染了别的 tab
          // （或段头/动作行整块没画）时，帧名会是唯一且不可信的说法。
          for (final key in const [
            Key('nutrition-subtab-bar'),
            Key('nutrition-menu-hero'),
            // 已记录的那一格（早餐）：有成因、没有卡片。
            Key('nutrition-menu-meal-breakfast-badge'),
            Key('nutrition-menu-meal-breakfast-reason'),
            // 已推荐的两格（午/晚）：卡片 + heading 行右端的「换一个」+ 动作行。
            // `RV4-P2-08`：单格 `-swap` 退役，整套重排入口改钉卡头那枚。
            Key('nutrition-menu-daily-set-repick'),
            Key('nutrition-menu-meal-lunch-candidates'),
            Key('cta-add-meal-1'),
            Key('cta-add-meal-2'),
            // 整套推荐卡（三餐在同一张卡里）+ 页尾（list-link / note）。
            Key('nutrition-menu-daily-set'),
            Key('cta-manage-canteen'),
            Key('nutrition-menu-note'),
          ]) {
            expect(
              find.byKey(key),
              findsOneWidget,
              reason:
                  'menu ${dark ? 'dark' : 'light'} ${width.toInt()}x$scale '
                  '缺 $key（接线断了？帧不代表菜单页）',
            );
          }
          expect(
            tester.takeException(),
            isNull,
            reason: 'menu ${dark ? 'dark' : 'light'} ${width.toInt()}x$scale',
          );
          await captureRound7(
            tester,
            'menu-${dark ? 'dark' : 'light'}-${width.toInt()}-$scale',
          );
        }
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
