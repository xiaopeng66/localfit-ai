import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_router.dart';
import 'package:localfit_ai/app/localfit_app.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart';
import 'package:localfit_ai/features/nutrition/application/add_dish_to_meal.dart';
import 'package:localfit_ai/features/nutrition/data/dish_library_repository.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/onboarding/domain/complete_onboarding.dart';
import 'package:localfit_ai/features/onboarding/domain/nutrition_target_calculator.dart';

import 'support/food_fixture.dart';
import 'support/round7_render.dart';

/// Round9：**食堂目录二级页（含「今日推荐」leading）** 整页渲染矩阵（真装配 + 真数据）。
///
/// 【为什么必须新增这一面】2026-10-16 用户第 9 批清单里，N3（分析后目录要显示
/// 「已分析」与结果）、N4（推荐卡要有菜品照片，后补照片也要跟着更新）、N7（今日
/// 推荐改手动按钮）、N5（价格从所有地方删掉）四处都在**这张页面上**，而它此前
/// **没有任何渲染帧**：`round7_menu_capture_test.dart` 拍的是饮食 tab 的菜单页
/// （`nutrition-menu-*`），不是这个从菜单页推入的二级页。这三条因此只能靠读码
/// 判断——正是用户会在真机上第一眼看到差异的地方。
///
/// 【照片口径】帧里出现的「菜品照片」是**合成色块 PNG**（16×16 双色斜带，
/// 见 [_dishStandInPngBase64]），**不是伪造的菜品照片**：它只用来验证「有照片时
/// 缩略图/封面真的渲染出来」这条接线与版式。没有照片的菜品一律保持无照片
/// （序号圆 / 渐变占位），与 docs/21 §2.5 的既有口径一致。
///
/// 与其它捕获件同口径：`LF_ROUND7_CAPTURE_DIR` 指向工作区 tmp 时才落盘，
/// 未设置时**仍跑完并断言**——所以它同时是这张页的接线回归面（缺 Key、
/// 出现价格字样、照片槽不渲染都会让这里变红）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 9, 13, 12);

  late AppDatabase database;
  late CanteenRepository canteenRepository;
  late FoodRepository foodRepository;
  late MealRepository mealRepository;
  late DishLibraryRepository dishLibraryRepository;
  late AddDishToMeal addDishToMeal;
  late Directory photoDir;
  late String venueId;
  late String windowId;
  late String analyzedDishId;
  late String photoPath;
  late String unanalyzedDishId;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await seedFoodFixture(database);
    const ids = UuidV7Generator();
    final clock = FixedAppClock(now);
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
    dishLibraryRepository = DishLibraryRepository(
      database: database,
      idGenerator: ids,
      clock: clock,
    );
    canteenRepository = CanteenRepository(
      database: database,
      idGenerator: ids,
      clock: clock,
    );
    addDishToMeal = AddDishToMeal(mealRepository: mealRepository, clock: clock);

    photoDir = Directory.systemTemp.createTempSync('localfit-canteen-frame-');
    addTearDown(() {
      try {
        photoDir.deleteSync(recursive: true);
      } on FileSystemException {
        // Windows 上 `Image.file` 可能仍持有句柄；临时目录留给系统清理。
      }
    });
    final photo = File('${photoDir.path}${Platform.pathSeparator}d.jpg')
      ..writeAsBytesSync(base64Decode(_dishStandInPngBase64));
    photoPath = photo.path;

    venueId = await canteenRepository.createVenue(
      name: '东区食堂',
      campusName: '示范大学',
    );
    windowId = await canteenRepository.createWindow(
      venueId: venueId,
      name: '一楼快餐',
      openTime: '08:00',
      closeTime: '13:30',
    );
    // ① 已分析 + 有照片 + 有档口：帧里同时看到证据角标、kcal、缩略图。
    analyzedDishId = await canteenRepository.createDish(
      windowId: windowId,
      name: '番茄牛腩饭',
      stationName: '川湘窗口',
      imagePath: photo.path,
    );
    await canteenRepository.recordNutrition(
      dishId: analyzedDishId,
      kcalPer100g: 210,
      proteinPer100g: 12,
      carbsPer100g: 18,
      fatPer100g: 8,
      grade: 'B',
      confidence: 0.7,
      sourceText: '档口标牌',
    );
    // ② 未分析 + 无照片：行头是序号圆，徽标是「未分析营养」（反面也在帧里）。
    unanalyzedDishId = await canteenRepository.createDish(
      windowId: windowId,
      name: '清炒时蔬',
    );
  });

  tearDown(() async {
    await database.close();
  });

  Widget app({Key? key}) => LocalFitApp(
    key: key,
    initialLocation: AppRoutes.nutrition,
    foodRepository: foodRepository,
    mealRepository: mealRepository,
    dishLibraryRepository: dishLibraryRepository,
    canteenRepository: canteenRepository,
    addDishToMeal: addDishToMeal,
    // 注入取图 ⇒ 菜品表单渲染照片字段（N5 的「没有价格字段」对照面）。
    pickDishImage: (fromCamera) async => null,
    now: now,
  );

  /// 与 `round7_menu_capture_test.dart` 同口径的有界推进：菜单页的骨架屏动画
  /// 会让 `pumpAndSettle` 永不返回。
  Future<void> settleBounded(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(seconds: 2));
  }

  /// 走真实动线进食堂目录：饮食 tab → 菜单 → 页尾「管理食堂目录」。
  Future<void> openDirectory(WidgetTester tester) async {
    await tester.tap(find.text('菜单').first);
    await settleBounded(tester);
    await tester.tap(find.byKey(const Key('cta-manage-canteen')));
    await settleBounded(tester);
  }

  /// 帧保真：`Image.file` 的解码是异步的，widget 测试里不推进**真实**事件
  /// 循环就永远停在「还没画」——帧里是一块空白（本用例第一版拍到了空白，
  /// 而「Key 在场」的判据看不出来）。照仓内既有 `drainIo` 口径：交替
  /// `runAsync(delay)` 与 `pump`，让解码回调落地后再重建。
  ///
  /// （不用 `precacheImage`：它在 widget 测试里 await 不到首帧，会挂住
  /// 整个用例——本用例第一版就是这么超时的。）
  Future<void> warmDishPhoto(WidgetTester tester) async {
    for (var round = 0; round < 20; round++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(photoPath, isNotEmpty);
  }

  /// 「图真的画出来了」：`Image` 解码完成才会在体内建 `RawImage`；走
  /// errorBuilder（文件缺失/解码失败）或还没解码都没有它。
  void expectPhotoPainted(String keyName) {
    expect(
      find.descendant(
        of: find.byKey(Key(keyName)),
        matching: find.byType(RawImage),
      ),
      findsOneWidget,
      reason: '$keyName：只挂了 Image 没真画出像素（未解码或走了 errorBuilder）',
    );
  }

  void configureView(WidgetTester tester, double width, double height) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, height);
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
    tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
  }

  testWidgets('食堂目录整页矩阵：未请求态（N7 手动按钮）+ 已分析/未分析行 + 无价格', (tester) async {
    await tester.runAsync(loadRound7Fonts);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    for (final (dark, width, scale) in const [
      (false, 360.0, 1.0),
      (true, 360.0, 1.0),
      (false, 320.0, 2.0),
      (false, 430.0, 1.5),
      (true, 320.0, 2.0),
    ]) {
      configureView(tester, width, 2600 * scale);
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      tester.platformDispatcher.platformBrightnessTestValue = dark
          ? Brightness.dark
          : Brightness.light;

      await tester.pumpWidget(
        RepaintBoundary(
          key: round7Boundary,
          child: app(key: UniqueKey()),
        ),
      );
      await tester.pumpAndSettle();
      await openDirectory(tester);

      final label =
          'canteen ${dark ? 'dark' : 'light'} ${width.toInt()}x$scale';
      // 帧必须是食堂目录页，且四个新面都在：
      // N7 = 未请求态说明 + 手动按钮；N3 = 目录统计里的「已分析」+ 行内证据角标；
      // N4 的照片槽在下一张帧里（请求后）；N5 = 全页没有价格字样。
      // 2026-10-22：食堂目录的「今日推荐」两件退场（推荐只在菜单页）。
      for (final key in const [
        Key('canteen-venue-stats'),
        Key('canteen-stat-windows'),
        Key('canteen-stat-dishes'),
        Key('canteen-stat-analyzed'),
      ]) {
        expect(find.byKey(key), findsOneWidget, reason: '$label 缺 $key');
      }
      expect(
        find.byKey(Key('canteen-window-$windowId')),
        findsOneWidget,
        reason: '$label 缺窗口卡',
      );
      expect(
        find.byKey(Key('canteen-dish-$analyzedDishId')),
        findsOneWidget,
        reason: '$label 缺已分析菜品行',
      );
      expect(
        find.byKey(Key('canteen-dish-grade-$analyzedDishId')),
        findsOneWidget,
        reason: '$label：已分析菜品要有证据角标（N3）',
      );
      expect(
        find.byKey(Key('canteen-dish-photo-thumb-$analyzedDishId')),
        findsOneWidget,
        reason: '$label：有照片的菜品行要渲染缩略图',
      );
      expect(
        find.byKey(Key('canteen-dish-station-$analyzedDishId')),
        findsOneWidget,
        reason: '$label 缺档口副行',
      );
      expect(
        find.byKey(Key('canteen-dish-unanalyzed-$unanalyzedDishId')),
        findsOneWidget,
        reason: '$label：未分析菜品要有「未分析营养」徽标',
      );
      expect(
        find.byKey(Key('canteen-dish-index-$unanalyzedDishId')),
        findsOneWidget,
        reason: '$label：无照片的菜品行行头是序号圆',
      );
      // N5：价格从所有地方删掉——这一页连「元」都不该出现。
      expect(
        find.textContaining('元'),
        findsNothing,
        reason: '$label：食堂目录里仍有价格字样',
      );
      expect(tester.takeException(), isNull, reason: label);

      await warmDishPhoto(tester);
      expectPhotoPainted('canteen-dish-photo-thumb-$analyzedDishId');

      await captureRound7(
        tester,
        'canteen-idle-${dark ? 'dark' : 'light'}-${width.toInt()}-$scale',
      );
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('食堂目录不再有今日推荐（2026-10-22）；目录统计与菜品行仍在', (tester) async {
    await tester.runAsync(loadRound7Fonts);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);

    configureView(tester, 360, 2600);
    await tester.pumpWidget(
      RepaintBoundary(
        key: round7Boundary,
        child: app(key: UniqueKey()),
      ),
    );
    await tester.pumpAndSettle();
    await openDirectory(tester);

    // 用户：「食堂目录里的今日推荐删掉，这个界面就记录食堂菜品」。
    for (final key in const [
      Key('recommended-menu-idle'),
      Key('cta-request-recommendation'),
      Key('recommended-menu-card'),
    ]) {
      expect(find.byKey(key), findsNothing, reason: '食堂目录不该再有 $key');
    }
    expect(find.text('今日推荐'), findsNothing);
    // 目录本身照常：统计 + 窗口卡 + 菜品行。
    expect(find.byKey(const Key('canteen-venue-stats')), findsOneWidget);
    expect(find.byKey(Key('canteen-window-$windowId')), findsOneWidget);
    expect(find.textContaining('元'), findsNothing, reason: '不显示价格');
    expect(tester.takeException(), isNull);
    // drift 的订阅计时器要在卸页面之后跑掉，否则报 pending timer。
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
  testWidgets('添加菜品弹层：只有名称（价格字段已退役）', (tester) async {
    await tester.runAsync(loadRound7Fonts);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    configureView(tester, 360.0, 1200);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;

    await tester.pumpWidget(
      RepaintBoundary(
        key: round7Boundary,
        child: app(key: UniqueKey()),
      ),
    );
    await tester.pumpAndSettle();
    await openDirectory(tester);
    await tester.tap(find.byKey(Key('canteen-add-dish-$windowId')));
    await settleBounded(tester);

    // N5 的正面判据：表单里没有价格字段，只有名称（+ 照片 + 档口）。
    expect(
      find.byKey(const Key('canteen-dish-name')),
      findsOneWidget,
      reason: '菜品表单缺名称字段',
    );
    expect(
      find.byKey(const Key('canteen-dish-price')),
      findsNothing,
      reason: '菜品表单不该再有价格字段（已随 S8-b 退役）',
    );
    expect(
      find.byKey(const Key('canteen-dish-photo-empty')),
      findsOneWidget,
      reason: '注入取图后表单应渲染照片字段（对照价格字段的缺席）',
    );
    expect(find.textContaining('元'), findsNothing, reason: '表单出现价格字样');
    expect(tester.takeException(), isNull);

    await captureRound7(tester, 'canteen-dish-form-light-360-1.0');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}

/// 合成占位图（16×16，双色斜带）。**不是菜品照片**：只用来让「照片槽真的画了
/// 一张图」在帧里可见（`Image.file` 需要能解码的真实文件）。色块刻意不像任何
/// 食物，避免被误读成伪造的菜品照片。
const _dishStandInPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAIAAACQkWg2AAAAUklEQVR42pXLyw0AIAgEUer06t0K'
    'rMRO7E4TjR9EWJI5vqFasity6RQDubRjGBodloaGU9sD08bwam0Q9Xf4aXlQtDDomg+mvgZE'
    '7wHUc8B1rwHRTYIw9No6pQAAAABJRU5ErkJggg==';
