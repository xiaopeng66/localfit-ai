import 'dart:convert';

import 'package:localfit_ai/features/ai_conversation/domain/ai_conversation_service.dart';
import 'package:localfit_ai/features/ai_conversation/domain/conversation_message.dart';
import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart';
import 'package:localfit_ai/features/daily_plan/domain/planning_constraints.dart';
import 'package:localfit_ai/features/nutrition/application/build_daily_meal_recommendation.dart';
import 'package:localfit_ai/features/nutrition/application/dietary_constraint_matcher.dart';
import 'package:localfit_ai/features/nutrition/application/supply_dish_candidates.dart';
import 'package:localfit_ai/features/nutrition/domain/dish_record.dart';
import 'package:localfit_ai/features/nutrition/data/supply_catalog_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';

/// 「换一套」的**内联 AI 重配**结果（R-4，2026-10-29 用户原话：
/// 「点击换一套后，不要跳转 AI 对话界面，而是显示加载中，然后直接在原界面
/// 询问 AI 进行替换，替换的内容需要来源于食堂目录，你需要让 AI 限定后进行
/// 检索，而不是让 AI 随机生成，或者用食物库的食材」）。
///
/// [bySlot] = 每餐 AI 选中的菜（**已本地硬校验**：只可能是食堂目录里
/// `hasNutrition` 的菜，映射成 `DishRecord` 供推荐卡直接渲染）；
/// [filtered] = 被本地校验丢弃的条数（编造 dishId / 清单外 / 跨餐重复），
/// 由 UI 如实提示「已忽略 N 条不在目录里的建议」。
enum MenuSetSwapUnavailableReason {
  noSupply,
  noNutrition,
  servingUnverified,
  configurationMissing,
  requestFailed,
  unusableOutput,
  constraintsUnavailable,
  constraintsExcluded,
  noActiveSlots,
  noSupplyForActiveSlots,
  localDataUnavailable;

  String get message => switch (this) {
    noSupply => '食堂目录还没有供应，请先添加供应。',
    noNutrition => '供应尚无可用的主库营养（未链接、不完整或已归档），请到食堂目录核对。',
    servingUnverified => '每份克数未知、仅为估计或来源未确认；请先补充可信份量。',
    configurationMissing => 'AI 配置缺失，请检查模型与密钥设置。',
    requestFailed => 'AI 请求失败，请稍后重试。',
    unusableOutput => 'AI 输出不可用，未通过本地目录、餐次或预算校验。',
    constraintsUnavailable => '饮食约束读取失败，本次未请求 AI。',
    constraintsExcluded => '按你的饮食约束，当前没有可用的供应。',
    noActiveSlots => '今日三餐均已记录或已过推荐时段。',
    noSupplyForActiveSlots => '供应时段未覆盖当前可推荐餐次，请到食堂目录核对。',
    localDataUnavailable => '本地供应或今日营养读取失败，请重试。',
  };
}

final class MenuSetSwapResult {
  const MenuSetSwapResult({required this.bySlot, required this.filtered})
    : unavailableReason = null;

  const MenuSetSwapResult.unavailable(
    MenuSetSwapUnavailableReason reason, {
    this.filtered = 0,
  }) : bySlot = const {},
       unavailableReason = reason;

  final Map<MealSlot, List<DishRecord>> bySlot;
  final int filtered;
  final MenuSetSwapUnavailableReason? unavailableReason;
}

/// 内联「换一套」用例：把食堂目录里有营养的菜作为**唯一候选池**交给 AI，
/// 要求它只返回清单里的 dishId；返回值经本地硬校验后才上屏。
///
/// 边界（与 docs/65 §4-B 裁决一致）：
/// * **不写任何餐记录**（本类不依赖 `MealRepository`——结构上就写不了）；
/// * **不产生对话消息**（请求走 service 的临时 messages，不进历史仓库）；
/// * [runDetailed] 返回明确不可用原因；兼容入口 [run] 仍以 null 表示失败。
///   调用方只在确有可计算候选时回退本地重排，不把资料不足包装成成功。
final class SwapDailySetWithAi {
  const SwapDailySetWithAi({
    required this.service,
    required this.canteenRepository,
    required this.now,
    this.supplyCatalog,
    this.loadMeals,
    this.loadNutrition,
    this.loadConstraints,
  });

