import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/features/ai_memory/domain/ai_memory.dart';
import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/dish_record.dart';
import 'package:localfit_ai/features/retrieval/application/dish_search.dart';
import 'package:localfit_ai/features/retrieval/application/memory_selector.dart';
import 'package:localfit_ai/features/retrieval/application/ranking.dart';
import 'package:localfit_ai/features/retrieval/domain/query_understanding.dart';

AiMemory _memory(
  String id,
  String text, {
  bool pinned = false,
  int importance = 50,
  AiMemoryKind kind = AiMemoryKind.preference,
  List<String> tags = const [],
}) => AiMemory(
  id: id,
  text: text,
  kind: kind,
  domain: AiMemoryDomain.nutrition,
  tags: tags,
  pinned: pinned,
  source: 'manual',
  status: 'active',
  createdAt: DateTime.utc(2026, 10, 18),
  updatedAt: DateTime.utc(2026, 10, 18),
  importance: importance,
);

DishRecord _dish(String id, String name, {double kcal = 300}) => DishRecord(
  id: id,
  name: name,
  mealSlot: '午餐',
  kcal: kcal,
  proteinG: 10,
  carbsG: 30,
  fatG: 10,
  source: 'manual',
  createdAt: DateTime.utc(2026, 10, 18),
  updatedAt: DateTime.utc(2026, 10, 18),
);

CanteenDish _canteenDish(
  String id,
  String name, {
  List<String> tags = const [],
}) => CanteenDish(
  id: id,
  windowId: 'w1',
  name: name,
  evidenceGrade: 'C',
  itemStatus: 'estimated',
  evidence: null,
  tags: tags,
);

