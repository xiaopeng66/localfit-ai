/// 三餐推荐引擎（docs/28 §4.3）：本地确定性、**零 AI**。
///
/// 「今天早/午/晚各吃什么」是一个纯函数问题：给同一份输入必然给同一个答案。
/// 因此这里没有随机、没有「换一个」的历史状态——排序依赖的候选顺序全部来自
/// 稳定排序（证据等级 → 与预算的差距 → `dish.id`）。同一份输入两次调用结果
/// 逐字段相同，否则用户每次进页面看到的推荐都不一样，很快就会不再相信它。
///
/// **不重写** `NextMealDecisionController`：那个控制器回答「下一餐吃什么」，
/// 仍是这件事的唯一事实源；本引擎只回答「早/午/晚各要什么」，两者共用
/// `DishLibrary` 与目标口径，但不共用状态（docs/28 §4.3 末条）。
library;

import 'package:localfit_ai/app/design/widgets/lf_evidence_badge.dart'
    show LfEvidenceGrade;
import 'package:localfit_ai/features/daily_plan/application/menu_service_window.dart'
    show parseHhmmToMinute;
import 'package:localfit_ai/features/nutrition/domain/dish_record.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_evidence.dart'
    show evidenceGradeForSource;
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart'
    show MealRecord, MealSlot;

/// 引擎负责的餐位：早 / 午 / 晚（加餐不进推荐位——它不是一顿饭）。
const mealRecommendationSlots = <MealSlot>[
  MealSlot.breakfast,
  MealSlot.lunch,
  MealSlot.dinner,
];

/// 每餐占当日目标的比例（docs/28 §4.3 规则 2，常量集中一处）。
const mealBudgetShares = <MealSlot, double>{
  MealSlot.breakfast: 0.30,
  MealSlot.lunch: 0.40,
  MealSlot.dinner: 0.30,
};

/// 三餐时段带（当天分钟数，左闭右开）。
///
/// 分界与 `NextMealDecisionController._slotFor` 完全同源（早 ≤09:30、
/// 午 ≤14:00、晚 ≤20:30），否则会出现「推荐卡说是午餐、这张卡说窗口关着」
/// 这种自相矛盾。带是给「窗口在该餐营业」用的，所以**允许一道菜同时属于
/// 多餐**（11:00–20:00 的窗口横跨午晚）——跨餐重复由规则 3 单独拦。
const _mealBands = <MealSlot, (int, int)>{
  MealSlot.breakfast: (0, 9 * 60 + 30),
  MealSlot.lunch: (9 * 60 + 30, 14 * 60),
  MealSlot.dinner: (14 * 60, 20 * 60 + 30),
};

/// 时段带的中文写法（空态里要说清「哪个时段」；页面头的「供应时段」也读它）。
const mealBandLabels = <MealSlot, String>{
  MealSlot.breakfast: '09:30 前',
  MealSlot.lunch: '09:30–14:00',
  MealSlot.dinner: '14:00–20:30',
};

/// 每餐最多给几个备选（「查看候选 N 道」里的 N）。
const mealAlternativeLimit = 5;

/// 一餐的推荐结果。
final class MealRecommendation {
  const MealRecommendation({
    required this.slot,
    required this.state,
    required this.reason,
    this.primary,
    this.alternatives = const [],
    this.budgetKcal,
    this.kcal,
    this.action = MealEmptyAction.none,
  });

  final MealSlot slot;
  final MealRecommendationState state;

  /// 主推的那一道；仅 [MealRecommendationState.recommended] 时非空。
  final DishRecord? primary;

  /// 备选（**不含主推**），按稳定排序取前 [mealAlternativeLimit] 条。
  final List<DishRecord> alternatives;

  /// 该餐预算；无当日目标时为 null（此时进度条不画，也不按预算挑）。
  final double? budgetKcal;

  /// 该餐的热量：已记录的那一餐是实际值，主推的那一餐是主推值。
  final double? kcal;

  /// 一句话说明：为什么是它 / 为什么这一餐给不出推荐。
  final String reason;

  /// 空态能做的事（只有真的接了线的那几种）。
  ///
  /// 它是个**枚举而不是文案**：页面按它决定画不画按钮，文案在页面侧写。
  /// 用文案匹配（`label == '去维护食堂目录'`）决定接线会在改一个字之后
  /// 静默变成「按钮不见」或「点了没反应」。
  final MealEmptyAction action;
}

