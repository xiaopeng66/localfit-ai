import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/features/food_scan/application/conversational_recognition_correction.dart';
import 'package:localfit_ai/features/food_scan/application/meal_scan_candidate.dart';
import 'package:localfit_ai/features/food_scan/domain/meal_estimate.dart';
import 'package:localfit_ai/features/nutrition/domain/food_record.dart';

/// TDD：对话式识别修正（2.0-6h）
///
/// 用户编辑 AI 候选（改名 + 改克数，或从本地择一），本地重新计算营养，
/// 草案值永远只是草案——不写 DB。控制器零 IO，全 pure function 风格。
void main() {
  late MealScanCandidate candidate;
  late ConversationalRecognitionCorrection correction;
  late FoodRecord rice;

  setUp(() {
    rice = _food(id: 'rice', name: '米饭', kcal: 116);
    candidate = MealScanCandidate.fromEstimate(
      MealEstimateItem(
        name: '米饭',
        estimatedGrams: 180,
        gramsRange: const GramRange(min: 140, max: 220),
        confidence: 0.8,
        ingredients: const [],
        needsConfirmation: false,
        questions: const [],
        cookingMethod: '蒸煮',
        nutrition: const MealEstimateNutrition(
          kcal: 120,
          proteinGrams: 2,
          carbsGrams: 26,
          fatGrams: 1,
        ),
      ),
      LocalFoodMatch(
        status: LocalFoodMatchStatus.exact,
        selectedFood: rice,
        suggestions: [rice],
      ),
    );
    correction = ConversationalRecognitionCorrection(
      candidate: candidate,
      searchFoods: (query) async => query.isEmpty
          ? [rice]
          : [rice].where((f) => f.name.contains(query)).toList(),
    );
  });

  test('grams-only correction scales nutrition from matched local food', () {
    final result = correction.correctGrams(200);

    expect(result.isRejected, isFalse, reason: '克数有效应当接受');
    expect(result.value!.grams, 200);
    // 米饭 116 kcal/100g → 200g = 232 kcal
    expect(result.value!.localNutrition?.nutrition.kcal.round(), 232);
    expect(
      result.value!.localNutrition?.nutrition.proteinGrams.toStringAsFixed(1),
      '4.0',
    );
  });

  test('rename correction keeps local food but relabels the item name', () {
    final result = correction.correctName('午餐米饭');

    expect(result.isRejected, isFalse);
    expect(result.value!.estimate.name, '午餐米饭');
    // 克数/营养不变；本地食物名称沿用匹配食物本身（估算名改不影响本地食物名）。
    expect(result.value!.grams, 180);
    expect(result.value!.localNutrition?.foodName, '米饭');
  });

  test('rename must be non-empty after trim', () {
    final result = correction.correctName('  ');
    expect(result.isRejected, isTrue);
    expect(result.rejection, contains('不能为空'));
  });

  test('grams must be positive finite', () {
    for (final bad in [0.0, -10.0, double.nan, double.infinity]) {
      final result = correction.correctGrams(bad);
      expect(result.isRejected, isTrue, reason: '克数 $bad 应当被拒');
      expect(result.rejection, contains('克数'));
    }
  });

  test(
    'selecting a different local food recomputes nutrition from that food',
    () async {
      final noodles = _food(id: 'noodles', name: '面条', kcal: 300);
      // searchFoods 返回的是初始种子，这里直接替换为面条。
      final corrected = ConversationalRecognitionCorrection(
        candidate: candidate,
        searchFoods: (_) async => [rice, noodles],
      );

      final result = await corrected.selectFood('面条');
      expect(result.isRejected, isFalse);
      expect(result.value!.selectedFood?.name, '面条');
      // 180g 面条 @ 300 kcal/100g = 540 kcal
      expect(result.value!.localNutrition?.nutrition.kcal.round(), 540);
    },
  );

  test('selecting unknown food rejects', () async {
    final result = await correction.selectFood('不存在的食物');
    expect(result.isRejected, isTrue);
    expect(result.rejection, contains('未找到本地食物'));
  });

  test('correction preserves AI estimate and match status lineage', () {
    final result = correction.correctGrams(200);
    expect(result.value!.estimate.name, candidate.estimate.name);
    // 克数修正不改变匹配状态血缘。
    expect(result.value!.match.status, candidate.match.status);
    expect(result.value!.autoCollected, candidate.autoCollected);
  });
}

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
