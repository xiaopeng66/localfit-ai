/// 扫描页状态机端到端回归：idle → selecting → recognizing →
/// needs-confirmation → editing → saving → success/cancelled/error。
library;

import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';

import 'scan_test_helpers.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/errors/app_failure.dart';
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

  group('food scan state machine', () {
    late AppDatabase database;
    late MealRepository meals;
    late _TemporaryStore store;
    late _Picker picker;
    late _Provider provider;
    late DateTime now;

    setUp(() async {
      now = DateTime(2026, 9, 25, 12);
      database = AppDatabase(NativeDatabase.memory());
      await _seedRice(database, now);
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

    // ── 状态 0 → 1：idle → selecting ────────────────────────────────
    testWidgets('idle selects image and shows preview', (tester) async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _app(meals, store, picker, now, recognition: provider),
      );
      expect(find.byKey(const Key('scan-camera')), findsOneWidget);
      expect(find.byKey(const Key('scan-preview')), findsNothing);

      picker.next = SelectedMealImage(
        bytes: Uint8List.fromList([1]),
        source: MealImageSource.camera,
      );
      await tester.tap(find.byKey(const Key('scan-camera')));
      // P10 拍照直通：选完图识别自动开始，预览短暂出现即被「识别中」
      // 卡替换；结束时预览回来。这里等整个识别收尾再断言。
      await _awaitRecognitionDone(tester);

      expect(find.byKey(const Key('scan-preview')), findsOneWidget);
      expect(picker.sources, [MealImageSource.camera]);
      expect(provider.calls, 1);
    });

    // ── 状态 1 → 2：selecting → recognizing ────────────────────────
    testWidgets('recognizing shows progress card with cancel button', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _app(meals, store, picker, now, recognition: provider),
      );
      picker.next = SelectedMealImage(
        bytes: Uint8List.fromList([1]),
        source: MealImageSource.camera,
      );
      await tester.tap(find.byKey(const Key('scan-camera')));
      // P10 拍照直通：识别自动开始。fake provider 延迟 100ms，识别中
      // 卡必然先于结果出现；一帧一帧等它上屏（识别完成后会被替换）。
      var sawRecognizing = false;
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
        if (find.byKey(const Key('scan-recognizing')).evaluate().isNotEmpty) {
          sawRecognizing = true;
          break;
        }
      }

      expect(sawRecognizing, isTrue);
      expect(find.byKey(const Key('scan-cancel-recognition')), findsOneWidget);
      expect(provider.calls, 1);

      await tester.pump(const Duration(milliseconds: 100));
      await _awaitRecognitionDone(tester);
    });

    // ── 状态 2 → 3：recognizing → draft card (无候选编辑器) ─────────
    testWidgets('recognition completes and shows draft card', (tester) async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _app(meals, store, picker, now, recognition: provider),
      );
      picker.next = SelectedMealImage(
        bytes: Uint8List.fromList([1]),
        source: MealImageSource.camera,
      );
      await tester.tap(find.byKey(const Key('scan-camera')));
      await _awaitRecognitionDone(tester);

      expect(find.byKey(const Key('scan-draft-card')), findsOneWidget);
      expect(provider.calls, 1);
    });

    // ── 状态 2 → 3：识别返回空结果 ───────────────────────────────────
    testWidgets('empty recognition shows error and returns to preview', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      provider.emptyResult = true;
      await tester.pumpWidget(
        _app(meals, store, picker, now, recognition: provider),
      );
      picker.next = SelectedMealImage(
        bytes: Uint8List.fromList([1]),
        source: MealImageSource.camera,
      );
      await tester.tap(find.byKey(const Key('scan-camera')));
      await _awaitRecognitionDone(tester);

      expect(find.byKey(const Key('scan-preview')), findsOneWidget);
      expect(find.byKey(const Key('scan-error')), findsOneWidget);
      expect(find.textContaining('未识别出可供确认的食物'), findsOneWidget);
    });

    // ── 识别失败：返回 error + 保留 preview ───────────────────────
    testWidgets('recognition failure keeps preview and shows error', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      provider.failure = const NetworkFailure(
        '网络连接不可用',
        kind: NetworkFailureKind.connection,
      );
      await tester.pumpWidget(
        _app(meals, store, picker, now, recognition: provider),
      );
      picker.next = SelectedMealImage(
        bytes: Uint8List.fromList([1]),
        source: MealImageSource.camera,
      );
      await tester.tap(find.byKey(const Key('scan-camera')));
      await _awaitRecognitionDone(tester);

      expect(find.byKey(const Key('scan-preview')), findsOneWidget);
      expect(find.byKey(const Key('scan-error')), findsOneWidget);
      expect(find.text('网络连接不可用，请检查网络后手动重试。'), findsOneWidget);
    });

    // ── 取消识别：状态回到 selecting ─────────────────────────────
    testWidgets('cancels recognition and returns to preview', (tester) async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _app(meals, store, picker, now, recognition: provider),
      );
      picker.next = SelectedMealImage(
        bytes: Uint8List.fromList([1]),
        source: MealImageSource.camera,
      );
      await tester.tap(find.byKey(const Key('scan-camera')));
      // P10 拍照直通：识别自动开始，fake provider 延迟 100ms——抢在它
      // 完成前抓到「识别中」窗口并取消。
      var caught = false;
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
        if (find.byKey(const Key('scan-recognizing')).evaluate().isNotEmpty) {
          caught = true;
          break;
        }
      }
      expect(caught, isTrue);

      await tester.tap(find.byKey(const Key('scan-cancel-recognition')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('scan-preview')), findsOneWidget);
      expect(find.byKey(const Key('scan-recognizing')), findsNothing);
      expect(find.byKey(const Key('scan-draft-card')), findsNothing);
    });

    // ── idle → idle：重新拍摄清空所有状态 ───────────────────────
    testWidgets('cta-rescan clears all state', (tester) async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _app(meals, store, picker, now, recognition: provider),
      );
      picker.next = SelectedMealImage(
        bytes: Uint8List.fromList([1]),
        source: MealImageSource.camera,
      );
      await tester.tap(find.byKey(const Key('scan-camera')));
      await _awaitRecognitionDone(tester);
      expect(find.byKey(const Key('scan-draft-card')), findsOneWidget);

      await tester.tap(find.byKey(const Key('cta-rescan')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('scan-preview')), findsNothing);
      expect(find.byKey(const Key('scan-draft-card')), findsNothing);
      expect(store.deleted, hasLength(1));
    });

    // ── 识别 + 解析器：显示 Candidate 编辑器 ───────────────────────
    testWidgets('with resolver shows candidate editor after recognition', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _app(
          meals,
          store,
          picker,
          now,
          recognition: provider,
          resolver: ResolveMealScanCandidates(foodSearch: _FoodSearch()),
        ),
      );
      picker.next = SelectedMealImage(
        bytes: Uint8List.fromList([1]),
        source: MealImageSource.camera,
      );
      await tester.tap(find.byKey(const Key('scan-camera')));
      await _awaitPreview(tester);

      await enterEditor(tester);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('scan-candidate-card')), findsOneWidget);
      expect(find.byKey(const Key('scan-candidate-grams-0')), findsOneWidget);
    });

    // ── 保存流：从候选编辑器确认 → 保存成功 ───────────────────────
    testWidgets('saves candidate and shows success', (tester) async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _app(
          meals,
          store,
          picker,
          now,
          recognition: provider,
          resolver: ResolveMealScanCandidates(foodSearch: _FoodSearch()),
        ),
      );
      picker.next = SelectedMealImage(
        bytes: Uint8List.fromList([1]),
        source: MealImageSource.camera,
      );
      await tester.tap(find.byKey(const Key('scan-camera')));
      await _awaitPreview(tester);

      await enterEditor(tester);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('scan-candidate-card')), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const Key('scan-candidate-confirm')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('scan-candidate-confirm')));
      await tester.pumpAndSettle();

      expect(find.text('确认入账？'), findsOneWidget);
      await tester.tap(find.byKey(const Key('scan-save-confirm')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('scan-success')), findsOneWidget);
      expect(store.deleted, hasLength(1));
      final records = await meals.listRecent();
      expect(records, hasLength(1));
      expect(records.single.source, 'ai_scan');
    });

    // ── 取消保存：退回候选编辑器 ─────────────────────────────────
    testWidgets('cancels saving and returns to editing state', (tester) async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _app(
          meals,
          store,
          picker,
          now,
          recognition: provider,
          resolver: ResolveMealScanCandidates(foodSearch: _FoodSearch()),
        ),
      );
      picker.next = SelectedMealImage(
        bytes: Uint8List.fromList([1]),
        source: MealImageSource.camera,
      );
      await tester.tap(find.byKey(const Key('scan-camera')));
      await _awaitPreview(tester);

      await enterEditor(tester);
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const Key('scan-candidate-confirm')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('scan-candidate-confirm')));
      await tester.pumpAndSettle();
      expect(find.text('确认入账？'), findsOneWidget);

      await tester.tap(find.byKey(const Key('scan-save-cancel')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('scan-candidate-card')), findsOneWidget);
      final records = await meals.listRecent();
      expect(records, isEmpty);
    });

    // ── 保存失败：保留候选，允许重试 ─────────────────────────────
    testWidgets('save failure retains candidate for retry', (tester) async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // 使用没有米饭记录的新数据库，使保存时找不到本地食物。
      final dbWithoutRice = AppDatabase(NativeDatabase.memory());
      final mealsNoRice = MealRepository(
        database: dbWithoutRice,
        idGenerator: _Ids(),
        clock: FixedAppClock(now),
      );

      await tester.pumpWidget(
        _app(
          mealsNoRice,
          store,
          picker,
          now,
          recognition: provider,
          resolver: ResolveMealScanCandidates(foodSearch: _FoodSearch()),
        ),
      );
      picker.next = SelectedMealImage(
        bytes: Uint8List.fromList([1]),
        source: MealImageSource.camera,
      );
      await tester.tap(find.byKey(const Key('scan-camera')));
      await _awaitPreview(tester);

      await enterEditor(tester);
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const Key('scan-candidate-confirm')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('scan-candidate-confirm')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('scan-save-confirm')));
      await tester.pumpAndSettle();

      expect(find.text('餐食未能保存到本机，请稍后重试。'), findsOneWidget);
      expect(find.byKey(const Key('scan-candidate-card')), findsOneWidget);
      final records = await mealsNoRice.listRecent();
      expect(records, isEmpty);

      dbWithoutRice.close();
    });
  });
}

