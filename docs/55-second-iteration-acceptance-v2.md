# 二次迭代验收与结果（第 1 轮）

日期：2026-10-22 ｜ 依据：[`docs/53`](53-review-remediation-goal-v2.md) §4.2 收敛判据 ｜
报告：[`docs/52`](52-review-report-v2.md) ｜ 修复计划：[`docs/54`](54-remediation-plan-v2.md)

---

## 1. 本轮闭环项逐条复验

| ID | 原缺陷 | 复验方式 | 结果 |
|---|---|---|---|
| **RV2-P1-01** | 「记录一餐」搜索对同名不同品牌食物不可区分 | ① 单元级：新增用例先红（`+23 -1`）→ 后绿（`+33`）；② 同类变体 `scan_candidate_editor.dart` 定向回归 8/8；③ **设备实帧**：重建 APK（versionCode 4051）装入自有 AVD，搜「米饭」三行分别显示 `116 kcal / 100g`、`千丰香米 · 338 kcal / 100g`、`叮咚 · 156 kcal / 100g`，读屏标签 `添加 米饭（千丰香米）` / `添加 米饭（叮咚）` | **闭环** |

## 2. 全量门禁（连续两次，同一轮）

| 标签 | format lib | format test | analyze | 测试 | exit | `changed_during_run` |
|---|---|---|---|---|---|---|
| `review-v2-baseline`（修复前） | 0 | 0 | `No issues found!` | `+2869 ~66` | 0 | `[]` |
| `review-v2-fix1`（修复后第 1 次） | 0 | 0 | `No issues found!`（6.4s） | **`+2870 ~66`** | 0 | `[]` |
| `review-v2-final`（修复后第 2 次） | 0 | 0 | `No issues found!`（6.2s） | **`+2870 ~66`** | 0 | `[]` |
| `review-v2-final2`（文档同步后） | 0 | 0 | `No issues found!`（7.6s） | **`+2870 ~66`** | 0 | `[]` |
| `review-v2-final3`（文档同步后重跑） | 0 | 0 | `No issues found!`（7.6s） | **`+2806 ~66 -2`** | **1** | `[]` |
| `review-v2-final4`（释放内存后） | 0 | 0 | `No issues found!`（7.3s） | **`+2870 ~66`** | 0 | `[]` |
| `review-v2-final5`（连续第二次） | 0 | 0 | `No issues found!`（5.7s） | **`+2870 ~66`** | 0 | `[]` |
| `review-v2-keysync`（第 2 轮：Key 对账升级 + 6 条断言） | 0 | 0 | `No issues found!`（6.1s） | **`+2876 ~66`** | 0 | `[]` |
| `review-v2-keysync2`（第 2 轮连续第二次） | 0 | 0 | `No issues found!`（5.7s） | **`+2876 ~66`** | 0 | `[]` |
| `review-v2-keysync3`（隔离变异逐字还原后复核） | 0 | 0 | `No issues found!`（4.8s） | **`+2876 ~66`** | 0 | `[]` |
| `review-v2-close1`（第 3 轮：退役契约 + 清死码 + 两处加固） | 0 | 0 | 见 §9 | 见 §9 | 0 | `[]` |
| `review-v2-close2`（第 3 轮连续第二次） | 0 | 0 | `No issues found!`（5.9s） | **`+2846 ~66`** | 0 | `[]` |
| `review-v2-mut1`（第 4 轮：变异驱动补断言 + 分层门禁） | 0 | 0 | `No issues found!`（5.0s） | **`+2850 ~66`** | 0 | `[]` |
| `review-v2-mut2`（第 4 轮连续第二次） | 0 | 0 | `No issues found!`（3.1s） | **`+2850 ~66`** | 0 | `[]` |

### 2.1 `review-v2-final3` 的失败：环境 OOM，非代码

