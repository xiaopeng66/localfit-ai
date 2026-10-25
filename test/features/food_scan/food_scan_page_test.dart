import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image_lib;
import 'package:localfit_ai/features/food_scan/application/prepare_meal_image.dart';
import 'package:localfit_ai/features/food_scan/application/recognize_confirmed_meal_image.dart';
import 'package:localfit_ai/features/food_scan/domain/meal_estimate.dart';
import 'package:localfit_ai/features/food_scan/domain/meal_image.dart';
import 'package:localfit_ai/features/food_scan/presentation/food_scan_page.dart';

void main() {
  late Directory directory;
  late _Picker picker;
  late _Store store;
  late _Provider provider;
  late PrepareMealImage prepare;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('localfit-scan-widget-');
    picker = _Picker();
    store = _Store(directory);
    provider = _Provider();
    prepare = PrepareMealImage(
      picker: picker,
      processor: const _Processor(),
      store: store,
    );
  });

  tearDown(() async {
    try {
      if (await directory.exists()) await directory.delete(recursive: true);
    } on PathAccessException {
      // Windows can keep Image.file handles briefly after a widget test.
    }
  });

  testWidgets('selects, previews and discards a locally processed image', (
    tester,
  ) async {
    picker.next = SelectedMealImage(
      bytes: Uint8List.fromList([1, 2, 3]),
      source: MealImageSource.gallery,
    );
    await tester.pumpWidget(
      MaterialApp(home: FoodScanPage(prepareMealImage: prepare)),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('图片只在本机处理，尚未上传'), findsNothing);
    await tester.tap(find.byKey(const Key('scan-camera')));
    for (var index = 0; index < 10; index++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      if (find.byKey(const Key('scan-preview')).evaluate().isNotEmpty) break;
    }

    expect(picker.sources, [MealImageSource.camera]);
    expect(find.byKey(const Key('scan-preview')), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('scan-discard')));
    await tester.tap(find.byKey(const Key('scan-discard')));
    for (var index = 0; index < 10; index++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      if (find.byKey(const Key('scan-preview')).evaluate().isEmpty) break;
    }
    expect(find.byKey(const Key('scan-preview')), findsNothing);
    expect(store.deleted, hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('scan-draft-card displays when recognition draft exists', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    picker.next = SelectedMealImage(
      bytes: Uint8List.fromList([1, 2, 3]),
      source: MealImageSource.gallery,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: FoodScanPage(
          prepareMealImage: prepare,
          recognizeConfirmedMealImage: RecognizeConfirmedMealImage(
            provider: provider,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('scan-camera')));
    for (var index = 0; index < 10; index++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      if (find.byKey(const Key('scan-preview')).evaluate().isNotEmpty) break;
    }

    // P10（需求 37）：拍照直通——选完图自动开始识别，不再手点分析。
    await _waitDraftCard(tester);

    expect(find.byKey(const Key('scan-draft-card')), findsOneWidget);
  });

  testWidgets('shows recoverable errors and keeps manual flow available', (
    tester,
  ) async {
    picker.failure = const MealImageFailure('权限被拒绝，请检查设置。');
    await tester.pumpWidget(
      MaterialApp(home: FoodScanPage(prepareMealImage: prepare)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('scan-camera')));
    await tester.pumpAndSettle();

    expect(find.text('权限被拒绝，请检查设置。'), findsOneWidget);
    expect(find.byKey(const Key('scan-camera')), findsOneWidget);
  });

  testWidgets(
    'shows back-to-nutrition button when onBackToNutrition is wired',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: FoodScanPage(
            prepareMealImage: prepare,
            onBackToNutrition: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('scan-back')), findsOneWidget);
    },
  );

  testWidgets('onBackToNutrition 为 null 时返回键退回 Navigator.maybePop', (
    tester,
  ) async {
    // docs/21 §3.6：LfTopBar 的返回键**常驻**（视觉规格就是那颗 36dp 圆钮），
    // 接线与否只决定它「回哪」，不决定它「在不在」。未接线时走默认
    // `Navigator.maybePop`——在本测试里没有可弹的路由，页面不应因此崩。
    await tester.pumpWidget(
      MaterialApp(home: FoodScanPage(prepareMealImage: prepare)),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('scan-back')), findsOneWidget);
    await tester.tap(find.byKey(const Key('scan-back')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('cta-rescan discards the current image and returns to idle', (
    tester,
  ) async {
    picker.next = SelectedMealImage(
      bytes: Uint8List.fromList([1, 2, 3]),
      source: MealImageSource.gallery,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: FoodScanPage(prepareMealImage: prepare, onBackToNutrition: () {}),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('scan-camera')));
    for (var index = 0; index < 10; index++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      if (find.byKey(const Key('scan-preview')).evaluate().isNotEmpty) break;
    }
    expect(find.byKey(const Key('scan-preview')), findsOneWidget);

    await tester.tap(find.byKey(const Key('cta-rescan')));
    for (var index = 0; index < 10; index++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      if (find.byKey(const Key('scan-preview')).evaluate().isEmpty) break;
    }
    expect(find.byKey(const Key('scan-preview')), findsNothing);
    expect(store.deleted, hasLength(1));
  });

  testWidgets('cancellation creates no preview or error', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: FoodScanPage(prepareMealImage: prepare)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('scan-camera')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('scan-preview')), findsNothing);
    expect(find.byKey(const Key('scan-error')), findsNothing);
  });
}

/// P10 拍照直通：选完图后识别在真实异步间隙里推进（fake provider 的
/// `Future` 要跨 `runAsync` 才 resolve），等 `scan-draft-card` 出现为止。
Future<void> _waitDraftCard(WidgetTester tester) async {
  for (var index = 0; index < 25; index++) {
    if (find.byKey(const Key('scan-draft-card')).evaluate().isNotEmpty) break;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
}

final class _Picker implements MealImagePicker {
  SelectedMealImage? next;
  MealImageFailure? failure;
  final sources = <MealImageSource>[];

  @override
  Future<SelectedMealImage?> pick(MealImageSource source) async {
    sources.add(source);
    if (failure case final error?) throw error;
    return next;
  }

  @override
  Future<SelectedMealImage?> recoverLost() async => null;
}

final class _Processor implements MealImageProcessor {
  const _Processor();

  @override
  Future<ProcessedMealImage> process(SelectedMealImage selected) async {
    return ProcessedMealImage(
      bytes: Uint8List.fromList(const [0xff, 0xd8, 0xff, 0xd9]),
      width: 100,
      height: 80,
    );
  }
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
      ),
    ],
    warnings: [],
    mealNotes: null,
  );
}

final class _Store implements TemporaryMealImageStore {
  _Store(this.directory);

  final Directory directory;
  final deleted = <PreparedMealImage>[];
  int count = 0;

  @override
  Future<void> clearStale() async {}

  @override
  Future<void> clearAll() async {}

  @override
  Future<void> delete(PreparedMealImage image) async {
    deleted.add(image);
  }

  @override
  Future<PreparedMealImage> save(ProcessedMealImage image) async {
    final file = File(
      '${directory.path}${Platform.pathSeparator}${count++}.jpg',
    );
    final preview = image_lib.Image(width: 2, height: 2);
    preview.setPixelRgb(0, 0, 255, 0, 0);
    await file.writeAsBytes(image_lib.encodeJpg(preview));
    return PreparedMealImage(
      path: file.path,
      width: image.width,
      height: image.height,
      byteLength: image.bytes.length,
    );
  }
}
