# LocalFit AI 2.0 Goal

> 这是 LocalFit AI 2.0 的长期目标和执行规则。
> 当前切片、真实验证和中断交接只看根目录 [`STATUS.md`](STATUS.md)。
> 详细产品、数据、AI、菜单、食物库和验收契约见 [`docs/07-localfit-2.0-development-spec.md`](docs/07-localfit-2.0-development-spec.md)。
> **UI 的唯一依据**见 [`docs/21-ui-redesign-spec.md`](docs/21-ui-redesign-spec.md)；本阶段改造方案见 [`docs/29-ui-ux-remediation-plan.md`](docs/29-ui-ux-remediation-plan.md)，文档地图见 [`docs/INDEX.md`](docs/INDEX.md)。

## 0. 当前目标（2026-10-05 起）：界面与体验治理

> **本阶段执行细则**：`docs/29-ui-ux-remediation-plan.md`（39 条需求 / 14 条裁决 D1–D14 / 工作包 P0–P12）。
> **文档地图**：`docs/INDEX.md`。**本节是「goal 引导文字」的唯一副本**（`docs/29` §7 只指向这里，避免两处漂移）。

### 0.1 现在做到哪、下一步做什么

- **P0（文档治理）已完成**：`docs/INDEX.md` + `docs/history/2.x/README.md` + 6 份已完成方案书的状态横幅
  + `GOAL.md`/`STATUS.md` 指针回改 + `docs/21 §3.11` 的 2026-10-05 状态块。
- **P1（个人资料页三件）已完成并 verified（2026-10-05）**：`/profile-edit` 入口 `go` → `push`
  修掉 `GoError: There is nothing to pop`（入口 push + `onClose` 单一出口）；身高/年龄/性别可编辑
  （页名「编辑个人资料」，落既有 `Profiles` 三列、零 schema 变更）；右上关闭钮。设备走查顺带
  发现并修掉「编辑页不回填当前目标 ⇒ 保存静默覆盖目标与目标体重」的数据事故。门禁 `EXIT=0` /
  1839 passed / 3 skipped；变异 6 条全 RED 且 sha256 还原。证据 `docs/evidence/2026-10-05-p1-profile-edit.md`。
- **P2（健康数据图形化）已完成并 verified（2026-10-05）**：HTML 设计稿先行
  （`ui设计/remediation/我的-健康数据.html` + 360dp 评审图），原生落成三件图形
  （BMI 分档刻度尺 / BMR 区间指示 / 饮水进度环，`lib/app/design/widgets/lf_metric_gauge.dart`），
  口径单独在 `lib/features/settings/domain/health_metric_bands.dart`；**空态一律不给假信息**
  （不画指示器、不放档位徽标）。**设备走查又抓出三个真实缺陷并修掉**：超重段画成近黑色、
  2.0× 刻度数字被上下裁一半、档界数字按「剩余空间」摊被挤向中间（2.0× 下偏 26px）；
  并顺带修掉「在今日页记饮水后切回「我的」仍显示旧值」（切 tab 回来会重读派生数据）。
  门禁 `EXIT=0` / 1856 passed / 3 skipped；变异 16 条全 RED 且 sha256 还原。
  证据 `docs/evidence/2026-10-05-p2-health-metrics.md`。
- **P3（成就分级与进度）已完成并 verified（2026-10-05）**：在 P2 的同一份设计稿里补「行卡 + 铜/银/金
  分级 + 进度环/条」段并重渲染 360dp 复核；原生落成
  `lib/features/settings/domain/achievement_levels.dart`（等级与计数口径、目标值 7/7/10/30 单源）与
  `lib/app/design/widgets/lf_achievement_row.dart`（`LfMedalTier` 三档色板 + 勋章环 + 名称 `scaleDown` 兜底 +
  `n/目标`），`settings_page.dart` 只做「业务枚举 → 设计枚举」映射；**纯展示层派生，不落库、不改 schema**。
  设备走查用 App 自己的「记录一餐」+ 逐日推进模拟器日期真造出 1/7、1/30、7/30、7/7 已解锁与银档（4/7–6/7）：
  条填充/条轨恒等于 `progress`、环弧恒等于 `progress×360° + 圆头帽`、解锁内盘 = 等级色 token 逐字节相等。
  门禁 `EXIT=0` / 1867 passed / 3 skipped；变异 17 条全 RED 且 sha256 还原（M04 补出「计数上限」断言、
  M17 从等价变异补成两条名称兜底断言）。证据 `docs/evidence/2026-10-05-p3-achievements.md`。
- **P4（AI 配置统一 + 连通性测试 + 模型拉取/选择 + 推理开关）已完成（2026-10-05）**：
  设置页 AI 组收敛为单行入口 + 配置弹层（协议 / Base URL / 模型 / `ai-config-probe` 连通性测试带
  分档文案与内联结果 / `/models` 拉取后 `ai-model-search` + `ai-model-option-<n>` 点选回填 /
  `ai-reasoning` 推理开关 / API Key 留空保持 + `ai-key-clear` 二次确认）；API Key 全程不进配置表
  （`AiApiKeyStore`，同 P3 前口径）。推理开关 = `AiReasoningMode`（NULL→disabled 产品默认），
  Chat Completions 关闭推理时发 `thinking: {"type": "disabled"}`，Responses/Anthropic 诚实不发；
  非流式 `content` 空而 `reasoning_content` 有货、或整条流只有推理增量 ⇒ 可解释错误而非空气泡。
  schema 19→20（`ai_provider_configs.reasoning` 可空列，存在性守卫 + from>=2 下界）。
  门禁 `EXIT=0`；变异 17 条全 RED 且 sha256 还原（M14 钉 `fromStorage` 的 NULL→disabled，经 v20 迁移测试）。
  证据 `docs/evidence/2026-10-05-p4-ai-config.md`。
