# 需求批次 4 审查计划（2026-10-24）

> **本文件是审查计划，不是实现。** 全部结论来自对现有代码的静态阅读（含行号）。
> 用户原话的 17 条诉求在 §2 被拆成 `R1–R17`（子项用字母后缀），每条都有：现状（代码事实）、
> 根因假设、改动面、判据、风险。§4 的 7 条裁决已于 2026-10-24 全部按推荐定稿，§5 是分批顺序。
>
> **后续文档**：审查结论与台账见 [`docs/57`](57-review-report-batch4.md)；
> 修复计划（含 RED 判据与逐条顺序）见 [`docs/58`](58-remediation-plan-batch4.md)。
> 本文件从此作为**需求规格**保留，不再随执行更新（执行结果以 57/58 为准）。

---

## 0. 定位与执行方式

**输入**：用户 2026-10-24 的一条 17 项需求（界面手感 + 两库合并后的残余 + AI 对话体验 + 训练表单）。
**产出**：本计划 →（批准后）RED 测试 → 实现 → 定向测试 → 全量门禁 → 设备实帧 → 文档同步。
**性质**：这批全是**行为/界面**改动，**不动 schema、不动 AI wire 形状、不新增第三方依赖**
（Markdown 渲染用本地最小实现，见 R13）。
**纪律**（沿用 `docs/51` §13）：
1. 每条先写会失败的断言，再改实现；不接受「改完再补测试」。
2. 不许放宽既有指标/预算，不许删断言来让门禁变绿。**退役功能的断言**走 §6 的退役台账，
   逐条写明「为什么这条断言失去对象」，与「删断言让自己变绿」严格区分。
3. 弹层一律 `useRootNavigator: true` + 弹层内 `Builder` context 取 `Navigator`
   （`extendBody: true` 的历史坑，`docs/21` §3.6）。
4. Key 变化必须同步 `docs/21` 附录 D 的 Key 表；`ui_spec_key_sync_test` 是三方对账门禁。
5. 每批一条唯一门禁标签，`changed_during_run` 必须 `[]`。

---

## 1. 基线（开工先实测一遍）

| 项 | 取值方式 | 期望 |
|---|---|---|
| 门禁 | `python E:/AI/zcode/tmp/localfit-round7-native-20261014/run.py batch4-baseline gate` | format 0（lib/test 分开）/ analyze `No issues found!` / exit 0 / `changed_during_run: []` |
| 测试总数 | 上一条日志末行 | 以实测为准（上一轮 `+2855 ~66`） |
| schema | `lib/data/database/app_database.dart` | 30（本批不改） |
| AI 命令数 | `chat_edit_registry.dart` 的 `action:` 计数 | 37（本批不改命令，只改展示与提示词文案） |
| 分层门禁 | `test/app/architecture_layering_test.dart` | 66 条跨 feature 边；本批**只允许减少**（R4 若整族退役） |
| 设备 | 自有 AVD `LocalFit_API35`（emulator-5554） | 只碰这一个 |

---

## 2. 需求 → 落点总表

| ID | 用户诉求（压缩） | 主要落点 | 性质 | 风险 |
|---|---|---|---|---|
| R1 | 饮水/步数 `n / n` 拆成上下两行，第二行右对齐，预留高度不撑卡 | `dashboard_quick_stats_row.dart` | 布局 | 中（同高契约） |
| R2 | 主页「记录晚餐」开抽屉、不跳食物库页、退出回原页 | `app_router.dart` / `dashboard_page.dart` / `nutrition_actions.dart` | 导航 | **高** |
| R3 | 食材搜索要含括号变体；按菜品要搜索框 + 餐次确认 | `meal_editor_dialog.dart` / `food_repository.dart` / `meal_entry_chooser_sheet.dart` | 检索 + 表单 | 中 |
| R4 | 记录页删「下一餐详情」入口与其内容，不留死码 | `nutrition_page.dart` / `next_meal_recommendation_page.dart` / `daily_plan/*` | 退役 | **高（级联）** |
| R5 | 「餐食已删除」提示不消失；撤销按钮看不清 | `app_snack_bar.dart` + 全部调用点 | 缺陷 | 低 |
| R6 | 引用食物库的候选卡间距太小、边缘重叠 | `food_reference_sheet.dart` | 布局 | 低 |
| R7 | 「让 AI 重新分析」「先不填」并排；底部标签删或解释 | `food_reference_sheet.dart` | 布局 + 文案 | 低 |
| R8 | 食物库卡片直接显示品牌（同名可区分） | `food_card.dart` | 信息架构 | 中（行高冻结） |
| R9 | 食物库底部「导入/管理」两条链删除 | `nutrition_tab_bodies.dart` / `food_library_footer.dart` | 退役 | 中（底栏预留） |
| R10 | 每日推荐：整套换（AI）、照片上封面、删「食堂营养更新」自动同步 | `daily_meal_set_card.dart` / `menu_dish_list.dart` / `add_canteen_dishes_to_library.dart` | 功能 + 底层联系 | **高** |
| R11 | 提取记忆要有状态；两按钮的区别/合并；结束有可见变化；历史可清 | `ai_conversation_page.dart` / `conversation_message_repository.dart` | 功能 | 中 |
| R12 | AI 创作与现有功能对不上（已删的计划仍在） | `ai_starter.dart` / `ai_workbench_prompt_templates.dart` | 契约漂移 | 中 |
| R13 | AI 输出用 Markdown 排版，约束格式 | `lf_chat_bubbles.dart` + 协议规则 | 渲染 | 中 |
| R14 | 食堂「AI 分析营养」转发的长菜品 id 不要显示 | `app_router.dart:444` / 启动提示通道 | 文案 + 通道 | 中 |
| R15 | 编辑卡不要「应用本组」，每个条目可单独应用（待应用→应用按钮） | `chat_edit_card.dart` | 交互 | 低 |
| R16 | 输入框上两个无用 chip 换成实用功能（**已裁决方案 A**） | `lf_chat_input.dart` / `ai_conversation_page.dart` | 设计 | 低 |
| R17 | 训练计划选不了天数；目标关键词选中态太浅 | `workout_plan_create_page.dart` | 缺陷 | 低 |

---

## 3. 逐条审查

### R1 饮水 / 步数卡：`n / n` 改上下两行（第二行右对齐，预留高度）

**现状（代码事实）**
- `_MetricValue`（`dashboard_quick_stats_row.dart:173–227`）用 `Wrap`（`spacing: spaceXSmall`，
  `crossAxisAlignment: end`）把「大数字 / 单位 / 小号后缀」排成一行；放不下时**整段换行**，
  且 `Wrap` 默认左对齐（`WrapAlignment.start`）——换行后第二行贴左，同时卡片被撑高。
- 水卡三态各一个 `_MetricValue`（`:276–293`）；步数卡在 `_StepsValue`（`:658–682`）。
- 两卡有「同高同构」契约：`stepsTitleRowHeight`（`:591` 附近注释）就是为了钉住卡高，
  未授权/有数据两种态曾经差 2px 被抓过。

**根因**：目标段是「同行可换行」的弹性布局，而不是「固定两行、第二行右对齐」。
数字变长（`100,000` / 大字号）时换行位置与行数都不稳定 ⇒ 卡高不稳定。

**改动面（只 1 个文件）**
1. `_MetricValue` 增加「两行」形态：`Column(crossAxisAlignment: stretch)` →
   - 第一行 `Row(mainAxisSize: min)`：`value`(displayLarge) + `unit`(caption)；
   - 第二行：`Align(alignment: Alignment.centerRight)` 包 `suffix`(caption)，
     `maxLines: 1` + `ellipsis`（超长先省略，不换行、不撑高）。
2. **预留高度**：`suffix == null` 时也渲染同高的空槽（`SizedBox(height: captionLineHeight)`），
   让「未设目标 / 暂无记录」与「有目标」三态卡高一致。这是用户「提前撑开、留足空白」的字面落点。
3. 水卡「未设目标」分支（`:281–286`，`unit: 'ml'` 无 suffix）保留单位在首行，第二行留空槽。

**判据（RED 先行）**
- 新增 `test/features/dashboard/quick_stats_two_line_test.dart`：
  - 三个数字长度（`750`、`12,345`、`123,456`）× 两卡：卡高**逐个相等**（`getSize` 比对，容差 0.5）；
  - `dashboard-water-target-inline` / `dashboard-steps-target-inline` 的**右边缘**与卡内容右边缘
    差 ≤ 1dp（右对齐几何断言）；
  - 目标数字最长时该 `Text` 仍 `findsOneWidget` 且不溢出（`tester.takeException()` 为 null）。
- 既有断言 `dashboard_steps_and_weight_test.dart:382`、`round7_dashboard_today_test.dart:391`、
  `dashboard_page_v2_test.dart:468` 检查的是**文案内容**（`'/ 10,000 步'`），两行化不改文案 ⇒ 应保持绿。

**风险**：`_MetricValue` 有 4 个调用点，两行化会改变水/步两卡的内部结构；`two_point_zero_ui_audit_test`
里可能有用例按 `Wrap` 定位 —— 实现时先跑这三份 dashboard 测试确认无 `byType(Wrap)` 依赖。

