# 修复计划（2026-10-20）

> S4 产物。逐条对应 [`docs/48`](48-review-report.md) §4.2 的 **14 条 P1**（审查代理原始定级；
> 另有 1 条经复验证伪，2 条原始 P2 放在文末 `fix-p2` 可选批次）。
> 纪律：一次一个 ID、**RED 先行**、修完定向回归、不夹带重构与文案；
> 每批跑门禁。P0 为 0 条，故批次从 `fix-p1-a` 开始。

> **影响面总述**：14 条 P1 + 2 条提前修复的 P2 **全部不触及** AI wire 形状、21 列 CSV 契约、数据库 schema（29 冻结）。
因此**没有 `decision-required`**；唯一涉及新增依赖的候选（RV-P2-22 离线探测）不在本轮修复范围，
登记为 `decision-required`。

---

## 批次 fix-p1-a（数据与写入正确性 + 误导）

### RV-P1-01 旧备份（schema<28）恢复整单失败

- **根因**：备份注册表 `write` 直接 `insert(from(row))`；drift 生成的 `fromJson` 对
  schema 28 新增的**非空**列（`meal_items.sourceType`、`dish_library.nutritionBasis/basisAssumed/userEdited`、
  `ai_memories.importance/useCount`）执行 `serializer.fromJson<T>(null)` → `null as T` → `TypeError`，
  事务回滚。旧包（v17–v27 导出）必然触发。
- **改法**：`backup_table_registry.dart` 的 `_table(...)` 新增 `defaults` 参数（`Map<String,Object?>`），
  `write` 改为 `{...?defaults, ...row}` 再 `from`。只为**后加的非空列**声明默认值：
  `meal_items: {sourceType:'manual'}`；`dish_library: {nutritionBasis:'perServing', basisAssumed:true, userEdited:false}`；
  `ai_memories: {importance:50, useCount:0}`。**为什么不选另一种**：不改生成的 `fromJson`（那是
  build_runner 产物，会随 `build_runner` 再次被覆盖）；也不做逐列 `schemaVersion` 分支（备份文件
  不带 schema 版本，RD-P2-13 已登记该缺口）。
- **影响面**：备份恢复路径；无 wire/CSV/schema 变更。旧包恢复后的语义：份量未知 → `basisAssumed=true`（诚实）。
- **先红测试**：`test/features/backup/old_backup_restore_test.dart` —— 由当前库导出一份 JSON，
  删除上述键后 `RestoreLocalFitData.restore`；断言**不抛**、行数正确、默认值落库。
- **判据**：该测试红→绿；既有 `export_restore_test.dart` 全绿。
- **回滚**：单文件回退 `backup_table_registry.dart`。
- **风险**：默认值选择影响「旧包恢复后的口径」；`basisAssumed=true` 会让旧菜品显示「按 100g 估算」，
  与迁移回填同口径（一致，不是新偏差）。

### RV-P1-02 记忆近似重复/水目标异常逃出执行器

- **根因**：`AiMemoryMergeSuggested implements Exception`（不是 `AiMemoryException` 子类）；
  `WaterTargetException` 同理。执行器 `apply` 的 catch 名单没有它们，异常穿出 `apply` →
  `applyProposed` 无 try → 整批行停在 `applying`，且不持久化。
- **改法**：`chat_edit_executor.dart` 的 `apply` catch 名单增加
  `on AiMemoryMergeSuggested catch (e) => failure(e.message)` 与
  `on WaterTargetException catch (e) => failure(e.message)`。
  **为什么不选另一种**：不把两个异常改成继承 `AiMemoryException`（会改变仓储层异常语义与既有测试契约）；
  也不在 `applyProposed` 外包 try（那只能兜住不崩，仍拿不到人话与行状态）。
- **影响面**：命令失败分支；不触 wire/CSV/schema。
- **先红测试**：`test/features/ai_conversation/application/executor_failure_isolation_test.dart`
  ① 用脚本化 `MemoryVectorIndex` 返回 0.90 → 首条记忆已存在时第二次 `memory.remember` 必须返回
  `ok=false` 且 message 含「建议合并」，**不抛**；② 只有 goals 没有 daily_targets 时
  `targets.update{waterMl}` 返回失败文案，不抛。
- **判据**：两测试红→绿；`chat_edit_executor_test.dart` 全绿。
- **回滚**：两行 catch。
- **风险**：极低；只是把异常翻成人话。

### RV-P1-03（**已证伪，不修**）