/// 空态的行动（docs/28 §4.1「空态：一句成因 + 一个行动」）。
enum MealEmptyAction {
  /// 没有可做的事：不画按钮，宁可只报成因也不给点了没反应的入口。
  ///
  /// 「这一餐的时段已经过了」属于这一类——补救方式是去记录吃过什么，
  /// 而记录入口不在这张页面上，画一个跳不过去的按钮就是撒谎。
  none,

  /// 去维护食堂目录（还没有窗口/菜品，或本餐候选被前面几餐用光了）。
  openCanteen,
}

enum MealRecommendationState {
  /// 当天已经记录过这一餐（推荐不再插嘴）。
  planned,

  /// 有主推。
  recommended,

  /// 给不出推荐（成因写在 [MealRecommendation.reason]）。
  empty,
}

/// 三餐推荐的完整输出。
final class DailyMealRecommendation {
  const DailyMealRecommendation({
    required this.meals,
    required this.plannedMeals,
    required this.plannedKcal,
  });

  final List<MealRecommendation> meals;

  /// 已安排 = 当天已记录的餐 + 有主推的餐。
  final int plannedMeals;

  /// 已记录的实际热量 + 主推菜品的热量。
  final double plannedKcal;
}

/// 产出三餐推荐。
///
/// 输入全部显式传入（含「现在几点」与「已记录的餐」），所以单测不需要
/// 假装时间、也不需要数据库：这是它可测的前提。
///
/// - [dishes]：`DishLibrary` 全量（**已分析**的菜品；调用方不必过滤）。
/// - [recordedKcalBySlot]：当天已记录餐食的热量，按餐位。
/// - [dailyTargetKcal]：`DailyTargets.calorieMaxKcal`；null = 没有当日目标。
/// - [nowMinute]：当天分钟数，用来判「这一餐的时段已经过了」。
DailyMealRecommendation buildDailyMealRecommendation({
  required List<DishRecord> dishes,
  Map<MealSlot, double> recordedKcalBySlot = const {},
  double? dailyTargetKcal,
  required int nowMinute,
}) {
  final budgets = _mealBudgets(
    recordedKcalBySlot: recordedKcalBySlot,
    dailyTargetKcal: dailyTargetKcal,
    nowMinute: nowMinute,
  );

  // 规则 3：同一道菜只出现在一餐。整个循环共用这一个集合，所以第二餐
  // 不会拿到第一餐已经推过的菜；候选被前面吃光时给空态而不是回头重挑。
  final used = <String>{};
  final meals = <MealRecommendation>[];

  for (final slot in mealRecommendationSlots) {
    meals.add(
      _recommendForSlot(
        slot: slot,
        dishes: dishes,
        recordedKcal: recordedKcalBySlot[slot],
        budgetKcal: budgets[slot],
        nowMinute: nowMinute,
        used: used,
      ),
    );
  }

  var plannedMeals = 0;
  var plannedKcal = 0.0;
  for (final meal in meals) {
    final kcal = meal.kcal;
    if (kcal == null) continue;
    plannedMeals++;
    plannedKcal += kcal;
  }
  return DailyMealRecommendation(
    meals: meals,
    plannedMeals: plannedMeals,
    plannedKcal: plannedKcal,
  );
}

