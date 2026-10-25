# 下一阶段开发文档：把检索接到入口、把治理补完（`docs/43`）

日期：2026-10-19
状态：**方案稿（待执行）**。前置：`docs/41`（总纲 v2）、`docs/39`（检索 v2）、`docs/40`（食物数据）、
`docs/21`（UI 规范，附录 D1–D9）。
基线：门禁 `p21-final`（`+2694 ~66`，exit 0，`changed_during_run: []`）；APK vc2037 / vc4037。

本文只写**还没做的那部分**。已完成项不重复描述，核对依据见 §1。

---

## 0. 一句话结论

三条线的**骨干**（数据模型、AI 交互、端上向量）已经落地并在设备上跑通；剩下的是
**「能力已建好但没接用户入口」4 项** 与 **「真没写」8 项**。本文按「先可见、再治理、后个性化」
分三个里程碑，每项给出接口、Key、判据与测试，全部不新增表、不改 21 列 CSV、不改 wire 形状。

---

## 1. 现状核对（2026-10-19，逐条查过代码）

**已完成并验收**：P1 八项（含设备帧）；P0 评测与稳态复测（32/B 档 p95 13.3ms、recall@10 相对
+92.6%）；P2 schema 28 全表全列 + 回填 + 份量口径 + 陈旧/同步 + 配料三层 + 队列底座；P3 检索核心
（IndexCoordinator / RRF+boost+MMR / 记忆 query-aware / 恢复后重建 / 前缀稳定化 / 调试面板）；
P4 的反馈闭环、软性排除、批量打标与重复建议、会话级临时记忆、时间语义（S14 / schema 29）；
端上向量启用（模型随包、worker isolate、空闲预热）。

**未完成（本文范围）**——分三类，依据是代码检索结果，不是推测：

| # | 项 | 核对事实 |
|---|---|---|
| A1 | 菜单页搜索框 | `DishSearchService` 的唯一调用点是 `retrieval_debug_page.dart`；`menu_dish_list.dart` 无搜索框 |
| A2 | AI 短名单接线 | `buildAiShortlist` 在 `lib/` 内零调用点 |
| A3 | 索引调度接设备状态 | `JobScheduler` 无生产调用点（只有实现与测试）；`pubspec` 无电池/充电依赖 |
| A4 | 调试面板第三档对比 | 面板只画 `BALANCED` / `KEYWORD_FIRST`；`RetrievalMode.semanticFirst` 枚举已存在 |
| B5 | 记忆容量对齐 | `kAiMemoryMaxCount = 200`，锁定决策是软顶 2000 / 硬顶 5000 |
| B6 | 记忆向量判重/合并提议 | 仓库内无 0.96 / 0.88 阈值逻辑，只有字符串归一化判重 |
| B7 | 整理建议（近义簇 / 长期未用） | 无实现 |
| B8 | 会话结束提炼进待确认 | 只有对话页手动「从对话提炼记忆」；无队列、无待确认面 |
| B9 | 口味向量 | `TasteProfile` 只有 `tagWeights`（标签口径），无向量质心 |
| B10 | 食物来源路由提示词 + `nutritionFrom` | 提示词无该段；命令层无该参数 |
| B11 | 记忆页分页 | `AiMemoryRepository.searchPage` 存在但页面仍本地 `contains` 过滤 |
| C | >5 万 1-bit 预筛 / >50 万 HNSW | 未实现（条目数远未到该档，**不列入本阶段**） |

---

## 2. 里程碑与顺序

| 里程碑 | 内容 | 依赖 | 为什么先做 |
|---|---|---|---|
| **M1 可见性** | A1 菜单搜索、A2 AI 短名单、A3 调度接线、A4 第三档 | 无 | 检索能力已经建好，但用户在日常界面里碰不到——这是当前最大的「投入没有产出」 |
| **M2 治理** | B5 容量、B6 向量判重、B7 整理建议、B8 会话提炼、B11 分页 | B6 依赖记忆向量索引 | 「用得越久越乱」的解药；B6 建好后 B7 才有数据 |
| **M3 个性化与协议** | B9 口味向量、B10 提示词与 `nutritionFrom` | M1（短名单）、M2（向量索引） | 口味向量要有落点（搜索/短名单）才有意义 |

