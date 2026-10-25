import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/widgets/app_sheet.dart';
import 'package:localfit_ai/app/design/widgets/design_card.dart';
import 'package:localfit_ai/app/design/widgets/lf_bottom_nav.dart';
import 'package:localfit_ai/app/design/widgets/lf_buttons.dart';
import 'package:localfit_ai/app/design/widgets/lf_search_field.dart';
import 'package:localfit_ai/app/design/widgets/lf_segmented_toggle.dart';
import 'package:localfit_ai/app/design/widgets/lf_select_field.dart';
import 'package:localfit_ai/app/design/widgets/lf_text_field.dart';
import 'package:localfit_ai/app/design/widgets/lf_top_bar.dart';
import 'package:localfit_ai/app/design/widgets/skeleton_box.dart';

import 'support/round7_render.dart';

void main() {
  final capture = Platform.environment.containsKey('LF_ROUND7_CAPTURE_DIR');

  testWidgets('Round7 native shared surfaces render with local CJK fonts', (
    tester,
  ) async {
    await tester.runAsync(loadRound7Fonts);
    for (final dark in [false, true]) {
      for (final scale in [1.0, 1.5, 2.0]) {
        for (final width in [320.0, 360.0, 390.0, 430.0]) {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(width, 800);
          tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
          tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
          final name =
              'components-${dark ? 'dark' : 'light'}-${width.toInt()}-$scale';
          await tester.pumpWidget(
            RepaintBoundary(
              key: round7Boundary,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: round7CaptureTheme(
                  dark ? AppTheme.dark() : AppTheme.light(),
                ),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(scale),
                    disableAnimations: true,
                  ),
                  child: child!,
                ),
                home: const _Components(),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await captureRound7(tester, '$name-top');
          await tester.drag(
            find.byKey(const Key('samples')),
            const Offset(0, -580),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await captureRound7(tester, '$name-controls');
          await tester.scrollUntilVisible(
            find.byKey(const Key('sheet-open')),
            300,
            scrollable: find
                .descendant(
                  of: find.byKey(const Key('samples')),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          await tester.tap(find.byKey(const Key('sheet-open')));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await captureRound7(tester, '$name-sheet');
          await tester.tap(find.text('取消'));
          await tester.pumpAndSettle();
          await tester.pumpWidget(const SizedBox.shrink());
        }
      }
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.view.resetPadding();
    tester.view.resetViewPadding();
  }, skip: !capture);
}

class _Components extends StatefulWidget {
  const _Components();

  @override
  State<_Components> createState() => _ComponentsState();
}

class _ComponentsState extends State<_Components> {
  var selected = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: const LfTopBar(title: '组件与交互'),
    extendBody: true,
    bottomNavigationBar: LfBottomNav(
      currentIndex: selected,
      onTap: (value) => setState(() => selected = value),
    ),
    body: ListView(
      key: const Key('samples'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
      children: [
        DesignCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('真实记录，清晰呈现', style: LfText.headline),
              const SizedBox(height: 12),
              const Text('用于审看共享原生组件；此处不连接业务数据。'),
              const SizedBox(height: 12),
              LfSegmentedToggle(
                segments: const ['周', '月'],
                selectedIndex: selected % 2,
                onChanged: (value) => setState(() => selected = value),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const LfTextField(
          fieldKey: Key('name'),
          label: '记录名称',
          initialValue: '早餐记录',
        ),
        const SizedBox(height: 16),
        const LfTextField(
          fieldKey: Key('grams'),
          label: '份量',
          unit: 'g',
          initialValue: '-1',
          errorText: '请输入大于零的份量，修改后可以重新保存。',
        ),
        const SizedBox(height: 16),
        LfSelectField<String>(
          fieldKey: const Key('activity'),
          label: '活动水平',
          value: '中等活动：每周三至五次训练',
          options: const ['轻度活动', '中等活动：每周三至五次训练'],
          optionLabel: (value) => value,
          onChanged: (_) {},
        ),
        const SizedBox(height: 16),
        LfSearchField(
          fieldKey: const Key('search'),
          hintText: '搜索食物、品牌或分类',
          onChanged: (_) {},
        ),
        const SizedBox(height: 16),
        LfPrimaryButton(label: '保存当前修改', onPressed: () {}, expand: true),
        const SizedBox(height: 8),
        const LfPrimaryButton(label: '当前不可保存', expand: true),
        const SizedBox(height: 8),
        const LfConfirmButton(label: '保存本次记录', busy: true),
        const SizedBox(height: 8),
        LfConfirmButton(label: '跳过重复并导入本次选择的全部食物', onPressed: () {}),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            LfPillButton(label: '已选中', selected: true, onPressed: () {}),
            LfPillButton(label: '未选中', onPressed: () {}),
            LfTextButton(label: '查看全部', onPressed: () {}),
            LfDangerButton(label: '删除记录', onPressed: () {}),
            LfSmallButton(label: '保存配置', onPressed: () {}),
          ],
        ),
        const SizedBox(height: 16),
        const SkeletonBox(height: 44),
        const SizedBox(height: 16),
        LfPrimaryButton(
          key: const Key('sheet-open'),
          label: '打开确认表单',
          onPressed: () => AppSheet.showSubmitForm<void>(
            context,
            title: '确认导入',
            submitLabel: '跳过重复并导入本次选择的全部食物',
            body: (_, _) => const Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('确认后才写入。取消不会改变当前记录。'),
                SizedBox(height: 16),
                LfTextField(
                  fieldKey: Key('note'),
                  label: '备注',
                  optional: true,
                  initialValue: '保留当前选择',
                ),
              ],
            ),
            onSubmit: () async => '保存失败，请重试。',
          ),
        ),
      ],
    ),
  );
}
