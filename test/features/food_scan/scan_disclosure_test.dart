import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image_lib;
import 'package:localfit_ai/features/food_scan/application/load_meal_recognition_disclosure.dart';
import 'package:localfit_ai/features/food_scan/application/local_food_search.dart';
import 'package:localfit_ai/features/food_scan/application/prepare_meal_image.dart';
import 'package:localfit_ai/features/food_scan/application/recognize_confirmed_meal_image.dart';
import 'package:localfit_ai/features/food_scan/application/resolve_meal_scan_candidates.dart';
import 'package:localfit_ai/features/food_scan/domain/meal_estimate.dart';
import 'package:localfit_ai/features/food_scan/domain/meal_image.dart';
import 'package:localfit_ai/features/food_scan/presentation/food_scan_page.dart';
import 'package:localfit_ai/features/nutrition/domain/food_record.dart';
import 'package:localfit_ai/features/settings/domain/ai_provider_settings.dart';

/// 发送披露（docs/21 §5.4「发送披露」）：扫描页必须以**常驻一行**
/// 写清「发给谁」——用户已否决发送前的二次确认弹层，但披露内容不能因此缩水。
///
/// 这里守的是那条被删除的死组件（`ScanUploadDisclosureDialog`）原本承载的
/// 信息：目的地主机与模型必须真的出现在屏幕上，而不只是「见设置」。
void main() {
  late Directory directory;
  late _Store store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('localfit-disclosure-');
    store = _Store(directory);
  });

  tearDown(() async {
    try {
      if (await directory.exists()) await directory.delete(recursive: true);
    } on PathAccessException {
      // Windows 可能短暂持有文件句柄。
    }
  });

  /// 构造被测页面（与真机同构：真实落盘的 store、真实 `PrepareMealImage`）。
  Widget page({LoadMealRecognitionDisclosure? load}) => FoodScanPage(
    prepareMealImage: PrepareMealImage(
      picker: _Picker(),
      processor: const _Processor(),
      store: store,
    ),
    recognizeConfirmedMealImage: RecognizeConfirmedMealImage(
      provider: _Provider(),
    ),
    resolveMealScanCandidates: ResolveMealScanCandidates(
      foodSearch: const _FoodSearch(),
    ),
    loadMealRecognitionDisclosure: load,
  );

  void sizeView(WidgetTester tester) {
    tester.view.physicalSize = const Size(900, 1700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> show(
    WidgetTester tester, {
    LoadMealRecognitionDisclosure? load,
  }) async {
    sizeView(tester);
    await tester.pumpWidget(MaterialApp(home: page(load: load)));
    await tester.pumpAndSettle();
  }

  /// 复刻 shell 分支的**保活**语义：`AppRoutes.foodScan` 是
  /// `StatefulShellRoute.indexedStack` 的一个分支，切走再切回时页面
  /// **不重建**（State 保留），只有 `Visibility.of` 会回调
  /// `didChangeDependencies`。这里的 `IndexedStack` 就是 go_router
  /// 分支容器用的同一个 widget。
  Widget shellWith({
    required int visibleIndex,
    required Widget page,
    Widget other = const Scaffold(body: SizedBox.shrink()),
  }) => MaterialApp(
    home: IndexedStack(index: visibleIndex, children: [other, page]),
  );

  /// 选一张图，让 `scan-disclosure` 那行进入屏面。
  Future<void> selectImage(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('scan-camera')));
    for (var index = 0; index < 60; index++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
      if (find.byKey(const Key('scan-preview')).evaluate().isNotEmpty) break;
    }
    expect(find.byKey(const Key('scan-preview')), findsOneWidget);
  }

  testWidgets('读到配置时：披露写明目的地主机与模型', (tester) async {
    await show(
      tester,
      load: LoadMealRecognitionDisclosure(
        configurationReader: _Reader(
          () => const AiProviderConfiguration(
            baseUrl: 'https://api.example.com/v1',
            model: 'gpt-image-2',
          ),
        ),
      ),
    );
    await selectImage(tester);

    final disclosure = find.byKey(const Key('scan-send-disclosure'));
    await tester.ensureVisible(disclosure);
    expect(disclosure, findsOneWidget);
    final text = tester.widget<Text>(disclosure).data!;
    expect(text, contains('api.example.com'), reason: '披露必须写明目的地主机，实际「$text」');
    expect(text, contains('gpt-image-2'), reason: '披露必须写明模型，实际「$text」');
  });

  testWidgets('未接线时：退回通用文案，不出现空占位', (tester) async {
    await show(tester); // load = null
    await selectImage(tester);

    final disclosure = find.byKey(const Key('scan-send-disclosure'));
    await tester.ensureVisible(disclosure);
    final text = tester.widget<Text>(disclosure).data!;
    expect(text, contains('发送给你配置的 AI 服务'));
    expect(text, contains('见设置'), reason: '未接线时指引到设置页');
    expect(text.trim(), isNotEmpty);
    // 不得残留模板痕迹。
    expect(text, isNot(contains('null')));
  });

  testWidgets('读取失败时：静默退回通用文案，不在拍照页挂红字', (tester) async {
    await show(
      tester,
      load: LoadMealRecognitionDisclosure(
        configurationReader: _Reader(() => null), // 设置里没有 AI 配置
      ),
    );
    await selectImage(tester);

    final disclosure = find.byKey(const Key('scan-send-disclosure'));
    await tester.ensureVisible(disclosure);
    final text = tester.widget<Text>(disclosure).data!;
    // 披露是辅助信息：读不到就退回通用文案，不该因为没填配置就在
    // 拍照页头顶报错——真正需要配置的时机是点「使用 AI 分析餐食」。
    expect(text, contains('见设置'));
    expect(find.textContaining('请先在设置中保存 AI 配置'), findsNothing);
  });

  testWidgets('分支保活场景：切走时配置就绪，切回后披露必须写明目的地与模型', (tester) async {
    // 真机复现路径（2026-09-27 模拟器实测）：
    //   1. 用户在扫描页（此时「我的」里还没填 AI 配置）→ 披露退回通用文案；
    //   2. 用户切到「我的」填好 Base URL / 模型并保存；
    //   3. 用户切回扫描页 → **页面不重建**，旧实现仍显示通用文案。
    // `AppRoutes.foodScan` 是 `StatefulShellRoute.indexedStack` 的保活分支，
    // 所以第 3 步只触发 `didChangeDependencies`，不会重跑 `initState`。
    var configuration = const AiProviderConfiguration(
      baseUrl: 'https://old.example.com/v1',
      model: 'old-model',
    );
    final load = LoadMealRecognitionDisclosure(
      configurationReader: _Reader(() => configuration),
    );
    sizeView(tester);

    Widget shell(int visibleIndex) => shellWith(
      visibleIndex: visibleIndex,
      page: page(load: load),
    );

    await tester.pumpWidget(shell(1)); // 扫描页可见
    await tester.pumpAndSettle();
    await selectImage(tester);

    var disclosure = find.byKey(const Key('scan-send-disclosure'));
    await tester.ensureVisible(disclosure);
    expect(
      tester.widget<Text>(disclosure).data,
      contains('old.example.com'),
      reason: '前置条件：首次可见时读到的是旧配置',
    );

    // 用户切到「我的」改配置——扫描页被保活，不在前台。
    await tester.pumpWidget(shell(0));
    await tester.pumpAndSettle();
    configuration = const AiProviderConfiguration(
      baseUrl: 'https://api.example.com/v1',
      model: 'gpt-image-4',
    );

    // 切回扫描页：分支保活 ⇒ 不重建，仅 `didChangeDependencies`。
    await tester.pumpWidget(shell(1));
    await tester.pumpAndSettle();

    disclosure = find.byKey(const Key('scan-send-disclosure'));
    await tester.ensureVisible(disclosure);
    final text = tester.widget<Text>(disclosure).data!;
    expect(
      text,
      contains('api.example.com'),
      reason: '切回后披露必须反映最新配置，实际「$text」',
    );
    expect(text, contains('gpt-image-4'), reason: '模型也必须更新，实际「$text」');
    expect(text, isNot(contains('old.example.com')), reason: '不得残留旧配置');
  });

  testWidgets('分支保活场景：配置被清空后切回，不得残留旧主机名', (tester) async {
    // 披露的意义是如实告知「发给谁」。写一个已经被清掉的主机名，比写
    // 「见设置」更糟——用户会以为自己仍在向那个地址发送图片。
    AiProviderConfiguration? configuration = const AiProviderConfiguration(
      baseUrl: 'https://api.example.com/v1',
      model: 'gpt-image-4',
    );
    final load = LoadMealRecognitionDisclosure(
      configurationReader: _Reader(() => configuration),
    );
    sizeView(tester);

    Widget shell(int visibleIndex) => shellWith(
      visibleIndex: visibleIndex,
      page: page(load: load),
    );

    await tester.pumpWidget(shell(1));
    await tester.pumpAndSettle();
    await selectImage(tester);
    var disclosure = find.byKey(const Key('scan-send-disclosure'));
    await tester.ensureVisible(disclosure);
    expect(tester.widget<Text>(disclosure).data, contains('api.example.com'));

    // 用户在「我的」里清掉配置（load() 会抛 ValidationFailure）。
    await tester.pumpWidget(shell(0));
    await tester.pumpAndSettle();
    configuration = null;
    await tester.pumpWidget(shell(1));
    await tester.pumpAndSettle();

    disclosure = find.byKey(const Key('scan-send-disclosure'));
    await tester.ensureVisible(disclosure);
    final text = tester.widget<Text>(disclosure).data!;
    expect(
      text,
      isNot(contains('api.example.com')),
      reason: '配置已清空，不得继续声称发往旧主机，实际「$text」',
    );
    expect(text, contains('见设置'), reason: '应退回通用文案，实际「$text」');
  });

  testWidgets('乱序完成：先发的读取后返回时，旧结果不得覆盖新结果', (tester) async {
    // 切回分支会重发一次读取；若首次读取（页面创建时发的、可能很慢）在
    // 重读之后才返回，不带序号守卫的实现会让**陈旧配置覆盖新配置**。
    // 这条只在「先发后到」这一时序下才成立，故用可手动放行的 reader。
    final reader = _GatedReader();
    final load = LoadMealRecognitionDisclosure(configurationReader: reader);
    sizeView(tester);
    Widget shell(int visibleIndex) => shellWith(
      visibleIndex: visibleIndex,
      page: page(load: load),
    );

    await tester.pumpWidget(shell(1));
    await tester.pumpAndSettle();
    expect(reader.pending, hasLength(1), reason: '页面创建时应发出首次读取');

    // 切走再切回 ⇒ 触发重读（第 2 次）。
    await tester.pumpWidget(shell(0));
    await tester.pumpAndSettle();
    await tester.pumpWidget(shell(1));
    await tester.pumpAndSettle();
    expect(reader.pending, hasLength(2), reason: '切回时应重读');

    // 重读先返回新配置，首次读取随后才返回旧配置。
    reader.complete(
      1,
      const AiProviderConfiguration(
        baseUrl: 'https://new.example.com/v1',
        model: 'new-model',
      ),
    );
    await tester.pumpAndSettle();
    reader.complete(
      0,
      const AiProviderConfiguration(
        baseUrl: 'https://stale.example.com/v1',
        model: 'stale-model',
      ),
    );
    await tester.pumpAndSettle();

    await selectImage(tester);
    final disclosure = find.byKey(const Key('scan-send-disclosure'));
    await tester.ensureVisible(disclosure);
    final text = tester.widget<Text>(disclosure).data!;
    expect(
      text,
      contains('new.example.com'),
      reason: '晚到的陈旧结果不得覆盖新结果，实际「$text」',
    );
    expect(
      text,
      isNot(contains('stale.example.com')),
      reason: '陈旧结果必须被序号守卫丢弃，实际「$text」',
    );
  });
}