顺序理由：M1 全部是「接线 + UI」，改动面小、可独立验收；M2 里 B6 是 B7/B9 的地基；M3 是锦上添花，
最后做不影响主路径。

---

## 3. 逐项设计

### A1 菜单页搜索框（`docs/39` §8）

**现状**：菜单 tab 只有推荐区与「其他菜品」，无搜索；检索服务只有调试面板在用。

**目标**：段头下方一个搜索框，输入即检索（防抖 200ms），结果替换推荐区；清空恢复推荐。

- 位置：`MenuDishList`（`lib/features/nutrition/presentation/sections/menu_dish_list.dart`）在段头 sliver
  之后插入 `TextField`（Key `nutrition-menu-search`，`hintText: '搜菜名、口味、窗口…'`，`Icons.search`）。
- 数据：`DishSearchService.search(query, dishes, semanticRanking: …, todayMenuItemIds: …, taste: …, exclusions: …, feedback: …)`；
  语义名次来自注入的 `SemanticRuntime?`（`rankDishes`），不可用时为 null（自动退化为关键词+标签）。
- 索引：进入菜单页后空闲触发一次 `SemanticRuntime.indexDishes(dishes)`（幂等、textHash 复用），
  避免「第一次搜索才建索引」的等待。
- 结果：抽件 `lib/features/nutrition/presentation/sections/menu_search_results.dart`（500 行预算）：
  - 行 Key `nutrition-menu-search-hit-<id>`：菜名、kcal、来源徽标（复用 `LfSourceBadgePair`）、
    「为什么命中」（`hit.reasons`，命中词/标签/语义）、「加入餐」按钮（复用 `onAddToMeal`）。
  - 空态 Key `nutrition-menu-search-empty`：「没有匹配「<query>」的菜。」+ 一句「试试更短的关键词或口味词」。
  - 结果头：`找到 N 道`（Key `nutrition-menu-search-count`）。
- 清空（`_query` 变空）⇒ 回到推荐区，不保留搜索状态。
- 语义不可用/索引为空：结果照常出（关键词+标签），不弹错；原因在调试面板可见。

**判据与测试**（`test/features/nutrition/menu_search_test.dart`）：

1. 防抖：连续输入 3 次，只触发 1 次检索（`fakeAsync` / `tester.pump` 断言查询次数）。
2. 关键词命中：输入菜名 → 结果含该菜，且行上有「加入餐」。
3. 仅语义命中：用 `FakeEmbeddingEngine` + 预置索引，查询与菜名无字面重叠但向量最近 → 结果含该菜，
   `reasons` 含「语义」。
4. 空态：无命中显示 `nutrition-menu-search-empty`，不显示「找到 0 道」。
5. 清空恢复：输入再清空 → 推荐区回来（Key `nutrition-menu-meal-breakfast` 存在）。
6. 320dp + 2.0×：搜索框与结果行不溢出（几何探针）。

**风险**：搜索结果与推荐区切换时的滚动位置——清空后回到顶部即可，不做记忆。

---

### A2 AI 短名单接线（`docs/39` §8 / `docs/41` §6）

**现状**：`buildAiShortlist` 零调用；AI 对话挑菜不经过本地检索。

**目标**：发送前把「本地检索到的候选菜品」作为 system 上下文的一段注入（**只加文本段，不改 wire**）。

- 位置：`DriftChatEditContextLoader`（`lib/features/ai_conversation/data/chat_edit_context_loader.dart`）
  新增段 `候选菜品（本地检索）`，与现有「食物库参考」并列；复用 `buildParts` 的段级缓存。
- 触发门控：仅当 `userMessage` 命中「吃/推荐/来点/今天吃」等意图词（或 `understandQuery` 的槽位非空）
  才注入，避免每轮塞 30 条。
