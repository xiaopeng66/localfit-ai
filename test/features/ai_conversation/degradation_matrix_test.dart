import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/features/ai_conversation/domain/degradation_matrix.dart';

/// 降级矩阵（docs/41 §10 G10）：**每一格都要有测试判据**。
/// 矩阵本体是 `degradation_matrix.dart` 的常量；这里把 5 行 × 4 列逐格钉住，
/// 页面文案改了、行为变了，这里先红。
void main() {
  test('矩阵覆盖 5 行 × 4 列，没有洞', () {
    expect(kDegradationMatrix.keys, hasLength(DegradationRow.values.length));
    for (final row in DegradationRow.values) {
      expect(
        kDegradationMatrix[row]!.keys.toSet(),
        DegradationColumn.values.toSet(),
        reason: '${row.label} 行缺列',
      );
    }
  });

  group('记忆注入列：任何降级都是「置顶 + 关键词」本地路径', () {
    for (final row in DegradationRow.values) {
      test('${row.label}：记忆注入退本地关键词', () {
        final cell =
            kDegradationMatrix[row]![DegradationColumn.memoryInjection]!;
        expect(cell.behavior, contains('置顶'));
        expect(cell.behavior, contains('关键词'));
        // 2026-10-21 裁决 D-2：断网不影响端上语义（不需要网络），
        // 该行**不喊**「语义不可用」；其余行必须如实标注。
        if (row == DegradationRow.offline) {
          expect(cell.notice, isEmpty);
          expect(cell.behavior, contains('端上语义'));
        } else {
          expect(cell.notice, contains('语义'));
        }
      });
    }
  });

  group('菜品推荐列：本地标签 + 规则，无 AI 文案', () {
    for (final row in DegradationRow.values) {
      test('${row.label}：推荐退本地标签规则', () {
        final cell =
            kDegradationMatrix[row]![DegradationColumn.dishRecommendation]!;
        expect(cell.behavior, contains('本地标签'));
        expect(cell.notice, contains('AI'));
      });
    }
  });

  group('搜索列：语义路径的有无按行如实区分', () {
    test('AI 未配置 / 无网 / 对话模型不可用：关键词+标签（不误报语义不可用）', () {
      for (final row in [
        DegradationRow.aiNotConfigured,
        DegradationRow.offline,
        DegradationRow.chatModelUnavailable,
      ]) {
        final cell = kDegradationMatrix[row]![DegradationColumn.search]!;
        expect(cell.behavior, contains('关键词'));
        // 这三行都是「语义要么本来没有、要么在端上照常可用」⇒ 不喊话。
        expect(cell.notice, isEmpty);
        if (row == DegradationRow.offline) {
          // 裁决 D-2：断网时本地语义仍可用，不能写成降级。
          expect(cell.behavior, contains('端上语义'));
        }
      }
    });

    test('端上模型不可用：如实提示「语义检索不可用」', () {
      final cell =
          kDegradationMatrix[DegradationRow
              .onDeviceModelUnavailable]![DegradationColumn.search]!;
      expect(cell.behavior, contains('语义检索不可用'));
      expect(cell.notice, contains('语义检索不可用'));
    });

    test('索引重建中：如实提示重建中且仍可用关键词', () {
      final cell =
          kDegradationMatrix[DegradationRow.indexBuilding]![DegradationColumn
              .search]!;
      expect(cell.behavior, contains('重建'));
      expect(cell.notice, contains('重建中'));
      expect(cell.behavior, contains('关键词'));
    });
  });

  group('记餐列：任何状态下都正常（D10 手动营养兜底）', () {
    for (final row in DegradationRow.values) {
      test('${row.label}：记餐不降级', () {
        final cell = kDegradationMatrix[row]![DegradationColumn.mealLogging]!;
        expect(cell.behavior, contains('正常'));
        expect(cell.behavior, contains('user_input'));
        expect(cell.notice, isEmpty, reason: '记餐可用时不需要任何降级提示');
      });
    }
  });

  test('degradationNotice 直读矩阵（页面不许各写一份 switch）', () {
    expect(
      degradationNotice(
        DegradationRow.onDeviceModelUnavailable,
        DegradationColumn.search,
      ),
      isNotEmpty,
    );
    expect(
      degradationNotice(DegradationRow.offline, DegradationColumn.mealLogging),
      isEmpty,
    );
  });

  test('AI 配置状态 → 行判定', () {
    expect(
      degradationRowFor(aiConfigured: false),
      DegradationRow.aiNotConfigured,
    );
    expect(
      degradationRowFor(aiConfigured: true),
      DegradationRow.chatModelUnavailable,
    );
  });

  // 2026-10-22（隔离变异 M06 抓到）：上面的断言只查「包含『语义』」，
  // 把整句文案改短照样绿。搜索列的提示是**用户能看到的降级标注**，
  // 逐字钉住——改措辞必须先改测试（评审里就会被看到）。
  test('搜索列两条降级提示逐字固定（用户可见文案不许悄悄漂移）', () {
    expect(
      degradationNotice(
        DegradationRow.onDeviceModelUnavailable,
        DegradationColumn.search,
      ),
      '（语义检索不可用，正在用关键词 + 标签搜索）',
    );
    expect(
      degradationNotice(DegradationRow.indexBuilding, DegradationColumn.search),
      '（语义索引重建中，先按关键词 + 标签搜索）',
    );
    expect(kSemanticBelowThresholdNotice, '（语义候选相关度不足，本次按关键词 + 标签显示）');
  });
}
