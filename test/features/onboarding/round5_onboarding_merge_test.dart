import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_router.dart';
import 'package:localfit_ai/app/localfit_app.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/lf_segment_control.dart';
import 'package:localfit_ai/app/design/widgets/lf_toggle_switch.dart';
import 'package:localfit_ai/features/onboarding/domain/complete_onboarding.dart';
import 'package:localfit_ai/features/onboarding/domain/nutrition_target_calculator.dart';
import 'package:localfit_ai/features/onboarding/presentation/onboarding_page.dart';

/// docs/32 §4 T15（需求 74 / §3 D18）：引导页合并设计稿的验收测试。
///
/// 只看**新并入的布局与交互**（阶段条 / 微标签 / 卡片副文案 / 描述式活动档 /
/// 性别分段控件 / 行式安全筛查 / 固定底部 CTA）；校验与保存流程的回归由
/// 既有的 `onboarding_page_test.dart`、`round5_target_sheet_test.dart` 覆盖。
///
/// 每条断言都对应 D18 的一条借入项 —— 设计稿 `ui设计/pages/初始引导.html`
/// 是视觉依据，但**档位数、图标、token 与动效仍以本仓现状为准**。
void main() {
  const rowKeys = [
    'onboarding-pregnancy-risk',
    'onboarding-chronic-risk',
    'onboarding-eating-risk',
  ];

  testWidgets('阶段条：4 段 24×4 胶囊，初始第 1 段主色、其余描边色（D18 第 1 条）', (tester) async {
    await _pumpPage(tester);
    final c = _colors(tester);

    final pills = _pills();
    expect(pills, findsNWidgets(4), reason: '阶段条 4 段（视觉进度，不拆步）');
    for (var i = 0; i < 4; i++) {
      expect(
        tester.getSize(pills.at(i)),
        const Size(24, 4),
        reason: '第 ${i + 1} 段尺寸取设计稿 24×4',
      );
      final decoration =
          tester.widget<Container>(pills.at(i)).decoration! as BoxDecoration;
      expect(
        decoration.color,
        i == 0 ? c.primary : c.border,
        reason: '第 ${i + 1} 段取色（当前段主色 / 未达段描边色）',
      );
    }
    expect(
      tester
          .widget<Text>(find.byKey(const Key('onboarding-progress-label')))
          .data,
      'STEP 1 / 4 · 建立档案',
      reason: '微标签逐字取设计稿（D18 第 2 条）',
    );
  });

  testWidgets('阶段条随滚动推进：p<.25/.5/.75 三档切换，标签同步（D18 第 1–2 条）', (tester) async {
    // 手机视口：900×1400 时长表单**整页可见**、`maxScrollExtent == 0`，
    // 滚动映射无从谈起（这正是不足一屏时恒为第 1 段的那条退化规则）。
    await _pumpPage(tester, size: const Size(390, 844));
    final c = _colors(tester);
    final position = _position(tester);
    expect(
      position.maxScrollExtent,
      greaterThan(0),
      reason: '长表单必须可滚，否则滚动映射无从谈起',
    );

    Future<void> jumpToRatio(double ratio) async {
      position.jumpTo(position.maxScrollExtent * ratio);
      await tester.pump();
    }

    int activeCount() => List.generate(4, (i) {
      final decoration =
          tester.widget<Container>(_pills().at(i)).decoration! as BoxDecoration;
      return decoration.color == c.primary;
    }).where((active) => active).length;

    // 比值刻意避开 .25/.5/.75 三个边界（边界处的浮点相等不可依赖）。
    await jumpToRatio(0.3);
    expect(_label(tester), 'STEP 2 / 4 · 建立档案');
    expect(activeCount(), 2, reason: '已过的段累计填充（设计稿 STEP 3/4 亮 3 段）');

    await jumpToRatio(0.6);
    expect(_label(tester), 'STEP 3 / 4 · 建立档案');
    expect(activeCount(), 3);

    await jumpToRatio(1);
    expect(_label(tester), 'STEP 4 / 4 · 建立档案');
    expect(activeCount(), 4);

    await jumpToRatio(0);
    expect(_label(tester), 'STEP 1 / 4 · 建立档案');
    expect(activeCount(), 1);
  });

  testWidgets('底部 CTA：在滚动容器之外、h48、滚到底位置不变、首帧可点（D18 第 7 条）', (tester) async {
    await _pumpPage(tester, size: const Size(390, 844));
    final submit = find.byKey(const Key('onboarding-submit'));
    expect(submit, findsOneWidget);
    expect(
      find.descendant(of: find.byType(Scrollable), matching: submit),
      findsNothing,
      reason: 'CTA 不能留在 ListView 里：那样会随内容滚出视口',
    );
    expect(submit.hitTestable(), findsOneWidget, reason: '首帧就可见可点，用户不必先滚到底');
    final before = tester.getRect(submit);
    expect(before.height, 48, reason: '§8.3 定案：高度取现有 token h48，不采设计稿 52dp');

    final position = _position(tester);
    position.jumpTo(position.maxScrollExtent);
    await tester.pump();
    expect(tester.getRect(submit), before, reason: '滚到底后 CTA 矩形逐值不变');
    expect(submit.hitTestable(), findsOneWidget);
  });

  testWidgets('活动档：仍 4 档，标签改描述式（D18 第 4 条：不新增枚举值）', (tester) async {
    await _pumpPage(tester);
    await _scrollTo(tester, find.byKey(const Key('onboarding-日常活动程度')));
    await tester.tap(find.byKey(const Key('onboarding-日常活动程度')));
    await tester.pumpAndSettle();

    for (final label in const [
      '久坐 — 几乎不运动',
      '中度 — 每周 3-4 次中等强度',
      '高强度 — 每周 5-6 次较高强度',
    ]) {
      expect(find.text(label), findsOneWidget, reason: '弹层里必须有「$label」');
    }
    // 默认档（轻度）在关态框里也显示同一串文案 ⇒ 弹层 + 框各一处。
    expect(
      find.text('轻度 — 每周 1-2 次低强度'),
      findsNWidgets(2),
      reason: '弹层行 + 关态框回显（默认档 = 轻度）',
    );
    for (final old in const ['久坐少动', '轻度活动', '中度活动', '高强度活动']) {
      expect(find.text(old), findsNothing, reason: '旧纯标签「$old」应已被替换');
    }
    expect(
      ActivityLevel.values.length,
      4,
      reason: '档位数以现有枚举为准（设计稿的 5 档不采纳，避免动领域模型）',
    );

    await tester.tap(find.text('中度 — 每周 3-4 次中等强度'));
    await tester.pumpAndSettle();
    expect(
      find.text('中度 — 每周 3-4 次中等强度'),
      findsOneWidget,
      reason: '关态框回显所选档的描述式文案',
    );
  });

  testWidgets('安全筛查：Key 不变、行式 46×28 开关、整行可点、行间 1px 分隔线（D18 第 6 条）', (
    tester,
  ) async {
    await _pumpPage(tester);
    await _scrollTo(tester, find.byKey(const Key('onboarding-eating-risk')));

    for (final key in rowKeys) {
      final row = find.byKey(Key(key));
      expect(row, findsOneWidget, reason: '$key 必须保留（docs/32 §4 T15 验收）');
      final toggle = find.descendant(
        of: row,
        matching: find.byType(LfToggleSwitch),
      );
      expect(toggle, findsOneWidget, reason: '$key 行右侧是自绘开关');
      expect(
        tester.getSize(toggle),
        const Size(46, 28),
        reason: '开关尺寸取设计稿 46×28',
      );
    }
    expect(
      find.byType(SwitchListTile),
      findsNothing,
      reason: 'M3 开关行已整体替换为行式布局',
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('onboarding-safety-card')),
        matching: find.byType(Divider),
      ),
      findsNWidgets(2),
      reason: '3 行之间 2 条 1px 分隔线（末行不画）',
    );

    const question = '存在需饮食或运动管理的慢性疾病';
    LfToggleSwitch toggleOf(String key) => tester.widget<LfToggleSwitch>(
      find.descendant(
        of: find.byKey(Key(key)),
        matching: find.byType(LfToggleSwitch),
      ),
    );

    // 整行可点：点在**问题文本**上（离开关很远），也必须切换。
    await tester.tap(find.text(question));
    await tester.pump();
    expect(
      toggleOf('onboarding-chronic-risk').value,
      isTrue,
      reason: '整行（≥44dp）可点，不必精确点到 46×28 的开关',
    );
    await tester.tap(find.text(question));
    await tester.pump();
    expect(
      toggleOf('onboarding-chronic-risk').value,
      isFalse,
      reason: '单次点按只切换一次（行与开关不叠加两次）',
    );
  });

  testWidgets('性别：M3 SegmentedButton 退场，自绘 52dp 分段控件可切换（D18 第 5 条 / A）', (
    tester,
  ) async {
    await _pumpPage(tester);
    expect(
      find.byType(SegmentedButton<BiologicalSex>),
      findsNothing,
      reason: 'M3 分段按钮已替换',
    );
    final control = find.byType(LfSegmentControl<BiologicalSex>);
    expect(control, findsOneWidget);
    expect(
      tester.getSize(control).height,
      52,
      reason: '轨道高 = A `.tabs` 的 4 + 44 + 4（写死字面量，不用被断言对象自己的常量）',
    );
    expect(
      tester.widget<LfSegmentControl<BiologicalSex>>(control).selected,
      BiologicalSex.female,
      reason: '默认档位不变（与改造前一致）',
    );

    await tester.tap(find.byKey(const Key('onboarding-sex-male')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<LfSegmentControl<BiologicalSex>>(control).selected,
      BiologicalSex.male,
    );

    // 两个方向都可切（只点得动一段的自绘控件是画出来的，不是控件）。
    await tester.tap(find.byKey(const Key('onboarding-sex-female')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<LfSegmentControl<BiologicalSex>>(control).selected,
      BiologicalSex.female,
    );
  });

  testWidgets('分组卡副文案落地（D18 第 3 条）', (tester) async {
    await _pumpPage(tester);
    expect(find.text('用于计算基础代谢率与营养分配'), findsOneWidget);
    await _scrollTo(tester, find.text('选择主要方向，系统将据此调整营养与训练计划'));
    expect(find.text('选择主要方向，系统将据此调整营养与训练计划'), findsOneWidget);
  });

  testWidgets('固定 CTA 直通保存：一眼不滚也能提交并进今日页（无回归）', (tester) async {
    OnboardingInput? saved;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      LocalFitApp(
        initialLocation: AppRoutes.onboarding,
        completeOnboarding: (input) async {
          saved = input;
          return const NutritionTarget(
            bmrKcal: 1699,
            tdeeKcal: 2633,
            calorieMinKcal: 2126,
            calorieMaxKcal: 2350,
            proteinMinGrams: 120,
            proteinMaxGrams: 150,
            carbsMinGrams: 200,
            carbsMaxGrams: 300,
            fatMinGrams: 53,
            fatMaxGrams: 75,
          );
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(_field('年龄'), '30');
    await tester.enterText(_field('身高'), '175');
    await tester.enterText(_field('当前体重'), '75');
    // 一行都不滚：CTA 钉在底部（这正是 D18 第 7 条要买到的行为）。
    await tester.tap(find.byKey(const Key('onboarding-submit')));
    await tester.pumpAndSettle();
    expect(find.text('确认每日目标'), findsOneWidget);

    await tester.tap(find.text('确认保存'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(saved, isNotNull, reason: '不经滚动也能完成建档');
    expect(saved!.age, 30);
    expect(saved!.activityLevel, ActivityLevel.lightlyActive, reason: '默认档位不变');
    expect(saved!.biologicalSex, BiologicalSex.female, reason: '默认档位不变');
    await tester.pumpAndSettle();
    expect(find.text('热量、营养目标和今日训练将在这里汇总。'), findsOneWidget);
  });
}

/// 阶段条的 4 枚胶囊（进度条本身 `ExcludeSemantics`，只做视觉）。
Finder _pills() => find.descendant(
  of: find.byKey(const Key('onboarding-progress')),
  matching: find.byType(Container),
);

String _label(WidgetTester tester) => tester
    .widget<Text>(find.byKey(const Key('onboarding-progress-label')))
    .data!;

LfSemanticColors _colors(WidgetTester tester) =>
    tester.element(find.byType(OnboardingPage)).lf;

ScrollPosition _position(WidgetTester tester) =>
    tester.state<ScrollableState>(find.byType(Scrollable).first).position;

Future<void> _pumpPage(
  WidgetTester tester, {
  Size size = const Size(900, 1400),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: OnboardingPage(completeOnboarding: (_) async => throw 'unused'),
    ),
  );
  await tester.pumpAndSettle();
}

/// 数值字段按页面自己的 Key 定位（`onboarding-<字段名>`）。
Finder _field(String label) => find.byKey(Key('onboarding-$label'));

Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}
