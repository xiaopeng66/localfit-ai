import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/widgets/design_card.dart';
import 'package:localfit_ai/app/design/widgets/lf_badge.dart';
import 'package:localfit_ai/app/design/widgets/lf_buttons.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/data/dish_library_repository.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/dish_record.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/menu_dish_list.dart';

/// 菜单页的 **A `nutritionMenus()` 结构**（Round7 阶段 3 步骤 1，D25–D30）。
///
/// A 的原型帧：`renders/a-prototype/menus-360-1.0.png`（360×900 实拍）。A 的菜单页
/// 没有 hero 卡，页首是**段头三件**（段标题「每日菜品推荐」+ `.pill`「本地已分析
/// 菜品」+ `.intro-copy` 指引行，`app.js:181`），槽卡是 `.dish-recommendation`
/// （`styles.css:295–300`：heading 行右端「换一个」`link()`，块底 `.dish-action-row`
/// 左「查看候选 N 道」+ 右「加入<槽>」`.btn.outline-brand`），页尾是 `.list-link`
/// 「管理食堂目录」+ `.subtle-note`。
///
/// 本仓比 A 多的**事实**（hero 的两枚统计、照片、三宏量小卡、进度、
/// 来源徽标、点评、微量营养素、时段带、状态徽标）不删，按 D25–D30 落进 A 的骨架：
/// 统计进段头的汇总行、管理入口进页尾 list-link。逐条断言只锚**结构与几何**
/// （Key + getRect + 组件型别），锚文案的地方只有当 A 的字面句就是契约时。
void main() {
  late AppDatabase database;
  late DishLibraryRepository dishes;
  late MealRepository meals;

  final now = DateTime(2026, 9, 15, 9); // 09:00：三餐时段都还没过
  final localDate = '2026-09-15';

  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    // 三餐块每块揣着一张完整菜品卡：默认 800 高的测试面里后面的块不会被构建。
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
    String source = 'manual',
  }) => dishes.create(
    DishDraft(
      name: name,
      mealSlot: mealSlot,
      kcal: kcal,
      proteinG: 10,
      carbsG: 20,
      fatG: 5,
      source: source,
    ),
  );

  /// 当日目标 2000 kcal（三餐预算 600/800/600）。
  Future<void> seedTarget() async {
    final nowUtc = DateTime.utc(2026, 9, 15, 1);
    await database
        .into(database.profiles)
        .insert(
          ProfilesCompanion.insert(
            id: 'profile-1',
            activityLevel: 'moderate',
            createdAt: nowUtc,
            updatedAt: nowUtc,
          ),
        );
    await database
        .into(database.goals)
        .insert(
          GoalsCompanion.insert(
            id: 'goal-1',
            profileId: 'profile-1',
            type: 'maintain',
            calorieMinKcal: 1800,
            calorieMaxKcal: 2000,
            effectiveFrom: nowUtc,
            createdAt: nowUtc,
            updatedAt: nowUtc,
          ),
        );
    await database
        .into(database.dailyTargets)
        .insert(
          DailyTargetsCompanion.insert(
            id: 'target-1',
            goalId: 'goal-1',
            effectiveDate: localDate,
            calorieMinKcal: 1800,
            calorieMaxKcal: 2000,
            proteinMinGrams: 100,
            proteinMaxGrams: 140,
            carbsMinGrams: 200,
            carbsMaxGrams: 260,
            fatMinGrams: 50,
            fatMaxGrams: 70,
            createdAt: nowUtc,
            updatedAt: nowUtc,
          ),
        );
  }

  /// 小米粥(早 300) / 豆浆(早 100) / 鸡胸肉饭(午 600) / 番茄炒蛋(晚 200) /
  /// 酸奶(加餐 120)。加餐不进推荐位（2026-10-22 起「其他已分析菜品」整块退场，
  /// 它只是不出现在推荐里，不再单列一块）。
  Future<void> seedFiveDishes() async {
    await addDish(name: '小米粥', mealSlot: 'breakfast', kcal: 300);
    await addDish(name: '豆浆', mealSlot: 'breakfast', kcal: 100);
    await addDish(name: '鸡胸肉饭', mealSlot: 'lunch', kcal: 600);
    await addDish(name: '番茄炒蛋', mealSlot: 'dinner', kcal: 200);
    await addDish(name: '酸奶', mealSlot: 'snack', kcal: 120);
  }

  Widget host({
    VoidCallback? onOpenCanteen,
    Future<void> Function(DishRecord dish)? onAddToMeal,
    double textScale = 1.0,
    Size viewport = const Size(480, 6000),
  }) {
    final content = MaterialApp(
      home: Scaffold(
        body: MenuDishList(
          repository: dishes,
          mealRepository: meals,
          now: now,
          onAddToMeal: onAddToMeal,
          onOpenCanteen: onOpenCanteen,
        ),
      ),
    );
    if (textScale == 1.0) return content;
    return MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: content,
    );
  }

  /// drift 的流在取消时会排一个 0 时长的 Timer（`markAsClosed`）：拆树后
  /// pump 一帧让它跑掉（本仓既有的收尾写法）。
  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  Finder inSlot(String slot, Finder matching) => find.descendant(
    of: find.byKey(Key('nutrition-menu-meal-$slot')),
    matching: matching,
  );

  /// 两个矩形是否落在同一行（纵向有重叠）。
  bool sameRow(Rect a, Rect b) => a.top < b.bottom - 1 && b.top < a.bottom - 1;

  /// 某个 Key 的文字样式（用于断言字阶取自 `LfText` 的哪一档）。
  TextStyle styleOf(WidgetTester tester, Finder text) =>
      tester.widget<Text>(text).style!;

  group('A 页首段头（D25）', () {
    testWidgets('标题 + pill + 合并指引行；页首不再是 hero 卡', (tester) async {
      await seedTarget();
      await seedFiveDishes();
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      // A `app.js:181` 字面：段标题 + `.pill` + `.intro-copy`。
      final title = find.text('每日菜品推荐');
      expect(title, findsOneWidget);
      expect(styleOf(tester, title).fontSize, LfText.title.fontSize);
      expect(styleOf(tester, title).fontWeight, LfText.title.fontWeight);

      final pill = find.text('本地已分析菜品');
      expect(pill, findsOneWidget, reason: 'A 的 .pill「本地已分析菜品」');
      expect(
        find.ancestor(of: pill, matching: find.byType(LfBadge)),
        findsOneWidget,
        reason: 'pill 是共享徽章件（§3.9），不是裸 Container',
      );

      // 指引行 = A 的字面句 + 原 hero 副标题的来源事实（两件都在）。
      final intro = find.textContaining('选好份量后再加入饮食记录');
      expect(intro, findsOneWidget);
      expect(
        tester.widget<Text>(intro).data,
        contains('按你的食堂窗口推荐'),
        reason: '「按你的食堂窗口」是这套推荐真正依赖的本地事实，不随 hero 退场而消失',
      );

      // 页首不再是一张卡：hero 键所指的是纯文字块。
      expect(
        find.ancestor(
          of: find.byKey(const Key('nutrition-menu-hero')),
          matching: find.byType(DesignCard),
        ),
        findsNothing,
        reason: 'A 的菜单页首没有卡（hero 卡退场，D25）',
      );
      // 原 hero 的标题「今日菜单」随之退场（职责被段头承接）。
      expect(find.text('今日菜单'), findsNothing);

      await drain(tester);
    });

    testWidgets('两枚统计搬进汇总行：同排、在段头之下、首个槽卡之上', (tester) async {
      await seedTarget();
      await seedFiveDishes();
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      final planned = find.byKey(const Key('nutrition-menu-hero-planned'));
      final kcal = find.byKey(const Key('nutrition-menu-hero-kcal'));
      expect(planned, findsOneWidget);
      expect(kcal, findsOneWidget);
      expect(
        sameRow(tester.getRect(planned), tester.getRect(kcal)),
        isTrue,
        reason: '「已安排 N 餐」与「预计 X kcal」是同一行里的两段（A 的两列事实）',
      );

      final header = tester.getRect(
        find.byKey(const Key('nutrition-menu-hero')),
      );
      final intro = tester.getRect(find.textContaining('选好份量后再加入饮食记录'));
      final summary = tester.getRect(planned);
      final firstCard = tester.getRect(
        find.byKey(const Key('nutrition-menu-daily-set')),
      );
      expect(summary.top, greaterThan(intro.bottom - 1));
      expect(summary.top, greaterThan(header.top));
      expect(
        firstCard.top,
        greaterThan(summary.bottom),
        reason: '汇总行必须在推荐整套卡之上（页首块整体在推荐区之前）',
      );
      // 整套卡内部：卡头在前，早餐段在卡头之下。
      final setTitle = tester.getRect(
        find.byKey(const Key('nutrition-menu-daily-set-title')),
      );
      final breakfast = tester.getRect(
        find.byKey(const Key('nutrition-menu-meal-breakfast')),
      );
      expect(breakfast.top, greaterThan(setTitle.bottom));

      // 汇总行说的就是原 hero 的两枚统计（口径不变：3 餐 + 三顿主推的热量）。
      expect(
        tester.widget<Text>(planned).data,
        '已安排 3 餐',
        reason: '「3 餐」= 300（粥）+ 600（鸡胸肉饭）+ 200（番茄炒蛋）三顿都有主推',
      );
      expect(tester.widget<Text>(kcal).data, '预计 1100 kcal');
      await drain(tester);
    });

    testWidgets('0 餐时预计写「—」而不是 0 kcal（原 hero 口径）', (tester) async {
      await seedTarget();
      // 空菜品库：一餐都排不出来（0 的意思是「今天不吃」，不能拿它冒充「还没推荐」）。
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<Text>(find.byKey(const Key('nutrition-menu-hero-planned')))
            .data,
        '已安排 0 餐',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('nutrition-menu-hero-kcal')))
            .data,
        '预计 —',
        reason: '未排餐时预计热量写「—」（不写死设计稿的 1470）',
      );
      await drain(tester);
    });

    testWidgets('页首顶距 = A 的 .page padding-top 12（段头是滚动内容第一件）', (tester) async {
      await seedTarget();
      await seedFiveDishes();
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      final header = tester.getRect(
        find.byKey(const Key('nutrition-menu-hero')),
      );
      final scrollTop = tester.getRect(find.byType(CustomScrollView)).top;
      expect(
        header.top - scrollTop,
        12,
        reason: 'A `.page{padding:12px 16px 28px}`（refinement.css:3）',
      );
      await drain(tester);
    });
  });

  group('A 槽卡骨架（D26/D27/D30）', () {
    // 【测试退役】「换一个」在 heading 行右端的几何断言随 `RV4-P2-08`
    // （单格「换一个」退役）删除——断言的**对象**（那枚文字链）不存在了。
    // 替代断言：`daily_set_repick_test.dart` 的「三枚 `-swap` 都不存在」+
    // 「`nutrition-menu-daily-set-repick` 在卡头可点」。
    // 同一处保留一条**反向**几何判据（新按钮在卡内、不越界），防止换个
    // 位置又画出线。
    testWidgets('「换一整套」在卡头且在卡内（RV4-P2-08 替代）', (tester) async {
      await seedTarget();
      await seedFiveDishes();
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      final repick = find.byKey(const Key('nutrition-menu-daily-set-repick'));
      expect(repick, findsOneWidget, reason: '整套重排入口必须在');
      expect(
        find.byKey(const Key('nutrition-menu-meal-breakfast-swap')),
        findsNothing,
        reason: '单格「换一个」已退役',
      );
      final cardRect = tester.getRect(
        find.byKey(const Key('nutrition-menu-daily-set')),
      );
      final rect = tester.getRect(repick);
      expect(rect.left, greaterThanOrEqualTo(cardRect.left - 0.01));
      expect(rect.right, lessThanOrEqualTo(cardRect.right + 0.01));

      // 段头 → 搜索框 → 首卡：两段间距都是 A 的页间隙 16（`gap:16px`）。
      // （原属「换一个」那条用例，那条退役后这段间距判据搬到这里，
      //  判据本身没放宽。）
      final header = tester.getRect(
        find.byKey(const Key('nutrition-menu-hero')),
      );
      final search = tester.getRect(
        find.byKey(const Key('nutrition-menu-search')),
      );
      expect(search.top - header.bottom, 16);
      expect(cardRect.top - search.bottom, 16);

      await drain(tester);
    });

    // 2026-10-16 用户：「推荐菜品点击加入午餐什么的时候，没有提示，请修复」。
    testWidgets('点「加入早餐」成功：给成功提示（原来只有失败提示）', (tester) async {
      await seedTarget();
      await seedFiveDishes();
      var added = 0;
      await tester.pumpWidget(
        host(
          onAddToMeal: (_) async {
            added++;
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('cta-add-meal-0')));
      await tester.pumpAndSettle();

      expect(added, 1, reason: '先把菜真的加进那一餐');
      expect(
        find.textContaining('已加入'),
        findsOneWidget,
        reason: '成功必须上屏（与失败提示同一条通路）',
      );
      await drain(tester);
    });

    testWidgets('块底动作行：查看候选链 + 加入钮同排；钮是 A 的软底档；卡内没有第二枚', (tester) async {
      await seedTarget();
      await seedFiveDishes();
      await tester.pumpWidget(host(onAddToMeal: (_) async {}));
      await tester.pumpAndSettle();

      final candidates = find.byKey(
        const Key('nutrition-menu-meal-breakfast-candidates'),
      );
      final add = find.byKey(const Key('cta-add-meal-0'));
      expect(candidates, findsOneWidget);
      expect(add, findsOneWidget);
      expect(
        find.ancestor(of: candidates, matching: find.byType(LfTextButton)),
        findsOneWidget,
        reason: 'A `.dish-action-row` 左侧是 `link()`',
      );
      expect(
        find.ancestor(of: add, matching: find.byType(LfSoftButton)),
        findsOneWidget,
        reason: 'A「加入<槽>」是 `.btn.outline-brand`（＝阶段 1 的 B10 软底按钮）',
      );
      expect(
        sameRow(tester.getRect(candidates), tester.getRect(add)),
        isTrue,
        reason: 'A 把两件放在同一个 `.dish-action-row` 里（space-between）',
      );
      expect(
        tester.getRect(add).left,
        greaterThan(tester.getRect(candidates).left),
        reason: 'A：候选链在左、加入钮在右',
      );

      // 动作行同样两端对齐（A `.dish-action-row{justify-content:space-between}`，
      // styles.css:300）：候选链贴卡内左边界、加入钮贴卡内右边界。
      final cardRect = tester.getRect(
        find.byKey(const Key('nutrition-menu-meal-breakfast')),
      );
      expect(
        tester.getRect(candidates).left,
        closeTo(cardRect.left + LfDimens.cardPadding, 1.5),
        reason: '候选链在动作行左端',
      );
      expect(
        tester.getRect(add).right,
        closeTo(cardRect.right - LfDimens.cardPadding, 1.5),
        reason: '加入钮在动作行右端（A 的两端）',
      );

      // 加入动作归动作行：卡内不再画第二枚加入钮（D27）。
      expect(
        find.descendant(
          of: find.byKey(const Key('nutrition-menu-dish-card-0')),
          matching: find.byType(LfPrimaryButton),
        ),
        findsNothing,
      );
      expect(
        inSlot('breakfast', find.byType(LfSoftButton)),
        findsOneWidget,
        reason: '一块只有一枚加入钮',
      );

      // 按钮标签仍是菜自己餐次（docs/21 §5.3 文案裁决不变）。
      expect(find.text('加入早餐'), findsWidgets);
      await drain(tester);
    });
  });

  group('A 页尾（D28/D29）', () {
    testWidgets('list-link「管理食堂目录」+ A 的 note；入口仍可达', (tester) async {
      var opened = 0;
      await seedTarget();
      await seedFiveDishes();
      // note 说的是「加入餐次」这件事，所以必须走接了加入动作的装配
      // （没接线时不写这句：说了也没用，D28）。
      await tester.pumpWidget(
        host(onOpenCanteen: () => opened++, onAddToMeal: (_) async {}),
      );
      await tester.pumpAndSettle();

      final link = find.byKey(const Key('cta-manage-canteen'));
      expect(link, findsOneWidget);
      expect(
        find.textContaining('地点、窗口与菜品'),
        findsOneWidget,
        reason: 'A 的 list-link 副行（app.js:185）',
      );

      // A：list-link 在推荐区之后、note 之前。
      final lastSlot = tester.getRect(
        find.byKey(const Key('nutrition-menu-meal-dinner')),
      );
      final note = find.byKey(const Key('nutrition-menu-note'));
      expect(note, findsOneWidget, reason: 'A 的 `.subtle-note` 中在本仓成立的那半句');
      expect(
        tester.widget<Text>(note).data,
        contains('加入餐次会记为已吃'),
        reason: 'docs/21 §5.3 的 `nutrition-menu-note` 契约',
      );
      expect(
        tester.widget<Text>(note).data,
        isNot(contains('演示样例')),
        reason: 'A 的前半句是原型免责声明：本仓的数据是真实分析结果，搬过来是假话（D28）',
      );
      expect(tester.getRect(link).top, greaterThan(lastSlot.bottom));
      expect(
        tester.getRect(note).top,
        greaterThan(tester.getRect(link).bottom),
      );

      await tester.tap(link);
      await tester.pump();
      expect(opened, 1, reason: 'list-link 承接原 hero 圆钮的同一路由');
      await drain(tester);
    });
  });

  group('2.0× / 320dp（A 无此档位，宁可换行不裁字）', () {
    testWidgets('段头/heading/动作行全部换行扩高、无溢出、不裁字', (tester) async {
      await seedTarget();
      await seedFiveDishes();
      tester.view.physicalSize = const Size(320, 6000);
      await tester.pumpWidget(host(textScale: 2.0));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      final card = tester.getRect(
        find.byKey(const Key('nutrition-menu-meal-breakfast')),
      );
      for (final key in const [
        'nutrition-menu-hero',
        'nutrition-menu-daily-set-repick',
        'nutrition-menu-meal-breakfast-candidates',
        'cta-add-meal-0',
      ]) {
        final rect = tester.getRect(find.byKey(Key(key)));
        expect(
          rect.left,
          greaterThanOrEqualTo(card.left - 0.01),
          reason: '$key 必须在卡内（大字下不越界）',
        );
        expect(rect.right, lessThanOrEqualTo(card.right + 0.01));
      }
      await drain(tester);
    });
  });
}

class _Ids implements IdGenerator {
  int _next = 0;

  @override
  String next() => 'id-${++_next}';
}
