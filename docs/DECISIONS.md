# LocalFit AI 2.0 决策记录

> 本文件是追加式决策日志，不是实时状态，也不是产品需求或数据契约。
> 当前状态只看根目录 `STATUS.md`；长期目标看 `GOAL.md`；详细规范看 `docs/07-localfit-2.0-development-spec.md`。
> 决策状态：`accepted`、`proposed`、`rejected`、`superseded`。

## ADR-001：本地优先，不建设业务后端

- Date: 2026-09-12
- Status: accepted
- Context: 用户要求无账号、本地保存和 BYOK；产品核心记录可在飞行模式下工作。
- Decision: 档案、餐食、食谱、训练、菜单、计划和统计以本地加密 SQLite/应用私有文件为事实源；不建设开发者业务后端、云端用户库或账号系统。
- Alternatives: 自建同步后端；放弃，因为会扩大隐私、运维和数据泄露边界。
- Consequences: 迁移、备份、恢复、清除、低存储和本地索引必须是一等能力。
- Affected: 全局架构、2.0-0 到 2.0-7。

## ADR-002：AI 草案与正式事实隔离

- Date: 2026-09-12
- Status: accepted
- Context: 模型可能产生错误食物、营养、过敏、价格或路线结论。
- Decision: AI 只能生成版本化、可编辑、可丢弃的草案；本地匹配、计算、规则校验和用户独立确认之后，才允许写入正式餐食、食谱或计划。
- Alternatives: AI 直接写库；拒绝，因为无法提供可靠审计和回滚边界。
- Consequences: 所有任务都需要 decoder、validation report、确认页和手动回退。
- Affected: AI、菜单、每日计划、训练、备份。

## ADR-003：BYOK、header-only Key、用户主动触发

- Date: 2026-09-12
- Status: accepted
- Context: 不在客户端放开发者 Key，也不让应用后台发送健康、菜单或位置数据。
- Decision: 用户自行配置 OpenAI-compatible Base URL、模型和 API Key；Key 只进 Secure Storage 和 Authorization header；AI/URL/路线请求必须由用户主动触发并先披露发送范围。
- Alternatives: 内置开发者 Key；拒绝，因为无法安全分摊密钥和计费。
- Consequences: 没有 AI 配置时必须保留本地记录和规划路径。
- Affected: `AiTransport`、设置、隐私说明、2.0-0/2.0-2/2.0-5。

## ADR-004：本地事实和确定性 solver 优先于 AI

- Date: 2026-09-12
- Status: accepted
- Context: 今日营养、菜单营业时间、过敏事实、价格库存和计划冲突可以由本地规则确定。
- Decision: 本地 facts 和 solver 先筛硬约束、重算营养和决定是否可确认；AI 只做候选创作、菜单结构化、排序解释或自然语言说明。
- Alternatives: 让 AI 直接生成每日推荐；拒绝，因为不可复现、难以测试且容易把未知当安全。
- Consequences: AI 不可用时基础推荐仍可运行；solver 必须有清晰的无解原因。
- Affected: 2.0-2、2.0-3、2.0-4、daily-menu-plan.v1。

## ADR-005：50k 食物目录采用离线 ETL、manifest、分片和 FTS5

- Date: 2026-09-12
- Status: accepted
- Context: 当前约 2,464 条种子和 LIKE 搜索不能承载 50,000+ canonical foods。
- Decision: 以可审计来源离线生成 canonical food、alias、nutrition revision、portion、evidence；输出带 hash/license/row count 的 SQLite 分片和 FTS5；应用分批导入，不在启动时解析全量 JSON。
- Alternatives: 继续单一大 JSON + LIKE；拒绝，因为启动、内存、搜索性能和质量无法控制。
- Consequences: 需要 ETL 工具、manifest、导入回滚、质量报告和历史快照兼容。
- Affected: 2.0-1、食物库、备份和迁移。

## ADR-006：校园菜单分为原文、快照、规范化条目和正式餐食

- Date: 2026-09-12
- Status: accepted
- Context: 学校菜单来源可能过期、缺营养或解析失败，不能直接成为餐食事实。
- Decision: `MenuSource/MenuSnapshot/MenuItem` 保存来源和结构化菜单；本地 food match/evidence 单独保存；只有用户走正式确认流程才创建 `Meal`。
- Alternatives: 菜单导入后直接写食物或餐食；拒绝，因为无法表达来源、过期和待确认状态。
- Consequences: 菜单需要快照 hash、来源、日期、过期状态、人工修正和导入回滚。
- Affected: 2.0-3、2.0-4、menu-normalize.v1。

## ADR-007：地点和路线默认手动、短 TTL、无后台定位

- Date: 2026-09-12
- Status: accepted
- Context: “去哪里”需要时间/可达性，但健康档案和精确位置不应被持续收集。
- Decision: 第一版使用用户命名地点和手动通勤分钟数；后续路线只在用户主动选择起点/终点时查询，保存最小区间、来源、置信度和短 TTL；不后台定位。
- Alternatives: 后台持续定位或长期保存精确坐标；拒绝，因为超出产品必要性和隐私边界。
- Consequences: 路线服务失败必须有手动时间回退；位置不得进入普通日志或 AI payload。
- Affected: 2.0-4、2.0-5、隐私和 UI。

## ADR-008：方案 A 作为 UI 基线，2.0 以信息架构增量演进

- Date: 2026-09-12
- Status: **superseded by ADR-023**（2026-09-27：视觉唯一依据改为 `ui设计/pages/*.html`）→ ADR-024（2026-09-28：其规范文档已从仓库删除）
- Context: 现有 UI 已完成薄荷奶油视觉基线，2.0 需要菜单、AI 工作台和证据状态。
- Decision: 保留方案 A 色彩、宏量三色、CalorieRing、浮岛导航、暗色和无障碍规则；新增今日决策卡、菜单、食物库和 route-level AI 工作台，不全面推翻现有主题。
- Alternatives: 等 2.0 完成后再整体换肤；拒绝，因为会让新功能和现有页面出现两套视觉语言。
- Consequences: 新页面必须复用现有 token，复杂流程逐步拆成 route-level controller。
- Affected: 旧 UI 规范（已删除）、2.0-6。

## ADR-009：STATUS.md 是唯一实时状态源

- Date: 2026-09-12
- Status: accepted
- Context: 旧路线图、README 和 Goal 同时记录阶段状态，导致新会话无法确定当前切片；项目没有 Git 元数据。
- Decision: 根目录 `STATUS.md` 只记录一个 active slice、真实证据、changed files、风险、handoff 和下一条命令。GOAL 只写长期目标，编号文档只写领域契约，历史内容放 `docs/history/1.x/`。
- Alternatives: 继续在 roadmap 末尾追加进度；拒绝，因为历史和当前状态会再次混杂。
- Consequences: 每个切片开始、检查点、验证和结束都必须更新 STATUS；旧验证结果必须标为 historical/not rerun。
- Affected: 全部文档、2.0-0 到 2.0-7、所有新会话。

## ADR-010：2.0-0 先统一 AI Transport，再做菜单和 50k 数据

- Date: 2026-09-12
- Status: accepted
- Context: 当前三个 Provider 重复实现网络逻辑，未来菜单和每日计划会增加更多 AI 任务。
- Decision: 首个 2.0 实现切片只做共享 transport、v1 adapter 和 decoder 边界测试；菜单正式实体、50k ETL 和真实 AI 调用必须等待该切片验证完成。
- Alternatives: 先做菜单 UI/爬虫或直接扩大食物库；拒绝，因为会把协议失败复制到更多功能。
- Consequences: 当前唯一 active slice 为 `2.0-0/ai-transport`。
- Affected: `STATUS.md`、`GOAL.md`、三条 Provider、2.0-0。

## ADR-011：共享 AiTransport 的接口形状与 adapter 过渡策略

- Date: 2026-09-15
- Status: accepted
- Context: 三个 Provider 的 HTTP 安全逻辑（endpoint 校验、重定向、超时、取消、大小上限、状态分类、content 提取）逐行重复；但 main.dart 组装和 14 个既有 Provider 测试依赖现有构造签名与 `dio` 公开字段。
- Decision: 新增 `lib/features/ai/domain/ai_transport.dart`（request/response/failure messages/cancellation token 最小接口）与 `data/open_ai_compatible_transport.dart`（全部共享 HTTP 行为）+ `data/ai_response_content_extractor.dart`（字符串/content blocks/原生 JSON 三种 content 统一策略）。三个 Provider 保留构造签名与 `dio` 字段，内部 `late final transport` 委托共享实现，作为 ADR-010 的过渡 adapter；未来任务（menu-normalize 等）直接依赖 `AiTransport` 接口。
- Alternatives: 一次性改构造签名为注入 `AiTransport`；拒绝，因为会同时触碰 main.dart、三个设置页组装点与全部 Provider 测试，回归面过大且无行为收益。
- Consequences: HTTP 行为单一来源；per-feature 失败文案经 `AiTransportFailureMessages` 注入保留；取消令牌逐 feature 桥接。后续新任务不得再自建 Dio 调用。
- Affected: `features/ai/*`、三条 Provider、2.0-0、2.0-2。

## ADR-012：全部清除清外围字节，恢复只清数据库行

- Date: 2026-09-15
- Status: accepted
- Context: 原 `ClearAllLocalData` 只删数据库行，临时餐图媒体与 Secure Storage 中的 AI API Key 在「清除全部本地数据」后残留；而恢复流程复用同一个 clear，会把不属于备份内容的外围字节清掉。
- Decision: `ClearAllLocalData` 增加可选 `temporaryMealImageStore`（clearStale）与 `apiKeyStore`（clear），全清在数据库行删除后执行；新增 `clearDatabaseRowsOnly` 供 `RestoreLocalFitData` 在恢复事务内使用。SQLCipher 数据库密钥不在全清范围（删密钥不重建库会导致下次启动损坏本地存储），完整密钥轮换需配合数据库重建另立切片评估。
- Alternatives: 保持仅删行并把外围清理放在设置页 UI 层；拒绝，因为清除语义会散落在页面，违反分层且难以测试。
- Consequences: 全清 = 行 + 临时媒体 + AI Key；恢复 = 仅行（外围字节保留）；媒体/Key 清理失败显式冒出不吞掉。
- Affected: `clear_all_local_data.dart`、`restore_localfit_data.dart`、`ai_api_key_store.dart`、`main.dart`、2.0-0、2.0-7。

## ADR-013：日志出口默认拒绝，白名单只有四个指标

- Date: 2026-09-15
- Status: accepted
- Context: `PrivacyLogger` 原本是默认放行——只在遇到已知敏感 key（学校/地点/菜单/健康）时替换值。任何新调用方只要换个字段名（`menuText`、`schoolName`、`food_id`）就能把原文写进日志，而 2.0 新增的菜单、目录、计划任务正是最容易踩这类字段的地方。
- Decision: 改成默认拒绝：只有 `resultKind`、`durationMs`、`requestBytes`、`responseBytes` 四个指标允许原样写入，其余 key 保留 key 名、值替换为 `[REDACTED:not-allow-listed]`；敏感 key 命中时用 `[REDACTED]` 且优先级高于白名单；容器类型（Map/List）未被列入白名单时整棵子树一并拒绝。生产代码仍不构造 `PrivacyLogger`（线上日志出口为零），出口接线前必须先扩展白名单并改审计断言。
- Alternatives: 保持默认放行、每加一个调用点就补一次敏感 key 清单；拒绝，因为漏一处就是隐私事故，且没有红得起来的测试。
- Consequences: 日志测试从「敏感值被替换」改成「非白名单值一律不出现」；新增日志指标必须同时改 `defaultAllowedKeys` 与测试。
- Affected: `lib/core/logging/privacy_logger.dart`、`test/privacy_logger_test.dart`、2.0-7d。

## ADR-014：第三方来源归属放应用内，开源组件许可走 LicenseRegistry

- Date: 2026-09-15
- Status: accepted
- Context: 随包食物种子来自 CFCT 镜像与 foodwake，`tool/food_seed/README.md` 声称「App 内已注明数据出处」，但应用里没有任何来源归属界面；同时 ODbL 的 OFF 目录将来也要求署名。开源依赖许可若手抄清单会漏掉传递依赖并很快过期。
- Decision: 新增 `lib/features/nutrition/domain/data_attribution.dart` 作为来源清单的单一来源（名称/上游/许可证/规模/是否随包），在「我的」页直读渲染；开源组件许可不手抄，用 Flutter `LicenseRegistry` 的 `showLicensePage` 汇总各依赖包 LICENSE。`test/privacy` 把清单与 `tool/food_seed/README.md`、`tool/food_catalog/etl_pipeline.py` 双向对齐。
- Alternatives: 只写 `docs/THIRD_PARTY_LICENSES.md` 不在应用内展示；拒绝，因为署名要求是给用户的，而且 README 的既有声明会变成假话。手写依赖许可清单；拒绝，维护成本高且必然过期。
- Consequences: 新增/替换数据源必须同时改清单、README/ETL 与 `docs/THIRD_PARTY_LICENSES.md`，否则测试红；`dataAttributionNote` 明确随包条目没有逐条许可证字段，不伪装。
- Affected: `data_attribution.dart`、`settings_page.dart`、`test/privacy/privacy_statement_audit_test.dart`、`docs/THIRD_PARTY_LICENSES.md`、`docs/08-store-privacy-and-permissions.md`、2.0-7d。

