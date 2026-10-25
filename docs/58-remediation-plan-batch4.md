# 批次 4 修复计划（2026-10-24 · v2）

> **输入**：[`docs/57`](57-review-report-batch4.md) 台账（P0=0 / **P1=9** / P2=12 / P3=5）。
> **需求与裁决**：[`docs/56`](56-batch-review-plan-2026-10-24.md)（D1–D7 已全部按推荐定稿）。
> **本版新增**：① 一条新发现的 P1（`RV4-P1-09` 选择胶囊不发 `Semantics(selected)`）；
> ② **一套覆盖全部按钮/控件的交互门禁**（§2，用户点名要，专门防「训练天数选不了」这类问题再犯）；
> ③ 批次重排为 **B1–B6**（控件门禁提到 B1 之前，先建安全网再改代码）。
>
> **纪律**：每条**先写会失败的断言**（RED）→ 改实现 → 定向绿 → 全量门禁 → 证据。不许放宽指标、
> 不许删断言换绿、不许跳测试。退役断言走 §5 台账。证据落 `docs/evidence/2026-10-24-batch4/`。

---

## 0. 目录

- §1 **执行方式（连续跑、不停、断点续跑）+ 为什么先建门禁**
- §2 **控件交互门禁（新增，四层）**
- §3 B1 门禁层（只加测试，含 B1 不跑全量 gate 的具体命令）
- §4 B2–B5 业务修复
- §5 B6 退役收尾
- §6 测试退役台账
- §6.1 收敛判据
- §6.5 **默认动作表（阻塞时照此走，不询问）+ §6.6 断点续跑**
- §7 风险与回滚
- §8 立即开始

---

## 1. 执行方式：连续跑完，不中途停

**本计划按「一次会话连续执行到收敛」设计**（对齐 `docs/53` §1）。执行者不必在批次之间、
ID 之间、门禁之间停下来汇报或等确认。

1. **不停、不等确认。** B1 → B2 → B3 → B4 → B5 → B6 一口气跑完；中间不输出「阶段完成」。
2. **唯一中间记录**：`docs/evidence/2026-10-24-batch4/run-log.md`，每次批次切换写一行时间戳
   （格式照 `evidence/2026-10-22-full-review-v2/run-log.md`）。**不面向用户**，只供断点续跑。
3. **需要取舍时按 §6.5 默认动作表执行并登记，继续往下走**，不阻塞。
4. **只有三种情况允许停**：
   ① 仓库不可读 / 工具链彻底不可用（`run.py` 跑不起来且重试无效）；
   ② 磁盘或权限导致连证据/文档都写不了；
   ③ 连续两轮同一 ID 修不绿且已试过 §6.5 的绕行。
   **注意**：缺真实 AI 凭据、缺设备、性能劣化超阈值、某条 RED 假设证伪、测试退役后发现仍有用 —— **都不属于允许停的情形**，见 §6.5 各自的动作。
5. **轮次上限 3 轮**：一轮 = B1–B6 全走完 + 一次全量门禁。第 3 轮仍未收敛 → 停，把残留逐条写成
   `decision-required` 交裁决（不允许静默收工，也不允许无限循环）。
6. **发现问题随时回流**：执行中新发现 P0/P1 → **就地修**（不排队、不等下一轮），登记进 `docs/57`
   台账并注明「执行期发现」；新发现 P2/P3 → 登进台账，本轮末尾统一处理（P3 只登记不修）。

### 1.1 为什么顺序是「先建安全网，再动业务代码」

v1 把业务修复放在最前面，控件门禁根本没排进去。这是错的，理由有三：

1. **这批修复本身会大量改动控件**（`LfPillButton` 新增 `selected` 档、编辑卡行级按钮、
   两枚新 chip、四枚餐次胶囊、按菜品搜索框）。没有门禁就改控件，等于重复犯错。
2. **已经证明这类缺陷测不出来**：`plan-days-*` 在 `test/` 下 **0 命中**；补 `imagePath` 后 12 条测试全绿不变。
   先有门禁，后续每条修复才自带「不退化」的证明。
3. **门禁本身能发现新缺陷**：写门禁的过程中就查出了 `RV4-P1-09`（`Semantics(selected)` 缺失），
   它本来不在台账里。

**因此：B1 = 建门禁（只加测试，不改 `lib`）**。B1 里会有几条**故意红**的测试——那是门禁在报告现存缺陷，
它们在对应业务修复完成前保持红（记录在 §2.6 的豁免表里，不允许为了变绿而放宽）。


