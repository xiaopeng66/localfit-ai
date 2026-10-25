# LocalFit AI 2.0 数据与 AI 合同

> 本文是 2.0 数据模型、生命周期、迁移和结构化 AI 输出的规范。
> 当前实现状态和 active slice 只看 `STATUS.md`；历史 1.x 契约备份见 `docs/history/1.x/`。

## 1. 分层原则

2.0 数据分成四类，禁止跨层静默转换：

1. **Local facts**：用户确认的档案、目标、营养、食物、餐食、菜单匹配和训练事实。
2. **External content**：用户导入或主动获取的学校菜单原文、PDF、图片、URL 响应和来源证据。
3. **Planning context**：每日计划、可用时间、预算、营业窗口和路线选项。
4. **AI drafts**：结构化、可编辑、可丢弃的模型输出，默认只驻留内存。

AI draft 不能直接写入 local facts。只有本地验证和独立用户确认后，才可通过领域用例写入事实。

## 2. ID、单位和版本

- 主键使用随机 UUID/ULID 文本；导入不得依赖供应商或学校的可变 ID。
- 重量统一使用 `REAL grams`，必须有限且非负；需要正值的字段显式使用 `> 0`。
- 能量统一使用 `REAL kcal`；宏量使用 `REAL grams`。
- 时间存 UTC，业务日期和营业窗口同时保存本地日期/时区。
- 每个可编辑事实带 `created_at`、`updated_at`、`revision`；不可变快照带 `content_hash`。
- 外部数据必须携带 `source_id`、`source_version`、`retrieved_at`、`license_status` 和 `quality_status`。
- 任何字段语义、单位、枚举或根结构改变都必须升级合同/迁移版本，不能只改提示词。

## 3. 食物目录实体

### 3.1 Canonical food

`foods` 作为 canonical food 入口，至少包含：

```text
id, canonical_name, locale, category, brand, state,
source_id, source_version, license_status, created_at, updated_at
```

`state` 至少有：`verified | estimated | incomplete | user_created | stale`。

**2026-10-21（ADR-036「存储格式定死」）**：实际 `foods` 的存储列收敛为 13 个字段——
`id`、`name`（食物名称）、`brand`（品牌，可空）、`category`（**唯一分类**，取值 = App
`FoodCategory` 十枚举 id）、`kcalPer100g`/`proteinPer100g`/`carbsPer100g`/`fatPer100g`（每 100 g）、
`defaultServingGrams`（默认份量，可空）、`source`、`isUserCreated`（自建/内置）、`createdAt`、
`updatedAt`。schema 29 → 30 把 21 列契约带来的 15 列（`libraryCode`…`sourceNature`）与
`categoryGroup`/`categorySub` 一起 DROP（带存在性守卫；`DROP COLUMN` 需 SQLite ≥ 3.35）。

官方导入格式 = **10 列 CSV**（ADR-037，表头一字不改、顺序即下方顺序）：`食品ID`（可空，
读取后丢弃——身份去重走（名称, 品牌））、`品牌`、`食物名称`、**`别名`**（可空，多个用
`、`/`,`/`;` 分隔，落 `food_aliases` 表）、`一级分类`、`热量(kcal/100g)`、`蛋白质(g/100g)`、
`碳水化合物(g/100g)`、`脂肪(g/100g)`、`自建/内置`（导入侧读都不读，导入行一律**内置**；2026-10-23 用户：导入的食物都属内置，只有 App 内新建才是自建）。

- **分类硬门禁**：入库分类只能是十档（中文标签或 id），或旧文件的 24 个中文库大类（导入期
  自动映射）；**其他值整行拒绝**，预览弹层给出「无法识别的分类」去重清单与条数——由用户
  手工把文件改成十档后重导，不猜、不兜底成「其他」。原文不落库；二级分类不导入不存储。
