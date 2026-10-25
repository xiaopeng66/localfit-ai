# LocalFit AI 2.0 详细开发规范

> 本文是 LocalFit AI 2.0 的 normative contract：定义产品、数据、AI 协议、UI、隐私、质量和分阶段交付要求。
> 实时实现进度、唯一 active slice、验证证据和下一条命令只看根目录 [`STATUS.md`](../STATUS.md)。
> 本文不承载聊天上下文、历史完成记录或当前会话状态；历史 1.x 资料仅在 `docs/history/1.x/` 追溯。
>
> 关联文档：
> - `docs/01-product.md`：2.0 产品范围
> - `docs/02-architecture.md`：2.0 分层、存储和隐私架构
> - `docs/03-data-and-contracts.md`：2.0 实体与 AI schema
> - `docs/04-roadmap.md`：2.0 阶段路线与退出条件
> - `docs/05-quality-and-release.md`：2.0 质量与发布门槛
> - `docs/21-ui-redesign-spec.md`：**UI 唯一依据**（视觉、交互、数据契约、测试策略）
> - `docs/22-ui-redesign-refactor-plan.md`：UI 重设计改造方案

---

## 1. 版本目标

### 1.1 2.0 一句话

LocalFit AI 2.0 是一个**本地优先、AI 辅助、以校园就餐场景为中心的饮食与训练决策工具**：它知道用户今天的目标、已经吃了什么、学校哪些窗口在营业、菜单有哪些可核验信息，然后给出“现在去哪里、吃什么、吃多少”的可解释候选，用户确认后才形成计划或记录。

### 1.2 2.0 要解决的问题

1. 现有 AI 能生成餐食和训练草案，但能力分散，两个 Provider 重复实现网络传输和错误处理，提示词与 schema 版本管理不统一。
2. AI 结果不能直接作为营养事实。模型可能编造食物、营养、价格、过敏原安全结论或不存在的动作 ID，2.0 必须把所有结果限制在本地允许集合内。
3. 用户在学校就餐时，问题不是“给我一道食谱”，而是“今天中午去哪一个食堂窗口，买什么，如何满足我的目标”。当前没有学校、食堂、窗口、菜单、营业时间或路线实体。
4. 2.0 之前随包食物种子约 2,464 条，仅适合小规模本地验证，不足以覆盖常见基础食物、地方菜、品牌包装食品和校园菜名。**2026-10-02 已整体替换为 FoodCalu 派生的随包中文库（`assets/seed/foods.v4.json`，49,464 条，见 §5.2/§5.3 与 ADR-025）**，数据量这一项在「条数」上达成 §5.2 A 层目标，但该来源**没有可再分发的许可证**，因此只适用于「个人自用、不再分发」的定位。
5. 现有 UI 是已作废的旧视觉语言（旧规范已于 2026-09-28 删除，见 §9.1）；用户已交付 7 个新设计稿（`ui设计/pages/*.html`），需要按新稿重建视觉与信息架构。

### 1.3 2.0 成功标准

以下指标是发布门槛，不是宣传承诺：

- 食物目录 manifest 的 canonical 食物条目达到 **50,000 条以上**；其中至少 10,000 条为经过人工抽样审计的常见中文基础食物或校园高频食物。
- 50,000 条目录中，具有完整 `kcal / protein / carbs / fat` 四项基础营养数据并允许参与本地计算的条目比例 ≥ 95%；不完整条目只能作为搜索参考，不能静默进入营养计算。
- 食物首屏搜索在中档 Android 真机、50,000 条目录下 P95 < 200ms；分页不超过 50 条，不允许一次性把全库加载到内存。
- 所有新增 AI 任务的结构化 schema 通过率 ≥ 99%（固定脱敏评测集）；失败结果进入可恢复错误路径，不丢失用户输入。
- AI 不得产生未知本地 ID 的可确认候选；未知、歧义、营养缺失或来源过期时，界面必须展示“需要确认”，不能展示为已验证推荐。
- 菜单导入支持至少一种稳定输入方式：用户粘贴文本或导入本地文件；解析失败可以保留原文并人工修正，不得生成空菜单覆盖原数据。
- 每日计划生成不依赖云端 AI 也能完成基础候选排序；AI 不可用时，用户仍可使用本地菜单、食物库和规则引擎完成规划。
- 飞行模式下可使用本地食物、已保存菜单、已保存计划、历史记录和训练功能；云端 AI、外部路线查询和远程菜单抓取明确显示不可用。
- 不引入账号、开发者业务后端、后台定位、广告、社区、排行榜、商城或自动下单。

---

## 2. 当前实现基线

本节以当前代码和文档为基线，历史文档中的测试数量和模拟器结果必须在 2.0 发布前重新执行，不能直接视为本轮新证据。

### 2.1 当前代码基线

本节只记录实现边界，不替代 `STATUS.md` 的实时状态。当前代码具备可继续承载 2.0 的本地加密存储、饮食/训练记录、既有 AI 草案流程和**待重建的旧视觉基线**（旧 UI 规范已删除，新依据见 §9.1）；2.0 新增的统一 Transport、校园菜单、50,000+ canonical food、FTS5、每日计划 solver、路线 adapter 和 AI route-level 工作台仍由路线图分阶段交付。

- Flutter/Dart 单体应用，Android 优先，iOS 已有工程骨架；数据库为 Drift + SQLite + SQLCipher，当前 schema v19。
- 本地档案、目标、餐食、训练、统计和备份是事实源；无账号、业务后端和云端用户库。
- 现有两个 BYOK OpenAI-compatible Provider 分别服务餐图识别和训练计划；兼容合同为 `meal-estimate.v1`、`workout-plan.v1`。（2026-10-04：`recipe-plan.v1` 与食谱/周计划整族删除，见 `docs/28` §6。）
- **AI 对话通用编辑 `chat-edit.v1`**（2026-10-02，docs/23）：对话内 AI 以 JSON 信封
  `{"reply","edits"}` 提议修改，23 条命令注册表（decoder/executor/prompt 三方单源）+
  可编辑数据快照注入 + 「用户点应用才写库」硬门；详见 `docs/23-chat-universal-edit.md`。
- **AI 供应商协议三选一**（2026-10-02，docs/24，schema v18）：设置里可选
  Chat Completions（默认，旧行为逐字节不变）/ Responses / Anthropic Messages；
  六个 AI 出口共用一张 wire 表（`ai_protocol_wire.dart`）；旧库 `protocol=NULL`
  回落 Chat Completions；非 chat 协议不支持语音转写（诚实拒绝）。详见
  `docs/24-ai-provider-protocols.md`。
