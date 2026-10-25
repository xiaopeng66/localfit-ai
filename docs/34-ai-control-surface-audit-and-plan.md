# AI 控制面审计与补全方案（2026-10-15；同日按本文补全，见 §7 落地结果）

> 触发：用户要求「**自己调用这些功能，测试是否正常，不正常就修；然后给出现在能控制的功能、还没接入的、以及补全方案**」。
> 本文是那次审计的结果与方案；实测证据见
> [`2026-10-14-round7-native-implementation.md`](evidence/2026-10-14-round7-native-implementation.md)
> 的「死代码清理与真实 AI 测试」节（含两轮供应商与实时控制矩阵）。
>
> 口径：**只统计经真实链路验证过的**——真模型出信封 → `parseChatEditTurn`（App 解析）
> → `RepositoryChatEditExecutor`（App 执行器）→ 真 Drift 写库 → 断言库里真的变了。

## 1. 结论摘要

- AI 目前能**写**的：**23 条 chat-edit 命令**，覆盖体重、饮水、餐食（含条目级）、自建食物、菜品库、食堂目录（地点/窗口/菜品全族）、健康目标与饮食约束、训练计划（建/删）。**本轮 9/9 场景、22 条命令在真模型下全部真的写进了库。**
- AI 目前能**读**的：一份「当前可编辑数据快照」（目标 / 今日与昨日餐记录 / 菜品库 / 食堂目录 / 今日饮水 / 最近体重 / 训练计划，含真实行 id）。
- 本轮**修了 1 个真正的接口缺陷**（快照 id 别名回填，见 §3.1；上一轮已修"协议没要求整段只有 JSON"，§3.2），并确认 2 类失败**不是 App 缺陷**（§3.3）。
- AI **还不能**碰的（值得补的）：**训练会话与逐组记录**、**计划的编排编辑**、**三个创作任务（菜单快照 / 营养估算 / 今日吃法）的写回**、**个人资料其余字段**、**自建食物的改与删**、以及**快照读取面的扩展**。明确**永不接**的是凭据、备份/恢复/CSV、清空数据、权限与设备配对（§4.2）。

## 2. 现在 AI 能控制什么（已接入，逐条经实时验证）

### 2.1 chat-edit 命令表（注册表 = 单一事实源：`chat_edit_registry.dart`）

| # | 命令 | 参数（`?` = 可选） | 落点（仓储/表） | 实时验证 |
|---|---|---|---|---|
| 1 | `weight.log` | weightKg, notes? | `MeasurementRepository.saveManualWeight` → `Measurements` | ✅ 真模型 → 库里有那一条（72.5kg + 备注） |
| 2 | `water.add` | amountMl | `WaterRepository.add` → `WaterIntakes` | ✅ 250ml 落库 |
| 3 | `water.delete` | waterId | `WaterRepository.delete` | ✅ 删掉刚记的那条（含 `water:` 前缀形态） |
| 4 | `meal.create` | slot, items[], notes? | `MealRepository.saveManualMeal` → `Meals`+`MealItems` | ✅ 按**食物名**解析后落库（鸡蛋 100g / 米饭 150g） |
| 5 | `meal.update` | mealId, slot?, notes? | `MealRepository.update`（餐行 UPDATE，条目重建） | ✅ 备注落库 |
| 6 | `meal.item.update` | itemId, grams | 同上（整草稿重建） | ✅ 克数 100→150 真改 |
| 7 | `meal.item.delete` | itemId | 同上 | ✅ 条目减少 |
| 8 | `meal.delete` | mealId | `MealRepository.delete` | ✅ 整餐清掉 |
| 9 | `food.create` | name, 四营养值, servingGrams?, brand? | `FoodRepository.create` → `Foods` | ✅ 「燕麦拿铁」落库（62kcal/100g） |
| 10 | `dish.upsert` | name, slot, kcal, protein, carbs, fat, comment? | `DishLibraryRepository` → `DishLibrary` | ✅ 「番茄炒蛋」收录 |
| 11 | `dish.delete` | dishId | 同上 | ✅ 删掉 |
| 12 | `canteen.venue.create` | name, campus | `CanteenRepository` → `Venues` | ✅ 「三食堂/南校区」落库 |
| 13 | `canteen.venue.rename` | venueId, name | 同上 | ✅ 改成「第三食堂」 |
| 14 | `canteen.venue.delete` | venueId | 同上 | — （矩阵未点火，路径与 13/16/17 同族） |
| 15 | `canteen.window.create` | venue, name, openTime, closeTime | → `MenuServices`（按快照 id 定位 venue） | ✅ 「4 号窗口 11:00–13:30」落库 |
| 16 | `canteen.window.delete` | windowId | 同上 | ✅ 删掉窗口 |
| 17 | `canteen.dish.create` | window, name | → `MenuItems` | ✅ 菜品落库（**2026-10-16 `priceYuan` 退役**：价格整条删除，见 docs/36 §3 S8-b） |
| 18 | `canteen.dish.update` | dishId, name? | 同上 | ✅ 改名（同上，改价随价格列退役） |
| 18b | `canteen.dish.nutrition` | dishId, kcal/protein/carbs/fat、grade、（confidence、区间、来源文本） | → `MenuItemNutritionEvidence` | ✅ **2026-10-16 新增**：AI 分析结果落库的唯一入口（N3） |
| 19 | `canteen.dish.delete` | dishId | 同上 | ✅（含 `canteen-dish:` 形态容忍） |
| 20 | `profile.goal.update` | goal, targetWeightKg? | `ProfileIdentityRepository.updateGoal` → `Goals` | ✅ 「减脂/65kg」落库 |
| 21 | `constraints.set` | dietaryLabels?, allergenAvoidances? | `PlanningConstraintsRepository` → `Profiles` | ✅ 素食 + 花生/鱼类/甲壳类 |
| 22 | `workout.plan.create` | name, days[](weekday+entries[exercise,sets,reps]) | `WorkoutPlanRepository.create` → `WorkoutPlans/Days/PlannedExercises` | ✅ 「AI 控制测试计划」2 天 4 条目（动作按**名字**解析到本地动作库） |
| 23 | `workout.plan.delete` | planId | `WorkoutPlanRepository.removePlan` | ✅ 删掉（含 `wplan:` 形态容忍） |

