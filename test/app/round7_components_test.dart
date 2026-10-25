import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/app_button_states.dart';
import 'package:localfit_ai/app/design/widgets/app_sheet.dart';
import 'package:localfit_ai/app/design/widgets/design_card.dart';
import 'package:localfit_ai/app/design/widgets/lf_bottom_nav.dart';
import 'package:localfit_ai/app/design/widgets/lf_buttons.dart';
import 'package:localfit_ai/app/design/widgets/lf_empty_state.dart';
import 'package:localfit_ai/app/design/widgets/lf_filter_chips.dart';
import 'package:localfit_ai/app/design/widgets/lf_segment_control.dart';
import 'package:localfit_ai/app/design/widgets/lf_segmented_toggle.dart';
import 'package:localfit_ai/app/design/widgets/lf_select_field.dart';
import 'package:localfit_ai/app/design/widgets/lf_text_field.dart';
import 'package:localfit_ai/app/design/widgets/lf_top_bar.dart';

void main() {
  Widget host(Widget child, {bool dark = false, double scale = 1}) =>
      MaterialApp(
        theme: dark ? AppTheme.dark() : AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: Padding(padding: const EdgeInsets.all(16), child: child),
        ),
      );

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets(
    'Round7 form surfaces separate input, card and sheet corner roles',
    (tester) async {
      await tester.pumpWidget(
        host(
          Column(
            children: [
              const DesignCard(child: Text('内容')),
              const LfTextField(fieldKey: Key('field'), label: '名称'),
              LfPrimaryButton(
                key: const Key('save'),
                label: '保存',
                onPressed: () {},
              ),
            ],
          ),
        ),
      );
      final input = tester.widget<InputDecorator>(find.byType(InputDecorator));
      expect(
        (input.decoration.enabledBorder! as OutlineInputBorder).borderRadius,
        BorderRadius.circular(12),
      );
      final button = tester.widget<FilledButton>(find.byKey(const Key('save')));
      expect(
        (button.style!.shape!.resolve(
          {},
        ) as RoundedRectangleBorder).borderRadius,
        BorderRadius.circular(12),
      );
      final card = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(DesignCard),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(card.borderRadius, BorderRadius.circular(16));
      final shape =
          Theme.of(tester.element(find.byKey(const Key('save'))))
                  .bottomSheetTheme
                  .shape!
              as RoundedRectangleBorder;
      expect(
        shape.borderRadius,
        const BorderRadius.vertical(top: Radius.circular(24)),
      );
    },
  );

  testWidgets(
    'Round7 enabled primary action is legible and visibly different from disabled',
    (tester) async {
      for (final dark in [false, true]) {
        await tester.pumpWidget(
          host(
            Column(
              children: [
                LfPrimaryButton(
                  key: const Key('enabled'),
                  label: '确认保存',
                  onPressed: () {},
                ),
                const LfPrimaryButton(key: Key('disabled'), label: '暂不可保存'),
              ],
            ),
            dark: dark,
          ),
        );
        await tester.pumpAndSettle();
        final context = tester.element(find.byKey(const Key('enabled')));
        final fill = lfSolidButtonFill(context);
        final label = tester.widget<Text>(find.text('确认保存')).style!.color!;
        final a = fill.computeLuminance();
        final b = label.computeLuminance();
        expect(
          (a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05)),
          greaterThanOrEqualTo(4.5),
        );
        expect(label, const Color(0xFF10271D));
        final disabled = Theme.of(context)
            .filledButtonTheme
            .style!
            .backgroundColor!
            .resolve({WidgetState.disabled});
        expect(disabled, isNot(fill));
        expect(
          context.lf.mutedForeground,
          dark ? const Color(0xFF8FA09A) : const Color(0xFF5C7067),
        );
      }
    },
  );

  testWidgets(
    'busy submit keeps its accessible purpose and rejects repeated taps',
    (tester) async {
      var calls = 0;
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          host(
            LfConfirmButton(
              key: const Key('busy'),
              label: '保存本次记录',
              busy: true,
              onPressed: () => calls++,
            ),
          ),
        );
        expect(
          tester.getSemantics(find.byKey(const Key('busy'))).label,
          contains('保存本次记录'),
        );
        await tester.tap(find.byKey(const Key('busy')), warnIfMissed: false);
        await tester.tap(find.byKey(const Key('busy')), warnIfMissed: false);
        expect(calls, 0);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'long confirmation at 320dp and 200 percent wraps without hiding action',
    (tester) async {
      phone(tester);
      const label = '跳过重复并导入本次选择的全部食物';
      var calls = 0;
      await tester.pumpWidget(
        host(
          LfConfirmButton(
            key: const Key('confirm'),
            label: label,
            onPressed: () => calls++,
          ),
          scale: 2,
        ),
      );
      final paragraph = tester.renderObject<RenderParagraph>(find.text(label));
      expect(paragraph.didExceedMaxLines, isFalse);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('confirm')));
      expect(calls, 1);
    },
  );

  testWidgets(
    'large-font selector exposes full current value and full option then returns selection',
    (tester) async {
      phone(tester);
      String? picked;
      const value = '中等活动：每周进行三至五次中等强度训练';
      await tester.pumpWidget(
        host(
          LfSelectField<String>(
            fieldKey: const Key('activity'),
            label: '活动水平',
            value: value,
            options: const [value, '轻度活动'],
            optionLabel: (option) => option,
            onChanged: (option) => picked = option,
          ),
          scale: 2,
        ),
      );
      expect(
        tester
            .renderObject<RenderParagraph>(find.text(value))
            .didExceedMaxLines,
        isFalse,
      );
      await tester.tap(find.byKey(const Key('activity')));
      await tester.pumpAndSettle();
      for (final paragraph in tester.renderObjectList<RenderParagraph>(
        find.text(value),
      )) {
        expect(paragraph.didExceedMaxLines, isFalse);
      }
      await tester.tap(find.text('轻度活动'));
      await tester.pumpAndSettle();
      expect(picked, '轻度活动');
      expect(find.byKey(const Key('activity')), findsOneWidget);
    },
  );

  testWidgets('switching reduced motion on stops the visible busy indicator', (
    tester,
  ) async {
    final reduced = ValueNotifier(false);
    addTearDown(reduced.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<bool>(
          valueListenable: reduced,
          builder: (context, value, _) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: value),
            child: const Scaffold(body: AppButtonDotsLoader(key: Key('dots'))),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 150));
    reduced.value = true;
    await tester.pump();
    List<Offset> positions() => [
      for (final element
          in find
              .descendant(
                of: find.byKey(const Key('dots')),
                matching: find.byType(Container),
              )
              .evaluate())
        (element.renderObject! as RenderBox).localToGlobal(Offset.zero),
    ];
    final stopped = positions();
    await tester.pump(const Duration(milliseconds: 200));
    expect(positions(), stopped);
    expect(tester.binding.hasScheduledFrame, isFalse);
    reduced.value = false;
    await tester.pump();
    final resumed = positions();
    await tester.pump(const Duration(milliseconds: 150));
    expect(positions(), isNot(resumed));
  });

  testWidgets('long option list opens with the selected wrapped row visible', (
    tester,
  ) async {
    phone(tester);
    final options = [for (var i = 0; i < 40; i++) '第$i项：每周进行三至五次中等强度训练并保持日常活动'];
    String? picked;
    await tester.pumpWidget(
      host(
        LfSelectField<String>(
          fieldKey: const Key('long-list'),
          label: '活动水平',
          value: options[30],
          options: options,
          optionLabel: (option) => option,
          onChanged: (option) => picked = option,
        ),
        scale: 2,
      ),
    );
    await tester.tap(find.byKey(const Key('long-list')));
    await tester.pumpAndSettle();
    final selected = find.byKey(const Key('lf-select-option-30'));
    expect(selected.hitTestable(), findsOneWidget);
    final viewport = tester.getRect(find.byKey(const Key('lf-select-options')));
    final row = tester.getRect(selected);
    expect(row.top, greaterThanOrEqualTo(viewport.top));
    expect(row.bottom, lessThanOrEqualTo(viewport.bottom));
    await tester.tap(selected);
    await tester.pumpAndSettle();
    expect(picked, options[30]);
  });

  testWidgets(
    'long submit remains fully reachable above keyboard at 320dp and 200 percent',
    (tester) async {
      phone(tester);
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      addTearDown(tester.view.resetViewInsets);
      var writes = 0;
      const label = '跳过重复并导入本次选择的全部食物';
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) => LfPrimaryButton(
              label: '打开',
              onPressed: () => AppSheet.showSubmitForm<void>(
                context,
                title: '确认导入',
                submitLabel: label,
                submitKey: const Key('import'),
                body: (_, _) =>
                    const LfTextField(fieldKey: Key('note'), label: '备注'),
                onSubmit: () async {
                  writes++;
                  return null;
                },
              ),
            ),
          ),
          scale: 2,
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final button = tester.getRect(find.byKey(const Key('import')));
      expect(button.left, greaterThanOrEqualTo(0));
      expect(button.right, lessThanOrEqualTo(320));
      expect(button.bottom, lessThanOrEqualTo(380));
      expect(
        tester
            .renderObject<RenderParagraph>(find.text(label))
            .didExceedMaxLines,
        isFalse,
      );
      await tester.tap(find.byKey(const Key('import')));
      await tester.pumpAndSettle();
      expect(writes, 1);
    },
  );

  testWidgets('sheet actions stay outside the bottom system gesture area', (
    tester,
  ) async {
    phone(tester);
    tester.view.padding = const FakeViewPadding(bottom: 24);
    tester.view.viewPadding = const FakeViewPadding(bottom: 24);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => LfPrimaryButton(
            label: '打开',
            onPressed: () => AppSheet.showSubmitForm<void>(
              context,
              title: '保存记录',
              submitKey: const Key('safe-save'),
              body: (_, _) => const Text('确认保存当前修改'),
              onSubmit: () async => null,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.byKey(const Key('safe-save'))).bottom,
      lessThanOrEqualTo(616),
    );
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('打开'), findsOneWidget);
  });

  testWidgets(
    'disabled primary labels stay legible on the dark disabled surface',
    (tester) async {
      await tester.pumpWidget(
        host(
          const Column(
            children: [
              LfPrimaryButton(label: '暂不可保存'),
              LfConfirmButton(label: '暂不可确认'),
              LfSmallButton(label: '暂不可生成'),
            ],
          ),
          dark: true,
        ),
      );
      for (final label in ['暂不可保存', '暂不可确认', '暂不可生成']) {
        final paragraph = tester.renderObject<RenderParagraph>(
          find.text(label),
        );
        final color = paragraph.text.style!.color!;
        final background = Theme.of(tester.element(find.text(label)))
            .filledButtonTheme
            .style!
            .backgroundColor!
            .resolve({WidgetState.disabled})!;
        final a = color.computeLuminance();
        final b = background.computeLuminance();
        expect(
          (a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05)),
          greaterThanOrEqualTo(4.5),
          reason: label,
        );
      }
    },
  );

  testWidgets('AI navigation label does not overlap its icon at 200 percent', (
    tester,
  ) async {
    phone(tester);
    var selected = -1;
    await tester.pumpWidget(
      host(
        LfBottomNav(currentIndex: 0, onTap: (value) => selected = value),
        scale: 2,
      ),
    );
    final circle = tester.getRect(find.byKey(const Key('nav-ai-workbench')));
    final label = tester.getRect(find.text('AI'));
    expect(label.top, greaterThanOrEqualTo(circle.bottom));
    await tester.tapAt(Offset(circle.center.dx, circle.top + 2));
    expect(selected, 2);
  });

  testWidgets(
    'card icon responds throughout its 44dp hit box and exposes a tap action',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        var taps = 0;
        await tester.pumpWidget(
          host(
            Center(
              child: LfIconButton(
                key: const Key('add-icon'),
                icon: Icons.add,
                semanticLabel: '添加记录',
                onPressed: () => taps++,
              ),
            ),
          ),
        );
        final rect = tester.getRect(find.byKey(const Key('add-icon')));
        expect(rect.width, greaterThanOrEqualTo(44));
        expect(rect.height, greaterThanOrEqualTo(44));
        await tester.tapAt(rect.topLeft + const Offset(2, 2));
        expect(taps, 1);
        await tester.tap(find.byKey(const Key('add-icon')));
        expect(taps, 2);
        expect(
          tester
              .getSemantics(find.bySemanticsLabel('添加记录'))
              .getSemanticsData()
              .hasAction(SemanticsAction.tap),
          isTrue,
        );
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'ordinary and compact actions use A 44dp surfaces without clipping labels',
    (tester) async {
      await tester.pumpWidget(
        host(
          Column(
            children: [
              LfPrimaryButton(
                key: const Key('ordinary'),
                label: '保存',
                onPressed: () {},
              ),
              LfSmallButton(
                key: const Key('compact'),
                label: '保存配置',
                onPressed: () {},
              ),
            ],
          ),
        ),
      );
      for (final key in ['ordinary', 'compact']) {
        final button = tester.widget<FilledButton>(find.byKey(Key(key)));
        expect(button.style!.minimumSize!.resolve({})!.height, 44);
        expect(
          tester.getSize(find.byKey(Key(key))).height,
          greaterThanOrEqualTo(44),
        );
      }
    },
  );

  testWidgets(
    'button labels inherit the active theme font instead of a separate fallback',
    (tester) async {
      // 2026-10-14（阶段 3 步骤 2b 渲染审看）：筛选胶囊是**漏网的一件**——它的
      // 文字走 `TextButton.styleFrom(textStyle: LfText.caption…)`，而 caption 不带
      // 字体族；`ButtonStyleButton` 用这份样式**替换**环境 `DefaultTextStyle`
      // （不是合并），于是族变成 null。真机上 null 会落到平台默认族、CJK 有系统
      // 兜底看不出来；测试引擎没有兜底，帧里会渲染成 .notdef 空方框（本仓
      // `lf_buttons.dart` 六个按钮家族在阶段 1 已按「并入主题字体」修过，胶囊漏了）。
      // 这条断言钉的是同一个口径：标签字体随主题，而不是自成一路。
      final theme = AppTheme.light();
      await tester.pumpWidget(
        MaterialApp(
          theme: theme.copyWith(
            textTheme: theme.textTheme.apply(fontFamily: 'PlatformCjk'),
          ),
          home: Scaffold(
            body: Column(
              children: [
                LfPrimaryButton(label: '保存', onPressed: () {}),
                LfConfirmButton(label: '确认', onPressed: () {}),
                LfPillButton(label: '筛选', onPressed: () {}),
                LfTextButton(label: '取消', onPressed: () {}),
                LfSmallButton(label: '配置', onPressed: () {}),
                LfFilterChip(label: '全部', selected: true, onPressed: () {}),
                // B11（Round7 阶段 3 · 3-2c）：页尾链带副行，两行都要随主题字体
                // ——副行若是自建 `TextStyle` 而不并入主题，2.0× 帧里是空方框。
                LfLinkButton(
                  label: '食物管理',
                  subtitle: '从文件读取到食物库',
                  onPressed: () {},
                ),
              ],
            ),
          ),
        ),
      );
      for (final label in [
        '保存',
        '确认',
        '筛选',
        '取消',
        '配置',
        '全部',
        '食物管理',
        '从文件读取到食物库',
      ]) {
        expect(
          tester
              .renderObject<RenderParagraph>(find.text(label))
              .text
              .style!
              .fontFamily,
          'PlatformCjk',
          reason: label,
        );
      }
    },
  );

  testWidgets(
    'AI header retains its full title between both actions at 200 percent',
    (tester) async {
      phone(tester);
      var backs = 0;
      var profiles = 0;
      await tester.pumpWidget(
        host(
          Column(
            children: [
              LfTopBar(
                title: 'LocalFit AI',
                respectTopInset: false,
                titleLeading: const SizedBox(width: 32, height: 32),
                onBack: () => backs++,
                actions: [
                  LfCircleIconButton(
                    key: const Key('profile'),
                    icon: Icons.person,
                    tooltip: '我的',
                    onPressed: () => profiles++,
                  ),
                ],
              ),
              const Expanded(child: Text('会话内容')),
            ],
          ),
          scale: 2,
        ),
      );
      final paragraph = tester.renderObject<RenderParagraph>(
        find.text('LocalFit AI'),
      );
      expect(paragraph.didExceedMaxLines, isFalse);
      final title = tester.getRect(find.text('LocalFit AI'));
      final header = tester.getRect(find.byType(LfTopBar));
      expect(title.top, greaterThanOrEqualTo(header.top));
      expect(title.bottom, lessThanOrEqualTo(header.bottom));
      await tester.tap(find.byKey(const Key('profile')));
      await tester.tap(find.byKey(const Key('top-bar-back')));
      expect(profiles, 1);
      expect(backs, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'mini range toggle retains A track and unclipped selected text at large size',
    (tester) async {
      phone(tester);
      var selected = 0;
      for (final scale in [1.0, 2.0]) {
        await tester.pumpWidget(
          host(
            StatefulBuilder(
              builder: (context, setState) => LfSegmentedToggle(
                segments: const ['周', '月'],
                selectedIndex: selected,
                segmentKeys: const [Key('week'), Key('month')],
                onChanged: (value) => setState(() => selected = value),
              ),
            ),
            dark: true,
            scale: scale,
          ),
        );
        await tester.pumpAndSettle();
        final track = tester.getRect(
          find.byKey(const Key('lf-segmented-track')),
        );
        final thumb = tester.getRect(
          find.byKey(const Key('lf-segmented-thumb')),
        );
        if (scale == 1) expect(track.height, 36);
        final label = tester.getRect(find.text(selected == 0 ? '周' : '月'));
        expect(label.top, greaterThanOrEqualTo(thumb.top));
        expect(label.bottom, lessThanOrEqualTo(thumb.bottom));
        final thumbDecoration =
            tester
                    .widget<DecoratedBox>(
                      find
                          .descendant(
                            of: find.byKey(const Key('lf-segmented-thumb')),
                            matching: find.byType(DecoratedBox),
                          )
                          .first,
                    )
                    .decoration
                as BoxDecoration;
        expect(thumbDecoration.color, const Color(0xFF171E1A));
        final target = find.byKey(Key(selected == 0 ? 'month' : 'week'));
        final rect = tester.getRect(target);
        expect(rect.width, greaterThanOrEqualTo(44));
        expect(rect.height, greaterThanOrEqualTo(44));
        final before = selected;
        await tester.tapAt(rect.topLeft + const Offset(2, 2));
        await tester.pumpAndSettle();
        expect(selected, 1 - before);
      }
    },
  );

  testWidgets(
    'form segments provide readable full choices and real 44dp targets',
    (tester) async {
      phone(tester);
      var selected = 0;
      const labels = ['保持当前体重', '逐步减少体重'];
      await tester.pumpWidget(
        host(
          StatefulBuilder(
            builder: (context, setState) => LfSegmentControl<int>(
              segments: const [
                LfSegment(value: 0, label: '保持当前体重'),
                LfSegment(value: 1, label: '逐步减少体重'),
              ],
              selected: selected,
              segmentKeys: const {0: Key('maintain'), 1: Key('reduce')},
              onChanged: (value) => setState(() => selected = value),
            ),
          ),
          scale: 2,
        ),
      );
      final paragraph = tester.renderObject<RenderParagraph>(
        find.text(labels[0]),
      );
      expect(paragraph.didExceedMaxLines, isFalse);
      final color = paragraph.text.style!.color!;
      expect(
        (Colors.white.computeLuminance() + .05) /
            (color.computeLuminance() + .05),
        greaterThanOrEqualTo(4.5),
      );
      final target = tester.getRect(find.byKey(const Key('reduce')));
      expect(target.height, greaterThanOrEqualTo(44));
      await tester.tapAt(target.topLeft + const Offset(2, 2));
      await tester.pumpAndSettle();
      expect(selected, 1);
      expect(
        tester
            .renderObject<RenderParagraph>(find.text(labels[1]))
            .didExceedMaxLines,
        isFalse,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'emphasized actions use the same accessible solid enabled and disabled surface',
    (tester) async {
      for (final dark in [false, true]) {
        await tester.pumpWidget(
          host(
            Column(
              children: [
                LfPrimaryButton.emphasized(
                  key: const Key('generate'),
                  label: '生成计划',
                  onPressed: () {},
                ),
                const LfPrimaryButton.emphasized(
                  key: Key('unavailable'),
                  label: '暂不可生成',
                ),
              ],
            ),
            dark: dark,
          ),
        );
        await tester.pumpAndSettle();
        final decorations = tester
            .widgetList<DecoratedBox>(
              find.ancestor(
                of: find.byKey(const Key('generate')),
                matching: find.byType(DecoratedBox),
              ),
            )
            .map((widget) => widget.decoration)
            .whereType<BoxDecoration>();
        expect(
          decorations.where((decoration) => decoration.gradient != null),
          isEmpty,
        );
        expect(
          decorations.expand(
            (decoration) => decoration.boxShadow ?? <BoxShadow>[],
          ),
          isEmpty,
        );
        Color fill(String key) => tester
            .widget<Material>(
              find
                  .descendant(
                    of: find.byKey(Key(key)),
                    matching: find.byType(Material),
                  )
                  .first,
            )
            .color!;
        expect(
          fill('generate'),
          dark ? const Color(0xFF4ED9A6) : const Color(0xFF2FBE8F),
        );
        expect(
          fill('unavailable'),
          dark ? const Color(0xFF1F2823) : const Color(0xFFEFF3F1),
        );
      }
    },
  );

  testWidgets(
    'standard cards use a quiet A shadow and dark outline without changing their actions',
    (tester) async {
      for (final dark in [false, true]) {
        var taps = 0;
        await tester.pumpWidget(
          host(
            DesignCard(
              key: const Key('card'),
              onTap: () => taps++,
              child: const Text('打开记录'),
            ),
            dark: dark,
          ),
        );
        await tester.pumpAndSettle();
        final decoration =
            tester
                    .widget<DecoratedBox>(
                      find
                          .descendant(
                            of: find.byKey(const Key('card')),
                            matching: find.byType(DecoratedBox),
                          )
                          .first,
                    )
                    .decoration
                as BoxDecoration;
        expect(
          decoration.boxShadow,
          dark
              ? const <BoxShadow>[]
              : const [
                  BoxShadow(
                    color: Color(0x051A201D),
                    offset: Offset(0, 1),
                    blurRadius: 3,
                  ),
                ],
        );
        expect(
          (decoration.border! as Border).top.color,
          dark ? const Color(0xFF2A342F) : Colors.transparent,
        );
        await tester.tap(find.byKey(const Key('card')));
        expect(taps, 1);
      }
    },
  );

  testWidgets(
    'canceling submit returns to the launching view and does not write',
    (tester) async {
      var writes = 0;
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) => LfPrimaryButton(
              label: '编辑',
              onPressed: () => AppSheet.showSubmitForm<void>(
                context,
                title: '编辑记录',
                body: (_, _) => const LfTextField(
                  fieldKey: Key('draft'),
                  label: '备注',
                  initialValue: '未保存草稿',
                ),
                onSubmit: () async {
                  writes++;
                  return null;
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('编辑'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(writes, 0);
      expect(find.text('编辑'), findsOneWidget);
      expect(find.byKey(const Key('draft')), findsNothing);
    },
  );

  testWidgets('裸 AppBar 的标题也随主题字体（缺陷 ㉒：与 ⑫/⑮ 同族）', (tester) async {
    // Round7 阶段 5 渲染审看抓到：`AiStarterGallery` 的 `AppBar(title: Text('AI 创作'))`
    // 在测试帧里渲染成空方框——主题的 `appBarTheme.titleTextStyle` 是
    // `LfText.headline`（自建样式、**不带字体族**），而 `AppBar` 用这份样式
    // **替换**而不是合并环境 `DefaultTextStyle`（与 ⑫ 的 `ButtonStyleButton`、
    // ⑮ 的 `ListTile` 同族同因）。真机靠系统兜底看不出来，测试引擎没有兜底。
    // 全仓 10 处裸 `AppBar`（app_router / 引导 / 计划 / 画廊…）都吃这一条。
    final theme = AppTheme.light();
    await tester.pumpWidget(
      MaterialApp(
        theme: theme.copyWith(
          textTheme: theme.textTheme.apply(fontFamily: 'PlatformCjk'),
        ),
        home: Scaffold(appBar: AppBar(title: const Text('AI 创作'))),
      ),
    );

    final title = tester.widget<Text>(find.text('AI 创作'));
    final resolved = DefaultTextStyle.of(tester.element(find.text('AI 创作')));
    // 主题没给族时，标题的族必须由**主题正文**合并而来（非空）。
    expect(
      title.style?.fontFamily ?? resolved.style.fontFamily,
      'PlatformCjk',
      reason: '裸 AppBar 标题的字体族必须随主题，而不是自成一路（空方框）',
    );
  });

  testWidgets('LfEmptyState 规格（A `.empty-state`）：52 R18 图标块 + 14 w600 标题', (
    tester,
  ) async {
    // Round7 阶段 3 · 3-2 收口：标题字重是登记的偏差项——A `.empty-state strong`
    // 是 14px **w600**，实现此前用 `LfText.body`（14 w400）。这条把 A 的字重钉住；
    // 图标块尺寸此前只有散点覆盖（帧与各页断言），这里一并读出来当单点规格。
    await tester.pumpWidget(
      host(
        const LfEmptyState(
          icon: Icons.search,
          title: '食物库还是空的',
          message: '新安装时为空库，可导入自己的食物数据。',
        ),
      ),
    );

    final chip = tester.getRect(
      find.ancestor(
        of: find.byIcon(Icons.search),
        matching: find.byType(Container),
      ),
    );
    expect(chip.width, LfEmptyState.iconChipSize);
    expect(chip.height, LfEmptyState.iconChipSize);

    final title = tester.widget<Text>(find.text('食物库还是空的'));
    expect(title.style?.fontSize, 14, reason: 'A `.empty-state strong` 14px');
    expect(
      title.style?.fontWeight,
      FontWeight.w600,
      reason: 'A 的 strong 是 w600（登记项：此前实现是 w400）',
    );
    final message = tester.widget<Text>(find.text('新安装时为空库，可导入自己的食物数据。'));
    expect(message.style?.fontSize, 12);
  });
}
