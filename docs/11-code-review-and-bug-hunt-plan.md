# 11. 代码审查与缺陷排查方案（Code Review & Bug Hunt Plan）

> 状态：已完成（2026-09-19）· 规范效力：无 · 后续以 `docs/29-ui-ux-remediation-plan.md` 为准 · 文档地图见 `docs/INDEX.md`

> 适用版本：2026-09-19（verify.bat 893 tests 基线）。
> 目标读者：要对 LocalFit AI 做全面 bug 检查与修复的开发者。
> 本方案基于项目真实架构（presentation → application → domain → data，Drift+SQLCipher，AI 合同体系）、
> 真实功能清单与历史踩坑记录（STATUS.md / docs/evidence/）定制，不是通用清单。

---

## 0. 红线（修复 bug 时永远不许碰）

修 bug 过程中以下边界一旦破坏，等于引入比原 bug 更严重的问题：

1. **营养三色**（蛋白=珊瑚、碳水=蜜黄、脂肪=雾紫）永不换相。
2. **业务文案、测试 Key、确认流程语义逐字不变**（文案级 bug 修复需先在缺陷登记里注明「文案变更」再动）。
3. **AI 结果必须过本地校验 + 独立确认**；不完整营养不得显示为已核验；推荐卡不得直写 `meals`。
4. **隐私行为不变**：`PrivacyLogger` 默认拒绝、披露面文案、Key 只进 header。
5. **每修一个 bug 必须带一个回归测试**（先红后绿），并跑 `verify.bat` 全绿才算修复完成。
6. 不提交/不推送（项目无 Git 元数据，改动记录靠 STATUS + evidence）。

---

## 1. 分级轨道（按风险排优先级）

| 级别 | 范围 | 理由 |
|---|---|---|
| **P0 数据完整性** | 备份/恢复、清除全部数据、目录导入、schema 迁移 | 数据损坏不可逆（历史基线：P0 崩溃与数据损坏为 0，必须守住） |
| **P0 隐私出口** | 日志、错误文本、披露面、AI 投影 | 隐私声明与行为一致是验收硬门槛 |
| **P1 AI 边界** | 7 个合同 decoder、本地校验、独立确认、取消 | AI 输出不可信，边界错了直接污染本地事实 |
| **P1 时钟/时区** | localDate、跨零点、新鲜度/营业窗口 | 全 App 按 localDate 取数，错一天=全错 |
| **P2 异步/生命周期** | context 跨异步、取消、流、Timer | 崩溃与「点了没反应」的主要来源 |
| **P2 输入与解析** | 数字解析、文件导入、边界值 | 崩溃类 bug 高发区 |
| **P3 UI/可达性** | 窄屏/大字体/减弱动画/TalkBack/44dp | 已有审计测试守护，抽查即可 |
| **P3 性能/资源** | FTS 分页、导入中断、图片清理 | 已有真机走查基线 |

---

## 2. 第一轮：静态扫描层（半天）

逐条跑命令，对每条命中做「合法/可疑/确认为 bug」三分类登记（模板见 §6）。

### 2.1 命令包与首轮基线（2026-09-19 实测）

| # | 检查 | 命令 | 基线命中 | 处置指引 |
|---|---|---|---|---|
| 1 | 吞异常 `catch (_)` | `grep -rn "catch (_)" lib/` | **57** | 数据写入路径上的必须逐个看（见 §3-A）；UI 降级路径可接受但要有日志口径 |
| 2 | 强解包 `!` | `grep -rnE "[a-zA-Z\)\]]!\." lib/ --include="*.dart" | grep -v ".g.dart"` | **53** | 重点审异步回调和 `first!`/`single!`；`match.group(1)!` 类正则自产自销可接受 |
| 3 | `Timer.periodic` | `grep -rn "Timer.periodic" lib/` | 1（rest_countdown） | 核对 dispose/didUpdateWidget 双取消（已有防护，验证即可） |
| 4 | 调试输出 | `grep -rn "print(\|debugPrint(" lib/ --include="*.dart" \| grep -v ".g.dart"` | **1** | 生产代码不允许，定位删除 |
| 5 | 异常文本进 UI/草案 | `grep -rn '\$error}\|\$e}\|error\.toString' lib/` | **2 处确认为疑点**（见 §2.2） | 错误文本出口白名单化（§3-B） |
| 6 | `DateTime.now()` 直用 | `grep -rn "DateTime.now()" lib/ --include="*.dart" \| grep -v ".g.dart"` | **48** | 分类：UI 即时动作可接受；domain/data 与「今天」语义的必须走注入时钟（§3-D） |
| 7 | TODO/FIXME | `grep -rn "TODO\|FIXME" lib/` | 0 | — |
| 8 | `parse` vs `tryParse` | `grep -rnE "double.parse\(\|int.parse\(" lib/ --include="*.dart" \| grep -v ".g.dart"` | **26** | 分两类：正则自产自销（合法）；`controller.text` 直接 parse（必须先 validate 或 tryParse，见 §3-F） |
| 9 | 写死 hex | `grep -rn "Color(0x" lib/features/` | **0**（2026-09-19 终审补漏后） | 保持 0，新代码一律走 AppColors/semantic |
| 10 | `Navigator.of(context).pop` | `grep -rn "Navigator" lib/ --include="*.dart"` | 历史已审计 30 处 | UI-B 曾修复 3 处页面 context 误弹分支页面；新代码沿用 Builder sheetContext 模式 |