/// 返回给定配置（或 null）的 reader；`_Reader` 支持中途换值。
final class _Reader implements AiProviderConfigurationReader {
  _Reader(this._configuration);

  final AiProviderConfiguration? Function() _configuration;

  @override
  Future<AiProviderConfiguration?> loadConfiguration() async =>
      _configuration();
}

/// 读取完成顺序**可手动控制**的 reader：用于制造「先发的读取后完成」。
final class _GatedReader implements AiProviderConfigurationReader {
  final List<Completer<AiProviderConfiguration?>> pending = [];

  @override
  Future<AiProviderConfiguration?> loadConfiguration() {
    final completer = Completer<AiProviderConfiguration?>();
    pending.add(completer);
    return completer.future;
  }

  /// 完成第 [index] 次读取。
  void complete(int index, AiProviderConfiguration? configuration) =>
      pending[index].complete(configuration);
}

final class _Picker implements MealImagePicker {
  @override
  Future<SelectedMealImage?> pick(MealImageSource source) async =>
      SelectedMealImage(
        bytes: Uint8List.fromList(const [1, 2, 3]),
        source: source,
      );

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

final class _Provider implements MealRecognitionProvider {
  @override
  Future<MealEstimateDraft> recognize(
    PreparedMealImage image, {
    MealRecognitionCancellationToken? cancellationToken,
  }) async => const MealEstimateDraft(
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
    mealNotes: null,
  );
}
