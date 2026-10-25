import 'package:flutter/widgets.dart';

import 'package:localfit_ai/app/design/widgets/lf_badge.dart';
import 'package:localfit_ai/app/design/widgets/lf_evidence_badge.dart';

/// 来源与证据的统一词汇表（docs/41 §4 铁律 ④「来源与证据永远可见」）。
///
/// 为什么要有这个文件：同一份数据会在四个地方出现——餐记录卡、菜品卡、
/// 食堂目录行、食物卡。若每处各写一份 `switch`，同一顿食堂菜会在饮食页写
/// 「食堂」、在今日页写「菜品」；这正是 docs/21 §3.3 当初把证据映射收进
/// `meal_evidence.dart` 的理由，本文件把**来源**那一维也收进来。
///
/// 两条硬约束：
/// * **不静默夸大**：来源不明一律按最保守的一档呈现（[FoodSourceKind.unknown] /
///   [LfEvidenceGrade.estimated]）——把不知道的事标成「已确认」是实质性的
///   证据夸大（沿用 `meal_evidence.dart` 的既有口径）。
/// * **没有配料/分析数据的行不许写「安全」**：本文件只渲染「是什么」，
///   不渲染「不含什么」（docs/40 §2.5 的诚实边界）。

/// 一条记录/一份数据的**来源种类**（不是证据等级；两者正交）。
enum FoodSourceKind {
  food('食物'),
  dish('菜品'),
  menuItem('食堂菜'),
  scan('扫描'),
  manual('手动'),
  chat('对话'),
  unknown('记录');

  const FoodSourceKind(this.label);

  /// 徽标文案（12 字以内，`LfBadge` 单行）。
  final String label;
}

/// `meals.source` / `meal_items` 来源列 → 来源种类。
///
/// 值域是本仓自有存储的字符串常量（`MealRepository.create(source:)` 的
/// 调用点集合）；新增一个写入值必须同时在这里登记，否则它会落到「记录」
/// 这个兜底档——兜底档是**如实**的（我们确实不知道），不是错。
FoodSourceKind foodSourceKindFor(String? source) => switch (source?.trim()) {
  'food' || 'food_library' => FoodSourceKind.food,
  'dish' || 'dish_library' => FoodSourceKind.dish,
  'menu_item' || 'canteen' => FoodSourceKind.menuItem,
  'ai_scan' || 'scan' => FoodSourceKind.scan,
  'manual' || 'history_reuse' => FoodSourceKind.manual,
  'ai_chat' || 'ai' => FoodSourceKind.chat,
  _ => FoodSourceKind.unknown,
};

/// 食堂营养证据的 `origin` → 给人看的来源文案（docs/40 §3.1）。
///
/// 三档：引用食物库 / AI 估算 / 用户输入。**不合并**成一档「有营养」——
/// 三者可信度不同，界面上必须分得开（这正是「不把引用伪装成实测」）。
String canteenOriginLabel(String? origin) => switch (origin?.trim()) {
  'food_library' => '食物库',
  'user_input' => '用户输入',
  'ai_estimate' => 'AI 估算',
  _ => '来源不明',
};

/// 食堂营养证据 `origin` → 证据等级（A/B/C/D 角标用的那一维）。
///
/// * `user_input`：用户自己填的数，按**已确认**档呈现（他对自己吃的东西
///   最权威），但来源文案仍是「用户输入」——两维分开表达。
/// * `food_library`：引用的是食物库的既有事实，按**已确认**档。
/// * `ai_estimate`：模型估的，按**估算**档。
LfEvidenceGrade canteenOriginGrade(String? origin) => switch (origin?.trim()) {
  'food_library' || 'user_input' => LfEvidenceGrade.confirmed,
  _ => LfEvidenceGrade.estimated,
};

/// 统一的「来源 + 证据」徽标对：左边是来源种类，右边是证据等级。
///
/// 两个徽标是**两个维度**，不合并成一句（「食堂 + AI 估算」和「食堂 +
/// 已确认」是两件不同的事）。任何一处展示来源都必须用本件，不许各页自绘。
class LfSourceBadgePair extends StatelessWidget {
  const LfSourceBadgePair({
    super.key,
    required this.kindLabel,
    required this.gradeLabel,
    required this.grade,
    this.keyPrefix,
  });

  /// 从 `meals.source` 值构造（餐记录卡）。
  factory LfSourceBadgePair.forMealSource(
    String? source, {
    Key? key,
    String? keyPrefix,
    LfEvidenceGrade? grade,
  }) {
    final kind = foodSourceKindFor(source);
    return LfSourceBadgePair(
      key: key,
      keyPrefix: keyPrefix,
      kindLabel: kind.label,
      grade: grade ?? LfEvidenceGrade.estimated,
      gradeLabel: switch (grade ?? LfEvidenceGrade.estimated) {
        LfEvidenceGrade.confirmed => '已确认',
        LfEvidenceGrade.estimated => 'AI 估算',
        LfEvidenceGrade.incomplete => '待补全',
      },
    );
  }

  /// 从食堂营养证据的 `origin` 构造（食堂目录行 / 详情）。
  factory LfSourceBadgePair.forCanteenOrigin(
    String? origin, {
    Key? key,
    String? keyPrefix,
  }) {
    final grade = canteenOriginGrade(origin);
    return LfSourceBadgePair(
      key: key,
      keyPrefix: keyPrefix,
      kindLabel: '食堂菜',
      grade: grade,
      gradeLabel: canteenOriginLabel(origin),
    );
  }

  final String kindLabel;
  final String gradeLabel;
  final LfEvidenceGrade grade;

  /// 给两枚徽标生成稳定 Key（`<prefix>-source` / `<prefix>-evidence`）。
  final String? keyPrefix;

  @override
  Widget build(BuildContext context) {
    final prefix = keyPrefix;
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        LfBadge.neutral(
          kindLabel,
          key: prefix == null ? null : Key('$prefix-source'),
        ),
        switch (grade) {
          LfEvidenceGrade.confirmed => LfEvidenceBadge.confirmed(
            key: prefix == null ? null : Key('$prefix-evidence'),
            text: gradeLabel,
          ),
          LfEvidenceGrade.estimated => LfEvidenceBadge.estimated(
            key: prefix == null ? null : Key('$prefix-evidence'),
            text: gradeLabel,
          ),
          LfEvidenceGrade.incomplete => LfEvidenceBadge.incomplete(
            key: prefix == null ? null : Key('$prefix-evidence'),
            text: gradeLabel,
          ),
        },
      ],
    );
  }
}