---

## 2. 控件交互门禁（新增）

### 2.1 目标与失效模式

用户原话：「加上一个全按钮和控件功能测试，避免出现刚刚那个训练天数选不了的问题再次出现」。
「选不了」在代码层面有三层可能，**必须分别测，不能只测一层**：

| 层 | 失效模式 | 训练天数这次的实际情况 | 只靠哪层能抓到 |
|---|---|---|---|
| **L1 状态层** | 点了但值没变 | 值是**变了**的（4 真发出去了） | 抓不到 |
| **L2 重建层** | 值变了但界面不重建 | **就是这个**（`ValueNotifier` 无监听） | ✅ |
| **L3 语义层** | 界面变了但读屏说不出 | 也坏了（不发 `Semantics(selected)`） | ✅ |

再加一层横向的：
| **L4 可测性层** | 控件没有 Key，根本没法测 | 有 Key（`plan-days-N`），但没用上 | 防「以后新加的控件无从下手」 |

四层合起来才是完整的「按钮/控件功能测试」。**只写 L1 会继续漏掉这次 bug。**

### 2.2 L1 · 状态层：点击必须产生可观察变化

**做法**：对每个**有状态语义**的控件族，写一条「点一下 → 断言目标值变了」的表驱动测试。
不是点遍 175 个可交互控件（那是维护地狱），而是**点遍有状态的控件实例**——它们才是"选不了"的候选。

| 控件 | 实例位置 | 断言 |
|---|---|---|
| `LfPillButton(selected:)` | `workout_plan_create_page.dart:374`（天数）、`:407`（关键词） | 点击后目标项 `selected == true`、同级目标项 `false` |
| `_SlotPill`（餐次） | `meal_editor_dialog.dart:243` | 点击后 `_slot` 变化，保存草稿的 `slot` 随之变 |
| 餐次胶囊（新增） | `DishMealConfirmSheet`（B4 引入） | 同上 |
| `LfFilterChip` | `food_category_chips.dart:40/47` | 点击后 `selected` 迁移，列表结果按分类过滤 |
| `LfSegmentControl` | `nutrition_page.dart:253`（sub-tab） | 点击后 `_tab` 变化且正文切换 |
| `LfSegmentedToggle` | 训练页 | 点击后 `selectedIndex` 迁移 |
| `LfToggleSwitch` / `Switch` | 设置项（步数开关等） | 点击后持久值真的写库（`app_settings` KV） |
| `AppMorphChip` | 4 处 | 点击后 `selected` 取反 |
| `_CandidateRow` | `menu_dish_list.dart:651` | 点候选后 `_swapOffset` 变化、卡上菜变了 |

**文件**：`test/app/interaction/control_state_changes_test.dart`（新目录，按层分文件）。

### 2.3 L2 · 重建层：`ValueNotifier` 必须有监听者（**这是本次 bug 的直接防线**）

**做法**：一条**静态结构门禁**，扫 `lib/`：找出所有 `ValueNotifier`/`ValueListenable` 字段，
要求每个都在同文件（或经构造器传入后在使用方）存在以下之一：
`ValueListenableBuilder`、`ListenableBuilder(listenable: …)`、`.addListener(`；且**读 `.value` 的处数 ≥ 1**。

本次扫描结果（已跑）：

| 文件 | 字段 | 监听 | 结论 |
|---|---|---|---|
| `workout_plan_create_page.dart` | `_days` / `days` | **无** | **真缺陷**（`RV4-P1-02`） |
| `catalog_bootstrap.dart` | `lastResult` | `settings_page.dart:734` 的 `valueListenable:` | 正常（跨文件消费） |
| `settings_page.dart` | `_identity` | `:2324` 的 `ListenableBuilder(listenable:)` | 正常（经 `identityFuture` 传入） |

⇒ 全仓**只有训练页是真漏**。门禁写好后：修为绿；且**将来任何新增 notifier 忘了监听会直接红**。

**实现要点**（避免脆弱的字符串匹配）：
- 扫 `lib/**/*.dart`（排除 `.g.dart`）；
- 字段匹配 `final/late final ValueNotifier<…> name`（含 `_` 前缀）；
- 消费匹配三种写法，且允许**跨文件**（按字段名 + 所属类的构造器参数名做一次全局搜索）；
- 豁免机制：`// interaction-gate: allow-unlistened <理由>` 同行注释，且**豁免数冻结**
  （`expect(allowlist.length, lessThanOrEqualTo(N))`，只减不增，与 `ui_literal_budget_test` 同一套手法）。
