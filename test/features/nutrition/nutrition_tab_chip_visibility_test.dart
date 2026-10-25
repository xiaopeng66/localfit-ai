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

/// 阶段 3 验收（docs/21 §5.8.3）：
///
/// 「横向 Tab/Chip/日期条使用懒列表并**保持选中项可见**。」
///
/// 2026-09-26 探针实测：320dp 下五枚 chip 依次为 53/53/53/61.5dp 宽，最后一枚
/// 「食物库」右缘到 329.5dp，而视口只有 320dp——点它（可见部分）能切 Tab
/// （`selected=true`），但选中标记被裁掉 9.5dp，用户看不到「当前在哪一页」
/// 的完整标记。修复前 `NutritionTabChips` 是 `StatelessWidget`，完全没有
/// 滚动到选中项的逻辑。
///
/// 2026-10-04（docs/28 §6.1）：五枚收敛为三枚（记录 / 菜单 / 食物库）。契约
/// 不变——无论胶囊多少，**选中的那枚必须完整可见**；本回归在三枚存活 chip 上
/// 重跑（最右仍是「食物库」）。
///
/// 这些断言按 dp 数值说话（不只看 `selected`），否则「切对了 Tab 但标记
/// 被裁」这种半对状态会漏过。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const narrow = 320.0;

  Future<void> pumpNutrition(WidgetTester tester) async {
    tester.view.physicalSize = const Size(narrow, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final clock = FixedAppClock(DateTime.utc(2026, 9, 17));
    await tester.pumpWidget(
      LocalFitApp(
        initialLocation: AppRoutes.nutrition,
        foodRepository: FoodRepository(
          database: db,
          idGenerator: _Ids(),
          clock: clock,
        ),
        mealRepository: MealRepository(
          database: db,
          idGenerator: _Ids(),
          clock: clock,
        ),
        now: DateTime(2026, 9, 17),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> unmountApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  /// 断言某枚 chip 完整落在视口内（左右都不裁）。
  void expectFullyVisible(WidgetTester tester, String key, String what) {
    final rect = tester.getRect(find.byKey(Key(key)));
    expect(
      rect.left,
      greaterThanOrEqualTo(-0.01),
      reason: '$what 左缘 ${rect.left} 跑出视口（docs/21 §5.8.3 要保持选中项可见）',
    );
    expect(
      rect.right,
      lessThanOrEqualTo(narrow + 0.01),
      reason:
          '$what 右缘 ${rect.right} 超出 ${narrow}dp 视口（docs/21 §5.8.3 要保持选中项可见）',
    );
  }

  testWidgets('320dp：选中最后一枚 chip 后它必须完整可见（docs/21 §5.8.3）', (tester) async {
    await pumpNutrition(tester);

    final foodlib = find.byKey(const Key('nutrition-tab-foodlib'));
    // 目标可能被裁到视口外，只能点可见交集（用户真实路径：点可见部分切 Tab）。
    final before = tester.getRect(foodlib);
    final x = before.center.dx.clamp(1.0, narrow - 1.0);
    await tester.tapAt(Offset(x, before.center.dy));
    await tester.pumpAndSettle();

    expect(
      tester.getSemantics(foodlib).flagsCollection.isSelected.toBoolOrNull(),
      isTrue,
      reason: '先确认真的切到了食物库 Tab，否则下面的位置断言没意义',
    );
    expectFullyVisible(tester, 'nutrition-tab-foodlib', '选中后的食物库 chip');

    await unmountApp(tester);
  });

  testWidgets('320dp：先选最右再选最左，选中项每次都完整可见（docs/21 §5.8.3）', (tester) async {
    await pumpNutrition(tester);

    // 先选最右（列表向右滚），再一路向左选回来——**必须能滚回左边**。
    // 只做「向右滚动」的半吊子修复会在这条露馅：列表停在右端时，
    // 「记录」chip 会留在视口左侧之外。
    const order = [
      ('nutrition-tab-foodlib', '食物库'),
      ('nutrition-tab-menu', '菜单'),
      ('nutrition-tab-record', '记录'),
    ];

    for (final entry in order) {
      final finder = find.byKey(Key(entry.$1));
      final rect = tester.getRect(finder);
      // 目标可能被裁到视口外，只能点可见交集。
      final x = rect.center.dx.clamp(1.0, narrow - 1.0);
      await tester.tapAt(Offset(x, rect.center.dy));
      await tester.pumpAndSettle();

      expect(
        tester.getSemantics(finder).flagsCollection.isSelected.toBoolOrNull(),
        isTrue,
        reason: '${entry.$2} 未被选中',
      );
      expectFullyVisible(tester, entry.$1, '选中后的${entry.$2} chip');
    }

    await unmountApp(tester);
  });
}

final class _Ids implements IdGenerator {
  int _value = 0;

  @override
  String next() => 'tab-visible-${_value++}';
}
