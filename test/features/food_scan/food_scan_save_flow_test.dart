import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';

import 'scan_test_helpers.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_router.dart';
import 'package:localfit_ai/app/localfit_app.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/food_scan/application/load_meal_recognition_disclosure.dart';
import 'package:localfit_ai/features/food_scan/application/local_food_search.dart';
import 'package:localfit_ai/features/food_scan/application/prepare_meal_image.dart';
import 'package:localfit_ai/features/food_scan/application/recognize_confirmed_meal_image.dart';
import 'package:localfit_ai/features/food_scan/application/resolve_meal_scan_candidates.dart';
import 'package:localfit_ai/features/food_scan/domain/meal_estimate.dart';
import 'package:localfit_ai/features/food_scan/domain/meal_image.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/food_record.dart';
import 'package:localfit_ai/features/settings/domain/ai_provider_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 9, 9, 12);
  late AppDatabase database;
  late MealRepository meals;
  late _TemporaryStore store;
  late _Picker picker;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await database
        .into(database.foods)
        .insert(
          FoodsCompanion.insert(
            id: 'rice',
            name: '米饭',
            kcalPer100g: 116,
            proteinPer100g: 2.6,
            carbsPer100g: 25.9,
            fatPer100g: 0.3,
            source: 'seed',
            isUserCreated: const Value(false),
            createdAt: now.toUtc(),
            updatedAt: now.toUtc(),
          ),
        );
    meals = MealRepository(
      database: database,
      idGenerator: _Ids(),
      clock: FixedAppClock(now),
    );
    store = _TemporaryStore();
    picker = _Picker();
  });

  tearDown(() => database.close());

  testWidgets(
    'renders one recognition candidate card per recognized item on the page',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      // 两项都识别出来：候选区要一行一项，而不是把多项挤成一行。
      await tester.pumpWidget(
        _app(
          meals,
          store,
          picker,
          now,
          provider: _Provider(
            meals: [
              [(name: '米饭', grams: 180.0), (name: '米饭', grams: 120.0)],
            ],
          ),
        ),
      );
      await _reachCandidate(tester, picker);

      // docs/21 §3 的 `MealRecognitionCandidateCard`（实现名
      // `_CandidateItemCard`，私有）在页面上的可断言落点：每个候选一整套
      // 编辑控件。两行 ⇒ 两组克数输入与两个移除按钮。
      expect(find.byKey(const Key('scan-candidate-grams-0')), findsOneWidget);
      expect(find.byKey(const Key('scan-candidate-grams-1')), findsOneWidget);
      expect(find.byKey(const Key('scan-candidate-remove-0')), findsOneWidget);
      expect(find.byKey(const Key('scan-candidate-remove-1')), findsOneWidget);
      // 候选区仍在草案卡内，确认按钮由候选解析结果驱动而非恒亮。
      expect(find.byKey(const Key('scan-candidate-card')), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('scan-candidate-confirm')),
            )
            .onPressed,
        isNotNull,
      );
    },
  );

  testWidgets(
    'final cancellation retains the candidate without saving or cleanup',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(_app(meals, store, picker, now));
      await _reachCandidate(tester, picker);

      await tester.scrollUntilVisible(
        find.byKey(const Key('scan-candidate-confirm')),
        400,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      // Ensure the button is fully within viewport before tapping
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('scan-candidate-confirm')));
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      expect(find.text('确认入账？'), findsOneWidget);
      await tester.tap(find.byKey(const Key('scan-save-cancel')));
      await tester.pumpAndSettle();

      expect(await meals.listRecent(), isEmpty);
      expect(store.deleted, isEmpty);
      expect(find.byKey(const Key('scan-candidate-card')), findsOneWidget);
    },
  );

  testWidgets('does not enable confirmation for an unresolved candidate', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _app(meals, store, picker, now, foodSearch: const _NoFoodSearch()),
    );
    await _reachCandidate(tester, picker);

    expect(find.text('尚未匹配本地食物，无法计算营养。'), findsOneWidget);
    final confirmation = tester.widget<FilledButton>(
      find.byKey(const Key('scan-candidate-confirm')),
    );
    expect(confirmation.onPressed, isNull);
    expect(await meals.listRecent(), isEmpty);
    expect(store.deleted, isEmpty);
  });

  testWidgets(
    'keeps the candidate and rolls back the meal when persistence fails',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        _app(meals, store, picker, now, foodSearch: const _MissingFoodSearch()),
      );
      await _reachCandidate(tester, picker);

      await tester.scrollUntilVisible(
        find.byKey(const Key('scan-candidate-confirm')),
        400,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('scan-candidate-confirm')));
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const Key('scan-save-confirm')));
      await tester.pumpAndSettle();

      expect(find.text('餐食未能保存到本机，请稍后重试。'), findsOneWidget);
      expect(find.byKey(const Key('scan-candidate-card')), findsOneWidget);
      expect(store.deleted, isEmpty);
      expect(await database.select(database.meals).get(), isEmpty);
      expect(await database.select(database.mealItems).get(), isEmpty);
    },
  );

  testWidgets(
    'retains an already saved meal when cleanup fails and allows discard retry',
    (tester) async {
      final failingStore = _TemporaryStore(failDeletes: true);
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(_app(meals, failingStore, picker, now));
      await _reachCandidate(tester, picker);

      await tester.scrollUntilVisible(
        find.byKey(const Key('scan-candidate-confirm')),
        400,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('scan-candidate-confirm')));
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const Key('scan-save-confirm')));
      await tester.pumpAndSettle();

      expect(find.text('餐食已保存到本机，但临时图片尚未清理；请稍后重试丢弃。'), findsOneWidget);
      expect(await meals.listRecent(), hasLength(1));
      expect(failingStore.deleteAttempts, 1);
      expect(failingStore.deleted, isEmpty);
      expect(find.byKey(const Key('scan-candidate-confirm')), findsNothing);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('scan-analyze')))
            .onPressed,
        isNull,
      );

      failingStore.failDeletes = false;
      await tester.tap(find.byKey(const Key('scan-discard')));
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      expect(failingStore.deleteAttempts, 2);
      expect(failingStore.deleted, hasLength(1));
      expect(find.byKey(const Key('scan-preview')), findsNothing);
      expect(await meals.listRecent(), hasLength(1));
    },
  );

  testWidgets(
    'saves an ai scan atomically, cleans its image, and updates today',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final haptics = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'HapticFeedback.vibrate') {
              haptics.add(call.arguments as String);
            }
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });
      await tester.pumpWidget(_app(meals, store, picker, now));
      await _reachCandidate(tester, picker);

      await tester.enterText(
        find.byKey(const Key('scan-candidate-grams-0')),
        '200',
      );
      await tester.pump();
      await tester.scrollUntilVisible(
        find.byKey(const Key('scan-candidate-confirm')),
        400,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('scan-candidate-confirm')));
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      expect(find.text('确认入账？'), findsOneWidget);
      expect(find.textContaining('米饭 · 200g · 232 kcal'), findsOneWidget);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('scan-save-confirm')));
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text('餐食未能保存到本机，请稍后重试。'), findsNothing);

      final records = await meals.listRecent();
      expect(records, hasLength(1));
      expect(records.single.source, 'ai_scan');
      expect(records.single.localDate, '2026-09-09');
      expect(records.single.slot.storedValue, 'lunch');
      expect(records.single.items, hasLength(1));
      expect(records.single.items.single.foodId, 'rice');
      expect(records.single.items.single.grams, 200);
      expect(records.single.items.single.nutrition.kcal, 232);
      expect(store.deleted, hasLength(1));
      expect(find.text('餐食已保存到本机，并已计入今日统计。'), findsOneWidget);
      // docs/21 §3：确认成功用 mint100 成功卡 + ✓ + light 触觉（不再走错误卡）。
      expect(find.byKey(const Key('scan-success')), findsOneWidget);
      expect(find.byKey(const Key('scan-error')), findsNothing);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(haptics, ['HapticFeedbackType.selectionClick']);

      // 拍照识餐是推入式二级页（docs/21 §4.1）：先经页面返回键
      // （back-nutrition）回饮食，再从底栏去今日。
      await tester.tap(find.byKey(const Key('scan-back')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('今日'));
      await tester.pumpAndSettle();
      // Round7 A `.energy-summary` 的标题就是「今日营养」（`app.js:128`）。
      expect(find.text('今日营养'), findsOneWidget);
      // 新今日页（docs/21 §5.1）：摄入量是圆环里的裸数字，剩余量在热量卡 foot。
      // 232 同时在**两处**出现（环心值 + 餐次行值），纯文本 finder 会命中 2 个
      // （round7 2A 实测），两处各锚 Key 断一次。
      expect(
        tester
            .widget<Text>(find.byKey(const Key('dashboard-ring-consumed')))
            .data,
        '232',
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('dashboard-meal-row-lunch-0')),
          matching: find.text('232'),
        ),
        findsOneWidget,
        reason: '识别入库的午餐也要出现在今日餐次卡的行值里',
      );
      // 这份夹具**没有建档/目标** ⇒ 今日页走 A 的无目标分支：foot 写
      // 「尚未设定目标 / 设置目标后查看进度」，剩余额度行（`dashboard-remaining-line`）
      // 只在有目标时存在——旧断言在这一档夹具里恒不成立（round7 2A 实测）。
      // 有目标的剩余行由 round7_dashboard_today_test 与 dashboard_page_test 钉住。
      expect(find.byKey(const Key('dashboard-remaining-line')), findsNothing);
      expect(find.text('设置目标后查看进度'), findsOneWidget);
      expect(find.textContaining('午餐'), findsWidgets);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    },
  );

  testWidgets(
    'compares a leftover photo and persists net intake while cleaning both images',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(_app(meals, store, picker, now));
      await _reachCandidate(tester, picker);

      await tester.enterText(
        find.byKey(const Key('scan-candidate-grams-0')),
        '200',
      );
      await tester.pump();
      await tester.scrollUntilVisible(
        find.byKey(const Key('scan-leftover-gallery')),
        600,
        scrollable: find.byType(Scrollable).first,
      );
      picker.next = SelectedMealImage(
        bytes: Uint8List.fromList([2]),
        source: MealImageSource.gallery,
      );
      await tester.ensureVisible(
        find.byKey(const Key('scan-leftover-gallery')),
      );
      await tester.tap(find.byKey(const Key('scan-leftover-gallery')));
      await tester.pumpAndSettle();
      expect(picker.pickCount, 2);
      await tester.scrollUntilVisible(
        find.byKey(const Key('scan-leftover-analyze'), skipOffstage: false),
        600,
        scrollable: find.byType(Scrollable).first,
      );
      // 剩余预览卡是 4:3（≈651dp 高），把分析键顶出懒 ListView 的构建范围；
      // 先滚到它再取，否则 finder 匹配不到（skipOffstage 只管路由，不管未构建）。
      await tester.scrollUntilVisible(
        find.byKey(const Key('scan-leftover-analyze')),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(
        find.byKey(const Key('scan-leftover-analyze')),
      );
      // 2026-10-03：`scan-leftover-analyze` 收敛到 §3.8 B3 `LfPillButton`
      // （内部 `TextButton`）⇒ 取 M3 按钮公共基类；断言仍是「这个键可点」。
      final analyzeButton = tester.widget<ButtonStyleButton>(
        find.byKey(const Key('scan-leftover-analyze'), skipOffstage: false),
      );
      analyzeButton.onPressed!();
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('scan-leftover-candidate-grams-0')),
        '50',
      );
      await tester.pump();
      // 剩余编辑器承担净摄入入账（文案区分两个编辑器）。
      //
      // 用 scrollUntilVisible 而不是 ensureVisible：页面末尾留了底栏
      // 高度（navBarReservedSpace）的空白，ensureVisible 只保证「进入
      // 视口」，会出现控件恰好落在浮岛底下、tap 打不到的情形。
      // scrollUntilVisible 逐次滚动直到目标真正可见再点。
      await tester.scrollUntilVisible(
        find.byKey(const Key('scan-leftover-candidate-confirm')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('scan-leftover-candidate-confirm')),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('米饭 · 150g · 174 kcal'), findsOneWidget);

      await tester.tap(find.byKey(const Key('scan-save-confirm')));
      await tester.pumpAndSettle();

      final records = await meals.listRecent();
      expect(records, hasLength(1));
      expect(records.single.items.single.grams, 150);
      expect(records.single.items.single.nutrition.kcal, 174);
      expect(store.deleted, hasLength(2));
    },
  );

  testWidgets('blocks saving when the leftover photo has unresolved items', (
    tester,
  ) async {
    // 剩余照片里若有未匹配项，`resolvedItems` 会把它静默丢掉，于是剩余量被
    // 少算、净摄入被高估（用户看到的摄入比真实吃进去的多）。这种「算不全」
    // 必须在入账前拦住，而不是拿部分剩余量凑一个数。
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // 第二次识别（剩余照片）返回本地食物库匹配不到的名字。
    final provider = _Provider(names: const ['米饭', '未知菜品']);
    await tester.pumpWidget(
      _app(meals, store, picker, now, provider: provider),
    );
    await _reachCandidate(tester, picker);

    await tester.enterText(
      find.byKey(const Key('scan-candidate-grams-0')),
      '200',
    );
    await tester.pump();
    await tester.scrollUntilVisible(
      find.byKey(const Key('scan-leftover-gallery')),
      600,
      scrollable: find.byType(Scrollable).first,
    );
    picker.next = SelectedMealImage(
      bytes: Uint8List.fromList([2]),
      source: MealImageSource.gallery,
    );
    await tester.ensureVisible(find.byKey(const Key('scan-leftover-gallery')));
    await tester.tap(find.byKey(const Key('scan-leftover-gallery')));
    await tester.pumpAndSettle();
    // 剩余预览卡是 4:3（≈651dp 高），把分析键顶出懒 ListView 的构建范围；
    // 先滚到它再取，否则 finder 匹配不到（skipOffstage 只管路由，不管未构建）。
    await tester.scrollUntilVisible(
      find.byKey(const Key('scan-leftover-analyze')),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.byKey(const Key('scan-leftover-analyze')));
    // 2026-10-03：同上，`scan-leftover-analyze` 的实现在 §3.8 里归 B3
    // `LfPillButton`（内部 `TextButton`），故取 M3 按钮公共基类。
    final analyzeButton = tester.widget<ButtonStyleButton>(
      find.byKey(const Key('scan-leftover-analyze'), skipOffstage: false),
    );
    analyzeButton.onPressed!();
    await tester.pumpAndSettle();
    expect(provider.calls, 2);

    // 从餐前编辑器点确认：必须被拦住，不能按 200g 全额入账。
    await tester.scrollUntilVisible(
      find.byKey(const Key('scan-candidate-confirm')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('scan-candidate-confirm')));
    await tester.pumpAndSettle();

    expect(find.text('确认入账？'), findsNothing, reason: '剩余项未解析时不得入账');
    expect(find.textContaining('剩余'), findsWidgets, reason: '要说明是剩余照片的问题');
    expect(await meals.listRecent(), isEmpty);
    expect(store.deleted, isEmpty);
  });

  testWidgets('applies net intake when confirmed from the before-meal editor', (
    tester,
  ) async {
    // 两个编辑器都走同一条净摄入路径：从餐前编辑器确认也不能绕过剩余量。
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_app(meals, store, picker, now));
    await _reachCandidate(tester, picker);

    await tester.enterText(
      find.byKey(const Key('scan-candidate-grams-0')),
      '200',
    );
    await tester.pump();
    await tester.scrollUntilVisible(
      find.byKey(const Key('scan-leftover-gallery')),
      600,
      scrollable: find.byType(Scrollable).first,
    );
    picker.next = SelectedMealImage(
      bytes: Uint8List.fromList([2]),
      source: MealImageSource.gallery,
    );
    await tester.ensureVisible(find.byKey(const Key('scan-leftover-gallery')));
    await tester.tap(find.byKey(const Key('scan-leftover-gallery')));
    await tester.pumpAndSettle();
    // 剩余预览卡是 4:3（≈651dp 高），把分析键顶出懒 ListView 的构建范围；
    // 先滚到它再取，否则 finder 匹配不到（skipOffstage 只管路由，不管未构建）。
    await tester.scrollUntilVisible(
      find.byKey(const Key('scan-leftover-analyze')),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.byKey(const Key('scan-leftover-analyze')));
    // 2026-10-03：同上，`scan-leftover-analyze` 的实现在 §3.8 里归 B3
    // `LfPillButton`（内部 `TextButton`），故取 M3 按钮公共基类。
    final analyzeButton = tester.widget<ButtonStyleButton>(
      find.byKey(const Key('scan-leftover-analyze'), skipOffstage: false),
    );
    analyzeButton.onPressed!();
    await tester.pumpAndSettle();
    final leftoverGrams = tester.widget<TextFormField>(
      find.byKey(
        const Key('scan-leftover-candidate-grams-0'),
        skipOffstage: false,
      ),
    );
    leftoverGrams.onChanged!('50');
    await tester.pump();

    await tester.scrollUntilVisible(
      find.byKey(const Key('scan-candidate-confirm')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('scan-candidate-confirm')));
    await tester.pumpAndSettle();
    expect(find.textContaining('米饭 · 150g · 174 kcal'), findsOneWidget);

    await tester.tap(find.byKey(const Key('scan-save-confirm')));
    await tester.pumpAndSettle();

    final records = await meals.listRecent();
    expect(records, hasLength(1));
    expect(records.single.items.single.grams, 150);
    expect(records.single.items.single.nutrition.kcal, 174);
    expect(store.deleted, hasLength(2));
  });

  testWidgets(
    'blocks saving while a picked leftover photo is not analyzed yet',
    (tester) async {
      // 只选了剩余照片但还没点「分析剩余餐食」时，_leftoverCandidateDraft 仍是 null：
      // 若此时按餐前量入账，用户挂上的剩余照片被静默忽略、净摄入被高估。
      // 必须先拦住，要求先分析或丢弃这张照片。
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(_app(meals, store, picker, now));
      await _reachCandidate(tester, picker);

      await tester.enterText(
        find.byKey(const Key('scan-candidate-grams-0')),
        '200',
      );
      await tester.pump();
      await tester.scrollUntilVisible(
        find.byKey(const Key('scan-leftover-gallery')),
        600,
        scrollable: find.byType(Scrollable).first,
      );
      picker.next = SelectedMealImage(
        bytes: Uint8List.fromList([2]),
        source: MealImageSource.gallery,
      );
      await tester.ensureVisible(
        find.byKey(const Key('scan-leftover-gallery')),
      );
      await tester.tap(find.byKey(const Key('scan-leftover-gallery')));
      await tester.pumpAndSettle();

      // 未点「分析剩余餐食」，直接确认入账。
      await tester.scrollUntilVisible(
        find.byKey(const Key('scan-candidate-confirm')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const Key('scan-candidate-confirm')));
      await tester.pumpAndSettle();

      expect(find.text('确认入账？'), findsNothing, reason: '剩余照片未分析时不得按餐前量入账');
      expect(find.textContaining('剩余'), findsWidgets);
      expect(await meals.listRecent(), isEmpty);
    },
  );

  testWidgets(
    'surfaces the warning when leftover exceeds the before-meal amount',
    (tester) async {
      // 剩余量大于餐前量时该项被整项扣掉（净摄入按 0）。只要还有别的项留下，
      // 入账会照常进行——所以这条告警是用户唯一能知道「为什么少了一项」的途径。
      // 视口放高一些：两项编辑器更高，否则懒加载 ListView 不会构建剩余照片按钮。
      tester.view.physicalSize = const Size(900, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      // 餐前：米饭 200g + 鸡胸肉 150g；剩余：米饭 500g（超过餐前）。
      final provider = _Provider(
        meals: const [
          [(name: '米饭', grams: 200), (name: '鸡胸肉', grams: 150)],
          [(name: '米饭', grams: 500)],
        ],
      );
      await tester.pumpWidget(
        _app(
          meals,
          store,
          picker,
          now,
          provider: provider,
          foodSearch: const _MultiFoodSearch(),
        ),
      );
      await _reachCandidate(tester, picker);

      await tester.enterText(
        find.byKey(const Key('scan-candidate-grams-0')),
        '200',
      );
      await tester.pump();
      await tester.scrollUntilVisible(
        find.byKey(const Key('scan-leftover-gallery')),
        600,
        scrollable: find.byType(Scrollable).first,
      );
      picker.next = SelectedMealImage(
        bytes: Uint8List.fromList([2]),
        source: MealImageSource.gallery,
      );
      await tester.ensureVisible(
        find.byKey(const Key('scan-leftover-gallery')),
      );
      await tester.tap(find.byKey(const Key('scan-leftover-gallery')));
      await tester.pumpAndSettle();
      // 剩余预览卡是 4:3（≈651dp 高），把分析键顶出懒 ListView 的构建范围；
      // 先滚到它再取，否则 finder 匹配不到（skipOffstage 只管路由，不管未构建）。
      await tester.scrollUntilVisible(
        find.byKey(const Key('scan-leftover-analyze')),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(
        find.byKey(const Key('scan-leftover-analyze')),
      );
      // 2026-10-03：`scan-leftover-analyze` 收敛到 §3.8 B3 `LfPillButton`
      // （内部 `TextButton`）⇒ 取 M3 按钮公共基类；断言仍是「这个键可点」。
      final analyzeButton = tester.widget<ButtonStyleButton>(
        find.byKey(const Key('scan-leftover-analyze'), skipOffstage: false),
      );
      analyzeButton.onPressed!();
      await tester.pumpAndSettle();

      // 剩余米饭 500g > 餐前 200g → 该项按 0 计并被扣掉，鸡胸肉保留。
      final leftoverGrams = tester.widget<TextFormField>(
        find.byKey(
          const Key('scan-leftover-candidate-grams-0'),
          skipOffstage: false,
        ),
      );
      leftoverGrams.onChanged!('500');
      await tester.pump();

      final confirm = tester.widget<FilledButton>(
        find.byKey(
          const Key('scan-leftover-candidate-confirm'),
          skipOffstage: false,
        ),
      );
      confirm.onPressed!();
      await tester.pumpAndSettle(const Duration(milliseconds: 300));

      expect(
        find.textContaining('剩余量超过餐前量'),
        findsOneWidget,
        reason: '整项被扣掉必须给出原因',
      );
    },
  );

  testWidgets(
    'explains an all-eaten-away meal without claiming amounts are equal',
    (tester) async {
      // 唯一一项被整项扣光时 items 为空、走不到确认弹层：这里必须说清真实原因
      // （剩余量不小于餐前量），不能笼统说成「剩余量与餐前量相同」——剩余量
      // 超过餐前量时那句话是错的，会把用户引向错误的排查方向。
      tester.view.physicalSize = const Size(900, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final provider = _Provider(
        meals: const [
          [(name: '米饭', grams: 200)],
          [(name: '米饭', grams: 500)],
        ],
      );
      await tester.pumpWidget(
        _app(meals, store, picker, now, provider: provider),
      );
      await _reachCandidate(tester, picker);

      await tester.enterText(
        find.byKey(const Key('scan-candidate-grams-0')),
        '200',
      );
      await tester.pump();
      await tester.scrollUntilVisible(
        find.byKey(const Key('scan-leftover-gallery')),
        400,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      picker.next = SelectedMealImage(
        bytes: Uint8List.fromList([2]),
        source: MealImageSource.gallery,
      );
      await tester.ensureVisible(
        find.byKey(const Key('scan-leftover-gallery')),
      );
      await tester.tap(find.byKey(const Key('scan-leftover-gallery')));
      await tester.pumpAndSettle();
      // 剩余预览卡是 4:3（≈651dp 高），把分析键顶出懒 ListView 的构建范围；
      // 先滚到它再取，否则 finder 匹配不到（skipOffstage 只管路由，不管未构建）。
      await tester.scrollUntilVisible(
        find.byKey(const Key('scan-leftover-analyze')),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(
        find.byKey(const Key('scan-leftover-analyze')),
      );
      // 2026-10-03：`scan-leftover-analyze` 收敛到 §3.8 B3 `LfPillButton`
      // （内部 `TextButton`）⇒ 取 M3 按钮公共基类；断言仍是「这个键可点」。
      final analyzeButton = tester.widget<ButtonStyleButton>(
        find.byKey(const Key('scan-leftover-analyze'), skipOffstage: false),
      );
      analyzeButton.onPressed!();
      await tester.pumpAndSettle();

      // 使用直接调用 onChanged 修改克数（规避键盘/输入框问题）
      final leftoverGrams = tester.widget<TextFormField>(
        find.byKey(
          const Key('scan-leftover-candidate-grams-0'),
          skipOffstage: false,
        ),
      );
      leftoverGrams.onChanged!('500');
      await tester.pump();

      // 点击确认按钮（调用 onPressed 直接触发，避免 tap 坐标问题）
      final confirm = tester.widget<FilledButton>(
        find.byKey(
          const Key('scan-leftover-candidate-confirm'),
          skipOffstage: false,
        ),
      );
      confirm.onPressed!();
      await tester.pumpAndSettle(const Duration(milliseconds: 300));

      // 错误卡在页面底部，懒加载 ListView 不滚到它就不会构建；先滚过去再断言。
      // 这里必须真的滚动：用 skipOffstage: false 找「未构建」的 widget 也会落空，
      // 断言会退化成「找不到就通过」。
      await tester.scrollUntilVisible(
        find.byKey(const Key('scan-error')),
        400,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      // 验证错误卡被创建：剩余量超过餐前量 → 该项被扣掉 → items 为空
      expect(
        find.byKey(const Key('scan-error')),
        findsOneWidget,
        reason: '剩余量超过餐前量时应显示错误卡',
      );
      // 错误卡包含真实原因，且不能出现「剩余量与餐前量相同」这种错误归因
      // （Key 挂在 Card 上，正文要往下找 Text，不能直接 widgetList<Text>）。
      final errorText = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byKey(const Key('scan-error')),
              matching: find.byType(Text),
            ),
          )
          .map((widget) => widget.data)
          .whereType<String>()
          .join(' | ');
      expect(errorText, contains('剩余量超过餐前量'));
      expect(errorText, isNot(contains('剩余量与餐前量相同')));
      expect(await meals.listRecent(), isEmpty);
    },
  );
}

Widget _app(
  MealRepository meals,
  _TemporaryStore store,
  _Picker picker,
  DateTime now, {
  LocalFoodSearch foodSearch = const _FoodSearch(),
  MealRecognitionProvider? provider,
  ResolveMealScanCandidates? resolveMealScanCandidates,
}) => LocalFitApp(
  initialLocation: AppRoutes.foodScan,
  mealRepository: meals,
  now: now,
  prepareMealImage: PrepareMealImage(
    picker: picker,
    processor: const _Processor(),
    store: store,
  ),
  recognizeConfirmedMealImage: RecognizeConfirmedMealImage(
    provider: provider ?? _Provider(),
  ),
  loadMealRecognitionDisclosure: LoadMealRecognitionDisclosure(
    configurationReader: const _Configuration(),
  ),
  resolveMealScanCandidates:
      resolveMealScanCandidates ??
      ResolveMealScanCandidates(foodSearch: foodSearch),
);

Future<void> _reachCandidate(WidgetTester tester, _Picker picker) async {
  // P10 拍照直通：scan-camera 选完图自动开始识别；结果面出来后进编辑器。
  picker.next = SelectedMealImage(
    bytes: Uint8List.fromList([1]),
    source: MealImageSource.camera,
  );
  await tester.tap(find.byKey(const Key('scan-camera')));
  await _pumpUntilRecognitionDone(tester);
  await enterEditor(tester);
  await tester.pumpAndSettle();
}

/// P10 拍照直通：识别在真实异步间隙推进；等它落定（预览/草稿卡/结果面/
/// 错误任一出现），最后统一 settle（结果态没有常驻动画，可以 settle）。
Future<void> _pumpUntilRecognitionDone(WidgetTester tester) async {
  for (var index = 0; index < 25; index++) {
    final preview = find.byKey(const Key('scan-preview')).evaluate();
    final draft = find.byKey(const Key('scan-draft-card')).evaluate();
    final overview = find.byKey(const Key('scan-result-overview')).evaluate();
    final error = find.byKey(const Key('scan-error')).evaluate();
    if (preview.isNotEmpty ||
        draft.isNotEmpty ||
        overview.isNotEmpty ||
        error.isNotEmpty) {
      break;
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

final class _Ids implements IdGenerator {
  int _value = 0;

  @override
  String next() => 'scan-id-${_value++}';
}

final class _Picker implements MealImagePicker {
  SelectedMealImage? next;
  int pickCount = 0;

  @override
  Future<SelectedMealImage?> pick(MealImageSource source) async {
    pickCount++;
    return next;
  }

  @override
  Future<SelectedMealImage?> recoverLost() async => null;
}

final class _Processor implements MealImageProcessor {
  const _Processor();

  @override
  Future<ProcessedMealImage> process(SelectedMealImage selected) async =>
      ProcessedMealImage(
        bytes: Uint8List.fromList([1, 2, 3]),
        width: 100,
        height: 80,
      );
}

final class _TemporaryStore implements TemporaryMealImageStore {
  _TemporaryStore({this.failDeletes = false});

  final deleted = <PreparedMealImage>[];
  bool failDeletes;
  int deleteAttempts = 0;

  @override
  Future<void> clearStale() async {}

  @override
  Future<void> clearAll() async {}

  @override
  Future<void> delete(PreparedMealImage image) async {
    deleteAttempts++;
    if (failDeletes) {
      throw const MealImageFailure('temporary cleanup failed');
    }
    deleted.add(image);
  }

  @override
  Future<PreparedMealImage> save(ProcessedMealImage image) async =>
      PreparedMealImage(
        path: '/private/meal.jpg',
        width: image.width,
        height: image.height,
        byteLength: image.bytes.length,
      );
}

final class _Configuration implements AiProviderConfigurationReader {
  const _Configuration();

  @override
  Future<AiProviderConfiguration?> loadConfiguration() async =>
      const AiProviderConfiguration(
        baseUrl: 'https://api.example.com/v1/',
        model: 'vision-test',
      );
}

final class _Provider implements MealRecognitionProvider {
  _Provider({this.names = const ['米饭'], this.meals});

  /// 第 n 次识别返回的名字（按调用次序取值，越界取最后一个）。
  final List<String> names;

  /// 第 n 次识别返回的整份条目（需要多项时用；给了它就忽略 [names]）。
  final List<List<({String name, double grams})>>? meals;

  /// 识别调用次数：断言第二次识别（剩余照片）确实发生过。
  int calls = 0;

  @override
  Future<MealEstimateDraft> recognize(
    PreparedMealImage image, {
    MealRecognitionCancellationToken? cancellationToken,
  }) async {
    final perCall = meals;
    final items = perCall != null
        ? perCall[calls.clamp(0, perCall.length - 1)]
        : [(name: names[calls.clamp(0, names.length - 1)], grams: 180.0)];
    calls++;
    return MealEstimateDraft(
      items: [
        for (final item in items)
          MealEstimateItem(
            name: item.name,
            estimatedGrams: item.grams,
            gramsRange: const GramRange(min: 140, max: 220),
            confidence: 0.8,
            ingredients: const [],
            needsConfirmation: false,
            questions: const [],
            cookingMethod: '蒸煮',
          ),
      ],
      warnings: const [],
      mealNotes: null,
    );
  }
}

/// 两项都能在本地匹配到的食物库（净摄入的「部分项被扣掉」场景需要）。
final class _MultiFoodSearch implements LocalFoodSearch {
  const _MultiFoodSearch();

  @override
  Future<List<FoodRecord>> search(String query, {int limit = 30}) async =>
      const [
        FoodRecord(
          id: 'rice',
          name: '米饭',
          kcalPer100g: 116,
          proteinPer100g: 2.6,
          carbsPer100g: 25.9,
          fatPer100g: 0.3,
          isUserCreated: false,
        ),
        FoodRecord(
          id: 'chicken',
          name: '鸡胸肉',
          kcalPer100g: 133,
          proteinPer100g: 24.6,
          carbsPer100g: 0.6,
          fatPer100g: 3.4,
          isUserCreated: false,
        ),
      ];
}

final class _FoodSearch implements LocalFoodSearch {
  const _FoodSearch();

  @override
  Future<List<FoodRecord>> search(String query, {int limit = 30}) async =>
      const [
        FoodRecord(
          id: 'rice',
          name: '米饭',
          kcalPer100g: 116,
          proteinPer100g: 2.6,
          carbsPer100g: 25.9,
          fatPer100g: 0.3,
          isUserCreated: false,
        ),
      ];
}

final class _MissingFoodSearch implements LocalFoodSearch {
  const _MissingFoodSearch();

  @override
  Future<List<FoodRecord>> search(String query, {int limit = 30}) async =>
      const [
        FoodRecord(
          id: 'missing-rice',
          name: '米饭',
          kcalPer100g: 116,
          proteinPer100g: 2.6,
          carbsPer100g: 25.9,
          fatPer100g: 0.3,
          isUserCreated: false,
        ),
      ];
}

final class _NoFoodSearch implements LocalFoodSearch {
  const _NoFoodSearch();

  @override
  Future<List<FoodRecord>> search(String query, {int limit = 30}) async =>
      const [];
}
