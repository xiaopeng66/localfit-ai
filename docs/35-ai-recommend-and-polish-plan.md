# Round8：AI 推荐交互与五页缺陷修复计划（2026-10-16）

> 触发：用户在真机实测中提出 **21 条缺陷 / 需求**（AI 对话 6 + 今日 6 + 饮食 3 + 训练 3 + 我的 3），
> 要求「分析原因后拟定可行的开发计划文档，**分阶段但连续进行、无需审批**」。
>
> 状态：**执行中**（本文件同时是执行台账；每片的判定与证据在 §5 逐条回填）
> 规范效力：本阶段执行细则以本文件为准；视觉细则仍以 `docs/21` 为规范、`design/round7` A 主稿为视觉方向。
> 地图见 `docs/INDEX.md`。上一阶段（Round7 原生 UI 全量替换）证据见
> `evidence/2026-10-14-round7-native-implementation.md`；AI 控制面见 `docs/23`、`docs/34`。

## 0. 范围与纪律

**在范围内自主连续推进，不逐包等待确认。** 只有「真正需要改变范围 / 不可逆操作 / 需要外部授权」才暂停。

- **不碰**：数据库结构（Drift schema）、CSV/备份/恢复格式、AI wire 协议形状（`chat_edit` 信封本身）、
  权限与数据恢复语义、已退役功能；不放宽测试与性能预算。
- **不自动提交、推送或发布。** 不调用真实用户数据、不操作无关设备。
- 每片内部纪律：**设计 → 自检两轮 → 测试先行（真实 RED）→ 实施 → 定向回归 → 帧实看 → 门禁 → 文档同步**。
- 既有判据**只按新事实迁移，不放宽**；每条迁移都登记「为什么变、依据哪条用户指令 / 哪份文档」。
- 受阻项**如实标 blocked / not run**，不以「测试全绿」替代视觉验收。

### 0.1 三处口径定案（用户未答，按推荐档执行；执行中可改）

| # | 待定项 | 定案 | 理由 |
|---|---|---|---|
| D-a | 饮水/步数数值格式 | 一行「**当前 / 目标 单位**」（`750 / 2,000 ml`、`6,231 / 10,000 步`），删独立目标行 | 用户原话「能不能都做成 `250ml/1000ml` 这种」+「步数也加『达标 n%』标签」——把目标并到同一行才与「达标 n%」徽标同族；两卡形态一致 |
| D-b | 「功能卡片」指哪个 | **两处都改**：欢迎区三格 → 紧凑小卡；助手气泡下的提案卡 → 加卡壳/徽标 | 用户分别在「功能卡片太丑，要做成小卡片，而不是堆在下边」（欢迎区）与「生成的计划界面太丑 ⇒ 卡片式，并能复用在 AI 对话里」（提案卡）提了两处，「小卡片 / 卡片式」是同一诉求 |
| D-c | 对话图片 | **真发图**（复用既有 `visionRequestBody` 多模态拼装），披露文案同步改；供应商不支持时报**真实错误**，不静默丢图 | 用户原话「是你的哪里设置不对吧，我的模型可以识图的」——诉求明确是「让图能发出去」；**这是对外披露变更，单列为 S1** |

### 0.2 范围变更登记（不夹带在视觉改造里）

| 编号 | 变更 | 性质 | 需同步 |
|---|---|---|---|
| **S1** | 对话图片真实上行 | **对外披露变更**：图片会离开本机发给用户配置的供应商 | 披露文案、`docs/08`、`ai_egress_evaluation_test`、隐私相关测试判据 |
| **S2** | 步数卡删「查看详情」 | **撤销上一轮 R11**（`dashboard-steps-detail`，2026-10-15 裁决「做」） | `docs/21` Key 表、登记本轮台账 |
| **S3** | 体重卡删周期注；趋势卡目标标签移出柱区 | **用户指令偏离 Round7 A**（A 把「目标 N」画在图内、体重卡带周期注） | `docs/21` 图表节、本轮台账 |
| **S4** | 删「水分摄入目标」卡 | **撤销 `docs/29` §P2 D10**（健康三卡之一） | `docs/29`、`docs/21`、6 个测试文件、`LfProgressRingGauge` 死代码判定 |
| **S5** | AI 计划请求体：目标**必填** + 候选动作改**全库** | 发送内容变更（**不动 wire 协议**） | `docs/23` 请求段、本轮台账 |
| **S6** | 头像/昵称入口迁移到「编辑资料」 | 入口变化 | `docs/21` 设置/资料节、6 个测试文件 |

## 1. 缺陷总台账（21 条，含根因定位）

> 「根因」列一律给 `file:line`；基线为 2026-10-16 执行前源码（APK vc4014 / 门禁 `rB-gate-3`）。

