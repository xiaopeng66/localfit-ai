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
import 'package:localfit_ai/features/nutrition/presentation/sections/meal_record_card.dart';
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
    void Function(List<MealRecord> records)? onEditSlot,
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
              onEditSlot: onEditSlot,
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
    // 【2026-10-31 断言语义变更（用户：热量行直接放标题后边，强度不降）】
    // 2026-10-25 曾把槽位汇总改成「只说条数」——因为当时合计 kcal 在卡内
    // 另起一行（「晚餐」下面还有一行「晚餐 N kcal」）。用户 2026-10-31：
    // 「标题晚餐下边还有一行显示晚餐和热量，不需要，直接放在标题晚餐后边」
    // ⇒ 卡内热量行整行退役（embedded 不画卡头），合计 kcal 挪到槽位头标题
    // 后面；多条记录时同时说清条数。合计数字一个没少，只是换了位置。
    expect(tester.widget<Text>(total(MealSlot.breakfast)).data, '116 kcal');
    expect(tester.widget<Text>(total(MealSlot.lunch)).data, '348 kcal · 2 条记录');
    // 无记录的两个槽位:A 写 `尚未记录`(不是 `0 kcal`——「无记录 ≠ 零值记录」)。
    expect(tester.widget<Text>(total(MealSlot.dinner)).data, '尚未记录');
    expect(tester.widget<Text>(total(MealSlot.snack)).data, '尚未记录');
    // 【2026-10-25 断言语义变更（需求 20b，强度不降）】原断言是「午餐两条
    // 记录各是一张卡，各写自己的 116 / 232 kcal」。用户 2026-10-25：
    // 「午餐就都放一起，不要因为我后边记的就分开显示」——同一餐次的多条记录
    // **合并成一张卡**，卡上写的是**两条之和**（348），而槽位小计同样是 348。
    //
    // 【2026-10-31 再改（用户：热量行直接放标题后边）】卡内热量行退役后，
    // 「348」这个合计数字的唯一落点是槽位头（`348 kcal · 2 条记录`）——
    // 判据改写为：槽位头完整写全合计（含条数），且两条记录的食物行都还在。
    expect(
      find.descendant(of: slotCard(MealSlot.lunch), matching: find.text('116')),
      findsNothing,
      reason: '合并后不再有「各自一张卡」的 116',
    );
    expect(
      find.descendant(of: slotCard(MealSlot.lunch), matching: find.text('232')),
      findsNothing,
      reason: '同上：232 不再单独成卡',
    );
    expect(
      find.descendant(
        of: slotCard(MealSlot.lunch),
        matching: find.text('348 kcal · 2 条记录'),
      ),
      findsOneWidget,
      reason: '槽位头完整写全合计（= 两条之和）与条数',
    );
    expect(
      find.descendant(
        of: slotCard(MealSlot.lunch),
        matching: find.text('午餐饭 100g'),
      ),
      findsOneWidget,
      reason: '合并卡的**第一组**菜品行仍在',
    );
    expect(
      find.descendant(
        of: slotCard(MealSlot.lunch),
        matching: find.text('午餐加饭 200g'),
      ),
      findsOneWidget,
      reason: '合并卡的**第二组**菜品行仍在（食物都在一起）',
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

  // 【语义变更，2026-10-27（docs/64 阶段 4 B-3，用户裁决「30 天，继续」）】
  // 这条原钉「历史日期一律不加号（历史只读）」。裁决后改成可补记近 30 天，
  // 于是拆成两条**更强**的边界断言：窗口内可补记（且有「补记」徽标、
  // 点了真的触发回调），窗口外仍不可补记（且如实说窗口）。
  testWidgets('历史日期（窗口内）:可补记 + 「补记」徽标;空槽位文案仍是历史句', (tester) async {
    // **必须传 onAddToSlot**:传 null 时「没有加号」可能只是因为调用方没接线
    // (那是另一条契约,由下一个用例的 null 分支钉)。
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
        findsOneWidget,
        reason: '${slot.label}:昨天在 30 天补记窗口内，必须能补记',
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
    expect(
      find.byKey(const Key('nutrition-record-backfill-badge')),
      findsNWidgets(MealSlot.values.length),
      reason: '非今天每张槽位卡都要有「补记」徽标（免得看成今天）',
    );
    // 今天用的是另一句(`还没记录这一餐`),与历史分开。
    expect(find.text('还没记录这一餐'), findsNothing);
    // 补记徽章在场时空槽**不再写「尚未记录」**:徽章 + 空态行已把状态说完,
    // 再挤一个「尚未记录」在 2.0× 窄屏会把槽位名截成「尚…」。
    expect(find.text('尚未记录'), findsNothing);
    await tester.tap(find.byKey(const Key('nutrition-record-slot-lunch-add')));
    expect(tapped, [MealSlot.lunch], reason: '补记入口必须真的触发写入入口');
    await drainStream(tester);
  });

  testWidgets('历史日期（窗口外，31 天前）:不加号 + 如实说「只支持补记近 30 天」', (tester) async {
    final tapped = <MealSlot>[];
    await pumpGrouping(
      tester,
      localDate: '2026-08-09', // now(2026-09-09) − 31 天
      selectedDate: DateTime(2026, 8, 9),
      onAddToSlot: tapped.add,
    );

    for (final slot in MealSlot.values) {
      expect(
        find.byKey(Key('nutrition-record-slot-${slot.storedValue}-add')),
        findsNothing,
        reason: '${slot.label}:超过 30 天不给补记入口',
      );
    }
    expect(
      find.byKey(const Key('nutrition-record-backfill-window-note')),
      findsOneWidget,
      reason: '窗口外要如实说窗口，不能默默少一个按钮',
    );
    expect(tapped, isEmpty);
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

  testWidgets('整卡编辑只传被点击槽位的记录，不会把其它餐次合并', (tester) async {
    final breakfastId = await addMeal(
      date: today,
      slot: MealSlot.breakfast,
      hour: 8,
      grams: 80,
      foodName: '鸡蛋',
    );
    final lunchId = await addMeal(
      date: today,
      slot: MealSlot.lunch,
      hour: 12,
      grams: 150,
      foodName: '番茄牛腩煲',
    );
    List<MealRecord>? edited;
    await pumpGrouping(
      tester,
      localDate: today,
      selectedDate: DateTime(2026, 9, 9),
      onEditSlot: (records) => edited = records,
    );

    await tester.tap(find.byKey(Key('meal-$lunchId')));
    await tester.pump();

    expect(edited, isNotNull);
    expect(edited!.map((meal) => meal.id), [lunchId]);
    expect(edited!.map((meal) => meal.id), isNot(contains(breakfastId)));
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
    // 槽位头合计按同一份食物数据手算（不硬编码，防目录改值后假红/假绿）。
    final stew = (await foods.search('番茄牛腩煲')).first;
    final expectedKcal = ((stew.kcalPer100g * 150) / 100).round();
    await pumpGrouping(
      tester,
      localDate: today,
      selectedDate: DateTime(2026, 9, 9),
      onEditSlot: (_) {},
    );

    final lunchCard = find.byKey(const Key('nutrition-record-slot-lunch'));
    expect(lunchCard, findsOneWidget);
    // 既有稳定 Key 一个不少(多选/编辑/来源都按这些键定位)。
    expect(find.byKey(Key('meal-$lunchId')), findsOneWidget);
    // 【2026-10-31 断言改写（用户：右下角三个点直接删掉，强度不降）】原断言
    // 钉住 `meal-manage-<id>`（⋮ 管理菜单圆钮）。菜单整件退役后其全部职责由
    // **整卡点击**承接（整卡开「该槽位全部已添加食物」编辑），长按多选不变；
    // 换成对这一新契约的更强断言：卡本体可点（onTapCard 已接），⋮ 键不再出现。
    expect(find.byKey(Key('meal-manage-$lunchId')), findsNothing);
    // 卡本体可点（onTapCard 已接）= ⋮ 菜单退役后的合并编辑入口。
    final cardWidget = tester.widget<MealRecordCard>(
      find.byType(MealRecordCard),
    );
    expect(
      cardWidget.onTapCard,
      isNotNull,
      reason: '⋮ 菜单退役后，整卡点击 = 编辑该槽位全部已添加食物',
    );
    // 【N-1 改写】来源徽标撤下（用户原话见 run-log）。
    expect(find.byKey(Key('meal-source-$lunchId')), findsNothing);
    // 项行仍是「名称 + 克数」（每条事实一行）。
    expect(find.text('番茄牛腩煲 150g'), findsOneWidget);
    // 【2026-10-25 断言语义变更（需求 20a，强度不降）】原断言是「`meal-totals`
    // 那一行写 `蛋白质 Xg · 碳水 Yg · 脂肪 Zg`」。用户 2026-10-25 点名：
    // 「三宏量有的根本看不见，被挡住了，变成省略号了，可以不显示三宏量，
    // 只显示热量」。于是那行整行退役（Key 一并退役，见证据文件退役清单）。
    // 判据改成**更强的一组**：视觉上不再出现宏量、但读屏仍能拿到（数字不丢）。
    expect(
      find.byKey(Key('meal-totals-$lunchId')),
      findsNothing,
      reason: '需求 20a：合计宏量那行整行退役',
    );
    expect(find.text('蛋白质'), findsNothing);
    expect(find.text('碳水'), findsNothing);
    expect(find.text('脂肪'), findsNothing);
    expect(
      find.bySemanticsLabel(RegExp('蛋白质')),
      findsWidgets,
      reason: '需求 20a 第 5 条：宏量退到读屏语义，信息不丢',
    );
    // 【2026-10-31 断言随热量位移动改写（强度不降）】卡内大号位退役
    // （embedded），热量数字的唯一落点是槽位头合计——`meal-kcal` 只属于
    // 非 embedded 形态；这里改钉槽位头合计行完整写全。
    expect(
      find.byKey(Key('meal-kcal-$lunchId')),
      findsNothing,
      reason: 'embedded 卡面不再画热量行（挪到槽位头标题后边）',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const Key('nutrition-record-slot-lunch-total')),
          )
          .data,
      '$expectedKcal kcal',
      reason: '热量在槽位头上完整可读（150g 番茄牛腩煲按每百克手算核对）',
    );
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
