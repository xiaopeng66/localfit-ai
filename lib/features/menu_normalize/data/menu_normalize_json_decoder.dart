/// `menu-normalize.v1` decoder（规范 docs/03 第 8/10 节）。
///
/// 模型只提取用户输入中明确存在的菜单内容；本地检查日期、时间、菜名、
/// 文本长度、重复项与字段范围。违规全量收集进 [MenuNormalizeFormatException.errors]。
library;

import 'package:localfit_ai/features/ai/data/structured_json_parser.dart';
import 'package:localfit_ai/features/ai/domain/ai_validation_report.dart';

/// 字段上限（规范第 10 节文本长度规则）。
const int maxTextFieldLength = 200;
const int maxItemsPerService = 100;
const int maxServicesPerDraft = 20;

class MenuNormalizeFormatException implements Exception, AiDecoderViolations {
  const MenuNormalizeFormatException(this.errors);

  final List<String> errors;

  // 能力层把违规清单收进校验报告上屏（docs/11 BUG-5）。
  @override
  List<String> get violations => errors;

  @override
  String toString() =>
      'MenuNormalizeFormatException(${errors.length} violations):\n'
      '${errors.join('\n')}';
}

class MenuNormalizeReportedNutrition {
  const MenuNormalizeReportedNutrition({
    required this.kcal,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.evidenceText,
  });

  final double? kcal;
  final double? proteinG;
  final double? carbsG;
  final double? fatG;
  final String? evidenceText;
}

class MenuNormalizeItem {
  const MenuNormalizeItem({
    required this.displayName,
    required this.stationName,
    required this.reportedNutrition,
    required this.ingredientHints,
    required this.allergenHints,
    required this.needsConfirmation,
    required this.questions,
  });

  final String displayName;
  final String? stationName;
  final MenuNormalizeReportedNutrition? reportedNutrition;
  final List<String> ingredientHints;
  final List<String> allergenHints;
  final bool needsConfirmation;
  final List<String> questions;
}

class MenuNormalizeService {
  const MenuNormalizeService({
    required this.serviceName,
    required this.openTime,
    required this.closeTime,
    required this.items,
  });

  final String serviceName;
  final String openTime;
  final String closeTime;
  final List<MenuNormalizeItem> items;
}

class MenuNormalizeDraft {
  const MenuNormalizeDraft({
    required this.schemaVersion,
    required this.sourceDate,
    required this.venueName,
    required this.services,
    required this.warnings,
  });

  final int schemaVersion;
  final String sourceDate;
  final String venueName;
  final List<MenuNormalizeService> services;
  final List<String> warnings;
}

final class MenuNormalizeJsonDecoder {
  const MenuNormalizeJsonDecoder();

  MenuNormalizeDraft decode(String content) {
    final Map<String, dynamic> json;
    try {
      json = parseStructuredJson(content);
    } on ArgumentError catch (error) {
      throw MenuNormalizeFormatException([
        'content is not a single JSON object: $error',
      ]);
    } on FormatException catch (error) {
      throw MenuNormalizeFormatException([
        'content is not parseable JSON: ${error.message}',
      ]);
    }

    final errors = <String>[];
    _validateAndBuild(json, errors);
    if (errors.isNotEmpty) {
      throw MenuNormalizeFormatException(errors);
    }
    return _build(json);
  }