- **名称固定格式**：`主名（备注；备注2）`。写入口（新建/编辑/CSV 导入/AI 建食物）统一归一化：
  `[]【】〔〕「」『』《》〈〉()` 与散引号按括号/引号处理、括号合并到名称末尾、括号前不留空格、
  末尾规格（`300克`）与短横线后缀（`鲫鱼-天津`）搬进括号；结构本来就坏的名称原样保留。
- 旧 21 列 / 旧 9 列 / 旧 8 列英文表头继续宽容接受，未认领的列读取后丢弃。
  用户的 xlsx 流水线（`tool/food_catalog/convert_food_xlsx.py`）产出前 8 列，可直接导入。

**别名（ADR-037）**：CSV 的「别名」列与编辑弹层的别名输入落 `food_aliases`
（`alias_type='manual'`、`source='import'/'user'`）；随包归一化资产派生的别名
`alias_type='nickname'`、`source='normalized'`。`normalized_text` 一律存
`normalizeSearchText` 归一化后的形态（去空白/全角→半角/小写），与菜单匹配、AI 预检索同一口径。

### 3.2 Alias

`food_aliases`：`food_id`、语言、规范化文本、alias type、来源、置信度。别名用于搜索和菜单匹配，不单独代表营养事实，不计入 50,000 canonical 计数。

**2026-10-21（ADR-037 起，别名可写）**：读点仍是三处（AI 预览搜索 `food_preview_search`、
菜单项匹配 `menu_item_matcher`、检索段重跑判据 `index_coordinator`），外加备份导出/恢复与
「清除所有数据」；**写入路径新增四条**：CSV 导入的「别名」列、手动新建/编辑弹层的别名输入、
随包归一化资产（`assets/seed/food_library_normalization.v1.csv` 一次性应用）、以及删除食物时的
外键级联清理。目录分片导入仍不写它（分片 ETL 生成的 `aliases` 表由分片检索通路自己读）。
匹配口径是**精确命中**（归一化后相等），不是模糊/向量——别名只解决「这东西还叫什么」。

### 3.3 营养 revision

`food_nutrition_revisions`：

```text
id, food_id, revision_number,
kcal_per_100g, protein_g_per_100g, carbs_g_per_100g, fat_g_per_100g,
source_evidence_id, quality_status, valid_from, valid_to
```

严格营养计算只能使用字段完整、范围有效、来源可追溯的 revision。历史 `meal_items` 必须保留使用的 revision 或完整数值快照。（2026-10-04：`recipe_items` 与「计划快照」随食谱/周计划整族删除，见 `docs/28` §6。）

### 3.4 Portions 和 evidence

`food_portions` 保存个、碗、勺、袋等用户可选份量及克数；`food_evidence` 保存来源、许可、采集时间、原始记录哈希、质量等级和转换版本。

## 4. 菜单实体

建议新增：

- `campus_profiles`：用户命名的学校/园区、时区和备注，不保存不必要的精确坐标；
- `venues`：食堂/餐厅名称和用户备注；
- `menu_sources`：输入类型、域名或文件引用、许可证和原文保存策略；
- `menu_snapshots`：不可变业务日期、导入时间、hash、版本、过期时间和状态；
- `menu_services`：窗口名称、星期规则、营业起止时间和时区；
- `menu_items`：菜名、窗口、**档口**、原文引用、照片路径和状态；
  （**2026-10-16 起没有价格列**：`price_minor` 随 v26 迁移整列删除，见 §4 末注。）
- `menu_item_food_matches`：菜单项到 food revision 的候选、匹配分数和用户确认状态；
- `menu_item_nutrition_evidence`：营养声明、范围、证据文本、来源、质量等级和更新时间；
- `menu_import_jobs`：输入、状态、行数、错误数、修正数和回滚状态。

菜单原文/图片和规范化条目必须分开。用户可选择导入后删除原文，只保留确认后的结构化信息。

### 菜单状态

- `draft`：尚未发布；
- `published`：可用于本地查询；
- `stale`：超过有效时间；
- `superseded`：被新快照替代但保留追溯；
- `failed`：解析失败，不能进入默认推荐。

