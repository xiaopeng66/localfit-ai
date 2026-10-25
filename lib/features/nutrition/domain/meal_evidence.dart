import 'package:flutter/widgets.dart' show Key;

import 'package:localfit_ai/app/design/widgets/lf_evidence_badge.dart';

/// 餐食来源 → 证据徽标文案（docs/21 §3.3 / §7.3「证据分级必须贯穿」）。
///
/// 判定只剩一个维度：这条营养数据**是人工确认的还是 AI 估出来的**。
/// 映射写在这里而不是各页面各写一份——两处口径不一致时，同一顿饭会在
/// 饮食页写「已确认」、在今日页写「AI 估算」。
///
/// 未知来源按 [LfEvidenceGrade.estimated] 呈现：宁可把人工记录标低，
/// 也不要把 AI 估算标成「已确认」（后者是实质性的证据夸大）。
LfEvidenceGrade evidenceGradeForSource(String source) => switch (source) {
  'manual' || 'history_reuse' => LfEvidenceGrade.confirmed,
  // 2026-10-20 审查 RV-P1-07：引用食物库的事实按「已确认」呈现，
  // 与 `canteenOriginGrade` 同口径。
  'food_library' => LfEvidenceGrade.confirmed,
  'ai_scan' => LfEvidenceGrade.estimated,
  // `recipe` 是**老库里遗留的来源值**：2026-10-04（docs/28 W4）起食谱整族
  // 下线，实时记录路径不再产生这一来源；这一支只为让老库既有记录仍按
  // 「人工确认」呈现，新代码不要复用。
  'recipe' => LfEvidenceGrade.confirmed,
  // 菜品库餐由用户从菜单里主动「添加」，但菜品本身的营养可能是 AI 估的
  // （`DishRecord.source` 另有分级，见菜品卡的来源徽标）——这里按**谨慎**
  // 口径记为估算：把来源不明的一餐标成「已确认」是实质性的证据夸大。
  'dish_library' => LfEvidenceGrade.estimated,
  _ => LfEvidenceGrade.estimated,
};

/// 徽标文案（`已确认` / `AI 估算`）。
String evidenceLabelForSource(String source) =>
    switch (evidenceGradeForSource(source)) {
      LfEvidenceGrade.confirmed => '已确认',
      LfEvidenceGrade.estimated => 'AI 估算',
      LfEvidenceGrade.incomplete => '待补全',
    };

/// 直接产出徽标。[LfEvidenceBadge] 的三个构造器是命名的，调用点各自写
/// switch 会把这个映射抄成三份、日后漏改一处。
LfEvidenceBadge evidenceBadgeForSource(String source, {Key? key}) =>
    switch (evidenceGradeForSource(source)) {
      LfEvidenceGrade.confirmed => LfEvidenceBadge.confirmed(
        key: key,
        text: evidenceLabelForSource(source),
      ),
      LfEvidenceGrade.estimated => LfEvidenceBadge.estimated(
        key: key,
        text: evidenceLabelForSource(source),
      ),
      LfEvidenceGrade.incomplete => LfEvidenceBadge.incomplete(
        key: key,
        text: evidenceLabelForSource(source),
      ),
    };
