import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/design/widgets/design_card.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/food_record.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/nutrition_record_slot_grouping.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/record_tab.dart';

/// 记录页的**槽位分组**(docs/33 阶段 2B 步骤 5,Round7 A `nutritionRecords()`)。
///
/// A 把当日的餐食按 `['早餐','午餐','晚餐','加餐']` 分进四张
/// `.meal-slot-card`:每张 = 槽位图标(28 无底)+ 槽位名 + 槽位合计
/// (`N kcal` / `尚未记录`)+(**仅今天**)加号;行区要么是餐食行,要么是
/// `.empty-meal` 一行空态。
///
/// 本仓按 D3/D16 保留每餐的**完整事实**(克数/宏量/来源/备注/管理菜单),
/// 但去掉卡中卡:槽位卡内嵌 `MealRecordCard(embedded: true)`。
///
/// 本文件同时钉住 2A 渲染审看登记的**改造前缺陷 3**(菜品名被
/// `maxLines/ellipsis` 截断成「番茄牛腩煲 32...」)。
void main() {
  late AppDatabase database;
  late FoodRepository foods;
  late MealRepository meals;

  final now = DateTime(2026, 9, 9, 12);
  const today = '2026-09-09';
  const yesterday = '2026-09-08';

  /// 整个文件共用一条 id 池:见 [addMeal] 的注释。
  final seedIds = _IncrementingIdGenerator();

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    // 食物仓储用另一条池,避免与餐食 id 抢号(两条池各自单调即可)。
    foods = FoodRepository(
      database: database,
      idGenerator: _IncrementingIdGenerator(),
      clock: FixedAppClock(now.toUtc()),
    );
    meals = MealRepository(
      database: database,
      idGenerator: seedIds,
      clock: FixedAppClock(now.toUtc()),
    );
  });

  tearDown(() => database.close());

  Future<FoodRecord> insertFood(String name, {double kcal = 116}) async {
    final id = 'food-${name.hashCode.abs()}';
    await database
        .into(database.foods)
        .insert(
          FoodsCompanion.insert(
            id: id,
            name: name,
            kcalPer100g: kcal,
            proteinPer100g: 2.6,
            carbsPer100g: 25.9,
            fatPer100g: 0.3,
            source: 'seed',
            createdAt: now.toUtc(),
            updatedAt: now.toUtc(),
          ),
        );
    return (await foods.search(name)).firstWhere((food) => food.id == id);
  }

  /// 加餐记录;返回 meal.id 供 `meal-<id>` 定位。
  ///
  /// [hour] 需显式给:`MealDraft` 不带时间,`create()` 一律取
  /// `clock.nowUtc()`(固定时钟下同槽位的多条记录时间相同,顺序就没有依据)。
  /// 这里按需换一个临时仓储把时间钉住——写库仍是同一条 `create` 路径。
  ///
  /// id 池必须**全测试共用一个**(_SeedIds):每条记录都建一个自带计数器的
  /// 仓储会让第二条也拿到 `slot-0`,`meals.id` 直接撞唯一约束。
  Future<String> addMeal({
    required String date,
    required MealSlot slot,
    required int hour,
    double grams = 100,
    String foodName = '米饭',
    String? source,
  }) async {
    final food = await insertFood(foodName);
    final at = DateTime(
      int.parse(date.substring(0, 4)),
      int.parse(date.substring(5, 7)),
      int.parse(date.substring(8)),
      hour,
    );
    final repo = MealRepository(
      database: database,
      idGenerator: seedIds,
      clock: FixedAppClock(at.toUtc()),
    );
    return repo.create(
      MealDraft(
        localDate: date,
        slot: slot,
        items: [MealItemDraft.fromFood(food, grams)],
      ),
      source: source ?? 'manual',
    );
  }

  /// 只挂分组件本身(组件的全部输入都是显式的,不必经整页)。
  Future<void> pumpGrouping(
    WidgetTester tester, {
    required String localDate,
    required DateTime selectedDate,
    ValueChanged<MealSlot>? onAddToSlot,
    ValueChanged<MealRecord>? onEdit,
    Size size = const Size(900, 1600),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: NutritionRecordSlotGrouping(
              repository: meals,
              localDate: localDate,
              now: now,
              onEdit: onEdit ?? (_) {},
              onDelete: (_) {},
              onAddToSlot: onAddToSlot,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 排掉 drift StreamBuilder dispose 时 schedule 的「0 时延」close timer。
  Future<void> drainStream(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('四个槽位卡按 MealSlot 域序渲染,标题为槽位名', (tester) async {
    await pumpGrouping(
      tester,
      localDate: today,
      selectedDate: DateTime(2026, 9, 9),
    );

    // A 的槽位序 `['早餐','午餐','晚餐','加餐']` = MealSlot.values 的域序。
    for (final slot in MealSlot.values) {
      expect(
        find.byKey(Key('nutrition-record-slot-${slot.storedValue}')),
        findsOneWidget,
        reason: '槽位卡 ${slot.storedValue}',
      );
    }
    final tops = [
      for (final slot in MealSlot.values)
        tester
            .getRect(
              find.byKey(Key('nutrition-record-slot-${slot.storedValue}')),
            )
            .top,
    ];
    expect(tops, orderedEquals([...tops]..sort()), reason: '四卡必须自上而下按域序');
    for (final slot in MealSlot.values) {
      expect(
        find.descendant(
          of: find.byKey(Key('nutrition-record-slot-${slot.storedValue}')),
          matching: find.text(slot.label),
        ),
        findsOneWidget,
        reason: '槽位名 ${slot.label}',
      );
    }
    await drainStream(tester);
  });

  testWidgets('槽位合计 = 该槽位当日各餐之和;空槽位写「尚未记录」', (tester) async {
    // 早餐 100g 米饭 = 116 kcal;午餐两餐 100g + 200g = 348 kcal。
    await addMeal(
      date: today,
      slot: MealSlot.breakfast,
      hour: 8,
      grams: 100,
      foodName: '早餐饭',
    );
    await addMeal(
      date: today,
      slot: MealSlot.lunch,
      hour: 12,
      grams: 100,
      foodName: '午餐饭',
    );
    await addMeal(
      date: today,
      slot: MealSlot.lunch,
      hour: 13,
      grams: 200,
      foodName: '午餐加饭',
    );
    await pumpGrouping(
      tester,
      localDate: today,
      selectedDate: DateTime(2026, 9, 9),
    );

    Finder slotCard(MealSlot slot) =>
        find.byKey(Key('nutrition-record-slot-${slot.storedValue}'));
    Finder total(MealSlot slot) => find.descendant(
      of: slotCard(slot),
      matching: find.byKey(
        Key('nutrition-record-slot-${slot.storedValue}-total'),
      ),
    );
    // 槽位合计走自己的锚点:槽位合计与卡内餐食合计会写出同值文本(单餐时
    // 两者恒等),按整卡查文本会撞上「两个 116 kcal」——它们是**两个不同的
    // 事实**(槽位小计 / 该餐总计),各自都要在屏上。
    expect(tester.widget<Text>(total(MealSlot.breakfast)).data, '116 kcal');
    expect(tester.widget<Text>(total(MealSlot.lunch)).data, '348 kcal');
    // 无记录的两个槽位:A 写 `尚未记录`(不是 `0 kcal`——「无记录 ≠ 零值记录」)。
    expect(tester.widget<Text>(total(MealSlot.dinner)).data, '尚未记录');
    expect(tester.widget<Text>(total(MealSlot.snack)).data, '尚未记录');
    // 每餐自己的合计仍在(内嵌形态不吞内容):午餐两条餐卡各写自己的 116 /
    // 232 kcal,与槽位合计 348 kcal 三者并存。
    // 2026-10-16（用户选定第一案）：餐卡热量改成「大数字 + 小单位」两段，
    // 于是按「116」+「kcal」两个文本各查一次（槽位合计那处仍是一整串）。
    Finder cardKcal(String amount) => find.descendant(
      of: slotCard(MealSlot.lunch),
      matching: find.text(amount),
    );
    expect(cardKcal('116'), findsWidgets);
    expect(cardKcal('232'), findsWidgets);
    expect(
      find.descendant(
        of: slotCard(MealSlot.lunch),
        matching: find.text('kcal'),
      ),
      findsWidgets,
      reason: '单位小字仍在餐卡里',
    );
    await drainStream(tester);
  });

  testWidgets('今天:四个槽位各带加号,点击回调收到对应槽位(D19)', (tester) async {
    final tapped = <MealSlot>[];
    await pumpGrouping(
      tester,
      localDate: today,
      selectedDate: DateTime(2026, 9, 9),
      onAddToSlot: tapped.add,
    );

    for (final slot in MealSlot.values) {
      final add = find.byKey(
        Key('nutrition-record-slot-${slot.storedValue}-add'),
      );
      expect(add, findsOneWidget, reason: '今天的 ${slot.label} 加号');
      await tester.tap(add);
      await tester.pumpAndSettle();
    }
    expect(tapped, orderedEquals(MealSlot.values));
    await drainStream(tester);
  });

  testWidgets('历史日期:不加号;空槽位文案换成「当天没有这餐记录」', (tester) async {
    // **必须传 onAddToSlot**:传 null 时「没有加号」可能只是因为调用方没接线
    // (那是另一条契约,由下一个用例的 null 分支钉),钉不住 A 的
    // `ui.date === state.today` 判定。传了回调而加号仍不出现,才是本条。
    final tapped = <MealSlot>[];
    await pumpGrouping(
      tester,
      localDate: yesterday,
      selectedDate: DateTime(2026, 9, 8),
      onAddToSlot: tapped.add,
    );

    for (final slot in MealSlot.values) {
      expect(
        find.byKey(Key('nutrition-record-slot-${slot.storedValue}-add')),
        findsNothing,
        reason: 'A 的加号只在 `ui.date === state.today` 时渲染',
      );
      expect(
        find.descendant(
          of: find.byKey(Key('nutrition-record-slot-${slot.storedValue}')),
          matching: find.text('当天没有这餐记录'),
        ),
        findsOneWidget,
        reason: '${slot.label} 的历史空态',
      );
    }
    // 今天用的是另一句(`还没记录这一餐`),与历史分开。
    expect(find.text('还没记录这一餐'), findsNothing);
    expect(tapped, isEmpty, reason: '历史日不该有任何写入入口被触发');
    await drainStream(tester);
  });

  testWidgets('未接 onAddToSlot:今天也不画加号(宁可少入口,不弹空编辑框)', (tester) async {
    await pumpGrouping(
      tester,
      localDate: today,
      selectedDate: DateTime(2026, 9, 9),
    );

    for (final slot in MealSlot.values) {
      expect(
        find.byKey(Key('nutrition-record-slot-${slot.storedValue}-add')),
        findsNothing,
        reason: '未接线时 ${slot.label} 的加号也不出现',
      );
    }
    await drainStream(tester);
  });

  testWidgets('空槽位一行带 key,今天写「还没记录这一餐」', (tester) async {
    await pumpGrouping(
      tester,
      localDate: today,
      selectedDate: DateTime(2026, 9, 9),
    );

    for (final slot in MealSlot.values) {
      final empty = find.byKey(
        Key('nutrition-record-slot-${slot.storedValue}-empty'),
      );
      expect(empty, findsOneWidget, reason: '${slot.label} 空态行');
      expect(
        find.descendant(of: empty, matching: find.text('还没记录这一餐')),
        findsOneWidget,
      );
    }
    // A 没有「日级空态」这一件:没有记录就是四张空槽位卡,不再另画一整块
    // (D23——旧日级整块空态退场,信息由四行槽位空态承载,仍是逐槽位可行动)。
    expect(find.text('当天还没有餐食记录。'), findsNothing);
    expect(find.text('点右下角「+」开始手动记餐。'), findsNothing);
    await drainStream(tester);
  });

  testWidgets('槽位内的餐卡走内嵌形态(D16):无卡中卡,但 Key 与内容零删除', (tester) async {
    final lunchId = await addMeal(
      date: today,
      slot: MealSlot.lunch,
      hour: 12,
      grams: 150,
      foodName: '番茄牛腩煲',
      source: 'ai_scan',
    );
    await pumpGrouping(
      tester,
      localDate: today,
      selectedDate: DateTime(2026, 9, 9),
    );

    final lunchCard = find.byKey(const Key('nutrition-record-slot-lunch'));
    expect(lunchCard, findsOneWidget);
    // 既有稳定 Key 一个不少(多选/编辑/来源/管理菜单都按这些键定位)。
    expect(find.byKey(Key('meal-$lunchId')), findsOneWidget);
    expect(find.byKey(Key('meal-manage-$lunchId')), findsOneWidget);
    expect(find.byKey(Key('meal-source-$lunchId')), findsOneWidget);
    // 完整事实仍在，但**一条一行**：2026-10-16 用户实测「餐食卡食物多了很乱、
    // 很多标签文字」——三枚合计宏量 chip 合成一行 muted 小字（`meal-totals`），
    // 项行只留「名称 + 克数」。
    expect(find.text('番茄牛腩煲 150g'), findsOneWidget);
    final totalsText = tester.widget<Text>(
      find.byKey(Key('meal-totals-$lunchId')),
    );
    expect(
      totalsText.data,
      matches(r'^蛋白质 [\d.]+g · 碳水 [\d.]+g · 脂肪 [\d.]+g$'),
    );
    // 旧形态的三枚独立 chip 文案不再各自成件。
    expect(find.text('蛋白质'), findsNothing);
    expect(find.text('碳水'), findsNothing);
    expect(find.text('脂肪'), findsNothing);
    // 内嵌 = 槽位卡内**不再**出现第二层 DesignCard。`meal-<id>` 的**最近**
    // 一个 DesignCard 祖先必须是槽位卡本身(即两者之间没有夹着第二张卡)。
    final nearestCard = find
        .ancestor(
          of: find.byKey(Key('meal-$lunchId')),
          matching: find.byType(DesignCard),
        )
        .evaluate()
        .last
        .widget;
    expect(
      (nearestCard as DesignCard).key,
      const Key('nutrition-record-slot-lunch'),
      reason: '槽位卡内的餐卡不得再套一层 DesignCard(卡中卡)',
    );
    // 槽位卡本身仍是卡(A `.meal-slot-card` 是 `.card`)。
    expect(
      find.byKey(const Key('nutrition-record-slot-lunch')),
      findsOneWidget,
    );
    await drainStream(tester);
  });

  testWidgets('缺陷 3:菜品行不再 ellipsis 截断,长菜名折行扩高', (tester) async {
    final longName = '番茄牛腩煲配杂粮饭与炝炒时蔬再加一份香煎鸡胸肉与牛油果沙拉佐油醋汁和味增汤';
    final id = await addMeal(
      date: today,
      slot: MealSlot.lunch,
      hour: 12,
      grams: 320,
      foodName: longName,
    );
    // 窄屏:320dp 卡内宽约 256dp,长名必然折行(宿主尺寸由 [pumpGrouping]
    // 的 `size` 给定——它在内部设置物理尺寸,不能提前设了再被覆盖)。
    await pumpGrouping(
      tester,
      localDate: today,
      selectedDate: DateTime(2026, 9, 9),
      size: const Size(320, 1600),
    );

    // 结构判据:该行文字不再有单行截断约束。
    final nameText = tester.widget<Text>(find.textContaining(longName).first);
    expect(nameText.maxLines, isNull, reason: '去掉 maxLines: 1');
    expect(
      nameText.overflow,
      isNot(TextOverflow.ellipsis),
      reason: '去掉 TextOverflow.ellipsis',
    );
    // 行为判据:文字盒真的比一行高(折行扩高,而不是被裁)。
    expect(
      tester.getSize(find.textContaining(longName).first).height,
      greaterThan(21 * 1.5), // 一行 21dp(LfText.body 14×1.5)
      reason: '长菜名必须折成多行并撑高行盒',
    );
    // 整条行仍然完整渲染到卡内(没有横向溢出)。
    expect(find.byKey(Key('meal-$id')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await drainStream(tester);
  });

  testWidgets('同一槽位内多餐按 eatenAt 升序(早的在上)', (tester) async {
    await addMeal(
      date: today,
      slot: MealSlot.lunch,
      hour: 13,
      grams: 100,
      foodName: '后吃的',
    );
    await addMeal(
      date: today,
      slot: MealSlot.lunch,
      hour: 11,
      grams: 100,
      foodName: '先吃的',
    );
    await pumpGrouping(
      tester,
      localDate: today,
      selectedDate: DateTime(2026, 9, 9),
    );

    final lunch = find.byKey(const Key('nutrition-record-slot-lunch'));
    final first = tester.getRect(
      find.descendant(of: lunch, matching: find.text('先吃的 100g')),
    );
    final second = tester.getRect(
      find.descendant(of: lunch, matching: find.text('后吃的 100g')),
    );
    expect(first.top, lessThan(second.top));
    await drainStream(tester);
  });

  testWidgets('记录页接线:今天有加号且走 initialSlot 通道(不新增写入路径)', (tester) async {
    tester.view.physicalSize = const Size(400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final slots = <MealSlot>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecordTab(
            mealRepository: meals,
            selectedDate: DateTime(2026, 9, 9),
            now: now,
            onSelectDate: (_) {},
            onEditMeal: (_) {},
            onDeleteMeal: (_) {},
            onAddToSlot: slots.add,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final add = find.byKey(const Key('nutrition-record-slot-snack-add'));
    await tester.scrollUntilVisible(
      add,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(add);
    await tester.pumpAndSettle();
    expect(slots, [MealSlot.snack]);
    await drainStream(tester);
  });
}

final class _IncrementingIdGenerator implements IdGenerator {
  int _value = 0;

  @override
  String next() => 'slot-${_value++}';
}