- 内容：`DishSearchService` + `buildAiShortlist`（top 30），按窗口分组；每行
  `id | 名称 | 窗口 | kcal/份 | 标签`；段首一句「这些 id 可直接用于 meal.create；营养值来自本地菜品库」。
- 空结果不写段；`SemanticRuntime` 可用时带语义名次，否则关键词+标签。
- 约束：**只注入文本**，不新增命令、不改任何 wire 形状；模型看不到全库，只看这 30 条。

**判据与测试**（`test/features/ai_conversation/dish_shortlist_context_test.dart`）：

1. 有吃/推荐意图 → 段存在、行数 ≤30、含 id。
2. 无意图（如「帮我改目标」）→ 不注入该段。
3. 空库 → 不注入（不写「（空）」占位）。
4. 分组正确（同一窗口的菜相邻）。
5. 段级缓存：其它段变化不影响该段复用（复用 `buildParts` 的既有测试口径）。

---

### A3 索引调度接设备状态（`docs/41` G11）

**现状**：`JobScheduler.tick(JobRunConditions(charging, idle))` 有实现与测试，但生产代码不调用。

**目标**：充电 + 空闲时自动跑队列（索引补齐、打标、重建），可暂停、断点续跑。

- 新增 `lib/features/jobs/application/power_state_source.dart`：

  ```dart
  abstract interface class PowerStateSource {
    Future<bool> isCharging();
    Stream<bool> watchCharging();
    Future<bool> isIdle();      // 应用在后台 / 屏幕关闭
  }
  ```

  - **实现 A（推荐，需新增依赖）**：`battery_plus`（BSD-3-Clause）读充电状态；
    `isIdle` 用 `AppLifecycleState.paused`。
  - **实现 B（不加依赖的降级）**：不判断充电，只用「应用在后台」近似空闲，文档与 UI 如实标注
    「未接充电判定」。两者都实现同一接口，默认装配 A，缺失时回退 B。
- 接线（`main.dart`）：启动后订阅 `watchCharging` + 生命周期；条件满足时
  `scheduler.tick(JobRunConditions(charging: true, idle: true))`；另设 15 分钟兜底 tick。
- 暂停/恢复：沿用 `scheduler.pause()/resume()`；用户在前台时 `idle=false`，不领取新任务；
  正在跑的任务允许跑完（不中断），符合「可暂停」的既有语义。
- 幂等：沿用 `dedupeKey`（`indexRebuild:afterRestore`、`ingredientTagging:dictionary`）。

**判据与测试**（`test/features/jobs/job_scheduler_wiring_test.dart`）：

1. 充电 + 后台 → tick 被调用、任务被领取。
2. 未充电（实现 A）→ 不领取；实现 B 下标注降级。
3. 前台 → 不领取新任务，但已领取的任务完成。
4. 暂停后 tick 不领取；恢复后续跑。
5. 失败任务按 `attempts` 重试，超过上限进 failed 并可手动重试。

**决策点 D1**：是否接受新增 `battery_plus` 依赖（约 100KB，无网络权限）。不接受则用实现 B 并如实标注。

---

### A4 调试面板第三档对比

面板「模式对比」增加 `SEMANTIC_FIRST` 一行（Key `retrieval-debug-mode-semantic`），
用同一个 `semanticRanking` 跑 `RetrievalMode.semanticFirst`。测试：三行都在、分数/首条与模式一致。

---

### B5 记忆容量对齐（软顶 2000 / 硬顶 5000）

**现状**：`kAiMemoryMaxCount = 200`（`lib/features/ai_memory/domain/ai_memory.dart`）。

**目标**：与锁定决策一致，且不拖慢注入。

- 常量拆分：`kAiMemorySoftCap = 2000`、`kAiMemoryHardCap = 5000`、`kAiMemoryInjectionCandidates = 200`
  （参与相关性打分的候选上限，与注入预算 3k/24 条无关）。
