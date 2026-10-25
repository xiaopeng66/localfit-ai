import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/features/nutrition/data/catalog_ai_projection.dart';
import 'package:localfit_ai/features/nutrition/data/catalog_search_service.dart';

void main() {
  CatalogSearchResult result(
    String id, {
    String name = 'Rice',
    String state = 'verified',
    double kcal = 130,
  }) => CatalogSearchResult(
    id: id,
    name: name,
    state: state,
    brand: null,
    category: null,
    kcalPer100g: kcal,
    proteinPer100g: 2.7,
    carbsPer100g: 28,
    fatPer100g: 0.3,
  );

  group('catalog AI projection', () {
    test('projects only joinable candidates with a capped top-K', () {
      final candidates = [
        result('a', name: 'Rice A'),
        result('b', name: 'Rice B', state: 'estimated'),
        result('c', name: 'Partial', state: 'incomplete'),
        result('d', name: 'Stale', state: 'stale'),
      ];
      final projection = CatalogAiProjection.projectCandidates(
        candidates,
        topK: 10,
      );

      // incomplete/stale 不发给 AI（不能参与计算）。
      expect(projection.map((c) => c.id), ['a', 'b']);
      expect(projection.singleWhere((c) => c.id == 'a').kcalPer100g, 130);
    });

    test('caps topK at 20 and floors at 1', () {
      final candidates = List.generate(30, (i) => result('id:$i'));
      expect(
        CatalogAiProjection.projectCandidates(candidates, topK: 500),
        hasLength(20),
      );
      expect(
        CatalogAiProjection.projectCandidates(candidates, topK: 0),
        hasLength(1),
      );
    });

    test('serializes to a compact JSON payload without full catalog data', () {
      final candidates = [result('a', name: 'Rice A')];
      final payload = CatalogAiProjection.toJsonPayload(candidates, topK: 5);
      final decoded = jsonDecode(payload) as Map<String, dynamic>;
      expect(decoded['top_k'], 5);
      final items = decoded['candidates'] as List;
      expect(items.single['id'], 'a');
      expect(items.single['name'], 'Rice A');
      // 每候选仅 id/name/state/brand/category/两项宏量 = 7 个键，
      // 不含完整目录或全库元数据。
      expect(
        (items.single as Map).keys,
        containsAll(['id', 'name', 'kcal_per100g', 'state']),
      );
      expect((items.single as Map).keys, hasLength(7));
    });

    test('empty candidates produce an empty payload', () {
      final payload = CatalogAiProjection.toJsonPayload([], topK: 10);
      final decoded = jsonDecode(payload) as Map<String, dynamic>;
      expect(decoded['candidates'], isEmpty);
    });
  });
}
