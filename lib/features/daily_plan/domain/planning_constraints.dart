import 'dart:convert';

/// 用户的饮食偏好与过敏原回避（存在 `profiles` 的
/// `dietaryPreferencesJson` / `allergenAvoidancesJson` 两列上）。
///
/// 位置说明（docs/28 §6.4 落地记录）：本文件原先在 `features/recipe_planning/`
/// 下，该目录随「食谱 / 计划」整族下线被删除。但这个模型**不是**食谱计划私有的
/// ——`DailyPlanEngine` 用 `allergenAvoidancesJson` 过滤推荐（活跃消费者），
/// 对话命令 `constraints.set` 是它唯一的写入者，所以按 docs/28 §6.7 对
/// `planning_facts_editor_dialog` 的同一处理办法搬到中立位置保留，行为零变化。
///
/// 2026-10-09（docs/31 S2）：**两个 enum 搬进本文件**。它们原住在
/// `features/nutrition/domain/food_constraint_facts.dart`（与食物侧的
/// `FoodConstraintFacts` 同处），该文件随「过敏原与饮食标签」整块下线被删
/// （需求 50）。enum 本身**不能删**——本文件与 `constraints.set` 命令还在用
/// 它们表达「我花生过敏」。搬到**唯一存活的消费者**身边，比留一个只为放
/// 两个 enum 而存在的营养域空壳文件诚实（docs/31 §2 D5）。
final class PlanningConstraints {
  const PlanningConstraints({
    this.dietaryLabels = const [],
    this.allergenAvoidances = const [],
  });

  static const maxDietaryLabels = 4;
  static const maxAllergenAvoidances = 9;

  final List<DietaryLabel> dietaryLabels;
  final List<String> allergenAvoidances;

  bool get isEmpty => dietaryLabels.isEmpty && allergenAvoidances.isEmpty;

  void validate() {
    if (dietaryLabels.length > maxDietaryLabels ||
        allergenAvoidances.length > maxAllergenAvoidances ||
        dietaryLabels.toSet().length != dietaryLabels.length ||
        allergenAvoidances.toSet().length != allergenAvoidances.length) {
      throw const FormatException('饮食偏好或过敏原避开项无效。');
    }
  }

  String get dietaryLabelsJson =>
      _encode(dietaryLabels.map((item) => item.name));
  String get allergenAvoidancesJson => _encode(allergenAvoidances);

  static PlanningConstraints fromStorage({
    required String dietaryLabelsJson,
    required String allergenAvoidancesJson,
  }) {
    final constraints = PlanningConstraints(
      dietaryLabels: _decode(dietaryLabelsJson, DietaryLabel.values),
      allergenAvoidances: [
        for (final value in _decodeRaw(allergenAvoidancesJson))
          if (value.trim().isNotEmpty) value.trim(),
      ],
    );
    constraints.validate();
    return constraints;
  }
}

/// 饮食标签（profiles 侧「我的 → 饮食约束」与 `constraints.set` 用）。
///
/// **不再出现在食物侧**：`foods.dietary_labels_json` 已随 schema 22 删除
/// （docs/31 需求 50），所以现在没有「这条食物是素食」这种声明了。
enum DietaryLabel {
  vegetarian('素食'),
  vegan('纯素'),
  dairyFree('无乳制品'),
  glutenFree('无麸质');

  const DietaryLabel(this.label);
  final String label;
}

/// 过敏原（profiles 侧回避清单用）。
///
/// **预设过敏原**（UI 下拉/提示用）。2026-10-16 起**不再是封闭集合**：
/// 用户可以声明任意食材的回避（如「芒果」）——`PlanningConstraints.allergenAvoidances`
/// 的存储与引擎读侧都是**自由字符串**（小写匹配），不受此枚举限制；
/// 对话命令 `constraints.set` 的解析器也随之放行任意非空食材名。
///
/// 历史注：`foods.allergens_json` 已随 schema 22 删除，每日计划 solver
/// 不再据此过滤推荐（docs/31 §2 D5 的已知代价，如实保留）。
enum FoodAllergen {
  egg('蛋类'),
  milk('乳制品'),
  soy('大豆'),
  gluten('麸质'),
  peanut('花生'),
  treeNut('树坚果'),
  fish('鱼类'),
  shellfish('甲壳类'),
  sesame('芝麻');

  const FoodAllergen(this.label);
  final String label;
}

String _encode(Iterable<String> values) => jsonEncode(values.toList()..sort());

List<String> _decodeRaw(String value) {
  final decoded = jsonDecode(value);
  return [
    for (final item in decoded as List<dynamic>)
      if (item is String) item,
  ];
}

List<T> _decode<T extends Enum>(String value, List<T> values) {
  final decoded = jsonDecode(value);
  if (decoded is! List || decoded.any((item) => item is! String)) {
    throw const FormatException('饮食限制信息格式无效。');
  }
  final result = decoded
      .map((item) {
        final name = item as String;
        return values.where((value) => value.name == name).firstOrNull;
      })
      .toList(growable: false);
  if (result.any((item) => item == null) ||
      result.toSet().length != result.length) {
    throw const FormatException('饮食限制信息包含不支持的值。');
  }
  return result.cast<T>();
}
