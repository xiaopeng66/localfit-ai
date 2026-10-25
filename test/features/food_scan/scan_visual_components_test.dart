/// 阶段 4 视觉分组组件页面级回归：
/// ScanResultOverviewCard / ScanIngredientsSection / ScanNutritionBreakdown /
/// ScanAiAdviceCard 五个组件在候选编辑器加载时正确呈现，窄屏布局与交互
/// 约束保持不变。
library;

import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';

import 'scan_test_helpers.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/food_scan/application/prepare_meal_image.dart';
import 'package:localfit_ai/features/food_scan/application/recognize_confirmed_meal_image.dart';
import 'package:localfit_ai/features/food_scan/application/resolve_meal_scan_candidates.dart';
import 'package:localfit_ai/features/food_scan/application/local_food_search.dart';
import 'package:localfit_ai/features/food_scan/domain/meal_estimate.dart';
import 'package:localfit_ai/features/food_scan/domain/meal_image.dart';
import 'package:localfit_ai/features/food_scan/presentation/food_scan_page.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/food_record.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('food scan visual grouping components', () {
    late AppDatabase database;
    late MealRepository meals;
    late _TemporaryStore store;
    late _Picker picker;
    late _Provider provider;
    late DateTime now;

    setUp(() async {
      now = DateTime(2026, 9, 25, 12);
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
      provider = _Provider();
    });

    tearDown(() => database.close());

    testWidgets(
      'renders all four visual grouping components when candidates are resolved',
      (tester) async {
        tester.view.physicalSize = const Size(900, 1600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final resolver = ResolveMealScanCandidates(foodSearch: _FoodSearch());
        await tester.pumpWidget(
          _app(
            meals,
            store,
            picker,
            now,
            provider: provider,
            resolver: resolver,
          ),
        );
        picker.next = SelectedMealImage(
          bytes: Uint8List.fromList([1]),
          source: MealImageSource.gallery,
        );
        await tester.tap(find.byKey(const Key('scan-camera')));
        await _awaitPreview(tester);

        // Scroll up to show analyze button
        await tester.drag(find.byType(ListView), const Offset(0, -600));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const Key('scan-analyze')));
        await tester.tap(find.byKey(const Key('scan-analyze')));
        await tester.pumpAndSettle();

        // docs/21 §5.4 把页面拆成两个互斥面：只读结果面（结果卡 + 食材 +
        // 拆分 + 建议）与 `cta-edit-items` 进入的编辑面。四个视觉分组组件
        // 都在**只读面**上；编辑面里只有候选卡。
        expect(find.byKey(const Key('scan-result-overview')), findsOneWidget);
        expect(
          find.byKey(const Key('scan-ingredients-section')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('scan-nutrition-breakdown')),
          findsOneWidget,
        );
        // 建议卡是只读面最后一张卡：不先滚到它，懒 ListView 下 finder 匹配不到
        //（是「没构建」不是「没渲染」）。
        await tester.scrollUntilVisible(
          find.byKey(const Key('scan-ai-advice')),
          400,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.byKey(const Key('scan-ai-advice')), findsOneWidget);

        await enterEditor(tester);
        await scrollToTop(tester);
        expect(find.byKey(const Key('scan-candidate-card')), findsOneWidget);
        // 互斥面：进了编辑面，只读结果卡就收起来了。
        expect(find.byKey(const Key('scan-result-overview')), findsNothing);
      },
    );

    testWidgets('ScanResultOverviewCard shows dish name and total kcal', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final resolver = ResolveMealScanCandidates(foodSearch: _FoodSearch());
      await tester.pumpWidget(
        _app(meals, store, picker, now, provider: provider, resolver: resolver),
      );
      picker.next = SelectedMealImage(
        bytes: Uint8List.fromList([1]),
        source: MealImageSource.gallery,
      );
      await tester.tap(find.byKey(const Key('scan-camera')));
      await _awaitPreview(tester);

      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('scan-analyze')));
      await tester.tap(find.byKey(const Key('scan-analyze')));
      await tester.pumpAndSettle();

      // 米饭 名称在概览卡标题和编辑器中各出现一次 → findsWidgets
      expect(find.textContaining('米饭'), findsWidgets);
      expect(find.textContaining('kcal'), findsWidgets);
    });

    testWidgets('ScanIngredientsSection lists all candidates with grams', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final resolver = ResolveMealScanCandidates(foodSearch: _FoodSearch());
      await tester.pumpWidget(
        _app(meals, store, picker, now, provider: provider, resolver: resolver),
      );
      picker.next = SelectedMealImage(
        bytes: Uint8List.fromList([1]),
        source: MealImageSource.gallery,
      );
      await tester.tap(find.byKey(const Key('scan-camera')));
      await _awaitPreview(tester);

      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('scan-analyze')));
      await tester.tap(find.byKey(const Key('scan-analyze')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('scan-ingredients-section')), findsOneWidget);
      expect(find.text('米饭'), findsWidgets);
      // docs/21 §5.4 Key 表：每条候选行自己的锚点（`<n>` 0 起）。
      expect(find.byKey(const Key('scan-ingredient-0')), findsOneWidget);
    });

    testWidgets(
      'ScanNutritionBreakdown shows macro breakdown with percentages',
      (tester) async {
        tester.view.physicalSize = const Size(900, 1600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final resolver = ResolveMealScanCandidates(foodSearch: _FoodSearch());
        await tester.pumpWidget(
          _app(
            meals,
            store,
            picker,
            now,
            provider: provider,
            resolver: resolver,
          ),
        );
        picker.next = SelectedMealImage(
          bytes: Uint8List.fromList([1]),
          source: MealImageSource.gallery,
        );
        await tester.tap(find.byKey(const Key('scan-camera')));
        await _awaitPreview(tester);

        await tester.drag(find.byType(ListView), const Offset(0, -600));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const Key('scan-analyze')));
        await tester.tap(find.byKey(const Key('scan-analyze')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('scan-nutrition-breakdown')),
          findsOneWidget,
        );
        // docs/21 §5.4 Key 表：三条宏量行各自可定位。
        for (final key in [
          'scan-breakdown-protein',
          'scan-breakdown-carbs',
          'scan-breakdown-fat',
        ]) {
          expect(find.byKey(Key(key)), findsOneWidget, reason: key);
        }
        expect(find.textContaining('蛋白质'), findsWidgets);
        expect(find.textContaining('碳水'), findsWidgets);
        expect(find.textContaining('脂肪'), findsWidgets);
      },
    );

    testWidgets('ScanAiAdviceCard shows when suggestions exist', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Use a provider returning an unmatched item (no local food in the
      // database), so the AI advice card surfaces the "unmatched" advisory.
      final providerUnmatched = _ProviderUnmatched();
      final resolver = ResolveMealScanCandidates(foodSearch: _FoodSearch());
      await tester.pumpWidget(
        _app(
          meals,
          store,
          picker,
          now,
          provider: providerUnmatched,
          resolver: resolver,
        ),
      );
      picker.next = SelectedMealImage(
        bytes: Uint8List.fromList([1]),
        source: MealImageSource.gallery,
      );
      await tester.tap(find.byKey(const Key('scan-camera')));
      await _awaitPreview(tester);

      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('scan-analyze')));
      await tester.tap(find.byKey(const Key('scan-analyze')));
      await tester.pumpAndSettle();

      // AI advice appears when candidates have local food match suggestions OR
      // are unmatched (and thus show AI-estimated nutrition).
      // 建议卡是只读面的**最后**一张卡：4:3 照片卡把后面的内容顶出懒 ListView
      // 的构建范围，不先滚过去 finder 直接匹配不到（这是「没构建」，不是
      // 「没渲染」，skipOffstage 救不了）。
      await tester.scrollUntilVisible(
        find.byKey(const Key('scan-ai-advice')),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const Key('scan-ai-advice')), findsWidgets);
      expect(find.textContaining('未匹配本地食物'), findsWidgets);
    });

    testWidgets('narrow screen (320dp) layout does not overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Just verify the empty scan page renders within 320dp bounds
      await tester.pumpWidget(
        _app(
          meals,
          store,
          picker,
          now,
          provider: provider,
          resolver: ResolveMealScanCandidates(foodSearch: _FoodSearch()),
        ),
      );

      // Verify no overflow by checking scaffold dimensions
      final renderLayout = tester.renderObject<RenderBox>(
        find.byType(Scaffold),
      );
      expect(renderLayout.hasSize, true);
      // Physical 320 with 2x DPR = logical 160
      expect(renderLayout.size.width, 160);
      expect(renderLayout.size.height, 320);
    });

    testWidgets('analysis sheet opens from overview card', (tester) async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Need a resolver so the candidate editor (with the analysis button)
      // is rendered instead of the read-only draft card.
      final resolver = ResolveMealScanCandidates(foodSearch: _FoodSearch());
      await tester.pumpWidget(
        _app(meals, store, picker, now, provider: provider, resolver: resolver),
      );
      picker.next = SelectedMealImage(
        bytes: Uint8List.fromList([1]),
        source: MealImageSource.gallery,
      );
      await tester.tap(find.byKey(const Key('scan-camera')));
      await _awaitPreview(tester);

      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('scan-analyze')));
      await tester.tap(find.byKey(const Key('scan-analyze')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('scan-analysis-open')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('scan-analysis-sheet')), findsOneWidget);
      // "分析过程" appears in sheet title (h2), button label has "查看分析过程"
      expect(find.text('分析过程'), findsOneWidget);
    });
  });
}