---

### R2 主页「记录晚餐」：抽屉开在原页，不跳食物库

**现状（代码事实）**
- 卡上按钮 `cta-log-dinner` → `dashboard_page.dart:385–387` → `onLogMeal(MealSlot.dinner)`；
- 路由实现（`app_router.dart:427–429`）：
  ```dart
  onLogMeal: (slot) {
    mealAddIntent.request(slot: slot);
    GoRouter.of(context).go(AppRoutes.nutrition);   // ← 就是这次跳转
  },
  ```
- `MealAddIntent`（`nutrition_intents.dart`）被 `NutritionPage._onMealAddRequest`（`nutrition_page.dart:191–197`）
  消费，`chooseRecordEntry`（`nutrition_actions.dart:58–70`）先弹「按食材/按菜品」，再 `AppSheet` 开编辑弹层。

**根因**：入口的**拥有者**选错了。抽屉归饮食页的动作层，但意图通道的实现方式是「先切页、再由目标页开层」。
用户看到的「跳到食物库」= 底栏切到「饮食」且该页当前停在第二个 tab（食物库）。退出弹层自然回到饮食页，
不是回到今日页。

**改动面（推荐方案 B）**
- 新增 `lib/features/nutrition/presentation/meal_record_launcher.dart`：
  一个不依赖页面状态的函数 `Future<void> openMealRecordSheet(BuildContext rootContext, {MealSlot? slot, required FoodRepository foods, required MealRepository meals, required DishLibraryRepository? dishes, required AddDishToMeal? addDish})`，
  内部就是 `chooseRecordEntry` 的那段流程（复用 `NutritionActions` 需要 `BuildContext`+`selectedDate`，
  所以抽成独立 launcher 而不是再造一份写逻辑）。
- `app_router.dart` 的 `onLogMeal` 改为：用 **shell 的 context**（builder 里已能拿到）直接 `await openMealRecordSheet(...)`，
  **不再 `GoRouter.go`**；`mealAddIntent` 只留给「跨页一次性的其他入口」（若无人使用则随 R2 一并删除）。
- `DashboardPage` 的 `onLogMeal` 签名不变（`ValueChanged<MealSlot?>`），所以卡片与测试不受牵连。

**判据（RED 先行）**
- `test/features/dashboard/dashboard_meal_sheet_test.dart`：
  1. 点 `cta-log-dinner` → `meal-entry-chooser` 出现，且 `nutrition-tab-menu` / `nutrition-tab-record`
     的 `Semantics.selected` **均为 false**（底栏没被点亮）；
  2. 继续「按食材」→ `meal-food-search` 出现；
  3. 关掉弹层（取消）→ `dashboard-next-meal` 仍在，`nutrition-record-week-strip` 不存在。
- 反向断言：`mealAddIntent.value == null`（没有留下一次性请求，避免下次进饮食页「诈尸」弹框）。

**风险**：launcher 需要 `DishLibraryRepository` + `AddDishToMeal` —— 这两者在 `app_router.dart` 已经是入参（`:142`、`:468`），
只需传进 `onLogMeal` 闭包，不改 `DashboardPage` 的构造。分层：`dashboard -> nutrition` 边已冻结存在（layering 第 57 行），不新增边。

---

### R3 记一餐抽屉：食材搜索覆盖括号变体；菜品要搜索 + 餐次确认

**现状（代码事实）**
- 食材搜索：`MealEditorDialog._onQueryChanged` 调 `foodRepository.search(value, limit: 10)`；
  `FoodRepository.page`（`food_repository.dart:59–99`）是 `name LIKE '%q%'`，
  排序 = `isUserCreated desc → 精确同名 desc → instr(name,q) asc → length(name) asc → name → id`。
- 实测（用随包 CSV 复算）：「鸡蛋」命中 **154 条**，`鸡蛋（熟）` 按现排序排在**第 32 位**，
  而结果区只取 **10 条** ⇒ 用户永远看不到它。**匹配是对的，排序 + 上限把它藏了**。
- 品牌不参与检索：`page` 只 `like(name)`，搜「千丰香米」搜不到「米饭」（同一族的可发现性缺陷）。
- 按菜品：`DishMealPickerDialog`（`meal_entry_chooser_sheet.dart:107–201`）是**无搜索的整表列表**；
  `DishMealConfirmSheet`（`:204–277`）把 `dish.mealSlot` 当**只读文案**显示，用户无法改餐次
  （`recordByDish` 里的 `slotOverride` 只吃页面传进来的 `initialSlot`）。

**改动面**
1. `FoodRepository.page` 排序**加一层**「括号前主名」优先：
   `ORDER BY (主名 == q) DESC, 主名长度 ASC, ...` 其中主名 = `substr(name, 1, instr(name,'（')-1)`（无括号时即整名）。
   实现用 drift 的 `CustomExpression`/`FunctionCallExpression`；**不新增列、不加索引**。
2. 结果上限 10 → 20（`_resultsHeight` 仍 168dp，内部滚动，不撑弹层），并在列表底部给一行
   「还有 N 条，输入更精确的名称」（`searchCount` 已有 `count()` 能力，或直接以「取到 20 条即视为还有」）。
3. 品牌参与检索：`page` 的 where 改为 `name LIKE q OR brand LIKE q`（`Foods.brand` 已存在）；
   排序里品牌命中排在同名之后。**这条与 R8 是同一族问题的两半**（卡片显示品牌 + 检索命中品牌）。
4. `DishMealPickerDialog`：顶部加 `LfSearchField`（`fieldKey: Key('dish-meal-picker-search')`），
   过滤逻辑与食材侧同口径（走 `normalizeSearchText` 包含匹配，纯本地 `where`，弹层已拿到全量 list）；
   空结果给「没有匹配的菜品，换个词」；`dishes` 仍由调用方读好传入（弹层不查库的既有约束不变）。
5. `DishMealConfirmSheet`：把只读餐次换成四枚胶囊（复用 `MealEditorDialog._SlotPill` 的形态，
   `Key('dish-meal-slot-<storedValue>')`），返回值从 `bool` 改为 `MealSlot`（null = 取消）；
   `recordByDish` 用返回的 slot 作为 `slotOverride`（**用户点的餐次优先于菜品库存档**，与 D9 同一口径）。

**判据（RED 先行）**
- `test/features/nutrition/meal_food_search_test.dart`：
  1. 库内插 `鸡蛋`、`鸡蛋仔`、`鸡蛋（熟）`、`鸡蛋清（代表值；生）`；输入「鸡蛋」→
     `鸡蛋（熟）` **必须**出现在前 3 行（现应为红：它排第 4 之外）；
  2. 插 `米饭` + 品牌 `千丰香米`；输入「千丰香米」→ 命中该行（现应为红）；
- `test/features/nutrition/dish_meal_picker_test.dart`：
  3. 输入「番茄」→ 只剩番茄类（不再整表）；空结果给空态文案；
  4. 点菜品 → 确认层出现 4 枚餐次胶囊，选「晚餐」→ `onAddDishToMeal` 的 `slotOverride == MealSlot.dinner`。
- 既有 `nutrition_presentation_design_test.dart:611` 用「鸡蛋」断言 `139 kcal / 100g` 可见 ——
  排序改动后该行的**行位**可能变，但仍在首 10 内（`鸡蛋干` 类短名不会被挤掉？需实测；若变红，
  改成用 `find.descendant` 在结果区内断言该行存在，而不是「首屏可见」）。

**风险**：`LIKE` 加 `OR brand` 会让 23,919 行的全表扫描慢一点（已无索引，现也是全扫），
`test/features/nutrition/query_benchmark_test.dart` 有实测护栏，必须复跑；若 p95 劣化 >10%，改为
「先按 name 查，无命中再按 brand 查」的两段式（同一函数内）。

---

### R4 记录页删「下一餐详情」入口与内容

**现状（代码事实）**
- 入口：`nutrition_page.dart:360–367` 给 `RecordTab.leading` 传 `NextMealEntryCard`（仅「今天」渲染）；
- 二级页：`next_meal_recommendation_page.dart` = `NextMealRecommendationPage` + `NextMealEntryCard._open`；
- 其内容：`sections/next_meal_decision_section.dart` → `NextMealDecisionCard`（`daily_plan/presentation/`）；
- 数据链：`NextMealDecisionController`（`main.dart:456`）→ `DailyPlanEngine`（`main.dart:458`）→ `daily_plans/slots/candidates` 三表；
- 引用面：`canteen_directory_page.dart` 的 `decisionController`/`mealRepository` 两个形参**已是死参数**
  （`:45–46` 注释自认「形参保留、不再消费」）。
- 测试引用：`secondary_entry_reachability_test.dart:176–185`、`two_point_zero_ui_audit_test.dart:328/498`、
  `next_meal_decision_wiring_test.dart:148`、`next_meal_slot_progression_test.dart`、`daily_plan_engine_test.dart`、
  `next_meal_decision_card_test.dart`、`round9_canteen_capture_test.dart:168`、`secondary_page_occlusion_test.dart:86`、
  `review_p2_batch_b_test.dart:99`、`nutrition_menu_tab_integration_test.dart:77`（仅注释）。