  final AiConversationService service;
  final CanteenRepository canteenRepository;

  /// 供应投影（docs/67 §6.5）：自动推荐只接受**完整营养 + 可信份量**的
  /// 供应，预算按"一份"比较，应用后记的也是这份量。null = 未接线，
  /// 「换一套」直接不可用（由调用方回退本地重排并如实说明），
  /// 而不是拿每 100g 当一份。
  final SupplyCatalogRepository? supplyCatalog;

  /// 当前时刻（组合根注入；测试可钉死）。
  final DateTime Function() now;

  /// 今日餐记录与营养汇总。生产由组合根接 `MealRepository` 的既有读路径；
  /// 测试可直接给快照。两者为 null 时保留旧的「无目标」行为。
  final Future<List<MealRecord>> Function(String localDate)? loadMeals;
  final Future<DailyNutritionSummary> Function(String localDate)? loadNutrition;

  /// 设置里的饮食约束。null = 未接线，按空约束处理。
  ///
  /// 这条路径此前**完全没读约束**：对话页的上下文加载器有「饮食偏好与忌口」
  /// 段，但菜单页的「AI 换一套」是独立 systemContext，AI 根本看不见用户
  /// 设的素食/忌口。现在既写进提示词，又在候选池和输出校验两处本地硬过滤。
  final Future<PlanningConstraints> Function()? loadConstraints;

  /// 交给 AI 的候选上限：清单太长会稀释注意力，也浪费 token。
  static const int maxCandidates = 60;

  /// 兼容旧调用者：任何不可用结果仍返回 null，且不泄漏请求异常。
  Future<MenuSetSwapResult?> run() async {
    final result = await runDetailed();
    return result.unavailableReason == null && result.bySlot.isNotEmpty
        ? result
        : null;
  }

  /// UI 使用详细结果，不再把严格池不足、配置缺失和网络故障混成一个 null。
  Future<MenuSetSwapResult> runDetailed() async {
    try {
      return await _runDetailed();
    } on Object {
      // 不把数据库异常内容或请求上下文写入日志/提示。
      return const MenuSetSwapResult.unavailable(
        MenuSetSwapUnavailableReason.localDataUnavailable,
      );
    }
  }

