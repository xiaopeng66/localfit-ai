import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/features/ai_memory/application/session_memory.dart';
import 'package:localfit_ai/features/ai_memory/domain/ai_memory.dart';
import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/dish_record.dart';
import 'package:localfit_ai/features/retrieval/application/dish_search.dart';
import 'package:localfit_ai/features/retrieval/application/feedback_store.dart';
import 'package:localfit_ai/features/retrieval/application/memory_selector.dart';
import 'package:localfit_ai/features/retrieval/application/taste_profile.dart';

DishRecord _dish(String id, String name) => DishRecord(
  id: id,
  name: name,
  mealSlot: '午餐',
  kcal: 300,
  proteinG: 10,
  carbsG: 30,
  fatG: 10,
  source: 'manual',
  createdAt: DateTime.utc(2026, 10, 18),
  updatedAt: DateTime.utc(2026, 10, 18),
);

CanteenDish _canteen(String id, String name, List<String> tags) => CanteenDish(
  id: id,
  windowId: 'w1',
  name: name,
  evidenceGrade: 'C',
  itemStatus: 'estimated',
  evidence: null,
  tags: tags,
);

AiMemory _memory(String id, String text, {bool pinned = false}) => AiMemory(
  id: id,
  text: text,
  kind: AiMemoryKind.preference,
  domain: AiMemoryDomain.nutrition,
  tags: const [],
  pinned: pinned,
  source: 'manual',
  status: 'active',
  createdAt: DateTime.utc(2026, 10, 18),
  updatedAt: DateTime.utc(2026, 10, 18),
);