菜单项证据状态至少包含：`matched | estimated | unresolved | expired | closed`。

## 5. 计划和路线实体

### 5.1 Availability

`availability_windows` 保存用户主动输入的可用就餐时间、星期/日期、时区和备注。课程、活动或日历只有用户明确选择导入后才可使用。

### 5.2 Daily plan

> **as-built（2026-10-24，`RV4-P3-01`/`R4`，`docs/56` D1 / `docs/58` B6 R4-4b）：**
> **三张表保留，生产读取者已整族退役。**
> `NextMealDecisionController` 与 `DailyPlanEngine` 已删除（零调用方），
> 「下一餐详情」入口 / 二级页 / 决策卡 / 事实行也一并删除。
> **表结构冻结不变**（`schema` 仍 30）：`daily_plans` / `daily_plan_slots` /
> `daily_plan_candidates` 继续存在，留将来复用与备份/恢复兼容；备份注册表与
> `export_restore_test` 的覆盖关系不变。
> `PlanningConstraintsRepository` 与 `constraints.set` 写入路径**保留**
> （`memory_promotion` 与 AI 记忆页仍在写），但**当前无本地读取者**——这是有意
> 保留的可写事实，不是死代码。

- `daily_plans`：业务日期、生成方式、状态和版本；
- `daily_plan_slots`：餐次、时间窗口、候选排序和用户确认状态；
- `daily_plan_candidates`：menu item/food 引用、营养快照、证据、原因码和待确认状态。

`daily_plans` 是安排，不是已摄入事实；不能参与今日 consumed nutrition 聚合。

### 5.3 Route option

`route_options` 只在路线能力实施时增加：起点/终点的用户命名引用、交通方式、时长区间、置信度、来源、查询时间和 TTL。精确坐标不长期保存；不后台定位。

路线只影响可达性排序，不裁决营养、过敏或医疗安全。

## 6. AI 草案生命周期

```text
created
 → disclosed
 → user_confirmed_send
 → sent
 → received
 → parsed
 → locally_validated
 → user_edited
 → confirmed
```

任意阶段可进入 `cancelled | failed | discarded | expired`。默认不建立持久化 `ai_drafts` 表；如果未来需要跨进程恢复，必须新增过期、加密、备份和清除设计。

## 7. AI 传输和任务合同

### 7.1 统一 Transport

```dart
abstract interface class AiTransport {
  Future<AiTransportResponse> complete(AiTransportRequest request);
}
```

Transport 负责 endpoint、Key header、响应模式、超时、取消、重定向、响应大小、状态分类和 content 提取；任务 adapter 负责 input projection、Prompt、decoder 和业务校验。

### 7.2 合同版本

冻结兼容：

- `meal-estimate.v1`；
- `workout-plan.v1`。

2.0 新增：

- `menu-normalize.v1`；
- `daily-menu-plan.v1`。

工作台六任务补全（2026-09-19，用户裁定放行）：

- `dish-guidance.v1`（这道菜怎么吃，咨询型）；
- `meal-pairing.v1`（常吃搭配）。

现有训练合同统一使用 `days`，不使用历史示例中的 `weeks` 根字段。

## 8. `menu-normalize.v1`

模型只能提取用户输入中明确存在的菜单内容：

```json
{
  "schema_version": 1,
  "source_date": "2026-09-12",
  "venue_name": "东区食堂",
  "services": [
    {
      "service_name": "一楼窗口",
      "open_time": "10:30",
      "close_time": "13:30",
      "items": [
        {
          "display_name": "鸡蛋炒饭",
          "station_name": "一楼窗口",
          "reported_nutrition": {
            "kcal": null,
            "protein_g": null,
            "carbs_g": null,
            "fat_g": null,
            "evidence_text": null
          },
          "ingredient_hints": ["米饭", "鸡蛋"],
          "allergen_hints": ["egg"],
          "needs_confirmation": true,
          "questions": ["是否包含额外用油？"]
        }
      ]
    }
  ],
  "warnings": []
}
```

