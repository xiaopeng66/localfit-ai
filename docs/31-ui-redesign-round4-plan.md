# LocalFit AI 界面重设计第四轮方案（`docs/31`）

日期：2026-10-09
依据：用户 2026-10-09 一次性反馈（**21 条**，见 §1，编号**续 docs/29 的 37 号**从 38 起）
+ 同日读码勘察（每条需求的现状落点、根因、影响面见 §1 逐条）
状态：**方案定稿，实施中**。工作包 S1→S8，每包独立过门禁（`tool/verify.bat`）。
前置：`docs/30` 的 R1–R8 已全部交付并闭环（见 `STATUS.md`），本方案是**新一轮**，不重开旧包。

---

## 0. 权威源与防误导（开工前必读）

| 类别 | 权威文件 | 说明 |
|---|---|---|
| **本方案的执行细则** | **本文 `docs/31`** | 21 条需求的唯一落点与顺序；与其余方案书冲突时以本文为准 |
| 长期目标与硬约束 | `GOAL.md` | 产品目标、隐私/AI 硬约束 |
| 产品/数据/AI/验收契约 | `docs/07-localfit-2.0-development-spec.md` | 契约层 |
| AI 可编辑面契约 | `docs/23-chat-universal-edit.md` | chat-edit 命令表；本轮删除两条参数需同步 |
| **UI 规范** | `docs/21-ui-redesign-spec.md` + `ui设计/pages/*.html` | token / 组件族 / 每页结构树。**本轮改动落地时同步改写 docs/21 对应小节**（它被 `ui_spec_key_sync_test.dart` 读盘） |
| 隐私与权限口径 | `docs/08-store-privacy-and-permissions.md` | 权限表；**S6 加蓝牙权限后必须同步**（`privacy_statement_audit_test.dart` 会先红一次） |
| 实时状态 / 交接 | `STATUS.md`（根目录） | 只有这里能说「做到哪一步了」 |
| 决策日志 | `docs/DECISIONS.md` | 追加式，本轮新决策按 ADR 编号追加 |

**已知会误导本轮的三处旧文本（实施时同步修正，不留「照它做就错」的注释）**：

1. `docs/21 §7.2`「体成分不单独建表——同一测量时刻的多个指标应同行」的记载与本轮
   「体脂率/肌肉量全删」相反：该小节要改成**已删除**并写明 schema 22 的 drop 迁移。
2. `docs/23` 的 `weight.log` 契约行写着 `bodyFatPercent 0–70、muscleMassKg 0–200` ——
   本轮两条参数删除，契约行必须同步（`chat_edit_registry_test` 会红）。
3. `docs/08` 的权限表在本轮**新增蓝牙**后失真（现在只声明 INTERNET +
   ACTIVITY_RECOGNITION，且 `privacy_statement_audit_test` 把这两个**按序**写死）。

---

## 1. 需求清单（用户原话 → 编号 → 现状实测）

> 原话逐条照录，不转写、不合并。现状一栏是 2026-10-09 读码勘察（含文件:行号）。

### 需求 38 · 体重卡整体「还是太丑」

> 「体重卡片还是太丑」

**现状**：`DashboardWeightCard`（`dashboard_weight_card.dart`）当前形态是
`DesignCard` + `DesignCardHeader`（标题 / 副标题 + trailing 行）+ 12dp 间隔 +
`WeightBarChart`。R2 已把它从「折线 + 三格趋势 + 大分段控件」改到这一步，
用户仍不满意 —— 本轮连同下面 39–44 六条一起重做（**这是一个视觉重做包，不是一个补丁**）。

### 需求 39 · 周/月切换照用户发的第二张图

> 「日月的切换需要我发的第二张图」

**现状**：R2 把旧的 `LfSegmentedToggle`（灰轨道 76×48 + 白滑块）换成
**两颗独立 `LfPillButton`**（`dashboard_weight_card.dart:100-120`，各自的
`MaterialTapTargetSize.padded` 让布局盒仍是 48×48）。

**用户给的第二张图 = 我们 R2 稿 `ui设计/remediation/今日-体重卡.html` 的
④ 改造前帧**（灰底**统一轨道** + 内嵌**白色凸起滑块**，选中项绿字、未选中灰字）。
即：用户否定的是 R2 的「两颗独立胶囊」，要的是**统一轨道 + 白滑块**这一形态。

> **注意**：R3 时用户嫌它「太大了，上下宽度也很大」——嫌的是**尺寸**（布局盒 48dp），
> 不是**形态**。本轮取形态、压尺寸（裁决 D2）。

### 需求 40 · 柱状图的柱子太宽

> 「你之前有设计过柱状图的柱子太宽了」

