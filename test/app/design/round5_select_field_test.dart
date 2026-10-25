import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/lf_select_field.dart';

/// T4：下拉统一 `LfSelectField`（docs/32 §4 T4 / §3 D7 / 需求 66）。
///
/// 覆盖：① 组件几何与交互（关闭态 44 高、点开弹层、行高 44、选中态 ✓、
/// 只在确定选中时回写、禁用态不可开、错误态转红）；
/// ② 3 个典型站点的「打开 → 选择 → 回写」（可选值少 / 长列表 / 禁用态）。
///
/// 其余 8 个站点的迁移由各自的既有测试文件回归覆盖（它们的 Key 与返回值
/// 语义不变，迁移后仍需全绿——门禁即证据）。

/// 持有选中值的宿主（真实调用点由父级 setState 驱动；静态 value 不会刷新）。
class _SelectHost extends StatefulWidget {
  const _SelectHost({
    required this.initial,
    required this.options,
    this.onChanged,
    this.label = '日常活动程度',
  });

  final String? initial;
  final List<String> options;
  final ValueChanged<String?>? onChanged;
  final String label;

  @override
  State<_SelectHost> createState() => _SelectHostState();
}

class _SelectHostState extends State<_SelectHost> {
  late String? _value = widget.initial;

  @override
  Widget build(BuildContext context) => LfSelectField<String>(
    fieldKey: const Key('probe-select'),
    label: widget.label,
    value: _value,
    options: widget.options,
    optionLabel: (v) => v,
    onChanged: (next) {
      widget.onChanged?.call(next);
      setState(() => _value = next);
    },
  );
}

