# LocalFit AI 2.0 界面与体验治理方案（`docs/29`）

日期：2026-10-05
依据：用户 2026-10-05 一次性反馈（**39 条**，见 §1）+ 同日实测（真实 BYOK 端点、代码可达性扫描）
状态：**P0–P12 全部交付（2026-10-07）**。P0（文档治理）、P1（个人资料页三件）、P2（健康数据图形化）、P3（成就分级与进度）
已于 2026-10-05 交付并 verified，P4（AI 配置统一 + 连通性测试 + 模型拉取/选择 + 推理开关）于 2026-10-05
交付、P5（动作库卡片 / 详情抽屉 / 弹窗流畅度）与 P6（记录页间距 / FAB / 下一餐卡图形化）、
P7（食堂目录：滚动保持 / chip 选中态 / 菜品行 / 菜品图片）于 2026-10-06 交付，
**P8a（食物库卡片与抽屉呈现一致化，需求 20–22、24、26–30）于 2026-10-06 交付**，
**P8b-1（审核台与账本：工具先就绪、进度可续、账本可真、覆盖率可见；未做人工裁决）于
2026-10-06 交付**；**P8b-2（v5 生成与 App 升级）于 2026-10-07 交付——账本达 100% 覆盖
（49,464 / 49,464），`foods.v5.json`（49,444 条）与人工品牌词表已产出，App 已从 v4
**原地升级**到 v5**（证据 `docs/evidence/2026-10-07-p8b2-v5-upgrade.md`）；**P9（今日页：体重周/月视图 + 选日期 +
本机步数，需求 31–34）于 2026-10-07 交付**（含设备走查：步数未授权→允许→无传感器
诚实空态两态、周↔月切换回读、选日期跨日重播种与「已保存到 9 月 30 日」回显）；
**P10（删免责声明 / 删语音转写 / 拍照直通，需求 35–37）于 2026-10-07 交付**
（含设备走查：输入栏无麦克风无免责声明、拍照 chip 直开系统相机、Done 后带回图
自动识别、无 AI 配置时诚实报错）；**P11（真实端点全功能实测与修复）于 2026-10-07
交付**（live 工具默认 skip 零外呼、六出口判定、两个「接口形态不匹配」真缺陷修复、
凭据 0 落盘，证据 `docs/evidence/2026-10-05-ai-live-endpoint.md`）；
**P12（全局收尾）于 2026-10-07 交付**（全量门禁 EXIT=0 1944/11、`--rerun-tasks`
重编译 0 警告、变异抽查 3/3 并修正一处测试假钉、设备走查 360dp 逐页 + 2.0× +
暗色 28 张截图归档 `docs/evidence/2026-10-05-ui-ux-remediation/`、arm64 混淆交付包
重建与产物核验（正向 36/36、负向 12/12、差分证明非上一版）、文档全面同步
（docs/21 §5.1/§6.1/§6.2、docs/24 §6/§7、INDEX、DECISIONS ADR-027）、
证据 `docs/evidence/2026-10-07-p12-global-wrapup.md`）；每包的实况与门禁以
`STATUS.md` 的 `Active Slice` 为准（本节不复制数字，避免漂移）。
§2 的 14 条裁决（D1–D14）均已给出默认选择与理由；用户若不同意，改一行即可，不需要重写方案。
工作包顺序：**P0 → P1 → P2 → P3 → P4 → P5 → P6 → P7 → P8 → P9 → P10 → P11 → P12**（每包独立过门禁）

---

## 0. 防误导：本方案与旧文档的关系（**开工前必读**）

用户明确要求「再三确认新的开发文档不会被旧的文档所误导，最好把旧文档整理存放」。
本节是这份要求的**正面回答**，也是 P0 的执行依据。

### 0.1 权威源（只有这四份 + 代码/测试）

| 类别 | 权威文件 | 说明 |
|---|---|---|
| 本方案的执行细则 | **本文 `docs/29`** | 39 条需求的唯一落点与顺序 |
| 长期目标与硬约束 | `GOAL.md` | 产品目标、隐私/AI 硬约束 |
| 产品/数据/AI/验收契约 | `docs/07-localfit-2.0-development-spec.md` | 契约层，不描述具体 UI 形态 |
| **UI 的唯一依据** | **`docs/21-ui-redesign-spec.md`** + `ui设计/pages/*.html` | 视觉 token、组件族、页面结构树 |
| AI 协议与 chat-edit | `docs/24-ai-provider-protocols.md`、`docs/23-chat-universal-edit.md` | 三协议 wire 事实、23 条命令注册表 |
| 实时状态 / 交接 | `STATUS.md`（根目录） | 只有这里能说「做到哪一步了」 |
| 决策日志 | `docs/DECISIONS.md` | 追加式，本方案的新决策按 ADR 编号追加 |

**规则**：`docs/26`、`docs/27`、`docs/28`、`docs/22`、`docs/11`、`docs/25` 是**已完成的方案书**，
不再具备规范效力；它们与本文冲突时**以本文 + 实测为准**。

### 0.2 「被旧文档骗」的三种真实形态（本仓都已发生过）

1. **状态行过期（最危险）**：实测 `docs/26`/`docs/27` 头部写着「状态：执行中」、
   `docs/28` 写着「待开工。**未实施**」、`docs/22` 写着「状态：待执行」——
   而这四份的实际状态是**已完成**（`docs/28` 的 `§9.6 实施记录` 与
   `docs/evidence/2026-10-04-input-menu-foodlib-redesign.md` 就是完成证据）。
   一个新会话读到「执行中/待开工」会去重做已完成的工作，或把已撤销的形态当成必须保留。
2. **需求文本未打补丁**：`GOAL.md` §2 第 84 行仍写着 AI 对话页包含
   「**语音（录音 + BYOK 端点转写）**」，而本轮 P10 要把它**整族删除**——
   旧文本会把待删功能描述成必须交付项。
3. **注释即规范**：`lf_insets.navReserve` 曾用一句注释误导实现（见 `docs/21` §6.2 实测记录）。
   本方案凡改动旧代码，**同时把那处的过时注释改掉**，不留「照它做就错」的注释。

### 0.3 整理动作（P0，本次随方案一起落地）

- 新增 **`docs/INDEX.md`**：全仓文档的唯一地图（权威性 / 状态 / 替代者 / 是否被测试引用）。
- 给已完成的 5 份方案书加**统一状态横幅**（`docs/11`、`docs/22`、`docs/25`、`docs/26`、`docs/27`、`docs/28`），
  首行固定格式：`> 状态：已完成（<日期>）· 规范效力：无 · 后续以 docs/29 为准 · 地图见 docs/INDEX.md`。
- 新增 **`docs/history/2.x/README.md`**：2.x 阶段已归档方案清单。
- **不物理搬移**这些文件的正文，理由见 0.4——这是本方案与「把所有旧文档扔进一个文件夹」的**有意偏离**。
- 修 `GOAL.md` 的三处过期指引：第 6 行「改造方案见 docs/22」→ 见 `docs/29`；
  第 84 行语音条目按 P10 标注「2026-10-05 裁定删除，见 `docs/29` §P10」；新增「§0 当前目标」引导段
  （**唯一副本在 `GOAL.md` §0**，§7 只指向它）。
- 在 **`docs/21 §3.11`** 顶部加 **2026-10-05 状态块**：该节「`0` 也当没有 / 缺项不占位 /
  不画 0%」三条数据口径已被 D14（用户要求「三项固定、没有的也写 `0g`」）取代——
  **不让活文档里的旧口径继续被当成当前前提**。该 doc 被 `ui_spec_key_sync_test.dart` 读盘，
  但那个测试只从含「测试 Key」的行抽 kebab key 且**跳过 `>` 引用块** ⇒ 状态块惰性；
  改后**单独跑该测试已实测通过**（`EXIT 0`）。

### 0.4 为什么不物理搬移（这是决定，不是偷懒）

实测引用数（`lib/` + `test/` + `tool/` 内的 `docs/NN` 指针）：

| 文档 | 代码/测试引用数 | 能否搬 |
|---|---|---|
| `docs/28` | **210** | ❌ 搬走会留下 210 个死指针 |
| `docs/11` | 59 | ❌ |
| `docs/22` | 51 | ❌ |
| `docs/27` | 25 | ❌ |
| `docs/25` | 6 | ⚠️ 可搬但收益 < 罚款 |
| `docs/26` | 0 | ✅ 唯一可搬 |

`docs/26` 是唯一零引用的，但它与 `docs/27`/`docs/28` 是同一份「界面专项」脉络，
单独搬一份会让脉络断开。**结论**：一半真源在一半在归档目录，比不归档更容易误导。
因此本项目对 2.x 完成方案采用「**原位 + 状态横幅 + 唯一地图**」，
而对 1.x 时代（已无代码引用）的文档继续用已有的 `docs/history/1.x/` 物理归档。
被测试直接读盘的文件只有 5 个（`THIRD_PARTY_LICENSES.md`、`docs/09`、`docs/21`、两份 evidence），
**归档动作不得触碰它们**。

---

## 1. 需求 → 工作包对照（39 条，逐条可验收）

