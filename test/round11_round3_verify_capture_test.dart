@Tags(['capture'])
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart'
    hide ConversationMessage;
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_command.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_registry.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_turn.dart';
import 'package:localfit_ai/features/ai_conversation/domain/conversation_message.dart';
import 'package:localfit_ai/features/ai_conversation/presentation/chat_edit_card.dart';
import 'package:localfit_ai/features/ai_memory/data/ai_memory_repository.dart';
import 'package:localfit_ai/features/ai_memory/presentation/ai_memory_page.dart';
import 'package:localfit_ai/features/campus_menus/application/food_reference_service.dart';
import 'package:localfit_ai/features/campus_menus/presentation/food_reference_sheet.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/dish_record.dart';
import 'package:localfit_ai/features/nutrition/domain/food_category.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';
import 'package:localfit_ai/features/nutrition/presentation/meal_entry_chooser_sheet.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/food_card.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/nutrition_record_slot_grouping.dart';
import 'package:localfit_ai/features/onboarding/domain/nutrition_target_calculator.dart';
import 'package:localfit_ai/features/settings/domain/ai_provider_settings.dart';
import 'package:localfit_ai/features/settings/presentation/settings_page.dart';
import 'package:localfit_ai/app/design/widgets/lf_chat_bubbles.dart';
import 'package:localfit_ai/app/design/widgets/lf_chat_input.dart';
import 'package:localfit_ai/app/design/widgets/lf_energy_card.dart';

import 'support/food_fixture.dart';
import 'support/round7_render.dart';

