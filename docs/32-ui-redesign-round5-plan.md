# 第五轮界面与体验重构方案（需求 59–79）

> 立项日期：2026-10-11。**二次修订 2026-10-11**（合并新增引导页设计稿、食物库清空重建、通勤确认、秤接口预留、弹层方案改定）。
> 来源：用户一次性反馈 **15 条**（12 项改动 + 3 个提问）+ 8 张真机截图
> （`docs/evidence/2026-10-11-round5-feedback/01..08.jpg`，逐条对应见 §1）+ **新增设计稿** `ui设计/pages/初始引导.html`（借鉴清单见 §8）
> + **第二轮 6 条追加需求**（74–79，见 §1 下半）。
>
> **本文件是本轮唯一权威源。** 它**自我包含**：不引用任何既往文档（含 `docs/21`、`docs/23`、`docs/30`、`docs/31` 等）的规范陈述；
> 凡涉及现状的描述都直接标注**代码事实**（`文件:行号`），与代码不一致时以代码为准并先更新本文件。
> 旧文档中任何与本文件冲突的内容，对本轮一律作废。
>
> **本轮已由用户明确定案 8 处**（§3/§8 内以「✅ 用户已定」标记）：D10 通勤全链路删除（副作用确认）、
> D5 生成今日吃法降级为对话建议（接受）、D13 彻底移除随包食物种子、D15 训练弹层用方案 B（保留拖动放大）、
> D16 电子秤先预留接口后期适配、D17 三行导出文案定稿、**§8.3-1 阶段条为视觉进度指示（不拆分步）**、
> **§8.3-2 底部 CTA 取现有 token h48**。

---

## §0 术语、工作纪律与交付纪律

**术语**

| 词 | 指 |
| --- | --- |
| AI 创作 | 画廊页（路由 `/ai-workbench`），今日页「AI 健康助手」横幅进入；截 03 |
| AI 工作台 / 对话页 | 底栏中央 AI 按钮进入的对话分支（路由 `/ai-chat`）；有消息流、流式回复、编辑卡 |
| 启动器（starter） | 创作页的一张任务卡：点开→描述需求→生成→跳对话 |
| 编辑卡 | 对话里对「模型提议的结构化修改」的展示卡，按钮「全部应用 / 忽略」 |
| 资料卡 | 「我的」页顶部身份卡；其「编辑资料」进入的页面（`/profile-edit`）承载身体与目标字段 |

**工作纪律（本轮全部工作包共同适用，逐条验收）**

1. 每个工作包独立过全量门禁 `tool/verify.bat`，**EXIT=0**；format 步骤报漂移必须手动 `dart format` 后重跑。
2. **红先测试**：每条新断言先写出会失败的测试；**每条新断言配一次隔离变异**（破坏→RED→还原→sha256 与还原前一致→GREEN）。
3. **UI 包先出 HTML 稿（自检制，v3 起不再送用户审批）**：360dp 稿先行，**作者自检两轮**——
   第一轮：程序化探针（帧宽 360dp / 无横向溢出 / 关键几何与 token 逐值）＋ 逐帧目视；
   第二轮：对照 §3 裁决与 §6 不动契约**复查一遍**（含文案、Key、返回值语义、边界态），
   把发现的瑕疵**当场改掉**再复跑探针，然后**直接进入原生实现**，不等待用户答复。
   实施顺序改为：出稿 → 自检 ×2（修瑕疵）→ 写原生 → 红先测试 → 变异 → 门禁 → 证据。
   证据里仍须记「自检两轮各查了什么、改掉了什么瑕疵」；`visual-judge` 不可用时以作者自检 +
   程序化探针替代，并在证据里**明确标注不等价**。
   （2026-10-12 用户指示：「后续所有设计稿无需我来审批，你自己核对 2 次，修改掉瑕疵后自动执行就行」）
4. 每包一份证据 `docs/evidence/2026-10-xx-*.md`（含方法与限制、变异记录、门禁输出、如实限制）；同步 `STATUS.md` 与 `docs/INDEX.md`。
5. **不发布 / 不推送 / 不提交**；API key 只进环境变量，不落仓库、不打进日志。
6. 设备走查纪律：坐标以 `uiautomator dump` 为准，截图只作证据（截图会滞后一帧）。
7. 性能敏感测试（如 50k 目录搜索 <100ms 单次计时）在**安静机器**上跑门禁；本轮**不修改**其预算口径（改抗抖口径属测试合同变更，留待用户单独裁决）。

---

## §1 用户需求逐字归档（59–73 为第一轮；74–79 见 §1.2）

| # | 需求（用户原话，保留语气与断句） | 截图 |
| --- | --- | --- |
| 59 | 「首页进入时，选择目标后，计算的数据，这个抽屉式弹窗里的数据太丑了，要图形化显示，设计一下。」 | 01 |
| 60 | 「体重卡片还是有问题，月视图也要留本月所有天数的位置，月视图柱子细一点，另外右上角的添加按钮的大小要跟周/月切换按钮的上下宽度一致。」 | 02 |
| 61 | 「柱状图的左坐标轴设置 4 个刻度，体重卡的柱子可以点击，点击后有小浮窗显示体重的数值（可以放在柱子顶部外侧，小一点就好）。」 | 02/04 |
| 62 | 「AI健康助手里边的AI创作，你根据软件现有的功能进行重新设计，并且优化界面显示，要美观，另外我希望能跟AI工作台链接，这个里边的按钮点击后，描述需求后点击生成就自动跳转到AI工作台，进行生成，结果就展示在工作台的对话里。」 | 03 |
| 63 | 「今日饮食的今日还没有记录的卡片要完整填充卡片（我的意思是左右边距相同，而不是只占据左边一点点位置）。」 | 04 |
| 64 | 「步数的目标可以自行设置，可以放在我的界面的资料卡里设置。」 | 04/08 |
| 65 | 「今日推荐里的查看菜单和确认加入计划按钮要相同上下宽度。」 | 05 |
| 66 | 「优化软件内所有下拉选项弹窗的流畅性和显示风格和大小，比如这个食物库的种类选项。」 | 06 |
| 67 | 「食物库的实物卡片点开后的抽屉式卡片上边的拖动按钮，拖动的话卡片会抖动，请检查修复，确认所有其他类似的卡片有没有相同的问题，并修复。」 | — |
| 68 | 「动作库卡片的底部边距还是有点大，留白很多，再缩小一点，跟上边距最少的地方一致。」 | 07 |
| 69 | 「我的界面头像和昵称需要支持编辑，昵称下边的已坚持n天及后边的句子都删掉，然后重新对齐昵称和头像的中心高度一致，另外，其他界面的头像按钮，均可点击跳转到我的界面。」 | 08 |
| 70 | 「我的界面的食物数据库编辑部分的导入拓展食物目录和添加自定义食材按钮都可以删掉了，下边的添加食物数据已经全包括了，通勤时间也删掉（全软件检查有没有遗漏）。」 | 08 |
| 71 | 「导出csv是导出什么，跟下边两个有什么区别。」（提问） | 08 |
| 72 | 「水分摄入目标是怎么得出的，如果是靠数据计算的，就没事了，如果是自定义的，那就在资料卡里再提供一个编辑水分目标。」（条件式） | 08 |
| 73 | 「电子体重秤支持什么体重秤，小米体重秤为什么不能支持，要怎么才能支持？」（提问） | — |

**截图索引**：01 onboarding「确认每日目标」抽屉（04:41）；02 今日页 本月体重（04:44）；03 AI 创作画廊（04:51）；
04 今日页 本周体重 + 今日饮食空态 + 步数未授权（04:55）；05 食堂目录「今日推荐」（04:58）；
06 新建食物「种类」下拉展开态（05:00）；07 动作库卡片（05:04）；08 我的页身份卡 + 健康数据（05:06）。

### §1.2 第二轮追加需求（74–79，2026-10-11 同日）

| # | 需求（用户原话，保留语气与断句） | 归属 |
| --- | --- | --- |
| 74 | 「我添加了初始引导界面的设计稿，需要你合并一下目前主题样式和设计稿的优势之处，**图标什么的按现有的来**，更新一下布局什么的，你看一下哪些可以借鉴，添加到开发文档中。」（稿 = `ui设计/pages/初始引导.html`） | T15 |
| 75 | 「**导入扩展食物目录不需要**，我更新了食物数据库的结构，以后按新的来，需要重新导入 csv 格式的新食物数据，**现在的 4.9 万个数据都要删掉，清空就行**。」 | T11 + T13 |
| 76 | 「导出 CSV 这个文字你要写清楚，是导出**饮食记录**，把另外两个的名字后边的 csv 字段都删掉，就写**导出饮食记录、导出训练记录、导出食物数据**三个就行了。」 | T12 |
| 77 | 「我不需要**通勤时间**这个设计，你从全部地方删掉就行，不要漏。」（副作用确认：推荐失去通勤感知、旧备份丢该字段） | T8 + T16 |
| 78 | 「小米秤：**先预留接口，后期适配**。」（不再要求给型号/真表） | T14 |
| 79 | 「训练页两个弹层会失去『拖动放大』手势……这个有没有更好的解决方式。」→ 采纳**方案 B**（保留拖动放大） | T5 |

**⚠️ 两处用户判断与代码实际不符（已核实，按代码事实执行并已回报用户）**

1. **4.9 万条食物不是「导入扩展食物目录」来的**。该目录机制（`CatalogBootstrap` + `assets/catalog/` 分片）**已停用**：`assets/catalog/` 目录**不存在**，pubspec 不再声明任何 `.sqlite` 分片，`prepare()` 因拿不到 manifest 而直接空转（`lib/features/nutrition/data/catalog_bootstrap.dart:75-102`）。真正的数据源是**随包 JSON 种子** `assets/seed/foods.v5.json`（11,342,444 B，49,444 条），由 `FoodSeedImporter.importIfNeeded()` 在 `lib/main.dart:106` **每次启动前同步导入**。⇒ **只清库无效**：下次启动原样灌回。必须同时移除随包种子（D13/T13）。
2. **仓库里找不到用户所说的「新食物库结构」**。当前 `foods` 表 17 列、CSV 8 列（§2·75 有完整列清单），`ui设计/remediation/食物库-大库与导入导出.html` 的 8 列契约与当前实现**逐字一致**，未含任何新列 ⇒ 新表头**待用户提供文件**后定稿（T11 留占位）。

---

## §2 现状核对与缺漏 / bug 分析（逐条，全部为代码事实）

### 59 · onboarding「确认每日目标」抽屉

- **现状**：四行数值是**同一个 `Text` 用 `\n` 拼的纯文本**，无任何图形元素 —— `lib/features/onboarding/presentation/onboarding_page.dart:307-336`（内容 :311-318）。
  弹层壳是 `AppSheet`（`lib/app/design/widgets/app_sheet.dart:146-208`）：标题 → 12dp → 内容 → 16dp → 按钮行（「返回修改」文字按钮 + 「确认保存」胶囊）。
- **数据来源**：`NutritionTargetCalculator().calculate(...)` 的 `calorieMin/MaxKcal`、`proteinMin/MaxGrams`、`carbsMin/MaxGrams`、`fatMin/MaxGrams`（`lib/features/onboarding/domain/nutrition_target_calculator.dart:34-57`）。
- **缺漏**：无图形化；四条数据没有视觉层级（热量与三个宏量等权排列）。

### 60 · 体重卡月视图 / 添加按钮尺寸

文件：`lib/features/dashboard/presentation/sections/dashboard_weight_card.dart`、`lib/app/design/widgets/weight_bar_chart.dart`、`lib/features/progress/domain/weight_chart_points.dart`。

- **月视图不是「本月每一天」**：`weightMonthMaxBuckets = 5`（`weight_chart_points.dart:22`），按**记录点序**连续切箱（`bucketSize = ceil(n/5)`），每箱取均值，标签=箱内最后一条记录的日期（`:100-121`）。
  ⇒ 用户截 02 里只出现 `10/2 10/4 10/6 10/11` 四根柱、中间大片空白，**没有本月其它天数的位置**。
- **月视图柱宽 22dp**：`maxBarWidth = 22`（`weight_bar_chart.dart:59`）+ 格内左右各 8dp（`:62`）⇒ 月视图格宽 ≥52dp，柱恒顶到上限 22dp。周视图格宽 ≈37dp、柱 ≈21.4dp。
- **添加按钮比切换控件高**：卡头顺序 `[＋][8dp][周/月切换]`（`dashboard_weight_card.dart:111-135`）；「＋」视觉圆 **36dp**、命中盒 44（`lib/app/design/widgets/lf_buttons.dart:374,411-413`）；
  切换件轨道视觉高 **28dp**、滑块 24、段宽 44、命中盒 44（`lib/app/design/widgets/lf_segmented_toggle.dart:55-69,88-103`）⇒ 两个控件视觉高度 36 vs 28 不一致（用户看到的正是这个）。
- **顺带发现的 2dp 偏差（既有缺陷）**：切换件轨道内文字 `Row` 左对齐（中心 x=22/66），而滑块 `left = 2 + i×44`（中心 24/68）——文字比滑块偏左 2dp（`lf_segmented_toggle.dart:88` vs `:109-128`）。本轮一并修正。
- **月视图观感「有问题」的第二个成因（数据侧，如实记）**：用户真机数据里 10/2 有一条远高于日常的体重（截 02 轴顶 223.9），轴按 `pad = 范围×25%` 拟合（`weight_bar_chart.dart:68-87`），把其余 43–60kg 的柱压成矮条。本轮**不改数据**；靠 4 刻度 + 柱点击浮窗让读数可辨（D2）。

### 61 · 坐标轴刻度数与柱交互

- **现状**：Y 轴 **3 档**刻度 + 3 条虚线（`weight_bar_chart.dart:85-86`，y = 0/65/130），标签 `toStringAsFixed(1)`（`:91`）；轴列宽 30dp、绘图区高 130dp（`lib/app/design/widgets/lf_dimens.dart:61,65`）。
- **现状**：柱是裸 `Container`，**全图零触摸交互**（文件内无 `GestureDetector/InkWell/onTap`）；唯一无障碍摘要是 `ChartSemantics`（`:113-114,297-314`）。

### 62 · AI 创作（画廊）与 AI 工作台（对话）

- **画廊现状**：`lib/features/ai_workbench/presentation/ai_workbench_page.dart`（宫格 `AiWorkbenchHub` :88 + 详情 `AiWorkbenchTaskDetail` :215，标题「AI 创作」:55/:105）；
  6 个任务由 `AiWorkbenchTask`（`lib/features/ai_workbench/application/ai_workbench_task.dart:9-62`）在 `lib/main.dart:361-455` 组装；
  点格子只 `setState` 开详情（`:80-83`），详情内是 `AiTaskCard` 相位机（`lib/features/ai/presentation/ai_task_card.dart:165-365`：idle→running→ready→确认写入/failed/cancelled/confirmed）；
  生成走**任务合同**：`OpenAiCompatibleTaskCapability` + `PromptCatalog` 模板 + 各任务严格 decoder（**不走**对话的 chat-edit 信封）；
  咨询型两任务（这道菜怎么吃、常吃搭配）不传 `onConfirm` 故无写入按钮（`dish_guidance_workbench_task.dart:69-84`、`meal_pairing_workbench_task.dart:79-94`）。
- **对话页现状**：`lib/features/ai_conversation/presentation/ai_conversation_page.dart`（shell 第 3 分支，`app_router.dart:365-392`）；
  消息模型 `ConversationMessage`（role/status/kind/editTurn，`domain/conversation_message.dart:5-55`）；SSE 流式（`data/open_ai_compatible_conversation_service.dart:162-273`）；
  23 条结构化命令以 chat-edit JSON 信封解码 → **`ChatEditCard`**（`presentation/chat_edit_card.dart:11`）逐行展示 + 「全部应用/忽略」（page :396-412、controller :481-533）；历史落 drift 表 `ConversationMessages`。
- **两者今天零衔接**：两个 feature 目录互不引用；对话页**没有**任何进「AI 创作」的入口；今日页横幅进的是**画廊**（`dashboard_ai_entry_card.dart:19-27` → `app_router.dart:305-306`）。
- **预填/自动发送机制：不存在**。输入框状态由页面 State 私有持有（`ai_conversation_page.dart:77,93`）；分支 builder 丢弃 route state（`app_router.dart:474-480`）；唯一先例是 canIEat chip **只预填不发送**（`:226-233`）。
- **命令覆盖映射（本轮的核心事实，逐条实测注册表）**：`lib/features/ai_conversation/domain/chat_edit/chat_edit_registry.dart` 共 23 条 ——
  `canteen.venue.create/rename/delete`、`canteen.window.create/delete`、`canteen.dish.create/update/delete`、
  `dish.upsert`、`dish.delete`、`food.create`、`meal.create/update/delete`、`meal.item.update/delete`、
  `water.add/delete`、`weight.log`、`profile.goal.update`、`constraints.set`、`commute.set`、`workout.plan.delete`。
  | 创作页任务 | 对话能力 | 判定 |
  | --- | --- | --- |
  | 解析学校菜单 | `canteen.venue.create` → `canteen.window.create` → `canteen.dish.create`（同信封链式） | ✅ 覆盖 |
  | 分析菜品营养 | `dish.upsert`（name/slot/kcal/protein… 必填，每份口径） | ✅ 覆盖 |
  | 生成今日吃法 | **无**计划写入命令（引擎 `confirmCandidate` 写 `dailyPlanCandidates`+`dailyPlans`，`daily_plan_engine.dart:205-232`；该路径现由食堂页「确认加入计划」可达） | ❌ 缺 |
  | 这道菜怎么吃 | 咨询型，对话原生 | ✅ |
  | 训练计划 | **无**创建命令（只有 `workout.plan.delete`）；`WorkoutPlanRepository.create(WorkoutPlanDraft)` 存在（`training/data/workout_plan_repository.dart:117`），校验 `_validateDraft` :240-259（名称非空/每星期唯一/每天≥1 动作/组次正整数）+ `_requireExercise` :309 | ❌ 缺 |
  | 常吃搭配 | 咨询型；快照含菜品库/食堂目录/餐记录 | ✅ |
- **快照分段（模型能看到的上下文）**：`data/chat_edit_context_loader.dart:71-78` 共 8 段 —— 当前目标 / 手动通勤 / 今日与昨日餐记录 / 菜品库 / 食堂目录 / 今日饮水 / 最近体重 / 训练计划。**没有动作库段** ⇒ 若新增「创建训练计划」命令，模型无法引用动作 id，必须补一段（D5/T6b）。
- **参数类型系统**：`domain/chat_edit/chat_edit_command.dart:9-38` 已含**组合类型先例**（`foodItems` = `[{"food":文本,"grams":数字}]`、`stringList`）⇒ 计划类嵌套参数可循同一机制扩展，无需改信封格式。

### 63 · 今日饮食空态卡片

- `lib/features/dashboard/presentation/sections/dashboard_meal_timeline.dart:286-315` 的 `_EmptyTimeline` = `MutedBlock`（`lib/app/design/widgets/design_card.dart:126-146`：`DecoratedBox` **无宽度约束**、padding 12、muted 底）。
  父级 `Column(crossAxisAlignment: start)`（`:73-76`）⇒ 只占左侧一小块（用户截 04 的现象）。

### 64 · 步数目标

- **硬编码常量**：`static const int dailyStepGoal = 10000;`（`lib/features/dashboard/presentation/sections/dashboard_quick_stats_row.dart:172-175`，注释自述「用户可在设置里改是后续项」），使用点 :266-267/:375-415/:459。
- 无任何编辑入口；设置页只有「步数与身体活动」权限行（`settings_page.dart:435-439`，只读授权状态）。
- 可复用存储：`AppSettings` 键值表（`lib/data/database/tables.dart:826-833`）+ `AppSettingsRepository`（`lib/features/settings/data/app_settings_repository.dart`）；已有绕过仓库直写的先例 `steps_baseline`（`lib/features/dashboard/data/steps_repository.dart:35-36,98-106`）。

### 65 · 今日推荐两个按钮

- `lib/features/daily_plan/presentation/next_meal_decision_card.dart:337-382`：`Wrap(spacing:8)` 一排 ——
  「查看菜单」= `LfPillButton(tone: muted)` **h32** 胶囊（`lf_buttons.dart:270-337`）；
  「确认加入计划」= `LfPrimaryButton` **h40**、圆角 16（`lf_buttons.dart:95-184`）；
  另「换一个」「调整时间」同为 h32。⇒ 同排混高 32/40（用户截 05 的观感）。

### 66 · 下拉弹窗

- 全库 **12 处** `DropdownButtonFormField`（无 `DropdownMenu`/`showMenu`）；仅 3 处做了精修（`isExpanded:true`+`itemHeight:null`+`selectedItemBuilder`+item 内 8dp）：
  `nutrition/presentation/new_food_dialog.dart:193`（种类，截 06）、`settings_page.dart:1112`（协议）、`:1264`（推理）；
  其余 9 处吃 M3 默认（`onboarding_page.dart:131` 活动程度、`training/presentation/sections/planned_entry_sheet.dart:66,89`、`training_page.dart:759,1819`、`food_scan/presentation/scan_candidate_editor.dart:123`、`ai_workbench/application/daily_menu_plan_workbench_task.dart:387`、`training/presentation/exercise_library_page.dart:144,157`）。
- `app_theme.dart` **没有** `dropdownButtonTheme`/`dropdownMenuTheme` 条目（只有 `popupMenuTheme` :351-358）⇒ 9 处默认下拉与 3 处精修版在字号、行高、配色上不一致；点开是 Flutter 锚定式系统菜单（截 06 全屏大行距列表）。
- **既有先例**：餐次曾从下拉改成横排胶囊，注释明写嫌「系统菜单」形态（`nutrition/presentation/meal_editor_dialog.dart:23-25` + `_SlotPill` :486-538）；选日期也是自绘弹层（`progress/presentation/date_picker_sheet.dart:10-16`）。

