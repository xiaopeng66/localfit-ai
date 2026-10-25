# LocalFit AI 界面重设计第三轮方案（`docs/30`）

日期：2026-10-08
依据：用户 2026-10-08 一次性反馈（**10 条**，见 §1）+ 同日代码可达性实测（每条需求的现状落点、两个真实缺陷的根因定位见 §1 逐条）
状态：**待实施**。本轮工作包 R1→R8，每包独立过门禁（`tool/verify.bat`）。
前置：`docs/29` 的 P0–P12 已全部交付并闭环（见 `STATUS.md`），本方案是**新一轮**，不重开旧包。

---

## 0. 权威源与防误导（开工前必读）

| 类别 | 权威文件 | 说明 |
|---|---|---|
| **本方案的执行细则** | **本文 `docs/30`** | 10 条需求的唯一落点与顺序；与其余方案书冲突时以本文为准 |
| 长期目标与硬约束 | `GOAL.md` | 产品目标、隐私/AI 硬约束 |
| 产品/数据/AI/验收契约 | `docs/07-localfit-2.0-development-spec.md` | 契约层 |
| **UI 规范** | `docs/21-ui-redesign-spec.md` + `ui设计/pages/*.html` | token / 组件族 / 每页结构树。**本轮改动落地时同步改写 docs/21 对应小节**（它被 `ui_spec_key_sync_test.dart` 读盘） |
| 实时状态 / 交接 | `STATUS.md`（根目录） | 只有这里能说「做到哪一步了」 |
| 决策日志 | `docs/DECISIONS.md` | 追加式，本轮新决策按 ADR 编号追加 |

**已知会误导本轮的三处旧文本（实施时同步修正，不留「照它做就错」的注释）**：

1. `docs/21 §3.11` 的食物卡「卡五段」表与「彩点行」行——本轮 R3 把卡片改成**单行三件**，
   该表整体重写；`FoodDensityScaleNote`（满刻度说明）保留。
2. `docs/21 §5.1` 结构树里的 `WeightChartCard → 3 × TrendTile` 与 Key 表里的
   `dashboard-trend-weight/bodyfat/muscle`——本轮 R2 删除，Key 表同步删除
   （`ui_spec_key_sync_test` 是「doc ⇄ lib ⇄ test」三方对账，删 Key 必须三处同删）。
3. `docs/21 §2.5` 「hero 渐变 5 处引用」——本轮 R4/R5 后记录页/菜单页/身份卡三处退场，
   引用处数变 2（今日 AI 卡、拍照页占位）。**改的是引用处数，不是渐变定义本身**
   （定义仍在 `lf_tokens.dart` 的 `heroGradient`，`design_source_parity_test` 继续对账）。

---

## 1. 需求清单（用户原话 → 编号 → 现状实测）

> 原话逐条照录，不转写、不合并。现状一栏是 2026-10-08 读码实测（含文件:行号），
> 供实施与评审对账。

### 需求 1 · 食物库卡片精简 + 详情弹层三行对齐

> 「我希望食物库的数据，主界面只显示图标，名称和再小一点的热量圆环，都在一行，水平居中，
> 卡片缩短上下宽度，点击后的卡片才显示详细的三营养数据，三行数据的所在行需要与圆环的圆心上下对齐。」

**现状**：卡片是**五段式**（`food_card.dart:110-208`）——① 图标 40 + 名称 + 环 44 ② 环下口径行
`kcal/100g` ③ 三彩点宏量行 ④ 品牌 chip 左下 + 自建/内置徽标右下 ⑤ 「营养不完整」行（条件）。
卡内边距 `12/12/12/8`，实测卡高 ≈136dp。行高由 `SliverPrototypeExtentList` 的
**最高变体原型卡**决定（`food_library_view.dart:373`），骨架 `FoodCardSkeleton` 逐行同构
且被测试钉死等高（`food_library_ui_test.dart:395`）。详情弹层（`food_detail_sheet.dart:215`）
是「环 56 + 环下标签」一列 + `MacroDotLine` **三格一行**，`CrossAxisAlignment.center`
居中的是**环那一整列**（56 + 2 + 14 = 72dp）⇒ 三格的文字块中心落在列中心（环心下方 8dp），
**不是环心**。

### 需求 2 · 今日页体重卡重设计