- **注意**：本门禁是启发式，会有假阳性风险 → 首次落地时把「正常但被误判」的两条（`lastResult`/`_identity`）
  写进白名单并注明原因，而不是放宽匹配规则。

**文件**：`test/app/interaction/notifier_listeners_gate_test.dart`。

### 2.4 L3 · 语义层：选择状态必须对读屏可见

**做法**：一条**组件级**门禁：所有声明「选择语义」的控件，必须发 `Semantics(selected:)`。

现状核对（已跑）：

| 控件 | 发 `selected` | 结论 |
|---|---|---|
| `LfFilterChip` | ✅ `lf_filter_chips.dart:42` | 正常 |
| `AppMorphChip` | ✅ `app_morph_chip.dart:80` | 正常 |
| `LfSegmentedToggle` | ✅ `lf_segmented_toggle.dart:213` | 正常 |
| `_SlotPill`（餐次） | ✅ `meal_editor_dialog.dart:508` | 正常 |
| **`LfPillButton`** | ❌ **无**（注释写了、实现没有） | **`RV4-P1-09`** |

**测试内容**：
```dart
// 组件级：每个「选择语义」控件的枚举成员都断言一遍
for (final selected in [false, true]) {
  pump(ControlUnderTest(selected: selected));
  expect(semanticsFlagsOf(control).isSelected, selected);
}
```
再加一条**一致性门禁**：`lib/app/design/widgets/` 下任何带 `selected` 参数的公开 widget 类，
其文件内必须出现 `selected:`（在 `Semantics(` 的调用块里）——防止将来新增第五个控件又忘。

**文件**：`test/app/interaction/control_semantics_selected_test.dart`。

### 2.5 L4 · 可测性层：可交互控件必须有稳定 Key

**现状（已测）**：`lib/features` 下 175 处裸可交互控件，131 处就近带 Key，**38 处没带**：

| 类型 | 缺 Key 数 |
|---|---|
| `TextButton` | 21 |
| `InkWell` | 12 |
| `IconButton` | 3 |
| `GestureDetector` | 2 |

**做法**：不要求一次补齐（38 处会牵动大量测试），而是**冻结预算 + 只减不增**：
```dart
test('可交互控件缺 Key 的数量只减不增（新增交互控件必须带 Key）', () {
  expect(unkeyedInteractiveCount(), lessThanOrEqualTo(38)); // 只许往下改
});
```
并在**本批新增/改动的控件**上强制带 Key（`plan-days-1..7`、`dish-meal-slot-*`、
`chat-edit-row-apply-*`、`ai-chat-chip-remaining/log-meal`、`meal-dish-*`、`daily-set-repick`）——
这条靠 B2–B5 各自的测试自然满足（没 Key 就写不出断言）。

**文件**：`test/app/interaction/interactive_key_budget_test.dart`。

### 2.6 B1 的「故意红」与豁免表

B1 落地后，门禁会红在这些地方（**这是正确行为**，不是失败）：

| 门禁 | 红在哪 | 什么时候变绿 |
|---|---|---|
| L2 `notifier_listeners_gate` | `workout_plan_create_page._days` | **B2**（`RV4-P1-02` 修完） |
| L3 `control_semantics_selected` | `LfPillButton` | **B2**（`RV4-P1-09` 修完） |
| L1 状态表 | `plan-days-*` 用例 | **B2** |

**规则**：这三条红**必须**在 `docs/evidence/.../tests/b1-gate-red.md` 里逐条记录（断言原文 + 当时的失败输出），
然后才进入 B2。**禁止**用 `skip:` / `expect(..., findsNothing)` 反向写法让它们"先绿"。

### 2.7 门禁自身也要被验证（变异抽验）

B1 完成后，对三条新门禁各做一次变异，证明它们**真的会红**：

| 变异 | 期望 |
|---|---|
| M-G1：把 `_days` 的 `ValueListenableBuilder` 注释掉（B2 修好后） | L2 红 |
| M-G2：删掉 `LfPillButton` 的 `Semantics(selected:)`（B2 修好后） | L3 红 |
| M-G3：给 `plan-days-5` 的 `onPressed` 改成 `null` | L1 红 |

三条都必须红，且**逐字节还原后复绿**（sha256 比对）。这条写进证据，证明门禁不是空壳——
这正是 `RV4-P1-03` 那个「补上 imagePath 测试全绿不变」的教训。

---

## 3. B1 · 门禁层（只加测试，不改 lib）