**根因**：这是**上一轮的产品级功能**（「下一餐吃什么」决策卡），用户现在判定其内容无用。
删掉入口后，页面 → 卡 → 控制器 → 引擎 → 三张表读路径会依次变成零调用，属于典型「删一半留一半」。

**改动面（两个选项，见 §4 D1）**
- **方案 A（推荐，整族退役）**：
  1. 删 `leading` 传参（`nutrition_page.dart`）与 `NextMealEntryCard` / `NextMealRecommendationPage`；
  2. 删 `sections/next_meal_decision_section.dart`、`daily_plan/presentation/next_meal_decision_card.dart`、
     `daily_plan/presentation/next_meal_facts_row.dart`；
  3. 删 `NextMealDecisionController` + `main.dart`/`localfit_app.dart`/`app_router.dart` 的装配与透传；
  4. `DailyPlanEngine`：`confirmCandidate` 随控制器消失；引擎本体若零调用则一并退役，
     `daily_plans/slots/candidates` 三表**保留不删**（schema 冻结，写退役横幅，留将来复用/备份兼容）；
  5. `canteen_directory_page.dart` 两个死形参删除；
  6. 测试退役台账见 §6。
- **方案 B（只删 UI）**：只删入口 + 二级页 + section/card，保留 controller/engine（内存里仍有装配但那两处已无 UI），
  **会留下无法触达的活代码**，与用户「保证不留死代码」直接冲突 ⇒ 不推荐。

**判据（RED 先行）**
- 先写 `test/features/nutrition/record_tab_no_next_meal_entry_test.dart`：
  `find.byKey('nutrition-record-next-meal-entry')` 为 `findsNothing`、`find.text('下一餐详情')` 为 `findsNothing`；
  同日 `record_tab` 其余卡（趋势/周条/餐卡/FAB）都在位。
- 退役后跑 `flutter analyze`：不得出现「未使用 import/字段」；再跑一次全仓 `grep` 兜底
  （`next-meal`、`NextMeal`、`DailyPlanEngine`、`decisionController`）只应剩注释/历史文档。
- 分层门禁：跨 feature 边只允许**减少**（删除 `nutrition->daily_plan` 这一条后，冻结表同步收窄）。

**风险**：删 `DailyPlanEngine` 会同时删掉 `constraints.set` 的**唯一活跃读取者**（`docs/43` 记过这条），
`PlanningConstraintsRepository` 会变成「只写不读」。处理：`memory_promotion.dart` 与 AI 记忆页仍在写约束，
读取者消失属于**功能性倒退**——所以方案 A 里保留 `PlanningConstraintsRepository` 与写入路径，
只在文档登记「当前无本地读取者」。这一条必须在计划里写明，不能悄悄做成「约束不再生效」。

---

### R5 「餐食已删除」不消失 + 撤销按钮看不清

**现状（代码事实）——根因已确认**
- Flutter SDK `SnackBar`（`/e/AI/toolchains/flutter/packages/flutter/lib/src/material/snack_bar.dart:303`）：
  ```dart
  persist = persist ?? action != null;
  ```
  **只要带 `action`，默认就永不过期**。`AppSnackBar.showOn`（`app_snack_bar.dart:45–75`）给删除流传了
  `actionLabel: '撤销'`（`nutrition_actions.dart:190–201`、`:221–232`）且**没有传 `persist`**
  ⇒ 删除提示条永远挂在屏上，直到下一条 `clearSnackBars()` 把它顶掉。
- 对比度实测：`snackBarTheme`（`app_theme.dart:293–300`）没有 `actionTextColor`/`actionTextStyle`，
  动作色走 `ColorScheme.secondary`（= `lf.primary`）：亮色 `#2FBE8F` on `#1A201D` = **7.0:1**，
  暗色 `#4ED9A6` on `#171E1A` = **9.5:1**。数字上过 4.5，但动作文字只有 `caption` 档、无字重，
  且与全局强调色同色系 ⇒ 在墨绿底上「不够跳」。用户说的是**视觉可读性**，不是合规性。

**改动面**
1. `AppSnackBar.show/showOn` 增加 `bool persist = false`，并在构造 `SnackBar` 时显式 `persist: persist`
   （注释写明 SDK 默认值陷阱 + 为什么必须显式传）。
2. `snackBarTheme` 增加：
   `actionTextColor: LfColors.mint(brightness).tone(300)`（亮 `#7FD9BC`，对比 9.9）或等价 token，
   `actionTextStyle: LfText.captionStrong.copyWith(...)` + `actionOverflowThreshold: 0.4`。
3. **同类问题全查**：`grep -rn "actionLabel"` 全部调用点逐条确认 `persist: false`；
   `ai_memory_page.dart:1031–1032` 里那条**裸 `SnackBar`** 改用 `AppSnackBar`（唯一绕开统一出口的地方）。
4. 4 秒（默认）对「撤销」是否够：删除是破坏性操作，建议删除族传 `duration: 6s`（显式，不是全局放宽）。

**判据（RED 先行）**
- `test/app/design/app_snack_bar_test.dart` 新增：
  1. `showOn(..., actionLabel: '撤销')` 后 `pump(Duration(seconds: 5))` → `find.byType(SnackBar)` 为 **findsNothing**
     （现应为红：`persist` 默认 true）；
  2. 带 action 时 `SnackBar.persist == false`（直接读 widget 字段，钉住「显式传参」）；
  3. 主题层断言：`snackBarTheme.actionTextColor` 非空、`actionTextStyle.fontWeight == w600`；
  4. 对比度单测（纯函数）：动作色 vs `snackBarBackground` ≥ 4.5（亮/暗两态）。
- 设备帧：删除一餐 → 提示条 6 秒后自动消失；撤销按钮可读（截图进证据目录）。

**风险**：`persist: false` 会让「撤销」有超时 —— 这是用户要的（提示该消失），且撤销本身不是唯一恢复路径
（餐食删除后可重新记录）。若担心误触，时长给 6s 而不是 4s。

---

### R6 引用食物库候选卡：间距太小、边缘重叠

**现状**：`food_reference_sheet.dart:96–110` 把候选塞进 `Column`，`_CandidateRow`（`:163–220`）
自带 `padding: 8` + `border: 1` + `radiusMd`，**相邻行之间零间距** ⇒ 两个 1px 描边直接贴在一起，
视觉上像共享一条边（「边缘重叠」）。8dp 内衬在大字号下也偏挤。

**改动面**：候选列表改 `ListView.separated` 或 `Column` 里插 `SizedBox(height: spaceSmall)`（8dp）；
内衬 8 → `spaceMedium`(12)；选中态描边 1.5 保留。
**判据**：新增几何测试 —— 相邻两个 `food-reference-candidate-*` 的矩形之间 gap ≥ 8dp；
选中态与未选中态高度一致（不因描边变粗而跳）。既有 `key_contract_test.dart:110–116` 只查存在性，不受影响。
**风险**：低。弹层是 `showCustom` + `Flexible + SingleChildScrollView`，插间距不会溢出。

---

### R7 「让 AI 重新分析 / 先不填」并排；底部标签处置

**现状**：
- 两枚动作是**上下堆叠的整宽** `LfTextButton`（`food_reference_sheet.dart:120–135`），占两行高度；
  「引用食物库营养」是上面的 `LfPrimaryButton`。
- 底部有 `LfSourceBadgePair.forCanteenOrigin('food_library', keyPrefix: 'food-reference')`
  → 渲染成两枚徽标：**「食堂菜」+「食物库」**（`source_badge.dart:120–127`），
  外加一行「匹配分 0.95 · 精确同名，建议引用」（`:139–146`）。
  这两枚徽标在**建菜/改名**语境里没有信息量（菜还没营养，来源尚未确定），用户判定无用。

**改动面**
1. 动作区改为：`Row(children: [Expanded(LfTextButton('让 AI 重新分析')), SizedBox(width: 8), Expanded(LfTextButton('先不填'))])`，
   主按钮「引用食物库营养」保持整宽在上一行。窄屏 + 2.0× 时改 `Wrap`（两个 `Expanded` 会挤字）。
2. 删 `food-reference-source` / `food-reference-evidence` 两枚徽标；把「匹配分」行改成一句人话：
   「按名称匹配到的候选；点哪条就用它的每 100g 数据」+ 精确/模糊两种文案（保留 `recommendAdopt` 的判断，只改呈现）。
3. 同步 `docs/21` 附录 D（`food-reference-source`/`-evidence` 标为退役）+ `key_contract_test.dart:114–116`（见 §6 台账）。

**判据**：`test/features/campus_menus/food_reference_sheet_test.dart` 新增：
两枚按钮**同一行**（`getTopLeft().dy` 相等，`getTopLeft().dx` 递增）；`food-reference-sheet` 内
`find.text('食堂菜')` 为 `findsNothing`；三个动作 Key 全部仍在。
**风险**：删徽标会让「来源+证据永远可见」这条铁律在这个弹层缺席——但此处**还没有来源事实**（弹层是决策前），
文档里写清这条例外，避免下次审查当缺陷报回来。

---

### R8 食物库卡片直接显示品牌

