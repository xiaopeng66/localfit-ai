@Tags(['capture'])
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/dashboard/presentation/sections/dashboard_weight_card.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/nutrition_record_slot_grouping.dart';
import 'package:localfit_ai/features/progress/domain/weight_measurement.dart';

import 'support/food_fixture.dart';
import 'support/round7_render.dart';

/// 复核 · 页面级新 UI 在「320dp × 2.0×」下的检查：槽位头「补记」徽标、
/// 体重卡头 ⋮。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestWidgetsFlutterBinding
      .instance
      .platformDispatcher
      .accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
    disableAnimations: true,
  );

  final now = DateTime(2026, 10, 26, 12);
  late AppDatabase database;
  late MealRepository meals;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await seedFoodFixture(database);
    meals = MealRepository(
      database: database,
      idGenerator: const UuidV7Generator(),
      clock: FixedAppClock(now.toUtc()),
    );
    await database
        .into(database.profiles)
        .insert(
          ProfilesCompanion.insert(
            id: 'profile-1',
            activityLevel: 'moderate',
            createdAt: now.toUtc(),
            updatedAt: now.toUtc(),
          ),
        );
  });

  tearDown(() => database.close());

  Future<void> settle(WidgetTester tester, [int frames = 14]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    double width = 320,
    double textScale = 2.0,
    double height = 1600,
  }) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = Size(width * 2, height * 2);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
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
            home: Scaffold(body: SingleChildScrollView(child: child)),
          ),
        ),
      ),
    );
    await settle(tester);
    expect(tester.takeException(), isNull, reason: '布局溢出');
  }

  Future<void> shot(WidgetTester tester, String name) async {
    await captureRound7(tester, name);
  }

  testWidgets('槽位头「补记」徽标（320×2.0）', (tester) async {
    await tester.runAsync(loadRound7Fonts);
    await pump(
      tester,
      NutritionRecordSlotGrouping(
        repository: meals,
        localDate: '2026-10-25',
        now: now,
        onAddToSlot: (_) {},
      ),
    );
    await shot(tester, 'review-slot-backfill-320x2');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('体重卡头（⋮ + 加号 + 周/月切换，320×2.0）', (tester) async {
    await tester.runAsync(loadRound7Fonts);
    await meals.create(
      const MealDraft(
        localDate: '2026-10-26',
        slot: MealSlot.lunch,
        items: [
          MealItemDraft(
            foodName: '米饭',
            grams: 200,
            nutrition: NutritionValues(
              kcal: 232,
              proteinGrams: 5.2,
              carbsGrams: 51.6,
              fatGrams: 0.6,
            ),
          ),
        ],
      ),
    );
    await pump(
      tester,
      DashboardWeightCard(
        overview: WeightOverview(
          measurements: [
            WeightMeasurement(
              id: 'w1',
              profileId: 'profile-1',
              localDate: '2026-10-26',
              weightKg: 70.5,
              source: 'manual',
              createdAt: now,
              updatedAt: now,
            ),
          ],
          latest: WeightMeasurement(
            id: 'w1',
            profileId: 'profile-1',
            localDate: '2026-10-26',
            weightKg: 70.5,
            source: 'manual',
            createdAt: now,
            updatedAt: now,
          ),
          sevenDayAverageKg: 70.5,
          sampleDays: 1,
        ),
        onRecord: () {},
        endLocalDate: '2026-10-26',
        onAdd: () {},
        onOpenRecords: () {},
      ),
    );
    await shot(tester, 'review-weight-card-header-320x2');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
