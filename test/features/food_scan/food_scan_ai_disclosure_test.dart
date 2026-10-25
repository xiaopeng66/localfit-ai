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
  late AppDatabase database;
  late MealRepository meals;
  late _Picker picker;
  late _Provider provider;
  late PrepareMealImage prepare;
  late DateTime now;

  setUp(() async {
    now = DateTime(2026, 9, 25, 12);
    database = AppDatabase(NativeDatabase.memory());
    meals = MealRepository(
      database: database,
      idGenerator: _Ids(),
      clock: FixedAppClock(now),
    );
    // 预种米饭食物，供 resolver 匹配
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
    picker = _Picker();
    provider = _Provider();
    prepare = PrepareMealImage(
      picker: picker,
      processor: const _Processor(),
      store: _Store(),
    );
  });

  tearDown(() => database.close());

  Widget page({ResolveMealScanCandidates? resolver}) => MaterialApp(
    home: FoodScanPage(
      prepareMealImage: prepare,
      recognizeConfirmedMealImage: RecognizeConfirmedMealImage(
        provider: provider,
      ),
      resolveMealScanCandidates: resolver,
      mealRepository: meals,
      now: now,
    ),
  );

  testWidgets('拍照直通（P10）：拍到图就自动开始识别，无需再点分析', (tester) async {
    // 900×1600 视口：默认 800×600 下草稿卡在懒加载 ListView 折叠线下，
    // 根本不会构建，finder 匹配不到（P10 排障实录，勿改回默认视口）。
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(page());
    await _selectPreparedImage(tester, picker, provider: provider);

    // P10（需求 37）：拍摄即识别——provider 在选择后已被调用，
    // 不再要求用户点「使用 AI 分析餐食」。
    await tester.pumpAndSettle();
    expect(provider.calls, 1);
    expect(find.byKey(const Key('scan-draft-card')), findsOneWidget);
  });

  testWidgets('confirmed upload invokes once and only displays a draft', (
    tester,
  ) async {
    // 视口说明同上：草稿卡要在 900×1600 下才进懒加载列表的构建区。
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(page());
    await _selectPreparedImage(tester, picker, provider: provider);
    // 直通已触发过一次识别；确认上传不应再次调用 provider。
    await tester.pumpAndSettle();

    expect(provider.calls, 1);
    expect(find.byKey(const Key('scan-draft-card')), findsOneWidget);
    expect(find.textContaining('尚未保存，也未计入今日统计'), findsOneWidget);
    expect(find.textContaining('not-a-real-api-key'), findsNothing);
    expect(find.textContaining('/private/meal.jpg'), findsNothing);
  });

  testWidgets(
    'candidate initialization follows immediate recognition and uses local food',
    (tester) async {
      // 900×1600 视口：与同文件其他用例一致。默认 800×600 下 4:3 照片卡
      // 占 576dp，固定底栏的遮挡差值最大，最容易出现「看得见点不到」。
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final search = _FoodSearch();
      final resolver = ResolveMealScanCandidates(foodSearch: search);
      await tester.pumpWidget(page(resolver: resolver));
      await _selectPreparedImage(tester, picker, provider: provider);

      // 拍照直通已触发识别；provider 与候选解析各一次、只一次。
      expect(provider.calls, 1);
      expect(search.calls, 1);
      // docs/21 §5.4：识别结果先落**只读面**，候选编辑器是 `cta-edit-items`
      // 进入的二级面。先等结果面出现，再进编辑面找候选卡——懒加载 ListView
      // 下没构建出来的元素 finder 直接匹配不到。
      await tester.scrollUntilVisible(
        find.byKey(const Key('scan-result-overview')),
        400,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.byKey(const Key('scan-result-overview')), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('cta-edit-items')),
        400,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await enterEditor(tester);
      await scrollToTop(tester);
      await tester.scrollUntilVisible(
        find.byKey(const Key('scan-candidate-card')),
        400,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.byKey(const Key('scan-candidate-card')), findsOneWidget);
      // 「本地食物：米饭」在食材概览区和候选编辑器各出现一次（两个区块都
      // 按设计渲染），所以断言要限定在候选编辑器内——这条测试要证的是
      // 「编辑器用了本地食物」，不是「全页只出现一次」。
      expect(
        find.descendant(
          of: find.byKey(const Key('scan-candidate-card')),
          matching: find.text('本地食物：米饭'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('本地合计 209 kcal'), findsOneWidget);
      expect(find.textContaining('not-a-real-api-key'), findsNothing);
      expect(find.textContaining('/private/meal.jpg'), findsNothing);
    },
  );

  testWidgets('P10 拍照直通：落地屏已删，空态只有拍摄主钮', (tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();

    // 需求 37：落地屏（空态插画 + 拍摄/相册两钮）删除，只留一个
    // 「拍摄照片」主按钮直接开相机。
    expect(find.byKey(const Key('scan-camera')), findsOneWidget);
    expect(find.byKey(const Key('scan-gallery')), findsNothing);
    // 旧落地屏的空态插画与它的取图说明都不该再出现。
    expect(find.textContaining('拍照识餐小助手'), findsNothing);
    expect(find.textContaining('从相册选择'), findsNothing);
  });

  testWidgets('P10 拍照直通：带 initialImage 进页即自动识别', (tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final prepared = PreparedMealImage(
      path: '/private/direct.jpg',
      width: 100,
      height: 80,
      byteLength: 3,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: FoodScanPage(
          prepareMealImage: prepare,
          recognizeConfirmedMealImage: RecognizeConfirmedMealImage(
            provider: provider,
          ),
          initialImage: prepared,
          autoStartCamera: true,
        ),
      ),
    );
    // 首帧后自动识别启动：不等用户任何操作 provider 已被调用。
    for (var index = 0; index < 25; index++) {
      if (provider.calls > 0) break;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(provider.calls, 1);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('scan-draft-card')), findsOneWidget);
  });

  testWidgets('P10 拍照直通：取图来源必须是相机（不是相册）', (tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(page());
    await _selectPreparedImage(tester, picker, provider: provider);

    // 需求 37：chip 直开相机；相册路径收在 AI 对话的图片按钮与剩余流程。
    expect(picker.sources, [MealImageSource.camera]);
  });

  testWidgets(
    'empty and network failures retain the preview without raw errors',
    (tester) async {
      provider.failure = const NetworkFailure(
        'provider-hostile-response not-a-real-api-key /private/meal.jpg',
        kind: NetworkFailureKind.connection,
      );
      await tester.pumpWidget(page());
      await _selectPreparedImage(tester, picker, provider: provider);
      await _openDisclosure(tester);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('scan-preview')), findsOneWidget);
      expect(find.text('网络连接不可用，请检查网络后手动重试。'), findsOneWidget);
      expect(find.textContaining('provider-hostile-response'), findsNothing);
      expect(find.textContaining('not-a-real-api-key'), findsNothing);
      expect(find.textContaining('/private/meal.jpg'), findsNothing);
    },
  );

  testWidgets(
    'cancelling an active recognition retains preview without error',
    (tester) async {
      provider.waitForCancellation = true;
      await tester.pumpWidget(page());
      // P10 拍照直通：选完图识别自动开始（provider 挂起等取消）。
      await _selectPreparedImage(tester, picker, provider: provider);
      expect(find.byKey(const Key('scan-recognizing')), findsOneWidget);
      expect(provider.calls, 1);

      await tester.tap(find.byKey(const Key('scan-cancel-recognition')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('scan-preview')), findsOneWidget);
      expect(find.byKey(const Key('scan-error')), findsNothing);
    },
  );
}

