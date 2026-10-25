# LocalFit AI 2.0 技术架构

> 本文定义 2.0 的技术承载方式，不记录当前切片进度。
> 当前实现和下一步只看根目录 `STATUS.md`；产品目标见 `docs/01-product.md`；详细综合契约见 `docs/07-localfit-2.0-development-spec.md`。

## 1. 总体架构

LocalFit AI 2.0 继续采用 Flutter/Dart 单体、feature-first、依赖向内的分层：

```text
Presentation
  ↓
Application / Controllers / Local Solver
  ↓
Domain contracts / entities / validation
  ↓
Infrastructure
  ├─ Drift + SQLite + SQLCipher
  ├─ encrypted private files
  ├─ FTS5 catalog index
  ├─ user-triggered AI transport
  └─ optional user-triggered route adapter
```

领域层不得依赖 Flutter、Dio、SQLCipher 或具体 AI SDK。UI 不执行 SQL、HTTP、文件加密或营养裁决。

## 2. 运行边界

### 本地事实

本地加密数据库保存：

- profile、goals、daily targets、measurements；
- canonical foods、aliases、nutrition revisions、portions、evidence；
- confirmed meals 和 meal item nutrition snapshots；
- daily plans；
- campus、venues、menu snapshots、services、items、matches、evidence；
- exercises、workout plans、sessions、sets；
- 用户明确保存的菜单修正、偏好、预算。（**手动通勤时间**已随第五轮通勤全链路下线删除：
  2026-10-13 docs/32 §3 D10，`profiles.manual_commute_minutes` 随 schema 23→24 drop。）

### 外部内容

菜单原文、用户选择的图片、PDF、抓取响应和临时 AI 原文默认存应用私有加密目录，数据库只保存路径、hash、摘要和保留策略。用户可以选择不保存原文，只保存确认后的结构化菜单。

### 派生结果

今日统计、趋势、营养缺口、菜单候选排名、路线可达性和验证报告优先即时计算，不重复维护多个事实源。若性能需要缓存，缓存必须可重建、有版本和清除入口。

## 3. 功能目录

```text
lib/
  app/                         # theme, router, global composition
  core/                        # errors, time, IDs, privacy, storage
  features/
    ai/                        # transport, task registry, prompts, lifecycle
    catalog/                   # catalog import, search, revisions, evidence
    nutrition/                 # foods, meals, nutrition calculations
    menu/                      # campus, venues, snapshots, import/correction
    planning/                  # daily plan, solver, availability, candidates
    route/                     # explicit route adapter and TTL cache
    food_scan/
    training/
    dashboard/
    progress/
    backup/
    settings/
  data/database/               # Drift schema, migrations, key management
assets/
  catalog/                     # manifest and SQLite shards
  seed/                        # small audited seed resources
  models/                      # optional local models
```

只在实际切片落地时创建对应目录和文件，不预建空抽象。

## 4. AI 架构

### 4.1 统一 Transport

新增最小窄接口：

```dart
abstract interface class AiTransport {
  Future<AiTransportResponse> complete(AiTransportRequest request);
}
```

`AiTransportRequest` 至少包含：

- normalized endpoint reference；
- model；
- task ID、contract version、prompt version；
- text/content blocks；
- response mode；
- request byte cap、response byte cap；
- timeout、cancellation token；
- API Key 的 secure-storage reference（不把明文 Key 交给领域层）。

`AiTransportResponse` 只输出受大小限制的结构化值/UTF-8 内容、status category、request ID、耗时和 token usage（若供应商提供）。不输出完整请求/响应日志。

现有餐图识别和训练计划 Provider 通过 adapter 使用共享 transport。adapter 只负责：

1. 构造最小 input projection；
2. 从 `PromptCatalog` 读取提示词；
3. 指定合同和 allow-list；
4. 调用 decoder；
5. 生成 domain draft 和 `ValidationReport`。

### 4.2 供应商安全策略