**现状**：`WeightBarChart.maxBarWidth = 40`（`weight_bar_chart.dart:54`，设计稿
`.bars .b { max-width: 40px }` 的落地）。360dp 屏 7 根柱时每根 ≈ `slot - 6`
≈ **36dp**（`EdgeInsets.symmetric(horizontal: 3)`，`weight_bar_chart.dart:169`）。

### 需求 41 · 周视图固定七格，没数据的时间空着

> 「一周就直接横坐标七天都显示，没有数据的时间就空着」

**现状（真缺陷级差异）**：`buildWeekChartPoints`（`weight_chart_points.dart:95-110`）
取**最近 ≤7 条记录**出点，标签是这些记录的星期几 —— 记录只有 1 条时图上**只有
1 根柱 1 个标签**，横坐标不是「一周七天」。用户要的是**恒定七格**
（一…日），**没有记录的那天留空槽**（不画柱、标签仍在）。

实现要点：`WeightChartPoint` 需要能表达「空槽」（`weightKg` 可空或新增
`isEmpty`），周视图按**当前周的 7 个日历日**（`localDate` 所在周的周一起 7 天）
生成 7 个槽位，有记录填值、没有则空；空槽不画柱但横轴标签照出。
「空槽」与「0 值」必须可区分 —— 空槽不能画成「0kg 的柱」。

### 需求 42 · 月视图标题写「本月体重」

> 「月视图标题写本月体重」

**现状**：`dashboard_weight_card.dart:78` — `monthView ? '体重趋势' : '本周体重'`。
改成 `'本月体重'`；`semanticLabel`（`:73`）同步。

### 需求 43 · 去掉「较月初」

> 「下边不要写较月初」

**现状**：`dashboard_weight_card.dart:82-84` — 月视图副标题追加 `'  较月初'`。
删掉该串（增减量箭头与数值本身保留与否见裁决 D3）。

### 需求 44 · 添加按钮只留图标

> 「添加的按钮做好看点，只要图标，不要添加两个字」

**现状**：`dashboard_weight_card.dart:90-95` — `LfTextButton(label: '添加', icon: Icons.add)`。
**`LfTextButton` 与 `LfPillButton` 都没有 icon-only 形态**（`lf_buttons.dart`：
`label` 一个是 `required String`、另一个 `required String`，无空串路径；
仓里唯一的纯图标按钮是 `LfCircleIconButton`（`lf_top_bar.dart:156+`，
36dp 视觉 / 44dp 命中盒），但它长在 top bar 家族里、语义是「次要页操作」。

### 需求 45 · 添加弹窗去掉体脂率与肌肉量

> 「添加的弹窗卡片去掉体脂率和肌肉量」

**现状**：`weight_entry_dialog.dart` — 两个 `AppNumberField`
（`weight-bodyfat-input` :155、`weight-muscle-input` :174）+ 各自的 validator
（:164-169、:183-188）+ date re-seed（:270-271）+ `WeightEntryResult` 两个字段
（:327-335）。`sheet_action_row_keyboard_test.dart:123` 把四个标签**写死**断言，
删字段时**必然变红**（要改成三个）。

### 需求 46 · 其他地方关于这两个数据的全删

> 「其他所有地方有关于这两个数据的都删掉」

**影响面（勘察实测，逐处）**：

| 层 | 落点 |
|---|---|
| DB 列 | `tables.dart:96` `bodyFatPercent`、`:98-100` `muscleMassKg`（`Measurements`） |
| 迁移 | `app_database.dart:232-252`（`from < 17` 加 `muscleMassKg`）；本轮要**反向 drop** |
| 领域模型 | `weight_measurement.dart:9-10, 19-24` |
| 仓储 | `measurement_repository.dart:18-19, 24-25, 32-41（两条校验）, 70-71, 87-88, 99-100, 115-116, 188-189` |
| 页面接线 | `dashboard_page.dart:148-149, 167-168, 180-181` |
| 弹窗 | 见需求 45 |
| AI 命令表 | `chat_edit_registry.dart:103-117`（两条 `ChatEditArgSpec`）+ `:127-128`（summarize） |
| AI 执行器 | `chat_edit_executor.dart:150-151` |
| AI 上下文 | `chat_edit_context_loader.dart:196-197`（**唯一会把体脂送进 prompt 的地方**） |
| 契约文档 | `docs/23:71` |
| 测试 | `app_database_v17_migration_test.dart:46-47,173,177`、`chat_edit_executor_test.dart:58,65`、`weight_entry_date_test.dart:112-113,129-130`、`sheet_action_row_keyboard_test.dart:123`、`dashboard_page_v2_test.dart:319-342`、`dashboard_steps_and_weight_test.dart` 5 处 fixture、`dashboard_breakpoint_test.dart:165-176`、`bento_layout_test.dart:131-142` |

