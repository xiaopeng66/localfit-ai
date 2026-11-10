import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_router.dart';
import 'package:localfit_ai/app/localfit_app.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';

import '../../support/food_fixture.dart';

/// 【2026-10-31 用户：「删除复用历史餐食按钮和功能」】
///
/// 本文件原先钉的是「复用历史餐食」弹层（周条右侧历史圆钮 → 卡片式行 →
/// 点行把整餐复制到所选日期）。该功能按用户要求**整族退役**：
///  * 入口：`NutritionRecordWeekSection` 不再有 `meal-reuse-history`；
///  * 动作：`NutritionActions.reuseMeal` 删除；
///  * 弹层：`meal_history_dialog.dart` 删除。
///
/// 原两条用例（复用到所选日期 / 卡片式行）的对象已不存在，不是放宽判据；
/// 这里改成**反向断言**：历史按钮与弹层标题都不在上屏树里，防止被顺手加回。
/// 历史餐本身仍可看：记录页按日期翻到那一天即可（周条是切换日期的主入口），
/// 这也是删除该旁路的理由——同一件事已经有一条更直接的路径。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase database;
  late FoodRepository foods;
  late MealRepository meals;
  final now = DateTime(2026, 9, 9, 12);

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await seedFoodFixture(database);
    final ids = _Ids();
    foods = FoodRepository(
      database: database,
      idGenerator: ids,
      clock: FixedAppClock(now.toUtc()),
    );
    meals = MealRepository(
      database: database,
      idGenerator: ids,
      clock: FixedAppClock(now.toUtc()),
    );
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      LocalFitApp(
        initialLocation: AppRoutes.nutrition,
        foodRepository: foods,
        mealRepository: meals,
        now: now,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('记录页周条不再有「复用历史餐食」入口，历史餐仍按日期可看', (tester) async {
    final egg = (await foods.search('鸡蛋'))
        .firstWhere((food) => food.name == '鸡蛋');
    await meals.create(
      MealDraft(
        localDate: '2026-09-08',
        slot: MealSlot.breakfast,
        items: [MealItemDraft.fromFood(egg, 50)],
      ),
    );
    await pumpApp(tester);

    expect(find.byKey(const Key('meal-reuse-history')), findsNothing);
    expect(find.byTooltip('复用历史餐食'), findsNothing);
    expect(find.text('复用历史餐食'), findsNothing);

    // 历史期仍可翻到：切到 09-08 就能看到那天实际吃了什么。
    await tester.tap(find.byKey(const Key('meal-day-2026-09-08')));
    await tester.pumpAndSettle();
    expect(find.textContaining('鸡蛋 50g'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}

final class _Ids implements IdGenerator {
  int value = 0;

  @override
  String next() => 'nutrition-widget-${value++}';
}