**现状**：`FoodCard`（`food_card.dart:126–200`）在 2026-10-08 的「单行三件」改造里
**把品牌行整条删掉**（`:67–92` 注释自认「品牌退到详情弹层」），`brand` 参数保留但卡面不用。
列表里 `米饭 × 4`（无品牌 / 叮咚 / 松屋 / 千丰香米）长得几乎一样 ⇒ 只能点进去才分辨。
`FoodSearchTab` 已经把 `brand: food.brand` 传进去了（`:131`），浪费了这个事实。

**改动面（不破行高）**
1. 名称行改为「主名 + ` · 品牌`」内联：主名 `Flexible` + ellipsis，品牌 `LfText.micro` +
   `mutedForeground`，**同一行**、不加行高（`:56` 契约：行高 56 由 40 图标 + 上下 8 决定）。
2. 品牌来源双轨：`brand` 列优先；为空时用 `splitFoodName(name).brand`（种子库里品牌常写在名称头部）。
3. `Semantics` label 补品牌（记餐结果行已有这条口径：`添加 米饭（千丰香米）`，列表行尚未补）。
4. 详情弹层已有品牌（`food_detail_sheet.dart:183`），不动。

**判据**：`test/features/nutrition/food_card_brand_test.dart`：
同名不同品牌两行渲染出**不同**的可读文本（`find.textContaining('千丰香米')`）；
两行 `getSize().height` 相等且 == 56（±0.5）；2.0× 字号下不溢出（`takeException()` null）；
语义 label 含品牌。
**风险**：行宽变紧（40 图标 + 名称 + 品牌 + 36 环），长名会被更早省略 —— 用「品牌优先保留、名称省略」
还是「名称优先」需要定：推荐**名称优先省略，品牌跟随省略**（品牌是补充信息），并在测试里钉住
「2.0× 下不溢出」而不是钉「品牌一定完整可见」。

---

### R9 食物库底部两条链删除

**现状**：`NutritionFoodLibraryTabBody`（`nutrition_tab_bodies.dart:66–80`）在 `Expanded(body)` 下挂
`FoodLibraryFooter`（`food_library_footer.dart:31–96`）＝「导入食物数据 / 食物管理」贴底条。
**它还承担底栏预留**：`LfInsets.navReserve(context)` 由页尾条自己给，列表末端因此不再预留
（`food_library_view.dart:283` 注释明说）。设置页已有同一入口（`settings_page.dart:749`「添加食物数据」）。
- 相关测试：`round7_foodlib_footer_capture_test.dart`、`food_library_footer_test.dart`、
  `food_library_reactivity_test.dart:162/199`、`nutrition_subtab_occlusion_test.dart:321–341`。

**改动面**
1. `nutrition_tab_bodies.dart` 删掉 `FoodLibraryFooter` 与其两个回调入参；
2. **把底栏预留搬到列表**：`FoodLibraryView` 末尾加无子节点的 `SliverPadding(bottom: navReserve)`，
   `FoodSearchTab` 同理（旧搜索路径）；漏这步 = 最后一行被底栏压住（`nutrition_subtab_occlusion_test` 会红）；
3. 删 `sections/food_library_footer.dart` 文件本身；`NutritionPage._foodBody` 的
   `onImportFoods/onManageFoods` 传参一并删；
4. `food_library_results.dart:99–113` 的**空态**「导入食物数据」保留（空库时唯一自助路径，不在页尾）；
5. `docs/21` §5.3 的页尾条与 D44 段落改写为「已退役，入口在设置页」。

**判据**：新增 `test/features/nutrition/food_library_no_footer_test.dart`：
`food-library-footer` / `-import` / `-manage` 全为 `findsNothing`；滚动到列表末尾最后一行底边
≥ 底栏遮挡线（复用 `nutrition_subtab_occlusion_test` 的量法）；设置页 `settings-food-data` 仍在。
**风险**：中 —— 底栏预留是「改了就看不出来、但最后一行点不到」的隐蔽坑，必须有几何断言。

---

### R10 每日菜品推荐：整套换（AI）、照片上封面、删「食堂营养更新」

三个子项，根因各不相同。

**R10-a 不要每卡「换一个」，要一套全换（由 AI 分析）**
- 现状：`DailyMealSetCard._MealSection` 每段一枚 `nutrition-menu-meal-<slot>-swap`（`daily_meal_set_card.dart:228–236`），
  点一下 `_swap`（`menu_dish_list.dart:627–660`）在**本地候选榜**里循环 + 记一次 `dislike`。三格各自独立，
  换完之后整套可能营养失衡（这是用户不满的实质：单格换破坏了「一整套」的一致性）。
- 改法：
  1. 删三段各自的「换一个」按钮（`-swap` Key 退役）；`_swapOffset`/`_swap`/`_showCandidates` 里的候选切换保留给
     「查看候选 N 道」（用户仍可指定某餐吃哪道）。
  2. 卡头加一枚 `nutrition-menu-daily-set-repick`「换一整套（AI）」：
     - 已配置 AI：写 `aiStarterRequest`（带上今日已吃、目标区间、本地菜池摘要与忌口），`go(aiChat)`，
       AI 用 `meal.create` 逐餐提议 → 编辑卡逐条应用（走既有 chat-edit 通道，不新增写路径）；
     - 未配置 AI：**不隐藏按钮**，点击给一句实话「AI 未配置；已按本地规则重排一整套」并走
       本地 `buildDailyMealRecommendation` 的另一种子重算（备选见 §4 D3）。
  3. 卡头文案由「同一道菜不跨餐重复」扩一句「换就整整齐齐换一套」。

**R10-b 有照片的要把照片放封面**
- 现状：`DishCard._PhotoHeader`（`dish_card.dart:300–340`）**已经**是 4:3 封面 + `Image.file`；
  菜单卡上看不到照片的真正原因是**数据没传**：`AddCanteenDishesToLibrary.run` 构造 `DishDraft`
  （`add_canteen_dishes_to_library.dart:105–124`）**没有 `imagePath:`** ⇒ 菜品库行 `imagePath` 恒为 null，
  卡上永远走渐变占位。
- 改法：`DishDraft(imagePath: dish.imagePath, ...)`；`_updated` 已透传 `draft.imagePath`（`dish_library_repository.dart:241`），
  菜换照片（`CanteenRepository.updateDish` 的钩子）也会同步过来。
- 判据：`canteen_dish_library_sync_test.dart` 加一条「食堂菜带照片 → 菜品库行 imagePath 相同 → `DishCard` 出现 `Image.file`」。

**R10-c 删「食堂营养更新」——两库已合并，应自动同步**
- 现状：`DishCard` 画陈旧角标 + 「同步」（`dish_card.dart:72–84`），数据由
  `MenuDishList._refreshStaleness`/`DishStalenessChecker`（`dish_staleness.dart`）算，
  动作走 `DishSourceSync.apply`（**拒绝覆盖 `userEdited` 行**）。
- 事实核对：2026-10-24 的自动同步（`CanteenRepository` 的 `onDishUpserted` → `AddCanteenDishesToLibrary.syncDish`）
  已经覆盖建菜/改名/换照片/写营养/删菜六条写路径 ⇒ 正常路径下**陈旧状态不可能出现**；
  唯一还能出现的是「用户手改过营养」的行（`_updated` 里 `userEdited` 保留，营养会被来源覆盖 —— 见风险）。
- 改法：
  1. `MenuDishList` 删陈旧计算、`_syncDish`、`onSync` 传参；`DishCard` 删 `staleness`/`onSync` 两个参数与角标；
  2. `dish_staleness.dart` + `dish_source_sync.dart` 是否一并退役见 §4 D2（推荐：**退役**，
     因为「提示 + 手动同步」这套交互已被自动同步取代；保留 = 死代码）；
  3. `userEdited` 行的策略：自动同步**跳过**用户手改行（不静默覆盖用户的数字），并在
     `docs/40 §6` 写明「手改即冻结，来源变化不再覆盖；用户可在食堂目录改回」。
- 判据：新增 `canteen_dish_library_sync_test` 用例 —— 用户手改营养后，食堂侧再写营养 →
  菜品库行**仍是用户的值**（RED 前应为「被覆盖」）；UI 侧 `find.text('食堂营养更新')` 为 `findsNothing`。

**R10 风险汇总**：R10-c 是本批唯一可能「改坏数据语义」的一条（静默覆盖用户输入）；
`DishSourceSync`/`DishStaleness` 退役会带走 3 份测试（`dish_source_sync_test`、`data_model_p2_test` 的 4 个用例、
`menu_staleness_ui_test`），全部进 §6 台账。

---

### R11 AI 对话：提炼状态、两按钮关系、结束的可见变化、清空历史

**现状（代码事实）**
- `_extractMemories`（`ai_conversation_page.dart:631–707`）：有 `_extractingMemory` 标志，但**只用来挡重复点击**，
  屏上没有任何进行中提示（要等结果才弹 snackbar）；耗时可能几十秒，用户会以为没反应。
