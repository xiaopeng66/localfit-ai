import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/design/widgets/app_button_states.dart';
import 'package:localfit_ai/app/design/widgets/design_card.dart';
import 'package:localfit_ai/features/food_scan/application/meal_scan_candidate.dart';
import 'package:localfit_ai/features/food_scan/domain/meal_estimate.dart';
import 'package:localfit_ai/features/food_scan/presentation/scan_candidate_editor.dart';
import 'package:localfit_ai/features/nutrition/domain/food_record.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';

void main() {
  testWidgets(
    'edits grams, replaces food, and removes only an in-memory candidate',
    (tester) async {
      final rice = _food(id: 'rice', name: '米饭', kcal: 116);
      final noodles = _food(id: 'noodles', name: '面条', kcal: 300);
      await tester.pumpWidget(_CandidateHarness(foods: [rice, noodles]));

      expect(find.textContaining('本地合计 209 kcal'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('scan-candidate-grams-0')),
        '200',
      );
      await tester.pump();
      expect(find.textContaining('本地合计 232 kcal'), findsOneWidget);

      await tester.tap(find.byKey(const Key('scan-candidate-search-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('面条'));
      await tester.pumpAndSettle();
      expect(find.text('本地食物：面条'), findsOneWidget);
      expect(find.textContaining('本地合计 600 kcal'), findsOneWidget);

      await tester.tap(find.byKey(const Key('scan-candidate-remove-0')));
      await tester.pump();
      expect(find.text('没有保留的候选项；请重新识别或改为手动记餐。'), findsOneWidget);
      expect(find.textContaining('本地合计 0 kcal'), findsOneWidget);
      expect(find.text('确认后将保存到本机并计入今日统计；保存成功后会清理本次临时图片。'), findsOneWidget);
    },
  );

  testWidgets('卡壳与卡内子块走共享件（§3.1：DesignCard + MutedBlock）', (tester) async {
    final rice = _food(id: 'rice', name: '米饭', kcal: 116);
    await tester.pumpWidget(_CandidateHarness(foods: [rice]));

    // 卡壳 = `DesignCard`（原裸 `Card`）。
    expect(find.byType(DesignCard), findsWidgets);
    // 卡内子块 = `MutedBlock`（原手写「1px outlineVariant + 12 圆角」描边盒）。
    // 设计稿的卡内子块一律 muted 底、不叠第二层描边；换回手写容器会在这里红
    // ——「点得到 / 文字在」的行为断言抓不住这一层。
    expect(
      find.descendant(
        of: find.byType(MutedBlock),
        matching: find.byKey(const Key('scan-candidate-grams-0')),
      ),
      findsOneWidget,
      reason: '候选条目子块必须由 MutedBlock 承载',
    );
  });

  testWidgets('shows structured recognition evidence on demand', (
    tester,
  ) async {
    final rice = _food(id: 'rice', name: '米饭', kcal: 116);
    await tester.pumpWidget(_CandidateHarness(foods: [rice]));

    expect(find.byKey(const Key('scan-analysis-sheet')), findsNothing);
    await tester.tap(find.byKey(const Key('scan-candidate-analysis-open')));
    await tester.pumpAndSettle();

    final sheet = find.byKey(const Key('scan-analysis-sheet'));
    expect(sheet, findsOneWidget);
    expect(
      find.descendant(of: sheet, matching: find.text('分析过程')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sheet, matching: find.textContaining('结构化识别依据')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sheet, matching: find.textContaining('不会展示模型内部思考')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sheet, matching: find.text('米饭')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: sheet,
        matching: find.textContaining('估算份量：180g（140–220g）'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sheet, matching: find.textContaining('置信度：80%')),
      findsOneWidget,
    );
  });

  testWidgets(
    'leaves unresolved candidates non-nutritive until the user selects food',
    (tester) async {
      final rice = _food(id: 'rice', name: '米饭', kcal: 116);
      final draft = MealScanCandidateDraft(
        items: [
          MealScanCandidate.fromEstimate(
            _estimate('未知食物'),
            const LocalFoodMatch(
              status: LocalFoodMatchStatus.unmatched,
              suggestions: [],
            ),
          ),
        ],
        slot: MealSlot.lunch,
        notes: null,
        warnings: const [],
      );
      await tester.pumpWidget(_CandidateHarness(foods: [rice], draft: draft));

      expect(find.text('尚未匹配本地食物，无法计算营养。'), findsOneWidget);
      expect(find.textContaining('本地合计 0 kcal'), findsOneWidget);
      expect(find.textContaining('本地食物：'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('scan-candidate-confirm')),
            )
            .onPressed,
        isNull,
      );

      await tester.tap(find.byKey(const Key('scan-candidate-search-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('米饭'));
      await tester.pumpAndSettle();
      expect(find.text('本地食物：米饭'), findsOneWidget);
      expect(find.textContaining('本地合计 209 kcal'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('scan-candidate-confirm')),
            )
            .onPressed,
        isNotNull,
      );
    },
  );
  testWidgets(
    'discloses the AI-estimated source for an unmatched item that still counts',
    (tester) async {
      final rice = _food(id: 'rice', name: '米饭', kcal: 116);
      final draft = MealScanCandidateDraft(
        items: [
          MealScanCandidate.fromEstimate(
            _estimate(
              '未知食物',
              nutrition: const MealEstimateNutrition(
                kcal: 200,
                proteinGrams: 10,
                carbsGrams: 20,
                fatGrams: 5,
              ),
            ),
            const LocalFoodMatch(
              status: LocalFoodMatchStatus.unmatched,
              suggestions: [],
            ),
          ),
        ],
        slot: MealSlot.lunch,
        notes: null,
        warnings: const [],
      );
      await tester.pumpWidget(_CandidateHarness(foods: [rice], draft: draft));

      // 这一项的 AI 估算确实计入了合计（保存时按它入账），卡片必须如实标注
      // 来源；说成「无法计算营养」会让用户以为它没进合计。
      expect(find.textContaining('本地合计 200 kcal'), findsOneWidget);
      expect(find.text('尚未匹配本地食物，无法计算营养。'), findsNothing);
      expect(
        find.text('尚未匹配本地食物，本项营养暂用 AI 估算（保存时自动收录到本地食物库）。'),
        findsOneWidget,
      );
    },
  );

  testWidgets('克数步进器胶囊：±10g 步进，直接输入保留（docs/21 §3）', (tester) async {
    final rice = _food(id: 'rice', name: '米饭', kcal: 116);
    await tester.pumpWidget(_CandidateHarness(foods: [rice]));

    // 180g 起步（AI 估算）。
    expect(find.textContaining('本地合计 209 kcal'), findsOneWidget);

    await tester.tap(find.byKey(const Key('scan-candidate-grams-plus-0')));
    await tester.pump();
    expect(find.text('190'), findsOneWidget);
    expect(find.textContaining('本地合计 220 kcal'), findsOneWidget);

    await tester.tap(find.byKey(const Key('scan-candidate-grams-minus-0')));
    await tester.pump();
    expect(find.text('180'), findsOneWidget);
    expect(find.textContaining('本地合计 209 kcal'), findsOneWidget);

    // 直接输入仍然有效（规格要求保留）。
    await tester.enterText(
      find.byKey(const Key('scan-candidate-grams-0')),
      '50',
    );
    await tester.pump();
    expect(find.textContaining('本地合计 58 kcal'), findsOneWidget);
  });

  testWidgets('克数非法中间态：不回填 NaN，± 从估算值恢复（docs/21 §3）', (tester) async {
    final rice = _food(id: 'rice', name: '米饭', kcal: 116);
    await tester.pumpWidget(_CandidateHarness(foods: [rice]));

    String gramsText() => tester
        .widget<EditableText>(
          find.descendant(
            of: find.byKey(const Key('scan-candidate-grams-0')),
            matching: find.byType(EditableText),
          ),
        )
        .controller
        .text;

    // 清空输入框 = 正在输入的非法中间态：保留用户输入，不得回写成 "NaN"。
    await tester.enterText(find.byKey(const Key('scan-candidate-grams-0')), '');
    await tester.pump();
    expect(gramsText(), '');

    // 非法字符同理（此前会被回写成 "NaN"，之后每次键入都被重置）。
    await tester.enterText(
      find.byKey(const Key('scan-candidate-grams-0')),
      '1x',
    );
    await tester.pump();
    expect(gramsText(), '1x');

    // ± 必须从 AI 估算值（180g）继续步进，不能被 NaN 卡死。
    await tester.tap(find.byKey(const Key('scan-candidate-grams-plus-0')));
    await tester.pump();
    expect(gramsText(), '190');
    expect(find.textContaining('本地合计 220 kcal'), findsOneWidget);
  });

  testWidgets('saving: 步进按钮禁用（与克数输入同步）', (tester) async {
    final rice = _food(id: 'rice', name: '米饭', kcal: 116);
    await tester.pumpWidget(_CandidateHarness(foods: [rice], saving: true));

    expect(
      tester
          .widget<IconButton>(
            find.byKey(const Key('scan-candidate-grams-plus-0')),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const Key('scan-candidate-grams-minus-0')),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets(
    'conversational correction: rename + grams via sheet, nutrition recomputes',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final rice = _food(id: 'rice', name: '米饭', kcal: 116);
      await tester.pumpWidget(_CandidateHarness(foods: [rice]));

      // 起步 180g → 209 kcal。
      expect(find.textContaining('本地合计 209 kcal'), findsOneWidget);

      // 打开修正 sheet。
      await tester.tap(find.byKey(const Key('scan-candidate-correct-0')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('scan-correction-sheet')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('scan-correction-sheet')),
          matching: find.text('修正识别'),
        ),
        findsOneWidget,
      );

      // 改名。
      await tester.enterText(
        find.byKey(const Key('scan-correction-name')),
        '午餐米饭',
      );
      // 改克数 200g。
      await tester.enterText(
        find.byKey(const Key('scan-correction-grams')),
        '200',
      );
      await tester.pumpAndSettle();

      // 提交。
      await tester.tap(find.byKey(const Key('scan-correction-submit')));
      await tester.pumpAndSettle();

      // sheet 关闭。
      expect(find.byKey(const Key('scan-correction-sheet')), findsNothing);
      // 克数生效、营养重算（200g @ 116 kcal/100g = 232 kcal）。
      expect(find.textContaining('本地合计 232 kcal'), findsOneWidget);
      // 估算名已改。
      expect(find.text('午餐米饭'), findsWidgets);
    },
  );

  testWidgets('saving: 确认按钮图标槽为三点跳动，无转圈（docs/21 §3）', (tester) async {
    final rice = _food(id: 'rice', name: '米饭', kcal: 116);
    await tester.pumpWidget(_CandidateHarness(foods: [rice], saving: true));

    expect(find.text('正在保存到本机…'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('scan-candidate-confirm')),
        matching: find.byType(AppButtonDotsLoader),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('scan-candidate-confirm')),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsNothing,
    );
  });

  testWidgets('scan-candidate-edit opens the conversational correction sheet', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final rice = _food(id: 'rice', name: '米饭', kcal: 116);
    await tester.pumpWidget(_CandidateHarness(foods: [rice]));

    expect(find.byKey(const Key('scan-correction-sheet')), findsNothing);
    await tester.tap(find.byKey(const Key('scan-candidate-edit')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('scan-correction-sheet')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('scan-correction-sheet')),
        matching: find.text('修正识别'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('修正弹层的拒绝原因必须画在弹层里，不能只发被盖住的 snackbar', (tester) async {
    // 同类缺陷回归（2026-10-02）：弹层挂根导航器盖住页面，页面级 snackbar
    // 会被挡住——用户点「应用」只看到没反应。断言必须锁「错误在弹层内」且
    // 可见；只查 find.text 会命中藏在弹层后面的那条 snackbar，抓不住缺陷。
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final rice = _food(id: 'rice', name: '米饭', kcal: 116);
    await tester.pumpWidget(_CandidateHarness(foods: [rice]));
    await tester.tap(find.byKey(const Key('scan-candidate-edit')));
    await tester.pumpAndSettle();

    // 空名称被拒绝：弹层不关，原因画在弹层内。
    await tester.enterText(find.byKey(const Key('scan-correction-name')), '');
    await tester.tap(find.byKey(const Key('scan-correction-submit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('scan-correction-sheet')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('scan-correction-sheet')),
        matching: find.text('名称不能为空。'),
      ),
      findsOneWidget,
    );
    expect(
      tester.getSize(find.byKey(const Key('scan-correction-error'))).height,
      greaterThan(0),
    );

    // 克数为 0 同样拒绝，错误在弹层内更新。
    await tester.enterText(find.byKey(const Key('scan-correction-name')), '米饭');
    await tester.enterText(find.byKey(const Key('scan-correction-grams')), '0');
    await tester.tap(find.byKey(const Key('scan-correction-submit')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const Key('scan-correction-sheet')),
        matching: find.textContaining('克数必须是正数'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('scan-correction-sheet')), findsOneWidget);
  });
}

final class _CandidateHarness extends StatefulWidget {
  const _CandidateHarness({
    required this.foods,
    this.draft,
    this.saving = false,
  });

  final List<FoodRecord> foods;
  final MealScanCandidateDraft? draft;
  final bool saving;

  @override
  State<_CandidateHarness> createState() => _CandidateHarnessState();
}

class _CandidateHarnessState extends State<_CandidateHarness> {
  late MealScanCandidateDraft _draft;

  @override
  void initState() {
    super.initState();
    _draft = widget.draft ?? _resolvedDraft(widget.foods.first);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: ListView(
        children: [
          ScanCandidateEditor(
            draft: _draft,
            searchFoods: (query) async => widget.foods
                .where((food) => food.name.contains(query))
                .toList(growable: false),
            onChanged: (draft) => setState(() => _draft = draft),
            onCorrection: (index, corrected) =>
                setState(() => _draft = _draft.replaceItem(index, corrected)),
            onConfirm: () {},
            confirmEnabled:
                _draft.resolvedItems.isNotEmpty && !_draft.hasUnresolvedItems,
            saving: widget.saving,
            onDismiss: () {},
          ),
        ],
      ),
    ),
  );
}

MealScanCandidateDraft _resolvedDraft(FoodRecord food) =>
    MealScanCandidateDraft(
      items: [
        MealScanCandidate.fromEstimate(
          _estimate('米饭'),
          LocalFoodMatch(
            status: LocalFoodMatchStatus.exact,
            selectedFood: food,
            suggestions: [food],
          ),
        ),
      ],
      slot: MealSlot.lunch,
      notes: '少油',
      warnings: const [],
    );

MealEstimateItem _estimate(String name, {MealEstimateNutrition? nutrition}) =>
    MealEstimateItem(
      name: name,
      estimatedGrams: 180,
      gramsRange: const GramRange(min: 140, max: 220),
      confidence: 0.8,
      ingredients: const [],
      needsConfirmation: false,
      questions: const [],
      cookingMethod: '蒸煮',
      nutrition: nutrition,
    );

FoodRecord _food({
  required String id,
  required String name,
  required double kcal,
}) => FoodRecord(
  id: id,
  name: name,
  kcalPer100g: kcal,
  proteinPer100g: 2,
  carbsPer100g: 20,
  fatPer100g: 1,
  isUserCreated: false,
);