本地必须检查日期、时间、文本长度、重复项和字段范围。`reported_nutrition` 只是来源证据，不能覆盖本地 food revision 的计算结果。

> **2026-10-16 契约变更（食堂菜品价格全删，用户指令）**：
> - `menu-normalize v1` 草案里**不再有** `price_minor`；解码器对它**容忍并忽略**
>   （旧草案/旧提示词仍可能带着它，收下比逼用户重跑更实在），不校验、不落库。
> - 本地 CSV 导入列约定收成 **4 列**：`窗口,开始,结束,菜名`（旧 5 列含 `价格分` 的
>   表头按新事实**拒绝**，报「文件内容不符合导入格式」；TXT 行尾的裸数字不再解析）。
> - `menu_items.price_minor` 列随 **schema v26** 迁移删除（`if (from < 26)` +
>   `sqlite_master`/`pragma_table_info` 存在性守卫 + `ALTER TABLE … DROP COLUMN`）。

## 9. `daily-menu-plan.v1`

> **as-built（2026-10-22，`RV2-P2-01`）：本节合同已随对应 AI 创作卡改为「对话启动」而退役。**
> 解码器（`DailyMenuPlanJsonDecoder`）已从 `lib/` 删除，生产链路零调用；原先由它保证的
> 「候选 allow-list / 不发明 id / 丢弃模型给的事实」现由 chat-edit 命令层承担
> （快照 id + 每命令参数规格）。本节文字保留为**历史合同**，不再有实现；
> 恢复消费面前须先补实现与测试。证据：`docs/52` `RV2-P2-01`、`docs/55` §7。
>
> **2026-10-24 补充（`RV4-P1-08`）：`dailyMenuPlanPromptTemplate` 已从 `promptCatalog`
> 摘除注册。** 它要求模型返回本节的 v1 JSON，而解码器早已退役——继续渲染等于
> 「要求模型输出 App 不能解析的形状」。文件保留（egress 评测集仍引用正文），
> 但 provider 不再渲染它。现行「生成今日吃法」的启动提示词在
> `ai_starter.dart::_dailyMenuPlanPrompt`（chat-edit 口径：`meal.create` 逐餐提议）。


AI 只能在本次请求提供的候选 allow-list 中选择和解释：

```json
{
  "schema_version": 1,
  "local_date": "2026-09-12",
  "slots": [
    {
      "slot": "lunch",
      "candidate_ids": ["menu-item-id-1", "menu-item-id-2"],
      "selected_candidate_id": "menu-item-id-1",
      "reason_codes": ["within_open_window", "protein_gap_match"],
      "needs_confirmation": true,
      "explanation": "优先满足当前午餐时间和蛋白质缺口，份量仍需确认。"
    }
  ],
  "unresolved": [],
  "warnings": []
}
```

本地必须验证候选 ID、餐次唯一性、日期、营业窗口、菜单新鲜度、证据状态、目标偏差和现有计划冲突。模型不得返回最终热量、宏量、价格、过敏安全或路线事实。

## 10. 解码和数值规则

所有 decoder 必须：

- 拒绝非 JSON、Markdown、代码围栏和多个根对象；
- 拒绝未知/不支持的 schema version；
- 对文本执行非空和长度上限；
- 对数字拒绝 NaN/Infinity，并按字段分别规定 `minInclusive` 或 `minExclusive`；
- 校验数组上限、ID 唯一性、枚举、日期和排序；
- 对本地 ID 做 allow-list 校验；
- 忽略未知字段但不放宽必填字段；
- 超时、取消、响应超限和非法结果均保留用户输入并进入可恢复路径。

## 11. 写入边界

- 菜单解析只能产生 `MenuSnapshot` 草案；不能直接创建 `Meal`。
- 每日推荐只能创建 `DailyPlan` 或待确认候选；不能直接写 `meals`。
- 用户点击“记录为已吃”时，必须重新走本地食物匹配、营养重算和餐食确认。
- 历史事实写入后不被 AI、菜单更新或目录更新静默覆盖。