`final3` 出现 60+ 条 `did not complete`，日志里 **`dart/runtime/vm/zone.cc: 95: error: Out of memory`**
与 `Crash occurred when compiling … in optimizing JIT mode`——是 **Dart VM 在编译期耗尽内存**，
不是断言失败（失败清单里没有一条是 `expect` 不成立）。同时刻宿主空闲内存仅 3.22 GB，
自有 AVD（1.5 GB）+ 三个 Gradle daemon（约 3.4 GB）+ 构建缓存占满了内存。

处置（与仓库历史同款纪律，`docs/41`/`STATUS` 均有先例）：
1. `adb -s emulator-5554 emu kill`（只关自有 AVD；5558/5566 属其它项目，**未触碰**）；
2. `flutter clean` + 停 Gradle daemon，空闲内存回到 4.82 GB；
3. **不改任何代码**重跑两次：`final4`、`final5` 均 `+2870 ~66`、exit 0、`changed_during_run: []`。

⇒ 收敛判据 ④ 的「连续两次绿」由 **`review-v2-final4` + `review-v2-final5`** 满足（同一份源码、
同一轮内、中间无改动）；`final3` 记为**运行器环境故障**（OOM），不计入代码结论，也不隐藏。

- 测试数净增 **+1**（新增的同名食物区分用例），**无删除、无 skip、无放宽**；
- `~66` 为无凭据跳过的 live 用例（与基线同数）；
- 两次日志路径：`E:/AI/Zcode/tmp/localfit-round7-native-20261014/logs/review-v2-{fix1,final}.{log,json}`。

## 3. 指标对比（基线 vs 本轮）

| 指标 | 基线 | 本轮 | 变化 |
|---|---|---|---|
| 今日页 `watchForDate` | 15 ms（`docs/50`） | 17 ms | +13%（单次测量抖动；同一测试内多次运行 15–17 ms，未超 10% 判定线所需的三次取中位——见下注） |
| 500 行食物搜索 | — | 4 ms | — |
| 50k 行前缀搜索 | p95 25.57 ms | <100 ms（测试断言上限，实测未打印） | 无劣化证据 |
| 语义 p95 | 13.3 ms | 13.3 ms（未重跑，沿用稳态结论） | 持平 |
| PSS | 121 MB（`docs/50`，不同数据量） | 117 MB | −3.3% |
| APK arm64 | 39,130,089 B（vc2046） | 39,435,990 B（vc2050） | +0.78% |
| 冷启动（后续次） | 996 ms（清白库） | 1,414 ms（23,916 库 + 模型） | 数据量不同，不作劣化判定 |
| 测试数 | 2,869 | 2,870 | +1 |

> **注（诚实口径）**：今日页 17 ms 是**单次**运行读数，基线 15 ms 来自 `docs/50` 的另一次运行。
> 两者差异在测试运行器抖动范围内（同一测试的历史读数为 15–17 ms）。本轮**没有**为它做三次取中位，
> 故不宣称「无劣化」而是「无劣化证据 + 抖动范围内」。这是本轮指标口径的唯一弱点，已登记。

## 4. 同类变体扫描（P1 的横向扩散）

对 `grep -rn "kcal / 100g" lib` 的 4 处命中逐个人工判定：

| 落点 | 是否同类 | 处理 |
|---|---|---|
| `meal_editor_dialog.dart`（记录一餐搜索行） | 是 | 已修 |
| `scan_candidate_editor.dart`（拍照识餐本地食物行） | **是**（同为「选择一条食物」的动作） | **同轮修**（品牌进副标题），回归 8/8 绿 |
| `food_library_results.dart`（列表头单位文案） | 否 | 不改 |
| `text_fit.dart`（注释里的示例） | 否 | 不改 |

其他可能的同族：`FoodCard`（食物库列表）**故意不显示品牌**——docs/21 §3.11 明文规定
「卡上不再有品牌，退到详情弹层」，且食物库是**浏览**而非**选择**，不构成歧义风险。判定：不是同类缺陷。

## 5. 改动面重新审查