### 2.2 快照给 AI 的读取面（`DriftChatEditContextLoader`）

`[venue:]`/`[window:]`/`[canteen-dish:]`/`[water:]`/`[meal:]`/`[item:]`/`[dish:]`/`[wplan:]` 八类行 id + 今天日期 + 当前目标 + 最近 3 条体重；分段超限**明说未列出**（不静默）。**没有**：食物库、训练历史/统计、步数、水量目标、成就。

### 2.3 安全与诚实规则（都在实测里被触发过）

- **不猜目标**：id 直查优先；按名字只接受「精确同名且唯一」；剥掉快照别名后仍查不到 ⇒ 如实报「不存在（可能已被删除）」。
- **双层校验**：decoder 校验一遍，落库前仓储再校验一遍（AI 给的数值不直接信）。
- **应用前不写库**：只有用户点「应用」才执行（`ChatEditExecutor` 契约）。
- **越界拒绝**（实测）：让模型删一个不存在的 venue、改 API Key ⇒ 模型**拒绝提案**（无信封）；即便硬给，未注册 action 也会解码失败——凭据面不可能被 AI 碰到。
- **单条失败不连坐**：一次回复里坏一条，其余照常成卡。

## 3. 本轮实测修掉的缺陷

### 3.1【已修·真缺陷】快照 id 别名回填 ⇒ 多步编辑假报「不存在」
快照把行印成 `[water:mx-1]`、`[wplan:mx-15]`，**方括号里的整串都像 id**，真实模型（`deepseek-v4.1-flash` 与 `GLM-5.3-Flash` 都实测出现过）会原样回填 ⇒ 执行器按原值查不到，报「饮水记录「water:mx-1」不存在（可能已被删除）」，用户看这句会以为数据没了。
**修法**：`RepositoryChatEditExecutor.normalizeTargetId` —— 凡「`<别名>:<真 id>`」形状先剥一层，别名表与加载器实际印出的前缀**逐一对齐**（`water/meal/item/dish/venue/window/canteen-dish/wplan` + 几个近义写法）；剥完仍查不到按不存在报，不猜。
**证据**：测试先行 RED（`r9-prefix-red-1`：`Expected: true / Actual: false`）→ 实施 → mock 18/18 绿（`r9-prefix-green-5`）→ 实时矩阵里 `water.delete(water:mx-1)`、`workout.plan.delete(wplan:mx-15)` **当场从✗转✓**。

