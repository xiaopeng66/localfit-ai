# 批次 4 全面审查报告（2026-10-24）

> **审查对象**：`E:/AI/Zcode/projects/localfit-ai/localfit-ai`（lib 375 个 Dart 文件 / test 381 个 / schema 30）。
> **触发**：用户 2026-10-24 提出的 17 条需求（[`docs/56`](56-batch-review-plan-2026-10-24.md) 已把诉求拆成 R1–R17 并定稿 7 条裁决）。
> **方法**：静态阅读（含逐文件行号）+ 定向测试 + **变异抽验** + 度量计算（对比度/排序位次）；**未改一行 `lib/`**。
> **配套**：修复计划 [`docs/58`](58-remediation-plan-batch4.md)；证据 [`docs/evidence/2026-10-24-batch4/`](evidence/2026-10-24-batch4/)。
>
> **结论一句话**：**能用，但有 9 条 P1 是「功能确实不工作 / UI 说的是假的 / 读屏读不出」级别**——其中 3 条（照片永不显示、
> 天数界面上不动、删除提示永不消失）在 2856 条测试全绿的情况下**零覆盖地**活到了今天。这批必须修，
> 且每条都要先补断言再改代码。

---

## 0. 结论摘要

| 级别 | 数量 | 含义 | 处置 |
|---|---|---|---|
| **P0** | **0** | 数据丢失 / 崩溃 / 静默写错事实 / 安全 | 无 |
| **P1** | **9** | 功能不可用、UI 与实际行为不一致、核心检索失效、无障碍语义缺失 | **全部本轮修** |
| **P2** | **12** | 体验缺陷、冗余入口、缺失的便利能力、AI 呈现 | 本轮修 10 条；2 条随功能退役消失 |
| **P3** | **5** | 可维护性、一致性、体积预算 | 修 3 条；2 条登记接受 |

**三条最值得注意的事**（不是「又一个 UI 小问题」）：

1. **`SnackBar` 带操作按钮时永不消失**，是 Flutter SDK 的默认值（`persist = persist ?? action != null`）。
   我们的删除流正好命中：删完一餐，「餐食已删除 + 撤销」永久挂在屏幕上。**两条调用点，286 秒的全量测试一条都没测它会不会消失。**
2. **训练计划的天数选择器界面不动、但发出去的值变了**。`ValueNotifier` 没有监听者，点「4天」胶囊仍显示 3 天选中，
   而 `_buildRequest()` 读到的是 4 —— **界面在骗用户**。这比「点不动」更严重。
3. **食堂菜的照片永远不进菜品库**。`DishDraft` 构造时没传 `imagePath`，所以 `DishCard` 那套 4:3 封面代码
   写得很完整却永远走渐变占位。变异实验证明：**把它补上，12 条测试全绿、一条不变**。

---

## 1. 基线与方法

### 1.1 基线（审查前实测）

| 项 | 值 | 证据 |
|---|---|---|
| 门禁 `batch4-review-baseline` | format lib 0 / format test 0 / analyze 干净 / **`+2856 ~66`** / exit 0 / `changed_during_run: []` | `baseline.md` |
| Key 三方对账 `batch4-review-keysync` | 通过（单测断言「无缺口」） | 同上 |
| schema | 30 | `app_database.dart` |
| AI 命令 | 37 | `chat_edit_registry.dart` |
| 分层跨 feature 边 | 66（冻结） | `architecture_layering_test.dart` |
| 备份覆盖 | 41 key / 43 表；缺 `embedding_index`+`background_jobs`（**已裁决例外，断言中显式列出**） | `export_restore_test.dart` |
| TODO/FIXME/HACK | **0** | `static/scan.md` §6 |
| 空 `catch` 块 | **0** | 全仓扫描 |

### 1.2 方法

| 手段 | 用途 | 局限（如实） |
|---|---|---|
| 逐文件静态阅读 + 行号定位 | 全部 22 条发现的直接证据 | 无运行时验证 |
| 定向测试复跑 | 确认基线绿、定位断言缺口 | 只能证明「已覆盖的没坏」 |
| **变异抽验 3 点** | 区分「测试有效」与「测试空转」 | 只抽 3 点，非全量变异 |
| 对比度/WCAG 计算 | 选中态、SnackBar 动作色 | 计算值，未取设备实帧 |
| 随包 CSV 复算排序 | 验证搜索位次（154 条命中 / 第 32 位） | 用真实种子数据，非模拟 |
| 设备 `adb` | 确认 AVD 在线与包名 | **本轮未做界面实帧**（审查阶段只读） |