### 67 · 抽屉拖动抖动（及同类排查）

- **食物详情抽屉**：`lib/features/nutrition/presentation/food_detail_sheet.dart:74-88` → `AppSheet.showCustom`（壳参数 `app_sheet.dart:106-139`：`enableDrag:false` + `showDragHandle:true` + `maxHeight 0.9` + 动效 250/150ms）。
  **根因（实锤）**：`food_detail_sheet.dart:130-131` 在 `build` 里创建 `FutureBuilder(future: load())`；而把手拖动起止会 `setState` 切换 `WidgetState.dragged`（Flutter `bottom_sheet.dart:269-273,297-299`）⇒ 重建整棵子树 → 重新 `load()` → 命中 waiting 分支的 24dp 进度圈（`:133-138`）→ 高度跳变 + 拖动位移换算实时读 `_childHeight`（`bottom_sheet.dart:260-263,285`）⇒ **拖动时闪加载、比例跳变**。
- **同类排查结论**：全 lib 只有一份共享壳 `AppSheet`（19 文件 46 处调用，把手统一 `showDragHandle` + `enableDrag:false`）；
  **体系外 5 处裸 `showModalBottomSheet` 全在 `training/presentation/training_page.dart`**：`:911`（计划详情，内含 `DraggableScrollableSheet` 0.6/0.9 :1467-1471）、`:987`（训练进行中，内含 0.75/0.95 :1684-1688）、`:1007`（统计，**未禁整层拖拽**）、`:1026`（训练达标，**缺 `isScrollControlled`**）、`:1051`（个人纪录，缺 `isScrollControlled` 且标题用 `Theme.textTheme`）；
  另有 2 处裸 `AlertDialog`（`campus_menus/presentation/menu_tab_view.dart:423-442`、`settings/presentation/profile_edit_page.dart:105-133`）。
  ⇒ 前两处「外层可拖 + 内层可拖」双体系是结构性抖动风险（外层位移用运行时 `_childHeight` 换算，内层 extent 变化会改变它）。

### 68 · 动作库卡片底部留白

- 卡片 `DesignCard` padding 对称 12（`training/presentation/exercise_library_page.dart:465`）；卡内 图标↔标题 8（:507）、标题↔标签 6（:518）。
- **真凶在行高公式**：`_cardExtent`（`:408-419`）在内容高（36+8+标题+6+标签行）之外 **`return content + 12`** ⇒ 每格多出 12dp 成为卡片底部空白；网格底 padding 另有 16+navReserve（`:357-366`）。

### 69 · 我的页身份卡与头像

- **`profiles` 表没有任何姓名/头像列**（`lib/data/database/tables.dart:27-51`：id/birthYear/biologicalSex/heightCm/activityLevel/dietaryPreferencesJson/allergenAvoidancesJson/planningBudget*/maximumDraftDeclaredMinutes/pantryCoverageEnabled/manualCommuteMinutes/createdAt/updatedAt）。
- 身份卡 `_IdentityCard`（`settings_page.dart:2154`）：头像 56dp 圆（:2180-2200，**无手势**，文字硬编码「Fit」）、姓名「Fit」（:2205-2211）、
  副标题 `settings-identity-subtitle`（:2213-2222，拼接函数 `_subtitle` :2277-2297 = 「已坚持 N 天」+「目标减脂 X kg」等）；「编辑资料」按钮（:2229-2234）→ `/profile-edit`。
  （**2026-10-12 T7 开工前以代码复核更正**：原文的行号区间偏后且把「编辑资料」并进副标题行，均与代码不符。）
- **全 App 只有今日页头像可点**：`dashboard/presentation/sections/dashboard_greeting_header.dart:116-158`（44dp 圆角 16 方块，`onTapAvatar` 由路由注入 `go('/settings')`）。
  `DashboardGreetingHeader` **本身已支持** `displayName`（:18-19/:59-62，用于问候语与首字），但 `dashboard_page.dart:275-281` 未传入 ⇒ 运行时恒显「Fit」。
  对话页顶栏用户头像（`ai_conversation_page.dart:303-321`，36dp 圆 + person 图标）与 AI 吉祥物头像（`lf_chat_bubbles.dart`，`AiMascotAvatar`）均为装饰、无手势；
  对话页**没有**任何跳「我的」的回调（`app_router.dart:369-387` 未注入）。

### 70 · 设置页清理与通勤时间

- 「食材库」组 `settings_page.dart:626-711` 六行：①「食材数据库」计数（无 onTap :635-648）②「导入扩展食物目录（可选）」→ `bootstrap.importAvailable()`（:651-662）③「添加自定义食材」→ `onAddCustomFood`（:663-670）④「添加食物数据」→ 弹层两动作（手动添加 / 从 CSV 导入，:674-681 + :784-833）⑤「维护地点/窗口/菜品」⑥「通勤时间」→ `_editCommute`（:693-708）。
- **重要事实（与用户认知有偏差，需按 D10 处理）**：扩展目录**首启即自动导入**——`lib/main.dart:459` `unawaited(catalogBootstrap.importAvailable())`（注释：放首帧之后，失败不影响启动，原因进 `bootstrap.lastResult`，设置页该行是**可行动提示与重试入口**）；`catalog_bootstrap.dart:51-56` 自述 `prepare()` 复制随包分片、`importAvailable()` 才是几万行写库（即用户真机首启 ~6 分钟慢启动的来源）。
  ⇒ ② 行删除**不损失导入能力**（自动跑），但**会丢掉失败时的恢复入口**——按 D10 保留为「仅失败时渲染」。
- **通勤是一条完整纵切（删除连锁，实测）**：DB 列 `profiles.manualCommuteMinutes`（`tables.dart:43-45`）+ v14 迁移（`app_database.dart:185-189`）+ 生成代码；
  `features/routing/application/route_options.dart:8-10,85-135`（`ManualCommute` + fallback 级）、`routing/application/resolve_commute.dart`、`routing/data/manual_commute_repository.dart`、`routing/presentation/manual_commute_dialog.dart`；
  solver 侧 `daily_plan/application/travel_fit.dart` + `daily_plan_engine.dart:54,80,261,419-421` + `next_meal_decision_controller.dart:11,15,39,50-51,64-73,126-163,210-224,369-395`；
  设置行 + `_commuteFuture/_loadCommute/_editCommute`（`settings_page.dart:38-39,116-118,693-708,713-757`）；
  AI 侧 `commute.set`（`chat_edit_registry.dart:591-604`）+ executor `_commuteSet`（`chat_edit_executor.dart:19,37,51,132-133,432-434`）+ 快照「手动通勤」段（`chat_edit_context_loader.dart:75` + `_renderCommute`）；
  接线 `main.dart:31,337-345,472,487,506`、`app/app_router.dart:7,114,440-443`、`app/localfit_app.dart:7,68,139-140,215`；
  **测试约 16 个文件**（`next_meal_decision_controller_test`、`settings_page_test`、`route_options_test`、`manual_commute_resolve_test`、`travel_fit_test`、`chat_edit_executor_test`、`chat_edit_registry_test`、`chat_edit_context_loader_test`、`app_database_v14_migration_test`、`test/live/*` 等）。

### 71 · 「导出 CSV」是什么（详见 §5.1）

- 三行都走 `lib/features/backup/application/export_csv_files.dart`：`mealsCsv()`（:21-24，文件名 `localfit-meals-*.csv`）、`trainingCsv()`（:26-32）、`foodsCsv()`（:37-45，文件名 `localfit-foods-*.csv`）；
  列定义在 `application/csv_exporters.dart`：meals **12 列**（:25-38）、training **9 列**（:40-50）、foods **8 列**（:54-63，与「从 CSV 文件导入」同表头，可回灌）；
  全部 UTF-8 BOM + 全引号 + 公式注入中和（:188-205）；另有「备份数据」= 加密 `.lfb`（`create_encrypted_backup.dart:26-33`），与三个 CSV 完全无关。
- 设置页三行：`cta-export-csv`（:408-414）→ meals；`backup-export-training-csv`（:415-421）；`backup-export-foods-csv`（:424-430）。

### 72 · 水分目标来源（详见 §5.2）

- `waterTargetMl` 是 `DailyTargets` 表的**列默认值 2000**（`tables.dart:81` `real().withDefault(const Constant(2000))`）；
  **唯一写入点**是 onboarding 建档 insert，且**根本没写这一列**（`onboarding/domain/onboarding_persistence.dart:67-83`）⇒ 恒为 2000，**不是计算出来的**；
  读取方：`features/hydration/data/water_repository.dart:9-47`、`settings/application/load_profile_overview.dart:114-121`、`meal_repository.dart:326`；**无任何编辑入口**。
- 按用户条件（「如果是自定义的，那就在资料卡里再提供一个编辑水分目标」）⇒ 需新增编辑（D11/T9）。

### 73 · 电子体重秤支持范围与小米（详见 §5.3）

- 现状（第四轮 S6 交付）：MethodChannel `localfit/scale`，**前台 10 秒扫描广播标准体重秤服务 `0x181D` 的设备 → 订阅 `0x2A9D`（Weight Measurement）通知 → 读一次断开**；IEEE-11073 SFLOAT 原生侧解析为克；仅公制；`source: 'ble_scale'`；同日已有记录默认不写（覆盖需用户点选）；权限 = SCAN(neverForLocation)+CONNECT，零定位权限，API≤30 诚实降级「设备不支持」。
- 小米（米家体重秤/体脂秤系列）**不实现标准测量特征的通知流程**，走小米私有广播（服务数据/厂商数据，按型号与固件解析体重与稳定标志）⇒ 标准订阅路径收不到读数。支持路径见 §5.3。

### 本轮 bug 清单（B 系列，供 T 包逐条闭合）

| # | 缺陷 | 归属包 |
| --- | --- | --- |
| B1 | 月视图按 ≤5 箱切分，无「本月每一天」位置 | T1 |
| B2 | 月视图柱宽 22dp（与周视图同宽，观感粗） | T1 |
| B3 | 添加按钮视觉 36dp vs 切换轨道 28dp，高度不一致 | T1 |
| B4 | 切换件轨道内文字比滑块偏左 2dp | T1 |
| B5 | 左轴仅 3 刻度；柱无点击交互 | T1 |
| B6 | 今日饮食空态块未铺满卡片宽度 | T3 |
| B7 | 今日推荐同排按钮 32/40 混高 | T3 |
| B8 | 动作库卡片行高公式多 +12 → 底部留白偏大 | T3 |
| B9 | 食物详情抽屉拖动时闪加载/高度跳变（build 内建 future） | T5 |
| B10 | training 5 处裸 sheet：双拖动体系 / 未禁层拖 / 缺 isScrollControlled / 标题样式漂移 | T5 |
| B11 | 9 处下拉走 M3 默认，与 3 处精修版风格/字号/行高不一致，长列表菜单观感差 | T4 |
| B12 | 身份卡副标题（已坚持 N 天…）用户要求删除；头像/昵称不可编辑；头像与昵称未垂直居中对齐 | T7 |
| B13 | 步数目标硬编码 10000，无编辑入口 | T9 |
| B14 | 水分目标硬编码 2000，无编辑入口 | T9 |
| B15 | 设置页两个冗余行（导入扩展目录 / 添加自定义食材）与通勤时间行 | T8 |
| B16 | 「导出 CSV」命名歧义（用户看不懂与另两行的区别） | T12 |
| B17 | 食物库陈旧：4.9 万条随包种子内容与用户新结构不符，且**每次启动自动回灌**（清库无效） | T11 + T13 |
| B18 | 随包种子在首启同步导入 4.9 万行，导致 ~6 分钟 splash（用户真机实测；移除种子后消失） | T13 |
| B19 | CSV 导入器上限 16 MiB + 预览期全表物化 + 逐行落库，无法承接 4.9 万级重建 | T11 |
| B20 | 训练「计划详情 / 训练进行中」双拖动体系：内层 `shouldCloseOnMinExtent` 默认 true → 内容缩到底会**误关整个弹层**；内层无 snap，高度自由漂移 | T5 |
| B21 | 电子秤协议硬编码在通道实现里，无抽象层与型号表挂点，新增私有协议秤需改核心代码 | T14 |

---

## §2.5 第二轮需求现状核对（74–79）

### 74 · 引导页设计稿（`ui设计/pages/初始引导.html`，643 行）

- **设计稿结构**：顶部品牌行（`LocalFit` 徽标 + 「跳过」）→ **阶段条**（4 段 `step-pill` 24×4px 胶囊，当前段主色）→ 微标签 `STEP 3 / 4 · 建立档案`（11px 大写）→ 大标题「建立本地档案」+ 副标题「设定你的起点」+ 两行免责说明 → **三张分组卡**：
  1. **基本信息**（说明「用于计算基础代谢率与营养分配」）：年龄（48dp 输入 + 数字键盘）、性别（**双段 segment-control**，48dp 高、3px 内衬）、身高、当前体重、日常活动程度（48dp 自绘 select + chevron，5 档含**描述式文案**「久坐 — 几乎不运动」…「极高 — 体力劳动或每日训练」）；
  2. **你的目标**（说明「选择主要方向，系统将据此调整营养与训练计划」）：**3 张 `goal-card`**（40dp 圆形图标底 + 13px 粗体标签；选中态 = 主色描边 2px + `--lf-mint-50` 底 + 图标底变主色 + `scale` 反馈）、目标体重（可选）；
  3. **安全筛查**：三项**行式开关**（左侧问题文本 + 右侧 iOS 风格 `toggle-switch` 46×28，行间 1px 分隔线）；
  - 底部 **固定 CTA**「计算并确认目标」52dp 全圆胶囊 + 主色阴影（点击后变「目标已确认」+ check 图标）。
- **设计稿的 token 与 App 现状**：稿内 `<style id="theme-vars">` 的 `--lf-mint-*` / `--lf-neutral-*` / `--lf-protein|carbs|fat` / `--lf-radius-*` / `--lf-shadow-*` / `--lf-hero-gradient` 与仓库现有主题**同源同值**（`#2FBE8F` 主色、`#D2F5E6` mint-100、`#EFF3F1` muted、16px radius、`0 1px 3px rgba(15,36,28,.04)` 阴影）⇒ **合并只涉及布局与交互，不需要重新定主题**。
- **现有实现（`lib/features/onboarding/presentation/onboarding_page.dart`）**：**单页长表单**（非分步）：`AppBar('建立本地档案')` + `ListView`，依次 = 标题「设定你的起点」+ 两行免责（:65-79）→ `_basicInfoCard()`（:106-155）→ `_goalSectionCard()`（:157-189）→ `_safetyCard()`（:191+）→ 底部 `LfConfirmButton`「计算并确认目标」（:90-95）。
  - 基本信息：`_numberField` + `SegmentedButton<BiologicalSex>`（:114-121，**M3 原生分段按钮**，非自绘 segment）+ `DropdownButtonFormField<ActivityLevel>`（:131-152，**4 档、纯标签**「久坐少动/轻度活动/中度活动/高强度活动」）。
  - 目标：`Row` 三个 `_GoalBigCard`（:163-184）= **emoji**（🔥/💪/🌿）+ 标签；选中态 `AnimatedScale`(0.97↔1.0, easeOutBack 380ms) + `AnimatedContainer`（mint-50 底 + 1.6px 主色描边）（:358-422）—— **「吞没变形」动效是现有优势，设计稿的静态 scale 反馈不如它**。
  - 安全筛查：`_safetyCard()` 内三个带 Key 的开关（`onboarding-pregnancy-risk` :202 / `onboarding-chronic-risk` :210 / `onboarding-eating-risk` :217）。
  - **无阶段条**（设计稿有 4 段）、**无顶部品牌行/跳过**、**CTA 不在底部固定区**（随 `ListView` 滚动）。
- **合并裁决见 D18**：借**布局与交互**（阶段条、分组卡说明文案、描述式活动档、行式筛查开关、底部固定 CTA、微标签），**保留现有主题与图标**（emoji 目标图标、mint token、`LfText`/`LfDimens`、`DesignCard`、吞没变形动效）。
- **分步 vs 单页：已定案（§8.3）** ✅ —— 设计稿是 **STEP 3 / 4** 的分步流程，现状是**单页长表单**。用户选择**按推荐来** ⇒ 阶段条**仅作视觉进度指示**（单页滚动位置映射 4 段），**不拆表单状态、不改校验、不引入分页路由**；真分步（4 页）需另立工作包。

### 75 · 食物库清空 + 按新结构重新导入（核心事实）

- **现状列定义（`lib/data/database/tables.dart:113-145`，schemaVersion = 22，`lib/data/database/app_database.dart:91`）**：`foods` 共 **17 列** ——
  `id`(text PK) / `name`(text NOT NULL) / `brand`(text null) / `default_serving_grams`(real null) /
  `kcal_per100g` / `protein_per100g` / `carbs_per100g` / `fat_per100g`（均 real NOT NULL）/ `source`(text NOT NULL) /
  `is_user_created`(bool NOT NULL default false) / `created_at` / `updated_at` /
  **`state`**(text NOT NULL default `'verified'`：verified|estimated|incomplete|user_created|stale) / `locale`(text null) /
  **`category`**(text null，存 `FoodCategory` 枚举 id) / `source_version`(int null) / `license_status`(text NOT NULL default `'unknown'`)。
  无 foods 表索引；食物相关迁移：`app_database.dart:146-163`（from<11 加五列 + 回填 state）、`:352-409`（from<22 删过敏原三列，本仓首次减列）。
- **4.9 万行来源（纠正）**：`assets/seed/foods.v5.json`（`version:5` + `foods:[...]`，键名 = `id/name/serving_g/kcal/protein/carbs/fat/constraint_knowledge/dietary_labels/allergens/brand`，**49,444 条**），pubspec 声明于 `pubspec.yaml:46`；导入器 `lib/features/nutrition/data/food_seed_importer.dart`（`seedSource='seed-v5'` :75、`legacySources` :83、`upgradeSource='seed-v4'` :88、入口 `importIfNeeded` :98、种类回填 `_backfillSeedCategories` :135-163、旧代清理 `_purgeLegacySeeds` :181-198），调用点 `lib/main.dart:106`（**首帧前同步**）。
- **FTS 事实（好消息）**：主库**没有** `food_search` 虚拟表（grep 零命中）—— FTS5 只存在于 `CatalogSearchService` 只读打开的**分片 SQLite**里（`catalog_search_service.dart:126-132`）；主库搜索走 `FoodRepository.page()` 的 `LIKE`。⇒ **删主库 foods 行不会破坏任何索引/触发器**。
- **引用 foods 的外键**：`food_aliases`/`food_revisions`/`food_portions` 为 `onDelete: cascade`（`tables.dart:151-152/174-175/196-197`）；**`meal_items.foodId` 与 `menu_item_food_matches.foodId` 为无级联引用**（`tables.dart:375/522`）⇒ 删食物前必须**置空**这两处（`FoodRepository.delete` :180-193 已是这个范式：先置空 `meal_items.food_id`、删 `menu_item_food_matches`，再删）。
- **清空路径**：`ClearAllLocalData.clear()`（`lib/features/backup/application/clear_all_local_data.dart:40-98`）**会清 foods（:72）但会连 AppSettings/AI Key/图片文件一起清**（`:81-83` allTables 兜底 + `:89-97`）⇒ **不适用**。只清内置需仿 `_purgeLegacySeeds` 写 `WHERE is_user_created = 0` 定点删（裁决 D14）。
- **CSV 契约（两处，须同改）**：导出 `lib/features/backup/application/csv_exporters.dart:54-63` 表头 8 列 `name,brand,category,kcal_per_100g,protein_per_100g,carbs_per_100g,fat_per_100g,origin`（渲染 :156-171）；导入 `lib/features/nutrition/data/food_csv_importer.dart`（必需 name + 4×`*_per_100g` :292-298，可选 brand :160 / category :200-219，`origin` **读都不读** :251）。落库一律 `FoodRepository.create` ⇒ **导入行恒为「自建」**（:255-285，单事务但**逐行** create）。
- **三套列名写法（易踩）**：主库 CSV = `kcal_per_100g`；分片 SQLite = `kcal_per100g`（无下划线，`catalog_search_service.dart:163-168`）；种子 JSON = `kcal`。更新结构时是**三处独立契约**。
- **大数据量瓶颈（B19）**：16 MiB 硬上限（`food_csv_importer.dart:97`）→ 全量 CSV 会超；预览期把全库 (name,brand,isUserCreated) 整批拉内存建索引（:128-143）；落库逐行 create（:269-276）无批量。清空后导入 4.9 万级需升级（D14/T11）。
- **会红的测试（T13 的连锁）**：`test/features/nutrition/food_seed_importer_test.dart`（读 `assets/seed/foods.v5.json`/`v4`，:19/:31-41/:69-81/:166-210/:339-430）、`test/privacy/privacy_statement_audit_test.dart`（:292 `retiredSeedFiles`、:323-337 断言随包资产清单、:510-536 校验 strip 脚本）。**不受影响**：`catalog_search_perf_test.dart`（自造 50k 分片）、`food_library_far_jump_test.dart`（自造 49,464 fixture）、`food_library_paging_test.dart`。