| 步骤 | 产出 | 出口 |
|---|---|---|
| B1-1 | `test/app/interaction/control_state_changes_test.dart`（L1） | 除 `plan-days` 外全绿 |
| B1-2 | `test/app/interaction/notifier_listeners_gate_test.dart`（L2） | 恰好红 1 处（`_days`） |
| B1-3 | `test/app/interaction/control_semantics_selected_test.dart`（L3） | 恰好红 1 处（`LfPillButton`） |
| B1-4 | `test/app/interaction/interactive_key_budget_test.dart`（L4） | 绿（预算 38） |
| B1-5 | `docs/evidence/.../tests/b1-gate-red.md` | 三条红的断言原文留档 |
| B1-6 | 门禁标签 `batch4-gate1` | `changed_during_run: []`（本批只加 test 文件） |

**B1 的运行方式（明确，避免执行时卡在"门禁红怎么办"）**：`run.py gate` 会因测试红而 exit 1。
所以 **B1 不跑全量 gate**，改为三步：

```bash
# ① 逐文件跑新门禁（期望：L1 除 plan-days 外绿；L2 恰好 1 红；L3 恰好 1 红；L4 绿）
run.py b4-gate-l1 test test/app/interaction/control_state_changes_test.dart
run.py b4-gate-l2 test test/app/interaction/notifier_listeners_gate_test.dart
run.py b4-gate-l3 test test/app/interaction/control_semantics_selected_test.dart
run.py b4-gate-l4 test test/app/interaction/interactive_key_budget_test.dart
# ② format + analyze（这两项在 B1 必须全绿——只加测试文件，不该引入新告警）
run.py b4-gate-format format lib
run.py b4-gate-format2 format test
run.py b4-gate-analyze analyze
# ③ 全量测试**暂时排除**四个新门禁文件，证明既有 2856 条未被影响
run.py b4-gate-regress test --exclude-tags interaction-gate
```

为此给四个门禁文件的 `main()` 加 `@Tags(['interaction-gate'])`，这样 B2 之后可以用
`test --tags interaction-gate` 单独复跑，全量 gate 也不会因「故意红」被卡住。
**B2 修完后**：`run.py batch4-fix2 gate`（全量，含四个门禁，此时应全绿）。

**这条要写进证据**（`tests/b1-gate-red.md`），避免「B1 没跑绿门禁」被误读成失败。

---

## 4. B2–B5 · 业务修复

### B2 · 提示与控件（RV4-P1-01 / P1-02 / P1-09 / P1-07 + P2-01）

| ID | 改法 | RED（先写，必须真红） |
|---|---|---|
| **P1-01** SnackBar 永不消失 | `app_snack_bar.dart` 的 `show/showOn` 加 `bool persist = false` 并**显式**传给 `SnackBar`；删除族传 `duration: 6s`；`ai_memory_page.dart:1032` 裸 `SnackBar` 改走统一出口（顺带 P3-05） | `pump(7s)` 后 `SnackBar` 为 `findsNothing`；`bar.persist == false` |
| **P2-01** 撤销按钮不够跳 | `snackBarTheme` 加 `actionTextColor`（亮 `#6FDBB0` / 暗同档）+ `actionTextStyle`（w600）+ `actionOverflowThreshold: 0.4` | 主题字段非空 + 对比度 ≥4.5（亮/暗） |
| **P1-02** 天数界面不动 | 天数行包 `ValueListenableBuilder<int>(valueListenable: days)`；取值域 `1..7` | 点 `plan-days-5` → 该枚 `selected`（现必红） |
| **P1-09** 胶囊不发 selected | `LfPillButton` 的 build 最外层包 `Semantics(button: true, selected: selected, enabled: onPressed != null)` + `ExcludeSemantics` 包内层（与 `LfFilterChip` 同一写法） | `getSemantics(...).isSelected == true`（现必红） |
| **P1-07** 选中态顺序颠倒 | `LfPillTone` 新增 `selected`：亮 `mintLight.tone(200) #A8EBCF` + 字 `tone(900) #114A36`（7.51）；暗 `mintDark.tone(300) #2A3A32` + `tone(400) #4ED9A6`（6.74）。`selected && muted` 升级目标 `soft → selected`。**不动** `soft` 渲染（5 处）、**不动** `brandSoft()`（10 处） | 选中底 vs 卡面 ≥1.30 **且 > 未选中 1.12**；`soft` 取色不变 |

