# 全应用审查报告（2026-10-20）

> S3 产物。审查范围与判据见 [`docs/47`](47-review-plan.md)；原始证据在
> [`docs/evidence/2026-10-20-full-app-review/`](evidence/2026-10-20-full-app-review/)。
> 审查阶段只读：本报告与证据之外未改任何 `lib/` 代码。

---

## 1 结论

**能用，但有条件。** 14 个维度逐维审完：核心写路径（记餐、记忆、备份、检索、AI 命令）在
正常路径上可靠，隐私与出网面干净（只有 3 处出网实现、零遥测、Key 只进 secure storage 且零日志），
SQLCipher 失败即拒开、随包 2.4 万食物库在设备上真实可用。

**最严重的三件事**（都是 P1，无 P0）：

1. **恢复旧备份会整单失败**：schema < 28 的导出包缺新列，drift 生成的 `fromJson` 对非空列
   执行 `null as T` 抛 `TypeError`，事务回滚，用户只看到「恢复失败，当前数据未受影响」。
   备份是最后一道恢复手段，这条必须先修。
2. **三处「静默/误导」破坏既有承诺**：① 「加入餐」双击写两条餐记录（设备实测 400 kcal、
   「估算 2 项」）；② 语义检索没有最低分阈值，查「不存在的菜」也「找到 1 道 · 命中：语义」；
   ③ 手填营养（用户输入）导入菜品库后仍标「AI 估算」。
3. **降级矩阵是死文本**：20 格常量与测试都在，但 `degradationNotice` / `degradationRowFor`
   在 `lib/` 下零调用——docs/41 §10「所有降级都在界面上如实标注」在端上模型不可用、
   索引重建等格子上并未实现。

另外，**开工基线本身是红的**：`importer_smoke_test.dart` 依赖仓库外的临时 CSV，文件被清理后
门禁掉到 `+2771 ~66 -1`。用随包 CSV（同 sha256）恢复后回到 `+2772 ~66`。这是「门禁不可自包含」
的真缺陷，已登记。

---

## 2 覆盖情况（逐格）

### 2.1 维度 × 目标 × 实际

| 维度 | 目标 | 实际 | 结论 |
|---|---|---|---|
| A 功能正确性 | 写路径 100%（含失败）；37 命令逐条 | 写路径 15 类逐条核对（`code/audit-A-F.md` §2）；37/37 成功路径；**37/37 失败分支**（本轮补 `command_failure_branches_test.dart` 15 例 + `executor_failure_isolation_test.dart` 3 例，原缺口 11 条已清零）；A-F03 经复验证伪 | **达标** |
| B 界面与视觉 | token/对比度/emoji/四态/深色/裁字/图片 | 43 组 token 配对比值实测（10 组 <4.5）；emoji 用户面 0；四态 9/11 空态、10/11 加载、8/11 错误、4/11 骨架；深色实看 | **不达标**：warning 作正文对比度 1.9–2.2（P1）；错误态/骨架缺口（P1/P2） |
| C 交互 | 热区/反馈/确认/取消/弹层/键盘/防抖 | 弹层逐个核对（3 处 D8 回归）；热区主流程 ≥48；危险操作 5/5 有确认；双击写路径缺忙态 | **不达标**：D8 回归 + 双击（P1） |
| D 流畅性/性能 | ≥10 项数字 | **16 项**数字（`perf/summary.md`）；冷启动 2.3–8.4s；PSS 194MB；50k 搜索 p95 25.6ms | **达标**（滚动掉帧 not run） |
| E 动画 | 单一 motion 源/无限动画/reduce motion | `AppMotion` 存在；19 处 `Duration(ms)` 字面量（7 处为防抖）；7 处 `.repeat()`，6 处有 reduce-motion 守卫 | **部分达标**：`training_hero.dart:543` 未守卫（P2） |
| F 状态与一致性 | 单一事实源/写后刷新/竞态/跨零点 | 6 个跨入口路径 + 3 个常驻页；发现段级缓存不带消息/不带日期（P2）、并发 load 无代次（P2） | **部分达标** |
| G 错误与降级 | 5×4 逐格 + 标注 | 20 格逐格核对（`code/audit-G-H.md` §2）；notice 无消费者 | **不达标**：降级未标注（P1） |
| H 数据与迁移 | 守卫/回填/旧包恢复/21 列/全清 | 迁移逐版本核对；21 列契约正确；全清漏 dish 图片；旧包恢复失败 | **不达标**：2 条 P1 |
| I 隐私与安全 | 出网面/Key/红线/权限/SQLCipher/许可 | 3 处出网实现、0 硬编码 host、0 遥测；权限 6 条均有用途；SQLCipher 失败即拒；明文目录 4 个（docs 只登记 1 个） | **基本达标**：明文目录披露缺口（P2） |
| J 无障碍与适配 | 1.0/1.3/2.0、320dp、标签、横屏 | 320dp+2.0× 设备实看无溢出；`semanticLabel` 覆盖主要图标钮；横屏未锁未测 | **部分达标**：1.3× 无专项断言（P2） |
| K 边界与异常 | ≥20 条 | **27 条**（22 处理 / 5 缺口） | **达标** |
| L AI 交互质量 | 协议/解析/修复/短名单/重试/截断 | 协议 12 条完整；信封严格（散文+JSON 可救、双 JSON/截断拒）；4 类 repair 完整；截断不标注 | **部分达标**：截断标注缺失（P2） |
| M 文档与测试一致性 | Key 三方对账 100% | 344 行 Key 表（`docs/key-sync.md` 由审查代理产出）；13 个 Key 零断言；docs/23 参数三处不一致 | **不达标**：Key 覆盖缺口（P1） |
| N 构建与发布 | 门禁/aapt2/体积/版本/许可 | 门禁绿（基线恢复后）；aapt2 2040/4040；APK 与源码同源（源码 mtime 全早于 APK、随包 CSV 字节相同） | **达标** |