### AI 对话（6）

| # | 现象 | 根因 | 对应片 |
|---|---|---|---|
| A1 | 缺「推荐回答按钮」：说「加早餐 1 个鸡蛋」而库中无鸡蛋时，只有文字，没有可点选项 | 协议只给命令清单（`chat_edit_registry.dart` `renderProtocol`），无「建议」信道；执行器缺实体时只返回失败文本（`chat_edit_executor.dart:961-971`），UI 无承载位 | 1.5 |
| A2 | 说「添加鸡肉食材」有回复但**没有应用按钮**，必须说「创建鸡肉食材」 | ①协议没写「**口语=命令**」映射，模型只按字面匹配 action 名；②快照只列**自建**食物（`chat_edit_context_loader.dart` `_renderUserFoods`），模型不知道「鸡肉」缺失；③无信封 ⇒ 无编辑卡 ⇒ 无按钮 | 1.6 + 1.5 |
| A3 | 「功能卡片」太丑、堆在下边 | 欢迎区三格与提案卡都是裸 `Column` 堆叠（`lf_chat_bubbles.dart:279-422`、`chat_edit_card.dart:11-144` 无卡壳） | 1.2 + 1.4 |
| A4 | 对话内容不能长按复制 | 全仓无 `SelectableText` / `SelectionArea`，气泡无 `onLongPress` | 1.3 |
| A5 | 发送图片提示「只能接收文字」 | `conversation_controller.dart:160-169` 在请求上下文里把图片**改写成文字**「…当前 AI 对话只支持文字，图片未发送」；`open_ai_compatible_conversation_service.dart:289-297` + `ai_protocol_wire.dart:168-217` 只拼文本；多模态件 `visionRequestBody`（`ai_protocol_wire.dart:95-158`）只服务拍照识别 | 1.7（S1） |
| A6 | 底部 chip 行要删「手动记录」、剩三枚占满一整行、调宽度与间距 | `lf_chat_input.dart:121-214`（枚举 `:216`）：四枚 chip 横滑、间距 `spaceSmall`；页面 `_onChipTap`（`ai_conversation_page.dart:281-287`）+ 路由参数（`:406-407`） | 1.1 |

### 今日（6）

| # | 现象 | 根因 | 对应片 |
|---|---|---|---|
| T1 | 体重趋势卡不该有「本周：周一至周日」描述（周/月都不要） | `dashboard_weight_card.dart:95-97` 计算 + `:206-213` 渲染（Key `dashboard-weight-period-note`） | 2.1（S3） |
| T2 | 柱子上方记录文字框歪、不居中 | `weight_bar_chart.dart:182-186` tooltip 用**写死半宽 32** 反推 `left = 格心 - 32`，而盒宽是内容宽（`maxWidth:64`）⇒ 内容短就左偏 `(64-宽)/2` | 2.1 |
| T3 | 月视图横坐标缺失 | `weight_chart_points.dart:98-101` 要求「锚点日 **且当天有记录**」才给标签 ⇒ 月视图多数锚点无标签 | 2.1 |
| T4 | 添加记录弹层「保存」太靠下；所有抽屉式卡片最下控件距底边太近 | `AppSheet` 底衬＝`viewInsets + padding.bottom`（`app_sheet.dart:129-136`）+ body 4dp；`weight_entry_dialog:165-177` 行动行无额外内衬 | 2.4 |
| T5 | 饮水/步数卡格式（`250/1000ml`、达标 n%）；饮水删 `+250ml`；步数删「查看详情」 | 饮水卡 `dashboard_quick_stats_row.dart:229-282`（徽标 `:232-238`、数值 `:253-263`、目标行 `:264-270`、`+250ml` `:275-282`）；步数卡 `_StepsCardShell:493-563`、`dashboard-steps-detail:411-417/:556-559` | 2.2（S2） |
| T6 | 步数**授权后仍识别不了** | ①原生 2s 窗口无事件回 `unavailable+no_event`（`MainActivity.kt:75-77,154-166`），Dart 把所有 `unavailable` 判成 **`noSensor`**（`steps_channel.dart:117-124`）⇒ 卡片写「没有计步传感器」；②首读成功把基线钉死显示 0（`:189-195`），要等下次 resume 才刷新；③`localDate ?? ''`（`:374`）可能写空日期 | 2.3 |

### 饮食（3）

