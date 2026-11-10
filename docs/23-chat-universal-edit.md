# docs/23 — AI 对话通用编辑（chat-edit v1）

> 状态：**normative**（与 docs/21 §5.7 冲突时以本文为准；docs/07 §4 合同清单同步）。
> 需求（用户原话）：「软件内所有可编辑的内容，都允许 ai 对话给我修改，你要做好接口，
> 保证 ai 可以识别我的对话，做出所有的调整」。
> 日期：2026-10-02。

## 0. 一句话架构

AI 对话保持「文本进、文本出」；新增一层**编辑协议**：

```
用户消息 ──┐
           ├─→ ConversationController ──→ AiConversationService（+systemContext）
可编辑快照 ─┘                                     │ 流式文本
                                                  ▼
                              完成时解析 chat-edit.v1 信封（严格 decoder）
                                                  ▼
                        编辑卡（AI 提议，用户点「应用」才写库）──→ ChatEditExecutor
                                                  ▼                     （逐条校验/落库）
                                        每条结果 ok/failed 回写卡片并落库
```

四条硬规则（违反即返工）：

1. **AI 提议 ≠ 事实**。任何编辑必须先渲染成编辑卡，由用户点「全部应用」才执行；
   executor 再按仓储自己的校验（量纲/区间/存在性）逐条落库，失败逐条如实显示，绝不静默。
2. **不猜 id、不猜名字**。改/删目标优先用快照里给的真实行 id；按名字定位只在
   「精确同名且唯一」时接受，命中多个或零个都报错给人话。
3. **设置与凭据永不可经对话修改**（AI 提供方、API Key、备份开关——安全边界，不在注册表里）。
4. **快照是新增出网数据**，必须在披露（docs/08 §3）里写清发了什么；快照只含
   「可编辑实体的 id+名字+关键数值」，绝不含 API Key、照片、完整食物目录。

## 1. chat-edit.v1 信封（模型输出契约）

模型两种合法回复：

- 纯文本（闲聊/问答，不修改）——原样渲染。
- **JSON 对象**：`{"reply": "<给用户看的中文说明>", "edits": [{"action": "<命令名>", "args": {…}}, …]}`。

解码规则（`parseChatEditEnvelope`，严格）：

- trim 后不以 `{` 开头 → 不是信封，按纯文本处理（返回 null）。
- `jsonDecode` 失败 / 顶层不是 Map / 缺 `reply`（非 String）/ `edits` 不是 List → 整体视为纯文本。
  **宁可当闲聊也不半信半疑**：坏信封不产生任何编辑卡。
- 每个 edit：`action` 必须是注册表里的命令名，`args` 必须是 Map；逐条校验
  （类型/区间/枚举/必填），**单条无效只废那一条**（卡片上显示失败原因），不连坐整包。
- `edits` 上限 **10** 条/回复：超出整包拒绝（防一次回复写一大片）。
- 数字必须是有限数（NaN/Infinity 拒绝）；未知 action 报「不支持的修改类型」。
- 编码回存（落库）：`encodeChatEditEnvelope` 把 executor 的逐条结果并进同一对象
  （`"outcomes": [{"index":0,"ok":true}, {"index":1,"ok":false,"message":"…"}]}`），
  重启后按文本重新解析即可还原卡片状态——**不新增 schema 列**（表 `ConversationMessages`
  不加 kind 列，形态仍由内容推导）。

**2026-10-16 扩（用户：「对话中遇到问题要推荐回答并弹出可点选按钮」+「添加鸡肉食材
为什么没有应用按钮」）**，三项都是**加在既有信封上的可选能力**，旧信封行为不变：

1. **可选 `suggestions` 通道**：`"suggestions":[{"label":"按钮短文案","action":"命令名","args":{…}}]`，
   0–3 条（`maxSuggestionsPerReply`）。每个建议与 `edits` 用**同一套**校验
   （未知 action / 空 label / 参数不合法 → **只丢这一条建议**，不降级整段回复）；
   点了按钮 = 应用那条命令（同一 executor），状态就地回写（已应用 / 失败 + 原因）并随卡落库。
   **不变式放宽一条**：`edits` 与 `suggestions` **不能同时为空**——`edits:[]` +
   非空 `suggestions` 现在合法（只给按钮、不写库，例如先问用户选哪一餐）；两者都空仍是纯文本。