**明确未做**（见 §5）：设备界面实帧、真实 AI 一轮（无 `LF_AI_LIVE_KEY` 于本会话环境）、arm64 真机、性能帧率采集。

---

## 2. 维度 A–P 逐维结论

> 每维给「检查了什么 / 结论 / 挂了哪条 ID」。ID 详见 §3 台账。

### A 界面视觉
**检查**：token 一致性、硬编码颜色、字号层级、卡片/按钮形态、对比度、图片占位、选中态可辨识。
**结论**：设计系统执行得好（375 文件里只有 13 处非 token 颜色，全在 `app/design/widgets` 内部做阴影/纯白遮罩这类合理场景）；
**唯一硬伤是选中态语义反了**——`LfPillButton` 的选中底 `#ECFBF5` 对白卡 1.07，未选中的 `muted #EFF3F1` 对白卡 1.12，
**未选中比选中更显眼**，在页底（`#F7F9F8`）更极端：1.01 vs 1.06。这不是「淡了点」，是顺序颠倒 → `RV4-P1-07`。
卡片封面的代码是完整的，但数据侧永远不给图 → `RV4-P1-03`（属 A 的上屏结果，根因在 C/H）。

### B 交互与手势
**检查**：热区、弹层 navigator、反馈位置、危险操作确认、连点防重、撤销通道。
**结论**：弹层规范执行严格（`showModalBottomSheet` 5 处全部 `useRootNavigator: true` + 弹层内 `Builder` context，
有历史坑注释）。**但撤销通道本身是坏的**：带「撤销」的提示条永不自动消失 → `RV4-P1-01`；
撤销按钮走 `ColorScheme.secondary`（= 全局 mint）、12px、无字重，在墨绿底上不够跳 → `RV4-P2-01`。
另有一处绕开统一出口的裸 `SnackBar`（`ai_memory_page.dart:1032`）→ `RV4-P3-05`。

### C 功能逻辑闭环
**检查**：每条写路径的入口→仓储→表三跳、重复提交幂等、UI 与实参一致。
**结论**：写路径本身健康（单一路径、幂等守卫齐全：`_saving` / `_inFlight` / 900ms 冷却都在）。
**两处闭环断裂**：
① 训练计划天数：UI 读 notifier 但不监听，**界面显示与实际请求分叉** → `RV4-P1-02`；
② 菜品照片：食堂菜 → 菜品库这条链漏了 `imagePath` 字段，功能从未成立 → `RV4-P1-03`。

### D 状态一致性与并发
**检查**：跨页一次性意向、生命周期、跨零点、流订阅收敛。
**结论**：意向通道设计正确（`MealAddIntent.take()` 消费即置空，避免「诈尸弹框」）；跨零点 `DailyRollover` 两页都在用。
**一处架构错位**：主页的记录入口把「切页」和「开弹层」绑在一起（先 `go(nutrition)` 再由目标页开层），
结果是用户被带走 → `RV4-P1-04`。这是 R2 的根因，不是并发问题。

### E AI 适配性与可用性
**检查**：37 命令注册/执行/测试三处一致、提示词与现行能力对齐、降级矩阵、上下文预算、回复可读性。
**结论**：命令层一致（37/37，`chat_edit_registry` 为单一事实源）；降级矩阵 159 行常量在。
**三类问题**：
① `daily-menu-plan` 启动卡的提示词**仍要求模型返回已在 `RV2-P2-01` 整族退役的 v1 JSON 形状** → `RV4-P1-08`；
② AI 回复纯文本直出，`**加粗**`/列表/代码块原样带符号上屏 → `RV4-P2-02`；
③ 食堂「AI 分析」把 `[canteen-dish:<id>]` 原样塞进用户气泡 → `RV4-P2-03`。
对话侧还缺三件可用性：提炼无进行中状态（`RV4-P2-04`）、结束会话无界面变化（`RV4-P2-05`）、
历史无法清除（`RV4-P2-06`）。编辑卡只有组级应用，行级能力其实早已具备（`onApplyRows`）→ `RV4-P2-07`。