> 「今日页面的体重卡，周/月切换的按钮太大了，上下宽度也很大，按钮不好看，你重新设计一下，
> 另外月视图的显示好像有问题，还有，数据做成柱状图，左边要有坐标，下边的本周趋势三个小卡片不要了，
> 不需要统计体脂率和肌肉量了。」

**现状**：① 周/月切换是 `LfSegmentedToggle`（`lf_segmented.dart`）——每段
`SizedBox(height: minTouchTarget=44)` 直接参与布局，外层再加 `padding: 2` ⇒ **控件整体高 48dp**，
在卡头行里把行高撑到 48（视觉胶囊只有 24）。② **月视图真缺陷**：分箱固定
`weightMonthBucketDays = 7`（`weight_chart_points.dart:14`），记录 **2–7 条**时只产出
**1 个点**，而卡片 `points.length < 2` 就渲染 `_EmptyChart`（「还没有体重记录」）——
**明明有记录却说没有**（1 条时周视图同样走空态，文案在那时也是错的）。③ 图是折线
（`weight_line_chart.dart`，7 点 + 渐变填充 + 网格），**没有 y 轴刻度**。④ 卡底
「本周/本月趋势」标题 + 分隔线 + 3 × `TrendTile`（体重 / 体脂率 / 肌肉量）整段要删。

### 需求 3 · 步数授权在设置页可取消

> 「步数的授权需要在设置页面可以取消。」

**现状**：设置页**没有任何步数/权限入口**（实测 `settings_page.dart` 全文无 `steps` 字样）。
权限只在今日页步数卡的「未授权 → 去设置」出现（`dashboard_quick_stats_row.dart:275-289`）。
原生侧 `openAppSettings` 已存在（`MainActivity.kt:178`，跳
`ACTION_APPLICATION_DETAILS_SETTINGS`）；`StepsRepository` 已转发 `requestPermission` /
`openAppSettings`（`steps_repository.dart:148-158`），但**没有注入设置页**。

### 需求 4 · 记录页与菜单页的绿色数据卡重设计

> 「记录和菜单页面的最上边的绿色数据卡太丑了，重新设计。」

**现状**：两页最上方都是 `HeroSection`（mint 渐变 `135deg #2FBE8F → #A8EBCF → #ECFBF5`
全宽铺顶 + 只圆下角 16）。记录页 hero（`nutrition_record_hero.dart`）= 标题「饮食记录」+
日期 + 三段统计（已摄入/目标/剩余）；菜单页 hero（`menu_dish_list.dart:577`）= 标题
「今日菜单」+ 副标题 + 右上管理圆钮 + 两段统计（已安排 N 餐 / 预计 kcal）。

### 需求 5 · 我的页绿色身份卡重设计

> 「我的界面的绿色个人信息卡和训练界面的黑色数据卡都很丑，请重新设计。」

**现状**：`_IdentityCard`（`settings_page.dart:1580`）= hero 渐变 + 全角 16 + 径向点纹理
（`_DotTexture`，1px 点 /14dp 间距）+ 64dp 圆头像「Fit」+ 姓名「Fit」+ 副标题
+ 「编辑资料」半透明药丸 + 三段统计（当前体重/总记录/连续天数，`_IdentityStat`）。

### 需求 6 · 训练页黑色数据卡重设计

> （同需求 5 原话后半句）

**现状**：`TrainingHero`（`training_hero.dart:23`）= `neutral.tone(900)` 纯色底（亮色近黑
`#1A201D`、暗色近白 `#DDE5E1`）+ 只圆下角 16 + 内容躲状态栏 + 标题「训练」+「第 N 周」
+ 三段统计（已完成训练/总时长/消耗 kcal，30px w800）+ 7 柱容量图
（`_CapacityChart`，hand-painted，柱色 mint-300/400）+ 休息日图例。

### 需求 7 · 训练计划「可 AI 可手动」

> 「训练计划需要设置成可ai可手动。」

**现状**：入口已被动线分裂——训练页 FAB `cta-new-plan` → `_openNewPlan`
（`training_page.dart:569`）：**四项 AI 依赖齐全**时跳 `/workout-plan-create`（**纯 AI 流程**：
表单→披露→生成→预览→保存 `source:'ai'`）；**任一缺失**时退回一个**只有名称输入**的弹层
（`_openCreatePlanDialog`，`create(source:'manual')` 但 `days: const []` ⇒ 建出来是**空计划**，
得再进详情逐个「添加动作」）。仓库 `WorkoutPlanRepository.create` 本就支持
`source: 'ai'|'manual'` 两值（`workout_plan_repository.dart:116-143`）——缺的是**入口层的模式选择**
和**手动路径的完整表单**。