2. **口语 = 命令**（协议规则 5）：日常说法（添加/记录/记一下/删掉/改成…）要直接翻译成
   命令输出信封，不许因为用户没说命令名就只回文字。缺库食材要 `food.create` 建它
   （规则 6），而不是只回「库里没有」。
3. **App 侧兜底「缺实体」**（2026-10-16 扩到四类）：执行器零命中时把失败升格成
   结构化 `ChatEditRepair`，编辑卡在那一行下渲染 `chat-edit-repair-<n>-<m>` 按钮，
   点了开**预填名称**的既有表单——营养值/时间/校区这些仍由用户填，App 绝不替用户
   编数据。该提示随 `outcomes[].repair`（含 `kind`，窗口还带 `venueId`）落库回环：

   | kind | 按钮 | 点开 |
   |---|---|---|
   | `createFood` | 创建食材「X」 | 新建食物弹层（`NewFoodDialog.prefillName`） |
   | `createExercise` | 新建动作「X」 | 新建动作弹层（`showCreateExerciseSheet`，从动作库页提出共用） |
   | `createVenue` | 新建地点「X」 | 添加食堂地点弹层（`MenuFormPrompts.promptAddVenue(prefillName:)`） |
   | `createWindow` | 新建窗口「X」 | 添加窗口弹层（带归属 `venueId`；一个地点都没有时不给按钮） |

   （菜品没有这一档：`dish.upsert` 本身就是「按名字新建或更新」，不存在「库里没有
   这道菜」的失败路径。）

4. **修改请求不许空回文字**（2026-10-16 用户要求：「对话只要涉及让你修改，就必须
   正确识别指令，而不是空回文字」）。三层保障：

   * **协议层**：规则 5 写成硬规则——含增/删/改意思的话必须给信封或 `suggestions`，
     缺信息也要给信封（`edits` 可空 + suggestions 候选）；
   * **App 自动补救**：`ConversationController` 在「用户消息像修改请求
     （`looksLikeModificationRequest`，保守启发式）＋ 回复没解析出信封」时，
     **自动带提示重跑一次**（提示写进 system 段、不插假的用户消息），每轮最多一次；
   * **手动兜底**：自动催过仍是纯文本时，该助手气泡下给一枚
     `ai-chat-request-envelope-<n>`「让 AI 给出可应用的修改」词条；这条残留的判定
     从**落库的消息**重算（末条纯文本 + 其上一条用户消息是修改请求），所以**重启后
     仍在**。

流式显示规则（页面）：缓冲区 trim 后以 `{` 开头 → 显示「正在生成修改方案…」占位，
完成后再换成 reply+卡片；否则照常流式。最终若 JSON 解析失败，全文按普通回复显示。

## 2. 命令注册表（v1，2026-10-17 起 **37 条**，与仓储写入方法一一对应）

> 2026-10-16（Round9 第二批）**35 条**：新增 `canteen.dish.nutrition`
> （N3 落库口）；同批 `canteen.dish.create/update` **删掉 `priceYuan`** 参数
> ——食堂菜品价格整条退役（DB 列随 v26 删除，见 `docs/03 §4` 末注与 `docs/36 §3`）。
> 2026-10-17（docs/38 S11）**37 条**：新增 `memory.remember` / `memory.forget`
> （长期记忆的显式写入与如实遗忘；分工见协议规则 11——能落结构化字段的一律
> 用对应命令，不进记忆）。
>
> 2026-10-15（docs/34 §7，用户指示补全）从 23 条扩到 34 条：训练域 6 条
> （`session.start` / `set.log` / `session.finish` / `plan.entry.add` /
> `plan.entry.remove` / `plan.rename`）、自建食物与资料/目标 4 条
> （`food.update` / `food.delete` / `profile.body.update` / `targets.update`）、
> 菜单快照 1 条（`menu.snapshot.publish`）。**逐条实测表在 `docs/34` §2.1**，
> 每条的落点与实时验证结果都在那里；本节表格自此只列 v1 的 23 条骨架，
> **注册表 `chat_edit_registry.dart` 始终是单一事实源**。