## ADR-015：目录只发布四项宏量齐全的条目，不完整条目在 ETL 阶段就不发

- Date: 2026-09-16
- Status: accepted
- Context: docs/07 §10/§5.2 要求「50,000 条目录中具备完整四项宏量、可参与本地营养计算的条目比例 ≥ 95%，不完整条目只能作搜索参考」。OFF 全量实测（2M 前缀）四项完整率只有 **80.27%**（20k 前缀是 96.94%，早期前缀偏乐观），按原实现把 `incomplete` 一并发布，`quality.macro_complete_ratio` 必然跌到 0.80，越过规范允许的 5% 搜索参考预算。
- Decision: 发布物只保留 `state == verified`（四项宏量齐全且通过异常校验）的条目；被排除的候选不静默丢弃，`quality.candidate_rows` 与 `quality.dropped_incomplete_macros` 如实计数；`build_manifest` 用 `MACRO_COMPLETE_MIN_RATIO = 0.95` 做硬门槛，不达标直接失败。`foods.state` 与 App 侧 `CatalogShardImporter` 的 incomplete 处理逻辑**保留不动**：一旦将来有来源能给出符合预算的少量搜索参考条目，管线仍能发布它们。
- Alternatives: ①把 `canonical_rows` 改定义为「仅完整条目」而继续发布 incomplete 行——被否，那是把门槛改成恒真，不完整条目仍会进发布包（App 侧会跳过，但包体、FTS 与审计口径都会说谎）。②靠 CFCT 等中文源补足 95%——中文源是 2.0-1 的另一个缺口，且 CFCT 再分发条款未清（`docs/THIRD_PARTY_LICENSES.md` §4），不能拿它救这一条。③放宽门槛到 80%——被否，规范数字是产品判断，不因单一数据源而改。
- Consequences: 发布目录 100% 可参与本地营养计算，`macro_complete_ratio` 由构造恒为 1.0（因此真正的把关是 `accept_catalog.py` 逐行重数「发布目录缺四项宏量的行 = 0」）；OFF 目录规模从 ~147 万降到 ~118 万（2M 前缀），仍远超 5 万门槛；中文/校园高频食物 ≥10,000 条仍缺，属独立缺口（需要可再分发的中文食物成分数据源）。
- Affected: `tool/food_catalog/etl_pipeline.py`、`tool/food_catalog/accept_catalog.py`、`tool/food_catalog/test_pipeline.py`、`test/fixtures/etl_catalog_manifest.smoke.json`、`test/features/nutrition/catalog_manifest_etl_fixture_test.dart`、2.0-1h。

## ADR-016：发布目录按流行度截断到 10 万条，搜索查询改成 FTS 先取 id

- Date: 2026-09-16
- Status: accepted
- Context: OFF 全量去重后有 **1,692,819** 条完整条目、85 个分片、849 MiB。真分片实测（`test/perf/catalog_real_scale_test.dart`）：搜索 `chicken*` 在 85 分片下进程内 P50 466 ms / P95 **750 ms**，超过 docs/07 §10 的「真机 P95 < 200 ms」；导入速度 8,196 行/秒 → 全量要 ~3.4 分钟纯 CPU（真机更慢），测试库内存增长 156 MiB/10 万行。docs/07 §2.0 的性能设计点写的是 **50k/100k**，1.69M 是它的 17–34 倍。
- Decision: ①发布目录按上游 `popularity_key`（OFF 的流行度键，越大越常见）降序截断到 `RELEASE_CANONICAL_CAP = 100000`（同分按 id，可复现），`top-N` 之外的数量写进 `quality.dropped_over_cap`；`--max-canonical 0` 仍可产出不截断的全量目录供离线分析。②`CatalogSearchService.search` 的 SQL 改成「FTS 子查询先按 bm25 取 top-N（含分页偏移）→ 外层按主键关联 foods」。③`accept_catalog.py` 增加「canonical ≤ 发布上限」门槛（`--max-canonical 0` 可关）。
- Alternatives: 只为搜索加连接缓存——被否，open/close 实测只占 5.6 ms/85 分片，瓶颈是 bm25 对全部前缀命中行打分（`ri*` 这类两字符前缀在 1.69M 下要 535 ms），缓存解决不了，且导入时长与包体问题依旧。一次性下载全部 1.69M 作为可选大目录——暂缓，先把发布物做对；真要在设备上跑通需要另立「大目录分片漫游/按需搜索」切片。
- Consequences: 发布目录 10 万条、5 个分片、约 50 MiB，落在规范的设计点内；`canonical ≥ 50,000` 仍有 2 倍余量；OFF 里流行度低的长尾商品不进发布包（用户仍可手动创建食物）；截断是发布层行为，ETL 的 normalize/去重/校验口径不变，全量目录随时可重建。
- Affected: `tool/food_catalog/etl_pipeline.py`（`FoodRecord.popularity`、`run_pipeline(max_canonical)`、manifest `dropped_over_cap`）、`tool/food_catalog/build_catalog.py`、`tool/food_catalog/accept_catalog.py`、`lib/features/nutrition/data/catalog_search_service.dart`、`test/perf/catalog_real_scale_test.dart`、2.0-1h。

## ADR-017：搜索排序改成「匹配层 + bm25」，末层再拆出「名称包含」层

- Date: 2026-09-16
- Status: accepted
- Context: docs/07 §9.3 定的是搜索优先级「精确 canonical 名称 > 用户常用别名 > 中文前缀 > 拼音/英文别名 > 品牌和分类」，但 2.0-1h 的实现是**纯 bm25**（FTS 先按 bm25 取 id）。真数据上 bm25 会给出规范明确否定的顺序：品牌为「牛奶」的商品「香肠」排在中文前缀「牛奶巧克力」之前（夹具复现见 `test/features/nutrition/catalog_search_service_test.dart`）。另外 bm25 不区分「主名包含查询」与「只命中品牌/分类」，而规范末层只点名了「品牌和分类」。
- Decision: ①排序键改成 **(匹配层, bm25, id)**，同层内 bm25 越好越靠前，同层同分用 id 兜底（避免页缓存不同导致顺序漂移）。②每个分片取**两批**候选：分层探测 `{text} : "…" *`（只在主名/别名那一列找连续命中，`*` 必须写在引号外——写进引号里 FTS5 会当普通字符，实测 0 命中）与原来的 token 窗口；按 id 合并时保留更好的一层与更好的 bm25，再排序切片。③层序 `exactName > exactAlias > namePrefix > nameToken > aliasPrefix > brandCategory`：规范点名的五个层相对顺序不变，规范没点名的「主名/别名包含查询但不是前缀」单列为 `nameToken`，插在 `namePrefix` 之后、`aliasPrefix` 之前（名称命中优先于别名命中，别名优先于只命中品牌/分类）。④单批候选 `LIMIT = (page+1)*pageSize + 2*pageSize`，每分片硬上限 1000；分页由「每片窗口 → 合并 → 排序 → 切片」保证，不再把 OFFSET 下推到 SQL。
- Alternatives: ①严格只按规范五层，把「名称包含」并进末层——被否，实测会让「香草牛奶」与「XX 牌牛奶」同层，先后交给 bm25 的算术（同分按 id），产品上说不通。②只扩大 bm25 窗口、不做分层探测——被否，单分片实测 `milk` 命中 490 条、名称前缀候选 69 条，其中 22 条落在 bm25 top-150 之外，纯窗口会把「Milk …」这类前缀名压到品牌命中后面。③把拼音/英文别名提到中文前缀之前——被否，规范原文顺序如此，不因个例调整。
- Consequences: 真分片（10 万条 / 5 分片）42 次查询 P50 20.3 ms / P95 **31.5 ms**（分层前 18.5~20.4 / 27.6~42.1，同一量级），距 200 ms 门槛仍有 6 倍余量；代价是每次搜索多一次 FTS 查询，每分片 warm 约 +1 ms。中文查询实测命中很窄（`牛奶` 24 条、`鸡` 15 条、`面包` 7 条，且都落在首个分片），拉丁宽查询才是分层真正起作用的地方（`milk` 首屏从混合命中变成 12 条精确 `Milk` + 38 条 `Milk …` 前缀）。边界：单分片命中超过 1000 条的极宽查询，窗口外的行不参与分层。层名不进 UI（页面仍只显示数据状态），它只在服务层决定顺序；用户主库的自建条目与别名仍由 `FoodLibraryController` 整体排在目录结果之前，对应规范里的「用户常用别名」。
- Affected: `lib/features/nutrition/data/catalog_search_service.dart`、`test/features/nutrition/catalog_search_service_test.dart`、`test/perf/catalog_real_scale_test.dart`、2.0-1j。

## ADR-018：分片一律用独立只读连接读，主库连接上不 ATTACH

- Date: 2026-09-16
- Status: accepted
- Context: 2.0-1i 的导入器把分片 `ATTACH` 到主库连接上，再把 `shard_src.foods` 拷进主库内的一张 staging 表。单元测试全绿（测试用 `NativeDatabase.memory()`，主库和分片都是明文 SQLite），但 2026-09-16 在 API 35 模拟器上首装即失败：主库是 **SQLCipher 加密库**，`ATTACH` 会把主库的密钥作用到被附着的库上，而分片是 ETL（Python 标准 sqlite3）产出的明文库——`sqlcipher: error decrypting page 1 data` + `SqliteException(26): file is not a database`。失败的还是启动路径：`CatalogBootstrap.importAvailable()` 只捕获 `CatalogImportException`，驱动异常直接变成 unhandled exception，界面上什么都不显示，目录静默为空（随包 21,266,432 B 的 core 分片已正确落盘，却一条也没进主库）。
- Decision: ①分片读取改用**独立连接**（`openCatalogShardReadOnly` → `sqlite3.open(path, mode: OpenMode.readOnly)`），与搜索层 `CatalogSearchService` 取分片 FTS 的做法统一；导入器里不再出现任何 `ATTACH`/`DETACH`，主库连接只写主库。②随之删掉 staging 表：它的唯一存在理由就是承接跨库 `INSERT … SELECT`；分片行本来就整批读进 Dart 内存（`_ShardRecord` 列表），staging 只是把同一批数据再往加密库里抄一遍，还留下「进程被杀就残留 staging 大表」和磁盘余量按 ×3 估算的尾巴。③分片读不出来（损坏/不是 SQLite）归入新类别 `CatalogImportFailureKind.unreadableShard`，而不是把 `SqliteException` 漏给调用方。④`CatalogBootstrap` 的 `importAvailable()`/`prepare()` 补 catch-all：分类之外的异常也收成 `lastResult.failure`（消息带 `error.runtimeType`），启动路径不许上抛——这是它本来就写在文档里的承诺。
- Alternatives: ①保留 `ATTACH` 但显式 `KEY ''`（SQLCipher 用它声明「被附着的库是明文」）——被否：普通 SQLite（Windows/Linux 测试环境、桌面构建）不认这条语法，等于把加密库的方言写进可移植代码，而且仍然把分片路径暴露在主库连接上。②把主库密钥交给导入器、由分片连接反过来 ATTACH 加密主库——被否，密钥只应留在数据库层。③只加 catch-all 不做连接改造——被否，那只是把「导入失败但界面不说」变成「导入失败界面会说」，目录仍然是空的（真机首装拿不到任何食物）。
- Consequences: 真机首装导入可用（设备复验见 `docs/evidence/2026-09-16-2.0-1k-device-import-fix.md`）；主库连接不再承载分片路径，导入器不再有跨库 SQL，代码少了一个 DDL 生命周期（`_stageShard`/`_dropStaging`/`staging_catalog_%` 全部消失，相关测试断言改为「导入后主库仍是 `['main']` 一个库」）。代价：同一个分片的行现在只存在于 Dart 内存里一份，峰值内存与改造前相同（改造前也要整批读回 `_ShardRecord`），但少了加密库里的临时副本，导入路径的磁盘瞬时占用更低。**教训**：单元测试的主库是明文 SQLite，凡是「主库连接上做与加密相关的事」都不会在 `flutter test` 里暴露——分片/加密交互必须上真机走查。
- Affected: `lib/features/nutrition/data/catalog_shard_importer.dart`、`lib/features/nutrition/data/catalog_bootstrap.dart`、`test/features/nutrition/catalog_shard_importer_test.dart`、`test/features/nutrition/catalog_bootstrap_test.dart`、2.0-1k。

## ADR-019：SQLCipher 库解析覆盖在主 isolate 也要装一次