### 3.2【已修·上一轮】协议没要求"整段回复只放那一个 JSON"
模型"先写中文说明、再贴 JSON"被严格解析当纯文本（编辑卡不出现）。协议第 1 条已补「**整段回复只放这一个 JSON 对象**……App 逐字解析：多一个字，这次提议就作废」。

### 3.3【确认非 App 缺陷】两类失败如实登记
- **模型散文 + JSON**（river 的 `deepseek-ai/DeepSeek-V4.1-Flash`）：同提示词下 `zai-org/GLM-5.3-Flash` 完全遵守，故为模型自律性差异；App 的严格解析是**刻意的**（宁可当闲聊也不产生半可信的卡）。是否放宽为"提取第一个配平 JSON"⇒ 范围项 **R13**（台账 §6，建议保持严格）。
- **模型回填过期 id**（5 步餐食链的最后一步 `meal.delete` 间歇报不存在）：已用确定性判据证明**餐 id 在条目编辑/备注编辑后不变且仍可删**（`r9-idstab-2` 19/19 绿），且执行器只报错、不写坏 ⇒ 属模型在长链里拿旧 id，用户重说一次即可。

## 4. 还没接入 AI 的能力（差距清单）

### 4.1 值得补（按优先级）

| 级 | 缺口 | 现状（UI 有、AI 没有） | 建议命令 |
|---|---|---|---|
| **P1** | **训练会话与逐组记录** | `WorkoutSessionRepository.start/logSet/finish` 都在，UI 可记组；AI 一条命令都没有 | `session.start`(planId?) / `set.log`(sessionId, exercise, weightKg, reps, rpe?) / `session.finish`(sessionId) |
| **P1** | **计划的编排编辑** | `WorkoutPlanRepository.addEntry/removeEntry` 在；AI 只能整份建/删 | `plan.entry.add`(planId, weekday, exercise, sets, reps, weightKg?) / `plan.entry.remove`(entryId) / `plan.rename`(planId, name) |
| **P1** | **三个创作任务的写回** | `menu-normalize`（发布菜单快照）、`dish-nutrition`（营养+证据等级落库）、`daily-menu-plan`（加入今日吃法）随旧工作台管线退役后**只剩对话文本** | `menu.snapshot.publish`(venue, window, rows[]) / `dish.nutrition.set`(dishId, kcal…, evidence) / `daily.plan.set`(date, items[]) |
| **P2** | **个人资料其余字段** | `profileIdentityRepository` 能改昵称/头像/目标；AI 只有 `profile.goal.update` | `profile.update`(nickname?/avatarPolicy?) / `profile.body.update`(heightCm?, age?, sex?, activityLevel?) / `targets.update`(waterMl?, steps?) |
| **P2** | **自建食物的改与删** | `FoodRepository.update/delete` 在；AI 只能 `food.create`（**建了改不了也删不掉**） | `food.update`(foodId, …) / `food.delete`(foodId)，**限 `isUserCreated` 行**（种子/目录行永不允许） |
| **P3** | **快照读取面扩展** | AI 看不见食物库/训练统计/步数/水量目标 ⇒ 相关编辑无从提议 | 加三段：自建食物（含 id）、本周训练统计、今日步数与目标 |

### 4.2 明确不接（安全与数据边界，写进注册表注释）

凭据与 AI Provider 配置、备份/恢复/CSV 导入导出、清空所有数据/清空内置食物、步数权限与电子秤配对、种子与目录食物的改删（`docs/23 §2` 既有排除项）、成就（只读域）。**这些不是缺口，是边界。**

## 5. 补全方案（分批实施，每批可独立验收）

**统一口径（每批都适用）**：不改 schema / CSV / 备份 / AI wire；只加「注册表 spec + executor 分支 + 测试」；
新命令一律**默认走用户确认**（现状不变）；破坏性命令（删）沿用危险样式；每个新命令都要有
**三条证据**：① mock 执行器测试（含"目标不存在/名字不唯一/数值越界"的拒绝路径）；② 实时控制矩阵新增一列（真模型能提出 + 真的写库）；③ 快照/下一轮可见性（写完能在下一轮快照里看到，形成闭环）。

