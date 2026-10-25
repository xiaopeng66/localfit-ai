// 2026-10-24：`DailyPlanEngine`（本文件的唯一生产调用者）随「下一餐」整族退役。
// 本文件**保留**：`daily_solver_test` 仍在验证排程算法，`menu_service_window` 的
// 窗口判定也被 `nutrition` 的两处推荐复用（`add_canteen_dishes_to_library` /
// `build_daily_meal_recommendation`）。
/// 2.0-4 solver 候选输入视图（docs/07 §7.2/7.3）。
///
/// 由上层（2.0-4c 接线）从本地事实构建：快照状态、窗口营业、过敏冲突、
/// 营养完整性与各项偏差/适配分数全部在本机计算。营养数字只来自本地
/// 匹配估算快照，不读模型自报。
class SolverCandidate {
  const SolverCandidate({
    required this.id,
    required this.kind,
    required this.refId,
    required this.displayName,
    required this.nutritionDeviation,
    required this.macroDeviation,
    required this.timeFit,
    required this.travelFit,
    required this.preferenceFit,
    required this.freshnessPenalty,
    this.venueId,
    this.snapshotExpired = false,
    this.windowState = 'open',
    this.allergenConflicts = const [],
    this.hasCompleteNutrition = true,
    this.conflictsWithExistingPlan = false,
    this.idExists = true,
    this.estimatedKcal,
    this.estimatedProteinG,
    this.estimatedCarbsG,
    this.estimatedFatG,
    this.evidenceGrade,
  });

  final String id;
  // kind: menu_item | food（统一 candidate contract）；老库里可能还留着
  // `recipe` 取值的候选行（食谱整族已于 docs/28 W4 下线），读取侧照旧兼容。
  final String kind;
  final String refId;
  final String displayName;
  final String? venueId;

  // ── 硬约束输入（7.3）──
  final bool snapshotExpired;
  // open | closed | not_open | unknown；closed/not_open 不过约束。
  final String windowState;
  // 命中的过敏原列表（非空即冲突）。
  final List<String> allergenConflicts;
  final bool hasCompleteNutrition;
  final bool conflictsWithExistingPlan;
  final bool idExists;

  // 营养估算快照（本地匹配结果；可空 = 不完整）。
  final double? estimatedKcal;
  final double? estimatedProteinG;
  final double? estimatedCarbsG;
  final double? estimatedFatG;
  final String? evidenceGrade;

  // ── 排序输入（7.4，全部归一化 0..1）──
  final double nutritionDeviation;
  final double macroDeviation;
  final double timeFit;
  final double travelFit;
  final double preferenceFit;
  final double freshnessPenalty;
}

/// solver 产出的候选：输入事实 + 本地得分 + 原因码。
class SolverResultCandidate {
  const SolverResultCandidate({
    required this.candidate,
    required this.score,
    required this.reasonCodes,
    this.unsatisfiedReason,
  });

  final SolverCandidate candidate;

  /// 便捷透传（= candidate.id）。
  String get id => candidate.id;

  /// 归一化总分 0..1（1 - 加权代价，越高越优）。
  final double score;

  /// 触发的原因码（硬约束失败或标注性提示，如 nutrition_incomplete）。
  final List<String> reasonCodes;

  /// 非空 = 未通过硬约束，不能进入「可确认推荐」。
  final String? unsatisfiedReason;
}

/// solver 输出：satisfied 按分数降序（平分按 id 稳定），unsatisfied
/// 携带原因码。全部被约束挡下时 [noSolutionReason] 非空。
class SolverResult {
  const SolverResult({
    required this.satisfied,
    required this.unsatisfied,
    this.noSolutionReason,
  });

  final List<SolverResultCandidate> satisfied;
  final List<SolverResultCandidate> unsatisfied;
  final String? noSolutionReason;
}

