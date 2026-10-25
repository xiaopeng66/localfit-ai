/// 拍照识餐页重建（docs/21 §5.4）的验收测试。
///
/// 三块内容：
/// 1. **§5.4 测试 Key 契约**——19 个键逐个按其语义定位，配防空转守卫
///    （先断言前置内容真的渲染了，再断言键存在）。
/// 2. **几何探针**——320dp × 1.0/1.5/2.0× 字号无横向溢出；480dp 矮视口
///    下固定底部 CTA 不得遮挡内容、自身可点。
/// 3. **营养拆分占比回归**——旧实现把「该项热量 ÷ 该项热量」当占比，三条
///    横条恒为满格；这里按 4/4/9 反推的宏量占比锁死，并做隔离变异红证
///    （见文件尾的 mutation 注记）。
///
/// 测试按 docs/21 §5.4 的两面结构组织：只读结果面（默认）与 `cta-edit-items`
/// 进入的候选编辑面互斥渲染。
library;

import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/fixed_bottom_primary_action.dart';
import 'package:localfit_ai/app/design/widgets/lf_progress_bar.dart';
import 'package:localfit_ai/app/design/widgets/lf_top_bar.dart';
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

import 'scan_test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('拍照识餐 · §5.4 测试 Key 契约', () {
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
      bool withImage = true,
      bool withResult = true,
    }) async {
      tester.view.physicalSize = const Size(900, 1600);
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
              provider: _Provider(),
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
      if (!withImage) return;

      picker.next = SelectedMealImage(
        bytes: Uint8List.fromList([1]),
        source: MealImageSource.camera,
      );
      // P10 拍照直通：scan-camera 选完图自动开始识别。withResult=false 的
      // 用例（空态/纯预览）在这里就返回——注意此时识别已在后台开跑，
      // 断言「无候选」的用例必须在返回前等识别**落定**，否则读到的是
      // 进行中的瞬态。
      await tester.tap(find.byKey(const Key('scan-camera')));
      if (!withResult) {
        await _pumpRecognitionSettled(tester);
        return;
      }
      await _pumpRecognitionSettled(tester);
    }

    testWidgets('顶栏：scan-back / scan-title / cta-rescan 三件齐', (tester) async {
      await pumpPage(tester, withImage: false, withResult: false);
      // 防空转：页面骨架先确认在。
      expect(find.text('拍照识餐'), findsOneWidget);
      expect(find.byKey(const Key('scan-back')), findsOneWidget);
      expect(find.byKey(const Key('scan-title')), findsOneWidget);
      expect(find.byKey(const Key('cta-rescan')), findsOneWidget);
      // 触达：圆形钮视觉 36dp，但命中盒必须 ≥44dp（§5.8.3）。
      final back = tester.getRect(find.byKey(const Key('scan-back')));
      expect(back.width, greaterThanOrEqualTo(44));
      expect(back.height, greaterThanOrEqualTo(44));
      // 几何：视觉圆 36dp 由内部 InkWell 承载。
      final ink = find.descendant(
        of: find.byKey(const Key('scan-back')),
        matching: find.byType(InkWell),
      );
      expect(tester.getRect(ink.first).width, 36);
    });

    testWidgets('照片卡：4:3 稳定约束 + scan-photo-preview / scan-photo-meta', (
      tester,
    ) async {
      await pumpPage(tester, withResult: false);
      // 防空转：照片卡在屏。
      expect(find.byKey(const Key('scan-preview')), findsOneWidget);
      final photo = tester.getRect(find.byKey(const Key('scan-photo-preview')));
      expect(photo.width / photo.height, closeTo(4 / 3, 0.01));
      expect(find.byKey(const Key('scan-photo-meta')), findsOneWidget);
      // 诚实规则（§6.1）：PreparedMealImage 没有时间戳，覆盖条不得编时间，
      // 只能写真实存在的图像参数。
      final metaText = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const Key('scan-photo-meta')),
          matching: find.byType(Text),
        ),
      );
      expect(metaText.data, contains('已拍摄'));
      expect(metaText.data, isNot(contains('12:15')));
      expect(metaText.data, contains('100 × 80'));
      // 重拍入口在照片卡上。
      expect(find.byKey(const Key('cta-retake')), findsOneWidget);
      // 压在照片上的两个动作取 §3.8 的 overlay 档（`拍照识餐.html:327` 的
      // `cta-retake` 是 card/90% 底 + foreground 字的带字胶囊），不是写死的
      // 黑底白字——后者在暗色主题下与主题给的取色不一致。
      expect(
        tester
            .widget<TextButton>(find.byKey(const Key('cta-retake')))
            .style!
            .backgroundColor!
            .resolve(<WidgetState>{}),
        LfSemanticColors.light.card.withValues(alpha: 0.9),
      );
      expect(
        tester.widget<LfCircleIconButton>(
          find.byKey(const Key('scan-discard')),
        ),
        isNotNull,
        reason: '丢弃照片 = §3.8 B4 的圆形图标钮（裸 IconButton 走 M3 基线）',
      );
    });

    testWidgets('识别结果面：结果卡 / 食材 / 拆分 / 建议 / 披露行', (tester) async {
      await pumpPage(tester);
      // 防空转：识别真的完成了（有候选）。
      expect(find.textContaining('米饭'), findsWidgets);
      expect(find.byKey(const Key('scan-result-overview')), findsOneWidget);
      expect(find.byKey(const Key('scan-result-name')), findsOneWidget);
      expect(find.byKey(const Key('scan-result-source')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('scan-result-overview')),
          matching: find.byKey(const Key('scan-result-confidence')),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('scan-result-kcal')), findsOneWidget);
      // 「修正」= B3 的 `soft` 档（浅品牌底 + 品牌字），不是裸
      // `TextButton.icon` + 手写底色。Round7 A 起浅品牌底是 `--brand-soft`
      // 的有效值 `#ECFBF5`（`refinement.css:1`；`styles.css:7` 的 `#E4F6ED`
      // 已被它覆盖），旧稿的 `mint-100`（#D2F5E6）不再参与。
      expect(
        tester
            .widget<TextButton>(find.byKey(const Key('cta-edit-items')))
            .style!
            .backgroundColor!
            .resolve(<WidgetState>{}),
        LfColors.brandSoft(Brightness.light),
      );
      // 拆分与建议是独立卡（不是卡中卡）。
      expect(find.byKey(const Key('scan-breakdown-total')), findsOneWidget);
      for (final macro in ['protein', 'carbs', 'fat']) {
        expect(
          find.byKey(Key('scan-breakdown-$macro')),
          findsOneWidget,
          reason: '缺 scan-breakdown-$macro',
        );
      }
      // 建议卡是只读面最后一张卡：懒 ListView 下不滚到它就没被构建。
      await tester.scrollUntilVisible(
        find.byKey(const Key('scan-ai-advice')),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const Key('scan-ai-advice')), findsOneWidget);
      // 披露行常驻（有照片时），且写明目的地（未接线 → 通用文案）。
      expect(find.byKey(const Key('scan-send-disclosure')), findsOneWidget);
      final disclosure = tester.widget<Text>(
        find.byKey(const Key('scan-send-disclosure')),
      );
      expect(disclosure.data, contains('见设置'));
      // 「修正」进入编辑面（§5.4 交互）。
      expect(find.byKey(const Key('cta-edit-items')), findsOneWidget);
      await enterEditor(tester);
      expect(find.byKey(const Key('scan-candidate-card')), findsOneWidget);
      // 两面互斥：进了编辑面，只读结果卡必须收起。
      expect(find.byKey(const Key('scan-result-overview')), findsNothing);
    });

    testWidgets('固定底部 cta-confirm-scan：有候选才可用，且可点', (tester) async {
      await pumpPage(tester);
      final cta = find.byKey(const Key('cta-confirm-scan'));
      // 防空转：CTA 必须真的挂载。
      expect(cta, findsOneWidget);
      final rect = tester.getRect(cta);
      final viewHeight =
          tester.view.physicalSize.height / tester.view.devicePixelRatio;
      // 贴底（含安全区）且完整可见。
      expect(rect.bottom, lessThanOrEqualTo(viewHeight));
      expect(rect.width, greaterThan(300));
      // 点心命中：不被别的层截走（「看得见点不到」缺陷类）。
      final renderCta = tester.renderObject<RenderBox>(cta);
      final hit = tester.hitTestOnBinding(rect.center);
      bool insideCta(RenderObject target) {
        RenderObject? node = target;
        while (node != null) {
          if (identical(node, renderCta)) return true;
          node = node.parent;
        }
        return false;
      }

      // 命中路径里可能有 TextSpan（RenderParagraph 加进来的），只看渲染对象。
      expect(
        hit.path.any((entry) {
          final target = entry.target;
          return target is RenderObject && insideCta(target);
        }),
        isTrue,
        reason: '确认键中心被别的层挡住（看得见点不到）',
      );
    });

    testWidgets('无候选时 cta-confirm-scan 禁用（没有可确认的东西）', (tester) async {
      // P10 拍照直通后「选了图但没识别」这个状态不存在了（选图即识别）。
      // 没有可确认东西的稳态 = 一张图都没选（空态）。
      await pumpPage(tester, withImage: false);
      final cta = tester.widget<FilledButton>(
        find.byKey(const Key('cta-confirm-scan')),
      );
      expect(cta.onPressed, isNull, reason: '没有识别结果不得亮确认键');
    });
  });

  group('拍照识餐 · 几何探针', () {
    testWidgets('320dp × 1.0/1.5/2.0× 字号：结果面无横向溢出', (tester) async {
      final overflowPixels = <String, double>{};
      for (final scale in const [1.0, 1.5, 2.0]) {
        final key = '${scale}x';
        // 两轮之间必须卸载：`pumpWidget` 对同位同型的 widget 会**复用 State**，
        // 不卸载的话上一轮选中的照片会带进下一轮，页面根本不是空态。
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 1));
        final database = AppDatabase(NativeDatabase.memory());
        addTearDown(database.close);
        final meals = _seededMeals(database);
        final picker = _Picker()..next = _image;
        await tester.pumpWidget(
          MaterialApp(
            home: FoodScanPage(
              prepareMealImage: PrepareMealImage(
                picker: picker,
                processor: const _Processor(),
                store: _TemporaryStore(),
              ),
              recognizeConfirmedMealImage: RecognizeConfirmedMealImage(
                provider: _Provider(),
              ),
              resolveMealScanCandidates: ResolveMealScanCandidates(
                foodSearch: const _FoodSearch(),
              ),
              mealRepository: meals,
              now: DateTime(2026, 9, 9, 12),
            ),
          ),
        );
        // §5.8.3 的「320dp」指**逻辑**宽度：320 物理 × DPR 1。
        tester.view.physicalSize = const Size(320, 800);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('scan-camera')));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byKey(const Key('scan-analyze')),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.byKey(const Key('scan-analyze')));
        await tester.pumpAndSettle();
        // 滚到列表底，让最深的卡也参与布局（懒构建）。
        for (var i = 0; i < 12; i++) {
          await tester.drag(find.byType(ListView), const Offset(0, -400));
          await tester.pumpAndSettle();
          if (find.byKey(const Key('scan-ai-advice')).evaluate().isNotEmpty) {
            break;
          }
        }
        overflowPixels[key] = await _overflowAt(tester);
      }
      for (final entry in overflowPixels.entries) {
        expect(
          entry.value,
          0,
          reason: '320dp × ${entry.key} 字号下横向溢出 ${entry.value}px',
        );
      }
    });

    testWidgets('480dp 矮视口：内容不得画进固定底部 CTA 条之下', (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final meals = _seededMeals(database);
      final picker = _Picker()..next = _image;
      await tester.pumpWidget(
        MaterialApp(
          home: FoodScanPage(
            prepareMealImage: PrepareMealImage(
              picker: picker,
              processor: const _Processor(),
              store: _TemporaryStore(),
            ),
            recognizeConfirmedMealImage: RecognizeConfirmedMealImage(
              provider: _Provider(),
            ),
            resolveMealScanCandidates: ResolveMealScanCandidates(
              foodSearch: const _FoodSearch(),
            ),
            mealRepository: meals,
            now: DateTime(2026, 9, 9, 12),
          ),
        ),
      );
      tester.view.physicalSize = const Size(400, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('scan-camera')));
      await _pumpRecognitionSettled(tester);

      // 遮挡线 = 固定 CTA 条的顶边。
      final barRect = tester.getRect(find.byType(FixedBottomPrimaryAction));
      final barrier = barRect.top;

      // 滚到底后，滚动体子树内的最深可见叶子必须仍在遮挡线之上。
      // 只在滚动体子树内走：Scaffold 的 FAB 过渡槽是零尺寸空叶子，整页走
      // 会把它误判成最深内容（nutrition_subtab_occlusion_test 的教训）。
      var deepest = 0.0;
      var measured = 0;
      for (final element
          in find
              .descendant(
                of: find.byType(ListView),
                matching: find.byType(Scrollable),
              )
              .evaluate()) {
        final viewportBottom = barrier;
        void walk(Element node) {
          final renderObject = node.renderObject;
          if (renderObject is RenderBox && renderObject.hasSize) {
            final rect =
                renderObject.localToGlobal(Offset.zero) & renderObject.size;
            final bottom = rect.bottom < viewportBottom
                ? rect.bottom
                : viewportBottom;
            if (bottom > deepest) deepest = bottom;
          }
          node.visitChildren(walk);
        }

        element.visitChildren(walk);
        measured++;
      }
      expect(measured, greaterThan(0), reason: '没找到可滚动体：断言会空转');
      expect(
        deepest,
        lessThanOrEqualTo(barrier + 0.5),
        reason: '内容最深叶子 $deepest 越过 CTA 条遮挡线 $barrier',
      );
    });
  });

  group('拍照识餐 · 营养拆分占比（回归 2026-09-30 修复的恒满缺陷）', () {
    testWidgets('三条横条按 4/4/9 反推的宏量占比取值，三项合计 100%', (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final meals = _seededMeals(database);
      final picker = _Picker()..next = _image;
      await tester.pumpWidget(
        MaterialApp(
          home: FoodScanPage(
            prepareMealImage: PrepareMealImage(
              picker: picker,
              processor: const _Processor(),
              store: _TemporaryStore(),
            ),
            recognizeConfirmedMealImage: RecognizeConfirmedMealImage(
              provider: _Provider(),
            ),
            resolveMealScanCandidates: ResolveMealScanCandidates(
              foodSearch: const _FoodSearch(),
            ),
            mealRepository: meals,
            now: DateTime(2026, 9, 9, 12),
          ),
        ),
      );
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('scan-camera')));
      await _pumpRecognitionSettled(tester);
      await tester.scrollUntilVisible(
        find.byKey(const Key('scan-breakdown-total')),
        400,
        scrollable: find.byType(Scrollable).first,
      );

      // 真值：米饭 180g → 蛋白 4.68g / 碳水 46.62g / 脂肪 0.54g
      //  → 4/4/9 热量 19 / 186 / 5 → 占比 9% / 90% / 2%。
      double ratioOf(String macro) => tester
          .widget<LfProgressBar>(
            find
                .descendant(
                  of: find.byKey(Key('scan-breakdown-$macro')),
                  matching: find.byType(LfProgressBar),
                )
                .first,
          )
          .value;

      final protein = ratioOf('protein');
      final carbs = ratioOf('carbs');
      final fat = ratioOf('fat');
      // 缺陷形态：恒为 1.0（满格）。这里直接排除满格并锁真值。
      expect(protein, isNot(1.0), reason: '蛋白条不应恒为满格');
      expect(carbs, isNot(1.0), reason: '碳水条不应恒为满格');
      expect(protein, closeTo(19 / 210, 0.01));
      expect(carbs, closeTo(186 / 210, 0.01));
      expect(fat, closeTo(5 / 210, 0.01));
      expect(
        protein + carbs + fat,
        closeTo(1.0, 0.005),
        reason: '三项占比之和必须为 100%',
      );
      // 「总 N kcal」与三项之和一致（同一口径，不给用户两个总数）。
      final totalText = tester.widget<Text>(
        find.byKey(const Key('scan-breakdown-total')),
      );
      expect(totalText.data, '总 210 kcal');
    });
  });
}