// ── 辅助函数 ──────────────────────────────────────────────────────

Future<void> _seedRice(AppDatabase db, DateTime now) async {
  await db
      .into(db.foods)
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
}

Future<void> _awaitPreview(WidgetTester tester) async {
  // P10 拍照直通：预览出现后可能立刻被「识别中」卡替换（`scan-preview`
  // 只在识别结束、保留预览时回到屏上），所以这里等「预览或识别中」任一
  // 出现即算取图流程完成。
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
    if (find.byKey(const Key('scan-preview')).evaluate().isNotEmpty) break;
    if (find.byKey(const Key('scan-recognizing')).evaluate().isNotEmpty) break;
    if (find.byKey(const Key('scan-draft-card')).evaluate().isNotEmpty) break;
  }
}

/// P10 拍照直通：识别在真实异步间隙里推进，等它**结束**（预览回来 /
/// 草稿卡 / 候选面 / 错误 任一出现即止）。
Future<void> _awaitRecognitionDone(WidgetTester tester) async {
  for (var i = 0; i < 25; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
    final preview = find.byKey(const Key('scan-preview')).evaluate();
    final draft = find.byKey(const Key('scan-draft-card')).evaluate();
    final error = find.byKey(const Key('scan-error')).evaluate();
    final overview = find.byKey(const Key('scan-result-overview')).evaluate();
    if (preview.isNotEmpty ||
        draft.isNotEmpty ||
        error.isNotEmpty ||
        overview.isNotEmpty) {
      break;
    }
  }
  await tester.pumpAndSettle();
}

