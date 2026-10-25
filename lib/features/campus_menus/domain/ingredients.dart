/// 配料与过敏原（docs/40 §2.5 / docs/41 D5）。
///
/// 一条原则：**过敏原不单独存，由食材推导**——「改了食材忘了改过敏原」是
/// 这类数据最容易出的错。三层来源的权威顺序是**用户 > AI > 词典**：
/// 用户改过就 `userEdited`，AI 不再覆盖；没有 AI 时词典兜底（离线可用）。
///
/// 诚实边界：**没有配料数据就不假装安全**——`CanteenIngredientInfo.isConfirmed`
/// 为 false 的菜在推荐卡上标「配料未确认」，绝不写「不含 X」。
library;

import 'dart:convert';

/// 配料来源（权威从高到低）。
enum IngredientSource {
  user('用户确认'),
  ai('AI 推断'),
  dictionary('关键词推测');

  const IngredientSource(this.label);
  final String label;

  static IngredientSource parse(String? raw) {
    for (final value in values) {
      if (raw == value.name || raw == value.label) return value;
    }
    return IngredientSource.dictionary;
  }

  /// 权威排序：数字越小越权威。
  int get rank => index;
}

/// 一条配料。
final class IngredientEntry {
  const IngredientEntry({
    required this.name,
    required this.source,
    this.confidence = 0.5,
  });

  final String name;
  final IngredientSource source;

  /// 0–1；用户手填恒 1.0。
  final double confidence;

  Map<String, Object?> toJson() => {
    'name': name,
    'source': source.name,
    'confidence': confidence,
  };

  static IngredientEntry? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final name = raw['name'];
    if (name is! String || name.trim().isEmpty) return null;
    return IngredientEntry(
      name: name.trim(),
      source: IngredientSource.parse(raw['source'] as String?),
      confidence:
          (raw['confidence'] as num?)?.toDouble().clamp(0.0, 1.0) ?? 0.5,
    );
  }
}

/// 菜品配料的解析视图（`menu_items.ingredients_json`）。
final class CanteenIngredientInfo {
  const CanteenIngredientInfo({required this.entries, this.userEdited = false});

  static const empty = CanteenIngredientInfo(entries: []);

  final List<IngredientEntry> entries;

  /// 用户是否改过（改过则 AI/同步不得覆盖）。
  final bool userEdited;

  bool get isEmpty => entries.isEmpty;

  /// 已确认 = 至少有一条用户来源的配料（AI/词典都只是推断）。
  bool get isConfirmed =>
      entries.any((entry) => entry.source == IngredientSource.user);

  /// 状态徽标文案（docs/40 §2.5）。
  String get badgeLabel {
    if (isEmpty) return '配料未确认';
    if (isConfirmed) return '配料：已确认';
    if (entries.any((entry) => entry.source == IngredientSource.ai)) {
      return '配料：AI 推断';
    }
    return '配料：关键词推测';
  }

  /// 推导出的过敏原组名（**由食材推导，不单独存**）。
  ///
  /// 例如「鸡蛋」→「蛋类」、「面粉」→「麸质」、「虾」→「甲壳类」。
  Set<String> get derivedAllergens => {
    for (final entry in entries) ...allergensForIngredient(entry.name),
  };

  /// 与用户忌口清单的交集（硬过滤的判据）。
  ///
  /// 匹配规则：`忌口词 ∩（食材名 ∪ 别名 ∪ 过敏原组名）`，归一化后包含匹配。
  Set<String> conflictsWith(List<String> avoidances) {
    final conflicts = <String>{};
    final allergens = derivedAllergens;
    for (final avoidance in avoidances) {
      final needle = _normalize(avoidance);
      if (needle.isEmpty) continue;
      for (final entry in entries) {
        final name = _normalize(entry.name);
        if (name.contains(needle) || needle.contains(name)) {
          conflicts.add(avoidance);
        }
      }
      for (final allergen in allergens) {
        if (_normalize(allergen).contains(needle) ||
            needle.contains(_normalize(allergen))) {
          conflicts.add(avoidance);
        }
      }
    }
    return conflicts;
  }

  /// 合并 AI 起草的配料：**用户已确认的条目保留**，AI 只补空缺。
  CanteenIngredientInfo mergeAi(List<IngredientEntry> aiEntries) {
    if (userEdited) return this;
    final byName = {for (final entry in entries) _normalize(entry.name): entry};
    final merged = <IngredientEntry>[...entries];
    for (final ai in aiEntries) {
      final key = _normalize(ai.name);
      final existing = byName[key];
      if (existing == null) {
        merged.add(
          IngredientEntry(
            name: ai.name,
            source: IngredientSource.ai,
            confidence: ai.confidence,
          ),
        );
      } else if (existing.source == IngredientSource.dictionary) {
        // 词典推测被 AI 推断升档（不改变用户条目）。
        merged[merged.indexOf(existing)] = IngredientEntry(
          name: ai.name,
          source: IngredientSource.ai,
          confidence: ai.confidence,
        );
      }
    }
    return CanteenIngredientInfo(entries: merged);
  }

