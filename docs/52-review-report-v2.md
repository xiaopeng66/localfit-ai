# 全应用审查报告 v2

日期：2026-10-22 ｜ 状态：**审查 + 报告 + 修复计划 + 修复 + 验证 + 二次复核（第 1 轮）已完成**
计划：[`docs/51`](51-comprehensive-review-plan-v2.md) ｜ 修复计划：[`docs/54`](54-remediation-plan-v2.md) ｜
二次验收：[`docs/55`](55-second-iteration-acceptance-v2.md) ｜ 证据：`docs/evidence/2026-10-22-full-review-v2/`

---

## 0. 结论

**能用（有条件）。P0 = 0；P1 = 1 已闭环（RV2-P1-01，设备实帧复验）；P2 11 条：7 条已闭环 / 1 条证伪 / 3 条接受；P3 1 条已闭环；门禁连续两次绿（`+2876 ~66`）；12 项指标无一劣化 >10%；设备 12 类场景有实帧。**

三个关键事实（按对用户的影响排序）：

1. **同名食物的记餐歧义（P1，已修）**：真实库 23,916 条里「米饭」有四条（116 / 156 / 181 / 338 kcal，
   分属无品牌 / 叮咚 / 松屋 / 千丰香米）。「记录一餐」的搜索结果行**只印名称 + 热量**，四条几乎一样，
   点错就把 338 kcal 记成 116 kcal——**静默记错营养**，符合 P1「结果错误且用户无法察觉」。
   已修：品牌进结果行（有品牌时 `品牌 · 热量`），并把读屏标签改成 `添加 米饭（千丰香米）`；
   同类变体（拍照识餐的本地食物选择行）同轮修复。先红后绿。
2. **AI 结构化契约的解码器成了孤儿（P2）**：`DishGuidanceJsonDecoder` / `MealPairingJsonDecoder` /
   `DailyMenuPlanJsonDecoder` / `DishNutritionJsonDecoder` 在 `lib/` 内**零调用**，只被测试引用。
   原因：AI 创作六卡已改成「拼启动提示词 → 切对话」，`docs/03` §9/§14/§15 的三份契约不再有消费面。
   **不删**（删要连带删 4 组断言，且契约仍是产品资产）→ 登记，交裁决是否正式退役。
3. **docs/21 附录 D1–D9 的 Key 不在对账测试扫描面内（P2，已闭环）**：`ui_spec_key_sync_test`
   原本只解析含「测试 Key」字样的行，附录 D1–D9 是表格行 ⇒ 6 个 Key 有 UI、无断言。
   **已彻底修复**：① 对账器新增「附录 D 表格 Key 列」来源（含 `/` 合并与 `-xxx` 简写补全、
   `-N` 占位归一化），并加锚点断言保证「附录 D 被扫到」本身受机器监视；
   ② 6 条渲染断言补进 `key_contract_test.dart`（含失败态与「取消必须返回 false」的语义断言）。
   现在**三方对账 338/338（100%）**，附录 D Key 列 50/50。
   > 口径修订：初版的「68/74」是把行为列类名、简写片段也算进分母的粗算；按「Key 列」这一真实契约，
   > 附录 D 是 50 个 Key、6 个缺口（44/50 → 50/50）。两次数字都留在 `docs/evidence/…/docs/key-sync.md`。

**未做（如实）**：真实 AI 一轮（`LF_AI_LIVE_KEY` 未在本会话环境里，按 `docs/53` §6 用契约/mock 替代，
不声称真机 AI 已验证）；arm64 真机；1000 行滚动帧率采样；iOS 构建。

---

## 1. 基线与执行方式

| 项 | 值 |
|---|---|
| 代码规模 | `lib/` **382** 个 dart 文件、**140,458** 行；`test/` **380** 个文件（377 个 `*_test.dart`） |
| 页面 | **18** 个 `*_page.dart`（17 条用户可达页 + `placeholder_feature_page.dart` 是共享组件，不是路由） |
| 顶层路由 | **15** 条 `AppRoutes` 常量 |
| 弹层 | **17** 个 `*_sheet.dart` / `*_dialog.dart`（+ `app_sheet.dart` 是宿主基础设施） |
| 设计系统 | **52** 个共享 widget（`lib/app/design/widgets`） |
| 数据 | schema **30**；`foods` 13 列；`food_aliases` 有写路径 |
| 食物库 | **23,916** 条（10 列 CSV；别名 6,711 行）——清空后重导入实测仍是 23,916 |
| AI | 命令注册表 **37** 条（`grep -c` = 37） |
| 门禁基线 | `review-v2-baseline`：format 0 / analyze `No issues found!` / **`+2869 ~66`** / exit 0 / `changed_during_run: []` |
| APK 基线 | vc2050 arm64 `f93e6086…13da`（39,435,990 B）/ vc4050 x86_64 `fcc622c1…10ba`（41,783,084 B） |
| 设备 | 自有 AVD `LocalFit_API35`（emulator-5554）；**未触碰** 5558 / 5566 |
| 执行方式 | 连续执行；中间只写 `run-log.md`；最终一次性交付 |