void main() {
  final now = DateTime.utc(2026, 10, 18);

  group('口味画像（满 N 餐前不参与）', () {
    test('冷启动：样本不足 ⇒ active=false，affinity 恒 0', () {
      final profile = buildTasteProfile(
        samples: [
          TasteSample(dishName: '面', eatenAt: now, tags: const ['面食']),
        ],
        now: now,
      );
      expect(profile.active, isFalse);
      expect(profile.affinityOf(name: '拉面', tags: const ['面食']), 0);
    });

    test('满 10 餐后：偏好标签权重最高，命中给正 affinity', () {
      final samples = [
        for (var i = 0; i < 12; i++)
          TasteSample(
            dishName: '拉面$i',
            eatenAt: now.subtract(Duration(days: i)),
            tags: i < 8 ? const ['面食', '清淡'] : const ['饭食'],
          ),
      ];
      final profile = buildTasteProfile(samples: samples, now: now);
      expect(profile.active, isTrue);
      expect(profile.tagWeights['面食'], closeTo(1.0, 0.001));
      expect(
        profile.affinityOf(name: '牛肉面', tags: const ['面食']),
        greaterThan(0),
      );
      expect(profile.affinityOf(name: '红烧肉', tags: const ['肉']), 0);
    });

    test('时间衰减：旧样本权重低于新样本', () {
      final samples = [
        for (var i = 0; i < 10; i++)
          TasteSample(
            dishName: '旧菜$i',
            eatenAt: now.subtract(const Duration(days: 120)),
            tags: const ['旧'],
          ),
        for (var i = 0; i < 10; i++)
          TasteSample(
            dishName: '新菜$i',
            eatenAt: now.subtract(Duration(days: i)),
            tags: const ['新'],
          ),
      ];
      final profile = buildTasteProfile(samples: samples, now: now);
      expect(profile.tagWeights['新']!, greaterThan(profile.tagWeights['旧']!));
    });
  });

  group('检索里的口味/软排除（只影响排序）', () {
    const service = DishSearchService();

    test('口味命中 ⇒ 分数更高；冷启动 ⇒ 不影响', () {
      final dishes = [_dish('d1', '牛肉面'), _dish('d2', '红烧肉')];
      final neutral = service.search(query: '面 肉 菜', dishes: dishes);
      final tasteOn = service.search(
        query: '面 肉 菜',
        dishes: dishes,
        taste: buildTasteProfile(
          samples: [
            for (var i = 0; i < 10; i++)
              TasteSample(dishName: '面$i', eatenAt: now, tags: const ['面食']),
          ],
          now: now,
        ),
      );
      double scoreOf(RetrievalResult result, String name) =>
          result.hits.firstWhere((h) => h.name == name).score;
      expect(scoreOf(tasteOn, '牛肉面'), greaterThan(scoreOf(neutral, '牛肉面')));
      expect(scoreOf(tasteOn, '红烧肉'), closeTo(scoreOf(neutral, '红烧肉'), 1e-9));
    });

    test('软排除只扣分（结果仍在，不硬过滤）', () {
      final dishes = [_dish('d1', '红烧肉')];
      const rules = SoftExclusionRules(dishNames: {'红烧肉'});
      final result = service.search(
        query: '红烧肉',
        dishes: dishes,
        exclusions: rules,
      );
      expect(result.hits.map((h) => h.name), contains('红烧肉'));
      final baseline = service.search(query: '红烧肉', dishes: dishes);
      expect(result.hits.single.score, lessThan(baseline.hits.single.score));
    });

    test('窗口软排除同样只扣分', () {
      final result = service.search(
        query: '汤',
        dishes: const [],
        canteenDishes: [
          _canteen('m1', '冬瓜汤', const ['汤']),
        ],
        exclusions: const SoftExclusionRules(windows: {'窗口A'}),
      );
      expect(result.hits, hasLength(1));
    });

    test('软排除 JSON 往返（app_settings 存储格式）', () {
      const rules = SoftExclusionRules(dishNames: {'红烧肉'}, windows: {'一楼'});
      final decoded = SoftExclusionRules.decode(rules.encode());
      expect(decoded.dishNames, contains('红烧肉'));
      expect(decoded.matches(name: '红烧肉盖饭'), isTrue);
      expect(SoftExclusionRules.decode('not json').isEmpty, isTrue);
    });
  });

  group('反馈闭环（显式、样本门槛）', () {
    test('一次点击不生效；两次同向才改变排序权重', () {
      final store = FeedbackStore();
      store.record('红烧肉', FeedbackVote.dislike);
      expect(store.multiplierFor('红烧肉'), 1.0, reason: '样本不足不生效');
      store.record('红烧肉', FeedbackVote.dislike);
      expect(store.multiplierFor('红烧肉'), 0.85);
      expect(store.scoreOf('红烧肉'), lessThan(0));
    });

    test('喜欢两次 ⇒ +5% boost；检索里真的生效', () {
      final store = FeedbackStore()
        ..record('红烧肉', FeedbackVote.like)
        ..record('红烧肉', FeedbackVote.like);
      expect(store.multiplierFor('红烧肉'), 1.05);
      const service = DishSearchService();
      final baseline = service.search(
        query: '红烧肉',
        dishes: [_dish('d1', '红烧肉')],
      );
      final boosted = service.search(
        query: '红烧肉',
        dishes: [_dish('d1', '红烧肉')],
        feedback: store,
      );
      expect(
        boosted.hits.single.score,
        greaterThan(baseline.hits.single.score),
      );
    });

    test('反馈 JSON 往返（app_settings 存储格式）', () {
      final store = FeedbackStore()
        ..record('A', FeedbackVote.like)
        ..record('B', FeedbackVote.dislike)
        ..record('B', FeedbackVote.dislike)
        ..record('B', FeedbackVote.dislike);
      final decoded = FeedbackStore.decode(store.encode());
      expect(decoded.scoreOf('B'), lessThan(0));
      expect(decoded.scoreOf('A'), 0, reason: '样本不足保持中性');
      expect(FeedbackStore.decode('not json').entries, isEmpty);
    });
  });

  group('会话级临时记忆（G20）', () {
    test('只在会话内：add/clear，不落库', () {
      final store = SessionMemoryStore();
      expect(store.add(const SessionMemory(text: '我在出差，只有便利店')), isTrue);
      expect(store.items, hasLength(1));
      final asMemories = store.asMemories(now);
      expect(asMemories.single.id, startsWith('session:'));
      expect(asMemories.single.pinned, isTrue);
      store.clear();
      expect(store.isEmpty, isTrue);
    });

    test('有界与去重：空白/超长/重复/超上限都被拒', () {
      final store = SessionMemoryStore(maxItems: 2);
      expect(store.add(const SessionMemory(text: '  ')), isFalse);
      expect(
        store.add(SessionMemory(text: '长' * (kAiMemoryMaxTextLength + 1))),
        isFalse,
      );
      expect(store.add(const SessionMemory(text: '出差')), isTrue);
      expect(store.add(const SessionMemory(text: '出差')), isFalse);
      expect(store.add(const SessionMemory(text: '只有便利店')), isTrue);
      expect(store.add(const SessionMemory(text: '第三条')), isFalse);
    });

    test('临时记忆在注入里排最前（比长期置顶更当前）', () {
      final store = SessionMemoryStore();
      store.add(const SessionMemory(text: '我在出差，只有便利店'));
      final selection = selectMemoriesForInjection(
        memories: [_memory('m1', '不吃香菜', pinned: true)],
        userMessage: '附近有什么吃的',
        sessionMemories: store.asMemories(now),
      );
      expect(selection.memories.first.text, '我在出差，只有便利店');
      expect(selection.injectedIds.first, startsWith('session:'));
    });
  });
}