| # | 用户原话要点 | 落点（实测） | 包 |
|---|---|---|---|
| 1 | 个人资料页只能编辑体重，无法调身高 | `profile_edit_page.dart:116-161` 只有 goal + 目标体重；身高只在 onboarding 可写 | P1 |
| 2 | 出现报错 `GoError: There is nothing to pop` | `app_router.dart:378` 用 `go`、`app_router.dart:177` `onClose=pop`、`profile_edit_page.dart:90` 调它 → `go_router` delegate 抛错，被 `:95-98` 捕成「更新失败」 | P1 |
| 3 | 该界面没有关闭按钮 | `profile_edit_page.dart:115` AppBar 无 leading/action | P1 |
| 4 | 健康数据三行太丑，要像截图的图形化；先做 HTML 再原生 | `settings_page.dart:1578` `_HealthMetricsCard` + `lf_stat_tile.dart` | P2 |
| 5 | 成就四个小卡片太丑；分等级、进度条/标识、文字不换行 | `settings_page.dart:1675` `_AchievementsCard`；`Achievements` 表已有 `progress`/`unlockedAt` | P3 |
| 6 | AI 配置的 Key 为什么单独在外边 | `settings_page.dart:268-299`（模型行进 sheet、Key 留在组内） | P4 |
| 7 | 加连通性测试 + 模型拉取 + 选择 | **全仓无 `/models` 调用、无连通性测试** | P4 |
| 8 | 同肌群替代动作一堆文字，要美化加图标 | `exercise_library_page.dart:48-90`（裸 `ListTile`，无 leading/onTap） | P5 |
| 9 | 分类「腿·自重」放卡片右上角 | `exercise_library_page.dart:432-439` | P5 |
| 10 | 图标↔标题、标签↔标题间距过大 ⇒ 卡片可减高 | `:421` 垂直 `Spacer`（≈35.6dp）＋`:431`+`:440`；`mainAxisExtent: 168` | P5 |
| 11 | 抽屉弹出卡片不丝滑（新建动作弹窗） | `app_sheet.dart:174-178` 动画 250/150ms；真凶是 grid `FutureBuilder` future 建在 `build` 里（`:298-299`）⇒ 键盘弹出引发重建即重查 DB + 骨架屏闪烁 | P5 |
| 12 | 下一餐推荐卡与饮食记录卡之间没间隔 | hero 与 `NextMealEntryCard` 之间的**外部间距 = 0**（`record_tab.dart:297-306`） | P6 |
| 13 | 记录一餐加号要更浮空、与下边分层 | `record_fab.dart:12-54`（48dp、`elevation:0`、阴影 blur12/α.30、底距 80） | P6 |
| 14 | 今日推荐卡不要通勤时间 | `next_meal_decision_card.dart:193-199` | P6 |
| 15 | 今日推荐卡下面一堆文字换图形化 | `:338`（目标影响）、`:340`（证据串） | P6 |
| 16 | 添加菜品要能加菜品图片 | `menu_form_prompts.dart:108-174` 只有名称+价格；`MenuItems` **无图片列** | P7 |
| 17 | 餐品一行行、没间隔没序号，很丑 | `canteen_window_card.dart:97-104` + `CanteenDishRow:162-240`（仅 6dp 垂直内边距） | P7 |
| 18 | 切换食堂地点时页面滚动被复原，要保持不变 | `menu_tab_view.dart:159-161` 带 venue key 的 `FutureBuilder` ⇒ 切换时新 future + `SliverFillRemaining` 加载片把 offset 夹回 0 | P7 |
| 19 | 食堂地点选择按钮与选中态丑 | `canteen_venue_selector.dart:68-87` + `app_morph_chip.dart:33-142` | P7 |
| 20 | 食物卡标题与图标中心不同高 | `food_card.dart:99-136`（R1 是 `CrossAxisAlignment.start`） | P8 |
| 21 | 宏量指标位置要固定，没有的写 0g | `food_card.dart:216-239`：缺项被省略、剩余 `Expanded` 重新分配宽度；**与 `docs/21 §3.11` 的「0 当没有 / 缺项不占位」正面冲突 ⇒ 按 D14 同批改写活文档** | P8 |
| 22 | 右上角热量没有单位 | `lf_food_kcal_ring.dart:86` 只印 `'${kcal.round()}'` | P8 |
| 23 | 圆环的「全部」代表什么热量值 | `lf_food_kcal_ring.dart:47-49,113`：满刻度 = **900 kcal/100g 能量密度**，上屏无任何说明 | P8 |
| 24 | 自建/内置标识放卡片右下角 | `food_card.dart:160-163`（现在跟在品牌后面，行内靠左） | P8 |
| 25 | 标题很多有问题（7 11 / 7 eleven 等），逐条筛选核对品牌与名称并校对 | 种子 49,464 条；`7-ELEVEN 7-11御饭团` 类重复品牌 token；`normalizeFoodName` 把 `-` 换成空格（`text_utils.dart:32-34`）；**纯汉字品牌是既有算法主动放弃的缺口**（`build_brand_gazetteer.py` 记 known gap）⇒ 只有人工能关 | **P8b（用户 2026-10-05 裁定：全量人工审核，D6）** |
| 26 | 品牌做带边框小标签放左下角，与自建/内置同尺寸高度、上下对齐、颜色不同 | `food_card.dart:148-155` 品牌是裸 `Text`；`LfBadge` 已有 mint/neutral | P8 |
| 27 | 卡片底部边距不要太多 | `food_card.dart:94`（`all(12)`）+ 末行前的 8dp | P8 |
| 28 | 详情抽屉与卡片一致；圆环小一点（三个营养同行）；单位注意；只要克数不要百分比；0g 也要写 | `food_detail_sheet.dart:224-263`（88dp 环）、`:246-253`+`:315-331`（百分比行） | P8 |
| 29 | 添加按钮放搜索框右边 | `nutrition_legacy_tab_shell.dart:72-84`（在顶栏右侧） | P8 |
| 30 | 删掉上边标题和左边返回按钮 | `lf_top_bar.dart:87-109`（**共享件，必须按页开关，不能全局删**） | P8 |
| 31 | 本周体重卡要能切周/月视图 | `dashboard_weight_card.dart:28,58`（硬编码 7 点 + 「周」徽标） | P9 |
| 32 | 加「添加」按钮；不要点卡片任意处弹窗 | `:44-47` 整卡 `onTap: onRecord` | P9 |
| 33 | 添加数据可选日期 | `weight_entry_dialog.dart:88-151` 无日期字段；仓库 `saveManualWeight` 已支持 `localDate` | P9 |
| 34 | 步数接手机本机数据 | 今日页步数卡**无数据源**（`dashboard_quick_stats_row.dart:133-165` 硬编码「暂无记录」）；全仓**零** MethodChannel | P9 |
| 35 | 删掉「内容由 ai 生成，请勿从事违法活动」 | `lf_chat_input.dart:477` `ChatDisclaimer` | P10 |
| 36 | 语音转写无法使用，删按钮与相关功能 | 见 §P10 文件清单（4 删 + 11 改 + 依赖/权限/文档） | P10 |
| 37 | 拍照识别点击后直接跳拍照；删二级菜单与相关内容；拍照后直接发 AI 识别 | 入口唯一：`app_router.dart:325`（AI 对话 `cta-photo-scan` 芯片）→ `/meal-recognition`；「二级菜单」= `food_scan_page.dart:257-300` 的落地屏（拍摄/相册两钮 + 空态） | P10 |
| 38 | 用给定 api 测所有 AI 功能（含 chat 修改可编辑内容），查接口是否正确、能否控制，然后修复 | 端点已实测（见 §P4/§P11 证据）；`ai_protocol_wire.dart` 只读 `delta.content` ⇒ 推理型模型会给出**空回复** | P4 + P11 |
| 39 | 再三确认新文档不被旧文档误导，整理存放旧文档 | §0；P0 落地 | P0 |

---

## 2. 裁决表（D1–D14：已给出默认选择；不同意改一行即可）

| # | 决定 | 理由 | 备选 |
|---|---|---|---|
| D1 | 2.x 已完成方案**原位保留 + 状态横幅**，不物理搬移 | 引用数 51–210，搬移制造死指针比不归档更误导（§0.4） | 全搬进 `history/2.x/`（❌ 已否决） |
| D2 | `/profile-edit` 改 `push`，删掉 `profile_edit_page.dart:94` 的裸 `Navigator.pop` | 唯一错误源是「`go` 进入 + `pop` 退出」；两处 pop 是设计味道 | 只把 `onClose` 改成 `maybePop`（保留 `go`）——**不选**：`go` 会让返回栈丢层级 |
| D3 | 身高/年龄/性别**并入**该页（页名改「编辑个人资料」），可编辑 | 用户语义是「个人资料编辑页」；`Profiles` 已有列，无需迁移 | 仅加身高——**不选**：同一页面分两批改，用户要再喊一次 |
| D4 | 步数用 **Android `TYPE_STEP_COUNTER` + 首个 MethodChannel**，不引 Health Connect | 零新依赖；Health Connect 需新依赖 + 新权限声明 + 仅 Android，收益不变 | 暂不做（❌ 用户点名要做）／Health Connect（记录为未来项） |
| D5 | 菜品图片与步数共用**一次迁移 `19→20`**（`MenuItems.imagePath` + `StepsDaily` 表） | 一次迁移 = 一份迁移测试 + 一次备份注册同步；两次迁移只是多一次门禁开销 | 分两次迁移（可接受，但无收益） |
| D6 | 食物库做**全量人工审核**：49,464 条逐条有人工裁决（名称/品牌/非食物/重复）；机器规则**只用于排队与预填，不作为结论上屏** | 用户 2026-10-05 明确裁定必做。而且**人工裁决正是既有算法的缺口所在**：W3 因「频率分不清品牌与描述词」主动排除纯汉字首 token（`build_brand_gazetteer.py` 记 known gap），人一眼能判 `明治` 是品牌 / `迷你` 不是——这条缺口只有人工能关。工时如实计入（§P8b 开头） | 规则化 + 抽样复核（❌ 已被用户否决） |
| D7 | 品牌进 `Foods.brand` 列（种子导入时写入），卡片左下角渲染为带边框 chip | `brand` 列已存在且目录行已在用；不新造列 | 只做前端拆分不落库（❌ 每次渲染都要重算，且聊天/备份拿不到） |
| D8 | 删语音转写**保数据列**（`audioPath`/`durationMs` 不 DROP），只删代码与依赖 | DROP 列要动备份注册表 + 迁移；留着是 Nullable 且无害 | 一并 DROP（记为后续清理项） |
| D9 | 摘掉 `record` 依赖与 `RECORD_AUDIO` 权限 | 语音是它唯一用途；权限越少越好（隐私说明同步改） | 保留依赖（❌ 留着一个没有调用方的录音权限） |
| D10 | 健康数据三指标用**三种不同的图形语言**（BMI 分档刻度尺、BMR 区间指示、饮水进度环），不照抄「三条一样的条」 ~~（2026-10-16 用户裁决：**饮水进度环删除**，健康区回到两格——见本表下注）~~ | BMI 有公认分档（18.5/24/28），BMR/饮水是单值目标，套同一根条会伪造语义 | 三条统一成进度条（❌ 会误导 BMI） |
| D11 | 今日推荐卡的「证据/目标影响」图形化后**只保留可核验事实**（证据等级徽标 + 营养完整度 + 候选序号），删掉散文式长句 | 那两句是「把三个事实拼成一串字」；图形化后信息量不减、可读性大增 | 全部删除（❌ 会丢掉「为什么推荐它」） |
| D12 | 照片识别入口**直通相机**并自动开始识别；下游结果/确认/剩余(餐前餐后)流程**保留** | 「不要影响其他功能」优先；剩余识别（净摄入）是已交付功能，仅存于本页 | 整页删除（❌ 会删掉净摄入） |
| D13 | 人工裁决词表**独立存放**（`lib/utils/food_brands_reviewed.g.dart`，由账本生成），`splitFoodName` 查 `自动表 ∪ 已裁决表` | 自动表的可贵性质是「能从种子重算、逐字节校验」（`food_name_test.dart` 就是这条断言）；混入人工 token 会毁掉它。分开后自动表继续可重算，人工表每条能回溯到账本哪一次裁决 | 直接改 `kFoodBrandTokens`（❌ 让「词表 = 规则重算」的测试失去意义） |
| D14 | 宏量三格**固定三格、缺值写 `0g`**（用户要求），**同时保留**「营养不完整 · 不可加入计划」标记；`docs/21 §3.11` 的「`0` 也当没有 / 缺项不占位 / 不画 0%」三条条文按此改写，「上游把缺失写成 0」的数据事实移入 `docs/07` | 用户对「位置固定 + `0g` 要写」的要求是明确的；而 §3.11 现在的写法（0 当没有、不占位）也是**刻意的诚实取舍**——两者不能同时成立，只能由用户口径优先并把取舍写清：**数字统一写 `0g`，「不完整」这件事仍由标记承担**，`0g` 不会被当作计算依据 | 保持「`0` 不占位」（❌ 与用户明确要求冲突，且卡片位置仍会漂） |