---

## 2. 维度 A–P 逐维结论

### A 界面视觉

**做过的**：17 个页面全部进入（含引导页，通过「清除所有数据」重建路径拿到）；17 个弹层逐层打开截图 +
`uiautomator dump` 取 bounds；尺寸矩阵 4 页 × {320dp / 1.3× / 2.0× / 深色 / 横屏} = 20 帧；
另有食堂目录、动作库、AI 创作、AI 记忆、搜索调试、整理重复菜品、下一餐推荐、编辑资料等页面的实帧。
证据：`ui/<page>/*.png|xml`、`ui/sheets/*.png`。

**结论**：布局一致性总体成立——卡片圆角/内衬/间距来自 token，页左右 padding 一致，食卡是文档规定的
单行三件（图标 40 / 名称 / 环 36），弹层动作行统一「取消左、主操作右」，主按钮唯一，危险操作
（清除所有数据 / 删除菜品）用红色且**要二次确认**（清空数据还要**手输「全部清除」**）。
无 RenderFlex overflow（20 帧 dump 扫描 0 命中）。

**两个 P2**：320dp 下底部中央「AI」标签与手势条重叠（`RV2-P2-05`）；2.0× 下记录页的
「还可摄入 2,048 kcal」被中央 FAB 压住（`RV2-P2-06`）。两处都在 2.0×/320dp 边缘档，正常档不受影响。

### B 交互与手势

**做过的**：逐屏点按走查（每个可点元素至少点一次，含 tab / chip / 卡 / 图标钮 / 弹层动作）；
返回键行为（弹层先关、页面后回）；双击/连点由既有 900ms 冷却 + 在途锁覆盖（`add-to-meal` 等写按钮
有 `_inFlight`；`ai_live` 与 widget 测试各有一批反重入断言）。

**结论**：可达性成立；写按钮的重复提交防护在既有测试里有机器判据（`food_scan` 连点 9 次不重入、
加入餐 800→200 kcal 的单次写入回归）。未发现新的手势冲突（无横滑删除、无长按多选）。

### C 功能逻辑闭环（写路径）

逐条核对 14 类写路径（入口 / 校验 / 写入 / 成功反馈 / 失败分支 / 重试 / 撤销 / 多入口同步）：

| # | 写路径 | 结论 |
|---|---|---|
| 1 | 建档 / 编辑资料 / 目标 | 通过。引导页必填校验「请填写年龄/身高/当前体重」实测触发；目标范围弹层确认后今日页目标随之变（2,048 → 1,844 kcal） |
| 2 | 记一餐（按食材 / 按菜品 / 扫描 / AI） | 通过。两个入口都是真实弹层（`meal-entry-kind`），共用一个 `MealRepository.create`；**P1 歧义已修** |
| 3 | 编辑 / 删除餐次 | 通过（既有 `meal_history` + `meal_editor` 断言；本轮确认入口可达） |
| 4 | 新建 / 编辑 / 删除食物（别名 / 分类 / 名称格式） | 通过。`new-food` 弹层含别名栏（`new-food-aliases`）；分类只十档 |
| 5 | CSV 导入（预览 / 跳过 / 全导 / 坏行 / 表外分类） | 通过（`food_import_preview_sheet` 可达；导入器单事务 + 分类硬门禁，既有 `importer_smoke` 覆盖 23,919 行） |
| 6 | 清空内置食物 / 清空全部数据 | **通过且实测**。清空后重导入 23,916 条，档案/餐食/菜单全清 |
| 7 | 备份导出 / 恢复 | 通过（弹层可达；`backup_table_registry` 含旧包缺列补默认值，既有测试） |
| 8 | 饮水 / 体重 / 步数 | 通过。饮水弹层 +250/350/500；体重空值提交被拦并显示「请输入有效体重」 |
| 9 | 训练：计划创建 / 编辑 / 开始 / 记组 / 结束 / 删除 | 通过。手动创建 → 选周一 →「添加动作」→ `planned-entry` 弹层可达；AI 计划表单（天数 + 目标描述 + 披露）可达 |
| 10 | 菜单：导入 / 发布 / 编辑 / 删除 / 匹配食物 | 通过。食堂目录建 地点→窗口→菜品 全链路实测；建菜命中食物库出「参考食物库」三选一（实测匹配分 0.95） |
| 11 | 菜品库：新建 / 编辑 / 删除 / 同步来源 | 通过。改名/删除/手动营养三个弹层可达；删除需二次确认 |
| 12 | 记忆：新增 / 改口 / 归档 / 待确认 / 整理合并 | 通过。记忆页开关、待确认 0 条、整理建议、按日期回看、清空全可达 |
| 13 | AI 命令 37 条 | 契约层 37/37 有失败分支断言（脚本扫描，`missing: []`）；**真模型未跑**（见 §5） |
| 14 | 设置项（每个开关 / 下拉真的写库并生效） | 通过。协议下拉 3 档、推理档、自动备份开关、记忆注入开关均写库；自动备份开关实测可切 |

