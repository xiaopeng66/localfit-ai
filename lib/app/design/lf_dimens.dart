/// 新设计尺寸 token（docs/21 §2.3 圆角 / §2.7 间距 / §3.6 底栏 / §5.8.4 几何）。
///
/// 唯一尺寸来源（旧 `AppDimens` 已于阶段 I-3 删除）。名字对齐设计稿的
/// `--lf-radius-*` 与 Tailwind gap 档，逐值可溯源。
abstract final class LfDimens {
  // ── 圆角（docs/21 §2.3：实际生效的只有 8/12/16/full，xs 档留给点/条）──
  static const double radiusXs = 4;
  static const double radiusSm = 8; // 徽章、tags、"周"字标
  static const double radiusMd = 12; // 图片缩略、输入框内部件
  static const double radiusLg = 16; // 内容卡
  static const double buttonRadius = 12;
  static const double inputRadius = 12;
  static const double sheetRadius = 24;
  static const double exerciseCardRadius = 14;
  static const double primaryActionHeight = 48;
  static const double radiusXl = 16; // 设计稿 xl/2xl 与 lg 同值
  static const double radius2xl = 16;
  static const double radiusFull = 999;

  // ── 间距（docs/21 §2.7，对齐 Tailwind gap 档）───────────────────────────
  static const double spaceMicro = 2; // gap-0.5
  static const double spaceXSmall = 4; // gap-1
  static const double spaceTiny = 6; // gap-1.5
  static const double spaceSmall = 8; // gap-2
  static const double spaceSmallPlus = 10; // gap-2.5
  static const double spaceMedium = 12; // gap-3
  static const double spaceMediumPlus = 14; // gap-3.5
  static const double spaceLarge = 16; // px-4 / p-4
  static const double spaceLargePlus = 20; // p-5

  /// 页面左右内边距与卡片内边距、卡片间距（统一 16，docs/21 §2.7）。
  static const double pagePadding = 16;
  static const double cardPadding = 16;
  static const double cardGap = 16;

  // ── 触达与图标 ─────────────────────────────────────────────────────────
  static const double minTouchTarget = 44;
  static const double iconSm = 16; // w-4（行内小图标，如 droplets 3.5→14 用 sm 档）
  static const double iconMd = 20; // w-5（底栏图标、卡内主图标）
  static const double iconLg = 24; // w-6（图片占位图标等中等尺寸）

  // ── 底栏（docs/21 §3.6 / §4.1 / §5.8.4）─────────────────────────────────
  /// 贴底直角栏高（`h-[64px]`），非旧设计的悬浮胶囊。
  static const double navBarHeight = 64;

  /// 中央凸起圆直径（`w-14 h-14`）。
  static const double navBumpSize = 56;

  /// CSS `-mt-4` 位移量。**注意：位移量 ≠ 净视觉量**（docs/21 §5.8.4 实测：
  /// 负 margin 参与 flex 分配后圆顶只超出栏顶约 9.5dp）。
  static const double navBumpMarginLift = 16;

  /// **净视觉上凸量 = 9.5dp**（7 个 HTML 实测一致：底栏顶边−圆顶边）。
  /// 槽位盒/页面预留按这个值算；按 16 校验会得到 6.5dp 假超标。
  static const double navBumpProtrusion = 9.5;

  /// `extendBody` 下页面内容底部预留：栏高 + 净上凸（列表末尾留白用）。
  static const double navReservedSpace = navBarHeight + navBumpProtrusion;

  // ── 图表（docs/21 §3.2）───────────────────────────────────────────────
  /// 体重图绘图区宽（设计稿 viewBox 320×130）。柱图里它是**去掉 y 轴列之后**
  /// 的绘图区宽 —— 轴列另占 [weightChartAxisWidth]。
  static const double weightChartWidth = 320;

  /// 体重图**柱区**高（周/月视图共用）。柱高按刻度轴映射到这个高度。
  ///
  /// Round7 A 有效值：`.weight-chart{height:150px;padding-top:12px}`（含标签行，
  /// 盒模型 border-box）− 标签行 [weightChartLabelRowHeight] 25 =
  /// 柱区 113（`refinement.css:6 .weight-bar-space{height:calc(100% - 25px)}`）。
  static const double weightChartHeight = 113;

  /// A `.weight-chart{padding-top:12px}`：图表容器上内边距（最高一档刻度上方留白）。
  static const double weightChartTopPadding = 12;

  /// A `.weight-slot{gap:5px}` + `.weight-slot small{height:20px}`：
  /// 柱区之下的标签行（间隔 5 + 文本行 20），网格线与刻度都只铺柱区内。
  static const double weightChartLabelRowHeight = 25;