- **🔴 2026-10-13 T11-b 落地后的现状（本节上半是规划期快照，勿当现状读）**：`foods` **32 列** = 17 + 15 个新 `text().nullable()`（`library_code`/`category_group`/`category_sub`/`cuisine`/`food_kind`/`data_basis`/`food_state`/`source_code`/`source_food_code`/`original_name`/`original_category`/`source_note`/`source_url`/`recipe_summary`/`source_nature`），`schemaVersion = 25`（存在性驱动的加列迁移）；CSV 契约 = **21 列中文表头逐字**（导出与导入同一套；`origin` 退役，旧文件里的它仍被接受但不读）；「一级分类」的 **24 个库大类**经 `food_category.dart` 的 `_libraryGroups` 映射进枚举，**表外值整行拒绝**。§6 第 7 条「三处列名事实不得单方面改动」的 **T11 例外已用掉**：主库 CSV 一处按用户新结构统一，分片 `*per100g` 与种子 JSON 未动（种子已随 T13 退场）。证据 §14 / §4 交付记录之八。

- **🔴🔴🔴 2026-10-21 ADR-037（最新，取代下面 ADR-036 的「9 列」）**：官方 CSV 变 **10 列**——
  `食品ID, 品牌, 食物名称, 别名, 一级分类, 四项营养, 自建/内置`（用户指示「名称后边加一个别名」）；
  别名落 `food_aliases` 表（非新增列），CSV/新建/编辑三处可写；分类入库**只认十档**
  （或旧文件 24 个库大类自动映射，其他值整行拒绝并在预览里汇总）；名称统一 `主名（备注）`；
  存量 23,919 条由随包 `food_library_normalization.v1.csv` 一次性归一化
  （102 条分类纠正 / 116 条名称重排 / 6,711 条派生别名，逐条记录在
  `docs/evidence/2026-10-21-food-library-audit/changes.csv`）。见 `docs/DECISIONS.md` ADR-037、
  `docs/03` §3.1/§3.2。

- **🔴🔴 2026-10-21 ADR-036 现状（上面那条 2026-10-13 的「32 列 / 21 列 CSV」已被这一条取代，勿再照它核对）**：
  用户指示「把数据库存储方式定死」「就是一个种类」「不要二级分类」——
  `foods` 收敛为 **13 个存储字段**：`id`、`name`、`brand`、**`category`（唯一分类 = App 10 枚举 id）**、
  四项营养（每 100 g）、`default_serving_grams`、`source`、`is_user_created`、`created_at`、`updated_at`；
  上面点名的 15 个契约列与 `category_group`/`category_sub` 由 **schema 30**（存在性守卫的
  `ALTER TABLE … DROP COLUMN`）**删除**。CSV 契约 = **官方 9 列中文表头**（顺序：食品ID / 品牌 /
  食物名称 / 一级分类 / 热量 / 蛋白质 / 碳水 / 脂肪 / 自建·内置；前 8 列与用户那份
  「国内食品营养数据」文件逐字同序）——导入侧认领 7 列（食品ID 读取后丢弃、自建/内置读都不读），
  旧 21 列与旧 8 列英文表头继续宽容接受、未认领的列读取后丢弃。分类的 24→10 映射表
  （`_libraryGroups`）保留，但只在**导入期**翻译：原文不落库。详情弹层的 meta 行同步撤掉分类文字
  （种类只由搜索行下面的 `food-library-category-row` 筛选）。见 `docs/DECISIONS.md` ADR-036、
  `docs/03` §3.1/§3.2、`docs/21` §5.3 详情弹层。

### 76 · 导出行文案

见 §5.1 与 D17。现状三行 + 一个加密备份的调用点：`settings_page.dart:408-430`（`cta-export-csv` / `backup-export-training-csv` / `backup-export-foods-csv`）。定稿文案**不带 CSV 后缀**。

### 77 · 通勤时间全链路删除

现状与连锁清单见 §2·70（20+ 文件、约 16 个测试）。本轮**追加确认**：副作用（推荐失去通勤感知、旧 `.lfb` 丢该字段）用户**已确认**；要求「从全部地方删掉，不要漏」⇒ 验收 = 全库 grep `通勤|commute|manualCommuteMinutes|ManualCommute` **零命中**（白名单：迁移历史注释、证据文件、本方案自身）。归属 T8，收口复核 T16。

> **2026-10-13 T8 交付修订（按代码事实）**：
> 1. **`travelFit` 从零命中集合中移除**——D10 明文「solver 参数保留但恒中性 = `TravelFit` 参考值」，
>    `TravelFit.neutral` 是**活代码**（恒 0.5，见 `lib/features/daily_plan/application/travel_fit.dart`），
>    不可能也不该零命中；下线的只是它的**输入源**（手动分钟数 + 路线查询）。
> 2. **实际门禁 = `test/app/round5_retired_feature_grep_test.dart`**：模式 `commute|通勤`（大小写不敏感），
>    扫 `lib/` + `test/` 全部 `.dart`；白名单 = **同一行点名历史列名** `manual_commute_minutes` /
>    `manualCommuteMinutes`（迁移历史注释、v24 fixture、`.lfb` 旧键测试）。比上面这条文字更严：
>    注释里写中文名都会被拦（T8 实施中真被拦过一次，见证据文件 §3）。

### 78 · 电子秤预留接口

- 现状（第四轮 S6）：MethodChannel `localfit/scale`，前台 10s 扫描标准服务 `0x181D` → 订阅 `0x2A9D` 通知 → 读一次断开；SFLOAT 原生解析为克；仅公制；`source: 'ble_scale'`；同日已有记录默认不写；权限 SCAN(neverForLocation)+CONNECT、零定位权限、API≤30 降级「设备不支持」。
- **缺口（B21）**：协议解析与扫描编排**耦合在通道实现里**，没有「读数来源」抽象、没有按型号/厂商分派的挂点 ⇒ 新增私有协议秤（小米等）要动核心代码。本轮按用户指示**只预留接口**（D16/T14），不实现小米。

### 79 · 训练弹层更好的方案

- 现状（B10/B20）：`training_page.dart` 5 处裸 `showModalBottomSheet`；其中 `:911`（计划详情）与 `:987`（训练进行中）内嵌 `DraggableScrollableSheet`（`:1467-1471` 0.6/0.9；`:1684-1688` 0.75/0.95），外层 `enableDrag` **缺省 true**（整层可拖）⇒ 与外层 modal 形成**双拖动体系**：外层把手位移按运行时 `_childHeight` 换算改入场 progress（Flutter `material/bottom_sheet.dart:285`）、内层 extent 变化会改变该高度 ⇒ 比例跳变；内层 `shouldCloseOnMinExtent` **默认 true** ⇒ 内容缩到最小**误关整个弹层**（`bottom_sheet.dart:325-330`）；两处内层 `snap` 缺省 false ⇒ 高度自由漂移无停靠点。另 `:1026`/`:1051` **缺 `isScrollControlled`**（受 9/16 屏限高）。
- 两处 `scrollController` **接线正确**（`training_page.dart:1507`/`:1723` 都 `ListView(controller: scrollController)`）⇒ 不存在「卡在 initialChildSize」的常见 bug。
- **裁决 D15 = 方案 B**（保留拖动放大）：外层 `enableDrag:false` + 把手；内层保留并加 `snap:true` + `snapSizes` + `shouldCloseOnMinExtent:false`；无拖动需求的 3 处（统计/训练达标/个人纪录）迁 `AppSheet`。
- **注意（如实记）**：`snapSizes` 改动需 rebuild 才生效（Flutter `widgets/draggable_scrollable_sheet.dart:381-386`）；「训练进行中」内容含**动态高度**（`RestCountdown` :1708、异步 `_PlannedTargetsHeader` :1714）⇒ snap 点须在 build 内按内容量重算，否则停靠点与视觉不符（T5 验收含此条）。

---

## §3 裁决（D1–D19；D13–D19 为第二轮追加）

### D1 · 月视图 = 本月逐日顺序格

- 月视图改为**本月 1 日→月末逐日顺序格**（28–31 格，左起 1 日，**不是周历网格**，不补首尾空位）；无记录日 = **空槽**（不画柱；不画标签）。
- **柱宽**：`clamp(格宽 − 2, 3, 8)` ⇒ 31 天月约 6dp（截 02 的 22dp 变细）；柱顶圆角 3dp；「最新一条」深色逻辑保留。
- **每格取值**：该日**最后一条**体重记录（与卡片「最新 X kg」口径一致）；同日多条不取均值。
- **横轴标签稀疏集合**：`{1, 5, 10, 15, 20, 25, 月末}`（自动去重；月末已含则省略），10px micro 字号不变。
- 周视图**不动**（恒定 7 格、柱宽 `min(22, 格宽−16)`）。
- 理由：用户原话「月视图也要留本月所有天数的位置」+「柱子细一点」；废除「≤5 箱均值」口径是因为它与「本月体重」标题和「所有天数」诉求直接冲突。

### D2 · 4 刻度 + 柱点击浮窗

- Y 轴 **4 档**刻度 + 4 条虚线：y = 0 / 130×⅓ / 130×⅔ / 130（值 = `max / max−(max−min)/3 / min+(max−min)/3 / min`，标签仍 `toFixed(1)`）；轴拟合公式（`pad = 范围×25%`）不变。
- **柱点击**：点任意有值柱 → 柱顶上方 **4dp 外侧**出现小气泡（高 ≤22dp、圆角 8、内容 = 体重一位小数，可选带「kg」），气泡**水平钳制在绘图区内**；被选柱用深一档色（`#22A877` → 更深）。
- 关闭：再点同柱 / 点图表空白 / 切换周月 / 页面滚动离开。**空槽点击无响应**。周视图与月视图**同样适用**（用户说「体重卡的柱子可以点击」）。
- 无障碍：气泡出现时语义标签补数值。

### D3 · 添加按钮与切换控件等高

- 「＋」视觉圆 **28dp**（= 切换轨道视觉高）、图标 16dp、底色/色不变；**命中盒仍 44dp**（不牺牲可点性）；与切换件间距 8dp、顺序（＋在左）不变。
- 理由：用户原话「添加按钮的大小要跟周/月切换按钮的上下宽度一致」；截 02/04 显示 ＋ 明显大于轨道。

### D4 · onboarding 目标抽屉图形化

- 热量行 = **大号区间数字**（`1,451–1,603 kcal`）+ 一条范围条（hero，主绿）；
- 三个宏量行 = 名称 + 范围条 + `91–114 g` 文本；范围条把 `[min,max]` 归一映射到 `[0, max×1.2]` 轨道上（**纯位置可视化，不引入假精度**）；
- 颜色沿用今日页宏量语言（蛋白质橙 / 碳水黄 / 脂肪紫）+ 热量绿；
- 无交互；「返回修改 / 确认保存」与弹层壳不变。视觉细节由 T2 的 HTML 稿定稿。

### D5 · AI 创作 = 对话启动器（六卡映射）

- 每张卡：点击 → `AppSheet` 描述框（标题=任务名、多行输入、placeholder=该任务既有 `inputHint` 文案、主按钮「生成」，**非空才可点**）→ 生成 → **切到对话分支**并**自动发送**拼好的启动提示词 → 结果在对话里流式呈现。
- 映射与落库方式：

  | 卡片 | 启动提示词方向 | 落库/结果 |
  | --- | --- | --- |
  | 解析学校菜单 | 「把下面这份菜单整理进本地菜单库（先建地点和窗口，再逐条加菜品）：…」 | 对话命令链 `canteen.venue.create→window.create→dish.create` → 编辑卡「应用」 |
  | 分析菜品营养 | 「估算这道菜每份的营养并收录：…」 | `dish.upsert`（每份口径）→ 编辑卡 |
  | 生成今日吃法 | 「按我的目标和今天已吃的，帮我搭配今天剩下几餐：…」 | **咨询型**：模型据快照给建议文本（见下「能力变化」） |
  | 这道菜怎么吃 | 「这道菜怎么吃、怎么搭配：…」 | 咨询型（对话原生） |
  | 训练计划 | 「按我描述的目标生成训练计划并保存：…」 | **新增命令 `workout.plan.create`**（T6b 规格）→ 编辑卡 |
  | 常吃搭配 | 「在这些本地食材里给我搭配：…」 | 咨询型（快照含菜品库/食堂目录/餐记录） |

- **「草案不自动成为事实」语义不变**：由编辑卡的「全部应用 / 忽略」承接（原任务卡片的确认写入语义等价迁移）。
- **如实记一处能力变化**：「生成今日吃法」原任务能在卡片内产草稿并**只写计划不写已吃**；改为对话后**不再直接产写库草案**，其「加入计划」写库路径仍在**食堂页「确认加入计划」**（引擎 `confirmCandidate` 未动）。若用户要求恢复对话内写计划，需另立命令包（本轮不做）。
- 训练计划落库与训练页既有「AI 生成计划（R7）」入口**并存**，两者落库规则一致（动作 allow-list、确认后写）。

### D6 · 旧任务执行管线退役

- 创作页保留（重设计），但其**执行机制退役**：`AiWorkbenchTask` 的执行字段、`AiTaskCard`、6 个 `*_workbench_task.dart` 的 runTask/decoder、任务用 `PromptCatalog` 模板、`OpenAiCompatibleTaskCapability`（删除前先确认全库无其它引用）。
- **安全属性必须重钉到命令层**（不允许「随删除一起消失」）：动作名解析拒绝未知/歧义（executor 层断言）、命令参数机械校验（含新 `planDays` 类型）、编辑卡应用前不落库、S7 实测仪器的命令计数与用例矩阵同步更新。
- `PromptCatalog` 基础设施**保留**（训练页 AI 生成计划 provider 仍在用）。
- 理由：用户明确要求「生成发生在工作台对话里」；保留两套并行的写入管线会留下「未被使用但仍存在」的路径（正是用户第 70 条要求排查的「遗漏」类型）。

### D7 · 下拉统一为 `LfSelectField`

- 新增共享组件 `lib/app/design/widgets/lf_select_field.dart`：**外观**=输入框形（label + 当前值 + chevron）；**点开**=`AppSheet` 单选列表（紧凑行高 44、选中项主色 + ✓、超长列表可滚）。
- 迁移 11 处 `DropdownButtonFormField`（第 12 处 `daily_menu_plan_workbench_task.dart:387` 随 D6 删除，不迁移）。
- `PopupMenuButton` 2 处（餐卡管理菜单，属动作菜单非选择器）不动；如需统一留后续。
- 理由：用户要「所有下拉选项弹窗的流畅性/显示风格/大小」统一；自绘弹层已有两个先例（餐次胶囊、选日期）；M3 锚定菜单在长列表下观感差且无法统一主题。

### D8 · 弹层拖动契约统一（**已被 D15 修订，见下**）

- **唯一拖动体系**：外层把手（`showDragHandle: true` + `enableDrag: false`）。
- `food_detail_sheet`：把 `load()` future **提升到 State**（不再 build 内创建）；新增回归测试钉「拖动起止不触发重载、不出现 waiting 帧」。
- 全库审计所有 `AppSheet` 内容中「build 内创建 future」的实例并一并修复（清单在 T5 实施时落证据）。
- 2 处裸 `AlertDialog`（菜单删除确认、资料更新确认）收敛到统一壳（低成本，含在 T5）。
- ~~training 5 处全迁 AppSheet、两处移除内层 DraggableScrollableSheet~~ → **改由 D15 处理**（保留拖动放大能力）。

### D9 · 身份（头像 / 昵称）

- **schema 22 → 23**：`profiles` + `displayName`(text, null) + `avatarPath`(text, null)。
  **2026-10-12 T7 开工前修订（按代码事实）**：原写「一次迁移，与 D10 的删列合并（−`manualCommuteMinutes`）」，
  但实测 `manualCommuteMinutes` 在 **67 个文件**里被引用（含 `app_database.g.dart` 的生成代码），
  而 drift 的生成代码由 `tables.dart` 派生——**在 T8 删掉那些引用之前从表定义里去掉这一列会让全仓编译失败**，
  与 §0 纪律 1「每个工作包独立过全量门禁 EXIT=0」直接冲突（T7 排在 T8 之前）。
  ⇒ **拆成两次迁移**：T7 = schema 23（+2 列，按列存在性判断）；T8 = schema 23→24（删 `manualCommuteMinutes`，
  与通勤代码删除同包落地）。**终点 schema 完全一致**，只是不再合并为一次；此修订已回报并记录于 T7 证据。
- 头像：`image_picker`（已是依赖）相册选择，`maxWidth/maxHeight 512`、`imageQuality 90`；文件复制到应用文档目录 `avatar/` 子目录（替换时删旧文件）；列里只存**路径**。
- **头像文件不进 `.lfb`**（如实记限制）：恢复备份后若文件不存在 → 回退首字母头像。
- 昵称：身份卡内直接编辑（tap 姓名/铅笔 → `AppSheet` 表单，1–20 字、trim、空则拒绝）；头像：tap 头像 → 选图。
- 身份卡：**删除副标题整行**（「已坚持 N 天 · 目标减…」）；头像与昵称**垂直居中对齐**。
- 展示接线：新增共享 `UserAvatar`（有图显示图、无图显示首字母，无昵称回退「Fit」）；今日页头像与对话页顶栏用户头像**可点 → 跳「我的」**；`displayName` 接入今日页（头像首字母/图片）。AI 吉祥物头像不是用户头像，不动。

### D10 · 设置清理与通勤下线

- 删「添加自定义食材」行（弹层「手动添加一种食物」已覆盖）。
- 删「导入扩展食物目录（可选）」行；**恢复能力保留为「仅失败时渲染」**：仅当 `bootstrap.lastResult` 显示失败/分片缺失时渲染恢复入口行。正常态零入口（用户要求），失败时恢复路径不死（既有设计意图）。
- **通勤全链路下线**（含 AI 命令 `commute.set`；**注册表 24→23**——原写「23→22」是以 T6b 之前的计数为基数，
  T6b 新增 `workout.plan.create` 后实际是 24 条，删这一条得 23 条，**以代码事实为准**，见
  `docs/evidence/2026-10-13-t8-settings-cleanup.md` §1；快照「手动通勤」段移除；**DB 列随 schema 23→24 drop**（见 D9 的 2026-10-12 修订：删列与代码删除必须同包，否则全仓编译不过）；solver 参数保留但恒中性 = `TravelFit` 参考值）。验收 = 全库 grep `通勤|commute|manualCommuteMinutes` **零命中**（白名单：迁移历史注释、证据文件；门禁实现见 §2·77 的 2026-10-13 修订）。
  **✅ 用户已定（2026-10-11）**：副作用（下一餐推荐失去通勤感知/退化为中性；旧 `.lfb` 恢复时该字段丢弃）**已确认接受**；并要求「从全部地方删掉，不要漏」。
- 「导出 CSV」行**改名「导出饮食记录」**（另两行同步去 CSV 后缀，见 D17）。

### D11 · 步数目标 / 水分目标编辑

- 两处都放**「编辑资料」页**（= 用户说的「资料卡里」）。
- 步数：`AppSettings` 新键 `steps_daily_goal`（字符串整数，默认 10000，范围 1000–50000）；步数卡改由注入方读该值（默认 10000 兼容旧行为）。
- 饮水：字段以 **L** 输入（0.5–6.0，步进 0.1）存 ml；写路径 = 新用例 `UpdateWaterTargetMl`：读当前生效 `DailyTargets` 行 → **今日已有行则就地更新，否则插入新版本行**（`effectiveDate=今天`、其余列复制、`updatedAt` 刷新），事务包裹。历史日期仍按各自生效行显示（版本化语义）。

### D12 · 小米体重秤 = 可选包（本轮不实施；**由 D16 细化**）

- 见 §5.3。触发条件：用户给出**具体型号**且**真表在场**可对验；否则不做（无法在无真表条件下诚实验收）。
- **✅ 用户已定（2026-10-11）**：不再要求现在给型号 —— 改为**先预留接口、后期适配**（见 D16/T14）。

---

### 🔒 第二轮裁决（D13–D19，2026-10-11 同日确定）

### D13 · 彻底移除随包食物种子　**✅ 用户已定**

- **动作**：① 删 `pubspec.yaml:46` 的 `assets/seed/foods.v5.json` 声明；② 删/移出仓库的 `assets/seed/foods.v5.json`（11 MB）与 `foods.v4.json`（10.7 MB，不随包但被测试读）；③ 退役 `FoodSeedImporter` 的**食物**分支（保留动作库 `ExerciseSeedImporter`，它独立且仍在使用）；④ 清掉 `lib/main.dart:106` 的调用与相关注入；⑤ 修 `test/features/nutrition/food_seed_importer_test.dart` 与 `test/privacy/privacy_statement_audit_test.dart`（随包资产清单、retiredSeedFiles、strip 脚本断言）。
- **理由**：数据源与用户要的「新结构 CSV」不符，且**每次启动回灌**导致清库无效（§1.2 事实①）。
- **如实记影响**：
  - 全新安装**首启无任何内置食物**，食物库为空直到用户导入 CSV（这正是用户要的；同时顺带消掉 ~6 分钟 splash，B18）。
  - 旧安装升级后：**已有 4.9 万行不会自动消失**（它们已在库里）⇒ 需配套一次性清理（D14 的 T11）。
  - 「导出食物数据」不再有「内置」来源；`origin` 列恒为「自建」。CSV 导入/去重/预览逻辑不受影响。
  - 若将来想恢复内置库：把数据做成符合新结构的 CSV，走普通导入即可（不再需要种子机制）。

### D14 · 食物库清空 + 按新结构重建　**✅ 已落地（2026-10-13；见证据 §14 与 §4 T11 交付记录之八）**

- **清空方式**：**不用** `ClearAllLocalData`（会连 AI Key/图片一起清，§2·75）。新增专用用例「清空内置食物」：
  `DELETE FROM foods WHERE is_user_created = 0`，**前置**：把 `meal_items.food_id` 指向被删行的**置空**、删对应 `menu_item_food_matches`（复用 `FoodRepository.delete` :180-193 的范式）；`food_aliases`/`food_revisions`/`food_portions` 走 `onDelete: cascade` 自动清；单事务；**保留用户自建食物与所有餐记录**。执行后必须**幂等可重跑**。
