import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_router.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/app/design/widgets/lf_food_kcal_ring.dart';
import 'package:localfit_ai/app/localfit_app.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart';
import 'package:localfit_ai/features/nutrition/application/food_library_controller.dart';
import 'package:localfit_ai/features/nutrition/data/catalog_search_service.dart';
import 'package:localfit_ai/features/nutrition/data/dish_library_repository.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/nutrition/presentation/food_category_icon.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/food_card.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/food_list_states.dart';

import 'support/food_fixture.dart';
import 'support/round7_render.dart';

/// Round7 阶段 3 步骤 2b **食物库列表渲染矩阵**（真装配 + 真数据）。
///
/// 3-2b 把食物库改成 A `app.js:195` 的 `.card.food-list` 单卡列表（D36/D37/D38）：
/// 一层卡面包住整列、行间 1px `--track` 分隔线（末行不画）、行内 40dp 分类方框
/// （`--bg` 底、R12）+ 名称 + 36dp 密度环、行高 56。改完「长什么样」此前没有
/// 任何渲染帧，本文件补上：**2 主题 × 3 字号 × 4 宽度 = 24 帧整页**，
/// 外加 4 帧**孤立骨架**（加载态是另一个屏面，只有在孤立宿主里才拍得稳）。
///
/// 与 `round7_menu_capture_test.dart` 同一套口径：`LF_ROUND7_CAPTURE_DIR` 指向
/// 工作区 tmp 时才落盘；未设置时仍会跑完并断言——所以它同时是「食物库在四档
/// 宽度、三档字号下不溢出、且 A 的骨架件真的在」的回归面。
///
/// 走**分页浏览**那条路径（`FoodLibraryController`）：它是装机后的默认路径
/// （`main.dart` 里配了目录 controller），也是唯一不靠查询词就能出列表的路径。
/// 数据：6 条夹具行（真种子原样）+ 18 条按同一张表结构插的行，热量跨 2–600
/// kcal/100g（黑咖啡到花生酱），好让密度环在帧里真的分档。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 9, 17, 12);

  late AppDatabase database;
  late FoodLibraryController libraryController;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await seedFoodFixture(database);
    await _seedLibraryRows(database);
    libraryController = FoodLibraryController(
      repository: FoodRepository(
        database: database,
        idGenerator: const UuidV7Generator(),
        clock: FixedAppClock(now),
      ),
      catalogSearch: CatalogSearchService(shardPaths: const []),
    );
  });

  tearDown(() async {
    await database.close();
  });

  Widget app({Key? key}) => LocalFitApp(
    key: key,
    initialLocation: AppRoutes.nutrition,
    foodRepository: FoodRepository(
      database: database,
      idGenerator: const UuidV7Generator(),
      clock: FixedAppClock(now),
    ),
    mealRepository: MealRepository(
      database: database,
      idGenerator: const UuidV7Generator(),
      clock: FixedAppClock(now),
    ),
    dishLibraryRepository: DishLibraryRepository(
      database: database,
      idGenerator: const UuidV7Generator(),
      clock: FixedAppClock(now),
    ),
    canteenRepository: CanteenRepository(
      database: database,
      idGenerator: const UuidV7Generator(),
      clock: FixedAppClock(now),
    ),
    foodLibraryController: libraryController,
    now: now,
  );

  testWidgets('食物库整页矩阵（2 主题 × 3 字号 × 4 宽度）', (tester) async {
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
          final frame =
              'foodlib-${dark ? 'dark' : 'light'}-'
              '${width.toInt()}-$scale';
          tester.view.devicePixelRatio = 1;
          var height = 2600 * scale;
          tester.view.physicalSize = Size(width, height);
          tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
          tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          tester.platformDispatcher.platformBrightnessTestValue = dark
              ? Brightness.dark
              : Brightness.light;
          // `UniqueKey` 强制每帧一个新 State（`LocalFitApp._router` 是
          // `late final`，复用同一棵树会继续渲染上一帧的页面）。
          await tester.pumpWidget(
            RepaintBoundary(
              key: round7Boundary,
              child: app(key: UniqueKey()),
            ),
          );
          await tester.pumpAndSettle();
          // 食物库不是默认 tab：先切过去。
          await tester.tap(find.byKey(const Key('nutrition-tab-foodlib')));
          await tester.pumpAndSettle();

          var missing = scrollRemainder();
          if (missing > 1) {
            height += missing;
            tester.view.physicalSize = Size(width, height);
            await tester.pumpAndSettle();
            missing = scrollRemainder();
          }

          // 帧必须真的是**食物库的列表**：装了帧却渲染了别的 tab、或列表整块
          // 没画出来时，帧名会是唯一且不可信的说法。
          expect(
            find.byKey(const Key('nutrition-subtab-bar')),
            findsOneWidget,
            reason: '$frame 缺 sub-tab 胶囊行',
          );
          expect(
            find.byKey(const Key('food-library-search')),
            findsOneWidget,
            reason: '$frame 缺搜索框（不是食物库 tab？）',
          );
          expect(
            find.byType(FoodDensityScaleNote),
            findsOneWidget,
            reason: '$frame 缺满刻度说明行',
          );

          // ① 单卡列表：列表里只有一层卡面，行不再是各自的卡。
          final list = find.byKey(const Key('food-library-list'));
          expect(list, findsOneWidget, reason: '$frame 没有列表锚点');
          expect(
            find.descendant(of: list, matching: find.byType(DecoratedSliver)),
            findsOneWidget,
            reason: '$frame 列表该有且只有一层卡面（A `.card.food-list`）',
          );

          // ② 行与分隔线：整列都建出来了（视口够高），所以「分隔线数 = 行数 − 1」
          // 是这一帧的自洽不变量（末行不画线、中间一根不少）。
          final rows = find.descendant(
            of: list,
            matching: find.byType(FoodCard),
          );
          final rowCount = rows.evaluate().length;
          expect(
            rowCount,
            _seededRowCount,
            reason: '$frame 只画了 $rowCount 行（夹具 $_seededRowCount 行该全部建出来）',
          );
          final dividers = find
              .byWidgetPredicate(
                (widget) =>
                    widget.key is ValueKey<String> &&
                    (widget.key! as ValueKey<String>).value.startsWith(
                      'food-library-row-divider-',
                    ),
              )
              .evaluate()
              .length;
          expect(
            dividers,
            rowCount - 1,
            reason: '$frame 分隔线 $dividers 根，应为 ${rowCount - 1} 根（末行不画线）',
          );

          // ③ 行几何：所有行等高（原型量高的列表），1.0 档就是 A 的 56。
          final first = tester.getRect(rows.at(0));
          for (var i = 1; i < rowCount; i++) {
            expect(
              tester.getRect(rows.at(i)).height,
              closeTo(first.height, 0.5),
              reason: '$frame 第 $i 行与第 0 行不等高（行高该由原型统一）',
            );
            expect(
              tester.getRect(rows.at(i)).top -
                  tester.getRect(rows.at(i - 1)).top,
              closeTo(first.height, 0.5),
              reason: '$frame 第 $i 行的行距与行高不一致',
            );
          }
          if (scale == 1.0) {
            expect(
              first.height,
              closeTo(56, 0.5),
              reason: '$frame 行高应为 A `.food-row` 的 56（40 图标 + 上下 8）',
            );
          }

          // ④ 每行有且只有一枚 40dp 分类方框（A `.food-symbol`）。
          for (var i = 0; i < rowCount; i++) {
            final icon = find.descendant(
              of: rows.at(i),
              matching: find.byType(FoodCategoryIcon),
            );
            expect(icon, findsOneWidget, reason: '$frame 第 $i 行缺分类图标');
            expect(
              tester.getSize(icon),
              const Size(40, 40),
              reason: '$frame 第 $i 行的分类方框不是 40×40',
            );
          }

          expect(tester.takeException(), isNull, reason: frame);
          await captureRound7(tester, frame);
        }
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  /// 加载态（骨架）在整页里只闪一两帧，拍不稳；这里在**孤立宿主**里拍，
  /// 帧名与整页帧分开（`foodlib-skeleton-*`），证据里也照此说明。
  testWidgets('食物库加载态骨架（孤立宿主 4 帧）', (tester) async {
    await tester.runAsync(loadRound7Fonts);
    for (final (dark, scale, width) in const [
      (false, 1.0, 360.0),
      (true, 1.0, 360.0),
      (false, 2.0, 320.0),
      (true, 1.5, 430.0),
    ]) {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 900);
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
      tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
      await tester.pumpWidget(
        RepaintBoundary(
          key: round7Boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: round7CaptureTheme(
              dark ? AppTheme.dark() : AppTheme.light(),
            ),
            // `disableAnimations: true` 不是「关掉动画好拍照」：`SkeletonBox`
            // 见它就把呼吸停在中点色（`Color.lerp(base, highlight, .5)`）——
            // 静帧因此取到的是一个**确定的**骨架色，而不是某个随机相位的淡出。
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(scale),
                disableAnimations: true,
              ),
              child: child!,
            ),
            home: const Scaffold(body: FoodListSkeleton()),
          ),
        ),
      );
      // `MaterialApp` 的 `AnimatedTheme` 会把上一帧的主题 lerp 到新主题
      // （200ms）：只 pump 一帧拍出来的是**上一帧的亮色**（第二帧因此白底 —
      // 2026-10-14 第一版就这么错了一次）。多走 400ms 让主题落到终值。
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
      await captureRound7(
        tester,
        'foodlib-skeleton-${dark ? 'dark' : 'light'}-'
        '${width.toInt()}-$scale',
      );
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