Future<void> _openDisclosure(WidgetTester tester) async {
  await tester.drag(find.byType(ListView), const Offset(0, -600));
  await tester.pumpAndSettle();
  // 确保按钮在视口可见后再点击，避免懒加载 ListView 遮挡
  await tester.ensureVisible(find.byKey(const Key('scan-analyze')));
  await tester.pumpAndSettle();
  final button = find.byKey(const Key('scan-analyze'));
  expect(button, findsOneWidget);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> _selectPreparedImage(
  WidgetTester tester,
  _Picker picker, {
  required _Provider provider,
}) async {
  picker.next = SelectedMealImage(
    bytes: Uint8List.fromList([1]),
    source: MealImageSource.camera,
  );
  await tester.tap(find.byKey(const Key('scan-camera')));
  await tester.pump();
  // P10 拍照直通：选择后自动开始识别。取图完成前页面显示「正在本机处理
  // 图片…」进度卡（识别中也有常驻动画），这里不能 pumpAndSettle——等它
  // 停下来会超时；逐帧推进直到识别结束（草稿卡出现）或调用方注入的
  // provider 进入「等取消」的挂起态。
  for (var index = 0; index < 25; index++) {
    if (find.byKey(const Key('scan-draft-card')).evaluate().isNotEmpty) break;
    if (provider.waitForCancellation &&
        find.byKey(const Key('scan-recognizing')).evaluate().isNotEmpty &&
        provider.calls > 0) {
      break;
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
}

final class _Provider implements MealRecognitionProvider {
  int calls = 0;
  bool waitForCancellation = false;
  Object? failure;

  @override
  Future<MealEstimateDraft> recognize(
    PreparedMealImage image, {
    MealRecognitionCancellationToken? cancellationToken,
  }) async {
    calls++;
    if (failure case final Object error?) throw error;
    if (waitForCancellation) {
      await cancellationToken!.whenCancelled;
      throw const NetworkFailure(
        'ignored remote error',
        kind: NetworkFailureKind.cancelled,
      );
    }
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
  int calls = 0;

  @override
  Future<List<FoodRecord>> search(String query, {int limit = 30}) async {
    calls++;
    return const [
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

final class _Ids implements IdGenerator {
  int _value = 0;

  @override
  String next() => 'test-id-${_value++}';
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

final class _Store implements TemporaryMealImageStore {
  @override
  Future<void> clearStale() async {}

  @override
  Future<void> clearAll() async {}

  @override
  Future<void> delete(PreparedMealImage image) async {}

  @override
  Future<PreparedMealImage> save(ProcessedMealImage image) async =>
      PreparedMealImage(
        path: '/private/meal.jpg',
        width: image.width,
        height: image.height,
        byteLength: image.bytes.length,
      );
}