注册表是**单一事实源**：decoder 按它校验，executor 按它分发，system prompt 里的
命令清单由它渲染（`ChatEditCommandRegistry.renderProtocol()`）。新增可编辑面 =
注册一条 spec + 一个 apply 分支 + 测试。

> P11 实测硬化（2026-10-07，docs/evidence/2026-10-05-ai-live-endpoint.md §3）：
> 协议段补了三条提示——`edits` 不能是空数组（要么提议要么纯文本）、用户已明确
> 要求的修改不要追问确认（「应用」确认步本来就在）、列表里没有的命令不要声称
> 不存在（先核对清单）。decoder 契约（空 edits 信封按纯文本）未改。

| 命令 | 必填参数（可选） | 落点 |
|---|---|---|
| `weight.log` | weightKg 35–300（localDate、notes） | `MeasurementRepository.saveManualWeight` |
> 2026-10-09 schema 22（docs/31 S2）删掉 `bodyFatPercent 0–70` 与 `muscleMassKg 0–200` 两个可选参数（字段与数据一起没了，AI 再收到就是往不存在的列上写）；本表 2026-10-10（docs/31 S8）补同步。注册表 `chat_edit_registry.dart` 是单一事实源。
| `water.add` | amountMl 1–5000（localDate；代码与仓储同口径 5000） | `WaterRepository.add` |
| `water.delete` | waterId | `WaterRepository.delete` |
| `meal.create` | slot、items[{food, grams 0.1–5000}]（localDate、notes） | 名字解析→`MealRepository.saveManualMeal` |
| `meal.update` | mealId（slot、notes） | 重建 draft→`update` |
| `meal.item.update` | itemId、grams | 扫近 7 天记录重建 draft→`update` |
| `meal.item.delete` | itemId | 同上 |
| `meal.delete` | mealId | `MealRepository.delete` |
| `food.create` | name、kcalPer100g 0–1000、proteinPer100g/carbsPer100g/fatPer100g 0–100（servingGrams 0.1–2000、brand） | `FoodRepository.create` |
| `dish.upsert` | name、slot、kcal 0–1000、protein/carbs/fat 0–100（comment） | `DishLibraryRepository.upsertByName`（source=`ai_chat`） |
| `dish.delete` | dishId | `DishLibraryRepository.delete` |
| `canteen.venue.create` | name、campus | `CanteenRepository.createVenue` |
| `canteen.venue.rename` | venueId、name | `renameVenue` |
| `canteen.venue.delete` | venueId | `deleteVenue` |
| `canteen.window.create` | venue（id 或精确唯一名）、name、openTime/closeTime `HH:mm` | `createWindow`（仓库自校验时间） |
| `canteen.window.delete` | windowId | `deleteWindow` |
| `canteen.dish.create` | window（id 或精确唯一名）、name | `createDish`（**2026-10-16 去 `priceYuan`**：价格随 S8-b 整条退役） |
| `canteen.dish.update` | dishId（name） | `updateDish`（同上，只剩改名） |
| `canteen.dish.delete` | dishId | `deleteDish` |
| `canteen.dish.nutrition` | dishId、kcalPer100g 1–900、protein/carbs/fatPer100g 0–100、grade A/B/C/D、（confidence 0–1、kcalMin/kcalMax、sourceText） | `CanteenRepository.recordNutrition`（**2026-10-16 新增**：分析结果落库的唯一入口——此前 `recordNutrition` 零调用方，菜品永远停在「未分析」；目录读侧因此看不到「已分析」与结果） |
| `profile.goal.update` | goal ∈ loseFat/maintain/gainMuscle（targetWeightKg 35–300） | `ProfileIdentityRepository.updateGoal`（无目标行→失败告知去建档） |
| `constraints.set` | dietaryLabels ≤4、allergenAvoidances ≤9（至少给一项；空列表=清空） | 解析枚举→`PlanningConstraintsRepository.save` |
| `workout.plan.create` | name、days[{weekday 1–7, entries[{exercise 动作名, sets, reps, weightKg?}]}] | 名字解析→计划仓储建计划（docs/32 §4 T6b 新增；对话启动器「生成训练计划/今日吃法」走这条） |
| `workout.plan.delete` | planId | `WorkoutPlanRepository.removePlan` |
| `session.start` | （planId，localDate） | `WorkoutSessionRepository.start`（**已有活跃会话→如实拒绝，不覆盖**） |
| `set.log` | exercise 动作名、weightKg 0–500、reps 1–100（rpe 6–10、sessionId） | 名字解析→`logSet`（缺 sessionId＝当前进行中的那次；没有活跃会话→如实拒绝） |
| `session.finish` | （sessionId） | `WorkoutSessionRepository.finish` |
| `plan.entry.add` | planId、weekday 1–7、exercise 动作名、sets 1–20、reps 1–100（weightKg 0–500） | 名字解析→`WorkoutPlanRepository.addEntry` |
| `plan.entry.remove` | entryId | `WorkoutPlanRepository.removeEntry` |
| `plan.rename` | planId、name ≤60 字 | `WorkoutPlanRepository.renamePlan`（**本轮新增的仓储方法**，只改名不动编排） |
| `food.update` | foodId、name、kcalPer100g 0–1000、protein/carbs/fat 0–100（servingGrams、brand） | `FoodRepository.update`（**仅自建行**；内置行如实拒绝；**保留原分类**） |
| `food.delete` | foodId | `FoodRepository.delete`（**仅自建行**；删前报被 N 条餐记录引用） |
| `profile.body.update` | （heightCm 100–250、birthYear 1900–2020、sex ∈ female/male） | 读现值→`updateBodyProfile`（只写给了的字段；性别白名单） |
| `targets.update` | （waterMl 500–6000、steps 1000–50000；至少给一项） | `UpdateWaterTargetMl.run`（**新增生效行**）+ `StepsRepository.updateDailyGoal` |
| `menu.snapshot.publish` | menuJson（`menu-normalize v1` 草案；**JSON 对象或字符串都收**，≤20000 字） | `MenuNormalizeJsonDecoder.decode` → `PublishMenuNormalizeDraft.call`（与文件导入同源；同日同地点的 active 快照即菜单 tab 的「今日推荐」入口） |

