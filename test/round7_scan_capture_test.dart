import 'dart:async';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/food_scan/application/local_food_search.dart';
import 'package:localfit_ai/features/food_scan/application/prepare_meal_image.dart';
import 'package:localfit_ai/features/food_scan/application/recognize_confirmed_meal_image.dart';
import 'package:localfit_ai/features/food_scan/application/resolve_meal_scan_candidates.dart';
import 'package:localfit_ai/features/food_scan/domain/meal_estimate.dart';
import 'package:localfit_ai/features/food_scan/domain/meal_image.dart';
import 'package:localfit_ai/features/food_scan/presentation/food_scan_page.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/food_record.dart';

import 'features/food_scan/scan_test_helpers.dart';
import 'support/round7_render.dart';

/// Round7 阶段 3 · 3-3 的渲染矩阵（拍照识餐页的两级整页与各状态面）。
///
/// 12 帧：空态 2（浅/深 360-1.0）、识别中 1（浅，pending provider）、结果面 3
/// （浅/深 360-1.0、浅 320-2.0）、编辑面 2（浅/深 360-1.0）、修正弹层 1（深）、
/// 本地匹配弹层 1（浅）、剩餐净摄入 1（浅）、结果面深 430-1.5 1。
///
/// A 未画拍照识餐（docs/33 §3.2 按同主题补齐），帧用于**审看现有实现与 A
/// 语言（卡片/段头/静音注/行动行）是否一致**，以及全状态是否可审看。
void main() {
  late AppDatabase database;
  late MealRepository meals;
  late _TemporaryStore store;
  late _Picker picker;
  final now = DateTime(2026, 9, 9, 12);

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

  Future<void> pumpPage(
    WidgetTester tester, {
    required bool dark,
    required double width,
    required double height,
    required double scale,
    MealRecognitionProvider? provider,
  }) async {
    // 每帧一个**全新 State**：同型无 key 的 `FoodScanPage` 会被 Flutter 复用
    // State（上一面的 `_image` / `_recognizing` 会带过来——挂着的识别中态还会
    // 让 `pumpAndSettle` 超时）。
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, height);
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
    tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
    await tester.pumpWidget(
      RepaintBoundary(
        key: round7Boundary,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: round7CaptureTheme(dark ? AppTheme.dark() : AppTheme.light()),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              disableAnimations: true,
            ),
            child: child!,
          ),
          home: FoodScanPage(
            prepareMealImage: PrepareMealImage(
              picker: picker,
              processor: const _Processor(),
              store: store,
            ),
            recognizeConfirmedMealImage: RecognizeConfirmedMealImage(
              provider: provider ?? _Provider(),
            ),
            resolveMealScanCandidates: ResolveMealScanCandidates(
              foodSearch: const _FoodSearch(),
            ),
            mealRepository: meals,
            now: now,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> takePhoto(WidgetTester tester) async {
    picker.next = SelectedMealImage(
      bytes: Uint8List.fromList([1]),
      source: MealImageSource.camera,
    );
    await tester.tap(find.byKey(const Key('scan-camera')));
    await tester.pumpAndSettle();
  }

  /// 长页里的控件要先滚进构建范围再点（`ListView` 的懒挂载：视口外的子件
  /// 根本不在 element 树里，`ensureVisible` 会报 `Bad state: No element`）。
  Future<void> tapAfterScroll(WidgetTester tester, Key key) async {
    final finder = find.byKey(key);
    await tester.scrollUntilVisible(
      finder,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await revealFully(tester, finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  /// 直接触发按钮回调（`scan_test_helpers` 之外的第三条路）：剩餐预览卡是
  /// 4:3（≈651dp 高），分析键可能恰好落在固定底栏之下，`tap` 会打空；
  /// `food_scan_save_flow_test` 的既有做法就是取 `ButtonStyleButton.onPressed`
  /// 直接调（断言仍是「这个键可点」）。
  Future<void> pressByWidget(WidgetTester tester, Key key) async {
    await tester.scrollUntilVisible(
      find.byKey(key, skipOffstage: false),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    final button = tester.widget<ButtonStyleButton>(
      find.byKey(key, skipOffstage: false),
    );
    button.onPressed!();
    await tester.pumpAndSettle();
  }

  Future<void> shot(WidgetTester tester, String name, Key sentinel) async {
    expect(tester.takeException(), isNull, reason: '$name：布局溢出');
    expect(find.byKey(sentinel), findsOneWidget, reason: '$name：关键件不在帧内');
    await captureRound7(tester, name);
  }

  testWidgets('拍照识餐：空态 / 结果面 / 编辑面 / 修正与匹配弹层（9 帧）', (tester) async {
    await tester.runAsync(loadRound7Fonts);

    // 空态（深链兜底：拍摄照片主钮 + 对话指令栏 + 禁用的固定 CTA）
    await pumpPage(tester, dark: false, width: 360, height: 800, scale: 1);
    await shot(tester, 'scan-empty-light-360-1.0', const Key('scan-camera'));

    await pumpPage(tester, dark: true, width: 360, height: 800, scale: 1);
    await shot(tester, 'scan-empty-dark-360-1.0', const Key('scan-camera'));

    // 结果面（浅/深 360-1.0）
    await pumpPage(tester, dark: false, width: 360, height: 900, scale: 1);
    await takePhoto(tester);
    await shot(
      tester,
      'scan-result-light-360-1.0',
      const Key('cta-confirm-scan'),
    );

    await pumpPage(tester, dark: true, width: 360, height: 900, scale: 1);
    await takePhoto(tester);
    await shot(
      tester,
      'scan-result-dark-360-1.0',
      const Key('cta-confirm-scan'),
    );

    // 结果面（320 + 2.0× 大字）
    await pumpPage(tester, dark: false, width: 320, height: 900, scale: 2);
    await takePhoto(tester);
    await shot(
      tester,
      'scan-result-light-320-2.0',
      const Key('cta-confirm-scan'),
    );

    // 结果面（430 + 1.5× 深色）
    await pumpPage(tester, dark: true, width: 430, height: 1000, scale: 1.5);
    await takePhoto(tester);
    await shot(
      tester,
      'scan-result-dark-430-1.5',
      const Key('cta-confirm-scan'),
    );

    // 编辑面（浅/深 360-1.0）
    await pumpPage(tester, dark: false, width: 360, height: 1000, scale: 1);
    await takePhoto(tester);
    await tapAfterScroll(tester, const Key('cta-edit-items'));
    await shot(
      tester,
      'scan-editor-light-360-1.0',
      const Key('scan-candidate-slot'),
    );

    await pumpPage(tester, dark: true, width: 360, height: 1000, scale: 1);
    await takePhoto(tester);
    await tapAfterScroll(tester, const Key('cta-edit-items'));
    await shot(
      tester,
      'scan-editor-dark-360-1.0',
      const Key('scan-candidate-slot'),
    );

    // 修正弹层（深色）：编辑面 → 第 0 项的「修正」（先滚进视口再点）
    await tapAfterScroll(tester, const Key('scan-candidate-correct-0'));
    await shot(
      tester,
      'scan-correction-dark-360-1.0',
      const Key('scan-correction-sheet'),
    );
    await tester.tap(find.byKey(const Key('scan-correction-cancel')));
    await tester.pumpAndSettle();

    // 本地匹配弹层（浅色）：重挂一次以拿浅色主题
    await pumpPage(tester, dark: false, width: 360, height: 1000, scale: 1);
    await takePhoto(tester);
    await tapAfterScroll(tester, const Key('cta-edit-items'));
    await tapAfterScroll(tester, const Key('scan-candidate-search-0'));
    await shot(
      tester,
      'scan-food-search-light-360-1.0',
      const Key('scan-food-search'),
    );

    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.view.resetPadding();
    tester.view.resetViewPadding();
  });

  testWidgets('拍照识餐：识别中（pending provider）与剩餐净摄入（3 帧）', (tester) async {
    await tester.runAsync(loadRound7Fonts);

    // 识别中：provider 永不返回 ⇒ 进度卡（呼吸被 disableAnimations 停住；
    // 内部 CircularProgressIndicator 仍在动，故只 pump 不 settle）
    await pumpPage(
      tester,
      dark: false,
      width: 360,
      height: 900,
      scale: 1,
      provider: _PendingProvider(),
    );
    picker.next = SelectedMealImage(
      bytes: Uint8List.fromList([1]),
      source: MealImageSource.camera,
    );
    await tester.tap(find.byKey(const Key('scan-camera')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await shot(
      tester,
      'scan-recognizing-light-360-1.0',
      const Key('scan-recognizing'),
    );

    // 剩餐净摄入：第二次识别返回 60g（净摄入 = 180 − 60 = 120g）
    await pumpPage(tester, dark: false, width: 360, height: 1000, scale: 1);
    await takePhoto(tester);
    picker.next = SelectedMealImage(
      bytes: Uint8List.fromList([2]),
      source: MealImageSource.gallery,
    );
    await tapAfterScroll(tester, const Key('scan-leftover-gallery'));
    await shot(
      tester,
      'scan-leftover-light-360-1.0',
      const Key('scan-leftover-preview'),
    );
    await pressByWidget(tester, const Key('scan-leftover-analyze'));
    await tester.scrollUntilVisible(
      find.byKey(const Key('scan-leftover-candidate-slot')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await shot(
      tester,
      'scan-leftover-editor-light-360-1.0',
      const Key('scan-leftover-candidate-slot'),
    );

    // 剩餐面的深色（同一路径再走一遍，用深色宿主）
    await pumpPage(tester, dark: true, width: 360, height: 1000, scale: 1);
    await takePhoto(tester);
    picker.next = SelectedMealImage(
      bytes: Uint8List.fromList([2]),
      source: MealImageSource.gallery,
    );
    await tapAfterScroll(tester, const Key('scan-leftover-gallery'));
    await pressByWidget(tester, const Key('scan-leftover-analyze'));
    await tester.scrollUntilVisible(
      find.byKey(const Key('scan-leftover-candidate-slot')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await shot(
      tester,
      'scan-leftover-editor-dark-360-1.0',
      const Key('scan-leftover-candidate-slot'),
    );

    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.view.resetPadding();
    tester.view.resetViewPadding();
  });
}

// ── 夹具（与 `scan_design_spec_test.dart` 同构；识别按调用次序返回两份）──

final class _Ids implements IdGenerator {
  int _value = 0;

  @override
  String next() => 'cap-${_value++}';
}

final class _Picker implements MealImagePicker {
  SelectedMealImage? next;

  @override
  Future<SelectedMealImage?> pick(MealImageSource source) async => next;

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
  @override
  Future<void> clearStale() async {}

  @override
  Future<void> clearAll() async {}

  @override
  Future<void> delete(PreparedMealImage image) async {}

  @override
  Future<PreparedMealImage> save(ProcessedMealImage image) async =>
      PreparedMealImage(
        path: '/private/cap.jpg',
        width: image.width,
        height: image.height,
        byteLength: image.bytes.length,
      );
}

/// 第一次识别给 180g（餐前），第二次给 60g（剩餐）——净摄入面因此有真数。
final class _Provider implements MealRecognitionProvider {
  int _calls = 0;

  @override
  Future<MealEstimateDraft> recognize(
    PreparedMealImage image, {
    MealRecognitionCancellationToken? cancellationToken,
  }) async {
    final grams = _calls++ == 0 ? 180.0 : 60.0;
    return MealEstimateDraft(
      items: [
        MealEstimateItem(
          name: '米饭',
          estimatedGrams: grams,
          gramsRange: GramRange(min: grams * 0.7, max: grams * 1.3),
          confidence: 0.8,
          ingredients: const [],
          needsConfirmation: false,
          questions: const [],
          cookingMethod: '蒸煮',
          nutrition: MealEstimateNutrition(
            kcal: grams * 1.16,
            proteinGrams: grams * 0.026,
            carbsGrams: grams * 0.259,
            fatGrams: grams * 0.003,
          ),
        ),
      ],
      warnings: const [],
      mealNotes: null,
    );
  }
}

final class _PendingProvider implements MealRecognitionProvider {
  final _never = Completer<MealEstimateDraft>();

  @override
  Future<MealEstimateDraft> recognize(
    PreparedMealImage image, {
    MealRecognitionCancellationToken? cancellationToken,
  }) => _never.future;
}

final class _FoodSearch implements LocalFoodSearch {
  const _FoodSearch();

  @override
  Future<List<FoodRecord>> search(String query, {int limit = 10}) async => [
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