- **P5（动作库卡片 / 详情抽屉 / 弹窗流畅度）已完成（2026-10-06）**：HTML 设计稿先行
  （`ui设计/remediation/训练-动作库.html` + 360dp 评审图）。原生只动
  `lib/features/training/presentation/exercise_library_page.dart`：卡片分类串 `'肌肉 · 器械'` 移到
  **右上角并与图标同行**（自建徽标固定在分类串左侧）、删掉把行高撑到 168 的垂直 `Spacer`、
  图标↔标题改显式 8dp、标题↔标签行 34dp 压到 6dp；`mainAxisExtent` 由固定 168 改为
  **实测内容高 + 12**（`_cardExtent(context)` 按 `textScaler` 逐项算），实测 1.0×/360dp
  **124.2dp**（≤140 达标）、2.0×/320dp 158.4dp 均无溢出；`_MiniTag` 改单行省略（2.0× 双行会把
  固定行高撑爆 71px）。详情抽屉换 `AppSheet.showCustom`（动效统一 `AppMotion`），替代动作由裸
  `ListTile` 改成 **可点行卡**（图标圆 + 名称 + 难度/器械 chip + 右箭头），点了**原地**换该动作详情
  （不叠层、不关窗），并补 `ConnectionState.waiting` 骨架行（此前加载中先闪「暂无替代动作」）。
  **流畅度真凶**：`repository.search(...)` 建在网格 `build` 里 ⇒ 键盘 inset/字号/主题任何重建都重查
  DB 并回骨架屏；提到 `initState` 由 state 持有 + 搜索加 **300ms 防抖**
  （`ExerciseLibraryPage.searchDebounce`，肌群 chip 走 `_commitQueryNow()` 立即提交），
  查询真变化时网格换 `ValueKey` 回顶部。门禁 `EXIT=0` / 1902 passed / 3 skipped / 552 files 0 changed；
  变异 2 条全 RED（M1 `Spacer` 加回 ⇒ 2 条红；M2 future 移回网格 `build` ⇒ 3 条红）且 sha256 还原。
  测试 5 → 15 条。证据 `docs/evidence/2026-10-06-p5-exercise-library.md`。
- **P6（记录页间距 / 记录一餐 FAB / 今日推荐卡图形化）已完成（2026-10-06）**：hero 与下一餐卡之间补
  `LfDimens.pagePadding` 16dp（设备实测 **16.0dp 整**）；FAB 底距 80→96dp、阴影 `0 4px 12px α30%` →
  **`0 6px 20px α40%`**（38% 不在 docs/21 §2.4 白名单，取最近档 40 并留档注意三；底栏顶分隔线为既有件）。
  下一餐卡**删通勤行**（数据与手动通勤对话框保留，入口移到食材库设置行）并把两句散文换成**图形事实行**
  `next_meal_facts_row.dart`（证据徽标 / 营养完整度 / 候选 n/m / 快照日期；没有的事不画）。
  **2026-10-13 更正（docs/32 §3 D10，T8 落地 / T16 复核）**：当初「保留」的那份数据与对话框也在
  第五轮通勤全链路下线里删掉了——列随 schema 23→24 drop、设置行与对话框下线、AI 快照段移除；
  下一餐卡从那以后一直没有通勤行。
  随包修真缺陷：`paddingOf` 在 `extendBody` 的 MediaQuery 里取到 max(手势区, 底栏高) ⇒ 换 `LfInsets.bottom`
  （训练页 FAB 同款一并修）。门禁 `EXIT=0` / 1915 passed / 3 skipped / 555 files 0 changed；
  变异 12/12 RED 且 sha256 还原；设备走查七项（**2.0× 未取得（如实）**：该 API-35 镜像 `font_scale 2.0`
  持久不生效，P12 用窗口化模拟器重试）。证据 `docs/evidence/2026-10-06-p6-record-page.md`。
- **P7（食堂目录：滚动保持 / chip 选中态 / 菜品行 / 菜品图片）已完成（2026-10-06）**：设计稿
  `ui设计/remediation/食堂-地点与菜品.html` 先行。滚动保持改 stale-while-revalidate（`_windowsByVenue` 缓存
  + 预取全部地点 + 有旧数据不进 `SliverFillRemaining` 加载分支 + 2dp 细进度条），设备实测切地点 scroll
  **803→803（Δ=0px）**；chip 选中态删圆点与极淡底色，改 2px 主色描边 + 主色文字 + 轻抬升（44dp 不变，
  `docs/21 §3.12` 同批改写）；菜品行加序号圆/44dp 缩略图行头 + stationName 副行 + 8dp 行距 + 1px 分隔线
  （首行无线）；菜品图片 schema **v20→v21**（`image_path` + `steps_daily` 供 P9）+ `DishImageStore`
  （原子写/扩展名白名单/目录前缀守卫）+ 表单「拍照/从相册选/移除照片」+ `setImagePath` absent 语义，
  设备端到端（相册→预览→保存→行首缩略图上屏）通过。
  **★ 设备走查抓到 P0 缺陷**：升级路径首启崩 `duplicate column name: image_path`（开发期该列曾在
  `from < 20` 分支，中途构建的库 `user_version=20` 但列已在）⇒ 守卫改 **`pragma_table_info` 列存在性**
  并嵌在表存在性守卫内（pragma 对不存在的表静默返回空），补 v20+列已在 fixture 回归 + 变异 P7-3 钉住。
  **教训：版本号只说明「跑没跑过链」，说明不了「列在不在」。**
  门禁 `EXIT=0` / **1940 passed / 3 skipped** / 560 files 0 changed；变异 **18/18 RED** 且 sha256 还原；
  设备走查 5556 七项。证据 `docs/evidence/2026-10-06-p7-canteen.md`。