  void _validateAndBuild(Map<String, dynamic> json, List<String> errors) {
    final schemaVersion = json['schema_version'];
    if (schemaVersion != 1) {
      errors.add('unsupported schema_version: $schemaVersion');
    }

    final sourceDate = json['source_date'];
    if (sourceDate is! String || !_isoDate.hasMatch(sourceDate)) {
      errors.add('source_date must be an ISO-8601 date');
    }

    _requiredText(json['venue_name'], 'venue_name', errors);

    final rawServices = json['services'];
    if (rawServices is! List) {
      errors.add('services must be an array');
      return;
    }
    if (rawServices.length > maxServicesPerDraft) {
      errors.add('services must have at most $maxServicesPerDraft entries');
    }

    final serviceNames = <String>{};
    for (final rawService in rawServices) {
      if (rawService is! Map<String, dynamic>) {
        errors.add('each service must be an object');
        continue;
      }
      final serviceName = _optionalText(
        rawService['service_name'],
        'service_name',
        errors,
      );
      if (serviceName != null && !serviceNames.add(serviceName)) {
        errors.add('duplicate service_name: $serviceName');
      }
      final openTime = rawService['open_time'];
      if (openTime is! String || !_hhmm.hasMatch(openTime)) {
        errors.add('service open_time must be HH:MM');
      }
      final closeTime = rawService['close_time'];
      if (closeTime is! String || !_hhmm.hasMatch(closeTime)) {
        errors.add('service close_time must be HH:MM');
      }

      final rawItems = rawService['items'];
      if (rawItems is! List) {
        errors.add('service items must be an array');
        continue;
      }
      if (rawItems.length > maxItemsPerService) {
        errors.add('service items must have at most $maxItemsPerService');
      }
      final displayNames = <String>{};
      for (final rawItem in rawItems) {
        if (rawItem is! Map<String, dynamic>) {
          errors.add('each item must be an object');
          continue;
        }
        final displayName = _requiredText(
          rawItem['display_name'],
          'display_name',
          errors,
        );
        if (displayName != null &&
            !displayNames.add(displayName) &&
            serviceName != null) {
          errors.add(
            'duplicate item display_name in service $serviceName: '
            '$displayName',
          );
        }
        _optionalText(rawItem['station_name'], 'station_name', errors);

        // 2026-10-16（用户删掉菜品价格）：`price_minor` **不再解析**。
        // 旧草案/旧提示词里仍然带着它——这里**容忍并忽略**（不是报错）：
        // 接受旧信封比逼用户重跑一次更实在，而价格已经不落在任何地方。

        final nutrition = rawItem['reported_nutrition'];
        if (nutrition != null) {
          if (nutrition is! Map<String, dynamic>) {
            errors.add('reported_nutrition must be an object');
          } else {
            for (final key in const ['kcal', 'protein_g', 'carbs_g', 'fat_g']) {
              final value = nutrition[key];
              if (value != null && value is! num) {
                errors.add('reported_nutrition $key must be a number or null');
              }
            }
            _optionalText(
              nutrition['evidence_text'],
              'reported_nutrition evidence_text',
              errors,
            );
          }
        }

        _stringArray(rawItem['ingredient_hints'], 'ingredient_hints', errors);
        _stringArray(rawItem['allergen_hints'], 'allergen_hints', errors);
        _stringArray(rawItem['questions'], 'questions', errors);

        final needsConfirmation = rawItem['needs_confirmation'];
        if (needsConfirmation != null && needsConfirmation is! bool) {
          errors.add('item needs_confirmation must be a boolean');
        }
      }
    }

    _stringArray(json['warnings'], 'warnings', errors);
  }

  MenuNormalizeDraft _build(Map<String, dynamic> json) {
    final services = <MenuNormalizeService>[];
    for (final rawService in json['services'] as List) {
      if (rawService is! Map<String, dynamic>) continue;
      final items = <MenuNormalizeItem>[];
      for (final rawItem in rawService['items'] as List? ?? const []) {
        if (rawItem is! Map<String, dynamic>) continue;
        items.add(
          MenuNormalizeItem(
            displayName: rawItem['display_name'] as String,
            stationName: rawItem['station_name'] as String?,
            reportedNutrition: _buildNutrition(rawItem['reported_nutrition']),
            ingredientHints: _stringListOf(rawItem['ingredient_hints']),
            allergenHints: _stringListOf(rawItem['allergen_hints']),
            needsConfirmation: rawItem['needs_confirmation'] is bool
                ? rawItem['needs_confirmation'] as bool
                : true,
            questions: _stringListOf(rawItem['questions']),
          ),
        );
      }
      services.add(
        MenuNormalizeService(
          serviceName: rawService['service_name'] as String? ?? '',
          openTime: rawService['open_time'] as String? ?? '00:00',
          closeTime: rawService['close_time'] as String? ?? '23:59',
          items: items,
        ),
      );
    }

    return MenuNormalizeDraft(
      schemaVersion: json['schema_version'] as int,
      sourceDate: json['source_date'] as String,
      venueName: json['venue_name'] as String,
      services: services,
      warnings: _stringListOf(json['warnings']),
    );
  }

  MenuNormalizeReportedNutrition? _buildNutrition(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    double? asDouble(Object? value) => value is num ? value.toDouble() : null;
    return MenuNormalizeReportedNutrition(
      kcal: asDouble(raw['kcal']),
      proteinG: asDouble(raw['protein_g']),
      carbsG: asDouble(raw['carbs_g']),
      fatG: asDouble(raw['fat_g']),
      evidenceText: raw['evidence_text'] as String?,
    );
  }

  List<String> _stringListOf(Object? raw) =>
      raw is List ? raw.whereType<String>().toList() : const [];

  void _stringArray(Object? raw, String field, List<String> errors) {
    if (raw == null) return;
    if (raw is! List || raw.any((e) => e is! String)) {
      errors.add('$field must be an array of strings');
    }
  }

  String? _requiredText(Object? raw, String field, List<String> errors) {
    if (raw is! String || raw.trim().isEmpty) {
      errors.add('$field must be non-empty text');
      return null;
    }
    if (raw.length > maxTextFieldLength) {
      errors.add('$field must be at most $maxTextFieldLength chars');
    }
    return raw;
  }

  String? _optionalText(Object? raw, String field, List<String> errors) {
    if (raw == null) return null;
    if (raw is! String) {
      errors.add('$field must be text or null');
      return null;
    }
    if (raw.length > maxTextFieldLength) {
      errors.add('$field must be at most $maxTextFieldLength chars');
    }
    return raw;
  }
}

final RegExp _isoDate = RegExp(r'^\d{4}-\d{2}-\d{2}$');
final RegExp _hhmm = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');