- 现有 AI 已具备 HTTPS、禁止重定向、header-only Key、超时、取消、响应大小限制、JSON 解码、本地匹配和用户确认边界；2.0-0 将抽取共享 `AiTransport`，不是改变领域语义。
- 现有 UI 的主题 token、今日/饮食/拍照/训练/我的页面、底部弹层、onboarding、骨架屏和暗色接线是**待按新设计稿重建的起点**；新视觉依据见 §9.1（`docs/21`），重建阶段编排见 `docs/22`。

### 2.2 2.0 必须先修正的基线问题

1. **AI 传输重复**：两个 Provider 各自实现 Dio、超时、取消、状态码和 `message.content` 提取。2.0 统一为 `AiTransport`，业务 Provider 只负责任务投影和 schema 解码。
2. **协议文档不一致**：当前训练计划文档示例曾使用 `weeks`，实际 Provider/domain/decoder 使用 `days`。2.0 以实际 `days` 合同为兼容基线，新增版本不得继续沿用 `weeks`。
3. **数值边界不统一**：不同 decoder 对 0、空文本、正数和非负数的约束不完全一致。2.0 禁止使用通用“所有数值必须大于 0”规则，必须按字段定义 `minInclusive` 或 `minExclusive`。
4. **大页面状态过多**：`training_page.dart`、`nutrition_page.dart`、`settings_page.dart` 和 AI 草案弹层承担了过多状态。2.0 逐步迁移到 route-level flow、controller 和 draft state，不做一次性全量重写。
5. **食物搜索扩容风险**：当前搜索主要是 SQLite `LIKE`，不能直接承载 50,000+ 条目录；必须先加入 FTS5、分页和导入分片。
6. **清除数据的完整性**：2.0 清空功能必须同步删除数据库、应用私有媒体、菜单原始文件、缓存、临时文件、Secure Storage 中的数据库密钥和 AI API Key 引用；当前 `clear_all_local_data.dart` 的数据库行删除不足以作为 2.0 方案。
7. **备份扩展**：新增菜单、食物目录用户修正、计划和 AI 审计元数据后，必须同步更新 JSON 导出、`.lfb` 恢复、CSV 策略、迁移测试和清除逻辑。

---

## 3. 产品信息架构 2.0

### 3.1 保留五个主导航

不增加第六个底部 Tab，避免导航拥挤。新能力按以下方式归位：

| 入口 | 2.0 内容 |
|---|---|
| 今日 | 今日目标、下一餐窗口、校园菜单推荐、计划执行状态、训练任务、体重与趋势 |
| 饮食 | 记录、校园菜单、食物库（2026-10-04：`计划`、`食谱`、`采购清单` 随整族删除，见 `docs/28` §6） |
| 拍照 | 拍照识别、候选修正、确认入账 |
| 训练 | 动作库、计划、执行、统计、AI 训练计划 |
| 我的 | 档案、AI 供应商、菜单来源管理、隐私、备份、数据管理 |

### 3.2 新增「AI 创作工作台」

AI 不做一个无限制聊天框。无限制聊天容易产生无法解析的文本、无法追溯的建议和未经确认的事实。2.0 使用任务卡式工作台：

1. **生成今日吃法**：根据目标、已摄入、保存菜单、营业窗口和用户时间生成计划草案。
2. ~~**创作一周食谱**~~（已下线：2026-10-04 按用户裁定 D3/N4 整族删除，见 `docs/28` §6）
3. **解析学校菜单**：把用户提供的文本、文件或照片转成可编辑菜单草案。
4. **这道菜怎么吃**：对某个菜单项或食物给出份量和替换解释，营养仍由本地计算。
5. **生成训练计划**：保留现有动作 ID allow-list 机制，升级统一协议。
6. **整理我的常吃搭配**：根据用户主动选择的本地历史摘要生成可编辑快捷餐，不发送完整历史明细（2026-10-04 起为只读建议，不写入本地事实，见 `docs/28` §6）。

每张任务卡都显示：发送什么、不会发送什么、目的地主机、模型、Prompt 版本、输出 schema 版本、结果如何被本地校验。

### 3.3 2.0 的核心决策流

```text
今天目标/时间/位置范围
  -> 本地读取已确认事实
  -> 本地筛选菜单与食物候选
  -> 确定性规则引擎计算可行候选
  -> 可选 AI 生成解释或排列草案
  -> 严格 schema 解码
  -> 本地 ID、营养、过敏、营业时间、冲突校验
  -> 用户编辑
  -> 独立的本地确认
  -> 写入计划或餐食事实
```

AI 不能跳过本地筛选、校验和确认。

---

## 4. AI 平台与结构化协议

### 4.1 统一 AI 分层

新增以下窄接口，具体命名可按现有 Dart 风格调整：

```dart
abstract interface class AiTransport {
  Future<AiTransportResponse> complete(AiTransportRequest request);
}

abstract interface class AiTaskCapability<TDraft> {
  String get taskId;
  String get contractVersion;
  String get promptVersion;
  Future<TDraft> run(AiTaskInput input, CancellationToken token);
}
```

建议目录：

```text
lib/features/ai/
  domain/ai_transport.dart
  domain/ai_task.dart
  domain/ai_draft_lifecycle.dart
  domain/ai_validation_report.dart
  data/open_ai_compatible_transport.dart
  data/ai_capability_registry.dart
  data/ai_response_content_extractor.dart
  data/prompt_catalog.dart
  data/prompt_projection.dart
```

现有两个 Provider 通过 adapter 接入，不在第一步删除，避免大范围回归：

- `OpenAiCompatibleMealRecognitionProvider` → `MealRecognitionTaskAdapter`
- `OpenAiCompatibleWorkoutPlanProvider` → `WorkoutPlanTaskAdapter`

### 4.2 统一请求元数据

每次调用在内存中生成以下元数据，只有非敏感摘要可以写入 `ai_usage`：

```json
{
  "task_id": "daily_menu_plan",
  "contract_version": "daily-menu-plan.v1",
  "prompt_version": "daily-menu-plan.prompt.2",
  "request_id": "local-random-id",
  "model": "user-selected-model",
  "input_projection_version": "projection.1",
  "response_mode": "native_json_or_strict_json"
}
```