- 两个按钮语义**确实不同**：
  | | 触发 | 门槛 | 落点 | 是否需设置 |
  |---|---|---|---|---|
  | `ai-chat-extract-memory`「从对话提炼记忆」 | 立即、同步 | 消息 ≥1 | 弹候选层，**点保存即写库** | 不需要 |
  | `ai-chat-end-session`「结束本次会话」 | 入队 `BackgroundJob` | ≥6 条 | 记忆页「待确认」，**确认才写** | 需「自动提炼」开关（默认关） |
- 结束对话**没有任何界面变化**：只有一个 snackbar（`result.message`），对话继续、历史不动。
- 历史清空**没有 API**：`ConversationMessageRepository` 只有 `loadRecent` / `save`（`conversation_message_repository.dart`）。

**改动面**
1. **提炼状态**：`_extractingMemory` 时把顶栏那枚 `LfIconButton` 换成 16dp `CircularProgressIndicator`
   + `Semantics(label: '正在提炼记忆')`，并在消息区顶部插一条非消息的忙态行
   （`ai-chat-extracting`，文案「正在从这段对话提炼记忆…」）；点它给「正在提炼，请稍候」。
2. **合并两个动作**（§4 D4 裁决）：推荐合并为**一个** `ai-chat-end-session`「结束本次对话」：
   1. 若回复中先 `cancel()`（沿用现有）；
   2. 不足 6 条 → 如实提示（沿用）；
   3. 走**同步候选层**（复用 `_showMemoryCandidateSheet`），保存即写——不再依赖「自动提炼」开关；
   4. 写会话边界 KV `ai_chat_session_ended_at` + 在消息列表尾部画一条分隔线
      「本次对话已结束 · HH:mm」，输入框占位改为「开始新对话…」；
   5. 双击幂等（同一 `conversationId` 已结束则只提示「本次对话已结束」）。
   「自动提炼」开关降级为**后台自动跑**的开关（不改记忆页的待确认队列），保留 `MemoryExtractionQueue` 代码。
3. **清空历史**：`ConversationMessageRepository` 新增 `Future<int> clear({String sessionId})`（返回删除条数）
   + Drift 实现（`delete(conversationMessages)..where(sessionId)`）；
   图片文件的清理走 `FileChatImageStore.clearAll()`（聊天副本本来就是「随清全清」语义）；
   UI 入口放在顶栏溢出菜单或设置页「清除聊天记录」——**二次确认** + 「已清除 N 条」如实报数。
   控制器侧新增 `clearHistory()`：先 `cancel()`/清 suggestions，再清内存消息，最后 `loadHistory()`。
4. 同步 `docs/21` §5.7/§5.8 的 Key 表（新增 `ai-chat-extracting`、`ai-chat-session-ended`、`ai-chat-clear-history`）。

**判据（RED 先行）**
- `test/features/ai_conversation/memory_extract_state_test.dart`：点提炼 → 立刻出现 `ai-chat-extracting`，
  service 完成前一直存在，完成后消失（用可控 `Completer` 的假 service）。
- `test/features/ai_conversation/end_session_visible_test.dart`：≥6 条后点结束 → `ai-chat-session-ended` 出现、
  输入框 hint 变化、再次点击不重复入队。
- `test/features/ai_conversation/clear_history_test.dart`：清空 → `loadRecent` 为空、DB 行数 0、
  图片目录清空、界面回欢迎区；取消确认 → 一条不少。
**风险**：清历史是**不可逆破坏性操作**（确认框 + 报数兜底）；合并两按钮会改变「自动提炼」开关的作用域，
必须在文档与设置页副标题里写清，否则下次会被当成回归。

---

### R12 AI 创作与现有功能的缺口

**现状（代码事实）——已确认一处真缺口**
- `aiStarters` 六卡（`ai_starter.dart:60–110`）。其中 `daily-menu-plan`「生成今日吃法」的启动提示词是
  「按我的目标和今天已吃的，帮我搭配今天剩下几餐」→ 走对话；而注册在 `promptCatalog` 的
  `dailyMenuPlanPromptTemplate`（`ai_workbench_prompt_templates.dart:58–81`）仍要求模型返回
  **`daily-menu-plan v1` JSON**（`schema_version`/`slots`/`candidate_ids`…）。
  该契约的解码器已在 `RV2-P2-01` **整族退役**（见 `docs/52`/`STATUS.md` 横幅）⇒ 这条模板现在是
  「要求模型输出一个 App 已经不能解析的形状」的孤本。
- 其余五卡描述与现行能力一致（`menu-normalize`→`canteen.*`、`dish-nutrition`→`canteen.dish.nutrition`、
  `dish-guidance`/`meal-pairing`→纯文本、`workout-plan`→`workout.plan.create`）。
- 旧「食谱/计划」字样在 UI 上已清（`ai_conversation_page.dart:877–879` 只剩注释），未发现残留入口。

**改动面**
1. `_dailyMenuPlanPrompt` 改成 chat-edit 口径：明确「用 `meal.create` 逐餐提议，reply 里说清每餐选了什么、为什么」，
   不再提 JSON schema；
2. `dailyMenuPlanPromptTemplate`：若无人消费（`grep` 只有 `main.dart:225` 注册与测试引用）→ 从 `promptCatalog` 摘除
   + 文件里加退役横幅（不物理删，egress 评测集里还引用正文）；若 egress 测试需要它，保留文件但不注册；
3. 逐卡核对「描述里承诺的动作」在 `chat_edit_registry` 里都有对应 action（一张对照表进证据目录）；
4. 顺带把「能力清单」对齐：`targets.update`（饮水/步数目标）与记忆类动作目前没有任何卡的引导语提及，
   可在 `daily-menu-plan`/新卡描述里补一句（不新增卡，避免超过 6 张的设计约束）。

**判据**：`test/features/ai_workbench/ai_starter_contract_test.dart`：
每张卡的 `promptBuilder('x')` 里**不得出现** `schema_version` / `v1 JSON` / `candidate_ids` 等已退役词；
`aiStarters` 的每个 `id` 都能在 `chat_edit_registry` 或纯文本能力里找到落点（表驱动断言）。
**风险**：改提示词 = 改 AI 行为，属于「行为变化但无 wire 变化」；真实模型验证受凭据限制（见 §7）。

---

### R13 AI 输出 Markdown 排版

**现状**：`AiMessageBubble`（`lf_chat_bubbles.dart:62–100`）就是一个 `Text(text)`；
模型输出的 `**加粗**`、`- 列表`、`1.` 编号、``` 代码块全部**原样带星号**显示 ——
这就是用户说的「乱七八糟堆成一堆」。协议层（`chat_edit_registry` 规则 1）只约束**信封**那一支，
纯文本支没有任何格式约束。

**改动面**
1. **本地最小渲染器**（不新增依赖）：`lib/app/design/widgets/lf_markdown.dart`
   - 支持：`#`/`##` 标题（映射 LfText.title/captionStrong）、无序列表（`- `/`* `）、有序列表（`1. `）、
   - 行内 `**粗**`/`*斜*`/`` `代码` ``、块引用 `> `、``` 围栏（等宽 + muted 底 + 横向滚动）​、分隔线 `---`；
   - **不支持**：表格、图片、链接跳转（链接降级为文字 + 下划线，不打开外部浏览器 —— 隐私口径）；
   - 段落间距 `spaceSmall`；列表项缩进 2 空格；单条消息最多渲染 200 行（超出折叠「展开全部」）。
2. `AiMessageBubble` 增加 `markdown: bool = true`（图片/语音消息走原 `Text`）；
   编辑卡的 reply 气泡同样走渲染器。
3. **协议约束**（`chat_edit_registry` 新增规则 14）：「reply 用 Markdown：短段落（≤3 行）、列表 ≤6 项、
   不用表格/图片/链接/HTML；不要用一级标题」。这样渲染器的能力边界与模型的输出面一致。
4. 与 `replyTextForDisplay`（清洗内部引用）串联：**先清洗，再渲染**（顺序写进代码注释与测试）。

**判据**：`test/app/design/lf_markdown_test.dart`：每种语法一段 → 对应 widget 形态（粗体 `TextSpan.fontWeight`、
列表项数量、代码块 `SelectableText`/等宽字体）；`**x**` 不再以星号出现在屏幕上；
`chat_reply_display_test` 顺序用例（含 `[canteen-dish:abc]` 的文本 → 渲染后不含该串）。
**风险**：自写渲染器是解析器，容易被畸形输入（未闭合 `**`、超长行）打穿 —— 全部用「容错降级为纯文本」
而不是抛异常；再加一条 fuzz 式测试（随机拼接 50 段）。

---

### R14 食堂「AI 分析营养」转发的长菜品 id

**现状**：`app_router.dart:444–460` 把菜名拼成
```
[canteen-dish:mx-3] 番茄炒蛋
[canteen-dish:mx-7] 宫保鸡丁
```
写进 `aiStarterRequest`，随后 `_sendCurrent` 原样作为**用户消息**发送 ⇒ 聊天气泡里出现一长串机器 id。
模型侧这些 id 其实**不需要**：`chat_edit_context_loader.dart:554` 已经会把食堂菜以同样的
`[canteen-dish:<id>] <name>` 形式放进 system 快照。

**改动面（§4 D5）**
- 方案 1（推荐）：启动通道从「一个字符串」扩成 `({String display, String send})` 或加一个并行的
  `aiStarterWireText`；用户气泡显示 `display`（只有菜名 + 一句任务），发给模型的是 `send`（含 id 的行）。
  改动点：`ai_conversation_page._sendStarterPrompt`、`AiConversationController.sendMessage(text, …)` 需要支持
  「显示文本 ≠ 发送文本」（控制器已有 `ConversationMessage.text` 用于落库与上屏，需加 `wireText` 或复用 systemContext）。
- 方案 2（更小）：**直接从用户消息里去掉 id**，只发菜名；模型靠 system 快照按名字定位。
  风险：未进快照的菜（未分析、无 active 菜单）无法定位，`canteen.dish.nutrition` 会失败 —— 需实测快照覆盖。
- 方案 3（最保守）：保留 id，但改为**行尾短引用** `番茄炒蛋  ·  #1` 并在消息下方折叠「技术细节」。
推荐方案 1（显示与发送分离），因为它不牺牲定位可靠性。