**不在影响面**（勘察已确认，避免误删）：`assets/seed/exercises.v3.json` 的
「肌肉抓举」是**动作名**、`foods*.json` 的「肌肉科技」是**品牌名**、
`tool/exercise_seed/build_exercises.py` 的 `"muscle": "肌肉"` 是**肌群译名映射** ——
三者与体成分无关。

> **备份兼容（必须如实写进证据）**：`.lfb` 是整行 drift JSON 序列化
> （`backup_table_registry.dart:122-127` + `app_database.g.dart` 的
> `toJson/fromJson`），**没有列级版本门**。drop 列后，旧包里的这两个键在恢复时
> 被**忽略并丢弃**，不报错。这是「删数据」的事实，不能糊过去。

### 需求 47 · 电子体重秤授权 + 自动导入体重

> 「另外能不能支持授权电子体重秤，例如小小米体重秤，可以自动导入体重数据」

**现状（这是个从零开始的能力，不是一个开关）**：

| 项 | 实测 |
|---|---|
| 蓝牙依赖 | **零**（`pubspec.yaml` 15 个依赖无 BLE；`.flutter-plugins-dependencies` 29 个插件无 BLE） |
| 蓝牙权限 | **零**（manifest 只声明 INTERNET + ACTIVITY_RECOGNITION，且 `privacy_statement_audit_test.dart:64-83` 把列表**按序写死**） |
| `ACCESS_FINE_LOCATION` | **被测试明文禁止**（`:82` `isNot(contains(...))`）—— 但 minSdk 24 在 API ≤30 上扫描 BLE **必须**要它 |
| minSdk / targetSdk | **24 / 36**（`android/app/build.gradle.kts:32-33`）⇒ 需要 `BLUETOOTH` + `BLUETOOTH_ADMIN`（≤30）+ `BLUETOOTH_SCAN`/`CONNECT`（31+，带 `neverForLocation`） |
| 原生通道 | 只有 1 个 `MethodChannel('localfit/steps')`（3 个方法）；BLE 需要**扫描/连接/订阅通知**的**多步生命周期**，不是一次性读 |
| 后台能力 | 通知/前台服务基础设施**完全没有**（无 `POST_NOTIFICATIONS`、无 `<service>`、无任何通知插件） |
| 写入路径 | `saveManualWeight` **硬编码 `source: 'manual'`**（`measurement_repository.dart:72,101`），且**无去重键**（只有 `localDate`，无测量时刻）⇒ 多天同步会**静默覆盖**用户手输的当天值，且事后**分不清哪条来自秤** |
| 唯一性 | `(profileId, localDate)` 是**仓储约定**（select-then-update），**不是 DB 约束**（`measurements.localDate` 无 `.unique()`） |

### 需求 48 · 步数卡未授权态只留徽标

> 「步数卡片未授权的时候就单纯加一个未授权的标识就好了，就是现在右上角那个，
> 其他的文字和按钮不需要，不要影响卡片已授权状态的高度和布局」

**现状**：`StepsStatCard`（`dashboard_quick_stats_row.dart:246-303`）未授权态渲染
`_StepsCardShell(badge: LfBadge.honey('未授权'), body: _StepsHint(headline:'—',
hint:'需要「身体活动」权限才能读步数', action:'去设置'), onActionTap: _openSettings)`
—— 即**除了右上角徽标**，还有大号 `—`、说明文字、「· 去设置」文字链，且
`_StepsCardShell` 在 `onActionTap != null` 时**多渲染一行**（:378-392）⇒ 卡高与
已授权态**不一致**，这正是用户点名的「不要影响高度和布局」。

**用户要的**：未授权 = **只有右上角 `未授权` 徽标**，卡内文字/按钮/进度条全部去掉，
**卡高与已授权态完全一致**。语义标签仍要如实说「未授权」（读屏不能只剩一个词）。

### 需求 49 · 食物库满刻度 900 → 1000 kcal/100g

> 「食物库的满刻度能不能设置为1000kcal/100g」

**现状**：`kFoodDensityFullScaleKcal = 900`（`lf_food_kcal_ring.dart:113`，单源），
注释与语义都写「纯油脂约 900 是物理上限」。改 1000 只需改这一个常量，但
**三处测试把数字/百分比写死**：`food_library_ui_test.dart:288`（`'满刻度 900 kcal/100g'`）、
`food_detail_sheet_test.dart:243`（`'…满刻度的 13%'`）、
`nutrition_presentation_design_test.dart:166`（同一个 13%）—— 都要同步。

> 1000 会让「纯油脂 900」不再顶格（900/1000 = 90%）——这是**用户要的口径**，
> 语义标签如实报百分比，常量注释要改写（不留「900 是上限」的旧话）。

