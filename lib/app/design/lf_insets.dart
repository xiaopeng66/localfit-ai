import 'package:flutter/widgets.dart';

import 'package:localfit_ai/app/design/lf_dimens.dart';

/// 系统叠层留白（docs/21 §5.8.5）。
///
/// 设计稿是浏览器视口，**不含任何系统叠层**；状态栏与手势条的高度只能来自
/// 运行环境，不得硬编码成常量。取值统一走这里，避免每个页面各写一遍
/// `MediaQuery.paddingOf(context)` 而漏掉某处。
///
/// 【为什么要有这个文件】阶段 J 真机走查实测：`docs/21` 全文没有一条叠层
/// 规则，实现里只有部分页面套了 `SafeArea`，于是 4 个页面的首个内容节点
/// （今日 `y=21` / 饮食·记录 `y=53` / 训练 `y=0` / 我的 `y=53`）落在
/// 状态栏带内（实测 API 35 模拟器状态栏 `frame=[0,0][1080,128]`，128px），
/// 被状态栏时钟压住。
abstract final class LfInsets {
  /// 顶部叠层（状态栏 / 刘海）高度；无叠层时为 0（桌面与 widget 测试默认）。
  ///
  /// 读 `padding` 而不是 `viewPadding`：这里的语义是「**这个 widget 还需要**
  /// 往下让多少」，祖先已经消费掉的叠层（例如 `Scaffold` 带 `appBar` 时抹掉
  /// body 的 `padding.top`）不该再让一次。贴顶 hero 与 `LfTopBar` 都是这个语义。
  static double top(BuildContext context) => MediaQuery.paddingOf(context).top;

  /// 底部叠层（手势条 / home indicator）高度。
  ///
  /// **不从 MediaQuery 取**：shell 的 `Scaffold` 带 `bottomNavigationBar`，
  /// 它会把 body 的 `padding.bottom` **和** `viewPadding.bottom` 一起抹成 0
  /// （`MediaQuery.removePadding` 两个字段都抹）——页面里读 `paddingOf` 或
  /// `viewPaddingOf` 都会得到 0，手势带就被漏算了。页面要的是「显示器在手势带
  /// 上留了多少」这个事实，直接问视图：这也是 `MediaQueryData.fromView` 内部
  /// 的来源，而 widget 测试里 `tester.view.padding` 注入的正是它。
  static double bottom(BuildContext context) {
    final view = View.of(context);
    return view.padding.bottom / view.devicePixelRatio;
  }

  /// shell 分支页（今日/饮食/训练/我的及其 tab）滚动容器末尾要预留的高度。
  ///
  /// = 栏体 64 + 净上凸（[navBumpProtrusion]，1.0× 下 9.5）+ 底部手势带。
  /// 手势带那一段**必须**算进来：`extendBody` 下滚动容器一直伸到屏幕物理底边，
  /// 只按 64+9.5 预留时，列表滚到底的最后一张卡会被栏体压住
  /// （docs/21 §5.8.4 的「64 + safe-area」，阶段 J 实测压在栏体下 7px）。
  ///
  /// 【谁需要预留】判据是**页面挂在哪个 Navigator 上**，不是"是不是二级页"：
  /// `AppShell` 的 `Scaffold(extendBody: true)` 把贴底栏盖在整个 body 之上，而
  /// 五个分支各自的嵌套 Navigator 就在这个 body 里（`app_router.dart` 的
  /// `StatefulShellRoute.indexedStack`）——**所以从分支页 push 出来的二级页同样
  /// 会被压住**，自带 `appBar` 也不改变这一点。
  ///
  /// 2026-10-03 走查实测（1080×2340 / dpi 480，栏体顶边 `y=2000`）：动作库网格
  /// 最后一格 `2254~2340`、食堂目录空态 CTA `2124~2268` 全落在栏体之下；食堂目录
  /// 还是 `SliverFillRemaining`（`maxScrollExtent == 0`）连滚都滚不上来，两次点按
  /// 都打在栏体/FAB 上——「唯一能建第一个食堂地点的控件不可达」。两处现已预留：
  /// `exercise_library_page.dart`（网格 padding）与 `menu_tab_view.dart`（末尾 sliver）。
  ///
  /// 只有声明在 shell **之外**的同级路由（`/meal-recognition`、`/ai-workbench`、
  /// `/profile-edit`、`/workout-plan-create` 等，见 `app_router.dart` 的 routes 表）
  /// 不适用：它们挂在根 Navigator 上，整屏覆盖 shell，底部由自己的 `SafeArea` 处理。
  /// 栏体高**固定** 64（A `refinement.css:3` `.app-nav{height:64px}`，覆盖
  /// `styles.css:113` 的 65px）。它不随系统字号长大：Round5 立过「零安全区 +
  /// 2.0× 字号下栏高仍是 64、不凭空多留白」的硬约束（`stress_ui_test` 两条），
  /// A 也把栏高写成常量——槽内文字用 10px 标签（`.nav-item{font-size:10px}`），
  /// 在 64 里排得下。
  static double navBarHeight(BuildContext context) => LfDimens.navBarHeight;

  /// 中央凸起圆**净上凸**多少（页面上方预留的那一段）。
  ///
  /// 1.0× 下就是 A 实测的 9.5dp。但大字号下 AI 槽的标签会变高（`LfText.micro`
  /// 10px × 1.4）：圆在栏内占 `56 - 上凸`，标签要贴栏底、且不得被圆压住，
  /// 于是上凸必须跟着长大——**长大的只能是圆，不能是栏体**（栏体有 Round5 的
  /// 固定 64 约束）。护栏：`round7_components_test` 的
  /// 「AI navigation label does not overlap its icon at 200 percent」。
  static double navBumpProtrusion(BuildContext context) {
    final labelLine = MediaQuery.textScalerOf(context).scale(10) * 1.4;
    // 标签底距栏底 1.5（`lf_bottom_nav.dart` 的 `_CenterSlotLabel`），
    // 圆在栏内占的高度 = navBumpSize - 上凸。
    final needed =
        labelLine + 1.5 - (LfDimens.navBarHeight - LfDimens.navBumpSize);
    return needed > LfDimens.navBumpProtrusion
        ? needed
        : LfDimens.navBumpProtrusion;
  }

  static double navReserve(BuildContext context) =>
      LfDimens.navBarHeight + navBumpProtrusion(context) + bottom(context);
}