## 12. 备份、恢复和清除

新表加入前必须明确：

- 是否进入 `.lfb` 加密备份；
- JSON/CSV 的字段和用户预览；
- raw menu、缓存、路线和 AI 审计是否可选；
- 恢复时的版本兼容和失败回滚；
- 全部清除对数据库、媒体、raw files、缓存、临时文件和 Secure Storage 的清理；
- 导入中断和低存储时的恢复行为。

## 13. 质量要求

每个新增合同、实体和 solver 必须在 `docs/evidence/` 记录实际测试结果；测试不得把模型原文、菜单原文、图片、Key、健康资料或精确位置写入日志。具体门槛见 `docs/05-quality-and-release.md`。

## 14. `dish-guidance.v1`（这道菜怎么吃，咨询型）

> **as-built（2026-10-22，`RV2-P2-01`）：本节合同已随对应 AI 创作卡改为「对话启动」而退役。**
> 解码器（`DishGuidanceJsonDecoder`）已从 `lib/` 删除，生产链路零调用；原先由它保证的
> 「候选 allow-list / 不发明 id / 丢弃模型给的事实」现由 chat-edit 命令层承担
> （快照 id + 每命令参数规格）。本节文字保留为**历史合同**，不再有实现；
> 恢复消费面前须先补实现与测试。证据：`docs/52` `RV2-P2-01`、`docs/55` §7。


输入投影：用户输入的菜名与补充说明（≤2KB）。合同要点：

```json
{
  "schema_version": 1,
  "dish_name": "番茄炒蛋",
  "portion_grams_min": 150,
  "portion_grams_max": 300,
  "portion_note": "少油",
  "slot_suggestion": "lunch",
  "pairing": ["配杂粮饭"],
  "substitutions": ["鸡蛋换豆腐"],
  "cautions": ["痛风少食"],
  "questions": ["咸淡如何"]
}
```

- **禁止营养字段**：decoder 丢弃模型返回的一切营养数字（`DishGuidanceDraft`
  类型上没有营养字段）；营养只能由本地目录匹配后计算，匹配不到就明示
  「无法计算（不猜测）」（docs/01 第 5 节第 4 条「不伪造营养事实」）。
- `slot_suggestion` 只接受四餐次值，无法识别归 null（不猜测）。
- 咨询型任务：不产生本地事实，任务卡不渲染「确认写入」。

## 15. `meal-pairing.v1`（常吃搭配）

> **as-built（2026-10-22，`RV2-P2-01`）：本节合同已随对应 AI 创作卡改为「对话启动」而退役。**
> 解码器（`MealPairingJsonDecoder`）已从 `lib/` 删除，生产链路零调用；原先由它保证的
> 「候选 allow-list / 不发明 id / 丢弃模型给的事实」现由 chat-edit 命令层承担
> （快照 id + 每命令参数规格）。本节文字保留为**历史合同**，不再有实现；
> 恢复消费面前须先补实现与测试。证据：`docs/52` `RV2-P2-01`、`docs/55` §7。


输入投影：用户点名的食材经本地目录匹配后的 allow-list（id、名称、每
100g 宏量）与搭配偏好。合同要点：

```json
{
  "schema_version": 1,
  "combos": [
    {
      "name": "高蛋白练后餐",
      "slot": "lunch",
      "items": [{ "food_id": "rice", "grams": 150 }],
      "note": "练后 1 小时内吃"
    }
  ],
  "warnings": []
}
```

- **allow-list 强制**：`food_id` 必须逐字来自本地匹配结果，发明 id 整单
  拒绝（与 workout-plan 同款）。
- 1–5 个方案、每方案 1–6 项、份量 1–1000g；营养由本地目录按份量重算。
- **只读建议**（2026-10-04）：食谱功能随整族删除后本任务不再有可写入的正式事实，
  任务卡不渲染「确认写入」；「不上传完整历史」= 只有点名食材的 allow-list 进投影，
  历史餐食一概不发送。