以下内容禁止进入日志：API Key、图片正文、菜单原文、学校名称、精确位置、行程、食物 ID 列表、健康档案、历史餐食明细、价格、库存、模型原文。

### 4.3 供应商能力矩阵

设置页不再假定所有模型都支持同一能力。每个配置记录或运行时探测结果只允许以下能力标志：

- `text_json_object`
- `vision_json_object`
- `response_format_json_schema`
- `content_blocks`
- `max_input_bytes`
- `max_output_tokens`
- `supports_cancel`

调用顺序：

1. 如果供应商声明支持原生 JSON Schema，发送 `response_format` 和严格 schema。
2. 如果只支持 JSON object，发送 schema 摘要和严格 JSON 指令。
3. 如果连 JSON object 都不可靠，只允许执行不需要 AI 的本地规则路径；不尝试用正则从长篇自然语言中猜事实。
4. 供应商返回 Markdown、代码围栏、多个 JSON 根对象、超大响应、错误版本或缺少必填字段时，整份草案失败并提供手动入口。

`message.content` 需要兼容以下已知形式：纯字符串、内容块数组中若干文本块、供应商原生 JSON 对象。统一 Transport 负责转换为一个受大小限制的 UTF-8 文本或 JSON 值；业务 decoder 不再处理 Dio 细节。

### 4.4 草案生命周期

```text
created
 -> disclosed
 -> user_confirmed_send
 -> sent
 -> received
 -> parsed
 -> locally_validated
 -> user_edited
 -> confirmed
```

任一阶段都可以进入：

```text
cancelled | failed | discarded | expired
```

草案默认只驻留内存。若未来需要恢复未完成草案，必须单独增加加密 `ai_drafts` 表、过期时间、清除策略和备份选择，不得把模型原文混入正式餐食或计划表。

### 4.5 合同版本策略

- 当前 `meal-estimate.v1`、`workout-plan.v1` 作为兼容合同冻结，不直接改字段语义。
- 新任务使用独立合同，例如 `menu-normalize.v1`、`daily-menu-plan.v1`。
- 字段语义变化、允许的枚举变化、单位变化或根结构变化必须升 `contract_version`，不能只改 Prompt。
- Prompt 改动即使不改 schema，也必须递增 `prompt_version` 并重新跑脱敏评测。
- 旧 decoder 继续保留，直到所有历史草案/导出兼容测试完成。
- 新 decoder 采用字段级边界：
  - 文本：非空、最大字符数；
  - 克数/分钟/价格：是否允许 0 由字段定义；
  - 比例：`0..1` 闭区间；
  - 枚举：未知值拒绝整份或标为 `unknown`，不得静默映射成安全值；
  - ID：必须属于本次请求发送的 allow-list；
  - 数组：有上限、有唯一性和排序约束。

### 4.6 AI 提示词规范

每个任务的提示词由四层拼装，不允许页面临时拼接一整段自由文本：

1. **System contract**：只输出 JSON，合同版本、单位、上限、禁止字段。
2. **Task instruction**：任务目标和失败时的空结果结构。
3. **Input projection**：由本地代码生成的最小输入，不接收 UI 自由拼接的整段用户资料。
4. **Output example**：只放极短的合法例子，例子中的 ID 必须与本次 allow-list 一致。

所有提示词必须明确：

- 不生成营养总值作为事实；
- 不生成医疗、过敏安全、价格、库存、路线真实耗时结论；
- 不创建本地不存在的食物、动作、菜单项或窗口 ID；
- 不使用 Markdown、解释段落或代码围栏；
- 无法判断时使用 `unknown`、空候选或 `needs_confirmation: true`；
- 只返回合同中声明的字段。

### 4.7 推荐 Prompt 模板

#### 4.7.1 菜单规范化

```text
你是菜单结构化助手。只返回 menu-normalize.v1 JSON。
不要输出 Markdown、解释文字、营养结论或安全结论。
只能整理输入中明确出现的菜名、窗口名、营业时间、价格和原文营养声明。
未出现或无法确认的字段使用 null、unknown 或 needs_confirmation=true。
不要创建不存在的日期、窗口或菜品。
营养声明只能作为 source evidence，不能作为最终本地营养值。
```

#### 4.7.2 每日菜单计划

```text
你是本地计划候选排序助手。只能从 INPUT.candidates 中选择 candidate_id。
不要创造新的食物、菜单项、价格、路线或热量数字。
不要声称过敏安全、医疗适合或一定减重。
每个候选必须说明 reason_codes，并在证据不足时标记 needs_confirmation=true。
最终热量和宏量由本地规则引擎根据本地快照重算。
只返回 daily-menu-plan.v1 JSON。
```

### 4.8 新增合同一：菜单规范化 `menu-normalize.v1`

模型只负责从用户主动提供的菜单内容中提取结构，不负责裁决营养：

```json
{
  "schema_version": 1,
  "source_date": "2026-09-12",
  "venue_name": "东区食堂",
  "services": [
    {
      "service_name": "一楼炒饭窗口",
      "open_time": "10:30",
      "close_time": "13:30",
      "items": [
        {
          "display_name": "鸡蛋炒饭",
          "station_name": "炒饭窗口",
          "price_minor": 800,
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
          "questions": ["是否包含额外用油或配菜？"]
        }
      ]
    }
  ],
  "warnings": []
}
```

本地处理顺序：菜名去重 → alias 匹配 → 候选食物展示 → 用户修正 → 以本地 food revision 计算营养。`reported_nutrition` 永远带来源证据，不能覆盖本地计算。

### 4.9 新增合同二：每日菜单计划 `daily-menu-plan.v1`

AI 只从本地候选中排序和写解释，确定性 solver 先做硬约束筛选：

```json
{
  "schema_version": 1,
  "local_date": "2026-09-12",
  "slots": [
    {
      "slot": "lunch",
      "candidate_ids": ["menu-item-local-id-1", "menu-item-local-id-2"],
      "selected_candidate_id": "menu-item-local-id-1",
      "reason_codes": ["within_open_window", "protein_gap_match"],
      "needs_confirmation": true,
      "explanation": "优先满足当前午餐窗口和蛋白质缺口，份量仍需确认。"
    }
  ],
  "unresolved": [],
  "warnings": []
}
```

本地必须验证：候选 ID 属于请求 allow-list、窗口仍营业、来源未过期、餐次未冲突、目标区间和过敏事实有效。最终热量和宏量来自本地 `food revision` 或菜单项已确认的本地匹配，不读取模型自报数字。

