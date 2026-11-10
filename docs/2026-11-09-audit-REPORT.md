# 2026-11-09 全量审查 + UI 审查（audit→fix）

**模式**：`audit→fix→re-audit`（用户要求「检查死代码和潜在隐患 + 全量审查 + 界面 UI 审查」）
**深度**：L2 标准审（变更面集中在 AI 对话/编辑卡，其余按风险分诊抽样）
**基线**：`1d89da0` + 433 项未提交改动；版本 `0.1.0+2131`；测试基线 **+3348 ~1 全绿**
**收尾基线**：**+3358 ~1 全绿**（新增 10 条回归）

---

## 一、基线（审查前实测）

| 项 | 命令 | 结果 |
| --- | --- | --- |
| 静态分析 | `flutter analyze` | No issues found |
| 格式 | `dart format --set-exit-if-changed` | 893 files, 0 changed |
| 全量测试 | `flutter test --exclude-tags capture test/app test/features` | **+3348 ~1，exit 0** |
| release 测试 | `flutter test test/release` | 18 passed |
| 源码规模 | — | lib 394 文件 / test 489 文件 / tool 5 |

---

## 二、死代码

扫描工具：`tmp/audit-2026-11-09/dead_code_scan.py`（自写 import 图可达性 + 顶层符号引用计数）。

| ID | 级别 | 位置 | 结论 |
| --- | --- | --- | --- |
| D-01 | P3 | `lib/features/nutrition/domain/meal_evidence.dart:40` `evidenceBadgeForSource` | **真死代码**：全仓零调用、零测试；同文件 `evidenceGradeForSource` 仍在用；`source_badge.dart:143-151` 已重复实现同样 switch |
| D-02 | P3 | `lib/features/daily_plan/application/menu_service_window.dart:7-11` `MenuServiceWindow` extension | **真死代码**（extension 三个成员零调用）；同文件 `parseHhmmToMinute` 仍活（2 处生产调用）；文件尾还有指向已删函数的悬空注释 |
| D-03 | P3 | `lib/features/ai/domain/prompt_catalog.dart:8-22,89-105` `PromptDisclosure` + `disclosureFor` | **真死代码**：零调用零测试；`PromptCatalog` 本体仍活（main.dart:229） |
| D-04 | P3 | `lib/features/nutrition/domain/food_seed_count.g.dart` | 生成物孤儿（14 行）：无 import，但会被 `tool/food_seed/apply_review.py` 重写；`docs/DECISIONS.md:308` 声称的消费者 `data_attribution.dart` 已不存在 |
| D-05 | P3 | 8 个「生产不可达但测试在用」文件：`session_memory`、`menu_file_importer`、`menu_snapshot_store`、`menu_tab_controller`、`daily_solver`、`travel_fit`、`catalog_ai_projection` | **属既有决定**：`docs/evidence/2026-11-02-dead-code/run-log.md:48-53` 明确「有意保留」；旧菜单子系统已被 `CanteenRepository + MenuTabView` 取代（826 行） |
| D-06 | P3 | `manualCardGeneration=false` 旧自动卡片路径 | **流程缺陷**：docs/66 要求「旧路径只保留一个版本，下一版（v2117）删除」，当前已到 **2131**，清理窗口早已过期 |
| D-07 | P3 | `HeroSection` / `HeroShape`（design_card.dart） | 仅测试使用；docs/21、docs/30 声称今日页仍用它，但 `dashboard_ai_entry_card.dart` 已无引用（文档过时） |

**已排除的误报**（扫描器按名字判断不可靠，逐个核实）：`LfTokensX`（388 处 `context.lf`）、`AiMemorySearchPage` / `CatalogSearchPage`（隐式返回类型，生产在用）、`LogWriter`（公共构造参数类型）。

**本轮不改**：死代码清理按 playbook 铁律 6「死代码/格式化单独一轮」，且删 D-05 会连带测试，需要单独排期。D-06 已升级为一条流程问题登记。

---

## 三、隐患（每条都有实锤）

### H-01 · S1 · 取消竞态：编译流结束后点「取消」，卡片仍会挂上

**位置**：`lib/features/ai_conversation/application/conversation_controller.dart:2036`