/// 夹具：6 条种子行 + 13 条同表结构行（合计 [_seededRowCount] 行，名字两两不同）。
///
/// 名称与四指标都是常见食物的真实量级（照《中国食物成分表》的上百克值抄），
/// 不是随机数：密度环要按真实比例分档 —— 黑咖啡 2 kcal 到花生酱 600 kcal。
/// `source='seed-v5'`、`isUserCreated=false`：与内置行同语义（可搜、不可改删）。
const int _seededRowCount = 19;

Future<void> _seedLibraryRows(AppDatabase db) async {
  const rows = [
    ('咖啡（黑）', 2.0, 0.2, 0.3, 0.0),
    ('西兰花', 36.0, 4.1, 4.3, 0.6),
    ('白粥', 46.0, 1.1, 9.9, 0.2),
    ('酸奶', 72.0, 2.5, 9.3, 2.7),
    ('香蕉', 93.0, 1.4, 22.0, 0.2),
    ('三文鱼', 139.0, 17.2, 0.0, 7.8),
    ('猪里脊', 155.0, 20.2, 0.7, 7.9),
    ('全麦面包', 246.0, 8.8, 41.0, 3.5),
    ('挂面（干）', 350.0, 11.0, 71.5, 1.6),
    ('燕麦片', 377.0, 15.0, 61.6, 8.1),
    ('薯片', 536.0, 6.0, 49.2, 34.2),
    ('巧克力', 589.0, 4.3, 53.4, 40.1),
    ('花生酱', 600.0, 25.0, 18.6, 50.4),
  ];
  for (final (index, row) in rows.indexed) {
    final (name, kcal, protein, carbs, fat) = row;
    await db
        .into(db.foods)
        .insert(
          FoodsCompanion.insert(
            // 与夹具行同一 id 空间（`seed-fc-*`），且避开夹具那六条的 id。
            id: 'seed-fc-lib-$index',
            name: name,
            kcalPer100g: kcal,
            proteinPer100g: protein,
            carbsPer100g: carbs,
            fatPer100g: fat,
            source: 'seed-v5',
            isUserCreated: const Value(false),
            createdAt: now(),
            updatedAt: now(),
          ),
        );
  }
}

DateTime now() => DateTime.utc(2026, 9, 17);