| 文件 | 改动 | 审查结论 |
|---|---|---|
| `lib/features/nutrition/presentation/meal_editor_dialog.dart` | `_FoodResultRow` 副标题与语义标签加品牌 | 纯呈现；无状态、无 IO、无契约；无品牌时文案逐字不变 |
| `lib/features/food_scan/presentation/scan_candidate_editor.dart` | `ListTile.subtitle` 加品牌前缀 | 同上；既有断言 `116 kcal / 100g`（夹具无品牌）不受影响 |
| `test/features/nutrition/nutrition_presentation_design_test.dart` | 新增 1 条用例 + `Value` import | 断言具体（文本 + 语义标签） |

改动面**只涉及 3 个文件**；无 schema / wire / CSV / 资产改动 ⇒ 不触发 decision-required。

## 6. 设备复验（重建 APK）

| 项 | 值 |
|---|---|
| 构建 | `flutter build apk --release --target-platform android-x64 --build-number 4051`，Gradle 53.1 s，exit 0 |
| 产物 | `release/localfit-ai-vc4051-20261022-universal-release.apk`（66,220,404 B，含 arm64-v8a / armeabi-v7a / x86_64） |
| sha256 | `764e50938b991ba0bb994765ffeb15eb9f37987d987fdc7f6e360108fb897677` |
| aapt2 | `versionCode='4051' versionName='0.1.0'`（`build-tools/36.0.0/aapt2.exe dump badging`） |
| 安装 | `adb install -r` Success；启动 `Status: ok`，`TotalTime 2361 ms` |
| 修复生效 | 设备搜索「米饭」三行带品牌（`ui/sheets/meal-search-brand-fixed.png`） |
| 崩溃/密钥 | logcat 末 400 行：`FATAL`/`AndroidRuntime` 0 条、`sk-` 0 条（`device/logcat-tail.txt`） |

> 旧 APK vc2050/vc4050 保留在 `release/` 不删（它们是本轮审查的基线产物）；新增 vc4051 是
> **仅含 P1 修复**的重建包。**未提交、未推送、未发布。**

## 7. 收敛判据逐条核对

| # | 判据 | 结果 |
|---|---|---|
| 1 | P0 = 0 未闭环 | **通过**（0 条 P0） |
| 2 | P1 = 0 未闭环 | **通过**（1 条 P1 已闭环，设备实帧） |
| 3 | 本轮新增 P0/P1 = 0 | **通过**（本轮审查未新增） |
| 4 | 门禁五项连续两次绿 | **通过**（第 1 轮 `final4` + `final5`；第 2 轮 `keysync` + `keysync2`，均 `+2876 ~66` / exit 0 / `[]`） |
| 5 | ≥12 项指标无劣化 >10% | **有条件通过**：15 项有数字；今日页 17 ms vs 15 ms 属抖动范围但未做三次取中位（已注）；其余持平或改善 |
| 6 | 设备 ≥10 类场景实帧 + APK 同源 | **通过**（12 类；vc4051 构建晚于全部源文件，aapt2 + sha256 已核，装上点开过） |
| 7 | P2 残留全部登记且有「接受/延后」 | **通过**（10 条 P2 接受/延后 + `RV2-P2-07` 已闭环 + 1 条 P3 加固项 `RV2-P3-01`） |
| 8 | docs/21 + STATUS + INDEX + 证据同步 | **通过**（本轮已更新；见 §8） |

**结论：两轮内收敛**（P0=0、P1 全闭环、P2 全部有结论、门禁连续两次绿、指标无条件劣化 >10%）。
第 2 轮（**2026-10-22 二次修订**）只做一件事：把 `RV2-P2-07` 彻底修掉——

- 对账器新增「附录 D 表格 **Key 列**」来源（`/` 合并、`-xxx` 简写补全、`-N` 占位归一化），
  并加**锚点断言**（解析器若退回「只认测试 Key 行」立刻红）；量级哨兵 `>100 → >150`；
- 6 条渲染/语义断言补进 `key_contract_test.dart`（空态/取消返回 false/关闭钮条件渲染/
  失败态不得永久 spinner/晋升后追问删除且真删）；