审查代理主张「有菜单快照的地点无法删除」；复验发现 `menu_sources.venue_id` 与
`menu_snapshots.source_id` **两跳都是 cascade**，删除地点会级联清掉快照。
反证与实测见 [`code/fp-check.md`](evidence/2026-10-20-full-app-review/code/fp-check.md)。
`delete_venue_with_snapshot_test.dart` 保留为不变量钉子（修复前即通过）。

### RV-P1-04 `canteen.dish.create + nutritionFrom=food` 未命中留下已建菜却报失败

- **根因**：先 `createDish` 落库，再 `_applyFoodNutrition`；未命中返回 failure 直接 `return applied`，
  菜已存在。用户重试 → 同名重复菜。
- **改法**：未命中时**如实返回部分成功**：`ChatEditApplyResult.ok('已新增菜品（$id），
  但食物库没有「X」，营养未填写；可改用 AI 分析或手动填写。')`。
  **为什么不选另一种**：不做「失败即删除菜」的回滚——建菜与填营养是两条独立事实，删掉会让用户
  重新建一次；也不静默改走 AI（违反 docs/40 §3.1）。
- **影响面**：命令结果文案与 `ok` 值；不触 wire/CSV/schema。
- **先红测试**：`test/features/ai_conversation/canteen_dish_create_partial_test.dart` —— 食物库无同名时
  执行 `canteen.dish.create{nutritionFrom:'food'}`；断言 `ok=true`、message 含「营养未填写」、
  `menu_items` 恰 1 行、`menu_item_nutrition_evidence` 0 行。
- **判据**：红→绿；`nutrition_source_routing_test.dart` 的失败文案断言按新事实迁移（**不放宽**：
  原来断言 `ok=false`，改为断言「ok=true 且明说营养未填」）。
- **回滚**：单分支回退。
- **风险**：与既有测试契约不同，需要显式迁移并说明理由。

### RV-P1-06 语义检索无相关性阈值

- **根因**：`rankDishes` 返回**全部**打分菜品（仅排序），不设最低 cosine；RRF 把语义名次当命中，
  于是任意查询都能「找到 N 道 · 命中：语义」。
- **改法**：`semantic_runtime.dart` 增加 `kDishSemanticMinCosine = 0.35`（与 docs/39 §6.4 记忆门控
  同一常量口径），`scored` 过滤 `>= 0.35`；过滤后为空 ⇒ `lastRankError='没有足够相关的菜（最高 cos …）'`
  并返回 `null`（调用方降级为两路，结果为空 → 空态）。
  **为什么不选另一种**：不在融合层按分数截断（语义只有名次，没有可比的分数）；不改评测门槛（P0 的
  recall@10 口径不受影响，阈值只影响 UI 展示）。
- **影响面**：语义检索召回；不触 wire/CSV/schema。
- **先红测试**：`test/features/nutrition/menu_search_semantic_threshold_test.dart` —— 脚本化引擎让
  查询与菜名正交（cos=0）→ 搜索空态、`reasons` 不含「语义」；让二者一致（cos=1）→ 命中且含「语义」。
- **判据**：红→绿；`menu_search_test.dart`（仅语义命中用例）全绿（其脚本引擎 cos=1，不受影响）。
- **回滚**：单常量 + 一行过滤。
- **风险**：阈值偏高会让弱相关菜消失；0.35 与记忆门控同源，且降级会如实显示（配合 RV-P1-09）。

### RV-P1-07 手填营养导入菜品库仍标「AI 估算」

- **根因**：`add_canteen_dishes_to_library.dart:72` 硬编码 `source: 'ai_estimate'`，未读证据 `origin`。
- **改法**：按 `dish.evidence?.origin` 映射：`user_input → 'manual'`、`food_library → 'food_library'`、
  其他 → `'ai_estimate'`；同时 `meal_evidence.dart` 的 `evidenceGradeForSource` 增加
  `'food_library' => confirmed`（与 `canteenOriginGrade` 同口径）。
  **为什么不选另一种**：不在 UI 层改文案（数据里的 source 才是单一事实源，AI 命令/导出/统计都读它）。
- **影响面**：菜品库来源徽标与统计（「已确认/估算」）；不触 wire/CSV/schema。
- **先红测试**：`test/features/nutrition/canteen_dish_source_test.dart` —— 手填营养（user_input）→
  加入菜品库 → `DishRecord.source == 'manual'`、`evidenceGradeForSource == confirmed`；
  引用食物库 → `'food_library'` 且 confirmed；AI 分析 → `'ai_estimate'` 且 estimated。