### 需求 50 · 删除「过敏原与饮食标签」

> 「过敏原与饮食标签这个删掉」

**现状**：`new_food_dialog.dart:204-259` —— 标题
`'过敏原与饮食标签（可选）'` + `SwitchListTile('我已确认本地事实')` +
勾选后才出的两组 `AppMorphChip`（`DietaryLabel` 4 个 / `FoodAllergen` 9 个）。
数据在 `foods` 三列：`constraintKnowledge` / `dietaryLabelsJson` / `allergensJson`
（`tables.dart:122-126`，`from < 5` 迁移加的）。

**关键约束（不能连带乱删）**：`DietaryLabel` / `FoodAllergen` 两个 enum
**与「我的 → 饮食约束（profiles 侧）」共用** —— `planning_constraints.dart`、
`constraints.set` chat 命令（`chat_edit_registry.dart:620-649`）、
`DailyPlanEngine` 的过敏过滤（`daily_plan_engine.dart:376-379`）都在用**profiles 的列**。
所以本轮**只删食物侧**（3 列 + 弹窗区块 + 种子导入字段），
**profiles 侧的过敏回避功能保留**。

**副作用（要如实处理）**：`foods.allergensJson` 是 `DailyPlanEngine` 过敏过滤的
**唯一食物侧输入** ⇒ 删掉后，每日计划 solver 的 `allergen_conflict` 原因码**失去
食物侧依据**（`daily_solver.dart:21,44-45`）。处理见裁决 D5。

### 需求 51–57 · 食物大库：格式升级 + 内置/自建 + 导入导出 + 去重

> 「升级一下食物库的数据库格式，我需要一个大库，大库数据分为内置和自建，
> 食物需要内置/自建标签，品牌（可以留空），种类，热量，蛋白质，碳水，脂肪几大指标，
> 自建需要用户在食物库手动添加，大库数据可以导出为csv格式，
> 然后设置界面需要留有添加食物数据入口，支持导入符合格式的新食物数据，
> 加入大库数据中（添加的食物可以识别内置/自建标签），如果有重复的食物数据支持提示去重。」

拆成 7 条：

| 编号 | 要求 | 现状实测 |
|---|---|---|
| **51** | 数据库格式升级为一个「大库」，分内置/自建 | **已经是一个表**（`Foods`，`:110-142`），内置/自建已由 `isUserCreated` 表达（`:120-121`，`state` 是平行派生列）。「升级」的实际缺口 = **种类未落库**（内置 49,444 行 `category` **全为 null**，`food_seed_importer._parseSeed` 不写；自建也不写，`food_repository.dart:111-129` 不含 category） |
| **52** | 字段：内置/自建标签、品牌（可空）、种类、热量、蛋白质、碳水、脂肪 | 品牌 `brand`（`:113`，nullable）✅、四个宏量 ✅、内置/自建 ✅；**种类缺**（DB 有列、无值；`FoodCategory` enum 只在**展示层**按关键词猜，`food_category.dart:57+`） |
| **53** | 自建在食物库手动添加 | 已有（`new_food_dialog` + `food_library_view._editItem`）✅ —— 需补**种类**字段 |
| **54** | 大库导出 CSV | **不存在**（`csv_exporters.dart` 只有 meals / training 两张；`foods` 不在 `CsvExportTables`） |
| **55** | 设置页留「添加食物数据」入口 | 设置页有 `settings-catalog-import`（**导入扩展目录**，`settings_page.dart:492-507`，与本需求不同）；**没有**「添加食物数据」入口 |
| **56** | 导入符合格式的新食物数据，识别内置/自建 | **不存在**（全仓无食物 CSV 导入；唯一的 CSV 解析在 `menu_file_importer.dart:220`，导的是**菜单**不是食物） |
| **57** | 重复食物数据提示去重 | **不存在**（无任何重复检测；`foods` 无唯一约束） |

### 需求 58 · 用用户给的供应商做 AI 接管能力多条件测试

> 「另外，用我给的供应商测试ai接管能力，检查有没有无法识别指令的情况（多条件测试）」

**现状（AI 架构，勘察实测）**：不是 tool-calling，是**JSON 信封**
—— `ChatEditCommandRegistry.renderProtocol()`（`chat_edit_registry.dart:31-55`）
把 **23 条命令**渲染成系统提示的一段文字，模型输出
`{"reply":…,"edits":[{"action":…,"args":{…}}]}`，由 `parseChatEditTurn`
（`chat_edit_turn.dart:70+`）解码。**无法识别的指令有三种落法**：
① 模型自己说「做不到」（纯文本）；② 输出未注册的 `action`
（→ 行级 `不支持的修改类型「X」`，`:120-127`）；③ 信封压根不合法
（→ 当纯文本闲聊，`:75-87`）。