- 结果：**三方对账 338/338（100%）**，附录 D Key 列 **50/50**；`key_contract_test` 12/12；
  门禁 `review-v2-keysync` / `review-v2-keysync2` **`+2876 ~66` ×2**。

> **口径修订（必须留痕）**：第 1 轮报的「68/74（91.9%）」分母不严谨——它把附录 D **行为列**里的
> 类名/方法名、简写片段、合并写法都算成独立 Key。按「Key 列」这一真实契约重算是 **50 个 Key、
> 6 个缺口（44/50）**，修完 **50/50**。两次口径都写在 `docs/evidence/…/docs/key-sync.md` §0。

仍未跑（不因收敛而改变）：真实 AI 一轮（无 `LF_AI_LIVE_KEY`）、arm64 真机、
1000 行滚动帧率、10 个隔离变异。**不得**在对外表述里说成已完成。

## 7.1 第 2 轮新增的 6 条断言（逐条）

| Key | 断言的不只是"键存在" |
|---|---|
| `dish-meal-picker-empty` | 空态是可行动文案，且**不出现「暂无数据」** |
| `dish-meal-cancel` | 点取消返回 **false**（不是 null）且弹层关闭 |
| `retrieval-debug-close` | 有 `onClose` 才渲染、点击回调计数 +1；`null` 时**不渲染** |
| `training-retry` | 删表造真实查询失败 → 错误文案 + 重试钮 + **无 CircularProgressIndicator** |
| `canteen-directory-retry` | 同上（食堂目录） |
| `ai-memory-promote-delete` | 晋升成功后弹「顺便删掉这条记忆？」→ 点删除 → 列表回空态（真删） |

## 8. 文档同步清单

| 文档 | 动作 |
|---|---|
| `docs/52-review-report-v2.md` | 全文重写（结论 + A–P 逐维 + 台账 + 指标 + 未覆盖） |
| `docs/54-remediation-plan-v2.md` | 新建（P1 修复方案 + P2 逐条结论 + decision-required） |
| `docs/55-second-iteration-acceptance-v2.md` | 本文件（新建） |
| `docs/21-ui-redesign-spec.md` | 追加 as-built 备注：记餐搜索结果行的品牌规则（`RV2-P1-01` 修复形态） |
| `STATUS.md` | 顶部新增本轮横幅 |
| `docs/INDEX.md` | §1 登记 54 / 55 与证据目录 |
| `docs/evidence/2026-10-22-full-review-v2/` | `run-log.md` / `static/` / `code/` / `ui/` / `perf/` / `edges/` / `docs/` / `device/` |


---

## 9. 第 3 轮（2026-10-22 收尾批）：把「接受/延后」全部落到结论

用户在看完报告后裁决：**按推荐执行**。本轮做的是「把剩余 P2 从『登记』推到『有终局』」，
不是新审查。逐条结果：