### 2.2 页面进入覆盖（100% 目标）

| 页面/入口 | 进入 | 帧 |
|---|---|---|
| 引导页（4 步） | ✅ | `device/01–05` |
| 今日页 | ✅ | `05`, `22`, `23`, `58` |
| 饮食 · 记录 | ✅ | `09`, `44`, `60` |
| 饮食 · 菜单 | ✅ | `07`, `35`, `41` |
| 饮食 · 食物库 | ✅ | `08`, `12a` |
| 食物详情弹层 | ✅ | `12` |
| 菜单搜索（命中/空态/清空） | ✅ | `42`, `45` |
| 记录一餐入口弹层 / 菜品选择器 | ✅ | `10`, `11` |
| 食堂目录 / 地点 / 窗口 / 菜品表单 | ✅ | `24`–`34` |
| 参考食物库弹层 / 菜品动作 / 手动营养 | ✅ | `33`, `36`–`39` |
| 训练页 / 动作库 / 计划创建入口 / 手动计划 | ✅ | `13`, `53`–`56` |
| AI 对话（欢迎/发送失败/结束会话/提炼） | ✅ | `14`, `15` |
| AI 创作画廊 | ✅ | `59` |
| 拍照识餐（相机 → 已拍摄 → AI 不可用） | ✅ | `61`–`63` |
| 我的/设置（含底部与危险确认） | ✅ | `16`, `17`, `47`, `48` |
| 资料编辑 | ✅ | `51` |
| AI 配置弹层 | ✅ | `19` |
| AI 记忆页 | ✅ | `18` |
| 搜索调试 | ✅ | `20` |
| 整理重复菜品 | ✅ | `52` |
| 备份/恢复/导出菜单 | ✅ | `49` |
| 深色模式（设置/今日） | ✅ | `21`, `22` |
| 320dp + 2.0× 今日页 | ✅ | `23` |
| 下一餐推荐二级页 | ✅ | `device/89-next-meal-page.png`（记录页「下一餐推荐」入口卡 → 二级页） |
| AI 工作台（`/ai-workbench`） | ✅ | `device/59-ai-create-gallery.png`（AI 页「AI 创作」chip → 工作台画廊） |

