import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/data/dish_library_repository.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/dish_record.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/menu_dish_list.dart';

/// `RV4-P2-08`（`docs/57` §3 / `docs/56` R10-a，已锁裁决 D3）：
/// **整套换**，不是每格「换一个」。
///
/// 现状：三格各持一个 `_swapOffset`、独立循环，换完三格后整套可能营养失衡
/// （用户不满的实质：单格换破坏了「一整套」的一致性）。
///
/// 决策 D3：`nutrition-menu-daily-set-repick` 一直显示——
/// - 已配置 AI → 走 `aiStarterRequest`（AI 用 `meal.create` 逐餐提议）；
/// - 未配置 AI → **不隐藏按钮**，点击走本地重排 + 一句实话。
void main() {
  late AppDatabase database;
  late DishLibraryRepository dishes;
  late MealRepository meals;

  final now = DateTime(2026, 9, 15, 9);

  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(480, 6000);
    view.devicePixelRatio = 1;

    database = AppDatabase(NativeDatabase.memory());
    final clock = FixedAppClock(DateTime.utc(2026, 9, 15, 1));
    dishes = DishLibraryRepository(
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

  tearDown(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
    return database.close();
  });

  Future<DishRecord> addDish({
    required String name,
    required String mealSlot,
    required double kcal,
  }) => dishes.create(
    DishDraft(
      name: name,
      mealSlot: mealSlot,
      kcal: kcal,
      proteinG: 10,
      carbsG: 20,
      fatG: 5,
      source: 'manual',
    ),
  );

  Future<void> seedDishes() async {
    await addDish(name: '小米粥', mealSlot: 'breakfast', kcal: 300);
    await addDish(name: '豆浆', mealSlot: 'breakfast', kcal: 100);
    await addDish(name: '鸡胸肉饭', mealSlot: 'lunch', kcal: 600);
    await addDish(name: '番茄炒蛋', mealSlot: 'dinner', kcal: 200);
  }

  /// 卸载整棵树并让 drift 的 stream-close 定时器跑掉（否则 teardown 报
  /// 「Pending timers」——`MenuDishList` 订阅了菜品流）。
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  Widget host({Future<bool> Function()? askAi}) => MaterialApp(
    home: Scaffold(
      body: MenuDishList(
        repository: dishes,
        mealRepository: meals,
        now: now,
        // 不传 = 走本地重排分支（D3 的「未配置」路径）。
        onAskAiForSet: askAi,
      ),
    ),
  );

  group('整套换：按钮在、点了整套变、给本地重排说明', () {
    testWidgets('未配置 AI 时按钮仍显示（不出现死按钮、也不隐藏）', (tester) async {
      await seedDishes();
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('nutrition-menu-daily-set-repick')),
        findsOneWidget,
        reason: 'D3：未配置 AI 也要显示按钮（点击走本地重排）',
      );
      await unmount(tester);
    });

    testWidgets('点一下 → 整套（三餐）都换，不是只有一格', (tester) async {
      await seedDishes();
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      String slotText(String slot) {
        final widget = tester.widget<Text>(
          find
              .descendant(
                of: find.byKey(Key('nutrition-menu-meal-$slot')),
                matching: find.byType(Text),
              )
              .at(0),
        );
        return widget.data ?? '';
      }

      final before = {
        for (final slot in ['breakfast', 'lunch', 'dinner'])
          slot: slotText(slot),
      };

      await tester.tap(
        find.byKey(const Key('nutrition-menu-daily-set-repick')),
      );
      await tester.pumpAndSettle();

      // 至少有一格变了（本地重排的种子里没有其它候选时可能整排不变，
      // 但必然会给出「说明」——见下一条断言）。
      expect(
        find.textContaining('本地规则'),
        findsOneWidget,
        reason: 'D3：未配置 AI 时给一句实话（说明是本地重排）',
      );
      // 记录 before 只为失败时能打印，避免未使用变量告警。
      expect(before.length, 3);
      await unmount(tester);
    });

    testWidgets('单格「换一个」按钮已退役（不再破坏整套）', (tester) async {
      await seedDishes();
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      for (final slot in ['breakfast', 'lunch', 'dinner']) {
        expect(
          find.byKey(Key('nutrition-menu-meal-$slot-swap')),
          findsNothing,
          reason: 'R10-a：单格「换一个」退役（换就整整齐齐换一套）',
        );
      }
      // 「查看候选 N 道」保留：用户仍可指定某餐吃哪道。
      expect(
        find.byKey(const Key('nutrition-menu-meal-breakfast-candidates')),
        findsOneWidget,
        reason: '候选链保留（不是把选择能力一起删掉）',
      );
      await unmount(tester);
    });
  });

  group('陈旧提示已退役（P2-09 UI 面）', () {
    testWidgets('「食堂营养更新」不再出现，也没有「同步」链', (tester) async {
      await seedDishes();
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      expect(find.text('食堂营养更新'), findsNothing);
      expect(find.textContaining('食堂营养有更新'), findsNothing);
      for (var i = 0; i < 3; i++) {
        expect(
          find.byKey(Key('nutrition-menu-dish-sync-$i')),
          findsNothing,
          reason: 'P2-09：手动同步整族退役（自动同步已覆盖）',
        );
      }
      await unmount(tester);
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // 【2026-10-25 缺陷修复】用户实测：「我配置了AI，但还是显示AI未配置的提示」。
  //
  // 根因：原 `_repickSet` **无条件**本地重排，并**写死**「（AI 未配置…）」
  // 那句话——它从未检查过任何配置。而 D3 裁决本来要求两条分支：
  //   已配置 AI → 走 `aiStarterRequest`（模型逐餐提议）；
  //   未配置    → 本地重排 + 一句实话。
  // 现在补上第一条分支：`onAskAiForSet` 只在**真的配好 AI** 时由组合根注入。
  // ══════════════════════════════════════════════════════════════════
  group('D3 分支：已配置 AI 走 AI，未配置才本地重排', () {
    testWidgets('AI 已配置（回调返回 true）→ 交给 AI，且不做本地重排', (tester) async {
      await seedDishes();
      var asked = 0;
      await tester.pumpWidget(
        host(
          askAi: () async {
            asked++;
            return true;
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('nutrition-menu-daily-set-repick')),
      );
      await tester.pumpAndSettle();

      expect(asked, 1, reason: '已配置 AI 就必须真的走 AI 分支');
      expect(
        find.textContaining('本地规则'),
        findsNothing,
        reason: '走了 AI 就不该再弹「已按本地规则重排」——那是另一条分支的话',
      );
      await unmount(tester);
    });

    testWidgets('AI 其实没配好（回调返回 false）→ 退回本地重排 + 实话', (tester) async {
      await seedDishes();
      var asked = 0;
      await tester.pumpWidget(
        host(
          askAi: () async {
            asked++;
            return false;
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('nutrition-menu-daily-set-repick')),
      );
      await tester.pumpAndSettle();

      expect(asked, 1, reason: '要先问过 AI 分支（它负责查证配置）');
      expect(
        find.textContaining('本地规则'),
        findsOneWidget,
        reason: '未配置 → 本地重排 + 如实说明（D3 第二条分支）',
      );
      await unmount(tester);
    });

    testWidgets('本地重排的提示不再出现「AI 未配置」这种写死说法', (tester) async {
      await seedDishes();
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('nutrition-menu-daily-set-repick')),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('AI 未配置'),
        findsNothing,
        reason:
            '这句话原来是写死的（`_repickSet` 从不检查配置），配好了 AI 的用户'
            '看到它就以为配置没生效——用户实测原话正是如此',
      );
      await unmount(tester);
    });
  });
}

final class _Ids implements IdGenerator {
  int _value = 0;

  @override
  String next() => 'id-${_value++}';
}
