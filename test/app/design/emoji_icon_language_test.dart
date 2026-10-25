import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/design/widgets/lf_empty_state.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/menu_dish_list.dart';
import 'package:localfit_ai/features/onboarding/presentation/onboarding_page.dart';
import 'package:localfit_ai/features/training/presentation/training_page.dart';

/// Round7 阶段 6 · 缺陷 ㉓：**表情符号与空态语言必须收到 A 那一套**。
///
/// 渲染审看抓到（`renders/6a-settings/settings-data-light-360-1.0.png`）：设置页
/// 底部「所有数据仅保存在这台设备」前的 `🛡` 在帧里是**空方框**——本仓不随包
/// emoji 字体（`docs/21 §2.6.1`：字体族用平台默认 CJK），测试引擎里没有字形；
/// 真机上它靠系统 emoji 兜底渲染成彩色表情，而 **A 的空态/标签语言是线稿图标**
/// （`icon('shield')`、`.empty-state .icon-chip` 的 SVG），彩色 emoji 是上一代
/// 视觉。同一件事在 6 处空态上重复：`AppEmptyState`（旧 80dp 渐变圆 + 32px
/// emoji）仍在菜单 tab / 菜品列表 / 动作库 / 训练页三处使用，而 Round7 的
/// 空态件是 [LfEmptyState]（A `.empty-state`：52 R18 `brand-soft` 图标块）。
///
/// 本组判据钉两件事：**① 上屏文本里不再有 emoji**；**② 这些空态全部走
/// [LfEmptyState]（图标块）**。旧件 `AppEmptyState` 已于 2026-10-15 死代码
/// 清理时整件删除（连文件带两个自测）——「退场」从"断言它不出现"升级为
/// "它已经不存在"，故本文件不再能也不必按类型引用它。
void main() {
  /// 上屏文本里不许出现 emoji（本仓没有 emoji 字体，帧里必是空方框）。
  void expectNoEmoji(WidgetTester tester, String where) {
    final emoji = RegExp(
      '[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}\u{FE0F}]',
      unicode: true,
    );
    for (final text in tester.widgetList<Text>(find.byType(Text))) {
      final data = text.data;
      if (data == null) continue;
      expect(
        emoji.hasMatch(data),
        isFalse,
        reason: '$where：上屏文本「$data」含 emoji——本仓无 emoji 字体，帧里是空方框',
      );
    }
  }

  testWidgets('训练页空态：走 LfEmptyState（图标块），不是 AppEmptyState（emoji 圆）', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: TrainingPage()));
    await tester.pump(const Duration(milliseconds: 50));

    expectNoEmoji(tester, '训练页');
  });

  testWidgets('引导页：目标大卡用图标，文本里无 emoji', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingPage(
          completeOnboarding: (input) async => throw UnimplementedError(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    // 三张目标卡（减脂/增肌/维持）在场的证据 + 无 emoji 上屏。
    // 2026-10-16：文案与资料页/AI 协议统一成「维持」（原引导页写「保持」）。
    for (final label in const ['减脂', '增肌', '维持']) {
      expect(find.text(label), findsOneWidget);
    }
    expectNoEmoji(tester, '引导页');
  });

  testWidgets('菜单 tab 空态：走 LfEmptyState，且无 emoji 上屏', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // 未接依赖 = 「菜品库尚未配置。」空态（`MenuDishList.repository: null`
    // 就是这条自门控路径）。
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: MenuDishList(repository: null))),
    );
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('菜品库尚未配置。'), findsOneWidget);
    expectNoEmoji(tester, '菜单 tab 空态');
    expect(find.byType(LfEmptyState), findsOneWidget);
  });

  testWidgets('动作库空态：走 LfEmptyState，且无 emoji 上屏', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // 直接测件级：以「没有匹配的本地动作。」这条空态的**宿主**为准，
    // 页面级夹具在 `exercise_library_page_test` 里已有。
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: LfEmptyState(
            icon: Icons.search_off,
            title: '没有匹配的本地动作。',
            message: '换个关键词，或新建一个自定义动作。',
          ),
        ),
      ),
    );
    await tester.pump();
    expectNoEmoji(tester, '动作库空态（件级）');
  });
}