**结论**：**23/23 进入并取帧（100%）**。早前把「AI 创作」画廊误记为独立页、把下一餐二级页
误判为无入口，已在交付自查中纠正。

### 2.3 写路径端到端（含失败）

| 写路径 | 成功 | 失败分支 | 结论 |
|---|---|---|---|
| 记餐（手动/食物/菜品/扫描） | ✅ 测试 + 设备（`44`） | 校验失败有人话；**双击不幂等**（P1） | 修 P1-05 |
| 菜品库增改删 | ✅ | 同名更新绕过营养校验（P2） | 登记 |
| 食堂地点/窗口/菜品/营养 | ✅ 设备（`27`–`39`） | **删地点被快照外键挡住**（P1）；`create+food` 未命中留下已建菜（P1） | 修 P1-03/04 |
| 食物库导入（CSV） | ✅ 23,919 行 | 事务整体回滚；坏行只计数 | 通过 |
| 自建食物增改删 | ✅ | `food.update.servingGrams` 静默无效（P2） | 登记 |
| 饮水/体重/步数 | ✅ | 同秒并发有 UNIQUE/更新 | 通过 |
| 训练计划/会话 | ✅ | 会话重复开始如实拒绝 | 通过 |
| AI 记忆写/删/改口/归档/待确认 | ✅ | 近似重复异常逃逸（P1）；importDocument 无事务（P1） | 修 P1-02/17 |
| 备份/恢复/全清 | ✅ 设备（`48`） | **旧包恢复失败**（P1）；全清漏菜品照片（P1） | 修 P1-01/08 |
| 37 条 AI 命令 | 37/37 | **37/37**（本轮补齐 15 例失败分支测试） | 通过 |

### 2.4 降级矩阵 5×4

逐格表见 `code/audit-G-H.md` §2。**20/20 有常量与测试**，但：
`offline` 行无法由 `degradationRowFor(aiConfigured:)` 推出（无网络探测依赖）；
「索引重建中」的「显示重建进度」在用户界面不存在；所有 notice 无渲染点（P1-09）。

### 2.5 Key 三方对账

见 `code/audit-I-K-L-M-N.md` §5（344 行）。**331/344 三方齐全**；13 个已上线 Key 零测试断言
（P1-15），3 个文档登记为动态生成（`food-reference-source/-evidence`）需在文档标注。

---

## 3 指标基线（16 项，详见 `perf/summary.md`）

| # | 指标 | 值 | 结论 |
|---|---|---|---|
| 1–3 | 冷启动（3 次） | 8,418 / 4,411 / 2,295 ms | 首次含导入；中位 4,411 |
| 4 | 启动帧 p50/p95 | 16 / 26 ms | 通过 |
| 5 | 今日页首查 | 15 ms | 通过 |
| 6 | `listRecent(50)` | 5 ms | 通过 |
| 7 | 30 天趋势 | 5 ms | 通过 |
| 8 | 30 天训练会话（22） | 28 ms | 通过 |
| 9 | 食物搜索（500） | 3 ms | 通过 |
| 10–11 | 分类计数/首页/深页（2 万） | 9 / 8 / 5 ms | 通过 |
| 12 | 5 万行 CJK 搜索 p50/p95 | 23.57 / 25.57 ms | 通过（<100ms） |
| 13 | CSV 23,919 预览/导入 | 156 / 315 ms | 记录 |
| 14 | 16.5MB 备份导出/恢复 | 541 / 1,142 ms | 记录 |
| 15 | 设备 PSS/RSS | 194 / 302 MB | 记录 |
| 16 | APK arm64/x86_64 | 39.1 / 41.5 MB | 未变 |

未测：1000+ 行滚动掉帧、设备端向量推理延迟、arm64 真机（无设备）。

---

## 4 缺陷台账

> 证据列指向 `docs/evidence/2026-10-20-full-app-review/`。详细复现步骤见对应 `code/audit-*.md`。

### 4.1 P0（阻断）

**0 条。** 未发现崩溃、数据丢失、隐私泄露、核心流程不可用或安全绕过。