- 写入：`remember` 达硬顶拒绝（文案给「整理」入口）；超过软顶仍可写，但返回/页面提示「建议整理」。
- 页面：顶部显示「已用 N / 2000（软顶）」；N > 软顶时提示「已超过软顶，建议整理」。
- 注入：`listActive(limit: kAiMemoryInjectionCandidates)`，保证每轮打分 <30ms（有性能测试）。
- 导入：上限 = 硬顶；超过整单拒绝（沿用 G22 口径）。
- **不新增表/列**：纯代码常量与文案。

**判据与测试**：2001 条可写且提示；5001 条拒绝；注入候选数不随总条数增长；导入上限；
`listAsOf` / 分页在 2000 条下 <100ms（基准测试）。

---

### B6 记忆向量判重与合并提议（`docs/39` §7）

**现状**：只有归一化字符串判重（完全相同/包含即拒）。

**目标**：写入前用向量做近重复判定；近义时**提议合并**而不是静默并存。

- 索引：记忆也写入 `embedding_index`（`ownerType='memory'`，`modelId=kEmbeddingModelId`，
  `encoding='f32'`，文本 = `memoryEmbedText`）。写入/更新时 upsert，删除时删；
  `IndexCoordinator` 的 orphan sweep 与恢复后重建覆盖 `memory`。
- 新 API（`AiMemoryRepository`）：
  - `Future<List<NearDuplicate>> findNearDuplicates(String text, {double threshold = 0.88})`
    ——返回候选（id、文本、cosine）。
  - `remember(..., DuplicatePolicy policy = DuplicatePolicy.reject)`：
    - 字符串完全相同（快速路径）→ 直接拒（不花一次嵌入）；
    - cosine ≥0.96 → 抛 `AiMemoryException`（文案带「已有非常接近的一条：…」）；
    - 0.88–0.96 → 抛 `AiMemoryMergeSuggested(candidates)`（新异常，命令层/页面转成「建议合并/更新」）；
    - <0.88 → 正常写入；
    - `DuplicatePolicy.allow` 供「我确定要另存一条」时使用。
- 合并动作（用户确认后）：更新旧条文本（保留 id/createdAt），旧条 `validTo=now`、新条生效——
  与 S14 的改口语义一致，不新造机制。
- **不新增表**：向量用 `embedding_index`，候选不落库。

**判据与测试**（`test/features/ai_memory/memory_vector_dedupe_test.dart`，用可控假引擎返回指定向量）：

1. 完全相同文本 → 拒（不调用嵌入：用计数引擎断言 embed 调用 0 次）。
2. cosine 0.97 → `AiMemoryException`。
3. cosine 0.90 → `AiMemoryMergeSuggested`，候选含旧条 id。
4. cosine 0.5 → 写入成功，索引新增一行。
5. 删除记忆 → 索引行同步删除。
6. 恢复备份后重建 → 记忆索引补齐（复用 `rebuildAll`）。

---

### B7 整理建议（`docs/39` §7）

**目标**：只读扫描 + 建议，用户确认才动。

- `lib/features/ai_memory/application/memory_hygiene.dart`：
  - `findNearDuplicateClusters()`：按 `domain` 分桶，桶内两两 cosine ≥0.9 聚簇（每簇 ≥2 条）；
    桶大小上限 500，避免 O(n²) 爆炸；结果按簇内最高相似度排序。
  - `findStaleMemories()`：`lastUsedAt` 为空或早于 180 天，且 `importance < 40`。
- UI：记忆页顶部入口 `ai-memory-hygiene` → 弹层（`ai-memory-hygiene-sheet`）：
  两个分组「可能重复（N 簇）」「长期未用（N 条）」，每条给「合并到…」「归档」「先不管」。
  **归档 = `status='archived'`**（列已存在），不删除；「合并」走 B6 的确认路径。
- 空态：「暂时没有整理建议。」

