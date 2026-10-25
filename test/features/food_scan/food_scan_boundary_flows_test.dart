import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image_lib;
import 'package:localfit_ai/core/errors/app_failure.dart';
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

/// 阶段 4 验收里**曾缺测**的三条边界：权限拒绝、相册取消、识别超时。
///
/// 三条都属于 docs/21 §5.8.1
/// 「错误、取消和中断恢复矩阵」：
/// - 权限拒绝/相册取消 → 保留当前页面，不伪造图片、不卡 loading；
/// - 超时 → 保留草稿与输入，可重试，且**不得重复写入事实**。
void main() {
  late Directory directory;
  late _Picker picker;
  late _Store store;
  late PrepareMealImage prepare;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('localfit-scan-edge-');
    picker = _Picker();
    store = _Store(directory);
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
      // Windows 可能短暂持有 Image.file 句柄。
    }
  });

  Future<void> pumpPage(
    WidgetTester tester, {
    RecognizeConfirmedMealImage? recognize,
    ResolveMealScanCandidates? resolve,
    MealRepository? meals,
    DateTime? now,
  }) async {
    tester.view.physicalSize = const Size(900, 1700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: FoodScanPage(
          prepareMealImage: prepare,
          recognizeConfirmedMealImage: recognize,
          resolveMealScanCandidates: resolve,
          mealRepository: meals,
          now: now,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 点选择按钮并等到处理结束（预览出现/不出现即止）。
  Future<void> tapSelect(
    WidgetTester tester,
    String key, {
    required bool untilPreview,
  }) async {
    await tester.ensureVisible(find.byKey(Key(key)));
    await tester.tap(find.byKey(Key(key)));
    for (var index = 0; index < 15; index++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      final has = find.byKey(const Key('scan-preview')).evaluate().isNotEmpty;
      if (has == untilPreview) break;
    }
  }

  // ------------------------------------------------------------ 权限拒绝

  testWidgets('权限拒绝：可行动错误、无预览、无文件残留、恢复后可重试', (tester) async {
    picker.failure = const MealImageFailure('无法选择图片，请检查相机或相册权限后重试。');
    await pumpPage(tester);

    await tapSelect(tester, 'scan-camera', untilPreview: false);

    // 1) 错误可见且是「去检查权限」这类可行动文案。
    expect(find.textContaining('请检查相机或相册权限'), findsOneWidget);
    // 2) 不伪造图片：既没有预览，也没有草案卡。
    expect(find.byKey(const Key('scan-preview')), findsNothing);
    expect(find.byKey(const Key('scan-candidate-card')), findsNothing);
    // 3) 不卡 loading：进度卡退场。
    expect(find.byKey(const Key('scan-processing')), findsNothing);
    // 4) 没写出任何临时文件。
    expect(store.savedCount, 0);
    // 5) 另一条选择入口仍可用（本地链路不被阻断）。
    // 2026-10-03 改判理由（不是放宽判据）：本断言的主体是「这个 key 的按钮
    // 可点吗」，按钮属于哪一型是实现细节。统一化后取图入口对改走 §3.8
    // （主 = B1 `LfPrimaryButton` / 次 = B6 `LfTextButton`），`scan-camera`
    // 的实现类型因此从 `OutlinedButton` 变为 `TextButton`；改取 M3 按钮的
    // 公共基类 `ButtonStyleButton` 后，断言强度不变（仍是真按钮、仍在查
    // `onPressed != null`），且不再与分型耦合。
    expect(
      tester
          .widget<ButtonStyleButton>(find.byKey(const Key('scan-camera')))
          .onPressed,
      isNotNull,
    );

    // 6) 可恢复：权限恢复后能正常选中。
    picker.failure = null;
    picker.next = SelectedMealImage(
      bytes: Uint8List.fromList([1, 2, 3]),
      source: MealImageSource.camera,
    );
    await tapSelect(tester, 'scan-camera', untilPreview: true);
    expect(find.byKey(const Key('scan-preview')), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  // -------------------------------------------------------------- 相册取消

  testWidgets('相册取消：零副作用（无预览、无错误、无文件），不进入错误态', (tester) async {
    picker.next = null; // 用户在系统相册里按了返回。
    await pumpPage(tester);

    await tapSelect(tester, 'scan-camera', untilPreview: false);

    expect(find.byKey(const Key('scan-preview')), findsNothing);
    expect(find.byKey(const Key('scan-processing')), findsNothing);
    // 取消是正常完成，不是错误 —— 屏幕不该出现错误卡。
    expect(find.byKey(const Key('scan-error')), findsNothing);
    expect(store.savedCount, 0);
    expect(store.deleted, isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  // ---------------------------------------------------------------- 超时

  testWidgets('识别超时：保留预览与图片、给出可重试文案、零事实写入', (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
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
            createdAt: DateTime.utc(2026, 9, 9),
            updatedAt: DateTime.utc(2026, 9, 9),
          ),
        );
    final meals = MealRepository(
      database: database,
      idGenerator: _Ids(),
      clock: FixedAppClock(DateTime.utc(2026, 9, 9)),
    );

    picker.next = SelectedMealImage(
      bytes: Uint8List.fromList([1, 2, 3]),
      source: MealImageSource.gallery,
    );
    await pumpPage(
      tester,
      recognize: RecognizeConfirmedMealImage(provider: _TimeoutProvider()),
      resolve: const ResolveMealScanCandidates(foodSearch: _NoFoodSearch()),
      meals: meals,
      now: DateTime(2026, 9, 9, 12),
    );

    await tapSelect(tester, 'scan-camera', untilPreview: true);
    expect(find.byKey(const Key('scan-preview')), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('scan-analyze')));
    await tester.tap(find.byKey(const Key('scan-analyze')));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    // 1) 超时文案可见且指向「手动重试」。
    expect(find.textContaining('超时'), findsOneWidget);
    // 2) 输入未被清空：预览还在（用户不必重拍）。
    expect(find.byKey(const Key('scan-preview')), findsOneWidget);
    // 3) 不卡 loading。
    expect(find.byKey(const Key('scan-processing')), findsNothing);
    expect(find.byKey(const Key('scan-candidate-card')), findsNothing);
    // 4) 零事实写入 —— 超时绝不能落库。
    expect(await database.select(database.meals).get(), isEmpty);
    expect(await database.select(database.mealItems).get(), isEmpty);
    // 5) 重试入口可用。
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('scan-analyze')))
          .onPressed,
      isNotNull,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

final class _Ids implements IdGenerator {
  int _value = 0;

  @override
  String next() => 'edge-id-${_value++}';
}

final class _NoFoodSearch implements LocalFoodSearch {
  const _NoFoodSearch();

  @override
  Future<List<FoodRecord>> search(String query, {int limit = 30}) async =>
      const [];
}

final class _Picker implements MealImagePicker {
  SelectedMealImage? next;
  MealImageFailure? failure;

  @override
  Future<SelectedMealImage?> pick(MealImageSource source) async {
    if (failure case final error?) throw error;
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
        bytes: Uint8List.fromList(const [0xff, 0xd8, 0xff, 0xd9]),
        width: 100,
        height: 80,
      );
}

/// 总是抛超时（NetworkFailure.timeout），模拟供应商无响应。
final class _TimeoutProvider implements MealRecognitionProvider {
  @override
  Future<MealEstimateDraft> recognize(
    PreparedMealImage image, {
    MealRecognitionCancellationToken? cancellationToken,
  }) async =>
      throw const NetworkFailure('识别请求超时', kind: NetworkFailureKind.timeout);
}

final class _Store implements TemporaryMealImageStore {
  _Store(this.directory);

  final Directory directory;
  final deleted = <PreparedMealImage>[];
  int savedCount = 0;

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