| # | 现象 | 根因 | 对应片 |
|---|---|---|---|
| N1 | 复用历史餐食界面丑 | `meal_history_dialog.dart:13-61` 纯 `ListTile` 列表，无卡片层次 | 3.3 |
| N2 | 七日趋势卡目标标签应在柱区**外**（上移） | `nutrition_trend_card.dart:276-302` `_targetLabelGap=4` 画在柱区内的目标线旁 | 3.1（S3） |
| N3 | 餐食卡条目多了很乱、标签文字多 | `meal_record_card.dart:74-295`：三处克数重复 + 三枚 `_MacroChip:135-158` 合计宏量 + 来源徽标 `:167-170` | 3.2 |

### 训练（3）

| # | 现象 | 根因 | 对应片 |
|---|---|---|---|
| W1 | AI 计划应由 AI **从动作库里选动作**、按**所填目标**生成（目标不能可选） | ①`workout_plan_create_page.dart:324` 目标 `optional: true` + 弹层手写「（可选…）」（`training_page.dart:867`），domain 只校验长度（`workout_plan.dart:179-181`）；②候选动作 = **用户手动选的 1 条**（`_buildRequest:152-162`）而非整库 | 4.1（S5） |
| W2 | 生成的计划界面太丑（且预览显示 `ex-v-bar-pullup` 而非动作名） | `workout_plan_create_page.dart:537` 直接渲染 `entry.exerciseId`，页面无 id→名解析；弹层版只加载 60 条（`training_page.dart:738`）+ `_exerciseName:993-998` 回落 id | 4.1 + 4.3 |
| W3 | 计划卡要能复用在 AI 对话里（AI 生成计划时对话里就出卡片） | 对话的 `workout.plan.create` 只在编辑卡里渲成**一行文字**（`chat_edit_card.dart` `_EditRow`）；无共享的计划卡组件 | 4.2 |

### 我的（3）

| # | 现象 | 根因 | 对应片 |
|---|---|---|---|
| P1 | 头像与昵称应统一在「编辑资料」里改 | 入口只在设置页身份卡（`settings_page.dart:2395-2439` + `_pickAvatar:348-375` + `_editDisplayName:277-344`）；资料页无身份字段（字段仅 `profile_edit_page.dart:301-441`） | 5.1（S6） |
| P2 | 资料页训练目标要改成引导页那种大卡 | 资料页是三行 `RadioListTile`（`profile_edit_page.dart:303-318`）；引导页是 `_GoalBigCard`（`onboarding_page.dart:665-736`，**私有**，签名 `icon/label/selected/onTap`）；文案「保持/维持」也不一致 | 5.2 |
| P3 | 去掉「水分摄入目标」卡 | `settings_page.dart:2705-2722`（渲染 `:491` 无条件）；`LfProgressRingGauge` 唯一调用方 | 5.3（S4） |

## 2. 阶段与切片

> 每片都是一次可独立验收的改动：**测试先行取 RED → 实施 → 定向回归 → 帧实看 → 门禁**。

### 阶段 0：计划落盘与基线
本文件 + 基线记录（起始门禁 `rB-gate-3`：format 638 文件 0 改动 / analyze `No issues found!` / `+2390 ~29` 全绿 / exit 0；
起始 APK `release/localfit-ai-vc4014-20261015-arm64-release.apk`）。在实施证据文件开 Round8 段。

### 阶段 1：AI 对话（最高优先）
- **1.1** chip 行：删「手动记录」（枚举/构建/页面 switch/路由参数/`docs/21:1550` Key 表/2 个测试文件），
  剩三枚 **`Row + Expanded` 等宽铺满**，间距/内距按 A 重定（等宽范式参考 `lf_segment_control.dart:86-101`）。
- **1.2** 欢迎区功能卡 → 紧凑小卡（小图标块 + 一行文案 + 更紧内距），保留 Key 与「无 CTA」纪律（`lf_chat_bubbles.dart:173-179` 断言）。
- **1.3** 长按复制：消息区包 **`SelectionArea`**（保留 `Text`，不碰 `tester.widget<Text>` / `RenderParagraph` 两类脆弱断言，
  见 `test/app/ui_display_pages_test.dart:45-60`）+ 气泡长按给「复制」动作（剪贴板 + snackbar）。**不用 `SelectableText`**。
- **1.4** 提案卡卡片化：`chat_edit_card.dart` 用 `DesignCard` 包壳、状态改 `LfBadge`，守住
  `chat-edit-apply/dismiss-<i>` Key 与「全部应用单行」判据（`ui_display_pages_test.dart:390-420`）。
- **1.5** 【新功能】**AI 推荐按钮**：协议扩展可选 `suggestions:[{label, action, args?}]` → 解析器接受（无 suggestions 仍合法）
  → 对话页在末尾提案卡下方渲染**横滑推荐 chip 行**（图标 + 文案，样式按用户参考图）→ 点按 = 直接应用该命令（同一 executor）。
  **App 侧兜底**：执行器报「找不到食材「X」」类缺实体失败时，自动生成「创建食材 X」建议，点开**预填名称**的既有新建食物弹层。
