import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_router.dart';
import 'package:localfit_ai/app/design/widgets/design_card.dart';
import 'package:localfit_ai/app/localfit_app.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart';
import 'package:localfit_ai/features/nutrition/data/dish_library_repository.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/nutrition/presentation/canteen_directory_page.dart';
import 'package:localfit_ai/features/training/data/exercise_repository.dart';
import 'package:localfit_ai/features/training/data/exercise_seed_importer.dart';
import 'package:localfit_ai/features/training/data/workout_plan_repository.dart';
import 'package:localfit_ai/features/training/data/workout_session_repository.dart';
import 'package:localfit_ai/features/training/presentation/exercise_library_page.dart';

/// **被推入的二级页**的底部遮挡（docs/21 §5.8.4）。
///
/// 2026-10-03 按钮/卡片统一化走查（0-7）在 API 35、360×780dp 上实测：
///
/// | 页 | 最深内容 | 栏体顶边 | 结果 |
/// |---|---|---|---|
/// | 食堂目录（空态） | 添加地点 y=2268（`SliverFillRemaining` ⇒ 无可滚余量） | 2000 | **被压住且永远滚不上来、两次点按都落到栏体/FAB 上** |
/// | 动作库（滚到底） | 最后一格 2254~2340 | 2000 | **整格被吃掉** |
///
/// 两页都由分支页 `Navigator.push` 推入，却仍挂在 shell 的 Navigator 上 ⇒
/// `extendBody: true` 的贴底栏浮在它们之上。`lf_insets.dart` 里「被推入的
/// 二级页不要用 navReserve，底部由 SafeArea 处理」只对**根导航器**上的全屏页
/// （如拍照识餐，实拍无底栏）成立，对这两页不成立——所以按几何判、按可达判。
///
/// 断言的是**用户看到的真相**：滑到底之后目标有没有压在遮挡线之下、以及那个
/// 按钮点不点得开。不按「有没有写那行 padding」判（换写法会假红/假绿）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestWidgetsFlutterBinding
      .instance
      .platformDispatcher
      .accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
    disableAnimations: true,
  );

  late AppDatabase database;
  final now = DateTime(2026, 10, 3, 12);

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
  });
  tearDown(() => database.close());

  Future<void> pumpApp(WidgetTester tester, String initialLocation) async {
    final ids = _Ids();
    final clock = FixedAppClock(now.toUtc());
    await tester.pumpWidget(
      LocalFitApp(
        initialLocation: initialLocation,
        // 饮食页与训练页在缺仓储时都会退化成 `PlaceholderFeaturePage`
        // （没有胶囊行、没有二级入口）——那测不到任何几何，所以按生产接线。
        foodRepository: FoodRepository(
          database: database,
          idGenerator: ids,
          clock: clock,
        ),
        mealRepository: MealRepository(
          database: database,
          idGenerator: ids,
          clock: clock,
        ),
        canteenRepository: CanteenRepository(
          database: database,
          idGenerator: ids,
          clock: clock,
        ),
        dishLibraryRepository: DishLibraryRepository(
          database: database,
          idGenerator: ids,
          clock: clock,
        ),
        exerciseRepository: ExerciseRepository(
          database: database,
          idGenerator: ids,
          clock: clock,
        ),
        workoutPlanRepository: WorkoutPlanRepository(
          database: database,
          idGenerator: ids,
          clock: clock,
        ),
        workoutSessionRepository: WorkoutSessionRepository(
          database: database,
          idGenerator: ids,
          clock: clock,
        ),
        now: now,
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 滚到某个入口出现为止，再点它。
  ///
  /// **不能只 `ensureVisible`**：`ListView` 是懒构建的，屏幕外的子项根本不在
  /// 树上，`ensureVisible` 找不到它。页面的高度只要动一点（例如 2026-10-08
  /// 训练页顶部卡白卡化后高了约 20dp），最下面那两个二级入口就会滑出
  /// `cacheExtent`，测试便以「入口不存在」这种**误导性的失败原因**变红——
  /// 而它真正想测的是二级页里网格的遮挡几何。滚到它出现才是「这个入口可达」
  /// 的准确表述。
  Future<void> tapKey(WidgetTester tester, String key) async {
    final finder = find.byKey(Key(key));
    for (var i = 0; i < 20 && finder.evaluate().isEmpty; i++) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -200));
      await tester.pumpAndSettle();
    }
    expect(finder, findsOneWidget, reason: '入口控件 $key 不存在');
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> unmountApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  /// 遮挡线 = 栏体顶边与中央凸起圆顶边的**更高者**：凸起圆会先挡到内容。
  double barrier(WidgetTester tester) {
    final bar = tester.getRect(find.byKey(const Key('lf-bottom-nav'))).top;
    final bump = tester.getRect(find.byKey(const Key('nav-ai-workbench'))).top;
    return bump < bar ? bump : bar;
  }

  /// 把某个滚动体滑到底（用户找底部内容时做的就是这件事）。
  Future<void> scrollToEnd(WidgetTester tester, Finder scrollable) async {
    final state = tester.state<ScrollableState>(scrollable);
    expect(state.position.hasContentDimensions, isTrue, reason: '滚动体还没量出内容尺寸');
    state.position.jumpTo(state.position.maxScrollExtent);
    await tester.pumpAndSettle();
  }

  testWidgets('食堂目录空态：滑到底的「添加地点」在遮挡线之上，并且点得开表单', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpApp(tester, AppRoutes.nutrition);
    await tapKey(tester, 'nutrition-tab-menu');
    await tapKey(tester, 'cta-manage-canteen');

    final cta = find.byKey(const Key('canteen-add-venue'));
    expect(cta, findsOneWidget, reason: '目录为空时必须有「添加地点」入口');

    await scrollToEnd(
      tester,
      find
          .descendant(
            of: find.byType(CanteenDirectoryPage),
            matching: find.byType(Scrollable),
          )
          .first,
    );

    final line = barrier(tester);
    final rect = tester.getRect(cta);
    expect(
      rect.bottom,
      lessThanOrEqualTo(line + 0.5),
      reason:
          '滑到底后「添加地点」仍画在底栏之下（会被压住）：'
          '底边 ${rect.bottom.toStringAsFixed(1)}，遮挡线 ${line.toStringAsFixed(1)}',
    );

    // 几何判完还要判「真按得到」：不 ensureVisible，就按它现在的位置。
    // 被栏体压住时这一下会落到栏体上，表单不会出现。
    await tester.tap(cta);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('canteen-venue-name')),
      findsOneWidget,
      reason: '按到了「添加地点」就该弹出添加地点的表单',
    );

    await unmountApp(tester);
  });

  testWidgets('动作库：滑到底最后一格动作不被底栏压住', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // 随包动作库 312 条：网格一定比视口高，滑到底才有最后一格可量。
    //
    // 导入必须包在 `runAsync` 里：`testWidgets` 的测试体跑在 fake-async 区，而
    // `ExerciseSeedImporter` 把「清理旧坏行 + 按 id 覆盖写」放进了一个
    // `database.transaction(...)`（docs/28 §7.3.3 要求两者同一次事务），drift
    // 的事务要真事件循环 ⇒ 直接在测试体里 await 永远不返回。2026-10-04 实测：
    // 整条测试卡到 10 分钟超时，而且连 `print` 都停在导入之前（看着像「滚动
    // 变慢」，其实是导入根本没回来）。
    await tester.runAsync(
      () => const ExerciseSeedImporter().importIfNeeded(database),
    );
    await pumpApp(tester, AppRoutes.training);
    await tapKey(tester, 'training-exercise-library');

    final grid = find.descendant(
      of: find.byType(ExerciseLibraryPage),
      matching: find.byType(GridView),
    );
    expect(grid, findsOneWidget);
    await scrollToEnd(
      tester,
      find.descendant(of: grid, matching: find.byType(Scrollable)).first,
    );

    final cards = find.descendant(of: grid, matching: find.byType(DesignCard));
    expect(cards, findsWidgets, reason: '网格里得真有动作卡，否则断言空转');
    final last = tester.getRect(cards.last);
    final line = barrier(tester);
    expect(
      last.bottom,
      lessThanOrEqualTo(line + 0.5),
      reason:
          '滑到底后最后一格动作仍画在底栏之下（会被压住、点不到）：'
          '底边 ${last.bottom.toStringAsFixed(1)}，遮挡线 ${line.toStringAsFixed(1)}',
    );

    await unmountApp(tester);
  });
}

class _Ids implements IdGenerator {
  var _value = 0;

  @override
  String next() => 'occlusion-id-${++_value}';
}