**P1-07 的连带改动（v1 漏了）**：`test/app/design/lf_buttons_test.dart:400` 有一条
`selected 提升到 soft 档（muted 未被显式指定时）` 断言 `_bg == LfColors.brandSoft`。
D7 改的就是这个行为 ⇒ **这条必须同步改写**为断言新 `selected` 档取色，并在证据里注明
「断言的对象语义变了（soft → selected），不是删断言换绿」。

**出口**：`batch4-fix2` 全量 gate 绿（含 B1 三条红转绿）。

### B3 · 记录路径（P1-04 / P1-05 / P1-06 + R4 的 UI 面）

| ID | 改法 | RED |
|---|---|---|
| **P1-04** 主页记录不跳页 | 新增 `meal_record_launcher.dart`（搬 `chooseRecordEntry` 流程，不复制写逻辑）；`app_router.onLogMeal` 直接 `await openMealRecordSheet(...)`，删 `go(nutrition)` | `meal-entry-chooser` 出现且两个 tab `Semantics.selected` 均 false；取消后 `dashboard-next-meal` 仍在；`mealAddIntent.value == null` |
| **P1-05** 搜索括号变体 + 品牌 | `page()` 排序前置「括号前主名优先」（`substr`+`instr`）+ `limit 10→20` + `where name LIKE q OR brand LIKE q` | 搜「鸡蛋」→ `鸡蛋（熟）` 在前 3（现第 32）；搜「千丰香米」命中 |
| **P1-06** 按菜品搜索 + 餐次可选 | `DishMealPickerDialog` 加 `LfSearchField(Key('dish-meal-picker-search'))`；`DishMealConfirmSheet` 四枚胶囊 `Key('dish-meal-slot-<v>')`，返回 `MealSlot?` | 输入「番茄」过滤生效；选「晚餐」→ `slotOverride == dinner` |
| R4-4a | 删 `leading` 传参 + `next_meal_recommendation_page.dart` + 三个展示组件 | `nutrition-record-next-meal-entry` 与「下一餐详情」均 `findsNothing` |

**性能硬条件（不许跳过）**：P1-05 改完复跑 `query_benchmark_test` 三项，p95 劣化 >10% 即改两段式
（先 name 后 brand）。结果写进 `batch4-fix3` 的证据。
**回归**：`food_repository_test`、`food_library_paging_test`（`id ASC` 末位不许动）、
`nutrition_presentation_design_test.dart:611`（排序变了可能移出首屏 → 改 `find.descendant` 断言该行存在）。

### B4 · 菜品库与菜单（P1-03 + P2-08 / P2-09 / P2-10）

| ID | 改法 | RED |
|---|---|---|
| **P1-03** 照片进菜品库 | `AddCanteenDishesToLibrary.run` 的 `DishDraft` 加 `imagePath: dish.imagePath` | 带照片 → 目标行 `imagePath` 相同 → 渲染 `Image.file`；换照片/删照片同步（**修前必红**，变异 M2 已证明现在补上全绿不变） |
| **P2-09** 陈旧提示 + 手动同步退役 | 删 `MenuDishList` 陈旧计算/`_syncDish`/`onSync`；删 `DishCard` 的 `staleness`/`onSync` 与角标；退役 `dish_staleness.dart` + `dish_source_sync.dart`。**语义硬化**：自动同步**跳过** `userEdited` 行 | 用户手改后食堂再写营养 → 菜品库**仍是用户的值**（修前必红）；`find.text('食堂营养更新')` 为 `findsNothing` |
| **P2-08** 整套换 | 删三段 `-swap`；卡头加 `nutrition-menu-daily-set-repick`：有 AI 走 `aiStarterRequest`，无 AI 本地重排 + 一句实话 | 无 AI 时按钮在、点击后整套变化、给出本地重排说明 |
| **P2-10** 删食物库页尾 | 删 `FoodLibraryFooter` + 两回调；**底栏预留搬到列表末尾**（两个 tab body 各加 `SliverPadding(bottom: navReserve)`） | 三条 Key 全 `findsNothing`；滚到末尾最后一行底边 ≥ 底栏遮挡线 |

**风险最高**：P2-09 是本批唯一可能改坏数据语义的。计划明确「手改即冻结 + 文档说明」，
**不新增手动覆盖动作**（避免又造一个冗余入口）。
**执行期遇到此情形不停**：若 B4 验收发现「食堂更新完全不落地」，按 §7 默认动作执行 ——
**保留自动同步覆盖手改行**（回到「来源是唯一事实」），在 `docs/40 §6` 如实写明
「餐厅侧更新会覆盖你手改的营养」，并登记为一条 P2 观察项；**不停下来问**。