- 只允许规范化 HTTPS API 根地址；
- 拒绝 query、fragment、userinfo、路径歧义和非允许端口；
- 固定相对 `chat/completions`，禁止重定向；
- API Key 只进 Authorization header；
- TLS 平台验证保持开启；
- 请求和响应均有字节上限；
- 支持取消、连接/发送/接收/总超时；
- 不做无限自动重试；可重试错误由 UI 提供有限手动重试；
- 错误只输出分类和用户可行动文案，不回显完整供应商响应。

### 4.3 结构化输出能力矩阵

按用户配置或一次性能力探测标记：

- `text_json_object`；
- `vision_json_object`；
- `response_format_json_schema`；
- `content_blocks`；
- `max_input_bytes`；
- `max_output_tokens`；
- `supports_cancel`。

调用优先级：原生 JSON Schema → JSON object → 严格 JSON。无法可靠返回 JSON 时禁用该任务并保留本地回退，不从自然语言或 Markdown 中正则猜事实。

统一 content extractor 可接受纯文本、文本 content blocks 或供应商原生 JSON 对象，但最终交给业务 decoder 的值必须是一个受限制的 JSON 根对象。

### 4.4 Task Registry 与 Prompt Catalog

每项 AI 能力注册：

```text
task_id
contract_version
prompt_version
input_projection_version
allowed_entities
max_input/max_output
privacy_disclosure
fallback
```

提示词由四层组成：

1. 固定 System contract；
2. Task instruction；
3. 本地代码生成的最小 Input projection；
4. 与 allow-list 一致的合法 Output example。

提示词禁止要求模型重复计算营养、判断医疗安全、声称真实烹饪时长、生成价格/库存/路线事实或创建本地不存在的 ID。

### 4.5 Draft Lifecycle

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

任何阶段可进入 `cancelled / failed / discarded / expired`。草案默认内存驻留；若未来需要跨进程恢复，必须单独设计加密草案表、TTL、清除和备份选择。

## 5. 本地规则和每日计划

### 5.1 Solver 优先

每日计划由本地 solver 先过滤硬约束，再排序。AI 可提供候选说明或排序草案，但不能改变硬约束和最终数值。

硬约束包括：

- 今日目标、已确认摄入和单位范围；
- 已知饮食/过敏事实；
- 菜单快照日期、新鲜度和证据等级；
- 窗口营业时间；
- 用户手动 availability windows；
- 计划日期/餐次冲突；
- 菜品/食物 ID 存在；
- 份量、价格和营养字段有效。

未知不等于通过。没有完整营养或过敏事实的条目可以显示为待确认，但不能进入严格的可确认推荐。

### 5.2 排序

默认分数由本地常量计算：

```text
0.40 nutrition deviation
0.20 macro deviation
0.15 time fit
0.10 distance/travel fit
0.10 preference fit
0.05 freshness penalty
```

所有分量需要可解释 reason code。用户可选择目标优先、省时优先或预算优先，但只能调整排序权重，不能绕过硬约束。

### 5.3 Route Adapter

> **2026-10-13 状态（docs/32 §3 D10）**：本节的「第一阶段」已实现过又被**整族下线**——
> 手动通勤时间（`profiles.manual_commute_minutes`、设置页对话框、AI 快照段）在第五轮
> 通勤全链路删除里清掉了，route adapter 从未接线。以下内容保留为**未接线的设计意图**；
> 将来要做「地点/路线」得从零重新裁决（当前 App 没有任何地点输入）。

第一阶段不请求地图：用户命名学校、食堂和常用地点，手动填写通勤分钟数或距离等级。

后续可接单一主动查询的 route adapter：

- 用户明确选择起点、终点、日期时间和交通方式；
- 只保存时长区间、置信度、来源、TTL 和请求 ID；
- 精确坐标不持久化或仅短 TTL 加密；
- 可取消、失败可回退手动通勤时间；
- 不后台定位、不持续追踪、不把路线和完整健康档案发给 AI。

## 6. 食物目录架构