- **判据**：红→绿；设备复验徽标显示「已确认」。
- **回滚**：单文件映射回退。
- **风险**：历史数据里被误标 `ai_estimate` 的行不会自动纠正（登记为残留，不静默改写）。

### RV-P1-16 门禁不可自包含（importer_smoke 依赖仓库外 CSV）

- **根因**：测试读 `E:/AI/Zcode/tmp/localfit-next/食品营养数据库_8列版_utf8.csv`，临时目录清理后红。
- **改法**：改读 `assets/seed/user_foods_8col.v1.csv`（随包资产，sha256 与文档一致，字节相同）。
  **为什么不选另一种**：不把 CSV 复制进 `test/fixtures`（1.65 MB 重复入库）；也不改成小样本
  （那会失去「全量 23,919 行」判据）。
- **影响面**：测试夹具路径；无 wire/CSV 契约变更。
- **先红测试**：本次基线已经红（`static/gate-review-baseline-red.log`），即 RED 见证。
- **判据**：门禁恢复 `+2772 ~66`；该测试单独跑绿。
- **回滚**：单行路径回退。
- **风险**：极低。

### RV-P1-17 `importDocument` 无事务

- **根因**：循环内逐条 `remember()`，第 N 条失败时 1..N-1 已提交（含向量行）。
- **改法**：整个循环包 `database.transaction`，异常时整体回滚；向量写入也在同一事务内（同一 database）。
  **为什么不选另一种**：不做「预校验后写入」两趟（校验与写入之间仍可能变；事务是唯一原子保证）。
- **影响面**：记忆导入（当前无 UI 调用方）；不触 wire/CSV/schema。
- **先红测试**：`test/features/ai_memory/import_document_transaction_test.dart` —— 两条记忆、第二条含敏感词 →
  抛 `FormatException`，`ai_memories` 0 行、`embedding_index` 0 行。
- **判据**：红→绿；`memory_governance_p2_test.dart` 全绿（其注释「调用方负责回滚」按新事实迁移）。
- **回滚**：单方法回退。
- **风险**：低。

---

## 批次 fix-p1-b（交互 / 视觉 / 验收基础）

### RV-P1-08 「清除全部数据」漏 `dishImageStore`

- **根因**：`main.dart` 的 `createAppDataClearer` 未传 `dishImageStore`；该参数在组合函数里恒 null。
- **改法**：把 `createAppDataClearer` 的 `dishImageStore` 改为 **required**（编译期强迫装配），
  `main.dart` 传入与 `CanteenRepository` 同一个 store 实例。
  **为什么不选另一种**：不在 `ClearAllLocalData` 里自己 `new` 一个 store（路径/ID 生成器会与生产不同源）。
- **影响面**：全清覆盖；不触 wire/CSV/schema。
- **先红测试**：`test/features/backup/clear_all_wiring_test.dart` —— 用真实 `FileDishImageStore`
  写入一张图 → `createAppDataClearer(...)` → 断言文件不存在。修复前该测试**编译失败**（缺必需参数）= RED；
  另加一条运行期断言（store 传入且清空）。
- **判据**：红→绿；`clear_all_local_data_test.dart` 全绿。
- **回滚**：单函数签名 + 调用点。
- **风险**：低（编译期兜底）。

### RV-P1-09 降级矩阵无消费者

- **根因**：`degradationNotice`/`degradationRowFor` 零引用；菜单搜索在语义不可用时静默退两路。
- **改法**：`MenuSearchController` 暴露 `semanticNotice`（来自 `runtime.lastRankError` 与
  `degradationNotice(degradationRowFor(aiConfigured:false), search)` 的组合）；
  `MenuSearchResultsSliver` 在结果为 0 且有查询时渲染一行 `Key('nutrition-menu-degraded-note')`，
  文案取矩阵常量（如「语义检索不可用，本次只用关键词与标签。」）。
  **为什么不选另一种**：不在所有 20 格都铺 UI（那需要新的全局降级状态机；本轮只修**用户能遇到**的
  搜索降级，其余格登记 P2）；也不把 notice 塞进 SnackBar（会遮挡且不可回看）。
- **影响面**：菜单搜索 UI；docs/21 需新增 1 个 Key。
- **先红测试**：`test/features/nutrition/menu_search_degradation_note_test.dart` —— 语义不可用 + 查询
  无关键词命中 → 空态 + note 文案等于矩阵常量。
- **判据**：红→绿；设备帧（无 AI 配置时搜索）。
- **回滚**：单文件 UI + controller 字段。
- **风险**：低；文案必须与矩阵常量同源（测试钉住）。