**已存在的 live 测试基建**：`test/live/ai_live_endpoint_test.dart`
（P11，**默认整组 skip**，`LF_LIVE_KEY` 未设时零外呼；key 只进环境变量，
不落仓库文件；可选 `LF_LIVE_KEY_PAID`/`LF_LIVE_MODEL_PAID`/`LF_LIVE_LOG`）。
**尚无多条件/多意图测试**（勘察确认：没有任何一条测试发复合请求）。

**用户给的供应商**：本机 `~/.zcode/v2/provider_config.json` 里有 **21 个**供应商
（幻城 / Docode / agrouter / 星见雅 / 小学生 / s3api / oaiapi / amd / kiosapi /
vyceai / jasper / Fate / 露娜（付费组）/ 露娜（免费组）/ 白雨 / doulor / 天使api /
zynk / 露娜无限 / xxzl / sheapi）。**取哪一个、用哪个模型由用户指定**（裁决 D8）。

---

## 2. 裁决（D1–D9）

### D1 · 本轮是「第四轮」，编号续 38 起，不重开 docs/30

`docs/29` 用到 37 号。本轮 21 条续 **38–58**，写进本文件；`docs/30` 的 R1–R8
保持「已交付、无规范效力」的历史记录，不改写。**理由**：用户每轮的意见都是
独立一轮，重开旧方案的编号会让「需求 N」在仓库里指两个东西。

### D2 · 周/月切换：取用户第二张图的**形态**，压掉它的**尺寸**（需求 39）

用户第二张图 = 统一灰轨道 + 内嵌白色凸起滑块（选中绿字）。**照形态做**：
一个 `LfSegmentedToggle` 式的单一控件（轨道 + 滑块 + 两段标签）。
**但不照它的 48dp 布局盒** —— R3 用户嫌的就是那个高度。
指标：**视觉轨道高 28dp**（与设计稿 CSS `.segmented{padding:2} + .seg{height:24}`
一致）、滑块与轨道等高减 2、**命中盒仍 ≥44dp 但用不参与布局的方式**
（`SizedBox` 外套 / 负 padding 思路由实现定，验收是**卡头行高 ≤ 32dp 且
命中区域 ≥44dp**）。

> 这一条是**对立的两个要求的合成**（R3「太大」vs R4「要这个形状」），
> 合成口径写死在代码注释里，免得下一轮又来回摇。

**顺带**：用户写的是「**日月**的切换」。按上下文（体重卡 + 同句「一周就…七天」）
判为「周月」的笔误，**仍是周/月**；若用户其实想要日/月切换，走 D2 备注改。

### D3 · 月视图副标题：删「较月初」三字，**保留**箭头与增减量（需求 43）

用户原话是「下边不要写**较月初**」——删的是**那三个字**。箭头 + 数值
（`↑ 0.8`）是需求 38「不丑」的一部分信息，且删了会让「最新 65.0 kg」这行
失去趋势信息。**只删后缀串**。

### D4 · 「添加」按钮：新增 icon-only 的共享件，不硬塞 `LfTextButton`

需求 44 要「只要图标」。`LfTextButton`/`LfPillButton` 的 `label` 都是
`required String`，塞空串是**滥用共享件**（还会破坏它们各自的
`LfText.caption` 排版断言）。做法：在 `lf_buttons.dart` 增
**`LfIconButton`（icon-only，36dp 视觉 / 44dp 命中盒，tone 档复用 `LfPillTone`）**,
体重卡用它（`Icons.add`）。**不**复用 `LfCircleIconButton`（那是 top bar 家族、
语义是次要页操作，且被既有测试按 top bar 语义钉住）。

### D5 · 删掉食物侧过敏原后，`allergen_conflict` 原因码**降级为「仅用户侧」并如实改名

删 `foods.allergensJson` 后，solver 再也拿不到「这道菜含什么过敏原」。
**不伪造**（不能凭空给食物打过敏原）。做法：
① `SolverCandidate.allergenConflicts` 恒为空集 ⇒ 该原因码**不再可能产生**；
② 保留 `profiles.allergenAvoidancesJson` 与 `constraints.set`（用户仍可声明
「我花生过敏」），但**它不再影响每日计划候选** —— 必须在 `docs/07 §9.3` 与
设置页文案里**如实说明**「过敏回避不再过滤推荐」（否则就是「能设却不生效」的谎）；
③ `daily_solver` 的 `allergen_conflict` 分支**保留**（不删代码路径，因为
solver 是纯函数、将来接回数据源时不必重写），但加注释写明**当前无输入源**。
> 这是本轮最需要用户知情的取舍：**「删过敏原标签」的代价是「过敏回避不再过滤
> 推荐」**。若用户要保留过滤能力，唯一诚实的做法是保留 `foods.allergensJson`
> 只删 UI —— 已在裁决备注里留了这条退路。