> 2026-10-13（docs/32 §3 D10 / §4 T8，T16 只读复核补漏）：**`commute.set` 已退役**（行已从上表移除）——
> 通勤全链路下线（`manual_commute_minutes` 随 schema 23→24 drop、仓储/对话框/快照段全删），
> 用户要求「从全部地方删掉，不要漏」。同一次复核把 T6b 新增的 `workout.plan.create` 补进本表
> （此前只在代码与证据里）。注册表条数：**T6b 之后 24 条、删 `commute.set` 之后 23 条**。
>
> 2026-10-15（用户指示「按 docs/34 补全剩余的 AI 接口」）：**再补 10 条**（训练域 6 + 自建食物与资料/目标 4，
> 见上表末十行），注册表**现共 33 条**。同轮的 `RepositoryChatEditExecutor` 两处加固：
> ① **快照 id 别名容忍**（`[water:…]`/`[wplan:…]` 等前缀先剥一层，剥完查不到仍如实报不存在）；
> ② **`FoodWriteFailure` 纳入失败翻译**（此前 `food.update` 打在内置食物上会**逃逸出 apply**）。
> 单一事实源仍是 `chat_edit_registry.dart`。
>
> 同日再补 1 条（**批次 B**）：`menu.snapshot.publish`（结构化菜单草案 → 解码 → 发布快照），**注册表现共 34 条**；
> 同轮给 `ChatEditArgSpec` 加两档：`maxLength`（string 型长度上限，缺省 300）与 `jsonObjectAllowed`（**收对象形态**——真模型把结构化载荷直接发对象，实测被「要是文本」挡下）。

**明确排除（写进披露与本文，不是漏做）**：

