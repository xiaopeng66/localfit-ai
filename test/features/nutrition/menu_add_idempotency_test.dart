import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/data/dish_library_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/dish_record.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/menu_dish_list.dart';

/// RV-P1-05：「加入餐」双击只能产生一次写入。
///
/// 设备实测（2026-10-20）双击写出了两条 400 kcal 的餐记录：
/// `_addToMeal` 没有重入锁，按钮在等待期间仍可点。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late DishLibraryRepository dishes;
  final now = DateTime(2026, 10, 20, 12);

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    dishes = DishLibraryRepository(
      database: database,
      idGenerator: _SeqIds(),
      clock: FixedAppClock(now.toUtc()),
    );
    await dishes.create(
      DishDraft(
        name: '番茄牛腩饭',
        mealSlot: '午餐',
        kcal: 200,
        proteinG: 8,
        carbsG: 30,
        fatG: 5,
        source: 'manual',
      ),
    );
  });

  tearDown(() => database.close());

  testWidgets('双击「加入餐」只触发一次写入', (tester) async {
    final gate = Completer<void>();
    var calls = 0;
    var clock = DateTime(2026, 10, 20, 12);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MenuDishList(
            repository: dishes,
            now: now,
            addClock: () => clock,
            onAddToMeal: (DishRecord dish) async {
              calls++;
              await gate.future;
            },
          ),
        ),
      ),
    );
    // 菜单页有常驻入场动画：pumpAndSettle 永不收敛（历史同类，见
    // menu_search_test 的 2.0× 用例），用定长 pump 走完首帧与入场。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    await tester.enterText(
      find.byKey(const Key('nutrition-menu-search')),
      '番茄',
    );
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 400));

    final add = find.byKey(const Key('nutrition-menu-search-add-id-0'));
    expect(add, findsOneWidget, reason: '搜索结果行要有「加入餐」');

    // 第一次点击进入在途状态；第二次点击必须被重入锁挡掉。
    await tester.tap(add);
    await tester.pump();
    await tester.tap(add, warnIfMissed: false);
    await tester.pump();

    expect(calls, 1, reason: '在途期间第二次点击不能再发起写入');

    gate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // 第一次已完成，但仍在 900ms 冷却窗口内：连点不能再写一条。
    await tester.tap(add, warnIfMissed: false);
    await tester.pump();
    expect(calls, 1, reason: '成功后的冷却窗口内连点必须被挡');

    // 冷却到期后允许再次加入（用注入时钟推进，不依赖真实等待）。
    clock = clock.add(const Duration(seconds: 1));
    await tester.tap(find.byKey(const Key('nutrition-menu-search-add-id-0')));
    await tester.pump();
    expect(calls, 2, reason: '冷却结束后的下一次点击应正常写入');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}

final class _SeqIds implements IdGenerator {
  int _n = 0;

  @override
  String next() => 'id-${_n++}';
}