### 4.2 P1（严重，全部进入修复；共 **14** 条）

| ID | 维度 | 标题 | 位置 | 证据 | 历史 |
|---|---|---|---|---|---|
| RV-P1-01 | A/H | 恢复 schema<28 旧包整单失败（缺列 `null as T`） | `app_database.g.dart:16993/22062/25539`；`restore_localfit_data.dart:88` | `code/audit-A-F.md` A-F02 | 新 |
| RV-P1-02 | A/L | `AiMemoryMergeSuggested`/`WaterTargetException` 逃出执行器 → 整批编辑卡卡在「应用中」 | `ai_memory_repository.dart:121`；`chat_edit_executor.dart:113-137/856-877` | `code/audit-A-F.md` A-F01/A-F12 | 新 |
| RV-P1-04 | A | `canteen.dish.create + nutritionFrom=food` 未命中：菜已落库却报失败，重试产生同名重复 | `chat_edit_executor.dart:455-473` | `code/audit-A-F.md` A-F04 | 新 |
| RV-P1-06 | A/L | 语义检索无相关性阈值：任意查询都「命中：语义」 | `semantic_runtime.dart:277-291` | `device/45-menu-search-empty.png`（「不存在的菜」→ 找到 1 道） | 新（设备复现） |
| RV-P1-07 | B/A | 手填营养（user_input）导入菜品库后仍标「AI 估算」 | `add_canteen_dishes_to_library.dart:72`；`meal_evidence.dart` | `device/41-menu-with-dish.png` | 新（设备复现） |
| RV-P1-08 | H/I | 「清除全部本地数据」生产装配漏 `dishImageStore`，菜品照片残留 | `main.dart:580-593`；`clear_all_local_data.dart:100` | `code/audit-G-H.md` G-H02 | 复发（2026-10-08 同类） |
| RV-P1-09 | G | 降级矩阵无消费者：降级不上屏（端上模型不可用/索引重建） | `degradation_matrix.dart:123-130`（零引用） | `code/audit-G-H.md` G-H01 | 新 |
| RV-P1-10 | C | AI 记忆候选弹层未用根导航器/inset，保存钮被底栏遮挡 | `ai_conversation_page.dart:635` | `code/audit-B-C-E-J.md` | 复发（D8 同类） |
| RV-P1-11 | C | 训练页两个弹层未用根导航器，关键按钮被底栏遮挡 | `training_page.dart:1034/1160` | 同上 | 复发（D8 同类） |
| RV-P1-12 | B/C | 三处加载失败永久 spinner（训练/菜单/记忆） | `training_page.dart:166-176`；`menu_tab_view.dart:188`；`ai_memory_page.dart:224-230` | 同上 | 新 |
| RV-P1-13 | B/J | warning 色作正文/图标时对比度 1.9–2.2（<4.5） | `week_strip.dart:61`；`exercise_library_page.dart:466`；`training_target_indicator.dart:36`；`food_card.dart:162`；`lf_chat_bubbles.dart:413` | `code/audit-B-C-E-J.md` §2 | 新 |
| RV-P1-15 | M | 13 个已上线 Key 零测试断言（含 D2 参考食物库整层） | 见 `code/audit-I-K-L-M-N.md` §5 | `docs/21` 附录 D | 新 |
| RV-P1-16 | N | 门禁不可自包含：`importer_smoke_test` 依赖仓库外临时 CSV，文件清理即红 | `test/features/nutrition/importer_smoke_test.dart:17` | `static/gate-review-baseline-red.log` | 新（基线红） |
| RV-P1-17 | H | `importDocument` 无事务，坏行留下半批（含向量） | `ai_memory_repository.dart:689-771` | `code/audit-G-H.md` G-H03 | 新 |

> **审查代理的 A-F03（「有快照的地点无法删除」）经复验证伪**：`menu_sources.venue_id` 与
> `menu_snapshots.source_id` 两跳都是 `onDelete: cascade`，删除地点会级联清掉快照。
> 反证与实测见 [`code/fp-check.md`](evidence/2026-10-20-full-app-review/code/fp-check.md)。
> 该条**不计入** P1 台账；`delete_venue_with_snapshot_test.dart` 保留为不变量钉子。