### 4.10 AI 失败时的体验

- 无配置：展示“先配置 AI”与“改用本地计划”。
- 无网、超时、401、429、5xx：保留用户输入和菜单草案，显示明确错误类型，提供手动继续。
- 非法 JSON：保留原始菜单草案在内存中但不显示为已解析事实，提供“重新生成 / 手动整理”。
- 部分菜项无法匹配：计划仍可展示，但未匹配项必须显著标记，不得进入确认按钮的“已核验”统计。
- AI 不可用不是 P1 记录链路的阻断条件。

---

## 5. 5 万级食物库 2.0

### 5.1 计数定义

“5 万种”按**去重后的 canonical food 条目**计数，不把别名、拼写、翻译和搜索关键词重复计算。每条 canonical food 必须拥有稳定 ID、来源、许可证状态和至少一个名称。

另行统计：

- `aliases`：搜索别名，不计入 50,000；
- `nutrition_revisions`：同一食物不同来源或时间版本；
- `portions`：碗、勺、袋、个等份量换算；
- `evidence`：数据来源、许可证、抓取时间、质量等级。

### 5.2 数据分层

| 层级 | 目标 | 能否参与本地营养计算 |
|---|---|---|
| A 常见基础食物 | ≥10,000；中文基础食材、熟制食品、校园高频菜 | 必须完整四项宏量并通过抽样审计 |
| B 包装/品牌食品 | ≥20,000；品牌、规格、口味变体 | 仅在来源和标签完整时参与 |
| C 地方菜/国际食物 | ≥15,000；地方名、英文名、异名 | 有完整数据才参与，否则搜索参考 |
| D 菜名与别名 | 不限；用于搜索和菜单匹配 | 不能独立参与计算，必须指向 canonical food |

目标合计至少 50,000 canonical rows。不能为了达到数字复制同一营养记录；近重复条目必须有品牌、配方、规格或来源差异。

> **2026-10-02 现状（ADR-025）**：随包中文库（`assets/seed/foods.v4.json`，49,464 条）
> 同时承担 A 层与 B/C 层的搜索覆盖——它按条数已超过「A 层 ≥10,000 中文基础食物」的
> 数字目标，但条目**没有人工抽样审计报告**，且来源无许可证（见 §5.3），所以判据上
> 只能算「数字达成、合规未达成」。目录（catalog）通道保留给有明确许可证的来源
> （当前只有按需导入的 Open Food Facts / ODbL），**2026-10-02 起不再随包任何分片**。

### 5.3 数据来源和许可证门槛

候选来源可以包括公开营养数据、公共营养数据库和用户主动录入，但每个来源必须先完成许可证审核：

- manifest 记录 source、license、attribution、retrieved_at、transform_version；
- 不清楚是否允许再分发的源不进入发布包；
- 用户自建食物只保存在本机，不进入官方种子；
- 任何品牌数据必须保留来源和地区，不能把用户上传照片的内容自动汇入公共种子；
- 2.0 发布前生成第三方许可清单和删除/替换来源的脚本。

**2026-10-02 起的实际来源与归属**（明细见 `docs/THIRD_PARTY_LICENSES.md`）：

| 层 | 来源 | 许可证 | 到达方式 |
|---|---|---|---|
| 随包种子 | FoodCalu 中文食物库（`gaosheng293/FoodCalu`） | 上游未声明许可证 | 随包 `assets/seed/foods.v4.json` |
| 随包种子 | `yuhonas/free-exercise-db`（动作库，2026-10-04 起） | `Unlicense`（public domain） | 随包 `assets/seed/exercises.v3.json`：312 条 = 上游派生 305 + 手写保留 7，上游只有英文名、中文名由本仓库译名表生成 |
| 目录 | Open Food Facts | `odbl-1.0` | 不随包，用户按需导入分片 |

动作种子的「删除/替换来源」脚本是 `tool/exercise_seed/strip_exercise_source.py`（与食物种子那份同形，
按每条记录的 `origin` 字段作业；`origin` 只在种子里，不落库、不上卡）。

两条硬约束：①**无明确许可证的来源进不了目录通道**（`allowedCatalogLicenses` 白名单是冻结的），
所以 FoodCalu 只能停在「随包种子 + 个人自用」这一格；②**目录机制不等于随包**——随时包任何
分片都要同步改 `test/privacy` 的审计断言、`CatalogManifest.coreShard` 的约定说明与 `docs/evidence`。

### 5.4 离线 ETL 管线

不把 50,000 条 JSON 在 App 启动时全量解析和逐行插入。采用离线生成、分片发布、校验后导入：

```text
raw source files
  -> normalize names / units / locales
  -> deduplicate canonical candidates
  -> validate nutrition ranges
  -> infer aliases and categories
  -> attach evidence and license
  -> generate stable IDs
  -> build SQLite shard + FTS5 index
  -> generate manifest + hash + row counts
  -> app verifies manifest
  -> background/batched import
```

建议目录：

```text
tool/food_catalog/
  sources/
  normalize.py
  deduplicate.py
  validate.py
  build_sqlite.py
  build_fts.py
  manifest.py
  README.md
assets/catalog/
  catalog.manifest.json
  foods-core-000.sqlite
  foods-core-001.sqlite
  foods-brand-000.sqlite
```

### 5.5 目录实体

保留现有 `foods` 作为 canonical 入口，增量增加：

- `food_aliases`：`food_id`、语言、规范化文本、别名类型、来源、置信度；
- `food_nutrition_revisions`：`food_id`、版本、每 100g kcal/蛋白/碳水/脂肪、微量营养可选字段、来源证据；
- `food_portions`：`food_id`、份量名称、克数、地区和来源；
- `food_evidence`：来源、许可证、采集时间、质量等级、原始记录哈希；
- `food_import_jobs`：导入版本、状态、已导入分片、错误数、回滚状态；
- `food_search`：SQLite FTS5 虚拟表，索引中文名称、拼音/别名、品牌、分类和规范化 token。

历史 `meal_items` 必须记录当时的 `food_revision` 或完整营养快照。目录升级不能改变历史营养。

### 5.6 导入策略

- 首次安装导入**随包种子**（`assets/seed/foods.v4.json`，49,464 条）保证首屏可用；
  2026-10-02 起**没有任何随包目录分片**（中文基础食物已由种子承担）；
