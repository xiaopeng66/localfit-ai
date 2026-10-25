import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/features/food_scan/data/meal_estimate_json_decoder.dart';
import 'package:localfit_ai/features/food_scan/domain/meal_estimate.dart';

void main() {
  const decoder = MealEstimateJsonDecoder();

  group('MealEstimateJsonDecoder', () {
    test('maps a valid v1 document and ignores unknown fields', () {
      final result = decoder.decode(_validDocument());

      expect(result.mealNotes, '午餐');
      expect(result.warnings, ['酱汁用量需确认']);
      expect(result.items, hasLength(1));
      final item = result.items.single;
      expect(item.name, '米饭');
      expect(item.estimatedGrams, 180);
      expect(item.gramsRange.min, 140);
      expect(item.gramsRange.max, 220);
      expect(item.cookingMethod, '蒸煮');
      expect(item.ingredients, ['大米']);
      expect(item.confidence, 0.78);
      expect(item.needsConfirmation, isFalse);
      expect(item.questions, isEmpty);
    });

    test('rejects malformed roots and unsupported schema versions', () {
      for (final document in [
        'not-json',
        '[]',
        _validDocument(version: 2),
        _validDocument(version: 1.0),
      ]) {
        expect(() => decoder.decode(document), throwsA(isA<FormatException>()));
      }
    });

    test('rejects missing required root and item fields', () {
      for (final document in [
        '{"schema_version":1}',
        _validDocument(
          item: '{"estimated_grams":180,"grams_range":{"min":140,"max":220},"cooking_method":"蒸煮","ingredients":[],"confidence":0.78,"needs_confirmation":false,"questions":[]}',
        ),
        _validDocument(
          item: '{"name":"米饭","grams_range":{"min":140,"max":220},"cooking_method":"蒸煮","ingredients":[],"confidence":0.78,"needs_confirmation":false,"questions":[]}',
        ),
        _validDocument(
          item: '{"name":"米饭","estimated_grams":180,"confidence":0.78,"cooking_method":"蒸煮","ingredients":[],"needs_confirmation":false,"questions":[]}',
        ),
        _validDocument(
          item: '{"name":"米饭","estimated_grams":180,"grams_range":{"min":140,"max":220},"cooking_method":"蒸煮","ingredients":[],"needs_confirmation":false,"questions":[]}',
        ),
        _validDocument(
          item: '{"name":"米饭","estimated_grams":180,"grams_range":{"min":140,"max":220},"confidence":0.78}',
        ),
      ]) {
        expect(() => decoder.decode(document), throwsA(isA<FormatException>()));
      }
    });

    test('rejects invalid numeric values and ranges', () {
      for (final item in [
        _item(estimatedGrams: '-1', min: '0', max: '220'),
        _item(estimatedGrams: '180', min: '200', max: '220'),
        _item(estimatedGrams: '180', min: '140', max: '160'),
        _item(estimatedGrams: '180', min: '220', max: '140'),
        _item(confidence: '1.01'),
        _item(confidence: '-0.01'),
        _item(estimatedGrams: '5000.1', min: '0', max: '5000.1'),
      ]) {
        expect(
          () => decoder.decode(_validDocument(item: item)),
          throwsA(isA<FormatException>()),
        );
      }
    });

    test('rejects invalid descriptive field types and list entries', () {
      for (final document in [
        _validDocument(warnings: '"not-a-list"'),
        _validDocument(item: _item(cookingMethod: 'false')),
        _validDocument(item: _item(ingredients: '[""]')),
      ]) {
        expect(() => decoder.decode(document), throwsA(isA<FormatException>()));
      }
    });

    test('classifies an empty item list as a recoverable empty result', () {
      expect(
        () => decoder.decode('{"schema_version":1,"items":[]}'),
        throwsA(isA<MealEstimateEmptyResult>()),
      );
    });

    test('rejects oversized documents, items, and text', () {
      final tooManyItems = List.filled(
        MealEstimateJsonDecoder.maxItems + 1,
        _defaultItem,
      ).join(',');
      final tooLongName = '食' * (MealEstimateJsonDecoder.maxTextLength + 1);

      for (final document in [
        ' ' * (MealEstimateJsonDecoder.maxJsonLength + 1),
        _validDocument(items: tooManyItems),
        _validDocument(item: _item(name: '"$tooLongName"')),
      ]) {
        expect(() => decoder.decode(document), throwsA(isA<FormatException>()));
      }
    });
  });
}

const _defaultItem =
    '{"name":"米饭","estimated_grams":180,"grams_range":{"min":140,"max":220},"cooking_method":"蒸煮","ingredients":["大米"],"confidence":0.78,"needs_confirmation":false,"questions":[],"future_item_field":true}';

String _validDocument({
  num version = 1,
  String? item,
  String? items,
  String? warnings,
}) {
  return '{"schema_version":$version,"items":[${items ?? item ?? _defaultItem}],"meal_notes":"午餐","warnings":${warnings ?? '["酱汁用量需确认"]'},"future_root_field":{"ignored":true}}';
}

String _item({
  String name = '"米饭"',
  String estimatedGrams = '180',
  String min = '140',
  String max = '220',
  String cookingMethod = '"蒸煮"',
  String ingredients = '["大米"]',
  String confidence = '0.78',
  String needsConfirmation = 'false',
  String questions = '[]',
}) {
  return '{"name":$name,"estimated_grams":$estimatedGrams,"grams_range":{"min":$min,"max":$max},"cooking_method":$cookingMethod,"ingredients":$ingredients,"confidence":$confidence,"needs_confirmation":$needsConfirmation,"questions":$questions}';
}
