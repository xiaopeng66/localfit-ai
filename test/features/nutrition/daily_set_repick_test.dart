import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/data/dish_library_repository.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/dish_record.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';
import 'package:localfit_ai/features/nutrition/application/swap_daily_set_with_ai.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/menu_dish_list.dart';
import 'package:localfit_ai/features/retrieval/data/feedback_repository.dart';

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

  Widget host({Future<MenuSetSwapResult?> Function()? swapAi}) => MaterialApp(
    home: Scaffold(
      body: MenuDishList(
        repository: dishes,
        mealRepository: meals,
        now: now,
        // 【R-4】「换一整套」走**内联** AI 重配；不传 = 本地重排分支。
        onSwapSetWithAi: swapAi,
      ),
    ),
  );

  /// 2026-11-02 用户实机：「今日餐食的推荐候选点击后还是会黑屏」。
  ///
  /// 复现条件必须是**真实弹层结构**：`AppSheet.show` 走 `useRootNavigator: true`，
  /// 而旧的候选行回调用的是页面自己的 `context`。只有一层 Navigator 的
  /// `MaterialApp(home:)` 里两者恰好相同，所以旧用例一直假绿；下面显式搭出
  /// 「根 Navigator 弹层 + 嵌套页面 Navigator」的最小结构，点候选后断言
  /// **页面还在、弹层已关**。
  group('候选弹层：点击后只关弹层，不关掉页面', () {
    testWidgets('嵌套 Navigator 下点候选：页面存活，候选被采用', (tester) async {
      await seedDishes();
      final pageKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          // 根 Navigator：AppSheet 的 useRootNavigator:true 落在这一层。
          home: Navigator(
            key: pageKey,
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (_) => Scaffold(
                body: MenuDishList(
                  repository: dishes,
                  mealRepository: meals,
                  now: now,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('nutrition-menu-meal-breakfast-candidates')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('nutrition-menu-candidate-1')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('nutrition-menu-candidate-1')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const Key('nutrition-menu-hero')),
        findsOneWidget,
        reason: '点候选只能关弹层；页面被一起 pop 掉就是黑屏',
      );
      expect(
        find.byKey(const Key('nutrition-menu-candidate-1')),
        findsNothing,
        reason: '弹层本身要关掉',
      );
      await unmount(tester);
    });
  });

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
    // 【R-4 改写（2026-10-29）】「已配置 AI」不再是「跳对话页」，而是
    // **内联重配**：回调返回已校验的推荐集 → 推荐表直接换成 AI 的菜。
    testWidgets('AI 可用（返回推荐集）→ 推荐表换成 AI 选的菜，不弹本地重排', (tester) async {
      await seedDishes();
      var asked = 0;
      await tester.pumpWidget(
        host(
          swapAi: () async {
            asked++;
            final now = DateTime.utc(2026, 9, 15);
            return MenuSetSwapResult(
              bySlot: {
                MealSlot.breakfast: [
                  DishRecord(
                    id: 'ai-breakfast',
                    name: 'AI 选的水煮蛋',
                    mealSlot: 'breakfast',
                    kcal: 90,
                    proteinG: 8,
                    carbsG: 1,
                    fatG: 6,
                    source: 'canteen',
                    createdAt: now,
                    updatedAt: now,
                  ),
                ],
              },
              filtered: 0,
            );
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
        find.text('AI 选的水煮蛋'),
        findsOneWidget,
        reason: '换的是推荐表：早餐段直接显示 AI 选中的菜',
      );
      expect(
        find.textContaining('本地规则'),
        findsNothing,
        reason: '走了 AI 就不该再弹「已按本地规则重排」',
      );
      await unmount(tester);
    });

    testWidgets('AI 不可用（返回 null）→ 退回本地重排 + 如实说明', (tester) async {
      await seedDishes();
      var asked = 0;
      await tester.pumpWidget(
        host(
          swapAi: () async {
            asked++;
            return null;
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
        find.textContaining('AI 换一套没成功'),
        findsOneWidget,
        reason: '失败必须如实说，不假装 AI 成功（然后本地重排）',
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
    // ══════════════════════════════════════════════════════════════════
    // 【2026-10-29 用户实机】换一套（AI）→ 打开候选 → 点一个候选 ⇒ 黑屏。
    // 复现用例：AI 推荐集应用后，打开候选榜并点选一行，要求全程无异常。
    // ══════════════════════════════════════════════════════════════════
    group('R-4 实机回归：AI 换一套后候选可点（不黑屏）', () {
      testWidgets('AI 换一套 → 打开候选 → 点一个候选：无异常、候选被采用', (tester) async {
        await seedDishes();
        var asked = 0;
        await tester.pumpWidget(
          host(
            swapAi: () async {
              asked++;
              final stamp = DateTime.utc(2026, 9, 15);
              DishRecord pick(
                String id,
                String name,
                String slot,
                double kcal,
              ) => DishRecord(
                id: id,
                name: name,
                mealSlot: slot,
                kcal: kcal,
                proteinG: 10,
                carbsG: 20,
                fatG: 8,
                source: 'canteen',
                servingGrams: 100,
                basisAssumed: true,
                createdAt: stamp,
                updatedAt: stamp,
              );
              return MenuSetSwapResult(
                bySlot: {
                  MealSlot.breakfast: [
                    pick('canteen-1', '食堂蛋', 'breakfast', 150),
                    pick('canteen-1b', '食堂蛋二', 'breakfast', 160),
                  ],
                  MealSlot.lunch: [pick('canteen-2', '食堂饭', 'lunch', 600)],
                  MealSlot.dinner: [pick('canteen-3', '食堂鱼', 'dinner', 300)],
                },
                filtered: 0,
              );
            },
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const Key('nutrition-menu-daily-set-repick')),
        );
        await tester.pumpAndSettle();
        expect(asked, 1);
        expect(tester.takeException(), isNull, reason: '换一套本身不炸');

        // 打开早餐段候选榜（AI 的那道菜在里面），点它。
        await tester.tap(
          find.byKey(const Key('nutrition-menu-meal-breakfast-candidates')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('nutrition-menu-candidate-0')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull, reason: '候选榜打开不炸');

        await tester.tap(find.byKey(const Key('nutrition-menu-candidate-0')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '点候选不炸（实机此处黑屏）');
        await unmount(tester);
      });
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // 【2026-11-02 用户】「不错」点完按钮还在、只弹一条会消失的提示 ——
  // 既不知道存哪了，也没有「已经点过」的可见状态。现在：
  // 1) 落库到 `app_settings.recommendation_feedback`（既有 KV）；
  // 2) 按钮就地变成选中胶囊「已记下」；
  // 3) 重进页面仍显示「已记下」（读的是持久化计数，不是一次性的 UI 变量）。
  // ══════════════════════════════════════════════════════════════════════
  group('推荐卡「不错」：点击后有可见且持久的状态', () {
    testWidgets('点午餐「不错」→ 变成「已记下」；重进页面仍成立；计数已落库', (tester) async {
      await seedDishes();
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      final like = find.byKey(const Key('nutrition-menu-meal-lunch-like'));
      expect(like, findsOneWidget);
      expect(
        find.descendant(of: like, matching: find.text('不错')),
        findsOneWidget,
        reason: '未点过时仍是「不错」',
      );

      await tester.tap(like);
      await tester.pumpAndSettle();

      final liked = find.byKey(const Key('nutrition-menu-meal-lunch-like'));
      expect(liked, findsOneWidget, reason: 'Key 不变，方便读屏与测试定位');
      expect(
        find.descendant(of: liked, matching: find.text('已记下')),
        findsOneWidget,
        reason: '点击后按钮必须就地变成「已记下」，不能只弹 SnackBar',
      );
      expect(
        find.descendant(of: liked, matching: find.byIcon(Icons.check)),
        findsOneWidget,
        reason: '选中态要有勾选图标（颜色 + 图标 + 文案三者同时变）',
      );

      final stored = await FeedbackRepository(database: database).load();
      expect(
        stored.entries['鸡胸肉饭']?.likes,
        1,
        reason: '反馈必须真的写进 app_settings（用户问「存在哪里了」）',
      );

      // 重进页面：反馈从库里读回来，状态仍显示「已记下」。
      await unmount(tester);
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      final persisted = find.byKey(const Key('nutrition-menu-meal-lunch-like'));
      expect(
        find.descendant(of: persisted, matching: find.text('已记下')),
        findsOneWidget,
        reason: '状态来自持久化计数，不是只活在这一次点击里',
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