### B5 · AI（P2-07 / P2-02 / P2-04·05·06 / P1-08 / P2-03 / R16）

顺序即依赖顺序：

| 序 | ID | 改法要点 | RED |
|---|---|---|---|
| 1 | **P2-07** 行级应用 | `proposed` 行尾徽标 → `LfPillButton(Key('chat-edit-row-apply-<c>-<r>'))`；已具备 `onApplyRows` | 点第一行 → 只有第一行 `已应用`（`rowIndexes == {0}`） |
| 2 | **P2-02** Markdown | 新增 `lf_markdown.dart`（**无新依赖**）：标题/列表/粗斜/代码/引用/围栏/分隔线；不支持表格外链；≤200 行。顺序：先 `replyTextForDisplay` 清洗再渲染。协议加规则 14 | 各语法 widget 形态；`**x**` 不上屏；`[canteen-dish:abc]` 不出现；畸形输入降级不崩 |
| 3 | **P2-04/05/06** | 提炼忙态行 `ai-chat-extracting`；**合并两按钮**为「结束本次对话」（同步候选层、不看开关）+ 分隔线 `ai-chat-session-ended` + hint 变化 + 幂等；`ConversationMessageRepository.clear()` + 图片清 + 二次确认 + 报数 | 忙态持续存在；分隔线/hint 出现；清空后 `loadRecent` 空、DB 0 行、取消则一条不少 |
| 4 | **P1-08** AI 创作对齐 | `_dailyMenuPlanPrompt` 改 chat-edit 口径；`dailyMenuPlanPromptTemplate` 从 `promptCatalog` 摘除（文件保留 + 退役横幅，egress 仍引用正文）；六卡逐条核对落点 | 提示词不含 `schema_version`/`v1 JSON`/`candidate_ids`（现必红） |
| 5 | **P2-03** 显示/发送分离 | 启动通道扩成 `({String display, String send})`；气泡只显示菜名 + 一行「含 N 道菜定位信息」披露 | 气泡不含 `canteen-dish:`；假 service 收到的 text **含** `[canteen-dish:` |
| 6 | **R16** 两枚 chip（D6=A） | `ai-chat-chip-remaining`（**不发模型**，本地算：已吃/目标区间/三大营养素差额；三条边界）+ `ai-chat-chip-log-meal`（调 B3 的 launcher）；退役 `apply-edits`/`can-i-eat` | 结果卡出现且 `messages.length` 不变；无目标/0 记录/已超三态文案正确 |

### B6 · 退役收尾 + 文档 + 复验

1. **R4-4b 整族退役**：删 `NextMealDecisionController` + 三处装配；`DailyPlanEngine` 零调用后退役；
   `daily_plans/slots/candidates` 三表**保留**（schema 冻结，文档写退役横幅）；
   删 `canteen_directory_page.dart` 两个死形参（P3-01）。
   **保留** `PlanningConstraintsRepository` 与写入路径，文档登记「当前无本地读取者」。
2. **P2-11 食物库品牌**、**P2-12 引用弹层**（v1 里在最早批，v2 移到 B6 前的独立小组，见 §4 附注）。
3. 死符号：`RV4-P3-02` 逐一确认（4 个里删 2 个、留 2 个测试专用）。
4. 文档：`docs/21`（`selected` 档、chip 改版、退役 Key、新 Key）、`docs/40 §6`（同步语义）、
   `docs/03` as-built、`STATUS.md`、`docs/INDEX.md`。
5. 连续两次全量门禁 `batch4-final` / `batch4-final2`；APK + `dist/` + sha256 + 局域网。

> **附注（P2-11 / P2-12 的批次归属）**：两者都是纯 UI 且与业务修复无依赖，放在 B6 是因为
> **不阻塞任何 RED 链**。**默认就按 B6 执行**（不提前）——连续跑时不做"看起来更好"的重排，
> 以免打乱 P1 的连续修复节奏。

---

## 5. 测试退役台账（逐条：断言的对象不存在了）