### D 状态一致性与并发

- **单一事实源**：今日摄入/目标/体重/水量各自只有一个写入口（`MealRepository` / `TargetsRepository` /
  `MeasurementRepository` / `WaterRepository`），页面只订阅 Drift 流。
- **多入口同步**：清空数据后所有页面同步归零；`watchAll` 在 build 里的闭环是历史缺陷，已由
  「流缓存 + 值相等才 setState」修掉（`docs/41` 记录，`menu_staleness_ui_test` 钉住）。
- **幂等**：随包导入、归一化（`food_library_normalized_v1`）、索引重建都是打标/幂等；清空后重导入
  实测 23,916（未翻倍）。
- **竞态**：搜索 future 在改克数时**不重建**（既有断言「改克数不得重建搜索 future」，本轮复跑绿）。
- **跨零点**：日期是本地日期字符串；设备时区 GMT、跨日切换实测今日页日期从 10/21 走到 10/22 正常。
- 未发现新的竞态或重复写。

### E AI 适配性与可用性

**结构**：37 条命令的注册表是单一事实源（decoder 校验 + executor 分发 + `renderProtocol()` 渲染）。
协议三档（Chat Completions / Responses / Anthropic Messages）由同一套端点规范化；https + 443 强制。
「确认才写」不可绕过：所有命令都进编辑卡，点「应用」才落库。

**实测到的降级**（设备）：
- 未配置 AI → 发出后如实回「请先在设置中保存 AI 配置。」+「重试发送」（`ai_conversation/no-ai-configured.png`）；
- 非法 Base URL → 「Base URL 无效：需要 HTTPS 地址（如 https://api.example.com/v1）。」（`sheets/ai-config-probe-fail.png`）；
- 飞行模式 → 全本地功能照常（`dashboard/airplane.png`）。

**未跑**：真实模型一轮（无 `LF_AI_LIVE_KEY`）。上一会话在**同一个证据目录**留下的
`ai/host-live.log` 记 53 通过 / 1 失败（`ai_live_control_matrix` 的训练记组场景模型反问而不出信封），
**不作为本轮结论**，只作为「该环境中跑过」的事实登记；本条已转成 `AI-E-01` 观察项随本轮保留。

**P2**：三份结构化契约的解码器成孤儿（`RV2-P2-01`）；降级矩阵 20 格的 `notice` 只有「搜索」列
有一个真实消费者（`menu_dish_list.dart:515`），记忆注入/推荐/记餐三列的文案**没有上屏点**
（`RV2-P2-04`）——矩阵常量与测试都在，但「降级必须标注」在这三列只落在文档层。

### F 端上检索与推荐

- 三路融合（关键词 / 标签 / 语义）+ RRF + 软 boost ×1.05 + MMR，阈值 0.45（真模型标定值）。
- 语义不可用时**如实标注**并给原因：设备搜索调试面板实测显示「语义检索 可用 · 已索引 0 条 /
  本轮语义名次：未参与 / 未参与原因：索引 0 新写 / 0 复用」（`ui/retrieval_debug/default.png`）——
  这是**空库下的正确行为**，不是缺陷。
- 50k 行 CJK 前缀搜索 <100 ms（测试约束）；500 行库 4 ms。
- 短名单 ≤30 条按窗口分组；口味向量 <10 餐不参与、30 天窗口、只软 boost。

### G 底层运行逻辑与使用习惯

| 检查项 | 结论 |
|---|---|
| 启动顺序 | 首帧后跑后台导入/归一化/索引；清空后重导入 23,916 条不阻塞 UI |
| 权限时机 | 步数/体重秤只在用户点行时申请；未授权显示「未授权」且可继续手记 |
| 保存语义 | 表单失败不关窗（体重空值、引导必填、窗口名必填实测都在窗内报错） |
| 返回与层级 | 弹层先关；二级页 ≤3 次返回回主 tab（实测） |
| 默认值 | 记录弹层默认早餐；新建计划默认 3 天；引导默认女性/轻度活动 |
| 空态引导 | 食物库空态给「导入食物数据」；食堂空态给「添加地点」；训练空态给「新建计划」 |
| 离线 | 除 AI 全可用（飞行模式实测） |
| 跨零点 | 本地日期字符串，跨日实测正常 |
| 文案语感 | 第二人称、动词开头，无「亲」、不夸大 |

### H 数据与迁移