**判据**：`test/app/canteen_analyze_prompt_test.dart`：
点「AI 分析 2 道」→ 切到 AI 页后，用户气泡文本**不含** `canteen-dish:` 与任何 8 位以上 id；
假 service 收到的 `messages.last.text` **含** 两条 `[canteen-dish:`（wire 未退化）。
**风险**：显示/发送分离会让「用户气泡里看不到自己到底发了什么」——所以在气泡下方加一行
「含 2 道菜的定位信息（技术细节）」的披露，保持诚实。

---

### R15 编辑卡：每个条目可单独应用

**现状**：行状态是徽标 `LfBadge.neutral('待应用')`（`chat_edit_card.dart:531–537`），
可点动作只有**组头**「应用本组」（`:286–292`）与卡底「全部应用 / 忽略」（`:149–158`）。
执行器与控制器**已支持按行**：`onApplyRows(Set<int>)` → `applyEdits(..., rowIndexes:)`。
⇒ 缺的只是「行级」这一层 UI。

**改动面**：`ChatEditRowStatus.proposed` 的尾部不再画徽标，画一枚可点的 `LfPillButton`
（`Key('chat-edit-row-apply-<card>-<row>')`，label「应用」，tone soft）；
点击 → `onApplyRows({item.index})`；`applying` 期间该行按钮变 `busy` 且不可点；
其余状态（applied/failed/dismissed）仍用徽标。组头「应用本组」保留（批量更省手）。
**判据**：`chat_edit_card_test.dart` 新增：两行待应用 → 点第一行「应用」→ 只有第一行变 `已应用`，
第二行仍 `待应用`（`applyEdits` 收到的 `rowIndexes == {0}`）；连点两次只有一次写入。
**风险**：低。注意 `_busy` 是整卡级（`_turn.isApplying`），行级按钮在 busy 时须统一禁用，避免并发写。

---

### R16 输入框上两个 chip 换成实用功能 —— **已裁决：方案 A（详见 §8）**

**现状**：`ChatQuickChips`（`lf_chat_input.dart:126–220`）三枚等宽：
`确认应用`（`applyEdits`）、`我可以吃吗`（预填一句话）、`AI 创作`（画廊）。
- 「确认应用」在 R15 之后就多余（每行都能点「应用」，卡底还有「全部应用」）；
- 「我可以吃吗」只是往输入框塞 5 个字，用户还得自己补后半句 —— 两次点击换半句话。

**裁决结果（2026-10-24）**：换成「今天还剩多少」+「记一餐」，`AI 创作` 原位不动。
完整的行为/数据源/边界/判据见 §8「已定方案 A」；未采纳的 B/C/D 三套在同处留档。

---

### R17 训练计划：天数选不了 + 关键词选中态太浅

**R17-a 天数选不了（真 bug）**
- 现状：`_days = ValueNotifier<int>(3)`（`workout_plan_create_page.dart:68`）；
  表单是 `_FormView extends StatelessWidget`，读 `days.value`（`:376`）**但没有监听**
  （全文件无 `ValueListenableBuilder`/`addListener`）⇒ 点 `plan-days-4` 只改了 notifier，
  **界面不重建**，胶囊选中态永远停在第 3 天。`_buildRequest` 读的是 `_days.value`（`:167`），
  所以「界面看着没变、实际发出去的是 4 天」——比不生效更糟。
- 另：只给 `1..5`，而 `AiWorkoutPlanRequest.maxDays = 7`（`workout_plan.dart:211`）。
- 改法：`_FormView` 改 `StatefulWidget` 或把天数行包一层 `ValueListenableBuilder<int>`；取值 `1..7`；
  选中态走 `LfPillTone.solid`（见 R17-b）。
- 判据：`test/features/training/workout_plan_days_test.dart`：点 `plan-days-5` → 该胶囊 `selected == true`、
  `plan-days-3` 为 false；进入 disclosure 后文案「目标天数：5 天」；`1..7` 七个都在。

**R17-b 关键词选中态太浅（实测根因：选中比未选中更不明显）**
- 现状：`LfPillButton(selected: true)` 在 `tone == muted` 时升级到 `soft`
  （`lf_buttons.dart:325–343`）：底 `LfColors.brandSoft`（亮 `#ECFBF5`）、字 `mintText`（亮 `#187653`）。
  实测：**选中底 vs 白卡 = 1.07，未选中 `muted` vs 白卡 = 1.12** ⇒ 选中态比常态更不显眼，
  「点了没反应」在视觉上成立。暗色好一些（1.42），但也偏弱。
- 改法（D7 已裁决：给 `LfPillButton` 新增 `selected` 档，不动 `soft`、不动 `brandSoft()`）：
  1. `lf_buttons.dart`：`LfPillTone` 增加 `selected` 成员；
     亮 `mintLight.tone(200)` `#A8EBCF` + 字 `mintLight.tone(900)` `#114A36`（字对比 7.51）；
     暗 `mintDark.tone(300)` `#2A3A32` + 字 `mintDark.tone(400)` `#4ED9A6`（字对比 6.74）；
     底 vs 卡面 1.36 / 1.41 > 未选中 1.12 ⇒ 可见顺序修正。
  2. `selected: true && tone == muted` 的自动升级目标从 `soft` 改为 `selected`
     （仅影响 `workout_plan_create_page.dart:373/406` 两处）；
     显式传 `tone: LfPillTone.soft` 的 5 处「轻强调动作」（识餐修正、饮水快捷值、
     菜单去维护、训练开始/今日开始）**行为不变**。
  3. **不动** `LfColors.brandSoft()` 与 `ColorScheme` 的 `primaryContainer`/`secondaryContainer`/
     `indicatorColor`/`selectedColor`（那 10 处是主题语义，改了等于换设计）。
  4. `docs/21` §3.8 补 `selected` 档的取值与理由（含「选中必须比未选中更远离背景」这条判据）。
- 判据：`test/app/design/lf_pill_selected_test.dart`（纯组件，不依赖页面）：
  选中态容器底色 == `mintLight.tone(200)` / `mintDark.tone(300)`；
  与卡底对比度 **≥ 1.30** 且 **> 未选中 muted 与卡底的对比度**（1.12）——这条是根因的反向断言；
  `soft` 档取色不变（回归钉住，防止顺手改坏 5 处轻强调动作）；
  训练页两处：点 `plan-days-5` 后该胶囊取色 == `selected` 档；`goal-keyword` 同。
- **风险**：`LfPillTone` 是 enum，新增成员会让所有 `switch` 穷尽性检查报错 —— 这是好事（编译期找齐调用点），
  但要一次改完 `lf_buttons.dart` 里的两处 `switch`（`:335`、以及 `_lfButtonLabel` 无 tone 分支）。

---

## 4. 需要裁决的 7 项（decision-required）

| ID | 问题 | 推荐 | 最保守默认 |
|---|---|---|---|
| D1（R4） | 「下一餐」整族是只删 UI 还是连 `NextMealDecisionController`/`DailyPlanEngine` 一起退役？ | **整族退役**（否则留死码，与用户诉求冲突）；三张 `daily_plan*` 表保留不删 | 只删入口+二级页，控制器保留并登记为「零 UI」 |
| D2（R10-c） | `DishStaleness`/`DishSourceSync`（陈旧提示 + 手动同步）是否退役？ | **退役**（自动同步已覆盖六条写路径） | 保留代码、隐藏 UI，登记为待退役 |
| D3（R10-a） | 「换一整套」在未配置 AI 时的行为 | 显示按钮 + 本地重排 + 一句实话（不出现死按钮） | 配置 AI 才显示按钮 |
| D4（R11） | 「提取记忆」与「结束会话」是否合并；合并后是否仍受「自动提炼」开关约束 | **合并为一个「结束本次对话」**，显式动作不受开关限制；开关只管后台自动跑 | 保留两个按钮，只改名 + 加状态提示 |
| D5（R14） | 用户气泡显示文本 vs 发送文本是否分离 | **分离**（`display` 只菜名，`send` 带 id），气泡下加一行技术披露 | 只把 id 缩短成 `#1` 短引用 |
| D6（R16） | 两枚 chip 换成哪套功能 | §8 方案 A（今天还剩多少 / 记一餐） | 保留现状，只把「确认应用」删除 |
| D7（R17-b） | 关键词选中态只在训练页改，还是提升 `LfPillButton` 的选中档 | 给 `LfPillButton` **新增 `selected` 档**（不改 `soft`、不改 `brandSoft()`）；见 §4.1 | 只改页面 |