- **P8a（食物库卡片与抽屉呈现一致化）已完成（2026-10-06）**：设计稿
  `ui设计/remediation/食物库-卡片与抽屉.html` 先行。卡片首行三件（40dp 图标 / 名称 / 44dp 环）改
  `CrossAxisAlignment.center` 共心中线——**环下口径行必须移出首行**：留在环那一列时该列高
  44+2+14 = 60dp，`center` 居中的是「整列」⇒ 图标与名称落到 30dp 中线而环心仍在 22dp（差 8dp）；
  移出后独立成行、右对齐与环同右边线，写 `kcal/100g`（缺热量写「无热量数据」）。宏量**恒三格**：
  新函数 `macroGramsOnScreen` 显式三态（`null`（上游没给）与 `0`（上游把没填写成 0）都写 `0g`），
  取代旧 `nutrientOrMissing` 的「0 当缺失」（那会让缺项不占位、剩下两格各自撑宽 ⇒ 三列逐行错位）；
  **热量那一格保持事实判断**（`kcalOrMissing`：null/0 都当没有 ⇒ 环里 `—`），两套口径并存、各自成立；
  「这一条不完整」由「营养不完整 · 不可加入计划」标记承担。满刻度上屏（需求 23）：`FoodDensityScaleNote`
  在列表头写一句「环 = 每 100g 能量密度 · 满刻度 900 kcal/100g」，数字由 `kFoodDensityFullScaleKcal`
  插值（改常量这句话跟着变），不逐卡重复。品牌带框 chip 左下（`LfBadge.outlinedBrand`：透明底 +
  1px `mint-300` 实线 + 品牌字，与 `dashed` 同源色）+ 自建/内置右下；**描边档的 1px 边从内边距里让出**
  （`Container` + `padding 7/3` + `Border.all`；`DecoratedBox` 只画边不占位会矮 2dp）⇒ 两档逐像素同高。
  卡底内距 12 → 8。顶栏：`LfTopBar` 加 `showBack`/`showTitle`（**默认 `true` = 现状不变**，共享件不得
  全局删），食物库那一条 60dp 顶栏**整条撤掉**，自建食物入口搬到搜索框右侧（`LfCircleIconButton`）；
  页头抽成共享件 `food_library_header.dart`（两条数据路径此前各写一遍，也把 `food_library_view.dart`
  从 504 行压回 466 行、修回 500 行预算）。详情弹层：环 88/8 → **56/6**，整段「并排/竖排」
  `LayoutBuilder` 与 `_macroRatios()` 删除，**占比行整行删除**，只留克数行、缺值 `0g`。骨架
  `FoodCardSkeleton` 逐行同步（实测口径行 10→14、宏量行 12→17 ⇒ 骨架 127dp → **136dp** = 真卡高，
  新增不变量用例钉死）。**同批改写 `docs/21 §3.11`（按 D14 整节重写）**，并把「上游把『没填』写成 0」
  的数据事实移到 `docs/07 §5.8`（实测 `kcal==0` **206** 行、`protein==0` **4,151** 行、`carbs==0` 1,273 行、
  `fat==0` 6,358 行；`food_seed_importer.number()` 拒绝非有限/负值 ⇒ JSON 里没有 `null` ⇒
  **领域层区分不了「真的 0 克」与「上游没填」**）。
  门禁 `EXIT=0` / **1950 passed / 3 skipped** / 561 files 0 changed / analyze clean；变异 **17/17 CAUGHT**
  且 sha256 还原（两条初判 SURVIVED 属「变异本身不合法」：一条变成编译错误、一条语义等价，重写后转红）；
  设备走查 `emulator-5556` **11 项**（含**远跳拖滑条到底不 ANR**、2.0×、暗色、暗色+2.0× 叠加）。
  证据 `docs/evidence/2026-10-06-p8a-food-library.md` + `docs/evidence/screenshots/p8a/`。
  当前切片与交接**永远**以 `STATUS.md` 的 `Active Slice` / `Next Command` / `Last Handoff` 为准。
- **P8b-1（食物库审核台与账本）已完成（2026-10-06）**：`tool/food_seed/review/` 四件
  （`export_display_preview.dart` / `review_lib.py` / `review_server.py` / `review_ui.html`）+ 三个测试
  （80 / 98 / 16 断言）+ `README.md`；**零新依赖、不进 App 包**（Python 标准库 `http.server`）。
  **本包交付的是工具与账本，未做任何人工裁决**（真账本至今不存在，`--stats` 已裁决 0 / 49,464）。
  ①**上屏预览同源**：`dart run` 调 App 自己的 `splitFoodName` / `normalizeFoodName` /
  `foodDisplayStrings` 产出 `reports/display_preview.jsonl`（9.69 MB / 49,465 行含 `_meta`），
  `--check` 逐字节比对、陈旧退 1；审核台启动校验预览 `seed_sha256` == 当前种子，不符**拒启动**。
  **禁止用 JS/Python 重写拆分规则**（两份实现必漂移 ⇒ 人审的是一张并不存在的卡）。
  **开工第一步实测**：`dart run` **能**解析纯 Dart 的 `lib/utils/*`（1.5 s），但**装不下 Flutter**
  （import `food_card.dart` 即 `dart:ui` 整片编译失败）⇒ D14 显示口径抽成**不含 Flutter** 的
  `lib/utils/food_display.dart`，`food_card.dart` 留 `export` 转发（历史导入点零改动）。
  同源**双证**：(a) Dart 侧手写 SHA-256（FIPS 180-4，零新依赖）逐字节等于 Python `hashlib`
  （`a36bb8bf6ea1…`）；(b) `test_review.py` 里另写一份 Python 版拆分规则，拿真实种子前 4,000 行
  与 Dart 预览逐字段比较全等。②**键盘八动作**（`1`–`8` + `b` 族批 + `j`/`k`；编辑框里 `Enter` 提交
  该字段的动作、`Esc` 失焦、数字照常打字）。③**可疑队列八个标记只做排序与预填**——真种子实测
  `han_head_frequent` **23,301**（D6 点名「只有人工能关」的缺口：纯汉字品牌前缀没有标记可与产品名
  分开，阈值降到「≥6 次」就混进 `迷你`/`理想`/`特惠`/`有限会社`/`日本产`，自动规则**主动放弃**）、
  `head_ascii` 7,127、`nutrient_zero_or_missing` 7,909、`kcal_macro_mismatch` 1,244、
  `slash_or_number_run` 1,243、`near_duplicate` 42、`brand_unresolved` 34、`duplicate_token` 3；
  队列 **17,833 组**，≥2 条的 5,402 组覆盖 37,033 条（最大组 288 = `明治`）。
  ④**账本 `reports/review_ledger.jsonl` 是唯一权威证据**：追加式、只增不改（撤销也是**再加一行**
  `revert`，可重放）；`review_mode` **服务端判定**（单条 `item`；`batch` 只在「提交的 id 恰好等于
  同首词全部待审成员的集合」时给，不成立**整批拒绝 400 且一个字节不写**、**不降级记 `item`**——
  「族批确认过的不许写成逐条核验」是 docs/29 点名的混称）；`edit_nutrition` 缺 `source` 服务端补
  「人工估值」；写入前整批 `validate_row`。⑤**断点续审**：`review_cursor.json` **派生自账本**
  （删掉也不丢进度）；`--stats` 五档（`已裁决 = 逐条核验 + 族批确认`，存疑是子集不计分母）；
  `--only <标记>` 单列工作面、不冒充全库进度。⑥**实测修掉四个缺陷**：键盘文案与实现矛盾
  （屏上说「先填框再按数字键」而框里数字被吞 ⇒ 照文档做静默无效、改名就这么丢过）、焦点按对象比
  字符串致 `j`/`k` 移动无可见反馈、**撤回打在「当前高亮行」上而那行在裁决瞬间就已退出队列 ⇒
  先 `6` 删除再 `8` 撤回什么也没发生、条目再也回不来**（改 `last_decidable_id()` 撤账本最近一条
  生效裁决）、族批守卫互相掩盖（见下）。
  **★ 门禁 `EXIT=0`（1962 passed / 3 skipped、format 563 files 0 changed、analyze No issues found）**；
  **变异 24/24 CAUGHT 且逐字节还原**——首轮 18/24，六条未捕获逐条查清：**P8b-13/14/15 是测试缺陷**
  （旧用例的三类输入在同一仓库里各自同时撞两三道守卫 ⇒ 拆掉任何一道仍 400、断言照绿；守卫重叠时
  只断言「会被拒」等于没测），修法是给每道守卫各造一个**只有它能拦住**的干净输入 + 新增
  `test_batch_guards_isolated`；**P8b-12 的「同首词」唯一独立可观察的效果是它给的诊断**（ids 里有
  两个首词时任何一个首词的待审集合都不可能等于 ids，拒绝本身已被「必须是整组」包含）⇒ 把给操作者
  看的那句理由一起钉住；**P8b-23 是编译错误**（`import …; library;` ⇒ library 必须在最前；按纪律
  **编译错误不算捕获**，与 P8a 同一个坑）⇒ 改成 `library;` 之后再 import 由静态契约抓；
  **P8b-25 断言只查「名字在文件里出现过」**而它们在调用点也出现 ⇒ 改成解析**声明块本身**逐项对账。
  **★ 真键盘走查未闭环（如实记录）**：浏览器控制面板的**操作系统级**按键注入到该面板**不产生
  `keydown`**，驱动与验证走的是**页面内** `Event` 派发 ⇒ 只证明了页面处理逻辑，真实物理键盘端到端
  待有人首次真正开审时做（账本第一行就是凭据）。浏览器写入全部落在**沙箱副本**
  （`E:/AI/Zcode/tmp/p8b-sandbox`），**真仓库 `reports/review_ledger.jsonl` 至今不存在**。
  证据 `docs/evidence/2026-10-06-p8b1-review-workbench.md`。
  当前切片与交接**永远**以 `STATUS.md` 的 `Active Slice` / `Next Command` / `Last Handoff` 为准。