`_completeManualCompile` 在 `onDone` 时校验一次 epoch，随后 `await coordinator.annotateDuplicates(pinned)`（真实链路要查库，几毫秒到几十毫秒），**回来之后没有再校验**。用户在这个窗口点「取消」：

1. `cancelCardGeneration` 把 epoch +1、状态回 idle；
2. 探针返回，代码继续走「挂卡 + `_persist`」；
3. 用户看到取消后闪出一张卡，且这张卡已落库。

违反 docs/66 §5.3「取消时先使 epoch 失效……迟到的流事件不得挂卡或写库」。

**证据**：审查探针（临时测试，已删）复现——`Expected: false / Actual: true`；该断言现固化为正式回归
`test/features/ai_conversation/manual_card_generation_test.dart`「编译流已结束、重复探针仍在查询时点取消：迟到的结果不得挂卡」。

**修复**：`annotateDuplicates` 之后补一次 `_disposed || epoch != epoch` 校验（1 行守卫 + 注释）。

**残余**：`annotateDuplicates` 内部已吞异常，不需要额外 try。

---

### H-02 · S1 · 2.0 字号窄屏：「尚未写入 + 生成应用卡片」同排溢出

**位置**：`lib/features/ai_conversation/presentation/ai_conversation_page.dart:2067`（`Row(mainAxisSize: min)`）

**实测（审查探针）**：

| 视口 | 溢出 |
| --- | --- |
| 390×844 @2.0 | 无 |
| 360×800 @2.0 | **RenderFlex overflowed by 39px** |
| 320×700 @2.0 | **RenderFlex overflowed by 79px** |

**为什么此前没被测到**：既有 `320dp × 2.0× 下按钮与状态不溢出` 用的回复是「你喝了 250 毫升水…」，不含 `replyClaimsChanges` 命中词 ⇒ 从不显示「尚未写入」提示，也就绕开了这一行。这是**测试覆盖盲区**，不是「测过没问题」。

**修复**：`Row` → `Wrap(alignment: end, crossAxisAlignment: center)`：放不下时提示退到按钮上一行；1.0 字号观感不变。

**回归**：`manual_card_page_test.dart` 新增 3 条（390/360/320 × 2.0），每条都先断言「尚未写入」提示存在（防止再次绕过目标布局）。

---

### H-03 · S1 · 结果说明文字对比度不足（浅色主题 2.11:1）

**位置**：`lib/features/ai_conversation/presentation/chat_edit_card.dart:1525`（单行结果）、`:242`（组尾 leftovers）