- **1.6** 意图识别强化：协议补「**口语 = 命令**」映射（加/记录/建/删/改 → 对应 action；「用户说加 X 而库中没有 ⇒ 先 `food.create` 并估算营养，不要只回文字」）。
- **1.7** 图片上行（S1）：控制器不再改写；请求体拼多模态 content（复用 `visionRequestBody` 三协议形状）；披露文案 + 失败如实报错。

### 阶段 2：今日页
- **2.1** 体重卡：删周期注（含 4 处断言迁移）；tooltip **定宽 64 居中**（贴边 clamp 判据不变，`round5_weight_chart_test:182-223`）；
  月视图横轴**锚点日恒显示日号**（S3，迁移 `dashboard_steps_and_weight_test:397-423,700-711`）。
- **2.2** 饮水/步数卡：数值行 `当前 / 目标 单位`、步数加**达标 N%** 徽标、删饮水 `+250ml`、删步数「查看详情」（S2）；
  守「三态同高」（`stepsTitleRowHeight = 23`）与空态诚实文案（无记录不写 0）；迁移 6 处断言（含 `round5_steps_goal_test:167-168`）。
- **2.3** 步数授权根因：`no_event` → **`noReading`**（文案「这次没读到步数」而非「没有传感器」）；**授权成功后有界重试**（3s 后重读，最多 2 次，dispose 取消）；`localDate == null` 不写库；补全链 mock 判据。
- **2.4** 弹层底部：`AppSheet` 统一**最小底衬**（`max(viewInsets + padding.bottom, 16)`）＋ 全仓 ~40 个调用点逐点复核；归一自加内衬的 `WaterEntryDialog`。

### 阶段 3：饮食页
- **3.1** 趋势卡：目标线与「目标 N」标签移出柱区（上方），迁移 `nutrition_trend_card_test:160-181` 两条几何判据（S3）。
- **3.2** 餐食卡减噪：克数只显示一次；删三枚合计宏量 chips（1 条目不画合计行，≥2 条用一行 muted 小字）；保留来源徽标/备注/管理菜单。
- **3.3** 复用历史弹层重做：卡片式行（日期·餐次标题 + 条目摘要 + kcal 徽标 + 圆形复用钮），保留 `history-meal-<id>` Key 与「点了就复用」行为。

### 阶段 4：训练
- **4.1**（S5）目标**必填**（两个入口 + 披露条件 + validate）；候选动作改**全库**（提示词行压缩）；修 `:537` 与弹层 `_exerciseName` 的 id→名称回落。
- **4.2** 抽共享 **`PlanDraftCard`**（name + days + id→名），三处共用：创建页预览 / 训练弹层预览 / **AI 对话提案卡里的 `workout.plan.create` 行**。
- **4.3** 视觉：创建页与弹层预览改卡片式（日卡 + 动作行「名 · N×M · Wkg」）。

### 阶段 5：我的
- **5.1**（S6）头像/昵称**统一进资料编辑页**（设置页身份卡改只读 + 点任意处进资料页），迁移 6 个测试文件。
- **5.2** 训练目标改**引导页大卡形态**（抽公共 `GoalBigCard`，两页共用；文案统一「保持」）。
- **5.3**（S4）删「水分摄入目标」卡；`LfProgressRingGauge` 按死代码纪律判定去留；迁移 6 个测试文件 + `docs/29`/`docs/21`。

### 阶段 6：收尾与交付
全量门禁 → 帧矩阵重拍 + 逐张实看 → 实时 AI 矩阵（含新场景）→ 模拟器设备走查（受阻项如实 not run）
→ 重建与终态源码一致的 APK → 回填本文件台账、实施证据、`docs/21`/`23`/`29`、`docs/INDEX.md`、`STATUS.md`。

## 3. 测试迁移清单（只按新事实，不放宽）

> 执行中逐条填写「原判据 → 新判据 → 依据」。已知需迁移者：