补充扫描（第二轮人工审时跑）：

```bash
# 未 dispose 的控制器/焦点（每个 StatefulWidget 自查）
grep -rn "TextEditingController(\|FocusNode(\|AnimationController(" lib/ --include="*.dart"
# 流订阅未取消
grep -rn "StreamSubscription\|\.listen(" lib/ --include="*.dart"
# 多表写操作未包事务
grep -rn "batch(\|transaction(" lib/features/*/data/
# drift 表结构与单一清单对账（2.0-7a 的守护口径）
grep -c "Table(" lib/data/database/tables.dart
```

### 2.2 首轮基线中已坐实的疑点（作为第一批审查任务）

| # | 位置 | 现象 | 风险 | 建议处置 |
|---|---|---|---|---|
| S-1 | `lib/features/ai/application/ai_draft_controller.dart:64` | `unexpected_error` 时 `error.toString()` 全文进 `AiValidationReport` 并渲染到任务卡 | Dio 类异常含完整 URL/路径，供应商环境信息泄漏到 UI | 错误出口改为按 `AppFailure` 分类映射的固定文案（参照 `_safeFailureMessage` 模式），原始异常只进 `PrivacyLogger` 白名单指标 |
| S-2 | `lib/features/campus_menus/presentation/menu_tab_view.dart:60` | `'导入失败：$error'` 全文进 SnackBar | file_picker/IO 异常可能含本机路径 | 换成分类文案（解析失败/文件不可读/格式错误），原始 error 落 PrivacyLogger |
| S-3 | `lib/features/nutrition/data/catalog_bootstrap.dart:77`、`catalog_shard_importer.dart:187` | 数据导入路径 `catch (_)` 静默吞错 | 导入半失败被掩盖（低存储/磁盘满场景 2.0-7f 靠它兜底过，需确认吞掉的范围） | 收窄 catch 范围或补 `PrivacyLogger` 计数，保证「导入结果」卡片如实反映 |
| S-4 | 48 处 `DateTime.now()` | 部分在 domain/data 层 | 「今天」语义不统一、测试不可注入 | 逐个分类登记；`restEnd` 类 UI 即时计算可保留，取数类改注入时钟 |

> S-1/S-2 的修复注意红线 §0.2：SnackBar 文案属于业务文案，变更前先在缺陷登记注明，并同步改受影响测试的文案断言。

---

## 3. 第二轮：八大战役（域专项，每域半天～一天）

每个域按固定四步：**读域内全部文件 → 按高危模式逐文件过 → 核对已有防护测试 → 登记/修复**。

### 3-A 数据完整性（P0）

**范围**：`lib/data/database/`（schema v14、37 表）、`lib/features/backup/`、`lib/features/nutrition/data/`（catalog 导入）、各 repository。

**高危 bug 模式**：
1. 多表写入没包事务（如记录一餐要一次写 meals + meal_items）。
2. 外键顺序：`profile → goal → dailyTargets`（B-4 踩过）；删 profile 级联范围。
3. 迁移 v11→v14 的 `onUpgrade` 路径与全新安装路径行为不一致。
4. 备份/恢复往返：`.lfb` 字段与 `LocalFitBackupTables` 单一清单漂移（2.0-7a 建立的单一事实源）。
5. 「清除全部本地数据」后 Secure Storage/媒体/缓存残留。
6. 分片 `ATTACH` 到加密主库连接、SQLCipher 库解析——**宿主测试测不到，必须真机**（ADR-018/019 的教训）。

**已有防线**：迁移测试覆盖到 v14；备份往返测试；`sqlcipher_library_binding_test.dart` 源码级顺序断言；37 表对账测试。

**审查动作**：
- 对每个 repository 的写方法问三个问题：包事务了吗？idGenerator/clock 注入了吗？失败回滚后 UI 状态一致吗？
- 手工做一轮备份→清除→恢复→再清除，比对行数（drift 下 `select count(*)` 逐表）。
- 导入中断（kill 进程）后重启，验证「已在库中，无需重复导入」口径。