### D6 · 电子体重秤：**仅前台、用户主动同步**；不做后台自动导入

用户原话是「**能不能**支持…可以**自动导入**体重数据」——问的是能力。
勘察结论（§1 需求 47）：真正的自动（后台监听）需要**通知 + 前台服务**整套
基础设施（本仓**零**）+ Android 12+ 后台 BLE 限制。做法：
① 设置页加「电子体重秤」行（与步数行同构）：**未授权 / 已授权 / 设备不支持**；
② 新增 `MethodChannel('localfit/scale')`，**仅前台扫描 + 连接 + 读一次**，
把读数落库；
③ 写入**必须**区分来源（`source: 'ble_scale'`）且**默认不覆盖当天已有记录**
（覆盖要让用户明确选择）—— 否则同步会静默毁掉手输值（勘察实测的既有缺陷）；
④ 需要新增蓝牙权限（minSdk 24 ⇒ `BLUETOOTH`/`BLUETOOTH_ADMIN`（≤30）+
`BLUETOOTH_SCAN`/`CONNECT`（31+，`neverForLocation`）），**并且**在 API ≤30
上扫描要 `ACCESS_FINE_LOCATION` —— 而它被 `privacy_statement_audit_test.dart:82`
**明文禁止**。这条**必须**先改测试 + `docs/08`，且**只有**在用户接受
「为秤加定位权限」时才做（见 **D6 备注**）。
⑤ 小米体重秤的协议是**厂商私有 BLE GATT**（服务/特征 UUID 未公开在 AOSP），
    实测只能对**真机 + 真秤**做；本轮**验收上限 = 通道契约 + 权限流 + 落地规则 +
    假设备单测**，真机对秤**明确记为未验证**。

> **D6 备注（需用户拍板）**：加 `ACCESS_FINE_LOCATION` 会**实质降低**
> 本仓「零位置权限」的隐私姿态（`docs/08` 的卖点之一）。可选替代：
> 只声明 API 31+ 的 `BLUETOOTH_SCAN`（带 `neverForLocation`）并把**扫描**限制在
> API 31+，API ≤30 的设备显示「本机不支持电子秤」（诚实降级、不撒谎）。
> **本方案默认取后者**（不加定位权限），因为「不加新敏感权限」比「多支持老设备」
> 更符合本仓既有硬约束。用户若要老设备也支持，再改。

### D7 · 食物库「大库」：**不新建第二张表**，而是把现有 `Foods` 用起来

勘察确认「一个大库 + 内置/自建」**已经存在**（单表 + `isUserCreated`）。
真正的缺口是 ①**种类没值**、②**无 CSV 导入导出**、③**无去重**、④**设置页无入口**。
新建表的做法**会**破坏 `backup_table_registry` 的双向对账
（`export_restore_test.dart:434-448` 把注册表与 `database.allTables` 对账）
与既有 49,444 行种子。做法：
① **种类**：内置行**按名字回填**（复用既有 `FoodCategory.classify`，
   确定性、可测试），自建行由**表单选择**（枚举下拉，不是自由文本）；
② **CSV**：新增 `foodsCsv()` 导出（列 = 需求 52 的七项）与**导入器**，
   导入走**同一个 `FoodRepository.create`**（不绕开校验）；
③ **去重**：按 `(name, brand)` **规范化后**比对（trim + 大小写 + 全角半角），
   命中时**提示**「已存在 N 条同名，仍要导入吗」——**提示**而不是静默跳过
   （用户要的是「支持提示去重」）；
④ **入口**：设置页新增「添加食物数据」行 → 同一弹层（手动添加 / 导入 CSV 两个动作）。

### D8 · AI 接管测试：**先建多条件测试骨架，供应商与 key 由用户给**

流程按用户既有纪律（`test/live` 的 `LF_LIVE_KEY` 模式，key 只进环境变量、
不落仓库）。做法：
① 新增 `test/live/ai_takeover_multi_intent_test.dart`：**多条件/多意图**用例
（一条消息里同时含 ≥2 个意图，跨命令族；含否定、含模糊指代、含需要快照 id 的引用）；
② 逐条记录**三态**：`parsed`（信封合法）/ `unknown_action`（模型编了没注册的动作）/
`plain_text`（模型只回话、没出信封）——**报告要区分「模型不行」与「我们没实现」**；
③ 产出一张 **23 命令 × 多条件覆盖表**，**列出所有无法识别的指令**（这正是用户要的）；
④ **不在常规门禁里跑**（默认 skip，零外呼）。

