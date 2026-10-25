import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// RV2-P2-08（`docs/52`）：UI 字面量漂移的**防回退门禁**。
///
/// 审查扫出：12 个 `Color(0x…)`、5 个源文件外的 `fontSize:`、36 处数字
/// `EdgeInsets`。逐处 token 化属于「重画 UI」——在没有逐帧复核的前提下改
/// 颜色/字号会引入真实视觉漂移，所以本轮**冻结存量、禁止新增**：
///
/// - 颜色/字号：只允许出现在 token 源文件（`lf_tokens.dart` /
///   `lf_text_styles.dart` / `app_theme.dart`）与 `lib/app/design/widgets/`
///   下的设计系统组件里；
/// - 业务页面（`lib/features/**`）**一个新字面量都不许加**——新增时必须在
///   设计系统里加 token，而不是就地写 `Color(0xFF…)` 或 `fontSize: 13`。
///
/// 这不是「放宽」，是把存量债务钉成显式白名单：白名单里每一条都带文件名，
/// 想新增必须改这份文件（也就必须在评审里说明理由）。
void main() {
  final repoRoot = Directory.current.path.replaceAll(r'\', '/');

  /// 存量白名单（2026-10-22 冻结）。键 = 相对路径，值 = 该文件里的条数上限。
  /// 只许**减**，不许加新文件；减少时把数字改小。
  const colorBudget = <String, int>{
    'lib/app/design/widgets/design_card.dart': 1,
    'lib/app/design/widgets/lf_achievement_row.dart': 1,
    'lib/app/design/widgets/lf_chat_bubbles.dart': 6,
    'lib/app/design/widgets/lf_chat_input.dart': 1,
    'lib/app/design/widgets/lf_segmented_toggle.dart': 1,
    'lib/app/design/widgets/lf_toggle_switch.dart': 1,
    'lib/features/dashboard/presentation/sections/dashboard_ai_entry_card.dart':
        1,
  };

  const fontSizeBudget = <String, int>{
    'lib/app/design/widgets/lf_food_kcal_ring.dart': 2,
    'lib/app/design/widgets/lf_metric_gauge.dart': 1,
    'lib/features/nutrition/presentation/food_detail_sheet.dart': 1,
    'lib/features/training/presentation/exercise_library_page.dart': 1,
  };

  Map<String, int> scan(String pattern) {
    final found = <String, int>{};
    for (final entity in Directory('$repoRoot/lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final relative = entity.path
          .replaceAll(r'\', '/')
          .replaceFirst('$repoRoot/', '');
      // token 源文件与文本样式表是「唯一事实源」，字面量本来就该在那里。
      if (relative.endsWith('lf_tokens.dart') ||
          relative.endsWith('lf_text_styles.dart') ||
          relative.endsWith('app_theme.dart')) {
        continue;
      }
      final text = entity.readAsStringSync();
      final count = RegExp(pattern).allMatches(text).length;
      if (count > 0) found[relative] = count;
    }
    return found;
  }

  void expectNoGrowth(
    Map<String, int> actual,
    Map<String, int> budget,
    String label,
  ) {
    final offenders = <String>[];
    for (final entry in actual.entries) {
      final allowed = budget[entry.key] ?? 0;
      if (entry.value > allowed) {
        offenders.add('${entry.key}（${entry.value} > 允许 $allowed）');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          '$label 字面量超出冻结预算：${offenders.join('；')}。'
          '新增请先在 lib/app/design 里加 token，不要在业务页面就地写死。',
    );
  }

  test('Color(0x…) 字面量不得超出冻结预算（新颜色先加 token）', () {
    final actual = scan(r'Color\(0x');
    expectNoGrowth(actual, colorBudget, 'Color(0x…)');
    // 预算只许减：白名单里写了的文件若已经完全清掉，提醒同步收窄。
    final stale = [
      for (final key in colorBudget.keys)
        if ((actual[key] ?? 0) == 0) key,
    ];
    expect(
      stale,
      isEmpty,
      reason: '这些文件已经没有颜色字面量了，请从 colorBudget 里删掉：${stale.join('、')}',
    );
  });

  test('fontSize 数字字面量不得超出冻结预算（新字号先加 LfText 档位）', () {
    final actual = scan(r'fontSize:\s*\d');
    expectNoGrowth(actual, fontSizeBudget, 'fontSize');
    final stale = [
      for (final key in fontSizeBudget.keys)
        if ((actual[key] ?? 0) == 0) key,
    ];
    expect(
      stale,
      isEmpty,
      reason: '这些文件已经没有字号字面量了，请从 fontSizeBudget 里删掉：${stale.join('、')}',
    );
  });
}
