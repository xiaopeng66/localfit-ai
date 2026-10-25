import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/features/ai_memory/domain/ai_memory.dart';
import 'package:localfit_ai/features/retrieval/application/memory_selector.dart';

/// **记忆「真的帮上忙」实测**（2026-10-24 用户：确保记忆系统对我的使用真正有帮助）。
///
/// 用户原话：「优化 ai 记忆的机制，确保这个记忆系统，对我的使用真正有帮助」。
///
/// 现有测试覆盖的是**存储层**（写入/去重/容量/过期/敏感信息）。但一个记忆
/// 系统「有没有用」不取决于存了多少，而取决于**这句话进来时，相关的那条
/// 记不记得起来**。所以本文件测的是**召回**。
///
/// 判据口径：模拟用户真实说法，断言「该被记起来的那条」在注入列表里。
/// 用的是线上同一套 `selectMemoriesForInjection`（关键词打分 + 门控 + MMR），
/// 不额外放宽。
void main() {
  final now = DateTime(2026, 10, 24, 12);

  AiMemory mem(
    String text, {
    String id = '',
    List<String> tags = const [],
    int importance = 50,
    bool pinned = false,
    AiMemoryKind kind = AiMemoryKind.preference,
    AiMemoryDomain domain = AiMemoryDomain.nutrition,
  }) => AiMemory(
    id: id.isEmpty ? 'm-${text.hashCode}' : id,
    text: text,
    kind: kind,
    domain: domain,
    tags: tags,
    pinned: pinned,
    source: 'explicit',
    status: 'active',
    createdAt: now,
    updatedAt: now,
    importance: importance,
    validFrom: now,
  );

  List<String> injectIds(List<AiMemory> memories, String message) =>
      selectMemoriesForInjection(
        memories: memories,
        userMessage: message,
      ).injectedIds;

  group('场景 1：口味偏好（最基础的一类记忆）', () {
    final memories = [
      mem('我喜欢清淡口味，不要太咸', tags: ['清淡', '口味'], id: 'light'),
      mem('我不吃香菜', tags: ['香菜', '忌口'], id: 'cilantro'),
    ];

    test('用户说「今天吃什么」→ 口味记忆应该被记起来', () {
      final ids = injectIds(memories, '今天吃什么');
      expect(
        ids,
        contains('light'),
        reason:
            '「今天吃什么」是最常见的开场白。如果连口味偏好都想不起来，'
            '这个记忆系统对用户就没有价值——每次都要重新说一遍。\n'
            '实际注入：$ids',
      );
    });

    test('用户说「推荐个午饭」→ 口味记忆应该被记起来', () {
      final ids = injectIds(memories, '推荐个午饭');
      expect(ids, contains('light'), reason: '推荐类问题最依赖口味记忆。实际注入：$ids');
    });

    test('用户说「晚饭吃啥好」→ 口味记忆应该被记起来', () {
      final ids = injectIds(memories, '晚饭吃啥好');
      expect(ids, contains('light'), reason: '实际注入：$ids');
    });
  });

  group('场景 2：忌口（安全相关，绝不能忘）', () {
    final memories = [
      mem('我不吃香菜', tags: ['香菜'], id: 'cilantro'),
      mem('我对花生过敏', tags: ['花生', '过敏'], id: 'peanut'),
    ];

    test('用户说「推荐个菜」→ 忌口/过敏记忆应该被记起来', () {
      final ids = injectIds(memories, '推荐个菜');
      expect(
        ids,
        contains('peanut'),
        reason:
            '过敏是**安全相关**的记忆。用户问「推荐个菜」时不记起来，'
            '模型就可能推荐含花生的菜——这比「记不住口味」严重得多。\n'
            '实际注入：$ids',
      );
    });
  });

  group('场景 3：说法变化（同一个意思换个词）', () {
    final memories = [
      mem(
        '我周三晚上练腿',
        tags: ['周三', '练腿'],
        id: 'wed-leg',
        domain: AiMemoryDomain.training,
      ),
      mem('我通常在食堂二楼的川菜窗口吃', tags: ['食堂', '二楼'], id: 'canteen'),
    ];

    test('用户说「今天练什么」→ 训练习惯应该被记起来', () {
      final ids = injectIds(memories, '今天练什么');
      expect(ids, contains('wed-leg'), reason: '实际注入：$ids');
    });

    test('用户说「去哪个窗口吃」→ 常去窗口应该被记起来', () {
      final ids = injectIds(memories, '去哪个窗口吃');
      expect(ids, contains('canteen'), reason: '实际注入：$ids');
    });
  });

  group('场景 4：完全无关的话 → 不该塞一堆记忆进去（防噪音）', () {
    final memories = [
      mem('我喜欢清淡口味', tags: ['清淡'], id: 'light'),
      mem('我不吃香菜', tags: ['香菜'], id: 'cilantro'),
      mem('我周三晚上练腿', tags: ['练腿'], id: 'wed-leg'),
    ];

    test('用户说「你好」→ 不该把三条记忆全塞进去', () {
      final selection = selectMemoriesForInjection(
        memories: memories,
        userMessage: '你好',
      );
      expect(
        selection.memories.length,
        lessThanOrEqualTo(1),
        reason:
            '打招呼时塞一堆记忆是噪音，会稀释模型对当前问题的注意力。\n'
            '实际注入：${selection.injectedIds}',
      );
    });
  });

  group('场景 5：置顶记忆永远在', () {
    final memories = [
      mem('我对花生过敏', tags: ['花生'], id: 'peanut', pinned: true, importance: 95),
      mem('我喜欢清淡口味', tags: ['清淡'], id: 'light'),
    ];

    test('无论说什么，置顶记忆都在（这是用户显式表达的「这条很重要」）', () {
      for (final message in ['你好', '今天吃什么', '帮我记一下体重']) {
        final ids = injectIds(memories, message);
        expect(ids, contains('peanut'), reason: '「$message」时丢了置顶记忆。实际：$ids');
      }
    });
  });

  group('场景 6：条目多时的召回（真实用户会存几十条）', () {
    final memories = [
      for (var i = 0; i < 30; i++)
        mem('这是第 $i 条无关的记忆，关于第 $i 件小事', id: 'noise-$i'),
      mem('我喜欢清淡口味，不要太咸', tags: ['清淡', '口味'], id: 'light'),
    ];

    test('30 条噪音里，说「今天吃什么」仍能想起来口味偏好', () {
      final ids = injectIds(memories, '今天吃什么');
      expect(ids, contains('light'), reason: '真实用户存几十条后，最该用的那条不能被噪音挤掉。实际：$ids');
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // 【RED→GREEN，2026-10-24】门控的**设计缺陷**（上面 6 条红就是这个）
  //
  // 原实现：`maxRelevance < 0.15` ⇒ `gated = true` ⇒ **候选集只剩
  // 「置顶 or importance ≥ 80」**。而记忆的默认 importance 是 50。
  //
  // 后果：用户存了「我喜欢清淡口味」「我对花生过敏」，问「今天吃什么」时
  // 字面零重叠（bigram 无交集）⇒ 分数 0 ⇒ 门控 ⇒ **一条都注入不进去**。
  //
  // 这不是参数调得不合适，是**判据本身错了**：
  // 记忆的价值恰恰在于「用户不会重复说」——要求用户这句话与记忆**字面**
  // 相关才能想起来，等于要求用户每次都复述一遍，记忆就没有意义。
  //
  // 但也不能反过来「永远全量注入」：那是噪音，会稀释模型注意力（场景 4
  // 已经钉住「打招呼不该塞一堆」）。正确做法是**按领域相关性兜底**：
  // 门控触发时，仍然保留「与这句话的意图领域相符」的记忆。
  // ══════════════════════════════════════════════════════════════════
  group('场景 7：门控兜底（不该因为「字面没重叠」就整条丢掉）', () {
    test('问吃的 → 饮食域记忆仍应注入（即使字面零重叠）', () {
      final memories = [
        mem('我不吃香菜', tags: ['香菜'], id: 'cilantro'),
        mem('我周三晚上练腿', id: 'leg', domain: AiMemoryDomain.training),
      ];
      final ids = injectIds(memories, '今天吃什么');
      expect(ids, contains('cilantro'), reason: '饮食问题应该带出饮食域的记忆。实际：$ids');
    });

    test('问训练 → 训练域记忆仍应注入，且不夹带饮食域噪音', () {
      final memories = [
        mem('我不吃香菜', tags: ['香菜'], id: 'cilantro'),
        mem('我周三晚上练腿', id: 'leg', domain: AiMemoryDomain.training),
      ];
      final ids = injectIds(memories, '今天练什么');
      expect(ids, contains('leg'), reason: '训练问题应该带出训练域记忆。实际：$ids');
      expect(
        ids,
        isNot(contains('cilantro')),
        reason: '训练问题不该夹带饮食忌口——领域兜底要能区分。实际：$ids',
      );
    });

    test('问了完全无关的事（如「你好」）→ 领域兜底也不该全量注入', () {
      final memories = [
        mem('我不吃香菜', id: 'cilantro'),
        mem('我周三晚上练腿', id: 'leg', domain: AiMemoryDomain.training),
        mem('我通常晚上 11 点睡', id: 'sleep', domain: AiMemoryDomain.schedule),
      ];
      final selection = selectMemoriesForInjection(
        memories: memories,
        userMessage: '你好',
      );
      expect(
        selection.memories.length,
        lessThanOrEqualTo(2),
        reason: '没有任何领域意图时不该把三类记忆全塞进去。实际：${selection.injectedIds}',
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // 场景 8–10：真实使用姿势（2026-10-24 补，防止为通过前面几组而过度注入）
  // ══════════════════════════════════════════════════════════════════
  group('场景 8：领域兜底有上限（不许因此把同域记忆全塞进去）', () {
    test('存了 20 条饮食记忆，问「今天吃什么」→ 最多带出 4 条兜底', () {
      final memories = [
        for (var i = 0; i < 20; i++) mem('饮食偏好第 $i 条：我喜欢某某口味', id: 'food-$i'),
      ];
      final selection = selectMemoriesForInjection(
        memories: memories,
        userMessage: '今天吃什么',
      );
      expect(
        selection.memories.length,
        lessThanOrEqualTo(4),
        reason:
            '门控兜底的意义是「别一条都不给」，不是「全给」。'
            '20 条全塞进去会稀释模型注意力。实际：${selection.memories.length} 条',
      );
      expect(
        selection.memories.length,
        greaterThan(0),
        reason: '但也不能一条都不给。实际：${selection.memories.length} 条',
      );
    });
  });

  group('场景 9：跨域不串味', () {
    test('问饮食不该带出作息/训练记忆（领域兜底要分得清）', () {
      final memories = [
        mem('我喜欢清淡口味', id: 'light'),
        mem('我周三晚上练腿', id: 'leg', domain: AiMemoryDomain.training),
        mem('我通常晚上 11 点睡', id: 'sleep', domain: AiMemoryDomain.schedule),
      ];
      final ids = injectIds(memories, '今天吃什么');
      expect(ids, contains('light'));
      expect(ids, isNot(contains('leg')), reason: '饮食问题不该带训练记忆。实际：$ids');
      expect(ids, isNot(contains('sleep')), reason: '饮食问题不该带作息记忆。实际：$ids');
    });

    test('问作息不该带出饮食忌口', () {
      final memories = [
        mem('我不吃香菜', id: 'cilantro'),
        mem('我通常晚上 11 点睡', id: 'sleep', domain: AiMemoryDomain.schedule),
      ];
      final ids = injectIds(memories, '我几点睡比较好');
      expect(ids, contains('sleep'));
      expect(ids, isNot(contains('cilantro')), reason: '作息问题不该带忌口。实际：$ids');
    });
  });

  group('场景 10：含否定的说法（「不辣」类）', () {
    test('用户说「想吃点不辣的」→ 口味记忆仍应记起来', () {
      final memories = [
        mem('我喜欢清淡口味', tags: ['清淡'], id: 'light'),
      ];
      final ids = injectIds(memories, '想吃点不辣的');
      expect(ids, contains('light'), reason: '实际：$ids');
    });
  });
}
