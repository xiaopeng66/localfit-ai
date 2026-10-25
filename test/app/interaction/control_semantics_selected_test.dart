@Tags(['interaction-gate'])
library;

import 'dart:io';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/app/design/widgets/app_morph_chip.dart';
import 'package:localfit_ai/app/design/widgets/goal_big_card.dart';
import 'package:localfit_ai/app/design/widgets/lf_buttons.dart';
import 'package:localfit_ai/app/design/widgets/lf_filter_chips.dart';
import 'package:localfit_ai/app/design/widgets/lf_segment_control.dart';
import 'package:localfit_ai/app/design/widgets/lf_segmented_toggle.dart';

/// L3 · 语义层门禁（`docs/58` §2.4）：选择状态必须对读屏可见。
///
/// 现状核对（审查时实测）：`LfFilterChip` / `AppMorphChip` /
/// `LfSegmentedToggle` / `_SlotPill` 四处都真发 `Semantics(selected:)`，
/// **只有 `LfPillButton` 没发**（类注释写了、实现里没有）⇒ `RV4-P1-09`。
///
/// B1 落地时这条门禁还抓到**第二个同类缺口**：`GoalBigCard`（引导页/编辑资料
/// 的训练目标大卡）也是「单选卡」，同样不发 `selected` —— 审查报告只点了
/// `LfPillButton`，这条是执行期新发现，按 §1.6「新发现 P1 就地修」进 B2。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget host(Widget child, {bool dark = false}) => MaterialApp(
    theme: dark ? AppTheme.dark() : AppTheme.light(),
    home: Scaffold(body: Center(child: child)),
  );

  bool? selectedFlagOrNull(WidgetTester tester, Finder widgetFinder) {
    final value = tester
        .getSemantics(widgetFinder)
        .getSemanticsData()
        .flagsCollection
        .isSelected;
    return switch (value) {
      Tristate.isTrue => true,
      Tristate.isFalse => false,
      Tristate.none => null,
    };
  }

  group('L3 · 选择语义控件必须发 Semantics(selected)', () {
    for (final dark in [false, true]) {
      final mode = dark ? '暗色' : '亮色';

      testWidgets('LfPillButton（$mode）：selected 真假两态都可读', (tester) async {
        final handle = tester.ensureSemantics();
        for (final selected in [false, true]) {
          await tester.pumpWidget(
            host(
              LfPillButton(
                key: const Key('l3-pill'),
                label: selected ? '已选中' : '未选中',
                selected: selected,
                onPressed: () {},
              ),
              dark: dark,
            ),
          );
          await tester.pumpAndSettle();
          expect(
            selectedFlagOrNull(
              tester,
              find.ancestor(
                of: find.byKey(const Key('l3-pill')),
                matching: find.byType(LfPillButton),
              ),
            ),
            selected,
            reason:
                'LfPillButton 必须发 Semantics(selected: $selected)——'
                '读屏用户靠它听出哪枚被选中（RV4-P1-09）',
          );
        }
        handle.dispose();
      });

      testWidgets('LfFilterChip（$mode）：selected 真假两态都可读', (tester) async {
        final handle = tester.ensureSemantics();
        for (final selected in [false, true]) {
          await tester.pumpWidget(
            host(
              LfFilterChip(
                key: const Key('l3-chip'),
                label: '分类',
                selected: selected,
                onPressed: () {},
              ),
              dark: dark,
            ),
          );
          await tester.pumpAndSettle();
          expect(
            selectedFlagOrNull(
              tester,
              find.ancestor(
                of: find.byKey(const Key('l3-chip')),
                matching: find.byType(LfFilterChip),
              ),
            ),
            selected,
          );
        }
        handle.dispose();
      });

      testWidgets('AppMorphChip（$mode）：selected 真假两态都可读', (tester) async {
        final handle = tester.ensureSemantics();
        for (final selected in [false, true]) {
          await tester.pumpWidget(
            host(
              AppMorphChip(
                key: const Key('l3-morph'),
                label: '地点',
                selected: selected,
                onSelected: (_) {},
              ),
              dark: dark,
            ),
          );
          await tester.pumpAndSettle();
          expect(
            selectedFlagOrNull(tester, find.byKey(const Key('l3-morph'))),
            selected,
          );
        }
        handle.dispose();
      });

      testWidgets('LfSegmentedToggle（$mode）：每段各自可读', (tester) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(
          host(
            LfSegmentedToggle(
              segments: const ['周', '月'],
              selectedIndex: 1,
              onChanged: (_) {},
              segmentKeys: const [Key('l3-seg-0'), Key('l3-seg-1')],
            ),
            dark: dark,
          ),
        );
        await tester.pumpAndSettle();
        expect(
          selectedFlagOrNull(tester, find.byKey(const Key('l3-seg-0'))),
          isFalse,
        );
        expect(
          selectedFlagOrNull(tester, find.byKey(const Key('l3-seg-1'))),
          isTrue,
        );
        handle.dispose();
      });

      testWidgets('LfSegmentControl（$mode）：每段各自可读', (tester) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(
          host(
            LfSegmentControl<String>(
              segments: const [
                LfSegment(value: 'a', label: '记录'),
                LfSegment(value: 'b', label: '菜单'),
              ],
              selected: 'b',
              onChanged: (_) {},
              segmentKeys: const {'a': Key('l3-sc-0'), 'b': Key('l3-sc-1')},
            ),
            dark: dark,
          ),
        );
        await tester.pumpAndSettle();
        expect(
          selectedFlagOrNull(tester, find.byKey(const Key('l3-sc-0'))),
          isFalse,
        );
        expect(
          selectedFlagOrNull(tester, find.byKey(const Key('l3-sc-1'))),
          isTrue,
        );
        handle.dispose();
      });

      testWidgets('GoalBigCard（$mode）：单选大卡也可读', (tester) async {
        final handle = tester.ensureSemantics();
        for (final selected in [false, true]) {
          await tester.pumpWidget(
            host(
              GoalBigCard(
                key: const Key('l3-goal'),
                icon: Icons.flag,
                label: '减脂',
                selected: selected,
                onTap: () {},
                expand: false,
              ),
              dark: dark,
            ),
          );
          await tester.pumpAndSettle();
          expect(
            selectedFlagOrNull(tester, find.byKey(const Key('l3-goal'))),
            selected,
            reason: 'GoalBigCard 是单选卡，读屏必须听出选中态（执行期新发现 P1）',
          );
        }
        handle.dispose();
      });
    }
  });

  group('L3 · 一致性门禁：带 selected 参数的设计系统控件必须发出 selected', () {
    test('lib/app/design/widgets 下每个带 bool selected 的公开控件的类体内有 Semantics(selected:)', () {
      final repoRoot = Directory.current.path.replaceAll(r'\', '/');
      final offenders = <String>[];
      final checked = <String>[];

      /// 从 `class X ... {` 的左花括号起做花括号配平，取类体。
      String classBody(String text, int braceStart) {
        var depth = 0;
        for (var i = braceStart; i < text.length; i++) {
          final c = text[i];
          if (c == '{') depth++;
          if (c == '}') {
            depth--;
            if (depth == 0) return text.substring(braceStart, i + 1);
          }
        }
        return text.substring(braceStart);
      }

      for (final entity in Directory(
        '$repoRoot/lib/app/design/widgets',
      ).listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final text = entity.readAsStringSync();
        final file = entity.path.replaceAll(r'\', '/').split('/').last;
        final classPattern = RegExp(
          r'^(?:final\s+)?class\s+([A-Z]\w*)\s+extends\s+(?:StatelessWidget|StatefulWidget)[^{]*\{',
          multiLine: true,
        );
        for (final match in classPattern.allMatches(text)) {
          final name = match.group(1)!;
          final body = classBody(text, match.end - 1);
          // 类体内必须有 `final bool selected` 字段（排除 selectedIndex 族）。
          if (!RegExp(r'\bfinal\s+bool\s+selected\b').hasMatch(body)) continue;
          checked.add('$file:$name');
          final emits = RegExp(
            r'Semantics\([^;]{0,600}?\bselected\s*:',
            dotAll: true,
          ).hasMatch(body);
          if (!emits) offenders.add('$file:$name');
        }
      }

      expect(
        checked,
        isNotEmpty,
        reason: '扫描器没找到任何带 bool selected 的公开控件 = 扫描失效',
      );
      expect(
        offenders,
        isEmpty,
        reason:
            '这些控件有 selected 参数但类体内没发 Semantics(selected:)：'
            '${offenders.join('、')}。读屏听不出选中态。',
      );
    });
  });
}