| 测试 / 断言 | 理由 | 替代 |
|---|---|---|
| **`lf_buttons_test.dart:400`「selected 提升到 soft 档」** | **D7 改的就是这个行为**（soft → selected） | 改写为断言新 `selected` 档取色 + 对比度 |
| `round7_foodlib_footer_capture_test.dart`（整文件） | 页尾条已删（P2-10） | `food_library_no_footer_test` |
| `food_library_footer_test.dart`（整文件） | 同上 | 同上 |
| `food_library_reactivity_test.dart:162/199` | 同上 | 改点设置页 `settings-food-data` |
| `nutrition_subtab_occlusion_test.dart:321–341` | 同上 | 改为「列表末行 vs 底栏」 |
| `key_contract_test.dart:114–116`（`food-reference-source/-evidence`） | 徽标已删（P2-12） | 保留三枚动作 Key 断言 |
| `secondary_entry_reachability_test.dart:176–185` | 入口已删（R4/D1） | `record_tab_no_next_meal_entry_test`（反向） |
| `two_point_zero_ui_audit_test.dart:328/330/498/499` | 同上 | 同上 |
| `next_meal_decision_wiring_test.dart` | 控制器退役 | — |
| `next_meal_slot_progression_test.dart` | 同上 | — |
| `daily_plan_engine_test.dart` | 引擎退役 | — |
| `next_meal_decision_card_test.dart` | 卡片退役 | — |
| `two_point_zero_ui_audit_test.dart:596–631`（golden） | 同上 | — |
| `dish_source_sync_test.dart` | 同步族退役（P2-09） | 「手改营养不被自动覆盖」 |
| `data_model_p2_test.dart:327–387`（4 例） | 同上 | — |
| `menu_staleness_ui_test.dart` | 同上 | `find.text('食堂营养更新') == findsNothing` |
| `menu_page_structure_test.dart:329/548`、`menu_meal_recommendation_ui_test.dart:403`、`round7_menu_capture_test.dart:325/328` | 单格换已删（P2-08） | `nutrition-menu-daily-set-repick` + 候选链仍在 |
| `dashboard_entry_routing_test.dart:80–115` | 入口不再跳页（P1-04） | `dashboard_meal_sheet_test` |
| `key_contract_test.dart` 的 `ai-chat-chip-can-i-eat` / `-apply-edits` | chip 改版（R16） | 新两枚 chip 断言 |

**原则**：每条都要在证据目录写「文件 / 断言 / 理由 / 替代」，与「删断言换绿」严格区分。
**特别注意第一条**：它是**语义变更**（同一件事换了正确档位），不是功能退役——必须在证据里单独说明。

---

## 6. 收敛判据

1. **P0 = 0**；**P1 = 9 全部闭环**（含新增的 P1-09），无「留待裁决」。
2. P2：应修 10 条闭环；2 条随退役消失。P3：修 3 条（P3-01/02/05），登记 2 条（P3-03/04）。
3. **控件门禁四层全绿**，且三条变异（M-G1/G2/G3）证明门禁真的会红。
4. 门禁**连续两次**全绿：format lib 0 / format test 0 / analyze `No issues found!` / 全绿 / exit 0 / `changed_during_run: []`。
5. **性能**：`query_benchmark_test` 三项劣化 ≤10%。
6. **Key 对账**通过；**分层边** 66 → 65（只减）。
7. 文档同步（见 B6-4）。
8. 设备实帧 ≥6 类：主页记录抽屉、两行数字卡、菜单照片封面、编辑卡行级应用、
   提炼忙态/结束分隔线、清空历史确认。
9. **执行期新发现的 P0/P1 也全部闭环**（登记在 `docs/57` 台账「执行期发现」栏），
   本轮新增 P0/P1 = 0。
10. **`run-log.md` 完整**：每个 ID 一行，含 RED 断言原文与门禁标签（供下一轮复核）。

---

## 6.5 默认动作表（遇到阻塞照此走，不停）

> 连续执行的核心是：**每个可能的阻塞都预先有答案**。下表任何一行命中时，按「动作」列执行并
> 在 run-log 写一行，然后继续下一条，**不询问、不等待**。只有 §1 第 4 条的三种情况才停。

