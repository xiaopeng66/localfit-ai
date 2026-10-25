import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/nutrition/presentation/nutrition_page.dart';

/// `R4`（`docs/56` §3 R4 / `docs/58` B3 的 R4-4a）：**记录页不再有「下一餐详情」入口**。
///
/// 用户原话：「记录页删『下一餐详情』入口与其内容，不留死码」。
///
/// 这是**反向断言**：入口与二级页都不存在。它与 §5 退役台账里那几条
/// 「原本断言入口存在」的用例成对——那几条随功能退役一起划掉，这一条是
/// 它们的替代（防止将来有人把入口加回来）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late FoodRepository foods;
  late MealRepository meals;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    final clock = FixedAppClock(DateTime.utc(2026, 10, 24, 2));
    foods = FoodRepository(
      database: database,
      idGenerator: _Ids(),
      clock: clock,
    );
    meals = MealRepository(
      database: database,
      idGenerator: _Ids(),
      clock: clock,
    );
  });
  tearDown(() => database.close());

  Future<void> pumpNutrition(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: NutritionPage(
          repository: foods,
          mealRepository: meals,
          now: DateTime(2026, 10, 24, 12),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 卸载整棵树并让 drift 的 stream-close 定时器跑掉（否则 teardown 报
  /// 「Pending timers」——与 `dashboard_entry_routing_test` 同一手法）。
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('记录页没有「下一餐详情」入口', (tester) async {
    await pumpNutrition(tester);

    expect(
      find.byKey(const Key('nutrition-record-next-meal-entry')),
      findsNothing,
      reason: 'R4：入口整族退役（用户：记录页不要这个入口）',
    );
    expect(
      find.text('下一餐详情'),
      findsNothing,
      reason: 'R4：连文案都不该出现（防止换个 Key 又加回来）',
    );
    await unmount(tester);
  });

  testWidgets('记录页其余结构仍在位（退役没有误伤首屏）', (tester) async {
    await pumpNutrition(tester);

    // 记录 tab 的核心结构：周条 + 至少一张餐卡 + FAB。
    expect(
      find.byKey(const Key('nutrition-record-week-strip')),
      findsOneWidget,
      reason: '周条不得被退役波及',
    );
    expect(
      find.byKey(const Key('nutrition-record-fab')),
      findsOneWidget,
      reason: '记录 FAB 不得被退役波及',
    );
    await unmount(tester);
  });
}

final class _Ids implements IdGenerator {
  int _value = 0;

  @override
  String next() => 'id-${_value++}';
}