- schema 30；迁移链每步有存在性守卫（`IF EXISTS`）与幂等；`DROP COLUMN` 只在 29→30 一次。
- 旧备份恢复：注册表按表补默认值（`BackupTableSpec`），失败整单回滚（既有测试）。
- CSV 往返：10 列导出 → 原样导入 = 0 新增（`docs` 已记）；公式守卫一对互逆函数。
- 归一化幂等：KV `food_library_normalized_v1` 打标，重跑 0 更新。
- 悬空引用：`menu_sources→menu_snapshots` 两跳 cascade；`meal_items.food_id` 置空。
- 全清：数据库、媒体、KV、Secure Storage、缓存都清；清后随包库重建实测通过。

### I 错误与降级

- 5×4 = 20 格常量齐全，测试逐格钉住（`degradation_matrix_test` 绿）。
- 上屏文案实测 3 格（AI 未配置 / 非法 URL / 无网），都可行动。
- **P2**：见 §E —— 三列的 notice 无消费者。

### J 性能

15 项数字见 `perf/summary.md`。要点：今日页 17 ms、搜索 4 ms（500 行）/ <100 ms（50k）、
语义 p95 13.3 ms、PSS 117 MB、APK 37.6 MB（arm64）、冷启动后续 1,414 ms。
**无一劣化 >10%**；唯一边缘项是**安装后首次**冷启动 4,016 ms（含首次建库 + 随包导入），
超 2,500 ms 门槛，登记 `RV2-P2-09`（仅首装一次，第二次起 1.4 s）。

### K 无障碍与适配

- 图标按钮带语义（`Semantics(button:true,label:…)`）：实测 dump 里「添加体重」「记录早餐」
  「查看体重记录」「步数，未授权，点击申请」都有 content-desc。
- 图表有文字替代：体重图 dump 出「体重图：本周 7 天里 1 天有记录，最新 70.0 公斤（四），比三的 70.0 公斤持平 0.0 公斤」。
- 字号 1.3× / 2.0×：四页无 overflow；2.0× 下 FAB 压字（P2，见 A）。
- 触控目标：弹层动作钮 46–48 高、列表行 ≥48、图标钮命中盒 44+。
- 横屏：可用、不崩。

### L 隐私与安全

- 出网面只有 AI 出口（+ 可选目录下载）；`privacy_statement_audit_test` 与「生产代码不构造 PrivacyLogger」绿。
- Key 只在 secure storage；DB/备份/CSV/日志/截图零出现（本轮截图里 Key 输入框只显示圆点）。
- 权限最小化（6 个 Android 权限都有对应功能）；SQLCipher 开启（`cipher_version` fail-closed）。
- 随包数据许可：`assets/seed` 只有审计过的动作库 + 用户食物库，sha256 对得上（测试绿）。

### M 代码健康

详见 `code/code-health.md`。要点：analyze 0 问题、TODO 0 条、同名重复实现 0 个、
零使用符号 6 个（`RV2-P2-02`）、契约孤儿 4 个（`RV2-P2-01`）、跨 feature import 68 条含 7 组双向环
（`RV2-P2-03`）、UI 字面量 12 个颜色 + 5 个字号在源文件外（`RV2-P2-08`）。

### N 测试质量

- 377 个 `*_test.dart`，门禁 `+2869`；`~66` 是**无凭据时跳过的 live 测试**（`ai_live` 5 个文件 +
  `test/live` 2 个 + `catalog_real_scale` + `round7_component_capture`），跳过原因都是「缺环境变量」，
  逐条可见（`skip:` 全部带 reason）。
- 断言强度抽查 60 条：绝大多数断言具体文案/几何/键（不是「不抛异常」）。本轮新增的 P1 回归
  断言文案与语义标签两层。
- 变异：本轮只做了一个自然变异（把品牌行去掉 → 新测试红；加回 → 绿）。
  10 个隔离变异**未做**，登记为 not run。
- flaky：`readInto failed` 历史偶发（单跑绿）；本轮门禁两次无 flaky。

### O 文档一致性

详见 `docs/key-sync.md`。**三方对账 338/338（100%）**：§5 主表 + 附录 D10 批量行 + 附录 D1–D9 的
表格 **Key 列**（2026-10-22 修订：对账器新增 Key 列解析、`/` 合并与 `-xxx` 简写补全、`-N` 占位归一化，
并加锚点断言）。附录 D Key 列 50/50（2 个运行时拼接键有渲染断言兜底）。
6 个历史缺口（`RV2-P2-07`）已全部补上渲染/语义断言。
`docs/03` §9/§14/§15 的三份契约与实现不一致（解码器无消费面），登记 `RV2-P2-01`。

### P 构建与发布

- 门禁五项：见 §4。
- APK 与源码同源：`release/` 里 vc2050/vc4050 两个包 + sha256 文件；
  aapt2 版本号历史已核（本次未重建 APK，故无新 sha256）。
- **每个 release 包必须装上点开一次**：本轮把 vc4050 装进自有 AVD 并点开（启动无崩溃）。

