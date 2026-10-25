import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/ai_memory/data/ai_memory_repository.dart';
import 'package:localfit_ai/features/ai_memory/domain/ai_memory.dart';
import 'package:localfit_ai/features/ai_memory/presentation/ai_memory_page.dart';
import 'package:localfit_ai/features/campus_menus/application/food_reference_service.dart';
import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart';
import 'package:localfit_ai/features/campus_menus/presentation/canteen_dish_actions_sheet.dart';
import 'package:localfit_ai/features/campus_menus/presentation/food_reference_sheet.dart';
import 'package:localfit_ai/features/campus_menus/presentation/menu_tab_view.dart';
import 'package:localfit_ai/features/daily_plan/data/planning_constraints_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/dish_record.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';
import 'package:localfit_ai/features/nutrition/presentation/meal_entry_chooser_sheet.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/dish_card.dart';
import 'package:localfit_ai/features/retrieval/presentation/retrieval_debug_page.dart';
import 'package:localfit_ai/features/training/data/exercise_repository.dart';
import 'package:localfit_ai/features/training/data/workout_plan_repository.dart';
import 'package:localfit_ai/features/training/presentation/training_page.dart';

/// RV-P1-15：docs/21 附录 D 的 13 个已上线 Key 必须有**渲染**断言。
///
/// 审查时这些 Key 只有实现、没有测试（`code/audit-I-K-L-M-N.md` §5）。
/// 本文件逐个把宿主 pump 出来并 `find.byKey`——不是 grep 源码。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  DishRecord dish({String name = '番茄牛腩饭', bool basisAssumed = false}) =>
      DishRecord(
        id: 'dish-1',
        name: name,
        mealSlot: '午餐',
        kcal: 200,
        proteinG: 8,
        carbsG: 30,
        fatG: 5,
        source: 'manual',
        createdAt: DateTime.utc(2026, 10, 20),
        updatedAt: DateTime.utc(2026, 10, 20),
        basisAssumed: basisAssumed,
        sourceType: 'canteen',
        sourceId: 'item-1',
      );

  FoodReferenceCandidate candidate() => const FoodReferenceCandidate(
    foodId: 'food-1',
    foodName: '番茄牛腩',
    state: 'verified',
    confidence: 0.95,
    kcalPer100g: 135,
    proteinPer100g: 8.8,
    carbsPer100g: 4.1,
    fatPer100g: 9.3,
  );

  /// 弹层/卡片（无自己的 Scaffold）：给一个可滚宿主，避免纵向溢出。
  Future<void> pumpSheet(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );
    await tester.pump();
  }

  /// 整页（自带 Scaffold）：直接作为 home，**不能再包** Scaffold/滚动体。
  Future<void> pumpPage(WidgetTester tester, Widget page) async {
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light(), home: page));
    await tester.pump();
  }

  testWidgets('D3 canteen-dish-manual-nutrition', (tester) async {
    await pumpSheet(tester, const CanteenDishActionsSheet(showAnalyze: true));
    expect(
      find.byKey(const Key('canteen-dish-manual-nutrition')),
      findsOneWidget,
    );
  });

  testWidgets('D1 meal-entry-by-dish / dish-meal-picker / dish-meal-confirm', (
    tester,
  ) async {
    await pumpSheet(tester, const MealRecordEntryChooser());
    expect(find.byKey(const Key('meal-entry-by-dish')), findsOneWidget);

    await pumpSheet(
      tester,
      DishMealPickerDialog(dishes: [dish()], mealSlotLabel: (slot) => slot),
    );
    expect(find.byKey(const Key('dish-meal-picker')), findsOneWidget);

    await pumpSheet(
      tester,
      DishMealConfirmSheet(dish: dish(), mealSlotLabel: (slot) => slot),
    );
    // `dish-meal-confirm` 是**动作钮**的契约名（内容根在本轮改为
    // `dish-meal-confirm-body`，因为同一 Key 挂在两处会让 tap 有歧义）。
    expect(find.byKey(const Key('dish-meal-confirm-body')), findsOneWidget);
  });

  testWidgets('D2 food-reference 六键（含 source/evidence）', (tester) async {
    await pumpSheet(
      tester,
      FoodReferenceSheet(dishName: '番茄牛腩饭', candidates: [candidate()]),
    );
    expect(find.byKey(const Key('food-reference-sheet')), findsOneWidget);
    expect(find.byKey(const Key('food-reference-adopt')), findsOneWidget);
    expect(find.byKey(const Key('food-reference-analyze')), findsOneWidget);
    expect(find.byKey(const Key('food-reference-skip')), findsOneWidget);
    // 【退役】`food-reference-source` / `-evidence` 两枚徽标随
    // `RV4-P2-12`（R7）删除——建菜语境里菜还没有营养、来源尚未确定，
    // 它们没有信息量。**三枚动作 Key 的断言保留在下面**（能力没删）。
    expect(find.byKey(const Key('food-reference-source')), findsNothing);
    expect(find.byKey(const Key('food-reference-evidence')), findsNothing);
  });

  // 【测试退役】`D6/D7 dish-basis / dish-sync` 里的 `dish-sync` 部分随
  // `RV4-P2-09`（陈旧提示 + 手动同步整族退役）删除；`dish-stale` 同理。
  // 替代断言：`daily_set_repick_test.dart` 的「没有同步链 / 没有陈旧文案」
  // 与 `food_library_no_footer_test.dart`。`dish-basis`（「按 100g 估算」）
  // 与陈旧无关，**保留**在下面的缩短版用例里。
  testWidgets('D6 dish-basis：份量未知时的「按 100g 估算」徽标仍在', (tester) async {
    final dish = DishRecord(
      id: 'dish-1',
      name: '番茄炒蛋',
      mealSlot: 'lunch',
      kcal: 200,
      proteinG: 10,
      carbsG: 20,
      fatG: 8,
      source: 'manual',
      basisAssumed: true,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );
    await pumpSheet(
      tester,
      SingleChildScrollView(child: DishCard(dish: dish, index: 0)),
    );
    expect(
      find.byKey(const Key('nutrition-menu-dish-basis-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('nutrition-menu-dish-stale-0')),
      findsNothing,
      reason: 'P2-09：陈旧徽标已退役',
    );
    expect(
      find.byKey(const Key('nutrition-menu-dish-sync-0')),
      findsNothing,
      reason: 'P2-09：「同步」链已退役',
    );
  });

  testWidgets('D5 retrieval-debug-rerun', (tester) async {
    // 视口给足：ListView 只构建可见子项，矮视口下「重新运行」不会被建出来。
    tester.view.physicalSize = const Size(500, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpPage(tester, RetrievalDebugPage(dishes: [dish()]));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const Key('retrieval-debug-rerun')), findsOneWidget);
  });

  // ── RV2-P2-07（2026-10-22）：附录 D 表格里「有 UI、无断言」的 6 个 Key。
  //
  // 根因不是这 6 个控件坏了，而是对账测试只扫「测试 Key」罗列行，附录 D 的
  // 表格行整段漏扫（`docs/52` / `docs/evidence/…/docs/key-sync.md`）。对账器
  // 已改为读 Key 列（`ui_spec_key_sync_test.dart`），这里把 6 条断言补齐。

  testWidgets('D1 dish-meal-picker-empty：空态文案是 Key 也是可行动文案', (tester) async {
    await pumpSheet(
      tester,
      DishMealPickerDialog(dishes: const [], mealSlotLabel: (slot) => slot),
    );
    expect(find.byKey(const Key('dish-meal-picker-empty')), findsOneWidget);
    // 空态必须是「能做什么」，不是「暂无数据」。
    expect(find.textContaining('暂无数据'), findsNothing);
    expect(find.textContaining('存为菜品'), findsOneWidget);
  });

  // 【语义变更，不是删断言换绿】`RV4-P1-06`（docs/56 R3-b / D9 同一口径）：
  // 确认层返回值从 `bool`（确认/取消）改成 `MealSlot?`（**用户选定的餐次**，
  // null = 取消）。断言对象变了（「返回 false」→「返回 null」），断言强度不变：
  // 仍然钉住「取消绝不写库」这条。
  testWidgets('D1 dish-meal-cancel：取消真的返回 null（不写库）', (tester) async {
    MealSlot? confirmed = MealSlot.lunch;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              key: const Key('open-confirm'),
              onPressed: () async {
                confirmed = await DishMealConfirmSheet.show(
                  context,
                  dish: dish(),
                  mealSlotLabel: (slot) => slot,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open-confirm')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('dish-meal-cancel')), findsOneWidget);
    await tester.tap(find.byKey(const Key('dish-meal-cancel')));
    await tester.pumpAndSettle();
    expect(confirmed, isNull, reason: '取消必须返回 null（调用方据此不写库）');
    expect(find.byKey(const Key('dish-meal-cancel')), findsNothing);
  });

  testWidgets('D5 retrieval-debug-close：关闭钮只在有 onClose 时出现且真回调', (
    tester,
  ) async {
    var closed = 0;
    await pumpPage(
      tester,
      RetrievalDebugPage(dishes: [dish()], onClose: () => closed++),
    );
    expect(find.byKey(const Key('retrieval-debug-close')), findsOneWidget);
    await tester.tap(find.byKey(const Key('retrieval-debug-close')));
    await tester.pump();
    expect(closed, 1);

    // 未接线时（null）不得画出一个点了没反应的关闭钮。
    await pumpPage(tester, RetrievalDebugPage(dishes: [dish()]));
    expect(find.byKey(const Key('retrieval-debug-close')), findsNothing);
  });

  testWidgets('D9 training-retry：训练数据加载失败给可重试的错误态', (tester) async {
    // 保留数据库连接（页面要订阅变更流），只让查询失败：删表即可。
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await database.customStatement('DROP TABLE workout_plans');
    final clock = FixedAppClock(DateTime.utc(2026, 10, 22));

    await pumpPage(
      tester,
      TrainingPage(
        exerciseRepository: ExerciseRepository(
          database: database,
          idGenerator: _SeqIds(),
          clock: clock,
        ),
        workoutPlanRepository: WorkoutPlanRepository(
          database: database,
          idGenerator: _SeqIds(),
          clock: clock,
        ),
        now: DateTime(2026, 10, 22),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('训练数据加载失败，请重试。'), findsOneWidget);
    expect(find.byKey(const Key('training-retry')), findsOneWidget);
    // 错误态不得退化成永久 spinner。
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('D1 canteen-directory-retry：目录加载失败给可重试的错误态', (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await database.customStatement('DROP TABLE venues');
    final clock = FixedAppClock(DateTime.utc(2026, 10, 22));

    await pumpPage(
      tester,
      Scaffold(
        body: MenuTabView(
          repository: CanteenRepository(
            database: database,
            idGenerator: _SeqIds(),
            clock: clock,
          ),
        ),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('食堂目录加载失败，请重试。'), findsOneWidget);
    expect(find.byKey(const Key('canteen-directory-retry')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('D3 ai-memory-promote-delete：晋升后追问删除，点删除才删', (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    var closed = false;
    addTearDown(() async {
      if (!closed) await database.close();
    });
    final clock = FixedAppClock(DateTime.utc(2026, 10, 22));
    // 晋升写约束要求有本地档案（`constraints.set` 同一写路径）。
    await database
        .into(database.profiles)
        .insert(
          ProfilesCompanion.insert(
            id: 'profile-1',
            activityLevel: 'moderate',
            createdAt: DateTime.utc(2026, 10, 22),
            updatedAt: DateTime.utc(2026, 10, 22),
          ),
        );
    final repository = AiMemoryRepository(
      database: database,
      clock: clock,
      idGenerator: _SeqIds(),
    );
    await repository.remember(
      text: '不吃香菜',
      kind: AiMemoryKind.preference,
      domain: AiMemoryDomain.nutrition,
    );

    await pumpPage(
      tester,
      AiMemoryPage(
        repository: repository,
        onClose: () {},
        constraintsRepository: PlanningConstraintsRepository(
          database: database,
          clock: clock,
        ),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // 行尾菜单 →「转为忌口/偏好」。
    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('转为忌口/偏好'));
    await tester.pumpAndSettle();

    expect(find.text('顺便删掉这条记忆？'), findsOneWidget);
    expect(find.byKey(const Key('ai-memory-promote-delete')), findsOneWidget);

    await tester.tap(find.byKey(const Key('ai-memory-promote-delete')));
    await tester.pumpAndSettle();
    // 删掉后列表回到空态（记忆真的没了）。
    expect(find.byKey(const Key('ai-memory-empty')), findsOneWidget);

    // drift 的流查询在取消订阅后留一个 `Timer.run`：必须「卸页面 → pump 一拍
    // 让计时器跑掉 → 关库」，否则测试结束会报 pending timer
    // （与 `ai_memory_page_test.dart` 的 disposePage 同序）。
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    await database.close();
    closed = true;
  });
}

final class _SeqIds implements IdGenerator {
  int _n = 0;

  @override
  String next() => 'id-${_n++}';
}
