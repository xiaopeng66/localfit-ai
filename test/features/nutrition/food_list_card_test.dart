import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/design_card.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/application/food_library_controller.dart';
import 'package:localfit_ai/features/nutrition/data/catalog_search_service.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/presentation/food_library_view.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/food_list_states.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/food_search_tab.dart';

import '../../support/food_fixture.dart';

/// Round7 阶段 3 · 步骤 2b（A `app.js:195` 的 `.card.food-list`）**单卡列表**。
///
/// A 的手法：一张 `.card` 包住整列 `.food-row`，行与行之间只有 1px
/// `--track` 分隔线（`:last-child` 不画），**行不再是各自的卡**；行内衬由
/// `.food-list{padding:0 12px}` 给卡的左右各 12，行的上下 8 在行自己身上
/// （`polish.css:19`）。本仓改造前是「每行一张白卡 + 8dp 间距」。
///
/// 四条判据（全部**先红**）：
///  ① 整列只有**一层**卡面，且那层卡面与内容卡 `DesignCard` 同一套外观
///     （浅色透明描边 + 阴影 / 暗色描边无阴影）；
///  ② 相邻行之间有 1px `--track` 分隔线，**末行没有**；
///  ③ 行距 = 行高 56（`SliverPrototypeExtentList` 的行高已知保护不变）；
///  ④ 骨架与真实行同卡面、同行高（加载完成时列表不跳）。
///
/// 另外钉住两条数据路径的同形（分页浏览 / 仓库直搜各自都是单卡列表）。
void main() {
  late AppDatabase database;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await seedFoodFixture(database);
  });

  tearDown(() async {
    await database.close();
  });

  FoodRepository repo() => FoodRepository(
    database: database,
    idGenerator: _Ids(),
    clock: FixedAppClock(DateTime.utc(2026, 10, 14)),
  );

  FoodLibraryController controller() => FoodLibraryController(
    repository: repo(),
    catalogSearch: CatalogSearchService(shardPaths: const []),
  );

  Key rowKey(String id) => Key('food-library-item-$id');
  Key dividerKey(String id) => Key('food-library-row-divider-$id');

  /// 屏上真实行的 id（按树序）。列表行的 Key 约定与分页视图一致，
  /// 两条数据路径都挂它。
  List<String> visibleIds(WidgetTester tester) => find
      .byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith(
              'food-library-item-',
            ),
      )
      .evaluate()
      .map(
        (element) => (element.widget.key! as ValueKey<String>).value.substring(
          'food-library-item-'.length,
        ),
      )
      .toList(growable: false);

  /// 分页浏览路径。`extra` 用来在**同一棵树**里挂一件对照件（卡面外观对账）。
  ///
  /// 视口给到 1000dp，让夹具的 6 行**全部**被构建：这一组要按真实行序判「末行
  /// 不画分隔线」，只看得见前几行时「最后一行」量到的是缓存边界而不是列表末行
  /// （第一版就是这么红的 —— 是判据写错，不是实现错）。
  Future<void> pumpLibrary(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
    Widget? extra,
  }) async {
    tester.view.physicalSize = const Size(360, 1300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: brightness == Brightness.light
            ? AppTheme.light()
            : AppTheme.dark(),
        home: Scaffold(
          body: Column(
            children: [
              SizedBox(
                height: 1000,
                child: FoodLibraryView(controller: controller(), revision: 0),
              ),
              ?extra,
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder listSurface() => find.descendant(
    of: find.byKey(const Key('food-library-list')),
    matching: find.byType(DecoratedSliver),
  );

  group('单卡列表（A `.card.food-list`）', () {
    testWidgets('整列食物共用一层卡面：行不再是各自的卡', (tester) async {
      await pumpLibrary(tester);

      final ids = visibleIds(tester);
      expect(ids.length, greaterThanOrEqualTo(3), reason: '夹具要有够多行才量得出行距');

      expect(listSurface(), findsOneWidget, reason: 'A 是「一张卡包住整列行」：列表里只该有一层卡面');
      expect(
        find.descendant(
          of: find.byKey(const Key('food-library-list')),
          matching: find.byType(DesignCard),
        ),
        findsNothing,
        reason: '每行再套一张卡就是「卡中卡」（A 没有第二层卡）',
      );
      for (final id in ids) {
        expect(
          find.descendant(
            of: find.byKey(rowKey(id)),
            matching: find.byType(DesignCard),
          ),
          findsNothing,
          reason: '行 $id 自己不该带卡面',
        );
      }
    });

    testWidgets('列表卡面 = 内容卡同一套外观（浅色透明描边 + 阴影 / 暗色描边无阴影）', (tester) async {
      for (final brightness in [Brightness.light, Brightness.dark]) {
        await pumpLibrary(
          tester,
          brightness: brightness,
          extra: const DesignCard(child: SizedBox(height: 20, width: 120)),
        );

        expect(
          listSurface(),
          findsOneWidget,
          reason: '$brightness：列表里该有且只有一层卡面',
        );
        final surface =
            tester.widget<DecoratedSliver>(listSurface()).decoration
                as BoxDecoration;
        final cardSurface =
            tester
                    .widget<DecoratedBox>(
                      find
                          .descendant(
                            of: find.byType(DesignCard),
                            matching: find.byType(DecoratedBox),
                          )
                          .first,
                    )
                    .decoration
                as BoxDecoration;

        expect(
          surface.borderRadius,
          cardSurface.borderRadius,
          reason: '$brightness：圆角与内容卡同',
        );
        expect(
          surface.border,
          cardSurface.border,
          reason: '$brightness：描边与内容卡同',
        );
        expect(
          surface.boxShadow,
          cardSurface.boxShadow,
          reason: '$brightness：阴影与内容卡同',
        );
        expect(
          surface.color,
          brightness == Brightness.light
              ? LfSemanticColors.light.card
              : LfSemanticColors.dark.card,
          reason: '$brightness：卡面底色 = `--card`（内容卡由 Material 画，列表卡由装饰画）',
        );
      }
    });

    testWidgets('相邻行之间有 1px `--track` 分隔线，末行没有', (tester) async {
      await pumpLibrary(tester);

      final ids = visibleIds(tester);
      expect(ids.length, 6, reason: '夹具 6 行全都在屏上（末行判据必须落在列表真正的末行）');

      for (final id in ids.take(ids.length - 1)) {
        expect(
          find.byKey(dividerKey(id)),
          findsOneWidget,
          reason: '行 $id 与下一行之间要有分隔线（A `.food-row{border-bottom:1px}）',
        );
      }
      expect(
        find.byKey(dividerKey(ids.last)),
        findsNothing,
        reason: 'A `.food-row:last-child{border-bottom:0}`：末行不画分隔线',
      );

      final divider = find.byKey(dividerKey(ids.first));
      final dividerRect = tester.getRect(divider);
      final rowRect = tester.getRect(find.byKey(rowKey(ids.first)));
      expect(dividerRect.height, 1, reason: '分隔线是 1px（A 的 border-bottom）');
      expect(
        tester
            .widget<ColoredBox>(
              find.descendant(of: divider, matching: find.byType(ColoredBox)),
            )
            .color,
        LfComponentColors.light.ringTrack,
        reason: '颜色 = `--track`（A polish 把 border 色改成 track）',
      );
      expect(dividerRect.left, closeTo(rowRect.left, 0.5), reason: '分隔线与行同宽');
      expect(dividerRect.right, closeTo(rowRect.right, 0.5));
      expect(
        dividerRect.bottom,
        closeTo(rowRect.bottom, 0.5),
        reason: '分隔线画在行的下缘（不在两行之间另占高度）',
      );
      expect(
        rowRect.left,
        closeTo(LfDimens.pagePadding + LfDimens.spaceMedium, 0.5),
        reason: '行从卡边缘内缩 12（A `.food-list{padding:0 12px}`），卡从页边距 16 起',
      );
    });

    testWidgets('行距 = 行高 56：单卡列表里行与行之间没有间距', (tester) async {
      await pumpLibrary(tester);

      final ids = visibleIds(tester);
      final first = tester.getRect(find.byKey(rowKey(ids[0])));
      final second = tester.getRect(find.byKey(rowKey(ids[1])));
      expect(
        first.height,
        closeTo(LfDimens.foodCardIconSize + LfDimens.spaceSmall * 2, 0.5),
        reason:
            '行高 = 图标 40 + 上下各 8（A `.food-row{min-height:56px;padding:8px 0}`）',
      );
      expect(
        second.top - first.top,
        closeTo(first.height, 0.5),
        reason: '行距 = 行高：A 的行之间只有分隔线，没有 8dp 间距',
      );
      expect(
        second.height,
        closeTo(first.height, 0.5),
        reason: '行高恒定（已知行高保护不变）',
      );
    });

    testWidgets('骨架与真实行同构：同一层卡面、同 56 行高、同分隔线', (tester) async {
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: FoodListSkeleton()),
        ),
      );
      // 骨架里的 `SkeletonBox` 是循环呼吸动画：只 pump 一帧，不用 pumpAndSettle。
      await tester.pump();

      final rows = find.byType(FoodCardSkeleton);
      expect(rows, findsWidgets);
      final first = tester.getRect(rows.at(0));
      final second = tester.getRect(rows.at(1));
      expect(
        first.height,
        closeTo(LfDimens.foodCardIconSize + LfDimens.spaceSmall * 2, 0.5),
        reason: '骨架行高必须与真行一致（否则加载完成时列表会跳）',
      );
      expect(second.top - first.top, closeTo(first.height, 0.5));
      expect(
        find.descendant(
          of: find.byType(FoodListSkeleton),
          matching: find.byType(DecoratedSliver),
        ),
        findsOneWidget,
        reason: '骨架也住在同一层卡面里',
      );
      expect(
        find.descendant(
          of: find.byType(FoodListSkeleton),
          matching: find.byType(DesignCard),
        ),
        findsNothing,
        reason: '骨架不再是每行一张卡',
      );
      expect(
        find.byKey(const Key('food-library-row-divider-skeleton-0')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('food-library-row-divider-skeleton-5')),
        findsNothing,
        reason: '骨架的末行同样不画分隔线（6 行的最后一行是下标 5）',
      );
    });

    testWidgets('直搜路径（无目录 controller）同形：同一层卡面 + 行内分隔线', (tester) async {
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: FoodSearchTab(
              repository: repo(),
              query: '鸡',
              revision: 0,
              onQueryChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final ids = visibleIds(tester);
      expect(ids.length, 2, reason: '夹具里「鸡」命中鸡蛋与鸡胸肉两行');
      expect(find.byType(DecoratedSliver), findsOneWidget);
      expect(find.byType(DesignCard), findsNothing, reason: '直搜路径同样是单卡列表');
      expect(
        find.byType(SliverPrototypeExtentList),
        findsOneWidget,
        reason:
            '两条数据路径同一套行高已知的列表（换回 SliverList 会丢掉'
            '「拖到底不卡死」的前提，见 food_library_far_jump_test.dart）',
      );
      expect(find.byKey(dividerKey(ids.first)), findsOneWidget);
      expect(find.byKey(dividerKey(ids.last)), findsNothing);
      expect(
        tester.getRect(find.byKey(rowKey(ids[0]))).height,
        closeTo(56, 0.5),
      );
    });
  });
}

final class _Ids implements IdGenerator {
  int _value = 0;

  @override
  String next() => 'id-${_value++}';
}