Widget _app(
  MealRepository meals,
  _TemporaryStore store,
  _Picker picker,
  DateTime now, {
  MealRecognitionProvider? recognition,
  ResolveMealScanCandidates? resolver,
}) => MaterialApp(
  home: FoodScanPage(
    prepareMealImage: PrepareMealImage(
      picker: picker,
      processor: const _Processor(),
      store: store,
    ),
    recognizeConfirmedMealImage: recognition != null
        ? RecognizeConfirmedMealImage(provider: recognition)
        : null,
    resolveMealScanCandidates: resolver,
    mealRepository: meals,
    now: now,
  ),
);

DateTime get now => DateTime(2026, 9, 25, 12);

// ── 测试夹具 ──────────────────────────────────────────────────────

final class _Ids implements IdGenerator {
  int _value = 0;
  @override
  String next() => 'scan-id-${_value++}';
}

final class _Picker implements MealImagePicker {
  SelectedMealImage? next;
  MealImageFailure? failure;
  final sources = <MealImageSource>[];

  @override
  Future<SelectedMealImage?> pick(MealImageSource source) async {
    sources.add(source);
    if (failure case final error?) throw error;
    if (next == null) return null;
    return next!;
  }

  @override
  Future<SelectedMealImage?> recoverLost() async => null;
}

final class _Processor implements MealImageProcessor {
  const _Processor();
  @override
  Future<ProcessedMealImage> process(SelectedMealImage selected) async =>
      ProcessedMealImage(
        bytes: Uint8List.fromList(const [0xff, 0xd8, 0xff, 0xd9]),
        width: 100,
        height: 80,
      );
}

final class _TemporaryStore implements TemporaryMealImageStore {
  final deleted = <PreparedMealImage>[];
  int deleteAttempts = 0;

  @override
  Future<void> clearStale() async {}
  @override
  Future<void> clearAll() async {}
  @override
  Future<void> delete(PreparedMealImage image) async {
    deleteAttempts++;
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

final class _Provider implements MealRecognitionProvider {
  int calls = 0;
  bool emptyResult = false;
  Object? failure;

  @override
  Future<MealEstimateDraft> recognize(
    PreparedMealImage image, {
    MealRecognitionCancellationToken? cancellationToken,
  }) async {
    calls++;
    await Future<void>.delayed(const Duration(milliseconds: 100));
    if (failure case final Object err?) throw err;
    if (emptyResult) throw const MealEstimateEmptyResult();
    return const MealEstimateDraft(
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
        ),
      ],
      warnings: [],
      mealNotes: null,
    );
  }
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