---

## 3. 缺陷台账

| ID | 维度 | 严重度 | 标题 | 证据 | 状态 |
|---|---|---|---|---|---|
| **RV2-P1-01** | C / A | **P1** | 「记录一餐」搜索结果对同名不同品牌的食物不可区分（米饭 116/156/181/338 kcal），点错即静默记错营养 | 设备帧 `ui/sheets/meal-search-results.png`（三行同名、无品牌）；测试 `nutrition_presentation_design_test.dart` 新增用例 | **已修**（先红后绿；同类变体 `scan_candidate_editor.dart` 同轮修） |
| RV2-P2-01 | M / O | P2 | 四份 AI 结构化契约解码器（dish-guidance / meal-pairing / daily-menu-plan / dish-nutrition）在 `lib/` 零调用，只被测试引用 | `code/dead-code.md` B 段；`grep` 计数 0 | **已闭环（2026-10-22 用户裁决「执行」）**：4 个解码器与 4 个专属测试文件已删；`docs/03` §9/§14/§15 加 as-built 退役横幅、`docs/21` D12 说明现行走 chat-edit 命令层；对抗电池改为只测 3 份**仍在链路里**的合同（9/9 绿） |
| RV2-P2-02 | M | P2 | 零使用符号清单（初版 6 个） | `code/code-health.md` §1 | **已闭环 + 一处自我纠正**：真死代码只有 2 个（`AiResponseContentExtractor`、`MetricCard`，含其专属测试）→ **已删**；另外 4 个（`LfTokensX`、`MealSlotIcons`、`MenuServiceWindow`、`OnboardingPersistence`）是 **extension**，成员按名字调用（`context.lf` 用了 **335** 处、`slot.icon`、`window.windowLabel`、`database.saveOnboardingProfile`）⇒ 初版扫描按「extension 名是否出现」判定，**误判**。已在 `code/code-health.md` 更正 |
| RV2-P2-03 | M | P2 | feature 之间 66 条 import、7 组双向环，未达「core→data→feature 单向」 | `code/feature-imports.md`、`code/deps.dot` | **已闭环（冻结 + 分层门禁）**：解环重构仍按推荐不做（无法证明行为不变），改为 `test/app/architecture_layering_test.dart` ① 锁死 66 条现存边（新增跨 feature import 即红）② `lib/core`/`lib/data` 不得 import `features`（当前 0 条，持续为 0）③ 白名单只许收窄（边消失而未删白名单也红）。已用「人为注入 `nutrition->backup`」验证门禁会红，还原 sha256 一致 |
| RV2-P2-04 | I / E | P2 | 降级矩阵 20 格的 notice 只有「搜索」列有消费者；记忆注入/推荐/记餐三列文案不上屏 | `degradation_matrix.dart:59–135`；全仓只有 `menu_dish_list.dart:515` 引用 | **接受（用户裁决 2026-10-22：不上屏）**，不再重提 |
| RV2-P2-05 | A / K | P2 | 320dp 宽下底部中央「AI」标签疑似与系统手势条重叠 | `ui/dashboard/size320true.png` | **证伪（测量假象）**：新增 `test/app/design/nav_ai_label_inset_test.dart`，在 320/360dp × 1.0×/2.0× 四种组合下断言「标签底边 ≤ 栏底 − 手势带」全绿；该帧来自 `wm size/density` override（系统 inset 未随 dp 换算），非真机缺陷。判据已入测试防复发 |
| RV2-P2-06 | A / K | P2 | 2.0× 字号下记录页「还可摄入 X kcal」被中央 FAB 压住 | `ui/nutrition/font20.png` | **已闭环**：`RecordFab.contentClearance()` = max(navReserve, 手势带+96+50)，记录页末尾 SliverPadding 改用它 ⇒ 内容可滚出圆钮覆盖带；`record_fab_clearance_test` 3/3（含「退回裸 navReserve 必须红」的回退检测） |
| RV2-P2-07 | O | P2 | docs/21 附录 D1–D9 的 6 个 Key 有 UI 无断言：`ai-memory-promote-delete`、`canteen-directory-retry`、`dish-meal-cancel`、`dish-meal-picker-empty`、`retrieval-debug-close`、`training-retry` | `docs/key-sync.md` §2 | **已闭环**：对账器改为读附录 D 的 Key 列（含简写补全 + 锚点断言），6 条渲染/语义断言补进 `key_contract_test.dart`；对账 **338/338**，12/12 绿 |
| RV2-P2-08 | A / M | P2 | UI 字面量漂移：12 个 `Color(0x…)`、5 个源文件外的 `fontSize`、36 处数字 `EdgeInsets` | `code/ui-literals.md` | **已闭环（冻结 + 门禁）**：逐处 token 化等于重画 UI（无逐帧复核会引入视觉漂移）⇒ 改为把存量钉成**显式预算白名单**并禁止新增（`test/app/design/ui_literal_budget_test.dart`：业务页面新增任何 `Color(0x…)`/`fontSize:` 立刻红；文件已清空时必须同步收窄白名单，防「白名单腐烂」）。36 处 `EdgeInsets` 未纳入（多为 4/8/12/16 的 token 等值，机械替换无收益） |
| RV2-P2-09 | J / G | P2 | 安装后首次冷启动 4,016 ms，超 2,500 ms 门槛（含首次建库 + 随包导入）；第二次起 1,358/1,414 ms | `perf/summary.md` §1 | 接受（仅首装一次，已注口径） |
| RV2-P2-10 | N | P2 | 无凭据时 66 条 live 测试跳过（`~66`），真模型覆盖缺失 | 门禁输出 `+2869 ~66` | 接受（缺凭据，不可推断） |
| RV2-P2-11 | N | P2 | 测试强度未被验证：断言可能只查「包含某词」，常量改动可存活 | `tests/mutation.md` | **已闭环**：10 个隔离变异先跑出 **5 个存活**（M02 分类分支无覆盖、M04 选错靶、M05 用被测常量自证、M06 文案只查包含、M08 阈值无断言）→ 补 5 处断言 → **0 存活 / 10**，逐字节还原 sha256 全一致 |
| RV2-P3-01 | H / K | P3 | 未来日期在**仓储 API 层**无拒绝（UI 入口已被体重日期选择器的 `lastDate: today` 挡住） | `edges/summary.md` #19 | **已闭环**：`saveManualWeight` 加「晚于本机今天一律拒绝、整笔不写」守卫；`measurement_future_date_test` 3/3（先红：2 条失败 → 后绿） |
| AI-E-01 | E | 观察项 | 训练记组场景真模型倾向反问而不出信封（上一会话同目录日志，非本轮跑） | `ai/host-live.log`（历史） | 记录（不升 P1：App 行为正确，缺信封即无动作、不静默写） |