| ID | 终局 | 本轮动作 |
|---|---|---|
| RV2-P2-01 | **已闭环（退役）** | 删 `DishGuidanceJsonDecoder` / `MealPairingJsonDecoder` / `DailyMenuPlanJsonDecoder` / `DishNutritionJsonDecoder`（4 文件）与 4 个专属测试文件；`docs/03` §9/§14/§15 加 as-built 横幅；`docs/21` 加 D12；对抗电池只保留 3 份**仍在链路上**的合同（**9/9 绿**） |
| RV2-P2-02 | **已闭环（2 删 + 4 平反）** | 删 `AiResponseContentExtractor`、`MetricCard` 与其专属测试；`LfTokensX` / `MealSlotIcons` / `MenuServiceWindow` / `OnboardingPersistence` **是活代码**（extension 成员按名调用：`context.lf` 335 处、`slot.icon`、`window.windowLabel`、`database.saveOnboardingProfile`）⇒ 纠正初版扫描的误判 |
| RV2-P2-05 | **证伪** | 新增 `nav_ai_label_inset_test`：320/360dp × 1.0×/2.0× 断言「AI 标签底边 ≤ 栏底 − 手势带」全绿；原帧是 `wm size/density` override 的测量假象 |
| RV2-P2-06 | **已闭环** | `RecordFab.contentClearance()` = max(navReserve, 手势带+96+50)；记录页末尾预留改用它；`record_fab_clearance_test` 3/3（含回退检测） |
| RV2-P2-08 | **已闭环（冻结 + 门禁）** | `ui_literal_budget_test`：颜色/字号存量钉成显式预算，业务页面新增即红；文件清空必须收窄白名单 |
| RV2-P3-01 | **已闭环** | `saveManualWeight` 拒绝未来日期且整笔不写；`measurement_future_date_test` 3/3（先红后绿） |
| RV2-P2-03 | **不做（明确理由）** | 解环需抽 domain 接口、改 20+ 文件，且本轮无法证明行为不变；不影响用户可见行为 ⇒ 风险与收益不成比例。第一步留给将来：先拆 `nutrition ↔ campus_menus` |
| RV2-P2-04 | **接受（用户裁决：不上屏）** | 不改代码 |
| RV2-P2-09 | **接受（不建议动）** | 首装一次性；改动会碰随包导入的幂等打标与「清空后重建」路径 |
| RV2-P2-10 | **接受（环境限制）** | 缺 `LF_AI_LIVE_KEY`；有 Key 时的执行命令已写进 `docs/54` |

### 9.1 本轮的删除面（必须留痕）

| 删除 | 原因 | 替代证据 |
|---|---|---|
| 4 个 AI 契约解码器 + 4 个测试文件 | 生产零调用（用户裁决退役） | 3 份在链路的合同仍有对抗电池 9/9；chat-edit 命令层承担输入约束 |
| `AiResponseContentExtractor` + 测试 | 生产走 `ai_protocol_wire.dart`，本类零调用 | `ai_protocol_wire` 既有测试全绿 |
| `MetricCard` | 零引用（页面用 `DesignCard` / `LfMetricGauge`） | 全仓 `grep` 0 命中 |

> 这是**功能退役**带来的断言减少，不是「为让门禁变绿而删断言」：被删的每条断言都只覆盖
> 已被删除的代码路径（删掉的类不存在了，断言无处可跑）。仍在链路上的同类保护一条未动。

### 9.2 本轮新增测试（8 条）

| 文件 | 条数 | 判据 |
|---|---|---|
| `test/features/ai/adversarial_json_battery_test.dart` | 9 | 3 份在链合同的越界/枚举/注入/形状攻击（重写后仍全绿） |
| `test/features/progress/measurement_future_date_test.dart` | 3 | 未来日期拒绝 + 整笔不写 + 今天/过去照常 |
| `test/app/design/record_fab_clearance_test.dart` | 3 | FAB 覆盖带预留（含退回检测） |
| `test/app/design/nav_ai_label_inset_test.dart` | 4 | AI 标签不越手势带（2 宽度 × 2 字号） |
| `test/app/design/ui_literal_budget_test.dart` | 2 | 颜色/字号字面量预算 |


---

## 10. 第 4 轮（2026-10-22 收尾二批）：变异驱动补强 + 分层门禁 + iOS 权限

本轮只做「不需要外部条件、且能机器验证」的剩余项。逐条：

### 10.1 10 个隔离变异：先跑出 5 个存活，再补到 0

第一遍结果（`tests/mutation.md` 的中间态）：

| 存活的变异 | 为什么存活（真实弱点） | 补法 |
|---|---|---|
| M02 分类 prepared 分支改判 | 测试用例 `raw: 'Plats préparés'` **匹配不到**关键词 `plat préparé`（单复数不同），走的是名称分支 ⇒ 分类关键词里的 prepared 分支零覆盖 | 补两条真正命中 `_preparedCategoryKeywords` 的用例（`Frozen foods` / `Sandwiches`） |
| M05 圆钮底距 96→80 | **我的测试用被测常量自证**（`expect(value, bottomOffset + footprint)`），改常量两边一起变 | 改成断言绝对数字 146 / 170 / ≥346 |
| M06 降级文案改短 | 原断言只查 `contains('语义')`，改短照样过 | 新增三条**逐字**文案断言（两个搜索格 + 低于阈值提示） |
| M08 语义阈值 0.45→0.50 | 阈值常量没有任何断言 | 新增「阈值 = 0.45（真模型标定值）」钉值 |
| M04 体重下限 35→30 | **变异脚本选错靶**（跑了未来日期测试而非 `measurement_repository_test`）——不是覆盖缺口 | 换靶文件 |

