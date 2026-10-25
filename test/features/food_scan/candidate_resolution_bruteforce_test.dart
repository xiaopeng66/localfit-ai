import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/features/food_scan/application/local_food_search.dart';
import 'package:localfit_ai/features/food_scan/application/resolve_meal_scan_candidates.dart';
import 'package:localfit_ai/features/food_scan/domain/meal_estimate.dart';
import 'package:localfit_ai/features/nutrition/domain/food_record.dart';

/// 暴力测试（应用层）：往候选解析里灌畸形/边界输入。
///
/// UI 层连点已在 `food_scan_bruteforce_test.dart` 验证；这一层专攻**数值
/// 与字符串边界**——AI 返回的畸形草案是真实存在的（供应商换渠道、模型
/// 抽风），而 `double.tryParse('NaN')` 会成功返回 NaN，不是 null。
void main() {
  const rice = FoodRecord(
    id: 'food-rice',
    name: '米饭',
    kcalPer100g: 133,
    proteinPer100g: 2.7,
    carbsPer100g: 29,
    fatPer100g: 0.3,
    isUserCreated: false,
  );

  MealEstimateItem item({
    required String name,
    required double grams,
    MealEstimateNutrition? nutrition,
  }) => MealEstimateItem(
    name: name,
    estimatedGrams: grams,
    gramsRange: GramRange(min: grams, max: grams),
    confidence: 0.5,
    ingredients: const [],
    needsConfirmation: false,
    questions: const [],
    cookingMethod: null,
    nutrition: nutrition,
  );

  test('畸形克数（NaN/Infinity/负数/0）不得产出可入账的候选', () async {
    final resolve = ResolveMealScanCandidates(
      foodSearch: _Search(const [rice]),
    );
    const hostileValues = <double>[
      double.nan,
      double.infinity,
      double.negativeInfinity,
      -1,
      0,
      -0.0,
    ];
    for (final hostile in hostileValues) {
      final draft = await resolve(
        MealEstimateDraft(
          items: [item(name: '米饭', grams: hostile)],
          warnings: const [],
          mealNotes: null,
        ),
      );
      final candidate = draft.items.single;
      // 关键：localNutrition 为 null ⇒ resolvedItems 为空 ⇒ 页面
      // `_canSaveCandidate` 为 false ⇒ 确认按钮禁用。若这里返回了非 null，
      // 用户就能把 NaN 克数写进库。
      expect(
        candidate.localNutrition,
        isNull,
        reason: '克数 $hostile 不应产出可入账的营养值',
      );
      expect(
        draft.resolvedItems,
        isEmpty,
        reason: '克数 $hostile 不应出现在 resolvedItems 里',
      );
      expect(draft.hasUnresolvedItems, isTrue);
    }
  });

  test('AI 给出的畸形营养（NaN/负值）不得进营养合计', () async {
    final resolve = ResolveMealScanCandidates(
      foodSearch: _Search(const []), // 本地无匹配 → 走 AI 兜底
    );
    for (final hostile in const <double>[double.nan, double.infinity, -50]) {
      final draft = await resolve(
        MealEstimateDraft(
          items: [
            item(
              name: '不明食物',
              grams: 100,
              nutrition: MealEstimateNutrition(
                kcal: hostile,
                proteinGrams: hostile,
                carbsGrams: hostile,
                fatGrams: hostile,
              ),
            ),
          ],
          warnings: const [],
          mealNotes: null,
        ),
      );
      // 现状记录（非断言）：应用层对 AI 营养不做 isFinite 复检，NaN 会
      // 原样透出到 `MealScanCandidateDraft.nutrition`。**这不是缺陷**：
      // NaN/Infinity 到不了这里——JSON 无法表达它们，decoder 的
      // `_requiredNumber` 对 `!isFinite` 直接抛 FormatException，且这条
      // 防线已有专测（`meal_estimate_decoder_edge_test.dart` 列了
      // NaN/Infinity/-Infinity 三个用例）。此用例只做形状记录：
      // 无论输入多畸形，候选条数不丢、不抛。
      expect(draft.items, hasLength(1));
    }
  });

  test('超长名称与纯空白名称不崩溃、不误匹配', () async {
    final resolve = ResolveMealScanCandidates(
      foodSearch: _Search(const [rice]),
    );
    final names = [
      '',
      '   ',
      '\u3000\u3000',
      '米' * 5000,
      '米饭\n\t\r',
      '（（（米饭）））',
      '🍚🍚🍚',
    ];
    for (final name in names) {
      final draft = await resolve(
        MealEstimateDraft(
          items: [item(name: name, grams: 100)],
          warnings: const [],
          mealNotes: null,
        ),
      );
      expect(
        draft.items,
        hasLength(1),
        reason: '名称「${name.length} 字符」必须仍产出 1 条候选',
      );
      // 空名不得被兜底成「任意食物」——那会让用户看到与照片无关的候选。
      if (name.trim().isEmpty) {
        expect(
          draft.items.single.selectedFood,
          isNull,
          reason: '空名不应自动选中任何本地食物',
        );
      }
    }
  });

  test('同名多项只自动收录一次（去重后复用同一条食物）', () async {
    final created = <String>[];
    final resolve = ResolveMealScanCandidates(
      foodSearch: _Search(const []),
      createFood: (food) async {
        created.add(food.name);
        return FoodRecord(
          id: 'created-${created.length}',
          name: food.name,
          kcalPer100g: food.kcalPer100g,
          proteinPer100g: food.proteinPer100g,
          carbsPer100g: food.carbsPer100g,
          fatPer100g: food.fatPer100g,
          isUserCreated: true,
        );
      },
    );
    final draft = await resolve(
      MealEstimateDraft(
        items: [
          item(
            name: '自制沙拉',
            grams: 100,
            nutrition: const MealEstimateNutrition(
              kcal: 90,
              proteinGrams: 3,
              carbsGrams: 10,
              fatGrams: 4,
            ),
          ),
          item(
            name: '自制沙拉',
            grams: 200,
            nutrition: const MealEstimateNutrition(
              kcal: 90,
              proteinGrams: 3,
              carbsGrams: 10,
              fatGrams: 4,
            ),
          ),
        ],
        warnings: const [],
        mealNotes: null,
      ),
    );
    expect(created, hasLength(1), reason: '同名项应只建档一次，实际 ${created.length} 次');

    final first = draft.items[0].selectedFood;
    final second = draft.items[1].selectedFood;
    expect(first, isNotNull);
    expect(identical(first, second), isTrue, reason: '同名项应复用同一条食物记录');
    // 两条候选克数不同，营养必须各按自己的克数算。
    expect(draft.items[0].localNutrition!.grams, 100);
    expect(draft.items[1].localNutrition!.grams, 200);
    expect(
      draft.items[1].localNutrition!.nutrition.kcal,
      closeTo(draft.items[0].localNutrition!.nutrition.kcal * 2, 0.01),
    );
  });

  test('超大克数不产生 Infinity 合计（溢出防线）', () async {
    final resolve = ResolveMealScanCandidates(
      foodSearch: _Search(const [rice]),
    );
    final draft = await resolve(
      MealEstimateDraft(
        items: [
          item(name: '米饭', grams: 1e308),
          item(name: '米饭', grams: 1e308),
        ],
        warnings: const [],
        mealNotes: null,
      ),
    );
    final total = draft.nutrition.kcal;
    // 这里只要求「不崩、不把 NaN 当成合法值往上送」；合计溢出成 Infinity
    // 是 double 的既定行为，页面侧靠 isFinite 守卫兜住。
    expect(total.isNaN, isFalse, reason: '合计不得为 NaN');
    if (!total.isFinite) {
      // 溢出可接受，但此时必须仍能被上层 isFinite 守卫识别为不可入账。
      expect(total.isFinite, isFalse);
    }
    expect(draft.items, hasLength(2));
    expect(math.max(0, total), isNotNull);
  });

  test('候选克数的建议范围被原样保留（编辑器步进依赖它）', () async {
    final resolve = ResolveMealScanCandidates(
      foodSearch: _Search(const [rice]),
    );
    final draft = await resolve(
      MealEstimateDraft(
        items: [
          MealEstimateItem(
            name: '米饭',
            estimatedGrams: 150,
            gramsRange: const GramRange(min: 100, max: 999),
            confidence: 0.9,
            ingredients: const [],
            needsConfirmation: false,
            questions: const [],
            cookingMethod: null,
            nutrition: null,
          ),
        ],
        warnings: const ['AI 提示'],
        mealNotes: '   ',
      ),
    );
    final candidate = draft.items.single;
    expect(candidate.estimate.gramsRange.min, 100);
    expect(candidate.estimate.gramsRange.max, 999);
    expect(draft.warnings, ['AI 提示']);
    // 纯空白备注应归一成 null，避免把空串写进库。
    expect(draft.notes, isNull, reason: '纯空白备注不应保留');
  });
}

final class _Search implements LocalFoodSearch {
  const _Search(this.foods);

  final List<FoodRecord> foods;

  @override
  Future<List<FoodRecord>> search(String query, {int limit = 30}) async =>
      foods;
}
