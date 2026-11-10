import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart';
import 'package:localfit_ai/features/nutrition/application/catalog_resolver.dart';
import 'package:localfit_ai/features/nutrition/application/food_catalog_service.dart';
import 'package:localfit_ai/features/nutrition/data/dish_library_repository.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/food_record.dart';
import 'package:localfit_ai/features/nutrition/data/supply_catalog_repository.dart';
import 'package:localfit_ai/features/ai_conversation/presentation/catalog_choice_sheet.dart';

/// 同名候选选择卡（docs/67 §6.4、D11）。
///
/// 一个名字同时命中主食物与食堂供应时，用户必须能挑"按哪一条记"：
/// * 供应行要带**窗口**和**份量状态**（每 100g 与每份分开）；
/// * 选中供应回 `[canteen-dish:id]`（不是 food/dish）；
/// * 候选清单本身来自 `CatalogResolver`，`resolveCatalogCandidates` 不能
///   把供应丢掉（旧实现只传 foods/dishes，供应永远选不到）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late FoodRepository foods;
  late DishLibraryRepository dishes;
  late CanteenRepository canteen;
  late SupplyCatalogRepository supplies;
  late FoodCatalogService catalog;
  late String windowId;
  final now = DateTime.utc(2026, 11, 9, 12);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    foods = FoodRepository(
      database: db,
      idGenerator: _Ids('food'),
      clock: FixedAppClock(now),
    );
    dishes = DishLibraryRepository(
      database: db,
      idGenerator: _Ids('dish'),
      clock: FixedAppClock(now),
    );
    catalog = FoodCatalogService(
      database: db,
      idGenerator: _Ids('master'),
      clock: FixedAppClock(now),
    );
    canteen = CanteenRepository(
      database: db,
      idGenerator: _Ids('canteen'),
      clock: FixedAppClock(now),
    );
    supplies = SupplyCatalogRepository(database: db);
    final venueId = await canteen.createVenue(name: '东区食堂', campusName: '示范大学');
    windowId = await canteen.createWindow(
      venueId: venueId,
      name: '一楼快餐',
      openTime: '11:00',
      closeTime: '13:30',
    );
  });

  tearDown(() => db.close());

  CatalogResolver resolver() =>
      CatalogResolver(foods: foods, dishes: dishes, supplies: supplies);

  /// 打开真正的选择卡（走 `AppSheet`），并把 `pop` 的返回值捕获下来。
  Future<void> openSheet(
    WidgetTester tester,
    CatalogCandidates candidates, {
    required void Function(CatalogPick?) onPicked,
  }) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              key: const Key('open-catalog-choice'),
              onPressed: () async {
                final pick = await showCatalogChoiceSheet(
                  context,
                  candidates: candidates,
                );
                onPicked(pick);
              },
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-catalog-choice')));
    await tester.pumpAndSettle();
  }

  /// 只渲染卡片本体（不需要 Navigator 的场景）。
  Future<void> pumpSheet(
    WidgetTester tester,
    CatalogCandidates candidates,
  ) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: CatalogChoiceSheet(candidates: candidates)),
      ),
    );
    await tester.pumpAndSettle();
  }

  test('解析：同名主食物 + 食堂供应 → CatalogAmbiguous 带上供应候选', () async {
    final masterId = await catalog.createMasterFood(
      name: '宫保鸡丁',
      kcalPer100g: 180,
      proteinPer100g: 12,
      carbsPer100g: 8,
      fatPer100g: 11,
    );
    await canteen.createDish(
      windowId: windowId,
      name: '宫保鸡丁',
      foodId: masterId,
      servingGrams: 200,
    );
    await db
        .into(db.menuItems)
        .insert(
          MenuItemsCompanion.insert(
            id: 'supply-x',
            serviceId: windowId,
            displayName: '宫保鸡丁',
            createdAt: now,
            updatedAt: now,
            foodId: Value(masterId),
            servingGrams: const Value(200),
            servingGramsStatus: const Value('known'),
            servingGramsSource: const Value('user_input'),
          ),
        );

    final resolution = await resolver().resolve('宫保鸡丁');
    expect(resolution, isA<CatalogAmbiguous>());
    final ambiguous = resolution as CatalogAmbiguous;
    expect(ambiguous.foods.map((row) => row.id), contains(masterId));
    expect(
      ambiguous.supplies.map((item) => item.id),
      contains('supply-x'),
      reason: '供应必须进候选，否则用户永远选不到"哪个窗口的一份"',
    );
  });

  testWidgets('选择卡：供应行带窗口与份量，选中回 supply 类型', (tester) async {
    final masterId = await catalog.createMasterFood(
      name: '宫保鸡丁',
      kcalPer100g: 180,
      proteinPer100g: 12,
      carbsPer100g: 8,
      fatPer100g: 11,
    );
    await db
        .into(db.menuItems)
        .insert(
          MenuItemsCompanion.insert(
            id: 'supply-x',
            serviceId: windowId,
            displayName: '宫保鸡丁（一窗口）',
            createdAt: now,
            updatedAt: now,
            foodId: Value(masterId),
            servingGrams: const Value(200),
            servingGramsStatus: const Value('known'),
            servingGramsSource: const Value('user_input'),
          ),
        );
    final candidates = await resolver().resolve('宫保鸡丁');
    final ambiguous = candidates as CatalogAmbiguous;

    CatalogPick? pick;
    await openSheet(
      tester,
      CatalogCandidates(
        reference: ambiguous.reference,
        foods: ambiguous.foods,
        dishes: ambiguous.dishes,
        supplies: ambiguous.supplies,
      ),
      onPicked: (value) => pick = value,
    );
    // 文案与结构都要点明"这是哪个窗口的一份"。
    expect(find.textContaining('按食堂供应记'), findsOneWidget);
    expect(find.textContaining('东区食堂 · 一楼快餐'), findsOneWidget);
    expect(find.textContaining('180 kcal/100g'), findsWidgets);
    expect(find.textContaining('每份 200g'), findsOneWidget);

    await tester.tap(find.byKey(const Key('catalog-choice-supply-supply-x')));
    await tester.pumpAndSettle();
    expect(pick, isNotNull);
    expect(pick!.kind, CatalogPickKind.supply);
    expect(pick!.id, 'supply-x');
    expect(pick!.label, '宫保鸡丁（一窗口）');
  });

  testWidgets('无供应的同名歧义：不渲染供应分组（不占位）', (tester) async {
    await foods.create(
      const NewFood(
        name: '米饭',
        kcalPer100g: 116,
        proteinPer100g: 2.6,
        carbsPer100g: 25.9,
        fatPer100g: 0.3,
      ),
    );
    await dishes.create(
      DishDraft(
        name: '米饭',
        mealSlot: 'lunch',
        kcal: 200,
        proteinG: 4,
        carbsG: 40,
        fatG: 1,
        source: 'manual',
        servingGrams: 200,
      ),
    );
    final resolution = await resolver().resolve('米饭') as CatalogAmbiguous;
    expect(resolution.supplies, isEmpty);

    await pumpSheet(
      tester,
      CatalogCandidates(
        reference: resolution.reference,
        foods: resolution.foods,
        dishes: resolution.dishes,
        supplies: resolution.supplies,
      ),
    );
    expect(find.textContaining('按食堂供应记'), findsNothing);
    expect(find.byKey(const Key('catalog-choice-food-food-0')), findsOneWidget);
  });
}

final class _Ids implements IdGenerator {
  _Ids(this.prefix);
  final String prefix;
  int value = 0;

  @override
  String next() => '$prefix-${value++}';
}