### 4.3 P2（2026-10-21 复核轮：**27/27 全部闭环**）

> **定级说明（decision-required，保守默认：不重定级）**：审查代理把「加入餐双击」与
> 「目标体重被清空」定为 **P2**。本轮按验收判据「原 P2 未升级为 P0/P1」**保持原 P2 定级**，
> 但因其属数据重复/静默丢失，已在可选批次 `fix-p2` 中**提前修复**（见 `docs/49`）。
> 是否应把这两条长期上调为 P1，留待用户裁决；在裁决前不改变台账定级。

| ID | 标题 | 位置 |
|---|---|---|
| RV-P2-26（原 A-F06，**本轮已修**） | 「加入餐」无忙态，双击写两条餐记录 | `menu_dish_list.dart` / `menu_search_results.dart` |
| RV-P2-27（原 A-F08，**本轮已修**） | `profile.goal.update` 省略 `targetWeightKg` 清空既有目标 | `chat_edit_executor.dart:940`；`profile_identity_repository.dart:109` |
| RV-P2-25（**本轮已修**） | 11 条命令缺执行器级失败分支测试 | `code/audit-A-F.md` §3；本轮 `command_failure_branches_test.dart` 15 例 |
| RV-P2-01（**2026-10-21 已修**） | 记忆/餐/水段级缓存不带消息与日期，跨零点不失效 | `chat_edit_context_loader.dart:154-199/497-509` |
| RV-P2-02（**2026-10-21 已修**） | `food.update.servingGrams` 静默无效（成功文案撒谎） | `chat_edit_executor.dart:786-800`；`food_repository.dart:178-204` |
| RV-P2-03（**2026-10-21 已修**） | 动作库查询默认 500 条，超出后精确同名假报不存在 | `exercise_repository.dart:26-32` |
| RV-P2-04（**2026-10-21 已修**） | 下一餐控制器并发 `load()` 无代次令牌 | `next_meal_decision_controller.dart:89-165` |
| RV-P2-05（**2026-10-21 已修**） | 同名菜品更新绕过营养校验，与创建路径口径相反 | `dish_library_repository.dart:137-173` |
| RV-P2-06（**2026-10-21 已修**） | 记忆页主列表未过滤已改口条目，条数与计数不一致 | `ai_memory_repository.dart:35-43` |
| RV-P2-07（**2026-10-21 已修**） | 引用食物库营养：链接失败时部分写入还报失败 | `chat_edit_executor.dart:525-548` |
| RV-P2-08（**2026-10-21 已修**） | 未来日期被接受；快照只取最近 30 条会被未来餐挤掉 | `chat_edit_command.dart:332-336`；`chat_edit_context_loader.dart:497-508` |
| RV-P2-09（**2026-10-21 已修**） | 记餐格文案把 canteen `origin=user_input` 说成记餐事实 | `degradation_matrix.dart:78` |
| RV-P2-10（**2026-10-21 已修**） | schema 28 回填 4 条 SQL 无测试，`basis_assumed` 会误标真实 100g | `app_database.dart:635-667` |
| RV-P2-11（**2026-10-21 已修**） | `from<10` 的 5 个 `createIndex` 不幂等 | `app_database.dart:141-150` |
| RV-P2-12（**2026-10-21 已修**） | 恢复成功后重建任务失败会被报成「恢复失败」（数据其实已替换） | `restore_encrypted_backup.dart:47-49`；`settings_page.dart:1627-1633` |
| RV-P2-13（**2026-10-21 已修**） | 调试面板原样打印异常文本（可含 SQL/路径） | `retrieval_debug_route.dart:95`；`retrieval_debug_page.dart:408-411` |
| RV-P2-14（**2026-10-21 已修**） | 四个明文私有目录，docs/08 只登记 `menu_raw/` | `file_chat_image_store.dart:138` 等 |
| RV-P2-15（**2026-10-21 已修**） | 发布密钥库与 `key.properties` 在仓库内且未 `.gitignore` | `android/key.properties`；`android/app/localfit-release.jks` |
| RV-P2-16（**2026-10-21 已修**） | UI 侧食物/菜品/地点/窗口名无长度上限（AI 路径 300） | `food_repository.dart:291-310`；`canteen_repository.dart:234` 等 |
| RV-P2-17（**2026-10-21 已修**） | 流式 `finish_reason` 零解析，截断不标注 | `open_ai_compatible_conversation_service.dart:212-323` |
| RV-P2-18（**2026-10-21 已修**） | 记忆红线在备份恢复路径不可达 | `backup_table_registry.dart:317-321` |
| RV-P2-19（**2026-10-21 已修**） | `applicationId` 与 `namespace` 不一致 | `android/app/build.gradle.kts:23,32` |
| RV-P2-20（**2026-10-21 已修**） | docs/23 参数表与代码三处不一致（water 上限/meal items 上限/过敏原条数） | `docs/23:128,130` |
| RV-P2-21（**2026-10-21 已修**） | `AiTransportRequest.apiKey` 死字段（声明并构造，零读取） | `ai_transport.dart:26,35` |
| RV-P2-22（**2026-10-21 已修**，裁决 D-2） | 「无网」降级行不可推导 | `degradation_matrix.dart` + `ai_connectivity_monitor.dart`；测试 `ai_connectivity_monitor_test` |
| RV-P2-23（**2026-10-21 已修**） | 错误态/骨架覆盖不足（8/11、4/11） | 见 §2.1 |
| RV-P2-24（**2026-10-21 已修**） | 训练页 hero 无限动画未受 reduce-motion 守卫 | `training_hero.dart:543` |