- 目录分片（若有）由用户主动点击导入或在设置中开启本地导入，不能无提示联网下载；
- 每个分片先写临时表，校验行数、哈希、唯一 ID、单位和营养范围后再切换；
- 新版本校验失败保留旧目录，不能把目录切成半套；
- 内存峰值和磁盘剩余空间不足时停止导入并提供恢复；
- 清空用户数据不能误删随包只读种子，但必须删除用户目录修正和缓存索引；
- 换种子版本时清理上一代种子行（`seed-v1/v2/v3`），**只删没有被餐次、菜单匹配引用的行**，用户自建行永不触碰。

### 5.7 搜索与匹配

搜索优先级：精确 canonical 名称 > 用户常用别名 > 中文前缀 > 拼音/英文别名 > 品牌和分类。所有结果分页并显示数据状态：

- `verified`：本地完整营养和来源；
- `estimated`：有来源但存在估算；
- `incomplete`：可搜索但缺营养，不能加入确认计划；
- `user_created`：用户自建，只在本机有效；
- `stale`：来源过期，需要重新确认。

AI 图片或菜单匹配只发送本地检索得到的 top-K 候选 ID、名称和必要元数据，不发送完整 50,000 条目录。

### 5.8 数据质量门槛

每次生成 manifest 必须报告：

- canonical 行数、alias 行数、重复 ID 数；
- 完整宏量比例、缺失字段分布；
- 每 100g 数值异常、能量与宏量差异异常；
- 中文名称覆盖率、校园常见菜名覆盖率；
- 来源和许可证缺失数；
- FTS 索引行数和 hash。

任何重复 ID、非法单位、NaN/Infinity、负营养值、无许可证来源不得进入发布分片。

> **缺值与 0 同形（2026-10-06 实测，P8a 登记）**：随包种子
> `assets/seed/foods.v4.json` 的四个营养素字段**永远是非负有限数字**——
> `food_seed_importer.dart` 的 `number()` 读到非 `num` / 非有限 / 负值直接抛
> `FormatException`，JSON 里既没有 `null` 也没有缺字段。上游把「没填」写成 `0`：
> 实测 49,464 行里 `kcal == 0` 有 **206** 行、`protein == 0` 有 **4,151** 行、
> `carbs == 0` 有 1,273 行、`fat == 0` 有 6,358 行。目录分片读取路径
> （`catalog_shard_detail_source.dart`）同样把缺字段折成 `0`
> （`(row['x'] as num?)?.toDouble() ?? 0`）。
> ⇒ **领域层无法区分「真的是 0 克」与「上游没填」**：「这一项有没有」只能靠
> `canJoinPlan` / 完整性标记这类**独立事实**判断，不能靠数值本身。UI 侧的两个
> 上屏口径（环按事实判断把 `0` 当「无热量数据」；详情弹层的三行宏量按显示约定
> 写 `0g`）见 `docs/21 §3.11`。

---

## 6. 学校食堂与窗口菜单

### 6.1 产品模型

用户可以建立一个或多个本地校园地点，但不要求打开精确定位：

```text
校园/学校
  -> 食堂楼宇或餐厅
      -> 窗口/档口
          -> 营业时段
              -> 日期菜单
                  -> 菜品
                      -> 本地食物匹配 / 营养证据 / 价格证据
```

推荐实体：

- `campus_profiles`：用户命名的学校或园区，时区、备注，不保存精确坐标；
- `venues`：食堂或餐厅名称、别名、用户备注；
- `menu_sources`：来源类型、用户输入 URL/文件引用、许可证、是否允许保存原文；
- `menu_snapshots`：不可变菜单版本、业务日期、抓取/导入时间、内容 hash、状态、过期时间；
- `menu_services`：窗口名称、营业起止时间、星期规则；
- `menu_items`：菜名、价格、原文、状态、来源 snapshot；
- `menu_item_food_matches`：菜单项与本地 `food_id` 的候选及用户确认状态；
- `menu_item_nutrition_evidence`：标签、来源、估算范围、原文证据、置信度；
- `menu_import_jobs`：导入状态、解析错误、人工修正数和回滚信息；
- `availability_windows`：用户可去餐时段、课程/活动阻塞的手动时间块。

菜单原文和图片存应用私有加密目录，数据库只保存相对路径、哈希和摘要。用户可以选择“不保存原文，只保存已确认的结构化菜单”。

### 6.2 输入方式分阶段实现

按可靠性和隐私风险排序：

1. **P0：手动录入/粘贴文本**：最稳，无需网络和额外权限；
2. **P0：导入本地 TXT/CSV/JSON**：适合学校公布的表格；
3. **P1：导入 PDF**：先本机提取文本，提取失败再询问是否临时发送给用户选择的 AI；
4. **P1：导入菜单图片/OCR**：先本机预处理和去元数据，再走 OCR/AI；
5. **P2：用户主动刷新受控 URL**：只在用户点击时抓取，展示域名、时间和保存策略；
6. **P2：学校自定义 JSON/CSV 模板**：允许用户维护适配规则，不做后台爬虫。

不做后台持续抓取、不默认定位、不自动访问学校登录系统、不绕过验证码或访问需要授权的内容。

### 6.3 菜单导入流程

```text
选择学校/食堂
  -> 选择输入方式
  -> 本机读取和预处理
  -> 若需要 AI，先显示披露和目的地主机
  -> 解析为 MenuSnapshot 草案
  -> 菜名/窗口/时间/价格人工校正
  -> 本地 food alias top-K 匹配
  -> 用户确认匹配和营养证据
  -> 发布为本地菜单快照
```

失败时保留原输入和错误位置，不覆盖上一个有效快照。所有菜单显示“来源、导入时间、业务日期、过期状态”。

### 6.4 营养证据等级

| 等级 | 来源 | 能否用于严格计划 |
|---|---|---|
| A | 用户确认的本地基础食物组合或可信标签 | 可以，显示证据 |
| B | 用户确认的估算范围 | 可以作为范围候选，需确认 |
| C | AI 从图片/文字推断 | 只能作为待核验草案 |
| D | 无法匹配或来源过期 | 不能用于严格目标计算 |

菜单项没有足够证据时，界面显示“热量未知/需要确认”，不能用一个看似精确的 AI 数字填满卡片。

### 6.5 菜单 UI

视觉与结构以 `docs/21` §5.3 为准（菜单页为 `饮食 · 菜单.html` 的**菜品卡列表**）。以下为与视觉无关的产品约束，仍然有效：