**批次 A（P1，训练域，4–5 条命令）** — 价值最高：让"我今天练了什么"能一句话记进去。
- `session.start` / `set.log` / `session.finish`：参数收紧（`set.log` 必须给 `exercise`，按名字/ id 解析；重量 0–500kg、次数 1–100、RPE 6–10 区间校验，与 UI 同源）。
- `plan.entry.add` / `plan.entry.remove` / `plan.rename`：`removeEntry` 已在仓储里返回 bool，执行器按"不存在"话术翻。
- 验收：真模型说「帮我开始今天的训练，记 3 组卧推 60kg×8」⇒ 库里 `WorkoutSessions/WorkoutSets` 真的有；再说「结束训练」⇒ session 置 finished，训练历史可见。
- 风险：会话是"进行中"状态机 ⇒ 命令必须查 `getActive()`，已有活跃会话时 `session.start` 要如实拒绝（不覆盖）。

**批次 B（P1，创作任务写回，3 条命令）** — 把 6 张创作卡从"只出文本"补成"能落地"。
- `menu.snapshot.publish`：复用 `PublishMenuNormalizeDraft` 的既有草稿→确认结构（**不新建管线**，只是把确认按钮接成命令）。
- `dish.nutrition.set`：只写"估算 + 证据等级"字段，**不覆盖**用户手填值（有手填值时按冲突拒绝，沿用秤同步的冲突口径）。
- `daily.plan.set`：写"今日吃法"（计划域），**绝不写已吃**（与 `meal.create` 严格分开，按钮文案与命令名都要能自证）。
- 验收：真模型产出候选 → 应用后菜单快照/营养等级/今日吃法各自可见，且**餐记录不变**（这条是安全断言）。

**批次 C（P2，资料与自建食物，4–5 条命令）**
- `profile.body.update` / `targets.update`：与 `profile_edit_page` 同一套校验（身高 100–250、年龄 10–100、水目标 500–5000ml、步目标 1000–50000）。
- `food.update` / `food.delete`：**仅 `isUserCreated`**；删之前先报"这个食物被 N 条餐记录引用"（引用数只读查询），让用户知道影响面。

**批次 D（P3，快照扩展 + 提示词与演示）**
- 快照加三段（自建食物 / 本周训练统计 / 今日步数目标），并把分段上限与"未列出"口径补齐。
- 提示词：`renderProtocol()` 会自动带出新命令（单一事实源），但**需要一次"命令名可读性"复核**（模型要能分清 `set.log` 与 `plan.entry.add`）。
- 演示脚本：把本文 §2.1 的 9 个场景固化成 `test/ai_live/ai_live_control_matrix_test.dart` 的常驻用例（现在已经是），作为每次改动的回归门。

**不做**：把 §4.2 的边界项接进来；为接 AI 而放宽任何既有校验（双层校验、应用前不写库、不猜目标三条是**红线**）。

## 6. 建议的下一步

1. **批次 A**（训练域）——用户日常最高频、当前完全空白，且仓储 API 已就绪，预计一次切片可交付。
2. **批次 B 的 `dish.nutrition.set` 与 `menu.snapshot.publish`**——把"解析学校菜单/分析菜品营养"两张卡从展示变成可落地。
3. **批次 C 的 `food.update/delete`**——修一个真实别扭：AI 建的自建食物现在只能手动去食物库改。

## 7. 落地结果（2026-10-15，用户指示「按文档补全剩下的缺漏」）

**命令总数 23 → 34**（`chat_edit_registry.dart` 为单一事实源；docs/23 §2 表已同步）。

| 批 | 内容 | 状态 |
|---|---|---|
| **A** | 训练域 6 条：`session.start` / `set.log` / `session.finish` / `plan.entry.add` / `plan.entry.remove` / `plan.rename` | ✅ **已交付**。会话是进行中状态机：已有活跃会话时 `session.start` **如实拒绝**（不覆盖）；`set.log` 缺 sessionId 时落到当前活跃会话、没有活跃会话时如实拒绝；`plan.rename` 用**新增的仓储方法** `WorkoutPlanRepository.renamePlan`（只改名、不动编排，名字校验与 `create` 同口径） |
| **C** | 自建食物与资料：`food.update` / `food.delete` / `profile.body.update` / `targets.update` | ✅ **已交付**。`food.*` **只动自建行**（仓储 `_requireUserCreated` 双保险，内置行如实拒绝）；`food.update` **保留原分类**（命令没有种类参数，传 null 会静默清掉用户选过的分类）；`food.delete` 删前报「被 N 条餐记录引用」；`profile.body.update` 只写给了的字段、性别白名单 `female/male`；`targets.update` 水量走 `UpdateWaterTargetMl`（**新增生效行**，保留历史）、步数走 `StepsRepository.updateDailyGoal` |
| **D** | 快照加两段：**自建食物**（`[food:id]` 名 + kcal，AI 改/删的前置）、**本周训练统计**（本周次数与组数，走会话仓储的文档化出口） | ✅ **已交付**（`DriftChatEditContextLoader`） |
| **B** | 创作任务写回：`menu.snapshot.publish`（结构化菜单草案 JSON → 解码 → 发布快照） | ✅ **已交付**（同一批次内完成；见下） |
| **B′** | `dish.nutrition.set` / `daily.plan.set` | ⚠️ **按实情改判，未做**（见下） |