**已全部裁决（2026-10-24，按推荐执行）**：D1 = 整族退役；D2 = 退役；D3 = 显示按钮 + 本地重排；
D4 = 合并为「结束本次对话」；D5 = 显示/发送分离；D6 = 方案 A；D7 = 新增 `selected` 档。
七条裁决全部走「推荐」列，无一条走最保守默认。**以下正文即为定稿规格，可直接开工。**

### 4.1 D7 的三层波及面（实测枚举，不是估算）

「全局改」有三种改法，波及面差 5–10 倍，必须分清：

| 层次 | 改什么 | 实测波及 | 判断 |
|---|---|---|---|
| **T1 选中档** | `LfPillButton` 里 `selected && tone==muted → soft` 这一条（`lf_buttons.dart:325–343`） | **2 处，都在训练页**：`workout_plan_create_page.dart:373`（天数）、`:406`（目标关键词） | **推荐改这里**——效果=页面级，但默认值修对了，以后任何「选择语义胶囊」不必各自绕 |
| **T2 soft 档渲染** | 改 `LfPillTone.soft` 的底色/字色 | **5 处**：识餐「修正」`food_scan_widgets.dart:726`、饮水快捷值 `water_entry_dialog.dart:122`、菜单空态「去维护食堂目录」`daily_meal_set_card.dart:285`、训练「开始训练」`training_page.dart:1457` 与 `training_hero.dart:900` | **不动**——这 5 处是「轻强调动作」，不是选中语义 |
| **T3 `brandSoft()` 本身** | 改 `LfColors.brandSoft()`（亮 `#ECFBF5` / 暗 `#203C30`） | **10 处**，含 `app_theme.dart:23` 把它设成 `primaryContainer`/`secondaryContainer`、导航 `indicatorColor`、`selectedColor` → 会连带改变 Material 组件的容器色、食物库分类胶囊（`lf_filter_chips.dart:49`）、日期周条（`nutrition_record_week_strip.dart:212`）、今日页三卡、菜单候选 | **禁止**——这不是「改一个胶囊」，是改主题语义 |

**为什么当前看不出选中（实测数字，这才是根因）**
选中底 `mint-50 #ECFBF5` 对白卡 `#FFFFFF` 的对比 = **1.07**；
而未选中的 `muted #EFF3F1` 对白卡 = **1.12**。
⇒ **未选中比选中还显眼**，用户看到的「点了没反应」在视觉上是真的：选中态比常态更接近背景。
这不是「颜色淡了一点」，是**顺序反了**。

**新 `selected` 档取值（亮/暗两套，均实测）**

| | 底 | 字 | 底 vs 卡面 | 字对比度 |
|---|---|---|---|---|
| 亮 | `mintLight.tone(200)` `#A8EBCF` | `mintLight.tone(900)` `#114A36` | 1.36 | 7.51 |
| 暗 | `mintDark.tone(300)` `#2A3A32` | `mintDark.tone(400)` `#4ED9A6` | 1.41 | 6.74 |

选它的理由：① 可见度 1.36 > 未选中的 1.12，顺序终于正确；② 文字 7.51 远超 4.5，大字小字都读得清；
③ 与 `LfPillTone.solid`（实底 `#2FBE8F` + `#10271D`）区分得开，不会让「选中」看起来像「主行动按钮」。
**备选**：`selected == solid`，与 `meal_editor_dialog._SlotPill` 的既有「选中=实底」完全一致（最不可能看错），
代价是整排胶囊会像一排主按钮——若你更看重「一眼看出」，选这个。

未获裁决时按「最保守默认」执行并在报告登记，不阻塞其他条目。

---

## 5. 分批与顺序（每批独立可验证、可回退）

**批次 1 · 提示与布局（低风险，先拿掉噪音）**
R5 → R1 → R6 → R7 → R8
理由：R5 是纯缺陷且改动最小；R1/R6/R7/R8 都是单文件布局，互不依赖。
出口：`batch4-ui` 门禁绿 + 4 条新测试。

**批次 2 · 记录路径（R2/R3 + R4 的 UI 面）**
R2 → R3 → R4（UI 部分；整族退取决于 D1）
理由：R2 改导航拥有者，R3 改弹层，二者都动「记一餐」这条链，放一起才能一次把 `meal_entry_chooser` 的测试写全。
出口：`batch4-record` 绿 + 设备帧（主页点记录→抽屉→退出回主页）。

**批次 3 · 菜品库与菜单（R9/R10）**
R9 → R10-b → R10-c → R10-a
理由：先删页尾（含底栏预留），再修照片数据链，再拆陈旧提示（依赖 D2），最后做整套换（依赖 D3）。
出口：`batch4-menu` 绿 + 照片实帧 + 手改营养不被覆盖的用例。

**批次 4 · AI（R11/R13/R15/R16/R12/R14）**
R15（最小，先把行级应用做出来）→ R13（渲染器）→ R11（状态/合并/清历史，依赖 D4）→ R12 → R14（依赖 D5）→ R16（依赖 D6）
理由：R15 让「确认应用」chip 退场成为自然结论；R13 必须在 R12/R14 之前，因为后者改的是**给模型看的文本**，
而 R13 改的是**给用户看的文本**，顺序颠倒会重复调文案。
出口：`batch4-ai` 绿 + 提炼忙态/结束分隔线/清空历史的设备帧。

**批次 5 · 训练 + 收尾**
R17 → 文档同步（docs/21 Key 表、docs/40 §6、docs/03 as-built、STATUS、INDEX）→ 连续两次全量门禁 → APK → 局域网
出口：`batch4-final` / `batch4-final2` 两次绿、`changed_during_run: []`、APK sha256 与下载校验。

**每批固定动作**：RED 测试先跑出红 → 实现 → 定向测试绿 → `run.py <label> format lib` 与 `format test` 分开跑
→ `gate` → 记日志标签。禁止跨批混改（一批里只做本批 ID）。

---

## 6. 测试退役台账（先登记，再动手）

> 退役 ≠ 删断言让自己变绿。每条都要写「断言的**对象**不存在了」。

| 测试文件 | 受影响断言 | 退役理由 | 替代断言 |
|---|---|---|---|
| `test/round7_foodlib_footer_capture_test.dart` | 整文件（页尾条几何/截图） | R9 删页尾条 | 新 `food_library_no_footer_test`（不存在 + 列表末行不被遮挡） |
| `test/features/nutrition/food_library_footer_test.dart` | 整文件 | 同上 | 同上 |
| `test/features/nutrition/food_library_reactivity_test.dart:162/199` | 点页尾两条链 | 同上 | 改点设置页 `settings-food-data` |
| `test/features/nutrition/nutrition_subtab_occlusion_test.dart:321–341` | 页尾条遮挡 | 同上 | 改为「列表末行 vs 底栏」 |
| `test/app/design/key_contract_test.dart:114–116` | `food-reference-source/-evidence` | R7 删徽标 | 保留三枚动作 Key 断言 |
| `test/app/secondary_entry_reachability_test.dart:176–185` | 「下一餐详情」可达 | R4 删入口 | 新 `record_tab_no_next_meal_entry_test`（反向：不存在） |
| `test/app/two_point_zero_ui_audit_test.dart:328/330/498/499` | 同上 | 同上 | 同上 |
| `test/features/daily_plan/next_meal_decision_wiring_test.dart` | 整文件 | D1 整族退役 | — |
| `test/features/daily_plan/next_meal_slot_progression_test.dart` | 整文件 | 同上 | — |
| `test/features/daily_plan/daily_plan_engine_test.dart` | 整文件 | 同上（若引擎退役） | — |
| `test/features/daily_plan/next_meal_decision_card_test.dart` | 整文件 | 同上 | — |
| `test/app/two_point_zero_ui_audit_test.dart:596–631` | `NextMealDecisionCard` golden | 同上 | — |
| `test/features/nutrition/dish_source_sync_test.dart` | 整文件 | D2 退役 | 新「手改营养不被自动覆盖」用例 |
| `test/features/p2/data_model_p2_test.dart:327–387` | 4 个陈旧判定用例 | 同上 | — |
| `test/features/nutrition/menu_staleness_ui_test.dart` | 陈旧提示/同步 | 同上 | `find.text('食堂营养更新') == findsNothing` |
| `test/features/nutrition/menu_page_structure_test.dart:329/548`、`menu_meal_recommendation_ui_test.dart:403`、`round7_menu_capture_test.dart:325/328` | `nutrition-menu-meal-*-swap` 存在/几何 | R10-a 删单格换 | 新 `nutrition-menu-daily-set-repick` 断言 + 候选链仍在 |