第二遍：**10/10 全部被抓，逐字节还原 sha256 全部一致**（`tests/mutation.md`）。
这把「测试质量」从「抽样看断言强度」升级为「10 个关键点位的真实杀伤力」。

### 10.2 分层门禁（RV2-P2-03 的可行解）

`test/app/architecture_layering_test.dart`：

- 跨 feature import **66 条现存边**锁死——新增即红（已用注入 `nutrition->backup` 验证）；
- `lib/core` 与 `lib/data` **不得** import `features`（实测都是 0 条，持续为 0）；
- 白名单只许收窄：某条边消失而未从白名单删掉，也红。

⇒ 「解环」仍是将来分批做的事，但**不会再恶化**，而且每拆一条白名单就必须减一行。

### 10.3 iOS 权限文案（`docs/52` §2.L 的遗留）

`ios/Runner/Info.plist` 补 `NSBluetoothAlwaysUsageDescription`（原文：只在你主动点「同步体重」时读取一次）。
缺它时 iOS 上蓝牙秤必然失败（代码会诚实显示「设备不支持」，但原因是权限字符串缺失，属配置缺陷）。
plist 已用 `xml.etree` 解析验证结构合法；**iOS 构建仍无法在本机验证**（如实登记）。

### 10.4 本轮门禁

`review-v2-mut1` / `mut2`：**`+2850 ~66`** ×2（`+2846` + 4 条新断言），
format 0 / analyze `No issues found!` / exit 0 / `changed_during_run: []`。

---

## 11. 追加验收：用户需求批次 1–3（2026-10-22/23）

### 11.1 门禁

| 标签 | 结果 |
|---|---|
| `review-v2-batch4`（批次 1+2） | `+2846 ~66` 全绿 |
| `review-v2-batch7`（批次 3） | **`+2849 ~66` 全绿**；format lib/test 0 改动 / analyze `No issues found!` / exit 0 / `changed_during_run: []` |

`batch5`/`batch6` 的失败**全部是本批语义变更的断言未同步**，逐条修实（不放宽）：
清除所有数据保留内置食物（3 个文件）、编辑卡分组头在 250dp/2.0× 溢出 57px（改 `Wrap`）、
`dart format` 漏跑（按 lib/test 分别跑）。

### 11.2 先红后绿 / 隔离变异（本批）

| 项 | RED 证据 | 变异验证 |
|---|---|---|
| 菜品删除（RV3-P1-01） | 新增嵌套导航器用例在改回页面 context 后 RED：`Found 0 widgets with type "MenuTabView"` | 变异即上条；还原后 sha256 与变异前逐字节一致（`a92b9ec3…4f12`） |
| 营养达标口径（RV3-P1-02） | 旧断言（`hitCount` 要求 `[min,max]`）在新口径下失败，逐条改写为新事实 + 新增低于下限用例 | — |
| AI 去重（RV3-P1-03） | `chat_edit_executor_test` 新增用例先断言「两条主记录 + 米饭 1 份」，旧实现下 `meal.create` 会写 2 条主记录 | — |
| 编辑卡分组 | 窄气泡用例（既有）在分组头 `Row` 下 RED（溢出 57px）→ 改 `Wrap` 后绿 | — |

### 11.3 指标（不劣化声明）

本批未新增性能预算面；`build_calorie_trend` 的口径变化只影响**计数语义**（字段名与算法复杂度不变），
`query_benchmark` / `catalog_search_perf` 等既有性能用例在 `batch7` 全量里未变慢（同一门禁耗时
81.9 s → 80.4 s）。AI 上下文新增的段落为**零**（只改协议文字与执行器逻辑），快照装配时长不变。