// ── 溢出探针 ─────────────────────────────────────────────────────────────

Future<double> _overflowAt(WidgetTester tester) async {
  var maxOverflow = 0.0;
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    final match = RegExp(r'overflowed by ([\d.]+) pixels')
        .firstMatch(details.toString());
    if (match != null) {
      maxOverflow = double.parse(match.group(1)!);
      return;
    }
    previous?.call(details);
  };
  try {
    await tester.pump(const Duration(milliseconds: 1));
  } finally {
    FlutterError.onError = previous;
  }
  return maxOverflow;
}

// ── 数据桩 ───────────────────────────────────────────────────────────────

MealRepository _seededMeals(AppDatabase database) => MealRepository(
  database: database,
  idGenerator: _Ids(),
  clock: FixedAppClock(DateTime(2026, 9, 9, 12)),
);

final _image = SelectedMealImage(
  bytes: Uint8List.fromList([1]),
  source: MealImageSource.gallery,
);

final class _Ids implements IdGenerator {
  int _value = 0;

  @override
  String next() => 'spec-${_value++}';
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
  final deleted = <PreparedMealImage>[];

  @override
  Future<void> clearStale() async {}

  @override
  Future<void> clearAll() async {}

  @override
  Future<void> delete(PreparedMealImage image) async => deleted.add(image);

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

/// 隔离变异红证（verify 后已复原）：
/// 把 `ScanNutritionBreakdown._totals` 里 `ratio(int part)` 的分母从
/// `totalKcal` 改回 `part`（即复刻旧缺陷），protein/carbs 两条 value 变 1.0，
/// 本文件的「不应恒为满格」与 `closeTo(19/210)` 断言全红；
/// 再把 `expect(protein, isNot(1.0))` 删掉单独跑，`closeTo` 仍红——
/// 证明断言不是靠恒真条件短路。

/// P10 拍照直通：识别在真实异步间隙推进；等它落定（草稿卡/结果面/错误
/// 任一出现）再 settle。识别结束态没有常驻动画，settle 不会超时。
Future<void> _pumpRecognitionSettled(WidgetTester tester) async {
  for (var index = 0; index < 25; index++) {
    final draft = find.byKey(const Key('scan-draft-card')).evaluate();
    final overview = find.byKey(const Key('scan-result-overview')).evaluate();
    final error = find.byKey(const Key('scan-error')).evaluate();
    final preview = find.byKey(const Key('scan-preview')).evaluate();
    if (draft.isNotEmpty ||
        overview.isNotEmpty ||
        error.isNotEmpty ||
        preview.isNotEmpty) {
      break;
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
}