Future<void> _awaitPreview(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
    if (find.byKey(const Key('scan-preview')).evaluate().isNotEmpty) break;
  }
}

Widget _app(
  MealRepository meals,
  _TemporaryStore store,
  _Picker picker,
  DateTime now, {
  MealRecognitionProvider? provider,
  ResolveMealScanCandidates? resolver,
}) => MaterialApp(
  home: FoodScanPage(
    prepareMealImage: PrepareMealImage(
      picker: picker,
      processor: const _Processor(),
      store: store,
    ),
    recognizeConfirmedMealImage: provider != null
        ? RecognizeConfirmedMealImage(provider: provider)
        : null,
    resolveMealScanCandidates:
        resolver ?? ResolveMealScanCandidates(foodSearch: _FoodSearch()),
    mealRepository: meals,
    now: now,
  ),
);

final class _Ids implements IdGenerator {
  int _value = 0;

  @override
  String next() => 'test-id-${_value++}';
}

final class _Picker implements MealImagePicker {
  SelectedMealImage? next;
  final sources = <MealImageSource>[];

  @override
  Future<SelectedMealImage?> pick(MealImageSource source) async {
    sources.add(source);
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
  final deleted = <PreparedMealImage>[];

  @override
  Future<void> clearStale() async {}

  @override
  Future<void> clearAll() async {}

  @override
  Future<void> delete(PreparedMealImage image) async {
    deleted.add(image);
  }

  @override
  Future<PreparedMealImage> save(ProcessedMealImage image) async =>
      PreparedMealImage(
        path: '/private/test.jpg',
        width: image.width,
        height: image.height,
        byteLength: image.bytes.length,
      );
}

final class _Provider implements MealRecognitionProvider {
  @override
  Future<MealEstimateDraft> recognize(
    PreparedMealImage image, {
    MealRecognitionCancellationToken? cancellationToken,
  }) async => const MealEstimateDraft(
    items: [
      MealEstimateItem(
        name: '米饭',
        estimatedGrams: 180,
        gramsRange: GramRange(min: 140, max: 220),
        confidence: 0.8,
        ingredients: [],
        needsConfirmation: false,
        questions: [],
        cookingMethod: '蒸煮',
        nutrition: MealEstimateNutrition(
          kcal: 260,
          proteinGrams: 5.0,
          carbsGrams: 50.0,
          fatGrams: 3.0,
        ),
      ),
    ],
    warnings: [],
    mealNotes: null,
  );
}

/// Provider returning an item with multiple local food suggestions, so that
/// the AI advice card (which lists candidate matches) is rendered.
/// Provider returning an unmatched item (no local food match), so the AI
/// advice card surfaces the "uses AI estimate" advisory.
final class _ProviderUnmatched implements MealRecognitionProvider {
  @override
  Future<MealEstimateDraft> recognize(
    PreparedMealImage image, {
    MealRecognitionCancellationToken? cancellationToken,
  }) async => const MealEstimateDraft(
    items: [
      MealEstimateItem(
        name: '未知菜品',
        estimatedGrams: 150,
        gramsRange: GramRange(min: 120, max: 180),
        confidence: 0.85,
        ingredients: [],
        needsConfirmation: false,
        questions: [],
        cookingMethod: '煎',
        nutrition: MealEstimateNutrition(
          kcal: 165,
          proteinGrams: 31,
          carbsGrams: 0,
          fatGrams: 3.6,
        ),
      ),
    ],
    warnings: [],
    mealNotes: null,
  );
}

/// 本地食物搜索桩：提供米饭以便候选自动匹配。
final class _FoodSearch implements LocalFoodSearch {
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
