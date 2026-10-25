import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/features/ai/data/structured_json_parser.dart';

void main() {
  group('structured json parser (three-layer fallback)', () {
    test(
      'layer 1: extracts JSON object from a native json_schema envelope',
      () {
        // response_format=json_schema 时 content 应是纯 JSON。
        const content = '{"schema_version":1,"items":[]}';
        final parsed = parseStructuredJson(content);
        expect(parsed, isA<Map<String, dynamic>>());
        expect((parsed as Map)['schema_version'], 1);
      },
    );

    test('layer 2: extracts a fenced JSON object from prose', () {
      const content = 'Here is the plan:\n```json\n{"schema_version":1}\n```';
      final parsed = parseStructuredJson(content);
      expect((parsed as Map)['schema_version'], 1);
    });

    test('layer 2: extracts the outermost JSON object embedded in prose', () {
      const content =
          'Sure! {"schema_version":1,"items":[{"name":"饭"}]} hope that helps';
      final parsed = parseStructuredJson(content);
      expect((parsed as Map)['schema_version'], 1);
      expect(((parsed as Map)['items'] as List).first['name'], '饭');
    });

    test('layer 3: repairs common strict-JSON issues (trailing commas)', () {
      const content = '{"schema_version":1,"items":[1,2,],}';
      final parsed = parseStructuredJson(content);
      expect((parsed as Map)['schema_version'], 1);
      expect((parsed as Map)['items'], hasLength(2));
    });

    test('layer 3: repairs smart quotes and single quotes', () {
      const content = "{'schema_version': 1, 'note': “ok”}";
      final parsed = parseStructuredJson(content);
      expect((parsed as Map)['note'], 'ok');
    });

    test('rejects non-object results (arrays, scalars)', () {
      expect(() => parseStructuredJson('[1,2,3]'), throwsArgumentError);
      expect(() => parseStructuredJson('42'), throwsArgumentError);
      expect(() => parseStructuredJson('"just text"'), throwsArgumentError);
    });

    test('rejects unparseable content with a descriptive error', () {
      expect(
        () => parseStructuredJson('no json here at all'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('no JSON object'),
          ),
        ),
      );
    });

    test('rejects empty content', () {
      expect(() => parseStructuredJson(''), throwsArgumentError);
      expect(() => parseStructuredJson('   '), throwsArgumentError);
    });

    test('handles nested braces inside strings during extraction', () {
      const content = 'prefix {"note":"has } brace and { inside","v":1} suffix';
      final parsed = parseStructuredJson(content);
      expect((parsed as Map)['v'], 1);
      expect((parsed as Map)['note'], 'has } brace and { inside');
    });
  });
}