### 3-B 隐私与日志出口（P0）

**范围**：`PrivacyLogger`、所有 SnackBar/卡片错误文案、AI 披露文案、`docs/08`。

**高危模式**：
1. `error.toString()` / `$error` 进 UI 或日志（首轮已抓 2 处，S-1/S-2）。
2. 新增日志字段绕过 allow-list（`PrivacyLogger` 默认拒绝设计）。
3. AI 投影超披露范围（如常吃搭配把未点名食材带进 prompt）。

**审查动作**：
- 全量审「错误 → 用户可见文本」的每一条路径：异常分类映射是否存在、兜底文案是否可行动。
- 对照 `privacy_statement_audit_test.dart`（11 项）确认新代码没有绕过；新增出口必须先进 allow-list 评审。

### 3-C AI 边界（P1）

**范围**：`lib/features/ai/`（transport/capability/prompt catalog）、7 份合同 decoder、各 `*_workbench_task.dart`、`food_scan` 识别链路。

**高危 bug 模式**：
1. decoder 对模型返回越界的数值/枚举放行（对照 docs/03 §14/§15 的字段上限逐项核）。
2. allow-list 缺口：AI 引用了白名单外 id 却没被整单拒绝（workout/pairing 已强制，逐份核对）。
3. 生成与写入分离被绕过：任何「生成成功即落库」的路径。
4. 取消令牌没穿透到 transport（取消后仍写入草案）。
5. 投影隐私：prompt 里混入未披露字段（对照任务卡披露文案逐字段核）。
6. fake 与真实能力的分层：真实 transport 路径上的超时/取消/重定向分类。

**已有防线**：decoder 单测、流级 fake 测试（16 例）、`fake_task_capabilities.dart` 与生产模板同源断言、2.0-7c 披露面评测。

**审查动作**：对 7 份 decoder 各构造一组「恶意 JSON」用例（超长字符串、负数、NaN、错误枚举、多余字段、双层嵌套注入），确认全部拒绝或截断；对每个任务确认「确认按钮 → 写库」之间没有第二跳。

### 3-D 时钟/时区/新鲜度（P1）

**范围**：`formatLocalDate`/`localDate` 全链路、`DailyRollover`、菜单新鲜度/营业窗口、休息倒计时、趋势区间。

**高危 bug 模式**：
1. `DateTime.now()` 在 domain/data 直用（S-4 清单）导致「今天」口径分裂。
2. 跨零点：Today 页滚动过零点后取数（B-4 已有 `DailyRollover`，核对覆盖面）。
3. `localDate` 解析器（`int.parse(match.group(n))` 那 4 组）对非法串的防御——目前靠正则保证，核对正则是否唯一入口。
4. UTC/local 混用（种子 `todayIso`、菜单 `source_date`、备份 `exportedAt`）。

**审查动作**：grep 全部 `DateTime.now()` 逐个登记分类（48 处）；对每个「今天」取数点确认走 `widget.now ?? observedToday` 或注入时钟；构造 23:59 记餐/00:01 查看的手测。

### 3-E 异步与生命周期（P2）

**范围**：全部 presentation + application。

**高危 bug 模式**：
1. `await` 后用 context/`setState` 无 mounted 守卫（历史修过多处 `!dialogContext.mounted`）。
2. 弹层闭包携带页面 context（StatefulShellRoute + useRootNavigator 组合，B-1 的坑）。
3. `StatefulBuilder` 的 `setDialogState` 打在已销毁 State 上。
4. `TextEditingController/FocusNode/AnimationController` 未 dispose。
5. `StreamSubscription` 未取消；drift 流的 0-duration Timer 排水（测试侧 `drainStream` 惯例）。
6. 取消令牌：取消后仍在 `then` 里 setState。

**审查动作**：对每个 `async` 方法核对「await 之后用到的 BuildContext/State 是否有 mounted/mounted 检查」；对照历史修复清单（UI-B 弹层闭包、F-4 三处 mounted 模式）确认新代码没有回退。

### 3-F 输入与解析（P2）

**高危 bug 模式**：
1. `double.parse(controller.text)` 在 validator 绕过路径上炸（首轮 26 处，重点看 `new_food_dialog.dart`、`weight_entry_dialog.dart`、`onboarding_page.dart`——它们的 validator 与 parse 是否同一口径）。
2. NaN 传播：克数输入 `double.nan` 曾被有意用于「无效」语义（scan candidate）——核对 NaN 不会流进数据库。
3. 边界值：克数 0/负数/超大、体重、身高、目标体重区间校验（complete_onboarding 的安全闸）。
4. 文件导入：菜单文本的编码/超长行/空行；CSV 导出的转义。