| 测试文件 | 位置 | 变更 | 依据 |
|---|---|---|---|
| `test/features/ai_conversation/presentation/conversation_widgets_test.dart` | 201-212 | chip 四枚 → 三枚等宽 | A6 |
| `test/features/ai_conversation/presentation/ai_conversation_page_test.dart` | 488-505（chip） | 同上；删「手动记录」路径 | A6 |
| 同上 | 391-420（图片） | 「只能收文字」→ 真发图 | A5 / S1 |
| `test/features/ai_conversation/application/conversation_controller_test.dart` | 331-359 | 同上 | A5 / S1 |
| `test/ai_evaluation/ai_egress_evaluation_test.dart` | 135-147、424-428 | 图片出口断言（现断言非图片出口无 `image_url`） | S1 |
| `test/features/dashboard/presentation/dashboard_steps_and_weight_test.dart` | 397-423、700-711 | 周期注 / 月轴标签 | T1 / T3 |
| `test/features/dashboard/presentation/round5_weight_chart_test.dart` | 182-223 | tooltip 对齐（clamp 行为不变） | T2 |
| `test/features/dashboard/presentation/round5_steps_goal_test.dart` | 167-168 | `12,000` 计数 → 目标并入数值行 | T5 |
| `test/features/nutrition/presentation/nutrition_trend_card_test.dart` | 160-181 | 目标标签移出柱区（两条几何判据） | N2 / S3 |
| `test/app/ui_display_pages_test.dart` | 45-60 / 390-420 | 可读性探针（`RenderParagraph`）与「全部应用单行」 | A3 / A4 |
| `test/app/ui_spec_key_sync_test.dart` + `docs/21` | `:1550` Key 表 | 删 `ai-chat-chip-manual-log`、删 `dashboard-steps-detail`、删 `settings-health-water` | A6 / S2 / S4 |
| `docs/29` + `docs/21` | 29:163,222,253-255；21:1389,1395,1445,1447,1512 | 健康三卡 → 两卡 | S4 |

（其余在施行时补充；**每条都要有「为什么变」的记录**，禁止静默放宽。）

## 4. 证据要求

1. **每片**：测试先行 RED 的真实失败输出 → 实施 → 定向回归通过 → 门禁日志。
2. **帧**：受动矩阵整批重拍 + **逐字节对账**（变化面必须恰为改动面）；新增面单独出帧（含 320×2.0 与深色）；
   必须**逐张实看**后才能写「通过」。
3. **AI**：mock 判据进常规门禁；真模型验证用环境变量 `LF_AI_LIVE_KEY` / `LF_AI_LIVE_BASE` / `LF_AI_LIVE_MODEL`
   （默认跳过，**密钥永不入库**）。
4. **设备**：模拟器 `127.0.0.1:5039` 走查；做不了的（如真实传感器）**如实标 not run**。

## 5. 执行台账（逐片回填）

| 片 | 内容 | 状态 | 证据 |
|---|---|---|---|
| 0 | 计划落盘 + 基线 | ✅ 完成 | 本文件；基线 `rB-gate-3` |
| 1.1 | chip 行三枚等宽 | ✅ 完成 | RED `r8-red-chip1` → 绿 `r8-green-chip2`（47/47） |
| 1.2 | 欢迎区功能卡小卡 | ✅ 完成 | RED `r8-red-card2` → 绿 `r8-green-card1`；帧 `ai-chat-welcome-*` 实看（并修折行：铺满内容宽） |
| 1.3 | 长按复制 | ✅ 完成 | RED `r8-red-copy2` + 隔离变异见证（3 红，逐字节还原） |
| 1.4 | 提案卡卡片化 | ✅ 完成 | RED `r8-red-card1` → 绿 `r8-green-editcard3`；帧 `ai-chat-edit-card-*` 实看 |
| 1.5 | AI 推荐按钮 + 缺实体兜底 | ✅ 完成 | 域/执行器/控制器/页面四层判据；隔离变异见证；实时矩阵 ⑭ ✓ |
| 1.6 | 意图识别强化（口语=命令） | ✅ 完成 | 协议判据 + 实时矩阵「添加鸡肉食材」→ `food.create` ✓ |
| 1.7 | 图片上行（S1） | ✅ 完成（mock 四层） | wire 23/23、服务 15/15、控制器/页面文案迁移、披露行 |
| 2.1 | 体重卡（周期注 / 浮窗 / 月轴） | ✅ 完成 | RED `r8-red-w21b` → 绿 `r8-green-w21c`（127/127） |
| 2.2 | 饮水步数卡格式与删按钮（S2） | ✅ 完成 | RED `r8-red-w22` → 绿；帧实看再修「值的截断」（见 §7） |
| 2.3 | 步数授权根因修复 | ✅ 完成 | RED `r8-red-steps1`/`r8-red-steps4` → 绿（82/82、130/130） |
| 2.4 | 弹层底部间距 | ✅ 完成 | RED `r8-red-sheet1` → 绿（221/221）；含训练页两个裸弹层 |
| 3.1 | 趋势目标标签移出柱区 | ✅ 完成 | RED `r8-red-n31` → 绿（515/515）；帧 `record-*` 实看 |
| 3.2 | 餐食卡减噪 | ✅ 完成 | RED `r8-red-m32` → 绿；帧实看（一行宏量 + 项行单克数） |
| 3.3 | 复用历史弹层重做 | ✅ 完成 | RED `r8-red-m33b` → 绿（516/516） |
| 4.1 | AI 计划目标必填 + 整库候选（S5） | ✅ 完成 | RED `r8-red-w41b`（3 红）→ 绿（3/3、训练域 207/207） |
| 4.2 | 共享 PlanDraftCard（含对话内渲染） | ✅ 完成 | RED `r8-red-w42c` → 绿（`ai_conversation/` 197/197） |
| 4.3 | 计划界面卡片式 | ✅ 完成 | 创建页/训练弹层预览均走共享卡 |
| 5.1 | 头像昵称并入资料页（S6） | ✅ 完成 | 路由/身份回归 5 处失败见证 → 绿（13/13） |
| 5.2 | 训练目标大卡 | ✅ 完成 | RED `r8-red-w52c` → 绿（173/173、onboarding 31/31） |
| 5.3 | 删水分卡（S4） | ✅ 完成 | RED `r8-red-w53` → 绿（176/176）；2 个死代码件删除 |
| 6 | 门禁 / 帧 / 实时 AI / APK / 文档 | ✅ 完成 | 见 §6/§7 |