### 11.4 设备与产物

- APK（**最新**：`--build-number 2058 --split-per-abi`，aapt2 核对）：arm64 **4058**
  39,435,126 B sha256 `ff99d93f34b80a733b10c6efaa0982e901b2418d4e434a2d7ad374fd6dcddf42`；
  arm32 **3058** 37,885,858 B `45358aaf…2cc7`；x86_64 **6058** 41,785,064 B `6b3cc338…c957`。
- 门禁（最终复核态）：`review-v2-final-check` / `final-check2` **`+2855 ~66`** ×2 全绿。
- 门禁（合并批次最终态）：`review-v2-merge9` **`+2855 ~66`** 全绿（含回复清洗 6 条 + 升级补齐 1 条断言）。
- 与上一轮 arm64 4053 单调递增（可直接覆盖安装）；`dist/SHA256SUMS.txt` 与 `dist/index.html` 同步。
- **本批未做设备实帧走查**（如实）：改动集中在页面内部逻辑与文案，且用户的主诉是「用手机上的旧包」；
  安装/升级路径由 versionCode 单调性保证，实帧走查登记为**下一批**（若用户需要）。

### 11.5 剩余限制（如实）

1. **真实 AI 未跑**：`LF_AI_LIVE_KEY` 不在本会话环境（沿用 `docs/52` §5 的限制）。
   本批新增的协议规则 13、建议气泡与去重逻辑都只经契约/mock 验证。
2. **拍照识餐页无 UI 入口**（RV3-P3-01，登记项）。
3. **「单独配置的模型」未落成独立设置项**：建议气泡复用对话服务实例，页面留了
   `suggestionService` 注入点；要在设置页配第二个模型需新增设置项（未做）。
4. `android/local.properties` 在 `flutter build` 时被工具改写（本地 SDK 路径，构建副产物）。

### 11.6 追加验收（2026-10-24）：食堂目录与菜品库合并

- **门禁**：`review-v2-merge2` → **`+2848 ~66`** 全绿（format lib/test 0 改动 /
  analyze `No issues found!` / exit 0 / `changed_during_run: []`）。
  `merge1` 唯一失败是 `dart format` 漏跑（按 lib/test 分别跑即绿）。
- **先红后绿 / 隔离变异**：新用例 `canteen_dish_library_sync_test.dart` 在**不注入
  钩子**（即改动前的接线）时 RED（库里 0 行）——`main.dart` 的钩子接线就是这条
  功能的开关，测试用与 `main.dart` 同构的装配（`late final` 服务 + 仓储钩子），
  接线断了会自动同步消失，用例当场变红。
- **测试净变化**：删 2 个文件（`canteen_add_to_library_test.dart`、
  `food_cleanup_page_test.dart`）+ 3 处用例（food_maintenance / settings_page /
  key_contract），新增 1 个文件 12 条 → 总数 `+2849` → `+2848`。
- **产物**：APK vc4058（见上），`dist/` 与共享页已更新。
- **最终复核（2026-10-24）**：① 用户需求逐条核对全绿（`docs/52` §7/§7.1 台账）；
  ② 重复入口扫描：食堂目录只有一个 push（菜单页 list-link）、AI 训练入口只剩 FAB 模式弹层、
  食物数据弹层是一个组件两个入口（标题不同、Key 相同，`docs/31` S5 既定）、
  推荐三处表面角色不同（菜单整套卡 / 记录页下一餐详情 / 今日页预算卡）——**无重复功能**；
  ③ 死代码：删 5 个零引用公共符号（RV3-P3-03），4 个 extension 经成员名复核为活代码；
  ④ 新 bug 扫描抓到并修掉 1 条自伤（RV3-P2-08 `userEdited` 被自动同步清零）+ 1 条文案指路不准
  + 1 处文档滞留（RV3-P3-04）。
