import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/app/design/lf_insets.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/application/food_library_controller.dart';
import 'package:localfit_ai/features/nutrition/data/catalog_search_service.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/food_record.dart';
import 'package:localfit_ai/features/nutrition/presentation/food_library_view.dart';

/// `RV4-P2-10`（`docs/57` §3 / `docs/56` R9）：**食物库页尾「导入/管理」退役**。
///
/// 根因：那两条链与设置页「添加食物数据」是同一能力的两处入口；页尾条还
/// 顺带承担了底栏预留——删它时必须把预留搬进列表末尾，否则**最后一行被
/// 底栏压住**（`nutrition_subtab_occlusion_test` 会红）。这是「改了就看不出来、
/// 但最后一行点不到」的隐蔽坑，所以必须有几何断言。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late FoodRepository foods;
  late FoodLibraryController controller;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    final clock = FixedAppClock(DateTime.utc(2026, 10, 24, 2));
    foods = FoodRepository(
      database: database,
      idGenerator: _Ids(),
      clock: clock,
    );
    controller = FoodLibraryController(
      repository: foods,
      catalogSearch: CatalogSearchService(shardPaths: const []),
    );
  });
  tearDown(() => database.close());

  Future<void> seed(int count) async {
    for (var i = 0; i < count; i++) {
      await foods.create(
        NewFood(
          name: '食物${i.toString().padLeft(2, '0')}',
          kcalPer100g: 100,
          proteinPer100g: 5,
          carbsPer100g: 10,
          fatPer100g: 3,
        ),
      );
    }
  }

  /// 宿主与 shell 同形：`Scaffold` 正文 + 贴底栏（56 占位）。
  Future<void> pumpView(WidgetTester tester, {VoidCallback? onImport}) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: FoodLibraryView(
            controller: controller,
            revision: 0,
            onImportFoods: onImport,
          ),
          bottomNavigationBar: const SizedBox(height: 56),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('页尾两条链已退役', () {
    testWidgets('三条页尾 Key 都不存在', (tester) async {
      await seed(5);
      await pumpView(tester);

      expect(
        find.byKey(const Key('food-library-footer')),
        findsNothing,
        reason: 'R9：页尾条整族退役（与设置页「添加食物数据」重复）',
      );
      expect(find.byKey(const Key('food-library-footer-import')), findsNothing);
      expect(find.byKey(const Key('food-library-footer-manage')), findsNothing);
    });

    testWidgets('页尾文案不出现（防换个 Key 又加回来）', (tester) async {
      await seed(3);
      await pumpView(tester);
      expect(find.text('导入食物数据'), findsNothing);
      expect(find.text('食物管理'), findsNothing);
    });

    testWidgets('空库态仍保留「导入食物数据」（空库时唯一自助路径）', (tester) async {
      var imports = 0;
      await pumpView(tester, onImport: () => imports++);
      // 空态行动钮在列表空态里（不在页尾条里）——删页尾不该删掉它。
      final action = find.textContaining('导入食物数据');
      expect(action, findsWidgets, reason: '真空库时导入是唯一自助路径，必须留着');
      await tester.tap(action.first);
      await tester.pumpAndSettle();
      expect(imports, 1);
    });
  });

  group('底栏预留搬到列表末尾（几何判据）', () {
    testWidgets('滚到末尾：最后一行底边不越过底栏遮挡线', (tester) async {
      await seed(12);
      await pumpView(tester);

      // 这棵树里有 3 个 Scrollable（搜索行、分类胶囊行、列表）。必须按
      // **列表自己的 Key** 找那一个，否则拖动落在胶囊行上、列表原地不动。
      final listFinder = find.byKey(const Key('food-library-list'));
      final scrollable = find.descendant(
        of: listFinder,
        matching: find.byType(Scrollable),
      );
      for (var i = 0; i < 10; i++) {
        await tester.drag(listFinder, const Offset(0, -400));
        await tester.pumpAndSettle();
      }

      final rows = find.byWidgetPredicate((widget) {
        final key = widget.key;
        return key is ValueKey<String> &&
            key.value.startsWith('food-library-item-');
      });
      expect(rows, findsWidgets, reason: '列表行必须渲染出来（否则几何判据无对象）');

      // 遮挡线 = 正文视口底边（贴底栏在它下面）。
      final viewport = tester.getRect(
        find.byKey(const Key('food-library-list')),
      );
      expect(
        tester.getRect(rows.last).bottom,
        lessThanOrEqualTo(viewport.bottom + 0.5),
        reason: '最后一行不得画到底栏遮挡线之下',
      );
      // 末尾预留必须真实存在（≥ navReserve 的量级），否则最后一行贴底栏。
      final reserve = LfInsets.navReserve(
        tester.element(scrollable.evaluate().isEmpty ? listFinder : scrollable),
      );
      expect(reserve, greaterThan(0), reason: '底栏预留必须是正的');
      expect(
        tester.getRect(rows.last).bottom,
        lessThanOrEqualTo(viewport.bottom - reserve + 1.0),
        reason: '最后一行底边应停在 `navReserve` 留白之上（实测预留 $reserve）',
      );
    });
  });
}

final class _Ids implements IdGenerator {
  int _value = 0;

  @override
  String next() => 'food-${(_value++).toString().padLeft(4, '0')}';
}