### D9 · 仍然：每包先 HTML 稿 → 渲染 360dp 评审图 → 再写原生

沿用 `docs/30 §2 D10` 的流程（用户本轮没提要改）。R1 式的**纯常量/纯删除**包
（如需求 49）可免稿，但**必须在证据文件里写明为什么不需稿**。

---

## 3. 工作包（S1 → S8，每包独立过门禁）

| 包 | 主题 | 需求 | 主要落点 | 设计稿 |
|---|---|---|---|---|
| **S1** | 体重卡重做：统一轨道切换 + 七格空槽 + 窄柱 + 本月体重 + 去较月初 + 纯图标添加 | 38–44 | `dashboard_weight_card.dart`、`weight_bar_chart.dart`（柱宽/空槽）、`weight_chart_points.dart`（周七格）、`lf_buttons.dart`（新 `LfIconButton`）、新 `lf_segmented_toggle.dart` | `今日-体重卡-v2.html` |
| **S2** | 数据层瘦身（schema 22）：删体脂率/肌肉量/食物侧过敏原 + 全库引用清除 | 45、46、50（数据侧） | `tables.dart`、`app_database.dart`（drop 迁移）、`weight_measurement.dart`、`measurement_repository.dart`、`dashboard_page.dart`、`weight_entry_dialog.dart`、`chat_edit_registry/executor/context_loader`、`new_food_dialog.dart`、`food_repository.dart`、`food_seed_importer.dart`、`docs/23`、~10 个测试文件 | 并入 S1 稿（弹窗同屏） |
| **S3** | 食物库满刻度 1000 + 表单字段调整 | 49（+45 的表单侧） | `lf_food_kcal_ring.dart`、3 处测试常量 | 免稿（常量 + 文案，写进证据说明） |
| **S4** | 步数卡未授权态：只留徽标、零布局位移 | 48 | `dashboard_quick_stats_row.dart` | `今日-步数卡.html`（或并入 S1 稿） |
| **S5** | 食物大库：种类落库 + CSV 导出/导入 + 去重提示 + 设置入口 | 51–57 | `food_category.dart`（回填）、`food_repository.dart`、`csv_exporters.dart`（新 `foodsCsv`）、新 `food_csv_importer.dart`、`settings_page.dart`、`new_food_dialog.dart`（种类字段）、`docs/07`、`docs/21` | `食物库-大库与导入导出.html` |
| **S6** | 电子体重秤：设置行 + `localfit/scale` 通道 + 来源标记 + 不覆盖手输 | 47 | `MainActivity.kt`、manifest（**+蓝牙权限**）、新 `scale_channel.dart`、新 `scale_repository.dart`、`measurement_repository.dart`（source）、`settings_page.dart`、`app_router.dart`、`main.dart`、`privacy_statement_audit_test.dart`、`docs/08` | `设置-电子体重秤.html` |
| **S7** | AI 接管多条件实测（用户给定供应商） | 58 | 新 `test/live/ai_takeover_multi_intent_test.dart`、证据 `docs/evidence/2026-10-09-ai-takeover-multi-intent.md` | —（测试包） |
| **S8** | 全局收尾 | — | docs/21（多处）+ docs/08 + docs/23 + docs/07 + INDEX + STATUS + DECISIONS + 全量门禁 + 设备走查 | —（收口包） |

**包内固定动作（每包都做）**：① 先出/更新 HTML 稿并渲染 360dp 评审图；
② 过视觉评审（不可用时按既有约定走程序化探针 + 作者自检并**如实标注不等价**）；
③ 原生实现 + 新断言（先写红再改绿）；④ 每条新断言配**隔离变异**（破坏 → 红 →
还原 → 绿 + sha256）；⑤ `tool/verify.bat` 全量门禁 EXIT=0；
⑥ 更新 `STATUS.md` 与证据文件 `docs/evidence/2026-10-09-s{n}-*.md`。

**顺序理由**：S1/S2 是用户点名的「最丑」与「全删」，且 S2 的 schema 22
是 S5/S6 都要碰数据层的地基 ⇒ 先做；S3 是 S1 弹窗的同屏小改；S4 独立且小；
S5 是最大的一块（要动店铺契约文档）；S6 依赖 S2 的 `source` 与 schema；
S7 不依赖代码改动（只测现状），可与 S5/S6 并行；S8 收口。

---

## 4. 设计稿与校正机制（沿用 docs/30 §2 D10）

1. **每包一份 HTML**，放 `ui设计/remediation/`，文件头写清「覆盖需求编号 / 裁决 /
   与现状的差异」；含 `.screen`（360dp 帧）+ 亮/暗两套 token。
2. **渲染 360dp 评审图**（headless Edge `--force-device-scale-factor=2`，
   方法沿用 P5–P9 / R2–R7 的既有流程），图放 `tmp/render/review_s{n}/`。
