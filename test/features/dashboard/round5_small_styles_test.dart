import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/features/dashboard/presentation/sections/dashboard_meals_card.dart';
import 'package:localfit_ai/features/training/presentation/exercise_library_page.dart';

/// T3 小样式（docs/32 §4 T3；需求 63 / 68）。
///
/// ① 需求 63：今日饮食空态块**铺满卡片宽度**（左右边距相等）；
/// ② 需求 68：动作库卡片**底部留白 = 顶部**（`_cardExtent` 去掉 +12）。
///
/// 需求 65（今日推荐同排同高）的两条用例随 `NextMealDecisionCard` 整族退役
/// 删除（`docs/56` R4 / `docs/58` §5 台账）——见文件内退役说明。
void main() {
  Widget host(Widget child) => MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );

  testWidgets('需求 63：今日饮食空态块居中且不偏左（Round7 A 空态仍须对称）', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Round7 A 起空态是 `.empty-state`（52dp 图标块 + 标题 + 说明，居中），
    // 不再是「铺满内容宽的 muted 块」——需求 63 的**意图**（不许只占左边
    // 一小块、外观对称）由「内容在卡片内水平居中」承担。
    await tester.pumpWidget(
      host(const DashboardMealsCard(entries: [], meals: [], onLogMeal: _noop)),
    );
    await tester.pumpAndSettle();

    final card = tester.getRect(find.byKey(const Key('dashboard-meals-card')));
    final empty = tester.getRect(
      find.byKey(const Key('dashboard-meals-empty')),
    );
    final leftGap = empty.left - card.left;
    final rightGap = card.right - empty.right;
    expect(
      leftGap,
      closeTo(rightGap, 0.5),
      reason: '左右边距必须相等（实测 左 $leftGap / 右 $rightGap）',
    );
    expect(leftGap, closeTo(16, 1.0), reason: '空态块应铺到卡片内容区（内边距 16），不是只占左边一小块');
  });

  // 【测试退役】需求 65 的两条用例（「今日推荐同排按钮同高」）随
  // `NextMealDecisionCard` 整族退役一并删除（`docs/56` R4 / `docs/58` §5
  // 台账）。断言的**对象**（那张卡的「查看菜单 / 调整时间」同排）不存在了，
  // 不是放宽判据——同排同高的规则由 `unified_card_button_audit_test`
  // 在全仓层面继续守。

  testWidgets('动作库卡片几何：行高公式不含额外底部留白（需求 68）', (tester) async {
    // 直接钉几何公式：内容高（图标行 36 + 间距 8 + 标题 + 6 + 标签行
    // + 卡内内边距 24）之后不得再加 12。用 1.0× 字号代入：
    // 36 + 8 + 21 + 6 + (13.2+4) + 24 = 112.2
    final extent = exerciseCardExtentForTesting(fontScale: 1.0);
    expect(extent, closeTo(112.2, 0.01), reason: '卡片高度应等于内容高（去掉历史上多出的 +12 底距）');
    expect(
      exerciseCardExtentForTesting(fontScale: 2.0),
      closeTo(36 + 8 + 42 + 6 + (26.4 + 4) + 24, 0.01),
      reason: '2.0× 下只有随字号缩放的三行变，间距与图标行不变',
    );
  });
}

/// 读一个动作按钮的**视觉高度**（`minimumSize` 的解析值）。
///
/// 为什么不能量布局盒：`LfPillButton`/`LfPrimaryButton` 都靠 Material 的
/// `padded` 把命中盒膨胀到 48，量 `getSize` 两档恒 48、分不出 h32 与 h40
/// ——这正是用户能看出「上下宽度不一样」而测试量不出来的地方。
/// 主按钮是 `FilledButton`、次级胶囊是 `TextButton`，两型分别读。

void _noop() {}