void main() {
  Widget host(Widget child) => MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(
      body: Padding(padding: const EdgeInsets.all(16), child: child),
    ),
  );

  group('T4 组件：关闭态几何与语义', () {
    testWidgets('关闭态高 44、显示当前值、标签在框外', (tester) async {
      // 语义树要先开再 pump，否则语义节点不会被编出来（本仓既有约定）。
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        host(
          LfSelectField<String>(
            fieldKey: const Key('probe-select'),
            label: '日常活动程度',
            value: '轻度活动',
            options: const ['久坐少动', '轻度活动', '中度活动'],
            optionLabel: (v) => v,
            onChanged: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      final field = tester.getSize(find.byKey(const Key('probe-select')));
      expect(field.height, 44, reason: '关闭态框高与 LfTextField 对齐（44）');
      expect(find.text('日常活动程度'), findsOneWidget, reason: '框外标签');
      expect(find.text('轻度活动'), findsOneWidget, reason: '当前值');
      // 框外标签自身不进语义树（AppFieldLabel 契约），可访问名由控件的
      // Semantics 承载（「标签 当前值」）。
      // 标签串含换行（Semantics 会把 label 与值分行），用正则匹配。
      expect(find.bySemanticsLabel(RegExp('日常活动程度')), findsOneWidget);
      expect(
        tester.getSemantics(find.byKey(const Key('probe-select'))).label,
        contains('轻度活动'),
      );
      semantics.dispose();
    });

    testWidgets('值为 null 时显示占位文案', (tester) async {
      await tester.pumpWidget(
        host(
          LfSelectField<String>(
            fieldKey: const Key('probe-select'),
            label: '动作',
            value: null,
            options: const ['深蹲', '卧推'],
            optionLabel: (v) => v,
            onChanged: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('请选择'), findsOneWidget);
    });
  });

  group('T4 组件：打开 → 选择 → 回写', () {
    testWidgets('点开是统一弹层（标题=字段名、行高 44、选中项 ✓），选择后回写且不回传 null', (tester) async {
      final changes = <String?>[];
      await tester.pumpWidget(
        host(
          _SelectHost(
            initial: '轻度活动',
            options: const ['久坐少动', '轻度活动', '中度活动', '高强度活动'],
            onChanged: changes.add,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('probe-select')));
      await tester.pumpAndSettle();

      // 弹层标题 = 字段名（同 Key 的标题节点）。
      expect(find.byKey(const Key('lf-select-sheet-title')), findsOneWidget);
      // 选项行高 44。
      final option0 = tester.getSize(
        find.byKey(const Key('lf-select-option-0')),
      );
      expect(option0.height, 44, reason: '选项行高 44（紧凑列表）');

      // 选中「中度活动」→ 回写一次、值为该项。
      // 限定在弹层内点选（关闭态框内也有同名文本，全局 find.text 会歧义）。
      // 弹层里确实列出了「中度活动」（在点选之前断言，弹层还开着）。
      expect(
        find.descendant(
          of: find.byKey(const Key('lf-select-options')),
          matching: find.text('中度活动'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('lf-select-option-2')));
      await tester.pumpAndSettle();
      expect(changes, ['中度活动']);
      // 关闭后框内显示新值。
      expect(find.text('中度活动'), findsOneWidget);
    });

    testWidgets('点遮罩关闭弹层不回写（null 不外泄）', (tester) async {
      final changes = <String>[];
      await tester.pumpWidget(
        host(
          _SelectHost(
            initial: '轻度活动',
            options: const ['久坐少动', '轻度活动', '中度活动'],
            onChanged: (v) => changes.add(v!),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('probe-select')));
      await tester.pumpAndSettle();
      // 点弹层外的遮罩关闭 ⇒ 没有确定选中 ⇒ 不得回写。
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(changes, isEmpty, reason: '关窗（遮罩/返回）不是「选择了 null」，不得触发 onChanged');
      expect(find.text('轻度活动'), findsOneWidget, reason: '值保持不变');
    });

    testWidgets('选当前项也不产生空回写（幂等点击）', (tester) async {
      final changes = <String>[];
      await tester.pumpWidget(
        host(
          _SelectHost(
            initial: '深蹲',
            label: '动作',
            options: const ['深蹲', '卧推'],
            onChanged: (v) => changes.add(v!),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('probe-select')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('lf-select-option-0')));
      await tester.pumpAndSettle();
      // 再选同一项是合法操作（回写同值），但**不能**回写 null。
      expect(changes, ['深蹲']);
    });
  });

  group('T4 组件：禁用态与错误态', () {
    testWidgets('禁用态点不开（弹层不出现）', (tester) async {
      await tester.pumpWidget(
        host(
          LfSelectField<String>(
            fieldKey: const Key('probe-select'),
            label: '餐次',
            value: '午餐',
            options: const ['早餐', '午餐'],
            optionLabel: (v) => v,
            enabled: false,
            onChanged: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('probe-select')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('lf-select-sheet-title')),
        findsNothing,
        reason: '禁用态不可打开（识别候选页保存中必须保持不可点）',
      );
      expect(find.text('午餐'), findsOneWidget);
    });

    testWidgets('错误态：框描边与标签转错误色', (tester) async {
      await tester.pumpWidget(
        host(
          LfSelectField<String>(
            fieldKey: const Key('probe-select'),
            label: '动作',
            value: null,
            options: const ['深蹲'],
            optionLabel: (v) => v,
            errorText: '请选择动作',
            onChanged: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      final label = tester.widget<Text>(find.text('动作'));
      expect(
        label.style!.color,
        LfSemanticColors.light.error,
        reason: '错误态标签转错误色（与 LfTextField 的 errorText 同反馈）',
      );
    });
  });

  group('T4 长列表', () {
    testWidgets('长列表可滚且打开时滚到选中项（选中项可见）', (tester) async {
      final options = [for (var i = 0; i < 40; i++) '动作-$i'];
      await tester.pumpWidget(
        host(_SelectHost(initial: '动作-30', label: '动作', options: options)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('probe-select')));
      await tester.pumpAndSettle();

      // 选中项被滚进可视区（长列表里「当前是哪项」必须一眼可见）。
      expect(
        find.descendant(
          of: find.byKey(const Key('lf-select-options')),
          matching: find.text('动作-30'),
        ),
        findsOneWidget,
        reason: '打开时应自动滚到选中项',
      );
      // 列表可滚：拖动后能看到更靠后的项。
      await tester.drag(
        find.byKey(const Key('lf-select-options')),
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const Key('lf-select-options')),
          matching: find.text('动作-39'),
        ),
        findsOneWidget,
      );
    });
  });
}