3. **视觉评审**：优先 `visual-judge` 子代理；不可用时按既有约定走
   **程序化探针 + 作者自检**，并在证据文件里**明确标注不等价**（不假装做了独立评审）。
4. **评审通过后再动原生**；原生实现后**设备 360dp 走查**复核与稿一致
   （截图归档 `docs/evidence/2026-10-09-*/`）。
5. 稿与最终实现不一致处，**以实测为准并在证据文件里记录差异**（不悄悄漂移）。

---

## 5. 门禁与验证要求

- **每包**：`tool/verify.bat`（`flutter pub get` + `dart format --set-exit-if-changed`
  + `flutter analyze` + `flutter test`）EXIT=0。
- **新断言 + 隔离变异**：每包至少 2 条隔离变异（破坏 → 红 → 还原 → 绿 + sha256）。
- **测试 Key 三方对账**：`ui_spec_key_sync_test.dart` 要求 docs/21 §5 Key 表 ⇄ lib
  ⇄ test 三方一致 ⇒ 新增/删除 Key（如 `dashboard-weight-add` 改形态、
  `weight-bodyfat-input` 删除）必须**三处同改**；§5 哨兵（>100 Key）不得跌破。
- **备份注册表双向对账**：`export_restore_test.dart:434-448` 要求
  `LocalFitBackupTables.all` ⇄ `database.allTables` 一致 ⇒ S2 只 drop 列
  （不加表）时不受影响；**S6 若加表必须先加注册项**。
- **隐私门禁**：`privacy_statement_audit_test.dart` 把 manifest 权限**按序**写死
  （:64-83）且禁止 `ACCESS_FINE_LOCATION`（:82）⇒ S6 改权限**必须**同步改该测试
  与 `docs/08`，且**不许**为了让测试变绿而放宽「禁止定位权限」那条。
- **已知会红的既有测试**（实施时逐条处理，**不允许「删断言换绿」而无替代**）：
  - S1：`dashboard_steps_and_weight_test.dart`（周视图 7 点的口径变了：
    从「最近 7 条记录」变「本周 7 格含空槽」）、`dashboard_page_v2_test.dart`（标题/副标题）、
    `dashboard_breakpoint_test.dart`、`bento_layout_test.dart`（柱宽）。
  - S2：`app_database_v17_migration_test.dart`、`chat_edit_executor_test.dart`、
    `weight_entry_date_test.dart`、`sheet_action_row_keyboard_test.dart`、
    `dashboard_page_v2_test.dart`、`food_repository_test.dart`、
    `food_seed_importer_test.dart`、`daily_plan_engine_test.dart`、`daily_solver_test.dart`、
    各 `*_migration_test.dart` 的 DDL fixture（含新删的列，**fixture 是「历史版本的
    真实形状」，不是断言当前列** —— 只有断言「迁移后列仍在」的那几条要改）。
  - S3：`food_library_ui_test.dart:288`、`food_detail_sheet_test.dart:243`、
    `nutrition_presentation_design_test.dart:166`。
  - S5：`settings_backup_test.dart`（设置页新行）、`csv_exporters_test.dart`。
  - S6：`privacy_statement_audit_test.dart`、`steps_permission_row_test.dart`（同页新行）。

---

## 6. 本轮明确**不做**（避免范围蔓延，逐条给出理由）

1. **后台自动同步体重秤**（应用未打开也能导入）：需要通知 + 前台服务整套新基础设施
   （本仓零），且 Android 12+ 后台 BLE 有系统级限制。本轮回前台主动同步（D6）。
2. **API ≤30 设备的体重秤支持**：需要 `ACCESS_FINE_LOCATION`，与既有隐私姿态冲突
   （D6 备注）。默认不加，老设备显示「本机不支持电子秤」。
3. **真机对秤验证**：无真秤/真机，本轮验收上限是通道契约 + 权限流 + 落地规则 + 假设备单测。
4. **`foods` 建唯一约束**：去重按需求是「**提示**」不是「强制」，且既有 49,444 行
   种子未做唯一性审计，加约束可能直接迁移失败。去重做在**导入路径**（用户可跳过）。
5. **`DietaryLabel`/`FoodAllergen` 两个 enum 的删除**：profiles 侧功能仍在用（D5）。
6. **iOS 侧电子体重秤**：本机无 iOS 环境（与 `docs/08 §6` 一致）。
7. **把 49,444 行种子的 `category` 重新生成**：只做**确定性回填**
   （`FoodCategory.classify`），不重跑 ETL、不改 `assets/seed/*.json`
   （改种子会让 `design_source_parity_test` / 种子校验大面积变红，收益不成比例）。
