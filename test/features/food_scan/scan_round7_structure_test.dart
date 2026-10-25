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

/// Round7 阶段 3 · 3-3 的结构判据（D53–D55；渲染审看抓到、逐条先取真实 RED）。
///
/// 1. **D53 键唯一**：两个编辑器（餐前 + 剩餐）可同屏，四个曾硬编码的键
///    必须各唯一、剩餐侧带自己的前缀；
/// 2. **D54 字体族**：本地食物选择弹层的行文字必须继承主题字体（与 ⑫ 同族
///    同因：`ButtonStyleButton` 会替换环境 `DefaultTextStyle`）；
/// 3. **D55 分析按钮三态**：识别在途 / 已有候选 ⇒ 隐藏；有图未分析 / 失败
///    ⇒ 仍在（重试路径不减）。
void main() {
  late AppDatabase database;
  late MealRepository meals;
  late _Store store;
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
    store = _Store();
    picker = _Picker();
  });

  tearDown(() => database.close());

  Future<void> pumpPage(
    WidgetTester tester, {
    MealRecognitionProvider? provider,
    String? fontFamily,
  }) async {
    tester.view.physicalSize = const Size(400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var theme = AppTheme.light();
    if (fontFamily != null) {
      theme = theme.copyWith(
        textTheme: theme.textTheme.apply(fontFamily: fontFamily),
        primaryTextTheme: theme.primaryTextTheme.apply(fontFamily: fontFamily),
      );
    }
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
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
    );
    await tester.pumpAndSettle();
  }

  Future<void> takePhoto(WidgetTester tester, {int bytes = 1}) async {
    picker.next = SelectedMealImage(
      bytes: Uint8List.fromList([bytes]),
      source: MealImageSource.camera,
    );
    await tester.tap(find.byKey(const Key('scan-camera')));
    await tester.pumpAndSettle();
  }

  Future<void> tapAfterScroll(WidgetTester tester, Key key) async {
    final finder = find.byKey(key, skipOffstage: false);
    await tester.scrollUntilVisible(
      finder,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  /// 进入编辑面 → 走剩餐流程 → 两个编辑器同时在场。
  Future<void> reachBothEditors(WidgetTester tester) async {
    await takePhoto(tester);
    await tapAfterScroll(tester, const Key('cta-edit-items'));
    picker.next = SelectedMealImage(
      bytes: Uint8List.fromList([2]),
      source: MealImageSource.gallery,
    );
    await tapAfterScroll(tester, const Key('scan-leftover-gallery'));
    await tester.scrollUntilVisible(
      find.byKey(const Key('scan-leftover-analyze'), skipOffstage: false),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    final button = tester.widget<ButtonStyleButton>(
      find.byKey(const Key('scan-leftover-analyze'), skipOffstage: false),
    );
    button.onPressed!();
    await tester.pumpAndSettle();
  }

  group('D53 两个编辑器同屏：四个键各唯一（缺陷 ⑭）', () {
    testWidgets('餐前 + 剩餐编辑器并存时，餐次/备注/分析/卡 键都只有一个', (tester) async {
      await pumpPage(tester);
      await reachBothEditors(tester);

      // 前提：两个编辑器都在场（防空转）。
      expect(find.byKey(const Key('scan-candidate-card')), findsOneWidget);
      expect(find.byKey(const Key('scan-leftover-editor')), findsOneWidget);

      // 主编辑器的四个键仍旧（前缀就是 `scan-candidate`，键名一字不变）。
      expect(find.byKey(const Key('scan-candidate-slot')), findsOneWidget);
      expect(find.byKey(const Key('scan-candidate-notes')), findsOneWidget);
      expect(
        find.byKey(const Key('scan-candidate-analysis-open')),
        findsOneWidget,
      );
      // 剩餐编辑器的四件必须带**自己的前缀**（此前硬编码 ⇒ 找不到自己那把）。
      expect(
        find.byKey(const Key('scan-leftover-candidate-card')),
        findsOneWidget,
        reason: '剩餐编辑器的卡键（此前与主编辑器同键）',
      );
      expect(
        find.byKey(const Key('scan-leftover-candidate-slot')),
        findsOneWidget,
        reason: '剩餐编辑器的餐次键（探针 3e-probe-leftover-3 实测 slot=0）',
      );
      expect(
        find.byKey(const Key('scan-leftover-candidate-notes')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('scan-leftover-candidate-analysis-open')),
        findsOneWidget,
      );
    });

    testWidgets('剩餐确认钮文案（裁决 ④：「净摄入入账」，不再折两行）', (tester) async {
      await pumpPage(tester);
      await reachBothEditors(tester);

      // 键落在内层 `FilledButton`（「key 只落内层」）⇒ 读按钮内文字。
      expect(
        find.descendant(
          of: find.byKey(const Key('scan-leftover-candidate-confirm')),
          matching: find.text('净摄入入账'),
        ),
        findsOneWidget,
        reason: '与主编辑器的「确认入账」仍能区分',
      );
      // 单行 = 与同排「取消」等高（折叠成两行会把整排拉得不等高，那是 ⑱ 的
      // 观测事实）；缩字不折行由 `LfPrimaryButton.fitLabel` 的 scaleDown 兜底。
      final cancel = tester.getRect(
        find.byKey(const Key('scan-leftover-candidate-cancel')),
      );
      final confirm = tester.getRect(
        find.byKey(const Key('scan-leftover-candidate-confirm')),
      );
      expect(confirm.height, closeTo(cancel.height, 0.5));
    });

    testWidgets('行动行的修正钮与逐项同一术语（裁决 ③：「修正识别」）', (tester) async {
      await pumpPage(tester);
      await takePhoto(tester);
      await tapAfterScroll(tester, const Key('cta-edit-items'));

      expect(
        find.descendant(
          of: find.byKey(const Key('scan-candidate-edit')),
          matching: find.text('修正识别'),
        ),
        findsOneWidget,
        reason: '同一件事两个名字（编辑 vs 修正识别）只会让人以为是两件事',
      );
      // 逐项入口仍在（键与文案都不动）。
      expect(find.byKey(const Key('scan-candidate-correct-0')), findsOneWidget);
    });
  });

  group('D54 本地食物弹层的行文字随主题字体（缺陷 ⑮）', () {
    testWidgets('行标题/副标题的字体族 = 主题字体，不是自成一族', (tester) async {
      await pumpPage(tester, fontFamily: 'PlatformCjk');
      await takePhoto(tester);
      await tapAfterScroll(tester, const Key('cta-edit-items'));
      await tapAfterScroll(tester, const Key('scan-candidate-search-0'));

      expect(find.byKey(const Key('scan-food-search')), findsOneWidget);
      final title = tester.widget<Text>(find.text('米饭').last);
      expect(
        title.style?.fontFamily,
        'PlatformCjk',
        reason: '行文字住在 ListTile/按钮里，族不从主题走 ⇒ 测试帧渲染成空方框',
      );
      final subtitle = tester.widget<Text>(find.text('116 kcal / 100g').last);
      expect(subtitle.style?.fontFamily, 'PlatformCjk');
    });
  });

  group('D55 分析按钮的**在场契约**（审看结论：不隐藏，登记待裁决）', () {
    // 审看曾把它当缺陷（在途重复、有候选再点会替换已改草稿）并试过隐藏，
    // 回归当场证伪：`food_scan_bruteforce_test` 的「识别在途连点 9 次不得重入」
    // 正是拿它当探针，另有 6 条视觉/流程判据依赖它在有候选时仍可点。按
    // 「不放宽测试、不夹带语义变化」收回 —— 这一组把**收回后的契约**钉住：
    // 按钮在有图的三态都在场，反重入由 `_interactionBusy` 保证（连点不重发）。
    testWidgets('识别在途：按钮在场且禁用，连点 3 次不重发', (tester) async {
      final provider = _CountingProvider();
      await pumpPage(tester, provider: provider);
      picker.next = SelectedMealImage(
        bytes: Uint8List.fromList([1]),
        source: MealImageSource.camera,
      );
      await tester.tap(find.byKey(const Key('scan-camera')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byKey(const Key('scan-recognizing')), findsOneWidget);
      expect(find.byKey(const Key('scan-analyze')), findsOneWidget);
      // `LfPrimaryButton` 的 key 落在内层 `FilledButton`（`ButtonStyleButton`）
      // 上（文件头「key 只落内层」）——descendant 不含自身，直接按 key 取。
      final button = tester.widget<ButtonStyleButton>(
        find.byKey(const Key('scan-analyze')),
      );
      expect(button.onPressed, isNull, reason: '在途禁用');
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byKey(const Key('scan-analyze')));
        await tester.pump();
      }
      expect(provider.calls, 1, reason: '连点不得重入、不得重复发送');
    });

    testWidgets('已有候选：按钮在场（既有重分析入口），文案改为「重新分析」', (tester) async {
      await pumpPage(tester);
      await takePhoto(tester);

      expect(find.byKey(const Key('cta-confirm-scan')), findsOneWidget);
      expect(find.byKey(const Key('scan-analyze')), findsOneWidget);
      expect(find.byKey(const Key('cta-rescan')), findsOneWidget);
      // 2026-10-15 用户批准的裁决 ②：在场契约不变（反重入探针与 6 条判据
      // 依赖它），只把文案改成它真实做的事——已有候选时再点会重发 AI 调用
      // 并替换当前草稿，那就写「重新分析」。
      expect(
        find.descendant(
          of: find.byKey(const Key('scan-analyze')),
          matching: find.text('重新分析'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('无候选（失败/首次）：文案仍是「使用 AI 分析餐食」', (tester) async {
      await pumpPage(tester, provider: _FailingProvider());
      await takePhoto(tester);

      expect(
        find.descendant(
          of: find.byKey(const Key('scan-analyze')),
          matching: find.text('使用 AI 分析餐食'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('分析失败：按钮仍可用（重试路径）', (tester) async {
      await pumpPage(tester, provider: _FailingProvider());
      await takePhoto(tester);

      final button = tester.widget<ButtonStyleButton>(
        find.byKey(const Key('scan-analyze')),
      );
      expect(button.onPressed, isNotNull);
    });
  });
}

// ── 夹具 ──────────────────────────────────────────────────────────────

final class _Ids implements IdGenerator {
  int _v = 0;

  @override
  String next() => 'st-${_v++}';
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
        path: '/private/st.jpg',
        width: image.width,
        height: image.height,
        byteLength: image.bytes.length,
      );
}

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
            proteinGrams: 1,
            carbsGrams: 10,
            fatGrams: 1,
          ),
        ),
      ],
      warnings: const [],
      mealNotes: null,
    );
  }
}

/// 计数版：断言「连点不重发」。
final class _CountingProvider implements MealRecognitionProvider {
  int calls = 0;
  final _never = Completer<MealEstimateDraft>();

  @override
  Future<MealEstimateDraft> recognize(
    PreparedMealImage image, {
    MealRecognitionCancellationToken? cancellationToken,
  }) {
    calls++;
    return _never.future;
  }
}

final class _FailingProvider implements MealRecognitionProvider {
  @override
  Future<MealEstimateDraft> recognize(
    PreparedMealImage image, {
    MealRecognitionCancellationToken? cancellationToken,
  }) async => throw StateError('provider down');
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
