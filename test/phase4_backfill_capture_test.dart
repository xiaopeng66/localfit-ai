@Tags(['capture'])
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/nutrition_record_slot_grouping.dart';

import 'support/round7_render.dart';

/// 阶段 4（docs/64 B-3）取帧件：过去日期的「补记」入口（窗口内）与窗口外
/// 的如实说明。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 10, 26, 12);
  late AppDatabase database;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() => database.close());

  Future<void> settle(WidgetTester tester, [int frames = 14]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  Future<void> shot(
    WidgetTester tester,
    String name,
    Key sentinel, {
    int count = 1,
  }) async {
    expect(tester.takeException(), isNull, reason: '$name：布局溢出');
    expect(
      find.byKey(sentinel),
      findsNWidgets(count),
      reason: '$name：关键件不在帧内（期望 $count 处）',
    );
    await captureRound7(tester, name);
  }

  Future<void> pumpGrouping(
    WidgetTester tester,
    MealRepository meals, {
    required String localDate,
    double height = 1100,
  }) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = Size(412 * 2, height * 2);
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(size: Size(412, height)),
        child: RepaintBoundary(
          key: round7Boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: round7CaptureTheme(AppTheme.light()),
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: NutritionRecordSlotGrouping(
                  repository: meals,
                  localDate: localDate,
                  now: now,
                  onAddToSlot: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await settle(tester, 20);
  }

  testWidgets('B-3 补记：昨天有「+」与「补记」徽标；窗口外如实说窗口', (tester) async {
    await tester.runAsync(loadRound7Fonts);
    final meals = MealRepository(
      database: database,
      idGenerator: const UuidV7Generator(),
      clock: FixedAppClock(now.toUtc()),
    );
    await meals.create(
      const MealDraft(
        localDate: '2026-10-25',
        slot: MealSlot.lunch,
        items: [
          MealItemDraft(
            foodName: '番茄牛腩饭',
            grams: 350,
            nutrition: NutritionValues(
              kcal: 520,
              proteinGrams: 28,
              carbsGrams: 62,
              fatGrams: 16,
            ),
          ),
        ],
      ),
    );

    // 窗口内（昨天）：有加号 + 补记徽标。
    await pumpGrouping(tester, meals, localDate: '2026-10-25');
    // 四张槽位卡各一枚「补记」徽标（四槽位是记录入口的承载）。
    await shot(
      tester,
      'fix2-history-backfill',
      const Key('nutrition-record-backfill-badge'),
      count: 4,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));

    // 窗口外（31 天前）：不加号，如实说窗口。
    await pumpGrouping(tester, meals, localDate: '2026-09-25');
    await shot(
      tester,
      'fix2-history-backfill-window',
      const Key('nutrition-record-backfill-window-note'),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
