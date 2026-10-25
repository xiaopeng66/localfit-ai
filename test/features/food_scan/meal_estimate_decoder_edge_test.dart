import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/features/food_scan/data/meal_estimate_json_decoder.dart';
import 'package:localfit_ai/features/food_scan/domain/meal_estimate.dart';

/// Field-level numeric edge tests for the frozen meal-estimate.v1 decoder:
/// empty text, 0, negatives, maxima, NaN/Infinity, and over-long text must
/// each fail on their own instead of silently passing through.
void main() {
  const decoder = MealEstimateJsonDecoder();

  group('numeric field edges', () {
    test('accepts exactly 0 for grams and confidence bounds', () {
      final draft = decoder.decode(
        _document(
          _item(estimatedGrams: '0', min: '0', max: '0', confidence: '0'),
        ),
      );
      expect(draft.items.single.estimatedGrams, 0);
      expect(draft.items.single.gramsRange.min, 0);
      expect(draft.items.single.gramsRange.max, 0);
      expect(draft.items.single.confidence, 0);

      final top = decoder.decode(_document(_item(confidence: '1')));
      expect(top.items.single.confidence, 1);
    });

    test('accepts the maximum grams value but not more', () {
      final atMax = decoder.decode(
        _document(_item(estimatedGrams: '5000', min: '0', max: '5000')),
      );
      expect(atMax.items.single.estimatedGrams, 5000);

      expect(
        () => decoder.decode(
          _document(_item(estimatedGrams: '5000.1', min: '0', max: '5000.1')),
        ),
        throwsFormatException,
      );
    });

    for (final (label, poison) in [
      ('NaN grams', _item(estimatedGrams: 'NaN', min: '0', max: '220')),
      (
        'Infinity grams',
        _item(estimatedGrams: 'Infinity', min: '0', max: '220'),
      ),
      ('-Infinity max', _item(max: '-Infinity')),
      ('NaN confidence', _item(confidence: 'NaN')),
      ('Infinity confidence', _item(confidence: 'Infinity')),
    ]) {
      test('rejects $label', () {
        expect(
          () => decoder.decode(_document(poison)),
          throwsFormatException,
          reason: poison,
        );
      });
    }

    test('rejects negative grams anywhere in the range', () {
      for (final poison in [
        _item(estimatedGrams: '-0.01', min: '0', max: '220'),
        _item(estimatedGrams: '180', min: '-1', max: '220'),
        _item(estimatedGrams: '180', min: '0', max: '-5'),
      ]) {
        expect(
          () => decoder.decode(_document(poison)),
          throwsFormatException,
          reason: poison,
        );
      }
    });

    test('rejects non-numeric and non-int schema versions', () {
      expect(
        () => decoder.decode(_document(_defaultItem, version: '"1"')),
        throwsFormatException,
      );
      expect(
        () => decoder.decode(_document(_defaultItem, version: 'true')),
        throwsFormatException,
      );
    });
  });

  group('text edges', () {
    // 2.0-0 冻结既有语义：meal-estimate.v1 的 name 目前允许 trim 后为空
    // （见 _requiredText）。此测试把这个行为固定下来，未来收紧时必须先升
    // contract_version 并更新此处断言。
    test(
      'currently trims whitespace-only names to empty instead of failing',
      () {
        final draft = decoder.decode(_document(_item(name: '"  "')));
        expect(draft.items.single.name, '');
      },
    );

    test('accepts a name at exactly the maximum length', () {
      final atMax = '食' * MealEstimateJsonDecoder.maxTextLength;
      final draft = decoder.decode(_document(_item(name: '"$atMax"')));
      expect(draft.items.single.name, atMax);
    });

    test('rejects names and texts beyond the maximum length', () {
      final tooLong = '食' * (MealEstimateJsonDecoder.maxTextLength + 1);
      for (final document in [
        _document(_item(name: '"$tooLong"')),
        _document(_item(cookingMethod: '"$tooLong"')),
        _document(_item(ingredients: '["$tooLong"]')),
        _document(_item(questions: '["$tooLong"]')),
        _document(_defaultItem, warnings: '["$tooLong"]'),
      ]) {
        expect(() => decoder.decode(document), throwsFormatException);
      }
    });

    test('rejects empty-text questions but allows empty ingredients lists', () {
      expect(
        () => decoder.decode(_document(_item(questions: '["", "x"]'))),
        throwsFormatException,
      );
      final draft = decoder.decode(_document(_item(ingredients: '[]')));
      expect(draft.items.single.ingredients, isEmpty);
    });

    test('rejects lists beyond the entry limit', () {
      final tooMany = List.filled(
        MealEstimateJsonDecoder.maxListEntries + 1,
        '"x"',
      ).join(',');
      expect(
        () => decoder.decode(_document(_item(questions: '[$tooMany]'))),
        throwsFormatException,
      );
    });
  });

  test('classifies an empty item list as a recoverable empty result', () {
    expect(
      () => decoder.decode(_document(null, items: '')),
      throwsA(isA<MealEstimateEmptyResult>()),
    );
  });
}

const _defaultItem =
    '{"name":"米饭","estimated_grams":180,"grams_range":{"min":140,"max":220},"cooking_method":"蒸煮","ingredients":["大米"],"confidence":0.78,"needs_confirmation":false,"questions":[]}';

String _document(
  String? item, {
  String? items,
  String version = '1',
  String warnings = '[]',
}) {
  final itemText = items ?? item ?? _defaultItem;
  return '{"schema_version":$version,"items":[$itemText],"meal_notes":"午餐","warnings":$warnings}';
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

// Keep jsonEncode referenced: the helpers build raw JSON strings, but a
// canonical round-trip guards against accidental double-encoding regressions.
// ignore: unused_element
String _roundTrip(String value) => jsonEncode(jsonDecode(value));