- 饮食页的 `菜单` 是一个 sub-tab chip，不增加底部导航槽（底栏固定 5 槽，见 `docs/21` §4.1）；
- 顶部是校园/日期/新鲜度条；
- 二级筛选为食堂、窗口、餐次和营业中；
- 菜品卡必须显示来源等级（证据分级徽章）、更新时间和“已匹配/待确认”标签；
- 每个窗口显示营业时间和“现在可去/即将开始/已结束”；
- 菜单详情显示本地匹配食物、份量控制、营养范围、过敏原事实状态和手动修正入口；
- 过期快照仍可查看，但不能默认进入“今日推荐”；
- **菜品库（`DishLibrary`）是菜单页的唯一展示数据源**，不得把 `MenuItems` 直接渲染成菜品卡（理由与写入路径见 `docs/21` §5.3）。

---

## 7. 每日“去哪里、吃什么”规划引擎

### 7.1 原则

推荐由本地确定性引擎负责，AI 只做候选组织、自然语言解释或菜单解析。推荐不等于医疗建议，不保证减重，不自动下单。

### 7.2 输入

只使用用户明确保存或当前操作选择的事实：

- 今日热量和三大宏量目标区间；
- 已确认摄入快照；
- 用户选择的学校/食堂范围；
- 当前日期和餐次；
- 菜单营业时间；
- 用户手动填写的可用时间窗、课程阻塞和交通方式；
- 过敏原/饮食偏好事实；
- 可选本地路线缓存。

不自动读取未授权的日历、通讯录、精确定位或后台活动数据。

### 7.3 硬约束

候选不满足以下任一项时不能进入“可确认推荐”：

- 菜单快照已过期且没有用户手动确认继续使用；
- 窗口在目标到达时间不可用；
- 食物匹配存在已知过敏原冲突；
- 需要严格目标时却没有完整营养或估算范围；
- 计划与现有同日期同餐次冲突；
- 菜品或窗口 ID 不存在；
- 份量、克数或价格超出字段边界。

未知不是安全通过。未知候选可以放在“待确认”区域，但不能伪装成已满足目标。

### 7.4 排序目标

在硬约束过滤后，对候选计算可解释的归一化分数：

```text
score =
  0.40 * nutrition_deviation
+ 0.20 * macro_deviation
+ 0.15 * time_fit
+ 0.10 * distance_or_travel_fit
+ 0.10 * preference_fit
+ 0.05 * freshness_penalty
```

权重写入代码常量并配测试，不由 AI 动态改变。用户可在设置中选择“目标优先/省时优先/预算优先”，本地只调整排序权重，不绕过硬约束。

### 7.5 路线与窗口

2.0 分两级实现：

**第一阶段：不使用精确定位**

- 用户为校园、食堂和宿舍/教学楼设置名称；
- 用户手动填写常用步行分钟数或距离等级；
- 只提供“约 8 分钟”“时间未知”等本地提示。

**第二阶段：一次性路线查询**

- 用户主动选择起点、终点和交通方式；
- 外部 routing adapter 只返回预计时长、区间、置信度、来源、过期时间；
- 精确坐标不持久化或仅短 TTL 加密缓存；
- 不后台定位、不连续追踪、不把路线和完整健康档案发送给 AI；
- 路线只影响可达性排序，不裁决营养安全。

### 7.6 结果 UI

今日页新增“下一餐决策”主卡：

```text
下一餐  午餐 · 12:10–13:20
去哪里  东区食堂 · 二楼轻食窗口 · 约 8 分钟
吃什么  鸡胸肉杂粮饭（建议先确认份量）
目标影响  预计填补蛋白缺口，热量仍以本地匹配结果为准
证据    菜单更新于今天 09:20 · 2 项食材已匹配 · 1 项待确认
[查看菜单] [调整时间] [换一个]
```

用户点击“确认加入计划”后才创建 `daily_plan` 或对应的本地计划条目；点击“记录为已吃”必须走餐食确认流程，不允许推荐卡直接写入 consumed meal。

---

## 8. 数据模型与迁移计划

### 8.1 新增表分批落地

不要一次迁移全部 2.0 表，建议分批：

**Catalog v2**

- `food_aliases`
- `food_nutrition_revisions`
- `food_portions`
- `food_evidence`
- `food_import_jobs`
- SQLite FTS5 virtual table

**Menu v1**

- `campus_profiles`
- `venues`
- `menu_sources`
- `menu_snapshots`
- `menu_services`
- `menu_items`
- `menu_item_food_matches`
- `menu_item_nutrition_evidence`
- `menu_import_jobs`

**Planning v1**

- `availability_windows`
- `daily_plans`
- `daily_plan_slots`
- `daily_plan_candidates`
- `route_options`（仅在路线能力开始时新增）

**AI audit v1（可选，第二阶段再决定）**

- `ai_task_runs`：只存任务、版本、状态、耗时和错误类型，不存正文；
- `ai_drafts`：只有明确需要跨进程恢复时才增加，默认不落库。

### 8.2 关系边界

- `meals` 是已经吃过的事实；菜单、推荐、计划均不能自动写入。
- `meal_plan_entries`、`recipes` 已随食谱/周计划整族删除（2026-10-04，用户裁定 D3/N4，见 `docs/28` §6）；不要让菜单 item 伪装成食谱。
- `daily_plans` 是推荐/安排层，不能进入营养统计。
- `menu_snapshots` 是来源内容，不能直接变成 `foods` 或 `meals`。
- `food_nutrition_revisions` 是营养事实版本，历史 meal 必须保留快照或 revision 引用。
- 任何外部来源的 raw content 都必须与规范化实体分开，解析失败不得产生“半个正式菜单”。

### 8.3 迁移、备份和清除

每个 schema 版本必须同时提供：

- 前向迁移和回滚/失败保持现状测试；
- 新表 JSON 导出和 `.lfb` 恢复策略；
- 是否包含菜单原文、AI 草案和搜索缓存的用户预览；
- CSV 是否导出来源、日期、证据等级和本地修正；
- 清空数据库、媒体、缓存、临时文件、Secure Storage 的完整测试；
- 低存储、导入中断、重复导入和旧版本备份恢复测试。

官方 50,000 条只读种子不必复制到用户备份；用户自建 food、别名修正、菜单、匹配和计划必须按用户选择导出。

---

## 9. UI 设计方案