- Date: 2026-09-16
- Status: accepted
- Context: 修掉 ADR-018 的 `ATTACH` 之后，真机首装导入**仍然**失败，但这次被 `importAvailable` 的 catch-all 写进了设置页：「目录导入遇到意外错误（**ArgumentError**）」。`ArgumentError` 不是 sqlite 错误而是库加载错误：`package:sqlite3` 在 Android 上的默认解析是 `DynamicLibrary.open('libsqlite3.so')`（系统里没有），应用只在**后台数据库 isolate** 里装了覆盖（`NativeDatabase.createInBackground(..., isolateSetup: _configureSqlCipher)`）。而主 isolate 里有三处裸 `sqlite3.open`：`CatalogSearchService`（分片 FTS 搜索）、`CatalogShardImporter`（分片导入）、`CatalogShardDetailSource`（详情弹层读分片）——三条路在真机上全部打不开分片。
- Decision: 把 `_configureSqlCipher` 提为公开的 `configureSqlCipherLibrary()`（幂等，只登记 Android 的加载函数），在 `main()` 里 `WidgetsFlutterBinding.ensureInitialized()` 之后、任何 sqlite3 使用之前调用一次；后台 isolate 的 `isolateSetup` 保持调用同一函数。非 Android 平台不受影响（覆盖按 OS 键登记，桌面继续走默认解析）。并用一个源码级测试钉住顺序：`main.dart` 里 `configureSqlCipherLibrary();` 必须在 `AppDatabase.open` 之前。
- Alternatives: ①在每个使用点各自 `DynamicLibrary.open('libsqlcipher.so')`——被否，等于把库名与加载细节散到三处业务代码里，桌面/测试环境还会因此走不到默认解析。②让 `CatalogBootstrap` 只在 Android 上跑、其他平台禁用分片读——被否，这不是平台差异而是启动接线缺失，禁用会把「桌面能用、真机不能用」的掩盖当作修复。③把三个使用点都改成走后台 isolate——被否，搜索是 UI 热路径（每次输入都要读分片 FTS），为了库加载再开 isolate 是过度设计。
- Consequences: 真机上分片搜索/导入/详情三条路都能读分片（设备复验：`milk` 搜索出现来源徽标「目录」的分片命中，导入 20,000 条成功，见 `docs/evidence/2026-09-16-2.0-1k-device-import-fix.md`）。代价：启动路径多一次 `open.overrideFor`（纯登记，无 IO）；副作用是任何**将来**在主 isolate 新增的 `sqlite3.open` 也自动拿到正确的库——这既是好处也是隐患：它让「忘了装覆盖」这类错误从「第一次运行就炸」变成「不会炸」，所以真正的护栏是源码级顺序测试 + 真机走查，而不是靠报错提醒。
- Affected: `lib/main.dart`、`lib/data/database/app_database.dart`、`test/data/database/sqlcipher_library_binding_test.dart`、2.0-1k。

## ADR-020：≥10,000 中文基础食物在可再分发前提下不可得，且随包 CFCT 种子违反 §5.3

- Date: 2026-09-16
- Status: accepted
- Context: 规范 §5.2 A 层写「≥10,000；中文基础食材、熟制食品、校园高频菜」，而 2.0-1j 的发布目录 10 万条里中文名只有 **1,932 条**（1.93%；实测其中同时带中文品牌的仅 **823 条**，见 `docs/evidence/2026-09-16-2.0-1l-chinese-food-source-license-investigation.md` §3），并且 `category` 是 OFF 的原始多语言品类文本（法语最多、7.76% 为空），**无法**据它声称「≥10,000 条常见基础食物」。2.0-1l 逐条查证了候选来源：①CFCT 镜像 `Sanotsu/china-food-composition-data` **没有 LICENSE 文件**，README 只写「所有版权都归原作者所有，脚本仅用于个人学习研究」，无 wiki、四个 issue 无任何授权答复；②官方口径都**不发布**许可——国家食品安全风险评估中心站点根本没有食物成分栏目、无使用条款，页脚只有「版权所有」；真正的查询平台在中国疾控中心营养与健康所（`nlc.chinanutri.cn`），同样只有「版权所有」；③唯一拿到**明确许可**的是 USDA FoodData Central（官方 API 指南原文「in the public domain and they are not copyrighted」「published under CC0 1.0 Universal (CC0 1.0)」「No permission is needed for their use」，FAQ 把「商业营养分析软件」列为认可用法），但它是**英文**成分库，对中文名覆盖没有直接帮助；④**没有**找到任何 CC0/PD/CC-BY 的中文成分表（同类数据集全是无许可的 CFCT 转载）；台湾 OGDL 1.0 只验证了**许可证文本**，对应数据集因域名 DNS 不通而**未验证**。带清晰许可且含中文条目的现成来源只有 foodwake（Apache-2.0，去重后约 830 条，已随包）与 OFF（ODbL，1,932 条，已在发布目录）——两个都远不够。
- Decision: ①**判定为「不可得」**（三种结论里的第三种）：可再分发前提下不存在能提供 ≥10,000 条中文基础食物的数据源，这不是工程量问题而是授权问题；规范 §5.2 A 层的「中文基础食材」半句**当前无法达成**，在 `STATUS.md`/`docs/09` 记为**已知边界 + 需权利人授权的开放项**，并注明它阻塞的是「A 层数字」而不是产品可用性（首装后 OFF 目录已提供 1,932 条中文名可搜可算）。②**不硬凑数字**：不把 823/1,932 说成达标，也**不把英文名机器翻译成中文充数**——错误食材名会直接污染 `MenuItemMatcher` 的 top-K 建议（那是用户确认菜单匹配的唯一依据）。③把调查暴露出的更硬问题写成**在包违规记录**：docs/07 §5.3 明文「**不清楚是否允许再分发的源不进入发布包**」，而随包的 `assets/seed/foods.v3.json` 里就有约 1,634 条 CFCT 来源条目， 末条本来就要求「发布前生成第三方许可清单**和删除/替换来源的脚本**」，那个脚本还没写。④两条出路**只记录不代做**：A 取得权利人（人民卫生出版社/官方机构）许可＝需人工对外联络，超出代理边界；B 按 §5.3 写「删除/替换来源」脚本（剔除 CFCT 条目，只留 Apache-2.0 的 foodwake 子集）＝代理可实现，但会让随包中文条目从 2,464 降到约 830，属**产品取舍**，需用户裁定。推荐 **B 先做（合规优先、不阻塞上架）、A 并行尝试**（拿到许可后作为独立数据源切片把 CFCT 条目加回）。⑤许可证白名单判据沿用 §5.3：只有 CC0/PD/CC-BY/ODbL 这类**明确许可**才能进 `allowedCatalogLicenses`，「仅供学习研究」永不入选。
- Alternatives: ①英文名机器翻译成中文把中文名刷到 10,000——被否，制造错误食材名、污染菜单匹配，且是对数据来源的伪造。②先把 CFCT 留在包里「等拿到许可再处理」——被否，§5.3 是硬规则，等价于明知违规发货。③现在直接删 CFCT 条目不问——被否，改发布内容是产品取舍（首装中文覆盖下降），且若 A 路成功则删除是白做。④改去用台湾 OGDL 数据集——**未决而非否决**：许可证文本已确认可商用可再分发（要求显名），但本机 DNS 不通，没有验证到「台湾食品营养成分资料库在该许可下发布」，列为下一个可查方向。
- Consequences: 2.0-1 的最后一个缺口从「待补数据」变成**一条授权结论 + 一条在包违规**：前者结案（不可得，不再花人力找源），后者仍是上架阻塞项且现在有了明确的执行路径（§5 表格两条路）。正面：不再有「中文条目凑数」的诱惑，也不会把翻译名塞进搜索与菜单匹配；随包数据的合法性有据可依。代价：中文覆盖停在 1,932（随包种子侧可能降到约 830），校园高频菜名匹配主要靠 OFF 的中文商品名 + 用户自建条目。边界：许可结论是**时点快照**（2026-09-16 读到的公开页面，上游可随时改条款）；本机 Web 搜索能力受限（必应重定向、DuckDuckGo/Mojeek/Brave/Yahoo/searx 全超时、GitHub 搜索页超时），所以「没有找到 CC0 中文表」是**可达来源内的否定结论**，不等于穷尽全网；USDA 的「可商用可再分发」是从 CC0/公有领域**推得**（Licensing 段无逐字字样）；本文件是来源摘录与推断，不是法律意见。
- Affected: `docs/evidence/2026-09-16-2.0-1l-chinese-food-source-license-investigation.md`、`docs/THIRD_PARTY_LICENSES.md`、`tool/food_seed/README.md`（来源表与风险列）、`assets/seed/foods.v3.json`（**本次未改**，待裁定）、`STATUS.md`、`docs/09-release-and-device-checklist.md`、2.0-1l。

### ADR-020 补记（2026-09-16，用户裁定）

- **用户决定：LocalFit AI 为个人自用，不做商业化、不上架分发。** 因此随包 CFCT 条目**保留**：
  §5.3 的「不清楚是否允许再分发的源不进入发布包」是为**对外分发**设的门槛，自用场景下
  不构成阻塞，**不改 `assets/seed/foods.v3.json`**（保持 2,464 条 / sha256 `f406c329…`）。
- **但 §5.3 的「删除/替换来源的脚本」仍然落地**（`tool/food_seed/strip_seed_source.py`
  + `tool/food_seed/test_strip_seed.py`，26 项检查）。理由不是合规姿态，而是**让这个决定可逆**：
  将来一旦要分发（或想换掉该来源），「剔除 1,634 条 CFCT 条目」应该是一条命令而不是一次
  高风险的手工编辑——项目没有 Git 元数据，手工编辑 JSON 改坏了没有第二份可回退。脚本因此
  自带走查纪律：按 id 前缀精确剥离、`--in-place` 先写 `.bak` 且拒绝覆盖已有备份、剥离后为空
  报错、已声明来源被删过时幂等退出 0、清单外前缀判为打错字退出 1。
  `test/privacy/privacy_statement_audit_test.dart` 里加了一条静态审计钉住「脚本存在 + 它的
  来源清单与真实种子的前缀集合相等」（两条断言都做过实跑红证：删掉脚本 → 红；把 `seed-fw-`
  从清单里去掉 → 红，扰动已还原）。
- **风险登记的措辞随之改变**：`STATUS.md` 与 `docs/09` 里这条从「在包违规 / 上架阻塞项」
  改为「**仅商店分发前置条件**」——自用构建不是违规；但**一旦要对外分发，它立刻变回阻塞项**，
  且届时优先做的不是删数据而是先走 A 路（取得权利人许可）。
- Consequences: 自用构建可以按现状继续（随包 2,464 条中文基础食物全在，中文覆盖比剥离后好
  得多：2,464 → 830 的差距是实打实的可用性差异）；代价是这份数据未来若要分发必须先解决授权，
  而解决路径已经写清楚且有工具兜底。**不改变的**：ADR-020 前半段的结论仍然成立——「≥10,000
  条中文基础食物」在**可再分发**前提下不可得，所以任何分发计划都不能指望补数据解决，只能
  要么取得 CFCT 授权、要么接受约 830 条的随包中文覆盖。
- Affected: `tool/food_seed/strip_seed_source.py`（新增）、`tool/food_seed/test_strip_seed.py`（新增）、
  `test/privacy/privacy_statement_audit_test.dart`（+1 断言）、`docs/THIRD_PARTY_LICENSES.md`、
  `docs/09-release-and-device-checklist.md`、`STATUS.md`、2.0-1l。

## ADR-021：UI 全量升级采用「薄荷奶油 2.0」设计语言

- Date: 2026-09-17
- Status: **superseded by ADR-023**（2026-09-27：该设计语言作废）→ **ADR-024**（2026-09-28：其规范已从仓库删除）。注意：其**实现的组件与 token 仍在代码中**，将由 `docs/22` 阶段 I 收口清理
- Context: 用户要求参考成熟 App 对所有界面的布局、动画、图画、色彩、主题、形状、图案和全部可交互控件做全面升级。既有方案 A 已是代码基线（2.0-6 已交付全部功能 UI），推翻重来会丢失已验收的识别度并制造两套视觉语言。
- Decision: 以方案 A 为品牌 DNA，吸收 Material 3 Expressive（弹簧动效 token、形状变形、tonal ramp、bento 布局）、Apple HIG/Liquid Glass（三层纵深、浮岛底栏局部毛玻璃）、小红书（双列内容流、生成式封面）、Keep/Apple Fitness+（训练深色沉浸、庆祝时刻、大号 tabular 数字）。完整规格见当时的 UI 2.0 升级规范（已删除），分 UI-A~UI-E 五个批次交付；营养三色编码、确认边界、隐私与事实分层不随视觉升级改变。
- Alternatives: 换全新设计语言；拒绝，因为需重做全部页面且违反「2.0 UI 是增量」的既定决策（ADR-008）。只做局部换肤；拒绝，因为用户明确要求全量升级，局部修补无法形成一致的动效/形状/图案语言。
- Consequences: presentation 层需要 token 三层化（primitive/semantic/component）与 ThemeExtension 化；动效从时长+曲线升级为弹簧参数并引入触觉与庆祝粒子（`CustomPainter` 自绘，零新增依赖）；高对比与 Material You 动态取色作为可选档。实施顺序由 `STATUS.md` 决定。
- Affected: 当时的 UI 2.0 升级规范（已删除）、`lib/app/design/**`、全部 presentation 层、UI-A~UI-E。

## ADR-022：动作难度/常用度存可空列且读数不抛错；弹层外壳不管滚动