### F 端上检索与推荐
**检查**：搜索排序、上限、别名/品牌参与、按菜品选择器、推荐整套性。
**结论**：**这是本轮缺陷最密集的维度**。
- 食材搜索对「鸡蛋」命中 154 条，`鸡蛋（熟）` 按现有排序（`instr` → 名称长度）落在第 **32** 位，
  而结果区只取 **10** 条 ⇒ **匹配是对的，被排序和上限藏了** → `RV4-P1-05`。
- 品牌完全不参与检索：搜「千丰香米」搜不到「米饭」（`page()` 只 `like(name)`）→ 同属 `RV4-P1-05`。
- 「按菜品记录」是**无搜索的整表列表**，且确认层把餐次当只读文案，用户无法改 → `RV4-P1-06`。
- 推荐的三格各自「换一个」会破坏整套营养平衡 → `RV4-P2-08`。
- 陈旧提示 + 手动同步在两库合并后已成冗余（自动同步覆盖六条写路径）→ `RV4-P2-09`。

### G 底层运行逻辑与使用习惯
**检查**：两库合并后的身份键、自动同步的触发面、旧数据补齐、用户手改的优先级。
**结论**：两库合并的**底层联系是真实存在且正确的**——`(sourceType='canteen', sourceId=menuItemId)` 为身份键，
建菜/改名/换照片/写营养/删菜/删窗口/删地点七条路径都挂上了钩子，且 `_updated` 用
`existing.userEdited || draft.userEdited` 保住了用户手改标记（上一轮自审抓出的自伤 bug 已修）。
唯一遗留是 UI 层还在提示「食堂营养更新」并要用户点「同步」→ `RV4-P2-09`。

### H 数据与迁移
**检查**：schema、备份/恢复、全清保留、未来日期、日期解析。
**结论**：健康。schema 30 冻结；备份 41 表 + 2 张派生表显式豁免（断言钉死，新增第三张会红）；
全清保留内置食物的判定在 `_isPreservedFoodTable`；AI 路径有未来日期拦截（`chat_edit_executor.dart:1182`）。
本轮唯一与数据语义相关的是 `RV4-P2-09`（陈旧/同步退役时**必须保住 `userEdited` 不被静默覆盖**）。

### I 错误与降级
**检查**：失败分支文案、是否吞异常、降级矩阵上屏、未接线入口。
**结论**：`catch (_) {}` 空吞 **0 处**；`on Object catch` 13 处全部有后续处理或注释说明；
未接线时按钮不渲染（`null` 回调即不画）纪律执行到位。
`RV4-P2-10`：`ai_memory_page` 那条裸 `SnackBar` 不走主题、不带图标，是同一条规范的例外。

### J 性能
**检查**：查询基准测试在门禁内、搜索全表扫、列表规模。
**结论**：`query_benchmark_test`（今日页首查 / 30 天趋势 / 搜索首批）在门禁内持续跑，绿。
**风险点（待修后复测）**：`RV4-P1-05` 的修法若要加 `OR brand LIKE`，会让本来已无索引的全表扫再宽一层，
**必须复跑 benchmark，p95 劣化 >10% 就改用两段式查询**（先 name 后 brand）。这条写进了修复计划的验收条件。

### K 无障碍与适配
**检查**：语义标签、`ExcludeSemantics`、大字（2.0×）、320dp 窄屏。
**结论**：`Semantics` 81 处 / `ExcludeSemantics` 33 处，比例健康；食物行已修过「读屏要能区分同名」（`添加 米饭（千丰香米）`）。
**两处缺口**：
① 食物库列表行（`FoodCard`）的语义 label 还没有品牌 → 与 `RV4-P2-11` 同批修；
② **`LfPillButton` 从不发 `Semantics(selected)`**（`RV4-P1-09`）——注释与实现不符，
   读屏用户听不出哪枚胶囊被选中。这条尤其重要，因为它正是 `RV4-P1-02`（训练天数）的隐藏面：
   即使把界面重建修好了，语义层仍然说不出「5 天被选中」，而 `docs/21` 的 Key/语义契约要求可读。