官方目录按四层组织：

```text
canonical food
  ├─ aliases/localized names
  ├─ nutrition revisions
  ├─ portions
  └─ evidence/license
```

canonical food 需要稳定 ID、名称、类别、来源和状态。alias 不计入 50,000。nutrition revision 记录每 100g 营养、版本和来源，历史餐食必须使用保存快照或 revision reference。

### 6.1 导入

离线 ETL：

```text
source → normalize → deduplicate → validate
→ attach license/evidence → stable IDs
→ SQLite shards + FTS5 → manifest/hash
→ verified batched import → atomic activation
```

应用不得在启动时解析完整 50k JSON。导入先写临时表/分片，校验数量、hash、唯一 ID、单位和营养范围后切换；失败保留旧目录。

### 6.2 搜索

使用 SQLite FTS5，索引中文名称、规范化名称、别名、拼音/英文 token、品牌和类别。搜索必须分页、限制结果数量并按精确度/来源/状态排序。不能把全库加载到 UI isolate。

## 7. 校园菜单架构

菜单领域与食物领域分离：

```text
MenuSource
  → immutable MenuSnapshot
      → Venue / MenuService / MenuItem
          → FoodMatch / NutritionEvidence
              → user-confirmed DailyPlan or Meal
```

- Source 保存输入类型、许可、域名/文件引用和保存策略；
- Snapshot 保存业务日期、导入时间、内容 hash、状态和 TTL；
- Service 保存窗口名和营业时间；
- Item 保存菜名、价格、原文引用和状态；
- Match 保存 food ID、候选分数和用户确认状态；
- Evidence 保存来源、营养范围、证据等级和修正者/时间。

解析失败不得写空 snapshot 或覆盖上一个有效版本。菜单快照不直接创建 food 或 meal。

## 8. 数据库、备份和清除

新增实体按 Catalog、Menu、Planning、Route、AI audit 分批迁移。每次 schema 变化必须同时提供：

- 向前迁移和失败回滚测试；
- `.lfb` 加密备份的导出/恢复策略；
- JSON/CSV 是否包含菜单原文、缓存、AI 草案和用户修正的明确选择；
- 清除数据库、媒体、raw files、缓存、临时文件和 Secure Storage 的策略；
- 低存储、导入中断、重复导入和旧备份兼容测试。

官方只读种子可不复制到用户备份；用户自建食物、菜单、别名修正、匹配、计划和路线偏好必须按用户选择导出。

## 9. 隐私日志

默认不记录：

- API Key、图片和模型正文；
- 菜单原文、学校/食堂名称、精确位置和行程；
- food/menu/exercise ID 列表；
- 健康档案、历史餐食、预算、库存和采购行。

允许记录：本地随机 request ID、task ID、contract/prompt version、供应商类别、耗时、字节数、状态类别和 token usage（如无敏感关联）。日志采用白名单，不依赖字段名黑名单。

## 10. UI 与状态架构

页面只处理布局和事件；draft、loading、error、validation、submit 由 controller/state 管理。复杂流程使用独立 route-level 页面，不继续扩大巨型 StatefulWidget。

所有新页面必须实现：

- empty/loading/error/offline/stale/conflict/needs-confirmation；
- source/freshness/evidence/confidence 的文字和图标表达；
- 窄屏、大字体、暗色、减弱动画、TalkBack/VoiceOver；
- 本地回退和不可用原因。

具体视觉沿用 `docs/21-ui-redesign-spec.md`。

## 11. 关键决策

详见 [`docs/DECISIONS.md`](DECISIONS.md)：

- ADR-001 本地优先；
- ADR-002 AI 草案隔离；
- ADR-003 BYOK；
- ADR-004 本地 facts/solver 优先；
- ADR-005 50k catalog；
- ADR-006 菜单分层；
- ADR-007 路线隐私；
- ADR-008 UI 基线；
- ADR-009 STATUS 单一状态源；
- ADR-010 先统一 transport。
