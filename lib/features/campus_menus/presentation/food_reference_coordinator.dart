import 'package:localfit_ai/features/campus_menus/application/food_reference_service.dart';
import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart';
import 'package:localfit_ai/features/campus_menus/presentation/food_reference_sheet.dart';

/// 建食堂菜/改名后的「参考食物库」编排（docs/40 §3.1，从 [MenuTabView] 拆出
/// 以守 500 行预算）：三选一弹层 + 「引用」落库。状态判断（mounted）与
/// 写操作外壳仍由页面自己提供——本类只聚合弹层与仓库调用。
final class FoodReferenceCoordinator {
  FoodReferenceCoordinator({
    required this.repository,
    required this.service,
    required this.loadDish,
    required this.onAnalyze,
  });

  final CanteenRepository repository;
  final FoodReferenceService service;

  /// 从页面窗口缓存里找刚建/刚改的那道菜（createDish 只回 id）。
  final Future<CanteenDish?> Function(String dishId) loadDish;

  /// 「AI 重新分析」走既有分析入口；null = 该选项不可选。
  final Future<void> Function(List<CanteenDish> dishes)? onAnalyze;

  /// 建菜/改名成功后的「参考食物库」三选一（docs/40 §3.1：给建议，不静默填）。
  ///
  /// * 命中 → 弹三选一；「引用」把食物库 per100g 写进证据表
  ///   （origin=food_library，链接置 confirmed）+ 成功提示；
  /// * 「AI 重新分析」→ 走既有分析入口（链接保留 suggested）；
  /// * 「先不填」/ 无命中 / 服务未接线 → 什么都不写，旧行为逐字不变。
  Future<void> run({
    required String dishId,
    required String dishName,
    required void Function(String message, {bool error}) showSnack,
    required Future<FoodReferenceDecision?> Function(
      String dishName,
      List<FoodReferenceCandidate> candidates,
    )
    showSheet,
    required bool Function() isMounted,
  }) async {
    final List<FoodReferenceCandidate> candidates;
    try {
      candidates = await service.suggestForDish(dishId);
    } on Object {
      return; // 匹配失败不挡建菜：这道菜只是没有参考建议。
    }
    if (candidates.isEmpty || !isMounted()) return;
    final decision = await showSheet(dishName, candidates);
    if (!isMounted() || decision == null) return;
    switch (decision.choice) {
      case FoodReferenceChoice.skip:
        return;
      case FoodReferenceChoice.analyze:
        final analyze = onAnalyze;
        if (analyze == null) return;
        final dish = await loadDish(dishId);
        if (dish == null || !isMounted()) return;
        await analyze([dish]);
      case FoodReferenceChoice.adopt:
        // 2026-10-22 用户：引用**用户点中的那条**，不再默认第一条。
        final picked = decision.candidate ?? candidates.first;
        final error = _adoptFoodReference(dishId, picked);
        // isMounted 已由调用方 guard（页面闭包 () => mounted）。
        if (!isMounted()) return;
        if (error != null) {
          showSnack(error, error: true);
        } else {
          showSnack('已引用食物库「${picked.foodName}」的营养（每 100g）。');
        }
    }
  }

  /// 「引用食物库营养」落库：证据表写 per100g + 链接置 confirmed（docs/40 §3.1）。
  /// 返回 null = 成功；文案 = 给用户的错误提示（调用方用 SnackBar 呈现）。
  String? _adoptFoodReference(String dishId, FoodReferenceCandidate candidate) {
    try {
      repository.recordNutrition(
        dishId: dishId,
        kcalPer100g: candidate.kcalPer100g,
        proteinPer100g: candidate.proteinPer100g,
        carbsPer100g: candidate.carbsPer100g,
        fatPer100g: candidate.fatPer100g,
        // 证据等级沿用食物条目的状态（verified→A / 自建→B / 其他→C）：
        // 引用的可信度就是食物那条数据的可信度，不重新发明一档。
        grade: switch (candidate.state) {
          'verified' => 'A',
          'user_created' => 'B',
          _ => 'C',
        },
        confidence: candidate.confidence,
        origin: 'food_library',
        sourceText: '引用食物库「${candidate.foodName}」',
      );
      return null;
    } on CanteenWriteException catch (error) {
      return error.userMessage;
    } on Object {
      return '引用失败，请稍后重试。';
    }
  }
}