### L 隐私与安全
**检查**：AI 出口端点、凭据存储、图片副本、备份加密、清全。
**结论**：AI 出口只走用户配置的 BYOK 端点（`dio` + transport 层统一），凭据在 secure storage；
聊天图片副本随「清除全部本地数据」删除；`.lfb` 有封套上限测试。
本轮新增的「清空聊天历史」（`RV4-P2-06`）按**破坏性操作**对待：二次确认 + 如实报数 + 图片副本一并清。

### M 代码健康（死代码 / 重复 / 体积）
**检查**：public 符号引用计数、`lib` 单处出现扫描、超大文件、死形参。
**结论**：
- 真正的死符号候选 **4 个**（`isNormalizedFoodName`、`canteenOriginExplanation`、`tasteVectorSamplesFromMeals`、
  `exerciseCardExtentForTesting`）——其中后两个有测试引用，属「仅供测试」→ `RV4-P3-02`。
- **死形参 2 个**：`CanteenDirectoryPage.decisionController` / `.mealRepository`（代码注释自认「形参保留、不再消费」）→ `RV4-P3-01`。
- 超 1000 行非生成文件 **10 个**，最大 `training_page.dart` 2923 行 → `RV4-P3-03`（登记，不在本批拆）。
- 硬编码颜色 13 处，全在设计系统内部 → `RV4-P3-04`（登记接受）。
- **本轮没发现新的重复实现**：`mealSlotLabel` 只有一处权威实现 + 一处映射函数，其余都是读 `slot.label`。

### N 测试质量
**检查**：断言是否真的能抓缺陷（变异抽验）、退役台账、盲区定位。
**结论**：**这是本轮最重要的发现维度**。三个变异点结果：
| 变异 | 结果 | 含义 |
|---|---|---|
| 搜索排序 `desc→asc` | **RED** | 检索测试有效 |
| 补上缺失的 `imagePath` | **全绿不变** | **盲区**：照片同步零断言 |
| 选中态对比度 | 无测试 | **盲区**：1.07 vs 1.12 无人察觉 |

同样零覆盖的还有：SnackBar 是否消失、天数选中是否重建、`plan-days-*` 的任何断言（`grep` 在 `test/` 下 **0 命中**）。
⇒ 这三条 P1 能活到今天，**不是实现疏忽，是验收从未覆盖**。修复计划里每条都要求先补断言。

### O 文档一致性
**检查**：`docs/21` Key 表 ⇄ lib ⇄ test 三方对账、STATUS/INDEX 与代码现状。
**结论**：Key 对账 **通过**（338/338 的机制仍在，单测跑绿）。
`docs/56` 与 `docs/57`/`docs/58` 的引用已互相连通。
**待修后同步**：`docs/21` 要新增 `LfPillTone.selected` 档、三枚 chip 的改版、退役的 Key
（`-swap`、`food-library-footer*`、`food-reference-source/-evidence`、`ai-chat-chip-can-i-eat`）。

### P 构建与发布
**检查**：版本号偏移、分 ABI、`dist/`、sha256。
**结论**：`docs/09` §D 的 x86_64 偏移已按实测修正为 **+4000**（上一轮用两次构建验证）。
本次审查**未构建、未发布**（审查阶段只读）。修复完成后按 §批次 5 重建 APK 并更新 `dist/`。

---

## 3. 缺陷台账（`RV4-*`）

> 定级口径：P0 数据/安全；P1 功能不工作或 UI 说谎；P2 体验/缺失能力/呈现；P3 可维护性。
> 「证据」列均可在 `docs/evidence/2026-10-24-batch4/` 或指明的文件行号处复核。

### P1（8 条，本轮必修）

