import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image_lib;
import 'package:localfit_ai/features/food_scan/application/local_food_search.dart';
import 'package:localfit_ai/features/food_scan/application/prepare_meal_image.dart';
import 'package:localfit_ai/features/food_scan/application/recognize_confirmed_meal_image.dart';
import 'package:localfit_ai/features/food_scan/application/resolve_meal_scan_candidates.dart';
import 'package:localfit_ai/features/food_scan/domain/meal_estimate.dart';
import 'package:localfit_ai/features/food_scan/domain/meal_image.dart';
import 'package:localfit_ai/features/food_scan/presentation/food_scan_page.dart';
import 'package:localfit_ai/features/nutrition/domain/food_record.dart';

/// 暴力测试（UI 层）：识别在途时反复点「使用 AI 分析餐食」。
///
/// 真实供应商一次识别要 20–60 秒，用户等待期间反复点按钮是常态。若守卫
/// 写在 `await` 之后（或只依赖渲染状态），每次点击都会另发一个请求——
/// 用户为此**重复付费**，且多份结果互相竞争上屏。
///
/// 数值/字符串边界的暴力测试在 `candidate_resolution_bruteforce_test.dart`
/// （应用层，纯逻辑，跑得快且覆盖更全）。
void main() {
  late Directory directory;
  late _Picker picker;
  late _Store store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('localfit-bruteforce-');
    picker = _Picker();
    store = _Store(directory);
  });

  tearDown(() async {
    try {
      if (await directory.exists()) await directory.delete(recursive: true);
    } on PathAccessException {
      // Windows 可能短暂持有文件句柄。
    }
  });

  testWidgets('识别在途时连点 9 次：不得重入、不得重复发送', (tester) async {
    final provider = _Provider(delay: const Duration(milliseconds: 300));
    tester.view.physicalSize = const Size(900, 1700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: FoodScanPage(
          prepareMealImage: PrepareMealImage(
            picker: picker,
            processor: const _Processor(),
            store: store,
          ),
          recognizeConfirmedMealImage: RecognizeConfirmedMealImage(
            provider: provider,
          ),
          resolveMealScanCandidates: ResolveMealScanCandidates(
            foodSearch: const _FoodSearch(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    picker.next = SelectedMealImage(
      bytes: Uint8List.fromList(const [1, 2, 3]),
      source: MealImageSource.camera,
    );
    // P10 拍照直通：选完图识别自动开始（provider 延迟 300ms），没有
    // 「点分析钮」这一步了。
    await tester.tap(find.byKey(const Key('scan-camera')));
    await settleUntil(
      tester,
      () => find.byKey(const Key('scan-recognizing')).evaluate().isNotEmpty,
    );

    final analyze = find.byKey(const Key('scan-analyze'));
    for (var index = 0; index < 9; index++) {
      await tester.tap(analyze, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 10));
    }
    // docs/21 §5.4：识别完成后先落**只读结果面**（`scan-result-overview`），
    // 候选编辑器是 `cta-edit-items` 进入的二级面。等结果面出现再进编辑面。
    await settleUntil(
      tester,
      () => find.byKey(const Key('scan-result-overview')).evaluate().isNotEmpty,
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('cta-edit-items')),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('cta-edit-items')));
    await settleUntil(
      tester,
      () => find.byKey(const Key('scan-candidate-card')).evaluate().isNotEmpty,
    );

    expect(
      provider.calls,
      1,
      reason: '识别在途时的重复点击不得重入；实际发送 ${provider.calls} 次',
    );
  });
}

/// 反复推进时钟直到条件成立（顺手推进动画时钟，让底部 Sheet 能走完入场）。
Future<void> settleUntil(
  WidgetTester tester,
  bool Function() done, {
  Duration timeout = const Duration(seconds: 6),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (done()) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  if (!done()) throw StateError('settleUntil 超时：条件在 $timeout 内未成立');
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
        bytes: Uint8List.fromList(const [0xff, 0xd8, 0xff, 0xd9]),
        width: 100,
        height: 80,
      );
}

final class _Store implements TemporaryMealImageStore {
  _Store(this.directory);

  final Directory directory;
  int savedCount = 0;

  @override
  Future<void> clearStale() async {}

  @override
  Future<void> clearAll() async {}

  @override
  Future<void> delete(PreparedMealImage image) async {}

  @override
  Future<PreparedMealImage> save(ProcessedMealImage image) async {
    savedCount++;
    final file = File(
      '${directory.path}${Platform.pathSeparator}$savedCount.jpg',
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

final class _FoodSearch implements LocalFoodSearch {
  const _FoodSearch();

  @override
  Future<List<FoodRecord>> search(String query, {int limit = 30}) async =>
      const [
        FoodRecord(
          id: 'food-rice',
          name: '米饭',
          kcalPer100g: 133,
          proteinPer100g: 2.7,
          carbsPer100g: 29,
          fatPer100g: 0.3,
          isUserCreated: false,
        ),
      ];
}

/// 可注入延迟的识别 provider，用来把请求停在「路上」制造重入窗口。
final class _Provider implements MealRecognitionProvider {
  _Provider({this.delay});

  final Duration? delay;
  int calls = 0;

  @override
  Future<MealEstimateDraft> recognize(
    PreparedMealImage image, {
    MealRecognitionCancellationToken? cancellationToken,
  }) async {
    calls++;
    if (delay != null) await Future<void>.delayed(delay!);
    return const MealEstimateDraft(
      items: [
        MealEstimateItem(
          name: '米饭',
          estimatedGrams: 150,
          gramsRange: GramRange(min: 120, max: 180),
          confidence: 0.8,
          ingredients: ['大米'],
          needsConfirmation: false,
          questions: [],
          cookingMethod: '蒸',
          nutrition: MealEstimateNutrition(
            kcal: 200,
            proteinGrams: 4,
            carbsGrams: 44,
            fatGrams: 0.5,
          ),
        ),
      ],
      warnings: [],
      mealNotes: '测试草案',
    );
  }
}