---

## 3. 共同纪律（每一包都适用，不再重复）

1. **门禁**：`tool/verify.bat` 退出码**重定向到文件**（**不走管道**；`echo` 会把退出码冲成 0），
   要求 `All tests passed` + `0 changed`（format）+ `No issues found`（analyze）。
   注意 `verify.bat` 的 **format 失败会短路 analyze/test**（可能掩盖测试是否跑过）。
2. **变异红证**：每条新断言配一条隔离变异（字节备份 → 一处最小改动 → 只跑该文件 →
   点名用例转红 → 逐字节还原 + sha256 相等）。多行锚点必须先确认目标文件的换行风格
   （本仓 CRLF 文件：`app_database.dart`、`lf_chat_bubbles.dart`、`food_library_view.dart`、`STATUS.md`）。
   变异电池会重写文件字节 ⇒ **电池之后必须再跑一次完整门禁**才算终态。
3. **设备**：只认 `emulator-5556`（AVD `LocalFit_API35`，1080×2340/density 480 = 360dp）。
   `uiautomator dump` 取真实 bounds 再 tap，坐标必须在**每次 tap 前重新 dump**；
   换行在 dump 里是 `&#10;`（底栏标签是 `'饮食&#10;饮食'`），判等不能 `strip()==label`；
   `adb` 的 `/sdcard` 路径要 `MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL="*"`。
4. **禁脚本化字符串手术**（本项目曾因切片脚本误删 `settings_page.dart` 约 300 行）：
   一律逐文件精确 Edit，改完 `grep` 复核计数。
5. **仓库无 git** ⇒ 任何包动手前先把 `lib/`+`test/` 相关子树备份到 `E:/AI/Zcode/backups/`；
   工具链重建前先断言旧产物与备份**逐字节相同**。
6. **文档与代码同步**：漏改活文档等于门禁红。每包结束同时更新 `docs/21`（若动到 UI 规范）、
   `docs/INDEX.md`（若新增/归档文档）、`STATUS.md`、证据文件。