### RV-P1-10 / RV-P1-11 弹层被底栏遮挡（D8 回归 3 处）

- **根因**：新弹层用裸 `showModalBottomSheet` 且缺 `useRootNavigator: true`；`sheetBottomInset` 只算
  键盘+安全区，不含底栏。
- **改法**：`ai_conversation_page.dart:635` 加 `useRootNavigator: true` + `enableDrag: false` +
  `padding: EdgeInsets.only(bottom: sheetBottomInset(sheetContext))`；`training_page.dart:1034/1160`
  各加 `useRootNavigator: true`（其余两件已具备）。
  **为什么不选另一种**：不改成 `AppSheet`（训练页两个弹层是 `DraggableScrollableSheet` 形态，改壳会动交互）。
- **影响面**：三处弹层；docs/21 附录 D8 增补「裸弹层清单」。
- **先红测试**：`test/app/sheet_convention_test.dart` —— 静态扫描 `lib/` 的
  `showModalBottomSheet(` 调用点，要求同块内出现 `useRootNavigator: true`、`enableDrag: false` 与
  `sheetBottomInset`。修复前 3 处违规 = RED；修复后 0 违规 = GREEN。
- **判据**：红→绿；设备帧（记忆候选弹层保存钮在底栏之上）。
- **回滚**：三处参数。
- **风险**：静态测试需容忍 `AppSheet` 内部调用（白名单）。

### RV-P1-12 加载失败永久 spinner

- **根因**：三个页面只判「无数据」，不判 `snapshot.hasError` / 不 catch。
- **改法**：训练页 `if (snapshot.hasError) → AppErrorText('训练数据加载失败，请重试。') + 重试按钮`；
  菜单 tab `_reloadOnce` 包 try/catch，失败设 `_loadError` 并渲染错误行 + 重试；
  记忆页 `if (snapshot.hasError) → AppErrorText('记忆加载失败，请重试。')`。
  **为什么不选另一种**：不做全局错误边界（Bloc/Provider 级重构超出范围）。
- **影响面**：三页错误态；不触 wire/CSV/schema。
- **先红测试**：`test/features/ai_memory/ai_memory_error_state_test.dart`（注入抛错的仓储）+
  `test/features/training/training_error_state_test.dart`（注入抛错 snapshot）；
  菜单 tab 由 widget 测试注入抛错 repository。
- **判据**：红→绿；三页加载态仍显示骨架/spinner（不回归）。
- **回滚**：三处 builder 分支。
- **风险**：低。

### RV-P1-13 warning/error 作正文对比度不足

- **根因**：`warning`（#FF9800）当文字色只有 2.16；`warningForeground` 是白色（画在橙底上 2.16）；
  `error`（#F44336）当正文 3.68；蛋白 chip 1.93。
- **改法**：
  1. 新增 token `warningText`（亮 `#9A5B00`：card 5.43 / bg 5.13 / muted 4.85；暗 `#FFB74D`）
     与 `errorText`（亮 `#B3261E`；暗 `#EF5350`）；
  2. 亮色 `warningForeground` 由白改 `#2B1B00`（画在 `#FF9800` 上 ≈7.0）；
  3. 5 处把 `warning`/`error` 当文字色的地方改用 `warningText`/`errorText`
     （`week_strip`、`exercise_library_page`、`training_target_indicator`、`food_card`、`settings_page:2790`）；
  4. 聊天卡「点击查看」chip 的文字色改 `cardForeground`（底仍 `protein100`）。
  **为什么不选另一种**：不整体替换 `warning` 主色（它是填充色，换掉会改所有徽标/图表的视觉）；
  也不改 `error` 主色（品牌语义与既有帧）。
- **影响面**：亮色主题若干文字/图标颜色；docs/21 §2.1.6 需登记新 token。**会改变捕获帧**（重拍）。
- **先红测试**：`test/app/design/token_contrast_test.dart` —— 计算并断言
  `warningText` 对 card/bg/muted ≥4.5、`warningForeground` 对 `warning` ≥4.5、`errorText` 对 card ≥4.5；
  修复前 token 不存在（编译失败 = RED）。
- **判据**：红→绿；捕获矩阵重拍后逐帧实看（变化面应为上述 5 处 + week strip）。
- **回滚**：token + 5 处调用点。
- **风险**：视觉变化需要人看；数值判据明确。

### RV-P1-15 13 个 Key 零测试断言