- **P9（今日页：体重周/月视图与选日期 + 本机步数）已完成（2026-10-07）**：需求 31–34。
  「添加」按钮（`dashboard-weight-add`）取代整卡 onTap；周/月分段切换（标题「本周体重 ⇄ 体重趋势」、
  子标题联动，月视图对既有 30 天数据按周分箱取均值）；`WeightEntryDialog` 加日期字段
  `weight-entry-date`（默认今天、可翻月、未来禁点，**改日期按目标日已有记录重播种**——有则回填、
  无则清空，不清空会把今天的数字写成历史日）。步数 = **仓里第一个 MethodChannel**：
  `MainActivity.kt` `localfit/steps`（read/requestPermission/openAppSettings）+ `StepsRepository.syncToday`
  （重启基线：计数值变小⇒重设；**同日二次同步按 local_date UNIQUE select-then-update 而非按 id
  upsert**——id 每次新生成，按 id upsert 第二次必撞 UNIQUE，这个真缺陷是测试先抓出来的）；不可用
  （无传感器/未授权/没读到）**一个字不写库**。卡片三态：可用 / 未授权（点卡片拉系统权限）/
  无传感器（诚实空态）。权限 ACTIVITY_RECOGNITION 三处同步（Manifest、docs/08、隐私说明测试）。
  门禁 `EXIT=0` / **1994 passed / 3 skipped** / format 0 changed / analyze 0；新增 31 条测试；
  变异 **10/10 killed** 且逐字节还原。设备走查（emulator-5556，x86_64 debug 包）：步数
  未授权→系统弹窗→Allow→「这台设备没有计步传感器」两态真机闭环；周↔月标题双向；选 09-30→
  字段清空→71.5 保存→「体重已保存到 9 月 30 日。」+ 本周卡「↑ 0.5」；重开改回 09-30 字段回填 71.5。
  诚实边界：AVD 无计步传感器 ⇒ 真机读数与重启基线由 fake 单测覆盖、不能声称真机通过。
  证据 `docs/evidence/2026-10-07-p9-dashboard.md`。
- **P10（AI 对话与拍照：删免责声明 / 删语音转写 / 拍照直通）已完成（2026-10-07）**：
  需求 35–37。免责声明整删；语音转写整族删除（实现 5 文件 + 录音行/VoiceMessage +
  接线 8 处 + `record`/`record_linux` 依赖 + `RECORD_AUDIO` 权限，D8 只读兼容保留
  旧语音消息列与降级气泡）；拍照直通（chip 直调相机 → 带图 push → `autoStartCamera`
  自动识别，落地屏整删，空态兜底只剩「拍摄照片」主钮）。门禁 `EXIT=0` /
  **1944 passed / 3 skipped** / format 0 changed / analyze 0；变异 **5/5 红证**且逐字节
  还原；设备走查（emulator-5556）四项全过（无麦克风无免责声明 / chip 直开系统相机 /
  Done 带回图自动识别诚实报错 / 无「从相册选择」钮）。
  证据 `docs/evidence/2026-10-07-p10-camera-direct.md`。
- **P11（真实端点全功能实测与修复）已完成（2026-10-07）**：live 工具
  `test/live/ai_live_endpoint_test.dart`（`LF_LIVE_KEY` 缺省整组 skip、门禁默认零外呼）
  驱动 App 真实服务类实测六出口＋错误分档：对话流式/训练计划/连通性可用（两推理档
  都被上游接受、空回复兜底 0 触发），chat-edit 代表集最终轮 4/6 落库成功，餐图识别
  在该上游不可用（视觉 4/4 轮超时、无 HTTP 形态错误→上游可用性）；上游路由实况=
  付费组仅 `gpt-6-astra` 可路由。真缺陷修复两项（接口形态不匹配）：五个工作台
  prompt 模板补全 decoder 合同键集（`promptVersion -2` + 重跑固定评测集重钉哈希 +
  menu-normalize 注入 `today=`）；chat-edit 协议段硬化（edits 非空/不追问确认/核对
  命令清单）。凭据收尾：tmp key 文件已删、全仓 grep 0 命中。
  门禁 `EXIT=0` / **1944 passed / 11 skipped**（8 条为 live 工具默认 skip）。
  证据 `docs/evidence/2026-10-05-ai-live-endpoint.md`。
