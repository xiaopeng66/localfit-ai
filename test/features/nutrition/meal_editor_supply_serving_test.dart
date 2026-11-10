import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart';
import 'package:localfit_ai/features/nutrition/application/food_catalog_service.dart';
import 'package:localfit_ai/features/nutrition/application/nutrition_math.dart';
import 'package:localfit_ai/features/nutrition/data/dish_library_repository.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/data/supply_catalog_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';
import 'package:localfit_ai/features/nutrition/presentation/meal_editor_dialog.dart';

/// 食堂供应在记餐编辑器里的口径（docs/67 §4.2、A03/A07/A22）。
///
/// * 选中供应 = 记 **1 份**，克数来自该供应自己的每份克数；
/// * 份量未知的供应不能按份记（不补 100g），提示去补份量或按克记；
/// * 每 100g 与每份**分开标注**；320dp + 2.0 字号不溢出。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase database;
  late FoodRepository foods;
  late DishLibraryRepository dishes;
  late CanteenRepository canteen;
  late SupplyCatalogRepository supplies;
  late FoodCatalogService catalog;
  late String windowId;
  final now = DateTime.utc(2026, 11, 9, 4);

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    foods = FoodRepository(
      database: database,
      idGenerator: _Ids(),
      clock: FixedAppClock(now),
    );
    dishes = DishLibraryRepository(
      database: database,
      idGenerator: _Ids(),
      clock: FixedAppClock(now),
    );
    catalog = FoodCatalogService(
      database: database,
      idGenerator: _Ids(),
      clock: FixedAppClock(now),
    );
    canteen = CanteenRepository(
      database: database,
      idGenerator: _Ids(),
      clock: FixedAppClock(now),
    );
    supplies = SupplyCatalogRepository(database: database);
    final venueId = await canteen.createVenue(name: '东区食堂', campusName: '示范大学');
    windowId = await canteen.createWindow(
      venueId: venueId,
      name: '一楼快餐',
      openTime: '11:00',
      closeTime: '13:30',
    );
  });

  tearDown(() => database.close());

  Future<void> seedSupply({
    required String id,
    required String name,
    required double kcal,
    required double? servingGrams,
  }) async {
    final foodId = await catalog.createMasterFood(
      name: name,
      kcalPer100g: kcal,
      proteinPer100g: 10,
      carbsPer100g: 20,
      fatPer100g: 8,
    );
    await database
        .into(database.menuItems)
        .insert(
          MenuItemsCompanion.insert(
            id: id,
            serviceId: windowId,
            displayName: name,
            createdAt: now,
            updatedAt: now,
            foodId: Value(foodId),
            servingGrams: Value(servingGrams),
            servingGramsStatus: Value(
              servingGrams == null ? 'unknown' : 'known',
            ),
            servingGramsSource: Value(
              servingGrams == null ? 'legacy_unknown' : 'user_input',
            ),
          ),
        );
  }

  Future<void> pumpEditor(
    WidgetTester tester, {
    Size size = const Size(900, 1800),
    double textScale = 1,
    ThemeData? theme,
    void Function(MealDraft draft)? onSubmit,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? AppTheme.light(),
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            body: SingleChildScrollView(
              child: MealEditorDialog(
                foodRepository: foods,
                dishRepository: dishes,
                supplyCatalog: supplies,
                localDate: '2026-11-09',
                onSubmit: (draft) async {
                  onSubmit?.call(draft);
                  return '留在弹层（测试只看 draft）';
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> search(WidgetTester tester, String query) async {
    await tester.enterText(find.byKey(const Key('meal-food-search')), query);
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('选中供应：记 1 份，克数 = 该供应每份克数，营养 = 每100g × 克数', (tester) async {
    await seedSupply(
      id: 'supply-gb',
      name: '宫保鸡丁',
      kcal: 180,
      servingGrams: 200,
    );
    MealDraft? captured;
    await pumpEditor(tester, onSubmit: (draft) => captured = draft);

    await search(tester, '宫保');
    expect(
      find.byKey(const Key('search-supply-name-supply-gb')),
      findsOneWidget,
      reason: '供应必须出现在记餐搜索里，且带自己的 id',
    );
    // 行内把"每 100g"与"一份"分开写。
    expect(find.textContaining('180 kcal/100g'), findsWidgets);

    await tester.tap(find.byKey(const Key('search-supply-name-supply-gb')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('meal-save')));
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    final item = captured!.items.single;
    expect(item.supplyId, 'supply-gb');
    expect(item.sourceType, 'menu_item');
    expect(item.servings, 1);
    expect(item.servingGrams, 200);
    expect(item.grams, 200);
    expect(item.nutrition.kcal, closeTo(360, 1e-9));
    expect(NutritionMath.resolveGrams(servings: 0.5, servingGrams: 200), 100);
  });

  testWidgets('份量未知的供应：不按份记、不补 100g，给出可行动提示', (tester) async {
    await seedSupply(
      id: 'supply-unknown',
      name: '炒面',
      kcal: 200,
      servingGrams: null,
    );
    MealDraft? captured;
    await pumpEditor(tester, onSubmit: (draft) => captured = draft);

    await search(tester, '炒面');
    expect(find.textContaining('每份克数未知'), findsWidgets);

    await tester.tap(
      find.byKey(const Key('search-supply-name-supply-unknown')),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('还没有可信的每份克数'),
      findsWidgets,
      reason: '必须说明为什么不能按份记',
    );
    // 没有条目被加进来：保存按钮即使点了也没有 draft items。
    await tester.tap(find.byKey(const Key('meal-save')));
    await tester.pumpAndSettle();
    expect(captured, isNull, reason: '空餐不该产出 draft');
  });

  testWidgets('A22 320dp + 2.0 字号：供应结果行不溢出', (tester) async {
    await seedSupply(
      id: 'supply-narrow',
      name: '招牌宫保鸡丁盖浇饭（大份）',
      kcal: 180,
      servingGrams: 250,
    );
    await pumpEditor(tester, size: const Size(320, 640), textScale: 2.0);
    await search(tester, '宫保');
    expect(
      tester.takeException(),
      isNull,
      reason: '320dp + 2.0 字号下供应行不得 overflow',
    );
    expect(
      find.byKey(const Key('search-supply-name-supply-narrow')),
      findsOneWidget,
    );
  });

  for (final width in const [320.0, 360.0, 390.0]) {
    testWidgets('A22 ${width.toInt()}dp + 2.0 字号：供应行与已加卡片都不溢出', (tester) async {
      await seedSupply(
        id: 'supply-wide',
        name: '招牌宫保鸡丁盖浇饭（加量）',
        kcal: 180,
        servingGrams: 250,
      );
      await pumpEditor(tester, size: Size(width, 720), textScale: 2.0);
      await search(tester, '宫保');
      expect(tester.takeException(), isNull, reason: '结果行不得 overflow');

      await tester.tap(find.byKey(const Key('search-supply-name-supply-wide')));
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason: '已加入项卡片（名称 + 克数 + 营养）也不得 overflow',
      );
      expect(find.byKey(const Key('meal-save')), findsOneWidget);
    });
  }

  testWidgets('A22 读屏：供应结果行有可读语义标签与按钮角色', (tester) async {
    await seedSupply(
      id: 'supply-a11y',
      name: '番茄牛腩',
      kcal: 130,
      servingGrams: 300,
    );
    final handle = tester.ensureSemantics();
    await pumpEditor(tester);

    await search(tester, '番茄');
    expect(
      find.bySemanticsLabel('添加食堂供应 番茄牛腩（东区食堂 · 一楼快餐）'),
      findsOneWidget,
      reason: '读屏要能说清"这是哪个窗口的一份"，不是一个裸名字',
    );
    expect(
      find.bySemanticsLabel('食堂'),
      findsNothing,
      reason: '来源标是视觉件，不该被读两遍（行内已 ExcludeSemantics）',
    );
    // SemanticsHandle 必须在用例体内释放（测试框架在 tearDown 之前校验）。
    handle.dispose();
  });

  testWidgets('A22 缺图降级：供应没有照片时仍可选中并保存', (tester) async {
    await seedSupply(
      id: 'supply-nophoto',
      name: '无图菜品',
      kcal: 90,
      servingGrams: 150,
    );
    MealDraft? captured;
    await pumpEditor(tester, onSubmit: (draft) => captured = draft);
    await search(tester, '无图');
    await tester.tap(
      find.byKey(const Key('search-supply-name-supply-nophoto')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('meal-save')));
    await tester.pumpAndSettle();
    expect(captured, isNotNull, reason: '缺图不阻断记餐');
    expect(captured!.items.single.grams, 150);
  });

  testWidgets('A22 暗色主题：供应结果行与状态文案可读', (tester) async {
    await seedSupply(
      id: 'supply-dark',
      name: '番茄牛腩',
      kcal: 130,
      servingGrams: 300,
    );
    await pumpEditor(tester, theme: AppTheme.dark());
    await search(tester, '番茄');
    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const Key('search-supply-name-supply-dark')),
      findsOneWidget,
    );
    expect(find.textContaining('一份 300g'), findsWidgets);
  });
}

final class _Ids implements IdGenerator {
  int value = 0;

  @override
  String next() => 'id-${value++}';
}
