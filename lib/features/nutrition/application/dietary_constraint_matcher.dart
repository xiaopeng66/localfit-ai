/// 饮食约束的**本地保守匹配**。
///
/// `foods.allergens_json` 在 schema 22 已删除，本地菜品没有结构化的配料表。
/// 因此这里只按菜名做**保守排除**：命中常见食材词就不推荐。它是安全兜底，
/// 不是营养学判定——AI 对话侧另有完整约束段，能按语义判断；本地菜单这边
/// 宁可多排除，也不把明显冲突的菜端上来。
///
/// 匹配口径：
/// * 自定义忌口/过敏原：菜名包含该词（归一化后）。
/// * 预设过敏原：按常见同义词表匹配（「蛋类」也要命中「鸡蛋」）。
/// * 饮食标签：素食排除常见肉/鱼/海鲜词；纯素再加蛋奶蜂蜜；无乳制品/无麸质
///   按对应食材词排除。
library;

import 'package:localfit_ai/features/daily_plan/domain/planning_constraints.dart';
import 'package:localfit_ai/features/nutrition/domain/dish_record.dart';

/// 菜品是否与约束冲突（true = 不应推荐）。
bool dishConflictsWithConstraints(
  DishRecord dish,
  PlanningConstraints? constraints,
) => dishNameConflictsWithConstraints(dish.name, constraints);

/// 同上，但只拿菜名：AI 换一套的候选是 `CanteenDish`，过滤池时不必先转
/// `DishRecord`。
bool dishNameConflictsWithConstraints(
  String dishName,
  PlanningConstraints? constraints,
) {
  if (constraints == null || constraints.isEmpty) return false;
  final name = _normalize(dishName);
  if (name.isEmpty) return false;

  for (final allergen in constraints.allergenAvoidances) {
    final keywords = _allergenKeywords[allergen] ?? [allergen];
    for (final keyword in keywords) {
      if (name.contains(_normalize(keyword))) return true;
    }
  }

  final labels = constraints.dietaryLabels.toSet();
  if (labels.contains(DietaryLabel.vegetarian) && _containsAny(name, _meat)) {
    return true;
  }
  if (labels.contains(DietaryLabel.vegan) &&
      _containsAny(name, [..._meat, ..._dairy, ..._egg, '蜂蜜'])) {
    return true;
  }
  if (labels.contains(DietaryLabel.dairyFree) && _containsAny(name, _dairy)) {
    return true;
  }
  if (labels.contains(DietaryLabel.glutenFree) && _containsAny(name, _gluten)) {
    return true;
  }
  return false;
}

/// AI 提示词里的一行硬约束。空约束返回 null（不往 prompt 里塞废话）。
String? dietaryConstraintsPromptLine(PlanningConstraints? constraints) {
  if (constraints == null || constraints.isEmpty) return null;
  final parts = <String>[
    if (constraints.dietaryLabels.isNotEmpty)
      '饮食标签：${constraints.dietaryLabels.map((item) => item.label).join('、')}',
    if (constraints.allergenAvoidances.isNotEmpty)
      '忌口/过敏原：${constraints.allergenAvoidances.join('、')}',
  ];
  return '用户饮食硬约束（${parts.join('；')}）。推荐、组合或替换菜品时'
      '必须避开；宁可少推荐，也不得违反。';
}

const Map<String, List<String>> _allergenKeywords = {
  '蛋类': ['蛋'],
  '乳制品': ['奶', '乳', '芝士', '奶酪', '黄油', '奶油'],
  '大豆': ['大豆', '黄豆', '豆腐', '豆浆', '豆干', '腐竹', '毛豆', '豆皮'],
  '麸质': [
    '小麦',
    '面粉',
    '面条',
    '面包',
    '馒头',
    '饼',
    '麸',
    '意面',
    '拉面',
    '乌冬',
    '油条',
    '包子',
    '饺子',
    '面',
  ],
  '花生': ['花生'],
  '树坚果': ['坚果', '核桃', '杏仁', '腰果', '榛子', '开心果', '松子'],
  '鱼类': ['鱼', '鲈', '鳕', '三文', '金枪', '带鱼', '鲫', '鲤'],
  '甲壳类': ['虾', '蟹', '龙虾'],
  '芝麻': ['芝麻', '麻酱'],
};

const List<String> _meat = [
  '猪肉',
  '牛肉',
  '羊肉',
  '鸡肉',
  '鸭肉',
  '鹅肉',
  '鱼',
  '虾',
  '蟹',
  '贝',
  '海鲜',
  '排骨',
  '香肠',
  '火腿',
  '培根',
  '肉丸',
  '肉丝',
  '肉片',
  '肉末',
  '鸡胸',
  '鸡腿',
  '鸡翅',
  '鸡排',
  '炸鸡',
  '烤鸭',
  '烧鹅',
  '猪脚',
  '牛腩',
  '牛排',
  '猪排',
  '羊排',
  '腊肉',
  '腊肠',
  '午餐肉',
  '肉酱',
  '肉松',
];

const List<String> _dairy = ['奶', '乳', '芝士', '奶酪', '黄油', '奶油'];
const List<String> _egg = ['蛋'];
const List<String> _gluten = [
  '小麦',
  '面粉',
  '面条',
  '面包',
  '馒头',
  '饼',
  '麸',
  '意面',
  '拉面',
  '乌冬',
  '油条',
  '包子',
  '饺子',
  '面',
];

bool _containsAny(String name, List<String> keywords) {
  for (final keyword in keywords) {
    if (name.contains(_normalize(keyword))) return true;
  }
  return false;
}

String _normalize(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'[\s\u3000]+'), '');