- **P12（全局收尾）已完成（2026-10-07）**：全量门禁 **EXIT=0（1944 passed /
  11 skipped）**；`--rerun-tasks` 强制重编译 0 警告；变异抽查 3/3 RED（其间修正
  `chat_edit_registry_test.dart` 的 `contains('10')` 假钉——被「10000」误匹配——
  硬化为字面 `contains('每次回复最多 10 条')`；逐包变异电池未全量复跑，诚实边界
  记入证据）；设备走查 360dp 逐页 + **2.0×** 抽查 + **暗色**抽查（emulator-5556，
  1080×2340 @480dp=360dp），28 张截图归档 `docs/evidence/2026-10-05-ui-ux-remediation/`，
  **0 新缺陷**，走查后 font_scale/night 已还原；**arm64 混淆交付包重建**（
  `--obfuscate --split-debug-info`，EXIT=0）+ 产物核验：`libapp.so` 解 DEFLATE 后
  正向 **36/36**（唯一初判 MISS 判明为 P8a 前旧文案，现役串命中——改判据留档）、
  负向 **12/12**（已下线流程 + 五个 `prompt-1` 旧版本号确不在二进制；`workout-plan-prompt-1`
  应存在且存在）、与 docs/28 基线差分（9,700,232 B / sha `56730a05…` ≠
  9,634,696 B / `d5996ae5…`）证明「**这版不是上一版**」；文档同步：docs/21
  §5.1 P9 as-built 增补 + §6.1/§6.2 步数裁决修订、docs/24 §6/§7 日期注与 P11
  补记、docs/INDEX 日期与状态、**DECISIONS ADR-027**、docs/29 头部与 §P12
  已交付记录。证据 `docs/evidence/2026-10-07-p12-global-wrapup.md`。
  **docs/29 P0–P12 全部交付完毕。**
- **P8b-2（v5 生成与 App 升级）已完成（2026-10-07）**：`docs/29` §P8b 的最后一段。
  账本达 **100% 覆盖**（49,464/49,464：逐条核验 18,920 + 族批确认 30,544，存疑 0），
  `tool/food_seed/apply_review.py` 幂等产出四份（`--require-coverage 100` **且
  `pending == 0`**，缺一条即拒；判据用待审条数本身而非四舍五入后的百分比）：
  `assets/seed/foods.v5.json`（49,444 条，删 20；紧凑序列化）、
  `lib/utils/food_brands_reviewed.g.dart`（3,897 token，**含 `明治` 等自动规则按设计
  排除的纯汉字品牌**）、`lib/features/nutrition/domain/food_seed_count.g.dart`（条数常量）、
  `reports/review_report.md`。**显示层 D13 并集**：`kFoodBrandTokensAll = 自动表 ∪ 人工表`，
  两表分开存放以保住「自动表可从种子重算」这条性质。
  **App 从 v4 原地升级**（docs/29 点名「最容易做错的地方」）：`seedSource='seed-v5'`、
  `legacySources=[v1,v2,v3]` 清理 + `upgradeSource='seed-v4'` **原地 UPDATE**（用户自建/
  改过的行永不触碰、v5 删掉的 id 若被餐次引用则保留旧行），返回
  `SeedImportResult{upgraded, inserted, deleted, keptWhileReferenced}`；四态测试全覆盖。
  **设备走查（emulator-5556 / `LocalFit_API35`，`5558` 全程未碰）**：食物库页脚
  「**全部 49,444 条**」（v4 是 49,464）、卡片品牌 chip 正常上屏、搜 `Nichirei` 的条上屏
  人工表 token `Nichirei日冷`（该 token 由账本逐条裁决而来，v5 行 `brand` 为 null ⇒ chip
  确由显示层剥头得出）。诚实边界：该 AVD 的 Gboard **无中文子类型**（144 locale 里 zh 系 0），
  无法用 `adb input text` 验证「纯汉字人工 token 剥头」，改以等价的 ASCII 人工 token 证据支撑，
  `明治` 由单测覆盖。**过程中自纠一处**：批次4 早期误把 `迷你`（尺寸描述词）并入词表，
  走账本追加 `revert` + 6 条 `approve` 更正。
  **门禁 EXIT=0（1,952 passed / 11 skipped，0 失败；`dart format lib test` 0 changed；`flutter analyze` No issues found）**。收官时另修掉第三个真缺陷：两张生成表的 `sha256` 常量声明超过 80 列 ⇒ 生成物被格式器改写后 `--check` 会 STALE，改由生成器直接输出换行形式（变异红证：改该字面量为全 0 ⇒ `--check` EXIT=1）。
  证据 `docs/evidence/2026-10-07-p8b2-v5-upgrade.md`。
  **`docs/29` P0–P12 全部交付完毕，无剩余开口。**
  **交付件（2026-10-07 追加）**：优化版 arm64 APK 已产出并完成设备验收 ——
  `E:/AI/Zcode/localfit-ai-simple-arm64-release.apk`，**13,915,632 B**，sha256
  `8a98e3fe…40a80`，正式密钥 v2 签名（与上一交付件**同一把密钥**，可直接覆盖升级），
  arm64-v8a 单 ABI。构建口径 `--release --split-per-abi --target-platform android-arm64
  --obfuscate --split-debug-info --extra-gen-snapshot-options=--strip
  --dart-define=APP_VERSION=0.1.0`。**修掉一个真缺陷**：漏加 `--split-per-abi` 时
  `--target-platform android-arm64` **不裁剪其它 ABI 的预编译依赖**，包内混进
  armeabi-v7a/x86_64 的 `libsqlcipher.so`/`libdartjni.so`，白扛 4.5 MB（18,374,994 B）。
  **v4→v5 原地升级的设备实测**：v4 里记录一餐含 v5 会删除的 `seed-fc-48243`（488 kcal），
  不卸载覆盖装 v5 ⇒ 档案/记录保留、库容 **49,445 = 49,444 + 1**、搜 `combos` 仍 3 条
  —— `+1` 即 `keptWhileReferenced` 的语义证据（先删后插、或被引用行一起删这两种错误
  都被真机证伪）。诚实缺口：未在真机 arm64 走查（本机仅 x86_64 模拟器），交付件的
  ABI/签名/对齐/随包资产已用 `aapt2`/`apksigner`/`zipalign` 逐项核验。
  证据 `docs/evidence/2026-10-07-p8b2-delivery-apk.md`。
  **门禁首轮红、两条逐条查清**：(a) **真缺陷**——`ai_egress_evaluation_test.dart` 钉住的
  `menu-normalize` 请求体哈希**每过一个午夜就失效**（正文含 `today=${_localDate()}`，
  该任务未注入时钟 ⇒ 真墙钟；本次跨 10-07→10-08 午夜）。决定性实验：注入
  `FixedAppClock(2026-10-07)` ⇒ 哈希**精确复现**钉住值且全绿，证明唯一差异是日期。
  修法＝注入固定时钟（同文件 `daily-menu-plan` 本来就注入了）+ 重钉哈希；
  **不删 `today=`**（它是 P11 实测的产物，模型无基准日会输出 null 被拒）。
  (b) **负载敏感**——50k 搜索 100 ms 绝对阈值全量并行下超时，单独跑 3/3 通过，
  本轮未改搜索代码，如实记录而不放宽阈值。**修后全量门禁 EXIT=0**
  （1,952 passed / 11 skipped / 0 失败）；本轮唯一改动的 Dart 文件是该测试，
  `lib/`/`assets/` 未改 ⇒ **已核验的 APK 无需重建**。