7. **路径安全**：所有文件只在 `E:\AI\Zcode\` 内；写入用 `E:/AI/Zcode/...`；
   临时文件只进 `E:\AI\Zcode\tmp\`。
8. **零真实 AI 请求**只适用于自动化测试（全程 fake provider）；
   本方案的 **P4/P11 是用户明确授权的真实端点实测**，不得在测试代码里留下 key。

---

## 4. 工作包

### P0 文档治理（防误导，先做，无门禁风险）

- 新增 `docs/INDEX.md`；新增 `docs/history/2.x/README.md`；
  给 `docs/11/22/25/26/27/28` 加统一状态横幅（格式见 §0.3）；
  修 `GOAL.md` 第 6 行与第 84 行，并新增「当前目标」引导段（§7 的文本）。
- 验收：`grep -c "状态：已完成" docs/{11,22,25,26,27,28}-*.md` 全 ≥1；
  `ls docs/INDEX.md docs/history/2.x/README.md` 存在；
  被测试读盘的 5 个文件**未被改动**（对比 sha256）；
  门禁 `EXIT=0`（纯文档改动也必须跑一次，证明没碰坏任何被测字符串）。

### P1 个人资料页三件（报错 / 身高 / 关闭）——用户第一条就要这个

- **修报错**（D2）：`app_router.dart:376-378` 的 `go` → `push`；
  删 `profile_edit_page.dart:94` 的裸 `Navigator.pop(context)`（保留 `onClose` 单一出口）。
- **身高/年龄/性别可编辑**（D3）：页名改「编辑个人资料」；新增身高输入（复用
  `AppNumberField` + `Key('profile-height')`），沿用 `Profiles.heightCm`；
  落库走 `ProfileIdentityRepository`（新增 `updateBodyProfile`，与 `updateGoal` 同事务风格）。
- **关闭按钮**：AppBar 右侧加 `LfCircleIconButton(key:'profile-edit-close', icon: Icons.close)`。
- 回归测试：`test/features/settings/profile_edit_route_test.dart`（新）：
  ①`push` 进入后保存**不得**出现「更新失败」；②保存成功后回到上一页且身高已落库；
  ③关闭按钮存在且能返回。变异：把 `push` 改回 `go` ⇒ ①必须红。
- 设备：360dp 走查三态（正常 / 键盘弹起 / 保存成功）。

### P2 健康数据图形化（HTML 先行，D10）

> **2026-10-16 范围变更（用户原话：「去除水分摄入目标卡片」）**：健康区的第三格
> （`settings-health-water` 饮水进度环）删除——饮水达成度在今日页饮水卡
> （`dashboard-stat-water` 的「已饮 / 目标 ml + 达标 N%」）已有更贴近使用场景的
> 表达，这里是同一事实的第二处重复。随之删除的死代码：`LfProgressRingGauge`
> （自此零调用方）与 `waterProgressOf`（零生产调用方）。D10 的**其余部分**
> （BMI 用分档刻度尺、BMR 用区间指示，不套同一根条）不变。

**状态：已交付（2026-10-05）**。设计稿 `ui设计/remediation/我的-健康数据.html`（含状态矩阵与暗色抽查）
+ 360dp 评审图已归档；三变体落地 `lib/app/design/widgets/lf_metric_gauge.dart`，口径另立
`lib/features/settings/domain/health_metric_bands.dart`；实况/门禁/变异清单见 `STATUS.md` 与
`docs/evidence/2026-10-05-p2-health-metrics.md`。
**开工后发现本方案没写死的一处**：BMR 的「区间」取**该用户自己的** `Goals.calorieMin/Max`
（仓库里没有公认的「正常 BMR 区间」，编一个就是伪造语义），为此 `ProfileOverview` 只加了两个
透传列（`calorieMinKcal`/`calorieMaxKcal`）与「今日饮水合计」（达成度的分子），
BMI/BMR/水目标的派生逻辑一行未改。下面各条为原始设计意图，实现与本节的差异以本段为准。

**本包设备走查抓到的三个真实缺陷（都已修 + 配回归与变异）**：
① 刻度尺**超重段**用 `gaugeToneColors(...).content` 上色 = `cardForeground` 墨色 ⇒ 画成近黑，
看不出是「超重」；改用 `track` 数据色（`carbs` 琥珀），并补一条四段配色的断言（M11）；
② 刻度数字行**行高写死 14px**，2.0× 下 micro 字高 20px ⇒ 数字上下各裁一半；改成由文字自己撑开（M12）；
③ 档界数字位置用 `Align(Alignment(x, 0))` 算 ⇒ 那是往「剩余空间」按比例摆，字越宽越向中间挤
（实测 2.0× 下「18.5」偏 26px、三档数字跨度窄 19px）；改成一格一档界 + 半字宽位移（M13/M14）。
设备像素实测（截图 `dev-07`/`dev-09` 的段边界 vs 数字中心）：2.0× 偏差 ≤1.1px、1.0× ≤0.2px。

**连带修掉的一处「旧数字」**：水分卡第一次显示「今日」进度后，在今日页记 500ml 再切回来，
卡上仍是 `0%`（设备实测 dev-11）——本页的 `_overviewFuture` 是 `initState` 里的一次性快照，
而 shell 分支切 tab 不重建。修法：`SettingsPage.didChangeDependencies` 观察 `TickerMode`
（go_router 给非当前分支套 `TickerMode(enabled: false)`）的 false→true 翻转，重造 future 重读；
`FutureBuilder` 换 future 保留旧 data ⇒ 不闪空态。**未覆盖**：停留本页期间别处写库、以及
分支内 push 的二级页返回（`/profile-edit`）——两条都记在 `docs/21 §5.6` 的已知限制里。

- **先做 HTML**：新建 `ui设计/remediation/我的-健康数据.html`（**不能放进 `ui设计/pages/`**：
  `test/app/design/design_source_parity_test.dart:334` 对该目录做 `unorderedEquals` 7 页断言，多一个文件即红）。
  用无头 Edge 渲染 360dp 截图评审（`ui设计/remediation/*.jpg`）。
- 三种图形语言：BMI 分档刻度尺（灰/绿/橙/红 四段 + 指示器 + 档位文字「正常」）、
  BMR 区间指示（数值 + 所处区间）、饮水进度环（目标达成度）。
- 原生：新增 `lib/app/design/widgets/lf_metric_gauge.dart`（三变体），`settings_page.dart:1578`
  的 `_HealthMetricsCard` 换成三张图形卡；数据仍来自 `load_profile_overview.dart`
  （BMI `:185-189`、BMR `:191-214`、水 `:94-101`），**派生逻辑零改动**。
- 测试：`test/features/settings/health_metrics_graphic_test.dart`（新，15 例）：
  分档边界（18.4/18.5/23.9/24.0/27.9/28.0）、缺数据时不给假档位、2.0× 不换行；
  另加 `settings_branch_refresh_test.dart`（2 例，切回重读 + 不闪空态）。
- 颜色只用 `LfColors` 既有 token（`macro_bar.dart` 的数据色），不新造色。

### P3 成就分级与进度（与 P2 同一份设计稿）

**状态：已交付（2026-10-05）**。设计稿 `ui设计/remediation/我的-健康数据.html` 的成就段补了「行卡 + 分级 +
进度环」并归档 360dp 评审图；落地三件：设计层行卡 `lib/app/design/widgets/lf_achievement_row.dart`
（含 `LfMedalTier` 三档色板）、业务口径 `lib/features/settings/domain/achievement_levels.dart`
（`AchievementSpec` 目标值单源 + `achievementLevelOf` + `achievementCountOf`）、
`settings_page.dart` 的 `_AchievementsCard` 只做「业务枚举 → 设计枚举」映射。**零 schema 变更、零新依赖**
（等级是纯展示层派生）。门禁/变异清单见 `STATUS.md`，证据 `docs/evidence/2026-10-05-p3-achievements.md`。
下面各条为原始设计意图。

**设备走查补到了「本方案没打算能到达」的状态**：空库只能看到「未解锁 / 进度 0」，而银档、金档、
已解锁、条有填充这几态**都要真实行为数据**。本轮用 App 自己的 UI 造数据（记餐搜索框只吃 ASCII，
而食物库保留品牌名 ⇒ 拿品牌名片段当查询词；再用 `adb root` + `date -s` 逐日推进模拟器日期凑满
7 天连续打卡），把银档 → 金档 → 已解锁一路摆到屏幕上，并逐像素复核（亮/暗 × 1.0×/2.0× 三种渲染）：

| 状态（真实 progress） | 条填充 / 条轨 | 环弧（理论 = progress×360° + 圆头帽 7.4°） | 内盘色 |
|---|---|---|---|
| 7天连续打卡 1/7 | 95 / 667 = **0.1424** | 0°→**59.0°**（理论 58.8°） | muted `#EFF3F1` |
| 健康饮食 1/30 | 21 / 648 = **0.0324** | 0°→**19.5°**（理论 19.4°） | muted |
| 健康饮食 7/30 | 151 / 648 = **0.2330** | 0°→**91.5°**（理论 91.4°） | muted |
| 7天连续打卡 7/7 + 已解锁 | 617 / 617 = **1.0** | 0°→**360°**（整环） | 金 **`#FFC94D`**（暗色 `#FFD56B`）逐字节相等 |

档位跳变也在设备上亲眼看到：`3/7 → 铜`、`4/7 → 银`（0.5 边界）、`7/7 → 金 + 已解锁`。

**两处如实记录（都是「记录边界、不改代码」）**：

① **2.0× 行高有 ≤1dp 的分数差**：行距 1.0× 实测 206–208px（零进度两组全 `[207, 207, 207]`，行高由 44dp 勋章撑定），2.0× 是 291–294px（零进度 `[294, 291, 291]`、金档 `[294, 291, 292]`）。
   1.0× 下 44dp 勋章撑定行高（整数 dp），2.0× 下变成**文字度量**撑定，而 Android 的非线性字体缩放
   给出的是分数 dp。曾按「钉死行盒」的假设给名称/计数加过 `forceStrutHeight` 的 strut，**设备截图
   逐字节无变化**，随即逐字节还原（sha256 相等）。既不换行也不裁切、不越卡片，故只记录不改。

② **320dp 下的名称缩小兜底永不触发**：实测最长的「7天连续打卡」在 2.0× 只需 **157.5dp**、可用
   **161.75dp**（差 4.25dp）⇒「去掉 `FittedBox`」这条变异在 320dp 用例上是**等价变异**（先跑出来是绿的
   才发现的）。为此补了两条断言：320dp 用例加「兜底在场且是 `scaleDown`」的结构断言，另加一条
   **300dp** 用例钉「真放不下时整体缩小而不是省略」（该宽度下名称 157.5dp > 可用 141.75dp，兜底真介入）。
   同时补了「计数上限 `target - 1`」的两条断言（`progress = 1 - 1e-10` 这类被 ε 顶到目标线的值）——
   该分支原本没有断言覆盖（去掉上限的变异也是绿的）。

- 数据已有：`Achievements.progress`（0..1）+ `unlockedAt`（`tables.dart:682-692`），
  `ProfileAchievement{key,label,unlocked,progress}`（`load_profile_overview.dart:331-345`）。
- 形态：**横向行卡**（图标 + 名称 + 进度条 + `n/目标`），解锁后换实心色 + 徽标；
  名称 `maxLines:1`（不换行），超长用更小档而不是省略号（信息性文本不得省略）。
- 新增 `level` 概念：按 `_evaluateAchievements`（`:224-229`）的目标值把 `progress` 映射
  到「铜/银/金」三档（纯展示层派生，**不落库、不改 schema**）。
- 测试：`test/features/settings/achievements_level_test.dart`（新）：0/0.49/0.5/0.99/1.0 的档位、
  未解锁不显示「已解锁」、2.0× 与 320dp 名称不换行、进度条宽度与 progress 单调。

### P4 AI 配置统一 + 连通性测试 + 模型拉取/选择 + **推理开关**（endpoint 可用性的前提）

**状态：已交付（2026-10-05）**。设置页 AI 组收敛为单行入口 + 配置弹层（协议 / Base URL / 模型 /
`ai-config-probe` 连通性测试分档文案 / `/models` 拉取 + `ai-model-search` 过滤 + 点选回填 /
`ai-reasoning` 推理开关 / API Key 留空保持 + 清除二次确认）；`AiReasoningMode`（NULL→disabled）
经 `AiProtocolWire` 作用于全部出口，纯推理回复两路兜底；schema 19→20。门禁 `EXIT=0`（1892/3）、
变异 17/17 RED。证据 `docs/evidence/2026-10-05-p4-ai-config.md`。
下面保留方案原文（行号按实施前代码，仅作战术参考）。

**实测证据（2026-10-05，用户提供的端点；key 不落盘，仅临时存 `tmp/`）**：

| 观测 | 结果 |
|---|---|
| `GET {base}/models` | `200`，**9 个模型**，目标 `deepseek-ai/deepseek-v4.1-flash` 在列表内 |
| Base URL `https://freeapi.site/v1` | 被 `open_ai_compatible_endpoint.dart:96-102` 正确规范成 `/v1/`，拼出 `/v1/chat/completions` ✅ 无需用户改输入 |
| 单次延迟 | **12.6–22.1 s**（与输出长度无关，上游排队为主）；`receiveTimeout` 45 s ⇒ 暂时不会误超时，但**总时长会逼近** |
| 默认行为 | 是**推理模型**：`reasoning_content` 160–203 字符，`content` 才 46–52 字符 |
| 小 `max_tokens` | `finish_reason=length` 且 **`content: null`**（token 全被推理吃掉） |
| 流式 | 14 条 delta 里 **13 条是 `reasoning_content`**；全仓只读 `delta.content`（`ai_protocol_wire.dart:273-282`） ⇒ **客户端会渲染成空回复** |
| `thinking:{type:"disabled"}` | ✅ 生效（reasoning 0） |
| `chat_template_kwargs:{enable_thinking:false}` | ✅ 生效（reasoning 0） |
| `reasoning_effort:"none"` | ✅ 生效（reasoning 0） |
| `enable_thinking:false`（顶层） | ❌ **400 `Unsupported parameter(s)`** |
| `max_tokens` 传字符串 | ❌ 400（上游严格按 u32 反序列化） |

- **配置统一**（需求 6）：把协议 / Base URL / 模型 / **API Key** 收进同一处
  （`_openAiConfigSheet` `settings_page.dart:693-814` 扩展，或整组改为一页设置），
  组内不再留「孤零零一行 Key」；`docs/21 §5.6` 结构树同步。
- **连通性测试**：`GET {base}/models`（带 5s 超时、失败分档报错：
  401 key 错 / 404 base 错 / 超时 网络不可达），结果内联显示，不弹系统提示。
- **模型拉取 + 选择**：把返回的 9 个（或任意数量）模型做成可选列表 + 搜索，
  选中即写入 `AiProviderConfigs.model`；列表拉不到时保留手输（永不阻塞用户）。
- **推理开关**（关键修复）：新增按 provider 的 `reasoning` 选项，默认对
  **chat 协议**发送 `thinking:{type:"disabled"}`（实测三种可行里语义最直白的一种），
  UI 上给「关闭推理（更快）/ 默认」两档；`ai_protocol_wire.dart` 的
  `conversationRequestBody`/`taskRequestBody` 增加可选字段（**不改变既有请求体的既有键**）。
  兼容性：respones/anthropic 两协议不发该字段（尚未实测，见 §6 诚实边界）。
- **空回复兜底**：`_chatCompletionsDelta`/`_chatCompletionsContent` 遇到
  「只有 reasoning、content 为空」时给出**可解释错误**（「模型只返回了推理内容，
  请在设置里关闭推理或增大输出上限」），不允许静默空气泡。
- 测试：`test/features/settings/ai_config_sheet_test.dart`（新，fake Dio）：
  连通性成功/401/404/超时四态；模型列表渲染与选中落库；推理开关默认值与请求体断言。
  变异：去掉 `thinking` 字段 ⇒ 请求体断言必须红。

### P5 动作库卡片 / 详情抽屉 / 弹窗流畅度

**状态：已交付（2026-10-06）**。设计稿 `ui设计/remediation/训练-动作库.html` + 360dp 评审图先行；
卡片（分类串右上角同行 / 删 `Spacer` / 实测行高 1.0× **124.2dp**、2.0× 158.4dp）、详情抽屉（可点行卡 +
原地切换 + `waiting` 骨架行 + `AppSheet` 统一动效）、流畅度（`search` 提 `initState` + 300ms 防抖 +
查询变化才换 `ValueKey`）均已落地——**行高目标 ≤140 达标**（124.2）；门禁 `EXIT=0`（1902/3）、
变异 2/2 RED、设备走查 7 项。证据 `docs/evidence/2026-10-06-p5-exercise-library.md`。
下面保留方案原文（行号按实施前代码，仅作战术参考）。

- **卡片**（需求 9/10）：
  - 分类串 `'肌肉 · 器械'` 移到**卡片右上角**（`Row` 的右侧，与左上角图标行同一行）；
  - 删 `:421` 的垂直 `Spacer`（≈35.6dp），图标↔标题间距改为显式 `SizedBox(8)`；
  - 标题↔标签行间距 `12+18.2+4`（≈34dp）压到 `6+8`；
  - `mainAxisExtent: 168` → **实测内容高 + 12**（先量后改；目标 ≤140）。
- **详情抽屉**（需求 8）：替代动作从裸 `ListTile` 改成「图标圆 + 名称 + 器械/难度 chip」的行卡，
  并**可点击切换**（`listAlternatives` 已返回完整 `ExerciseRecord`，含 `difficulty`/`popularity`，当前全未使用）；
  加 `ConnectionState.waiting` 分支（现在加载中会闪「暂无同肌群的本地替代动作」）。
- **流畅度**（需求 11，真凶已定位）：把 `_ExerciseLibraryGrid` 的
  `future: repository.search(...)`（`:298-299`）提成 `initState` + 查询变化才重建的字段
  （并给搜索加 debounce）；这样键盘 inset 变化引发的重建不再重查 DB、不再回骨架屏。
  抽屉动画统一到 `AppSheet` 的 `AppMotion` token（现在详情走默认 M3 时长）。
- 测试：`exercise_library_page_test.dart` 扩充：卡片布局断言（分类在右上角、固定行距）、
  替代动作行可点、搜索不因重建重查（用计数 fake repository 断言查询次数）。
  变异：把 `Spacer` 加回去 ⇒ 高度断言红；把 future 移回 `build` ⇒ 查询次数断言红。

### P6 记录页间距 + 记录一餐 FAB + 今日推荐卡图形化

**状态：已交付（2026-10-06）**。hero↔下一餐卡 16dp 外间距、FAB 抬 96 + 阴影加强、
通勤行删除 + 散文改图形事实行（`NextMealFactsRow`：证据徽标/营养完整度/候选 n/m/快照标签，
「没有的事就不画」）均已落地；门禁 `EXIT=0`（1915/3）、变异 12/12、设备走查 7 项
（**实测**：16dp 整、FAB↔凸起净距 23.7dp≈设计 22.5）。证据 `docs/evidence/2026-10-06-p6-record-page.md`。
**三处前提经实测修正**：①「`ManualCommuteDialog` 仍可从别处进入」为假——被删行是唯一调用点，
对话框已迁到设置页（`settings-commute-row`，并顺手修掉「保存报失败但落库成功」的 setState 既有缺陷）；
②「FAB 与凸起圆只有 ~6.5dp」是训练页几何（80−73.5），记录页真缺陷是
`MediaQuery.paddingOf` 在 `extendBody` 下双算底栏高（真实旧距 ~81.5dp），已改 `LfInsets.bottom`
（训练页同款隐患一并修掉）；③阴影 α .38 不在 docs/21 §2.4 白名单，取最近档 **40%**。
底栏顶分隔线系 docs/21 既有 `border-t`，无需新增。设备 2.0× 实拍本轮未取得
（OS 不应用 font_scale，五条路径全试；组件级 2.0× 审计绿，P12 再试）。
下面保留方案原文（行号按实施前代码，仅作战术参考）。

- **间距**（需求 12）：hero 与下一餐推荐卡之间加 `LfDimens.pagePadding`（16dp）外部间距
  （现在 **0**；注意 hero 的 20dp 内边距是渐变内部的，不能当间距）。
- **FAB 浮空**（需求 13）：抬高底部偏移（80 → 约 96）+ 加大阴影（`LfShadows.recordFab`
  blur 12→20、α .30→.38、offset y 4→6），并给底栏上缘一条极淡的分隔（或给 FAB 加 1px 描边环）；
  改后必须实测 FAB 与中间凸起圆的**像素间距**（现在只有 ~6.5dp）。
- **今日推荐卡**（需求 14/15，D11）：
  - 删 `next_meal_decision_card.dart:193-199` 的通勤行（`ManualCommuteDialog` 仍可从别处进入，
    **不删数据与对话框**，只删这张卡上的呈现）；
  - `:338`/`:340` 两句散文换成图形块：证据等级徽标（已有 `AppEvidenceBadge`）+ 营养完整度图标 +
  候选序号 `n/m` + 快照日期（都是已有字段），一排 chip/图标；
  - 测试：`next_meal_decision_card_test.dart` 断言「不再出现 `通勤时间` 文案」+
  「证据/候选信息仍可读」（**不能只断言删除，必须断言替代形态留下了信息**）。
- 变异：把通勤行加回 ⇒ 文案断言红；把证据徽标拿掉 ⇒ 信息断言红。

### P7 食堂目录：不跳顶 / chip / 菜品行 / 菜品图片

**状态：已交付（2026-10-06）**。设计稿 `ui设计/remediation/食堂-地点与菜品.html` 先行；
滚动保持（stale-while-revalidate：`_windowsByVenue` 缓存 + 预取全部地点 + 有旧数据不进加载分支 + 2dp 细进度条）、
chip 选中态重做（删圆点与极淡底色 → 2px 主色描边 + 主色文字 + 轻抬升，44dp 触达不变）、
菜品行（序号圆/缩略图行头 + stationName 副行 + 8dp 行距 + 1px 分隔线，首行无线）、
菜品图片（schema v20→**v21**：`image_path` + `steps_daily`；`DishImageStore` 原子写 +
扩展名白名单 + 目录前缀守卫；表单三动作「拍照/从相册选/移除照片」；`setImagePath` absent 语义）
均已落地。门禁 `EXIT=0`（**1940/3**）、变异 **18/18 RED**、设备走查 7 项
（**实测**：切地点 scroll 偏移 803→803 Δ=0px；相册取图→缩略图上屏端到端）。
证据 `docs/evidence/2026-10-06-p7-canteen.md`。
**★ 设备走查抓到 P0 缺陷**：升级路径首启崩溃
`SqliteException(1): duplicate column name: image_path`（开发期该列曾在 `from < 20` 分支，
中途构建的库 `user_version=20` 但列已在）⇒ 迁移守卫从「版本区间」改为
**`pragma_table_info` 列存在性**（嵌在表存在性守卫内，因为 pragma 对不存在的表静默返回空），
补回归 fixture（v20 + 列已在）与变异 P7-3 钉住；**教训：版本号只说明「跑没跑过链」，
说明不了「列在不在」**。方案原文说「一次迁移 19→20」，实际因 P4 已发 v20 而顺延为 20→21。
下面保留方案原文（行号按实施前代码，仅作战术参考）。

- **滚动保持**（需求 18，机制已定位）：`menu_tab_view.dart:159-161` 改成
  「保留上一份数据的 `FutureBuilder`」或把 `listWindows` 结果存进 state，
  切换 venue 时**不进入 loading 分支**（加载中继续显示旧列表 + 顶部细进度条），
  从根上消除 `SliverFillRemaining` 造成的 offset 夹回。
  测试断言：切换地点前后 `ScrollPosition.pixels` 差 ≤1px（在 360dp 上有足够内容可滚）。
- **chip 与选中态**（需求 19）：`AppMorphChip` outlined 变体重做选中态（去掉「圆点 + 极淡底色」
  这种弱表达，改为主色描边加粗 + 主色文字 + 轻微抬升/内阴影二选一，设计稿先出 HTML），
  并保证 44dp 触达不受影响（这是既有不变量）。
- **菜品行**（需求 17）：`CanteenWindowCard:97-104` 从「裸行 + 6dp」改成
  带序号或图标的行卡（左图/序号、中名、右价格），行间 `8~12dp` 间距 + 细分隔线；
  不引入新数据（`stationName` 若存在可作为副行）。
- **菜品图片**（需求 16，D5）：一次迁移 `19→20`：
  - `MenuItems` 加 `imagePath TEXT NULL`；新增 `StepsDaily` 表（P9 用）；
  - 迁移测试 + 备份注册表（`backup_table_registry.dart` 的 path 字段集合）同步；
  - 图片来源复用 `image_picker`（已在依赖里）+ `FileChatImageStore` 的
    「复制进 app documents 再存路径」模式（`file_chat_image_store.dart:9-140`）；
  - 表单 `_promptDishForm`（`menu_form_prompts.dart:135-174`）加「菜品照片」字段（可选，可删）；
  - `CanteenDishRow` 有图显示缩略图、无图保持现状（**诚实空态**）。
- 变异：滚动保持断言（把 loading 分支改回 ⇒ 红）；迁移（去掉新列 ⇒ 迁移测试红）。

### P8 食物库：卡片与抽屉一致化 + **全量人工审核**（本方案最大的包，拆三段：P8a 呈现 / P8b-1 工具与账本 / P8b-2 v5 与升级）

**P8a 呈现一致化（需求 20–22、24、26–30）**

**状态：已交付（2026-10-06）**。设计稿 `ui设计/remediation/食物库-卡片与抽屉.html` 先行；
卡片/骨架/详情弹层/顶栏四件按 D14 落地（首行共心中线、宏量恒三格缺值写 `0g`、环下
`kcal/100g`、满刻度上屏、品牌带框 chip 左下 + 自建/内置右下、卡底内距 8、`LfTopBar`
的 `showBack`/`showTitle` 开关、添加钮移到搜索框右侧、详情环 56/6 删占比行）。
页头抽成共享件 `food_library_header.dart`（两条数据路径同一份，也修回
`ui_maintainability_audit_test` 的 500 行预算）。**`docs/21 §3.11` 已按 D14 整节重写**，
「上游把『没填』写成 0」的数据事实已落到 `docs/07 §5.8`。门禁
**1950 passed / 3 skipped，All tests passed**、`No issues found!`、format 0 changed；
**变异 17/17 CAUGHT**（两条初判 SURVIVED 的按「变异本身不合法」重做后转红）；
设备走查 11 项（emulator-5556，含**远跳不 ANR** 与 2.0×/暗色叠加）。
证据 `docs/evidence/2026-10-06-p8a-food-library.md`。

- 卡片 R1 改 `CrossAxisAlignment.center`（标题与图标/环同高中线）；
- 宏量三格**固定三格**（缺值写 `0g`，`nutrientOrMissing` 的「0 当缺失」语义改为
  「缺失与 0 都上屏写 0g，但 `无热量数据` 保持事实判断」——注意 `:305-308` 现在是
  「null 和 0 都当缺」，必须改成显式三态，否则「0g 也要写」做不出来）；
- 环心文本加单位（`2 8 8 kcal` 或 `288` + 环下标签写 `kcal/100g`）；
- 环满刻度 900 kcal/100g 的**语义上屏**（环下或详情里一句「能量密度满刻度 900 kcal/100g」），
  否则用户永远不知道「环的全部」代表什么（需求 23）；
- `LfBadge(自建/内置)` 移到**卡片右下角**；品牌改**带边框 chip 放左下角**，
  与 `LfBadge` 同高同字号、上下对齐、颜色不同（新增 `LfBadge.outlinedBrand` 变体，
  不新造第 8 种按钮/标签形态）；
- 卡片底部内边距 12 → 8（`:94`）；
- 顶栏（需求 29/30）：`LfTopBar` 加 `showBack`/`showTitle` 开关（**默认保持现状**，
  只有食物库这个 tab body 传真），添加按钮从顶栏移到搜索框右侧；**共享件不得全局删**
  （`lf_top_bar.dart:87-109` 被拍照/食堂/下一餐多页使用）。
- 抽屉（需求 28）：环 88 → 约 56/6（保证三格同行放得下，`_ringColumnWidth` 与
  `_macroRatioRowBaseNeed=219` 的并排判据要重算）；**删百分比行**
  （`_macroRatios`/`MacroRatioRow`，`food_detail_sheet.dart:246-253,315-331`）；只留克数行；缺值 `0g`。
- **这一包与活文档正面冲突，必须同批改写**（§3 纪律 6；`docs/21 §1` 的冲突裁决）：
  `docs/21 §3.11` 现在明文写着三条与本包相反的口径——「`0` 也当没有」、「缺项的宏量
  **不占位**」、「占比行整行不渲染而不是画 0%」，理由是「不假装测过」。用户要求
  「没有的也要写 `0g`」⇒ 按 D14 改写 §3.11，并把「上游把『没填』写成 0」
  （`kcal` 0 有 206 行、`protein` 0 有 4,151 行）这条**数据事实**从 §3.11 移到 `docs/07`
  数据契约。**漏改即门禁红。**
- 测试：卡片与抽屉各加断言（对齐中心、三格固定宽、0g 上屏、单位、标签位置、底部间距）；
  变异逐条对应（每处改动一条）。

**P8b 食物库全量人工审核（需求 25；D6/D7/D13）**

> **用户 2026-10-05 裁定：人工审核必须做。** 所以本包不是「规则 + 抽样」，而是
> **49,464 条逐条有人工裁决**。先把规模说清：按 3–5 s/条，逐条走完约 **40–70 小时**
> 键盘时间。工作台提供**族批**（同前缀/同品牌的连续条目成组，一次按键确认整组，组内仍可
> 展开逐条）把按键数压下来，但**账本如实区分「逐条核验」与「族批确认」**，报告分列两个数。
> 本包承诺的是**工具先就绪、进度可续、账本可真、覆盖率可见**——不是「几天就能做完」。

**P8b-1 工具与账本（立即可做，不阻塞 P9–P12）**

**状态：已交付（2026-10-06）**。`tool/food_seed/review/` 四件（导出脚本 / `review_lib.py` /
`review_server.py` / `review_ui.html`）+ 三个测试 + `README.md`；**零新依赖、不进 App 包**。
门禁 **1962 passed / 3 skipped，All tests passed**、`No issues found!`、format 0 changed；
**变异 24/24 CAUGHT**（首轮 18/24，六条未捕获逐条查清：四条是「守卫重叠时只断言『会被拒』
等于没测」的测试缺陷、一条是编译错误不算捕获、一条是断言只查名字出现过）。
**未做任何人工裁决**（真账本至今不存在，`--stats` = 0/49,464）——本包交付的是工具与账本。
证据 `docs/evidence/2026-10-06-p8b1-review-workbench.md`。

实测要点（都是方案里没写、开工才会撞上的事）：
- `dart run` **能**跑纯 Dart 的 `lib/utils/*`，但**装不下 Flutter**（import 卡片即 `dart:ui`
  整片编译失败）⇒ D14 显示口径抽成**不含 Flutter 的 `lib/utils/food_display.dart`**
  （卡片留 `export` 转发），导出脚本与 App 因此读同一份实现，方案禁止的「别处重算一遍」
  一次也没有发生；同源由**种子 sha256 对账**（Dart 手写 SHA-256 == Python hashlib，
  零新依赖）+ **独立 Python 重算 vs Dart 预览前 4,000 行**双证；
- 真种子标记分布：`han_head_frequent` **23,301** 条（D6 点名的「只有人工能关」的缺口）、
  `head_ascii` 7,127、`nutrient_zero_or_missing` 7,909、`near_duplicate` 42……
  队列 **17,833 组**，其中 ≥2 条的 5,402 组覆盖 37,033 条（最大组 288 = `明治`）；
- **`review_mode` 由服务端判定**（单条 `item`、整组 `batch`），不成立**整批拒绝、一个字节
  都不写**，**不降级**——「族批确认写成逐条核验」正是本方案点名的混称；
- 撤回的语义目标是**账本里最近一条生效裁决**，不是「当前高亮行」（那一行在裁决瞬间就已
  退出队列 ⇒ 旧写法下先 `6` 删除再 `8` 撤回什么也没发生、条目再也回不来）；
- 真键盘走查**未闭环**（控制面板的 OS 级按键注入不到该面板，走的是页面内 `Event` 派发），
  如实记在证据文件里。

- `tool/food_seed/review/`：Python 标准库 `http.server` + 1 个静态 HTML，
  **零新依赖、不进 App 包**（审核台是开发工具，不是产品功能）。
  1. **上屏预览必须由 App 的同一份 Dart 函数生成**：离线跑 `splitFoodName` +
     `normalizeFoodName` 产出 `reports/display_preview.jsonl`（id → 品牌 / 上屏品名），
     审核台读它显示「这条在卡上长这样」。**禁止用 JS 重写拆分规则**——两份实现必漂移，
     而本包的全部意义就是让「人看到的就是上屏的」。开工第一步（≤10 分钟）：确认
     `dart run` 能解析这两个纯 Dart 文件的依赖；不能则用一个 `flutter test` 用例导出
     同一 artifact，并断言它与源码同源。
  2. 每条显示：原始 `name` / 上屏预览 / 四项营养 / 来源 id；键盘操作：
     `通过` `改名称` `定品牌` `并入品牌词表` `改营养` `删除` `存疑` `撤回`。
  3. **可疑队列只用于排序与预填**（品牌未拆、首 token 含 ASCII、重复品牌 token、
     名称含 `/` 或连续数字、营养四项有空/为 0、kcal 与宏量不自洽 >±25%、近似重名），
     **不是结论**；低风险条目走族批。
  4. 断点续审：`review_cursor.json` 记已裁决 id；`--stats` 打印
     「已裁决 / 逐条核验 / 族批确认 / 待审 / 存疑」五档进度——**进度是唯一的完成度声明**。
- 账本 `review_ledger.jsonl`（追加式，一行一条：`id, decision, before, after,
  source, review_mode(item|batch), ts`）——**这是本包唯一的权威证据**，也是
  「人工审核到底审了什么」唯一能点名的来源。

**审核边界（写死，不许含糊）**

- **必审（全量）**：名称、品牌拆分与命名、明显非食物条目、重复条目。
- **可疑才改**：四项营养——**改数值必须填 `source` 或标「人工估值」**，账本留痕
  （不许无来源地改数字）。
- **明确不审**（诚实边界）：营养学的绝对正确（需实验室数据）、过敏原/膳食标签
  （上游字段，与名称无关）——不假装审过。

**P8b-2 v5 生成与 App 升级（出口条件：覆盖率 100%）**

**状态：已交付（2026-10-07）**。出口条件已达成（账本 49,464 / 49,464 全覆盖，逐条核验
18,920 + 族批确认 30,544，存疑 0），四份产物已产出、App 已在设备上从 v4 原地升级到 v5；
实测与证据见 `docs/evidence/2026-10-07-p8b2-v5-upgrade.md`（含一处自纠：`迷你` 误并已更正）
与 `STATUS.md` 最上一条。与下文原始方案的差异（as-built）：

- 产物是**四份**不是三份：多一份 `lib/features/nutrition/domain/food_seed_count.g.dart`
  （条数常量）。原文说「改为从种子 manifest 派生」——**没有引入 manifest**，改成由
  `apply_review.py` 直接从 v5 生成一个 Dart 常量，效果相同（条数不再硬编码）且少一个
  需要校验一致性的文件；
- 门控比原文更严：除 `--require-coverage 100` 外**还要求 `pending == 0`**。原判据用
  四舍五入后的百分比，实测摘掉 1 条仍显示 100.0% ⇒ 漏判（已由「覆盖率对账」用例钉住）；
- `legacySources` **不含 `seed-v4`**：v4 是**升级源**（原地 UPDATE），不是被清理的旧源。
  混淆两者会让 `_purgeLegacySeeds` 先把待升级行删光（实测踩过）；
- `splitFoodName` 的默认参数写成 `Set<String>?` + `?? kFoodBrandTokensAll`——并集是运行期
  表达式，spread 不能直接当 const 默认值；
- 设备走查未能验证「纯汉字人工 token 剥头」：该 AVD 的 Gboard 无中文子类型，`adb input
  text` 注入不了中文。改由等价的 ASCII 人工 token（`Nichirei日冷`）真机证据支撑，
  纯汉字路径由 `test/utils/food_name_test.dart` 单测覆盖（详见证据文件 §七）。

以下为原始方案要求：

- `tool/food_seed/apply_review.py`：账本 → `assets/seed/foods.v5.json`（`version: 5`）
  + `lib/utils/food_brands_reviewed.g.dart`（人工裁决词表，D13）
  + `reports/review_report.md`（覆盖率、五档计数、删除清单、存疑清单）。
  **幂等**：连跑两次逐字节相同（sha256 断言）。
- **未审完不产出 v5**：`apply_review.py` 带 `--require-coverage 100`，缺一条即拒绝生成
  ——不出现「只审了一半的种子」这种中间态；未达 100% 时 App 继续用 v4。
- **App 侧不是「换个 asset」**（本包最容易做错的地方，三条实测事实）：
  - `_importV4` 的 gate 是「库里已有 `source='seed-v4'` 的行就 return」
    （`food_seed_importer.dart:56-62`）⇒ 换 asset 不会触发任何导入；
  - `_insertMissing` **永不覆盖既有行**（用户编辑保留，`:127-143`）；
  - `_purgeLegacySeeds` 只删**未被 `meal_items`/`menu_item_food_matches` 引用**的旧种子行
    （`:39-54`）。
  ⇒ 必须新增 `seed-v5` **原地升级**：对 `source ∈ 种子族` 且非用户自建的行做 **UPDATE**
  （name/brand/四项营养）并把 source 改为 `seed-v5`；`isUserCreated` / `source='user'`
  的行**永不触碰**；v5 删掉的 id 若仍被引用则**保留旧行并在报告里计数**（宁可留一条旧名字，
  不可让 `meal_items.food_id` 指向空）。
- 词表：`build_brand_gazetteer.py` 的自动规则**不动**（纯汉字仍由规则排除），
  人工结论走 D13 的独立表；`splitFoodName` 查 `kFoodBrandTokens ∪ kReviewedBrandTokens`。
- **同批改掉过时文本**（§0.2 形态 3）：`build_brand_gazetteer.py` 的
  「pure-Han prefixes stay in the name for now (recorded as a known gap)」要改写成
  「自动规则继续排除纯汉字；**人工已裁决**的品牌走 `food_brands_reviewed.g.dart`」。
  `docs/28`、`docs/evidence/2026-10-04-*`、`STATUS.md` 的 W3 条目是**历史记录，不回改**
  ——取代关系写进本包的新 evidence 与 `docs/21`。
- **条数会变**（删除条目）：`data_attribution.dart:25` 的「随包 49,464 条中文食物」
  与 `settings_page_test.dart:271` 的断言必须同步，**改为从种子 manifest 派生**
  （本仓已被「硬编码条数被连带打死」咬过一次，别留死字面量）。

**测试与变异**

- 账本→v5 **幂等**（连跑两次 sha256 相等）；
- **覆盖率对账**（v5 每条 id 都能追到一条账本裁决）——**摘掉一条裁决 ⇒ 必须红**；
- v5 升级四态：全新安装 / v4 未引用 / v4 被餐次引用 / 用户自建或用户改过的行**不被覆盖**；
- **不丢字**不变量在 v5 上继续成立（`food_name_test.dart` 的表枚举改读 v5）；
- 已裁决词表只含账本出现过的 token（**手加一个 ⇒ 红**）；
- 卡片品牌 chip 断言（`Foods.brand` 写入后上屏，P8a 的渲染接上真值）。

### P9 今日页：体重周/月视图与选日期 + 本机步数（D4/D5）

**状态：已交付（2026-10-07）**。实现与实测要点：

- **体重卡**（需求 31–33）：右上角「添加」按钮（`Key('dashboard-weight-add')`），
  整卡 `onTap` 已去掉；周/月分段控件（`周`/`月` 两个 `LfCircleIconButton` 风格的分段钮，
  切换后卡片标题在「本周体重 ⇄ 体重趋势」间变化，趋势子标题「本周趋势 ⇄ 本月趋势」，
  月视图对 30 天数据按周分箱取均值）；`WeightEntryDialog` 加日期字段
  （`Key('weight-entry-date')`，默认今天，可翻月选任意过去日期，未来日期禁点），
  **改日期时字段按目标日已有记录重播种**（有记录回填、无记录清空——不清空会把
  今天的数字写成历史日的记录）。
- **步数**（需求 34）：`MainActivity.kt` 的 `MethodChannel('localfit/steps')`
  （`read`/`requestPermission`/`openAppSettings`）+ `StepsRepository.syncToday`
  （重启基线：计数值变小 ⇒ 重设基线从 0 起算；同一天二次同步按 `local_date`
  UNIQUE select-then-update，**不是**按 id upsert——id 每次新生成，按 id upsert
  第二次就撞 `UNIQUE constraint failed`）。卡片三态：
  可用（数值+「今天」徽标）/ 未授权（`dashboard-steps-denied`，点卡片拉起系统
  权限申请）/ 无传感器（`dashboard-steps-empty`「这台设备没有计步传感器」）；
  **不可用时一个字不写库**（写 `steps: 0` 等于把「没读成」记成「没走过」）。
- **测试**：新增 31 条（steps_domain 14 / dashboard_steps_and_weight 7 /
  weight_entry_date 10），全量门禁 1962+31→1994 通过 EXIT=0；变异 10/10 killed
  （含「id upsert 假装可用」「均值改取首个」「跨日不重播种」「月视图切换不动」等）。
- **设备走查**（emulator-5556，emulator x86_64 debug 包）：① 步数卡先呈未授权态
  （未授权 / — / 去设置），点卡片拉起系统「身体活动」权限弹窗 → Allow → 卡片复读为
  「这台设备没有计步传感器」诚实空态（denied 与 noSensor 两态都在真机链路验证）；
  ② 周切月：标题「本周体重」→「体重趋势」、切回周标题复原；③ 添加 → 日期字段 →
  选 2026-09-30 → 字段从 72.0 清空 → 填 71.5 保存 → snackbar「体重已保存到 9 月 30 日。」、
  本周卡出现「↑ 0.5」；重开对话框改回 09-30 ⇒ 字段回填 71.5（跨日重播种双向验证）。
- **诚实边界**：AVD 无 `TYPE_STEP_COUNTER` ⇒ 「有传感器真机读数」无法端到端验证
  （§6 原口径不变）；重启基线逻辑由 Dart 侧 fake 单测覆盖，不能声称真机通过。

### P10 AI 对话与拍照：删免责声明 / 删语音转写 / 拍照直通

**状态：已交付（2026-10-07）**。实现与实测要点：

- **删免责声明**（需求 35）：`ChatDisclaimer` 类与挂载点整删，输入栏到「发送⇄停止」
  单状态为止；对话页测试改为负断言（`findsNothing` ×2）。
- **删语音转写**（需求 36，D8/D9）：删实现 5 文件（`voice_input_controller` /
  `record_voice_recorder` / `open_ai_compatible_transcription_service` /
  `voice_recorder` / `lf_recording`）+ `lf_chat_input` 录音行与麦克风钮 +
  `lf_chat_bubbles` 的 `VoiceMessage`；接线 8 处（controller / page /
  localfit_app / app_router / main）同步拆除；`pubspec.yaml` 删 `record` 与
  `record_linux` 覆盖整块；`AndroidManifest.xml` 删 `RECORD_AUDIO`（隐私审计
  测试同步改为只允许 INTERNET + ACTIVITY_RECOGNITION）；`docs/08` §4/§6 与
  `docs/21 §5.7`（结构树 / 语音表 / 测试 Key）同步。**D8 遗留兼容**：
  `audioPath`/`durationMs` 列与 `kind=voice` 保留只读，历史语音消息降级为
  普通用户气泡（键 `ai-chat-voice-<n>` 仍在），仓储测试与 UI 测试各留一条
  往返/降级断言。
- **拍照直通**（需求 37，D12）：可达性审计证实 `/meal-recognition` 仅
  `app_router.dart` 一处 push。`cta-photo-scan` chip 改为直接调相机
  （`_openCameraAndPushScan`：`prepare.select(camera)` → 带图 `push(extra:
  PreparedMealImage)`）；`FoodScanPage` 新增 `initialImage` + `autoStartCamera`
  （帧后 `_startDirectRecognition`），落地屏（`_ScanEmptyState` + 拍摄/相册
  两钮）整删，空态深链兜底只剩一枚「拍摄照片」主钮（`_selectAndAnalyze`）；
  识别/确认/剩余(餐前餐后)/`cta-rescan`/相册路径（对话图片按钮）全保留。
- **测试**：33 处 `scan-gallery→scan-camera` 迁移；7 个测试文件重写为
  「选图即识别」时序（懒加载 ListView 折叠线教训：默认 800×600 下草稿卡
  在构建区外，finder 永远匹配不到——905×1600 视口或逐帧泵到结果态）；
  新增 3 条 P10 断言（无落地菜单 / `initialImage` 进页即识别 / fake picker
  记录 `MealImageSource.camera`）+ 遗留语音气泡降级断言。
- **变异 5/5 红证**：相机→相册 ⇒ 来源断言红；选图不自动分析 ⇒ 直通测试红；
  `autoStartCamera` 短路 ⇒ 带图测试红；落地屏加回 ⇒ 删除断言红；
  `initialImage` 丢弃 ⇒ 带图测试红。源码还原后全量门禁 **EXIT=0**
  （format+analyze+全测 1944 过 / 3 skip / 0 败）。
- **设备走查（emulator-5556 / LocalFit_API35）**：AI 对话输入栏无麦克风钮、
  无免责声明（uiautomator 语义树负查证）；`拍照识别` chip 直开系统相机
  （`com.android.camera2`），无落地菜单；快门→Done 回到拍照页带图
  （`已拍摄 · 1200 × 1600 · 74 KB · JPEG`），识别自动开始，无 AI 配置时
  诚实报错「AI 配置不可用，请在设置中检查 Base URL、模型和 API Key。」；
  页面无「从相册选择」钮。

### P11 真实端点全功能实测与修复（用户授权，key 不落盘）

**状态：已交付（2026-10-07）。** 证据：`docs/evidence/2026-10-05-ai-live-endpoint.md`。

- **工具**：`test/live/ai_live_endpoint_test.dart` —— 驱动 App 真实服务类跑全部
  六出口 + 错误分档；`LF_LIVE_KEY` 不设置时整组 skip（门禁默认零真实请求，
  `+0 ~8: All tests skipped` 已验证）。
- **路由发现**：免费组 key 无任何可路由模型（404/503）；付费组仅 `gpt-6-astra`
  可路由并全程使用。「/models 列表 ≠ 可用模型」如实记录。
- **六出口判定**：对话流式 ✅（两种推理档都被接受、空回复兜底 0 触发）；chat-edit
  代表集 ✅（最终轮 matched=4/6 applied=4/6，跨轮 5 种 action 落库成功）；训练计划
  ✅（5/5 轮）；连通性/模型拉取 ✅（401/404/不可达分档全对）；餐图识别 ❌（该上游
  视觉通道 4/4 轮 45s 超时，无一次 HTTP 形态错误——上游可用性，非接口缺陷）；
  工作台 ✅（合同修复后 dish-nutrition/daily-menu-plan/meal-pairing 连续通过，
  menu-normalize 无干净轮，列诚实边界）。
- **真缺陷修复（2 项，均在「接口形态不匹配」类）**：
  1. 五个工作台 prompt 模板与 decoder 合同脱节（模型按旧模板猜不出键集，
     4/5 合同被整单拒绝）→ 模板逐一枚举全部键/类型/枚举 + `promptVersion -2` +
     重跑固定评测集更新 `_pinned` 哈希 + menu-normalize 任务层注入 `today=`。
  2. chat-edit 协议段硬化：`edits` 非空、不追问确认、先核对命令清单
     （`renderProtocol()`；decoder 契约不变，docs/23 §2 已记）。
- **收尾**：tmp 凭据文件已删；全仓 `grep -r` key 字符串 0 命中；全量门禁
  **EXIT=0（1944 passed / 11 skipped）**。

### P12 收尾（每包都在做，这里做全局）

> **状态：已交付（2026-10-07）**——全量门禁 EXIT=0（1944 passed / 11 skipped）；
> `--rerun-tasks` 重编译 0 警告；变异抽查 3/3（并修正 `chat_edit_registry_test`
> 一处「`contains('10')` 假钉」测试缺陷，硬化为字面断言；逐包变异电池未全量复跑，
> 诚实边界记入证据）；设备走查 360dp 逐页 + 2.0× + 暗色，28 张截图归档
> `docs/evidence/2026-10-05-ui-ux-remediation/`，0 新缺陷；arm64 混淆交付包重建
> （EXIT=0）+ 产物核验：正向 36/36（1 条初判 MISS 判明为引用了 P8a 前旧文案，
> 现役串命中——改判据留档）、负向 12/12（含五个 `prompt-1` 旧版本号确已不在
> 二进制里）、`libapp.so` 9,700,232 B 与 docs/28 基线差分证明「不是上一版」；
> 文档同步（docs/21 §5.1/§6.1/§6.2 P9 as-built、docs/24 §6/§7 日期注、INDEX、
> DECISIONS **ADR-027**、GOAL、STATUS、记忆）。证据：
> `docs/evidence/2026-10-07-p12-global-wrapup.md`。

- 全量门禁 + 全量变异复跑；`--rerun-tasks` 强制重编译确认 **0 警告**；
- 设备走查（360dp 逐页 + **2.0×** 抽查 + **暗色**抽查），截图归档到
  `docs/evidence/2026-10-05-ui-ux-remediation/`；
- **arm64 混淆交付包重建**（`--obfuscate --split-debug-info=…`）+ 产物核验
  （正向标记、新中文文案按 **UTF-16LE** 查、负向对照、改动面 Key；
  `libapp.so` 需先解 DEFLATE；**缺席要先问「那一支是否根本不可达」（TFA）**）；
- 文档：`docs/21`（新增/重写的 §3.10 输入框、§3.8 按钮族新增变体、§5.1 今日、§5.3 菜单、
  §5.6 我的、§5.7 AI 对话、§6.2 裁决、§3.11 食物卡（D14 口径改写））、`docs/INDEX.md`、`docs/DECISIONS.md`（ADR 追加）、
  `GOAL.md`、`docs/08`（权限）、`docs/23`/`docs/24`（若接口形态变）、证据文件、
  `STATUS.md` 顶部新 `Updated:` 条目、记忆（`localfit-ui-display-review` 第八轮）；
- 按用户需求**不发布、不推送、不提交**。

---

## 5. 交付与验收（本方案的完成定义）

1. §1 表里 39 条**逐条**有落点、有测试或设备证据、有变异（凡新增断言）；
2. 门禁 `EXIT=0`（format 0 changed / analyze 0 issue / 全测试通过），变异全部捕获；
3. 设备走查 360dp 逐页 + 2.0× + 暗色，坐标级证据（像素/边界）归档；
4. arm64 交付包重建 + 产物核验通过（含差分证明「不是上一版」）；
5. 文档同步完成（§3 纪律 6），且 `docs/INDEX.md` 反映最终状态；
6. 真实端点实测报告（P11）含失败项与未覆盖项；
7. `STATUS.md` 与记忆更新；未发布/未推送/未提交；
8. **食物库人工审核**（P8b）：覆盖率对账 **100%**（v5 每条 id 都能追到一条账本裁决），
   `reports/review_report.md` 如实分列「逐条核验 / 族批确认 / 存疑」，
   `foods.v5.json` 幂等可重建（同一账本两次生成逐字节相同）。
   **核验方式不得混称**——族批确认过的不许写成逐条核验。
   **✅ 已满足（2026-10-07）**：覆盖率 100.0%（49,464 / 49,464），报告分列
   逐条核验 18,920 / 族批确认 30,544 / 存疑 0，幂等由 `test_apply_review.py` 连跑两次
   逐字节断言。

## 6. 风险、诚实边界与不做的事

- **步数在模拟器上无法端到端验证**（AVD 无计步传感器）⇒ P9 的设备证据只能是
  「无传感器时诚实空态」，真机行为列入待验证项；`TYPE_STEP_COUNTER` 的**重启基线**
  逻辑只能用 Dart 侧 fake + 单元测试覆盖，不能声称真机通过。
- **菜品图片与步数引入 `19→20` 迁移** ⇒ 必须验证**旧库升级后不丢数据**、
  备份/恢复往返、清除逻辑；任何 DROP 前先备份数据库。
- **人工审核的价值是真的，成本也是真的**：上游 FoodCalu 既无品牌列（所以**没有外部对照源**），
  审核的权威性只能来自**账本本身**（每条裁决可点名到时间 / 前后值 / 来源），不来自任何外部比对。
  49,464 条逐条核验是 40–70 小时的真实工时；族批可压缩按键数，但**报告里不许写成逐条**。
  **本项不阻塞 P9–P12**：工具与账本（P8b-1）先交付，v5 与 App 升级（P8b-2）以覆盖率 100%
  为出口；未达 100% 时 App 继续用 v4（不出现「审了一半的种子」这种中间态）。删除条目会让
  canonical 条数下沿变动（GOAL §7 的 5 万目标本就未达，ADR-025 已如实记录），条数变动必须
  同步 `data_attribution.dart` 与既有断言。**实际工时**：账本落账由 47 批驱动完成（脚本在
  `E:/AI/Zcode/tmp/`），族批把按键数压到可行范围；本轮**改营养 0 条**（审核边界只含
  名称/品牌/非食物/重复，营养仅在可疑时改且必须填 source）。
- **推理开关只在 chat 协议实测**（三种写法均已实测可用）；`responses`/`anthropic`
  两种协议是否接受同一字段**未实测** ⇒ 默认不发，列入待验证。
- **上游延迟 12–22 s** 是链路性质，App 侧只能选「关闭推理」减轻，不能消除；
  45 s 的 `receiveTimeout` 在长任务（工作台/训练计划）上可能需要按出口放宽——**按实测决定，不预先放宽**。
- **不做**：不新增除 `image_picker`/`file_picker`（已在依赖内）之外的任何依赖；
  不改 AI 合同与 decoder 语义；不删 `docs/21`；不物理搬移被大量引用的旧方案（§0.4）；
  不发布/推送/提交；不动业务逻辑之外的领域计算（BMI/BMR 公式零改动）。

## 7. 「goal 引导文字」

**唯一副本在 `GOAL.md` §0**（本节不再复制一份——两处副本必然漂移，本轮已经修过一轮计数漂移）。
要点：按 39 条需求 / 14 条裁决（D1–D14）/ P0→P12 逐包实施；每包独立过门禁 + 隔离变异 +
360dp 设备走查 + 活文档同步；权威源只有 `docs/29`、`GOAL.md`、`docs/07`、
`docs/21` + `ui设计/pages/*.html`，`docs/11/22/25/26/27/28` 无规范效力；视觉包先出 HTML
设计稿（放 `ui设计/remediation/`）；**食物库全量人工审核**（§P8b）以覆盖率 100% 为出口；
真实 AI 请求只在 P4/P11；不发布、不推送、不提交。
