import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/application/food_library_controller.dart';
import 'package:localfit_ai/features/nutrition/data/catalog_search_service.dart';
import 'package:localfit_ai/features/nutrition/data/catalog_shard_detail_source.dart';
import 'package:localfit_ai/features/nutrition/data/food_detail_loader.dart';
import 'package:localfit_ai/features/nutrition/data/food_detail_repository.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/presentation/nutrition_page.dart';
import 'package:localfit_ai/features/nutrition/domain/food_category.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/food_card.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/food_list_states.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/nutrition_legacy_tab_shell.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/nutrition_sub_tab_chips.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// 2.0-6f：食物库 tab 50k 搜索接线（docs/07 §9.3）：
/// 主库 + 目录分片合并、加载更多（分页 ≤50）、骨架屏与错误态保留、
/// 空查询展示主库默认列表。
///
/// 2026-10-03 改版：搜索框由 M3 `SearchBar` 换成主题内的
/// `LfSearchField`（Key `food-library-search`），结果行由 `ListTile` 换成共用
/// 的 `FoodCard`。**分类筛选 chips 仍为有意不做**：`FoodCategory.classify`
/// 对中文覆盖弱（「牛肉面」落到「其他」），拿它当筛选器会让多数条目挤进同一
/// 格——分类只用于卡上的图标。
void main() {
  late AppDatabase database;
  late Directory tempDir;
  late String shardPath;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    tempDir = Directory.systemTemp.createTempSync('localfit-foodlib-ui-');
    shardPath = '${tempDir.path}${Platform.pathSeparator}foods-core-000.sqlite';
    final shardDb = sqlite.sqlite3.open(shardPath);
    addTearDown(shardDb.dispose);
    shardDb.execute('''
CREATE TABLE foods (
  id TEXT NOT NULL PRIMARY KEY,
  name TEXT NOT NULL,
  state TEXT NOT NULL,
  locale TEXT,
  category TEXT,
  brand TEXT,
  kcal_per100g REAL,
  protein_per100g REAL,
  carbs_per100g REAL,
  fat_per100g REAL,
  source_id TEXT NOT NULL,
  source_version TEXT,
  license_status TEXT NOT NULL
);
CREATE VIRTUAL TABLE food_search USING fts5(food_id UNINDEXED, text, brand, category);
CREATE TABLE portions (
  id TEXT NOT NULL PRIMARY KEY,
  food_id TEXT NOT NULL,
  name TEXT NOT NULL,
  grams REAL NOT NULL,
  locale TEXT,
  source TEXT
);
CREATE TABLE revisions (
  id TEXT NOT NULL PRIMARY KEY,
  food_id TEXT NOT NULL,
  revision_number INTEGER NOT NULL,
  kcal_per100g REAL, protein_per100g REAL, carbs_per100g REAL, fat_per100g REAL,
  source_evidence_id TEXT,
  quality_status TEXT NOT NULL,
  valid_from TEXT
);
CREATE TABLE evidence (
  id TEXT NOT NULL PRIMARY KEY,
  source_id TEXT NOT NULL,
  license TEXT NOT NULL,
  attribution TEXT,
  retrieved_at TEXT NOT NULL,
  transform_version TEXT NOT NULL,
  quality_status TEXT NOT NULL,
  record_hash TEXT NOT NULL
);
''');
    // 2.0-1j：分片自带份量/修订/证据，导入之前详情就能读到。
    shardDb.execute(
      "INSERT INTO portions VALUES ('cat-rice:portion:1', 'cat-rice', '一碗',"
      " 150, 'zh-CN', 'openfoodfacts')",
    );
    shardDb.execute(
      "INSERT INTO evidence VALUES ('cat-rice:ev', 'openfoodfacts',"
      " 'odbl-1.0', 'Open Food Facts, ODbL', '2026-09-15T20:45:07Z',"
      " '2.0-1j', 'ok', '${'a' * 64}')",
    );
    shardDb.execute(
      "INSERT INTO revisions VALUES ('cat-rice:rev:1', 'cat-rice', 1, 116,"
      " 2.6, 25.9, 0.3, 'cat-rice:ev', 'ok', '2026-09-15T20:45:07Z')",
    );
    void catalogFood(String id, String name, {String? category}) {
      shardDb.execute(
        'INSERT INTO foods (id, name, state, locale, category, brand,'
        ' kcal_per100g, protein_per100g, carbs_per100g, fat_per100g,'
        " source_id, license_status) VALUES ('$id', '$name', 'verified', 'zh',"
        " ${category == null ? 'NULL' : "'$category'"}, NULL, 100, 1, 1, 1,"
        " 'openfoodfacts', 'allowed')",
      );
      final spaced = name.split('').join(' ');
      shardDb.execute(
        "INSERT INTO food_search (food_id, text, brand, category)"
        " VALUES ('$id', '$spaced', '', ${category == null ? "''" : "'$category'"})",
      );
    }

    catalogFood('cat-rice', '蒸米饭');
    catalogFood('cat-noodle', '牛肉面', category: 'noodle');

    final now = DateTime.utc(2026, 9, 15, 7);
    await database
        .into(database.foods)
        .insert(
          FoodsCompanion.insert(
            id: 'user-rice',
            name: '米饭（自建）',
            kcalPer100g: 116,
            proteinPer100g: 2.6,
            carbsPer100g: 25.9,
            fatPer100g: 0.3,
            source: 'user',
            state: const Value('user_created'),
            // 卡上的「自建 / 内置」读的是这一列（docs/28 §5.1 D2）。
            isUserCreated: const Value(true),
            createdAt: now,
            updatedAt: now,
          ),
        );
  });

  tearDown(() async {
    await database.close();
    tempDir.deleteSync(recursive: true);
  });

  Widget host(FoodLibraryController controller) => MaterialApp(
    home: Scaffold(
      body: NutritionPage(
        repository: FoodRepository(
          database: database,
          idGenerator: _Ids(),
          clock: FixedAppClock(DateTime.utc(2026, 9, 9)),
        ),
        foodLibraryController: controller,
        now: DateTime(2026, 9, 9),
      ),
    ),
  );

  FoodLibraryController libController({bool withDetails = true}) =>
      FoodLibraryController(
        repository: FoodRepository(
          database: database,
          idGenerator: _Ids(),
          clock: FixedAppClock(DateTime.utc(2026, 9, 9)),
        ),
        catalogSearch: CatalogSearchService(shardPaths: [shardPath]),
        detailLoader: withDetails
            ? FoodDetailLoader(
                databaseDetails: FoodDetailRepository(database: database),
                shardDetails: CatalogShardDetailSource(shardPaths: [shardPath]),
              )
            : null,
      );

  testWidgets('empty query displays the default main-library list', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(host(libController()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('食物库'));
    await tester.pumpAndSettle();

    expect(find.text('米饭（自建）'), findsOneWidget);
    expect(find.byKey(const Key('food-library-list')), findsOneWidget);
  });

  testWidgets('uncategorized rice renders a labeled staple SVG icon', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(host(libController()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('食物库'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('food-category-icon-staple-user-rice')),
      findsOneWidget,
    );
    // Round7 阶段 3（D33）：分类胶囊行上线后，「主食」这个语义标签在页面上
    // 合法地出现两次（列表行图标 + 筛选胶囊）⇒ 作用域收窄到列表内部。
    // 本条要钉的是「行上的图标带可读标签」，不是「全页唯一这个标签」——
    // 全局 findsOneWidget 会顺带变成「不许有分类胶囊」的间接断言，那不是
    // 这里要保护的事实（胶囊有自己的结构测试）。
    expect(
      find.descendant(
        of: find.byKey(const Key('food-library-list')),
        matching: find.bySemanticsLabel(RegExp('主食')),
      ),
      findsOneWidget,
    );
  });

  testWidgets('search merges main-db and catalog rows into the same card', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(host(libController()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('食物库'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('food-library-search')), '米饭');
    await tester.pumpAndSettle();

    // 主库在前、目录在后，两条来源共用同一张单行卡（`FoodCard`）。
    expect(find.text('米饭（自建）'), findsOneWidget);
    expect(find.text('蒸米饭'), findsOneWidget);
    expect(find.byType(FoodCard), findsNWidgets(2));
    // 来源标签整批退场（2026-10-08 docs/30 §2 D1：卡只剩图标 + 名称 + 环）。
    // 「自建 / 内置」现在是**详情弹层**里的话，「主库 / 目录」是内部数据分层，
    // 两者都不该出现在卡面——这四种文本一个都不许在。
    for (final gone in const ['自建', '内置', '主库', '目录']) {
      expect(find.text(gone), findsNothing, reason: '「$gone」不该出现在单行卡上');
    }
  });

  testWidgets('需求 29/30：食物库 tab 没有细顶栏，自建食物入口在搜索框右侧', (tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(host(libController()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('食物库'));
    await tester.pumpAndSettle();

    // 需求 30：标题与返回键都不在这枚 tab 上（顶栏是共享件，只按页开关——
    // 其余几处二级页的返回键由 `system_inset_test` 继续钉住）。
    expect(find.byKey(const Key('nutrition-legacy-bar-食物库')), findsNothing);
    expect(find.byKey(const Key('top-bar-back')), findsNothing);

    // 需求 29：入口紧贴搜索框右侧、同一行（几何判定，不只看「在不在」）。
    final search = tester.getRect(find.byKey(const Key('food-library-search')));
    final cta = tester.getRect(find.byKey(const Key('cta-new-food')));
    expect(cta.left, greaterThanOrEqualTo(search.right), reason: '按钮在搜索框右边');
    expect(cta.center.dy, closeTo(search.center.dy, 1), reason: '同一行 ⇒ 中心对齐');
    // 顶栏撤掉之后，搜索行紧接页级胶囊行下缘。
    final chips = tester.getRect(find.byKey(NutritionSubTabChips.barKey));
    final header = tester.getRect(
      find.byKey(NutritionTabs.foodLibraryHeaderKey),
    );
    expect(header.top, chips.bottom);
  });

  testWidgets('需求 23：满刻度 1000 在列表头写一次（不逐卡重复）', (tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(host(libController()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('食物库'));
    await tester.pumpAndSettle();

    final note = find.byKey(const Key('food-density-scale-note'));
    expect(note, findsOneWidget, reason: '同一句话只出现一次');
    expect(
      tester.widget<Text>(note).data,
      contains('满刻度 1000 kcal/100g'),
      reason: '数字来自 kFoodDensityFullScaleKcal，改刻度这句话跟着变',
    );
    // 卡上不再重复这句（环下只写每行都会变的单位）。
    expect(find.textContaining('满刻度'), findsOneWidget);
  });

  testWidgets('no controller falls back to repository-only search', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      host(
        FoodLibraryController(
          repository: FoodRepository(
            database: database,
            idGenerator: _Ids(),
            clock: FixedAppClock(DateTime.utc(2026, 9, 9)),
          ),
          catalogSearch: CatalogSearchService(shardPaths: const []),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('食物库'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('food-library-search')), '米饭');
    await tester.pumpAndSettle();

    // 只有主库行；目录行不存在。
    expect(find.text('米饭（自建）'), findsOneWidget);
    expect(find.text('蒸米饭'), findsNothing);
  });

  testWidgets('tapping a catalog row shows the graphical nutrition sheet', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(host(libController()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('食物库'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('food-library-search')), '米饭');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('food-library-item-cat-rice')));
    await tester.pumpAndSettle();

    // 目录条目还没导入主库：详情照样能从分片读出来（kcal 116 → 大环 + 占比），
    // 但 docs/28 §5.2 已删的份量/修订/证据三节不再渲染。
    expect(find.byKey(const Key('food-detail-sheet')), findsOneWidget);
    expect(find.byKey(const Key('food-detail-ring-kcal')), findsOneWidget);
    expect(find.text('一碗 · 150g'), findsNothing);
    expect(find.textContaining('第 1 次修订'), findsNothing);
    expect(find.textContaining('odbl-1.0'), findsNothing);
  });

  testWidgets('tapping a main-db row shows the same graphical sheet', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(host(libController()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('食物库'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('food-library-search')), '米饭');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('food-library-item-user-rice')));
    await tester.pumpAndSettle();

    // 主库条目：同一张图形化弹层（大环 + 供能占比），没有目录数据也不借。
    expect(find.byKey(const Key('food-detail-sheet')), findsOneWidget);
    expect(find.byKey(const Key('food-detail-ring-kcal')), findsOneWidget);
    expect(find.text('一碗 · 150g'), findsNothing);
    expect(find.textContaining('来源证据'), findsNothing);
  });

  testWidgets('without a detail loader rows are not tappable', (tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(host(libController(withDetails: false)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('食物库'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('food-library-search')), '米饭');
    await tester.pumpAndSettle();

    final card = tester.widget<FoodCard>(
      find.byKey(const Key('food-library-item-cat-rice')),
    );
    expect(card.onTap, isNull);
  });

  testWidgets('骨架与真行逐项同构：加载完成时列表不跳（单卡列表后同步）', (tester) async {
    // 卡片在 2026-10-06（P8a）改了首行对齐、加了环下口径行、宏量行改恒三格，
    // 骨架必须逐行跟上——行高差一点，加载完成时整列表就会跳一下。
    // Round7 阶段 3（D36）：行不再是各自的卡（整列共用一层卡面），骨架同步
    // 换成行形态 —— 这条量的是**行高**，两侧都量它。
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(width: 328, child: FoodCardSkeleton()),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final skeletonTall = tester.getSize(find.byType(FoodCardSkeleton)).height;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                width: 328,
                child: FoodCard(
                  id: 'skeleton-shape-pin',
                  name: '米饭',
                  category: FoodCategory.other,
                  kcalPer100g: 116,
                  proteinPer100g: 2.6,
                  carbsPer100g: 25.9,
                  fatPer100g: 0.3,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final rowTall = tester.getSize(find.byType(FoodCard)).height;

    expect(
      skeletonTall,
      rowTall,
      reason: '骨架行高必须与真行一致（$skeletonTall vs $rowTall）',
    );
  });
}

final class _Ids implements IdGenerator {
  int _value = 0;

  @override
  String next() => 'food-${_value++}';
}
