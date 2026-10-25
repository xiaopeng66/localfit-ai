import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/features/nutrition/domain/dish_record.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';
import 'package:localfit_ai/features/retrieval/application/dish_search.dart';
import 'package:localfit_ai/features/retrieval/application/taste_profile.dart';

/// 口味向量（docs/43 B9 / docs/39 §8）。
void main() {
  final now = DateTime.utc(2026, 10, 19, 12);

  DishRecord dish(String id, String name) => DishRecord(
    id: id,
    name: name,
    mealSlot: '午餐',
    kcal: 200,
    proteinG: 10,
    carbsG: 20,
    fatG: 8,
    source: 'manual',
    createdAt: now,
    updatedAt: now,
  );

  List<TasteVectorSample> samples(
    int count, {
    required List<double> vector,
    int ageDays = 0,
  }) => [
    for (var i = 0; i < count; i++)
      TasteVectorSample(
        eatenAt: DateTime.utc(
          2026,
          10,
          19,
          0,
        ).subtract(Duration(days: ageDays + i)),
        vector: vector,
      ),
  ];

  test('<10 餐不参与（active=false）', () {
    final profile = buildTasteVectorProfile(
      samples: samples(9, vector: const [1, 0]),
      now: now,
    );
    expect(profile.active, isFalse);
    expect(profile.vector, isNull);
    expect(profile.affinityOf(const [1, 0]), 0);
  });

  test('质心 L2 归一（两个同向样本 → 单位向量）', () {
    final profile = buildTasteVectorProfile(
      samples: samples(10, vector: const [3, 4]),
      now: now,
    );
    expect(profile.active, isTrue);
    final vector = profile.vector!;
    final norm = math.sqrt(vector.fold(0.0, (sum, v) => sum + v * v));
    expect(norm, closeTo(1.0, 1e-9));
    expect(vector[0], closeTo(0.6, 1e-9));
    expect(vector[1], closeTo(0.8, 1e-9));
  });

  test('衰减：14 天前的权重减半', () {
    // 10 条 14 天前的 [0,1] + 10 条今天的 [1,0]：权重 0.5 vs 1.0。
    final profile = buildTasteVectorProfile(
      samples: [
        for (var i = 0; i < 10; i++)
          TasteVectorSample(eatenAt: now, vector: const [1, 0]),
        for (var i = 0; i < 10; i++)
          TasteVectorSample(
            eatenAt: now.subtract(const Duration(days: 14)),
            vector: const [0, 1],
          ),
      ],
      now: now,
    );
    final vector = profile.vector!;
    // 归一化前质心 = [10, 5] ⇒ 归一后 [0.894, 0.447]，比值 2:1。
    expect(vector[0] / vector[1], closeTo(2.0, 0.02));
  });

  test('超 30 天的样本被剔除', () {
    final profile = buildTasteVectorProfile(
      samples: [
        ...samples(10, vector: const [1, 0]),
        for (var i = 0; i < 20; i++)
          TasteVectorSample(
            eatenAt: now.subtract(Duration(days: 40 + i)),
            vector: const [0, 1],
          ),
      ],
      now: now,
    );
    expect(profile.sampleCount, 10, reason: '只有近 30 天的样本参与');
    expect(profile.vector![0], closeTo(1.0, 1e-9));
  });

  MealRecord meal({
    required String id,
    required String sourceType,
    String? sourceId,
    int daysAgo = 0,
  }) => MealRecord(
    id: id,
    localDate: '2026-10-19',
    slot: MealSlot.lunch,
    eatenAt: now.subtract(Duration(days: daysAgo)),
    source: 'manual',
    createdAt: now,
    updatedAt: now,
    items: [
      MealItemRecord(
        id: 'item-$id',
        foodName: '某道菜',
        grams: 200,
        nutrition: const NutritionValues(
          kcal: 300,
          proteinGrams: 10,
          carbsGrams: 30,
          fatGrams: 10,
        ),
        createdAt: now,
        updatedAt: now,
        sourceType: sourceType,
        sourceId: sourceId,
      ),
    ],
  );

  test('样本投影：只收近 30 天、sourceType=dish 且有向量的条目', () {
    final samples = tasteVectorSamplesFromMeals(
      meals: [
        meal(id: 'a', sourceType: 'dish', sourceId: 'd1'),
        meal(id: 'b', sourceType: 'food', sourceId: 'f1'),
        meal(id: 'c', sourceType: 'dish', sourceId: 'missing'),
        meal(id: 'd', sourceType: 'dish', sourceId: 'd1', daysAgo: 40),
        meal(id: 'e', sourceType: 'manual'),
      ],
      dishVectors: const {
        'd1': [1, 0],
        'f1': [0, 1],
      },
      now: now,
    );
    expect(samples, hasLength(1), reason: '只有 a 符合：dish + 有向量 + 近 30 天');
  });

  test('boost 只影响排序，不改变命中集合（绝不硬过滤）', () {
    final dishes = [dish('d1', '清蒸鱼'), dish('d2', '红烧肉')];
    final service = DishSearchService();
    final plain = service.search(query: '鱼', dishes: dishes);
    final boosted = service.search(
      query: '鱼',
      dishes: dishes,
      tasteVector: buildTasteVectorProfile(
        samples: samples(10, vector: const [1, 0]),
        now: now,
      ),
      dishVectors: const {
        'd1': [0, 1],
        'd2': [1, 0],
      },
    );
    expect(
      plain.hits.map((hit) => hit.id).toSet(),
      boosted.hits.map((hit) => hit.id).toSet(),
      reason: '软 boost 不得排除任何候选',
    );
  });

  test('与标签画像取较大者，不叠加', () {
    final dishes = [dish('d1', '清蒸鱼')];
    final service = DishSearchService();
    final taste = buildTasteProfile(
      samples: [
        for (var i = 0; i < 10; i++)
          TasteSample(
            dishName: '清蒸鱼',
            eatenAt: now.subtract(Duration(days: i)),
            tags: const ['清淡'],
          ),
      ],
      now: now,
    );
    final vector = buildTasteVectorProfile(
      samples: samples(10, vector: const [1, 0]),
      now: now,
    );
    final tagOnly = service.search(query: '鱼', dishes: dishes, taste: taste);
    final both = service.search(
      query: '鱼',
      dishes: dishes,
      taste: taste,
      tasteVector: vector,
      dishVectors: const {
        'd1': [1, 0],
      },
    );
    // 两条路给出同一个 0–1 亲和度 ⇒ 取较大者后分数相同（叠加会更大）。
    expect(both.hits.single.score, closeTo(tagOnly.hits.single.score, 1e-9));
  });
}