**批次 B 落地详情（`menu.snapshot.publish`）**：
- **承载形态＝结构化载荷**：参数 `menuJson` 放 `menu-normalize v1` 草案（`schema_version`/`source_date`/`venue_name`/`services[]`/`warnings[]`），执行器交 **`MenuNormalizeJsonDecoder`** 逐字段校验后调 **`PublishMenuNormalizeDraft`** —— 与文件导入**同一条**写入通路（`menu_snapshots` + `menu_services` + `menu_items`），**不新造管线**。
- **可见性实测**：草案的 `source_date` 落在今天时，发布出的就是菜单 tab 「今日推荐」读的那条 **active 快照**（`MenuSnapshotStore.activeSnapshotFor`），判据里直接断言该入口取得到刚发布的那份（mock 第 1 条）。
- **两处组件级扩充（都是加法）**：`ChatEditArgSpec.maxLength`（string 型长度上限，缺省 300 不变）+ **`jsonObjectAllowed`** —— 2026-10-15 实时矩阵实测：真模型把草案**直接发对象**而不是转义字符串，被「要是文本」挡下；开档后对象/字符串两条都收（同批判据两条都在册）。
- 失败话术：解码不合格 ⇒ **不逐条回显英文 violations**，只说「几处问题 + 该核对哪些字段」；发布异常 ⇒ `userMessage` 为 null 时用固定兜底（不回显 errors，docs/11 §3-B 白名单化）；同内容重发 ⇒ 如实报「跳过重复（快照 id）」。
- 实时矩阵新增 **⑬**：真模型先 `canteen.venue.create` 建地点、再 `menu.snapshot.publish`（对象形态）⇒ **`active snapshots=1 services=1 items=2`** 真写库。

**批次 B′ 的两条经代码核查后的结论（如实登记）**：
1. **`dish.nutrition.set` → 不需要新命令**：营养写入已由已注册的 `dish.upsert` 覆盖（name/slot/kcal/protein/carbs/fat/comment）；而**「证据等级」在 `DishLibrary` 没有列**（列清单：kcal/proteinG/carbsG/fatG/fiberG/sodiumMg/vitaminDMcg/source/comment…）⇒ 要落「证据等级」就得加列＝ **schema 变更（禁）**。可做的小改：给 `dish.upsert` 补可选 `fiberG/sodiumMg` ——**本轮核查后不做**：列虽存在，但领域层 `DishDraft/DishRecord` **不携带**这两个字段，要接就得扩 `DishDraft` + 仓储写入 + 文件导入/发布两条调用点，属跨层改动（登记，不夹带）。
2. ~~`menu.snapshot.publish`~~ → **已在本轮交付**（见上）。
3. **`daily.plan.set` → 不可实现（无存储）**：旧「计划/食谱」族随 docs/28 §6.4 退役后，`features/daily_plan/data/` 只剩 JSON 解码器与约束表，**没有任何可写的「今日吃法」表**；新建表＝ schema 变更（禁）⇒ 该命令**不接**，「生成今日吃法」继续只产出对话建议（与它自己的文案「只加入计划，不记录已吃」现已无落点一致——这句描述本身也需要随之下修口径）。

**同轮修掉的两个接口级缺陷**（详见实施证据）：① 快照 id 别名回填（`water:`/`wplan:`…）⇒ `normalizeTargetId`；② `FoodWriteFailure` 未纳入失败翻译 ⇒ `food.update` 打在内置食物上会**逃逸出 apply**。

**实时验证**：`test/ai_live/ai_live_control_matrix_test.dart` 扩到 **12 个场景**（新增 ⑩ 训练域、⑪ 自建食物建→改→删、⑫ 资料与目标），真模型（`zai-org/GLM-5.3-Flash`）下 **12/12 全绿、32 条命令真的写进库**。