  Future<MenuSetSwapResult> _runDetailed() async {
    final catalog = supplyCatalog;
    if (catalog == null) {
      return const MenuSetSwapResult.unavailable(
        MenuSetSwapUnavailableReason.configurationMissing,
      );
    }
    // docs/67 §6.5：候选池 = 可供应窗口 + 主食物生效营养 + **有依据的**该
    // 供应份量。待分析、份量未知或只有历史未验证份量的项一律排除——
    // 它们没有"一份多少千卡"这个可比较的量。
    final supplies = await catalog.listAll();
    if (supplies.isEmpty) {
      return const MenuSetSwapResult.unavailable(
        MenuSetSwapUnavailableReason.noSupply,
      );
    }
    final analyzable = supplies.where(
      (supply) => supply.isAnalyzable && !supply.foodArchived,
    );
    if (analyzable.isEmpty) {
      return const MenuSetSwapResult.unavailable(
        MenuSetSwapUnavailableReason.noNutrition,
      );
    }
    final pool = [
      for (final supply in analyzable)
        if (supply.isAutoRecommendable &&
            supply.kcalPerServing?.isFinite == true)
          supply,
    ];
    if (pool.isEmpty) {
      return const MenuSetSwapResult.unavailable(
        MenuSetSwapUnavailableReason.servingUnverified,
      );
    }

    PlanningConstraints constraints = const PlanningConstraints();
    if (loadConstraints != null) {
      try {
        constraints = await loadConstraints!();
      } on Object {
        // 设置读失败不当作「无约束」放行。
        return const MenuSetSwapResult.unavailable(
          MenuSetSwapUnavailableReason.constraintsUnavailable,
        );
      }
    }
    final constraintAllowed = [
      for (final supply in pool)
        if (!dishNameConflictsWithConstraints(supply.displayName, constraints))
          supply,
    ];
    if (constraintAllowed.isEmpty) {
      return const MenuSetSwapResult.unavailable(
        MenuSetSwapUnavailableReason.constraintsExcluded,
      );
    }

    // 【2026-10-31 用户】AI 换一套不能只报菜名：必须读同一天的记录与目标，
    // 已记录的餐次不再推荐，剩余热量/宏量只分配给尚未记录的餐位。预算计算
    // 复用本地推荐的 `mealBudgetFor`，不在这里另写一套 30/40/30 口径。
    final current = now();
    final localDate = formatLocalDate(current);
    final dailyMeals = loadMeals == null
        ? const <MealRecord>[]
        : await loadMeals!(localDate);
    final summary = loadNutrition == null
        ? null
        : await loadNutrition!(localDate);
    final recorded = recordedKcalBySlot(dailyMeals);
    final nowMinute = current.hour * 60 + current.minute;
    final activeSlots = [
      for (final slot in mealRecommendationSlots)
        if (!recorded.containsKey(slot) &&
            isMealRecommendationSlotOpen(slot, nowMinute))
          slot,
    ];
    if (activeSlots.isEmpty) {
      return const MenuSetSwapResult.unavailable(
        MenuSetSwapUnavailableReason.noActiveSlots,
      );
    }
    // 硬约束、有效餐次先裁决，再截断；无效供应不能占满 60 个名额。
    final allowed = [
      for (final supply in constraintAllowed)
        if (activeSlots.any((slot) => _isSuppliedForSlot(supply, slot))) supply,
    ].take(maxCandidates).toList(growable: false);
    if (allowed.isEmpty) {
      return const MenuSetSwapResult.unavailable(
        MenuSetSwapUnavailableReason.noSupplyForActiveSlots,
      );
    }
    final byId = {for (final supply in allowed) supply.id: supply};
    final target = summary?.target;
    final budgetMin = <MealSlot, double?>{
      for (final slot in activeSlots)
        slot: mealBudgetFor(
          slot: slot,
          recordedKcalBySlot: recorded,
          dailyTargetKcal: target?.calorieMinKcal,
          nowMinute: nowMinute,
        ),
    };
    final budgetMax = <MealSlot, double?>{
      for (final slot in activeSlots)
        slot: mealBudgetFor(
          slot: slot,
          recordedKcalBySlot: recorded,
          dailyTargetKcal: target?.calorieMaxKcal,
          nowMinute: nowMinute,
        ),
    };
    final consumed =
        summary?.consumed ??
        dailyMeals.fold<NutritionValues>(
          NutritionValues.zero,
          (sum, meal) => sum + meal.nutrition,
        );
    final remaining = target == null
        ? null
        : NutritionValues(
            kcal: (target.calorieMaxKcal - consumed.kcal).clamp(
              0.0,
              double.infinity,
            ),
            proteinGrams: (target.proteinMaxGrams - consumed.proteinGrams)
                .clamp(0.0, double.infinity),
            carbsGrams: (target.carbsMaxGrams - consumed.carbsGrams).clamp(
              0.0,
              double.infinity,
            ),
            fatGrams: (target.fatMaxGrams - consumed.fatGrams).clamp(
              0.0,
              double.infinity,
            ),
          );
    final budgetText = target == null
        ? '今天尚未设置营养目标；只按菜品营养与餐次选择，不编造预算。'
        : [
            '今日已摄入 ${consumed.kcal.round()} kcal，蛋白质 ${consumed.proteinGrams.round()}g，碳水 ${consumed.carbsGrams.round()}g，脂肪 ${consumed.fatGrams.round()}g。',
            '剩余上限 ${remaining!.kcal.round()} kcal，蛋白质 ${remaining.proteinGrams.round()}g，碳水 ${remaining.carbsGrams.round()}g，脂肪 ${remaining.fatGrams.round()}g。',
            for (final slot in activeSlots)
              '${slot.label}预算 ${budgetMin[slot]?.round() ?? 0}–${budgetMax[slot]?.round() ?? 0} kcal。',
          ].join('\n');
    final slotSchema = activeSlots
        .map((slot) => '"${slot.storedValue}":["dishId"]')
        .join(',');
    final recordedText = recorded.keys.isEmpty
        ? '无'
        : recorded.keys.map((slot) => slot.label).join('、');

    // 清单按**一份**给数：模型据此分配预算，展示与应用也用同一份结果。
    final list = [
      for (final supply in allowed)
        '${supply.id}\t${supply.displayName}\t'
            '${supply.kcalPerServing!.round()} kcal/份\t'
            '每份 ${_num(supply.servingGrams!)}g\t'
            '供应时段 ${supply.servingWindow}\t'
            '蛋白质 ${_gramsOf(supply.proteinPer100g!, supply.servingGrams!)}g\t'
            '碳水 ${_gramsOf(supply.carbsPer100g!, supply.servingGrams!)}g\t'
            '脂肪 ${_gramsOf(supply.fatPer100g!, supply.servingGrams!)}g',
    ].join('\n');
    final constraintLine = dietaryConstraintsPromptLine(constraints);
    final system =
        '你是食堂菜单规划器。**只能**从下面清单里选菜（第一列 dishId 原样输出），'
        '不许编造清单外的菜，也不许使用食物库食材。'
        '已记录餐次：$recordedText；这些餐次已经吃完，禁止再次推荐或输出。'
        '根据今日目标和已摄入营养分配剩余量，不得随机选菜，不得超过各餐热量预算。\n'
        '${constraintLine == null ? '' : '$constraintLine\n'}'
        '$budgetText\n'
        '输出**严格 JSON**（不要代码块、不要解释）：{$slotSchema}；'
        '每餐 1–3 道；全部不得重复；只能安排在供应时段覆盖的餐次。'
        '\n清单（营养均为每份）：\n$list';

    final buffer = StringBuffer();
    try {
      final stream = service.sendMessage(
        messages: [
          ConversationMessage(
            id: 'swap-set-${now().toUtc().microsecondsSinceEpoch}',
            role: ConversationRole.user,
            text: '按食堂目录给我换一套今日三餐推荐。',
            createdAt: now().toUtc(),
          ),
        ],
        onProgress: buffer.write,
        systemContext: system,
      );
      await stream.drain<void>();
    } on Object {
      return const MenuSetSwapResult.unavailable(
        MenuSetSwapUnavailableReason.requestFailed,
      );
    }

    final decoded = _decode(buffer.toString());
    if (decoded == null) {
      return const MenuSetSwapResult.unavailable(
        MenuSetSwapUnavailableReason.unusableOutput,
      );
    }

    var filtered = 0;
    final seen = <String>{};
    final bySlot = <MealSlot, List<DishRecord>>{};
    for (final entry in decoded.entries) {
      // 模型即使违背提示词重新输出已记录餐次，也不能上屏。这个校验必须在
      // 本地，不能把「跳过」寄托在模型自觉上。
      if (!activeSlots.contains(entry.key)) {
        filtered += entry.value.length;
        continue;
      }
      final dishes = <DishRecord>[];
      var slotKcal = 0.0;
      for (final id in entry.value) {
        final dish = byId[id];
        // 硬校验：不在清单（编造/食物库食材）或跨餐重复 → 丢弃并计数。
        if (dish == null ||
            seen.contains(id) ||
            !_isSuppliedForSlot(dish, entry.key)) {
          filtered++;
          continue;
        }
        // 即使模型违背提示词，饮食约束也在本地再挡一次。
        if (dishNameConflictsWithConstraints(dish.displayName, constraints)) {
          filtered++;
          continue;
        }
        final maxKcal = budgetMax[entry.key];
        final dishKcal = dish.kcalPerServing!;
        if (maxKcal != null && slotKcal + dishKcal > maxKcal + 0.001) {
          // 超预算的组合也不接受；不能一边展示「剩余 600」一边推 900。
          filtered++;
          continue;
        }
        seen.add(id);
        dishes.add(_toDishRecord(dish, entry.key));
        slotKcal += dishKcal;
        if (dishes.length >= 3) break;
      }
      if (dishes.isNotEmpty) bySlot[entry.key] = dishes;
    }
    if (bySlot.isEmpty) {
      return MenuSetSwapResult.unavailable(
        MenuSetSwapUnavailableReason.unusableOutput,
        filtered: filtered,
      );
    }
    return MenuSetSwapResult(bySlot: bySlot, filtered: filtered);
  }