## 6. 终态门禁

- **APK（与终态源码一致）**：`release/localfit-ai-vc2015-20261016-arm64-release.apk`
  （sha256 `ac1e13f287317420606043e0cc6860eba977ff468b5893f3785a7aca942f8cbd`）与
  `release/localfit-ai-vc4015-20261016-x86_64-emulator.apk`
  （sha256 `56461264a3b851394a8d03d82ef0e3244b5f603408a4fd7abf2cc86b7d53d227`）；
  versionCode 用 `aapt2 dump badging` 核对为 2015 / 4015（与文件名一致）。
- **设备走查 not run（blocked）**：上一轮的 `LocalFit_API35`（5039）已不在线，当前在线的
  两台模拟器属其他项目（不得操作）；我重新拉起自己的 AVD 等了 ~135s，adb 桥始终未注册
  ⇒ 判为环境受阻，只杀掉自己起的进程。**设备级验证（设备帧、真机安装升级、软键盘/读屏、
  图片上行的真模型看图）全部 not run**，依赖帧矩阵与几何/行为判据代理。

- `r8-gate-final2`（所有代码与测试编辑之后）：format **643 文件 0 改动** / analyze **`No issues found!`** /
  `flutter test` **+2422 ~30 全绿** / exit 0 / **`changed_during_run: []`**。
- 中间四次门禁（阶段 1 / 2 / 3+4 / 5+6 第一次）见证据文件 §2；其中两次的
  `changed_during_run` 非空是「门禁运行期间我在编辑下一阶段的测试」，逐次记录在案，未当作洁净见证。

## 7. 帧实看发现并修掉的一处新缺陷（帧审看的价值）

帧矩阵重拍后**逐张实看**，在今日页 360dp 首拍帧里发现：饮水/步数卡改「当前 / 目标」一行后，
值行在半宽卡（≈130dp）里被**截断**成 `750 / 2,...`（步数 `6,231 / 10,000 …`）。

- 根因：一整个 `750 / 2,000` 字符串在 22 档下宽 ≈152dp > 可用 130dp，`Text` 按 `ellipsis` 收尾。
- 修法：`_MetricValue` 拆「大号当前值 + 小号 `/ 目标 单位` 后缀」（同一行，读数仍是
  「750 / 2,000 ml」，层次与「大数字 + 小单位」的既有语言一致），并把值行由 `Row` 换成
  `Wrap`（放不下就整段换行，**不截断、不缩字**）。
- 判据按新事实迁移 3 处（`dashboard-water-value` 回到 `750` 并新增
  `dashboard-water-target-inline` / `dashboard-steps-target-inline`），未放宽任何断言。
- 复拍验证：360dp 与 320dp×2.0 两档都完整显示（`renders/r8e/`）。

## 8. 实时 AI 矩阵（真模型 → App 解析 → 执行器 → 真库）

`r8-mx-full2`（供应商 `https://api.river.ai/v1`，模型 `deepseek-ai/DeepSeek-V4.1-Flash`；
凭据只走 `LF_AI_LIVE_*` 环境变量）：**11/14 场景通过**。

- ✅ **新增场景 ⑭（口语请求）**：「添加鸡肉食材」→ 模型按新协议规则 5/6 输出 `food.create`
  （口语→命令生效）；同一场景还断言了缺食材时执行器返回**结构化** `missingFoodName`
  （App 据此渲染「创建食材」按钮）。