### 需求 8 · 基础代谢率绿色填充偏上

> 「基础代谢率的绿色填充和进度条有偏移，偏上了一点。」

**现状（根因已定位）**：`LfBandTargetGauge`（`lf_metric_gauge.dart:345-400`）的 16dp 高
`SizedBox` 里——灰轨走 `Align(centerLeft)`（垂直居中，占 `y 4..12`），而**绿色区间填充**
是 `Positioned(top: 0, height: 8)`（占 `y 0..8`）⇒ **填充比灰轨高 4dp**，正是用户看到的
「偏上了一点」。值圆点 16×16 `top: 0` 与整块同高（这个是对的）。

### 需求 9 · 所有设计重构先出 HTML 校正

> 「所有的设计重构都需要先做html，进行校正，没有问题再实施。」

**现状**：`ui设计/remediation/` 已有 6 份此机制的设计稿（P5/P6/P7/P8a/P9 各一份 + 记录页）。
本轮**每包先出 HTML 稿、渲染 360dp 评审图、过视觉评审后再写原生**（§4 详述）。

### 需求 10 · 先写设计方案，再实施

> 「先根据我的需求，写一份设计方案。然后再实施。」

**本文件的正文即是这一条**。§2 给全部裁决，§3 给工作包，§4 给设计稿与校正机制，§5 给门禁。

---

## 2. 裁决（每条给默认选择 + 理由；用户若不同意，改一行即可）

### D1 · 食物库卡=单行三件；「营养不完整」降级为**内联小图标**（需求 1）

- **卡片恒为一行**：`[图标 40] [名称 Expanded] [环 36]`，三件 `CrossAxisAlignment.center`
  共中线；内边距由 `12/12/12/8` 收到 `12/8`（上下同 8），卡高 ≈ 56–60dp。
- **「水平居中」的落点 = 三件沿同一条水平中线**（不是「整行内容在卡内水平居中」）。
  理由：名称长度天然不一，整行居中会让扫一列卡片时**名称起点逐行跳动**，可扫视性受损；
  图标→名称→环三段在同一中线上已经是用户要的「一行、居中」的视觉。候选（评审可改）：
  名称也水平居中（改 `Text` 的 `textAlign` 一行即可，评审时给出两版）。
- **环再小一点**：44 → **36dp**（stroke 4 不变，内孔 28dp；三位数 2.0× 由既有
  `FittedBox.scaleDown` 兜底）。新增 `LfDimens.foodKcalRingSmallSize = 36`，
  `foodKcalRingSize` 44 保留给其他调用点（若删干净则一并删）。
- **删掉的四段**：环下口径行、宏量三格行、品牌 chip + 自建/内置徽标行、
  「营养不完整」文字行。理由：用户点名「主界面只显示图标，名称和圆环」。
- **但「不可加入计划」是功能事实，不能只活在详情里**——`canJoinPlan == false` 时
  在**名称行内**名称之后内联一枚 **12dp 警告图标**（`Icons.error_outline`，`c.warning` 色，
  `Semantics(label: '营养不完整，不可加入计划')`）。它不占独立行、不加卡高（原型仍单行）。
  理由：`docs/07 §9.3` 要求「能搜到不等于能进计划」写在明面上；整行文字退场后，
  图标+语义是最低成本的保留。
- **品牌与自建/内置**：卡片不再显示，信息在**详情弹层**看（弹层已渲染品牌与徽标，一行不改）。
- 骨架 `FoodCardSkeleton` 同步改单行（等高断言是硬要求）；原型卡保持「最高变体」语义
  （现在所有变体等高，原型= 真卡形态即可）。

### D2 · 详情弹层=三行营养 + 行块中心对环心（需求 1）

- **三营养改竖排三行**（每行：彩点 6dp + 名称 + 克数），**不再是三格一行**。
  行块 `CrossAxisAlignment.center` 与**只含环的那一列**对齐 ⇒ 行块中心 = 环心。
  环那一列**只放环**（56dp）——环下口径标签移出该列（P8a 的教训：列里加任何东西，
  `center` 居中的就是「整列」而不是环心）。
- **口径文字的位置**：弹层改为「环 + 三行」整块下方一行小字
  「每 100g · 满刻度 900 kcal/100g」（`FoodDensityScaleNote` 同一常量插值），
  环下不再挂 `kcal/100g` 标签。