/// **第三轮修复的复核取帧件**（用户 2026-10-26：「你要自己截图验证」）。
///
/// 与 `round10_*` 的区别：那边只覆盖第二批的版式项；这里把**每一个视觉面**
/// 都拍下来——尤其是测试断言覆盖不到「好不好看」的那些：合并后的编辑卡、
/// 热量区间卡（含超上限）、记录页多选、320dp×2.0×、两处记录入口并排对比、
/// 引用抽屉、快捷 chip、全屏看图、帮助与反馈弹层。
///
/// 帧落盘到 `LF_ROUND7_CAPTURE_DIR`（工作区 tmp），复核后归档进
/// `docs/evidence/2026-10-25-round3/frames/`。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 10, 26, 12);

  late AppDatabase database;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await seedFoodFixture(database);
  });

  // 每个取帧用例都新建一个内存库；不关会把 18 个库与流订阅堆到文件末尾，
  // 最后一条 setUp 直接 hang（2026-11-02 全量实测 did not complete）。
  tearDown(() => database.close());

  /// 卸树 + 推进一拍：drift 的流订阅在取消时会排一个 0 时延 timer，
  /// 不排掉就会以「A Timer is still pending」的形式在收尾处报红
  /// （`ai_memory_page_test.dart` 记着同一条教训）。
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  Future<void> shot(WidgetTester tester, String name, Key sentinel) async {
    expect(tester.takeException(), isNull, reason: '$name：布局溢出');
    expect(find.byKey(sentinel), findsOneWidget, reason: '$name：关键件不在帧内');
    await captureRound7(tester, name);
  }

  Future<void> pumpSurface(
    WidgetTester tester,
    Widget child, {
    double width = 390,
    double height = 900,
    double textScale = 1.0,
    bool wrapScaffold = true,
    double dpr = 2,
  }) async {
    tester.view.devicePixelRatio = dpr;
    tester.view.physicalSize = Size(width * dpr, height * dpr);
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(
          size: Size(width, height),
          textScaler: TextScaler.linear(textScale),
        ),
        child: RepaintBoundary(
          key: round7Boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: round7CaptureTheme(AppTheme.light()),
            home: wrapScaffold
                ? Scaffold(
                    body: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: child,
                    ),
                  )
                : child,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  // ── 19 / 6d：编辑卡（合并后的样貌 + 确认弹层）─────────────────────────

  final registry = ChatEditCommandRegistry();
  ChatEditCommand cmd(String action, Map<String, Object> args) {
    final spec = registry.specOf(action)!;
    return ChatEditCommand(spec: spec, args: validateChatEditArgs(spec, args));
  }

  /// 用户原话场景：早餐「米饭 + 鸡蛋水煮」，而鸡蛋水煮是同卡新建的。
  ChatEditTurn eggTurn({
    ChatEditRowStatus mealStatus = ChatEditRowStatus.proposed,
  }) => ChatEditTurn(
    reply: '我准备把早餐记下来，并新建食材鸡蛋水煮。',
    rows: [
      ChatEditTurnItem(
        index: 0,
        raw: const {'action': 'meal.create'},
        command: cmd('meal.create', {
          'slot': 'breakfast',
          'items': [
            {'food': '米饭', 'grams': 150.0},
            {'food': '鸡蛋水煮', 'grams': 100.0},
          ],
        }),
        status: mealStatus,
      ),
      ChatEditTurnItem(
        index: 1,
        raw: const {'action': 'food.create'},
        command: cmd('food.create', {
          'name': '鸡蛋水煮',
          'kcalPer100g': 155.0,
          'proteinPer100g': 13.0,
          'carbsPer100g': 1.1,
          'fatPer100g': 10.6,
        }),
        status: mealStatus,
      ),
    ],
  );

  ConversationMessage messageWith(ChatEditTurn turn, {String id = 'm19'}) =>
      ConversationMessage(
        id: id,
        role: ConversationRole.assistant,
        text: turn.reply,
        kind: ConversationMessageKind.editProposal,
        editTurn: turn,
        createdAt: now,
      );

  Future<void> pumpCard(
    WidgetTester tester,
    ChatEditTurn turn, {
    VoidCallback? onApply,
  }) => pumpSurface(
    tester,
    ChatEditCard(
      index: 0,
      message: messageWith(turn),
      onApply: onApply ?? () {},
      onApplyRows: (_) {},
      onDismiss: () {},
      onApplySuggestion: (_) {},
      onRepair: (_) {},
    ),
    height: 620,
  );

  testWidgets('复核·19a：记一餐 + 同卡新建食材（待应用）', (tester) async {
    await tester.runAsync(loadRound7Fonts);
    await pumpCard(tester, eggTurn());
    await shot(
      tester,
      'verify-19-merged-pending',
      const Key('chat-edit-card-0'),
    );
  });

  testWidgets('复核·19b：同上，已应用态（徽标应变「已新建」）', (tester) async {
    await tester.runAsync(loadRound7Fonts);
    await pumpCard(tester, eggTurn(mealStatus: ChatEditRowStatus.applied));
    await shot(
      tester,
      'verify-19-merged-applied',
      const Key('chat-edit-card-0'),
    );
  });

  testWidgets('复核·19c：纯新建食材（应保留独立板块）', (tester) async {
    await tester.runAsync(loadRound7Fonts);
    var applyRequests = 0;
    await pumpCard(
      tester,
      ChatEditTurn(
        reply: '好，给你加一个叫麻辣烫的食材。',
        rows: [
          ChatEditTurnItem(
            index: 0,
            raw: const {'action': 'food.create'},
            command: cmd('food.create', {
              'name': '麻辣烫',
              'kcalPer100g': 90.0,
              'proteinPer100g': 6.0,
              'carbsPer100g': 9.0,
              'fatPer100g': 3.0,
            }),
          ),
        ],
      ),
      onApply: () => applyRequests++,
    );
    // 单命令不再重复画组头；真实食材分块必须保留，且不能误归到记餐。
    const foodBlockKey = Key('chat-edit-block-0-food');
    final foodBlock = find.byKey(foodBlockKey);
    expect(find.byKey(const Key('chat-edit-block-0-meal')), findsNothing);
    for (final (key, text) in const [
      ('chat-edit-subitem-title-0-0-0', '麻辣烫'),
      ('chat-edit-food-kcal-0-0', '90'),
      ('chat-edit-food-macro-0-0-0', '6.0g'),
      ('chat-edit-food-macro-0-0-1', '9.0g'),
      ('chat-edit-food-macro-0-0-2', '3.0g'),
    ]) {
      expect(
        find.descendant(of: foodBlock, matching: find.text(text)),
        findsOneWidget,
        reason: '独立食材分块必须完整展示 $text',
      );
      expect(tester.widget<Text>(find.byKey(Key(key))).data, text);
    }
    expect(applyRequests, 0, reason: '提议展示不能自动应用');
    await shot(tester, 'verify-19-pure-food', foodBlockKey);

    await tester.tap(find.byKey(const Key('chat-edit-apply-0')));
    await tester.pumpAndSettle();
    expect(applyRequests, 1, reason: '纯新建食材仍可通过全部应用交给控制器');
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  // ── 20：记录页（正常 / 320×2.0 / 多选）────────────────────────────────

  Future<MealRepository> seedLunch() async {
    // 两条记录各自建仓储（为了钉住 eatenAt），但 **id 池必须共用**：
    // 各建一个计数器会让第二条也拿到 `vf-0`，直接撞主键（第一版就是这么红的）。
    final seedIds = _Ids();
    final foods = FoodRepository(
      database: database,
      idGenerator: seedIds,
      clock: FixedAppClock(now),
    );
    for (final (name, kcal) in const [('红烧肉盖浇饭', 156.0), ('凉拌黄瓜', 45.0)]) {
      await database
          .into(database.foods)
          .insert(
            FoodsCompanion.insert(
              id: 'vf-${name.hashCode.abs()}',
              name: name,
              kcalPer100g: kcal,
              proteinPer100g: 8,
              carbsPer100g: 20,
              fatPer100g: 5,
              source: 'seed',
              createdAt: now,
              updatedAt: now,
            ),
          );
    }
    final meals = MealRepository(
      database: database,
      idGenerator: seedIds,
      clock: FixedAppClock(now),
    );
    for (final (hour, name, grams, notes) in const [
      (12, '红烧肉盖浇饭', 250.0, '食堂二楼'),
      (13, '凉拌黄瓜', 120.0, null),
    ]) {
      final food = (await foods.search(name)).first;
      final repo = MealRepository(
        database: database,
        idGenerator: seedIds,
        clock: FixedAppClock(DateTime(2026, 10, 26, hour)),
      );
      await repo.create(
        MealDraft(
          localDate: '2026-10-26',
          slot: MealSlot.lunch,
          items: [MealItemDraft.fromFood(food, grams)],
          notes: notes,
        ),
        source: 'manual',
      );
    }
    return meals;
  }

  Future<void> pumpRecord(
    WidgetTester tester, {
    double width = 412,
    double textScale = 1.0,
    bool selectionMode = false,
  }) async {
    final meals = await seedLunch();
    final ids = await meals
        .watchForDate('2026-10-26')
        .first
        .then((list) => {for (final meal in list) meal.id});
    await pumpSurface(
      tester,
      NutritionRecordSlotGrouping(
        repository: meals,
        localDate: '2026-10-26',
        now: now,
        selectionMode: selectionMode,
        selectedIds: selectionMode ? ids : const {},
        onToggleSelected: (_) {},
      ),
      width: width,
      height: 700,
      textScale: textScale,
    );
  }

  testWidgets('复核·20a：记录页一槽一张卡（合并 + 只显示热量）', (tester) async {
    await tester.runAsync(loadRound7Fonts);
    await pumpRecord(tester);
    await shot(
      tester,
      'verify-20-merged-card',
      const Key('nutrition-record-slot-lunch'),
    );
    await unmount(tester);
  });

  testWidgets('复核·20b：320dp × 2.0×（不溢出、底行不许有省略号）', (tester) async {
    await tester.runAsync(loadRound7Fonts);
    await pumpRecord(tester, width: 320, textScale: 2.0);
    await shot(
      tester,
      'verify-20-narrow-320-2.0x',
      const Key('nutrition-record-slot-lunch'),
    );
    await unmount(tester);
  });

  testWidgets('复核·20c：多选模式（每条记录各自的勾选圈）', (tester) async {
    await tester.runAsync(loadRound7Fonts);
    await pumpRecord(tester, selectionMode: true);
    await shot(
      tester,
      'verify-20-multiselect',
      const Key('nutrition-record-slot-lunch'),
    );
    await unmount(tester);
  });

  // ── 1：热量区间卡（正常 / 超上限 / 无目标）────────────────────────────

  final target = const NutritionTargetCalculator().calculate(
    const NutritionTargetInput(
      age: 28,
      biologicalSex: BiologicalSex.female,
      heightCm: 165,
      weightKg: 60,
      activityLevel: ActivityLevel.moderatelyActive,
      goal: HealthGoal.loseFat,
    ),
  );

  DailyNutritionTarget dailyTarget() => DailyNutritionTarget(
    calorieMinKcal: target.calorieMinKcal.toDouble(),
    calorieMaxKcal: target.calorieMaxKcal.toDouble(),
    proteinMinGrams: target.proteinMinGrams.toDouble(),
    proteinMaxGrams: target.proteinMaxGrams.toDouble(),
    carbsMinGrams: target.carbsMinGrams.toDouble(),
    carbsMaxGrams: target.carbsMaxGrams.toDouble(),
    fatMinGrams: target.fatMinGrams.toDouble(),
    fatMaxGrams: target.fatMaxGrams.toDouble(),
    goalType: 'loseFat',
  );

  Future<void> pumpEnergy(
    WidgetTester tester, {
    required double consumed,
    DailyNutritionTarget? targetOverride,
    bool hasTarget = true,
  }) => pumpSurface(
    tester,
    LfEnergyCard(
      consumed: NutritionValues(
        kcal: consumed,
        proteinGrams: 60,
        carbsGrams: 120,
        fatGrams: 40,
      ),
      target: hasTarget ? (targetOverride ?? dailyTarget()) : null,
      title: '今日营养',
      cardKey: const Key('verify-energy'),
      keyPrefix: 'verify-ring',
      remainingKey: const Key('verify-remaining'),
      statusKey: const Key('verify-status'),
    ),
    width: 412,
    height: 420,
  );

  testWidgets('复核·1a：区间卡（卡头区间 + 环带 + 三宏量区间 + 依据）', (tester) async {
    await tester.runAsync(loadRound7Fonts);
    await pumpEnergy(tester, consumed: 1200);
    await shot(tester, 'verify-1-range-card', const Key('verify-energy'));
  });

  testWidgets('复核·1b：超上限（暖色带 + 「超上限 X」）', (tester) async {
    await tester.runAsync(loadRound7Fonts);
    await pumpEnergy(tester, consumed: target.calorieMaxKcal + 120);
    await shot(tester, 'verify-1-over-limit', const Key('verify-energy'));
  });

  testWidgets('复核·1c：未设目标（不编区间、不编依据）', (tester) async {
    await tester.runAsync(loadRound7Fonts);
    await pumpEnergy(tester, consumed: 300, hasTarget: false);
    await shot(tester, 'verify-1-no-target', const Key('verify-energy'));
  });

  // ── 11a：两处记录入口的行并排对比 ────────────────────────────────────

  testWidgets('复核·11a：食物库行（按食材）', (tester) async {
    await tester.runAsync(loadRound7Fonts);
    await pumpSurface(
      tester,
      SizedBox(
        width: 390,
        child: FoodCard(
          key: const Key('verify-food-card'),
          id: 'x',
          name: '米饭',
          brand: '叮咚',
          category: FoodCategory.staple,
          kcalPer100g: 116,
        ),
      ),
      height: 200,
    );
    await shot(tester, 'verify-11a-food-row', const Key('verify-food-card'));
  });

  testWidgets('复核·11a：菜品行（按菜品）', (tester) async {
    await tester.runAsync(loadRound7Fonts);
    await pumpSurface(
      tester,
      DishMealPickerDialog(
        dishes: [
          DishRecord(
            id: 'd1',
            name: '番茄炒蛋',
            mealSlot: '午餐',
            kcal: 220,
            proteinG: 12,
            carbsG: 9,
            fatG: 14,
            source: 'ai_estimated',
            createdAt: now,
            updatedAt: now,
          ),
        ],
        mealSlotLabel: defaultMealSlotLabel,
      ),
      height: 260,
    );
    await shot(tester, 'verify-11a-dish-row', const Key('dish-meal-picker'));
  });

  // ── 7：引用食物库抽屉（用户逐字要求的三条）───────────────────────────

  testWidgets('复核·7：引用抽屉（删长文案 + 两主按钮并排 + 先不填右下）', (tester) async {
    await tester.runAsync(loadRound7Fonts);
    await pumpSurface(
      tester,
      FoodReferenceSheet(
        dishName: '番茄牛腩饭',
        candidates: [
          FoodReferenceCandidate(
            foodId: 'f1',
            foodName: '番茄牛腩饭',
            kcalPer100g: 200,
            proteinPer100g: 10,
            carbsPer100g: 20,
            fatPer100g: 8,
            state: 'verified',
            confidence: 0.95,
          ),
          FoodReferenceCandidate(
            foodId: 'f2',
            foodName: '番茄牛腩',
            brand: '叮咚',
            kcalPer100g: 180,
            proteinPer100g: 12,
            carbsPer100g: 8,
            fatPer100g: 9,
            state: 'verified',
            confidence: 0.8,
          ),
        ],
      ),
      height: 620,
    );
    await shot(
      tester,
      'verify-7-reference-sheet',
      const Key('food-reference-sheet'),
    );
  });

  // ── 8c：三个快捷 chip（按文字长度自适应）──────────────────────────────

  testWidgets('复核·8c：快捷 chip', (tester) async {
    await tester.runAsync(loadRound7Fonts);
    await pumpSurface(tester, ChatQuickChips(onChipTap: (_) {}), height: 160);
    await shot(tester, 'verify-8c-chips', const Key('chat-quick-chips'));
  });

  // ── 3：全屏看图 ──────────────────────────────────────────────────────

  testWidgets('复核·3：全屏看图（黑底 + 可缩放 + 关闭键）', (tester) async {
    await tester.runAsync(loadRound7Fonts);
    // 全屏件必须**全屏**拍：它是 `Positioned.fill` + Stack，放进滚动体里
    // 高度无界会连抛一堆布局异常（第一版就是 16 个 exception）。
    await pumpSurface(
      tester,
      const Scaffold(
        body: ChatImageZoomView(
          key: Key('verify-zoom'),
          // 必须给**有尺寸**的占位：`ColoredBox` 没 child 时是 0×0，取帧出来
          // 只有黑底 + 关闭键 + caption，看不出「图片在中间」这件事
          // （第一版就是这样，等于没拍到看图页的主体）。
          image: SizedBox(
            width: 280,
            height: 200,
            child: ColoredBox(
              color: Color(0xFF3366AA),
              child: Center(
                child: Text('示例图片', style: TextStyle(color: Color(0xFFFFFFFF))),
              ),
            ),
          ),
          caption: '这是今天的午饭（示例图）',
        ),
      ),
      height: 700,
      wrapScaffold: false,
    );
    await shot(tester, 'verify-3-image-zoom', const Key('verify-zoom'));
  });

  // ── 17d / 17e：帮助与反馈弹层 ────────────────────────────────────────

  testWidgets('复核·17d/17e：帮助（Markdown）与反馈（issue + 复制环境信息）', (tester) async {
    await tester.runAsync(loadRound7Fonts);
    for (final (name, key, tapKey) in const [
      ('verify-17d-help', 'help-markdown', 'about-help'),
      ('verify-17e-feedback', 'feedback-open-issue', 'about-feedback'),
    ]) {
      // 每一轮都**先卸树**：弹层是挂在 `MaterialApp` 的 Navigator 上的 route，
      // 而 `MaterialApp` 没有 Key ⇒ 直接再 pump 一次会复用同一个 Navigator，
      // 上一轮的弹层还盖在页面上，第二次的 tap 落在遮罩上、弹层根本不开
      // （第一版就是这样只拍到了帮助、漏了反馈）。
      await unmount(tester);
      await pumpSurface(
        tester,
        SettingsPage(
          key: UniqueKey(),
          settingsStore: _NoopStore(),
          appVersion: '4076',
          helpContentLoader: () async =>
              '## 数据存在哪里？\n\n全部条目存在这台设备的加密数据库里。\n\n'
              '## 热量目标是怎么算出来的？\n\nMifflin–St Jeor 公式算基础代谢，'
              '再按目标调整，给出区间。\n',
        ),
        width: 412,
        // 设置页比一屏高：用高视口让「帮助文档 / 反馈」两行都在视口内，
        // 不必滚动查找（`scrollUntilVisible` 在懒构建列表里会报
        // 「Bad state: No element」）。
        height: 1800,
        wrapScaffold: false,
      );
      await tester.ensureVisible(find.byKey(Key(tapKey)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key(tapKey)));
      await tester.pumpAndSettle();
      await shot(tester, name, Key(key));
    }
  });

  // ── 16a：记忆弹窗（用户点名「分类选择按钮贴太近」的那一处）───────────
  testWidgets('复核·16a：记忆弹窗（类型 / 领域的间距）', (tester) async {
    await tester.runAsync(loadRound7Fonts);
    await pumpSurface(
      tester,
      AiMemoryPage(
        repository: AiMemoryRepository(
          database: database,
          clock: FixedAppClock(now),
          idGenerator: _Ids(),
        ),
      ),
      width: 412,
      height: 900,
      wrapScaffold: false,
    );
    await tester.tap(find.byKey(const Key('ai-memory-add')));
    await tester.pumpAndSettle();
    await shot(
      tester,
      'verify-16a-memory-editor',
      const Key('ai-memory-editor-kind'),
    );
    await unmount(tester);
  });

  // ── 4：聊天里的用户带图消息（缩略图 + 文件名 + 说明）─────────────────
  testWidgets('复核·4：用户带图消息（缩略图 + 文件名 + 说明）', (tester) async {
    await tester.runAsync(loadRound7Fonts);
    await pumpSurface(
      tester,
      Center(
        child: ImageMessage(
          key: const Key('verify-image-message'),
          image: const SizedBox(
            width: 180,
            height: 140,
            child: ColoredBox(
              color: Color(0xFF7C8F6A),
              child: Center(
                child: Text(
                  '菜照缩略图',
                  style: TextStyle(color: Color(0xFFFFFFFF)),
                ),
              ),
            ),
          ),
          caption: '帮我看看这顿午饭',
          onZoom: () {},
        ),
      ),
      width: 412,
      height: 320,
    );
    await shot(
      tester,
      'verify-4-image-bubble',
      const Key('verify-image-message'),
    );
  });
}

final class _Ids implements IdGenerator {
  int _value = 0;

  @override
  String next() => 'vf-${_value++}';
}

final class _NoopStore implements AiProviderSettingsStore {
  @override
  Future<void> clearApiKey() async {}

  @override
  Future<AiProviderSettings> load() async =>
      const AiProviderSettings(configuration: null, hasApiKey: false);

  @override
  Future<AiProviderConfiguration?> loadConfiguration() async => null;

  @override
  Future<void> save(AiProviderSettingsInput input) async {}
}