- **设置/凭据**（AI 提供方、API Key、备份开关）：安全边界，注册表里根本没有。
- **训练计划的创建与条目编辑**：已有专属 AI 流程（工作台「训练计划」卡，带草稿确认）；
  计划是「天→条目→组次」三层结构，快照塞不下且与专属流程双写易漂移。对话只覆盖
  `workout.plan.delete`。进行中的训练会话（logSet）同理不在对话里改。
- **种子食物/目录食物的修改删除**：应用 UI 本来就不可改（事实纪律），对话也不开。
- **食谱 / 周计划 / 库存 / 价格 / 规划偏好（已下线）**：这五类功能整族删除；
  其中「食堂菜品价格」在 2026-10-16 由用户点名**连库列一起删**（S8-b）
  （docs/28 §6，DECISIONS ADR-026），其 10 条对话命令 `recipe.*` / `plan.*` /
  `pantry.*` / `price.set` / `planning.preferences.set` 随之退役。例外是
  `constraints.set`——它写 `profiles.allergenAvoidancesJson`，仍被每日推荐引擎读取，
  已随仓储搬到 `daily_plan/` 保留。

## 3. 可编辑快照（上下文注入）

`ChatEditContextLoader`（drift 直查）→ 纯文本段，拼进 `systemContext`：

- **饮食偏好与忌口**（2026-10-17，docs/38 S11）：`饮食偏好：素食…` /
  `忌口/过敏：芒果…` + 一行「硬约束」说明；空段写「（空：还没有声明…）」。
- **关于用户的长期记忆**（2026-10-17，docs/38 S11）：置顶优先、最近更新在前；
  **≤12 条且 ≤1500 字**；条目形如 `- [习惯] 周三晚上练腿（训练）`；
  开关关着时写「（记忆已关闭…）」且不注入任何条目。
- 当前目标（goal/目标体重）。
- 今天+昨天的餐记录（≤30 行）：`[meal:<id>] 日期 餐次 「名」(条目: [item:<id>] 名 x 克)`。
- 菜品库（≤15）。
- 食堂（≤4 地点，各 ≤6 窗口，各窗口菜品聚合 ≤12）。
- 今日饮水（≤10 条）。
- 最近 3 次体重。
- 训练计划（≤8 条）：`[wplan:<id>] 名（N 个条目）`。
- 自建食物（≤20）、本周训练统计、进行中的训练（含 `[session:<id>]`）。

每段带真实行 id；空段写「（空）」；超限截断并注「（更多未列出，需要时让我先查）」。
**实测口径更正（2026-10-17）**：本文件早前写的「总大小软上限 6 KB（超限砍段）」
**从未实现**——代码里只有每段的行数上限；真正的硬闸门是请求体 **64 KiB**
（`maxRequestBytes`，带图 8 MiB）。**快照只进 systemContext，不进用户气泡**。

## 4. 执行器语义

- `applyAll(commands)` **按序**逐条执行；单条失败不影响后续；每条产出
  `ChatEditOutcome{index, ok, message}`（失败消息必须人话、可行动）。
- 名字解析：`food`/`venue`/`window` 参数先试「精确同名唯一」，再试 id 直查；
  零命中/多命中都是失败（多命中要列出候选数）。
- 数值复核：executor 不信 decoder 的区间校验，依赖仓储自身校验并捕获其异常转人话
  （双层防线）。
- `grams` 等数值接受 number；`slot` 接受 `breakfast/lunch/dinner/snack` 或中文
  （早餐/午餐/晚餐/加餐）。
- **条目 id 会换新**：`MealRepository.update` 的既有语义是「整餐条目重建」，
  对话改克数/删条目后该条目的 id 不再是快照里那个；下一轮快照会把新 id 发给
  模型，期间拿旧 id 来改会被如实拒绝（不猜）。

## 5. UI（docs/21 §5.7 第七种消息形态：编辑卡）

- 助手编辑消息 = 气泡（reply 文本）+ **`DesignCard` 卡壳**：卡头一行
  （「待你确认的修改」/「这次修改的结果」+ 汇总 `LfBadge`）+ 逐行「命令标题 + 参数摘要 +
  状态徽标」，底部「全部应用」「忽略」。Key：`chat-edit-card-<index>` /
  `chat-edit-apply-<index>` / `chat-edit-dismiss-<index>` / 行 `chat-edit-row-<index>-<n>`。
  （2026-10-16：卡壳与徽标是用户「功能卡片太丑，要做成小卡片」的落地；此前是裸 `Column`。）