**判据与测试**：分桶正确；簇识别（≥0.9）；未用判定（180 天/importance）；不自动改数据；
归档后不出现在 `listActive` 但 `listAsOf` 仍可回看（与时间语义一致）。

---

### B8 会话结束提炼进「待确认」（`docs/39` §7）

**现状**：只有手动「从对话提炼记忆」。

**目标**：会话结束自动生成候选，进待确认队列；**用户确认才写**。

- **不新增表**：候选存 `background_jobs.payload`（`type='memoryExtraction'`，
  `dedupeKey='memoryExtraction:<conversationId>'`，`state=pending`），payload 为
  `{candidates: [{text, kind, domain, tags, reason}], conversationId, createdAt}`。
- 触发：对话页新增「结束本次会话」入口（Key `ai-chat-end-session`）；点击后若消息数 ≥6 且
  「自动提炼」开关开启（KV `ai_memory_auto_extract`，**默认关**——真实 AI 调用受授权范围限制，
  必须用户显式开启），入队并立即执行一次；失败进 `failed` 可重试。
- 执行：调用现有 AI 服务（与手动提炼同一条路径），**复用 `ai_memory_candidates.dart` 的
  `AiMemoryCandidateParse` 解析**（不新写一套候选解析），结果只写 job payload，不写 `ai_memories`。
- 待确认面（复用候选解析结果）：记忆页顶部「待确认 N 条」入口（Key `ai-memory-pending`）→ 弹层逐条「保存/忽略」；
  保存走 `remember(source='extracted')`，忽略只从 payload 移除；全部处理完 job 标记完成。
- **决策点 D2**：是否允许该功能发起真实 AI 调用（默认关，开启前弹一次说明）。

**判据与测试**：消息不足不入队；开关关闭不入队；候选不自动写库；保存后 `source='extracted'`；
忽略后不再出现；AI 失败进 failed 且可重试。

---

### B9 口味向量（`docs/39` §8）

**现状**：`TasteProfile` 是标签权重。

**目标**：向量质心 + 指数衰减，作为**软 boost**；标签画像保留兜底。

- `TasteVectorProfile.build({meals, dishVectors, now})`：
  - 取近 30 天、来源为 `dish` 的餐记录 → 对应菜品向量；
  - 权重 = `0.5^(ageDays/14)`（半衰期 14 天）；
  - 加权平均后 L2 归一；样本 <10 餐 → `active=false`（沿用现有门槛）。
- `DishSearchService` 增加可选 `tasteVector`：命中时 `score *= 1.05`（与标签画像同量级，
  两者同时 active 时取较大者，不叠加）。
- 只影响软排序，**绝不硬过滤**；与 `SoftExclusionRules` 的 ×0.5 惩罚可叠加（乘积有上限 1.05）。

**判据与测试**：<10 餐不参与；衰减权重正确（同菜品 14 天前权重减半）；质心归一；
boost 只作用于排序不改变硬过滤结果；与标签画像不叠加。

---

### B10 食物来源路由提示词 + `nutritionFrom`（`docs/40` §5 / §3.1）

**目标**：让模型按「今日食堂菜 → 菜品库 → 食物库 → 自建」的顺序选来源；命令层支持显式指定。

- 提示词：在协议段的渲染处 `chat_edit_registry.dart`（`renderProtocol()`）增加
  「食物来源优先级」段（docs/40 §5 原文的四条）——**只加提示词**，不改命令与 wire。
- 命令（加法，旧 payload 行为不变）：
  - `canteen.dish.create` / `canteen.dish.nutrition` 增加可选 `nutritionFrom`：
    `'food' | 'ai' | 'none'`（缺省 `none` / `ai`，与旧行为一致）。
  - `'food'`：按名称精确→别名匹配 `foods`；命中则写证据（`origin='food_library'`、grade 沿用、
    confidence 取匹配分）并把 `menu_item_food_matches` 置 confirmed；未命中 → 明确失败文案
    「食物库没有「X」，请改用 AI 分析或手动填写」，**不静默改走 AI**。
  - 非法取值 → 中文错误（与其他枚举参数同一口径）。