- Date: 2026-09-23
- Status: accepted
- Context: 当时的 UI 重设计文档要求动作库展示「难度、常用度」，但这两项在既有 `Exercises` 表里不存在。同时要决定三件事：①新列可不可空；②难度用什么类型存；③`AppSheet.show` 遇到超长内容（新增的帮助文档问答列表）溢出 69px，怎么修。
- Decision: ①`difficulty` / `popularity` **均可空**，读取侧用**不抛错**的 `ExerciseDifficulty.fromStoredValue`，null 显示「难度未知」——与 `MuscleGroup` 的抛错策略**刻意不同**：「未标注」是历史行的合法状态，抛错会把整份旧库存变成打不开的库，而 `MuscleGroup` 缺失才是真脏数据。**绝不拿默认值冒充已标注事实。** ②难度存**枚举名字符串**而不是 `index`：索引会随枚举增删被静默重解释成另一个难度（加一个「专家」枚举值，历史「高级」就变成别的）。③弹层外壳 `_AppSheetBody` **不**给内容套 `Flexible + SingleChildScrollView`，职责收窄为「标题/内容/按钮」三段；需要滚动的调用方自己 `ConstrainedBox(maxHeight) + SingleChildScrollView`。
- Alternatives: ①新列给非空默认值（如 `'beginner'` / `0`）——被否，等于给全部历史动作伪造难度标注，违反「本地事实优先、不猜」的既定原则（ADR-002/004）。②难度存 `index`——被否，理由见上。③外壳统一套 `Flexible + 滚动`——**实测被否**：调用方（`training` 记录组弹层）自己已在滚动视图里，再插 `Flexible` 时父节点是 `_SingleChildViewport` 而不是 `Flex`，直接抛 `Incorrect use of ParentDataWidget`，打挂两个既有测试；`SingleChildScrollView` 也没有 `shrinkWrap` 参数可退让。④让外壳自动探测子节点是否可滚动——被否，脆弱且把布局决策藏进组件内部。
- Consequences: 正面：旧库升级不丢可读性（未标注如实显示）、枚举扩展不腐蚀历史数据、弹层外壳保持单一职责且不会因调用方形态不同而崩。代价：每个超长内容的调用点都要自己记得加滚动（用回归测试锁契约：短内容不被包滚动层 / 调用方自带滚动时不抛 `ParentDataWidget`）。边界：本轮**未**给难度/常用度提供编辑入口（只有种子与显示），用户自建动作一律写 null、显示「未知」——这是有意的（不猜），若后续要支持人工标注需另开切片。
- Affected: `lib/data/database/tables.dart`、`lib/data/database/app_database.dart`（schema v15→v16）、`lib/features/training/domain/exercise_record.dart`、`assets/seed/exercises.v2.json`、`lib/app/design/widgets/app_sheet.dart`、`lib/features/settings/presentation/settings_page.dart`、`test/app/design/app_sheet_form_test.dart`、`docs/evidence/2026-09-23-docs12-completion.md`、`STATUS.md`、docs12/refactor-completion-2。

## ADR-023：UI 唯一依据改为 `ui设计/pages/*.html`，旧 UI 规范全部作废

- Date: 2026-09-27
- Status: accepted
- Context: 用户在 `ui设计/pages/` 下交付了 7 个新视觉稿（今日 / 饮食·记录 / 饮食·菜单 / 拍照识餐 / 训练 / 我的 / AI 工作），并要求「所有功能和交互都按新 UI 设计来，如果冲突的话，抛弃所有旧的设定和功能」。此前的实现基线是 ADR-021 的「薄荷奶油 2.0」，与设计稿是**两套不同的视觉语言**（背景色、边框、圆角体系、底栏形态、圆环形状、页面结构均不同）。此外，早前一份已删除的迁移方案文档声称「阶段 0~6 已交付」，但那些证据只验证了 Key 存在与数据驱动，**从未做过截图与设计稿的对比**（该文档自己也写明不能据此宣称完成）。
- Decision: ①**视觉与交互的唯一依据是 `ui设计/pages/*.html`**；规范译法落在新建的 `docs/21-ui-redesign-spec.md`，与任何旧文档冲突时以它为准。②共 8 份旧 UI 文档（旧规范 2 份 + 旧细化/重设计/完整规范 3 份 + 旧设计系统 1 份 + 旧迁移方案 1 份 + 改名前遗留 1 份）**全部停止生效**（先归档，随后于 2026-09-28 按 ADR-024 删除）；`lib/` 与 `test/` 内约 304 处引用按章节语义改指 `docs/21`。③**区分「冲突」与「设计稿未画到」**：冲突按设计稿做（抛弃旧设定，不留兼容层）；设计稿未画到的功能**保留数据与逻辑**，UI 上收进二级入口（已裁决）。④底栏中间槽由「拍照」改为「AI 对话」（设计稿 `nav-key="ai"`），拍照识餐改为推入式二级页。⑤「我的」页的「数据同步」开关降级为「自动本地备份」，不破「全数据本地」硬约束。⑥新增数据域（饮水 / 体成分 / 成就 / 菜品库 / 心血管处方 / 识别结果 / 聊天记录 / 应用设置）全部落地，schema 16→17。⑦**步数保持「暂无记录」**，不引计步插件与设备权限。⑧语音输入完整实现（录音 + BYOK 端点转写），需新增麦克风权限并同步 `docs/08` 权限表。
- Alternatives: ①就地修补现有页面（保留 2.0 视觉，只调颜色）——被否，差异是结构级的（半圆环→全圆环、Bento→白卡、悬浮胶囊→贴底栏），就地改等于每个 widget 重写两遍。②新建平行目录、完成后切换——被否，会产生两套设计系统共存期，切换时仍需一次性改写大量测试。③**归档而非删除**——本轮采用（保留审计痕迹），随后被 ADR-024 推翻：归档仍让旧规范留在仓库内可被读取。④删除 HTML 未画到的旧功能——被否（用户裁决为「保留数据与逻辑，收进二级入口」）。
- Consequences: 正面：视觉依据唯一且可截图验证、旧文档冲突彻底消除、数据与业务逻辑约 85% 可复用、114 个纯行为测试文件（694 用例）基本不动。代价：95 个含 widget 的测试文件（456 `testWidgets` + 313 个 Key 字面量）需按新设计改写；`lib/app/design/` 的 token 需大面积重新灌注（仅品牌锚点与五个数据色逐字节一致，mint ramp 其余 9 档、整套中性色、四个状态色、hero 渐变中末段均需修改）；`BentoCell` / `AppCoverPattern` / `MacroPill` 三个组件废弃。风险最高项是 schema 16→17 迁移，对策是「只增不改不删 + 专门的迁移测试 + 备份表注册表同步」。改造策略与阶段编排见 `docs/22-ui-redesign-refactor-plan.md`。
- Affected: `docs/21-ui-redesign-spec.md`、`docs/22-ui-redesign-refactor-plan.md`、`docs/02-architecture.md`、`docs/06-token-efficient-development.md`、`docs/07-localfit-2.0-development-spec.md`、`docs/08-store-privacy-and-permissions.md`（待改权限表）、`README.md`、`lib/**`、`test/**`。

## ADR-024：旧 UI 文档从仓库物理删除，不再保留归档目录