**P0 = 0。**

---

## 4. 门禁与指标

| 项 | 值 |
|---|---|
| `review-v2-baseline` | format lib 0 / test 0 · analyze `No issues found!` · `+2869 ~66` · exit 0 · `changed_during_run: []` |
| `review-v2-fix1` | `+2870 ~66` · exit 0 · `[]`（修复后第 1 次） |
| `review-v2-final2` | `+2870 ~66` · exit 0 · `[]`（文档同步后） |
| `review-v2-final3` | **exit 1**：Dart VM `zone.cc: Out of memory`，60+ `did not complete`（非断言失败）——环境 OOM，详见 `docs/55` §2.1 |
| `review-v2-final4` / `review-v2-final5` | **`+2870 ~66` ×2 · exit 0 · `[]`**（释放内存后连续两次绿；收敛判据 ④ 以此为准） |
| 指标 | 15 项，见 `perf/summary.md`；无一项劣化 >10% |
| 覆盖 | 页面 17/17、弹层 17/17、写路径 14/14 类、命令 37/37（契约层）、降级 20/20 格（常量+测试）、边界 32 条、设备 12 类、代码健康全量、Key **338/338（100%）** |

---

## 5. 未覆盖 / not run（如实）

| 项 | 原因 | 替代证据 |
|---|---|---|
| 真实 AI 一轮（Host `test/ai_live` 5 文件） | `LF_AI_LIVE_KEY/BASE/MODEL` 不在本会话环境；凭据不可推断 | 契约/mock 层全绿 + 设备侧三条降级路径实帧；上一会话同目录日志登记为历史事实 |
| 设备侧真实对话 / 写库命令 / 配置探针成功路径 | 同上（无 Key） | 未配置与非法 URL 两条失败路径已实帧 |
| arm64 真机安装升级 | 无实体设备 | x86_64 AVD 实测 |
| 1000 行滚动帧率 | 未用 `--profile` 采样 | 进程内 DB/搜索基准 |
| 10 个隔离变异 | 时间盒；只做了 1 个自然变异 | 新增断言先红后绿 |
| iOS 构建 | 本机无法构建（计划内排除） | — |
| docs/21 附录 D1–D9 的 6 个 Key 断言 | 需 6 个独立 widget 夹具 | 清单与写法在 `docs/54` §P2 |

---

## 6. 与历史对账

- `docs/48`/`docs/50` 的 14 条 P1 + 3 条 P2 **未复发**：本轮复跑了
  `privacy_statement_audit_test`、`degradation_matrix_test`、`ui_spec_key_sync_test`、
  `query_benchmark_test`、`catalog_search_perf_test` 全绿；弹层被底栏遮挡（D8）在 17 个弹层实帧里未再出现。
- `docs/50` 的「1 条证伪」（`deleteVenue` cascade）结论不变。
- 历史 flaky（`readInto failed`）本轮未出现。

