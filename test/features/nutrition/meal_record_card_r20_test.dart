import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/nutrition_record_slot_grouping.dart';

/// **需求 20 的独立复核**（用户 2026-10-25 原话 + 2026-10-26「你要自己截图验证」）。
///
/// 用户原话（docs/60 §6.6）：
/// > 「三宏量有的根本看不见，被挡住了，变成省略号了，可以不显示三宏量，
/// >   只显示热量」；「去掉时间显示，午餐就都放一起，不要因为我后边记的
/// >   就分开显示」。
///
/// 本文件**不问实现怎么写的**，只按「用户看得见的事实」逐条问，
/// 并且走**真实链路**（真数据库 → 真仓储 → 真槽位分组 → 真餐卡）：
///
/// 1. 卡面上还有没有 `HH:mm`？（时间只能出现在管理菜单里，用来指认改哪一条）
/// 2. 同一餐次记两次 → 屏幕上几张卡？（一张；两条记录都在同一张卡里）
/// 3. 两段记录之间有没有分隔线、位置对不对？（「这是两次记录」这件事没被抹掉）
/// 4. 卡头那个数字是不是两条之和？（**自己按克数手算一遍**再比对显示值）
/// 5. 三宏量是不是从卡面消失、但读屏仍拿得到？（数字不丢，且与手算值逐个相等）
/// 6. 点第二段是不是改第二条记录？（按原 `meal.id`，不是按卡）
/// 7. 多选时每条记录是不是各有自己的勾选圈？
/// 8. 320dp × 2.0× 字号下会不会溢出？（用户最容易碰到的极端）
void main() {
  late AppDatabase database;
  late FoodRepository foods;
  late MealRepository meals;
  late _Ids ids;

  const localDate = '2026-10-26';
  final now = DateTime(2026, 10, 26, 18);

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    // id 池必须**全程共用**：各建一个计数器会让第二条记录也拿到 `v-0`，
    // 直接撞主键（round11 取帧件第一版就是这么红的）。
    ids = _Ids();
    foods = FoodRepository(
      database: database,
      idGenerator: ids,
      clock: FixedAppClock(now),
    );
    meals = MealRepository(
      database: database,
      idGenerator: ids,
      clock: FixedAppClock(now),
    );
  });

  tearDown(() => database.close());

  /// 建一条午餐记录（返回 `meal.id`）。
  ///
  /// 时间要显式给：`MealDraft` 不带时间，`create()` 一律取 `clock.nowUtc()`
  /// ——固定时钟下两条记录会同一时刻，就没法验证「按时刻指认哪一条」。
  Future<String> record({
    required int hour,
    required String food,
    required double grams,
    String? notes,
  }) async {
    final item = (await foods.search(food)).first;
    final repository = MealRepository(
      database: database,
      idGenerator: ids,
      clock: FixedAppClock(DateTime(2026, 10, 26, hour)),
    );
    return repository.create(
      MealDraft(
        localDate: localDate,
        slot: MealSlot.lunch,
        items: [MealItemDraft.fromFood(item, grams)],
        notes: notes,
      ),
      source: 'manual',
    );
  }

  /// 用户原话的场景：中午记一次、下午又记一次。
  ///
  /// 两条的数值**刻意取不同**，好让「合计」这件事能自己算一遍核对：
  /// - 红烧肉盖浇饭 156 kcal/100g × 250 g = 390；蛋白质 20 / 碳水 50 / 脂肪 12.5
  /// - 凉拌黄瓜      45 kcal/100g × 120 g =  54；蛋白质 1.2 / 碳水 3.6 / 脂肪 2.4
  /// - 合计 **444 kcal**；蛋白质 **21.2 g**；碳水 **53.6 g**；脂肪 **14.9 g**
  Future<({String first, String second})> seedLunch() async {
    for (final (id, name, kcal, protein, carbs, fat) in const [
      ('f-braised', '红烧肉盖浇饭', 156.0, 8.0, 20.0, 5.0),
      ('f-cucumber', '凉拌黄瓜', 45.0, 1.0, 3.0, 2.0),
    ]) {
      await database
          .into(database.foods)
          .insert(
            FoodsCompanion.insert(
              id: id,
              name: name,
              kcalPer100g: kcal,
              proteinPer100g: protein,
              carbsPer100g: carbs,
              fatPer100g: fat,
              source: 'seed',
              createdAt: now,
              updatedAt: now,
            ),
          );
    }
    final first = await record(
      hour: 12,
      food: '红烧肉盖浇饭',
      grams: 250,
      notes: '食堂二楼',
    );
    final second = await record(hour: 13, food: '凉拌黄瓜', grams: 120);
    return (first: first, second: second);
  }

  /// 只挂分组件本身（它的全部输入都是显式的，不必经整页）。
  Future<void> pumpGrouping(
    WidgetTester tester, {
    bool selectionMode = false,
    Set<String> selectedIds = const {},
    Set<String> selectedItemIds = const {},
    void Function(List<MealRecord> records)? onEditSlot,
    ValueChanged<MealRecord>? onToggleSelected,
    void Function(MealRecord meal, MealItemRecord item)? onToggleItemSelected,
    double width = 412,
    double textScale = 1.0,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 1600);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(
          size: Size(width, 1600),
          textScaler: TextScaler.linear(textScale),
        ),
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: NutritionRecordSlotGrouping(
                repository: meals,
                localDate: localDate,
                now: now,
                onEditSlot: onEditSlot,
                selectionMode: selectionMode,
                selectedIds: selectedIds,
                selectedItemIds: selectedItemIds,
                onToggleSelected: onToggleSelected,
                onToggleItemSelected: onToggleItemSelected,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 排掉 drift 的 StreamBuilder 在 dispose 时排的「0 时延」close timer
  /// （不排掉会以「A Timer is still pending」在收尾处报红）。
  Future<void> drainStream(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  Finder lunchSlot() => find.byKey(const Key('nutrition-record-slot-lunch'));

  // 【2026-10-31 用户：「每个食物独立勾选删除，而不是整餐删除」】
  // 食物圈以 `MealItemRecord.id` 为身份，不再映射到 meal.id；回调同时带回
  // 所属记录与当前食物，删除范围可以精确到 item。
  testWidgets('多选态：每条食物都有独立勾选圈，回调定位到 item.id', (tester) async {
    final seeded = await seedLunch();
    final first = (await meals.getById(seeded.first))!;
    final second = (await meals.getById(seeded.second))!;
    final firstItem = first.items.single;
    final secondItem = second.items.single;
    final toggled = <String>[];
    await pumpGrouping(
      tester,
      selectionMode: true,
      selectedItemIds: {firstItem.id},
      onToggleItemSelected: (meal, item) =>
          toggled.add('${meal.id}:${item.id}'),
    );

    expect(
      find.byKey(Key('meal-food-select-circle-${firstItem.id}')),
      findsOneWidget,
    );
    expect(
      find.byKey(Key('meal-food-select-circle-${secondItem.id}')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(Key('meal-food-${secondItem.id}')));
    await tester.pump();
    expect(toggled, ['${second.id}:${secondItem.id}']);

    await drainStream(tester);
  });

  testWidgets('普通态：食物行没有勾选圈（不新增可见控件）', (tester) async {
    final seeded = await seedLunch();
    final first = (await meals.getById(seeded.first))!;
    await pumpGrouping(tester);
    expect(
      find.byKey(Key('meal-food-select-circle-${first.items.single.id}')),
      findsNothing,
    );

    await drainStream(tester);
  });

  testWidgets('复核 20b：卡面上没有时刻；⋮ 管理菜单已随整卡编辑退役', (tester) async {
    final seeded = await seedLunch();
    await pumpGrouping(tester);

    // 卡面（整卡编辑弹层未开）：一处 HH:mm 都不该有——用户要的就是「去掉时间显示」。
    expect(
      find.textContaining(RegExp(r'\d{1,2}:\d{2}')),
      findsNothing,
      reason: '需求 20b：卡头不再写 HH:mm',
    );

    // 【2026-10-31 断言改写（用户：右下角三个点直接删掉，强度不降）】原来
    // 这后半段验证「时间搬到管理菜单里」。菜单整件退役后，指认记录的职责
    // 由**整卡点击的合并编辑弹层**承接（弹层里每条记录自带时刻与垃圾桶），
    // 卡面上与管理入口都不再有 HH:mm 可看。
    for (final id in [seeded.first, seeded.second]) {
      expect(find.byKey(Key('meal-manage-$id')), findsNothing);
    }
    await drainStream(tester);
  });

  testWidgets('复核 20b：同一餐次记两次 = 一张卡，两条记录都在卡内（含分隔线）', (tester) async {
    final seeded = await seedLunch();
    await pumpGrouping(tester);

    // 一张卡：卡根 Key 取第一条记录的 id；第二条**不该**再起一张卡。
    expect(find.byKey(Key('meal-card-${seeded.first}')), findsOneWidget);
    expect(
      find.byKey(Key('meal-card-${seeded.second}')),
      findsNothing,
      reason: '需求 20b：「不要因为我后边记的就分开显示」',
    );
    // 两条记录各自的分组与食物行都在同一张卡里（食物放一起）。
    for (final id in [seeded.first, seeded.second]) {
      expect(find.byKey(Key('meal-$id')), findsOneWidget, reason: '记录分组 $id');
    }
    expect(
      find.descendant(of: lunchSlot(), matching: find.text('红烧肉盖浇饭 250g')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: lunchSlot(), matching: find.text('凉拌黄瓜 120g')),
      findsOneWidget,
    );
    // 极淡分隔线：夹在**两段记录之间**（两次记录这件事没被抹掉）。
    final divider = find.byKey(Key('meal-merge-divider-${seeded.second}'));
    expect(divider, findsOneWidget, reason: '两段之间的分隔线');
    expect(tester.getSize(divider).height, 1);
    expect(
      tester.getRect(divider).top,
      greaterThan(tester.getRect(find.byKey(Key('meal-${seeded.first}'))).top),
      reason: '分隔线在第一段之下',
    );
    expect(
      tester.getRect(divider).bottom,
      lessThan(tester.getRect(find.byKey(Key('meal-${seeded.second}'))).top),
      reason: '分隔线在第二段之上',
    );
    // 来源徽标每条一份（事实不合并）。
    // 【2026-10-29（N-1 改写，用户：AI估算/已确认徽标看不懂、要求去掉）】
    // 来源徽标从餐卡撤下（事实在 sourceType 列与编辑弹层里）。
    expect(find.byKey(Key('meal-source-${seeded.first}')), findsNothing);
    expect(find.byKey(Key('meal-source-${seeded.second}')), findsNothing);
    await drainStream(tester);
  });

  testWidgets('复核 20a/20b：热量合计只有一个数字、等于两条之和，写在槽位头标题后边（手算核对）', (tester) async {
    final seeded = await seedLunch();
    await pumpGrouping(tester);

    // 【2026-10-31 断言语义变更（用户：热量行直接放标题后边，强度不降）】
    // 卡内热量行整行退役（embedded 不再画「午餐 444 kcal」再叠一行），合计
    // kcal 由槽位头承载。数字与手算值必须逐位一致。
    Finder slotTotal(String key) => find.byKey(Key(key));
    expect(
      tester.widget<Text>(slotTotal('nutrition-record-slot-lunch-total')).data,
      '444 kcal · 2 条记录',
      reason: '390 + 54：按插进去的克数与每百克热量手算得出（不许凭空造数）',
    );
    // 卡面上不再有第二个热量数字（`meal-kcal` 只属于非 embedded 形态）。
    expect(
      find.byKey(Key('meal-kcal-${seeded.first}')),
      findsNothing,
      reason: '合并后槽位头是唯一热量位，不是卡内再一个',
    );
    expect(find.text('390'), findsNothing, reason: '各自的小计不再单独出现');
    expect(find.text('54'), findsNothing, reason: '同上');
    expect(
      find.descendant(of: lunchSlot(), matching: find.textContaining('kcal')),
      findsOneWidget,
      reason: '单位小字也只该有一处（槽位头那个 444 kcal）',
    );
    await drainStream(tester);
  });

  testWidgets('复核 20a：三宏量从卡面退场，但读屏仍拿得到（数值不丢）', (tester) async {
    final seeded = await seedLunch();
    await pumpGrouping(tester);

    // 视觉：卡面上一个宏量词都没有。
    for (final word in const ['蛋白质', '碳水', '脂肪']) {
      expect(find.text(word), findsNothing, reason: '需求 20a：$word 不再占卡面');
    }
    // 退役的那行（及其 Key）确实不在了。
    for (final id in [seeded.first, seeded.second]) {
      expect(find.byKey(Key('meal-totals-$id')), findsNothing);
    }
    // 读屏：【2026-10-31 挂点随卡头退役移到卡根】卡头热量行整行退役后，
    // 三宏量合计的语义面板挂到整卡——手算的三个合计逐个对得上
    // （21.2 / 53.6 / 14.9）。
    final label = tester
        .getSemantics(find.byKey(Key('meal-card-${seeded.first}')))
        .label;
    expect(label, contains('444'), reason: '热量与宏量是同一个数字面板的读法');
    expect(label, contains('蛋白质 21.2 克'));
    expect(label, contains('碳水 53.6 克'));
    expect(label, contains('脂肪 14.9 克'));
    await drainStream(tester);
  });

  testWidgets('复核 20b：点第二段不再触发单条编辑；整卡点击 = 合并编辑回调', (tester) async {
    final seeded = await seedLunch();
    var slotEditCount = 0;
    await pumpGrouping(tester, onEditSlot: (_) => slotEditCount++);

    // 【2026-10-31 断言改写（用户：每个食物不要单独点开编辑，整卡点击看
    // 全部已添加食物，强度不降）】原来「点第二段 → 改第二条」；现在卡内
    // 组行不再吃点击（不弹单条编辑），点卡内任意一段打开的都是**该槽位
    // 全部记录**的合并编辑弹层——回调一次、不按段数翻倍。
    await tester.tap(find.byKey(Key('meal-${seeded.second}')));
    await tester.pump();
    expect(slotEditCount, 1, reason: '点第二段 → 整卡合并编辑（不是单条编辑）');
    await tester.tap(find.byKey(Key('meal-${seeded.first}')));
    await tester.pump();
    expect(slotEditCount, 2, reason: '点第一段同样是合并编辑；两次点击两次回调');
    await drainStream(tester);
  });

  testWidgets('复核 20b：多选时每个食物各有自己的勾选圈（组头不再重复）', (tester) async {
    final seeded = await seedLunch();
    final first = (await meals.getById(seeded.first))!;
    final second = (await meals.getById(seeded.second))!;
    final toggledItems = <String>[];
    final toggledGroups = <String>[];
    await pumpGrouping(
      tester,
      selectionMode: true,
      selectedItemIds: {second.items.single.id},
      onToggleSelected: (meal) => toggledGroups.add(meal.id),
      onToggleItemSelected: (meal, item) => toggledItems.add(item.id),
    );

    for (final (meal, food) in [(first, '红烧肉盖浇饭'), (second, '凉拌黄瓜')]) {
      final item = meal.items.single;
      final circle = find.byKey(Key('meal-food-select-circle-${item.id}'));
      expect(circle, findsOneWidget, reason: '每个食物要有自己的圈');
      // 20dp 且圆心对齐食物文字行中心；组头不再多画一枚重复圈。
      expect(tester.getSize(circle).width, 20, reason: '勾选圈 20dp');
      expect(
        find.byKey(Key('meal-select-circle-${meal.id}')),
        findsNothing,
        reason: '组头圈退役：否则首行并排两枚圈，分不清点哪个',
      );
      final circleCenter = tester.getCenter(circle).dy;
      final foodRowCenter = tester
          .getCenter(
            find.descendant(
              of: find.byKey(Key('meal-${meal.id}')),
              matching: find.textContaining(food),
            ),
          )
          .dy;
      expect(
        (circleCenter - foodRowCenter).abs(),
        lessThanOrEqualTo(3),
        reason: '勾选圈与食物文字同一高度',
      );
    }
    // 勾上的食物显示对勾，另一条不显示。
    expect(
      find.descendant(
        of: find.byKey(
          Key('meal-food-select-circle-${second.items.single.id}'),
        ),
        matching: find.byIcon(Icons.check),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(Key('meal-food-select-circle-${first.items.single.id}')),
        matching: find.byIcon(Icons.check),
      ),
      findsNothing,
    );
    await tester.tap(find.byKey(Key('meal-food-${first.items.single.id}')));
    await tester.pump();
    expect(toggledItems, [first.items.single.id], reason: '点食物只切换该食物');

    // 组行点击不再作为主要交互（逐食物圈已覆盖精确选择）；这里只验证
    // 长按/组行回调接口仍在，不把点击坐标落在某个食物行上做歧义断言。
    expect(toggledGroups, isEmpty);
    await drainStream(tester);
  });

  testWidgets('复核 20b：320dp × 2.0× 字号下不溢出，备注不再被省略、也不许一字一列', (tester) async {
    final seeded = await seedLunch();
    await pumpGrouping(tester, width: 320, textScale: 2.0);

    expect(tester.takeException(), isNull, reason: '极端字号下不许溢出');
    final notesFinder = find.byKey(Key('meal-notes-${seeded.first}'));
    final notes = tester.widget<Text>(notesFinder);
    expect(notes.data, '食堂二楼');
    expect(notes.maxLines, isNull, reason: '三宏量退场后底行宽松了：备注不再被截');
    expect(notes.overflow, isNot(TextOverflow.ellipsis));
    // 【看图复核缺陷 7】取帧（`verify-20-narrow-320-2.0x.png`）实测：修复前
    // 备注只剩 ~26dp 宽，「食堂二楼」被压成四行**竖排**、⋮ 菜单挤在边上。
    // 「不溢出」这一条当时是绿的——溢出和「丑到读不出来」是两件事，所以要
    // 单独钉宽度：2.0× 下至少 100dp（≈4 个字）。
    expect(
      tester.getSize(notesFinder).width,
      greaterThanOrEqualTo(100),
      reason: '备注必须拿到可读宽度（否则就是一列一个字）',
    );
    // 【2026-10-31 断言随热量位移动改写】卡内大号位退役后，合计数字由槽位
    // 头承载——320dp 极端字号下它仍要完整可读（不是被截成省略号）。
    final slotTotal = tester.widget<Text>(
      find.byKey(const Key('nutrition-record-slot-lunch-total')),
    );
    expect(slotTotal.data, '444 kcal · 2 条记录', reason: '合计完整写全');
    expect(slotTotal.maxLines, isNull, reason: '窄屏也不许截断合计行');
    expect(slotTotal.overflow, isNot(TextOverflow.ellipsis));
    await drainStream(tester);
  });
}

final class _Ids implements IdGenerator {
  int _value = 0;

  @override
  String next() => 'v-${_value++}';
}