- 判据与测试：注册表 spec 接受三值；三种分支各一条；旧 payload（不带该参数）行为逐字节不变；
  未命中时返回可行动文案。

---

### B11 记忆页分页（`docs/41` G5）

- 页面在「总数 > 50 或搜索非空」时改用 `repository.searchPage(query, offset, limit: 50)`，
  底部「加载更多」（Key `ai-memory-load-more`），头部显示「共 N 条」。
- 判据与测试：第 1 页 50 条、加载更多不重复、总数正确、搜索跨页一致。

---

## 4. 明确不做（本阶段）

- `>5 万` 条目的 1-bit 预筛与 `>50 万` HNSW：当前条目数远未到该档，且需要基准与压测样本；
  继续留在「未做」清单，不做半成品。
- arm64 真机延迟复测：无可用真机（外部阻塞）；模拟器数据已登记，不冒充真机结论。
- 向量进备份、跨设备同步、图谱/文档 RAG：`docs/39` §14 已明确不做。
- 不改 21 列 CSV、不改任何 wire 形状、不新增数据库表/列（本阶段全部复用既有 schema 29）。

---

## 5. 验收与证据口径

每个里程碑独立验收，沿用既有纪律：

1. **RED 先行**：每个行为先写会红的测试（含降级矩阵对应格）。
2. **定向回归**：受影响目录先跑一遍。
3. **全量门禁**：`run.py <label> gate`，要求 format 0 改动 / analyze 干净 / 全绿 / exit 0 /
   `changed_during_run: []`。
4. **设备复验**：自有 AVD `LocalFit_API35`；至少覆盖「菜单搜索一次真实查询（含语义命中）」、
   「AI 短名单注入一次」、「调度在充电+后台时真的领取任务」三类帧。
5. **文档同步**：`docs/21`（新增 Key）、`docs/INDEX.md`、`STATUS.md`、逐包证据；
   blocked/not run 如实登记。

建议门禁标签：`m1-gate`、`m2-gate`、`m3-gate`，最终 `next-final`。

---

## 6. 风险与回滚

| 风险 | 对策 |
|---|---|
| 搜索框让菜单页超过 500 行预算 | 结果抽成独立件；页内只留输入框与状态 |
| 语义名次在搜索框里造成首查卡顿 | 进页空闲预建索引（textHash 复用）；不可用即退关键词 |
| 短名单每轮注入 30 条抬高 token | 意图门控 + 30 条上限 + 段级缓存；无意图不注入 |
| 调度自动跑任务耗电 | 只在充电 + 后台；用户可暂停；任务幂等可重入 |
| 容量提到 2000 后注入变慢 | 注入候选固定 200 条打分，与总条数解耦（有基准测试） |
| 向量判重误杀正常记忆 | 只对 ≥0.96 拒绝；0.88–0.96 一律「提议」；`allow` 可强制写入 |
| 自动提炼产生真实 AI 调用 | 默认关 + 开启前说明 + 失败可重试；不静默写库 |
| 口味向量与标签画像叠加放大 | 取较大者不叠加；只软排序，硬过滤不动 |

回滚：全部为加法（新文件/新 Key/可选参数/常量），回滚 = 移除调用点；无 schema 变更，无数据迁移。

---

## 7. 决策点（需用户点头）

| # | 问题 | 建议 |
|---|---|---|
| D1 | 是否新增 `battery_plus` 依赖用于充电判定 | 建议加（BSD-3、无网络权限）；不接受则用「后台近似空闲」并如实标注 |
| D2 | 会话结束提炼是否允许自动发起真实 AI 调用 | 建议默认关、用户开启后运行；不开启时只做「手动提炼」 |

---

## 8. 变更记录

- 2026-10-19：首版。依据 `p21-final` 基线与逐条代码核对（见 §1 表）；范围限定为 A1–A4 / B5–B11，
  C 类（HNSW、arm64 真机）继续登记为未做。