  /// 用户编辑：整表替换并置 `userEdited=true`。
  CanteenIngredientInfo withUserEntries(List<String> names) =>
      CanteenIngredientInfo(
        entries: [
          for (final name in names)
            if (name.trim().isNotEmpty)
              IngredientEntry(
                name: name.trim(),
                source: IngredientSource.user,
                confidence: 1.0,
              ),
        ],
        userEdited: true,
      );

  String encode() => jsonEncode([for (final entry in entries) entry.toJson()]);

  static CanteenIngredientInfo decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return empty;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return empty;
      return CanteenIngredientInfo(
        entries: [for (final item in decoded) ?IngredientEntry.tryParse(item)],
      );
    } on FormatException {
      return empty;
    }
  }
}

/// 食材 → 过敏原组（docs/40 §2.5 的推导表）。
///
/// 只做**确定性的常见映射**；查不到的食材返回空集（不猜）。
Set<String> allergensForIngredient(String name) {
  final value = _normalize(name);
  final out = <String>{};
  for (final entry in _allergenTable.entries) {
    for (final keyword in entry.value) {
      if (value.contains(keyword)) {
        out.add(entry.key);
        break;
      }
    }
  }
  return out;
}

const Map<String, List<String>> _allergenTable = {
  '蛋类': ['蛋', '鸡蛋', '鸭蛋', '鹌鹑蛋', '皮蛋', '蛋黄', '蛋白'],
  '乳制品': ['牛奶', '奶油', '奶酪', '黄油', '酸奶', '炼乳', '奶粉', '芝士'],
  '麸质': ['面粉', '面条', '面包', '馒头', '包子', '饺子', '饼干', '麦', '意面'],
  '甲壳类': ['虾', '蟹', '龙虾', '小龙虾'],
  '大豆': ['黄豆', '豆腐', '豆浆', '豆干', '腐竹', '豆皮', '毛豆', '酱油'],
  '花生': ['花生', '花生米'],
  '树坚果': ['核桃', '腰果', '杏仁', '榛子', '开心果', '松子', '夏威夷果'],
  '鱼类': ['鱼', '鲈鱼', '带鱼', '三文鱼', '鳕鱼', '鲅鱼', '鱼丸'],
  '芝麻': ['芝麻', '香油', '麻酱'],
};

/// 本地词典：按菜名关键词推测主要食材（没有 AI 时的离线兜底）。
///
/// 刻意保守：只推**名字里明确出现**的食材（「番茄炒蛋」→ 番茄/鸡蛋），
/// 不猜隐藏配料（油/盐/酱料）。猜测一律标 [IngredientSource.dictionary]。
List<IngredientEntry> dictionaryIngredients(String dishName) {
  final name = _normalize(dishName);
  final found = <String>{};
  for (final entry in _ingredientKeywords.entries) {
    for (final keyword in entry.value) {
      if (name.contains(_normalize(keyword))) {
        found.add(entry.key);
        break;
      }
    }
  }
  return [
    for (final ingredient in found)
      IngredientEntry(
        name: ingredient,
        source: IngredientSource.dictionary,
        confidence: 0.4,
      ),
  ];
}

const Map<String, List<String>> _ingredientKeywords = {
  '番茄': ['番茄', '西红柿'],
  '鸡蛋': ['蛋', '鸡蛋'],
  '土豆': ['土豆', '洋芋', '马铃薯'],
  '青椒': ['青椒'],
  '牛肉': ['牛', '牛肉'],
  '猪肉': ['猪肉', '五花', '里脊', '排骨', '肉丝', '肉片'],
  '鸡肉': ['鸡', '鸡肉', '鸡丁', '鸡翅'],
  '鱼': ['鱼'],
  '虾': ['虾'],
  '豆腐': ['豆腐'],
  '米饭': ['饭', '米饭'],
  '面条': ['面', '面条', '拉面', '拌面'],
  '白菜': ['白菜'],
  '包菜': ['包菜', '卷心菜'],
  '西兰花': ['西兰花'],
  '茄子': ['茄子'],
  '豆角': ['豆角', '四季豆'],
  '黄瓜': ['黄瓜'],
  '木耳': ['木耳'],
  '香菇': ['香菇', '蘑菇'],
  '胡萝卜': ['胡萝卜'],
  '洋葱': ['洋葱'],
  '蒜': ['蒜'],
  '辣椒': ['辣椒', '剁椒', '辣'],
};

String _normalize(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'[\s\u3000]+'), '')
    .replaceAll(RegExp(r'''[，。！？、；：,.!?;:（）()「」“”"'`]'''), '');
