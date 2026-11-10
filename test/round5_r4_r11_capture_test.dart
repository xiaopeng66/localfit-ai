@Tags(['capture'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/features/campus_menus/presentation/canteen_dish_actions_sheet.dart';
import 'package:localfit_ai/features/nutrition/application/build_daily_meal_recommendation.dart';
import 'package:localfit_ai/features/nutrition/domain/dish_record.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/daily_meal_set_card.dart';

import 'support/round7_render.dart';

/// R-4（推荐小图卡 + 点图放大）与 R-11（食堂菜操作弹窗重设计）取帧。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('推荐小图卡 + 菜品操作弹窗（320×2.0 / 412×1.0）', (tester) async {
    await tester.runAsync(loadRound7Fonts);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    // 生成一张 64×64 的本地菜图（推荐卡缩略图用）。
    final dir = Directory.systemTemp.createTempSync('lf-r4-img');
    final file = File('${dir.path}/dish.png');
    await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 64, 64),
        Paint()..color = const Color(0xFFE8A33D),
      );
      canvas.drawCircle(
        const Offset(32, 32),
        16,
        Paint()..color = const Color(0xFF7A4A12),
      );
      final image = await recorder.endRecording().toImage(64, 64);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
    });

    final now = DateTime.utc(2026, 10, 29, 8);
    DishRecord dish(String id, String name, {double kcal = 220}) => DishRecord(
      id: id,
      name: name,
      mealSlot: 'lunch',
      kcal: kcal,
      proteinG: 12,
      carbsG: 30,
      fatG: 8,
      source: 'canteen',
      imagePath: file.path,
      servingGrams: 100,
      basisAssumed: true,
      createdAt: now,
      updatedAt: now,
    );

    Future<void> pumpFrame(
      double width,
      double height,
      double textScale,
      Widget child,
    ) async {
      tester.view.devicePixelRatio = 2;
      tester.view.physicalSize = Size(width * 2, height * 2);
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(
            size: Size(width, height),
            textScaler: TextScaler.linear(textScale),
          ),
          child: RepaintBoundary(
            key: round7Boundary,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: round7CaptureTheme(AppTheme.light()),
              home: Scaffold(
                body: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    final meals = [
      MealRecommendation(
        slot: MealSlot.breakfast,
        state: MealRecommendationState.recommended,
        reason: '蛋白够、热量不高，早餐轻负担。',
        primary: dish('d1', '水煮蛋'),
        budgetKcal: 500,
      ),
      MealRecommendation(
        slot: MealSlot.lunch,
        state: MealRecommendationState.recommended,
        reason: '主食 + 蛋白 + 蔬菜，本餐预算内。',
        primary: dish('d2', '番茄牛腩饭', kcal: 620),
        budgetKcal: 700,
      ),
      MealRecommendation(
        slot: MealSlot.dinner,
        state: MealRecommendationState.recommended,
        reason: '清淡为主，留出夜间余量。',
        primary: dish('d3', '清蒸鱼', kcal: 320),
        budgetKcal: 600,
      ),
    ];
    final views = {
      for (final meal in meals)
        meal.slot: DailyMealSetSlotView(
          candidates: [meal.primary!],
          displayed: meal.primary,
          displayedIndex: 0,
        ),
    };

    for (final (tag, w, ts) in const [
      ('320x2', 320.0, 2.0),
      ('412x1', 412.0, 1.0),
    ]) {
      await pumpFrame(
        w,
        900,
        ts,
        DailyMealSetCard(
          meals: meals,
          views: views,
          onShowCandidates: (_) {},
          onAddToMeal: null,
          onOpenCanteen: null,
          onLike: (_) async {},
          onRepickSet: () {},
        ),
      );
      await captureRound7(tester, 'review2-daily-set-compact-$tag');
    }

    // R-11：食堂菜操作弹窗两态（有/无 AI 分析入口）。
    for (final (tag, showAnalyze) in const [
      ('with-ai', true),
      ('no-ai', false),
    ]) {
      await pumpFrame(
        320,
        640,
        2.0,
        CanteenDishActionsSheet(showAnalyze: showAnalyze),
      );
      await captureRound7(tester, 'review2-canteen-dish-actions-$tag');
    }

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    dir.deleteSync(recursive: true);
  });
}