### 4.4 P3（登记，不修）

`code/audit-*.md` 共记 30 条：emoji 按 UTF-16 计长、CSV 导出公式中和破坏往返、未知餐次静默落「加餐」、
`daily_targets` 无唯一约束、`importDocument` 无调用方、`markUsed`/`expiresAt` 悬空、
`cardio_prescriptions` 死表、iOS 缺 `PrivacyInfo.xcprivacy` 等。

---

## 5 未覆盖与 not run（如实）

| 项 | 状态 | 原因 |
|---|---|---|
| 真实 AI 端到端（对话/信封/短名单注入） | **not run** | 环境无 `LF_AI_LIVE_*` 凭据；按硬约束只用契约/mock，**不声称真机 AI 已验证** |
| 下一餐推荐二级页 | not entered | 当日卡片走「记录晚餐」CTA，无二级页入口 |
| AI 工作台独立页 | not entered | 无用户可达入口（仅深链/画廊内部） |
| 1000+ 行连续滚动掉帧 | not run | 需 profile 构建 + gfxinfo reset；release 包未插桩 |
| 设备端向量推理 p50/p95 | not run | 设备库仅 1 道菜，索引 1 条，测量不具代表性；沿用历史稳态数据 |
| arm64 真机 | blocked | 无实体设备 |
| 1.3× 字号专项 | not run | 既有捕获矩阵为 1.0/1.5/2.0；设备只验 1.0/2.0 |
| 横屏 | not run | 未锁；无测试矩阵 |
| TalkBack 实机走查 | not run | 模拟器读屏不可靠（历史同类登记） |
| 恢复旧包的真实端到端 | not run（代码级确定） | 需构造旧列集包；本轮按代码路径判定，修复时补测试 |
| B7 归档 / B8 待确认的设备复验 | not run | 设备库无近义簇、无待确认候选 |

---

## 6 与历史问题对账