- 克数口径不变：缺值与 0 都写 `0g`（`macroGramsOnScreen`，D14 既定口径，本次不动）。
- 环尺寸 56/6 不变（用户只要求主界面环变小）。

### D3 · 体重卡：紧凑双胶囊切换 + 柱状图（含 y 轴）+ 月视图修复（需求 2）

- **周/月切换换成两颗小胶囊**：`LfPillButton`（B3 档，视觉高 32、`selected` 档 =
  `soft`(mint-100 底 + mintText 字) / 未选 = `muted`），并排间距 6dp。
  触达：`TextButton` 的 `MaterialTapTargetSize.padded` 把命中盒撑到 48 —— **视觉 32 不参与布局高**，
  卡头行高不再被 44 命中盒撑到 48。`LfSegmentedToggle` 若因此零调用点则删除
  （`lf_segmented.dart` 全删，含其测试）。
- **柱状图替折线**：新件 `WeightBarChart`（`lib/app/design/widgets/weight_bar_chart.dart`）：
  - 柱：周视图 ≤7 根（一天一根）、月视图 ≤5 根（分箱均值）；圆角顶 6；色 `mint-500`，
    末柱（最新）用 `mint-600` 或加深以示「当前」；
  - **左侧 y 轴刻度**：三档（max / mid / min 的舍入值）+ 顶部单位 `kg`。
    轴范围 = 数据真实 min/max 外扩 25% 后取整（**不从 0 起**：体重从 0 画会把整段压成平线，
    这是与热量柱图不同的口径，注释写清）；刻度值如实标注（不四舍五入到假整数）；
  - 横轴标签在柱下方：周视图「一…日」、月视图「8/8」；
  - 网格：与刻度对齐的 3 条水平虚线（沿用现有风格）；
  - 语义：`ChartSemantics` 一行摘要（沿用全仓图表的文字等价物模式）。
- **月视图修复（真缺陷）**：分箱数改为 **≤5 箱自适应**：`bucket = max(1, (n / 5).ceil())`，
  于是 n≥2 恒有 ≥2 点；n=1 时柱图**画单根柱**（柱图天然支持单点）
  ⇒ 「还没有体重记录」空态**只在 0 条记录时出现**（文案在那时才是真的）。
  单测同步：`dashboard_steps_and_weight_test.dart` 的分箱用例按新口径改写。
- **删趋势三格**：卡底「本周趋势/本月趋势」标题、Divider、3 × TrendTile 全部删除；
  `TrendTile` / `MiniSparkline` / `TrendDirection` 若无其他生产调用点则**整件删除**
  （实测 `lib/` 内唯一调用点就是体重卡）。数据层不动：体脂率/肌肉量仍在
  `Measurements` 落库，只是本卡不再统计显示。
- 卡头保留：标题（随分段换「本周体重/体重趋势」）、最新值 + 增减副标题、
  「添加」文字按钮、两颗胶囊。

### D4 · 记录页/菜单页 hero 白卡化（需求 4）

- **mint 渐变整块退场**，两页顶部改为**标准 `DesignCard`**（白底 + 1px 描边 + 16 圆角 +
  浅阴影），与全 App 其余卡片同一语言；强调用**局部色彩**（数值/图标用 mint-700）。
  理由：用户连续点名三张「大色块数据卡」丑（绿×3 + 黑×1），方向一致 = 大色块退场、
  信息用排版与局部色表达；白卡是设计系统里唯一的卡形态（`docs/21 §3.1`）。
- **记录页卡内容**：标题「饮食记录」+ 日期（右侧 muted 小字）→ 三段统计
  （已摄入/目标/剩余，分隔线 1px）→ **有目标时补一根达成度进度条**
  （`LfProgressBar`，consumed/target，超出按 1 画满、剩余为负时条换 `warning` 色）；
  无目标不画条（没有分母就不画进度，既有诚实口径）。
- **菜单页卡内容**：标题「今日菜单」+ 副标题「按你的食堂窗口推荐今天吃什么」+
  右上管理圆钮（保留）→ 两段统计（已安排 N 餐 / 预计 kcal）。
- `HeroSection` 组件**保留**（今日页 AI 卡仍在用）；`HeroShape.bottomOnly` 的
  「记录/菜单 hero」注释同步改写。