### 9.1 视觉依据

**UI 的唯一依据是 [`docs/21-ui-redesign-spec.md`](21-ui-redesign-spec.md)**（按 `ui设计/pages/*.html` 制定）。

本节不再复述具体视觉规格——凡涉及 token、组件、页面结构、数据接线与测试 Key，一律以 `docs/21` 为准。历史版本（方案 A「薄荷奶油」及其 2.0 增量）**已于 2026-09-28 从仓库删除**，不具备效力也不可读取。

改造策略、阶段编排与风险见 [`docs/22-ui-redesign-refactor-plan.md`](22-ui-redesign-refactor-plan.md)。

### 9.2 本节保留的通用约束

以下约束是工程性的、与具体视觉无关，仍然有效：

- **证据表达**：菜单项与 AI 生成数据不能只用热量大数字，必须使用证据标签。产品语义档位为 `已匹配` / `估算` / `待匹配` / `已过期` / `窗口已关`；视觉呈现见 `docs/21 §2.1.5` 与 `§3.5`。
- **状态齐备**：菜单项与 AI 结果必须同时显示 AI 生成字段、本地重算字段、来源与更新时间；未匹配、歧义、过期、未知状态必须可见。
- **两个按钮**：AI 结果的「生成」与「写入」是两个不同按钮，不得合并。
- **不阻塞**：AI/路线不可用时不阻塞本地记录。
- **数据纪律**：5 万条食物库必须采用搜索框、分类筛选、分页与骨架屏，禁止瀑布流一次展示全库。

### 9.3 UI 可维护性

新增页面必须遵守：

- 页面只负责布局和用户事件；
- draft、loading、error、validation 和 submit 由 feature controller/state 承担；
- 单个 Dart 页面建议控制在约 300–500 行以内，超过后拆成 section/widget/controller；
- 所有输入支持大字体和窄屏；
- 统一 empty/loading/error/offline/stale/conflict 状态；
- AI、菜单、路线按钮都必须提供 tooltip/semanticLabel；
- 不用颜色单独表达"已验证/待确认"，必须同时提供文字或图标。

---

## 10. 分阶段实施路线

### 2.0-0：协议和数据安全冻结

内容：

- 统一 `AiTransport` 和响应内容提取；
- 冻结当前三个 v1 合同；
- 修正文档中的 `days/weeks` 不一致；
- 统一字段级数值边界；
- 完成清空数据的 Secure Storage、媒体和临时文件清理；
- 为备份/导出/清除增加“新增实体清单”测试框架。

退出条件：现有所有 AI、备份、迁移和核心旅程不回归。

### 2.0-1：食物目录 v2

内容：

- ETL、manifest、许可证清单；
- aliases、nutrition revisions、portions、evidence；
- SQLite FTS5、分页、top-K 匹配；
- 先导入 10,000 条 core，再扩展到 50,000 条；
- benchmark 覆盖 50k/100k、冷启动、搜索、批量匹配和低存储。

退出条件：数量、来源、重复 ID、营养完整率和真机搜索指标达标。

### 2.0-2：AI 创作工作台

内容：

- capability registry、Prompt Catalog、合同版本；
- 新增菜单规范化和每日计划合同；
- 统一披露、取消、重试、失败和草案生命周期；
- AI 只能使用本地 allow-list；
- 生成与本地确认完全分离。

退出条件：脱敏集 JSON 通过率、未知 ID 拦截、非法结果恢复、提示词版本审计全部通过。

### 2.0-3：校园菜单本地能力

内容：

- campus/venue/service/menu snapshot/item；
- 粘贴文本、CSV/JSON、本地文件导入；
- 人工修正、去重、过期、新鲜度和证据展示；
- 菜单项与本地食物匹配；
- 旧快照不可被新导入静默覆盖。

退出条件：有效导入、重复导入幂等、解析失败可恢复、过期状态正确、备份恢复完整。

### 2.0-4：每日计划 solver

内容：

- 目标和已摄入缺口；
- 营业时间和用户手动 availability window；
- 菜单/食物统一候选接口；
- 硬约束过滤和可解释排序；
- AI 只生成候选理由或排序草案；
- 确认后写入 daily plan，不直接写 consumed meal。

退出条件：离线规则路径可用，冲突/过敏/过期/未知营养不误通过。

### 2.0-5：路线和“去哪里”

> **2026-10-13 退役（docs/32 §3 D10；第五轮 T8 落地、T16 复核）**：本阶段做过的
> 手动通勤时间（`profiles.manual_commute_minutes` + 设置页对话框 + AI 可编辑快照段）
> 已**整族删除**（列随 schema 23→24 drop），routing adapter 从未接线。本节清单保留为
> 历史计划；将来若要恢复「地点/通勤」按新需求重新裁决，不要照抄本段。

内容：

- 先实现手动通勤时间和用户命名地点；
- 再接一个可取消、短 TTL、字段白名单的 routing adapter；
- 增加路线来源、过期和置信度；
- 绝不后台定位。

退出条件：路线服务失败不影响菜单和手动计划；精确位置不进入日志、AI 请求或长期备份。

### 2.0-6：UI 和状态架构重构

内容：

- 按 `docs/21` 重建 7 个页面（今日 / 饮食·记录 / 饮食·菜单 / 拍照识餐 / 训练 / 我的 / AI 对话）；
- 底栏改 5 槽贴底栏（中间 AI 对话凸起圆），拍照识餐改为推入式二级页；
- 饮食页记录、菜单、食物库 sub-tab；
- route-level AI 工作台；
- 菜品卡、计划确认、证据状态；
- 将大页面拆分为 section/widget/controller；
- 50k 搜索骨架屏、分页、空/错/过期/离线态。

退出条件：设计稿视觉一致（`docs/21`），大字体/窄屏/暗色/无障碍通过，核心流程真机走通。

### 2.0-7：发布和数据质量

内容：

- Android 封闭测试，再做 iOS；
- 迁移、备份、清除、恢复和低存储测试；
- 50k 性能基准和 AI 脱敏评测；
- 菜单来源和第三方许可证检查；
- 商店隐私说明与实际网络行为逐项核对。

退出条件：P0 数据损坏和崩溃为 0，核心旅程全绿，签名包复测通过。

---

## 11. 测试和验收矩阵

### 11.1 AI

