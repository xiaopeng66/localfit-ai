import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/features/ai_memory/application/memory_promotion.dart';
import 'package:localfit_ai/features/ai_memory/domain/ai_memory.dart';
import 'package:localfit_ai/features/daily_plan/domain/planning_constraints.dart';

/// 记忆 → 忌口/偏好晋升（docs/41 §5 G1）：每条判据一个用例。
AiMemory _memory(String text) => AiMemory(
  id: 'm1',
  text: text,
  kind: AiMemoryKind.preference,
  domain: AiMemoryDomain.nutrition,
  tags: const [],
  pinned: false,
  source: 'manual',
  status: 'active',
  createdAt: DateTime.utc(2026, 10, 18),
  updatedAt: DateTime.utc(2026, 10, 18),
);

void main() {
  group('memoryPromotionKeyword：从记忆文本提取忌口词', () {
    test('常见句式都能剥出食材词', () {
      expect(memoryPromotionKeyword('不吃香菜'), '香菜');
      expect(memoryPromotionKeyword('对芒果过敏'), '芒果');
      expect(memoryPromotionKeyword('芒果过敏'), '芒果');
      expect(memoryPromotionKeyword('忌口花生'), '花生');
      expect(memoryPromotionKeyword('讨厌芹菜'), '芹菜');
      expect(memoryPromotionKeyword('别给我香菜'), '香菜');
      expect(memoryPromotionKeyword('鸡蛋吃了不舒服'), '鸡蛋');
    });

    test('剥不出食材词时返回 null（不给晋升）', () {
      // 整句抽象、没有具体食材的记不住约束。
      expect(memoryPromotionKeyword('我喜欢清淡的口味'), isNull);
      expect(memoryPromotionKeyword(''), isNull);
    });
  });

  group('promoteMemoryToConstraint', () {
    test('新词落库（走 persist 闭包，等价 constraints.set 的写路径）', () async {
      final saved = <String>[];
      final result = await promoteMemoryToConstraint(
        memory: _memory('不吃香菜'),
        current: const ['芒果'],
        persist: (next) async => saved
          ..clear()
          ..addAll(next),
      );
      expect(result, MemoryPromotionResult.added);
      expect(saved, ['芒果', '香菜']);
    });

    test('重复晋升幂等：归一化后已存在就不重复添加', () async {
      var called = false;
      final result = await promoteMemoryToConstraint(
        memory: _memory('不吃 香菜'),
        current: const ['香菜'],
        persist: (next) async => called = true,
      );
      expect(result, MemoryPromotionResult.alreadyPresent);
      expect(called, isFalse);
    });

    test('清单满（9 项）时如实拒绝，不静默挤掉旧项', () async {
      var called = false;
      final result = await promoteMemoryToConstraint(
        memory: _memory('不吃香菜'),
        current: List.generate(
          PlanningConstraints.maxAllergenAvoidances,
          (i) => '食材$i',
        ),
        persist: (next) async => called = true,
      );
      expect(result, MemoryPromotionResult.full);
      expect(called, isFalse);
    });

    test('提取不出忌口词的记 refused（抛出可行动文案）', () async {
      await expectLater(
        promoteMemoryToConstraint(
          memory: _memory('我喜欢清淡的口味'),
          current: const [],
          persist: (_) async {},
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