- 页面结构（`record_tab.dart` 的 hero sliver、`menu_dish_list.dart` 的 `_MenuHero`）
  不动位置，只换皮与内部布局；**测试 Key 全部保留**
  （`nutrition-record-hero` / `-consumed` / `-target` / `-remaining`、`nutrition-menu-hero`
  / `-planned` / `-kcal`）⇒ 既有断言不因换皮而红。

### D5 · 我的页身份卡白卡化（需求 5）

- hero 渐变 + 点纹理 + 半透明药丸退场，改**标准 `DesignCard`**：
  - 头部：56dp 圆头像（`mint-100` 底 + mint-700「Fit」字，替代半透明白底）+
    姓名「Fit」+ 副标题（`已坚持 N 天 · 目标减脂 M kg`）在**同一行右邻**；
  - 右侧「编辑资料」= `LfTextButton`（B6，不再用半透明药丸）；
  - 三段统计在下：值 `headline` w800 墨色 + 标签 `micro` muted，纵向 1px 分隔线。
- Key 全保留：`settings-identity-card`、`settings-avatar`、`settings-identity-subtitle`、
  `cta-edit-profile`、`settings-stat-weight/-records/-streak`。
  （`profile_identity_card_test.dart` 断言的是「Key 在 + 认到文案」，换皮不该红。）

### D6 · 训练页 hero 白卡化 + 保留容量图（需求 6）

- `neutral-900` 纯色大块退场，改**标准 `DesignCard`**（与 D4/D5 同一方向）：
  - 第一行：标题「训练」+「第 N 周」（muted）；
  - 三段统计：`displayHero` 30px w800 墨色（保留设计稿的量级感）+ `micro` 标签；
  - 7 柱容量图保留（它是真数据），配色从「压黑底」改「白底」：
    训练日 `mint-400`、今日 `mint-600`、无训练 `muted`；休息日图例同套色；
  - 容量图的 `ChartSemantics` 摘要不变。
- Key 全保留：`training-hero`、`-week`、`-count`、`-duration`、`-kcal`、
  `training-capacity-chart`、`training-rest-legend`。
- 页面顶部不再铺到屏幕物理顶边 ⇒ 页面上边距改回 `pagePadding + LfInsets.top`
  （与我的页同一处理）；`respectTopInset` 相关注释同步改写。

### D7 · 训练计划：入口先选「AI 生成 / 手动创建」，两条路都能走通（需求 7）

- **FAB 点击 → 模式选择弹层**（`AppSheet`，两个大选项行）：
  - 「AI 生成」→ 走现有 `/workout-plan-create`（四项依赖不全时该行**禁用并说明原因**，
    不消失——用户知道有这条能力、以及怎么把它配好）；
  - 「手动创建」→ 进**新的手动计划页**（`/workout-plan-manual`，或复用同页 `mode` 参数）：
    名称 + 逐日（周一..周日任选）+ 每天逐个添加动作（复用详情页既有的「添加动作」弹层字段：
    动作 / 组 / 次 / 重量），保存 `source: 'manual'`。
- 手动页**不依赖 AI 四项依赖**（只需要 `exerciseRepository` + `workoutPlanRepository`）
  ⇒ AI 未配置的用户第一次就能建出**有内容的**计划（现状只能建空计划再逐个加动作）。
- 训练页二级入口「AI 生成训练计划」保留（它直达 AI 路径，不经过模式弹层）。
- 空态文案同步：「还没有本地训练计划 → 新建一个计划」不变。

### D8 · BMR 绿色填充偏移：`top: 4`（需求 8）

- `LfBandTargetGauge` 的绿色区间填充从 `Positioned(top: 0, height: 8)` 改为
  **`top: 4`**（与 16dp 容器内垂直居中的灰轨同轴：灰轨 `y 4..12`）。
  或等价改写：把灰轨与填充都放进同一 `Align(centerLeft)` 的 `Row`/`Stack` 里统一居中。
  选前者（最小改动、几何可断言）。
- **新增几何断言**（现在没有）：灰轨与绿填充的 `top` 相等（±0.5dp），
  且都相对容器垂直居中（`top == 4`）。配隔离变异（把 4 改回 0 ⇒ 必红）。

### D9 · 步数授权：设置页新增一行 + 说明弹层（需求 3）