- 状态机：`proposed → applying → applied / failed / dismissed`；已应用/已忽略后按钮消失，
  只留结果。应用中按钮禁用（防双击重复写库）。
- **推荐按钮**（`chat-edit-suggest-<index>-<n>`）：卡内 `Wrap` 一排 chip（图标 + 文案 +
  终态「已应用 / 失败」），点一下就等于应用那条命令；点过的结果下面留一行小字说明。
- **修复按钮**（`chat-edit-repair-<index>-<n>`）：失败行下面「创建食材「X」」——
  见 §1 第 3 条。
- 大字号 2.0× 下不溢出（行摘要用 `Flexible`+省略号，动作行用 `Wrap` 折行而不是横向滚动）。
- 快捷 chip 增加一个「帮我改」示例入口？**不加**——保持 §5.7 既有三个 chip 不动。
  （2026-10-16：三个 chip 中的「手动记录」按用户要求下线，其余三枚等宽占满一行；
  记录入口仍在饮食分支与输入框，未丢功能。）

## 6. 测试矩阵（最低门槛）

decoder（信封形状/坏 JSON/未知 action/超 10 条/NaN/枚举与区间）、注册表完整性
（名字唯一、参数声明与 executor 一致、protocol 渲染含全部命令）、executor
（23 条命令各 ≥1 正例 + 关键失败路径：目标缺失/歧义/越界）、快照（含 id、上限截断、
空库）、controller（信封→编辑卡、应用/忽略/双击守卫、落库回环）、页面（卡片渲染、
按钮接线、流式占位、2.0× 不溢出）。隐私审计补一条：对话披露写明「发送可编辑数据快照」。

---

## 7. 按需生成应用卡片（docs/66 v2，2116 起的手动链路）

**正常对话（含图片轮）不再强制 JSON、不再自动弹卡**：聊天上下文与编译上下文
拆分——`ChatEditCoordinator.buildChatContext`（内容纪律 + 能力边界 + 快照，
不含命令协议）给普通发送；`buildEditContext`（`renderProtocol(compileMode: true)`
编译变体 + 现场快照）只给手动编译。协议里的对话型规则（估算、suggestions、
「必须给信封」）在编译变体里被移除；内容事实纪律压缩成 `chatContentDiscipline`
（≤2 KB，不含命令名/JSON 字样）留在聊天侧。

**手动编译链路**（`ConversationController.generateEditCard`，不复用旧
`_runCompiler`）：输入 = 用户请求（wireText 优先）+ 目标助手回复（≤6000 字，
超限直接失败不重试）+ 最近 6 条对话（单条 ≤600 字、总 ≤3000 字，图片用
`[图片]` 占位，不含目标回复本身）+ 编译协议变体 + 点击时现场快照；输出经
严格 decoder → **suggestions 全部丢弃** → **数字接地闸门**
（`chat_edit_number_grounding.dart`：全部数值写入字段须在用户请求/目标回复
中有可见依据，`150` 不误匹配 `1500`，带对象锚点的要求数字邻近锚点，
`weekday` 用语义别名接地，`food.create` 每 100g 营养是唯一例外；字段无策略
fail-closed 拒绝挂卡）→ **日期钉定**（缺省 `localDate` 的命令钉到目标消息
本地日期，`targets.update` 只钉 `waterMl` 分支，`steps` 保持全局语义；
`ChatEditTurnItem.copyWith(raw:)` 同步 raw，落库读 raw）→ 挂到**同一条助手
消息**（`turn.reply == 原文`，不新增气泡、不改原文）→ 落库 → 审查。

**状态机**（内存态，独立 `cardGeneration` notifier，不触发页面滚到底）：
`idle / generating / empty / failed`；取消先失效 epoch，再向 token 发取消
事件、取消订阅、关 token、回 idle，迟到流事件不挂卡不写库；生成期间可继续
聊天（不占 `_pending`、不改 `ConversationState.status`）。

