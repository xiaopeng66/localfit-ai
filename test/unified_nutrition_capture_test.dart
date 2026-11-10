@Tags(['capture'])
library;

import 'dart:convert';

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
import 'package:localfit_ai/features/nutrition/data/dish_library_repository.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/nutrition/data/supply_catalog_repository.dart';
import 'package:localfit_ai/features/nutrition/presentation/legacy_migration_sheet.dart';
import 'package:localfit_ai/features/nutrition/presentation/meal_editor_dialog.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/menu_dish_list.dart';

import 'support/round7_render.dart';

/// 统一营养主库相关新 UI 的**渲染帧**（docs/67 §5、A22）。
///
/// 捕获跑法（帧落到工作区 tmp，便于逐张目视）：
/// ```
/// LF_ROUND7_CAPTURE_DIR=E:/AI/Zcode/tmp/cap-unified \
///   flutter test --tags capture test/unified_nutrition_capture_test.dart
/// ```
/// 未设置环境变量时**仍然跑完并断言**（无 overflow、关键文案在屏），所以它同时
/// 是这几处的接线回归面。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late FoodCatalogService catalog;
  late CanteenRepository canteen;
  late SupplyCatalogRepository supplies;
  late FoodRepository foods;
  late DishLibraryRepository dishes;
  late MealRepository meals;
  late String windowId;
  final now = DateTime.utc(2026, 11, 10, 11);

  setUpAll(loadRound7Fonts);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    foods = FoodRepository(
      database: db,
      idGenerator: const UuidV7Generator(),
      clock: FixedAppClock(now),
    );
    catalog = FoodCatalogService(
      database: db,
      idGenerator: const UuidV7Generator(),
      clock: FixedAppClock(now),
    );
    canteen = CanteenRepository(
      database: db,
      idGenerator: const UuidV7Generator(),
      clock: FixedAppClock(now),
    );
    supplies = SupplyCatalogRepository(database: db);
    dishes = DishLibraryRepository(
      database: db,
      idGenerator: const UuidV7Generator(),
      clock: FixedAppClock(now),
    );
    meals = MealRepository(
      database: db,
      idGenerator: const UuidV7Generator(),
      clock: FixedAppClock(now),
    );
    final venueId = await canteen.createVenue(name: '东区食堂', campusName: '示范大学');
    windowId = await canteen.createWindow(
      venueId: venueId,
      name: '一楼快餐',
      openTime: '06:00',
      closeTime: '21:00',
    );
  });

  tearDown(() => db.close());

  Future<void> seedSupply({
    required String id,
    required String name,
    required double kcal,
    double? servingGrams,
    String status = 'known',
  }) async {
    final foodId = await catalog.createMasterFood(
      name: name,
      kcalPer100g: kcal,
      proteinPer100g: 12,
      carbsPer100g: 8,
      fatPer100g: 11,
    );
    await db
        .into(db.menuItems)
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
              servingGrams == null ? 'unknown' : status,
            ),
            servingGramsSource: Value(
              servingGrams == null ? 'legacy_unknown' : 'user_input',
            ),
          ),
        );
  }

  Future<void> pumpFrame(
    WidgetTester tester,
    Widget child, {
    required double width,
    double height = 820,
    double textScale = 1,
    ThemeData? theme,
  }) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? AppTheme.light(),
        home: RepaintBoundary(
          key: round7Boundary,
          child: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
            child: Scaffold(body: child),
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

  // 真实弹层是**可滚动**的（AppSheet）；帧捕获也照这个结构，否则 2.0 字号
  // 下底部会被固定按钮区裁掉，看起来像布局 bug。
  Widget editor() => SingleChildScrollView(
    child: MealEditorDialog(
      foodRepository: foods,
      dishRepository: dishes,
      supplyCatalog: supplies,
      localDate: '2026-11-10',
      onSubmit: (draft) async => '留在弹层（帧捕获用）',
    ),
  );

  testWidgets('帧：360dp 供应结果（份量已知）', (tester) async {
    await seedSupply(id: 's-known', name: '宫保鸡丁', kcal: 180, servingGrams: 200);
    await pumpFrame(tester, editor(), width: 360);
    await search(tester, '宫保');
    expect(tester.takeException(), isNull);
    expect(find.textContaining('180 kcal/100g'), findsWidgets);
    expect(find.textContaining('一份 200g'), findsWidgets);
    await captureRound7(tester, 'supply-row-known-360');
  });

  testWidgets('帧：360dp 供应结果（份量未知）', (tester) async {
    await seedSupply(id: 's-unknown', name: '炒面', kcal: 200);
    await pumpFrame(tester, editor(), width: 360);
    await search(tester, '炒面');
    expect(find.textContaining('每份克数未知'), findsWidgets);
    await captureRound7(tester, 'supply-row-unknown-360');
  });

  testWidgets('帧：320dp × 2.0 供应结果 + 已加入卡片', (tester) async {
    await seedSupply(
      id: 's-narrow',
      name: '招牌宫保鸡丁盖浇饭（加量）',
      kcal: 180,
      servingGrams: 250,
    );
    await pumpFrame(tester, editor(), width: 320, textScale: 2);
    await search(tester, '宫保');
    expect(tester.takeException(), isNull);
    await captureRound7(tester, 'supply-row-added-320-2x');
    await tester.tap(find.byKey(const Key('search-supply-name-s-narrow')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await captureRound7(tester, 'supply-row-added-320-2x-item');
  });

  testWidgets('帧：360dp 已加入的供应条目（每份口径）', (tester) async {
    await seedSupply(id: 's-item', name: '宫保鸡丁', kcal: 180, servingGrams: 200);
    await pumpFrame(tester, editor(), width: 360, height: 900);
    await search(tester, '宫保');
    await tester.tap(find.byKey(const Key('search-supply-name-s-item')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('360'), findsWidgets);
    await captureRound7(tester, 'supply-item-card-360');
  });

  testWidgets('帧：390dp 暗色 供应结果', (tester) async {
    await seedSupply(id: 's-dark', name: '番茄牛腩', kcal: 130, servingGrams: 300);
    await pumpFrame(
      tester,
      editor(),
      width: 390,
      textScale: 1.3,
      theme: AppTheme.dark(),
    );
    await search(tester, '番茄');
    expect(tester.takeException(), isNull);
    expect(find.textContaining('一份 300g'), findsWidgets);
    await captureRound7(tester, 'supply-row-dark-390');
  });

  testWidgets('帧：旧数据迁移记录（待补全 + 已换算）', (tester) async {
    final stamp = DateTime.utc(2026, 11, 10);
    await db
        .into(db.legacyEntityMappings)
        .insert(
          LegacyEntityMappingsCompanion.insert(
            id: 'm-pending',
            legacyKind: 'dish_library',
            legacyId: 'dish-1',
            sourceFingerprint: 'fp1',
            conversionVersion: 'legacy-nutrition-v1',
            outcome: 'needs_completion',
            originalBasis: 'perServing',
            preservedJson: jsonEncode({
              'name': '宫保鸡丁',
              'basis': 'perServing',
              'servingGrams': 100,
              'basisAssumed': true,
              'kcal': 400,
              'comment': '偏油',
            }),
            createdAt: stamp,
            updatedAt: stamp,
            reasonCode: const Value('assumed_serving'),
            reasonText: const Value('旧记录只有"一份"营养，份量是历史假设的 100g，不能据此换算每 100 g。'),
          ),
        );
    await db
        .into(db.legacyEntityMappings)
        .insert(
          LegacyEntityMappingsCompanion.insert(
            id: 'm-done',
            legacyKind: 'menu_item',
            legacyId: 'menu-1',
            sourceFingerprint: 'fp2',
            conversionVersion: 'legacy-nutrition-v1',
            outcome: 'converted',
            originalBasis: 'per100g',
            preservedJson: jsonEncode({
              'displayName': '番茄牛腩饭',
              'canteenEvidence': {'kcalPer100g': 130},
            }),
            createdAt: stamp,
            updatedAt: stamp,
            foodId: const Value('food-1'),
          ),
        );
    await pumpFrame(
      tester,
      // AppSheet 给了页边距；帧捕获补上同样的内边距，否则文字贴边。
      Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(child: LegacyMigrationSheet(database: db)),
      ),
      width: 360,
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('待补全（1）'), findsOneWidget);
    expect(find.textContaining('已换算进食物库（1）'), findsOneWidget);
    await captureRound7(tester, 'legacy-migration-360');
  });

  testWidgets('帧：菜单页三餐推荐（候选来自食堂供应）', (tester) async {
    await seedSupply(id: 's-lunch', name: '宫保鸡丁', kcal: 180, servingGrams: 200);
    await seedSupply(id: 's-rice', name: '米饭', kcal: 116, servingGrams: 220);
    await pumpFrame(
      tester,
      MenuDishList(
        repository: dishes,
        mealRepository: meals,
        supplyCatalog: supplies,
        now: now,
        onAddToMeal: (_, {slotOverride}) async {},
        onOpenCanteen: () {},
      ),
      width: 360,
      height: 900,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('宫保鸡丁'), findsWidgets);
    await captureRound7(tester, 'menu-supply-cards-360');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