- **根因**：D1/D2/D3/D5/D6/D7 的若干 Key 只实现未测。
- **改法**：新增 `test/app/design/key_contract_test.dart`（或按页面拆），逐个 pump 宿主并断言 Key 存在：
  `canteen-dish-manual-nutrition`、`dish-meal-confirm`、`dish-meal-picker`、`meal-entry-by-dish`、
  `food-reference-sheet/-adopt/-analyze/-skip/-source`、`nutrition-menu-dish-basis-<n>`、
  `nutrition-menu-dish-sync-<n>`、`food-cleanup-suggestion-<n>`、`retrieval-debug-rerun`。
  **为什么不选另一种**：不做「源码里 grep Key」的伪断言——必须渲染出来（docs/21 §8.1）。
- **影响面**：仅测试；不改产品代码。
- **先红测试**：该文件在补齐断言前不存在（RED = 缺失覆盖）；先写一条必失败的（对未渲染 Key 断言
  会失败），再逐个补齐到绿。对 13 个 Key 的每一个，先跑一次「找不到」的失败输出留档。
- **判据**：13/13 Key 有渲染断言；`docs/21` Key 三方对账脚本 0 缺口。
- **回滚**：删测试文件。
- **风险**：部分弹层依赖较重（食物库/食堂仓储），测试宿主需要最小夹具；只断言 Key 不写库。

---

## 批次 fix-p2（可选，本轮已提前执行 2 条）

> 依据验收判据「原 P2 未升级为 P0/P1」：这两条**保持审查代理原始定级 P2**，不重定级；
> 但因属数据重复/静默丢失，作为可选批次提前修复。是否长期上调为 P1 留待用户裁决
> （`decision-required`，默认不改定级）。

### RV-P2-26（原 A-F06，原始定级 P2，**已提前修复**）「加入餐」双击写两条

- **根因**：`_addToMeal` 无重入锁；按钮无 busy 态。
- **改法**：`MenuDishList` 增加 `_addingDishIds` 集合；`_addToMeal` 入口 `if (!_adding.add(id)) return;`
  并在 `finally` 移除 + `setState`；把 `busy` 传给 `DishCard`/`MenuSearchResultsSliver` 的「加入餐」按钮
  （`onPressed: busy ? null : ...`）。搜索行的按钮同样按 id 禁用。
  **为什么不选另一种**：不在仓储层加「同菜同秒去重」——真实用户可能确实要加两份，幂等应由交互层保证。
- **影响面**：菜单页按钮态；不触 wire/CSV/schema。
- **先红测试**：`test/features/nutrition/menu_add_idempotency_test.dart` —— 双击「加入餐」，
  断言 `meals` 只有 1 条 + 1 个 item；第二次点击期间按钮 `onPressed == null`。
- **判据**：红→绿；设备帧复验（单击 1 条）。
- **回滚**：两处 UI 文件回退。
- **风险**：极低。

### RV-P2-27（原 A-F08，原始定级 P2，**已提前修复**）`profile.goal.update` 清空目标体重

- **根因**：`updateGoal` 无条件 `Value(targetWeightKg)`，可选参数缺省即 `null` 落库。
- **改法**：`ProfileIdentityRepository.updateGoal` 改为 `double? targetWeightKg` 且**仅在非 null 时**写入
  （`if (targetWeightKg != null) 'targetWeightKg': Value(targetWeightKg)`）；
  资料编辑页本来就预填，行为不变。
  **为什么不选另一种**：不在执行器里先读旧值再回填（会与页面编辑产生竞态，且语义应固定在仓储）。
- **影响面**：AI 命令与资料页同一路径；不触 wire/CSV/schema。
- **先红测试**：同 `executor_failure_isolation_test.dart` 第三例：目标体重 65 → `profile.goal.update{goal:'减脂'}`
  → 目标体重仍 65；显式给 60 → 变 60。
- **判据**：红→绿；`profile_identity_repository` 相关测试全绿。
- **回滚**：单方法回退。
- **风险**：低。

## 执行顺序与门禁

| 批次 | 内容 | 门禁标签 |
|---|---|---|
| fix-p1-a | RV-P1-01/02/03/04/05/06/07/14/16/17 | `fix-p1-a` |
| fix-p1-b | RV-P1-08/09/10/11/12/13/15 | `fix-p1-b` |
| fix-p2（可选） | RV-P2-26 / RV-P2-27（本轮已修）+ RV-P2-25 命令失败分支补齐 | `fix-p2` |
| 终态 | 全量回归 + 文档同步 | `review-final` |

每条修完立即跑该条定向测试；每批结束跑全量门禁（format 0 / analyze 干净 / 全绿 / exit 0 /
`changed_during_run: []`）。
