在 E:/AI/Zcode/projects/localfit-ai/localfit-ai 中，按 docs/43-next-phase-delivery-plan.md 执行
「记忆 · 检索 · 食物数据」的下一阶段：**把已建好的检索能力接到用户入口，并把记忆治理补完**。
本任务自包含，不依赖上一轮对话。

先读（按顺序）：STATUS.md、docs/43、docs/41、docs/39、docs/40、docs/21（附录 D1–D9）、AGENTS.md。
基线：门禁 p21-final（+2694 ~66，exit 0，changed_during_run: []）；APK vc2037 / vc4037；
schema 29；端上向量已启用（maxLen 32 + 前缀 B，worker isolate）。

一、任务与顺序（每个里程碑独立验收，不逐包等确认）

M1 可见性（先做，改动面最小、收益最大）
1) A1 菜单页搜索框：MenuDishList 段头下加搜索框（Key nutrition-menu-search），200ms 防抖；
   走 DishSearchService（关键词+标签+语义三路），语义名次来自注入的 SemanticRuntime
   （不可用自动退关键词+标签，不弹错）；进页空闲触发一次 indexDishes（幂等、textHash 复用）；
   结果抽成 menu_search_results.dart（守 500 行预算），行 Key nutrition-menu-search-hit-<id>、
   空态 nutrition-menu-search-empty、结果头 nutrition-menu-search-count；清空恢复推荐区。
2) A2 AI 短名单接线：在 DriftChatEditContextLoader 新增「候选菜品（本地检索）」段——
   仅当用户消息命中吃/推荐意图时注入，DishSearchService + buildAiShortlist 取 top 30，
   按窗口分组，每行带 id；只加 system 文本段，不改任何 wire 形状、不新增命令。
3) A4 调试面板补第三档：模式对比加 SEMANTIC_FIRST（Key retrieval-debug-mode-semantic）。
4) A3 索引调度接设备状态：新增 PowerStateSource（isCharging / watchCharging / isIdle）；
   实现 A 用 battery_plus（需用户点头，见决策点 D1），实现 B 用「应用在后台」近似空闲并如实标注；
   main 里在充电+空闲时 tick，前台不领取新任务、已领取的允许跑完；15 分钟兜底 tick；
   沿用 dedupeKey 幂等。D1 未答复前先做实现 B 的骨架，不擅自加依赖。

M2 治理
5) B5 记忆容量对齐锁定决策：拆 kAiMemorySoftCap=2000 / kAiMemoryHardCap=5000 /
   kAiMemoryInjectionCandidates=200；达硬顶拒绝、超软顶提示整理；注入候选固定 200 条打分
   （性能测试 <30ms）；导入上限 = 硬顶。不新增表/列。
6) B6 记忆向量判重与合并提议：记忆向量写 embedding_index（ownerType='memory'）；
   findNearDuplicates；remember 的 DuplicatePolicy：字符串完全相同快速拒（不花嵌入）、
   cosine ≥0.96 拒、0.88–0.96 抛 AiMemoryMergeSuggested、<0.88 写入、allow 可强制；
   删除同步删索引；恢复后重建覆盖 memory。
7) B7 整理建议：memory_hygiene.dart——按 domain 分桶找 cosine ≥0.9 的近义簇（每桶 ≤500）、
   180 天未用且 importance<40 的条目；记忆页入口 ai-memory-hygiene + 弹层；
   只建议不自动，归档用已有 status='archived'。
8) B8 会话结束提炼进待确认：候选存 background_jobs.payload（type=memoryExtraction，
   dedupeKey=memoryExtraction:<conversationId>，state=pending），复用
   ai_memory_candidates.dart 的 AiMemoryCandidateParse；对话页加「结束本次会话」
   （Key ai-chat-end-session），消息 ≥6 且开关 ai_memory_auto_extract 开启（默认关）才执行；
   记忆页「待确认 N 条」（Key ai-memory-pending），确认才 remember(source='extracted')，
   忽略只移出 payload；不新增表。
9) B11 记忆页分页：总数 >50 或搜索非空时用 repository.searchPage(query, offset, limit: 50)，
   底部「加载更多」（Key ai-memory-load-more），头部「共 N 条」。

M3 个性化与协议
10) B9 口味向量：近 30 天、来源 dish 的餐记录 → 菜品向量，权重 0.5^(ageDays/14)，加权平均后
    L2 归一；<10 餐不参与；DishSearchService 可选 tasteVector 只做 ×1.05 软 boost，
    与标签画像取较大者不叠加，绝不硬过滤。
11) B10 食物来源路由提示词 + nutritionFrom：chat_edit_registry.dart 的 renderProtocol()
    加「食物来源优先级」段（docs/40 §5 原文）；canteen.dish.create / canteen.dish.nutrition
    增加可选 nutritionFrom（food|ai|none，缺省保持旧行为）；food 分支命中写
    origin='food_library' + grade 沿用 + 链接 confirmed，未命中给可行动文案，不静默改走 AI。

二、已锁定，不要重新讨论
端上 bge-small-zh-v1.5 int8 随包（已做）；检索用 maxLen 32 + 查询前缀 B，记忆用 64；
worker isolate + 空闲预热（已做）；Drift 存向量 + 暴力余弦三档（sqlite-vec 不适用）；
RRF + boost + MMR，硬过滤只留安全/可用性；记忆注入默认 3k/24 条、容量软顶 2000/硬顶 5000、
向量不进备份、会话结束提炼进待确认；四层职责与四条铁律（docs/40 §0）；
份量未知标「按 100g 估算」；配料未确认推荐但标注；时间语义（S14 / schema 29）已落地。

三、硬约束
只写 E:/AI/Zcode 内（native/Write 用 Windows 路径；临时文件只放 tmp/<context>/）；
不自动提交/推送/发布；不改 21 列 CSV 与任何 wire 形状；DB 只允许 docs/41 §11 已登记内容
（本阶段全部复用 schema 29，不新增表/列；新功能用 embedding_index / background_jobs / app_settings）；
保护「确认才写 / 取消重试 / 历史快照 / 权限与恢复」语义；不放宽测试与性能预算；
真实 AI 仅限已授权范围、凭据只走环境变量且零入库；设备只动自有 AVD LocalFit_API35；
向量绝不绕过硬约束，没配料的菜标「未确认」。

四、工作纪律与交付
先取 RED → 实施 → 定向回归 → 全量门禁（run.py <label> gate：format 0 改动 / analyze 干净 /
全绿 / exit 0 / changed_during_run: []）→ 必要帧实看与设备复验（菜单搜索一次含语义命中的真实
查询、AI 短名单注入一次、调度在充电+后台真的领取任务）→ 同步 docs/21（新 Key）、docs/INDEX.md、
STATUS.md 与逐包证据；如实登记 blocked/not run；交付改动清单、评测数据（召回/延迟）、
APK 路径 + sha256、剩余限制。建议门禁标签：m1-gate、m2-gate、m3-gate，最终 next-final。

五、两个决策点（未答复时的默认行为）
D1 是否新增 battery_plus 依赖用于充电判定：未答复 → 用实现 B（后台近似空闲），如实标注「未接充电判定」。
D2 会话结束提炼是否允许自动发起真实 AI 调用：未答复 → 默认关（只保留手动提炼）。

六、立即开始
先做 M1 的 A1、A2、A4（A3 等 D1），一轮内跑完门禁与设备复验；然后 M2（B5 → B6 → B7 → B8 → B11）；
最后 M3（B9、B10）。明确不做：>5 万条目的 1-bit 预筛 / >50 万 HNSW、arm64 真机延迟复测
（无设备，继续如实登记）。
