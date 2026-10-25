import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_router.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/localfit_app.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/nutrition_legacy_tab_shell.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/nutrition_sub_tab_chips.dart';

/// 饮食页三个 sub-tab 的胶囊行必须在**同一个位置**（用户 2026-10-03 走查）。
///
/// 走查原话：「饮食界面的五个菜单按钮能不能移动到顶部，不然每个界面的位置
/// 都不在一个地方」。旧实现把同一条胶囊行分三处渲染（记录页塞在 hero 与趋势
/// 卡之间、菜单页塞在 hero 之下、未画 tab 塞在外壳里），实测三个不同
/// 高度：y≈300 / 139 / 60。
///
/// 2026-10-04（docs/28 §6.1）：五枚收敛为三枚（记录 / 菜单 / 食物库），
/// 计划 / 食谱两枚随该族功能下线；位置契约不变，本回归在三枚上重跑。
///
/// 判据按**几何**说话，不按「有没有用页级实例」这种实现细节：
///  1. 页面上只有一份 [NutritionSubTabChips]（唯一渲染点）；
///  2. 每一枚 tab 上，胶囊行底色都从屏幕物理顶边开始（`top == 0`）；
///  3. 每一枚 tab 上，该 tab 的页头（hero / 细顶栏）都**紧接**胶囊行下缘，
///     中间不得再夹一张卡（记录页的趋势卡曾经就夹在这里）；
///  4. 注入状态栏后：胶囊行底色仍贴顶边、行高 = 52 + 叠层、内容与页头整体
///     下移一个叠层高度，且不得落进状态栏带。
///
/// 阶段 2B（D15）追加**形态**契约：A `.tabs`（`styles.css:158-160` +
/// `refinement.css:3`）= `--track` 轨道 + 等宽三段，选中段 `--card` 底 + `--fg`
/// + w600；段 `min-height 44`，行高 52；大字号下文字必须按自然行高布局
/// （旧件固定行高 54 把内容槽压到 30，2.0× 文字自然行高 34 被裁 16dp）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const chipBarHeight = NutritionSubTabChips.barHeight;

  /// 每个 tab 的胶囊 Key、「该 tab 页首元素」的 Key、以及它与胶囊行的净距。
  ///
  /// 页首元素就是胶囊行下缘之后的第一个元素：菜单是**段头块**
  /// （`nutrition-menu-hero`，在滚动视图首槽；阶段 3 步骤 1 D25 起它是段头
  /// 文字块而不是卡），食物库是**搜索行**
  /// （docs/29 §P8a 需求 29/30 把那一枚的细顶栏整条撤掉——标题与返回键都删、
  /// 自建食物入口搬到搜索框右侧，于是紧接胶囊行的第一个元素变成搜索行），
  /// 记录页的阶段 2B 步骤 6 起是**周条**（A `nutritionRecords()` 的第一件是
  /// `.date-strip`；此前是共享热量卡，那是「页首卡」时代的装配）。
  ///
  /// 净距不是装饰：A `.page{padding:12px 16px 28px; gap:16px}` 的页首元素
  /// 顶距就是 12。记录页（2B）与菜单页（3-1）的页首件都按 A 的 `.page` 顶距
  /// 让出 12；食物库这一个 tab 仍是 0——它的首元素是搜索行，自带 0 顶距
  /// （等它的页首结构按 A 重排时再单独裁决，不要顺手改）。三个 tab 都必须
  /// 紧接胶囊行、中间不夹任何东西，这一条不变。
  final tabs = <(String chip, Key header, double gap)>[
    ('nutrition-tab-record', const Key('nutrition-record-week-strip'), 12),
    ('nutrition-tab-menu', const Key('nutrition-menu-hero'), 12),
    ('nutrition-tab-foodlib', NutritionTabs.foodLibraryHeaderKey, 0),
  ];

  Future<void> pumpNutrition(
    WidgetTester tester, {
    double topInset = 0,
    double textScale = 1,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    final insets = FakeViewPadding(top: topInset);
    tester.view.padding = insets;
    tester.view.viewPadding = insets;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
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
        now: DateTime(2026, 9, 17),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> unmountApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('三个 sub-tab 的胶囊行位置逐像素一致：贴顶边 + 页头紧接其下', (tester) async {
    await pumpNutrition(tester);

    final tops = <double>[];
    for (final (chipKey, headerKey, gap) in tabs) {
      await tester.tap(find.byKey(Key(chipKey)));
      await tester.pumpAndSettle();

      expect(
        find.byType(NutritionSubTabChips),
        findsOneWidget,
        reason: '胶囊行必须只有一份（页级唯一渲染点），否则三处各画一条又会跑偏',
      );
      final chips = tester.getRect(find.byKey(NutritionSubTabChips.barKey));
      final header = tester.getRect(find.byKey(headerKey));
      tops.add(chips.top);

      expect(chips.top, 0, reason: '$chipKey：胶囊行底色必须从屏幕顶边开始');
      expect(
        chips.height,
        chipBarHeight,
        reason: '$chipKey：无叠层时行高应是 $chipBarHeight（A `.tabs` 4 + 段 44 + 4）',
      );
      expect(
        header.top,
        chips.bottom + gap,
        reason:
            '$chipKey：$headerKey 必须紧接胶囊行下缘（中间不得再夹卡片；'
            '净距 ${gap}dp = A 的页首顶距）',
      );
    }
    expect(tops.toSet().length, 1, reason: '三个 tab 的胶囊行 top 必须完全相同，实测各为 $tops');

    await unmountApp(tester);
  });

  testWidgets('注入状态栏后：胶囊行底色仍贴顶边，内容与页头整体下移一个叠层', (tester) async {
    const statusBar = 48.0;
    await pumpNutrition(tester, topInset: statusBar);

    final chips = tester.getRect(find.byKey(NutritionSubTabChips.barKey));
    expect(chips.top, 0, reason: '胶囊行的底色必须铺到屏幕物理顶边（不能留一条空白带）');
    expect(
      chips.height,
      chipBarHeight + statusBar,
      reason: '行高 = $chipBarHeight + 叠层：背景吃叠层、内容不吃',
    );

    // 胶囊**内容**与页头都躲开状态栏，且页头仍紧接行下缘。
    final chip = tester.getRect(find.byKey(const Key('nutrition-tab-record')));
    expect(chip.top, greaterThanOrEqualTo(statusBar), reason: '胶囊本体不得落进状态栏带内');
    final header = tester.getRect(
      find.byKey(const Key('nutrition-record-week-strip')),
    );
    expect(
      header.top,
      chipBarHeight + statusBar + 12,
      reason: '页首元素（周条）不得再自己吃一次叠层（那会把它推下两倍状态栏高度）',
    );

    await unmountApp(tester);
  });

  group('A `.tabs` 形态（阶段 2B D15）', () {
    testWidgets('轨道 + 等宽三段：选中段 card 底 + fg + w600，行高 52', (tester) async {
      await pumpNutrition(tester);

      expect(chipBarHeight, 52, reason: 'A：轨道内衬 4 + 段 min-height 44 + 4');
      final bar = tester.getRect(find.byKey(NutritionSubTabChips.barKey));
      final track = tester.getRect(find.byKey(NutritionSubTabChips.trackKey));
      expect(track.height, chipBarHeight, reason: '轨道铺满整行内容盒（无额外上下留白）');
      expect(track.top - bar.top, 0, reason: '轨道顶边 = 行顶边（不含叠层）');
      // 段盒 = 轨道内容盒 = 行高 − 2×4 内衬。
      final segment = tester.getRect(
        find.byKey(const Key('nutrition-tab-record')),
      );
      expect(
        segment.height,
        44,
        reason: '段盒高 = 行高 − 2×4 内衬（A `min-height:44px`）',
      );
      expect(segment.top - track.top, 4, reason: 'A `.tabs{padding:4px}`');

      // 轨道：--track 底 + 12 圆角（refinement 覆盖 styles 的 28）。
      final trackBox = tester.widget<Container>(
        find.byKey(NutritionSubTabChips.trackKey),
      );
      final trackDec = trackBox.decoration! as BoxDecoration;
      expect(
        trackDec.color,
        LfComponentColors.light.ringTrack,
        reason: 'A `--track`',
      );
      expect(trackDec.borderRadius, BorderRadius.circular(12));

      // 三段等宽（A `flex:1` + gap 5）：五枚时代的横滑补丁不再需要。
      final widths = [
        for (final key in const [
          'nutrition-tab-record',
          'nutrition-tab-menu',
          'nutrition-tab-foodlib',
        ])
          tester.getRect(find.byKey(Key(key))).width,
      ];
      for (final width in widths) {
        expect(widths.first - width, closeTo(0, 0.5));
      }

      // 选中段 = card 底 + 9 圆角；未选中 = 透明。
      final selected = tester.widget<Material>(
        find.byKey(const Key('nutrition-tab-record')),
      );
      expect(selected.color, LfSemanticColors.light.card);
      expect(selected.borderRadius, BorderRadius.circular(9));
      final unselected = tester.widget<Material>(
        find.byKey(const Key('nutrition-tab-menu')),
      );
      expect(unselected.color, Colors.transparent);

      // 字：13px（bodySmall），选中 w600 + fg、未选中 muted。
      final selectedText = tester.widget<Text>(find.text('记录'));
      expect(selectedText.style?.fontSize, 13);
      expect(selectedText.style?.color, LfSemanticColors.light.foreground);
      expect(selectedText.style?.fontWeight, FontWeight.w600);
      final unselectedText = tester.widget<Text>(find.text('菜单'));
      expect(
        unselectedText.style?.color,
        LfSemanticColors.light.mutedForeground,
      );
      expect(unselectedText.style?.fontWeight, FontWeight.w400);

      await unmountApp(tester);
    });

    testWidgets('2.0×：三段文字按自然行高布局（不裁字，旧件裁 16dp）', (tester) async {
      await pumpNutrition(tester, textScale: 2.0);

      for (final label in const ['记录', '菜单', '食物库']) {
        final para = tester.renderObject<RenderParagraph>(find.text(label));
        final intrinsic = para.getMaxIntrinsicHeight(double.infinity);
        // 旧件：行高固定 54、内容槽 30、文字盒 18 —— 2.0× 自然行高 34，
        // 16dp 的笔画被 ListView 视口裁掉（2A 帧 `_rec32020_top.png`）。
        expect(
          para.size.height,
          greaterThanOrEqualTo(intrinsic - 0.5),
          reason: '$label：文字盒 ${para.size.height} 装不下自然行高 $intrinsic',
        );
      }

      final bar = tester.getRect(find.byKey(NutritionSubTabChips.barKey));
      for (final key in const [
        'nutrition-tab-record',
        'nutrition-tab-menu',
        'nutrition-tab-foodlib',
      ]) {
        final segment = tester.getRect(find.byKey(Key(key)));
        expect(segment.height, greaterThanOrEqualTo(44), reason: '$key 段盒');
        expect(segment.top, greaterThanOrEqualTo(bar.top - 0.01));
        expect(segment.bottom, lessThanOrEqualTo(bar.bottom + 0.01));
      }

      await unmountApp(tester);
    });
  });
}

final class _Ids implements IdGenerator {
  var _value = 0;

  @override
  String next() => 'subtab-pos-${++_value}';
}