- **新增设置行**（「数据管理」组内，`SettingRow`，Key `settings-steps-permission`）：
  - 标题「步数与身体活动」；`value` = 当前状态短词——`已授权` / `未授权` / `设备不支持` /
    `状态未知`（由 `StepsChannel.read()` 的四态映射，**不猜**：`available`→已授权、
    `denied`→未授权、`noSensor`→设备不支持、其余→状态未知）；
  - 点击 → `AppSheet` 说明弹层：「步数权限由系统管理。要取消，请在系统设置里关闭
    「身体活动」权限；取消后步数卡显示『未授权』，其余功能不受影响。」
    + 按钮「去系统设置」（`StepsRepository.openAppSettings`，跳
    `ACTION_APPLICATION_DETAILS_SETTINGS`）。
- **为什么不是应用内开关**：Android 的运行时权限**只能由用户在系统设置里撤销**，
  应用内做「取消授权」的开关只能停用**读数**、撤不掉权限本身——那会让设置页说
  「已取消」而系统里权限还在，违背诚实条款。应用内停用（隐藏步数卡）是**将来可选项**，
  本轮不做（用户没有要求「隐藏步数」）。
- 接线：`createAppRouter` 已有 `stepsRepository` 形参（`app_router.dart:90`），
  加一行传给 `SettingsPage`；未接线（null）时**不渲染该行**（与 `settings-commute-row` 同约定）。
- `docs/08` 权限说明同步补一句「取消路径：我的 → 步数与身体活动 → 去系统设置」。

### D10 · 流程：每包先 HTML 稿、渲染、评审、再原生（需求 9/10）

- 每个工作包开工前产出 `ui设计/remediation/` 下同名 HTML 稿（360dp 两屏：改前/改后或
  关键态）+ 渲染 360dp 评审 PNG + 过视觉评审（`visual-judge`），**评审通过才写原生**；
  评审意见先改稿再改码，改稿记录写进证据文件。
- 设计稿**不得**放进 `ui设计/pages/`（那个目录有 7 页 `unorderedEquals` 断言，
  被 `design_source_parity_test` 读盘对账 token）。

---

## 3. 工作包（R1 → R8，每包独立过门禁）

| 包 | 主题 | 需求 | 主要落点 | 设计稿 |
|---|---|---|---|---|
| **R1** | BMR 填充偏移修复（最小包，先行） | 8 | `lf_metric_gauge.dart` + 几何断言 + 变异 | 不需要（1 行几何修复，附 360dp 截图对比即可） |
| **R2** | 体重卡：胶囊切换 + 柱图 + y 轴 + 删三格 + 月视图修复 | 2 | `dashboard_weight_card.dart`、新 `weight_bar_chart.dart`、`weight_chart_points.dart`、`lf_segmented.dart`（删）、`trend_tile.dart`/`mini_sparkline.dart`（删） | `今日-体重卡.html` |
| **R3** | 食物库卡单行化 + 详情弹层三行对齐 + 骨架同步 | 1 | `food_card.dart`、`food_detail_sheet.dart`、`food_list_states.dart`、`food_library_view.dart`（原型）、`lf_food_kcal_ring.dart`、`lf_dimens.dart` | `食物库-单行卡与详情.html` |
| **R4** | 记录页 + 菜单页 hero 白卡化 | 4 | `nutrition_record_hero.dart`、`menu_dish_list.dart`（`_MenuHero`）、`design_card.dart`（`HeroSection` 注释） | `记录与菜单-顶部卡.html` |
| **R5** | 我的身份卡 + 训练 hero 白卡化 | 5、6 | `settings_page.dart`（`_IdentityCard`）、`training_hero.dart`、`training_page.dart`（顶部留白） | `我的与训练-顶部卡.html` |
| **R6** | 步数授权设置行 + 说明弹层 | 3 | `settings_page.dart`、`app_router.dart`、`docs/08` | 并入 R5 稿（设置页同屏）或独立 `设置-步数授权.html` |
| **R7** | 训练计划 AI/手动双模式 | 7 | `training_page.dart`（模式弹层）、新手动计划页、`app_router.dart` | `训练-计划创建双模式.html` |
| **R8** | 全局收尾 | — | docs/21 三处同步 + docs/08 + INDEX + STATUS + DECISIONS + 全量门禁 + 设备走查 | — |