10px 文字用 `c.primary`(#2FBE8F) / `c.error`(#F44336) 压 `c.muted`(#EFF3F1)：

| 组合 | 实测比值 | AA 要求 |
| --- | --- | --- |
| primary / muted | **2.11:1** | 4.5:1 |
| primary / card | 2.36:1 | 4.5:1 |
| primary / mint-50（快捷 chip） | 2.22:1 | 4.5:1 |
| error / muted | **3.29:1** | 4.5:1 |
| error / card（破坏性正文） | 3.68:1 | 4.5:1 |
| mintText / muted | 5.00:1 | ✅ |
| errorText / muted | 5.84:1 | ✅ |

这是用户 2026-11-07 抱怨「我看不懂你要表达什么」的一个物理原因：淡绿 10px 小字在浅灰底上几乎读不出。

**修复**：所有「当文字/小图标」的位置改用文字专用档 `LfColors.mintText` / `c.errorText`（token 注释里本来就写着「文字级一律 600/700」）。涉及：
- `chat_edit_card.dart`（单行结果、组尾 leftovers、推荐 chip 图标）
- `lf_chat_input.dart:271`（第一枚快捷 chip 文字）
- `ai_conversation_page.dart:2337`（建议气泡图标、兜底卡）

**新增守卫测试**：`test/app/design/text_color_contrast_guard_test.dart` —— 钉住 mintText/errorText 在 card/background/muted/mint-50 四底上 ≥4.5:1，并显式记录「primary 不许当浅色文字」的实测值（若哪天 token 改成达标会红，提醒同步规则）。

---

### H-04 · S2 · 暗色 errorText 4.35:1（差一点点）

**位置**：`lib/app/design/lf_tokens.dart:296`

`errorText` 在暗色下与 `error` 同值 `#EF5350`，压 muted(#1F2823) 只有 **4.35:1**（低于 AA 4.5）。既有 `token_contrast_test` 只测 card 底（4.87 通过），没测 muted 底。

**修复**：暗色 `errorText` 提到 `#F26A63`：muted 5.06 / card 5.67 / background 6.21，色相不变。`error`（填充档）不动。

---

### H-05 · S2 · 图片删除按钮热区约 14dp

**位置**：`lib/app/design/widgets/lf_chat_input.dart:429`

删除圆视觉 20×20，但 `GestureDetector` 本身只有 20dp，`Positioned(right:-6, top:-6)` 溢出的部分不参与命中 ⇒ 有效热区约 14×14dp；且无 `Semantics` 标签，读屏得到无名节点。

**修复**：外层 `SizedBox(40×40)` + `Center`（视觉圆仍 20，不挤压预览图），加 `Semantics(button: true, label: '移除第 N 张图片')`，`HitTestBehavior.opaque`。

---

### H-06 · S2 · 「检查更新」无加载态，重复点击被静默忽略

**位置**：`lib/features/settings/presentation/settings_page.dart:1596`

`_updating` 只做闸门，不 `setState`：慢网时行内毫无变化，用户不知道点上没有；再点被 `if (_updating) return` 静默吞掉，只有一条会消失的 SnackBar。

**修复**：行内 `value: _updating ? '检查中…' : null`，期间 `onTap: null`；进入/退出都 `setState`（`mounted` 守卫）。

---

### H-07 · S2 · 「发现新版本」按钮行窄屏溢出

**位置**：`settings_page.dart:1658`（`Row(spaceBetween)`）

320dp 屏扣掉 16×2 内边距剩 288dp，两按钮自然宽约 300dp ⇒ 2.0 字号溢出。

**修复**：`OverflowBar(alignment: end, overflowAlignment: end)`（与 `AppSheet.showSubmitForm` 同口径）。

---

### H-08 · S2 · 旧兜底卡按钮行同类溢出

**位置**：`ai_conversation_page.dart:2414`

`Row(spaceBetween)` + 「重新生成可应用指令」（2.0× 自然宽约 384dp）。同类问题，同类修法（`OverflowBar`）。

---

### H-09 · S2 · 推荐 chip 文案无 `Flexible`

**位置**：`chat_edit_card.dart:1291`

`_SuggestionChip` 的 `Text` 直接在 `Row` 里，label 来自模型，可任意长；同文件 `_SuggestionBubble` 有 `Flexible`，这里漏了。

**修复**：包 `Flexible` + `maxLines: 2` + ellipsis。

---

### 已核查、**未发现问题**（避免重复审查）

| 面 | 结论 |
| --- | --- |
| 备份加密 | PBKDF2-HMAC-SHA256 **600k 迭代** + AES-256-GCM + SHA-256 校验双保险；`maxPayloadBytes` / `maxEnvelopeChars` 双上限；密钥派生在 isolate |
| API Key 存储 | `flutter_secure_storage`（Android Keystore / iOS Keychain `unlocked_this_device`），不进备份不外迁；超长/控制字符校验 |
| 明文 HTTP | `usesCleartextTraffic="false"`（**实测 aapt2 核对 vc4131 APK 确认**）；局域网通道是用户显式填地址的已知取舍（docs/evidence/2026-10-30-lan-update） |
| `allowBackup` | `false` + `fullBackupContent` + `dataExtractionRules` 双保险 |
| CSV 注入 | `csv_formula_guard` 覆盖 `csv_exporters.dart` 全部导出；导入侧 `food_csv_importer` 也过 |
| 事务边界 | `meal.create`、`food.create`、menu publish、backup restore、executor 的 meal 写入都在 `database.transaction` 内 |
| 日期解析 | `parseLocalDate` 用 `DateTime(y,m,d)` 回读校验，拒绝 `2026-02-30`；写入侧有未来日期守卫 |
| 日志 | `PrivacyLogger` 默认 writer 在 `assert` 里（release 不输出）；`main.dart` 的 `debugPrint` 只在 release 也输出——但内容只有条数与固定中文，不含路径/密钥/用户文本（逐条核对 9 处） |
| 控制器 dispose | epoch 全失效 → 取消订阅 → 关 token → 释放 notifier，顺序正确 |
| 页面 dispose | 两个 listener 都 remove；四个 controller 都 dispose |

---

## 四、UI 实帧（逐张查看）

渲染命令：`LF_ROUND7_CAPTURE_DIR=E:/AI/Zcode/tmp/audit-2026-11-09/frames flutter test <capture> --tags capture`

| 帧 | 尺寸 | 目视结论 |
| --- | --- | --- |
| `state-03-applied-results` | 390×900 | 每食物结果紧贴自己那行、绿字改成 mintText 后明显更清楚；「已应用」徽标与结果不重复 |
| `state-09-320-2.0` | 320×900 @2.0 | 序号随字号放大、名称单行省略、按钮行不溢出；**摘要行截断成「15…」可接受**（下方行内有完整 150 g） |
| `state-10-dark-applied` | 390×700 dark | 暗色结果文字 8.5:1，层级清楚 |
| `manual-card-idle-390-1.0` | 390×844 | 按钮在气泡右下、右对齐、「尚未写入」同排不挤 |
| `manual-card-320-2.0` | 320×844 @2.0 | 生成按钮独占一行、不溢出；顶栏头像几何实测 `right=304 < 320`（未裁切）；按钮文字看似下划线实为 CJK 字形（390 帧同样存在，已排除） |

**未验证**：真机触感/性能、动效、系统字体替换（如厂商字体）下的字形测量；iOS 端未渲染。

---

## 四之二、第二轮：死代码清理 + 剩余隐患（同日追加）

用户指令「先清理死代码，修复隐患」。本轮**只做这两件事**，不新增功能。

### 已删除的死代码

| ID | 位置 | 处理 |
| --- | --- | --- |
| D-01 | `meal_evidence.dart` `evidenceBadgeForSource` | 删除（连带不再需要的 `Key` import）；同文件 `evidenceGradeForSource` / `evidenceLabelForSource` 保留 |
| D-02 | `menu_service_window.dart` `MenuServiceWindow` extension + 文件尾悬空注释 | 删除；`parseHhmmToMinute` 保留（2 处生产调用） |
| D-03 | `prompt_catalog.dart` `PromptDisclosure` + `disclosureFor` | 删除；`PromptTemplate` 的 `sendsWhat/neverSends/destinationHint` 字段保留（披露文本仍是模板事实） |
| D-04 | `food_seed_count.g.dart` | 删除文件 **+ 生成路径**（`apply_review.py` 的 `OUT_COUNT` / `render_count` / 三处解包）、`test_apply_review.py` 的对应断言；并修正 3 处失效文档（`DECISIONS.md` §ADR-028 ⑤、`docs/29` 产物份数、`docs/32` T13 第 3 条） |

D-04 的判定依据（不是「看着没人用就删」）：生成器 `apply_review.py --check` 实测已 **FileNotFoundError**（种子 `foods.v4.json` 按 docs/32 T13 退役），即该文件**永远不会再被重新生成**，且全仓零 Dart 引用、设置页早已改为从数据库实算。同时删掉生成路径，避免将来从归档恢复种子后它又长回来。

D-05（6 个「仅测试用」旧子系统文件）与 D-06（`manualCardGeneration=false` 旧路径）**仍然保留**——前者有 2026-11-02 审计的明确保留结论，后者需要独立排期。

### 本轮修掉的剩余隐患

| ID | 位置 | 修法 | 证据 |
| --- | --- | --- | --- |
| H-10 | `LfDangerButton`（`lf_buttons.dart`） | 字色 `error` → `errorText` | 填充档 3.68:1（白卡）/3.29:1（muted）→ 文字档 6.54:1/5.84:1 |
| H-11 | `SettingRow.destructive`（`setting_row.dart`） | 标题色 `error` → `errorText` | 同上；「清除所有数据」等行标题是 14px 正文 |
| H-12 | 4 处错误正文：`dietary_constraints_sheet`、`ai_memory_page`、`app_sheet`、`lf_text_field` | `error` → `errorText` | 同上 |
| H-13 | `_showImageFull`（附件预览放大） | 删除第二套全屏实现，复用 `ChatImageZoomView` | 原实现 `Positioned(top:32)` 无 `SafeArea`、裸 `Colors.black/Colors.white54`、无 `Semantics` |
| H-14 | 编辑卡修复胶囊（「新建食材 X」） | 内边距移进 `InkWell` | 命中盒约 29dp（2.0× 41dp）→ 45dp，视觉胶囊尺寸不变 |

配套回归：
- `lf_buttons_test` 的 B7 断言改为钉 `errorText`，并**加入对比度断言**（浅色 card/muted、暗色 muted 全部 ≥4.5:1），另断言「填充档 ≠ 文字档」；
- `chat_edit_card_food_row_b_test` 新增「修复胶囊命中盒 ≥44dp」；
- 4 个按旧色定位删除按钮的测试（`record_tab_selection`、`settings_backup`、`settings_page`、`training_page`）改为 `errorText`，并在注释里写明为什么改。

---

## 五、门禁（收尾）

| 项 | 命令 | 结果 |
| --- | --- | --- |
| 定向（新增回归） | `flutter test test/features/ai_conversation test/features/settings test/app` | **+1446 全绿** |
| 全量（第一轮） | `flutter test --exclude-tags capture test/app test/features` | +3358 ~1；**首次运行 4 条红**（均按旧 `error` 色定位删除按钮，见 H-10…H-12） |
| 全量（第二轮，修正断言后） | 同上 | 见文末「收尾结果」 |
| release | `flutter test test/release` | **+18 全绿，exit 0** |
| 格式 | `dart format --output=none --set-exit-if-changed lib test tool` | **0 changed** |
| 静态 | `flutter analyze` | **No issues found** |
| 编码 | `python E:/AI/Zcode/scripts/check-encoding.py` | **OK（exit 0）** |



---

## 六、残余与未验证

1. **死代码未删**（D-01/02/03 真死代码、D-04 孤儿生成物）：按铁律「死代码单独一轮」，需要用户确认是否开清理批次。
2. **D-06 旧自动卡片路径**：docs/66 说 v2117 删，现在是 2131，已过期两年版本号。建议单独排期，不要顺手删（回滚价值已消失，但影响面大）。
3. **文档过时**：`docs/DECISIONS.md:308` 的 `data_attribution.dart` 已不存在；`docs/21:283`/`docs/30:215` 说今日页用 `HeroSection`，实际已不用。
4. **`test/privacy` 的 http 字面量审计**：历史遗留红（LAN 更新引入），需要用户裁定「局域网明文 HTTP 保留与否」，本工具链未改动。
5. **真机未验证**：本轮全部证据来自 widget 测试 + 离屏渲染帧，未在任何实机/模拟器上安装本轮改动。
6. **UI 代理报告的其余项未全部采信**：仅采纳并逐条实测/复算的部分；「读屏缺长按复制入口」「预览条固定高度压扁输入区」等属于设计取舍，未改，记录在此。

---

## 收尾结果（第二轮）

| 项 | 命令 | 实际结果 |
| --- | --- | --- |
| 全量 | `flutter test --exclude-tags capture test/app test/features` | **+3360 ~1，exit 0**（第一轮 +3358，本轮 +2：命中盒回归 + 对比度断言组） |
| release | `flutter test test/release` | **+18，exit 0** |
| 格式 | `dart format --output=none --set-exit-if-changed lib test tool` | **0 changed** |
| 静态 | `flutter analyze` | **No issues found** |
| 编码 | `python E:/AI/Zcode/scripts/check-encoding.py` | **OK** |

本轮改动文件（源码 8 / 测试 7 / 工具 2 / 文档 4）：

- 删除：`lib/features/nutrition/domain/food_seed_count.g.dart`
- 源码：`meal_evidence.dart`、`menu_service_window.dart`、`prompt_catalog.dart`、
  `lf_buttons.dart`、`setting_row.dart`、`lf_text_field.dart`、`app_sheet.dart`、
  `ai_memory_page.dart`、`dietary_constraints_sheet.dart`、
  `ai_conversation_page.dart`、`chat_edit_card.dart`
- 测试：`lf_buttons_test.dart`、`chat_edit_card_food_row_b_test.dart`、
  `record_tab_selection_test.dart`、`settings_backup_test.dart`、
  `settings_page_test.dart`、`training_page_test.dart`、`no_bundled_food_seed_test.dart`
- 工具：`tool/food_seed/apply_review.py`、`tool/food_seed/test_apply_review.py`
- 文档：`DECISIONS.md`、`docs/29`、`docs/32`、本报告

**未升版本、未构建、未发布、未提交。真机未验证。**