- **重建方式**：走既有「添加食物数据 → 从 CSV 文件导入」链路（`app_router.dart:532-582`），但需按 D14 升级导入器（B19）：
  1. 上限 16 MiB → 可配置/提高（全量 CSV 预计 30+ MB）；
  2. 预览期全表物化 → 改**流式/分批**建去重索引（清空后库内只需与**自建行**比对，量级骤降）；
  3. 落库逐行 `create()` → 改**批量 insert**（单事务内 `batch`），保留同一套校验。
- **⛔ 已被取代（2026-10-21 ADR-036 → 再被 ADR-037 取代为 10 列）**：下面这条 21 列契约已作废——现行为**官方 10 列**，见本节 2·74 的 ADR-036 横幅与 `docs/DECISIONS.md` ADR-036。原文保留只为历史追溯。
- ~~**新表头契约（2026-10-13 定稿并落地）**~~：= 用户文件 `国内食品营养数据_扩充版2.csv` 的 **21 列中文表头逐字**（`食品ID` … `来源性质`），21 列**全部入库**（15 个新 DB 列 + 6 个既有列对位；`origin` 不再导出）。四处同步：`csv_exporters.dart:54-63`（导出表头）、`food_csv_importer.dart:292-298`（导入必需列）、以及 `foods` 表列定义（新结构 15 个新列，**schema 24→25** 独立一次迁移；D9 的 profiles 列变更已在 22/23 落地）。落地差异清单对 §13.5 草案的五点修正见证据 §13.5 横幅与 §14。
- **兼容性**：用户旧导出的 8 列 CSV 应仍可导入（新列留空/给默认），除非用户明确要求不兼容。
- **验收**：清空后 `foods` 表仅剩自建行；餐记录完整（引用被置空但记录在）；导入 4.9 万级 CSV 在可接受时间内完成且计数正确；去重提示正确。　**（2026-10-13 实测）**：清空 49,444 条 → 回灌 49,444 条（升级走查 22 帧）；新结构 19,974 行导入预览 **19974/0/0**、计数 19,974 条、二遍同文件全判重复（13 帧）；证据 §14。

### D15 · 训练弹层：保留拖动放大（方案 B）　**✅ 用户已定**

- **`training_page.dart:911`（计划详情）与 `:987`（训练进行中）**：
  - 外层 `showModalBottomSheet` 加 **`enableDrag: false`** + 保留 `showDragHandle: true`（把手仍可关窗，且不再整层截胡手势）；
  - 内层 `DraggableScrollableSheet` 加 **`snap: true` + `snapSizes`**（如计划详情 `[0.6, 0.9]`、训练进行中 `[0.75, 0.95]`）+ **`shouldCloseOnMinExtent: false`**（杜绝「缩到底误关整个弹层」）；`expand: false` 保留（否则 `SizedBox.expand` 撑满与 modal 打架）；`scrollController` 已正确接线不动；
  - **动态内容重算 snapSizes**：训练进行中的 `RestCountdown`（`:1708`）与异步 `_PlannedTargetsHeader`（`:1714`）会改变内容高度 ⇒ 在 build 内按内容量重算 snap 点（Flutter `draggable_scrollable_sheet.dart:381-386`：snapSizes 变更需 rebuild 生效）。
- **另 3 处**（统计 `:1007` / 训练达标 `:1026` / 个人纪录 `:1051`）：本无拖动需求 ⇒ 迁 `AppSheet`（`show`/`showStateful`），顺带修掉 `:1026`/`:1051` 缺 `isScrollControlled` 的 9/16 屏限高。
- **源码依据**：把手单独手势仅在 `!enableDrag` 时挂（`material/bottom_sheet.dart:377-384`）；整层手势仅在 `enableDrag:true` 时挂（`:420-427`）；把手位移改的是入场 progress 而非内容高度（`:285`）⇒ 方案 A（全迁 AppSheet）会**彻底失去放大**。内层 `shouldCloseOnMinExtent` 经 `DraggableScrollableNotification` 触发外层 `onClosing`（`:325-330`）。
- **如实记**：`snapSizes` 与动态高度的匹配需设备走查确认手感；若发现吸附点与视觉不符，退化为「仅 `shouldCloseOnMinExtent:false` + 自由拖动」。

### D16 · 电子秤：先预留接口，后期适配　**✅ 用户已定**

- 抽出一层「读数来源」抽象（拟名 `ScaleReadingSource`），把**扫描 + 订阅 + 解析**从通道实现里解耦：
  - 接口：`Future<List<ScaleDevice>> scan(Duration window)` / `Stream<ScaleReading> readings(ScaleDevice)`（克、公制）；
  - 现有标准协议实现（`0x181D`/`0x2A9D`）作为**第一个实现**，行为不变；
  - **型号/厂商分派挂点**：按设备名/广播服务 UUID 路由到对应解析器（为小米等私有广播预留 registry 条目，**本轮只留空挂点，不写解析**）。
- 保持既有落地规则不变：`source: 'ble_scale'`、同日已有记录默认不写、覆盖需用户点选、权限清单不改（manifest 不动）。
- **验收**：抽象层单测（fake source 驱动编排七种结局）；标准协议行为无回归；**新增私有协议只需注册一个 parser，不改编排代码**（用一个假 parser 在测试里证明）。
- **范围修订（2026-10-13，按代码事实收窄操作面；T14 交付时登记）**：接口的**操作面**不能照抄上面的 `scan`/`readings` 两段式——原生通道只有**合成原语** `scanOnce`（扫描 → 连接 → 订阅 → 解析在一次调用里完成并一次答复，`MainActivity.kt:280-470`；ok 载荷只有 `grams`/`atMs`，不带设备身份）。拆成两段只有两条路：让一次调用冒充两段（撒谎）、或改原生（本轮无法进 `flutter test` 门禁验证 ⇒ 违反 §6「不引入新 bug」）。故定为：
  - `ScaleReadingSource`：`check()` / `requestPermission()` / `openAppSettings()`（编排与界面要用的能力面）+ **`parsers`**（分派表）+ `readOnce({Duration window})`（扫描 → 分派 → 订阅一次 → 断开）；
  - **型号/厂商挂点 = `ScaleParserRegistry`**：`forDevice(ScaleDevice)` 按**广播服务 UUID / 设备名**认领第一个 parser，`register(...)` 追加（重复 id 直接抛）；本轮只注册标准 parser（`standard_weight_measurement`），私有协议条目**不写**（D16 原意「只留空挂点」）；
  - 将来真要接私有协议：Dart 侧只需实现一个 `ScaleProtocolParser` 并 `register` 进来源的 `parsers`（编排零改动，测试用假 parser 证明）；**原生侧还需要补「发现（去掉 0x181D 过滤）+ 原始字节透传」那一半**——这是后期适配备件（§5 答复 73：具体型号 + 真表在场），不在本轮；
  - 验收四条（无回归 / 编排只依赖抽象 / 假 parser 分派证明 / 落地规则不变）**不变**。

### D17 · 导出行文案定稿　**✅ 用户已定**

- 三行最终文案（**一律不带 "CSV" 后缀**）：**`导出饮食记录`** / **`导出训练记录`** / **`导出食物数据`**。
- 用户原话里「就写导出导出饮食记录」判定为**笔误**（重复「导出」）。
- 语义说明写进设置页（可选）：点按即导出为 CSV 文件（沿用 `export_csv_files.dart`，文件名不变）。
- 理由：用户原话「导出 CSV 这个文字你要写清楚，是导出饮食记录，把另外两个的名字后边的 csv 字段都删掉」。

### D18 · 引导页合并设计稿（借布局交互，不换主题）

- **借入（来自 `ui设计/pages/初始引导.html`）**：
  1. **阶段条**：4 段 24×4px 胶囊（当前段主色）—— 现状无（**定为视觉进度指示**，§8.3 定案 ✅）；
  2. **微标签**：`STEP n / 4 · 建立档案`（11px 大写、字距放宽、主色）；
  3. **分组卡说明副文案**（如基本信息下「用于计算基础代谢率与营养分配」、目标下「选择主要方向，系统将据此调整营养与训练计划」）；
  4. **描述式活动档**：设计稿 5 档带解释（「久坐 — 几乎不运动」…「极高 — 体力劳动或每日训练」）；现状是 **4 档纯标签**（`ActivityLevel` 枚举只有 4 值）⇒ **档位数以现有枚举为准，只把标签改成描述式**（不新增枚举值，避免动领域模型）；
  5. **性别自绘 segment-control**（48dp 高、3px 内衬、选中白底 + 主色字 + 阴影）—— 现状是 M3 `SegmentedButton`；与本轮 T4 的 `LfSelectField`/选控件统一方向一致，**可复用同一套自绘分段控件**；
  6. **行式安全筛查开关**（左问题文本 + 右 iOS 风格 46×28 开关 + 1px 分隔线）—— 现状已是开关，**统一为设计稿的行式布局与开关尺寸**；
  7. **底部固定 CTA**：固定在可视区底部（不随内容滚动）—— 现状 `LfConfirmButton` 随 `ListView` 滚动 ⇒ 改为底部固定行动区；**高度取现有 token h48**（§8.3 定案 ✅，不采设计稿 52dp）；
  8. **顶部品牌行 + 跳过**：设计与现状均无「跳过」语义（建档是必经流程）⇒ **不加跳过**（如实记：设计稿的「跳过」与现有流程语义冲突，不采纳）。
- **保留（现有优势，不采纳设计稿的对应形态）**：
  - **emoji 目标图标**（🔥/💪/🌿）——用户明确「图标什么的按现有的来」；设计稿的 40dp 圆形单色图标底**不采纳**；
  - **吞没变形动效**（`AnimatedScale` 0.97↔1.0 easeOutBack 380ms + `AnimatedContainer` 描边/底色，`:373-421`）——优于设计稿的静态 `scale(.97)`；
  - **主题 token**：`LfColors.mint` / `context.lf.*` / `LfText` / `LfDimens` / `DesignCard`（设计稿 `--lf-*` 与它们是同一套值，无需重新定义）；
  - **`DesignCard` 卡片形态**（现已在用 :106/:157/:191）。
- **不采纳**：设计稿的「跳过」、单色图标底、Tailwind 任意值写法（不是 App 的样式体系）。
- **实施顺序**：先出合并后的 HTML 稿（360dp）→ 自检两轮（修瑕疵）→ 直接写原生（§0 纪律 v3，不再送用户审批）。

### D19 · 弹层方案收敛（承接 D8 → D15）

- 原 D8「training 5 处全迁 AppSheet」**作废**，改按 **D15** 执行：**2 处保留拖动放大（方案 B）+ 3 处迁 AppSheet**。
- D8 其余条目（food_detail_sheet future 提升、build 内建 future 审计、2 处 AlertDialog 收敛）**继续有效**。

---

## §4 工作包（T1–T16；X1 已并入 D16/T14）

> 每包：范围 → 验收（可测语句）→ 测试与变异 → 门禁 → 证据名。所有包默认遵守 §0 纪律。

### T1 · 体重卡图表升级（需求 60/61；D1+D2+D3）

- **文件**：`lib/app/design/widgets/weight_bar_chart.dart`、`lib/features/progress/domain/weight_chart_points.dart`、`lib/features/dashboard/presentation/sections/dashboard_weight_card.dart`、`lib/app/design/widgets/lf_segmented_toggle.dart`（B4 的 2dp 对齐）。
- **验收**：
  1. 月视图格数 = 当月天数（28/29/30/31 各测一例）；空槽不画柱；
  2. 月视图柱宽 = `clamp(格宽−2, 3, 8)`（360dp 屏 31 天月 ≈6dp）；周视图柱宽与格数不变；
  3. 轴刻度 = 4 个（值/位置各断言），虚线 4 条；
  4. 点有值柱出现浮窗（含数值文本）、再点同柱消失、点空白消失、切换周月消失；浮窗不越绘图区左右边界；
  5. 「＋」视觉尺寸 28dp、命中 44dp、与切换件间距 8dp；
  6. 切换件文字与滑块中心对齐（2dp 偏差修复）；
  7. 既有语义摘要不回归。
- **测试与变异**：≥6 条新断言，每条一次隔离变异（格数、柱宽公式、刻度数、浮窗显隐、钳制、+尺寸）。
- **门禁**：`tool/verify.bat` EXIT=0；**HTML 稿先行 + 自检两轮**（周/月/浮窗三态 360dp 稿）。
- **证据**：`docs/evidence/2026-10-1x-t1-weight-chart.md`。

### T2 · onboarding 目标确认抽屉图形化（需求 59；D4）

- **文件**：`lib/features/onboarding/presentation/onboarding_page.dart`（:307-336）+（如需）共享范围条组件。
- **验收**：四个数值全部可见且数值与 `NutritionTargetCalculator` 输出一致；范围条归一函数单测（min/max/边界）；「返回修改/确认保存」流程不回归（含保存后进今日页）。
- **测试与变异**：数值渲染、归一函数、按钮流程；≥3 变异。
- **门禁** + HTML 稿先行 + 自检两轮。**证据**：`...-t2-onboarding-target-sheet.md`。

### T3 · 小样式三连（需求 63/65/68）

- **文件**：`dashboard/presentation/sections/dashboard_meal_timeline.dart`（空态铺满）、`daily_plan/presentation/next_meal_decision_card.dart` + `lf_buttons.dart`（同排按钮同高 40；「换一个/调整时间」在出现时同样 40）、`training/presentation/exercise_library_page.dart`（`_cardExtent` 去掉 `+12`，底部=顶部=12）。
- **验收**：空态块宽度 = 卡片内容宽（左右边距相等）；该卡片动作行所有按钮高度一致（40）；动作库卡底距 = 12dp（与上同）。
- **测试与变异**：三条各一变异。**证据**：`...-t3-small-styles.md`。

### T4 · 下拉统一 `LfSelectField`（需求 66；D7）

- **文件**：新 `lib/app/design/widgets/lf_select_field.dart` + 11 处迁移（`onboarding_page.dart:131`、`settings_page.dart:1112,1264`、`planned_entry_sheet.dart:66,89`、`training_page.dart:759,1819`、`scan_candidate_editor.dart:123`、`exercise_library_page.dart:144,157`、`new_food_dialog.dart:193`）。
- **验收**：11 处点开都是统一弹层（同标题/行高/选中态）；返回值与旧下拉一致（逐站点回归）；长列表（动作名/候选）可滚动且选中项可见；禁用态与校验错误态保持。
- **测试与变异**：每站点至少 1 条「打开→选择→回写」断言；变异：选中态样式、返回值、禁用态。
- **门禁** + HTML 稿先行 + 自检两轮（组件 + 两类典型站点）。**证据**：`...-t4-select-field.md`。

### T5 · 弹层稳定性与统一（需求 67/79；D8+D15+D19）

- **文件**：`nutrition/presentation/food_detail_sheet.dart`（future 提升）+ 审计清单命中文件 + `training/presentation/training_page.dart`（**2 处方案 B 改造 + 3 处迁 AppSheet**）+ 2 处 `AlertDialog` 收敛。
- **验收**：
  1. 食物详情抽屉：拖动把手起/止**不重建数据 future**（loader 调用计数不变）、无 waiting 帧、高度稳定；
  2. 全库审计清单落证据（每处「是否 build 内建 future」+ 结论）；
  3. **计划详情 / 训练进行中（方案 B）**：外层 `enableDrag:false` 生效（整层拖拽不再触发）；内层 `snap` 生效（松手停在 snap 点）；**内容缩到最小不再关闭整个弹层**（`shouldCloseOnMinExtent:false`）；动态内容出现时 snap 点重算（断言 snapSizes 与实际高度匹配）；把手仍可关窗；
  4. **另 3 处**走统一壳（`enableDrag:false` + 把手 + 90% 限高 + 统一动效）；`:1026`/`:1051` 不再受 9/16 屏限高；内部列表可滚；
  5. 2 处 `AlertDialog` → 统一壳后交互等价（确认/取消路径）。
- **测试与变异**：拖动稳定性回归（计数断言）、方案 B 三条（缩到底不关窗 / snap 停靠 / snapSizes 重算）、3 处冒烟、2 处确认路径；≥4 变异。
- **证据**：`...-t5-sheet-stability.md`。

### T6 · AI 创作对话化（需求 62；D5+D6）— 三个子包

**T6a 画廊重设计**
- **文件**：`features/ai_workbench/presentation/ai_workbench_page.dart` + 新 starter 定义数据（id/标题/说明/图标/启动提示词模板/inputHint）。
- **验收**：6 张卡分组展示（饮食 / 训练与搭配）；卡片点击 → 描述框（非空才可生成）；视觉规格由 HTML 稿定稿；无障碍标签齐全。
- **门禁** + HTML 稿先行 + 自检两轮。
- **交付记录（2026-10-13，T10 走查补记）**：六卡文案「逐字沿用既有 task 文案」这句原先**有一处不成立**——
  `daily-menu-plan` / `dish-guidance` / `meal-pairing` 三条 `description` 停在子句中间（残留「；」「，」），`meal-pairing` 还少一整句隐私承诺。
  原文两处独立出处：`docs/evidence/2026-10-04-input-menu-foodlib-redesign/w4-07-ai-workbench-6-tasks.xml` 的旧卡片 `content-desc`、
  以及 `docs/08-store-privacy-and-permissions.md:44`（「不上传餐食历史」）。已在 T10 走查中补回三句原文本（`ai_starter.dart` 只改这三行字符串），
  新断言 `test/features/ai_workbench/round5_ai_gallery_test.dart` 的「六卡描述都是完整句子」（三条逐字 + 一条「不许停在 `；`/`，` 上」兜底），
  隔离变异 2 条全 RED 且还原 sha256 一致；重建 APK 后真机复拍 `25-ai-creation-gallery.png`。
  详见 `docs/evidence/2026-10-13-t10-walkthrough.md` §2.1/§4。

**T6b 预填 + 自动发送 + 命令增补**
- **文件**：`lib/app/app_router.dart`（路由级 `ValueNotifier` 启动请求，仿既有 `menuTabRequest` 先例 :157）、`ai_conversation_page.dart`（消费 pending：`initState` 读 + `addPostFrameCallback` 发送；`isReplying` 守卫 → 只预填不发送 + 提示）、`chat_edit_registry.dart`/`chat_edit_command.dart`（新组合类型 `planDays`，仿 `foodItems` 先例）、`chat_edit_executor.dart`（`workout.plan.create`）、`chat_edit_context_loader.dart`（新增「动作库」段，上限常量，含 id+名称+肌群）。
- **命令规格 `workout.plan.create`**：`name`(string, 必填) + `days`(planDays, 必填；≤7 天，每天 `weekday` 1–7、`entries` 1–20 条，每条 `exercise` 文本 + `sets`/`reps` 正整数 + `weightKg` 可选非负)；执行器：动作名→库内**精确唯一**解析（未知/歧义**整条拒绝**，错误文案进编辑卡）→ `WorkoutPlanRepository.create`（其 `_validateDraft`/`_requireExercise` 二次把关）。
- **验收**：创作页任一卡 → 描述 → 生成 → 落在对话分支且消息已自动发送；对话流式回复出现；`isReplying` 时不自动发送；冷启动（对话分支未建）pending 不丢；`workout.plan.create` 正常/拒绝（未知动作、重名星期、空 entries）路径；快照含动作库段。
- **测试与变异**：预填机制、守卫、命令解码/执行/拒绝、快照段；≥4 变异。

**T6c 旧管线退役**
- **验收**：删除清单执行后全库 grep 零残留（逐文件确认，含 `OpenAiCompatibleTaskCapability` 无引用）；**安全断言在命令层重建**（动作解析拒绝未知/歧义、应用前不落库、参数机械校验）；`test/app/secondary_entry_reachability_test.dart` 等入口测试按新语义更新；**S7 实测仪器同步**（`chat_edit_registry_test.dart` 计数与成员、`test/live/ai_takeover_multi_intent_test.dart` 用例矩阵与命令表）。
- **门禁**：删后全量 EXIT=0。**证据**：`...-t6-ai-creation-to-chat.md`（含 a/b/c 三段）。

### T7 · 身份与迁移（需求 69；D9）

- **文件**：`lib/data/database/tables.dart` + `app_database.dart`（schema 23 迁移）+ 备份序列化（`backup/application/backup_table_registry.dart:114` 一带的 `Profile.fromJson` 兼容）+ `settings/presentation/settings_page.dart`（身份卡）+ 新 `UserAvatar` 组件 + `dashboard/presentation/sections/dashboard_greeting_header.dart` + `ai_conversation_page.dart`（顶栏头像）。
- **验收**：
  1. v22→v23 迁移：老库升级后旧数据完整、新列 null、`manualCommuteMinutes` 列不存在；onCreate 新装即 v23；
  2. 旧 `.lfb`（含 commute 键、无新键）恢复不崩、新列 null、commute 键丢弃（钉测试）；新 `.lfb` 往返含新列；
  3. 昵称编辑：1–20 字、trim、空拒绝；今日页头像首字母/图片随昵称变化；
  4. 头像编辑：选图 → 落文件 + 列更新 + 旧文件删除；无图回退首字母；
  5. 身份卡副标题**不再存在**；头像与昵称垂直居中（几何断言）；
  6. 今日页头像与对话页用户头像点击 → 我的页。
- **测试与变异**：迁移双向、`.lfb` 兼容、编辑校验、几何居中、跳转；≥4 变异。**证据**：`...-t7-identity.md`。

### T8 · 设置清理与通勤下线（需求 70/71；D10）