---

## 7. 追加台账：2026-10-22/23 用户需求批次 1–3（审查后新增面）

> 这三批不在 `docs/51` 的审查范围内（审查已收口：P0=0、P1 闭环、门禁两次绿）。
> 用户逐条提出新需求/缺陷，仍按同一纪律执行（RED 先行、隔离变异、全量门禁、证据落盘）。
> 台账从 `RV3-` 起编号，避免与 `RV2-` 混。

| ID | 级别 | 现象 | 根因 | 修法 | 判据 |
|---|---|---|---|---|---|
| RV3-P1-01 | P1 | 食堂菜品「删除」跳界面且删不掉（用户实报） | 删除确认弹层的按钮用**页面 context** `Navigator.pop`；`AppSheet` 走根导航器、食堂目录页挂在 shell 分支 ⇒ 弹掉的是目录页 | `Builder` 取弹层内 context（`canteen_delete_confirms.dart`）；同类两处同轮修（`profile_edit_page`、`onboarding_page`） | 新增**嵌套导航器**回归用例：改回 `context` 即 RED（`MenuTabView` 消失） |
| RV3-P1-02 | P1 | 营养分析卡「今日达标但 0/7」 | 目标区间是中心值 ±5%，达标原按 `[min,max]` 判：摄入在上限 95% 附近时达成率看着达标、达标天数仍 0 | 达标改按**未超上限**（`kcal <= calorieMax`）；新增 `belowMinCount` 与洞察「另有 N 天低于下限」；`_goalHitDays` / `goalDaysMet` 同口径 | `build_calorie_trend_test`（低于下限计入 + 超上限不计）、`nutrition_analysis_section_test`（洞察逐字）、`trend_calculator_test`、`nutrition_record_reactivity_test` |
| RV3-P1-03 | P1 | AI「加午餐后再加晚餐」把午餐条目重复计入 | `meal.create` 直接 `saveManualMeal`，无同日/同餐去重 | 同日同餐并入 + 跳过同名食物；新餐次按全天去重（跳过 N 条如实上屏） | `chat_edit_executor_test`：两条主记录、米饭只算一份、二次提议「没有重复写入」 |
| RV3-P1-04 | P1 | 「新建食材」已有同名仍失败 | `food.create` 遇重名直接 failed | 应用前查库：同名 1 条直接引用（未新建），多条才要求指定 | 同文件用例改判据（成功 + 「已直接引用」+ 库里仍 1 条） |
| RV3-P2-01 | P2 | 菜单页三餐是「分开」的三张卡 | 设计如此，用户要「一整套」 | 合并为一张 `DailyMealSetCard`（卡头「一整套」）；「其他已分析菜品」整块退场 | `menu_meal_recommendation_ui_test`（一张卡/三段/无 others）、`menu_page_structure_test`（几何改锚整套卡） |
| RV3-P2-02 | P2 | 手动营养四值缺单位/说明 | 标签只有 `热量 kcal` 等，无 per-100g 口径说明 | 保留单位标签 + `manual-nutrition-hint`「每 100 克、保存后不会被 AI 覆盖」 | `manual_nutrition_sheet_test` 新增单位与说明用例 |
| RV3-P2-03 | P2 | 导入食物被算「自建」；全清会删内置食物 | `createMany` 落 `isUserCreated=true`；`clear()` 无差别清空所有表 | 导入行落**内置**（`source='import'`）；`clear()` 只删自建食物并让食物五表跳过兜底循环；恢复前 `clearDatabaseRowsOnly` 仍全清 | `bundled_user_food_importer_test` / `food_csv_importer_test` / `food_repository_test` / `clear_all_local_data_test` / `export_restore_test` / `settings_backup_test` 同步改判 + docs/03、docs/08、docs/21 |
| RV3-P2-04 | P2 | 对话页副标题冗余、两个 AI 按钮常灰、底部「拍照识别」无用 | 设计遗留 | 删副标题；按钮恒可点（回复中先 `cancel()` 再结算）；chip 换「确认应用」；复制提示 4s→1.2s | `ai_conversation_page_test`（副题 findsNothing、apply chip、behaviour）、`conversation_widgets_test`（三枚等宽 + 枚举） |
| RV3-P2-05 | P2 | 编辑卡不能按类单独应用；「忽略」语义不明 | 只有「全部应用/忽略」 | 按类分组（记一餐 / 新建自定义食材 / 其他）+ 组级「应用本组」；`dismissEdits` 钉死只忽略 proposed | 新用例：三组头 + 只执行本组 + 应用后忽略仍「已应用」 |
| RV3-P2-06 | P2 | 训练页两个 AI 入口、且必须先点一个动作 | 页内抽屉与 FAB 页重复 | 删页内入口与整条 `_openAiPlanFlow`；创建页改**先选/填目标关键词**（chips）再由 AI 从整库选 | `workout_plan_create_page_test`（关键词增删/无「选择训练动作」/整库 75 条）、`secondary_entry_reachability_test`（只在 FAB）、`round7_training_capture_test` 改渲染创建页 |
| RV3-P2-07 | P2 | 步数授权取消不掉 / 授权后读不到 | 无应用内开关；回前台只 `_sync()` 无重试 | 新增 `steps_enabled` + 弹层开关 + 卡片「已关闭」态；回前台改 `_syncWithRetry()` | `dashboard_steps_and_weight_test`（关闭不写库/重开恢复）、`steps_permission_row_test`（开关往返 + 文案） |
| RV3-P3-01 | P3 | 拍照识餐页暂无 UI 入口 | 聊天 chip 换成「确认应用」后唯一入口消失 | **接受**：页面/路由/管线保留，深链可达；docs/21 §848/§1312 如实登记「暂无 UI 入口」 | 无（登记项） |