| ID | 现象 | 根因 | 证据 | 对应需求 |
|---|---|---|---|---|
| **RV4-P1-01** | 「餐食已删除」提示永不消失 | SDK `SnackBar.persist = persist ?? action != null`；`AppSnackBar.showOn` 传了 `actionLabel` 却没传 `persist` | `app_snack_bar.dart:47–75`；SDK `snack_bar.dart:303`；调用点 `nutrition_actions.dart:193/223` | R5 |
| **RV4-P1-02** | 训练天数点不动；界面显示 3 天但实际按 4 天发请求 | `_days` 是 `ValueNotifier`，`_FormView` 是 `StatelessWidget` 只读 `.value`，全文件无监听 | `workout_plan_create_page.dart:68/376`；`grep plan-days- test/` = 0 | R17-a |
| **RV4-P1-03** | 食堂菜有照片，菜单/菜品库永远是渐变占位 | `AddCanteenDishesToLibrary.run` 构造 `DishDraft` 未传 `imagePath` | `add_canteen_dishes_to_library.dart:105–124`；变异 M2 全绿不变 | R10-b |
| **RV4-P1-04** | 主页点「记录晚餐」被带到饮食页（食物库），退出也回不去主页 | 入口拥有者选错：`onLogMeal` 先 `mealAddIntent.request` 再 `go(nutrition)`，由目标页开层 | `app_router.dart:427–430`；`nutrition_page.dart:191–197` | R2 |
| **RV4-P1-05** | 搜「鸡蛋」看不到「鸡蛋（熟）」；搜品牌搜不到 | 排序 `isUserCreated→精确→instr→length`，括号变体排到第 32 位，而 `limit=10`；`page()` 只 `like(name)` | CSV 复算：154 命中 / `鸡蛋（熟）` 第 32；`food_repository.dart:59–99` | R3-a |
| **RV4-P1-06** | 「按菜品记录」无搜索框；确认时不能改餐次 | `DishMealPickerDialog` 是整表 `ListView`；`DishMealConfirmSheet` 把 `dish.mealSlot` 当只读文案 | `meal_entry_chooser_sheet.dart:107–201 / 204–277` | R3-b |
| **RV4-P1-07** | 选中态比未选中更不显眼 | `selected && muted → soft`，`soft` 底 `#ECFBF5`（对白卡 1.07）< 未选中 `muted #EFF3F1`（1.12） | `lf_buttons.dart:325–343`；计算见 `docs/56 §4.1` | R17-b |
| **RV4-P1-08** | 「生成今日吃法」要求模型输出已退役的 `daily-menu-plan v1` JSON | 解码器在 `RV2-P2-01` 整族退役，提示词模板未同步 | `ai_workbench_prompt_templates.dart:58–81`；`ai_starter.dart:114` | R12 |
| **RV4-P1-09** | 选择语义胶囊**从不发** `Semantics(selected)`，读屏听不出「哪个被选中」 | `LfPillButton` 的类注释写「选中：加 `Semantics(selected)`」，但 build 里只有 `PressableScale` + `TextButton`，**没有任何 Semantics 包裹**。对照：`LfFilterChip`/`AppMorphChip`/`LfSegmentedToggle`/`meal_editor_dialog._SlotPill` 四处都真发了 | `lf_buttons.dart:306–313`（注释）vs `:320–367`（实现）；四处对照见 `lf_filter_chips.dart:42`、`app_morph_chip.dart:80`、`lf_segmented_toggle.dart:213`、`meal_editor_dialog.dart:508` | R17 |

### P2（12 条）

