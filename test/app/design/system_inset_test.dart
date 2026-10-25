import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_router.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/widgets/design_card.dart';
import 'package:localfit_ai/app/design/widgets/lf_bottom_nav.dart';
import 'package:localfit_ai/app/design/widgets/lf_top_bar.dart';
import 'package:localfit_ai/app/localfit_app.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/nutrition_sub_tab_chips.dart';
import 'package:localfit_ai/features/progress/data/measurement_repository.dart';
import 'package:localfit_ai/features/training/data/exercise_repository.dart';
import 'package:localfit_ai/features/training/data/workout_plan_repository.dart';
import 'package:localfit_ai/features/training/data/workout_session_repository.dart';
import 'package:localfit_ai/features/training/presentation/sections/training_hero.dart';

import '../../support/food_fixture.dart';

/// 系统叠层（状态栏 / 手势条）契约（docs/21 §5.8.5）。
///
/// **2026-10-08（docs/30 §2 D4/D5/D6）后的贴顶情况**：记录 / 菜单 / 训练三处
/// 顶部卡白卡化、我的身份卡白卡化 ⇒ 全 App **只剩「今日页」与二级页顶栏**是
/// 贴顶铺满（前者整块内容随叠层下移，后者 `LfTopBar` 自己吃叠层）。训练页因此
/// 从「色块贴顶」改为「页面给 `pagePadding + LfInsets.top`」，断言同步改写。
///
/// 阶段 J 真机走查实测：状态栏 `frame=[0,0][1080,128]`，而 4 个页面的首个
/// 内容节点落在 `y = 0..53`，被状态栏时钟压住。这条缺陷的**测试空洞原因**
/// 很具体——widget 测试里 `MediaQuery.padding` 默认恒为 0，任何"内容躲开了
/// 状态栏"的断言不注入人造叠层就**恒真**。所以这里一律注入。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 人造状态栏高度（物理像素 == 逻辑像素：本文件全部 case 都把
  /// `devicePixelRatio` 设为 1，避免 px/dp 换算把偏移量算错）。
  const double statusBar = 48;

  /// 人造手势条高度。
  const double gestureInset = 24;

  /// 只在**页面之外**注入顶部叠层，页面内部的 `LfInsets.top` 必须自己去读
  /// `MediaQuery.paddingOf`——这正是被测逻辑。
  ///
  /// 底部叠层**不能**用这个函数注入：`LfInsets.bottom` 读的是视图原始内边距
  /// （shell 的 Scaffold 会把 body 的 `padding.bottom` 与 `viewPadding.bottom`
  /// 一起抹成 0，见该方法的说明），所以那组 case 走 `tester.view.padding`。
  Widget injectTop(Widget child, double top) {
    return Builder(
      builder: (context) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: EdgeInsets.only(top: top),
            viewPadding: EdgeInsets.only(top: top),
          ),
          child: child,
        );
      },
    );
  }

  Widget heroUnderTest({required bool respectTopInset, Key? childKey}) {
    return MaterialApp(
      home: injectTop(
        Scaffold(
          // hero 贴到屏幕顶边（真实调用点的排布方式：无障碍列表置顶）。
          body: Column(
            children: [
              HeroSection(
                key: const Key('probe-hero'),
                respectTopInset: respectTopInset,
                child: Text('标题', key: childKey ?? const Key('probe-child')),
              ),
            ],
          ),
        ),
        statusBar,
      ),
    );
  }

  group('HeroSection.respectTopInset（机制）', () {
    testWidgets('关闭时内容按设计内边距排布，叠层不参与', (tester) async {
      await tester.pumpWidget(heroUnderTest(respectTopInset: false));

      final heroTop = tester.getTopLeft(find.byKey(const Key('probe-hero'))).dy;
      final childTop = tester
          .getTopLeft(find.byKey(const Key('probe-child')))
          .dy;

      expect(heroTop, 0, reason: 'hero 背景必须从屏幕顶边开始');
      expect(
        childTop,
        LfDimens.spaceLargePlus,
        reason: '未开启时内容只吃设计内边距（20dp），不受人造状态栏影响',
      );
    });

    testWidgets('开启时背景仍贴顶边，只有内容下移 padding.top', (tester) async {
      await tester.pumpWidget(heroUnderTest(respectTopInset: true));

      final heroTop = tester.getTopLeft(find.byKey(const Key('probe-hero'))).dy;
      final childTop = tester
          .getTopLeft(find.byKey(const Key('probe-child')))
          .dy;

      // 两项分别断言：渐变没有被打断（§5.8.5 约束 1）与内容确实躲开了。
      expect(heroTop, 0, reason: '渐变必须铺到屏幕物理顶边，不得被安全区推下去');
      expect(
        childTop,
        LfDimens.spaceLargePlus + statusBar,
        reason: '内容应整体下移 padding.top',
      );
    });

    testWidgets('叠层为 0 时开启与关闭等价（桌面 / 无叠层设备）', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: injectTop(
            const Scaffold(
              body: Column(
                children: [
                  HeroSection(
                    respectTopInset: true,
                    child: Text('标题', key: Key('probe-child')),
                  ),
                ],
              ),
            ),
            0,
          ),
        ),
      );

      expect(
        tester.getTopLeft(find.byKey(const Key('probe-child'))).dy,
        LfDimens.spaceLargePlus,
        reason: '无叠层设备上不得凭空多出一段留白',
      );
    });
  });

  group('LfTopBar（二级页顶栏自己吃叠层）', () {
    Finder back() => find.byKey(const Key('top-bar-back'));

    testWidgets('作为 appBar：槽位已含叠层，栏填满槽位，返回键落在状态栏之下', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: injectTop(
            Scaffold(
              appBar: LfTopBar(title: '拍照识餐'),
              body: const SizedBox.expand(),
            ),
            statusBar,
          ),
        ),
      );

      final barBox = tester.getRect(find.byType(LfTopBar));
      expect(
        barBox.height,
        60 + statusBar,
        reason:
            'Scaffold 给的槽位 = 60 + padding.top，栏必须填满它（否则下沿留空、'
            '内容被画进状态栏带）',
      );
      expect(
        tester.getTopLeft(back()).dy,
        greaterThanOrEqualTo(statusBar),
        reason: '返回键不得落在状态栏带内',
      );
    });

    testWidgets('关掉 respectTopInset 时条带回到 60，且必须由外层补叠层', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: injectTop(
            Scaffold(
              body: SafeArea(
                bottom: false,
                child: Column(
                  children: const [
                    LfTopBar(title: '周计划', respectTopInset: false),
                  ],
                ),
              ),
            ),
            statusBar,
          ),
        ),
      );

      expect(
        tester.getRect(find.byType(LfTopBar)).height,
        60,
        reason: '显式关掉时不得再吃叠层（同时也是「标志确实生效」的反向证据）',
      );
      expect(
        tester.getTopLeft(back()).dy,
        greaterThanOrEqualTo(statusBar),
        reason: '关掉标志的正确用法是外层套 SafeArea——这样返回键仍在状态栏之下',
      );
    });
  });

  group('底栏与页面底部预留（extendBody 下的手势带）', () {
    const double barHeight = 64; // LfDimens.navBarHeight

    /// 底栏的叠层走 `LfInsets.bottom` = 视图原始内边距，所以注入必须走
    /// `tester.view.padding`（不是自造 MediaQuery）——这也与真机同构。
    Future<void> pumpNav(
      WidgetTester tester, {
      required double bottomInset,
    }) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);
      tester.view.padding = FakeViewPadding(bottom: bottomInset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: LfBottomNav(currentIndex: 0, onTap: (_) {}),
          ),
        ),
      );
    }

    testWidgets('栏体毛玻璃铺到屏幕底边，槽位内容抬到手势带之上，上凸量不变', (tester) async {
      await pumpNav(tester, bottomInset: gestureInset);

      final screenBottom = tester.getRect(find.byType(Scaffold)).bottom;
      final bar = tester.getRect(find.byKey(const Key('lf-bottom-nav')));

      expect(
        bar.bottom,
        screenBottom,
        reason: '手势带里必须仍是栏体（毛玻璃铺到屏幕物理底边）——否则手势带露出页面内容',
      );
      expect(
        bar.height,
        barHeight + gestureInset,
        reason: '栏高 = 64dp 栏体 + 手势带',
      );
      expect(
        bar.top,
        screenBottom - barHeight - gestureInset,
        reason: '栏体顶边位置由「栏高 + 手势带」共同决定',
      );
      // 槽位内容（图标 + 标签）整块必须在手势带之上，别被系统手势条压住。
      final slot = tester.getRect(find.byKey(const Key('nav-dashboard')));
      expect(
        slot.bottom,
        lessThanOrEqualTo(screenBottom - gestureInset),
        reason: '槽位内容不得落进手势带',
      );
      // 凸起圆的净视觉上凸量与手势带无关（docs/21 §5.8.4 实测 9.5dp）。
      final bump = tester.getRect(find.byKey(const Key('nav-ai-workbench')));
      expect(
        bar.top - bump.top,
        closeTo(LfDimens.navBumpProtrusion, 0.01),
        reason: '加了手势带之后，凸起圆相对栏顶的净上凸量必须仍是 9.5dp',
      );
    });

    testWidgets('无手势带的设备上栏高仍是 64dp（不许凭空多留）', (tester) async {
      await pumpNav(tester, bottomInset: 0);

      expect(
        tester.getRect(find.byKey(const Key('lf-bottom-nav'))).height,
        barHeight,
        reason: '无手势带时不得多出留白',
      );
    });
  });

  group('四个底栏分支页的顶部叠层（真机同构：真 App + 真库 + 注入状态栏）', () {
    late AppDatabase database;
    late FoodRepository foodRepository;
    late MealRepository mealRepository;
    late MeasurementRepository measurementRepository;
    late ExerciseRepository exerciseRepository;
    late WorkoutPlanRepository workoutPlanRepository;
    late WorkoutSessionRepository workoutSessionRepository;
    final now = DateTime(2026, 10, 1, 12);

    setUp(() async {
      database = AppDatabase(NativeDatabase.memory());
      await seedFoodFixture(database);
      final ids = _IncrementingIdGenerator();
      foodRepository = FoodRepository(
        database: database,
        idGenerator: ids,
        clock: FixedAppClock(now.toUtc()),
      );
      mealRepository = MealRepository(
        database: database,
        idGenerator: ids,
        clock: FixedAppClock(now.toUtc()),
      );
      measurementRepository = MeasurementRepository(
        database: database,
        idGenerator: ids,
        clock: FixedAppClock(now.toUtc()),
      );
      // 训练三件套：`TrainingPage` 缺任一训练仓储就退化成 `PlaceholderFeaturePage`
      // （没有 hero），那条页面级叠层断言会以「找不到卡片」空转失败。
      exerciseRepository = ExerciseRepository(
        database: database,
        idGenerator: ids,
        clock: FixedAppClock(now.toUtc()),
      );
      workoutPlanRepository = WorkoutPlanRepository(
        database: database,
        idGenerator: ids,
        clock: FixedAppClock(now.toUtc()),
      );
      workoutSessionRepository = WorkoutSessionRepository(
        database: database,
        idGenerator: ids,
        clock: FixedAppClock(now.toUtc()),
      );
    });

    tearDown(() => database.close());

    Future<void> pumpAt(
      WidgetTester tester,
      String location, {
      required double topInset,
      double bottomInset = 0,
    }) async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewPadding);
      // 两个都要设：`padding` 供 `paddingOf`，`viewPadding` 供 `viewPaddingOf`
      // （真实设备无键盘时两者相等；测试里不设 `viewPadding` 会退化成宿主的 0，
      // 于是底部手势带的断言会静默恒真）。
      final insets = FakeViewPadding(top: topInset, bottom: bottomInset);
      tester.view.padding = insets;
      tester.view.viewPadding = insets;

      await tester.pumpWidget(
        LocalFitApp(
          initialLocation: location,
          foodRepository: foodRepository,
          mealRepository: mealRepository,
          measurementRepository: measurementRepository,
          exerciseRepository: exerciseRepository,
          workoutPlanRepository: workoutPlanRepository,
          workoutSessionRepository: workoutSessionRepository,
          now: now,
        ),
      );
      // **不能用 `pumpAndSettle`**：这些页面在缺依赖时会停在骨架屏 / 脉冲
      // 动画上（重复动画永不 settle，会把测试拖到 10 分钟超时）。改成有界
      // 推进——先让 Stream/Future 回填，再走完入场动画，让节点位置定格。
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(seconds: 2));
    }

    /// 在指定叠层下渲染页面，返回一组探针节点的顶点 y。
    Future<Map<String, double>> topsAt(
      WidgetTester tester,
      String location,
      double inset,
      Map<String, Finder> probes,
    ) async {
      await pumpAt(tester, location, topInset: inset);
      return {
        for (final entry in probes.entries)
          entry.key: tester.getTopLeft(entry.value).dy,
      };
    }

    /// 两次测量之间必须把上一棵树换掉：`pumpWidget` 同类型 widget 会走
    /// 复用路径，页面内的一次性状态（如 tab 选择）会串味。
    Future<void> disposeApp(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    }

    /// 非贴顶页面：整块内容随叠层下移，位移 = 叠层高度。
    Future<void> expectContentShifted(
      WidgetTester tester,
      String location,
      Map<String, Finder> probes, {
      required String label,
    }) async {
      final plain = await topsAt(tester, location, 0, probes);
      await disposeApp(tester);
      final shifted = await topsAt(tester, location, statusBar, probes);
      for (final name in probes.keys) {
        expect(
          shifted[name]! - plain[name]!,
          statusBar,
          reason: '$label 的 $name 必须随系统叠层整体下移，不多不少',
        );
      }
      await disposeApp(tester);
    }

    /// 饮食页：**胶囊行**（页级唯一实例）贴屏幕物理顶边，行内一切与其下的
    /// 页首卡整体随叠层下移。
    ///
    /// 2026-10-03 起胶囊行由页壳统一画在全部 sub-tab 内容之上（用户要求五个
    /// 界面位置一致），「贴顶铺满」的责任由页首卡转到这一行：页首卡不再是页面
    /// 第一个元素，也不再自己避让叠层（`respectTopInset: false`）。
    ///
    /// 记录页的页首卡在阶段 2B D10 从 hero 换成共享热量卡
    /// （`nutrition-record-energy`，标题「今日营养」），探针名与判据不变。
    Future<void> expectStickySubTabChips(
      WidgetTester tester, {
      required String headerKey,
      required String headerTitle,
      Future<void> Function()? switchToTab,
    }) async {
      Future<Map<String, double>> measure(double inset) async {
        await pumpAt(tester, AppRoutes.nutrition, topInset: inset);
        if (switchToTab != null) await switchToTab();
        return {
          '胶囊行': tester.getTopLeft(find.byKey(NutritionSubTabChips.barKey)).dy,
          '胶囊内容': tester
              .getTopLeft(find.byKey(const Key('nutrition-tab-record')))
              .dy,
          '页首件': tester.getTopLeft(find.byKey(Key(headerKey))).dy,
          '页首件标题': tester.getTopLeft(find.text(headerTitle).first).dy,
        };
      }

      final plain = await measure(0);
      await disposeApp(tester);
      final shifted = await measure(statusBar);
      expect(plain['胶囊行'], 0, reason: '$headerTitle：胶囊行底色必须从屏幕顶边开始');
      expect(shifted['胶囊行'], 0, reason: '$headerTitle：胶囊行底色不得被安全区推下去');
      for (final name in ['胶囊内容', '页首件', '页首件标题']) {
        expect(
          shifted[name]! - plain[name]!,
          statusBar,
          reason: '$headerTitle 的 $name 必须随叠层下移 padding.top',
        );
        expect(
          shifted[name]!,
          greaterThanOrEqualTo(statusBar),
          reason: '$headerTitle 的 $name 不得落在状态栏带内',
        );
      }
      // 显式拆树：这些页面上还有重复动画（骨架/脉冲），留在树上会在测试结束
      // 时触发「Ticker was active」不变量断言，让失败原因指向错误的地方。
      await disposeApp(tester);
    }

    testWidgets('今日：整块内容随系统叠层下移', (tester) async {
      await expectContentShifted(tester, AppRoutes.dashboard, {
        '问候头': find.byKey(const Key('dashboard-greeting')),
      }, label: '今日页');
    });

    testWidgets('我的：身份卡随系统叠层下移', (tester) async {
      await expectContentShifted(tester, AppRoutes.settings, {
        '身份卡': find.byKey(const Key('settings-identity-card')),
      }, label: '我的页');
    });

    testWidgets('饮食·记录：胶囊行贴顶边 + 页首卡与胶囊内容随叠层下移', (tester) async {
      await expectStickySubTabChips(
        tester,
        headerKey: 'nutrition-record-energy',
        headerTitle: '今日营养',
      );
    });

    testWidgets('饮食·菜单：胶囊行贴顶边 + 段头块与胶囊内容随叠层下移', (tester) async {
      // 菜单 tab 不是默认 tab，先切过去再量。切 tab 也用有界推进
      // （同一页上的骨架屏动画会让 pumpAndSettle 永不返回）。
      Future<void> tapMenu() async {
        await tester.tap(find.text('菜单').first);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(seconds: 2));
      }

      // `nutrition-menu-hero` 自 2026-10-14（3-1 D25）起是**段头块**（不是卡），
      // 键与贴顶契约不变：页首件（含标题）随叠层整体下移，胶囊行仍从物理顶边
      // 铺起。
      await expectStickySubTabChips(
        tester,
        headerKey: 'nutrition-menu-hero',
        headerTitle: '每日菜品推荐',
        switchToTab: tapMenu,
      );
    });

    testWidgets('训练：白卡不再贴顶，页面用 `pagePadding + 叠层` 让出状态栏', (tester) async {
      // **契约在 2026-10-08 变了（docs/30 §2 D6）**：训练页顶部卡白卡化后
      // 不再铺到屏幕物理顶边，所以「色块必须从 y=0 开始」这条**不再成立**。
      // 断言随之改成新的真契约：**叠层 + 页面留白一起把卡片推到状态栏之下**，
      // 且卡片左右与页面其余内容对齐（不是只躲状态栏、左右贴着屏边）。
      //
      // 【为什么必须驱动真页面】这条断言曾经把 hero 塞进一个**复刻页面排布**
      // 的 ListView 里量——看着等价，实则**什么都测不到**：复刻品自己写的
      // padding 与被测页面无关，把 `training_page.dart` 里那行
      // `top: pagePadding + LfInsets.top` 整段删掉，测试照样全绿（2026-10-08
      // 变异 M7 实测）。所以这里走与上面几个分支页**同一条路**：真 App +
      // 真库 + 注入叠层，从页面上量。
      Future<Map<String, double>> measure(double inset) async {
        await pumpAt(tester, AppRoutes.training, topInset: inset);
        expect(
          find.byType(TrainingHero),
          findsOneWidget,
          reason: '训练页没渲染出 hero（仓储不全会退化成占位页），断言会空转',
        );
        final heroRect = tester.getRect(find.byKey(const Key('training-hero')));
        return {
          'heroTop': heroRect.top,
          'heroLeft': heroRect.left,
          '标题': tester.getTopLeft(find.byKey(const Key('training-title'))).dy,
        };
      }

      final plain = await measure(0);
      await disposeApp(tester);
      final shifted = await measure(statusBar);

      expect(
        plain['heroTop'],
        LfDimens.pagePadding,
        reason: '无叠层时卡片顶边 = 页面留白（不再从 y=0 铺满）',
      );
      expect(
        shifted['heroTop'],
        LfDimens.pagePadding + statusBar,
        reason: '卡片必须整体下移一个叠层高度，落到状态栏之下',
      );
      expect(
        shifted['标题']!,
        greaterThanOrEqualTo(statusBar),
        reason: '训练标题不得落在状态栏带内',
      );
      // 左右留白与页面其余内容同一档：白卡不再贴屏边（旧实现是铺满宽度）。
      expect(
        shifted['heroLeft'],
        LfDimens.pagePadding,
        reason: '卡片左右必须留出页面留白，不再贴屏幕边',
      );
      // 白卡 = 不透明 `card` 底 + 1px 描边，与全 App 其余卡片同一形态。
      final material = tester.widget<Material>(
        find
            .descendant(
              of: find.byKey(const Key('training-hero')),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(material.color, isNotNull);
      expect(material.color!.a, 1.0, reason: '白卡底必须不透明（不再是色块）');
      await disposeApp(tester);
    });

    testWidgets('分支页末尾预留必须把手势带算进去（否则最后一张卡压在栏体下）', (tester) async {
      await pumpAt(
        tester,
        AppRoutes.dashboard,
        topInset: 0,
        bottomInset: gestureInset,
      );

      final list = tester.widget<ListView>(find.byType(ListView).first);
      final reserved = list.padding!.resolve(TextDirection.ltr).bottom;

      expect(
        reserved,
        LfDimens.navReservedSpace + gestureInset,
        reason: 'docs/21 §5.8.4：末尾预留 = 栏体 64 + 净上凸 9.5 + 手势带',
      );
      expect(
        reserved,
        greaterThan(LfDimens.navReservedSpace),
        reason: '翻滚回退检测：把 navReserve 换成裸的 navReservedSpace 时必须红',
      );
      await disposeApp(tester);
    });
  });
}

final class _IncrementingIdGenerator implements IdGenerator {
  int _value = 0;

  @override
  String next() => 'inset-id-${_value++}';
}
