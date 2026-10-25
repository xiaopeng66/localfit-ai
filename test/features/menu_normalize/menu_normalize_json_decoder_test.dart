import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/features/menu_normalize/data/menu_normalize_json_decoder.dart';

void main() {
  group('menu-normalize.v1 decoder', () {
    test('decodes a valid payload', () {
      final draft = const MenuNormalizeJsonDecoder().decode(_validJson);
      expect(draft.schemaVersion, 1);
      expect(draft.sourceDate, '2026-09-12');
      expect(draft.venueName, '东区食堂');
      expect(draft.services, hasLength(1));
      final service = draft.services.single;
      expect(service.serviceName, '一楼窗口');
      expect(service.openTime, '10:30');
      expect(service.closeTime, '13:30');
      final item = service.items.single;
      expect(item.displayName, '鸡蛋炒饭');
      // 2026-10-16 用户删掉菜品价格：`price_minor` 不再解析。
      // `_validJson` 保留该键**作 legacy 容忍**（旧草案/旧提示词
      // 仍会带着它），断言改为「能解出来、别的字段不受影响」。
      expect(item.ingredientHints, ['米饭', '鸡蛋']);
      expect(item.allergenHints, ['egg']);
      expect(item.needsConfirmation, isTrue);
      expect(item.questions, hasLength(1));
      expect(draft.warnings, isEmpty);
    });

    test('ignores unknown fields but not missing required ones', () {
      const json = '''
      {"schema_version":1,"source_date":"2026-09-12","venue_name":"V",
       "services":[{"service_name":"S","open_time":"08:00","close_time":"09:00",
       "items":[{"display_name":"D"}],"extra":"ok"}],"future_field":true}
      ''';
      final draft = const MenuNormalizeJsonDecoder().decode(json);
      expect(draft.services.single.items.single.displayName, 'D');
    });

    test('rejects unsupported schema version', () {
      const json =
          '{"schema_version":2,"source_date":"2026-09-12","venue_name":"V","services":[]}';
      expect(
        () => const MenuNormalizeJsonDecoder().decode(json),
        throwsA(
          isA<MenuNormalizeFormatException>().having(
            (e) => e.errors.join(';'),
            'errors',
            contains('unsupported schema_version: 2'),
          ),
        ),
      );
    });

    test('rejects a bad date format', () {
      const json =
          '{"schema_version":1,"source_date":"09/12/2026","venue_name":"V","services":[]}';
      expect(
        () => const MenuNormalizeJsonDecoder().decode(json),
        throwsA(
          isA<MenuNormalizeFormatException>().having(
            (e) => e.errors.join(';'),
            'errors',
            contains('source_date must be an ISO-8601 date'),
          ),
        ),
      );
    });

    test('rejects a bad time format', () {
      const json = '''
      {"schema_version":1,"source_date":"2026-09-12","venue_name":"V",
       "services":[{"service_name":"S","open_time":"8am","close_time":"13:30","items":[]}]}
      ''';
      expect(
        () => const MenuNormalizeJsonDecoder().decode(json),
        throwsA(
          isA<MenuNormalizeFormatException>().having(
            (e) => e.errors.join(';'),
            'errors',
            contains('service open_time must be HH:MM'),
          ),
        ),
      );
    });

    test('tolerates and ignores a legacy price_minor', () {
      // 价格退役前这里断言「负数/非整数价格必须被拒」。字段与列都不存在
      // 之后，唯一合理的语义是**容忍并忽略**（见 2026-10-16 用户指令与
      // docs/36 §3 S8-b）：旧信封照收，价格不落在任何地方。
      const json = '''
      {"schema_version":1,"source_date":"2026-09-12","venue_name":"V",
       "services":[{"service_name":"S","open_time":"08:00","close_time":"09:00",
       "items":[{"display_name":"D","price_minor":-1}]}]}
      ''';
      final draft = const MenuNormalizeJsonDecoder().decode(json);
      expect(draft.services.single.items.single.displayName, 'D');
    });

    test('rejects oversized text fields', () {
      final longName = 'A' * 201;
      final json =
          '{"schema_version":1,"source_date":"2026-09-12","venue_name":"$longName","services":[]}';
      expect(
        () => const MenuNormalizeJsonDecoder().decode(json),
        throwsA(
          isA<MenuNormalizeFormatException>().having(
            (e) => e.errors.join(';'),
            'errors',
            contains('venue_name must be at most 200 chars'),
          ),
        ),
      );
    });

    test('rejects duplicate item display names within one service', () {
      const json = '''
      {"schema_version":1,"source_date":"2026-09-12","venue_name":"V",
       "services":[{"service_name":"S","open_time":"08:00","close_time":"09:00",
       "items":[{"display_name":"D"},{"display_name":"D"}]}]}
      ''';
      expect(
        () => const MenuNormalizeJsonDecoder().decode(json),
        throwsA(
          isA<MenuNormalizeFormatException>().having(
            (e) => e.errors.join(';'),
            'errors',
            contains('duplicate item display_name in service S: D'),
          ),
        ),
      );
    });

    test('rejects markdown-wrapped or multi-root payloads', () {
      expect(
        () => const MenuNormalizeJsonDecoder().decode('not json'),
        throwsA(isA<MenuNormalizeFormatException>()),
      );
      expect(
        () => const MenuNormalizeJsonDecoder().decode(
          '{"schema_version":1} trailing garbage',
        ),
        throwsA(isA<MenuNormalizeFormatException>()),
      );
    });

    test('collects multiple violations at once', () {
      const json = '''
      {"schema_version":3,"source_date":"bad","venue_name":"",
       "services":[{"service_name":"","open_time":"xx","close_time":"09:00","items":[]}]}
      ''';
      try {
        const MenuNormalizeJsonDecoder().decode(json);
        fail('expected MenuNormalizeFormatException');
      } on MenuNormalizeFormatException catch (e) {
        expect(e.errors.length, greaterThanOrEqualTo(4));
      }
    });
  });
}

/// `price_minor` 是 **legacy 容忍键**：退役前的信封里有它，解码器忽略
///（2026-10-16 用户删掉菜品价格；见 docs/36 §3 S8-b）。
const _validJson = '''
{"schema_version":1,"source_date":"2026-09-12","venue_name":"东区食堂",
 "services":[{"service_name":"一楼窗口","open_time":"10:30","close_time":"13:30",
  "items":[{"display_name":"鸡蛋炒饭","station_name":"一楼窗口","price_minor":800,
   "reported_nutrition":{"kcal":null,"protein_g":null,"carbs_g":null,"fat_g":null,
    "evidence_text":null},"ingredient_hints":["米饭","鸡蛋"],"allergen_hints":["egg"],
    "needs_confirmation":true,"questions":["是否包含额外用油？"]}]}],
 "warnings":[]}
''';
