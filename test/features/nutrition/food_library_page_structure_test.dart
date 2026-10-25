import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/application/food_library_controller.dart';
import 'package:localfit_ai/features/nutrition/data/catalog_search_service.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/food_category.dart';
import 'package:localfit_ai/features/nutrition/presentation/food_library_view.dart';

/// 阶段 3 步骤 2（食物库）**A 结构**的判据（对应证据文件 D31–D43）。
///
/// 本文件只管 3-2a 的三件事：
///  * D34 分类筛选的**数据面**（仓储 `count/page` 的可选分类 + 控制器主库行
///    必须带落库分类——旧实现下「按分类筛」会把用户自己导入的主库整个筛空）；
///  * D33 A `.food-category-row` 的**形态**（横滑胶囊、选中 brandSoft/brand-strong
///    + w600），标签集合按本仓真实分类域（全部 + 十档），不是 A 的 8 枚演示标签；
///  * 点胶囊真的换列表（行为的落点，不是只有壳）。
///
/// 判据一律**先红**：这些件与参数在本步之前都不存在。
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
    clock: FixedAppClock(DateTime.utc(2026, 10, 14)),
  );

  FoodLibraryController controller() => FoodLibraryController(
    repository: repo(),
    catalogSearch: CatalogSearchService(shardPaths: const []),
  );

  /// 7 条：主食 ×3（含一条自建）、蛋白质 ×2（一条名字带「鸡」）、
  /// **没落库分类** ×1、**落库串不是合法枚举 id** ×1（目录分片导入的原串）。
  Future<void> seedCategories() async {
    final now = DateTime.utc(2026, 10, 14);
    FoodsCompanion row(
      String id,
      String name, {
      String? category,
      bool userCreated = false,
    }) => FoodsCompanion.insert(
      id: id,
      name: name,
      kcalPer100g: 100,
      proteinPer100g: 1,
      carbsPer100g: 1,
      fatPer100g: 1,
      source: 'seed',
      createdAt: now,
      updatedAt: now,
      isUserCreated: Value(userCreated),
      category: Value(category),
    );
    await database.batch((batch) {
      batch.insertAll(database.foods, [
        row('staple-0', '米饭', category: 'staple'),
        row('staple-1', '面条', category: 'staple'),
        row('staple-2', '馒头（自建）', category: 'staple', userCreated: true),
        row('protein-0', '鸡胸肉', category: 'protein'),
        row('protein-1', '牛肉', category: 'protein'),
        row('nocat-0', '没落库分类的食物'),
        row('raw-0', '上游原串分类的食物', category: 'noodle'),
      ]);
    });
  }

  Widget host(
    FoodLibraryController controller, {
    double width = 360,
    VoidCallback? onImportFoods,
  }) => MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: width,
        height: 800,
        child: FoodLibraryView(
          controller: controller,
          revision: 0,
          onImportFoods: onImportFoods,
        ),
      ),
    ),
  );

  Future<void> pumpHost(
    WidgetTester tester,
    FoodLibraryController controller, {
    double width = 360,
    VoidCallback? onImportFoods,
  }) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      host(controller, width: width, onImportFoods: onImportFoods),
    );
    await tester.pumpAndSettle();
  }

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
        (element) => ((element.widget.key! as ValueKey<String>).value)
            .substring('food-library-item-'.length),
      )
      .toList(growable: false);

  group('仓储分类筛选（D34）', () {
    test('count/page 带分类只回该分类；不带分类与现状一字不差', () async {
      await seedCategories();
      final repository = repo();

      // 不带分类：仍是全库实数（滑条长度与「全部」读它，不许变）。
      expect(await repository.count(), 7);
      expect((await repository.page(offset: 0, limit: 50)), hasLength(7));

      expect(await repository.count(category: FoodCategory.staple), 3);
      final staples = await repository.page(
        offset: 0,
        limit: 50,
        category: FoodCategory.staple,
      );
      // 排序是既有的 `is_user_created DESC, name ASC, id ASC`：自建行在前，
      // 其余按名称——**不是** id 序（首版断言按 id 写，被真实输出纠正）。
      expect(staples.map((food) => food.id), [
        'staple-2',
        'staple-0',
        'staple-1',
      ]);

      // 分类与查询词同时生效（LIKE + category）。
      final queryAndCategory = await repository.page(
        query: '鸡',
        offset: 0,
        limit: 50,
        category: FoodCategory.protein,
      );
      expect(queryAndCategory.map((food) => food.id), ['protein-0']);
    });

    test('落库串不是合法枚举 id 的行不进任何分类，但仍在「全部」里', () async {
      await seedCategories();
      final repository = repo();

      // `noodle` 不是本仓枚举 id（目录分片导入的原串）⇒ 不猜、不回落。
      expect(await repository.count(category: FoodCategory.staple), 3);
      expect(await repository.count(category: FoodCategory.other), 0);
      expect(await repository.count(category: FoodCategory.protein), 2);

      final all = await repository.page(offset: 0, limit: 50);
      expect(all.map((food) => food.id), contains('raw-0'));
      expect(all.map((food) => food.id), contains('nocat-0'));
    });
  });

  group('控制器分类（D34：主库行必须带落库分类）', () {
    test('浏览路径的分类筛选过主库（旧实现把主库行整个筛空）', () async {
      await seedCategories();
      final c = controller();

      expect(await c.count('', category: FoodCategory.staple), 3);
      final page = await c.page(
        '',
        offset: 0,
        limit: 50,
        category: FoodCategory.staple,
      );
      // 同上：自建行在前（`is_user_created DESC, name ASC, id ASC`）。
      expect(page.map((item) => item.id), ['staple-2', 'staple-0', 'staple-1']);
      // 主库行必须带上落库分类（`_fromMainRow` 的洞）：否则上面的断言只能
      // 靠目录分片行通过，而用户自己导入的 5 万条全是主库行。
      expect(page.every((item) => item.category == 'staple'), isTrue);
    });

    test('合并搜索路径：主库行与目录行按同一判据归一（合法 id 才留下）', () async {
      await seedCategories();
      final c = controller();

      final items = await c.page(
        '鸡',
        offset: 0,
        limit: 50,
        category: FoodCategory.protein,
      );
      expect(items.map((item) => item.id), ['protein-0']);
    });
  });

  group('A 分类胶囊行（D33：形态搬 A、标签用真实分类域）', () {
    testWidgets('全部 + 十档；选中 = brandSoft 底 / brand-strong 字 / w600', (
      tester,
    ) async {
      await seedCategories();
      await pumpHost(tester, controller());

      expect(
        find.byKey(const Key('food-library-category-row')),
        findsOneWidget,
        reason: 'A `app.js:201` 的 `.food-category-row`',
      );
      expect(find.byKey(const Key('food-category-chip-all')), findsOneWidget);
      for (final category in FoodCategory.values) {
        expect(
          find.byKey(Key('food-category-chip-${category.id}')),
          findsOneWidget,
          reason: '十档一档不落（A 的 8 枚演示标签不覆盖本仓分类域）',
        );
      }

      // 默认选中「全部」：A `.food-category-row [aria-pressed="true"]`
      // （styles.css:271）= brand-soft 底 + brand-strong 字 + w600（polish.css:45）。
      final all = tester.widget<TextButton>(
        find.byKey(const Key('food-category-chip-all')),
      );
      final brightness = Theme.of(
        tester.element(find.byKey(const Key('food-category-chip-all'))),
      ).brightness;
      expect(
        all.style?.backgroundColor?.resolve(const {}),
        LfColors.brandSoft(brightness),
      );
      expect(
        all.style?.foregroundColor?.resolve(const {}),
        LfColors.mintText(brightness),
      );
      expect(
        all.style?.textStyle?.resolve(const {})?.fontWeight,
        FontWeight.w600,
      );

      // 未选中一枚：透明底 + muted 字（A polish 把描边也设为透明）。
      final staple = tester.widget<TextButton>(
        find.byKey(const Key('food-category-chip-staple')),
      );
      expect(
        staple.style?.backgroundColor?.resolve(const {}),
        Colors.transparent,
      );
      expect(
        staple.style?.foregroundColor?.resolve(const {}),
        isNot(LfColors.mintText(brightness)),
      );
    });

    testWidgets('点「主食」只列该分类的行，点回「全部」恢复', (tester) async {
      await seedCategories();
      await pumpHost(tester, controller());
      expect(visibleIds(tester), hasLength(7));

      await tester.tap(find.byKey(const Key('food-category-chip-staple')));
      await tester.pumpAndSettle();
      expect(visibleIds(tester), ['staple-2', 'staple-0', 'staple-1']);

      await tester.tap(find.byKey(const Key('food-category-chip-all')));
      await tester.pumpAndSettle();
      expect(visibleIds(tester), hasLength(7));
    });

    testWidgets('该分类一条都没有 → 空态（不是空白列表）', (tester) async {
      await seedCategories();
      await pumpHost(tester, controller());

      // 「饮品」是第 7 枚，360dp 下在视口右缘之外（横滑行的必然）：先滚到
      // 可见再点，否则 tap 的落点在 root 之外、点了个空（首跑的真实输出：
      // `derived an Offset (Offset(400.0, 92.0)) that would not hit test ...
      // outside the bounds of the root of the render tree, Size(360.0, 800.0)`）。
      final beverage = find.byKey(const Key('food-category-chip-beverage'));
      await tester.ensureVisible(beverage);
      await tester.pumpAndSettle();
      await tester.tap(beverage);
      await tester.pumpAndSettle();
      expect(visibleIds(tester), isEmpty);
    });

    testWidgets('320dp 下 11 枚不换行：行高 = 44（A 的胶囊档）、横向可滚', (tester) async {
      await seedCategories();
      await pumpHost(tester, controller(), width: 320);

      final row = tester.getRect(
        find.byKey(const Key('food-library-category-row')),
      );
      // 44 = A `.food-category-row button{min-height:44px}`（styles.css:271）；
      // 明写而不是读 `LfDimens.minTouchTarget`：这条断言钉的就是「用的是 A 的
      // 44 档」，读同一个常量会让断言跟着实现一起漂。
      expect(row.height, closeTo(44, 0.5));
      // 全部 11 枚的自然宽必然超过 320；行内是横向滚动而不是折行
      // （折行的话行高会是 44 的两倍以上）。
      final chip = tester.getRect(
        find.byKey(const Key('food-category-chip-condiment')),
      );
      expect(chip.height, closeTo(44, 0.5));
      expect(row.height, lessThan(44 * 2));
    });
  });

  group('A 结果头与空态（D32/D41）', () {
    testWidgets('结果头 = 「N 种食物」+「kcal / 100g」两端（A .section-title.with-link）', (
      tester,
    ) async {
      await seedCategories();
      await pumpHost(tester, controller());

      final count = find.byKey(const Key('food-library-count'));
      // 旧措辞「全部 N 条 / 搜到 N 条」退役（A 只有一种：`app.js:195`）。
      expect(tester.widget<Text>(count).data, '7 种食物');
      final unit = find.text('kcal / 100g');
      expect(unit, findsOneWidget);

      // 两端：左端贴页边距 16、右端贴另一侧 16（A 的 `justify-content:
      // space-between` + `.page` 页边距）。量几何而不是只看「在不在」。
      expect(tester.getRect(count).left, closeTo(16, 0.5));
      expect(tester.getRect(unit).right, closeTo(360 - 16, 0.5));
      // 同一行的两端（A 是单行 flex，不是两行）。
      expect(
        tester.getRect(unit).center.dy,
        closeTo(tester.getRect(count).center.dy, 0.5),
      );
    });

    testWidgets('筛到 0 行：结果头照画「0 种食物」（A 字面），空态说不打结果头', (tester) async {
      await seedCategories();
      await pumpHost(tester, controller());

      final beverage = find.byKey(const Key('food-category-chip-beverage'));
      await tester.ensureVisible(beverage);
      await tester.pumpAndSettle();
      await tester.tap(beverage);
      await tester.pumpAndSettle();

      // A 的标题行无条件渲染（`rows.length` 为 0 时写 0）；旧实现的
      // 「0 条就不画计数行」随本步退役。
      expect(
        tester.widget<Text>(find.byKey(const Key('food-library-count'))).data,
        '0 种食物',
      );
      expect(
        find.text('没有找到这类食物'),
        findsOneWidget,
        reason: 'A `app.js:198` 的筛选空态标题',
      );
      expect(find.text('试试其他名称或分类。'), findsOneWidget);
      expect(find.byKey(const Key('food-empty-clear')), findsOneWidget);
    });

    testWidgets('「清除筛选」真的清到底：查询词与分类都复位（搜索框也空）', (tester) async {
      await seedCategories();
      await pumpHost(tester, controller());

      await tester.enterText(
        find.byKey(const Key('food-library-search')),
        '米饭',
      );
      await tester.pumpAndSettle();
      final beverage = find.byKey(const Key('food-category-chip-beverage'));
      await tester.ensureVisible(beverage);
      await tester.pumpAndSettle();
      await tester.tap(beverage);
      await tester.pumpAndSettle();
      expect(visibleIds(tester), isEmpty, reason: '两个条件同时生效才是 0 行');

      await tester.tap(find.byKey(const Key('food-empty-clear')));
      await tester.pumpAndSettle();

      // 查询词清空要连**输入框里的字**一起清（不然框里还写着「米饭」，
      // 列表却是全部——那是最容易骗过用户的一种不一致）。
      final field = tester.widget<TextField>(
        find.byKey(const Key('food-library-search')),
      );
      expect(field.controller?.text ?? '', isEmpty);
      expect(
        tester
            .widget<TextButton>(find.byKey(const Key('food-category-chip-all')))
            .style
            ?.backgroundColor
            ?.resolve(const {}),
        isNot(Colors.transparent),
        reason: '分类回到「全部」（选中 = 有底色）',
      );
      expect(visibleIds(tester), hasLength(7));
      expect(
        tester.widget<Text>(find.byKey(const Key('food-library-count'))).data,
        '7 种食物',
      );
    });

    testWidgets('空库（没查词没筛选）走 A 的空库文案，不是「没有找到」', (tester) async {
      var imports = 0;
      await pumpHost(tester, controller(), onImportFoods: () => imports++);

      expect(find.text('食物库还是空的'), findsOneWidget);
      expect(find.text('新安装时为空库，可导入自己的食物数据。'), findsOneWidget);
      // A 这里给的是「导入示例食物」——本仓不塞演示数据（D41）。行动钮留着
      // （3-2c 落点）：点了进的是**真实**导入通路，不是演示食物。
      expect(find.byKey(const Key('food-empty-clear')), findsNothing);
      final action = find.byKey(const Key('food-empty-import'));
      expect(action, findsOneWidget);
      await tester.tap(action);
      await tester.pump();
      expect(imports, 1);
    });

    testWidgets('空库态没接导入通路时不摆死钮', (tester) async {
      await pumpHost(tester, controller());

      expect(find.text('食物库还是空的'), findsOneWidget);
      expect(find.byKey(const Key('food-empty-import')), findsNothing);
    });
  });
}

class _Ids implements IdGenerator {
  var _value = 0;

  @override
  String next() => 'test-${(_value++).toString().padLeft(4, '0')}';
}
