import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// docs/07 §9.3「UI 可维护性」的行数审计（2.0-6i-3b）：
///
/// - 页面只负责布局和用户事件；
/// - 单个 Dart 页面建议控制在约 300–500 行以内，超过后拆成
///   section/widget/controller。
///
/// 清单只覆盖 2.0 的 UI 面（饮食页及其 section、AI 工作台、菜单、下一餐主卡）。
/// 1.x 遗留的巨型页面（training 2140 行、settings 879、dashboard 559、
/// food_scan 547 等）不在此清单：docs/07 §9.3 针对新增页面，它们的拆分不属于
/// 本切片。这里用真实文件行数兜住「拆完又长回去」。
void main() {
  const budget = 500;
  const pagesUnderBudget = <String>[
    // 饮食页（2.0-6i-3b 拆分：页面 + 动作层 + 五个 section）
    'lib/features/nutrition/presentation/nutrition_page.dart',
    'lib/features/nutrition/presentation/nutrition_actions.dart',
    'lib/features/nutrition/presentation/sections/record_tab.dart',
    'lib/features/nutrition/presentation/sections/meal_card.dart',
    'lib/features/nutrition/presentation/sections/food_search_tab.dart',
    // （原 `nutrition_tab_chips.dart` / `nutrition_week_strip.dart` 是旧视觉件，
    // 阶段 I-2c 已删除；换成它们的新设计取代者。旧周条的滑动切周手势在
    // I-2c 迁回新件并配了测试。）
    'lib/features/nutrition/presentation/sections/nutrition_sub_tab_chips.dart',
    'lib/features/nutrition/presentation/sections/nutrition_record_week_strip.dart',
    'lib/features/nutrition/presentation/sections/nutrition_analysis_sliver.dart',
    'lib/features/nutrition/presentation/food_library_view.dart',
    // AI 工作台（2.0-6g）
    'lib/features/ai_workbench/presentation/ai_workbench_page.dart',
    // 菜单 tab（2.0-6c）
    'lib/features/campus_menus/presentation/menu_tab_view.dart',
    // （原 `menu_freshness_bar.dart` 是旧视觉件，阶段 I-2c 已删除：快照
    // 新鲜度概念被「地点→窗口→菜品」常驻结构取代；诚实性断言迁到
    // menu_source_license_test。）
    // 【清单退役】`next_meal_decision_card.dart` 随「下一餐」整族退役删除
    // （`docs/56` R4 / `docs/58` §5 台账）。清单必须跟着收窄——留一条不存在的
    // 路径会红在「不存在（清单过期？）」上，那是清单维护失败而不是行数问题。
  ];

  test('2.0 页面与 section 都在 500 行以内', () {
    final over = <String>[];
    for (final path in pagesUnderBudget) {
      final file = File(path);
      expect(file.existsSync(), isTrue, reason: '$path 不存在（清单过期？）');
      final lines = file.readAsLinesSync().length;
      if (lines > budget) over.add('$path（$lines 行）');
    }
    expect(
      over,
      isEmpty,
      reason:
          'docs/07 §9.3：超过 $budget 行的页面要拆成 section/widget/controller；'
          '当前超预算：${over.join('、')}',
    );
  });

  test('饮食页只留布局与用户事件（2.0-6i-3b 拆分后回归不到 400 行）', () {
    final lines = File(
      'lib/features/nutrition/presentation/nutrition_page.dart',
    ).readAsLinesSync().length;
    expect(lines, lessThanOrEqualTo(400));
  });
}