**应用前日期确认**：整卡 / 分组 / 旧卡 suggestion / 选卡重放统一经过控制器
preflight——选中命令有非今天 `localDate` 时经页面 `confirmEditDates` 确认
（`chat-edit-date-confirm`）；新模式下回调缺失 / 拒绝 / 异常都不写库。旧模式
（`manualCardGeneration=false`，构造参数默认值即回滚开关）行为与 2115 逐字节
一致，正式入口 `app_router` 显式传 `true`。

**落库回环前置修复**（§5.8）：`outcomes` 增加 `status`（`dismissed` 落库，
重启不复活成 proposed；`ok` 布尔保留兼容旧 reader）；`copyWith(raw:)` 让
日期钉死与选卡重放的改写同步进 raw。待应用卡摘要（`pendingProposalSummaryOf`）
压平空白后 ≤240 字。

旧自动弹卡/补信封链路（`_promoteEditTurn`、`_maybeRetryForEnvelope`、
`_runCompiler`、兜底卡等）**保留一个版本**（v2117 再清），新模式下
`needsEnvelopeRetry` 恒为 false。

### 7.1 编译上下文的结构化分离（2122）

手动编译的输入里，**编辑卡一律不进「最近对话」**：

- 已应用的卡，其 reply 就是「米饭 150g、鸡胸肉 150g」——把它当素材会让编译器重复生成
  （餐食有全天去重兜底，饮水/体重没有，会真记两条）；
- 待应用的卡若也塞进对话文本，会与快照的「尚未应用的提议」段重复。

因此「今天已记录什么」只有**一个权威来源**：数据快照（今日餐记录 / 饮水 / 体重 / 目标）；
「上一张待应用卡」由 `ChatEditCoordinator.buildEditContext(pendingProposal:)` 以结构化段注入。
编译器不再需要从自由文本里重建已经发生过的事实——重复的入口被删除，而不是被规则拦截。

尚未做的更强防线（下一版）：命令级幂等键（`action+args+date` 指纹，执行器记「最近执行过」，
重复则跳过并说明）；挂卡前对照今天已有记录做「重复可见化」标注。

### 7.2 重复可见化（2123）

编译侧的结构化分离（§7.1）让「已落库内容」进不了编译素材；但模型仍可能对同一件事
再提一次（连点两次生成、回复里重复列出同一份食物）。执行器对餐食做全天去重、体重是
**同日覆盖**、**饮水则是追加**，所以需要让用户在**点应用前**看见重复：

| 命令 | 应用前提示 | 应用后行为 |
|---|---|---|
| `meal.create` | 今天已经记过 X，应用时不会重复写入 | 全天去重跳过同名食物 |
| `water.add` | 今天已有 N 次 Xml 的饮水，确认要再记一次吗 | 追加（用户可忽略该行） |
| `weight.log` | 今天已记过 X kg，应用会覆盖为这次的值 | 同日覆盖 |

实现：`ExistingFactProbe`（查当天餐/饮水/体重，按日期缓存）→ `duplicateHintFor`
（纯判断，可单测）→ `ChatEditCoordinator.annotateDuplicates`（探针缺失/异常一律
原样返回）→ `ChatEditTurnItem.duplicateHint`（内存态，不落库）→ 卡片主行下显示。
组合根 `main.dart` 注入；未接线时行为与之前完全一致。

**仍未做**：命令级幂等键（`action+args+date` 指纹 + 最近执行记录），需新增存储。

### 7.3 短时窗幂等（2124）

「重复」的最后一道防线在**执行器**：同一动作在 **15 秒**内重复执行只写一次。

- 指纹：`action | 规范化 args（去 notes、键排序、items 按食物名排序）| 目标日期`；
- 只对**追加型且业务无去重**的命令启用：`water.add` / `set.log` / `plan.entry.add` /
  `session.start`。其余命令各自的去重文案更精确，不参与：
  `meal.create`（全天去重）、`food.create`/`dish.upsert`/`canteen.*.create`（同名引用）、
  `memory.remember`（重复拒绝）、`menu.snapshot.publish`（同 hash 跳过）、`weight.log`（同日覆盖）；