MealRecommendation _recommendForSlot({
  required MealSlot slot,
  required List<DishRecord> dishes,
  required double? recordedKcal,
  required double? budgetKcal,
  required int nowMinute,
  required Set<String> used,
}) {
  if (recordedKcal != null) {
    return MealRecommendation(
      slot: slot,
      state: MealRecommendationState.planned,
      kcal: recordedKcal,
      budgetKcal: budgetKcal,
      reason: '已经记录了${slot.label}',
    );
  }

  final band = _mealBands[slot]!;
  if (nowMinute > band.$2) {
    return MealRecommendation(
      slot: slot,
      state: MealRecommendationState.empty,
      budgetKcal: budgetKcal,
      reason: '${slot.label}时段（${mealBandLabels[slot]}）已经过了',
      // 过去的时段：没有可执行的动作（见 MealEmptyAction.none 的注释）。
    );
  }

  final eligible = _eligibleFor(slot, dishes);
  if (eligible.isEmpty) {
    return MealRecommendation(
      slot: slot,
      state: MealRecommendationState.empty,
      budgetKcal: budgetKcal,
      reason: _emptyReason(slot, dishes),
      action: MealEmptyAction.openCanteen,
    );
  }

  final available = [
    for (final dish in eligible)
      if (!used.contains(dish.id)) dish,
  ];
  if (available.isEmpty) {
    // 规则 3 的直接后果：候选都被前面几餐占了。说清成因，不回头重挑。
    return MealRecommendation(
      slot: slot,
      state: MealRecommendationState.empty,
      budgetKcal: budgetKcal,
      reason: '这一餐的候选都被前面几餐用掉了（同一道菜不跨餐重复）',
      action: MealEmptyAction.openCanteen,
    );
  }

  available.sort((a, b) => _compare(a, b, budgetKcal));
  final primary = available.first;
  final alternatives = available.skip(1).take(mealAlternativeLimit).toList();
  // 规则 3 标的是**主推**：「不拿别餐**已推过**的菜填位」（D8）。备选不进
  // 这个集合——备选本来就是「可以再挑」的意思，把它也算作已推，等于让午餐
  // 的候选列表把晚餐的候选吃掉。
  used.add(primary.id);

  return MealRecommendation(
    slot: slot,
    state: MealRecommendationState.recommended,
    primary: primary,
    alternatives: alternatives,
    budgetKcal: budgetKcal,
    kcal: primary.kcal,
    reason: _pickReason(primary, budgetKcal),
  );
}

/// 规则 1（时段过滤）+ 规则 4（证据等级 / 营养不全不当候选）。
///
/// 时段以**窗口为准**：`servingWindow`（窗口营业时段，写入菜品库时由窗口的
/// 开关时间生成）与该餐时段带有交集才算候选；没有供应时段的菜（非食堂菜）
/// 退回到它自己的餐次标签。菜品标签是从窗口**结束时间**派生的
/// （`AddCanteenDishesToLibrary._mealSlotForWindow`），所以窗口是更强的事实。
List<DishRecord> _eligibleFor(MealSlot slot, List<DishRecord> dishes) {
  final band = _mealBands[slot]!;
  return [
    for (final dish in dishes)
      if (_isUsable(dish) && _coversBand(dish, slot, band)) dish,
  ];
}

bool _isUsable(DishRecord dish) {
  // 规则 4：`incomplete`（营养不全）不当候选；热量为 0 的条目在这张表里
  // 就是「没有营养值」（`DishLibrary` 的四项数值非空，0 = 分析没给出结果）
  // ——把 0 kcal 当一顿饭推荐给用户就是编事实。
  if (evidenceGradeForSource(dish.source) == LfEvidenceGrade.incomplete) {
    return false;
  }
  return dish.kcal > 0;
}

bool _coversBand(DishRecord dish, MealSlot slot, (int, int) band) {
  final window = dish.servingWindow?.trim();
  if (window == null || window.isEmpty) {
    return MealSlot.fromStoredValue(dish.mealSlot) == slot;
  }
  final match = RegExp(r'^(\d{2}):(\d{2})-(\d{2}):(\d{2})$').firstMatch(window);
  if (match == null) {
    // 供应时段格式不合法（历史数据）：只认餐次标签，不拿坏字符串猜。
    return MealSlot.fromStoredValue(dish.mealSlot) == slot;
  }
  final open = parseHhmmToMinute('${match.group(1)}:${match.group(2)}');
  final close = parseHhmmToMinute('${match.group(3)}:${match.group(4)}');
  return open < band.$2 && band.$1 < close;
}

/// 空态成因（规则 6「不猜」）：分清「没有菜品」与「窗口不在这个时段营业」。
String _emptyReason(MealSlot slot, List<DishRecord> dishes) {
  final tagged = dishes.where(
    (dish) =>
        _isUsable(dish) && MealSlot.fromStoredValue(dish.mealSlot) == slot,
  );
  if (tagged.isNotEmpty) {
    return '这一餐的窗口都不在${mealBandLabels[slot]}营业';
  }
  return '这一餐还没有已分析的菜品';
}

/// 规则 5：稳定排序。证据等级 → 与预算的差距 → `dish.id`。
///
/// 没有当日目标时**不按预算挑**（预算不存在，任何「最接近」都是编的），
/// 只按证据等级 + id 排——仍然是确定的。
int _compare(DishRecord a, DishRecord b, double? budgetKcal) {
  final grade = _gradeRank(a).compareTo(_gradeRank(b));
  if (grade != 0) return grade;
  if (budgetKcal != null) {
    final distance = (a.kcal - budgetKcal).abs().compareTo(
      (b.kcal - budgetKcal).abs(),
    );
    if (distance != 0) return distance;
  }
  return a.id.compareTo(b.id);
}

