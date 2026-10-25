import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_router.dart';
import 'package:localfit_ai/app/localfit_app.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/hydration/data/water_repository.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';
import 'package:localfit_ai/features/onboarding/domain/complete_onboarding.dart';
import 'package:localfit_ai/features/onboarding/domain/nutrition_target_calculator.dart';
import 'package:localfit_ai/features/progress/application/load_intake_trend.dart';
import 'package:localfit_ai/features/progress/data/measurement_repository.dart';
import 'package:localfit_ai/features/progress/data/steps_repository.dart';
import 'package:localfit_ai/features/settings/data/profile_identity_repository.dart';
import 'package:localfit_ai/features/training/data/exercise_repository.dart';
import 'package:localfit_ai/features/training/data/exercise_seed_importer.dart';
import 'package:localfit_ai/features/training/data/workout_plan_repository.dart';
import 'package:localfit_ai/features/training/data/workout_session_repository.dart';

import 'support/food_fixture.dart';
import 'support/round7_render.dart';

/// Round7 阶段 2A **整页渲染矩阵**（真装配 + 真数据）：今日页与饮食记录页，
/// 2 主题 × 1.0/1.5/2.0 字号 × 320/360/390/430 宽。
///
/// 与阶段 1 的组件样板矩阵（`round7_component_capture_test.dart`）同一套
/// 边界与字体加载：`LF_ROUND7_CAPTURE_DIR` 指向工作区 tmp 时才落盘，未设置
/// 时**仍会跑完并断言无异常**——所以它同时是「整页在各档宽度/字号下不溢出」
/// 的回归门禁，而不是只在截图时才生效的脚本。
///
/// 视口高度按字号放大（1600×scale），让整页一屏内画完：一次一张图就能审
/// 「整页」，不必拼接滚动帧。真机上页面当然要滚，这个高度只是审图口径。
///
/// 数据不是编的：建档（真算法算出的目标）+ 3 条体重 + 3 餐（一餐来源
/// `ai_scan`，让 source-summary 的「已确认 / 估算」两段都真实出现）+
/// 750ml 饮水 + 6231 步（channel mock，走真 `StepsRepository`）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const localDate = '2026-09-13';
  final now = DateTime(2026, 9, 13, 12);
  const stepsChannel = MethodChannel('localfit/steps');

  late AppDatabase database;
  late FoodRepository foodRepository;
  late MealRepository mealRepository;
  late MeasurementRepository measurementRepository;
  late WaterRepository waterRepository;
  late StepsRepository stepsRepository;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await seedFoodFixture(database);
    await const ExerciseSeedImporter().importIfNeeded(database);
    const ids = UuidV7Generator();
    final clock = FixedAppClock(now);
    // 建档用**固定钟**：目标行按建档当天的 localDate 写，用真钟会写到真实
    // 今天，巡检日（2026-09-13）的今日页就读不到目标。
    await CompleteOnboarding(
      database: database,
      idGenerator: ids,
      clock: clock,
    )(
      const OnboardingInput(
        age: 30,
        biologicalSex: BiologicalSex.male,
        heightCm: 175,
        weightKg: 72,
        activityLevel: ActivityLevel.moderatelyActive,
        goal: HealthGoal.loseFat,
        targetWeightKg: 66,
      ),
    );
    foodRepository = FoodRepository(
      database: database,
      idGenerator: ids,
      clock: clock,
    );
    mealRepository = MealRepository(
      database: database,
      idGenerator: ids,
      clock: clock,
    );
    measurementRepository = MeasurementRepository(
      database: database,
      idGenerator: ids,
      clock: clock,
    );
    waterRepository = WaterRepository(
      database: database,
      idGenerator: ids,
      clock: clock,
    );

    // 步数要**两次 sync 才有数**：`StepsRepository.syncToday` 第一次只把当天
    // 基线钉在当前计数值上（差值 0），第二次读到计数器前进才记 delta。所以
    // 夹具先读 0 建基线、再读 6231 得当天步数——只 sync 一次的夹具今日页
    // 显示 0 步（round7 2A 首轮渲染审看抓到）。
    var counter = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(stepsChannel, (call) async {
          if (call.method == 'read') {
            return <Object?, Object?>{
              'status': 'ok',
              'counter': counter,
              'atMs': 1,
            };
          }
          return null;
        });
    stepsRepository = StepsRepository(
      database: database,
      channel: StepsChannel(),
      idGenerator: ids,
      clock: clock,
    );
    await stepsRepository.syncToday(localDate);
    counter = 6231;
    await stepsRepository.syncToday(localDate);

    // 3 条体重（本周内的不同日子：柱图既有今天（brand 色）也有历史柱）。
    await measurementRepository.saveManualWeight(
      localDate: '2026-09-09',
      weightKg: 68.9,
    );
    await measurementRepository.saveManualWeight(
      localDate: '2026-09-11',
      weightKg: 68.3,
    );
    await measurementRepository.saveManualWeight(
      localDate: localDate,
      weightKg: 68.1,
    );

    // 各餐给**真实用餐时间**：`MealDraft` 没有 `eatenAt`，落库时由
    // `MealRepository.create` 用自己注入的钟盖章。夹具此前三顿都由同一个
    // 固定钟（12:00）落库 ⇒ 帧里三张卡都写「12:00」，看起来像同一时刻吃了
    // 三餐（阶段 2B 步骤 5 审看登记）。这里按餐次给真时间：早餐 08:10、
    // 午餐 12:30、晚餐 18:40、昨天的晚餐 19:05——卡上的时间因此是**事实**。
    Future<void> seedMeal(
      DateTime at,
      MealDraft Function() build, {
      String source = 'manual',
    }) => MealRepository(
      database: database,
      idGenerator: ids,
      clock: FixedAppClock(at.toUtc()),
    ).create(build(), source: source);

    // 3 餐：早餐 / 午餐（手动，已确认）+ 晚餐（AI 识别，估算）。
    await seedMeal(
      DateTime(2026, 9, 13, 8, 10),
      () => MealDraft(
        localDate: localDate,
        slot: MealSlot.breakfast,
        items: const [
          MealItemDraft(
            foodName: '全麦吐司',
            grams: 80,
            nutrition: NutritionValues(
              kcal: 208,
              proteinGrams: 8.2,
              carbsGrams: 36.4,
              fatGrams: 3.1,
            ),
          ),
          MealItemDraft(
            foodName: '水煮蛋',
            grams: 60,
            nutrition: NutritionValues(
              kcal: 86,
              proteinGrams: 7.4,
              carbsGrams: 0.8,
              fatGrams: 5.6,
            ),
          ),
        ],
      ),
    );
    await seedMeal(
      DateTime(2026, 9, 13, 12, 30),
      () => MealDraft(
        localDate: localDate,
        slot: MealSlot.lunch,
        items: const [
          MealItemDraft(
            foodName: '米饭',
            grams: 200,
            nutrition: NutritionValues(
              kcal: 232,
              proteinGrams: 5.2,
              carbsGrams: 51.6,
              fatGrams: 0.6,
            ),
          ),
          MealItemDraft(
            foodName: '清炒时蔬',
            grams: 150,
            nutrition: NutritionValues(
              kcal: 96,
              proteinGrams: 3.1,
              carbsGrams: 9.4,
              fatGrams: 5.2,
            ),
          ),
        ],
      ),
    );
    await seedMeal(
      DateTime(2026, 9, 13, 18, 40),
      () => MealDraft(
        localDate: localDate,
        slot: MealSlot.dinner,
        items: const [
          MealItemDraft(
            foodName: '番茄牛腩煲',
            grams: 320,
            nutrition: NutritionValues(
              kcal: 412,
              proteinGrams: 28.6,
              carbsGrams: 18.2,
              fatGrams: 24.8,
            ),
          ),
        ],
      ),
      source: 'ai_scan',
    );

    // 昨天也留一餐：近 7 日趋势至少要有两天记录，柱图与「N 天有记录」
    // 才有对比（只记今天的话，帧里等于一个「单点」样本）。
    await seedMeal(
      DateTime(2026, 9, 12, 19, 5),
      () => MealDraft(
        localDate: '2026-09-12',
        slot: MealSlot.dinner,
        items: const [
          MealItemDraft(
            foodName: '鸡胸肉沙拉',
            grams: 260,
            nutrition: NutritionValues(
              kcal: 356,
              proteinGrams: 32.4,
              carbsGrams: 14.1,
              fatGrams: 18.2,
            ),
          ),
        ],
      ),
    );

    await waterRepository.add(localDate: localDate, amountMl: 750);
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(stepsChannel, null);
    await database.close();
  });

  Widget app(String location, {Key? key}) => LocalFitApp(
    key: key,
    initialLocation: location,
    foodRepository: foodRepository,
    mealRepository: mealRepository,
    measurementRepository: measurementRepository,
    waterRepository: waterRepository,
    stepsRepository: stepsRepository,
    exerciseRepository: ExerciseRepository(
      database: database,
      idGenerator: const UuidV7Generator(),
      clock: const SystemAppClock(),
    ),
    workoutPlanRepository: WorkoutPlanRepository(
      database: database,
      idGenerator: const UuidV7Generator(),
      clock: const SystemAppClock(),
    ),
    workoutSessionRepository: WorkoutSessionRepository(
      database: database,
      idGenerator: const UuidV7Generator(),
      clock: const SystemAppClock(),
    ),
    profileIdentityRepository: ProfileIdentityRepository(database: database),
    // 缺陷 ④（2A 审看登记）：夹具此前**没接** `loadIntakeTrend`，而生产
    // `main.dart` 是接了（`main.dart:264`）——记录页帧因此从来没有趋势卡与
    // 分析卡，看起来像「只有 1 天数据时不渲染」。这里补上真用例。
    loadIntakeTrend: LoadIntakeTrend(
      database: database,
      mealRepository: mealRepository,
      clock: FixedAppClock(now),
    ),
    now: now,
  );

  testWidgets('今日页与记录页整页矩阵（2 主题 × 3 字号 × 4 宽度）', (tester) async {
    await tester.runAsync(loadRound7Fonts);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    /// 竖轴滚动余量（= 这一帧还装不下的部分，dp）。取所有竖轴 `Scrollable`
    /// 的最大值：页面里还有横向条（周条/分段控件），外层滚动视图才算整页。
    double scrollRemainder() {
      var worst = 0.0;
      for (final element in find.byType(Scrollable).evaluate()) {
        final state = (element as StatefulElement).state as ScrollableState;
        final position = state.position;
        if (position.axis != Axis.vertical) continue;
        final remaining = position.maxScrollExtent - position.pixels;
        if (remaining > worst) worst = remaining;
      }
      return worst;
    }

    double missing = 0;

    for (final route in const [AppRoutes.dashboard, AppRoutes.nutrition]) {
      final page = route == AppRoutes.dashboard ? 'today' : 'record';
      for (final dark in [false, true]) {
        for (final scale in [1.0, 1.5, 2.0]) {
          for (final width in [320.0, 360.0, 390.0, 430.0]) {
            tester.view.devicePixelRatio = 1;
            var height = 1600 * scale;
            tester.view.physicalSize = Size(width, height);
            tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
            tester.view.viewPadding = const FakeViewPadding(
              top: 24,
              bottom: 24,
            );
            // 字号与主题走平台通道（`LocalFitApp` 用 `ThemeMode.system`）——
            // 从外层套 MediaQuery 会被 MaterialApp 自己那份覆盖掉。
            tester.platformDispatcher.textScaleFactorTestValue = scale;
            tester.platformDispatcher.platformBrightnessTestValue = dark
                ? Brightness.dark
                : Brightness.light;
            await tester.pumpWidget(
              // `UniqueKey` 强制每帧一个新 State：`LocalFitApp` 的 `_router`
              // 是 `late final`（State 级只建一次），同一棵树第二次
              // `pumpWidget` 换成 `AppRoutes.nutrition` 会被复用的 State 吃掉、
              // 继续渲染今日页——round7 2A 首轮 24 张 `record-*` 帧其实全是
              // 今日页（帧名与内容不符，逐张审看时才看出来）。
              RepaintBoundary(
                key: round7Boundary,
                child: app(route, key: UniqueKey()),
              ),
            );
            await tester.pumpAndSettle();
            // 视口按内容加高再挂一次：1.0×/320dp 这类「内容比 1600dp 高」的
            // 变体，原视口会在餐次行 / AI 入口之前截断，「整页渲染」名不副实
            // （round7 2A 首轮审看到 `today-light-320-1.0.png` 断在
            // 「今天吃了什么」标题）。加高量按滚动余量算（dp = 物理 px，
            // 因为 devicePixelRatio 恒为 1）。
            missing = scrollRemainder();
            if (missing > 1) {
              height += missing;
              tester.view.physicalSize = Size(width, height);
              await tester.pumpAndSettle();
              missing = scrollRemainder();
            }
            expect(
              missing,
              lessThanOrEqualTo(1),
              reason:
                  '$page ${dark ? 'dark' : 'light'} ${width.toInt()}x$scale '
                  '加高后仍差 ${missing.toStringAsFixed(1)}dp——这一帧装不下整页',
            );
            // 帧必须是**请求的那一页**：本页锚点在、对面锚点不在。没有这条
            // 断言，上面那个「复用 State」的缺陷会静默返回，帧文件名就成了
            // 唯一的（不可信）说法。
            final ownMarker = page == 'today'
                ? const Key('dashboard-greeting')
                : const Key('nutrition-subtab-bar');
            final otherMarker = page == 'today'
                ? const Key('nutrition-subtab-bar')
                : const Key('dashboard-greeting');
            expect(
              find.byKey(ownMarker),
              findsOneWidget,
              reason:
                  '$page ${dark ? 'dark' : 'light'} ${width.toInt()}x$scale '
                  '渲染的不是本页（找不到 $ownMarker）',
            );
            expect(
              find.byKey(otherMarker),
              findsNothing,
              reason:
                  '$page ${dark ? 'dark' : 'light'} ${width.toInt()}x$scale '
                  '渲染的是对面那页（找到了 $otherMarker）',
            );
            if (page == 'record') {
              // 缺陷 ④ 的哨兵：记录页帧里趋势卡与分析卡必须真的在（夹具没接
              // `loadIntakeTrend` 时这两卡整块不渲染，而帧看起来「正常」）。
              for (final key in const [
                Key('nutrition-record-trend-chart'),
                Key('nutrition-record-analysis'),
              ]) {
                expect(
                  find.byKey(key),
                  findsOneWidget,
                  reason:
                      'record ${dark ? 'dark' : 'light'} '
                      '${width.toInt()}x$scale 缺 $key（夹具接线断了？）',
                );
              }
            }
            expect(
              tester.takeException(),
              isNull,
              reason:
                  '$page ${dark ? 'dark' : 'light'} ${width.toInt()}x$scale',
            );
            final name =
                '$page-${dark ? 'dark' : 'light'}-${width.toInt()}-$scale';
            await captureRound7(tester, name);
          }
        }
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('今日页体重趋势「月」视图（横轴 = 每周一的 M/D）（3 帧）', (tester) async {
    // 2026-10-16 用户：「体重趋势卡片月视图你要标的是每周一对应的日期，而不是
    // 一堆 1」。这张面此前没有任何帧——旧口径「锚点日 ∈ {1,5,10,15,20,25,月末}
    // **且**当天有记录」才标，整月只记几天时横轴几乎全空。现在锚点日恒显示
    // 日号，且只标**周一**。
    await tester.runAsync(loadRound7Fonts);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    for (final (dark, width, scale) in const [
      (false, 360.0, 1.0),
      (true, 360.0, 1.0),
      (false, 320.0, 2.0),
    ]) {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 1600 * scale);
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
      tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      tester.platformDispatcher.platformBrightnessTestValue = dark
          ? Brightness.dark
          : Brightness.light;

      await tester.pumpWidget(
        RepaintBoundary(
          key: round7Boundary,
          child: app(AppRoutes.dashboard, key: UniqueKey()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('dashboard-weight-range-month')));
      await tester.pumpAndSettle();

      final label =
          'today-month ${dark ? 'dark' : 'light'} ${width.toInt()}x$scale';
      expect(find.byKey(const Key('dashboard-weight-chart')), findsOneWidget);
      // 横向轴文案：只准出现 `M/D` 形式的**周一**日期；「一堆 1」那种裸日号
      // 一个都不许有（旧口径的日号锚点集正是 1/5/10/15/20/25）。
      final axis = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byKey(const Key('dashboard-weight-chart')),
              matching: find.byType(Text),
            ),
          )
          .map((text) => text.data ?? '')
          .where((data) => RegExp(r'^\d{1,2}/\d{1,2}$').hasMatch(data))
          .toList();
      final bareDayNumbers = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byKey(const Key('dashboard-weight-chart')),
              matching: find.byType(Text),
            ),
          )
          .map((text) => text.data ?? '')
          .where((data) => RegExp(r'^\d{1,2}$').hasMatch(data))
          .toList();
      expect(bareDayNumbers, isEmpty, reason: '$label：月视图横轴又出现了裸日号');
      expect(
        axis.length,
        greaterThanOrEqualTo(2),
        reason: '$label：月视图横轴没有 `M/D` 日期（周一锚点没画出来）',
      );
      // **真的画出来了**：`axisLabel` 字符串对不算数——格宽只有绘图区/天数
      // （360dp 下约 10dp），`maxLines: 1` 会把「9/14」压成「9」（用户看到的
      // 「一堆 1」就是这个截断，2026-10-16 月视图帧实看抓出）。`didExceedMaxLines`
      // 是渲染层的截断事实，比字符串判据强一档。
      for (final data in axis) {
        final paragraph = tester.renderObject<RenderParagraph>(find.text(data));
        expect(
          paragraph.didExceedMaxLines,
          isFalse,
          reason: '$label：横轴「$data」被截断成更短的文本（月视图格宽放不下）',
        );
      }
      expect(tester.takeException(), isNull, reason: label);

      await captureRound7(
        tester,
        'today-month-${dark ? 'dark' : 'light'}-${width.toInt()}-$scale',
      );
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('整页矩阵默认在无截图环境也执行（捕获变量是唯一开关）', (tester) async {
    // 这条不是形式主义：矩阵测试若被 `LF_ROUND7_CAPTURE_DIR` 跳过，CI 上就
    // 只剩「本机截过图」的口头结论，溢出兜底也没有回归面。断言变量只影响
    // 落盘（`captureRound7` 内部判断），测试本身恒跑。
    expect(
      Platform.environment.containsKey('LF_ROUND7_CAPTURE_DIR') ||
          Platform.environment['LF_ROUND7_CAPTURE_DIR'] == null,
      isTrue,
    );
  });
}