- Date: 2026-09-28
- Status: accepted
- Context: ADR-023 把 8 份旧 UI 文档移入仓库内的 `docs/archive/`。用户随后要求「保证所有地方不要出现旧文档的引用，最好把旧文档直接删掉」。归档方案有两个保留问题：①旧规范仍在仓库内可被读取，新会话读文档时可能仍按其执行；②`docs/archive/` 的字面路径以及旧文件名持续出现在 README、索引、证据与注释里，形成**指向已失效内容的活引用**。
- Decision: ①**物理删除** 8 份旧 UI 文档与 `docs/archive/` 目录，并删除已空的 `docs/development/`。②删除前**按 sha256 逐文件校验备份到仓库外**（`E:\AI\Zcode\backups\localfit-old-ui-docs-2026-09-28\`）——本仓库无 Git 元数据，物理删除不可恢复，备份是唯一回退路径。③**全仓引用清零**：治理文档（README、GOAL、`docs/01`~`docs/09`、`docs/21`、`docs/22`、`docs/DECISIONS.md`、状态文件活段）、历史记录（`docs/evidence/`、`docs/history/`、状态文件历史段）与配置注释中的旧文件名/旧编号一律改为中性描述（如「已删除的旧 UI 规范」）或删除该引用，**不保留任何可点击/可解析的旧路径**。④记录本次删除的规范文本（ADR-023/024、`docs/22` §4）**有意不列出旧文件名与路径**，只按类别描述——列出即等于留下新引用。⑤`docs/11-code-review-and-bug-hunt-plan.md` 与 `docs/06-token-efficient-development.md` 保留：它们是非 UI 文档，其编号引用（`§3-x`/`BUG-n`/`P2`/`P3`）与旧 UI 规范无关。
- Alternatives: ①继续用归档目录（ADR-023 原方案）——被否，旧规范仍可读，且归档路径本身是活引用。②删除但不备份——被否，仓库无 Git，误删即永久丢失，且无法核对删除内容。③连 `docs/11-code-review` 等非 UI 同号文档一起删——被否，它们被约 59 处代码注释引用，删除会破坏有效引用。④对历史证据文档做全文重写——被否，证据文档的审计价值在于如实记录当时依据；只把失效路径改为中性描述（并标注文档已删除），不改变其结论与数据。
- Consequences: 正面：仓库内不再存在旧视觉的可读来源与可解析引用，`docs/21` 成为唯一视觉依据；新会话不可能再据旧规范行事。代价：①历史证据文档中的引用被改为描述性文字，失去「点回原文」的能力（原文只在仓库外备份）；②若日后需要复核旧规范，必须去备份目录，不在仓库内。风险：机械替换可能把中性描述改得语句不通——已按「先长后短、边界断言、dry-run 逐文件核对」执行，并复查治理文档的措辞。
- Affected: `README.md`、`GOAL.md`、`docs/**`（删除 `docs/archive/**`、`docs/development/`；修改 `docs/01`~`docs/09`、`docs/21`、`docs/22`、`docs/DECISIONS.md`、`docs/evidence/**`、`docs/history/**`）、`pubspec.yaml`（注释）、`design/logo/preview.html`、`STATUS.md`、`E:\AI\Zcode\backups\localfit-old-ui-docs-2026-09-28\`（仓库外备份）。

## ADR-025：食物库整体替换为 FoodCalu 中文库（49,464 条），旧种子与随包分片全部下线

- Date: 2026-10-02
- Status: accepted
- Context: ADR-020 判定「可再分发前提下 ≥10,000 条中文基础食物不可得」，当时随包中文只有 2,464 条（CFCT 1,634 + foodwake 830），另需用户按需导入 OFF 分片才有 1,932 条中文名。用户随后给出两个参考项目（`maksimowiczm/FoodYou`、`gaosheng293/FoodCalu`）并要求「现在的食物库都去除掉」改用它们的数据，且明确「数据不是中文的话自行翻译」。调查结论：FoodYou 本体不带离线食物库——食物来自运行时的 Open Food Facts 与 USDA FoodData Central（USDA 需用户自备 API Key），唯一可随包的 Swiss 通用库（1,191 条欧洲食品、瑞士联邦版权）对中文饮食记录价值有限且需约 1.2k 条人工翻译；FoodCalu 随包一个 `food_database.db`（SQLite，49,520 条，含 id/name/热量/蛋白/脂肪/碳水，均为每 100g 值），可离线、可随包。两边的食物数据都**没有**可随包的明确许可证（FoodYou 的 OFF 是 ODbL 运行时数据；FoodCalu 仓库无 LICENSE）。
- Decision: ①**整体替换随包食物库**为 FoodCalu 派生的 `assets/seed/foods.v4.json`（49,464 条：源 49,520 − 归一化去重 54 − 物理不可能值 2），`FoodSeedImporter` 改为 v4 单一来源（`source='seed-v4'`），导入前清理老库里的 `seed-v1/v2/v3` 行（**只删未被食谱/餐次/菜单匹配/库存/价格事实引用的行**，用户自建行永不触碰）。②上游 **430 条名称不含汉字**（英文/日文/品牌）逐条人工翻译，词表 `tool/food_seed/raw/foodcalu/name_zh.tsv` 由构建脚本强制覆盖（缺译名即报错退出），随包条目 100% 含汉字。**并折叠重复品牌块**（1,234 行把同一品牌写了两三遍，如 `Kelsen凯尔森 Kelsen 凯尔森 黄油曲奇饼干`；规则只删重复不译品牌，折叠后仍断言每条含汉字），这一步还暴露出 4 行原本只差品牌重复的真重复条目。③饮食标签/过敏原由**名称启发式**保守推断（复合制品不声明属性；`unknown ⇒ 无标签无过敏原`），并加入撞车黑名单（「贝」不认——贝果/巴黎贝甜/贝壳面；「螺旋/螺丝/陀螺面」不是螺；「金龙鱼」是粮油品牌；「鱼腥草」是植物；「蟹味菇」是菌菇；「肉桂/果肉」不是肉；「蛋白粉/棒/肽」是补充剂；「奶白菜」是菜）。④**旧库下线**：`foods.v1/v2/v3.json`、`assets/catalog/` 的 manifest 与 5 个分片、旧生成脚本 `generate_seed.py` 与其原始输入（`raw/cfct.csv`、`raw/foodwake.json`）全部从仓库删除，备份到 `E:/AI/Zcode/backups/localfit-old-food-library-2026-10-02/`（含 `_SHA256SUMS.txt`）；pubspec 不再声明任何 `assets/catalog/**`。⑤**目录（catalog）机制保留但不随包**：它要求来源有清单白名单内的许可证，无许可的 FoodCalu 进不去这条通道，因此中文基础食物只走随包种子层；用户要 OFF 数据可把分片放进支持目录后「重新扫描本地分片」。⑥合规口径沿用 ADR-020 并**收紧到单一来源**：FoodCalu 无许可证 ⇒ 只适用「个人自用、不再分发」；一旦对外分发就变回阻塞项，届时按 `docs/THIRD_PARTY_LICENSES.md` §4.1 走 A（取得作者许可）或 B（`strip_seed_source.py` 换源；注意 v4 是单一来源，剥完为空会被脚本拒绝，必须先备好替代源）。
- Alternatives: ①直接用 FoodYou 的数据——被否，它没有可随包的离线中文库（OFF 已是现有按需通道、USDA 需用户 API Key、Swiss 库是欧洲食品且需大量人工翻译）。②保留 CFCT/foodwake 并叠加 FoodCalu——被否，用户明确要求「都去除掉」，且叠加会让同义食物大量重复（实测与 CFCT 重叠的主食条目里 183/1044 条热量差异 >15%）。③把 FoodCalu 塞进 catalog 分片通道——**不可行**：目录 manifest 的许可证白名单是冻结的（`odbl/cc0/cc-by/cc-by-sa/public-domain`），无许可来源进不去。④用机器翻译补 430 条非中文名——被否（沿用 ADR-020 的判断）：错误食材名会污染菜单匹配的 top-K 建议，故逐条人工译并写死词表。⑤对源数据的 0 kcal 行按 Atwater 4-4-9 补热量——被否，源里 206 条 0 kcal 的是纤维素/糖醇类（魔芋果冻、零卡调味），强补热量反而是错的；只丢弃 2 条物理不可能行（蛋白 202 g/100g、碳水 228.7 g/100g）。⑥随包保留 OFF core 分片——被否，中文基础食物已由随包种子解决，104MB 分片没有再随包的理由。
- Consequences: 正面：装完即得 49,464 条**中文**食物，不再依赖用户按需导入；包体减去约 104MB 分片资产；来源清单从两条随包来源收敛为一条，合规审查面更小。代价与已知边界：①过敏原/饮食标签是名称启发式，会有漏标与多标（如「年糕」按米处理、「墨鱼汁意面」标成 fish 而非 shellfish），界面与文档都必须说明这是推断而不是标签事实；②水/盐/茶等 0 kcal 条目保持原样，不做修正；③首启导入 49,464 行的耗时需在真机实测（`FoodSeedImporter` 在 `runApp` 之前 await）；④清理只在启动时跑一次，若用户库中残留的老行被引用则按设计保留（`meal_items.food_name_snapshot` 保证历史餐食显示不变）。测试口径：门禁 1553 passed / 3 skipped（原 1552/2；新增 seed 清理与「全部条目含汉字」断言，1 个随包分片实测因不再随包而如实跳过）。
- Affected: `assets/seed/foods.v4.json`（新）、`assets/seed/foods.v1/v2/v3.json`（删）、`assets/catalog/**`（删）、`tool/food_seed/build_foodcalu.py`（新）、`tool/food_seed/raw/foodcalu/**`（新）、`tool/food_seed/generate_seed.py` 与 `raw/cfct.csv`/`raw/foodwake.json`（删）、`tool/food_seed/strip_seed_source.py`、`tool/food_seed/test_strip_seed.py`、`lib/features/nutrition/data/food_seed_importer.dart`、`lib/features/nutrition/domain/data_attribution.dart`、`pubspec.yaml`、`test/features/nutrition/food_seed_importer_test.dart`、`test/privacy/privacy_statement_audit_test.dart`、`test/features/settings/settings_page_test.dart`、`tool/food_seed/README.md`、`docs/THIRD_PARTY_LICENSES.md`、`docs/07-localfit-2.0-development-spec.md` §5.2/§5.3/§5.6、`docs/evidence/2026-10-02-food-library-foodcalu.md`、`STATUS.md`、`E:\AI\Zcode\backups\localfit-old-food-library-2026-10-02\`（仓库外备份）。

## ADR-026：食谱 / 周计划 / 食谱计划整族下线（schema 18→19，5 张表 DROP）

- Date: 2026-10-04
- Status: accepted
- Context: 用户裁决 D3 / N4（记录在 `docs/28-input-menu-foodlib-redesign-plan.md` §6）判定「本周计划和食谱计划彻底不要了，没啥用」、「把食谱和计划界面删掉」，并要求相关数据与 AI 侧一并删除（不是只删界面）。既有实现里这套功能横跨三个 feature 目录（`lib/features/recipes/` 6 文件、`lib/features/meal_plans/` 7 文件、`lib/features/recipe_planning/` 17 文件）、数据库三张核心表、6 条对话命令，以及为一个 AI 合同（`recipe-plan.v1`）和若干界面入口提供支撑。复核时另发现两张由 v6 加进来、只为「生成食谱计划时算预算 / 算冰箱存量」服务的表（`food_price_facts`、`pantry_stocks`）在 `recipe_planning/` 删除后会变成「界面无入口、只有 AI 命令能写」的孤儿数据（其唯一 UI 入口 `planning_facts_editor_dialog.dart` 随目录一起消失）。
- Decision: ①**整族下线**：删除上述三个 feature 目录与 `lib/features/ai_workbench/application/recipe_plan_workbench_task.dart`，AI 合同 `recipe-plan.v1` 与其工作台任务一并删除。②**数据库 DROP 五张表**——用户点名的 `recipes` / `recipe_items` / `meal_plan_entries`，加上一并下线的孤儿表 `food_price_facts` / `pantry_stocks`；`schemaVersion` 18 → **19**，迁移块放迁移链**最末**、用 `DROP TABLE IF EXISTS`、且**子表在前**（`recipe_items` → `meal_plan_entries` → `recipes`）。备份表清单 `backup_table_registry.dart` 由 **44 张 → 39 张**。`profiles` 上的四个 `planningBudget*` 列**保留**（SQLite 删列要整表重建，风险与收益不成比例；留作不可见的空列，**不是**被删除）。③**10 条对话命令退役**：`recipe.create` / `recipe.update` / `recipe.delete` / `plan.create` / `plan.update` / `plan.delete` / `pantry.set` / `pantry.clear` / `price.set` / `planning.preferences.set`（命令注册表 33 → **23** 条，见 `docs/23`）。④**营养页 sub-tab 5 → 3**（记录 / 菜单 / 食物库），删 `NutritionTabs.planIndex` / `recipeIndex` 与 `nutrition-tab-plan` / `nutrition-tab-recipe` 两个 Key。⑤今日页时间线的「计划态」、AI 工作台「生成食谱计划」入口、买菜清单入口、AI 快照里的「计划餐 / 库存 / 食谱」三段一并移除，**不做补偿入口**。⑥「常吃搭配」（meal-pairing）工作台任务**保留但降级为只读建议**：它不再有确认/写入步骤（其食谱写入目标已不存在）。⑦食物库 / 菜单 / 每日推荐（每日推荐）功能**全部保留**；`MealItems` 仍保存完整营养快照的规则**不变**。
- Alternatives: ①只删界面、保留数据表——被否（D9：「界面删了、只有 AI 能写」的孤儿数据没有价值，且三张表会与备份/迁移长期并存的死重）。②保留 `food_price_facts` / `pantry_stocks` 并给它们另找一个中立入口——被否，这两张表只被已删的食谱计划生成器消费，搬迁入口等于给一串没人用的数据续命；用户裁决口径是「相关的都删掉」。③直接删 `profiles.planningBudget*` 列——被否，SQLite 无 `DROP COLUMN` 时需要 drop + recreate + copy 整表重建，对一个不可见的空列不成比例。④把「常吃搭配」也一起删——被否，它功能是配餐建议（只因引用 `recipe_record.dart` 才与食谱有依赖），摘掉依赖后仍是有效能力。
- Consequences: ①**不可逆的数据丢失**：v18 → v19 第一次启动即 DROP，用户录过的食谱与计划数据**永久消失**（D9 的明确后果，不是意外）。②**备份三向行为**：新版备份（v19）不再含这五张表；**旧备份 → 新版应用不报错、静默丢弃**这五张表的数据（恢复遍历的是 registry，多出来的键被忽略）；**新版备份 → 旧版应用报错**「备份缺少数据表：recipes」（老版 registry 里它们非 `optional`，本应用不做降级，此向不兼容）。③正面：删掉三套 feature 与两套孤儿数据的维护面，AI 出口由 7 收敛为 6、对话命令由 33 收敛为 23，文档与代码重新对齐。④两条**实施偏差**（如实记录）：其一，`constraints.set` **未经退役**——它写的是 `profiles.allergenAvoidancesJson`，仍被每日推荐引擎读取，因此随仓储从 `recipe_planning/` 搬到 `daily_plan/` 保留（不在上述 10 条退役命令内）；其二，`nutrition_actions.dart` **文件保留**，只删除其中只服务被删功能的 `openRecipePlan` / `addRecipeToMeal` / `editRecipe` 三个方法（不整文件删除）。
- Affected: `lib/features/recipes/**`（删）、`lib/features/meal_plans/**`（删）、`lib/features/recipe_planning/**`（删）、`lib/features/ai_workbench/application/recipe_plan_workbench_task.dart`（删）、`lib/data/database/tables.dart`、`lib/data/database/app_database.dart`（schema v18→v19）、`lib/features/backup/application/backup_table_registry.dart`（44→39）、`lib/features/ai_conversation/domain/chat_edit/chat_edit_registry.dart`、`lib/features/ai_conversation/application/chat_edit_executor.dart`、`lib/features/ai_conversation/data/chat_edit_context_loader.dart`、`lib/features/nutrition/presentation/nutrition_legacy_tab_shell.dart`、`lib/features/nutrition/presentation/nutrition_page.dart`、`lib/features/nutrition/presentation/nutrition_actions.dart`（保留文件、删 3 方法）、`lib/features/dashboard/presentation/sections/dashboard_meal_timeline.dart`、`lib/main.dart`、`lib/app/app_router.dart`、`lib/app/localfit_app.dart`、`lib/features/nutrition/data/food_seed_importer.dart`、`test/features/recipes/**`（删）、`test/features/meal_plans/**`（删）、`test/features/recipe_planning/**`（删）、`test/features/ai_conversation/domain/chat_edit/chat_edit_registry_test.dart`、`test/features/backup/export_restore_test.dart`、`test/app/**`（迁移与索引断言）、`docs/21-ui-redesign-spec.md`、`docs/22-ui-redesign-refactor-plan.md`、`docs/23-chat-universal-edit.md`、`docs/24-ai-provider-protocols.md`、`docs/11-code-review-and-bug-hunt-plan.md`、`docs/26-ui-display-review-plan.md`、`docs/THIRD_PARTY_LICENSES.md`、`docs/28-input-menu-foodlib-redesign-plan.md` §6、`docs/evidence/2026-10-04-input-menu-foodlib-redesign.md`、`STATUS.md`。

## ADR-027：docs/29 UI/UX 修复计划（P0–P12）的应用级裁决收束

- Date: 2026-10-07
- Status: accepted
- Context: `docs/29-ui-ux-remediation-plan.md`（P0–P12，2026-10-05 起）共 12 包已全部交付。计划内部裁决（D1–D14 及各包 as-built）散落在 docs/29 §2 裁决表与各证据文件里；其中数条**改变了 ADR-026 时代的口径**或建立了跨包长期有效的接口约定，需要在 DECISIONS 层收束，避免后来者只看 ADR 不看计划书时用错口径。
- Decision: 收束以下五组为长期裁决（细节仍以 docs/29 §2 与各包证据为准）：①**设计稿先行**（D 系程序性约定延续 docs/29 既有做法）：后续视觉类工作包先出 HTML 设计稿放 `ui设计/remediation/`，经确认再落 Flutter；§5.1/§6.1/§6.2 已按 P9/P10/P11 as-built 补记。②**本机步数接线**（docs/29 D4/D5）：`ACTIVITY_RECOGNITION` 权限 + 首个 MethodChannel（`TYPE_STEP_COUNTER`），`StepsDaily` 表随 schema 19→20 迁移——**推翻** docs/21 §6.1/§6.2 #9「步数卡不引设备依赖、显示暂无记录」的旧裁决（该节已加日期注，不删原文）。③**拍照直通**（D12）：照片识别入口直通系统相机 Intent 并自动开始识别，**不声明 `CAMERA` 权限**（docs/08 §4 同步）；语音转写整族删除（D8/D9：删代码与 `record` 依赖及 `RECORD_AUDIO` 权限，保 `audioPath`/`durationMs` 数据列）。④**prompt 模板＝输出契约的唯一载体**（P11 真实端点实测确立，docs/evidence/2026-10-05-ai-live-endpoint.md）：wire 从不发送 `response_format`，五个工作台 prompt 模板必须逐一枚举全部键/类型/枚举（`promptVersion -2`），改模板必须重跑固定评测集 re-pin `_pinned` 哈希；workout-plan 首轮即通过未 bump（仍 `-1`）。⑤**chat-edit 协议硬化**（docs/23 §2 P11 注）：`renderProtocol()` 明确「edits 非空 / 用户已明确要求时不追问确认 / 先核对命令清单再回答」，decoder 契约不变（`maxEditsPerReply=10` 字面钉死）。
- Alternatives: ①每条裁决各立一个 ADR（14+ 条）——被否，docs/29 §2 已有逐条矛盾裁决表，DECISIONS 只收束「跨包长期有效、且与旧 ADR/常青文档冲突」的五组，避免重复维护两层。②只改 docs/21/§6 不立 ADR——被否，步数卡裁决的推翻与 prompt 契约是接口级约定，未来任何新会话都可能据旧 ADR/docs/21 口径做出错误实现。③把 P8b 食物库人工审核（D6/D7/D13，覆盖率对账 100%）也写入——不立新条，它延续 ADR-025 的库口径且已按包闭环（`reports/review_report.md`），ADR-025 不需修订。
- Consequences: 正面：常青文档（docs/21 §5.1/§6.1/§6.2、docs/24 §6/§7）与 docs/23/24 的 P 期补记有了 ADR 级锚点；「prompt 模板＝唯一契约载体」进入决策记录，后续任何 AI 出口改动都有可引用的裁决。代价：docs/21 §6.2 #9 的原裁决以删除线保留（历史可读但不可再引用为现状）；docs/24 §6/§7 以日期注标注陈旧段而非重写，读时须先看注。风险：本 ADR 是收束性条目，docs/29 §2 裁决表仍是逐条 first source——两者冲突时以 docs/29 as-built 证据为准并回改本表。
- Affected: `docs/21-ui-redesign-spec.md`（§5.1 P9 增补、§6.1/§6.2 #9 修订）、`docs/24-ai-provider-protocols.md`（§6/§7 日期注 + P11 补记）、`docs/23-chat-universal-edit.md`（§2 P11 注，P11 已记）、`docs/08-store-privacy-and-permissions.md`（P9/P10 已记，无改动）、`docs/29-ui-ux-remediation-plan.md`、`docs/evidence/2026-10-05-ai-live-endpoint.md`、`docs/evidence/2026-10-07-p12-global-wrapup.md`、`STATUS.md`。

## ADR-028：食物库 v5 定稿与 App 原地升级（P8b-2 完成，ADR-025 的后续）

- Date: 2026-10-07
- Status: accepted
- Context: ADR-025 把随包食物库整体换成 FoodCalu 派生的 49,464 条，并如实记下该库的两个已知缺陷：**没有品牌列**（上游 `food_database.db` 只有 name/四项营养），以及**名称里品牌与品名混在一起**（`Kelsen凯尔森 Kelsen 凯尔森 黄油曲奇饼干`）。docs/29 的诊断进一步点明：既有自动规则（`build_brand_gazetteer.py`，W3）**主动放弃纯汉字首 token**——按频率分不清「品牌」与「描述词」，因此 `明治`（品牌）与 `迷你`（尺寸词）在算法眼里同形，这条缺口**只有人工能关**（D6，用户 2026-10-05 裁定全量人工审核必做）。P8b-1 交付了审核台与账本（`tool/food_seed/review/`，账本 `reports/review_ledger.jsonl` 追加式、可重放），P8b-2 的出口条件是账本覆盖率 100%。本会话达成该条件并完成 v5 生成与 App 升级。
- Decision: ①**账本为唯一权威**：49,464 条逐条有人工裁决（逐条核验 18,920 + 族批确认 30,544，存疑 0），每条可点名到时间/前后值/来源；**报告不得把族批确认写成逐条核验**（`reports/review_report.md` 分列，不混称）。②**v5 定稿**：`assets/seed/foods.v5.json` = 49,444 条（审核删除 20 条），`version: 5`；生成器 `tool/food_seed/apply_review.py` 幂等（连跑两次逐字节相同），门控 `--require-coverage 100` **且 `pending == 0`**——判据用待审条数本身，**不用四舍五入后的百分比**（实测摘掉 1 条仍显示 100.0%，属真缺陷）。③**D13：两张词表分开存放**。自动表 `lib/utils/food_brands.g.dart`（2,650 token，**仍从 v5 按规则重算**，性质未变）与人工表 `lib/utils/food_brands_reviewed.g.dart`（3,897 token，含 `明治`/`桃李` 等**纯汉字**品牌）**不得合并成一个文件**——合并会毁掉「自动表可从种子重算」这条可核验性质。显示层取并集 `kFoodBrandTokensAll`。④**App 原地升级而非换 asset**：`seedSource='seed-v5'`、`legacySources=[seed-v1,seed-v2,seed-v3]`（清理）、`upgradeSource='seed-v4'`（**原地 UPDATE**）。`source='user'` 或 `isUserCreated` 的行**永不触碰**；v5 删掉的 id 若被 `meal_items.food_id` 或 `menu_item_food_matches.food_id` 引用则**保留旧行**（宁可留一条旧名字，不可让餐次指向空）。返回 `SeedImportResult{upgraded, inserted, deleted, keptWhileReferenced}`。⑤**条数不硬编码**：`apply_review.py` 生成 `lib/features/nutrition/domain/food_seed_count.g.dart`（`kFoodSeedV5RowCount` / `kFoodSeedV5RowCountGrouped`），`data_attribution.dart` 与设置页断言引用它；**不引入 manifest 文件**（多一个需校验一致性的文件，收益不成比例）。⑥**v4 不再随包**（两份都带白扛约 10 MB），但**留在仓库**作账本裁决对象与升级测试输入；隐私审计加 `retiredSeedFiles` 断言退役文件不得回到 pubspec。⑦**审核边界（README 写死，不得扩大解释）**：必审名称/品牌拆分与命名/明显非食物/重复；**不审**营养学绝对正确与过敏原标签；改营养必须填 source 或标「人工估值」（本轮改营养 0 条）。
- Alternatives: ①**只换 asset 路径不做升级**——**不可行**（docs/29 点名的「最容易做错的地方」）：既有 gate 是「库里已有当前 source 的行就 return」⇒ 换 asset 根本不触发导入；且 `_insertMissing` 永不覆盖既有行 ⇒ 老库原地不动，用户看到的还是 v4 的 49,464 条。②**把 v4 行直接删光再灌 v5**——被否：用户编辑过的行会丢，且被餐次引用的行会让 `meal_items.food_id` 指向空（历史餐食显示依赖 `food_name_snapshot` 才没炸，但食物库详情会断）。③**把两张词表合并成一个 `food_brands.g.dart`**——被否（D13）：自动表的价值恰恰在于「可从种子重算」，人一改就再也无法用它验种子是否被悄悄动过。④**人工表只收自动规则排除的部分（纯汉字）**——被否：人工裁决也可能**推翻自动表的误判**（`FINE` 是停用词形但确属品牌，账本有据），表里以账本为准而非以规则为准。⑤**用 manifest 文件派生条数**——被否（见上 ⑤）。⑥**把删除的 20 条直接物理删除不留痕**——被否：被引用者必须保留，且删除清单要进 `review_report.md` 留档。
- Consequences: 正面：App 装完即得**人工审核过**的 49,444 条中文食物；纯汉字品牌（`明治` 等）首次能被正确剥头上屏；品牌词表的「机器部分可重算 + 人工部分有账本证据」两层结构可长期核验。代价与已知边界：①**人工审核的权威性只来自账本本身**——上游没有品牌列，**不存在外部对照源**，无法用第二个数据集证明审核结论「正确」，只能证明每条结论**有出处、可追溯、可重放**；②**审核不是逐条键盘敲的**：族批确认占 30,544 条（62%），族批的成立条件是「≥2 条、同一首词、提交的 id 恰好等于该首词当前全部待审成员」，报告如实分列，不冒充逐条；③**审核范围有限**：营养值只在可疑时改（本轮 0 条），过敏原/膳食标签仍是名称启发式（ADR-025 的边界不变）；④**人工判断会出错且有更正通道**：本轮实测一处——批次4 早期把 `迷你`（尺寸描述词：`迷你 可爱多 甜筒` = 尺寸+品牌+品名）误并进词表，走账本追加 `revert` + 6 条 `approve` 更正并记入证据（`revert` 撤的是**账本最近一条生效裁决**而非指定行，期间误弹 `seed-fc-49520` 已补回——这是审核台的操作陷阱，证据文件已记）；⑤**设备走查有一项未闭环**：该 AVD 的 Gboard **无中文子类型**（144 个 locale 里 zh 系 0 个），`adb input text` 注入不了中文 ⇒ 「纯汉字人工 token 剥头」改为由等价的 ASCII 人工 token（`Nichirei日冷`，同样只存在于人工表、v5 行 `brand` 为 null）真机证据支撑，纯汉字路径由单测覆盖。**门禁 EXIT=0（1,952 passed / 11 skipped / 0 失败；`dart format lib test` 0 changed；`flutter analyze` No issues found）**，`apply_review.py --check` / `build_brand_gazetteer.py --check` / 三个 Python 测试套件全通过。收官时修掉第三处真缺陷：两张**生成表**的 `sha256` 常量声明与声明名同行、超过 `dart format` 的 80 列 ⇒ 生成物被格式器改写后就不再是生成器逐字节输出（`--check` 立刻 STALE）。**裁决口径**：这类冲突一律**改生成器让输出 format-clean**，不把生成物排除在门禁之外——否则生成物可以被任意手改而不被发现，`--check` 的可信度就没了。
- **交付件（2026-10-07 同日追加）**：优化版 arm64 APK = `E:/AI/Zcode/localfit-ai-simple-arm64-release.apk`，
  **13,915,632 B**，sha256 `8a98e3fe…40a80`，正式密钥 v2 签名（**与上一交付件同一把密钥** ⇒ 已装用户可覆盖升级），
  arm64-v8a 单 ABI。构建口径 `--release --split-per-abi --target-platform android-arm64 --obfuscate
  --split-debug-info --extra-gen-snapshot-options=--strip --dart-define=APP_VERSION=0.1.0`。
  **真缺陷**：漏加 `--split-per-abi` 时 `--target-platform android-arm64` **不裁剪其它 ABI 的预编译依赖**，
  包内混进 armeabi-v7a/x86_64 的 `libsqlcipher.so`/`libdartjni.so`，白扛 4.5 MB（18,374,994 B）⇒
  **单 ABI 交付必须同时给 `--split-per-abi`，并以 `aapt2 dump badging` 的 `native-code` 复核**。
  **v4→v5 原地升级的真机验收**（emulator-5556）：v4 里记录一餐含 v5 会删除的 `seed-fc-48243`（488 kcal），
  不卸载覆盖装 v5 ⇒ 档案/记录保留、库容 **49,445 = 49,444 + 1**、搜 `combos` 仍 3 条；
  `+1` 即 `keptWhileReferenced` 的语义证据（「连被引用行一起删」与「先删后插」两种错误都被真机证伪）。
  证据 `docs/evidence/2026-10-07-p8b2-delivery-apk.md`。
  **门禁首轮红的两条**：(a) **真缺陷**——`ai_egress_evaluation_test.dart` 钉住的
  `menu-normalize` 请求体哈希**每过一个午夜就失效**（正文含 `today=${_localDate()}`，
  而该任务构造时未注入时钟 ⇒ 落到真墙钟；本次跨 10-07→10-08 午夜）。
  **裁决**：注入 `FixedAppClock(now)`（同文件 `daily-menu-plan` 本就注入）+ 重钉哈希；
  **不删请求体里的 `today=`**——它是 P11 真实端点实测的产物（模型无基准日会输出
  `null` 被整单拒绝），属功能需要，不能为测试方便砍掉；正确做法是让测试控制时钟。
  (b) `catalog_search_perf_test.dart` 的 100 ms 绝对阈值在全量并行下超时，单独跑 3/3 通过、
  修 (a) 后全量亦通过，本轮未改搜索代码 ⇒ 记为已知负载敏感用例，**不放宽阈值**。
  **修后全量门禁 EXIT=0**（1,952 passed / 11 skipped / 0 失败）；唯一改动的 Dart 文件是该测试，
  `lib/`/`assets/` 未改 ⇒ 已核验的 APK 无需重建。
- Affected: `assets/seed/foods.v5.json`（新；v4 留仓库不随包）、`tool/food_seed/apply_review.py`（新）、`tool/food_seed/test_apply_review.py`（新）、`tool/food_seed/build_brand_gazetteer.py`（SEED→v5、known gap 段改写）、`tool/food_seed/review/`（账本落账）、`reports/review_ledger.jsonl`、`reports/review_report.md`、`reports/display_preview.jsonl`、`lib/utils/food_brands_reviewed.g.dart`（新）、`lib/features/nutrition/domain/food_seed_count.g.dart`（新）、`lib/utils/food_name.dart`（并集 + `Set<String>?` 默认参数）、`lib/features/nutrition/data/food_seed_importer.dart`（seed-v5 原地升级）、`lib/features/nutrition/domain/data_attribution.dart`、`pubspec.yaml`、`test/features/nutrition/food_seed_importer_test.dart`、`test/utils/food_name_test.dart`、`test/features/settings/settings_page_test.dart`、`test/features/training/exercise_seed_importer_test.dart`、`test/privacy/privacy_statement_audit_test.dart`、`docs/29-ui-ux-remediation-plan.md`、`docs/21-ui-redesign-spec.md`（as-built 注）、`GOAL.md`、`STATUS.md`、`docs/evidence/2026-10-07-p8b2-v5-upgrade.md`、`docs/evidence/screenshots/p8b2/`。

## ADR-029：披露面文案「只陈述真实行为」——三处假话改正（BUG-4/BUG-5/BUG-6）

- Date: 2026-10-08
- Status: accepted
- Context: 2026-10-08 的缺陷排查（`docs/11` 口径）在用户可见文案里查出**三处与真实行为矛盾**的陈述，其中两处**被测试钉住**因而长期存活：①帮助弹层『数据存在哪里？』写「应用不会把照片、体重或饮食记录上传到任何服务器。」——而拍照识别会把去 EXIF 的 JPEG base64 进视觉请求体、AI 对话每次带走今天+昨天的餐记录与最近 3 次体重（`docs/08 §2` 自己就是这么写的）；②反馈弹层写「当前版本不联网」「你的数据不会流出设备」（`settings_page_test.dart:437` 钉着这句）；③关于弹层中文里夹着英文单词 `you`（`AI 功能只在 you 主动配置并调用时…`）。这类错误比功能缺陷更重：它让用户在**做出是否使用 AI 的知情决定**时依据的是假信息。
- Decision: 三处一律**改成只陈述真实行为、不加新承诺、不弱化**：①帮助 → 「不主动使用 AI 功能就不会有内容离开这台设备；用拍照识别、AI 工作台或 AI 对话时，会把这次功能需要的那部分内容发给你自己配置的 AI 服务。」②反馈 → 标题「没有内置上报通道」，正文写清「这个版本没有内置上报通道：出错不会自动回传，也没有崩溃上报 SDK。唯一会联网的是你自己配置的 AI 服务，而且只在你用 AI 功能时才请求。」③关于 → 「AI 功能只在你主动配置并调用时，才经你自己配置的供应商端点发生。」**测试钉住旧错话时必须同步改测试**——被钉住的假话是「测试在保护缺陷」，改文案而不改断言等于没改。本轮属 `docs/11 §0.4` 允许的「文案级修复」，故以本 ADR 作为**文案变更登记**，证据 `docs/evidence/2026-10-08-bug-hunt-and-delivery.md` §1 逐条列出新旧文案。
- Alternatives: ①只改帮助那一处（反馈/关于的假话会留下，且反馈那句还被测试钉着）——被否：同类问题同一轮清干净，否则下一轮还要再走一遍。②把「不联网」改成「只在 AI 功能时联网」——被否：这只说了半句，漏掉「那部分数据会离开设备」，仍是弱化。③改 `docs/08 §2` 让文档去迎合文案——被否：行为是正确的（AI 功能必须把该次所需内容发给用户自己配置的供应商），错的是文案；改文档等于把假话合法化。④顺手把披露面做成「每次发送前弹窗确认」——超出「改文案」的范围，且改动确认流程语义（红线），不在此处做；对话侧缺披露的问题另行登记（证据 §4-U1）。
- Consequences: 正面：披露面三处与 `docs/08` 口径一致，帮助文档「先给你看清『发送了什么』」的说法对工作台任务卡与对话两个出口都不再自相矛盾；「没有内置上报通道」把「不联网」的合理内核（无遥测/无崩溃上报 SDK）保留下来。代价：三处测试断言同步更新（帮助弹层、反馈弹层短语钉、关于弹层新用例），属预期内。风险：文案不进任何 prompt 模板，**不影响 `_pinned` 出口哈希与 `templateSha256`**（本轮实测钉值全绿佐证）。**已知未闭环**：AI 对话出口仍没有任何用户可见的发送披露（`docs/23 §6` 要求的审计也未落地）——那属披露面**新增**，不在本轮「改假话」范围，登记为 U1。

## ADR-030：全清承诺必须覆盖磁盘字节——菜品照片纳入 `ClearAllLocalData`（BUG-7）

- Date: 2026-10-08
- Status: accepted
- Context: `ClearAllLocalData` 抬头写着「a full clear must leave no user-controlled bytes anywhere」，弹层对用户说「本地数据已全部清除。」但 2026-10-08 排查发现**菜品照片（docs/29 §P7 需求 16 的拍照留存）不在清理名单里**：`DishImageStore` 连 `clearAll` 都没有，用户拍过的每张照片都留在应用文档目录 `localfit_ai/dish_images/`。聊天图片当年就因同一漏洞补过一次，菜品照片是漏网的那个——说明「靠人记着把新存储加进名单」这个机制本身不可靠。
- Decision: ①**「文件型存储」是清理名单的强制成员**：全清 = 行（人工维护的表清单，schema 17 那次漏 7 张表的教训已入测试）+ 餐照 + 菜单原文 + 聊天图片 + **菜品照片** + API Key；②`DishImageStore` 新增 `clearAll()`：**整目录删、不先创建目录**（清理不该反过来创建目录），清不掉才抛 `DishImageStoreException('本地菜品照片清理失败，请重试。')`；③应用层通过**窄接口** `DishImageStoreRef` 依赖它（沿用 `AiApiKeyStoreRef` 既有手法），**不**让 `backup/application` import `campus_menus/data`；④`clearDatabaseRowsOnly()`（还原前用）**必须不碰**字节——两条方向都有测试钉住。
- Alternatives: ①让 `campus_menus` 自己监听并清理——被否：全清只有一个入口，分散清理会出现「某些路径漏清」。②让 `ClearAllLocalData` 直接持 `DishImageStore`——被否：应用层依赖数据层，破坏既有分层与可测性（假 store 注入是这两条测试的前提）。③**靠「下次启动回收 stale」**——被否：用户此刻看到的是「已全部清除」，不能把承诺推到将来。④把清理做成「注册表式」自动收集所有 store（更根治）——方向正确但属重构（要动 `main.dart` 的装配与全部 store 的接口），本轮以窄接口最小改动落地，注册表化留待与 U6（级联删行不清照片）一并做。
- Consequences: 正面：全清承诺对「照片类字节」补齐，与「不留用户字节」的不变量一致；`DishImageStoreRef` 让 campus_menus 之外也能安全清理而不反向依赖。代价：新增接口、注入点与 4 条测试（2 条真 IO + 2 条假 store），`main.dart` 的装配顺序要保证 store 先于 `ClearAllLocalData` 构造。**已知未闭环**：级联删行（删地点/窗口/菜品）仍不清磁盘照片、孤儿 JPEG 会累积（不影响隐私，全清与下次启动能回收）——登记为 U6，与本 ADR 的注册表化一并考虑。

## ADR-031：AI 任务卡的 `onConfirm` 是异步契约——类型即文档（BUG-1）

- Date: 2026-10-08
- Status: accepted
- Context: `AiTaskCard.onConfirm` 原是 `VoidCallback?`，但确认写入**本来就是异步落库**（训练计划 create / 菜单发布 / 菜品营养写库）。类型把 Future 丢掉，于是卡片无法知道「写入还没完成」，按钮在整个落库期间保持可点 ⇒ **双击真的写两份**：训练计划每次 `create` 都新 id、无去重，实测插入两条计划行。框架内同类守卫早有先例（对话编辑卡「应用中按钮禁用（防双击重复写库）」），任务卡这条路漏了。
- Decision: ①`onConfirm` 类型定为 **`Future<void> Function()?`**——确认是异步的，类型必须说实话（`lib/features/ai/presentation/ai_task_card.dart` 与 `ai_workbench/application/ai_workbench_task.dart` 同步）；②卡片加 `bool _confirming`：落库期间 `onPressed: _confirming ? null : _confirm`，`await onConfirm()` 后 `finally` 复位（**复位必须做**，否则一次失败后按钮永久禁用）；③防重入是**应用层/卡片层责任**，不是每个任务各自 `if (_busy) return`——三条任务路径只写一遍。
- Alternatives: ①在每个任务实现里加忙标记——被否：守卫分散到训练计划/菜单/菜品三处各自实现，漏一个就复发。②给按钮加 debounce 定时器——被否：只是把窗口变窄，竞态仍在（写入慢于窗口时照样两份）。③保持 `VoidCallback?` 而在调用处 `unawaited`——被否：类型继续骗人，下一个读代码的人还会踩。④在仓储层做去重（同内容同分钟只插一条）——被否：语义不明（用户确实可能想连记两次同内容），且治不了「菜单发布两次」这类副作用。
- Consequences: 正面：双击重复写库这条路径从「三层里漏一层」变成类型上不可能；测试用例直接把「写入挂起时再点」写成回归（红证 `Expected: <1> Actual: <2>`）。代价：3 个测试夹具的闭包类型同步为 `() async {}`（`Future<void>` 上下文不接受块体 void 闭包——`() {}` 会报 `body_might_complete_normally`）；后续任何新任务卡必须按异步契约实现 `onConfirm`。风险：若将来某个确认变回纯同步，仍应包成 `Future`（`() async {}`）而不是把类型退回 `VoidCallback`——**类型不许再退化**。

## ADR-032：测试里的固定时刻一律取「本地墙钟正午」`DateTime(y,m,d,12).toUtc()`

- Date: 2026-10-08
- Status: accepted
- Context: 生产把「今天」定义为**本地日**（`_localDate()` = `clock.nowUtc().toLocal()`，`docs/29` P11 起如此），而出口评测与工作台测试注入固定时刻来钉住请求体哈希。历史写法是 `DateTime.utc(2026,9,15,4)` 这种「本地 12:00（UTC+8）的巧合字面量」——它的**本地日期依赖运行机器的 UTC 偏移**：偏移 ≥ −4 时算出 `2026-09-15`（钉值成立），美东/美西机器算出 `09-14` ⇒ **同样的输入、同样的模板、同样的披露结论，钉值无端变红**。这类脆弱在单时区机器（本机 UTC+8）上永远不会红，属于「测试在别人的机器上炸、却查不出为什么」的隐患，2026-10-08 排查一并清掉。
- Decision: 测试中注入的固定时刻统一写 **`DateTime(y, m, d, 12).toUtc()`（本地墙钟正午）**：本地正午经 `.toLocal()` 往返**恒等**（任何偏移下都还是同一天同一时刻），因此该时刻在任何时区都给出同一个本地日期。四处（`test/ai_evaluation/ai_egress_evaluation_test.dart` 的出口钉值、`test/features/ai_workbench/daily_menu_plan_task_test.dart`、`test/features/ai_conversation/data/chat_edit_context_loader_test.dart`、`test/features/ai_conversation/application/chat_edit_executor_test.dart`）本轮统一。**不改生产语义**：`_localDate()` 继续走本地日（用户看到的「今天」必须是他的本地日）。
- Alternatives: ①把 `_localDate()` 改成 UTC 日期——被否：会改变生产语义（跨零点时段用户看到的日期不符本地认知），为测试方便改产品行为不可接受。②在每个测试里设 `TZ`——不可行：Dart 无法在进程内切时区（时区来自进程环境），且测试要与 `flutter test` 同进程。③保留巧合字面量并加注释警告——被否：脆弱性仍在，且不红的隐患不会被提醒救回。④钉值改成「相对时刻」（now + 0）——被否：会引入真实墙钟依赖，退回到上一轮修掉的 midnight 缺陷。
- Consequences: 正面：钉值不再随运行机器的时区变红，「本地日」的语义在测试与生产两头都成立。代价：无（本机两种写法是**同一个瞬间**，故 `requestSha256`/`templateSha256` 一个都没变，全绿佐证）。**诚实的局限**：这类脆弱**无法在单时区机器上做红绿实验**，本轮是「按构造性质论证 + 本机零差异」，要真红绿得在偏移 ≤ −5 的机器上跑一次（已记入证据 §3/§6）。**同类未修**：非 AI 面还有两处（`menu_tab_controller_test.dart:118-120` 甚至显式断言机器偏移 ≥ +4、`menu_file_importer_test.dart`），登记为 U9。

---

## ADR-033：界面改动的验收必须包含「设备走查」——组件测试的 sample 会掩盖缺陷

- Date: 2026-10-08
- Status: accepted
- Context: `docs/30` 的 R1–R7 七个包全部以「组件层断言 + HTML 稿渲染 + 隔离变异 + 门禁 EXIT=0」交付，每个包的证据文件都如实记着「未做真机走查，归 R8 统一做」。R8 补做走查（`LocalFit_API35` 模拟器，360dp，25 张走查页）后，**在 10 分钟里找出一个七个包都没抓到的真缺陷**：体重卡单条记录时那一根柱被 `Expanded` 撑满整个绘图区（实测 256dp 宽的一整块绿矩形）。根因不是逻辑错，而是**测试样本**：《今日-体重卡》的实现断言用的 fixture 是 31 条记录（月视图分箱后 5 根柱，每格 ≈60dp），而「柱宽上限」这道设计稿里写着的约束（`.bars .b { max-width: 40px }`）**只在柱数少时才可能被违反**——单柱/双柱场景在组件测试里从来没被构造过，于是「全部测试通过」与「用户看到一块绿板」同时成立。
- Decision: ①**界面改动的验收清单里必须有设备走查**（`docs/30 §3` 的 R8 行即为此而设），且走查要覆盖**边界样本**（单条记录、空态、首末态）而不只是有代表性的正常样本；②走查发现的缺陷**当轮就要修**并补**能抓住它的**断言（本轮的断言不看常量 40、只看「柱宽 < 绘图区一半」与「柱底贴基线」两条相对关系）；③**走查必须在 360dp 专用 AVD 上做**：本机另一台 AVD（`ZCodeRelayReview`）住着第三方应用会反复抢前台，导致 `uiautomator dump` 拿到**别的 App 的语义树**（本轮实测撞了三次），走查机必须是干净机；④重装 APK 后**必须核对 `lastUpdateTime`**——本轮有一次安装跑在构建产物落盘前 22 秒，装上去的还是旧包，读数（256dp）与修复后的代码不符，差点被当成「修复无效」。
- Alternatives: ①只信组件测试与稿子渲染——被否：本轮反例即此，稿子有 `max-width` 而实现没有，且稿子渲染用的是**多柱**样本，两边都不会报错。②把「设备走查」并入每个包的固定动作——被否（成本）：R1–R7 里多数包是单点几何修复（BMR 填充偏移）或文案/结构改动，逐包都起模拟器会把一轮的交付时间拉长数倍；改为**每轮收口一次全量走查**（R8 的位置），既覆盖了「包与包之间的相互作用」，也覆盖了「组件测试样本之外的真实数据形态」。③用 golden 测试代替走查——被否：golden 判的是「与上次快照是否一致」，而本轮缺陷从第一版快照起就一致（错的样子被固化了）。
- Consequences: 正面：R8 走查一轮即闭环了七个包积欠的设备验证（R1 的填充同轴、R2 的柱状图、R3 的单行卡与环心对齐、R4/R5 的白卡化、R6 的授权行与「去系统设置」真跳转、R7 的双模式与手动页），并顺带关掉 R6 明写的「未在设备上确认系统设置页真的打开」这条缺口（实测跳到 LocalFit 的 App info 页且已授权态正确显示为「设备不支持」）。代价：每轮收口多一次构建+走查（本轮 ≈35 分钟，含两次 APK 重建）。**诚实的局限**：走查在 x86_64 模拟器上做，**没有真机**（无计步传感器，所以步数只能验证到「设备不支持」这一态；真机的「已授权 + 有读数」态未验证）；iOS 依然完全未验证。


## ADR-034：构造函数收了却不用的参数等于没有——无障碍参数必须在语义树层断言（docs/31 S8）

2026-10-10（docs/31 S8 收口专项）。`DesignCard.semanticLabel` 从加入那天起就是**死参数**：
构造函数收、doc 注释写着「读屏标签（设计稿卡片无可访问名称时由调用方补）」、`build()`
从不使用——体重卡（`dashboard-weight-chart`）与快捷统计卡（`dashboard-stat-water` /
`-steps`）等调用方传的读屏标签全部被**静默丢弃**，49 处使用面里没有任何一条既有断言
发现（组件测试断言的全是可见文本与布局，`find.text` 看不见 label）。

1. **widget 的无障碍参数必须在语义树层断言**（`tester.ensureSemantics()` +
   `find.bySemanticsLabel` / `getSemantics`），可见文本断言量不到它。
2. **构造参数要么接线要么删除**：新增参数必须至少有一条测试读它的效果，否则它只是
   一个会撒谎的签名。
3. 修复形态与 `LfSegmentedToggle` 同一约定：`Semantics(label: …, container: true)`——
   整卡一个语义节点带标签、子节点照常可读、`InkWell` 点击动作不丢（同批补了
   「不传 label 不凭空造节点」的反向断言防过度合并）。

---

## ADR-035：缺陷定级规则——「静默数据丢失 / 重复写入 / 错误结论」直接进 P1（2026-10-21 裁决 D-1）

- Date: 2026-10-21
- Status: accepted
- Context: 2026-10-20 全应用审查里，审查代理把「加入餐双击写两条」与「`profile.goal.update`
  省略参数清空既有目标体重」定为 P2。S3 复评时按影响上调为 P1 并修复，但验收判据要求
  「原 P2 未升级为 P0/P1」，于是台账改回 P2、修复保留（`fix-p2` 批次）。这暴露的是**定级
  规则缺一条**：判据只看「功能是否可用」，没把「静默写坏数据」与「给出错误结论」算进严重度。
- Decision:
  1. **P1 定义补充三类**（与 docs/45 §9 的 P0/P1 定义兼容，不新增档位）：
     ① 静默数据丢失或重复写入（用户没有确认、界面也没提示）；
     ② 把不存在/不相关的结果说成命中，或把失败说成成功（误导性结论）；
     ③ 关键恢复路径（备份/恢复/全清）对某一代旧数据不可用。
  2. **定级在 S3 一次定死**：修复阶段不得上调/下调级别来迁就验收数字；若 S3 定错，
     在下一轮审查修正，而不是在修复中改。
  3. 台账保留「原始定级」与「本轮实际处理」两列；可选批次修 P2 不等于升级。
- Alternatives: ①新增「高危 P2」档——被否：docs/45 只有 P0–P3 四档，加档会让历史台账无法比较。
  ②按「是否已修」决定级别——被否：级别衡量风险，不衡量工作量。
- Consequences: 正面：以后同类问题不会因为「功能还能用」被降成 P2；本轮台账不需要重定级
  （两条保持原始 P2，修复事实单独记录）。代价：P1 数量会变多，排期压力更真实。

---

## ADR-036：食物库存储格式定死——单一分类 + 9 列官方导入 + 冗余列清除（2026-10-21 用户指示）

- Date: 2026-10-21
- Status: accepted（用户指示「把数据库存储方式定死」「就是一个种类」「不要二级分类」）
- Context: `foods` 表现有 32 列，其中 15 列来自 21 列 CSV 契约（libraryCode…sourceNature）、
  2 列是导入时的分类中间量（categoryGroup 24 类原文 / categorySub 二级分类），全部**只写不读**
  （仅 csv_exporters 回程导出）。分类事实上存在两套（category 10 枚举 + categoryGroup 24 类），
  违背用户「分类是一个指标、不要二级分类」的要求。
- Decision:
  1. **食物库定死为 13 个存储字段**：id、食物名称(name)、品牌(brand,可空)、**分类(category，
     唯一分类，取值=App 10 枚举 id)**、热量/蛋白质/碳水/脂肪(每 100g)、默认份量(defaultServingGrams，
     可空，App 记餐功能字段)、来源(source)、自建/内置(isUserCreated)、createdAt、updatedAt。
  2. **单一分类口径**：`FoodCategory` 10 枚举是唯一分类；导入的 24 个中文一级分类经
     `FoodCategory._libraryGroups`（24→10 写死映射）在**导入时翻译成枚举 id 存储**，
     原文不落库；二级分类一律不导入不存储。
  3. **官方导入格式定死为 9 列 CSV**（表头一字不改、顺序即下方顺序，前 8 列与用户那份
     「国内食品营养数据」文件逐字同序）：食品ID(可空，读取后丢弃——身份去重走（名称, 品牌）)、
     **品牌**、**食物名称***、一级分类*、热量*、蛋白质*、碳水*、脂肪*、
     自建/内置(可空，导入侧读都不读——导入行一律自建)。`*` = 除食品ID 外的空值规则按既有导入器。
     旧 21 列 CSV 继续宽容接受，但除上列字段外的列**读取后丢弃**（不报错、不编数据）；
     旧 8 列英文表头（name/brand/category/四项营养/origin）同样继续接受。
  4. **schema 30**：DROP 17 列（15 列契约列 + categoryGroup + categorySub），带存在性守卫。
  5. **food_aliases 保持现状（事实澄清）**：App 侧这张表**只有读、没有写**——
     读点三处（AI 预览搜索 `food_preview_search`、菜单项匹配 `menu_item_matcher`、
     检索段重跑判据 `index_coordinator`），外加备份导出/恢复与清空；随包 CSV 导入、
     用户 CSV 导入、手动新建、AI 建食物、目录分片导入**都不写它**。
     分片 ETL（`tool/food_catalog/etl_pipeline.py`）会在分片库里生成 `aliases` 表，
     但分片导入器只读 foods/revisions/evidence/portions，不把它搬进 App 表。
     ⇒ 现状：**没有一条食物有别名**（除非恢复旧备份）。
- Alternatives: ①保留 24 类作为主分类——被否：10 枚举已接图标/筛选/映射，24 类交叉过多。
  ②保留冗余列只停写——被否：用户明确「定死」，死列违背。③不改 schema 只改导入——被否：同上。
  ④给 aliases 补写入路径（导入时按品牌/别名生成）——本轮不做（用户未要求；且会让
  「别名」与（名称,品牌）身份去重两套口径并存）。
- Consequences: 正面：存储=用户清单；分类单一；导入格式可交给用户流水线长期使用。
  代价：schema 30 迁移（DROP COLUMN 需要 SQLite ≥3.35，bundled sqlite3 3.45 满足）；
  21 列 CSV 导出/导入测试迁移；旧备份恢复时 15 列值被丢弃（可接受——本来只写不读）。

---

## ADR-037：食物库加「别名」列（10 列格式）+ 名称格式 + 分类硬门禁 + 存量库一次归一化（2026-10-21 用户指示）

- Date: 2026-10-21
- Status: accepted（用户指示：「名称后边加一个别名」「所有现有食物都检索一遍，看看有什么别名，都加上」
  「自建食物数据的时候也加一个别名输入框」「名称要有固定的格式，备注要放在括号里放在名称后边」
  「以后的分类都必须是你这 10 个分类才能入库，不然就进行手动转化分类」）
- Context: ADR-036 把导入格式定死为 9 列、别名表只读不写。用户要求把别名变成**一等字段**
  （导入/导出/手动新建都能填），并一次性把存量 23,919 条的名称、分类、别名核对干净。
  名称层面源数据有真实瑕疵：括号用了 `[]【】「」«»` 混写、括号错位、品牌被复制两遍
  （`逍遥老杨家逍遥老杨家…`）、规格混在主名里（`…300克…`）。
- Decision:
  1. **官方导入/导出格式 = 10 列**（别名紧跟食物名称）：
     `食品ID, 品牌, 食物名称, 别名, 一级分类, 热量(kcal/100g), 蛋白质(g/100g),
     碳水化合物(g/100g), 脂肪(g/100g), 自建/内置`。别名列可空；多个用 `、`/`,`/`;` 分隔。
     旧 9 列 / 21 列 / 8 列文件继续接受（缺别名列 = 无别名）。
  2. **别名仍存 `food_aliases` 表**（不新增列）：`normalized_text` 存归一化形态
     （去空白、全角→半角、小写，与 `normalizeMenuText` 同一函数）；CSV 导入的别名
     `alias_type='manual'`、`source='import'`；随包规则派生的 `alias_type='nickname'`、
     `source='normalized'`。`NewFood.aliases` 为 `List<String>?`：null = 不动（AI 改营养时
     不会误删别名），`[]` = 清空（编辑弹层提交空列表的语义）。
  3. **分类硬门禁**：入库分类只能是十档（label/id）或 24 个库大类（自动映射，兼容旧文件）；
     **其他值整行拒绝**，预览弹层给出「无法识别的分类」去重清单与条数，由用户手工把文件
     改成十档后重导——不猜、不兜底成「其他」。
  4. **名称格式**：`主名（备注；备注2）`——括号只用全角 `（）` 且合并到名称末尾、括号前不留
     空格；`[]【】〔〕「」『』《》〈〉` 与散引号在导入/归一化时按括号/引号处理；主名为空
     （整名都在括号里）或结构本来就坏（右括号先于左括号）**不改**，进审计报告由人看。
  5. **存量库一次归一化**：随包 `assets/seed/food_library_normalization.v1.csv`
     （旧(名称,品牌) → 新名称/品牌/分类/别名，只含需要改或能派生别名的行）由一个幂等
     后台任务应用一次（KV `food_library_normalized_v1`）；与随包导入同序执行。
     归一化只搬文字、不删备注；分类只改「强关键词」命中的行（102 条），疑点进报告。
  6. **手动新建/编辑**：新增可选「别名」输入（逗号分隔）；编辑弹层预载现有别名，
     保存即替换（`[]` 清空语义）。
- Alternatives: ①别名存 `foods` 新列——被否：与 ADR-036「13 字段定死」冲突，且多值列无法索引；
  ②导入时自动把 24 类翻成十档之外再「猜」——被否：用户要求确保正确，猜错无法分辨；
  ③把归一化规则引擎搬进 Dart——被否：规则与数据一起演进，两份实现必然漂移；
  改为「Python 产出资产 + Dart 只做确定性表单格式化 + 资产应用」。
- Consequences: 正面：别名可查可写，菜单匹配/AI 预检索立刻受益；存量数据一次性对齐；
  分类入库有硬门禁。代价：随包资产 +1.4 MB（未压缩）；导入/导出/弹层三处测试迁移；
  归一化会改写 116 个名称（全部列出在 `docs/evidence/2026-10-21-food-library-audit/changes.csv`）。