- Provider 原生 JSON Schema、JSON object 和严格 JSON fallback；
- content 字符串、content blocks、空 content、非 JSON、Markdown、多个根对象；
- 未知 schema、缺字段、空文本、0/负数/NaN/Infinity、超长文本、超数组；
- 未知 food/menu/exercise ID；
- 供应商 401、403、408、429、5xx、重定向、证书、超时、取消、响应过大；
- Prompt 版本变化触发固定评测集；
- 推理开关（docs/29 §P4）：关闭推理时 Chat Completions 请求体带
  `thinking: {"type": "disabled"}`，Responses / Anthropic 不发推理字段；
  纯推理回复（`content` 空、`reasoning_content` 有货）报可解释错误；
- 不记录正文、Key、图片、地点、学校、菜单、健康资料。

### 11.2 食物库

- ETL 重复 ID、名称归一化、别名、许可证缺失、营养异常；
- 分片导入幂等；
- 导入中断回滚；
- FTS 中文、拼音、英文、品牌和特殊字符搜索；
- 50k/100k 搜索 P95；
- 目录升级不改变历史 meal 快照；
- 用户自建食物和官方种子隔离；
- 种类枚举落库与回填（2026-10-10，docs/31 S5 需求 51/53）：`foods.category`
  存 `FoodCategory.id` 文本；内置种子行按名字确定性归类（`classify`，只补
  NULL，幂等），自建行由表单枚举下拉给值，不替用户猜「其他」；
- 食物库 CSV 导出（需求 54）：`localfit-foods-*.csv`，8 列
  （name/brand/category/kcal_per_100g/protein_per_100g/carbs_per_100g/
  fat_per_100g/origin），UTF-8 BOM + 全引号 + `\r\n`，category 落中文标签，
  origin 分内置/自建；
- 食物库 CSV 导入（需求 55–57）：设置页「添加食物数据」入口 → RFC 4180
  解析（上限 **256 MiB**——2026-10-13 由 16 MiB 提高，全库重建的 CSV 预计
  30+ MB，见 `docs/32` §4 T11）→ 预览三本账（可导入/与库内重复/格式错误）→
  用户决定跳过或全导；去重键 = (名称, 品牌) trim + 忽略大小写 + 全角折半角；
  导入一律走 `FoodRepository.createMany`（与 `create` 共用行构造）落「自建」，
  origin 列写「内置」也改不了身份；落库为**分批 + 单事务**，去重索引**分页**建。

### 11.3 菜单

- 文本/CSV/JSON/PDF/OCR 每种输入的成功、空、破损和超限；
- 日期、时区、营业时段和跨午夜窗口；
- 重复导入、同名不同窗口、价格缺失、来源过期；
- raw 文件保留/不保留选择；
- AI 解析失败后人工修正；
- 菜单匹配不自动写 meal；
- 菜单快照备份/恢复/清除。

### 11.4 每日规划

- 热量和三宏目标存在/缺失；
- 已摄入、未记录、超标和估算范围；
- 过敏冲突、未知事实、过期菜单；
- 窗口已关、无时间窗、路线未知；
- 候选无解时给出“无法严格推荐”的原因和手动入口；
- 计划确认不创建 consumed meal；
- 用户点击“已吃”必须进入餐食确认和本地快照流程。

### 11.5 UI

- 今日页、AI 工作台、菜单列表、菜单详情、每日确认页；
- 亮色、暗色、窄屏、大字体、系统减弱动画；
- empty/loading/error/offline/stale/conflict；
- TalkBack/VoiceOver 读出证据等级、确认状态和动作；
- 首屏搜索和菜单打开时间；
- 所有不可用按钮解释原因。

---

## 12. 明确不做和风险控制

### 不做

- 不做开放式 AI 聊天并把聊天内容直接转成记录；
- 不做 AI 自主写库、自主记录已吃、自主覆盖计划；
- 不做没有来源和许可证的 50,000 条“凑数数据”；
- 不做后台爬取学校网站、绕过登录/验证码或持续定位；
- 不做 AI 自报热量、价格、过敏安全或路线耗时作为最终事实；
- 不做开发者统一 API Key 或隐藏的云端用户数据库；
- 不把菜单推荐包装成医疗、减重保证或营养治疗。

### 主要风险

| 风险 | 控制措施 |
|---|---|
| 5 万数据授权不完整 | manifest 许可证门槛；不合规来源不进发布包 |
| AI 输出无法解析 | 原生 JSON Schema、版本化合同、严格 decoder、fake 评测 |
| 菜单热量误导 | 证据等级、范围、待确认状态、本地重算 |
| 菜单过期 | snapshot 不可变、业务日期、过期标签、禁止默认推荐 |
| 过敏误判 | 未知不等于安全；本地已知事实优先，冲突阻断 |
| 位置隐私 | 手动地点优先、短 TTL、无后台定位、日志白名单 |
| 新表破坏备份 | 每次迁移同步导出/恢复/清除/回滚测试 |
| 页面继续变大 | route-level flow、controller、section 拆分门槛 |
| AI 服务不可用 | 本地食物库、菜单和 solver 始终可用 |

---

## 13. 2.0 Definition of Done

一个 2.0 功能只有同时满足以下条件才算完成：

- 有明确的领域实体、来源和生命周期；
- AI 任务有独立 `task_id / contract_version / prompt_version`；
- 结构化结果通过 decoder、单位、范围、allow-list 和业务规则校验；
- AI 草案与正式事实隔离，用户编辑和本地确认是独立步骤；
- 营养、过敏、营业时间和路线结论由本地事实或明确来源支持；
- 数据库有迁移、导出、恢复、清除和失败回滚测试；
- 不影响离线手动记餐、训练和备份闭环；
- `dart format`、`flutter analyze`、相关单测、widget 测试、集成测试通过；
- Android 中档真机走通，之后再做 iOS；
- 真实 AI 调用只在手动 smoke test 使用，自动测试全部 fake；
- 文档、隐私声明、菜单来源许可证和实际网络行为一致。

## 14. 当前实施入口

当前唯一 active slice、实施边界、真实证据和下一条命令见 [`STATUS.md`](../STATUS.md)。新会话必须先读取该文件，再按其中的 Active Slice 读取本规范的相关章节和直接源码/测试。

在当前 `2.0-0/ai-transport` 完成并验证前，不得跳到菜单正式实体、50,000+ 目录、FTS5、每日计划 solver 或路线半成品。后续切片必须继续遵守本规范的 AI 可识别、可校验、可恢复和隐私边界。
