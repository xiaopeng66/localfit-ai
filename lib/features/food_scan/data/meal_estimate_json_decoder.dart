import 'dart:convert';

import 'package:localfit_ai/features/food_scan/domain/meal_estimate.dart';

final class MealEstimateJsonDecoder {
  const MealEstimateJsonDecoder();

  static const int schemaVersion = 1;
  static const int maxJsonLength = 64 * 1024;
  static const int maxItems = 20;
  static const int maxTextLength = 500;
  static const int maxListEntries = 20;
  static const double maxGrams = 5000;

  MealEstimateDraft decode(String json) {
    if (json.length > maxJsonLength) {
      throw FormatException('餐食估算结果不能超过 $maxJsonLength 个字符。');
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException {
      throw const FormatException('餐食估算结果不是有效 JSON。');
    }

    final root = _object(decoded, '根对象');
    final version = _requireExactInt(root, 'schema_version');
    if (version != schemaVersion) {
      throw FormatException('不支持的餐食估算版本：$version。');
    }

    final itemsValue = _required(root, 'items');
    final items = _array(itemsValue, 'items');
    if (items.isEmpty) throw const MealEstimateEmptyResult();
    if (items.length > maxItems) {
      throw FormatException('餐食条目不能超过 $maxItems 项。');
    }

    return MealEstimateDraft(
      items: List<MealEstimateItem>.unmodifiable(
        items.indexed
            .map((entry) => _item(entry.$2, entry.$1))
            .toList(growable: false),
      ),
      mealNotes: _requiredText(root, 'meal_notes'),
      warnings: _requiredStringList(root, 'warnings'),
    );
  }

  MealEstimateItem _item(Object? value, int index) {
    final object = _object(value, 'items[$index]');
    final name = _requiredText(object, 'name');
    final estimatedGrams = _requiredNumber(
      object,
      'estimated_grams',
      minimum: 0,
      maximum: maxGrams,
    );
    final range = _object(_required(object, 'grams_range'), 'grams_range');
    final min = _requiredNumber(range, 'min', minimum: 0, maximum: maxGrams);
    final max = _requiredNumber(range, 'max', minimum: 0, maximum: maxGrams);
    if (min > estimatedGrams || estimatedGrams > max) {
      throw FormatException('items[$index] 的克数估算必须位于范围内。');
    }

    return MealEstimateItem(
      name: name,
      estimatedGrams: estimatedGrams,
      gramsRange: GramRange(min: min, max: max),
      cookingMethod: _requiredText(object, 'cooking_method'),
      ingredients: _requiredStringList(object, 'ingredients'),
      confidence: _requiredNumber(object, 'confidence', minimum: 0, maximum: 1),
      needsConfirmation: _requiredBool(object, 'needs_confirmation'),
      questions: _requiredStringList(object, 'questions'),
      nutrition: _optionalNutrition(object, index),
    );
  }

  /// 可选的整份营养估算：四个字段必须成组出现（部分出现视为畸形响应）。
  /// 上限按单份 5000g 的物理上界放宽，负数/非有限数拒绝。
  MealEstimateNutrition? _optionalNutrition(Object? value, int index) {
    final object = _object(value, 'items[$index]');
    final keys = ['kcal', 'protein_g', 'carbs_g', 'fat_g'];
    final present = keys.where(object.containsKey).toList(growable: false);
    if (present.isEmpty) return null;
    if (present.length != keys.length) {
      throw FormatException(
        'items[$index] 的营养估算字段（kcal/protein_g/carbs_g/fat_g）必须成组提供。',
      );
    }
    return MealEstimateNutrition(
      kcal: _requiredNumber(object, 'kcal', minimum: 0, maximum: 20000),
      proteinGrams: _requiredNumber(
        object,
        'protein_g',
        minimum: 0,
        maximum: 2000,
      ),
      carbsGrams: _requiredNumber(object, 'carbs_g', minimum: 0, maximum: 2000),
      fatGrams: _requiredNumber(object, 'fat_g', minimum: 0, maximum: 2000),
    );
  }

  Object? _required(Map<String, Object?> object, String key) {
    if (!object.containsKey(key)) {
      throw FormatException('缺少必填字段：$key。');
    }
    return object[key];
  }

  int _requireExactInt(Map<String, Object?> object, String key) {
    final value = _required(object, key);
    if (value is! int) {
      throw FormatException('$key 必须是整数。');
    }
    return value;
  }

  String _requiredText(Map<String, Object?> object, String key) {
    final value = _required(object, key);
    if (value is! String) throw FormatException('$key 必须是文本。');
    final text = value.trim();
    if (text.length > maxTextLength) {
      throw FormatException('$key 不能超过 $maxTextLength 个字符。');
    }
    return text;
  }

  double _requiredNumber(
    Map<String, Object?> object,
    String key, {
    required double minimum,
    required double maximum,
  }) {
    final value = _required(object, key);
    if (value is! num || !value.isFinite) {
      throw FormatException('$key 必须是有限数字。');
    }
    final number = value.toDouble();
    if (number < minimum || number > maximum) {
      throw FormatException('$key 必须在 $minimum 到 $maximum 之间。');
    }
    return number;
  }

  bool _requiredBool(Map<String, Object?> object, String key) {
    final value = _required(object, key);
    if (value is! bool) throw FormatException('$key 必须是布尔值。');
    return value;
  }

  List<String> _requiredStringList(Map<String, Object?> object, String key) {
    final entries = _array(_required(object, key), key);
    if (entries.length > maxListEntries) {
      throw FormatException('$key 不能超过 $maxListEntries 项。');
    }
    return List<String>.unmodifiable(
      entries.map((entry) {
        if (entry is! String) throw FormatException('$key 必须只包含文本。');
        final text = entry.trim();
        if (text.isEmpty || text.length > maxTextLength) {
          throw FormatException('$key 不能包含空白文本或超过 $maxTextLength 个字符的文本。');
        }
        return text;
      }),
    );
  }

  Map<String, Object?> _object(Object? value, String label) {
    if (value is! Map<Object?, Object?>) {
      throw FormatException('$label 必须是对象。');
    }
    final result = <String, Object?>{};
    for (final entry in value.entries) {
      if (entry.key is! String) {
        throw FormatException('$label 的字段名必须是文本。');
      }
      result[entry.key as String] = entry.value;
    }
    return result;
  }

  List<Object?> _array(Object? value, String label) {
    if (value is! List<Object?>) throw FormatException('$label 必须是数组。');
    return value;
  }
}