int _gradeRank(DishRecord dish) =>
    switch (evidenceGradeForSource(dish.source)) {
      LfEvidenceGrade.confirmed => 0,
      LfEvidenceGrade.estimated => 1,
      LfEvidenceGrade.incomplete => 2,
    };

String _pickReason(DishRecord dish, double? budgetKcal) {
  final grade = evidenceGradeForSource(dish.source) == LfEvidenceGrade.confirmed
      ? '已确认数据'
      : 'AI 估算';
  if (budgetKcal == null) {
    return '$grade里按证据等级挑的（还没有当日目标，不按预算推荐）';
  }
  return '$grade里离这一餐预算（约 ${budgetKcal.round()} kcal）最近';
}

/// 规则 2：按**剩余目标**分配三餐预算。
///
/// 已经记录过的那一餐不再参与分配（它的预算已经被吃掉了），剩余目标只分给
/// 还没吃的餐位——否则「早餐已吃 600 kcal，午餐预算还按全天 40% 算」会把
/// 同一天的目标算两遍。没有当日目标时三餐预算都是 null。
Map<MealSlot, double?> _mealBudgets({
  required Map<MealSlot, double> recordedKcalBySlot,
  required double? dailyTargetKcal,
  required int nowMinute,
}) {
  final none = {for (final slot in mealRecommendationSlots) slot: null};
  if (dailyTargetKcal == null || dailyTargetKcal <= 0) return none;

  final openSlots = [
    for (final slot in mealRecommendationSlots)
      if (!recordedKcalBySlot.containsKey(slot) &&
          nowMinute <= _mealBands[slot]!.$2)
        slot,
  ];
  if (openSlots.isEmpty) return none;

  final eaten = recordedKcalBySlot.values.fold(
    0.0,
    (sum, value) => sum + value,
  );
  final remaining = dailyTargetKcal - eaten;
  if (remaining <= 0) {
    // 目标已经吃满：预算不是负数，而是「0 预算 = 这一餐不该再加」。
    return {for (final slot in openSlots) slot: 0.0};
  }
  final shareSum = openSlots.fold(
    0.0,
    (sum, slot) => sum + (mealBudgetShares[slot] ?? 0),
  );
  if (shareSum <= 0) return none;
  return {
    for (final slot in openSlots)
      slot: remaining * (mealBudgetShares[slot] ?? 0) / shareSum,
    for (final slot in mealRecommendationSlots)
      if (!openSlots.contains(slot)) slot: null,
  };
}

/// 把当天的餐食记录折算成「每餐已摄入的 kcal」。
///
/// 菜单页的三餐块与下一餐决策卡的进度条都要这份数字，所以它只有一份实现：
/// 两处各折一次，会让同一顿饭在一屏上显示两个热量。
///
/// 加餐（`snack`）也进结果——它不进推荐位，但要参与「今天还剩多少预算」。
Map<MealSlot, double> recordedKcalBySlot(List<MealRecord> meals) {
  final out = <MealSlot, double>{};
  for (final meal in meals) {
    final slot = MealSlot.fromStoredValue(meal.slot.storedValue);
    out[slot] = (out[slot] ?? 0) + meal.nutrition.kcal;
  }
  return out;
}

/// 单餐预算（`NextMealDecisionCard` 的进度条分母）。
///
/// 与三餐推荐**同一套口径**（剩余目标按 30/40/30 分给还没吃、还没过的餐位）。
/// 两处各算一套比例，会让「推荐卡说本餐还有 800 kcal」与「菜单页说 640」
/// 同时出现在用户的屏幕上——同一个数字两个值，用户只会两个都不信。
///
/// [MealSlot.snack] 不是推荐位，恒返回 null（加餐没有预算这回事）。
double? mealBudgetFor({
  required MealSlot slot,
  Map<MealSlot, double> recordedKcalBySlot = const {},
  double? dailyTargetKcal,
  required int nowMinute,
}) => _mealBudgets(
  recordedKcalBySlot: recordedKcalBySlot,
  dailyTargetKcal: dailyTargetKcal,
  nowMinute: nowMinute,
)[slot];