**包内固定动作（每包都做）**：① 先出/更新 HTML 稿并渲染评审图；② 过视觉评审；
③ 原生实现 + 新断言（先写红再改绿）；④ 每条新断言配**隔离变异**（人为破坏 → 必须红 →
还原 → 必须绿，记录 sha256）；⑤ `tool/verify.bat` 全量门禁 EXIT=0；⑥ 更新 `STATUS.md`
的 Active Slice 与证据文件（`docs/evidence/2026-10-08-r{n}-*.md`）。

**顺序理由**：R1 是单点几何修复（最小风险、立刻可验）；R2/R3 是用户点名的两处主界面
（改动最大、依赖新件）；R4/R5 是四张卡的同一套「白卡化」语言（一起做视觉一致）；
R6 依附设置页（与 R5 同页，顺路）；R7 是新流程（依赖前几包稳定后的训练页）；
R8 收尾时统一改文档（避免中途反复改 docs/21）。

---

## 4. 设计稿与校正机制（需求 9 的细则）

1. **每包一份 HTML**，放 `ui设计/remediation/`，文件头写清「覆盖需求编号 / 裁决 / 与现状的差异」；
   含 `.screen`（360dp 帧）+ 亮/暗两套 token（沿用既有 remediation 稿的 `:root` 块）。
2. **渲染 360dp 评审图**（Chromium headless 截图，方法沿用 P5–P9 的 `_check380`/评审图流程），
   图放同目录。
3. **视觉评审**：用 `visual-judge` 子代理逐图评审（视觉资产 + 排版构图两个维度），
   返回逐图 pass/fail + 证据；fail 则改稿重渲，直到通过。
4. **评审通过后再动原生**；原生实现后**设备/模拟器 360dp 走查**复核与稿一致
   （截图归档 `docs/evidence/2026-10-08-r*/`）。
5. 稿与最终实现不一致处，**以实测为准并在证据文件里记录差异**（不悄悄漂移）。

---

## 5. 门禁与验证要求

- **每包**：`tool/verify.bat`（`flutter pub get` + `dart format` + `flutter analyze` +
  `flutter test`）EXIT=0；`dart format --set-exit-if-changed` 0 changed。
- **新断言 + 隔离变异**：每包至少 2 条隔离变异（破坏 → 红 → 还原 → 绿 + sha256 记录）。
- **测试 Key 三方对账**：`ui_spec_key_sync_test.dart` 要求 docs/21 §5 Key 表 ⇄ lib ⇄ test
  三方一致 ⇒ 删 Key（`dashboard-trend-*`）或改形态时必须**三处同改**；§5 的哨兵
  （>100 个 Key）不得跌破。
- **既有测试同步**（已实测出会红的清单，实施时逐条处理，不允许「删断言换绿」而无替代）：
  - 体重卡：`dashboard_steps_and_weight_test.dart`（分段/分箱）、`dashboard_page_v2_test.dart`
    （折线/三格）、`bento_layout_test.dart` + `dashboard_breakpoint_test.dart`（trend-* 三格）。
  - 食物库：`food_library_ui_test.dart`（骨架等高）、`food_detail_sheet_test.dart`
    （三格行 → 三行）、`nutrition_presentation_design_test.dart`（`MacroDotLine` 用法）、
    `food_library_far_jump_test.dart`（原型/行高）。
  - hero 换皮：`system_inset_test.dart`、`nutrition_subtab_position_test.dart`、
    `p6_record_page_geometry_test.dart`、`record_tab_confidence_summary_test.dart`、
    `training_page_test.dart`、`profile_identity_card_test.dart`
    —— 这些钉的是 Key/位置/文案，**换皮不动这些**，预期不红；若红说明碰到了不该碰的东西。
- **诚实边界**：本轮**不新增**任何数据源与权限；体脂率/肌肉量数据层不动（只删显示）；
  步数授权只能跳到系统设置撤销（应用内撤不掉，说明弹层如实写）。

---

## 6. 与 docs/29 的关系

`docs/29` 的 P0–P12 已全部交付、verified 并闭环。本轮是**新一轮界面重设计**：
其中 R3（食物库）覆盖 `docs/29 §P8a` 定下的「五段卡」形态（D14 的宏量三格口径
**不在卡上用了**，但 `macroGramsOnScreen` 函数与详情弹层仍用），R2 覆盖
`docs/29 §P9` 定下的折线图形态（分段控件的 Key 保留、控件换成胶囊对）。
`docs/29` 的历史记录**不改写**；形态变更全部落在 `docs/21`（UI 唯一依据）并在
`docs/DECISIONS.md` 追加 ADR。