| ID | 现象 | 根因 | 证据 | 对应 |
|---|---|---|---|---|
| **RV4-P2-01** | 撤销按钮在黑底上不够跳 | `snackBarTheme` 无 `actionTextColor`/`actionTextStyle`，回落 `ColorScheme.secondary`（12px 无字重） | `app_theme.dart:293–300` | R5 |
| **RV4-P2-02** | AI 回复原样显示 `**`、`- `、代码围栏 | `AiMessageBubble` 是纯 `Text`；协议只约束信封不约束纯文本 | `lf_chat_bubbles.dart:62–100` | R13 |
| **RV4-P2-03** | 食堂「AI 分析」的用户气泡带 `[canteen-dish:<id>]` | 启动提示词直接当用户消息发送，显示文本 = 发送文本 | `app_router.dart:444–460` | R14 |
| **RV4-P2-04** | 点「提取记忆」后界面无任何进行中提示 | `_extractingMemory` 只用于挡重复点击，不上屏 | `ai_conversation_page.dart:631–707` | R11-a |
| **RV4-P2-05** | 「结束本次会话」点了没有可见变化 | 只有 snackbar；无会话边界状态、无分隔线 | `ai_conversation_page.dart:709–745` | R11-b |
| **RV4-P2-06** | 对话历史无法清除 | 仓储接口只有 `loadRecent`/`save` | `conversation_message_repository.dart` | R11-c |
| **RV4-P2-07** | 编辑卡只能「应用本组/全部应用」 | 行级能力已在控制器（`onApplyRows`），UI 只画徽标 | `chat_edit_card.dart:531–537` | R15 |
| **RV4-P2-08** | 每格「换一个」破坏整套平衡 | 三格各持 `_swapOffset`，独立循环 | `menu_dish_list.dart:627–660` | R10-a |
| **RV4-P2-09** | 「食堂营养更新」+ 手动同步冗余；且退役有覆盖用户手改的风险 | 自动同步已覆盖七条写路径，UI 仍按旧模型提示 | `dish_staleness.dart` / `dish_source_sync.dart` / `dish_card.dart:203–213` | R10-c |
| **RV4-P2-10** | 食物库页尾「导入/管理」与设置页重复 | 两处入口同一能力；页尾条还承担底栏预留 | `food_library_footer.dart`；`nutrition_tab_bodies.dart:76` | R9 |
| **RV4-P2-11** | 食物库卡片不显示品牌，同名无法区分 | 2026-10-08「单行三件」改造把品牌行整条删除，参数保留未用 | `food_card.dart:67–92 / 126–200` | R8 |
| **RV4-P2-12** | 引用食物库弹层：候选卡贴在一起、底部两枚徽标无意义、两枚动作上下堆叠 | `Column` 直接排 `_CandidateRow`（各带 1px 描边、零间距）；徽标在建菜语境无信息 | `food_reference_sheet.dart:96–146` | R6 / R7 |

### P3（5 条）

| ID | 现象 | 证据 | 处置 |
|---|---|---|---|
| **RV4-P3-01** | `CanteenDirectoryPage.decisionController` / `mealRepository` 是死形参 | `canteen_directory_page.dart:45–46`（注释自认） | 随 R4 退役删 |
| **RV4-P3-02** | 4 个疑似死符号 | `static/scan.md` §3 | 逐一确认后删 2 个、保留 2 个（测试专用） |
| **RV4-P3-03** | 10 个非生成文件 > 1000 行（最大 2923） | `static/scan.md` §2 | **登记接受**（拆分会动 Key 与测试面，单独立项） |
| **RV4-P3-04** | 13 处硬编码颜色 | `static/scan.md` §1 | **登记接受**（全在设计系统内部的阴影/纯白遮罩） |
| **RV4-P3-05** | `ai_memory_page.dart:1032` 裸 `SnackBar` 绕开统一出口 | 全仓唯一一处 | 改用 `AppSnackBar` |

---

## 4. 交叉验证：三条「假绿」是怎么形成的

这三条值得单列，因为它们说明**测试全绿 ≠ 功能可用**：

| 缺陷 | 门禁为什么没红 | 缺的是哪种断言 |
|---|---|---|
| `RV4-P1-01` 提示不消失 | 测试只验证「撤销按钮存在且可点」，从不推进时间 | 「一段时间后应当消失」的时间断言 |
| `RV4-P1-02` 天数界面不动 | `test/` 下 `plan-days-` **0 命中**；现有训练测试只点关键词与「下一步」 | 「点选后选中态迁移」的 widget 断言 |
| `RV4-P1-03` 照片不显示 | `canteen_dish_library_sync_test` 12 条覆盖营养/来源/级联，独独没有 `imagePath` | 「来源有照片 → 目标行有照片」的数据断言 |

`RV4-P1-05`（搜索）不同：它有测试且变异能抓（M1 RED），只是**测的都是「能不能搜到」，没有一条测「括号变体在不在前 10」**。

---

## 5. 未覆盖清单（如实）

| 项 | 为什么没做 | 影响 |
|---|---|---|
| 设备界面实帧 | 审查阶段只读，且本轮改动尚未开始 | 视觉结论（对比度、间距）来自计算与代码，非实拍；修复后补帧 |
| 真实 AI 一轮 | 本会话环境无 `LF_AI_LIVE_KEY` | `RV4-P1-08`/`RV4-P2-02`/`RV4-P2-03` 只做契约与文案层验证，不声称「真模型已验证」 |
| arm64 真机 | 无设备 | 只保证模拟器（`emulator-5554`） |
| 1000 行滚动帧率 | 无 profile 采集条件 | 不提供帧率数字 |
| 全量变异 | 只抽 3 点 | 其余路径的测试有效性未逐一验证 |
| iOS 构建 | 本机无法验证 | 与上轮一致 |