  /// 弹层（`AppSheet`）的**最小底衬**（2026-10-16 用户实测：「添加记录时保存
  /// 按钮太靠下」）。弹层原本只垫「键盘高 + 安全区内边距」，两者都为 0 时
  /// （手势条不占内边距的机型）主行动会贴到屏幕底边。取 max(键盘+安全区, 16)。
  static const double sheetBottomMinInset = 16;

  /// 体重柱图选中浮窗的**定宽**（2026-10-16 用户实测「文字框有点歪」）。
  /// 定宽 + 框内居中后，「格心 − 半宽」才真的把框心对到格心；此前用
  /// `maxWidth: 64`，框宽随文字长短变、框心偏左 (64 − 宽)/2。
  static const double weightChartTooltipWidth = 64;

  /// 横轴日期标签允许的**最大宽度**（可以大于一格："9/14" 这类 M/D
  /// 要 ~20dp，而月视图一格只有绘图区/当月天数 ≈ 10dp）。给到 56dp
  /// 既容得下两位月/两位日（如 12/28），又远小于月视图里相邻标签的
  /// 7 格间距（≈70dp）⇒ 不会互相压字。
  static const double weightChartAxisLabelMaxWidth = 56;

  /// A `.chart-hint{margin-top:9px}`（refinement）：图表下方一行 10px 说明。
  static const double chartHintMarginTop = 9;

  /// 体重柱图左侧 y 轴列宽：刻度文字（`micro` 档「71.0」约 26dp）。
  /// 2026-10-08（docs/30 §2 D3）新增 —— 折线图没有轴列；
  /// 2026-10-11（docs/32 §3 D2）刻度由 3 档升 4 档，列宽不变。
  static const double weightChartAxisWidth = 30;

  /// CalorieRing（docs/21 §3.2：120×120，r=52，stroke 10）。
  static const double calorieRingSize = 120;
  static const double calorieRingRadius = 52;
  static const double calorieRingStroke = 10;

  /// 圆环**内孔**直径（描边内缘围出的空洞）：中心三段文字只能住在这里面。
  /// 设计稿只在 1.0× 下给过中心三段，未规定放大字号时的退化；真机 2.0×
  /// 实测过：若把中心块缩到 120dp 框宽，最宽的「/ N kcal」会横跨到轨道
  /// 描边上（视觉上压线）。以内孔为上限则任何字号都不会压到环。
  static const double calorieRingInnerSize =
      2 * (calorieRingRadius - calorieRingStroke / 2);

  // ── 食物卡（docs/28 §5.1）──────────────────────────────────────────────
  /// 食物卡左上分类图标块边长（计划给的字面值 40dp）。
  static const double foodCardIconSize = 40;

  /// 食物卡右上「能量密度环」：44dp 迷你环 + 4dp 描边。
  ///
  /// 与 `calorieRingSize` 是两件东西：那个是「今日摄入 / 目标」，这个是
  /// 「每 100 克热量在 0–1000 kcal/100g 刻度上的位置」，口径不同不共用尺寸。
  static const double foodKcalRingSize = 44;
  static const double foodKcalRingStroke = 4;

  /// 食物**列表卡**上的小档能量密度环：36dp + 4dp 描边（内孔 28dp）。
  ///
  /// 2026-10-08（docs/30 §2 D1，用户走查需求 1「再小一点的热量圆环」）：
  /// 列表卡由五段压成**单行三件**，环是行内最右一件 —— 44dp 会把行高顶到
  /// 44 以上，与「卡片缩短上下宽度」的要求相反；36dp 时行高由图标 40 决定。
  /// 三位数（如 `900`）在 28dp 内孔里由既有 `FittedBox.scaleDown` 兜底。
  ///
  /// 另起常量而不是改 [foodKcalRingSize] 的值：后者是 `LfFoodKcalRing` 的
  /// 默认值，详情弹层等调用点仍经由默认档使用它。
  static const double foodKcalRingSmallSize = 36;
  static const double foodKcalRingSmallStroke = 4;

  /// 同一件环的大档（食物详情弹层的「图形化营养」主图）：56dp + 6dp 描边。
  ///
  /// 2026-10-06（docs/29 §P8a 需求 28）：原来是 88/8，用户要求「圆环小一点
  /// （三个营养同行）」⇒ 收到 56/6，三格克数行与环**同行**。中心数字仍是
  /// `titleLarge` 档（16px）：56−6 = 50dp 内孔放得下三位数，不必降档。
  static const double foodKcalRingLargeSize = 56;
  static const double foodKcalRingLargeStroke = 6;

  // ── 成就勋章（docs/29 §P3）──────────────────────────────────────────────
  /// 成就行的勋章环：44dp 外径 + 5dp 描边 ⇒ 内盘 34dp（放图标或挂锁）。
  ///
  /// 与 `foodKcalRingSize` 同为 44dp 但是两件东西（那个是能量密度环，口径
  /// 与语义都不同），所以不共用常量。
  static const double achievementMedalSize = 44;
  static const double achievementMedalStroke = 5;
}
