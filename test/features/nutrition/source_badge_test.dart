import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/features/nutrition/domain/source_badge.dart';

/// 统一来源徽标（docs/41 §7 铁律 ④「来源与证据永远可见」）：
/// 同一份数据在餐记录卡/菜品卡/食堂目录行四处的映射必须是**同一份**。
void main() {
  group('meals.source 值域 → 来源种类', () {
    test('食物/菜品/食堂/扫描/手动/对话各档如实映射', () {
      expect(foodSourceKindFor('food_library').label, '食物');
      expect(foodSourceKindFor('dish_library').label, '菜品');
      expect(foodSourceKindFor('menu_item').label, '食堂菜');
      expect(foodSourceKindFor('ai_scan').label, '扫描');
      expect(foodSourceKindFor('manual').label, '手动');
      expect(foodSourceKindFor('history_reuse').label, '手动');
      expect(foodSourceKindFor('ai_chat').label, '对话');
    });

    test('未知来源按保守兜底「记录」，不编造来源', () {
      expect(foodSourceKindFor(null).label, '记录');
      expect(foodSourceKindFor('').label, '记录');
      expect(foodSourceKindFor('something_new').label, '记录');
    });
  });

  group('食堂营养证据 origin 三档', () {
    test('三档文案分开（引用 / 用户输入 / AI 估算 不合并）', () {
      expect(canteenOriginLabel('food_library'), '食物库');
      expect(canteenOriginLabel('user_input'), '用户输入');
      expect(canteenOriginLabel('ai_estimate'), 'AI 估算');
      expect(canteenOriginLabel(null), '来源不明');
    });

    test('user_input / food_library 是已确认档，ai_estimate 是估算档', () {
      // 直接断言等级语义（用字符串 repr 对照，避免引 UI 件）。
      expect(
        canteenOriginGrade('user_input').toString(),
        'LfEvidenceGrade.confirmed',
      );
      expect(
        canteenOriginGrade('food_library').toString(),
        'LfEvidenceGrade.confirmed',
      );
      expect(
        canteenOriginGrade('ai_estimate').toString(),
        'LfEvidenceGrade.estimated',
      );
      expect(canteenOriginGrade(null).toString(), 'LfEvidenceGrade.estimated');
    });

    // `RV4-P3-02`：「每档解释句」这条用例随 `canteenOriginExplanation`
    // 一起退役——那个函数生产零调用（详情卡改画徽标之后没人读它）。
    // 断言的**对象**（解释句）不存在了；档位判据仍由上面
    // `canteenOriginGrade` 的用例覆盖。
  });
}
