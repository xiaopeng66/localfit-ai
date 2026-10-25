import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/app_morph_chip.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart';
import 'package:localfit_ai/features/campus_menus/presentation/menu_tab_view.dart';

/// 3.0 食堂 tab 视图：地点 chip 切换 → 窗口卡 → 菜品行；
/// 「添加地点/窗口/菜品」三个入口 + AI 分析按钮（无待分析菜品时不渲染）。
void main() {
  late AppDatabase database;
  late CanteenRepository repository;
  final now = DateTime.utc(2026, 9, 22, 8);

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = CanteenRepository(
      database: database,
      idGenerator: _IncrementingIdGenerator(),
      clock: FixedAppClock(now),
    );
  });

  tearDown(() async {
    await database.close();
  });

  Widget host({
    Future<void> Function(List<CanteenDish>)? onAnalyze,
    Future<String?> Function(bool fromCamera)? pickDishImage,
  }) => MaterialApp(
    home: Scaffold(
      body: MenuTabView(
        repository: repository,
        onAnalyzeDishes: onAnalyze,
        pickDishImage: pickDishImage,
      ),
    ),
  );

  testWidgets('空态：提示加地点，只有一个「添加地点」入口', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(find.text('还没有食堂地点。'), findsOneWidget);
    expect(find.byKey(const Key('canteen-add-venue')), findsOneWidget);
    await drain(tester);
  });

  testWidgets('有地点无窗口：提示加窗口，渲染「添加窗口」', (tester) async {
    await repository.createVenue(name: '东区食堂', campusName: '示范大学');
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(find.text('东区食堂'), findsOneWidget);
    expect(find.textContaining('示范大学'), findsOneWidget);
    expect(find.textContaining('这个地点还没有窗口'), findsOneWidget);
    expect(find.byKey(const Key('canteen-add-window')), findsOneWidget);
    await drain(tester);
  });

  testWidgets('窗口与菜品：时段、菜名、未分析标记', (tester) async {
    final venueId = await repository.createVenue(
      name: '东区食堂',
      campusName: '示范大学',
    );
    final windowId = await repository.createWindow(
      venueId: venueId,
      name: '一楼快餐',
      openTime: '08:00',
      closeTime: '13:30',
    );
    await repository.createDish(windowId: windowId, name: '番茄炒蛋');

    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(find.text('一楼快餐'), findsOneWidget);
    expect(find.textContaining('08:00–13:30'), findsOneWidget);
    expect(find.text('番茄炒蛋'), findsOneWidget);
    expect(find.text('未分析营养'), findsOneWidget);
    // 2026-10-16 用户删掉价格：菜品行不再印任何价格（旧断言
    // `12.00 元` 按新事实改成「没有价格字样」）。
    expect(find.textContaining('元'), findsNothing);
    // docs/28 §4.6：窗口时段从「一句话里的一段」升为独立徽章，
    // 菜品行不再把四项营养拼成一整串。
    expect(find.byKey(Key('canteen-window-window-$windowId')), findsOneWidget);
    // 删除窗入口是 B4 圆钮（docs/28 §4.6 保留形态 + 保留 Key）。
    expect(find.byKey(Key('canteen-delete-window-$windowId')), findsOneWidget);
    expect(find.textContaining('kcal/100g'), findsNothing);
    await drain(tester);
  });

  testWidgets('窗口卡：三钮在同一行、右对齐（docs/28 §4.6）', (tester) async {
    final venueId = await repository.createVenue(
      name: '东区食堂',
      campusName: '示范大学',
    );
    final windowId = await repository.createWindow(
      venueId: venueId,
      name: '一楼快餐',
      openTime: '08:00',
      closeTime: '13:30',
    );
    final dishId = await repository.createDish(
      windowId: windowId,
      name: '番茄炒蛋',
    );
    await repository.recordNutrition(
      dishId: dishId,
      kcalPer100g: 92,
      proteinPer100g: 5.4,
      carbsPer100g: 6.1,
      fatPer100g: 5.2,
      grade: 'C',
      confidence: 0.6,
    );
    // 回调都要接线：为空时对应的按钮整枚不渲染（降级不画假按钮），
    // 那样断言测的就不是「排版成不成立」而是「按钮在不在」。
    // 2026-10-24：「加入菜品库」按钮整枚退场（食堂目录与菜品库就是一个库）。
    await repository.createDish(windowId: windowId, name: '待分析菜');
    await tester.pumpWidget(host(onAnalyze: (_) async {}));
    await tester.pumpAndSettle();

    // 「添加菜品」是虚线钮，AI 分析是胶囊：两个 Key 都要在、排在同一行。
    final addDish = find.byKey(Key('canteen-add-dish-$windowId'));
    final analyze = find.byKey(Key('canteen-analyze-$windowId'));
    expect(addDish, findsOneWidget);
    expect(analyze, findsOneWidget);
    expect(
      find.byKey(Key('canteen-add-to-library-$windowId')),
      findsNothing,
      reason: '2026-10-24：不再有手动「加入菜品库」入口',
    );
    final card = tester.getRect(find.byKey(Key('canteen-window-$windowId')));
    final tops = [addDish, analyze].map((f) => tester.getRect(f).top);
    expect(tops.toSet().length, 1, reason: '两钮排成一行');
    expect(
      card.right - tester.getRect(analyze).right,
      closeTo(LfDimens.cardPadding, 1),
    );
    // 顺序：添加菜品 → AI 分析（主行动在右）。
    expect(tester.getRect(addDish).left < tester.getRect(analyze).left, isTrue);
    await drain(tester);
  });

  testWidgets('地点 chip（docs/21 §3.12 重做）：描边档、高 44、选中 2px 主色描边不换底', (
    tester,
  ) async {
    final east = await repository.createVenue(name: '东区食堂', campusName: '示范大学');
    final west = await repository.createVenue(name: '西区食堂', campusName: '示范大学');
    await repository.createWindow(
      venueId: east,
      name: '东区一楼',
      openTime: '08:00',
      closeTime: '13:30',
    );
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    // 全仓唯一 chip 件的第二档，不是第三个 chip 组件。
    for (final id in [east, west]) {
      final chip = tester.widget<AppMorphChip>(
        find.byKey(Key('canteen-venue-$id')),
      );
      expect(chip.variant, AppMorphChipVariant.outlined);
      // 44 = 触达线：低于它就不该当作可点控件（docs/21 §3.12）。
      expect(tester.getSize(find.byKey(Key('canteen-venue-$id'))).height, 44);
    }

    BoxDecoration? decoration(String id) {
      for (final box in tester.widgetList<AnimatedContainer>(
        find.descendant(
          of: find.byKey(Key('canteen-venue-$id')),
          matching: find.byType(AnimatedContainer),
        ),
      )) {
        final value = box.decoration;
        if (value is BoxDecoration) return value;
      }
      return null;
    }

    // 选中（2026-10-06 重做）：底色恒为 card + 2px 主色描边 + 轻抬升。
    final selected = decoration(east)!;
    expect(selected.color, LfSemanticColors.light.card);
    final selectedBorder = selected.border! as Border;
    expect(selectedBorder.top.width, 2);
    expect(selectedBorder.top.color, LfColors.mint(Brightness.light).tone(600));
    expect(selected.boxShadow, hasLength(1));
    // 未选中维持 1px 常规边。
    final plain = decoration(west)!;
    expect((plain.border! as Border).top.width, 1);
    expect(plain.boxShadow, isNull);
    // 6dp 圆点已随重做删除（形状信息由描边宽度变化承担）。注意
    // AnimatedContainer 内部本就构建真实 Container，不能按类型排除；
    // 圆点的特征是「圆形装饰」，按它判。
    expect(
      find.descendant(
        of: find.byKey(Key('canteen-venue-$east')),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Container &&
              widget.decoration is BoxDecoration &&
              (widget.decoration! as BoxDecoration).shape == BoxShape.circle,
        ),
      ),
      findsNothing,
    );
    await drain(tester);
  });

  testWidgets('地点统计行（docs/28 §4.5）：三个小瓦片，不再是一句顿号', (tester) async {
    final venueId = await repository.createVenue(
      name: '东区食堂',
      campusName: '示范大学',
    );
    final windowId = await repository.createWindow(
      venueId: venueId,
      name: '一楼快餐',
      openTime: '08:00',
      closeTime: '13:30',
    );
    final analyzedId = await repository.createDish(
      windowId: windowId,
      name: '已分析菜',
    );
    await repository.createDish(windowId: windowId, name: '待分析菜');
    await repository.recordNutrition(
      dishId: analyzedId,
      kcalPer100g: 92,
      proteinPer100g: 5.4,
      carbsPer100g: 6.1,
      fatPer100g: 5.2,
      grade: 'C',
      confidence: 0.6,
    );
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('canteen-venue-stats')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('canteen-stat-windows')),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('canteen-stat-dishes')),
        matching: find.text('2'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('canteen-stat-analyzed')),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
    // 旧形态「示范大学 · 1 个窗口 · 2 道菜 · 已分析 1」整句已删除。
    expect(find.textContaining('个窗口'), findsNothing);
    await drain(tester);
  });

  testWidgets('已分析菜品显示每 100g 营养与等级', (tester) async {
    final venueId = await repository.createVenue(
      name: '东区食堂',
      campusName: '示范大学',
    );
    final windowId = await repository.createWindow(
      venueId: venueId,
      name: '一楼快餐',
      openTime: '08:00',
      closeTime: '13:30',
    );
    final dishId = await repository.createDish(
      windowId: windowId,
      name: '番茄炒蛋',
    );
    await repository.recordNutrition(
      dishId: dishId,
      kcalPer100g: 92,
      proteinPer100g: 5.4,
      carbsPer100g: 6.1,
      fatPer100g: 5.2,
      grade: 'C',
      confidence: 0.6,
    );

    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    // docs/28 §4.6：四项营养不再拼成一整串——三彩点行与食物卡同源，
    // 右侧只留一个热量数字，单位由窗口卡头行统一说明。
    expect(find.text('92 kcal'), findsOneWidget);
    expect(find.textContaining('蛋白质 5.4g'), findsOneWidget);
    expect(find.textContaining('碳水 6.1g'), findsOneWidget);
    expect(find.textContaining('脂肪 5.2g'), findsOneWidget);
    expect(find.textContaining('kcal/100g'), findsNothing);
    expect(find.text('C级'), findsOneWidget);
    expect(find.text('未分析营养'), findsNothing);
    await drain(tester);
  });

  testWidgets('AI 分析按钮：待分析 N 道；无待分析时不渲染', (tester) async {
    final venueId = await repository.createVenue(
      name: '东区食堂',
      campusName: '示范大学',
    );
    final windowId = await repository.createWindow(
      venueId: venueId,
      name: '一楼快餐',
      openTime: '08:00',
      closeTime: '13:30',
    );
    final analyzed = await repository.createDish(
      windowId: windowId,
      name: '已分析菜',
    );
    await repository.createDish(windowId: windowId, name: '待分析菜');
    await repository.recordNutrition(
      dishId: analyzed,
      kcalPer100g: 100,
      proteinPer100g: 5,
      carbsPer100g: 5,
      fatPer100g: 5,
      grade: 'C',
      confidence: 0.5,
    );

    List<CanteenDish>? passed;
    await tester.pumpWidget(
      host(
        onAnalyze: (dishes) async {
          passed = dishes;
        },
      ),
    );
    await tester.pumpAndSettle();

    final button = find.byKey(Key('canteen-analyze-$windowId'));
    expect(button, findsOneWidget);
    expect(find.text('AI 分析 1 道'), findsOneWidget);

    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(passed, hasLength(1));
    expect(passed!.single.name, '待分析菜');
    await drain(tester);
  });

  testWidgets('未接 AI 回调时不渲染分析按钮（降级不报错）', (tester) async {
    final venueId = await repository.createVenue(
      name: '东区食堂',
      campusName: '示范大学',
    );
    final windowId = await repository.createWindow(
      venueId: venueId,
      name: '一楼快餐',
      openTime: '08:00',
      closeTime: '13:30',
    );
    await repository.createDish(windowId: windowId, name: '待分析菜');

    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(find.byKey(Key('canteen-analyze-$windowId')), findsNothing);
    expect(find.text('待分析菜'), findsOneWidget);
    await drain(tester);
  });

  testWidgets('添加地点：表单保存后列表出现新地点', (tester) async {
    await repository.createVenue(name: '东区食堂', campusName: '示范大学');
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('canteen-add-venue')));
    await tester.pumpAndSettle();
    expect(find.text('添加食堂地点'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('canteen-venue-name')), '西区食堂');
    await tester.tap(find.byKey(const Key('canteen-form-submit')));
    await tester.pumpAndSettle();

    expect(find.text('西区食堂'), findsOneWidget);
    expect((await repository.listVenues()), hasLength(2));
    await drain(tester);
  });

  testWidgets('添加窗口：默认时段 08:00–20:00，保存后出现窗口卡', (tester) async {
    final venueId = await repository.createVenue(
      name: '东区食堂',
      campusName: '示范大学',
    );
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('canteen-add-window')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('canteen-window-name')),
      '一楼快餐',
    );
    await tester.tap(find.byKey(const Key('canteen-form-submit')));
    await tester.pumpAndSettle();

    final windows = await repository.listWindows(venueId);
    expect(windows, hasLength(1));
    expect(windows.single.openTime, '08:00');
    expect(windows.single.closeTime, '20:00');
    expect(find.text('一楼快餐'), findsOneWidget);
    await drain(tester);
  });

  testWidgets('别处写入的营养（如 AI 分析应用）会让目录**自动**刷新', (tester) async {
    // 2026-10-16 设备实测：在「食堂目录」点 AI 分析 → 到对话里应用
    // `canteen.dish.nutrition` → 返回目录时**那张还活着的页面**仍显示
    // 「未分析营养」「0 道 已分析」，而营养其实已落库 —— 用户会以为分析失败了。
    // 目录页订阅 `CanteenRepository.watchDirectory()`，任何一端写入就重载。
    final venueId = await repository.createVenue(
      name: '东区食堂',
      campusName: '示范大学',
    );
    final windowId = await repository.createWindow(
      venueId: venueId,
      name: '一楼快餐',
      openTime: '08:00',
      closeTime: '13:30',
    );
    final dishId = await repository.createDish(
      windowId: windowId,
      name: '番茄牛腩饭',
    );
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(find.text('未分析营养'), findsOneWidget);

    // 模拟**另一端**的写入（AI 分析应用走的就是这条仓储方法）。
    await repository.recordNutrition(
      dishId: dishId,
      kcalPer100g: 150,
      proteinPer100g: 6,
      carbsPer100g: 21,
      fatPer100g: 5,
      grade: 'D',
      confidence: 0.5,
    );
    // 真实事件循环跑一拍，让 Drift 的 tableUpdates 事件送达。
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await tester.pumpAndSettle();

    expect(find.text('未分析营养'), findsNothing, reason: '营养已落库，页面不该还写着「未分析」');
    expect(find.textContaining('150 kcal'), findsOneWidget);
    await drain(tester);
  });

  testWidgets('添加菜品：只填名称即可写入（价格字段已随 S8-b 退役）', (tester) async {
    final venueId = await repository.createVenue(
      name: '东区食堂',
      campusName: '示范大学',
    );
    final windowId = await repository.createWindow(
      venueId: venueId,
      name: '一楼快餐',
      openTime: '08:00',
      closeTime: '13:30',
    );
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(Key('canteen-add-dish-$windowId')));
    await tester.pumpAndSettle();

    // 2026-10-16 用户：「把食堂菜品添加的时候的价格删掉（包括其他所有关于
    // 这个食堂菜品的价格分析和功能，没有用了）」。字段、校验、库列（v26
    // DROP `price_minor`）与提示词同批退役 ⇒ 表单里不再有价格输入，「只写
    // 名称就能存」是新的唯一事实。原「价格非法 / NaN·1e400 / 元→分」
    // 三则用例所测功能整体不存在，按功能退役删除（证据文件已登记）。
    expect(find.byKey(const Key('canteen-dish-price')), findsNothing);

    await tester.enterText(find.byKey(const Key('canteen-dish-name')), '番茄炒蛋');
    await tester.tap(find.byKey(const Key('canteen-form-submit')));
    await tester.pumpAndSettle();

    final dishes = await repository.listDishes(windowId);
    expect(dishes.single.name, '番茄炒蛋');
    expect(find.text('番茄炒蛋'), findsOneWidget);
    await drain(tester);
  });

  testWidgets('点菜品 → 动作表：改名 / AI 分析（未分析时）/ 删除', (tester) async {
    final venueId = await repository.createVenue(
      name: '东区食堂',
      campusName: '示范大学',
    );
    final windowId = await repository.createWindow(
      venueId: venueId,
      name: '一楼快餐',
      openTime: '08:00',
      closeTime: '13:30',
    );
    final dishId = await repository.createDish(
      windowId: windowId,
      name: '番茄炒蛋',
    );
    await tester.pumpWidget(host(onAnalyze: (_) async {}));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(Key('canteen-dish-$dishId')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('canteen-dish-edit')), findsOneWidget);
    expect(find.byKey(const Key('canteen-dish-analyze')), findsOneWidget);
    expect(find.byKey(const Key('canteen-dish-delete')), findsOneWidget);
    await drain(tester);
  });

  testWidgets('删除菜品：确认后从列表消失', (tester) async {
    final venueId = await repository.createVenue(
      name: '东区食堂',
      campusName: '示范大学',
    );
    final windowId = await repository.createWindow(
      venueId: venueId,
      name: '一楼快餐',
      openTime: '08:00',
      closeTime: '13:30',
    );
    final dishId = await repository.createDish(
      windowId: windowId,
      name: '番茄炒蛋',
    );
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(Key('canteen-dish-$dishId')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('canteen-dish-delete')));
    await tester.pumpAndSettle();

    expect(find.text('删除菜品'), findsOneWidget);
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(find.text('番茄炒蛋'), findsNothing);
    expect(await repository.listDishes(windowId), isEmpty);
    await drain(tester);
  });

  // 2026-10-23 用户：「菜品新建无法删除（跳界面且删不掉）」。
  //
  // 真机上 `AppSheet` 走**根导航器**，而食堂目录页挂在 shell 分支导航器上；
  // 确认弹层的按钮若用页面 context `pop`，弹掉的是目录页、弹层还留着。
  // 单导航器的 `host()` 复现不了（两个 context 解析到同一个 Navigator），
  // 所以这里显式套一层嵌套 Navigator —— 与真机的导航层级同构。
  testWidgets('删除菜品（嵌套导航器）：确认只关弹层，页面不跳走、菜真的删掉', (tester) async {
    final venueId = await repository.createVenue(
      name: '东区食堂',
      campusName: '示范大学',
    );
    final windowId = await repository.createWindow(
      venueId: venueId,
      name: '一楼快餐',
      openTime: '08:00',
      closeTime: '13:30',
    );
    final dishId = await repository.createDish(
      windowId: windowId,
      name: '番茄炒蛋',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Navigator(
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (_) => MenuTabView(repository: repository),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(Key('canteen-dish-$dishId')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('canteen-dish-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    // 页面仍在（旧实现会把嵌套路由弹掉，这里会 findsNothing）。
    expect(find.byType(MenuTabView), findsOneWidget);
    // 确认弹层已关。
    expect(find.text('删除菜品'), findsNothing);
    // 菜真的删了。
    expect(await repository.listDishes(windowId), isEmpty);
    await drain(tester);
  });

  testWidgets('无 pickDishImage 时菜品表单不渲染照片字段（降级）', (tester) async {
    final venueId = await repository.createVenue(name: '东区食堂', campusName: '');
    await repository.createWindow(
      venueId: venueId,
      name: '一楼快餐',
      openTime: '08:00',
      closeTime: '13:30',
    );
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    final windowId = (await repository.listWindows(
      (await repository.listVenues()).single.id,
    )).single.id;
    await tester.tap(find.byKey(Key('canteen-add-dish-$windowId')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('canteen-dish-photo-empty')), findsNothing);
    await drain(tester);
  });

  testWidgets('注入 pickDishImage：拍照返回路径 → 表单显示缩略图 → 落库 imagePath', (
    tester,
  ) async {
    final venueId = await repository.createVenue(name: '东区食堂', campusName: '');
    await repository.createWindow(
      venueId: venueId,
      name: '一楼快餐',
      openTime: '08:00',
      closeTime: '13:30',
    );
    var pickCalls = 0;
    await tester.pumpWidget(
      host(
        pickDishImage: (fromCamera) async {
          pickCalls++;
          expect(fromCamera, isTrue, reason: '拍照按钮传 true');
          return '/docs/localfit_ai/dish_images/dish_new.jpg';
        },
      ),
    );
    await tester.pumpAndSettle();

    final venue = (await repository.listVenues()).single;
    final windowId = (await repository.listWindows(venue.id)).single.id;
    await tester.tap(find.byKey(Key('canteen-add-dish-$windowId')));
    await tester.pumpAndSettle();

    // 空态在场 → 点拍照 → 预览出现。
    expect(find.byKey(const Key('canteen-dish-photo-empty')), findsOneWidget);
    await tester.tap(find.byKey(const Key('canteen-dish-photo-shoot')));
    await tester.pumpAndSettle();
    expect(pickCalls, 1);
    expect(find.byKey(const Key('canteen-dish-photo-empty')), findsNothing);

    await tester.enterText(find.byKey(const Key('canteen-dish-name')), '红烧排骨');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('canteen-form-submit')));
    await tester.pumpAndSettle();

    // 断言的是**仓库里真的写了 imagePath**，不是弹层内部状态。
    final dish = (await repository.listDishes(windowId)).single;
    expect(dish.name, '红烧排骨');
    expect(dish.imagePath, '/docs/localfit_ai/dish_images/dish_new.jpg');
    await drain(tester);
  });

  testWidgets('编辑菜品不动照片字段：imagePath 保持原值', (tester) async {
    final venueId = await repository.createVenue(name: '东区食堂', campusName: '');
    final windowId = await repository.createWindow(
      venueId: venueId,
      name: '一楼快餐',
      openTime: '08:00',
      closeTime: '13:30',
    );
    await repository.createDish(
      windowId: windowId,
      name: '红烧排骨',
      imagePath: '/docs/dish_old.jpg',
    );
    await tester.pumpWidget(host(pickDishImage: (_) async => null));
    await tester.pumpAndSettle();

    final dishId = (await repository.listDishes(windowId)).single.id;
    await tester.tap(find.byKey(Key('canteen-dish-$dishId')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('canteen-dish-edit')));
    await tester.pumpAndSettle();

    // 初值回填（有图 → 预览而不是空态），只改名保存。
    expect(find.byKey(const Key('canteen-dish-photo-empty')), findsNothing);
    await tester.enterText(
      find.byKey(const Key('canteen-dish-name')),
      '红烧排骨（大份）',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('canteen-form-submit')));
    await tester.pumpAndSettle();

    final dish = (await repository.listDishes(windowId)).single;
    expect(dish.name, '红烧排骨（大份）');
    expect(dish.imagePath, '/docs/dish_old.jpg', reason: '没碰照片字段就不动列');
    await drain(tester);
  });

  testWidgets('多地点：chip 切换只显示选中地点的窗口', (tester) async {
    final east = await repository.createVenue(name: '东区食堂', campusName: '示范大学');
    final west = await repository.createVenue(name: '西区食堂', campusName: '示范大学');
    await repository.createWindow(
      venueId: east,
      name: '东区一楼',
      openTime: '08:00',
      closeTime: '13:30',
    );
    await repository.createWindow(
      venueId: west,
      name: '西区二楼',
      openTime: '08:00',
      closeTime: '13:30',
    );

    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    // 首个地点（东区）默认选中。
    expect(find.text('东区一楼'), findsOneWidget);
    expect(find.text('西区二楼'), findsNothing);

    await tester.tap(find.byKey(Key('canteen-venue-$west')));
    await tester.pumpAndSettle();

    expect(find.text('西区二楼'), findsOneWidget);
    expect(find.text('东区一楼'), findsNothing);
    await drain(tester);
  });

  ScrollPosition verticalPosition(WidgetTester tester) {
    final scrollable = find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.down,
    );
    return tester.state<ScrollableState>(scrollable).position;
  }

  /// 需求 18（docs/29 §P7）：切换地点前后滚动位置差 ≤1px。
  ///
  /// 旧实现带 venue key 的 `FutureBuilder` 在切换时重挂 ⇒ 进
  /// `SliverFillRemaining` 加载分支 ⇒ 滚动视图内容高坍成视口高
  /// （maxScrollExtent=0），offset 被夹回 0（且数据到达后不会自己回来）。
  /// 滚动距离受「chip 必须还在视口内可点」约束（地点行与列表共用一个
  /// 滚动上下文，往下滚 chip 会离开视口被懒加载销毁）——60px 就足够
  /// 判别：旧代码坍缩后任何非零 offset 都会被夹回 0。
  testWidgets('切换地点：滚动位置保持（差 ≤1px），不回加载分支跳顶', (tester) async {
    final east = await repository.createVenue(name: '东区食堂', campusName: '示范大学');
    final west = await repository.createVenue(name: '西区食堂', campusName: '示范大学');
    for (final venueId in [east, west]) {
      for (var i = 1; i <= 6; i++) {
        final windowId = await repository.createWindow(
          venueId: venueId,
          name: '$i 号窗口',
          openTime: '08:00',
          closeTime: '20:00',
        );
        await repository.createDish(windowId: windowId, name: '菜品 $i-A');
        await repository.createDish(windowId: windowId, name: '菜品 $i-B');
      }
    }

    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -60));
    await tester.pumpAndSettle();
    final before = verticalPosition(tester).pixels;
    // tester.drag 会被手势 touch slop 吃掉 ~20px（拖 60 实滚 ~40）。
    expect(before, greaterThan(20), reason: '前提：页面确实处于滚动过的状态');

    await tester.tap(find.byKey(Key('canteen-venue-$west')));
    await tester.pumpAndSettle();

    expect(find.text('西区食堂'), findsOneWidget);
    expect(find.text('1 号窗口'), findsOneWidget);
    final after = verticalPosition(tester).pixels;
    expect((after - before).abs(), lessThanOrEqualTo(1));
    // 加载分支不该在切换路径上出现（出现过的痕迹 = 页面级 spinner）。
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await drain(tester);
  });

  /// 需求 18 的刷新路径：刷新 pending 期间**继续画旧列表** + 顶部细进度条，
  /// 不闪加载占位。用门控子类只卡刷新路径的 `listWindows`（`listVenues`
  /// 内部的同名调用放行，否则整条 reload 链挂死）。
  testWidgets('刷新中：旧列表保持 + 2dp 细进度条，不闪加载占位', (tester) async {
    final gated = _GatedRepository(
      database: database,
      idGenerator: _IncrementingIdGenerator(),
      clock: FixedAppClock(now),
    );
    final venueId = await gated.createVenue(name: '东区食堂', campusName: '示范大学');
    final windowId = await gated.createWindow(
      venueId: venueId,
      name: '东区一楼',
      openTime: '08:00',
      closeTime: '13:30',
    );

    gated.arm(); // 首拉挂起：这是「从未有过数据」的合法加载态
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MenuTabView(repository: gated)),
      ),
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    gated.release();
    await tester.pumpAndSettle();
    expect(find.text('东区一楼'), findsOneWidget);

    // 走一次写操作：表单提交后 reload 会再次拉 listWindows，重新挂起。
    gated.arm();
    await tester.tap(find.byKey(const Key('canteen-add-window')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('canteen-window-name')),
      '东区二楼',
    );
    await tester.tap(find.byKey(const Key('canteen-form-submit')));
    // 只推进弹层退场帧，不 settle：此刻刷新 pending。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // 旧列表仍在（缓存渲染），顶部是 2dp 细进度条而不是加载占位。
    expect(find.text('东区一楼'), findsOneWidget);
    expect(find.byKey(Key('canteen-window-$windowId')), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    gated.release();
    await tester.pumpAndSettle();
    expect(find.text('东区二楼'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await drain(tester);
  });
}