| 历史问题 | 本轮状态 | 说明 |
|---|---|---|
| 弹层被底栏遮挡（D8, 2026-10-19 修） | **复发 2 处 + 新 1 处** | RV-P1-10/11 是同类新弹层未照约定；D8 约定未形成静态护栏 |
| `watchAll()` 写在 build 里（2026-10-18） | **仍有 5 处** | RV-P2-01 同族；`menu_dish_list` 已有注释但无静态护栏 |
| worker isolate 读资产 / 平台通道 | 未复发 | 语义链路设备上「可用 · 已索引 0 条」正常 |
| 待确认任务被调度器标失败 | 未复发 | `kUserConfirmedJobTypes` 有效 |
| 搜索「刷新→notify→再检索」死循环 | 未复发 | `identical(dishes,...)` 守卫有效 |
| 全清漏用户字节（2026-10-08 修过） | **装配层再漏** | RV-P1-08 |
| 门禁 OOM | 本轮未遇 | 未同时跑模拟器与全量测试 |
| `importer_smoke` 依赖外部 CSV | **新登记** | RV-P1-16 |

---

## 7 修复建议顺序

1. **数据恢复与写入正确性**：RV-P1-01（旧包恢复）→ RV-P1-04（食堂写入）→ RV-P1-05（双击）→ RV-P1-14（目标被清空）。
2. **误导与静默**：RV-P1-06（语义阈值）→ RV-P1-07（来源徽标）→ RV-P1-09（降级标注）→ RV-P1-02（异常逃逸）。
3. **数据清理与隐私**：RV-P1-08（全清漏图）→ RV-P1-17（导入事务）。
4. **交互与视觉**：RV-P1-10/11（D8）→ RV-P1-12（永久 spinner）→ RV-P1-13（对比度）。
5. **验收基础**：RV-P1-16（门禁自包含）→ RV-P1-15（Key 断言）。
6. P2 按「便宜且低风险」挑选（RV-P2-02/03/04/06/09/10/20/21），其余进残留。

---

## 8 已接受的设计选择（不算缺陷）

1. **记餐无唯一约束**：同一餐可以有多条同食物记录（真实世界会吃两份）；幂等由 UI 忙态保证，不靠 DB 唯一键。
2. **语义检索不做硬过滤**：口味/语义只做软 boost（×1.05），不改变命中集合——docs/39 明确。
3. **待确认记忆/整理建议不自动写库**：确认才写；归档只改 `status`，`listAsOf` 仍可回看。
4. **备份不含向量**（docs/41 裁决）：恢复后由 `rebuildIndexRows` 重建。
5. **`foods` 无配料/过敏原列**（schema 22 删除）：配料三层来源只在食堂菜上。
6. **「离线」降级行不可推导**：不新增 connectivity 依赖（docs/45 §2.3「需要新增第三方依赖除非阻塞 P0」）→ 登记 `decision-required`，本轮不修。
7. **iOS 打包项**（`PrivacyInfo.xcprivacy`、蓝牙 usage string）：当前只发 Android；docs/08 §6 已列为上架前项。
8. **P3 死表/悬空 API**（`cardio_prescriptions`、`markUsed`、`expiresAt`）：历史演进残留，非本轮范围。

---

## 9 待裁决（decision-required，均已取保守默认并继续）

| # | 事项 | 保守默认（已执行） | 影响 |
|---|---|---|---|
| D-1 | 「加入餐双击」「目标体重被清空」是否长期上调为 P1 | **已裁决（2026-10-21）**：台账保持原始 P2（不重定级，`fix-p2` 已提前修复）；**定级规则改在 `DECISIONS.md` ADR-035**（静默丢失/重复写入/错误结论直接进 P1） | 下一轮审查起生效，不影响本轮数字 |
| D-2 | 「无网」降级行是否需要 connectivity 依赖才能推导 | **已裁决（2026-10-21，选项 A）**：不加依赖；`AiConnectivityMonitor` 用真实 `NetworkFailure(connection)` 证据判离线（10 分钟窗口、成功即清），矩阵 `degradationRowFor(offline:)` 可推出该行，AI 对话页显示 `ai-chat-offline-note`；离线行搜索格改为「端上语义可用、不降级」 | 没调用过 AI 的用户看不到该提示（设计如此：有证据才说） |
| D-3 | 词义阈值 0.45 是否随模型迭代重标 | **已裁决（2026-10-21，选项 A）**：保持 0.45；`kEmbeddingModelId` 注释写明「换模型必须同时重标阈值」 | 换模型时按标定文档重跑 |
