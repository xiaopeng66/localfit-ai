import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/features/daily_plan/application/daily_solver.dart';

/// 2.0-4b：每日计划确定性 solver（docs/07 §7.3 硬约束 + 7.4 权重公式）。
///
/// 全程本机：不联网、不调用 AI；营养数字只来自本地匹配估算快照，
/// 不读模型自报。未知不放行（无营养证据 → unsatisfied，不伪装达标）。
void main() {
  // 权重常量与 docs/07 §7.4 一致且和为 1。
  test('solver weights match spec 7.4 and sum to 1', () {
    expect(DailySolverWeights.nutritionDeviation, 0.40);
    expect(DailySolverWeights.macroDeviation, 0.20);
    expect(DailySolverWeights.timeFit, 0.15);
    expect(DailySolverWeights.distanceOrTravelFit, 0.10);
    expect(DailySolverWeights.preferenceFit, 0.10);
    expect(DailySolverWeights.freshnessPenalty, 0.05);
    final sum =
        DailySolverWeights.nutritionDeviation +
        DailySolverWeights.macroDeviation +
        DailySolverWeights.timeFit +
        DailySolverWeights.distanceOrTravelFit +
        DailySolverWeights.preferenceFit +
        DailySolverWeights.freshnessPenalty;
    expect(sum, closeTo(1.0, 1e-9));
  });
  SolverCandidate candidate({
    String id = 'c1',
    String kind = 'menu_item',
    String refId = 'item-1',
    String displayName = '鸡蛋炒饭',
    bool snapshotExpired = false,
    String windowState = 'open',
    List<String> allergenConflicts = const [],
    bool hasCompleteNutrition = true,
    bool conflictsWithExistingPlan = false,
    bool idExists = true,
    double estimatedKcal = 500,
    double estimatedProteinG = 20,
    double estimatedCarbsG = 60,
    double estimatedFatG = 15,
    double nutritionDeviation = 0.2,
    double macroDeviation = 0.2,
    double timeFit = 1.0,
    double travelFit = 1.0,
    double preferenceFit = 1.0,
    double freshnessPenalty = 0.0,
  }) => SolverCandidate(
    id: id,
    kind: kind,
    refId: refId,
    displayName: displayName,
    snapshotExpired: snapshotExpired,
    windowState: windowState,
    allergenConflicts: allergenConflicts,
    hasCompleteNutrition: hasCompleteNutrition,
    conflictsWithExistingPlan: conflictsWithExistingPlan,
    idExists: idExists,
    estimatedKcal: estimatedKcal,
    estimatedProteinG: estimatedProteinG,
    estimatedCarbsG: estimatedCarbsG,
    estimatedFatG: estimatedFatG,
    nutritionDeviation: nutritionDeviation,
    macroDeviation: macroDeviation,
    timeFit: timeFit,
    travelFit: travelFit,
    preferenceFit: preferenceFit,
    freshnessPenalty: freshnessPenalty,
  );
  group('hard constraints (7.3)', () {
    test('a fully clean candidate passes all constraints', () {
      final result = DailySolver.solve(
        candidates: [candidate()],
        slot: 'lunch',
      );
      expect(result.satisfied, hasLength(1));
      expect(result.satisfied.single.reasonCodes, isEmpty);
    });
    test('expired snapshot is excluded with reason code', () {
      final result = DailySolver.solve(
        candidates: [candidate(id: 'dead', snapshotExpired: true)],
        slot: 'lunch',
      );
      expect(result.satisfied, isEmpty);
      expect(result.unsatisfied.single.id, 'dead');
      expect(
        result.unsatisfied.single.reasonCodes,
        contains('snapshot_expired'),
      );
    });
    test('closed/not-yet-open window is excluded', () {
      for (final state in const ['closed', 'not_open']) {
        final result = DailySolver.solve(
          candidates: [candidate(id: 'c-$state', windowState: state)],
          slot: 'lunch',
        );
        expect(
          result.unsatisfied.single.reasonCodes,
          contains('window_unavailable'),
          reason: 'windowState=$state must fail',
        );
      }
    });
    test('allergen conflict is excluded with reason code', () {
      final result = DailySolver.solve(
        candidates: [
          candidate(id: 'allergen', allergenConflicts: ['peanut']),
        ],
        slot: 'lunch',
      );
      expect(
        result.unsatisfied.single.reasonCodes,
        contains('allergen_conflict'),
      );
    });
    test('strict target without complete nutrition is excluded', () {
      final result = DailySolver.solve(
        candidates: [candidate(id: 'noinfo', hasCompleteNutrition: false)],
        slot: 'lunch',
        strictNutritionRequired: true,
      );
      expect(
        result.unsatisfied.single.reasonCodes,
        contains('nutrition_incomplete'),
      );
    });
    test('nutrition incomplete passes when strict target not required '
        'but stays flagged as estimate', () {
      final result = DailySolver.solve(
        candidates: [candidate(id: 'loose', hasCompleteNutrition: false)],
        slot: 'lunch',
        strictNutritionRequired: false,
      );
      expect(result.satisfied.single.id, 'loose');
      expect(
        result.satisfied.single.reasonCodes,
        contains('nutrition_incomplete'),
      );
    });
    test('existing plan conflict and missing id are excluded', () {
      final result = DailySolver.solve(
        candidates: [
          candidate(id: 'dup', conflictsWithExistingPlan: true),
          candidate(id: 'ghost', idExists: false),
        ],
        slot: 'lunch',
      );
      expect(
        result.unsatisfied.singleWhere((c) => c.id == 'dup').reasonCodes,
        contains('plan_conflict'),
      );
      expect(
        result.unsatisfied.singleWhere((c) => c.id == 'ghost').reasonCodes,
        contains('id_not_found'),
      );
    });
  });
  group('scoring (7.4)', () {
    test('score follows the weighted formula deterministically', () {
      final c = candidate(
        nutritionDeviation: 0.5,
        macroDeviation: 0.4,
        timeFit: 1.0,
        travelFit: 0.5,
        preferenceFit: 0.8,
        freshnessPenalty: 0.2,
      );
      final result = DailySolver.solve(candidates: [c], slot: 'lunch');
      // fit 归一化为代价：dev = 1 - fit；score = 1 - Σ w × dev。
      final expected =
          1 -
          (0.40 * 0.5 +
              0.20 * 0.4 +
              0.15 * (1 - 1.0) +
              0.10 * (1 - 0.5) +
              0.10 * (1 - 0.8) +
              0.05 * 0.2);
      expect(result.satisfied.single.score, closeTo(expected, 1e-9));
    });
    test(
      'lower deviation ranks higher; deterministic tie-break by id',
      () async {
        final good = candidate(
          id: 'b-good',
          nutritionDeviation: 0.1,
          macroDeviation: 0.1,
        );
        final bad = candidate(
          id: 'a-bad',
          nutritionDeviation: 0.9,
          macroDeviation: 0.9,
        );
        // 同分（对称参数）时按 id 稳定排序。
        final twin1 = candidate(
          id: 'twin-b',
          nutritionDeviation: 0.3,
          macroDeviation: 0.3,
        );
        final twin2 = candidate(
          id: 'twin-a',
          nutritionDeviation: 0.3,
          macroDeviation: 0.3,
        );
        final result = DailySolver.solve(
          candidates: [bad, twin2, twin1, good],
          slot: 'lunch',
        );
        expect(result.satisfied.map((c) => c.id).toList(), [
          'b-good',
          'twin-a',
          'twin-b',
          'a-bad',
        ]);
      },
    );
  });
  group('no-solution reporting', () {
    test(
      'all constrained out yields empty satisfied with unsatisfied list',
      () {
        final result = DailySolver.solve(
          candidates: [
            candidate(id: 'dead', snapshotExpired: true),
            candidate(id: 'closed', windowState: 'closed'),
          ],
          slot: 'lunch',
        );
        expect(result.satisfied, isEmpty);
        expect(result.unsatisfied, hasLength(2));
        expect(result.noSolutionReason, isNotNull);
      },
    );
    test('empty candidate set reports no_solution_empty', () {
      final result = DailySolver.solve(candidates: const [], slot: 'lunch');
      expect(result.satisfied, isEmpty);
      expect(result.noSolutionReason, 'no_solution_empty');
    });
  });
}
