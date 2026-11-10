import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/data/dish_library_repository.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';
import 'package:localfit_ai/features/nutrition/presentation/meal_editor_dialog.dart';

/// 菜品→一餐的份量契约（2026-11-04）。
///
/// 菜品库的 `kcal/protein/carbs/fat` 是**每份**值；`servingGrams` 是这一份
/// 多少克。加入一餐时必须按「目标克数 / 这份克数」缩放，**不能**再乘一次
/// `servingGrams/100`——那会把 268 kcal/份 算成 804 kcal。
/// 同时，餐条目必须保留 `sourceType=dish` / `sourceId`，不能退化成 manual。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase database;
  late FoodRepository foods;
  late DishLibraryRepository dishes;
  final now = DateTime.utc(2026, 11, 4, 12);

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
    await database
        .into(database.dishLibrary)
        .insert(
          DishLibraryCompanion.insert(
            id: 'dish-hg',
            name: '红油豆腐粉',
            mealSlot: '午餐',
            kcal: 268,
            proteinG: 8,
            carbsG: 32,
            fatG: 12,
            servingGrams: const Value(300),
            source: 'manual',
            createdAt: now,
            updatedAt: now,
          ),
        );
  });

  tearDown(() => database.close());

  testWidgets('按菜品加入一餐：不重复乘份量，且保留 dish 来源', (tester) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    MealDraft? captured;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: MealEditorDialog(
              foodRepository: foods,
              dishRepository: dishes,
              localDate: '2026-11-04',
              onSubmit: (draft) async {
                captured = draft;
                return '留在弹层（测试只看 draft）';
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.enterText(find.byKey(const Key('meal-food-search')), '红油');
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byKey(const Key('search-dish-name-dish-hg')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('meal-save')));
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    final item = captured!.items.single;
    expect(item.grams, 300);
    expect(item.nutrition.kcal, 268, reason: '每份 268 kcal，不是 268×300/100');
    expect(item.nutrition.proteinGrams, 8);
    expect(item.nutrition.carbsGrams, 32);
    expect(item.nutrition.fatGrams, 12);
    expect(item.sourceType, 'dish');
    expect(item.sourceId, 'dish-hg');
  });
}

final class _Ids implements IdGenerator {
  int value = 0;

  @override
  String next() => 'id-${value++}';
}