- **缺陷排查 + AI 测试审查 + 优化版 APK 再交付（2026-10-08）**：按用户指令「检查一下软件有没有
  bug，ai测试有没有问题，然后输出最新优化版apk给我」执行（口径 `docs/11`），三条只读子代理轨
  （AI 测试面 / AI 生产代码 / 数据完整性）+ 我逐条复核后才动手。**修掉 9 条缺陷，每条先红后绿**：
  ①**P0 隐私声明与行为矛盾 ×3**（帮助弹层「不会把照片、体重或饮食记录上传到任何服务器」、
  反馈弹层「当前版本不联网」**且被测试钉住因而长期存活**、关于弹层中文夹英文 `you`）——
  全部改成只陈述真实行为（不主动用 AI 就不外传；用 AI 功能时会把这次所需的那部分发给你
  自己配置的服务），属文案变更，以 **ADR-029** 登记；②**P1 全清承诺落空**：「清除全部本地
  数据」**不删菜品照片**（`DishImageStore` 连 `clearAll` 都没有，聊天图片当年补过同一漏洞）
  ⇒ 补整目录 `clearAll()`（不先建目录）+ `DishImageStoreRef` 窄接口接线，**变异验证**（注释掉
  调用即红 `Expected: <1> Actual: <0>`），以 **ADR-030** 登记；③**P2 双击真的写两份**：
  任务卡 `onConfirm` 是 `VoidCallback?` 把异步 Future 丢了 ⇒ 训练计划双击插两条，
  类型改 `Future<void> Function()?` + 卡片 `_confirming` 关按钮（红证 `Expected: <1> Actual: <2>`），
  以 **ADR-031** 登记；④**P2 静默半写**：每日推荐确认前候选被换批 ⇒ `ArgumentError` 抛穿、
  一条提示都没有（补 `on ArgumentError` 如实报部分写入数）；⑤**P2 界面死路**：克数清空/输
  非法字符回填 `"NaN"` 且 `±` 一起卡死；⑥**P3** 价格 `NaN`/`1e400` 过校验后在提交时炸成通用
  「保存失败」；⑦**P3 谎报**：清除失败提示「数据未受影响」（其时行事务已提交、数据其实已删）。
  **AI 测试审查**：5 条出口 `requestSha256` 与 4 个 `templateSha256` 被**逐字节独立重建全部命中**
  ⇒ 钉值本身没错；与时间有关的只有 `today=`/`date=` 且都已注入时钟；新查出并修掉一类
  **跨时区脆弱**（固定时刻写成 `DateTime.utc(...)` 的巧合字面量，经 `.toLocal()` 后本地日期
  随机器偏移变 ⇒ 美东/美西机器钉值无端变红），四处统一改 `DateTime(y,m,d,12).toUtc()`
  （本地墙钟正午，任何时区往返恒等，本机同一瞬间 ⇒ **钉值一个都没变**），以 **ADR-032** 登记；
  **诚实局限**：该类脆弱无法在单时区机器上做红绿实验，是按构造性质论证。
  **登记未修 10 条（U1–U10）**，最重两条须所有者裁决：**AI 对话没有任何用户可见的发送披露**
  却每次带走「可编辑数据快照」（`docs/23 §6` 要求的披露与审计都没落地）；快照会发
  `meal.notes` 自由文本而 `docs/08 §2` 把快照写成「id+名称+关键数值」（文档与代码口径不一致）。
  **门禁 EXIT=0**（`pub get` / `dart format` **566 files 0 changed** / `analyze` No issues found /
  `flutter test` **+1962 passed ~11 skipped**）。**交付件**：
  `E:/AI/Zcode/localfit-ai-simple-arm64-release.apk`，**13,916,504 B**，sha256
  `fb6453d7eb87651c58aabefa2d9e93d6fab3258474f03cb56f86c536e3c5bb2b`，`versionCode 2002`
  （`pubspec` 0.1.0+1 → **0.1.0+2**，arm64 = 1000×2+2 > 上一件 2001 ⇒ 保证原地覆盖升级），
  arm64-v8a 单 ABI、v2 签名通过且**与上一交付件同一把密钥**、四个 `.so` 全 DEFLATE、
  随包种子恰为 `foods.v5.json` 且与仓库源**逐字节相同**；上一交付件已备份
  `E:/AI/Zcode/backups/localfit-delivery-arm64-before-bughunt-2026-10-08.apk`。
  **修好的文案「进包/出包」受控证据**：`libapp.so` 串探针必须在 6 条全命中、必须缺席 3 条
  全缺席、对照 2 条两包皆有（证明探针能红也能绿）。**设备走查（emulator-5556，5558/5560 未碰）**：
  帮助/关于/反馈三处披露 + 菜品表单价格填 `NaN` 四组对**屏幕上真实渲染的文本**断言全 PASS，
  顺带确认食材库仍 49,445 条（上一轮 `keptWhileReferenced` 证据仍在）、logcat 无
  `FATAL`/`E/flutter`。**诚实缺口**：「清除所有数据」的破坏性路径**本轮没在设备上执行**
  （确认框要求手打中文「全部清除」，adb 注入不了 CJK、`cmd clipboard` 在 API 35 无实现），
  设备侧只走到「未输入短语时按钮禁用」；因此 BUG-7 的「菜品照片随清除一起删」在设备上未实测
  （两条真 IO 测试 + 假 store 用例作证）；双击守卫/克数中间态/清除失败提示同样只有测试证据。
  证据 `docs/evidence/2026-10-08-bug-hunt-and-delivery.md`，截图
  `docs/evidence/screenshots/bughunt-delivery/`。

