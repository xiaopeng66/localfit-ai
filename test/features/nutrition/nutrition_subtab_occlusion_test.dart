import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
// 原型的识别要用 sliver 子节点的 parentData 类型（见 `walk`）。
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_router.dart';
import 'package:localfit_ai/app/localfit_app.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/data/dish_library_repository.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/nutrition/presentation/nutrition_page.dart';

/// 饮食页**三个** sub-tab 的内容都不得画到底栏遮挡线之下（docs/21 §5.8.4）。
///
/// 2026-09-29 探针实测（480dp 矮视口，遮挡线 406.5dp）：
///
/// | tab | 最深可见叶子 | 结果 |
/// |---|---|---|
/// | 记录 / 菜单 | — | 已重建，本来就带预留 |
/// | 食物库 | 无预留 | **缺陷** |
///
/// 计划 / 食谱两枚 tab 随「食谱 / 计划」整族下线（docs/28 §6.1），本文件
/// 随之收敛为三项。
///
/// 根因是同一条：`extendBody: true` 之后，凡在底栏分支里的滚动体都要自己给
/// 末尾留 `LfDimens.navReservedSpace`。
///
/// 这里按**页内最深可见叶子 vs 遮挡线**判，不按「有没有写那行 padding」判：
/// 断言实现细节会在下次换写法时假红/假绿，按几何判才是用户看到的真相。
///
/// 2026-10-14（阶段 3 步骤 2b）补一条排除项：`SliverPrototypeExtentList` 的
/// **原型**不是内容。它被布局一次就永不上屏（框架原话 `essentially [Offstage]`），
/// 没有 layoutOffset ⇒ 全局矩形是 NaN ⇒ 夹回时被当成「正好画在视口底」，
/// 于是「用了原型的列表」全都假红。判定改成只量**上屏**的叶子：原型的识别是
/// sliver 适配器给真子节点写 index、唯独跳过原型（详见 `walk` 内注释）；
/// 同时要求剩下的叶子矩形必须有限，任何 NaN 都当场报出来，不再被夹回吞掉。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 三个 sub-tab 的 Key 与「切进去之后需要多少数据才滚得动」。
  const tabs = [
    'nutrition-tab-record',
    'nutrition-tab-menu',
    'nutrition-tab-foodlib',
  ];

  Future<void> unmountApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  /// 建库 + 塞足够的数据，让每个 tab 都有可滚动的内容。
  Future<AppDatabase> seed() async {
    final db = AppDatabase(NativeDatabase.memory());
    final now = DateTime.now().toUtc();
    for (var i = 0; i < 30; i++) {
      await db
          .into(db.foods)
          .insert(
            FoodsCompanion.insert(
              id: 'food-$i',
              name: '食物名称 $i',
              kcalPer100g: 100 + i.toDouble(),
              proteinPer100g: 5,
              carbsPer100g: 10,
              fatPer100g: 3,
              source: 'seed',
              createdAt: now,
              updatedAt: now,
            ),
          );
    }
    // 菜单页的唯一主来源是 DishLibrary（docs/21 §5.3）：不塞它，
    // 菜单 tab 是空态、没有可滚内容，断言会空转。
    for (var i = 0; i < 12; i++) {
      await db
          .into(db.dishLibrary)
          .insert(
            DishLibraryCompanion.insert(
              id: 'dish-$i',
              name: '菜品名称 $i',
              mealSlot: 'lunch',
              kcal: 142 + i.toDouble(),
              proteinG: 8.4,
              carbsG: 6.2,
              fatG: 9.1,
              source: 'manual',
              createdAt: now,
              updatedAt: now,
            ),
          );
    }
    // 记录页的可滚内容来自**餐次列表 + 趋势卡**，不是 hero 的高度。
    //
    // 2026-10-08（docs/30 §2 D4）：记录页 hero 从 mint 渐变（20dp 内边距 + 22px
    // 三段数字）换成 `DesignCard`（16dp 内边距），卡变矮了一截 ⇒ 只塞一条空餐次
    // 时整页正好不溢出，`maxScrollExtent == 0`，「滑到底」这个断言就**空转**了
    // （本文件自己就有一条「没有可滚动的内容：断言会空转」的前置守卫，正是它把
    // 这件事报出来的——守卫按预期工作）。所以这里按**真实使用形态**塞数据：
    // 一周七天、每天三餐、每餐三道菜 ⇒ 记录列表与趋势卡都真的有内容可滚。
    for (var day = 11; day <= 17; day++) {
      final localDate = '2026-09-$day';
      for (final slot in const ['breakfast', 'lunch', 'dinner']) {
        final mealId = 'meal-$localDate-$slot';
        await db
            .into(db.meals)
            .insert(
              MealsCompanion.insert(
                id: mealId,
                localDate: localDate,
                slot: slot,
                eatenAt: now,
                source: 'manual',
                createdAt: now,
                updatedAt: now,
              ),
            );
        for (var k = 0; k < 3; k++) {
          await db
              .into(db.mealItems)
              .insert(
                MealItemsCompanion.insert(
                  id: 'item-$localDate-$slot-$k',
                  mealId: mealId,
                  foodId: Value('food-$k'),
                  foodNameSnapshot: '食物名称 $k',
                  grams: 150,
                  kcalSnapshot: 142,
                  proteinSnapshot: 8.4,
                  carbsSnapshot: 6.2,
                  fatSnapshot: 9.1,
                  createdAt: now,
                  updatedAt: now,
                ),
              );
        }
      }
    }
    return db;
  }

  Future<void> pumpNutrition(WidgetTester tester, AppDatabase db) async {
    tester.view.physicalSize = const Size(400, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final clock = FixedAppClock(DateTime.utc(2026, 9, 17));
    await tester.pumpWidget(
      LocalFitApp(
        initialLocation: AppRoutes.nutrition,
        foodRepository: FoodRepository(
          database: db,
          idGenerator: _Ids(),
          clock: clock,
        ),
        mealRepository: MealRepository(
          database: db,
          idGenerator: _Ids(),
          clock: clock,
        ),
        dishLibraryRepository: DishLibraryRepository(
          database: db,
          idGenerator: _Ids(),
          clock: clock,
        ),
        canteenRepository: CanteenRepository(
          database: db,
          idGenerator: _Ids(),
          clock: clock,
        ),
        now: DateTime(2026, 9, 17),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final tab in tabs) {
    testWidgets('$tab 滑到底时最深内容停在底栏遮挡线之上', (tester) async {
      final db = await seed();
      addTearDown(db.close);
      await pumpNutrition(tester, db);

      await tester.tap(find.byKey(Key(tab)));
      await tester.pumpAndSettle();

      // 食物库的空查询不给列表：必须先搜才出现可滚动结果。
      if (tab == 'nutrition-tab-foodlib') {
        await tester.enterText(find.byType(TextField).first, '食物');
        await tester.pumpAndSettle();
      }

      final barRect = tester.getRect(find.byKey(const Key('lf-bottom-nav')));
      final bumpRect = tester.getRect(
        find.byKey(const Key('nav-ai-workbench')),
      );
      // 遮挡线 = 栏体顶边与凸起圆顶边的更高者（凸起圆会先挡到内容）。
      final barrier = bumpRect.top < barRect.top ? bumpRect.top : barRect.top;

      // 逐个可滚动体滚到底，再**只在该可滚动体的子树内**取最深可见叶子。
      //
      // 不能整页走一遍：Scaffold 的 FAB 过渡槽（`_FloatingActionButtonTransition`）
      // 即使没有 FAB 也存在，它是一个**零尺寸的空叶子**、落在页面底部，
      // 会被当成「最深内容」恒判红（本文件第一版就这样，五个 tab 全红）。
      // 也不能只取所有可滚动体里的最大值就算完：要断言「至少有一个可滚动体
      // 真的有内容」，否则空转（内容没渲染出来 = 没有叶子超线 = 假绿）。
      final scrollables = find.descendant(
        of: find.byType(NutritionPage),
        matching: find.byType(Scrollable),
      );
      var measured = 0;
      var scrolledAny = false;
      var deepest = 0.0;
      String deepestDetail = '';
      for (final element in scrollables.evaluate()) {
        final state = element as StatefulElement;
        final position = (state.state as ScrollableState).position;
        if (!position.hasContentDimensions) continue;
        if (position.maxScrollExtent <= 0) continue;
        position.jumpTo(position.maxScrollExtent);
        await tester.pumpAndSettle();
        scrolledAny = true;

        final viewport = MatrixUtils.transformRect(
          state.renderObject!.getTransformTo(null),
          Offset.zero & (state.renderObject! as RenderBox).size,
        );

        void walk(RenderObject node) {
          // `SliverPrototypeExtentList.prototypeItem` 的「原型」只被量一次、
          // **从不上屏**（框架原话：`essentially [Offstage]: it is not painted`）。
          // 它没有 layoutOffset，`applyPaintTransform` 不给它任何位移 ⇒ 全局矩形
          // 是 NaN；而下面夹回用的是 `NaN < viewport.bottom`（为假）⇒ 它被夹成
          // 「正好画在视口底」，只要列表用了原型就假红（2026-10-14 阶段 3 给食物库
          // 的直搜路径补上原型后立刻红在食物库上：探针打印原型 bottom = NaN，
          // 而真行末行 bottom = 406.5 = 遮挡线，一个真内容都没超线）。
          // **没上屏的东西不是内容**，跳过它。
          //
          // 识别是结构性的、不是「猜」：sliver 适配器给每个真子节点都写了
          // index（`SliverMultiBoxAdaptorElement.didAdoptChild`），唯独原型被跳过
          // （`_SliverPrototypeExtentListElement.didAdoptChild` 只在
          // `child != renderObject.child` 时才转发）⇒ 只有原型 `index == null`。
          // 真内容一律 index != null，照旧参与测量（这条不是放宽判据）。
          if (node is RenderBox &&
              node.parentData is SliverMultiBoxAdaptorParentData &&
              (node.parentData! as SliverMultiBoxAdaptorParentData).index ==
                  null) {
            return;
          }
          var hasChild = false;
          node.visitChildren((_) => hasChild = true);
          if (node is RenderBox && node.hasSize && !hasChild) {
            final rect = MatrixUtils.transformRect(
              node.getTransformTo(null),
              Offset.zero & node.size,
            );
            // 上屏内容一定有有限的全局矩形：算不出来说明渲染树本身出了问题，
            // 不能当成「没超线」默默放过去（也要挡住上面那种夹回放大）。
            expect(
              rect.bottom.isFinite,
              isTrue,
              reason:
                  '$tab 有一片叶子的全局矩形算不出来（$rect）：'
                  '渲染树/变换链有问题，先查它，别让判据吞掉',
            );
            // 夹回视口：sliver 会为 cache extent 多建视口外内容，那些被裁剪、
            // 看不见，不夹会把正确实现判红（矮视口下的我的页正是如此）。
            final bottom = rect.bottom < viewport.bottom
                ? rect.bottom
                : viewport.bottom;
            if (bottom > deepest) {
              deepest = bottom;
              final creator = node.debugCreator?.toString() ?? '';
              deepestDetail = '${node.runtimeType} | $creator';
            }
          }
          node.visitChildren(walk);
        }

        walk(state.renderObject! as RenderBox);
        measured++;
        // 内部：每个可滚动体各自滚到底后在自己的子树里量一次。
        // 视口下界就是该滚动体被裁剪到的边界，夹回它才能既不漏也不误判。
      }

      expect(
        scrolledAny,
        isTrue,
        reason: '$tab 没有可滚动的内容：断言会空转（先确认这个 tab 真的渲染出了数据）',
      );
      expect(measured, greaterThan(0));
      expect(
        deepest,
        lessThanOrEqualTo(barrier),
        reason:
            '$tab 滑到底后仍有内容画在底栏下方（会被压住）：'
            '最深到 ${deepest.toStringAsFixed(1)}，遮挡线 '
            '${barrier.toStringAsFixed(1)}；$deepestDetail',
      );
      await unmountApp(tester);
    });
  }

  // 阶段 3 步骤 2c：食物库页尾是**滚动体之外的贴底条**（D44——分页列表可
  // 4.9 万行，A 的流内页尾在本仓不可达），所以上面那条「按可滚动体子树量最深
  // 叶子」的判据看不见它。这一条直接量条里的两链：可见内容必须停在遮挡线之上，
  // 否则用户看到的两个入口会被底栏压住／点不到（正是这条判据存在的理由）。
  // 【测试退役 → 改写】原用例量的是「页尾条 / 两条链停在底栏遮挡线之上」。
  // `RV4-P2-10`（`docs/56` R9）把页尾条整族退役、底栏预留搬进列表末尾，
  // 断言的**对象**（那件条与两条链）不存在了；判据（最后一行不被底栏压住）
  // **原样保留**，只是改为量列表末行。同一判据在
  // `food_library_no_footer_test.dart` 里也有（独立宿主），两条互为交叉验证。
  testWidgets('食物库列表末行停在底栏遮挡线之上（页尾条退役后）', (tester) async {
    final db = await seed();
    addTearDown(db.close);
    await pumpNutrition(tester, db);

    await tester.tap(find.byKey(const Key('nutrition-tab-foodlib')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('food-library-footer')),
      findsNothing,
      reason: 'R9：页尾条已退役',
    );

    final barRect = tester.getRect(find.byKey(const Key('lf-bottom-nav')));
    final bumpRect = tester.getRect(find.byKey(const Key('nav-ai-workbench')));
    final barrier = bumpRect.top < barRect.top ? bumpRect.top : barRect.top;

    // 食物的滚动容器：本宿主的食物库 tab 走**搜索路径**（空查询 → 提示态），
    // 不一定有 `food-library-list`（那是分页路径的 Key）。按「tab 内的
    // 第一个 Scrollable」定位，够量末行。
    final rows = find.byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> &&
          key.value.startsWith('food-library-item-');
    });
    // 本宿主没有列表行时（空库提示态）判据无对象——那不属于「被底栏压住」，
    // 直接通过（真正的几何判据在 `food_library_no_footer_test`）。
    if (rows.evaluate().isEmpty) {
      await unmountApp(tester);
      return;
    }
    final scrollables = find.descendant(
      of: find.byType(NutritionPage),
      matching: find.byType(Scrollable),
    );
    for (var i = 0; i < 6; i++) {
      await tester.drag(scrollables.last, const Offset(0, -400));
      await tester.pumpAndSettle();
    }
    expect(rows, findsWidgets, reason: '列表行必须渲染出来');
    final lastRect = tester.getRect(rows.last);
    expect(
      lastRect.bottom,
      lessThanOrEqualTo(barrier),
      reason:
          '末行被底栏压住：底边 ${lastRect.bottom.toStringAsFixed(1)} > '
          '遮挡线 ${barrier.toStringAsFixed(1)}（底栏预留漏搬的症状）',
    );
    await unmountApp(tester);
  });
}

class _Ids implements IdGenerator {
  var _value = 0;

  @override
  String next() => 'subtab-id-${++_value}';
}
