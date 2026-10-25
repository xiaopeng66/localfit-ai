import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/features/food_scan/application/local_food_search.dart';
import 'package:localfit_ai/features/food_scan/application/prepare_meal_image.dart';
import 'package:localfit_ai/features/food_scan/application/recognize_confirmed_meal_image.dart';
import 'package:localfit_ai/features/food_scan/application/resolve_meal_scan_candidates.dart';
import 'package:localfit_ai/features/food_scan/domain/meal_estimate.dart';
import 'package:localfit_ai/features/food_scan/domain/meal_image.dart';
import 'package:localfit_ai/features/food_scan/presentation/chat_message_ui.dart';
import 'package:localfit_ai/features/food_scan/presentation/food_scan_page.dart';
import 'package:localfit_ai/features/nutrition/domain/food_record.dart';

/// 拍照页的对话式状态行（docs/21 §5.4）。
///
/// 只锁「气泡何时出现」这条规则：
/// - 空闲不出现（不占首屏）；
/// - 识别中有加载气泡，且不复述状态卡片自己的文案（同一句说两遍是噪音）；
/// - 识别成功后转为「请确认结果」；
/// - 识别失败时**不**出现「请确认结果」（不能一边报错一边催确认）——
///   包括「候选仍在屏幕上、错误来自另一次识别」这种状态：剩余照片分析失败时
///   餐前候选不会被清掉，若不看 `_error` 就会一边报错一边催确认。
void main() {
  late _Picker picker;
  late _Store store;
  late PrepareMealImage prepare;

  setUp(() {
    picker = _Picker();
    store = _Store();
    prepare = PrepareMealImage(
      picker: picker,
      processor: const _Processor(),
      store: store,
    );
  });

  Future<void> pumpWithProvider(
    WidgetTester tester,
    MealRecognitionProvider provider, {
    LocalFoodSearch foodSearch = const _FoodSearch(),
    ResolveMealScanCandidates? resolver,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FoodScanPage(
          prepareMealImage: prepare,
          recognizeConfirmedMealImage: RecognizeConfirmedMealImage(
            provider: provider,
          ),
          resolveMealScanCandidates:
              resolver ?? ResolveMealScanCandidates(foodSearch: foodSearch),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pickAndAnalyze(WidgetTester tester) async {
    // P10（需求 37）：拍照直通——点 `scan-camera` 选完图后识别**自动开始**，
    // 不再有「点扫描钮」这一步。识别进行中屏幕上有永不停止的
    // `CircularProgressIndicator`，这里只能 `pump` 不能 `pumpAndSettle`。
    picker.next = SelectedMealImage(
      bytes: Uint8List.fromList([1, 2, 3]),
      source: MealImageSource.camera,
    );
    await tester.tap(find.byKey(const Key('scan-camera')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  /// 把列表滚回顶部。
  ///
  /// 页面顶部的对话气泡会随列表变长而滚出视口，`scrollUntilVisible` 对
  /// **尚未构建**的元素也无能为力（懒 ListView 下 finder 直接匹配不到，
  /// 报 `Bad state: No element`），所以断言顶部气泡前要显式回顶。
  ///
  /// 用 `pump` 而不是 `pumpAndSettle`：识别中屏幕上有个永不停止的
  /// `CircularProgressIndicator`，`pumpAndSettle` 会一直等它停下而超时。
  Future<void> scrollToTop(WidgetTester tester) async {
    await tester.drag(find.byType(ListView).first, const Offset(0, 2000));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('空闲时没有对话气泡', (tester) async {
    await pumpWithProvider(tester, _BlockingProvider(Completer()));

    expect(find.byType(ChatMessageUI), findsNothing);
  });

  testWidgets('识别中出现加载气泡，且不复述状态卡片文案', (tester) async {
    final blocker = Completer<MealEstimateDraft>();
    await pumpWithProvider(tester, _BlockingProvider(blocker));
    await pickAndAnalyze(tester);

    final bubble = find.byKey(const Key('scan-chat-analyzing'));
    // 气泡在列表顶部；pickAndAnalyze 会滚到下方的识别按钮，顶部的气泡
    // 因此可能已滚出视口（懒构建下 finder 匹配不到）。断言前滚回顶部。
    await scrollToTop(tester);
    expect(bubble, findsOneWidget);
    expect(
      find.descendant(
        of: bubble,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );

    final bubbleText = tester
        .widgetList<Text>(
          find.descendant(of: bubble, matching: find.byType(Text)),
        )
        .map((widget) => widget.data)
        .whereType<String>()
        .join(' | ');
    expect(bubbleText, contains('正在分析这张照片'));
    expect(
      bubbleText,
      isNot(contains('正在发送并分析当前图片')),
      reason: '气泡不得复述识别卡片正文（会出现两遍同样的句子）',
    );

    blocker.complete(_draft());
    await tester.pumpAndSettle();
  });

  testWidgets('识别完成后气泡转为「请确认结果」', (tester) async {
    final blocker = Completer<MealEstimateDraft>();
    await pumpWithProvider(tester, _BlockingProvider(blocker));
    await pickAndAnalyze(tester);
    await scrollToTop(tester);
    expect(
      find.byKey(const Key('scan-chat-analyzing'), skipOffstage: false),
      findsOneWidget,
    );

    blocker.complete(_draft());
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('scan-chat-analyzing'), skipOffstage: false),
      findsNothing,
    );
    await scrollToTop(tester);
    expect(find.byKey(const Key('scan-chat-candidates')), findsOneWidget);
  });

  testWidgets('识别失败时不出现「请确认结果」气泡', (tester) async {
    final blocker = Completer<MealEstimateDraft>();
    await pumpWithProvider(tester, _BlockingProvider(blocker));
    await pickAndAnalyze(tester);

    blocker.completeError(StateError('boom'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('scan-chat-candidates')),
      findsNothing,
      reason: '出错时不能一边报错一边催用户确认结果',
    );
  });

  testWidgets('剩余照片分析失败时，屏幕上残留的候选也不催确认', (tester) async {
    // 失败发生在**另一次**识别上：餐前候选不会被清掉（`_recognize` 只清自己那份
    // 草案），所以「候选存在 + 有错误」是真实可达状态。只按候选是否为空判断，
    // 就会在报错的同时催用户确认一份已经算不全的结果。
    // 视口放高：ListView 懒构建，矮视口下「选择剩余餐食照片」根本不会进树。
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpWithProvider(tester, _FailAfterFirstProvider());
    await pickAndAnalyze(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('scan-chat-candidates')), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const Key('scan-leftover-gallery')),
      600,
      scrollable: find.byType(Scrollable).first,
    );
    // scrollUntilVisible 只保证「已构建」，不保证完全可见：按钮若只露一半，
    // tap 会打到空白处（warnIfMissed）而静默不触发，下一行就会 No element。
    await tester.ensureVisible(find.byKey(const Key('scan-leftover-gallery')));
    picker.next = SelectedMealImage(
      bytes: Uint8List.fromList([2]),
      source: MealImageSource.gallery,
    );
    await tester.tap(find.byKey(const Key('scan-leftover-gallery')));
    await tester.pumpAndSettle();

    // 剩余预览卡是 4:3（≈651dp 高），把分析键顶出懒 ListView 的构建范围；
    // 先滚到它再取，否则 finder 匹配不到（skipOffstage 只管路由，不管未构建）。
    await tester.scrollUntilVisible(
      find.byKey(const Key('scan-leftover-analyze')),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.byKey(const Key('scan-leftover-analyze')));
    // 2026-10-03：`scan-leftover-analyze` 从裸 `OutlinedButton` 收敛到 §3.8
    // B3 `LfPillButton`（`muted` 档），实现类型变为 `TextButton`；断言要的是
    // 「这个键可点并触发分析」，取 M3 按钮公共基类后强度不变。
    final analyzeLeftover = tester.widget<ButtonStyleButton>(
      find.byKey(const Key('scan-leftover-analyze'), skipOffstage: false),
    );
    analyzeLeftover.onPressed!();
    await tester.pumpAndSettle();

    // 两条断言各在自己会被构建的滚动位置取：气泡在列表顶部、错误卡片在最底部，
    // 懒构建下它们不会同时在树里。先滚到底确认「确实进了出错状态」，
    // 再滚回顶部确认「顶部那块真的没有催确认气泡」——反过来先断言气泡不存在，
    // 就可能只是因为它没被构建而假通过。
    await tester.drag(find.byType(ListView), const Offset(0, -1200));
    await tester.pumpAndSettle();
    expect(
      find.text('剩余餐食识别未能完成，请稍后重试。'),
      findsOneWidget,
      reason: '先确认这条路径真的走到了出错状态',
    );

    await tester.drag(find.byType(ListView), const Offset(0, 1200));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('scan-chat-candidates')),
      findsNothing,
      reason: '剩余照片分析失败时，餐前候选仍在屏幕上，但不能再催确认',
    );
  });

  // 守卫里 `_successMessage == null` 那一半没有测试覆盖：全文件只有一处给它赋值
  // （保存成功，food_scan_page.dart:690），而那一处与清空两份候选草案在同一个
  // setState 里完成，因此「已保存成功 + 候选仍在」不可达。留着它是防御性写法，
  // 不写测试去凑——凑出来的测试只会锁住一个不存在的状态。
}

MealEstimateDraft _draft() => const MealEstimateDraft(
  items: [
    MealEstimateItem(
      name: '米饭',
      estimatedGrams: 200,
      gramsRange: GramRange(min: 150, max: 250),
      confidence: 0.8,
      ingredients: [],
      needsConfirmation: false,
      questions: [],
      cookingMethod: '蒸煮',
      nutrition: MealEstimateNutrition(
        kcal: 232,
        proteinGrams: 5.2,
        carbsGrams: 51.8,
        fatGrams: 0.6,
      ),
    ),
  ],
  warnings: [],
  mealNotes: null,
);

final class _BlockingProvider implements MealRecognitionProvider {
  _BlockingProvider(this.completer);

  final Completer<MealEstimateDraft> completer;

  @override
  Future<MealEstimateDraft> recognize(
    PreparedMealImage image, {
    MealRecognitionCancellationToken? cancellationToken,
  }) => completer.future;
}

/// 首次识别成功（留下候选），之后的识别一律失败——用于复现
/// 「候选还在屏幕上、错误来自下一次识别」这种状态。
final class _FailAfterFirstProvider implements MealRecognitionProvider {
  int calls = 0;

  @override
  Future<MealEstimateDraft> recognize(
    PreparedMealImage image, {
    MealRecognitionCancellationToken? cancellationToken,
  }) async {
    if (calls++ == 0) return _draft();
    throw StateError('leftover recognition failed');
  }
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
  final deleted = <PreparedMealImage>[];
  int _count = 0;

  @override
  Future<void> clearStale() async {}

  @override
  Future<void> clearAll() async {}

  @override
  Future<void> delete(PreparedMealImage image) async => deleted.add(image);

  @override
  Future<PreparedMealImage> save(ProcessedMealImage image) async =>
      PreparedMealImage(
        path: '/tmp/scan-conversation-${_count++}.jpg',
        width: image.width,
        height: image.height,
        byteLength: image.bytes.length,
      );
}

final class _FoodSearch implements LocalFoodSearch {
  const _FoodSearch();

  @override
  Future<List<FoodRecord>> search(String query, {int limit = 30}) async =>
      const [];
}