void main() {
  group('查询理解（同义词/槽位/否定）', () {
    test('别名扩展：土豆↔洋芋、西红柿↔番茄', () {
      expect(understandQuery('想吃洋芋').expanded, contains('土豆'));
      expect(understandQuery('番茄炒蛋').expanded, contains('西红柿'));
    });

    test('槽位：中午→午餐、宵夜→加餐', () {
      expect(understandQuery('中午吃点什么').slots, contains('午餐'));
      expect(understandQuery('宵夜有吗').slots, contains('加餐'));
    });

    test('否定词单独成集（只做软惩罚）', () {
      final q = understandQuery('想吃点不辣的');
      expect(q.negations, contains('辣'));
      expect(q.expanded, isNot(contains('辣')));
    });
  });

  group('RRF 融合', () {
    test('两路都命中的条目排在只命中一路之前', () {
      final fused = reciprocalRankFusion({
        'a': ['x', 'y', 'z'],
        'b': ['y', 'x'],
      });
      // y 在 a 第 2、b 第 1；x 在 a 第 1、b 第 2 ⇒ 两者接近，z 只有一路。
      expect(fused.first.id, anyOf('x', 'y'));
      expect(fused.last.id, 'z');
    });

    test('权重只做轻微可解释加权（keywordFirst 抬关键词）', () {
      final balanced = reciprocalRankFusion({
        'keyword': ['x'],
        'tags': ['y'],
      });
      final keywordFirst = reciprocalRankFusion(
        {
          'keyword': ['x'],
          'tags': ['y'],
        },
        weights: {'keyword': 4, 'tags': 1},
      );
      expect(balanced.first.score, closeTo(balanced.last.score, 1e-9));
      expect(keywordFirst.first.id, 'x');
    });

    test('boost 有上界：置顶最多 ×1.15', () {
      final base = 1.0;
      expect(applyBoosts(base, pinned: true), closeTo(1.15, 1e-9));
      expect(
        applyBoosts(base, pinned: true, importance: 100),
        closeTo(1.15 * 1.1, 1e-9),
      );
    });

    test('近期吃过是软惩罚（×0.85），不是排除', () {
      expect(applyBoosts(1.0, recentlyEaten: true), closeTo(0.85, 1e-9));
    });
  });

  group('MMR 去冗余', () {
    test('近义条目不会占满预算', () {
      final fused = [
        const FusedCandidate(id: 'a1', score: 1.0, routeRanks: {'k': 1}),
        const FusedCandidate(id: 'a2', score: 0.99, routeRanks: {'k': 2}),
        const FusedCandidate(id: 'b1', score: 0.5, routeRanks: {'k': 3}),
      ];
      final texts = {'a1': '不吃香菜', 'a2': '不吃香菜叶', 'b1': '周三晚上练腿'};
      final defaultLambda = maximalMarginalRelevance(
        candidates: fused,
        similarity: (a, b) => textOverlapSimilarity(texts[a]!, texts[b]!),
        limit: 2,
      );
      // λ=0.7 是**相关性优先**：近义但更相关的条目仍可能入选（这是
      // docs/39 §6.4 的既定取舍，不粉饰）。
      expect(defaultLambda.first, 'a1');
      expect(defaultLambda, hasLength(2));

      final diversityFirst = maximalMarginalRelevance(
        candidates: fused,
        similarity: (a, b) => textOverlapSimilarity(texts[a]!, texts[b]!),
        limit: 2,
        lambda: 0.3,
      );
      expect(diversityFirst.first, 'a1');
      expect(diversityFirst, contains('b1'), reason: 'λ 降低后多样性优先：近义重复被挤掉');
    });
  });

  group('记忆 query-aware 注入', () {
    test('相关记忆被选中，无关条目在门控下不注入', () {
      final memories = [
        _memory('m1', '不吃香菜'),
        _memory('m2', '周三晚上练腿', importance: 90),
        _memory('m3', '喜欢清淡口味'),
      ];
      final selection = selectMemoriesForInjection(
        memories: memories,
        userMessage: '今天想吃香菜牛肉',
      );
      expect(selection.injectedIds, contains('m1'));
      expect(selection.gated, isFalse);
      expect(selection.charCount, greaterThan(0));
    });

    test('完全不相关时触发门控：只注入置顶/高重要性', () {
      final memories = [
        _memory('m1', '不吃香菜'),
        _memory('m2', '周三晚上练腿', importance: 90),
        _memory('m3', '喜欢清淡口味'),
      ];
      final selection = selectMemoriesForInjection(
        memories: memories,
        userMessage: '今天天气怎么样？',
      );
      expect(selection.gated, isTrue);
      expect(selection.injectedIds, ['m2'], reason: '只有高重要性 90 的那条');
    });

    test('三档预算：紧凑档条数与字符都更少', () {
      final memories = [
        for (var i = 0; i < 30; i++)
          _memory('m$i', '这是一条比较长的记忆内容第$i条，用来测试预算上限'),
      ];
      final compact = selectMemoriesForInjection(
        memories: memories,
        userMessage: '记忆',
        budget: MemoryBudget.compact,
      );
      final more = selectMemoriesForInjection(
        memories: memories,
        userMessage: '记忆',
        budget: MemoryBudget.more,
      );
      expect(compact.memories.length, lessThanOrEqualTo(12));
      expect(more.memories.length, greaterThan(compact.memories.length));
      expect(compact.charCount, lessThanOrEqualTo(1500));
      expect(more.charCount, lessThanOrEqualTo(6000));
    });

    test('注入 id 可回读（D11）', () {
      final selection = selectMemoriesForInjection(
        memories: [_memory('m1', '不吃香菜')],
        userMessage: '香菜',
      );
      expect(selection.injectedIds, ['m1']);
    });
  });

  group('菜品检索（关键词 + 标签，向量路关闭）', () {
    const service = DishSearchService();

    test('口语查询命中菜名/标签；调试信息齐全', () {
      final result = service.search(
        query: '想吃点清淡的汤',
        dishes: [_dish('d1', '番茄炒蛋'), _dish('d2', '清蒸鲈鱼')],
        canteenDishes: [
          _canteenDish('m1', '紫菜蛋花汤', tags: ['清淡', '汤']),
        ],
      );
      expect(result.hits, isNotEmpty);
      expect(
        result.hits.map((h) => h.name),
        contains('紫菜蛋花汤'),
        reason: '标签路命中「清淡/汤」',
      );
      expect(result.debug.routeHits['keyword'], greaterThan(0));
      expect(result.debug.routeHits['tags'], greaterThan(0));
      expect(result.debug.semanticEnabled, isFalse, reason: 'P0 结论：向量默认关');
      expect(result.debug.mode, RetrievalMode.balanced);
    });

    test('今日菜单硬过滤：不在今日菜单上的食堂菜不出现', () {
      final result = service.search(
        query: '汤',
        dishes: const [],
        canteenDishes: [
          _canteenDish('m1', '紫菜蛋花汤', tags: ['汤']),
          _canteenDish('m2', '冬瓜汤', tags: ['汤']),
        ],
        todayMenuItemIds: {'m1'},
      );
      expect(result.hits.map((h) => h.id), ['m1']);
    });

    test('否定词只软惩罚（不辣不会把辣菜硬删）', () {
      final result = service.search(
        query: '想吃辣但不要太辣的',
        dishes: [_dish('d1', '辣子鸡'), _dish('d2', '清炒时蔬')],
      );
      // 辣子鸡仍然出现（软惩罚只扣分，不排除）；完全不相关的菜不出现。
      expect(result.hits.map((h) => h.name), contains('辣子鸡'));
      expect(result.hits.map((h) => h.name), isNot(contains('清炒时蔬')));
      expect(result.debug.negations, contains('辣'));
    });

    test('AI 短名单按窗口分组且每窗口有上限', () {
      final hits = [
        for (var i = 0; i < 10; i++)
          FoodHit(
            id: 'h$i',
            name: '菜$i',
            kind: 'menuItem',
            score: 1 - i * 0.01,
            window: i < 8 ? '窗口A' : '窗口B',
          ),
      ];
      final shortlist = buildAiShortlist(hits, limit: 30);
      expect(shortlist.where((h) => h.window == '窗口A'), hasLength(6));
      expect(shortlist.where((h) => h.window == '窗口B'), hasLength(2));
    });

    test('检索模式影响权重（KEYWORD_FIRST 抬关键词路）', () {
      final dishes = [_dish('d1', '清蒸鲈鱼')];
      final balanced = service.search(
        query: '清蒸鲈鱼',
        dishes: dishes,
        mode: RetrievalMode.balanced,
      );
      final keywordFirst = service.search(
        query: '清蒸鲈鱼',
        dishes: dishes,
        mode: RetrievalMode.keywordFirst,
      );
      expect(
        balanced.hits.single.score,
        isNot(equals(keywordFirst.hits.single.score)),
      );
    });
  });
}