/// 排掉 drift 的 stream-dispose 闭环 Timer。
Future<void> drain(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}

final class _IncrementingIdGenerator implements IdGenerator {
  int _value = 0;

  @override
  String next() => 'view-id-${++_value}';
}

/// 门控仓库：只把**刷新路径**的 `listWindows` 挂在 Completer 上，让
/// 「刷新 pending」成为可断言的稳定状态（验证 stale-while-revalidate 的
/// 旧列表保持路径）。`listVenues` 内部也会调用 `listWindows`（统计窗口
/// 数）——那次调用必须放行，否则整个 reload 链挂死、页面级 spinner 永不
/// 消失，pumpAndSettle 直接超时（首轮就踩过）。
final class _GatedRepository extends CanteenRepository {
  _GatedRepository({
    required super.database,
    required super.idGenerator,
    required super.clock,
  });

  Completer<void>? _gate;

  @override
  Future<List<CanteenVenue>> listVenues() async {
    final held = _gate;
    _gate = null;
    try {
      return await super.listVenues();
    } finally {
      _gate = held;
    }
  }

  @override
  Future<List<CanteenWindow>> listWindows(String venueId) async {
    final gate = _gate;
    if (gate != null) await gate.future;
    return super.listWindows(venueId);
  }

  void arm() => _gate = Completer<void>();

  void release() {
    _gate?.complete();
    _gate = null;
  }
}