/// docs/07 §7.4 权重（代码常量 + 测试固定；用户偏好只调整权重，不绕过
/// 硬约束；AI 不得改变权重）。
abstract final class DailySolverWeights {
  static const double nutritionDeviation = 0.40;
  static const double macroDeviation = 0.20;
  static const double timeFit = 0.15;
  static const double distanceOrTravelFit = 0.10;
  static const double preferenceFit = 0.10;
  static const double freshnessPenalty = 0.05;
}

/// 2.0-4b：每日「去哪里、吃什么」确定性 solver（docs/07 §7.1-7.4）。
///
/// 本地规则路径可离线执行；未知/过期/过敏冲突/不完整营养（严格目标
/// 时）/关闭窗口/计划冲突一律挡下并带原因码，绝不伪装达标。推荐不是
/// 事实：确认加入计划是独立动作（2.0-4c），不写 consumed meal。
abstract final class DailySolver {
  /// 过滤硬约束 → 按权重公式打分排序。
  static SolverResult solve({
    required List<SolverCandidate> candidates,
    required String slot,
    bool strictNutritionRequired = true,
  }) {
    if (candidates.isEmpty) {
      return const SolverResult(
        satisfied: [],
        unsatisfied: [],
        noSolutionReason: 'no_solution_empty',
      );
    }

    final satisfied = <SolverResultCandidate>[];
    final unsatisfied = <SolverResultCandidate>[];

    for (final candidate in candidates) {
      final reasonCodes = <String>[];

      // ── 硬约束（7.3）──
      if (candidate.snapshotExpired) {
        reasonCodes.add('snapshot_expired');
      }
      if (candidate.windowState == 'closed' ||
          candidate.windowState == 'not_open') {
        reasonCodes.add('window_unavailable');
      }
      if (candidate.allergenConflicts.isNotEmpty) {
        // **当前无输入源**（docs/31 S2 / 需求 50）：`foods.allergens_json`
        // 已随 schema 22 删除，`DailyPlanEngine` 现在恒传空列表 ⇒
        // 这条原因码不可能产生。分支**刻意保留**：solver 是纯函数，
        // 将来接回任何过敏数据源时不必重写它的硬约束段。
        reasonCodes.add('allergen_conflict');
      }
      final nutritionIncomplete = !candidate.hasCompleteNutrition;
      if (nutritionIncomplete) {
        reasonCodes.add('nutrition_incomplete');
      }
      if (candidate.conflictsWithExistingPlan) {
        reasonCodes.add('plan_conflict');
      }
      if (!candidate.idExists) {
        reasonCodes.add('id_not_found');
      }

      final blocking = reasonCodes
          .where(
            (code) => code != 'nutrition_incomplete' || strictNutritionRequired,
          )
          .toList();
      if (blocking.isNotEmpty) {
        unsatisfied.add(
          SolverResultCandidate(
            candidate: candidate,
            score: 0,
            reasonCodes: reasonCodes,
            unsatisfiedReason: blocking.first,
          ),
        );
        continue;
      }

      // ── 排序（7.4）：score = 1 - Σ weight × deviation ──
      final cost =
          DailySolverWeights.nutritionDeviation * candidate.nutritionDeviation +
          DailySolverWeights.macroDeviation * candidate.macroDeviation +
          DailySolverWeights.timeFit * (1 - candidate.timeFit) +
          DailySolverWeights.distanceOrTravelFit * (1 - candidate.travelFit) +
          DailySolverWeights.preferenceFit * (1 - candidate.preferenceFit) +
          DailySolverWeights.freshnessPenalty * candidate.freshnessPenalty;
      final score = (1 - cost).clamp(0.0, 1.0);
      satisfied.add(
        SolverResultCandidate(
          candidate: candidate,
          score: score,
          reasonCodes: reasonCodes,
        ),
      );
    }

    satisfied.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return a.candidate.id.compareTo(b.candidate.id);
    });

    return SolverResult(
      satisfied: satisfied,
      unsatisfied: unsatisfied,
      noSolutionReason: satisfied.isEmpty
          ? 'no_solution_all_constrained'
          : null,
    );
  }
}