- ✗ 3 例（⑦ 健康目标与约束 / ⑩ 训练域 / ⑫ 资料与目标）：模型「先写一句中文说明、再贴 JSON」，
  被 App 的严格解析（整段必须恰好是一个 JSON 对象）当纯文本丢弃 ⇒ 无信封。
  **这是已登记的范围项 R13（是否放宽解析），不是本轮改动引入的缺陷**：同一提示词下
  有的模型（如 `zai-org/GLM-5.3-Flash`）会严格只输出 JSON，本轮建议维持严格解析。

**图片上行的实时端到端 not run**：本仓测试环境下 `TestWidgetsFlutterBinding` 会把真实 HTTP
拦成 400（工程事实），所以图片只做到 wire/服务/文案四层 mock 判据；真模型看图需设备走查。

---

## 9. 追加轮（2026-10-16 下半场，用户追加指令）

> 用户原话：「1、2都要，并且你要自己看看还有没有可以优化的地方，我的需求是我对话只要是
> 涉及到让你修改，你就必须正确识别指令，而不是空回文字」。
> 1 = 纯文本回复也给候选按钮；2 = 缺实体兜底扩到更多种类。

### 9.1 「修改请求不许空回文字」——三层保障

| 层 | 做什么 | 判据/证据 |
|---|---|---|
| **协议层** | 规则 5 写成硬规则（含增/删/改意思的话必须给信封或 `suggestions`，缺信息也要给信封、edits 可空 + suggestions 候选）；规则 6 把「缺库实体要建」从食材扩到**动作/地点/窗口** | `chat_edit_registry_test`（含「修改请求必须给信封或 suggestions」两条文本判据） |
| **App 自动补救** | 新的本地判定 `looksLikeModificationRequest`（保守：**问句优先判假**，宁漏不误）＋ 控制器在「修改请求却没解析出信封」时**自动带提示重跑一次**（提示写进 system 段、不插假用户消息、每轮最多一次） | `chat_edit_intent_test` 4/4；控制器 6 条新用例（自动催、闲聊不催、有界两次、手动词条、手动催、未接线不催） |
| **残留兜底** | 自动催过仍是纯文本 ⇒ 该助手气泡下给 `ai-chat-request-envelope-<n>`「让 AI 给出可应用的修改」词条；残留判定**从落库消息重算**（末条纯文本 + 其上一条是修改请求）⇒ **重启后仍在** | 页面用例（词条出现→点击真催→拿到信封后词条撤下）；重启用例（新控制器载入历史仍识别）；帧 `ai-chat-envelope-retry-light-360-1.0` 实看 |

**实时实证（`r8-mx-b5`，真模型 deepseek-v4.1-flash）**：场景 ⑮ 用「先说明再贴 JSON」这一族
的请求做对照——不带提示与带提示**两趟都拿到 `profile.goal.update` 信封**；而 ⑦/⑩/⑫ 三条
（同一模型自律性问题）仍是「先散文再 JSON」⇒ 说明**补救路径有效但不保证**，所以第三层
（气泡词条 + 如实显示文字）必须一直在。全矩阵 **12/15**（3 例失败全是这一族模型行为）。

### 9.2 缺实体兜底扩到四类（原只有食材）

`ChatEditRepair` 增 `kind` + 窗口归属 `venueId`；执行器三处零命中各自挂上：

| kind | 触发点 | 按钮 → 点开的既有表单 |
|---|---|---|
| `createFood`（原有） | `meal.create` 等引用库外食材 | 创建食材「X」→ `NewFoodDialog`（预填名称） |
| `createExercise` | 训练域按名字引用库外动作 | 新建动作「X」→ `showCreateExerciseSheet`（**从动作库页提成共享函数**，动作库页自己改走它） |
| `createVenue` | 食堂窗口建在库外地点的名下 | 新建地点「X」→ `MenuFormPrompts.promptAddVenue(prefillName:)` |
| `createWindow` | 地点在、窗口不在（**带 venueId**；一个地点都没有时不给按钮） | 新建窗口「X」→ `promptAddWindow(venueId, prefillName:)` |

（菜品没这一档：`dish.upsert` 本身就是「按名字新建或更新」，不存在「库里没有这道菜」的失败。）
判据：执行器用例（三类各自断言 kind/name/venueId）、往返用例（含 `venueId`）、页面用例
（三条按钮文案 + 三次分发各开对表单）。

### 9.3 自查优化（我自己找的）

1. **残留词条扛得住重启**（见 9.1 第三层）——原设计只在内存里记账，重启就没了；改成从
   落库消息重算，代价为零（不加 schema 列）。
2. **协议规则编号与交叉引用**统一（规则 1 里对 suggestions 的引用指向新编号 8），并把
   「缺库实体」从「食物/菜品」扩写成「食物/菜品/动作/地点/窗口」。
