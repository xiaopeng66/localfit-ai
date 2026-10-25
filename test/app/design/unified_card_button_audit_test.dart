import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 卡片与按钮形态统一化的防回退审计（docs/21 §3.1 卡片 / §3.8 按钮九型）。
///
/// 两条机械规则，都是「只减不增」：把**存量**按文件登记进预算表，本轮每转换一处
/// 就下调一次数字，最终全部归零。这样能抓住行为测试抓不住的那一类回归——
/// 换件前后**像素一致**时（例如 `DesignCard` 改回裸 `Card` 只差一圈描边），
/// 所有行为断言依旧全绿。
///
/// 【为什么不查 `Divider`】分隔线的颜色已由 `dividerTheme` 全局接管，
/// 裸 `Divider()` 就是收敛后的正确写法。
/// 【为什么不机械禁止 `ListTile`】`ListTile` 当**列表行**（如历史餐食弹层）是
/// 合法形态，「当卡片用」静态判断不了。它由 `component_theme_test.dart` 的
/// `listTileTheme` 断言兜住（至少不再是系统默认观感）。
/// 【计数口径】先剥掉 `//` 行注释（文档里提到 `Card(` 不算用例），再按
/// `\bCard\(` 计次——`DesignCard(` 的 `C` 前是词字符，没有词边界，天然不计入。
void main() {
  String codeOf(File file) => file
      .readAsLinesSync()
      .map((line) {
        final at = line.indexOf('//');
        return at < 0 ? line : line.substring(0, at);
      })
      .join('\n');

  Map<String, int> counts(
    RegExp pattern, {
    required bool Function(String path) include,
  }) {
    final found = <String, int>{};
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll(r'\', '/');
      if (!include(path)) continue;
      final hits = pattern.allMatches(codeOf(entity)).length;
      if (hits > 0) found[path] = hits;
    }
    return found;
  }

  void expectNoGrowth({
    required String rule,
    required Map<String, int> actual,
    required Map<String, int> budget,
  }) {
    final grown = <String>[];
    for (final entry in actual.entries) {
      final allowed = budget[entry.key] ?? 0;
      if (entry.value > allowed) {
        grown.add('${entry.key}：${entry.value} 处 > 预算 $allowed');
      }
    }
    expect(grown, isEmpty, reason: '$rule 出现新增散件（收敛到共享件后请不要放宽本规则）：$grown');
    final stale = budget.entries
        .where((e) => (actual[e.key] ?? 0) != e.value)
        .map((e) => '${e.key}：登记 ${e.value}，实际 ${actual[e.key] ?? 0}')
        .toList();
    expect(
      stale,
      isEmpty,
      reason: '$rule 的预算表已与实际不符，请改成实际值（暂缓的存量不得被悄悄写回来）：$stale',
    );
  }

  test('裸 `Card(` 只减不增（全部卡片收敛到 DesignCard/MutedBlock）', () {
    expectNoGrowth(
      rule: '卡片统一化',
      actual: counts(
        RegExp(r'\bCard\('),
        include: (path) => !path.startsWith('lib/app/design/'),
      ),
      budget: const {
        // 波 3 收尾（2026-10-03）：29 处存量已全部收敛到 `DesignCard`/
        // `MutedBlock`。2026-10-04（docs/28 §6.2）：原先剩下的两个
        // `recipe_planning/` 例外文件（3 处语义填色面）随整个目录一起删掉了
        // ——预算表因此归零，`Card(` 在全仓 features 内已无任何实例。
      },
    );
  });

  test('手写 `styleFrom(` 只减不增（按钮样式一律出自 lf_buttons/主题层）', () {
    expectNoGrowth(
      rule: '按钮统一化',
      actual: counts(
        RegExp(r'styleFrom\('),
        include: (path) =>
            !path.startsWith('lib/app/design/') &&
            path != 'lib/app/app_theme.dart',
      ),
      // 仅剩训练 hero 上那两处**刻意保留的例外**：模板主色实心/文字按钮压在
      // 品牌渐变 hero 上会消失，所以继续显式反转取色（与 hero 上的 `_AlbumBadge`
      // 同类）。同文件其余 `styleFrom` 已随波 2 收敛，见该文件的就地注释。
      budget: const {
        'lib/features/training/presentation/sections/training_hero.dart': 2,
      },
    );
  });

  test('裸按钮构造只减不增（波 3 收尾后 features 内一律走 lf_buttons）', () {
    // 波 4 补的规则：前两条只冻结「卡片」与「按钮内联样式」，抓不到**新写
    // 一个裸 `FilledButton`/`IconButton`** 这种回归——它既不是 `Card(` 也不带
    // `styleFrom`，却会把 M3 基线观感重新漏回界面。这里按构造名计次，
    // 白名单只剩两处就地注释过的例外（原因写在各自文件里）。
    //
    // 【为什么用负向后行断言】`LfCircleIconButton(`/`LfTextButton(` 的类名里也
    // 含 `IconButton`/`TextButton`，`(?<![A-Za-z0-9_.])` 保证只有在前面不是
    // 词字符时才算裸件（与 `Card(` 的计数口径一致）。
    expectNoGrowth(
      rule: '裸按钮统一化',
      actual: counts(
        RegExp(
          r'(?<![A-Za-z0-9_.])'
          r'(FilledButton|OutlinedButton|ElevatedButton|TextButton|IconButton)'
          r'(\.icon|\.filled|\.tonal)?\(',
        ),
        include: (path) =>
            !path.startsWith('lib/app/design/') &&
            path != 'lib/app/app_theme.dart',
      ),
      budget: const {
        // 贴着输入框的 ± 数值步进控件（不是独立动作，换圆钮会与输入框高度打架）。
        'lib/features/food_scan/presentation/scan_candidate_editor.dart': 2,
        // 压在品牌实色 hero 上的反色档（§3.8 没有反色档）。
        'lib/features/training/presentation/sections/training_hero.dart': 2,
      },
    );
  });
}