---

## 5.5 执行期发现（2026-10-24 批次 4 修复期间新增）

> 按 `docs/58` §1.6「发现问题随时回流」。**本轮新增 P0 = 0**。

| ID | 级别 | 现象 | 处置 |
|---|---|---|---|
| **EXEC-P1-01** | **P1** | `GoalBigCard`（引导页 / 编辑资料的训练目标大卡）是**单选卡**，但不发 `Semantics(selected)` —— 与 `RV4-P1-09` 同族。审查报告只点了 `LfPillButton`，这条是写 L3 门禁时抓出来的 | **已修**（B2，与 P1-09 同批）：外层 `Semantics(button, selected)` + 内层 `ExcludeSemantics`。断言：`control_semantics_selected_test.dart` 的 `GoalBigCard（亮/暗）` 两条 |
| **EXEC-P2-01** | P2 | `docs/58` §2.5 写的「175 处裸控件 / 38 处缺 Key」是**子串误算**（把 `LfTextButton(` 也算成裸 `TextButton(`） | 按**更严格**的实测口径（`lib/features/**` + 7 类裸交互件 + 实参无 `key:`）冻结为 **9 处**，比 38 更紧。登记在 `interactive_key_budget_test.dart` 的注释与 `tests/gates-summary.md` |
| **EXEC-P2-02** | P2 | `SnackBarThemeData` 在本仓 Flutter **3.47.2 没有 `actionTextStyle` 字段**（`docs/58` P2-01 写「加 `actionTextStyle: w600`」不可达；`SnackBarAction` 内部是普通 `Text`） | 按 §6.5「文档与实现冲突以实现为准」改为「专用高对比动作色 + `actionOverflowThreshold`」；暗色首版取 `mint-300` 实测对比 **1.41** → 改 `mint-400`（8.5:1）。登记在 `app_snack_bar_test.dart` 与 `docs/21` |
| **EXEC-P2-03** | P2 | `DishMealConfirmSheet` 的 `Key('dish-meal-confirm')` **同时挂在内容 Column 与确认按钮上**（`tap` 报「ambiguous, found 2」；既有 `key_contract_test` 只查存在性所以没抓到） | **已修**：内容根改 `dish-meal-confirm-body`，动作钮保留契约名；`key_contract_test` 的断言随之改到 `-body` |
| **EXEC-P3-01** | P3 | `LfPillButton` 加 `ExcludeSemantics` 会吞掉**动作按钮**用法（13 处）的 label/tap 语义（`next_meal_decision_card_test` 立刻红） | 改为 `Semantics(container: false, selected:)` **叠加**，不动按钮原有语义。登记在 `lf_buttons.dart` 注释 |
| **EXEC-OBS-01** | 观察 | 全量 gate 偶发 **Dart VM OOM / 连接关闭**（`round7_*_capture_test`、`catalog_search_perf` 等），单独跑或清锁重跑即绿 | 按 §6.5「Dart VM OOM」处置：杀残留 `flutter_tester` + 清 `flutter-running.lock` 重试；已发生的两次都如实记进 run-log，**未改任何断言** |

## 6. 收敛判断

**当前状态**：P0 = 0；P1 = 9（全部有明确根因与修法）；P2 = 12；P3 = 5。
**是否可发版**：功能主体可用，但 9 条 P1 里有 3 条是「用户会直接撞上」的（提示不消失、天数选择失灵、照片不显示），
**建议修完再发**。
**收敛条件**（[`docs/58`](58-remediation-plan-batch4.md) §6 展开）：P1 全闭环且每条有先红后绿的证据；
P2 该修的 10 条闭环、退役类 2 条随代码消失；门禁连续两次全绿且 `changed_during_run: []`；
三项性能基准无劣化 >10%；文档（`docs/21` Key 表、STATUS、INDEX）与代码一致。