### 0.2 每包都要过的纪律（不重复写在各包里）

1. **门禁**：`tool/verify.bat` 退出码**重定向到文件、不走管道**（管道会把退出码冲成 0）；
   `cmd /c "*.bat"` 在 Git Bash 里**静默不执行** ⇒ 一律经 Python `subprocess` 调用。
   要求 `All tests passed` + format `0 changed` + `No issues found`。
2. **变异红证**：每条新断言配一条隔离变异（字节备份 → 一处最小改 → 只跑该文件 →
   点名用例转红 → 逐字节还原 + sha256 相等；多行锚点先确认目标文件的换行风格）。
   变异电池会改写字节 ⇒ **电池之后必须复跑一次完整门禁**才算终态。
3. **设备**：只认 `emulator-5556`（AVD `LocalFit_API35`，1080×2340 / density 480 = 360dp），
   **勿动他项目的模拟器**；`uiautomator dump` 取真实 bounds，坐标在**每次 tap 前重新 dump**。
4. **文档同步**：漏改活文档等于门禁红（`docs/21`、`docs/INDEX.md`、`STATUS.md`、证据文件）。
5. **路径安全**：所有文件只在 `E:\AI\Zcode\` 内；写入用 `E:/AI/Zcode/...`（不要 `/e/...` 或 `/tmp/...`）；
   临时文件只进 `E:\AI\Zcode\tmp\`。仓库无 git ⇒ 动手前把 `lib/` + `test/` 相关子树备份到
   `E:/AI/Zcode/backups/`。

### 0.3 权威源（只有这四份 + 代码/测试）

`docs/29`（本阶段细则）、本文件（目标与硬约束）、`docs/07`（契约）、
`docs/21` + `ui设计/pages/*.html`（UI 唯一依据）；AI 协议与对话式编辑见 `docs/24` / `docs/23`。
`docs/11`/`22`/`25`/`26`/`27`/`28` 是**已完成的方案书，无规范效力**。
任何旧文档与本阶段冲突，以 `docs/29` + **实测**为准，并把冲突点写进证据文件。

### 0.4 本阶段的两条硬约定

- **视觉类工作包先出 HTML 设计稿**（放 `ui设计/remediation/`，**不得放进 `ui设计/pages/`**——
  该目录有 7 页 `unorderedEquals` 断言），无头渲染 360dp 评审后再原生实现。
- **食物库全量人工审核**（用户 2026-10-05 指定必做，见 `docs/29` §P8b）：49,464 条逐条有人工裁决；
  权威证据 = 审核账本 `reports/review_ledger.jsonl` → `foods.v5.json`；
  **未达 100% 覆盖率不产出 v5**（App 继续用 v4，不出现「审了一半的种子」）；
  报告如实分列「逐条核验 / 族批确认 / 存疑」，**不得混称**；
  先交付工具与账本（P8b-1），v5 与 App 升级（P8b-2）以覆盖率为出口。
  **2026-10-07 状态：已完成**——账本 100% 覆盖、v5 已产出、App 已升级到 v5（见上 §0.1 P8b-2 条）。

### 0.5 边界

真实 AI 请求只发生在 `docs/29` 的 P4/P11（用户授权）；自动化测试全程 fake provider；
API Key 不进文档、日志、截图。不新增依赖（`image_picker` / `file_picker` 已在依赖内）。
不发布、不推送、不提交。

## 1. 产品目标

在 `E:\AI\Zcode\localfit-ai` 持续开发 LocalFit AI 2.0：一款本地优先、AI 辅助、以校园就餐决策为核心的饮食与健身管理 App。

2.0 必须能够回答：

1. 现在去哪个食堂/窗口；
2. 现在吃什么、吃多少；
3. 今天应该怎样安排饮食与训练。

核心闭环：

```text
本地事实 → 菜单与食物目录 → 本地约束筛选 → AI 可选创作/解释
→ 严格 JSON → 本地校验 → 用户编辑 → 独立确认
→ 写入计划或已摄入事实 → 本地统计
```

## 2. 2.0 必须交付

### AI 创作工作台

以任务卡替代无边界聊天：

- 生成今日吃法；
- ~~创作一周食谱~~（已下线：2026-10-04 按用户裁定 D3/N4 整族删除，见 `docs/28` §6）；
- 解析学校菜单；
- 解释菜品和份量；
- 生成训练计划；
- 整理用户主动选择的常吃搭配（只读建议，不写入本地事实）。

每个任务具备 `task_id`、`contract_version`、`prompt_version`、input projection、allow-list、校验报告、用户编辑和独立确认。

### 结构化 AI 协议

冻结兼容合同：`meal-estimate.v1`、`workout-plan.v1`。（2026-10-04：`recipe-plan.v1` 随食谱/周计划整族删除，见 `docs/28` §6。）

新增合同：`menu-normalize.v1`、`daily-menu-plan.v1`。

AI 不得直接生成正式营养、安全、价格、库存、营业时间、路线或数据库事实。未知本地 ID、非法 JSON、超限响应和未确认结果必须被拦截。

### 50,000+ 食物目录

以去重后的 canonical food 计数，目标至少 50,000 条：

- 优先覆盖中文基础食物和校园高频菜；
- 再扩展品牌、包装、地方菜和国际食物；
- 使用离线 ETL、来源/license manifest、内容 hash、SQLite 分片和 FTS5；
- alias 不计入 canonical 数量；
- 不完整数据只能搜索展示，不能参加严格营养计算；
- 目录升级不能改变历史快照。

> **2026-10-02 现状（ADR-025）**：随包食物库整体替换为 FoodCalu 派生的中文库
> （`assets/seed/foods.v4.json`，**49,464 条**，每 100g 四项宏量），首装即用；
> 旧种子（CFCT 1,634 + foodwake 830）与随包目录分片全部下线。条数已接近本目标，
> 但该来源**无再分发许可证**，只适用于「个人自用、不再分发」——对外分发前必须
> 先解决许可（`docs/THIRD_PARTY_LICENSES.md` §4.1）。分片/FTS5 机制保留给按需
> 导入的许可数据。

### 校园菜单和每日规划

支持学校、食堂、窗口、营业时段、日期菜单、价格、食物匹配、营养证据和过期状态。

输入按阶段支持：粘贴文本、本地 TXT/CSV/JSON、PDF、图片/OCR、用户主动 URL 和学校模板。

本地 solver 先过滤目标、已摄入、过敏、营养证据、营业时间、冲突和数据完整性，再按营养偏差、时间、通勤、偏好和新鲜度排序。AI 只负责候选组织和解释。

### UI：按 `ui设计/pages/*.html` 重建

**视觉与交互的唯一依据是 7 个设计稿 HTML**（今日 / 饮食·记录 / 饮食·菜单 / 拍照识餐 / 训练 / 我的 / AI 工作）；规范译法见 `docs/21`；本阶段改造方案见 `docs/29`（`docs/22` 是当时方案，已完成、无规范效力）。此前所有 UI 规范（方案 A「薄荷奶油」、薄荷奶油 2.0、旧 IA 重设计）**已于 2026-09-28 从仓库删除**（`docs/DECISIONS.md` ADR-024），**仓库内不存在旧视觉的任何可读来源**——`docs/21` 是唯一依据。

- 底栏 5 槽：今日 / 饮食 / **AI 对话（中间凸起圆）** / 训练 / 我的——中间槽由「拍照」改为「AI 对话」，拍照识餐改为推入式二级页；
- 今日页：问候头 + 全圆环热量卡 + 宏量条 + 体重折线 + 三趋势格 + AI 入口卡 + 计划态时间线 + 饮水/步数双卡；
- 饮食页：`记录 | 菜单 | 食物库` 三 chip（2026-10-04：`计划`、`食谱` 两个 chip 随整族删除，见 `docs/28` §6）；记录页含 hero 三段统计、7 日趋势、周条、餐卡、营养分析、FAB；菜单页为菜品卡列表（含点评与微量营养素）；
- 训练页：暗色 hero + 容量图 + 进行中横幅 + 分段 + 肌群 chips + 计划卡（含心血管处方）；休息日与「今天」必须按真实数据与计划推导；
- 我的页：渐变身份卡 + 健康数据 + 成就网格（含未解锁态）+ 4 个设置分组；「数据同步」降级为「自动本地备份」；
- AI 对话页：6 种消息形态 + 双状态输入栏 + 快捷 chips + 图片预览条（**2026-10-05 裁定：删除免责声明与语音转写、拍照识别改为直通相机，见 `docs/29` §P10**）；
- 复杂页面逐步拆为 controller/draft/section/widget（沿用 §5 规则 5）。

**设计稿未画到的现有功能不删除**——保留数据与逻辑，UI 上收进二级入口（`docs/21` §1.2）。
**设计稿里的数值全部是演示数据**，一律不得上屏；无数据走诚实空态（`docs/21` §6.1）。

## 3. 硬约束

- 无账号、无开发者业务后端、无云端用户库、无广告、无社区、无自动下单。
- 档案、餐食、菜单、训练、计划和统计默认只存在本地加密数据库/应用私有文件。
- API Key 只存 Keychain/Keystore，不进入数据库、日志、备份明文或请求正文。
- AI、URL 和路线请求必须由用户主动触发并披露发送范围；不后台定位、不持续跟踪、不绕过登录/验证码。
- AI 只能产可编辑草案；本地事实、公式和 solver 决定最终可用性。
- `meals` 只表示已经吃过；推荐和计划不能直接创建 consumed meal。
- 未知不等于安全；过期菜单、未知过敏、未匹配食物和不完整营养必须显式标记。
- 新数据实体必须同步考虑迁移、备份、恢复、清除、日志、导出和失败回滚。

## 4. 执行路线

1. `2.0-0`：统一 AI Transport、冻结兼容合同、修正字段边界、补齐清除安全边界。
2. `2.0-1`：50k 食物目录、ETL、FTS5、分页、分片导入和历史快照兼容。
3. `2.0-2`：AI 创作工作台、Prompt Catalog、合同版本、menu-normalize/daily-menu-plan。
4. `2.0-3`：校园菜单本地实体、文本/文件导入、人工修正、快照和证据。
5. `2.0-4`：每日计划 solver、菜单/食物候选、离线回退和无解解释。
6. `2.0-5`：手动地点和通勤时间，再做主动、短 TTL、可取消路线查询。
7. `2.0-6`：今日决策卡、菜单/食物库 UI、AI route-level flow 和状态拆分。
8. `2.0-7`：真机、低存储、迁移、备份、许可证、隐私和签名包发布门槛。

每项依赖和退出条件见 `docs/04-roadmap.md`。

## 5. 开发规则

1. 每轮只做一个最小可验收切片；当前 active slice 只看 `STATUS.md`。
2. 先读 `STATUS.md`，再读本文件、相关 2.0 规范和直接源码/测试。
3. 页面不执行 SQL/HTTP；领域层不依赖 Flutter、Dio 或供应商 SDK。
4. 自动化 AI 测试全部 fake，不消耗真实 token；真实 Provider 只做手动 smoke test。
5. 提示词、schema、数据转换和 UI 状态分开维护；不把大型契约嵌入页面。
6. 每个切片开始、检查点、验证、阻塞和结束都更新 `STATUS.md`。
7. 真实命令、环境、结果和限制写入 `docs/evidence/`；历史结果必须标为 historical/not rerun。
8. 架构取舍追加到 `docs/DECISIONS.md`，不在聊天中形成第二份事实源。
9. 不自动提交、推送或发布；不在未运行验证前声称通过。

## 6. 当前切片指针

当前切片不在此处维护，见 [`STATUS.md`](STATUS.md) 的 `Active Slice`、`Next Command` 和 `Last Handoff`。

## 7. 总验收

2.0 完成必须同时满足：

- ≥50,000 条 canonical food 有来源、许可证、manifest 和质量报告；
- 50k 搜索/导入满足真机门槛；
- AI 合同和 Prompt 版本化，结构化评测达标；
- 未知 ID、模型自报营养/安全/路线不会直接成为事实；
- 学校菜单支持来源、快照、窗口、日期、人工修正、过期和证据；
- 本地 solver 在 AI 不可用时仍可运行并解释无解；
- 计划与已吃严格分离；
- UI 按 `docs/21` 重建完成后，在亮/暗色、窄屏、大字和无障碍下可用；
- 迁移、备份、恢复、清除、低存储和中断导入不损坏数据；
- Android 签名包核心旅程通过，再完成 iOS 验证；
- 隐私说明与实际网络、存储、日志和权限行为一致。