3. **动作表单去重**：动作库页与 AI 修复按钮**共用同一份**「新建动作」弹层实现
   （原先只存在于动作库页 State 里，AI 侧接不了）。

### 9.4 门禁与交付

- 中间门禁 `r8-gate-b1`：format 0 改动 / analyze clean / **+2437 ~30 全绿** / exit 0 / `changed_during_run: []`。
- 终态门禁 **`r8-gate-b3`**（修掉门禁 b2 抓到的一条 `use_null_aware_elements` lint 之后）：
  format **645 文件 0 改动** / analyze **`No issues found!`** / `flutter test`
  **`+2437 ~31: All tests passed!`** / exit 0 / **`changed_during_run: []`**。
- **APK（与终态源码一致）**：
  * `release/localfit-ai-vc2016-20261016-arm64-release.apk`
    sha256 `58ac0ff5b074805ecd79b6acf97a00c08c3af5cd343633fe82a5be81e6f73b04`
  * `release/localfit-ai-vc4016-20261016-x86_64-emulator.apk`
    sha256 `34cd8012e506055a7fb5b821e2752a7e96e71bee7a6fc80eaea615bd72199d10`
  * versionCode 用 `aapt2 dump badging` 核对为 2016 / 4016（与文件名一致）。
- **设备走查仍 not run（blocked）**：同 §6 的原因（本机 AVD 起不来、在线的两台属其他项目）。

---

## 10. 用户实测缺陷诊断（2026-10-16 晚）：「打开 app 的 ai 对话显示发送失败，点击重试」

### 10.1 先排除「我把请求改坏了」

用 **App 自己的客户端栈**（同一个 `OpenAiCompatibleConversationService` + 真实协议/快照）
打真请求：`r9-diag1` **4/4 全绿**（探针 ok / 对话流式 / 编辑信封 / 计划草案）。
⇒ 请求形状、协议文本、SSE 解析都没坏，问题在**设备侧配置/网络/供应商**，或在我上一轮
改动**没覆盖到的两条路径**（下面）。

### 10.2 复现到两条真缺陷（都是我 S1 图片上行引入的）

| # | 场景 | 旧行为（用户看到的） | 现在 |
|---|---|---|---|
| **D1** | 历史里有一条**带图**消息，而供应商的模型不支持图片输入（多数网关对多模态 body 回 400） | 400 ⇒「供应商拒绝了该请求。」+「发送失败，点击重试。」；**因为那条图一直在历史里、每次发送都会重发它 ⇒ 整个对话永久发不出去** | **自动去掉图片重发一次**（有界），并把原因如实写进回复开头：「供应商拒绝了带图片的请求…这条已经改用纯文字重发；想让我看图，请换一个支持视觉的模型。」 |
| **D2** | 某条**历史**图片消息的文件已不在本机（清数据/系统清理） | 读文件抛 `ValidationFailure` ⇒ 每次发送都失败 | 只在**正在发的这一条**读不到图时硬失败（可行动：重新选图）；**历史**消息读不到就写一句「（这条消息里的图片已不在本机，未随本条发送。）」并继续 |

判据（测试先行）：`r9-red-imgfb5`（两条真红：`NetworkFailure: 供应商拒绝了该请求。` /
`ValidationFailure: 这条消息的图片读不到了`）→ 实施 → `r9-green-imgfb3`
（`ai_conversation/` + `ai/` **280/280**）。新增一个脚本化 adapter 复现「带 `image_url`
即回 400」的网关。

### 10.3 设备侧该看什么（给用户的动作清单）

错误气泡的真实原因是**第一行文字**，「发送失败，点击重试。」只是尾行。对照表：

| 气泡第一行 | 含义 | 怎么办 |
|---|---|---|
| `API Key 无效或无权使用该服务。` | 401/403 | 设置里重填 Key |
| `服务请求过于频繁，请稍后手动重试。` | 429 | 等一会儿 |
| `供应商暂时不可用，请稍后手动重试。` | 5xx | 换时间/换供应商 |
| `AI 请求超时，请稍后重试。` | 超时 | 网络或供应商慢 |
| `网络连接不可用，请检查网络后重试。` | 连接失败 | 检查网络（域名能否解析） |
| `供应商拒绝了该请求。` | **400/422** | 多半是**模型名不对**或**模型不支持图片**（D1 已自动降级） |
| 只有「发送失败，点击重试。」一行 | 错误没有中文原因（异常对象 toString 为空） | 极少见；把气泡截图给我 |

**另外值得先查的一条**：设置里的**模型名**必须与供应商 `/v1/models` 里的一致——
上一轮实测过：用户给的 `glm-5.3-flash` 在其供应商侧是 **503 model_not_found**
（可用的是 `deepseek-v4.1-flash`）。模型名写错同样会表现为「发送失败」。
