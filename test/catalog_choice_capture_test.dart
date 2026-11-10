@Tags(['capture'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/features/ai_conversation/presentation/catalog_choice_sheet.dart';
import 'package:localfit_ai/features/nutrition/application/catalog_resolver.dart';
import 'package:localfit_ai/features/nutrition/domain/dish_record.dart';
import 'package:localfit_ai/features/nutrition/domain/food_record.dart';

import 'support/round7_render.dart';

/// 同名双库「选择卡」的实帧（2026-11-05）。不是 Android 真机截图：
/// 由 Flutter 测试引擎渲染生产弹层内容，只验证排版与信息层级。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime.utc(2026, 11, 5, 12);
  final candidates = CatalogCandidates(
    reference: '番茄炒蛋',
    foods: const [
      FoodRecord(
        id: 'food-1',
        name: '番茄炒蛋',
        kcalPer100g: 142,
        proteinPer100g: 8.4,
        carbsPer100g: 6.2,
        fatPer100g: 9.1,
        isUserCreated: false,
      ),
    ],
    dishes: [
      DishRecord(
        id: 'dish-1',
        name: '番茄炒蛋',
        mealSlot: 'lunch',
        kcal: 300,
        proteinG: 15,
        carbsG: 10,
        fatG: 21,
        servingGrams: 250,
        source: 'manual',
        createdAt: now,
        updatedAt: now,
      ),
    ],
  );

  Future<void> pump(
    WidgetTester tester, {
    required double width,
    required double scale,
  }) async {
    await tester.runAsync(loadRound7Fonts);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 1100 * scale);
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    await tester.pumpWidget(
      RepaintBoundary(
        key: round7Boundary,
        child: MaterialApp(
          theme: AppTheme.light(),
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            backgroundColor: const Color(0xFFF7F9F8),
            body: Align(
              alignment: Alignment.bottomCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: width),
                child: Card(
                  margin: const EdgeInsets.all(16),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: CatalogChoiceSheet(candidates: candidates),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('选择卡 360dp 1.0×', (tester) async {
    await pump(tester, width: 360, scale: 1.0);
    expect(find.byKey(const Key('catalog-choice-food-food-1')), findsOneWidget);
    expect(find.byKey(const Key('catalog-choice-dish-dish-1')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await captureRound7(tester, 'catalog-choice-light-360-1.0');
  });

  testWidgets('选择卡 320dp 2.0×', (tester) async {
    await pump(tester, width: 320, scale: 2.0);
    expect(find.byKey(const Key('catalog-choice-food-food-1')), findsOneWidget);
    expect(find.byKey(const Key('catalog-choice-dish-dish-1')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await captureRound7(tester, 'catalog-choice-light-320-2.0');
  });
}
