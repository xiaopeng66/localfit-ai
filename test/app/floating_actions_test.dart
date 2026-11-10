import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_router.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/lf_float_actions.dart';
import 'package:localfit_ai/app/localfit_app.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart';
import 'package:localfit_ai/features/nutrition/data/dish_library_repository.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/training/data/exercise_repository.dart';
import 'package:localfit_ai/features/training/data/exercise_seed_importer.dart';
import 'package:localfit_ai/features/training/data/workout_plan_repository.dart';
import 'package:localfit_ai/features/training/data/workout_session_repository.dart';

import '../support/food_fixture.dart';

/// 13a / 13b + 2026-11-02 用户改版：**右下浮动按钮**。
///
/// * 13a：菜单页「管理食堂目录」在右下浮动按钮上（Key `cta-manage-canteen`
///   沿用）。2026-11-02 用户点名去掉文字，改成**纯图标圆钮**。
/// * 13b：训练页常驻 ➕；训练统计 / 训练达标 / 动作库 收进它上方的
///   「上拉三角」，点开才展开，点页面空白处收回。➕ 复用记录页 `RecordFab`。
///
/// 【harness 说明】用 `LocalFitApp` 走真装配（与
/// `secondary_page_occlusion_test` 同一套）：壳/底栏/分支导航器都在场，
/// 量出来的坐标才是用户看到的坐标。`disableAnimations` 必须在建 app 之前设：
/// 菜品库加载态有无限骨架动画，开着它 `pumpAndSettle` 永远等不到静止
/// （第一版没设，实测挂到 10 分钟超时）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestWidgetsFlutterBinding
      .instance
      .platformDispatcher
      .accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
    disableAnimations: true,
  );

  late AppDatabase database;
  final now = DateTime(2026, 10, 25, 12);

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await seedFoodFixture(database);
  });

  tearDown(() => database.close());

  Future<void> pumpApp(WidgetTester tester, String initialLocation) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final ids = _Ids();
    final clock = FixedAppClock(now.toUtc());
    await tester.pumpWidget(
      LocalFitApp(
        initialLocation: initialLocation,
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

  Future<void> pumpMenu(WidgetTester tester) async {
    await pumpApp(tester, AppRoutes.nutrition);
    await tester.tap(find.byKey(const Key('nutrition-tab-menu')));
    await tester.pumpAndSettle();
  }

  Future<void> pumpTraining(WidgetTester tester) async {
    await tester.runAsync(
      () => const ExerciseSeedImporter().importIfNeeded(database),
    );
    await pumpApp(tester, AppRoutes.training);
  }

  /// 展开上拉三角（统计/达标/动作库只在展开态存在）。
  Future<void> expandTrainingActions(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('training-actions-toggle')));
    await tester.pumpAndSettle();
  }

  /// 卸掉整棵树：真装配下壳里有零延时计时器（日切/任务调度），不卸就报
  /// 「A Timer is still pending even after the widget tree was disposed」——
  /// 与 `secondary_page_occlusion_test` 的 `unmountApp` 同一手法。
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  /// 「在右下方」的量化判据：右缘距屏右 ≤ 80dp、底边在下半屏。
  void expectBottomRight(WidgetTester tester, Key key) {
    final rect = tester.getRect(find.byKey(key));
    final screen = tester.getSize(find.byType(Scaffold).first);
    expect(
      screen.width - rect.right,
      lessThanOrEqualTo(80.0),
      reason: '$key 不在右侧（离右缘 ${screen.width - rect.right}dp）',
    );
    expect(
      rect.bottom,
      greaterThan(screen.height * 0.5),
      reason: '$key 不在下半屏（bottom=${rect.bottom} / 屏高 ${screen.height}）',
    );
  }

  testWidgets('13a：菜单页右下是纯图标圆钮，页尾不再有那一行', (tester) async {
    await pumpMenu(tester);
    final fab = find.byKey(const Key('cta-manage-canteen'));
    expect(fab, findsOneWidget, reason: '入口不能丢：Key 沿用到浮动按钮上');
    expectBottomRight(tester, const Key('cta-manage-canteen'));
    // 2026-11-02 用户：「删除文字只留图标」。
    expect(
      find.text('管理食堂目录'),
      findsNothing,
      reason: '可见文字已按用户要求删除（tooltip / 读屏标签仍在）',
    );
    expect(
      find.descendant(
        of: fab,
        matching: find.byIcon(Icons.storefront_outlined),
      ),
      findsOneWidget,
      reason: '纯图标档必须留下能看出「食堂」的图标',
    );
    final material = tester.widget<Material>(fab);
    expect(material.shape, isA<CircleBorder>(), reason: '圆钮，不是带字胶囊');
    expect(
      (material.shape! as CircleBorder).side,
      BorderSide.none,
      reason: '浅品牌底圆钮不叠描边（白边来源）',
    );
    expect(
      find.text('地点、窗口与菜品'),
      findsNothing,
      reason: '页尾那行两行文字的入口已退役（挪到浮动按钮）',
    );
    await unmount(tester);
  });

  testWidgets('13a：浮动按钮真的能打开食堂目录（点了有反应）', (tester) async {
    await pumpMenu(tester);
    await tester.tap(find.byKey(const Key('cta-manage-canteen')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('canteen-add-venue')),
      findsOneWidget,
      reason: '点开应进食堂目录页（空态给「添加地点」）',
    );
    await unmount(tester);
  });

  testWidgets('13b：平时只露➕和上拉三角；展开后统计/达标/动作库在同一列', (tester) async {
    await pumpTraining(tester);
    final toggle = find.byKey(const Key('training-actions-toggle'));
    final add = find.byKey(const Key('cta-new-plan'));
    expect(add, findsOneWidget, reason: '➕ 常驻');
    expect(toggle, findsOneWidget, reason: '上拉三角是展开入口');
    for (final key in const [
      'training-stats',
      'training-target-progress',
      'training-exercise-library',
    ]) {
      expect(
        find.byKey(Key(key)),
        findsNothing,
        reason: '$key 平时必须收起来（用户：平时不显示）',
      );
    }

    await expandTrainingActions(tester);
    final stats = find.byKey(const Key('training-stats'));
    final target = find.byKey(const Key('training-target-progress'));
    final library = find.byKey(const Key('training-exercise-library'));
    for (final (name, finder) in [
      ('统计', stats),
      ('达标', target),
      ('动作库', library),
    ]) {
      expect(finder, findsOneWidget, reason: '$name 入口必须在展开列里');
    }

    final rects = [
      tester.getRect(stats),
      tester.getRect(target),
      tester.getRect(library),
    ];
    // 统计在用户点名的「三个按钮上边」：从上到下依次是 统计 → 达标 → 动作库。
    expect(rects[0].top, lessThan(rects[1].top), reason: '统计在达标之上');
    expect(rects[1].top, lessThan(rects[2].top), reason: '达标在动作库之上');
    for (var i = 1; i < rects.length; i++) {
      expect(
        (rects[i].right - rects[0].right).abs(),
        lessThanOrEqualTo(1.0),
        reason: '三枚次级必须同一列（右缘对齐）',
      );
    }
    final toggleRect = tester.getRect(toggle);
    final addRect = tester.getRect(add);
    expect(toggleRect.top, greaterThan(rects[2].bottom), reason: '三角在动作库之下');
    expect(addRect.top, greaterThan(toggleRect.bottom), reason: '➕ 在最下面');
    // 【2026-11-03 用户】三角圆的大小、水平位置都要和加号一致。
    expect(
      toggleRect.width,
      closeTo(addRect.width, 0.5),
      reason: '三角圆直径必须与加号相同（${toggleRect.width} vs ${addRect.width}）',
    );
    expect(
      toggleRect.center.dx,
      closeTo(addRect.center.dx, 0.5),
      reason:
          '三角圆与加号必须同一竖线（中心 ${toggleRect.center.dx} vs ${addRect.center.dx}）',
    );
    final brightness = Theme.of(tester.element(add)).brightness;
    expect(
      tester.widget<Material>(toggle).color,
      LfColors.brandStrong(brightness),
      reason: '三角也要用加号的深绿底（用户 2026-11-03 指定）',
    );
    // 都在右下（不遮住内容，也不掉进底栏）。
    for (final key in const [
      'training-stats',
      'training-target-progress',
      'training-exercise-library',
      'training-actions-toggle',
      'cta-new-plan',
    ]) {
      expectBottomRight(tester, Key(key));
    }
    await unmount(tester);
  });

  testWidgets('13b：点页面空白处，展开的三枚收回', (tester) async {
    await pumpTraining(tester);
    await expandTrainingActions(tester);
    expect(find.byKey(const Key('training-stats')), findsOneWidget);

    await tester.tap(find.byKey(const Key('training-actions-scrim')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('training-stats')), findsNothing);
    expect(find.byKey(const Key('training-target-progress')), findsNothing);
    expect(find.byKey(const Key('training-exercise-library')), findsNothing);
    expect(find.byKey(const Key('cta-new-plan')), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('13b：训练统计圆钮能打开统计弹层', (tester) async {
    await pumpTraining(tester);
    await expandTrainingActions(tester);
    await tester.tap(find.byKey(const Key('training-stats')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('training-stats-sheet')),
      findsOneWidget,
      reason: '统计圆钮要真的打开统计弹层',
    );
    // 点开动作后三角自动收回：下次看到的是干净的 ➕ + 三角。
    expect(find.byKey(const Key('training-stats')), findsNothing);
    await unmount(tester);
  });

  testWidgets('13b：三枚浮钮都不与底栏重叠（extendBody 的坑）', (tester) async {
    await pumpTraining(tester);
    final bar = tester.getRect(find.byKey(const Key('lf-bottom-nav'))).top;
    final add = tester.getRect(find.byKey(const Key('cta-new-plan')));
    expect(
      add.bottom,
      lessThanOrEqualTo(bar + 0.5),
      reason:
          '最下方那枚浮钮压到底栏上了（底边 ${add.bottom} vs 栏体顶边 $bar）——'
          'shell 是 extendBody，浮钮必须按 LfInsets 抬起来',
    );
    await unmount(tester);
  });

  testWidgets('13b：展开列恰好是统计/达标/动作库三枚，不许多出第四枚', (tester) async {
    await pumpTraining(tester);
    await expandTrainingActions(tester);
    final column = find.byType(LfFloatingActions);
    expect(column, findsOneWidget, reason: '展开后是一列次级浮钮');
    expect(
      find.descendant(of: column, matching: find.byType(InkWell)),
      findsNWidgets(3),
      reason: '用户点名的三枚是 统计/达标/动作库，不许多出第四枚',
    );
    for (final key in const [
      'training-stats',
      'training-target-progress',
      'training-exercise-library',
    ]) {
      expect(
        find.descendant(of: column, matching: find.byKey(Key(key))),
        findsOneWidget,
        reason: '$key 必须在这一列里',
      );
    }
    await unmount(tester);
  });

  testWidgets('13b：列表滚到底后浮钮仍钉在右下（不跟内容滚走）', (tester) async {
    await pumpTraining(tester);
    final scrollable = find.byType(Scrollable).first;
    final state = tester.state<ScrollableState>(scrollable);
    state.position.jumpTo(state.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('cta-new-plan')), findsOneWidget);
    expectBottomRight(tester, const Key('cta-new-plan'));
    await unmount(tester);
  });

  testWidgets('浮钮触达 ≥ 44dp（无障碍下限）', (tester) async {
    await pumpTraining(tester);
    await expandTrainingActions(tester);
    for (final key in const [
      'training-stats',
      'training-target-progress',
      'training-exercise-library',
      'training-actions-toggle',
      'cta-new-plan',
    ]) {
      final rect = tester.getRect(find.byKey(Key(key)));
      expect(
        rect.width,
        greaterThanOrEqualTo(LfDimens.minTouchTarget),
        reason: '$key 宽度不足触达下限',
      );
      expect(rect.height, greaterThanOrEqualTo(LfDimens.minTouchTarget));
    }
    await unmount(tester);
  });

  testWidgets('次级浮钮与加号同深绿底（2026-11-03 用户：整簇统一）', (tester) async {
    await pumpTraining(tester);
    await expandTrainingActions(tester);
    final brightness = Theme.of(
      tester.element(find.byKey(const Key('cta-new-plan'))),
    ).brightness;
    for (final key in const [
      'training-target-progress',
      'training-exercise-library',
    ]) {
      final finder = find.byKey(Key(key));
      final material = tester.widget<Material>(finder);
      expect(
        material.color,
        LfColors.brandStrong(brightness),
        reason: '$key 应与加号同为深绿实心底（用户 2026-11-03 指定）',
      );
      final icon = tester.widget<Icon>(
        find.descendant(of: finder, matching: find.byType(Icon)),
      );
      expect(
        icon.color,
        LfColors.onBrandStrong(brightness),
        reason: '$key 的图标应是深绿底上的反白色（onBrandStrong）',
      );
      // 无描边：圆形本身就是容器。
      expect((material.shape! as CircleBorder).side, BorderSide.none);
      // 【2026-10-31 断言改写（用户：动作库和训练达标没有同样的悬浮效果，
      // 强度不降）】原断言钉「次级无阴影」（2026-10-28 灰晕顾虑）。用户本轮
      // 裁决三档**统一**悬浮效果 ⇒ 次级现在必须带与主行动同一套
      // fabPrimary 彩色阴影，且 DecoratedBox 填与按钮同色（不再有 1dp
      // 透明内衬——那是训练页按钮「白边」的来源）。
      final decorated = tester.widget<DecoratedBox>(
        find.ancestor(of: finder, matching: find.byType(DecoratedBox)).first,
      );
      final deco = decorated.decoration as BoxDecoration;
      expect(deco.boxShadow, isNotEmpty, reason: '$key 次级浮钮要有与主行动一致的悬浮阴影');
      expect(deco.color, material.color, reason: '阴影层与按钮同色（白边修复：1dp 透明内衬已退役）');
    }
    // 主行动不受影响：实心品牌底 + 彩色阴影（唯一允许彩色阴影的那一档）。
    // 【2026-10-29】底从 primary 改为 brandStrong（亮 #187653）——实心面带
    // 文字的档位统一深绿 + 白字，见 `LfColors.brandStrong`。
    final add = tester.widget<Material>(find.byKey(const Key('cta-new-plan')));
    expect(add.color, LfColors.brandStrong(Brightness.light));
    // 【2026-11-02 用户：训练页加号还有白边】训练页现在直接用 RecordFab，
    // 与饮食页同一枚；圆面不带任何描边。
    expect(add.shape, isA<CircleBorder>());
    expect(
      (add.shape! as CircleBorder).side,
      BorderSide.none,
      reason: '加号不能有描边（用户反复点名的白边）',
    );
    await unmount(tester);
  });
}

final class _Ids implements IdGenerator {
  int _value = 0;

  @override
  String next() => 'fa-${_value++}';
}