- 命中时返回**成功** + 「刚才已经记过，没有重复写入」（这条提议确实已经生效过）；
- 并发双击：`await` 之前用 in-flight 集合占位，不会两条都写；
- **不做永久幂等**：超过窗口的相同动作照常写入（「又喝一杯 250ml」是真实需求）；
- 记录是进程内内存态（不落库），重启清零——只服务于短时间内的重复动作。

### 7.4 流程加固与卡片密度（2125）

- **失败先失效 epoch**：真实 SSE 在 `addError` 之后还会补一个 done 事件。取消订阅
  是主防线，但时序不巧时迟到的 `onDone` 会进完成路径、把 failed 覆盖成挂卡
  （缓冲区里可能已攒了半个合法信封）。现在失败时**先让 epoch 失效**再收尾。
- **单条命令卡不画组头**：卡头已有「1 条修改」+ 摘要，组头「记一笔饮水 1 条」纯属
  重复。多组（记餐 + 新建食材 + 记忆…）时组头保留——那是归类线索。
  「板块存在性」的判据改为浅灰块 key（`chat-edit-block-<卡>-<组>`）。
- **应用前后提示互斥**：「今天已有…」只在应用前显示，应用后由每行的结果说明取代。
- 密度：行垂直间距 6→5、结果/提示小字行高 1.4→1.3。

### 7.5 状态矩阵复核（2126）

编辑卡的状态矩阵逐张渲染审看（`test/card_states_capture_test.dart`，10 帧）后修正：

| 条件 | 修前 | 修后 |
|---|---|---|
| 全部行失败 | 卡头绿色「已完成」 | 中性「未应用」（有成功的行才算完成） |
| 320dp × 2.0× | 序号数字被 18×18 框裁切 | 框随字号放大（上限 1.6×） |
| 320dp × 2.0× | 食物名被行尾徽标挤成「抹茶曲奇…」 | >1.4× 时徽标下移右对齐，名称拿回整行宽；徽标限幅 1.3× |
| 单命令单行卡 | 卡头摘要与行摘要重复一遍 | 卡头不显示摘要（信息全在行里） |

## 8. 统一主库后的协议增量（schema 31，2026-11-09）

方案：[`docs/67`](67-unified-nutrition-master-canteen-catalog-feasibility-plan-2026-11-09.md)
· 实际契约：[`docs/68`](68-unified-nutrition-data-contract.md)。

### 8.1 新增可选参数（缺省 = 旧协议 v1）

| 命令 | 参数 | 说明 |
|---|---|---|
| `canteen.dish.create` | `foodId` | 链接主食物（快照里的 `[food:id]`）；写了就建立权威引用 |
| `canteen.dish.create` | `servingGrams` / `servingGramsSource` | 这个窗口的每份克数与来源（`weighed|user_input|label|ai_estimate`） |
| `canteen.dish.create` / `canteen.dish.nutrition` / `dish.upsert` | `contract` | `v1`（缺省）或 `v2`；其它值整条拒绝 |

`contract=v2` 时 `canteen.dish.create` 必须给 `foodId`（或 `nutritionFrom=food`）。

### 8.2 语义变更

- `canteen.dish.create` 的 `nutritionFrom=food` 现在是**建立链接**，不再把每 100g
  复制进证据表（供应的当前营养从主食物生效修订派生）。
- `dish.upsert` 只做**旧信封兼容**：按旧"每份"语义解码，必须有 `servingGrams` 才能
  换算进主库；没有就明确要求补全，不会再写一份独立的每份营养副本。
- `meal.create` 的 `items[].food` 支持 `[canteen-dish:id]`（供应），克数按该供应解析；
  旧 `[dish:id]` 保持每份语义，份量不可信时报错要求补全。
- 快照段（`chat_edit_context_loader`）里的食堂供应会带：主食物 id/名称、每 100g、
  份量状态、每份克数、一份大约多少千卡（仅份量可信时）。

### 8.3 数字接地

`canteen.dish.create.servingGrams` 已登记接地策略；未配置策略的数值字段仍**整卡拒绝**
（fail-closed），不因为新增参数而放宽。