**新增测试清单（预估 16 份）**：`quick_stats_two_line`、`dashboard_meal_sheet`、`meal_food_search`、
`dish_meal_picker`、`record_tab_no_next_meal_entry`、`app_snack_bar`（扩）、`food_reference_sheet`（扩）、
`food_card_brand`、`food_library_no_footer`、`canteen_dish_library_sync`（扩：照片/手改）、
`daily_set_repick`、`memory_extract_state`、`end_session_visible`、`clear_history`、
`ai_starter_contract`、`lf_markdown`、`canteen_analyze_prompt`、`chat_edit_card`（扩）、
`workout_plan_days`、`goal_keyword_chip`。

---

## 7. 不变量与明确不做

**不变量（改错即回滚）**
1. schema 不动（仍 30）；不新增表/列/索引。
2. AI 命令仍 37 条；`chat_edit_registry` 的**信封形状**不动（本批只加展示与提示词文案）。
3. 每一条写入仍只有一条落库路径（`MealRepository.create` / `DishLibraryRepository` / `CanteenRepository`）。
4. 弹层 `useRootNavigator: true` + 弹层内 context 弹出（R2/R3 改弹层时重点）。
5. 分层门禁只减不增；`core/`、`data/` 不得 import `features/`。
6. 「不编事实」：所有新文案要么说清来源，要么说清「不知道」。

**明确不做**
- 不新增第三方依赖（Markdown 自己写）。
- 不做「AI 自动写入」的新路径（R10-a 的整套换仍走编辑卡逐条确认）。
- 不动价格/购物/食谱计划（已退役族）。
- 不做真实 AI 断言以外的旁路（真实模型验证仅走 `LF_AI_LIVE_*` 环境变量，零入库）。
- 不改 iOS/Android 权限与打包脚本（除版本号）。

---

### R16 输入框两枚 chip：已定方案 A（今天还剩多少 / 记一餐）

**裁决（2026-10-24 用户）**：采用方案 A。`确认应用` 与 `我可以吃吗` 双双退场（前者在 R15 行级应用之后多余，
后者只是把 5 个字塞进输入框）。`AI 创作` 原位不动。

**chip 1 · `今天还剩多少`（`ai-chat-chip-remaining`，图标 `Icons.pie_chart_outline`）**
- 行为：**不发给模型**，直接在对话流里插一条助手消息（不入库，标记为本地计算结果），
  内容由本地事实算出：
  ```
  今天还剩 560–760 kcal（已摄入 1,240 / 目标 1,800–2,000 kcal）
  蛋白质 还差 28g · 碳水 还差 96g · 脂肪 已超 6g
  ```
- 数据源：`MealRepository.watchNutritionForDate(localDate)` 的快照 + `daily_targets`（`DailyTargetRow`）。
  与今日页热量卡、营养分析卡**同一份口径**（不许自算第二套），差额文案复用 `buildNutritionInsights` 的措辞风格。
- 边界（必须如实，不许美化）：
  - 没有目标（`daily_targets` 空）→ 「还没设营养目标；去「我的 → 目标」设一个我才能算差额」+ 一个可点跳转；
  - 今日 0 条记录 → 「今天还没记任何东西，剩余 = 全天目标」；
  - 某项已超 → 明说「已超 N」而不是显示负数。
- Key：`ai-chat-chip-remaining`、结果气泡 `ai-chat-remaining-card`、每行 `ai-chat-remaining-<kcal|protein|carbs|fat>`。

**chip 2 · `记一餐`（`ai-chat-chip-log-meal`，图标 `Icons.restaurant_menu`）**
- 行为：调 R2 抽出的 `openMealRecordSheet(...)`，**不离开 AI 页**；记完给一条 `AppSnackBar`
  「已记一份「X」到午餐」并保持在对话页（不自动发消息、不跳页）。
- 前置：未接线（`mealRepository == null`）时该 chip 不渲染，不做「点了没反应」的按钮。
- 复用：与主页「记录晚餐」、饮食页 FAB 是同一个 launcher、同一份两个入口（按食材/按菜品），不新增第三条记录路径。

**判据（RED 先行）**
- `test/features/ai_conversation/chat_chip_remaining_test.dart`：
  1. 有目标 + 已记 1,240 kcal → 点 chip → `ai-chat-remaining-card` 出现，文案含「560」与「1,240」，
     且**没有**发出一条 `ConversationMessage`（`controller.state.messages.length` 不变）；
  2. 无目标 → 文案含「还没设营养目标」，且出现跳转入口；
  3. 某营养素已超 → 文案含「已超」，不含负号。
- `test/features/ai_conversation/chat_chip_log_meal_test.dart`：点 chip → `meal-entry-chooser` 出现、
  `ai-chat-title` 仍在（没跳页）；选「按菜品」→ 记录成功后仍停在对话页。
- `test/app/design/key_contract_test.dart`：`ai-chat-chip-can-i-eat` 已退役、新两枚 Key 有断言。
- 文档：`docs/21` §3.4 的三枚 chip 表重写（含废弃的 `can-i-eat` 标为退役）。

**§8 其余方案（未采纳，留档备将来）**

### 方案 A：`今天还剩多少` + `记一餐`（**已采纳**）
| chip | 点击后 | 实现 | 价值 |
|---|---|---|---|
| 今天还剩多少 | 在对话里**直接**回一条助手消息：`已摄入 1,240 / 目标 1,800–2,000 kcal；蛋白 62/90g 还差 28g` | 读 `DailyNutritionSummary` + `daily_targets`，纯本地计算，0 网络 | 最高频问题，秒回 |
| 记一餐 | 打开「按食材/按菜品」抽屉（复用 R2 的 launcher），不离开 AI 页 | `openMealRecordSheet` | 在 AI 页聊完就记，少跳一次 |
**优点**：一「问」一「做」，覆盖最常见的两个意图；都不依赖 AI 配置。
**风险**：第一条是**本地计算**，与「AI 助手」的定位有轻微落差（但更可信、更快）。

### 方案 B：`这套换一换` + `今日推荐`
| chip | 点击后 | 实现 | 价值 |
|---|---|---|---|
| 这套换一换 | 发一条「按我的目标把今天三餐整套重排，别重复同一道菜」→ 走 R10-a 同一条 AI 通道 | `aiStarterRequest` + chat-edit | 与菜单页「换一整套」同一个动作，两处入口一致 |
| 今日推荐 | 切到「饮食·菜单」tab 并滚到推荐卡 | `menuTabRequest`（已有） | 一句话看到今天吃什么 |
**优点**：把 R10-a 的能力暴露到对话里，AI 页与菜单页形成闭环。
**风险**：两个 chip 都围绕「菜单」，不吃食堂的用户用不上；且第一条依赖 AI 配置（未配置要有本地兜底）。

### 方案 C：`查食物` + `记饮水`
| chip | 点击后 | 实现 | 价值 |
|---|---|---|---|
| 查食物 | 打开食物库搜索弹层（预聚焦输入框） | 复用 `FoodDetailSheet`/`food_search_tab` 的检索 | 「这个多少卡」的高频需求 |
| 记饮水 | 弹 250/500ml 快捷加水层 | `WaterEntryDialog`（已有） | 一天点 4–6 次的动作 |
**优点**：都是高频小动作，全部本地、零 AI。
**风险**：与「饮食页 / 今日页」的入口重复；对话页承担了太多「工具箱」职责。

### 方案 D：`按目标配一餐` + `记体重`
| chip | 点击后 | 实现 | 价值 |
|---|---|---|---|
| 按目标配一餐 | 带上剩余额度发一条配餐请求 | chat-edit `meal.create` 提议 | 最贴近「AI 营养助手」的定位 |
| 记体重 | 弹体重录入（最近 3 次做参考） | `WeightEntryDialog`（已有） | 每周 1–2 次，但每次都要找入口 |
**优点**：一个 AI 重动作 + 一个纯记录动作，互补。
**风险**：配一餐要等模型；记体重频次低，占一个常驻位不划算。

~~推荐组合：A（问 + 记）。~~ **已于 2026-10-24 裁决为 A**，见本节开头。

---

## 9. 证据与交付

- 证据目录：`docs/evidence/2026-10-24-batch4/`
  - `static/`：改前改后的 `grep` 输出（死码扫描、Key 清单、`actionLabel` 全量清单）
  - `tests/`：每批门禁日志摘要（标签、`+N ~M`、`changed_during_run`）
  - `device/`：主页记录抽屉、两行数字卡、菜单照片封面、编辑卡行级应用、提炼忙态、结束分隔线
  - `retirement.md`：§6 台账的执行结果（每条：文件、断言、理由、替代）
- 文档同步：`docs/21`（Key 表 + 已退役项）、`docs/40 §6`（同步语义改写）、`docs/03`（as-built 横幅）、
  `STATUS.md`（批次横幅）、`docs/INDEX.md`（本文件登记）。
- 交付：APK（`--build-number` 递增，arm64 + x86_64，sha256 + `dist/index.html` + 局域网）、
  回归清单（17 条逐条「已满足 / 部分 / 未做 + 原因」）。

## 10. 立即开始的动作（批准后第一条命令）

```bash
cd E:/AI/Zcode/projects/localfit-ai/localfit-ai
python E:/AI/zcode/tmp/localfit-round7-native-20261014/run.py batch4-baseline gate
```
然后从批次 1 的 R5 开红（`app_snack_bar_test.dart` 里那条「带 action 5 秒后应消失」）。
