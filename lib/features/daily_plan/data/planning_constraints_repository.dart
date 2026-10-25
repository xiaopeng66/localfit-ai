// 2026-10-24 批次 4（`docs/56` R4 / `docs/58` B6 R4-4b）：**「下一餐」整族退役**。
//
// `NextMealDecisionController` 与 `DailyPlanEngine` 已删除（零调用方）。
// 本文件**保留**：`memory_promotion.dart` 与 AI 记忆页仍在写约束
// （`constraints.set` 是记忆晋升的落点之一），但**当前没有本地读取者**——
// 原先唯一读它的是 `DailyPlanEngine`。这是有意保留的可写事实，不是死代码；
// `docs/03` 的 as-built 与 `docs/40 §6` 都登记了这条现状。
//
// `daily_plans` / `daily_plan_slots` / `daily_plan_candidates` 三张表**保留不删**
// （schema 冻结，留将来复用与备份兼容）。
import 'package:drift/drift.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/daily_plan/domain/planning_constraints.dart';

/// 读写 `profiles` 上的饮食偏好 / 过敏原回避两列。
///
/// 位置说明（docs/28 §6.4 落地记录）：原先在 `features/recipe_planning/`
/// 下，随该目录整族删除后按「搬到中立位置保留」处理（同 §6.7 对
/// `planning_facts_editor_dialog` 的办法）——`DailyPlanEngine` 仍读
/// `allergenAvoidancesJson`，对话命令 `constraints.set` 仍写它。
/// 只改动了一个 import，逻辑逐字未动。
final class PlanningConstraintsRepository {
  const PlanningConstraintsRepository({
    required this.database,
    required this.clock,
  });

  final AppDatabase database;
  final AppClock clock;

  Future<PlanningConstraints> load() async {
    final profile = await (database.select(
      database.profiles,
    )..limit(1)).getSingleOrNull();
    if (profile == null) return const PlanningConstraints();
    return PlanningConstraints.fromStorage(
      dietaryLabelsJson: profile.dietaryPreferencesJson,
      allergenAvoidancesJson: profile.allergenAvoidancesJson,
    );
  }

  Future<void> save(PlanningConstraints constraints) async {
    constraints.validate();
    final profile = await (database.select(
      database.profiles,
    )..limit(1)).getSingleOrNull();
    if (profile == null) {
      throw StateError('请先完成本地建档，再保存饮食限制。');
    }
    await (database.update(
      database.profiles,
    )..where((row) => row.id.equals(profile.id))).write(
      ProfilesCompanion(
        dietaryPreferencesJson: Value(constraints.dietaryLabelsJson),
        allergenAvoidancesJson: Value(constraints.allergenAvoidancesJson),
        updatedAt: Value(clock.nowUtc()),
      ),
    );
  }
}