**这一批的退役件（如实登记）**：`test/app/camera_route_regression_test.dart`（聊天拍照入口移除）、
`training_page.dart` 的 `_openAiPlanFlow` + `_AiPlanStage` + 4 条页内用例（等价覆盖在
`workout_plan_create_page_test`）、`ai-chat-subtitle` / `cta-photo-scan` / `training-ai-plan` /
`nutrition-menu-others` 四族 Key（docs/21 各表已同步删除）。

### 7.1 追加（2026-10-24）：食堂目录与菜品库合并为一个库

| ID | 级别 | 现象 | 根因 | 修法 | 判据 |
|---|---|---|---|---|---|
| RV3-P1-05 | P1 | 在食堂目录加菜/分析完，菜单页（菜品库）里看不到；要自己去点「加入菜品库」 | 两个表面写两张表：食堂目录写 `menu_items`+证据，菜品库（菜单页唯一主来源）写 `dish_library`，靠一个**手动按钮**搬运；且 `upsertByName` 按**名字**找行 ⇒ 改一次名就多一张同名卡 | 合成一个库：`CanteenRepository` 加 `onDishUpserted/onDishDeleted` 钩子（组合根注入，无新跨 feature import），建菜/改名/换照片/改份量/写营养/删菜/删窗口/删地点都会自动同步；`DishLibraryRepository.upsertBySource` 以 `(sourceType='canteen', sourceId=menuItemId)` 为身份键（改名更新同一行） | `canteen_dish_library_sync_test.dart` 12 条：无营养不写空卡、写营养即进库（值=per100g×份量）、改名不新增行且 id 稳定、改份量重算、删菜/删窗口/删地点跟随删、钩子抛异常不阻断、`findDish` 空操作、窗口卡无按钮 |
| RV3-P2-08 | P2 | 复核时抓到**自伤**：`_updated` 原先把 `userEdited` 直接写成草稿值（默认 false），一次自动同步就把用户「我手改过这一行」的标记抹掉 | 老实现按「拷贝模型」写，标记只保护旧同步路径 | `userEdited: existing.userEdited \|\| draft.userEdited`（**只置位不清零**），并加回归用例 | `canteen_dish_library_sync_test`：手改标记在重新分析后仍为 true，数值仍跟着来源走 |
| RV3-P3-03 | P3 | 仓库内 5 个**零引用**公共符号（历史遗留） | 功能下线/改写后没人回头看 | 删除：`aiConfiguredFrom`、`describeFeedback`、`goldenTokensJson`、`l2Normalize`、`startersFor`（含随之无用的 4 个 import）；4 个 extension（`LfTokensX`/`MealSlotIcons`/`MenuServiceWindow`/`OnboardingPersistence`）经成员名复核**为活代码**（误报，与 `docs/55` §9 同结论） | 全仓（lib+test+tool）逐符号 grep 零引用；删后门禁全绿 |
| RV3-P3-04 | P3 | `docs/21` §5.1 滞留「步数卡查看详情」一行（该入口 2026-10-16 已按用户裁决删除） | 文档没跟着裁决走 | 改为四态描述 + 「卡上不再有进弹层的入口，开关与去系统设置在设置页弹层里」 | 文档同步（无代码影响） |
| RV3-P3-02 | P3 | 「整理重复菜品 / 关联到食堂菜品」整族 | 它是「两个库」时代的产物：同名两份才需要关联 | **整族退役**：页面 `food_cleanup_page.dart`、路由 `/food-cleanup`、设置行 `settings-food-cleanup-row`、`loadDuplicateSuggestions`/`DuplicateSuggestion`、`FoodCleanupPage` 用例、Key 表条目全删；`docs/40 §4` 加 as-built（菜品库 ↔ **食物库**的关联建议仍成立，那是两类东西） | `ui_spec_key_sync_test`（文档不再点名退役 Key）、`key_contract_test` / `food_maintenance_test` / `settings_page_test` / `menu_tab_view_test` 同步删改 |