**审查动作**：每个输入框构造 5 组非法输入手测（空、负、0、超大、非数字）；decoder 的恶意 JSON 组（3-C 共用）。

### 3-G UI/可达性（P3，抽查）

已有 15 例结构化巡检 + 组件级 golden 守护。抽查动作：
- 320dp + 2.0× 跑一遍新页面（六任务详情、dish-guidance 长文案）。
- TalkBack：关键确认按钮的 Semantics 标签（复用 `accessibility_semantics_test` 口径）。
- 减弱动画：新增动效（呼吸/脉冲/庆祝）都有退化测试（已覆盖），新动效按同口径补。

### 3-H 性能与资源（P3）

- FTS5 分页 ≤50 与 bm25 排序（已有真分片基线 P50 20.4/P95 31.6ms）。
- 图片生命周期：`PreparedMealImage` 的 discard 路径全走查（保存成功/失败/取消/页面退出四条）。
- 目录导入中断/低存储（2.0-7f 场景回归）。

---

## 4. 第三轮：设备走查（半天，需真机）

复用 `docs/09` B 节场景 + 2.0-7f 的 adb 技巧（`uiautomator dump` 取坐标、`input text` 不支持中文的规避）。重点盯**宿主测试测不到类**：
- SQLCipher 真机库解析、分片 ATTACH 到加密主库；
- 低存储 98%/100% 两档的导入与保存；
- 真机杀进程后的恢复（记餐、导入、备份）；
- 真机相册/相机权限拒绝路径。

---

## 5. 缺陷登记与修复流程

### 缺陷登记模板（每条一条记录，放 `docs/evidence/YYYY-MM-DD-bug-hunt.md`）

```markdown
### BUG-<序号>：<一句话标题>
- 级别：P0~P3 ／ 域：§3-A~H
- 现象：<用户可见行为>
- 复现：<最小复现步骤（含输入）>
- 根因：<代码级根因，给 file:line>
- 修复：<最小改动描述>
- 回归测试：<新增/修改的测试名，先红后绿>
- 验证：flutter test <scope> → verify.bat EXIT=0
- 红线检查：文案/Key/三色/确认语义/隐私是否受影响
```

### 修复节奏（每个 bug 一条闭环）

1. 复现（能写成测试的先写成红测试；不能写成测试的记手测步骤）。
2. 根因定位到 file:line，不许「顺手重构成修复」。
3. 最小修复 + 回归测试转绿。
4. `verify.bat` 全绿（不降断言、不跳测试）。
5. 登记缺陷条目；P0/P1 的修复在 STATUS 记一行。

---

## 6. 命令速查

```bash
# 统一验证（每修一个 bug 必跑）
cmd.exe //d //c "E:\AI\Zcode\localfit-ai\tool\verify.bat"

# 定向测试（审查某域时快速迭代）
E:/AI/toolchains/flutter/bin/flutter.bat test test/features/<feature>
E:/AI/toolchains/flutter/bin/flutter.bat analyze

# 真机走查辅助（docs/09 B 节）
adb shell uiautomator dump && adb pull /sdcard/window_dump.xml
adb shell settings put global window_animation_scale 0   # 关动画便于截图比对
```

---

## 7. 建议时间盒

| 轮次 | 内容 | 建议投入 |
|---|---|---|
| 第 1 轮 | §2 静态扫描全量分类 + S-1~S-4 修复 | 0.5~1 天 |
| 第 2 轮 | §3-A/B（P0 数据与隐私） | 1 天 |
| 第 3 轮 | §3-C/D/E（P1 AI/时钟/异步） | 1~2 天 |
| 第 4 轮 | §3-F/G/H 抽查 + §4 设备走查 | 1 天 |

---

## 8. 历史坑速查（已修复并有回归防护，审查时用于确认防线仍在）

| 坑 | 防线所在 |
|---|---|
| drift 流 dispose 0-duration Timer 打死测试 | `drainStream`/`drain` 助手（UI-C） |
| 页面 context 误弹分支页面（StatefulShellRoute+根导航器弹层） | UI-B 审计 30 处 Navigator；Builder sheetContext 模式 |
| `MeasurementRepository.saveManualWeight` 需先有 profile | 测试种子顺序断言 |
| 克数输入 initialValue 在元素复用时被忽略 | `ObjectKey(estimate)`（scan candidate） |
| 触觉统一走 `HapticFeedback.vibrate`+type 参数 | nav_bar/rest_countdown 测试口径 |
| SQLCipher 库解析/分片 ATTACH 只在真机暴露 | `sqlcipher_library_binding_test` 源码断言 + 真机走查 |
| 菜单快照跨天假过期 | 组件级 golden + `todayIso` 种子口径 |
| 假任务能力必须返回「AI 响应」而非解码用户投影 | 六任务流级测试 |
