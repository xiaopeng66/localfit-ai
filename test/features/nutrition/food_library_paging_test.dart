import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/application/food_library_controller.dart';
import 'package:localfit_ai/features/nutrition/domain/food_category.dart';
import 'package:localfit_ai/features/nutrition/data/catalog_search_service.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/food_record.dart';
import 'package:localfit_ai/features/nutrition/presentation/food_library_view.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/food_card.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/nutrition_tab_bodies.dart';

/// docs/28 §8：食物库全量浏览（D5「食物库只能显示一部分」）。
///
/// 旧实现一次只取 30 条，下滑永远只有 30 张卡。这里钉四件事：
///  ① 总数 = 真实条数（`COUNT(*)`，不是已加载量）；
///  ② 翻页无重复、无漏行——**唯一键兜底**（`isUserCreated DESC, name ASC, id ASC`）
///     的可观测判据：同分组内 id 必须升序且各页恰好划分全集；
///  ③ 滑条常显且可拖，拖过未加载区间能一路滑到底（不是停在骨架上）；
///  ④ 某一页加载失败有错误行 + 重试，重试成功才出卡。
void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  FoodRepository repo() => FoodRepository(
    database: database,
    idGenerator: _Ids(),
    clock: FixedAppClock(DateTime.utc(2026, 10, 4)),
  );

  FoodLibraryController controller() => FoodLibraryController(
    repository: repo(),
    catalogSearch: CatalogSearchService(shardPaths: const []),
  );

  /// 造 [count] 条食物。**故意只给 3 个名字**（重名）且**按打乱的 id 顺序插入**：
  /// 这样「同一分组内的先后」只可能来自 `id ASC` 兜底——SQLite 自己的平局顺序
  /// 是扫描（插入）序，与 id 升序不一致。
  Future<void> seed(int count) async {
    final now = DateTime.utc(2026, 10, 4);
    // 打乱插入序：插入序 = 按 name 分组后的交错序，与 id 升序不同。
    final order = <int>[for (var i = 0; i < count; i++) i]
      ..sort((a, b) => ((a * 7919) % count).compareTo((b * 7919) % count));
    await database.batch((batch) {
      batch.insertAll(database.foods, [
        for (final i in order)
          FoodsCompanion.insert(
            id: 'food-${i.toString().padLeft(4, '0')}',
            name: '米饭${i % 3}',
            kcalPer100g: 100,
            proteinPer100g: 1,
            carbsPer100g: 1,
            fatPer100g: 1,
            source: 'seed',
            createdAt: now,
            updatedAt: now,
          ),
      ]);
    });
  }

  Widget host(FoodLibraryController controller) => MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 360,
        height: 800,
        child: FoodLibraryView(controller: controller, revision: 0),
      ),
    ),
  );

  Future<void> pumpHost(WidgetTester tester, FoodLibraryController c) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(host(c));
    await tester.pumpAndSettle();
  }

  test(
    'count() is the real total; pages partition every row exactly once',
    () async {
      await seed(130);
      final repository = repo();
      expect(await repository.count(), 130);

      final seen = <String>[];
      for (
        var offset = 0;
        offset < 130;
        offset += FoodLibraryController.pageSize
      ) {
        final page = await repository.page(
          offset: offset,
          limit: FoodLibraryController.pageSize,
        );
        seen.addAll(page.map((food) => food.id));
      }
      // 无漏行、无重复：130 条恰好各一次。
      expect(seen.length, 130);
      expect(seen.toSet().length, 130);
      expect(seen.toSet(), {
        for (var i = 0; i < 130; i++) 'food-${i.toString().padLeft(4, '0')}',
      });

      // 唯一键兜底的可观测形态：全部「米饭0」在前、「米饭1」其次、「米饭2」最后，
      // 且组内 id 严格升序。去掉 `id ASC` 后组内顺序退化成插入序 ⇒ 这条转红。
      String nameOf(String id) => '米饭${int.parse(id.substring(5)) % 3}';
      expect(seen.map(nameOf).toList(), [
        ...List.filled(44, '米饭0'),
        ...List.filled(43, '米饭1'),
        ...List.filled(43, '米饭2'),
      ]);
      for (final group in ['米饭0', '米饭1', '米饭2']) {
        final ids = seen.where((id) => nameOf(id) == group).toList();
        expect(ids, orderedEquals(ids.toList()..sort()));
      }
    },
  );

  testWidgets(
    'count row shows the real total and the scrollbar is persistent',
    (tester) async {
      await seed(130);
      await pumpHost(tester, controller());

      expect(find.text('130 种食物'), findsOneWidget);
      final scrollbar = tester.widget<Scrollbar>(find.byType(Scrollbar));
      expect(scrollbar.thumbVisibility, isTrue);
      expect(scrollbar.interactive, isTrue);
      // 首屏只加载第一页：最后一页的条目还没构建（不是假卡，是没到）。
      expect(
        find.byKey(const Key('food-library-item-food-0129')),
        findsNothing,
      );
      expect(find.byType(FoodCard), findsWidgets);
    },
  );

  testWidgets(
    'dragging to the bottom loads the landing page (no stuck skeleton)',
    (tester) async {
      await seed(60);
      await pumpHost(tester, controller());

      expect(
        find.byKey(const Key('food-library-item-food-0059')),
        findsNothing,
      );
      // 拖到底的距离按**真实可滚长度**算，不写死像素：行高（原型卡高度）一改，
      // 写死的距离就会差一点点滑不到底，测试变成假失败。
      final position = tester
          .state<ScrollableState>(
            find.descendant(
              of: find.byKey(const Key('food-library-list')),
              matching: find.byType(Scrollable),
            ),
          )
          .position;
      await tester.drag(
        find.byKey(const Key('food-library-list')),
        Offset(0, -(position.maxScrollExtent + 200)),
      );
      await tester.pumpAndSettle();

      // 拖到底能看到最后一页内容——不是骨架停在那儿。
      expect(
        find.byKey(const Key('food-library-item-food-0059')),
        findsOneWidget,
      );
      // 末页那几格确实是真卡（名字按 id 升序分组，末尾一段是「米饭2」）。
      expect(find.text('米饭2'), findsWidgets);
    },
  );

  testWidgets('a failed page shows a retry row; retrying loads the cards', (
    tester,
  ) async {
    await seed(60);
    await pumpHost(tester, _FlakyController(repository: repo()));

    // 第一页第一次拉失败：画一行错误 + 重试，不画假卡。
    expect(find.byKey(const Key('food-library-page-error-0')), findsOneWidget);
    expect(find.byKey(const Key('food-library-page-retry-0')), findsOneWidget);

    await tester.tap(find.byKey(const Key('food-library-page-retry-0')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('food-library-page-error-0')), findsNothing);
    expect(
      find.byKey(const Key('food-library-item-food-0000')),
      findsOneWidget,
    );
  });

  // 2026-10-04 W5 设备走查抓到的缺口：页面顶栏的「自建食物」是 tab 级动作，
  // 落库后只把 `revision` 抬一；分页视图当时既不重取总数、也不清页缓存
  // ⇒ 计数行写着 49,464（真值 49,465），新食物在列表里也看不见（我的页
  // 是另一个库计数，同一时刻已经写对，正是它把「没刷新」与「没落库」分开）。
  testWidgets('自建食物后 revision 抬一格 ⇒ 计数行与列表按当前查询重来', (tester) async {
    await seed(130);
    final repository = repo();
    final c = FoodLibraryController(
      repository: repository,
      catalogSearch: CatalogSearchService(shardPaths: const []),
    );
    var revision = 0;
    late StateSetter rebuild;
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return SizedBox(
                width: 360,
                height: 800,
                child: FoodLibraryView(controller: c, revision: revision),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('130 种食物'), findsOneWidget);

    // 顶栏那枚动作的真实落库路径。
    await repository.create(
      const NewFood(
        name: '新加的',
        kcalPer100g: 88,
        proteinPer100g: 3,
        carbsPer100g: 5,
        fatPer100g: 2,
      ),
    );
    expect(await repository.count(), 131);

    // 反向控制：**只重建、不抬 revision** 不得重来。它同时把两种实现分开——
    // 「比较 revision」与「每次 update 都重来」（后者会把页缓存白白清空）。
    rebuild(() {});
    await tester.pumpAndSettle();
    expect(find.text('130 种食物'), findsOneWidget);
    expect(find.byKey(const Key('food-library-item-id-0')), findsNothing);

    // 抬一格：总数换成真实值，自建那条排在最前（`isUserCreated DESC`）。
    rebuild(() => revision += 1);
    await tester.pumpAndSettle();
    expect(find.text('131 种食物'), findsOneWidget);
    expect(find.byKey(const Key('food-library-item-id-0')), findsOneWidget);
  });

  // 接线端：缺口就是断在这条透传上（只传给旧搜索路径）。视图端那条用例
  // 直接构造 FoodLibraryView，抓不到这里把 revision 写死。
  testWidgets('tab body 把 revision 透传到分页视图', (tester) async {
    await seed(130);
    final repository = repo();
    final c = FoodLibraryController(
      repository: repository,
      catalogSearch: CatalogSearchService(shardPaths: const []),
    );
    var revision = 0;
    late StateSetter rebuild;
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return SizedBox(
                width: 360,
                height: 800,
                child: NutritionFoodLibraryTabBody(
                  repository: repository,
                  controller: c,
                  query: '',
                  revision: revision,
                  onQueryChanged: (_) {},
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('130 种食物'), findsOneWidget);

    await repository.create(
      const NewFood(
        name: '新加的',
        kcalPer100g: 88,
        proteinPer100g: 3,
        carbsPer100g: 5,
        fatPer100g: 2,
      ),
    );
    rebuild(() => revision += 1);
    await tester.pumpAndSettle();
    expect(find.text('131 种食物'), findsOneWidget);
  });
}

/// 第一页的第一次 `page` 调用抛错，其余照常——用来验证「加载失败有重试」。
final class _FlakyController extends FoodLibraryController {
  _FlakyController({required super.repository})
    : super(catalogSearch: CatalogSearchService(shardPaths: const []));

  int _pageCalls = 0;

  @override
  Future<List<FoodLibraryItem>> page(
    String query, {
    required int offset,
    required int limit,
    FoodCategory? category,
  }) {
    _pageCalls++;
    if (offset == 0 && _pageCalls == 1) {
      return Future<List<FoodLibraryItem>>.error(StateError('这一页没加载出来'));
    }
    return super.page(query, offset: offset, limit: limit, category: category);
  }
}

final class _Ids implements IdGenerator {
  int _value = 0;

  @override
  String next() => 'id-${_value++}';
}