  /// 复用本地推荐的窗口/餐次规则，不能把「时段正确」寄托在 AI 自觉上。
  bool _isSuppliedForSlot(SupplyCatalogItem supply, MealSlot slot) =>
      buildDailyMealRecommendation(
        dishes: [_toDishRecord(supply, slot)],
        recordedKcalBySlot: {
          for (final other in mealRecommendationSlots)
            if (other != slot) other: 0,
        },
        nowMinute: 0,
      ).meals.any((meal) => meal.slot == slot && meal.primary != null);

  /// 解析 AI 输出：抓首个 `{` 到末个 `}`，按 JSON 解；键只认三个餐次。
  Map<MealSlot, List<String>>? _decode(String raw) {
    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    Object? json;
    try {
      json = jsonDecode(raw.substring(start, end + 1));
    } on FormatException {
      return null;
    }
    if (json is! Map<String, dynamic>) return null;
    const keys = {
      'breakfast': MealSlot.breakfast,
      'lunch': MealSlot.lunch,
      'dinner': MealSlot.dinner,
    };
    final out = <MealSlot, List<String>>{};
    for (final entry in keys.entries) {
      final value = json[entry.key];
      if (value is! List) continue;
      final ids = [
        for (final item in value)
          if (item is String && item.trim().isNotEmpty) item.trim(),
      ];
      if (ids.isNotEmpty) out[entry.value] = ids;
    }
    return out.isEmpty ? null : out;
  }