- **文件**：`settings_page.dart`（删两行/恢复入口条件渲染/三导出行去 CSV 后缀——后者与 T12 同批交付）+ 通勤纵切全部文件（§2·70 清单）+ 注册表/执行器/快照段。
- **验收**：全库 grep `通勤|commute` 零命中（白名单外，门禁 = `test/app/round5_retired_feature_grep_test.dart`；
  实现与修订见 §2·77）；**注册表 24→23**（`commute.set` 移除，计数断言同步更新；原文「23→22」按代码事实修正）；
  设置页「食材库」组行序与文案符合 D10；扩展目录失败态仍可恢复；三导出行文案 = 「导出饮食记录」/「导出训练记录」/「导出食物数据」（T12 的文案部分随本包交付）。
- **测试与变异**：grep 断言、行渲染断言、注册表计数、恢复入口条件渲染、三导出调用回归；≥3 变异（实做 5 条 + 1 条门禁实拦，见证据）。**证据**：`...-t8-settings-cleanup.md`。

### T9 · 目标编辑（需求 64/72；D11）

- **文件**：`settings/presentation/profile_edit_page.dart`（两行）+ 新用例 `UpdateWaterTargetMl` + `steps_repository.dart`（读目标）+ `dashboard_quick_stats_row.dart`（读注入目标）。
- **验收**：步数目标写读往返、范围校验、步数卡显示新值（含未授权态）；饮水目标写读往返、今日已有行/新行两条路径、今日页水管与我的页 gauge 联动、历史日期不受影响；默认值兼容（未设置=10000/2000）。
- **测试与变异**：用例两条路径、消费者联动、默认兼容；≥3 变异。**证据**：`...-t9-goal-editing.md`。
- **交付记录（2026-10-13）**：落地口径以本段为准（与上文差异逐条登记）。
  - **两行落位**：`编辑资料` 页新增「每日目标」分组（新 Key `profile-steps-goal`、`profile-water-target`，已同步 docs/21 §5 与三方对账门禁），保存沿用既有确认弹层；
    **空框 = 不改**（这两个字段都没有 null 语义：步数目标未设置时是默认 10000，水分目标是 NOT NULL 列——写不了 null 就不假装写）。
  - **步数目标**：存 `AppSettings` 键 `steps_daily_goal`（十进制整数字符串）；读侧 `StepsRepository.readDailyGoal/watchDailyGoal` 对**缺键 / 坏值 / 越界**一律按 10000（不纠正写回——读不偷偷写）；写侧只有 `updateDailyGoal`，越界（<1000 或 >50000）抛 `ArgumentError` 且不落库。
  - **步数卡口径**：目标来源优先级 = 注入 `stepGoal` > `watchDailyGoal()` 流（设置页改完不重建页面也跟着变）> 默认 10000；**未授权态的隐形占位用同一个目标值**（§6.2 裁决 9 不变）；原先恒 10,000 的常量 `StepsStatCard.dailyStepGoal` 已删（那是第二处目标口径）。
  - **水分目标**：新用例 `UpdateWaterTargetMl`（0.5–6.0 L 之外抛 `WaterTargetException` 且一行不写）；**当日已有生效行 ⇒ 就地更新**（id 与行数不变，只刷 `waterTargetMl` + `updatedAt`），否则**复制上一生效行的全部宏量列另起一行**（`effectiveDate` = 今天）——历史日期行不动（回归断言：昨天的行仍是旧值）。
  - **与原文「未设置=2000」的差异（按代码事实登记）**：未建档（`daily_targets` 没有任何生效行）时**水分目标行留空**，保存时 `run` 拒绝并提示「尚未建立每日目标，无法设置水分目标」——不替用户伪造 2000。
    理由：`daily_targets.water_target_ml` 是 NOT NULL 列，真正的「未设置」不是「列空」而是「没有行」；有行时读到的就是行里的真值。步数目标那边的 10000 才是真默认（无键可读、也不写键）。
  - **设计稿**：`ui设计/round5/t9-goal-editing.html`（4 帧 360dp：编辑资料全页 / 两个越界态 / 步数卡前后 / 水分联动），按 §0 纪律两次自评后开工。

### T10 · 收口

- 全量真机走查（新构建装机，逐条核对 59–79 + 证据帧）；`STATUS.md`/`docs/INDEX.md` 同步；最终门禁 EXIT=0；遗留清单（含 D16 待硬件项、D14 新表头待定、性能测试抗抖建议）。
- **交付记录（2026-10-13）**：走查完成，证据 `docs/evidence/2026-10-13-t10-walkthrough.md` + 帧目录 `docs/evidence/2026-10-13-t10-walkthrough/`（42 张，全新安装起步、`adb install -r` 覆盖复查）。
  走查抓到两个东西，都写进该文件 §2：
  - **当轮修复**：AI 创作三条卡面说明被截断（T6a 的「逐字沿用」有一处不成立）—— 红先断言 + 双变异 + 重建 APK 复拍（§4 T6a 交付记录有详述）；
  - **遗留**：手动创建计划保存成功后训练页计划列表不刷新（切 tab 无效、重启进程才出现；代码位置 `training_page.dart:110` 一带「写路径都以 setState 收尾」的前提在 route 写路径上不成立）。
  其余遗留：设置页清空入口（可选，未做）、AI Key 缺失导致 62 的端到端未在真机走、真秤（D16 待硬件）、`关于` 版本号注入、性能预算抗抖建议。**（D14 新表头 / T11 验收 3 的新结构真机侧与验收 4 已于 2026-10-13 落地，见 §4 T11 交付记录之八与证据 §14。）**

---

### 🔒 第二轮工作包（T11–T16，追加需求 74–79）

### T11 · 食物库清空 + 按新结构重建管线（需求 75；D14）

- **文件**：新用例「清空内置食物」（放 `lib/features/nutrition/application/` 或 `data/`，依赖 `AppDatabase`）+ `food_csv_importer.dart`（三处升级）+ `csv_exporters.dart`（表头，待新结构）+ `app_router.dart`（`_importFoodCsv` 入口）+ 设置页（清空入口，可选）。
- **前置（阻塞）**：**新结构表头需用户提供**（§1.2 事实②）。在拿到表头前，本包只能先做「清空 + 导入器升级」两部分，表头相关改动留占位。
- **验收**：
  1. 清空用例：执行后 `foods` 表**仅剩 `is_user_created=1` 的行**；`meal_items`/`menu_item_food_matches` 引用被置空但**记录完整**；级联表（aliases/revisions/portions）已清；单事务；**可重跑且幂等**；不影响 AppSettings/AI Key/图片（与 `ClearAllLocalData` 明确区分，配一条断言证明 key 未被清）；
  2. 导入器升级：大文件（≥30 MB）不再被上限拒绝；去重索引**流式/分批**建立；落库**批量**且单事务；导入 N 万行耗时可接受（记录实测值）；
  3. 全量重建端到端：清空 → 导入新 CSV → 计数正确、去重提示正确、预览三本账正确；
  4. 新表头落地后：导入/导出/表结构三处一致（三方对账测试）。
