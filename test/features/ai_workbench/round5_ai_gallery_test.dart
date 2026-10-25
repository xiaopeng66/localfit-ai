import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/features/ai_workbench/application/ai_starter.dart';
import 'package:localfit_ai/features/ai_workbench/presentation/ai_workbench_page.dart';

/// T6a（docs/32 §4 T6a / §3 D5 / 需求 62）：AI 创作画廊重设计。
///
/// 验收：6 张卡**分组**展示（饮食 / 训练与搭配）；卡片点击 → 描述框
/// （标题=任务名、placeholder=该任务既有 inputHint、主按钮「生成」
/// **非空才可点**）；无障碍标签齐全；文案逐字沿用既有 task 文案。
///
/// 「生成后切到对话分支并自动发送」属 T6b，本文件只钉到「点了生成之后
/// 拿到拼好的启动提示词」这一步（用注入的 onGenerate 回执）。
void main() {
  /// 高视口：六张卡在默认 800×600 下会滚出可点区（第三张起 tap 命中不到）。
  void useTallViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget host(Widget child) =>
      MaterialApp(theme: AppTheme.light(), home: child);

  /// 六个已接线任务的夹具：id/文案取自 [aiStarters]（与生产一致）。
  Widget page({ValueChanged<String>? onGenerate}) =>
      host(AiWorkbenchPage(onGenerate: onGenerate ?? (_) {}));

  testWidgets('画廊按两组渲染 6 张卡：饮食 4 + 训练与搭配 2', (tester) async {
    useTallViewport(tester);
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();

    // 两个分组标签。
    expect(find.text('饮食'), findsOneWidget);
    expect(find.text('训练与搭配'), findsOneWidget);

    // 六张卡的 Key 全在（沿用 `ai-workbench-task-<id>`）。
    for (final starter in aiStarters) {
      expect(
        find.byKey(Key('ai-workbench-task-${starter.id}')),
        findsOneWidget,
        reason: '${starter.title} 卡必须在',
      );
    }
    // 六条既有描述文案逐字上屏（不新造文案）。
    for (final starter in aiStarters) {
      expect(
        find.textContaining(starter.description),
        findsOneWidget,
        reason: '${starter.title} 的描述沿用既有 inputSummary',
      );
    }
  });

  testWidgets('卡片点击 → 描述框：标题=任务名、placeholder=既有 inputHint、生成初始禁用', (
    tester,
  ) async {
    useTallViewport(tester);
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();

    const target = 'workout-plan';
    await tester.tap(find.byKey(const Key('ai-workbench-task-$target')));
    await tester.pumpAndSettle();

    // 弹层标题 = 任务名（弹层里再出现一次「训练计划」）。
    expect(find.text('训练计划'), findsNWidgets(2));
    // placeholder = 该任务既有 inputHint。
    expect(
      find.text('例如：一周 4 练，增肌，家里只有哑铃'),
      findsOneWidget,
      reason: 'placeholder 沿用既有 inputHint',
    );

    // 「生成」初始禁用（非空才可点）。
    final generate = find.byKey(const Key('ai-starter-generate'));
    expect(generate, findsOneWidget);
    final button = tester.widget<FilledButton>(generate);
    expect(button.onPressed, isNull, reason: '空输入时「生成」必须不可点');
  });

  testWidgets('输入非空后「生成」可点，点击回执拼好的启动提示词', (tester) async {
    useTallViewport(tester);
    String? prompt;
    await tester.pumpWidget(page(onGenerate: (p) => prompt = p));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('ai-workbench-task-workout-plan')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('ai-starter-input')),
      '一周 4 练，增肌',
    );
    await tester.pumpAndSettle();

    final generate = find.byKey(const Key('ai-starter-generate'));
    expect(
      tester.widget<FilledButton>(generate).onPressed,
      isNotNull,
      reason: '非空输入后「生成」可点',
    );
    await tester.tap(generate);
    await tester.pumpAndSettle();

    expect(prompt, isNotNull);
    expect(prompt, contains('按我描述的目标生成训练计划并保存'));
    expect(prompt, contains('一周 4 练，增肌'));
  });

  testWidgets('六卡提示词方向与 D5 表格逐条对应', (tester) async {
    // 纯函数层直接钉：每张卡把用户输入拼进自己的方向句。
    for (final starter in aiStarters) {
      final prompt = starter.promptBuilder('样板输入');
      expect(prompt, contains('样板输入'), reason: '${starter.id} 必须带上用户输入');
      expect(prompt, endsWith('样板输入'), reason: '${starter.id} 的输入应在末尾');
    }
    expect(
      aiStarters
          .firstWhere((s) => s.id == 'daily-menu-plan')
          .promptBuilder('x'),
      contains('帮我搭配今天剩下几餐'),
      reason: '生成今日吃法 = 咨询型建议（D5）',
    );
  });

  test('六卡描述都是完整句子（T10 真机走查补钉：三条曾被截断）', () {
    // 逐字来源（不是新造文案）：
    // - `docs/evidence/2026-10-04-input-menu-foodlib-redesign/w4-07-ai-workbench-6-tasks.xml`
    //   里旧卡片 content-desc（六条完整句）；
    // - `docs/08-store-privacy-and-permissions.md:44` 独立记着常吃搭配的
    //   「不上传餐食历史」承诺。
    // T10 走查发现 gallery 的三条描述停在子句中间（残留「；」「，」），此处补钉。
    final byId = {
      for (final starter in aiStarters) starter.id: starter.description,
    };
    // 【语义变更，2026-10-25】原句写「确认只加入计划」——「加入计划」随
    // `daily_plan` 整族退役（docs/58 D1）已不存在，那句话在给用户承诺一个
    // 没有的功能（用户实测：「明明那个描述说加入计划，计划这个功能已经删除了」）。
    // 改为如实描述**现在的真实行为**：产出一张可应用的编辑卡。
    expect(
      byId['daily-menu-plan'],
      '用本地菜单候选和目标先算一遍，再让 AI 只在这些候选里选；'
      '结果是一张可应用的卡片——点「应用」才记进当天餐记录。',
    );
    expect(
      byId['dish-guidance'],
      '只解释怎么吃：份量、搭配与可替换方向；营养由本地目录计算，AI 不提供营养数字，也不写入任何记录。',
    );
    expect(
      byId['meal-pairing'],
      '你点名的本地食材 → AI 只在这些食材里组织搭配 → 本地重算营养（只读建议）。不上传餐食历史。',
    );
    // 兜底判据：描述不许停在子句分隔符上——那正是被截断的痕迹。
    for (final starter in aiStarters) {
      expect(
        starter.description.endsWith('；') || starter.description.endsWith('，'),
        isFalse,
        reason: '${starter.id} 的描述像被截断了：${starter.description}',
      );
    }
  });

  testWidgets('分组归属与顺序：饮食 4 张在前，训练与搭配 2 张在后', (tester) async {
    useTallViewport(tester);
    final diet = aiStarters
        .where((s) => s.group == AiStarterGroup.diet)
        .toList();
    final training = aiStarters
        .where((s) => s.group == AiStarterGroup.training)
        .toList();
    expect(diet.length, 4);
    expect(training.length, 2);

    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    // 「饮食」标签的 y 必须小于「训练与搭配」。
    final dietY = tester.getTopLeft(find.text('饮食')).dy;
    final trainingY = tester.getTopLeft(find.text('训练与搭配')).dy;
    expect(dietY, lessThan(trainingY));
  });
}