| 阻塞 | 动作（直接执行，不询问） |
|---|---|
| 门禁跑不起来（`run.py` 报错/锁冲突） | 删 `flutter-running.lock` 重试 3 次；仍失败改直接调 `dart`/`flutter`；三次后记 `toolchain: blocked` 并**跳过该批门禁步骤**，继续下一批代码修复（门禁在 B6 统一补跑） |
| 单条测试报「Dart VM OOM / zone.cc」 | 关掉 AVD 释放内存后重跑；连续 2 次仍 OOM → 该文件单独重跑一次，再失败记 `env-flaky` 并继续 |
| 某条 RED 断言写出来就是绿的（说明假设错了） | **先信代码**：重读实现确认根因；若根因不成立，把该 ID 降级/改判并登记「原假设证伪」，继续下一条 |
| 某条 RED 修了两轮仍不绿 | 记 `blocked-2rounds` + 已试过的绕行，**跳过该 ID** 继续下一批；B6 末尾统一重试一次 |
| 修完发现连带把别的测试弄红了 | **立刻修到绿再前进**（唯一不能跳过的情形——带红前进会污染后续判断）；若 30 分钟内修不好，按批内 `git diff` 手工回滚该条，登记后跳过 |
| 性能劣化 >10% | 立即按备用方案改（P1-05 → 两段式查询）再测；仍劣化则回滚该条并登记，继续 |
| 设备（AVD）起不来 | 清锁/重启 3 次；仍失败 → `device: blocked`，用 widget 测试 + 历史帧替代，**不阻塞代码修复** |
| 无 `LF_AI_LIVE_KEY`（真实 AI 不可测） | 只做契约/mock 与文案层验证，记 `ai-live: not run`；**绝不声称真模型已验证**，继续 |
| Markdown 某语法实现超时（>1h） | 降级为「该语法按纯文本显示」，登记为 P2 观察项，继续其余语法 |
| 新发现 P0（崩溃/数据错/安全） | **就地修**，插到当前批最前面（P0 优先于一切），修完回到原顺序 |
| 新发现 P1 | 就地修（不排队），台账登记「执行期发现」 |
| 新发现 P2 / P3 | 只登记台账；P3 不修；P2 在 B6 统一处理 |
| 文档与实现冲突（`docs/21` Key 表等） | 以实现为准改文档（实现是事实），证据里注明「文档滞后已修」 |
| 测试退役时发现「其实还有用」 | 不删，改为「保留 + 注释说明为何仍有意义」，并在 §5 台账划掉该行 |

### 6.6 断点续跑（中断后如何接着跑）

**每完成一个 ID**，在 `docs/evidence/2026-10-24-batch4/run-log.md` 追加一行：

```
- 2026-10-24T03:15Z B2 · RV4-P1-01 完成（RED→GREEN；门禁 b4-fix2 未跑，批次未完）
```

**恢复时**：读 run-log 最后一行 → 从「下一个未出现的 ID」继续；批次级门禁若未记录则补跑。
**不要**从头重跑已完成的 ID（会重复改代码、重复退役断言）。run-log 每行同时记：
RED 断言原文（便于核对真红过）、改动文件列表、对应门禁标签。

---

## 7. 风险与回滚

| 风险 | 影响 | 缓解 |
|---|---|---|
| **L2 门禁是启发式** | 误判可维护性 | 首次落地把正常的两条（`lastResult`/`_identity`）写白名单并注明；豁免数冻结只减不增 |
| **B1 门禁故意红** | 易被误读为「没跑绿」 | B1 只逐文件跑 `test`，证据里写明三条红的原因与转绿批次 |
| `lf_buttons_test.dart:400` 需改写 | 容易被当成「删断言」 | 单列进台账第一条，说明是语义变更 |
| R4 整族退役（最大删除） | 8 份测试 + 4 文件 + 装配 | 拆 4a/4b，各自跑门禁；三表保留 |
| P1-05 加 `OR brand` | 全表扫变宽 | 先测 benchmark，>10% 改两段式 |
| P2-09 跳过 `userEdited` | 来源更新不落地 | 文档写清「手改即冻结」；若真不落地按 §7 默认动作（改回覆盖 + 如实写明），**不停** |
| P2-10 漏搬底栏预留 | 最后一行点不到 | 必须有几何断言 |
| Markdown 自写解析器 | 畸形输入崩溃 | 全容错降级 + 随机拼接测试 |
| 清空历史不可逆 | 数据删除 | 二次确认 + 报数 + 图片副本一并清 |

**回滚粒度**：每批一个门禁标签；任一批不绿即停在该批内修，不带病进下一批。

---

## 8. 立即开始

```bash
cd E:/AI/Zcode/projects/localfit-ai/localfit-ai
# B1-2：先写 L2 门禁（这是训练天数那个 bug 的直接防线），跑它有且只有 1 处红
python E:/AI/zcode/tmp/localfit-round7-native-20261014/run.py b4-gate-l2 test test/app/interaction/notifier_listeners_gate_test.dart
```

顺序：**B1（L1→L2→L3→L4→留档）→ B2（01→02→09→07→P2-01）→ B3（04→05→06→4a）→
B4（03→09→08→10）→ B5（07→02→04/05/06→08→03→R16）→ B6（4b + 11/12 + 文档 + 双门禁 + APK）**。