- **测试与变异**：清空（保自建/置空引用/幂等/不碰 key）、导入器（上限/流式/批量）、重建端到端；≥4 变异。
- **证据**：`...-t11-food-rebuild.md`。
- **交付记录（2026-10-13，部分交付：验收 1、2 已落地；3、4 阻塞待新表头）**：落地口径以本段为准（与上文差异逐条登记）。
  - **范围**：严格按本段的「前置（阻塞）」一行——只做「清空 + 导入器升级」，**表头相关改动留占位未动**
    （`csv_exporters.dart` 表头、`_mapHeader` 必需列、`foods` 表列定义/schema 迁移）。
  - **验收 1（清空用例）✅**：新用例 `lib/features/nutrition/application/clear_builtin_foods.dart`——
    `ClearBuiltinFoods(AppDatabase).call()` 单事务定点删 `is_user_created = 0` 的行；顺序是外键要求
    （`meal_items.food_id` `tables.dart:381` 与 `menu_item_food_matches.food_id` `:528` 无级联 + 连接开了
    `PRAGMA foreign_keys = ON` `app_database.dart:476` ⇒ 先置空/先删匹配再删食物；派生表走 `onDelete: cascade`）。
    「内置行」用**子查询**表达（`isInQuery`），不把四万多个 id 拉进 Dart 再回传；返回值
    `ClearBuiltinFoodsResult{deletedFoods, unlinkedMealItems, droppedMenuMatches}` 如实报数；幂等（第二次 0/0/0）。
    五条断言：只删内置、引用置空但记录完整、级联表跟着走、幂等、**不碰 AI Key/设置/其它表**（`AiApiKeyStore`
    内存 store 写入后跑清空仍读得到 `secret-key`；另按 `allTables` 逐表比行数，除被清的 6 张表外一张都不许少）。
  - **验收 2（导入器三处升级）✅**：① 上限 16 MiB → **256 MiB**（`sizeViolation` 收 `limit` 参数、实例可注入；
    30/40 MB 放行、**1 GiB 仍拒**）；② 去重索引整表物化 → **分页**（`indexPageSize` 默认 5000，`ORDER BY id ASC`，
    用 `isInQuery` 无关的三列投影）；③ 落库逐行 `create` → **分批 `createMany` + 单事务**（`insertBatchSize` 默认 500）。
    `FoodRepository` 新增 `createMany` + `FoodBatchCreateResult{created, rejected}`，并把行构造抽成 `_row()` 让
    `create`/`createMany` **共用同一套校验与同一套自建标记**（不是两处巧合）。**`failed` 语义按代码事实变更**：
    DB 级意外不再被吞（上抛 + 整批回滚），`failed` 只剩「校验被拒行数」；`app_router._importFoodCsv` 落库步骤
    补 try/catch 给中文原因（本包唯一的生产路径行为变更）。
  - **实测**：2 万行 `preview + execute` = **463 ms**（门禁 `gate5.log:1907`；空载单跑 339–470 ms），
    三本账与落库计数逐条对得上，另设 120 s 松上界只抓数量级退化。
  - **验收 3 / 4 ⛔ 阻塞（如实）**：都要用户的新食物结构文件（§1.2 事实②），本包不做；拿到表头后剩余改动是机械的
    （加列 + 必需列 + 导出表头），两条路径（`_row()` / `_mapHeader`）都没有旁路可绕。**2026-10-13 已解阻**：新结构落地并在真机走通（§4 T11 交付记录之八 / 证据 §14）。
  - **设置页「清空入口」未做**：本段文件清单把它写作「可选」、四条验收也都没要求它 ⇒ 本包不摆 UI 触发点。
    **后果如实记**：全新安装库里本就没有内置食物；**升级安装现存的那 4.9 万行在入口落地前没有可点入口**
    （不会自己消失）。建议与验收 3/4（新表头到位）一并做，一次把「清空 → 重建」做成连贯流程（补它要 UI 稿 + 门禁 + docs/21 §5.8 同步）。
  - **红先**：三个测试文件先写先跑 = **34 条编译错误 + EXIT=1**（API 缺席层面的红）；行为牙齿 = 隔离变异 **11 条**
    （m1–m4 清空判据/两条外键断开/越界删自建；m5 上限回退；m6 跳页；m7 逐批各自提交；m8 批边界丢行；
    m9 去自建标记；m10 同批共用一个 id；m11 跳过校验），**全 RED 且还原后 sha256 逐字节一致**。
  - **门禁**：冻结代码树后 `EXIT=0` / `580 files (0 changed)` / `No issues found!` / **`+2060 ~11 passed`**
    （T15 的 2048 → **+12** = 本包新测试 12 条：清空 5 + 导入器 4 + 仓储 3）。前三次 EXIT=1 分别是
    format 漂移 5 文件（手动 `dart format` 后复跑）、`avoid_print` info lint（测试里的实测耗时打印，按本仓既有
    做法补 `// ignore: avoid_print`）、以及事后改分批索引测试又引出的 format 漂移。
  - **如实限制**：见证据文件 §6（「单事务」在清空侧是结构判据不是注入测试；分批只压住分页正确性、没测内存峰值，
    `preview` 仍全量解析文本；`ORDER BY id` 这条守卫本地测不出，故没进变异表；上限只有纯函数 + 30 MB 字节流、无文件选择器 e2e；`failed` 语义变更；无真机走查）。
  - **交付记录之二（2026-10-13，设置页「清空内置食物」入口补做——本段文件清单里的「（清空入口，可选）」现在落地）**：
    动因 = 上述「后果如实记」那一条：升级安装里那 4.9 万行在入口落地前**没有可点入口**，而需求 75 要的就是「清空」。
    验收 3/4 仍阻塞待用户表头，但清空这半条与表头无关，故先做。
    - **设计稿**：`ui设计/round5/t11-clear-foods.html`（5 帧 × 360dp：有内置行时的组 / 三种不渲染态 / 有引用弹层 / 无引用弹层 / 执行后回写）。
      作者自评两轮修掉 **5 条**瑕疵：① 11 处字面 `**` 星号上屏（改 `<strong>`）；② 弹层遮罩没压暗（读不出模态）；
      ③ 两动作竖排全宽按钮与仓内先例（`_openClearAllDialog` = Row `spaceBetween`：取消左 / 销毁右）不一致；
      ④ frame ⑤ 用「判据 ②」这种自造编号要读者回查（改写成「库里已无内置行」）；
      ⑤ 销毁动作画成实心红底，而 §3.8 B7 的 `LfDangerButton` 是 **error 字色文字按钮**（「清除所有数据」同款）⇒ 改稿对齐。
      渲染图 `docs/evidence/2026-10-13-t11-clear-foods-entry/04-draft-review-sheet-r4.png`。
    - **位置与形态**：`SettingRow(key: settings-clear-builtin-foods, icon: layers_clear_outlined, destructive: true)` 放
      **食材库组末**（D10 的三行常驻顺序不动，销毁行与「添加食物数据」拉开距离）。
    - **自门控（三条全真才渲染）**：`clearBuiltinFoods != null`（未接线不渲染，对齐设置页既有约定）+
      概览已加载且 `foodCount > userCreatedFoodCount`（**库里有内置行**；T13 之后全新安装恒 0 条 ⇒ 不摆空动作）+
      概览加载失败按「无内置」处理。判据与计数行读**同一个** `_overviewFuture` ⇒ 清空后行自己消失。
    - **弹层的数是现算的**：`ClearBuiltinFoods.preview()`（新增只读预览，与 `call()` 共用同一个「内置行」子查询判据）
      给三组计数——内置食物 N / 引用它们的餐次条目 M / 菜单匹配 K；正文按 0/非 0 拼句（M 或 K 为 0 那句整条不提）。
      预览为空（库里已无内置行）**不弹层**，只回「没有内置食物可清空。」并顺手重读概览。
    - **执行后三个后果**：库真清（用例已交付）+ 计数行就地重读（`_refreshOverviewAfterFoodWrite`，弹层返回不触发
      `TickerMode` 重读）+ 行消失 + snackbar 如实报数（`deletedFoods`/`unlinkedMealItems`；`deletedFoods == 0` 照实说）。
      取消 = `LfTextButton`（左，纯文字）；销毁 = `LfDangerButton`（右，error 字色）执行中变「正在清空…」+ busy，失败复位并给一行红字原因。
    - **接线**：`main.dart`（构造 `ClearBuiltinFoods(database)`）→ `LocalFitApp`（透传）→ `createAppRouter` → `SettingsPage`
      ——与 `clearAllLocalData` 同一条通路；**这条通路在 `flutter analyze` 之外还抓到一个真错**（见下）。
    - **红先**：两个测试文件先写先跑 = **编译错 RED**（`No named parameter 'clearBuiltinFoods'` / `The method 'preview' isn't defined`），
      与验收 1/2 的「API 缺席层面的红」同口径。新断言 **9 条**（清空入口 7 条 widget + preview 2 条用例）。
    - **隔离变异 6 条全 RED**（驱动器 `E:/AI/Zcode/tmp/localfit-t11/mutate_clear_foods.py`，日志 `mcf1..6.log`）：m1 preview 判据反转 /
      m2 行自门控只剩 null 判据 / m3 执行后不重读概览 / m4 空预览照样弹层 / m5 清空行离开组末 / m6 正文去掉 >0 守卫；
      每条还原后 sha256 与基线**逐字节一致**。
    - **设备与探针（如实）**：正向分支（有内置行）在模拟器上**不可达**——内置行只可能来自升级安装的旧数据，
      而设备库是 SQLCipher 加密（`app_database.dart:74-84`，sqlite3 CLI 打不开）、CSV 导入一律自建
      （`food_csv_importer.dart:266` 明写「origin 列只作展示对照」）、扩展目录导入需要随包 manifest（本构建没有）。
      所以：真机只验**负分支**（全新安装 + 0 内置行 ⇒ 组内仍是三行、无清空行；帧
      `01-device-fresh-install-group-3rows.png`），正向分支改用 **host 渲染探针**（T15 §59 同类做法，临时件、不入常驻 golden）
      出 `02-probe-group-with-row.png`（组末红色行）/`03-probe-confirm-sheet.png`（弹层几何与两枚文字按钮）——
      CJK 在测试环境是方框，探针只作**几何与配色**证据，文案正确性由 widget 测试的字符串断言钉。
    - **docs/21 §5.8 同步**：树里补清空行（并顺手修掉 T8 已删的「添加自定义食材」旧提法）+ 测试 Key 表加
      `settings-clear-builtin-foods`、`clear-builtin-foods-body`、`clear-builtin-foods-confirm`（三方对账测试绿）。
    - **门禁**：见 STATUS.md 的 T11 第二次 Updated 段。

  - **交付记录之三（2026-10-13，验收 3/4 的机器外框与落地清单——验收本身仍 ⛔ 阻塞待用户表头）**：
    动因 = 上文「验收 3 / 4 ⛔ 阻塞」那条。本段只做两件**与表头无关**的准备（清单 + 外框），**不勾任何验收**。
    - **新 pin（验收 4 的机器外框）**：`test/features/nutrition/food_csv_importer_test.dart` 新增
      「导出表头的列集 == 导入器消费列 ∪ 显式仅展示列（防新列静默丢弃）」。表头取自**导出器自己的输出**
      （`_foodsHeader` 是私有常量 ⇒ 走 `const CsvExporters().foodsCsv(空库)` + `FoodCsvImporter.parseCsvRows`
      两条公开通路），消费列 = `_mapHeader` 必需 5 列（`food_csv_importer.dart:347-359`）+ `preview` 真读的
      brand（:174）/ category（:214），仅展示 = origin（:266「CSV 里的 origin 列只作展示对照」，读都不读）。
    - **为什么值钱**：`_mapHeader` 注释明写「多出的列忽略，宽容导入」⇒ 新结构落地时「CSV/导出加了列、
      导入器没接线」**不会报错也不会进库**（静默丢数据），而既有往返测试（`food_csv_importer_test.dart:335`）
      在「加列」方向恰好被宽容导入吃掉、是**绿的** ⇒ 这条 pin 把静默变成一条**带落地指引的红**。
    - **红先做不到（如实）**：pin 描述的是既有行为，天生是绿的 ⇒ 牙齿用**隔离变异**证明（与 T12 验证-only 同口径）：
      m1 表头多一列 `fiber_per_100g`、m2 表头少一列 `origin`，**两条都 EXIT=1 RED**（失败消息即落地指引，
      m1 的 Actual 集合里直接列出 `fiber_per_100g`），还原后 sha256 `dd7f7e11…` 与基线逐字节一致
      （驱动器 `E:/AI/Zcode/tmp/localfit-t11/mutate_header_guard.py`，日志 `mhg1/mhg2.log`；基线
      `mhg0-baseline.log` = 该测试文件 `+22` EXIT=0，改造前 21 → 加 1 条 pin）。变异锚点要按**文件自己的换行**拼：
      `csv_exporters.dart` 是纯 CRLF，测试文件是纯 LF（第一版驱动器用 `\n` 锚点 0 命中，当场修）。
    - **落地清单（行号 = 2026-10-13 冻结树；**已按本清单落地**，行号仅存史）**：导出表头 `csv_exporters.dart:54-63` +
      行渲染 `:156-171`；导入消费 `food_csv_importer.dart:347-359`（必需列）/ `:174`（brand）/ `:214`（category）/
      `:184-207`（数值校验）；落库映射 `food_repository.dart:230-246`（`_row()`，`create`/`createMany` 共用）+
      `NewFood` 字段 `food_record.dart:34`；表结构 `tables.dart:119-146`（`Foods` 现 17 列）+
      `app_database.dart:91`（`schemaVersion 24`）与 `:99`（`onUpgrade` 链）——**加列 ⇒ 24→25，迁移历史不改写**；
      测试字面量 `food_csv_importer_test.dart:42`（fixture 表头）/ `:117-124`（缺必需列文案）/ `:335`（往返——
      加字段后要把「读回一致」扩到新字段）/ 新 pin 的 consumed+displayOnly；`csv_exporters_test.dart:231-232`（表头字面量）。
    - **两处如实提醒**：① §6 的三处列名契约里，分片与种子 JSON 两处已随 T13 退役（`archive/food-seed-2026-10-13/`），
      活着的只剩主库 CSV 一处——改动只需一处但**必须导出 + 导入成对**同步；② 设计源
      `ui设计/remediation/食物库-大库与导入导出.html` 的 8 列契约**没有机器门禁**（`design_source_parity_test` 不读它）
      ⇒ 结构变时要么同改、要么明确归档（本次不动它：它与当前实现仍逐字一致）。
    - **验收 3/4 仍未做**：验收 3 的「新 CSV」与验收 4 的「新表头」都要用户文件（§1.2 事实②）⇒ 本段不勾任何验收。
      门禁与四次文档同步见 STATUS.md 的 T11 第三次 Updated 段、证据 §9。

  - **交付记录之四（2026-10-13，验收 3 的机器部分：「清空 → 回灌」连贯测试；真机侧与验收 4 仍 ⛔ 阻塞待用户文件）**：
    验收 3 的三条判据（计数正确 / 去重提示正确 / 预览三本账正确）此前只在**各自包内部**被覆盖（清空 5 条、导入器 4 条、
    预览↔落库对账 1 条），**连贯流程（清空 → 导入 → 对账）没有测试**；本条把它补上，且**新表头落地后无需改动**。
    - **表头自适应是刻意的**：CSV 用**导出器自己的输出**（`CsvExporters().foodsCsv(整库)`）⇒ 不写死任何列名，
      用户的新表头一落地，这条测试直接覆盖新结构、fixture 零改动。
    - **场景**：库 = 2 条内置（`source='seed-v5'`）+ 1 条自建（`repository.create`）+ 1 条引用内置行的饮食记录 ⇒
      导出整库 ⇒ `ClearBuiltinFoods.call()` ⇒ `preview` ⇒ `execute(skipDuplicates)` ⇒ 再 `preview` 一遍。
    - **十五条断言**（清空侧 5 / 预览侧 3 / 落库侧 5 / 幂等 2）：
      `deletedFoods == 2`、`unlinkedMealItems == 1`、清空后只剩自建行、记录本身保留、引用被置空、
      `errorCount == 0`、`newCount == 2`（被清掉的内置行回灌时是新增）、`duplicateCount == 1`（保住的自建行是唯一重复）、
      `imported == 2` + `skippedDuplicates == 1` + `failed == 0`、回灌后 3 行且**全是自建**、
      第二遍 `newCount == 0`（「没有幽灵重复」）+ `duplicateCount == 3`。
    - **红先做不到（如实）**：pin 类（描述既有行为，天生绿）⇒ 牙齿 = 3 条隔离变异，**全 RED 且归因到本测试**
      （归因判据写进驱动器：失败行必须同时带 `[E]` 与测试名片段「用导出文件回灌」——m2 那次连带 4 个测试红，
      没这条判据就可能把别人的红当成自己的）：m1 清空判据反转（删自建）→ `deletedFoods` Expected `<2>` Actual `<1>`；
      m2 身份索引致盲（`return keys;` → 空表）→ `newCount` Expected `<2>` Actual `<3>`（reason 即「被清掉的内置行回灌时是新增」）；
      m3 置空改连记录删 → `hasLength(1)` Actual `[]`（reason「记录本身保留」）。还原后 `clear_builtin_foods.dart`
      与 `food_csv_importer.dart` 的 sha256 逐字节一致（驱动器 `E:/AI/Zcode/tmp/localfit-t11/mutate_rebuild_flow.py`，
      日志 `mrb1..3.log`；基线 `mrb0-baseline.log` = 该测试文件 `+23` EXIT=0）。
    - **仍缺的一半（如实）**：CSV 不是**用户那份新结构文件**（那份文件本机不存在，§1.2 事实②）⇒ 验收 3 只补齐了
      **机器侧 / 结构无关的那部分**；真机侧（拿新结构 CSV 走一次「清空 → 导入」）与验收 4 的新表头对账仍等用户文件。
      门禁与文档同步见 STATUS.md 的 T11 第四次 Updated 段。
  - **交付记录之五（2026-10-13，验收 3 的**真机侧（旧结构 CSV）**：升级安装走查补齐「清空 → 导出 → 回灌」全循环；新结构真机侧与验收 4 仍 ⛔ 阻塞待用户文件）**：
    交付记录之二「如实限制 ①」写过「正向分支无真机帧——内置行只可能来自升级安装的旧数据」；本次走查证明那条路**走得通**：把 Oct 11 的 pre-T13 构建真装一次，它的 `FoodSeedImporter` 会真灌 49,444 行，再原地升级到新构建（`adb install -r -d`，数据完整保留）⇒ 正向分支在真机可达。**22 帧** `docs/evidence/2026-10-13-t11-clear-device-upgrade/`（`LocalFit_API35`，1080×2340 = 360dp）。
    - **清空正向分支（帧 04–11）**：旧构建实拍「食材数据库 49,444 条（自建 0 条）」+ 仍在的「通勤时间」行 → 升级后新构建同库同数 + 红字「清空内置食物数据」行 → 确认弹层「将删除 49,444 条内置食物（自建食物保留）。设置、AI 配置与照片不受影响；此操作不可撤销。」（`preview()` 现算）→ **取消不动数**（复拍同数）→ 先导出（SAF 落 Downloads：4,287,517 B、BOM + 8 列表头、`wc -l` 49,444 数据行、`origin=内置`；adb 拉回宿主 sha256 `3516e676…`）→ 再开弹层 → 执行 → snackbar「已清空内置食物：删除 49,444 条。」+ 计数行就地变「0 条（自建 0 条）」+ **行自己消失**（自门控成立）。
    - **回灌全循环（帧 12–20）**：添加食物数据 → 从 CSV 文件导入 → 同一份导出 → 预览「可导入 49444 / 重复 0 / 错误 0」→「跳过重复，导入 49444 条」→ 计数行「49,444 条（自建 49,444 条）」（模拟器写入 ≈40–60 s；完成 snackbar 在轮询间隙消失，完成由三方互证：计数行 + 二遍全判重复 + 第三遍按导入行判重）。**同文件二遍** = 「可导入 0 / 重复 49444 / 错误 0」+4 条样本 +「……另有 49440 条重复。」= **分页去重索引在 49,444 规模的真机判据**；`newCount == 0` 时「跳过重复」按钮按代码设计不渲染（`food_import_preview_sheet.dart:91`），`全部导入` 语义会整库复制 ⇒ 取消。**旧 4 行 fixture 混账**（`localfit-foods-test.csv`）= 「可导入 2 / 重复 1（鸡蛋（无品牌））/ 错误 1」+ 错误行原文「第 4 行「abc」不是数字。」→「跳过重复，导入 2 条」→ snackbar「已导入 2 条食物（自建）。跳过重复 1 条。」→ 终态「49,446 条（自建 49,446 条）」。
    - **升级路径顺手复核**：新构建在升级数据上**没有**「通勤时间」行（旧构建帧 02 有）——需求 77 的删除在升级路径也成立；旧种子行在新构建里原样可见（帧 04），说明 schema 24 迁移在同一加密库上无损。
    - **门禁**：本走查**零代码改动**（只增帧与文档）⇒ 不触发新门禁；T11 门禁仍以 `t11rb-gate1.log`（EXIT=0 / +2072）为准（docs 里只有 docs/21 被测试读，未动）。
    - **如实限制**：CSV 仍是**旧结构**（导出↔导入同一格式）——新结构表头未到位 ⇒ 验收 3 的「新结构真机侧」与验收 4 三方对账仍等用户文件；模拟器 + 通用 APK 非实体机；第一遍导入的完成 snackbar 未捕获（三方互证补齐）；应用库 SQLCipher加密、adb 读不了 ⇒ 全部计数取自应用 UI（读真库）；模拟器时钟比宿主晚一天（帧内 2026-10-12 23:0x，同 T10 遗留 ⑦）；`-d` 降级安装是 dev 构建 versionCode 倒挂（4003→3）的产物，真实发行不会出现。文档同步见 STATUS.md 的 T11 第五次 Updated 段。
   - **交付记录之六（2026-10-13，验收 4 的第三条腿：`foods` 表结构 ↔ CSV 映射 pin；验收 4 的**新表头对账**本身仍 ⛔ 阻塞待用户文件）**：
     交付记录之三那条 pin 管「导出表头 ↔ 导入器消费列」，交付记录之四的连贯测试管「清空 → 回灌」的语义——**表结构本身没有断言**：`foods` 上偷加一列、或两个命名系错位（表列 `kcal_per100g` vs CSV `kcal_per_100g`），既有断言都照绿。新 pin（`test/features/nutrition/food_csv_importer_test.dart`，1 测试 2 断言）：A）`database.foods.$columns` 的 SQL 名集 == `csvToTable.values ∪ tableNotInCsv`（8 个 CSV 列的去向 + 9 个显式登记的不参与列 = 17 列一个不多一个不少；`origin` → `is_user_created` 是派生列）；B）导出表头列集 == `csvToTable.keys`（把两个命名系的映射显式记住，不再靠人脑）。失败消息即落地指引：新列先决定去向（进映射还是进登记），再同步导出表头 / `_mapHeader` / 行映射 / §2 列清单；落库新列还要 schema 24→25。
     - **隔离变异 3 条全 RED**（pin 天生绿，牙齿全在变异；驱动器 `E:/AI/Zcode/tmp/localfit-t11/mutate_threeway_pin.py`）：m1 表头删 `origin`、m3 表头插 `fiber_per_100g`（模拟新结构落地未登记）⇒ 两条 pin 齐红且归因成立（失败行须同时含 `[E]` 与测试名片段「表结构腿」）；m2 把 `app_database.g.dart` 里 `$FoodsTable` 的 `kcalPer100g` SQL 名改成 `kcal_per_100g`（按类范围定位，避开 `$FoodNutritionRevisionsTable` / `$MenuItemNutritionEvidenceTable` 两处同名列镜像）⇒ 本 pin 报 `does not contain 'kcal_per100g'` 归因成立，**但爆炸半径 10/24 红**：生成代码 SQL 名与迁移 DDL 里写死的 `kcal_per100g` 分了家 ⇒ 插入路径全断（`no such column`）。这条如实说明**迁移 DDL 是第二处列名事实**，新结构落地时它也在清单里。还原后两生产件 sha256 逐字节一致（`dd7f7e11…` / `15ef731d…`），复跑基线 EXIT=0。
     - **门禁**：`t11tw-gate1.log`：`581 files (0 changed)` / `No issues found! (ran in 6.0s)` / **`+2073 ~11: All tests passed!`** / **EXIT=0**（交付记录之四的 2072 → **+1** = 本 pin 一条）。文档同步见 STATUS.md 的 T11 **第六次** Updated 段；证据 §11。
   - **交付记录之七（2026-10-13，验收 4 的**值**腿：逐列值往返 pin；验收 4 的**新表头对账**本身仍 ⛔ 阻塞待用户文件）**：
     交付记录之三/六把「导出 / 导入 / 表结构三处一致」钉到了**列名**层；值这一半此前是空的——先审缺口（读遍既有断言）确认三处真实破坏都能**全绿**：`_row()` 置空 `brand` 只红两条去重身份测试；导出把 `protein_per_100g` / `carbs_per_100g` 两格调换 = **0 红**；导入把 `carbs` 读成 `protein` 那列 = **0 红**。⇒ 新结构落地后的「解析了却没落库 / 落库了却没回读」不会被机器抓住。新 pin（`test/features/nutrition/food_csv_importer_test.dart`）：源行**直插表**（每列一个区分值，`isUserCreated=true` 让 `origin` 首尾都是「自建」）→ 导出 → 清空库 → 同一份文件导入 → 再导出，**逐列**比对两遍数据行，不写死任何列名。
     - **一个自我修正（如实记）**：第一版 fixture 走 `repository.create` 时，m1（`_row()` 丢 `brand`）**打不红**本 pin——源行也过 `_row()`，漏列被「第一次导出本来就是空的」掩盖；改直插表后立刻在「brand」列红。
     - **隔离变异 3 条全 RED**（驱动器 `E:/AI/Zcode/tmp/localfit-t11/mutate_value_roundtrip_pin.py`）：m1 `_row()` 置空 `brand`（失败集合 = 2 条去重测试 + 本 pin）、m2 导出调换 protein/carbs、m3 导入错列（后两条的失败集合**恰是本 pin 一条** ⇒ 「没这条 pin 会全绿」是量出来的）；失败消息带列名与前后两个值。还原后 `food_repository.dart` `1a4189d6…` / `food_csv_importer.dart` `3e86c65b…` / `csv_exporters.dart` `dd7f7e11…` 逐字节一致；基线 `vrp0b-baseline.log` = 该测试文件 `+25` EXIT=0，末尾复跑绿。
     - **门禁**：`t11vr-gate1.log`：`581 files (0 changed)` / `No issues found! (ran in 5.4s)` / **`+2074 ~11: All tests passed!`** / **EXIT=0**（交付记录之六的 2073 → **+1**）。文档同步见 STATUS.md 的 T11 **第七次** Updated 段；证据 §12。

  - **交付记录之八（2026-10-13，**T11 验收 3 的新结构真机侧 + 验收 4 的新表头对账**：新结构已落地并真机走通）**：动因 = §13.4 找到用户的新结构（`国内食品营养数据_扩充版2.csv`，21 列 / 19,974 行）而 §13.4 的三问在会话里**未获回答**；裁定依据 = §6 第 7 条自己写下的例外「**除 T11 按新结构统一外**」（本轮就是 T11），且三问一律取**无信息损失**那一支：结构源 = 该文件表头、入库 = 全 21 列、分类 = 库大类原文进新列 + 24→10 映射表填枚举（不动枚举本身）。**这一段即 T11 的既定动作，不是新需求。**
    - **四处成对改（生产）**：`tables.dart`（`Foods` 17→**32** 列，15 个 `text().nullable()`）+ `app_database.dart`（`schemaVersion 24→25`，`if (from < 25)` **存在性驱动**加列：查表有无、列有无 ⇒ 幂等 / 裁剪库 no-op / 半迁移库不炸）+`build_runner` 重跑（未手改生成件）；`csv_exporters.dart`（表头 **21 列中文逐字**；一级分类 = 库大类原文 ?? 枚举标签 ?? 空；`origin` 退役）；`food_csv_importer.dart`（`_columnAliases` 21 键中文首选 + 旧英文别名 ⇒ **旧 8 列文件照旧可导**、缺必需列报中文名、行映射读全 21 列）；`food_category.dart`（**24 条**库大类映射表 + 只读视图 + `tryFromLibraryGroup`；表外值走既有「不是有效种类」整行拒绝，不猜「其他」）；`food_record.dart`/`food_repository.dart`（`NewFood` +15 字段、`_row()` +15 列）。
    - **测试 +9 / 门禁**：三条 pin 重写（导出表头 pin 改成「21 列全消费 + 仅展示集为空」、表结构腿 pin `csvToTable` 21 键 + `tableNotInCsv` 11 列、值往返 fixture 21 列各给区分值）+ 新断言 4 条（21 列逐列接线 / 旧 8 列兼容且 15 新列 null / 24 库大类映射全覆盖 /导出表头逐字 == 用户 21 列）+ v25 迁移测试 5 条。`d-gate3.log`：`582 files (0 changed)` / `No issues found!` /**`+2083 ~11: All tests passed!`** / **EXIT=0**（基线 2074 → **+9**）。（`d-gate1.log` 先红于 `dart format --set-exit-if-changed`（5 文件），格式化后转绿；文档同步后在冻结树上复跑 `d-gate4.log` 同样 **EXIT=0 / +2083** = **最终那次**。）
    - **隔离变异 9 条全 RED 且逐字节还原**（驱动器 `E:/AI/Zcode/tmp/localfit-t11/mutations_t11b.py`；M1 别名断 / M2 删英文别名 / M3 映射少一条 / M4 表头改字面量 / M5 表头偷加列 / **M6 表结构偷加列 + 真跑 `build_runner`** / M7 `_row()` 丢列 / M8 导出器不回退 /M9 迁移去存在性判断）：目标断言逐条变红，复原后 sha256 与绿基线逐字节相同，末尾复跑门禁绿。
    - **验收 3 的新结构真机侧 ✅**（**13 帧** `docs/evidence/2026-10-13-t11-new-structure-device/`）：全新安装（先 uninstall）→设置页「食材数据库 **0 条（自建 0 条）**」且**无清空行**（行自门控）→ 导入 `t11-new-structure.csv`（= 用户 `扩充版2.csv` 原字节 7,865,727 B）→预览**三本账 19974 / 0 / 0** → 落库计数 **19,974 条（自建 19,974 条）** → 导出真机文件（宿主复核：8,703,486 B / BOM / 纯 CRLF /19,975 行 / 每行 21 格 / sha256 `7cb03804…`）→ **二遍同文件 = 可导入 0 / 重复 19974 / 错误 0**（首页「……另有 19970 条重复。」）→ 取消后库仍 19,974。清空正向分支仍以升级走查 `2026-10-13-t11-clear-device-upgrade`（22 帧 / 49,444 行）为据——全新安装没有内置行，那一支真机点不到。
    - **验收 4 的新表头对账 ✅**（`reconcile_export.py`，**16 项全过**；报告 `accept4-report.json` 与帧同目录）：① 导出表头逐字 == 用户 21 列；② 21 列在导入器别名表全有归属、5 必需列齐；③ `foods` 表列集 == `csvToTable.values ∪ tableNotInCsv`（**独立解析 `tables.dart`** 得来）+ `csvToTable` 键集 == 21 列；④ 值体检（营养值范围 / 一级分类全在 24 大类 / 计量口径两种 / ID 与名称非空）；⑤ **抽样 24 行 × 21 列与源文件逐格相同** + `食品ID` 全集相等（19,974/19,974）。
    - **如实限制**：模拟器 + 通用 release APK，非实体机；SQLCipher 库 adb 读不了 ⇒ 计数取自 UI；模拟器时钟晚一天（帧内 2026-10-12 23:0x）；导入件在设备上改用 ASCII 名（中文名 `adb push` 静默失败，与产品无关）；候选文件是流水线 2026-10-12 21:53 版，再导出一版时第一条变红的会是「导出表头逐字」pin；导出件 8.7 MB 未入库（留 sha256 + 抽样）。文档同步见 STATUS.md 的 T11 **第九次** Updated 段（收官段；前一段是完成度审计）；证据 §14。

### T12 · 导出行文案（需求 76；D17）

- **范围修订（2026-10-13）**：三行 label 的改名**已随 T8 一起交付**（同一段代码、同一次门禁，拆成两包
  只会让 T8 的「设置页文案符合 D10」验收悬空）。⇒ 本包只保留**验证**部分：三行文案精确断言 +
  点击行为与导出内容回归；证据并入 `...-t8-settings-cleanup.md`，不另开文件。
- **文件**：`settings_page.dart` 三行 label（已在 T8 落地）。
- **验收**：三行文案 = `导出饮食记录` / `导出训练记录` / `导出食物数据`；**不含 "CSV"**；点击行为与导出内容**不变**（回归测试钉住三行各自的导出调用与文件名——`test/features/settings/round5_settings_cleanup_test.dart`）。
- **测试与变异**：三行文案断言 + 三行调用回归；≥2 变异（文案回退带 CSV 后缀 = 已在 T8 的 M3 做过，红/绿均有记录）。
- **交付记录（2026-10-13，验证-only）**：落地口径以本段为准。
  - **没有新写代码**：三行 label 在 T8 就位（`settings_page.dart`），本包的全部工作是**确认验收两条都被机器钉住**，
    并把结论落进 T8 的证据文件（不另开证据文件，按本段的范围修订）。
  - **验收 1（文案）✅**：`test/features/settings/round5_settings_cleanup_test.dart` 的
    「三个导出行：文案去 "CSV" 后缀，全页无 CSV 字样」——`find.text('导出饮食记录'|'导出训练记录'|'导出食物数据')`
    各 `findsOneWidget`，外加 `find.textContaining('CSV') == findsNothing`（**整页**无 CSV 字样，比只查三行严）。
  - **验收 2（行为不变）✅**：同文件「三行各自的点击仍触发各自的导出（文件名区分，行为未变）」——三行分别点按后
    断言落盘文件名前缀 `localfit-meals-` / `localfit-training-` / `localfit-foods-`，并断言食物库导出正文里
    **真的有那条自建食物**（不是「导了个空壳还报成功」）；三个 Key（`cta-export-csv` / `backup-export-training-csv` /
    `backup-export-foods-csv`）一字未改，作为回归抓手。
  - **变异**：T8 的 M3（「导出饮食记录」→ 加回「 CSV」后缀）已让该文案断言变红、还原后 sha256 一致（见
    `...-t8-settings-cleanup.md` §4）；本包不重复做同一条变异。
  - **门禁**：本包无改动 ⇒ 沿用 T8/T16 的 EXIT=0（T16 复核那次全量门禁 `+2025 ~11 passed`，
    三个导出行用例都在其中）。

### T13 · 移除随包食物种子（需求 75；D13）

- **文件**：`pubspec.yaml:46`（删声明）+ `assets/seed/foods.v5.json`、`foods.v4.json`（移出仓库，建议归档到 `E:/AI/Zcode/projects/localfit-ai/archive/` 而非真删——它们是不可再生的数据资产）+ `food_seed_importer.dart`（退役食物分支，**保留动作库导入器**）+ `lib/main.dart:106`（删调用）+ 两个测试。
- **验收**：
  1. 启动**不再**导入任何食物种子（全新安装首启后 `foods` 表为空）；
  2. `assets/seed/` 仅剩 exercises 系列；
  3. 动作库导入**不受影响**（回归）；
  4. 两个测试按新语义更新（`food_seed_importer_test` 退役/改写；`privacy_statement_audit_test` 的随包资产清单与 retiredSeedFiles 更新）；
  5. 首启耗时改善（记录 before/after 实测，验证 B18 消失）。
- **测试与变异**：启动不导入断言、资产清单断言、动作库回归；≥3 变异。
- **风险与如实记**：旧安装升级后 4.9 万行**仍在库里** ⇒ 必须配套 D14 清空（T11）；数据文件归档而非删除，避免不可逆损失。
- **证据**：`...-t13-seed-removal.md`。
- **交付记录（2026-10-13）**：落地口径以本段为准（与上文差异逐条登记）。
  - **范围修订（本包比原文估计的大一档，原因是「种子同时是测试 fixture」）**：原文写「退役食物分支 + 两个测试」，
    实际 `FoodSeedImporter` 是整个文件删除（它只有食物逻辑），并且它**同时是 26 个测试文件的 fixture 提供者**——
    `await const FoodSeedImporter().importIfNeeded(db);` 这种调用出现在 **25 个文件 / 28 处**（营养、仪表盘、备份、
    恢复、压力与窄屏几何探针等都靠它把库垫起来）。所以本包实际动了：**新增** `test/support/food_fixture.dart`
    （6 条代表性食物 + `seedFoodFixture()`，`onConflict: DoNothing`）+ **迁移 25 个文件 28 处调用** +
    `test/utils/food_name_test.dart`（它直接读 v5 种子做 49,444 条全量枚举）+ 隐私审计的四处断言 +
    `tool/food_seed/` 两个脚本的种子路径 + 一个**新测试文件**。
  - **删除与归档**：`lib/features/nutrition/data/food_seed_importer.dart`、
    `test/features/nutrition/food_seed_importer_test.dart`（其断言对象已不存在；随包导入契约由
    `no_bundled_food_seed_test.dart` 与动作导入器测试接续）删除；`assets/seed/foods.v5.json`（11,342,444 B、49,444 条）
    与 `foods.v4.json`（10,703,218 B、49,464 条）归档到 `E:/AI/Zcode/projects/localfit-ai/archive/food-seed-2026-10-13/`
    （含 README：来源、sha256、为什么退役、谁还在读它）。`assets/seed/` 现在只剩 exercises 三件（验收 2 ✅）。
  - **`lib/main.dart`**：删掉那行导入调用，注释改成如实说明（退役日期、退役原因、归档路径、动作库照旧）。
    `await const ExerciseSeedImporter().importIfNeeded(database);` 保留 —— 动作库回归见验收 3。
  - **来源标注的诚实修正（原文没提，本包新增一处产品改动）**：`DataDelivery` 增一档 `DataDelivery.retiredSeed`
    （`lib/core/attribution.dart`），FoodCalu 条目从 `bundledSeed` 改成它，note 改成「历史随包（截至 2026-10-13 的版本）
    49,444 条中文食物；新版本不再随包，升级安装的库里可能仍保留这些行」，设置页标注显示
    **`FoodCalu 中文食物库（历史随包 · 现已不随包）`**。理由：继续写「随包」是假话（新包里没有），直接删条目是另一种
    假话（升级安装的库里可能还有那批行，用户看不到它是什么）；`shipped` 判定同步排除该档。许可证调查结论与上游地址
    继续留在 `tool/food_seed/README.md`（隐私审计新增断言：退役来源的 README 必须同时含上游、许可证原文、且写明「退役」）。
  - **隐私审计（`privacy_statement_audit_test.dart`）四处改法**：① `retiredSeedFiles` 变量没了，退役名单改成
    测试内写死的两个文件名（「必须不被 pubspec 声明」）；② `shippedDatasets() => bundledDatasets()`（盘上剩下的就都是
    随包的）；③ 随包清单断言变成**只有三个动作库文件**；④ strip 脚本对账改成「仓库里或 `../archive/` 里找得到种子才跑」
    （脚本自身路径也按同一次序解析）。`test/features/training/exercise_seed_importer_test.dart` 里拿 food 种子当
    「随包但版本不匹配」的反例改指 `exercises.v1.json`（v1=version 1，仍能考版本拒绝，只是不再是跨类型反例）。
  - **验收 1（启动不再导入食物种子）**：`test/features/nutrition/no_bundled_food_seed_test.dart` 三条——retired 资产的
    `rootBundle.loadString` 必须抛（不再随包）+ **反向对照**（同一次运行里动作种子照旧读得到，否则「bundle 整个坏了」
    也会让它通过）+ 全新内存库跑完随包导入路径后 `foods` 为空、`exercises` 312 条；第四条是 `lib/` 静态扫描
    （不许再出现 `FoodSeedImporter` 或带引号的 `assets/seed/foods…` 字面量）。
  - **验收 5（B18 前后实测）**：退役前基准 `fresh_food_import_ms=842 rows=49444` / `second_food_import_ms=10`
    （宿主机、`flutter test` 口径，一次性 bench，测完删除）；退役后该路径不存在，首启少掉的是**首装 842 ms 的
    同步导入 + 每次启动 10 ms 的幂等探测**，包体少 **11.3 MB** 资产（`pubspec.yaml` 声明删除）。
  - **变异（6 条 + 1 条观察，全红、还原后 sha256 逐字节一致）**：M0 只声明不拷文件 → 观察：`flutter test` 连
    asset bundle 都构建不出来（fail-fast 防线，未跑到断言层）；M1 拷回 v5 + 声明（完整恢复随包态）→ 隐私两条断言红；
    M2 只拷回不声明 → 同两条红；M3 FoodCalu 改回 `bundledSeed` → 设置页标注断言红；M4 `lib/main.dart` 里塞回带引号的
    退役路径 → 静态扫描红；M5 拔掉 `splitFoodName` 的词表判据 → 真实种子全量枚举（49,444 条）等 4 条红；
    M6 剥离脚本来源清单多一项 → Python 对账 FAIL。报告：`E:/AI/Zcode/tmp/localfit-t13-mutations/mutation-report-t13.txt`。
  - **如实记（局限，不藏）**：
    1. **归档在仓库外 ⇒ 三条断言在有归档的机器上跑、在全新检出的机器上不注册**（food_name 的 49,444 条全量枚举、
       隐私审计的 strip 来源对账、`test_strip_seed.py` 的两条真实种子断言）。这是退役的直接代价：真数据不再在仓库里，
       就没有仓库内的真值可比。守卫写在断言的注册条件里（有归档才注册），不是「删断言假装还覆盖着」。
    2. `tool/food_seed/` 的**生成**脚本（`build_foodcalu.py`、`apply_review.py`、`build_brand_gazetteer.py`、
       `review/review_lib.py`、`review/export_display_preview.dart`）路径仍指向仓库内旧位置，本轮只改了**剥离脚本**
       （它被仓库测试审计）并在 README 写明「重跑前需从归档恢复」；要重跑生成链得先把种子放回 `assets/seed/`。
    3. `lib/utils/food_brands*.g.dart` 与 `lib/features/nutrition/domain/food_seed_count.g.dart` 的注释里仍写着
       种子路径与 sha256 —— **故意保留**：那是这批历史数据的来源交代（同时 `kFoodSeedV5RowCountGrouped` 仍被
       设置页标注使用），静态扫描因此只查代码引用、不查注释。
    4. `.dart_tool/build/generated/` 下还留着已删两个文件的 drift 产物（`.drift_elements.json`/`.drift_module.json`）：
       可弃构建产物，未清理（删 build_runner 的产物条目容易引出无意义的重建报错）。
    5. 升级安装的 4.9 万行**不会自己消失**（本包只管不再随包）⇒ T11 的「清空内置食物」仍是必须项（D14）。
    6. 本轮全量门禁 `2025 passed / 11 skipped`（T9 收口时 2033）：删了随导入器一起退役的那个测试文件、新增本包 4 条；
       **逐文件差额没有单独记账**，只知这一增一删，不去编一个刚好的数字。

### T14 · 电子秤接口预留（需求 78；D16）

- **文件**：新抽象 `ScaleReadingSource`（+ `ScaleDevice`/`ScaleReading` 值对象 + parser registry）+ 现有标准协议实现迁移到该接口 + `ScaleSyncController` 改依赖抽象。
- **验收**：
  1. 标准协议（`0x181D`/`0x2A9D`）行为**无回归**（既有七种结局测试全绿）；
  2. 编排层只依赖抽象（注入 fake source 可驱动全部结局）；
  3. **新增私有协议只需注册 parser**：用一个假 parser 注册进 registry 并断言被正确分派（证明扩展点有效）；
  4. 落地规则不变（`source: 'ble_scale'`、同日不覆盖手输、权限清单不动）。
- **测试与变异**：抽象层单测、fake parser 分派断言、既有行为回归；≥3 变异。
- **范围修订（2026-10-13，交付前登记）**：接口操作面按平台事实收窄（原生只有合成原语 `scanOnce`，
  拆两段要么撒谎要么改原生 ⇒ 不可门禁验证）——`ScaleReadingSource` = `check`/`requestPermission`/
  `openAppSettings`/`parsers`/`readOnce({window})`，厂商挂点 = `ScaleParserRegistry`（按广播名/服务 UUID 认领）；
  细则与理由见 §3 D16 的「范围修订」条。上面验收 1–4 **不变**。
- **证据**：`...-t14-scale-abstraction.md`。
- **交付记录（2026-10-13）**：落地口径以本段为准（与上文差异逐条登记）。
  - **交付物**（无原生改动：Kotlin / AndroidManifest / 权限清单零改动）：
    - 新增 `lib/features/progress/data/scale_reading_source.dart`：`ScaleDevice`（id / 广播名 / 服务 UUID + `advertises` 大小写归一）、
      `ScaleProtocolParser`（`id` / `matches` / `readOnce`）、`ScaleParserRegistry`（`register` 追加、重复 id 抛、
      `forDevice` 按注册序取第一个认领者、`readOnce` 分派）与 `ScaleReadingSource` 接口；
    - 新增 `lib/features/progress/data/standard_scale_reading_source.dart`：标准协议 = **第一个实现**
      （`StandardWeightMeasurementParser` 认领 0x181D；SFLOAT 解析仍在原生侧、不重复实现协议），
      能力面直通通道、读取过 `parsers` 分派（换掉认领者输出就换人）；
    - `ScaleSyncController` 依赖 `channel: ScaleChannel` → `source: ScaleReadingSource`（编排逻辑未改）；
      `main.dart` 接线、`settings_page.dart` 的「去系统设置」改走 `sync.source`；
    - 两条老测试（`scale_sync_controller_test`、`settings_scale_row_test`）**只换构造参数、断言零改动**（= 不回归证据）；
    - 新测试 `test/features/progress/scale_reading_source_test.dart` **15 条**。
  - **验收 1–4 全过**，逐条机器判据见证据文件 §2：① 老回归 8/8 + 10/10 绿；② fake source 驱动七种结局 + `availability()` 直通；
    ③ 假厂商 parser 注册后被按设备正确分派（标准设备归标准、未知名如实 `null`、`readOnce` 把设备与窗口原样带给认领者）；
    ④ `ble_scale` 落库 / 同日不覆盖 / 权限清单由 `privacy_statement_audit_test` 钉住且 manifest 未动。
  - **红先（如实）**：新测试先写先跑 = 60 条编译错误（API 不存在）+ EXIT=1（`red1.log`）；
    这是「API 缺席」层面的红，行为牙齿 = 5 条变异 + 两条老回归。
  - **变异 5 条**（M1 来源绕过 registry / M2 `forDevice` 不看 matches / M3 `advertises` 大小写敏感 /
    M4 放行重复 id / M5 编排删掉同日冲突分支）：每条唯一失败用例 + 还原后 sha256 逐字节一致 + 复跑绿；
    M5 在新老两个文件同时红。报告 `E:/AI/Zcode/tmp/localfit-t14/mutation-report-t14.txt`。
  - **门禁**：`575 files (0 changed)` / `No issues found!` / `+2040 ~11 passed` / **EXIT=0**（T13 的 2025 → +15 = 新测试 15 条）；
    前两次 EXIT=1 都是 info 级 lint（`prefer_initializing_formals` ×2 + `unnecessary_import` ×5，后者因为我给控制器加了
    两个 re-export，已撤掉改显式 import）。
  - **如实限制**（详见证据 §5）：① 生产路径上 registry 的输入是常量设备描述（原生按 0x181D 过滤、不回传设备名/地址）
    ⇒ 「按厂商认领」的能力边界由假设备/假 parser 证明；② 私有协议真要跑通还缺原生「发现 + 原始字节透传」那半（后期适配备件，本轮故意不做）；
    ③ `window` 对标准协议不生效（原生固定 10 秒），文档写明不假装可控；④ 真机走查属 T10。

### T15 · 引导页合并设计稿（需求 74；D18）

- **文件**：`onboarding_page.dart`（布局重组）+ 复用 T4 的自绘分段控件（性别）+ 底部固定行动区 + `ui设计/` 下新增合并稿。
- **验收**：§8 借鉴清单逐项落地；**现有主题与 emoji 图标不变**；`_GoalBigCard` 吞没变形动效保留；安全筛查三开关的 Key 不变（`onboarding-pregnancy-risk`/`chronic`/`eating`）；底部 CTA **固定不随滚动、高度 = h48**（§8.3 定案）；阶段条**仅视觉进度**（滚动位置映射 4 段，不拆分步、不与校验状态绑定，§8.3 定案）；活动档**仍 4 档**（标签描述式）；表单校验与保存流程无回归。
- **测试与变异**：阶段条渲染（4 段 + 当前段随滚动推进）、固定 CTA 位置与 h48、活动档 4 值、筛查 Key 保留、保存回归；≥3 变异。
- **门禁** + **HTML 合并稿先行**（360dp 评审图）。
- **证据**：`...-t15-onboarding-merge.md`。
- **交付记录（2026-10-13，已交付）**：落地口径以本段为准（与上文差异逐条登记）。
  - **交付物**：新增 `lf_segment_control.dart`（153 行，`LfSegmentControl<T>` + `LfSegment<T>`）、
    `lf_toggle_switch.dart`（81 行，`LfToggleSwitch` 46×28，**呈现件**不接手势）、
    `test/features/onboarding/round5_onboarding_merge_test.dart`（8 条）、
    `ui设计/round5/t15-onboarding-merge.html`（360dp 合并稿 4 帧，自评两轮）；`onboarding_page.dart`
    725 行（布局重组）；`docs/21` 新增 **§5.9 建档页**（落地形状 + 9 个 `onboarding-*` Key 表）。
  - **一条被测试逼出来的设计决定（登记为 D18 第 1 条的落地细则）**：阶段条**钉在正文之上**
    （`Column[Padding(_stepHeader), Expanded(ListView)]`），不参与滚动——合并稿 frame ③ 把指示器画在
    滚到底的视口顶部；若照原样放进 `ListView`，滚到底时它正好被懒加载回收。变异 m8 证明这条决定
    是承重的（放回列表 ⇒「阶段条随滚动推进」变红）。
  - **两条测试侧脚手架改动**（断言逐字未改）：4 个既有文件删掉「滚到底才点得到主行动」的
    `_scrollTo`（5+3 处）与失去引用的助手；`secondary_entry_reachability_test` 那条**收紧**为
    `hitTestable()`（从「滚过去找得到」升级为「首帧可点」）。
  - **验收（逐条机器判据见证据 §2）**：阶段条 4 段 24×4 + 累计填充 + 三段阈值（0.3/0.6/1/0 → STEP 2/3/4/1）
    + 不足一屏恒第 1 段；CTA 在滚动容器之外、h48、滚到底矩形不变、首帧可点；活动档仍 4 档描述式；
    筛查三 Key 保留 + 行式 46×28 + 行间 2 条 1px 分隔线 + 整行可点（点问题文本即切换）；
    性别自绘 48dp 分段控件双向可切；两张分组卡副文案；一行不滚完成建档回归。
  - **红先账**：① 只写测试 → 20 条编译错（两个共享控件未定义）；② 只补共享控件、页面未改 →
    **8/8 行为 RED**；③ 实现 → 8/8 绿。**变异 10 条全捕获**（m1–m10，含段数/宽度/映射/CTA 归位/
    标签/开关尺寸/整行可点/指示器钉位/轨道高/副文案），逐条按字节还原、sha256 一致。
  - **门禁**：第 1 轮 EXIT=1（`dart format 578 files (0 changed)` + analyze 报 1 条 `unused_element`：
    `round5_target_sheet_test.dart` 的 `_scrollTo` 失去全部调用点）⇒ 删该助手；第 2 轮
    **EXIT=0**（`No issues found!` / `+2048 ~11` / `All tests passed!`）；删掉临时视觉探针后
    **第 3 轮（交付态）复跑仍 EXIT=0 / +2048**。用例数对账：T14 收尾 +2040 ⇒ 本包**恰好 +8**。
  - **实现后的视觉自检**（临时 golden 探针，核对完即删）：顶帧与底帧逐项对合并稿——4 段胶囊第 1 段主色 /
    滚到底仍钉在视口顶部且 4 段全亮 / 性别分段控件 muted 轨道 + 选中白底主色字 / 安全筛查三行 46×28 开关 +
    2 条 1px 分隔线 / 主行动主色胶囊 h48 ✓。顺带实测：`ListView` 的 `maxScrollExtent` 是懒加载估算值，
    首次 `jumpTo` 会落在真底之上（连跳 2–3 次才是真底帧）；测试断言按归一比值判定，不受影响。
  - **未采纳（登记）**：设计稿的「跳过」（与必经流程语义冲突）、活动档第 5 档（不动枚举与目标计算）、
    CTA 52dp（§8.3 定案 h48）、40dp 单色图标底（保留 emoji）。滚动观感与真机走查归 T10。
  - **与证据文件的分工**：逐条判据、红先/变异/门禁账、视觉自检与 7 条诚实局限见
    `docs/evidence/2026-10-13-t15-onboarding-merge.md`。

### T16 · 通勤删除收口复核（需求 77；D10）

- **验收**：全库（含 `test/`）grep `通勤|commute|manualCommuteMinutes|ManualCommute|travelFit` **零命中**（白名单：迁移历史注释、`docs/evidence/**`、本方案自身）；注册表计数 22 且成员断言更新；快照无「手动通勤」段；`.lfb` 旧/新往返测试通过。
- **说明**：本包是 T8 的**只读复核 + 补漏**，若 T8 已彻底则本包仅落证据。
- **证据**：并入 `...-t8-settings-cleanup.md`。
- **交付记录（2026-10-13，只读复核 + 补漏）**：落地口径以本段为准（与上文差异逐条登记）。
  - **范围修订（两条判据按代码事实收窄，与 §3 D10 的 2026-10-12 修订对齐）**：
    1. **grep 清单去掉 `travelFit`**。原文把 `travelFit` 也列进零命中项，但 D10 明确写「solver 参数保留、
       恒中性 = `TravelFit` 参考值」，§6·3 也把「推荐引擎决策逻辑（**除通勤输入中性化**）」列为不动契约；
       代码事实是 `DailySolverWeights.distanceOrTravelFit`、`Candidate.travelFit`、`TravelFit.neutral`
       都还在（`daily_plan_engine.dart` 里以中性值传入并注释指向 D10）。⇒ 零命中判据按 D10 的口径 =
       `通勤|commute|manualCommuteMinutes`（`ManualCommute` 驼峰键只在 .lfb 旧包与迁移注释里出现，属白名单）。
    2. **注册表计数 22 → 23**。原文写 22，是拿 T6b 之前的基数算的；T6b 新增 `workout.plan.create` 后是 24，
       T8 删 `commute.set` 后**实测 23**（`chat_edit_registry.dart` 里 23 条 `action:`；断言在
       `chat_edit_registry_test.dart:20`、`round5_plan_create_test.dart:191`，S7 仪器矩阵同数）。
  - **复核结论（逐条）**：
    - **`lib/` + `test/` 零活引用 ✅**：`通勤`/`commute` 只出现在①迁移史（`app_database.dart` 的 v14 补列、
      v24 drop、`app_database_v14_migration_test.dart` 的列存在性断言）、②门禁自身（`round5_retired_feature_grep_test.dart`
      用 `String.fromCharCodes` 拼词 + `allowedTokens`）。门禁测试本身就是这条判据的可执行版本，绿灯。
    - **注册表 23 条 ✅**：计数与成员断言都在（两条）。
    - **快照无「手动通勤」段 ✅**：`DriftChatEditContextLoader.build()` 的段固定为
      当前目标 / 今日与昨日餐记录 / 菜品库 / 食堂目录 / 今日饮水 / 最近体重 / 训练计划 七段。
    - **`.lfb` 旧/新往返 ✅**：`export_restore_test.dart` 既有「1.x 的 19 张表旧包能恢复」，也有一条
      旧包里带 `manualCommuteMinutes: 25` 的恢复断言（恢复即丢弃，不报错）。
  - **补漏（T8 漏掉的文档面，本包补上）**：T8 只改了代码与测试，**文档里还有把通勤当现状的地方**，
    其中**隐私说明是硬伤**（本项目把「隐私说明 ↔ 实际行为不一致」当缺陷处理）：
    | 文件 | 原文问题 | 处理 |
    | --- | --- | --- |
    | `docs/08-store-privacy-and-permissions.md` | ①快照内容清单里仍写「通勤分钟数」②「2.0-5 只实现本地手动通勤时间」③位置行的「地点与通勤时间全部手动输入」 | 三处都改成事实（快照已无该字段；当前没有任何路线出网；已无任何地点/路线输入），带日期注 |
    | `docs/21-ui-redesign-spec.md`（**被测试读盘**） | 设置页结构树里仍画着「通勤时间行 + ManualCommuteDialog + 四个 Key」；另一处拿 `settings-commute-row` 当自门控约定的例子 | 结构树改成「已删」+ 日期注；例子换成仍在的 `settings-food-data` 行 |
    | `docs/23-chat-universal-edit.md` | 注册表表里还有 `commute.set` 行（且缺 T6b 新增的 `workout.plan.create`）；快照清单里有「手动通勤分钟」 | 删 `commute.set` 行、补 `workout.plan.create` 行、删快照条目，附一条日期注说明「23 条数字相同、名单不同」 |
    | `GOAL.md` | 2026-10-06 的记录写着「数据与手动通勤对话框保留」——现在是假的 | 原文保留 + 追加 2026-10-13 更正 |
    | `docs/07`（2.0 契约）§2.0-5、`docs/02-architecture.md`（数据清单 + §5.3 Route Adapter） | 把手动通勤时间写成现状/存储内容 | 各加日期注，说明整族已删、routing adapter 从未接线；§5.3 明确「将来要做按新需求重新裁决」 |
  - **不动的地方（如实记录）**：`docs/01-product.md`、`docs/04-roadmap.md`、`docs/28`、`docs/29`、`docs/30`、
    `docs/09`（2.0-6i-5 的**过去完成时**走查记录）、`docs/DECISIONS.md` 里的通勤条目、`docs/evidence/**` —— 
    都是历史叙述（阶段计划/已完成轮次的记录/逐字反馈），保留原样才诚实；`docs/09` 那处的语义是「当时走过
    通勤对话框」，改掉反而是篡改记录。
  - **门禁**：本包只改文档（其中 `docs/21` 被测试读盘）⇒ 按纪律**复跑全量门禁**：EXIT=0 /
    `No issues found!` / `+2025 ~11 passed`（日志 `E:/AI/Zcode/tmp/localfit-t13-mutations/gate3.log`）。
  - **测试与变异**：本包是只读复核，**没有新增断言**（D10 的三条判据早就由 T8 的门禁测试与注册表断言承担），
    因此不产生新变异；复核用到的证据是门禁绿灯 + 四条逐条核对（上面）。

---

## §5 三个提问的答复

### 5.1 「导出 CSV 是导出什么，跟下边两个有什么区别」（**D17 已定案**）

设置页「数据管理」组里与导出有关的是 **4 项**（3 个 CSV + 1 个加密备份）：

| 行（**最终文案，不带 CSV 后缀**） | 导出内容 | 列数/文件名 | 用途 |
| --- | --- | --- | --- |
| **导出饮食记录** | 饮食记录明细：每条餐记录 × 每个食材条目 | 12 列（meal_id/local_date/slot/eaten_at/source/item_id/food_name/grams/kcal/protein/carbs/fat），`localfit-meals-<时间戳>.csv` | 拿去做表格分析 |
| **导出训练记录** | 训练会话 × 组 | 9 列（session_id/session_date/session_status/set_sort_order/exercise_name/weight_kg/reps/rpe/completed_at），`localfit-training-<时间戳>.csv` | 训练量分析 |
| **导出食物数据** | 食物库全量（内置+自建；移除随包种子后仅自建） | 8 列（name/brand/category/kcal_per_100g/protein_per_100g/carbs_per_100g/fat_per_100g/origin），`localfit-foods-<时间戳>.csv` | **可回灌**：与「添加食物数据 → 从 CSV 文件导入」同一表头 |
| 备份数据 | 全部本地数据（39 张表）加密包 | `.lfb`（口令加密） | 换机/重装恢复用 |

区别一句话：**三行是「三张不同表」的明文导出（饮食记录 / 训练记录 / 食物数据），彼此不重叠；食物数据可回灌，另两个是单向导出；`.lfb` 才是全量加密备份。** 实现见 `export_csv_files.dart` / `csv_exporters.dart`（§2·71）。
**本轮动作**：三行去掉 "CSV" 字样（D17/T12），语义在行内或点按提示里写清。

### 5.2 「水分摄入目标是怎么得出的」

**不是计算出来的，是硬编码的**：`DailyTargets.waterTargetMl` 的列默认值就是 `2000`（ml），建档时甚至没有显式写这一列（`tables.dart:81`、`onboarding_persistence.dart:67-83`），全库也没有任何编辑入口。所以按你的条件（「如果是自定义的，那就在资料卡里再提供一个编辑水分目标」）→ **要加编辑**：落在「编辑资料」页（D11/T9），输入以 L 计（0.5–6.0），写库用版本化新行/今日行就地更新，历史日期口径不变。

### 5.3 「电子体重秤支持什么体重秤，小米体重秤为什么不能支持，要怎么才能支持」

- **现在支持什么**：广播**标准蓝牙体重秤服务 `0x181D`**、并实现**标准 Weight Measurement 特征 `0x2A9D` 通知**的秤（市面上一批标准协议秤）。流程 = 前台 10 秒扫描 → 订阅通知 → 读一次断开；只收公制；Android 12+ 免定位权限（`neverForLocation`），API≤30 诚实显示「设备不支持」。
- **小米为什么不行**：米家体重秤/体脂秤系列**不实现标准测量特征的通知流程**——体重放在**小米私有广播**里（服务数据/厂商数据，按型号与固件差异大），部分型号还需私有握手；标准订阅路径收不到稳定读数。这不是权限或兼容开关问题，而是协议不同。
- **本轮结论（用户已定）**：**先预留接口、后期适配**（D16/T14）——把「扫描+订阅+解析」抽象成 `ScaleReadingSource` 并留出**型号/厂商 parser 注册挂点**，本轮**不**实现小米解析（无真表无法诚实验收：私有广播的字节布局必须逐型号对验）。将来适配备件：具体型号 + 真表在场。若只想「能用就行」，买一支标准 `0x181D` 协议的秤成本最低。

---

## §6 「不引入新 bug」的防线

**明确不动的契约（改到即视为回归）**

1. chat-edit 信封格式与「应用/忽略」语义、注册表里除 `commute.set`（删）/`workout.plan.create`（增）之外的其余命令参数契约。
2. `.lfb` 加密备份格式与 39 张表清单（除 `profiles` 的列增减）。
3. 推荐引擎决策逻辑（除通勤输入中性化）、扫码流程、权限清单（manifest 不动）。
4. drift 表结构除本轮 ±列（profiles +2/−1；若新食物结构要求，foods 列变更与之合并为**同一次**迁移）之外零改动。
5. onboarding 建档数据流（除抽屉视觉与 D18 的布局重组）。
6. AI 对话流式/落库/重试语义。
7. **食物库的三处 CSV/列名契约**（主库 CSV `*_per_100g`、分片 `*per100g`、种子 JSON 裸键）—— 除 T11 按新结构统一外，不得单方面改动其中一处。

**高风险区的专项防线**

| 风险区 | 防线 |
| --- | --- |
| schema 23 迁移 | v22→v23 升级测试（老库数据完整 + 新列 null + 旧列不存在）+ onCreate 新装测试 + `.lfb` 旧/新往返测试 |
| **移除随包种子（T13）** | 启动不导入断言（全新库 foods 为空）+ 资产清单断言（`assets/seed/` 仅 exercises）+ 动作库导入回归 + 数据文件**归档而非删除** |
| **清空内置食物（T11）** | 保自建断言 + 引用置空但记录完整断言 + 幂等重跑断言 + **不碰 AppSettings/AI Key/图片** 断言（与 `ClearAllLocalData` 显式区分） |
| **CSV 重建（T11）** | 大文件上限断言 + 流式索引 + 批量落库 + 端到端计数/去重/预览三方对账 |
| 通勤删除 | 全库 grep 零命中断言 + 迁移 drop 断言 + 注册表 23→22 计数断言 + S7 仪器同步 + T16 只读复核 |
| 命令新增/删除 | 注册表成员与计数断言、执行器拒绝路径断言（未知动作/歧义/越界）、快照段渲染断言 |
| 旧管线退役 | 删除后逐文件 grep 零残留；安全断言在命令层重建并各自配变异 |
| 下拉迁移 | 逐站点「打开→选择→回写」回归（11 站点全覆盖） |
| 弹层改造 | 拖动稳定性计数断言 + 方案 B 三条（缩到底不关窗/snap 停靠/snapSizes 重算）+ 3 处迁移冒烟 + 2 处确认路径 |
| 电子秤抽象（T14） | 标准协议行为无回归 + 编排只依赖抽象 + 假 parser 分派证明扩展点 + 落地规则不变 |
| 引导页合并（T15） | 三筛查 Key 不变 + 活动档仍 4 值 + emoji 图标与吞没动效保留 + 保存流程回归 |
| 头像文件 | 无图回退、替换删旧文件、路径越界防护（只写应用文档目录） |
| 性能敏感门禁 | 安静机器跑门禁（先关模拟器等负载）；不修改测试预算口径（如需改，另立裁决） |

---

## §7 全局验收清单（交付前逐条勾）

- [x] 59 目标抽屉图形化（四值完整、范围条归一正确、保存流程不回归）— 真机 `04`；四值 1,631–1,803 / 109–136 / 119–235 / 48–68，轴 0–2,164
- [x] 60 月视图 = 本月逐日格 + 细柱 + ＋与切换等高 — 真机 `07`
- [x] 61 轴 4 刻度 + 柱点击浮窗（显/隐/钳制）— 真机 `07`/`08`（显、隐各一次；钳制在 T1 测试）
- [x] 62 创作页重设计 + 六卡 → 描述 → 生成 → 对话自动发送 → 结果在对话；`workout.plan.create` 可用；旧管线退役且安全断言重建 — 真机 `25`/`26`/`26b`/`23` 覆盖画廊与描述框；「生成→自动发送」需用户 AI Key，本轮以 T6b 仪器同步 + `test/live/` 用例为据（证据 §6·2）
- [x] 63 今日饮食空态铺满卡片 — 真机 `06`
- [x] 64 步数目标可设（资料卡）+ 步数卡联动 — 真机 `13`（可编辑）；写读往返/联动在 T9 测试
- [x] 65 今日推荐按钮同高 — 真机 `17`；h40 几何断言在 T3 测试
- [x] 66 全部下拉统一（11 站点）— 真机 `21`（种类）/`33`（动作）；11 站点回归在 T4 测试
- [x] 67 抽屉抖动修复 + 同类全面排查与修复 — 真机 `38b`/`39b`（内容区与把手小幅下拖都不关窗）；抖动为流畅度主张，计数断言在 T5/T15 测试
- [x] 68 动作库卡底距 = 12dp — 真机 `28`
- [x] 69 头像/昵称可编辑 + 副标题删除 + 居中对齐 + 他页头像跳我的 — 真机 `09`/`10`/`11`（改名 FitPro 往返成功）；他页头像跳转在 T7 测试
- [x] 70 两个冗余行删除（恢复入口条件保留）+ 通勤全链路下线（grep 零命中） — 真机 `14`；grep 门禁在 T8/T16 测试
- [x] 71 三行导出文案 = 导出饮食记录 / 导出训练记录 / 导出食物数据（无 CSV 字样），导出行为不变 — 真机 `14`
- [x] 72 饮水目标可编辑（资料卡）— 真机 `13`（水分目标 2）+ 我的页 gauge 联动
- [x] 73 秤支持范围已答复 + 接口已预留（T14） — 真机 `16`（含小米如实提示）；真秤读数链路待硬件（证据 §6·3）
- [x] 74 引导页合并（§8 清单逐项）+ 主题与 emoji 图标不变 + 底部固定 CTA（h48）+ 阶段条为**视觉进度**（§8.3 定案） — 真机 `01`–`04`
- [x] 75 食物库：随包种子移除 + 内置行清空 + 设置页清空入口 + 按新结构 CSV 重建（新表头到位后定稿） — 真机 `14`（0 条（自建 0 条））+ `22`（手工 1 条）+ T11 补做帧 `01b`（全新安装组内三行、无清空行）；清空入口的正向分支**已在真机取证**（升级安装走查：旧构建灌 49,444 行 → 原地升级 → 弹层 49,444 → 取消不变 → 导出 4.29 MB CSV → 清空 49,444 条 + 计数 0 条 + 行自隐 → 回灌 49,444 条，22 帧 `docs/evidence/2026-10-13-t11-clear-device-upgrade/`）；**「按新结构重建」已于 2026-10-13 落地并真机走通**：21 列中文表头（导出逐字）+ schema 24→25（+15 列）+ 24 类映射表；真机全新安装 → 导入 19,974 行（预览 19974/0/0）→ 计数 19,974 条（自建 19,974 条）→ 导出 21 列 19,974 行、二遍全判重复，三方对账 **16/16**（13 帧 `docs/evidence/2026-10-13-t11-new-structure-device/`）；清空正向分支以升级走查 22 帧为据。见 §4 T11 交付记录之三…**之八**、证据 §9–§14
- [x] 76 三行文案不含 "CSV" — 真机 `14`（T12 验证-only，走查复核）
- [x] 77 通勤全链路删除（含 test/，grep 零命中） — 真机 `14` 无通勤行 + T8/T16 门禁
- [x] 78 电子秤抽象接口 + parser 挂点（假 parser 分派证明） — T14 测试为据；真机只有文案层可点（证据 §6·3）
- [x] 79 训练弹层方案 B（保留拖动放大 + 缩到底不关窗 + snap 停靠） — 真机 `37`–`39b`（真建 PlanA 后开训练会话）
- [x] 每包：红先测试 + 隔离变异 + 门禁 EXIT=0 + 证据文件 + STATUS/INDEX 同步 — T1–T16 逐包登记见 §4 各包「交付记录」与 `docs/evidence/2026-10-1*-t*.md`
- [x] T10：真机走查（59–79 逐条证据帧）+ 最终门禁 + 遗留清单 — `docs/evidence/2026-10-13-t10-walkthrough.md` + `docs/evidence/2026-10-13-t10-walkthrough/`（42 帧）；走查另抓出两个问题（一个当轮修复、一个进遗留清单）

---

## §8 设计稿借鉴清单（`ui设计/pages/初始引导.html` → 引导页）

> **总原则（用户原话）：「合并目前主题样式和设计稿的优势之处，图标什么的按现有的来，更新一下布局。」**
> 该稿的 `--lf-*` CSS 变量与仓库现有主题**同源同值**（`#2FBE8F` 主色、mint-100 `#D2F5E6`、muted `#EFF3F1`、radius 16、`shadow-1`），
> ⇒ **合并范围 = 布局与交互，不含重新定主题、不含换图标体系**。

### 8.1 采纳（借入布局/交互）

| # | 设计稿元素 | 稿内实现 | 落地方式 | 归属 |
| --- | --- | --- | --- | --- |
| 1 | **阶段条** | `.step-bar` + `.step-pill`（24×4px、圆角 2、未选 `--lf-border`、当前 `--lf-primary`） | 新增 4 段进度指示；**仅视觉指示**（§8.3 定案 ✅：单页滚动位置映射，不拆分步） | T15 |
| 2 | **微标签** | `STEP 3 / 4 · 建立档案`（11px、uppercase、tracking-wider、主色） | 大标题上方加一行；文案中的步号由阶段条状态驱动 | T15 |
| 3 | **分组卡说明副文案** | 「用于计算基础代谢率与营养分配」等 12px muted 说明 | 三张 `DesignCard` 的标题下各加一行说明 | T15 |
| 4 | **描述式活动档** | 5 档带解释文案 | **档位数仍 4（现有枚举）**，标签改描述式：「久坐 — 几乎不运动」「轻度 — 每周 1-2 次低强度」「中度 — 每周 3-4 次中等强度」「高强度 — 每周 5-6 次较高强度」 | T15 |
| 5 | **自绘性别分段控件** | `.segment-control` 48dp + 3px 内衬 + `.segment-btn.active` 白底/主色字/阴影 | 复用/新建与 T4 同族的自绘分段控件替换 M3 `SegmentedButton` | T15（与 T4 共用件） |
| 6 | **行式安全筛查** | 左文本 + 右 iOS 开关 46×28 + 1px 分隔线（`padding 18px 8px` 目标卡） | 三开关改为行式布局；**Size 与分隔线**照稿；语义与 Key 不变 | T15 |
| 7 | **底部固定 CTA** | `.cta-btn` 52dp、全圆、主色、`0 8px 24px rgba(47,190,143,.25)` 阴影 | 现有 `LfConfirmButton`（**h48**，见 §8.3 定案）移入底部固定行动区（不随滚动）；**只借位置，不借 52dp**（与全 App 一致） | T15 |
| 8 | **输入框形态** | `.form-input` 48dp、muted 底、1.5px 透明边、focus 主色描边 + 3px 光晕 | 核对现有 `_numberField` 是否已同形态；不足处补齐 focus 态 | T15 |

### 8.2 不采纳（保留现有优势）

| 设计稿元素 | 现有实现 | 理由 |
| --- | --- | --- |
| 40dp 单色圆形图标底的 `goal-card` | **emoji 图标**（🔥/💪/🌿）+ 吞没变形动效（`AnimatedScale` 0.97↔1.0 easeOutBack 380ms + 描边/底色，`onboarding_page.dart:373-421`） | 用户明确「图标什么的按现有的来」；现有动效**优于**稿的静态 `scale(.97)` |
| **「跳过」按钮** | 无（建档是必经流程） | 语义冲突：跳过会导致无档案无法计算目标；不引入半成品状态 |
| Tailwind 任意值 class（`text-[13px]` 等） | `LfText` / `LfDimens` token 体系 | 稿是 HTML 原型载体，落地一律走 App token |
| 稿的 `--lf-*` 变量定义 | `LfColors` / `context.lf.*`（**同值**） | 同一套系统，重复定义反而会漂移 |
| 5 档活动程度 | `ActivityLevel` 4 值枚举 | 改档数要动领域模型 + 计算器 + 测试，**收益不抵风险**；只改标签 |

### 8.3 已定案（2026-10-11，用户选择「按你推荐来」）

1. **阶段条 = 视觉进度指示（不真分步）。** ✅ 定案：单页长表单不变，阶段条仅作**滚动位置的进度映射**；不拆表单状态、不改校验、不引入分页路由。理由：改造量小、不动数据流；真分步（4 页）价值不抵风险（需拆表单状态与逐步校验，另立工作包才做）。
   - 落地细则：4 段进度由**滚动位置或区块可见性**驱动（区块 = 基本信息 / 目标 / 安全筛查 / 计算确认；`Scrollable` 的 position 映射到 0–3 段）；微标签文案随之更新为「STEP n / 4 · 建立档案」。
   - **如实记**：这是**近似进度**而非真流程步骤（单页里四个区块在同一屏滚动流上），不与「已填完」语义绑定；不显示「完成度百分比」以免暗示校验状态。
2. **底部 CTA 高度 = 现有 token（48dp），非设计稿 52dp。** ✅ 定案：复用 `LfConfirmButton`（h48 / full 圆角 / 主色阴影），**只改位置**（移入底部固定行动区、不随滚动）。理由：与全 App 主行动形态一致（§0 纪律：设计稿的优势在布局，token 取现有者），避免 52dp 成为孤例。
   - 设计稿的 52dp 仅记录在 §8.1 第 7 行作参考，**不落地**。

---

## §9 2026-10-13 整体回归修复交付补记

用户在整体排查确认 11 类问题后要求「修复」。本节是同范围修复记录，不改 §3/§8 已定裁决，也不重开 T11 表头决策。以下 B01–B11 为本次回归编号，与前文 B1–B21 区分。

**已落地**：B01 训练计划日传递/今天开练/空选择器；B02 手动计划返回刷新；B03 周日索引与容量桶；B04 完整动作候选；B05 餐食变更及撤销后的趋势、均值；B06 同周已记录日期显示；B07 跨分支食物库和同词缓存更新；B08 相机取消/失败导航；B09 恢复/全清后的 Settings 快照；B10 真实路由身份接线；B11 真实头像选择接线及私有头像全清。

训练日期采用既有 schema 可表达的口径：新会话只从今天对应行开始，其他日仍可查看编辑；已开始会话可跨天继续，动作取保存的 localDate 对应计划日。无动作或坏日期的旧会话禁止选动作和保存，但保留取消、结束；不伪造 session 日期或组数。另修昵称 sheet 的 controller 生命周期、360dp/2×字号横幅溢出、空库零进度成就回写，以及数据替换与旧异步读取交错。

**机器验证**：9 个新测试文件、91 项回归；113 个不同的有效行为变异逐条 RED → bytes 还原/SHA256 一致 → GREEN。不是每个 expect 都有独立变异，也不是全部用例严格 RED-first；编译失败及一条先触发框架约束的 stale-snapshot 变异排除，后者经纠正重跑获得目标断言 RED。全量原样门禁 `verify-final-2`：591 files / 0 changed、analyze clean、2174 passed / 11 skipped、exit 0。两份旧身份 fixture 只补卸树与 1ms 时钟清理，没有放宽业务断言。

**完整性**：623 个冻结源码/测试/配置文件对账一致；两份保护清单去重后 92 个实现文件与修复前基线一致，§6 原文不变。schema 仍为 25；不改备份格式/39 表、CSV 21 列、AI 流式与 chat-edit、onboarding 数据流、推荐、识别核心或权限。

**APK 与设备边界**：通用 release（37,756,059 B）及 x86_64 release（13,669,319 B）均构建 exit 0；通用包在新建 `LocalFit_Bugfix_API35`（Android 15 / API 35 / 360dp）安装 Success，包元数据为 0.1.0 / versionCode 3。Computer Use 截图只返回编码文本、无障碍树仅见模拟器外壳，因此**本次未完成应用启动和修复流程 GUI 验收**，未盲点点击或改用 adb UI 自动化。历史 §7 勾选与 T10/T11 帧是当时证据，不冒充本次修复版验证。只定点关闭本次 AVD，未清用户数据或覆盖原 AVD。

**如实限制**：保留既有全量日志中的测试监听器 `Future already completed` 非失败诊断及构建字体 warning；未测真实 AI/硬件与 Android 生命周期跨午夜，仓储内部 await 跨午夜窗口仅为未覆盖项，不记为已确认缺陷。受当前工具规则约束，本次不采用 §0 的历史 uiautomator 操作方式；不放宽性能预算，也不为清空机器负载而停止用户应用。

详细证据与 SHA256 见 `docs/evidence/2026-10-13-regression-repairs.md`，原始日志、变异、快照和 APK 在 `E:/AI/Zcode/tmp/localfit-bugfix-20261013/`。未发布、未推送、未提交。