  /// 供应 → 推荐卡用的 `DishRecord`（docs/67 §6.5）。
  ///
  /// 映射本身在 [supplyDishCandidates] 里，与本地每日推荐**同一份**实现：
  /// 预算比较、卡上展示、应用后的克数因此都来自同一份解析结果。
  DishRecord _toDishRecord(SupplyCatalogItem supply, MealSlot slot) {
    final mapped = supplyDishCandidates([supply], now: now()).single;
    return DishRecord(
      id: mapped.id,
      name: mapped.name,
      mealSlot: slot.storedValue,
      servingWindow: mapped.servingWindow,
      kcal: mapped.kcal,
      proteinG: mapped.proteinG,
      carbsG: mapped.carbsG,
      fatG: mapped.fatG,
      source: mapped.source,
      imagePath: mapped.imagePath,
      servingGrams: mapped.servingGrams,
      basisAssumed: mapped.basisAssumed,
      sourceType: mapped.sourceType,
      sourceId: mapped.sourceId,
      createdAt: mapped.createdAt,
      updatedAt: mapped.updatedAt,
    );
  }

  static String _num(double value) => value == value.roundToDouble()
      ? value.round().toString()
      : value.toStringAsFixed(1);

  static String _gramsOf(double per100g, double servingGrams) =>
      _num(per100g * servingGrams / 100);
}
