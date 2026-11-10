**2026-11-09 全量审查 + UI 审查（未升版本）· 修复完成**：死代码扫描（自写 import 图可达性）给出 3 处真死代码 + 1 个生成物孤儿 + 6 个「已决定保留」的旧子系统文件，按铁律不顺手删；隐患 8 条全部实锤并修复——取消竞态（探针窗口内点取消仍挂卡）、2.0 字号「尚未写入+生成按钮」窄屏溢出（360dp 39px / 320dp 79px，旧测试因回复不含完成态而绕开了这行）、结果文字对比度（primary 2.11:1 / error 3.29:1）、暗色 errorText 4.35:1、图片删除热区 14dp、检查更新无加载态、两处按钮行窄屏溢出、推荐 chip 缺 Flexible。门禁 **定向 1446 / 全量 +3358 ~1 / release 18 / format 0 / analyze clean / encoding OK**；UI 实帧 15 张逐张查看，并用坐标探针排除 2 个误报：[`docs/2026-11-09-audit-REPORT.md`](2026-11-09-audit-REPORT.md)。

**2026-11-07 应用卡片按需生成（2116）· 施工完成（发布待另行确认）**：正常对话只出内容，不再强制 JSON/自动弹卡；**今天完成**的内容卡右下角加「生成应用卡片」，点击后才用编译器基于目标回复 + 最近对话 + 最新快照生成信封，并挂到**同一条助手消息**。已按方案施工完成：内容纪律保留、编译协议变体 + 数字接地闸门、上下文/字节预算拆分、日期钉死与应用前确认、状态机（含 `retryable`）、滚动隔离、`dismissed`/`raw` 落库回环前置修复；控制器 32 条 + 页面 10 条 + 接地 9 条 + Drift 回环 3 条测试全绿，双路径回滚保持（详见 STATUS.md 与 docs/23 §7、docs/24 §11）：[`docs/66`](66-manual-card-generation-plan-2026-11-06.md)。

**2026-11-06 编辑卡优化（2115）· 完成并发布**：单组卡不再重复「应用本组/全部应用」；记餐行统一紧凑样式，新食材不再把每 100g 热量当成这一份热量；「已忽略」改中性浅灰徽标。门禁 **3247 / 0 / 1 skipped**，release 18、format/analyze clean；3 ABI 2115 已发布 `v4115`（哈希回读一致）。

**2026-11-06 局域网更新（2114）· 完成并发布**：设置 → 关于新增「局域网更新」，填电脑地址后「检查更新」优先读 `lan/manifest.json`、按 versionCode/ABI 选包走 Wi-Fi 下载，失败自动回 GitHub。门禁 **3246 / 0 / 1 skipped**，release 18、format/analyze clean；3 ABI 2114 已发布 GitHub Release `v4114`（公开回读哈希一致）。v4114 需先手动装一次，之后可在 App 内局域网更新。

**2026-11-06 AI 补信封与“改记为”修复（2113）· 完成**：修改请求/照片记餐首轮强制 JSON，补跑信封并回首轮、不再显示重复回复；协议要求改餐次用 `meal.update`，跨餐重复不再假报“已应用”，合并时按全天去重并点名跳过食物。门禁 **3242 / 0 / 1 skipped**，release 18、format/analyze clean；3 ABI 2113 包已构建，x86_64 自有 AVD 启动通过。源码未提交/未推送；**已发布 GitHub Release v4113**（三资产公开回读 SHA256 一致）。

# LocalFit AI 文档地图（`docs/INDEX.md`）

日期：2026-10-14
用途：**本仓文档的唯一地图**。先读 `STATUS.md` 最新状态与本页，再读 [`docs/33`](33-round7-native-ui-migration-guide.md) 的评估和未来实施路线；当前原生行为仍以代码、测试及 `docs/32` 已落地裁决为准。

**2026-11-06 全量审查 + 2112 个人自用包 · 完成**：修复跨槽位串餐、训练回顾二次 pop、扫描元数据 round-trip、地点/识别/心肺 FK 删除链、true v1 备份缺字段、30 天餐食写入窗口、菜单失败清理、AI DB 异常隔离、食堂营养边界与下载进度无障碍语义。全量门禁 **3240 / 0 / 1 skipped**，release 18、interaction 36、format/analyze clean。新包 `LocalFitAI-vc3112-arm32.apk` / `vc4112-arm64.apk` / `vc6112-x86_64.apk` 已构建、签名/对齐/资产检查，并已发布 GitHub Release **v4112**（公开回读哈希一致）；x86_64 自有 AVD 5554 完成 v6111→v6112 应用内更新实测（下载→系统安装器→启动、数据保留）。报告：[`2026-11-06-full-audit-REPORT.md`](2026-11-06-full-audit-REPORT.md)，证据：[`evidence/2026-11-06-full-audit/run-log.md`](evidence/2026-11-06-full-audit/run-log.md)。

**2026-11-05 三库收敛 Phase 2–5 + 选择卡 · 完成**：
—— AI 快照收敛：食堂段只列未分析菜（标不能直接记餐），候选段只发 `[dish:]`；
`CatalogSearch` + `searchByName` 统一记餐搜索；AI 建菜按「窗口+精确名」查重；
`dish.upsert` 增可选 `servingGrams`、按名更新保留份量；跨库同名如实提示；
退役手动同步死代码；同名窗口歧义列「地点·窗口」候选；同名冲突选择卡
（候选弹层 → 改写该行引用 → 只重放该行）；餐级 source 收敛；快照菜品段用
`energyLabel`。真模型 C18/C05b 通过（C18 主动输出 servingGrams=250）。
审计补修：食物归一化名称回查、来源身份去重、重复来源行防崩、同名多行
修复定位；再优化手改份量冻结、跨库提示失败隔离、缺失文案去前缀、快照
餐次中文。门禁 **3231 / 0 / 1 skipped** + release 18、format 877/0、
analyze clean。仍开放 3 条 P2：食物宽搜口径、菜品库唯一索引、协议预算。
证据
[`evidence/2026-11-05-catalog-phase2-5/run-log.md`](evidence/2026-11-05-catalog-phase2-5/run-log.md)。

**2026-11-06 AI 协议反哺（SFT 误差分析 → 规则 16）· 完成**：本地 SFT 试点量出的命令族混淆（删除族跨库、goal/targets 顶替、录菜单≠逐条建菜、`servingGrams` 凭空补值）压成规则 16 写进 `renderProtocol()`；预算对冲压缩规则 0/13/15，受保护短语全保留。先红后绿（3 红 → 13/13 绿）；`test/features/ai_conversation` 507 绿；全量门禁 **+3234 ~1 全绿**；format 0 改动；analyze 干净。不改 schema/依赖/wire。证据：[`evidence/2026-11-06-ai-protocol-contrastive/run-log.md`](evidence/2026-11-06-ai-protocol-contrastive/run-log.md)。

**2026-11-04 三库数据契约 Phase 0 + 记餐认菜品 Phase 1 · 完成**：
—— Phase 0 修 9 个数据契约问题：餐条目来源（food/dish/scan）全链路保留、
菜品→一餐不再重复乘份量、食堂同步不清点评/微量、AI 按名更新不清食堂来源、
食堂来源菜删除守卫、四值齐全才算已分析；食堂菜品表单补「一份多少克」并接入
自动同步；无份量时不再冒充 `/份`；「引用食物库营养」改为同事务写营养 + 确认链接。
Phase 1 新增 `CatalogResolver` + `NutritionMath`：`meal.create` 认 `[dish:id]`、
已同步的 `[canteen-dish:id]` 与精确菜名；同名双库如实报冲突。
门禁 **3224 / 0 / 1 skipped** + release 18、format 875/0、analyze clean；
Phase 0 十二条 + Phase 1 四条先红后绿。证据
[`evidence/2026-11-04-catalog-phase0/run-log.md`](evidence/2026-11-04-catalog-phase0/run-log.md)。

**2026-11-04 检查更新下载进度（v4111）· 完成并发布**：
—— 下载弹层显示真实进度条、百分比、已下载/总大小及取消；无总大小不猜进度。
关闭/返回立即中止下载，安装交接返回真实结果；独立 `.part` 防止旧清理误删新包。
发布核验发现并修复 arm32 架构名二次解析为空、误报缺包的问题（v4110 → v4111）。
门禁 **3205 / 0 / 1 skipped** + release 18、format clean、analyze clean；
5 张实际渲染图已检查，模拟器 vc6109→6111 保留数据升级启动通过，三包与发行
资产核验一致；已发布 v4111。证据
[`evidence/2026-11-04-update-download/run-log.md`](evidence/2026-11-04-update-download/run-log.md)。

**2026-11-03 根治 JSON 信封（v4109）· 完成**：
—— 新增「信封编译器」：对话照常说人话，解析失败后改发纯文字、强制 JSON 的
编译请求（chat `response_format: json_object` / Responses `text.format`），
不再重发整段对话与图片；供应商拒绝该字段时自动降级一次。门禁 **3158 / 0 /
1 skipped** + release 18；已发布 v4109。证据
[`evidence/2026-11-03-card-loop-v4105/`](evidence/2026-11-03-card-loop-v4105/run-log.md)。

**2026-11-03 发图不弹卡 + 浮钮簇（v4108）· 完成**：
—— 视觉模型只回完整记餐提案却不输出 JSON：新增极保守的散文抢救（应用口吻
+ 餐次唯一 + 每条有克数）本地拼成 `meal.create` 卡；训练/饮食加号删掉 1dp
平移，三角改 48dp 同径同线，整簇按钮改深绿实心底。门禁 **3154 / 0 /
1 skipped** + release 18；已发布 v4108。证据
[`evidence/2026-11-03-card-loop-v4105/`](evidence/2026-11-03-card-loop-v4105/run-log.md)。

**2026-11-03 条目卡最终版 + AI 补查（v4107）· 完成**：
—— 条目卡第一行「名称 → 克数 → 删除」、第二行「热量 + 三宏量」；窄屏与大
字号自动分行。AI 对话补查：隐藏中间气泡不落库、停止时移除而非露出、失败/
空文本不静默、跳过无界面建议请求、兜底卡标题中性化。门禁 **3147 / 0 /
1 skipped** + release 18；已发布 v4107。证据
[`evidence/2026-11-03-card-loop-v4105/`](evidence/2026-11-03-card-loop-v4105/run-log.md)。

**2026-11-03 条目卡重排 + AI 自动续答（v4105 / v4106）· 完成**：
—— 编辑餐食条目卡改「名称+删除 / 克数→热量→宏量」，克数与热量相邻不再隔
半个卡片；320dp 窄屏与 >1.3× 大字号（含 2.0×）自动分行，热量不再被截断。
设计稿三选见 `design/round12/meal-card-layouts.html`。AI 对话自动催信封的
中间气泡不再渲染，按「停止」后不再自动催、不弹「没有可执行操作」兜底卡。
门禁 **3145 / 0 / 1 skipped** + release 18；证据
[`evidence/2026-11-03-card-loop-v4105/`](evidence/2026-11-03-card-loop-v4105/run-log.md)；
已发布 v4105 / v4106。

**2026-11-02 文案收敛 + 帮助重组（v4100）· 完成**：
—— 长说明迁入帮助（新增目录与 AI/目标/扫描/体重秤/备份条目），关于/页脚/AI 配置/
体重秤/反馈/目标/扫描只留短标签；同批修 AI 已过餐次、删除标题、开关手势与两处
async 销毁隐患。门禁 **3120 / 0 / 1 skipped** + release 18 + 取帧 17；证据
[`evidence/2026-11-02-copy-help/`](evidence/2026-11-02-copy-help/run-log.md)；已发布 v4100。

**2026-11-02 全仓死代码与稳定性审计（v4099）· 完成**：
—— 删 4 个不可达展示组件、2 个无引用函数、完整 DishCard/菜品营养编辑死 UI
与无入口写方法；修复 2 处 await 后 setState 销毁隐患；控制器/订阅与路由引用
全量核对；追加修 AI 跳过已过餐位、删除标题、开关手势。门禁 **+3351 ~70 / 0**；已发布 v4099；证据
[`evidence/2026-11-02-dead-code/`](evidence/2026-11-02-dead-code/run-log.md)。

**2026-11-02 文案收敛 + 数据管理二级弹层（v4097）· 完成**：
—— 数据管理压到 4 行：备份与导出抽屉（备份/恢复/3 导出 + 自动备份开关）、
数据自检、步数、电子体重秤；菜单/训练空态/扫描/今日占位/AI 工作台说明压缩。
门禁 **+3392 ~70 / 0**；实帧与证据
[`evidence/2026-11-02-density/`](evidence/2026-11-02-density/run-log.md)。

**2026-11-02 GitHub Releases 更新通道（v4096）· 完成**：
—— 新建公开 `xiaopeng66/localfit-ai-releases`（仅 APK/Release）；App 检查更新改读该仓库，
局域网入口、服务、网络诊断权限与测试完整退役；发布脚本动态版本、幂等上传、API 直连。
v4096 修复推荐候选点击黑屏（弹层在根 Navigator，旧代码 pop 了分支页面；改用
`sheetContext` 关闭自己），并新增嵌套导航回归。最新 Release v4096；实机 v6095
检查更新返回「已是最新」。门禁 **+3392 ~70 / 0**；
证据 [`evidence/2026-11-02-github-update/`](evidence/2026-11-02-github-update/run-log.md)。

**2026-11-01 用户反馈批次（v4094）· 完成**：
—— 下一餐按时刻动态（0–9 早 / 9–14 午 / 14–20 晚 / 20–24 加餐）、删统计行与空态
「记一餐」、步数刷新忙碌态；复用历史餐食退役；营养目标三段式且 2.0× 不裁数字；
餐卡逐食物勾选删除（部分删除保留其他食物、撤销按 item id）；AI 换一套携带剩余营养
并硬跳过已记录餐次；推荐卡三点菜单退役；新建/AI 食物自动分类；候选留白按 token 重算。
门禁 **+3408 ~70 / 0**；证据 [`evidence/2026-11-01-round13/`](evidence/2026-11-01-round13/run-log.md)；
LAN manifest **v4094**。

**2026-10-29 第三批实机反馈八项（统一弹层/黑屏/圆环/回到今天）**：
—— ① 看图弹层不透明化（黑屏观感根因）+ AI 候选点选生效；② 圆环指针到顶不再绕回起点；
③ 三入口合并为统一记录弹层（双库搜索+来源标+手动添加可存库，chooser/按菜品/自定义退役，
条目同屏编辑）；④ 餐卡来源徽标与自动备注撤下（「已确认/AI 估算」= 证据等级，留在菜品库卡）；
⑤ 克数 g 后缀入框；⑥ 记录页「回到今天」胶囊（实机验证）；⑦ 补记徽标 mint 化；
⑧ 八个旧用例按新契约改写 + 回补误删接线。v6080 实机走查，截图
[`evidence/2026-10-29-n2/emulator/`](evidence/2026-10-29-n2/emulator/)；
LAN `http://10.38.159.142:18080/`。

**2026-10-29 docs/65 十二项 + 体检 · 完成**：
—— 十二项全落地（徽章缩放、三框等高、三入口、推荐小图+内联换一套[食堂目录限定+硬校验]、
个人记录卡化、真实周序、AI 兜底卡、记忆页重设计、收回根因修复、多图缩略图墙、菜品弹窗
主次分明），体检 20 条（P0×1/P1×14/P2×1）。证据：
[`evidence/2026-10-29-round5/`](evidence/2026-10-29-round5/run-log.md)（含 audit.md）；
门禁 +3087 ~1 全绿。验收表见
[`docs/65`](65-next-development-2026-10-29.md) 附录 C（已填）。

**2026-10-29 下一轮任务书（十二项需求 + 底层体检，待启动）**：
[`65-next-development-2026-10-29.md`](65-next-development-2026-10-29.md) ——
连续执行模式（不逐阶段停、最终一次汇报）；R-1…R-12 逐条含用户原话 / 落点 / 判据；
§4 五条默认裁决（周序口径 / 推荐只取食堂目录 / AI 兜底卡保守方案 / 「＋」统一三入口 /
多图持久化局限如实登记）；证据目录 `evidence/2026-10-29-round5/`。

**2026-10-28 第二批实机反馈四连修**：
—— ① 浮钮图标居中（Center 兜底）；② 营养卡脚注公式说明撤下（docs/60 §9「卡上标依据」
正式修订为「核实表 + 计算器单测承担」，断言改写两处留原文；记录页编辑入口改图标钮）；
③ 「按菜品记录」改与按食材同构的表单弹层（`DishMealEditorSheet`：共享胶囊 + 搜索加菜 +
已添加 + 合计 + 保存，逐条 `AddDishToMeal.run` 不新增写路径，新测试 7 例）；④ 自定义一顿
胶囊统一 + 合计卡（共享件 `meal_slot_pill.dart` 三弹层一颗胶囊）。帧 7 张
`frames/review2-*`；docs/21 附录 D1 与 §5.1 同步。门禁 +3080 ~1 全绿。

**2026-10-28 实机验证（自有 AVD emulator-5554，v6077）**：
—— 构建 release APK 装机实跑，核对训练页三枚浮钮（浅品牌底 + 品牌图标 + 实心主行动）、
页底空态可滚出浮钮覆盖带、菜单页带字档未受波及、体重卡头同款浅底；截图 4 张在
[`evidence/2026-10-28-redesign/emulator/`](evidence/2026-10-28-redesign/run-log.md)。

**2026-10-28 浮钮重画（实机截图：训练页右下浮钮像禁用态）**：
—— 次级浮钮「白底 + 灰边 + 灰图标」→ 浅品牌底（mint-100 底 + mintText 图标、去描边
去阴影）；带字档与主行动不动。试过 mint-50 后发现与页面底几乎同色，退回 mint-100
（试错写进注释）。新增取帧器 3 张（320×2.0 / 412×1.0 / 带字档）+ 契约测试 1 例，
变异验证；主行动「白月牙」经像素采样证伪后撤回误改。证据同上目录 run-log「第三轮」；
门禁 +3073 ~1 全绿。

**2026-10-28 第二轮复核（逐处核对 → 修 3 个真缺陷）**：
—— ① 菜品宏量单位只在 hint、有值不可见 → 单位写进顶部说明；② `AppSheet.showCustom`
主体无滚动层，真实壳 320×640×2.0 下饮食约束溢出 305px / 数据自检 547px / 菜品编辑
1.00px → 三个 `show*Sheet` 各包 `SingleChildScrollView`，新增 `test/review_ui_shell_fit_test.dart`
7 个真实壳用例（三处包裹逐一变异复现后恢复全绿）；③ 体重确认行仍是旧形态 → 与水表
对齐「整行文案 + 按钮下沉」，补两档确认态帧；取帧器 State 跨档残留一并修。12 帧重取
逐张审看。证据：
[`evidence/2026-10-28-redesign/`](evidence/2026-10-28-redesign/run-log.md)；
门禁 +3072 ~1 全绿。

**2026-10-28 新增 UI 重设计（新按钮「太丑」→ 按 320dp × 2.0× 约束重画六处）**：
—— 饮水确认整行化、自检页卡片化（DesignCard + 「N 条」徽章 + MutedBlock）、
忌口/菜品字段标签去括号注（单位进 hint）、菜品菜单改 ListTile 图标行、
体重卡头两行降级（纯算术判据，不能套 fitsRow）、补记空槽省略「尚未记录」；
12 帧逐张目视达标。证据：
[`evidence/2026-10-28-redesign/`](evidence/2026-10-28-redesign/run-log.md)；
门禁 +3072 ~1 全绿。

**2026-10-27 AI 对话 · 信封升级梯子（卡片弹出率强化）**：
—— 自动催 2 次（第 2 次自动改用「引用模型上一条回复」加强版提示）+ 回复侧触发器
`replyClaimsChanges`（模型散文声称已改数据却没信封 ⇒ 直接上加强版）+ 全程有界；
run-log（含 RED 原文、连带红改写、诚实边界与两条待裁决的更强方案）：
[`evidence/2026-10-27-envelope-escalation/`](evidence/2026-10-27-envelope-escalation/run-log.md)；
门禁 +3072 ~1 全绿。

**2026-10-27 复核 · 模拟器实机走查 + 查漏补缺**：
—— 静态自查补 3 个缺口（E-2 备份弹层哨兵改真断言、搜索空态加「自建食物」动作、
C-4 建议动作链静态测试）；自建 release APK 在 emulator-5554 上 adb 走查四阶段全部新交互
（饮水删/撤销、体重记录表、饮食约束、数据自检、昨天补记徽标、菜品营养编辑、
训练自由会话与删除整次），26 张截图逐张看过；两处环境问题如实记录（adb 长按注入局限、
模拟器时钟竞速致短暂黑屏，数据无损）。证据：
[`evidence/2026-10-27-review/`](evidence/2026-10-27-review/run-log.md)；
门禁 +3068 ~1 全绿。

**2026-10-27 改进四阶段 · 阶段 4 完成（B-1 裁决「30 天，继续」→ B-3 历史补记）**：
—— 过去日期也能补记：槽位头「+」+「补记」虚框徽标；窗口 30 天，窗口外如实说明，
未来不可补记。两条旧断言按新口径改写（理由与原文见 run-log）。门禁 +3066 ~1 全绿；
实帧 2 张在 [`evidence/2026-10-27-phase4-backfill/`](evidence/2026-10-27-phase4-backfill/run-log.md)。
**四阶段（17 项）至此全部完成。**

**2026-10-27 改进四阶段 · 收官（阶段 0–3 完，阶段 4 待裁决）**：
—— 阶段 0/1/2/3 全部完成并归档（四个 evidence 目录：phase0-b2 / phase1-delete /
phase2-parity / phase3-selfcheck，各含 run-log + frames + gate-logs）；阶段末门禁
+3061 ~1 全绿。**阶段 4 的 B-1 两条裁决（历史补记口径 / 补多久）已登记 docs/60 §0.3，
等用户答复后才做 B-3**——这是 docs/64 约定的唯一停点。

**2026-10-27 改进四阶段 · 阶段 3 施工证据（docs/64 自检与清扫）**：
—— D-1 数据自检页（三类脏数据 + 安全修复 + 撤销）、D-2 最近一次备份、E-1 五处空态动作、
E-2 12 页 320dp×2.0× 扫描（抓到并修掉记忆页两处溢出）、E-3 大数字单行量测；
run-log 在 [`evidence/2026-10-26-phase3-selfcheck/`](evidence/2026-10-26-phase3-selfcheck/run-log.md)，
实帧 6 张；门禁 +3061 ~1 全绿。B-1 补记裁决已登记 docs/60 §0.3。
[`docs/64`](64-improvement-roadmap-2026-10-26.md) 附录 C 已更新。

**2026-10-27 改进四阶段 · 阶段 2 施工证据（docs/64 能力对等）**：
—— C-1 AI↔UI 能力矩阵测试（37 条逐条声明 + 静态扫描守卫）、C-2 设置页「饮食约束」
（与 AI 同一张表，分层只许减的回调接线）、C-3 `menu.snapshot.publish` 保持 ai-only；
run-log（含连带红「跨 feature 只许减」的处置与一次施工事故的如实恢复记录）在
[`evidence/2026-10-26-phase2-parity/`](evidence/2026-10-26-phase2-parity/run-log.md)，
实帧 2 张；门禁 +3036 ~1 全绿。[`docs/64`](64-improvement-roadmap-2026-10-26.md) 附录 C 已更新。

**2026-10-27 改进四阶段 · 阶段 0/1 施工证据（docs/64）**：
—— 阶段 0（B-2 餐食未来日期守卫）与阶段 1（A-1 饮水删/撤销、A-2 体重删、A-3 菜品营养
手动改 + `userEdited` 冻结、A-4 训练删组/删整次、A-5 能力静态回归清单）完成：
run-log（逐项 RED 原文 / 变异 / 门禁数字）在
[`evidence/2026-10-26-phase0-b2/`](evidence/2026-10-26-phase0-b2/run-log.md) 与
[`evidence/2026-10-26-phase1-delete/`](evidence/2026-10-26-phase1-delete/run-log.md)，
实帧 6 张在 `evidence/2026-10-26-phase1-delete/frames/`；门禁 +3027 ~1 全绿。
[`docs/64`](64-improvement-roadmap-2026-10-26.md) 附录 C 已按行打勾。

**2026-10-26 GOAL（改进四阶段任务书）**：[`docs/65`](65-goal-improvement-phases-2026-10-26.md)
—— 可直接粘贴执行的引导文：先读清单（docs/64 为唯一施工依据）、执行纪律（先红后绿/变异/
实帧/连坐红）、阶段 0（未来日期守卫）→ 1（删除与修正）→ 2（能力对等，先写矩阵测试）→
3（自检 + 空态/字号清扫）→ 4（历史补记，先裁决），每阶段 DoD 与四条门禁、证据归档约定、
三种停止条件、设备与凭据约束；末尾附「为什么这样写 GOAL」的逐条理由。

**2026-10-26 改进方案施工文档（可执行）**：[`docs/64`](64-improvement-roadmap-2026-10-26.md)
—— 把 `docs/63` §6 的五套方案拆成**四阶段 17 项**：① 修正与删除（饮水/体重/菜品营养/
训练组次，半天）② 能力对等（先写「AI↔UI 能力矩阵」测试，再补 AI-only 的入口，1–2 天）
③ 数据自检页 + 空态/极端字号清扫（1 天）④ 历史补记（**需先裁决**，半天）。
每项给现状证据（文件:行）、RED 断言原文、施工步骤、变异、实帧、风险与验收勾选行；
附录含 37 条命令的能力矩阵、空态清单、风险登记与可直接粘贴的引导话术。

**2026-10-26 记录与目标的手动入口（用户：「营养摄入自己不能改 / 运动记录输入不了 / 步数读不到也不能自己输入」）**：[`docs/63`](63-manual-entry-fixes-2026-10-26.md)
—— 补齐 4 个入口：**自由训练**（无计划 / 休息日都能记录，原来没有计划就完全记不了）、
**自定义一顿**（直接填热量与三宏量，不依赖食物库）、**手动步数**（当天优先于传感器，
可恢复自动）、**手动营养目标**（热量卡「依据」格可点，从今天起生效、卡上如实写「手动设定」）。
顺手修 4 个真 bug：基线写库触发开关流导致「首读不落 0」被二次同步抵消、手动弹层
controller 在退场动画里被用、自由训练入口被右下浮钮压住、热量卡铅笔图标在 320dp×2.0×
溢出 11px。实帧 9 张、门禁与语义变更清单见文档。

**2026-10-26 第三轮修复的独立复核（用户：「你要自己截图验证」）**：[`docs/62`](62-round3-independent-verification-2026-10-26.md)
—— 不复用第三轮自己的测试：按**需求原文**重写独立判据（能量卡区间 9 条 / 编辑卡合并 5 条 /
记录卡 7 条，全部走真实链路、数字自己算一遍），并把 19 个视觉面拍成实帧**逐张自己看**。
复核**抓到并修掉 5 个真缺陷**（§19 卡头把新食材说两遍并搬回 P/C/F 压缩写法、§19 合并后丢了
每 100g 热量与三色点、§1 未设目标写「/ 0 g」这个编出来的目标、§20 320dp×2.0× 备注被压成一字
一列、图片气泡尾角跑到右上），每条都补了会红的判据（尾角那条做了变异验证：17 vs 70）。
实帧 `evidence/2026-10-26-round3-verify/frames/`（19 张）+ 门禁 `gate-logs/`；
另登记 2 项「只有行为断言、没有实帧」的理由（§2 步数态、§16b 候选去重）。

**2026-10-22 全应用审查 v2（Goal + 计划 + 报告 + 修复计划 + 二次验收，第 1 轮已收敛）**：
[`docs/53`](53-review-remediation-goal-v2.md)（Goal：审查→报告→修复计划→修复→验证→二次迭代，
连续执行不中途汇报，含可整段复制的引导文字；收敛判据与 5 轮上限）；
[`docs/51`](51-comprehensive-review-plan-v2.md)（计划：界面细化到按钮位置/卡片尺寸/文字换行/主题色/适配，
功能闭环、状态一致、AI 适配与 37 条命令、运行习惯、代码冲突与死代码、测试质量，共 16 维 A–P；
连续执行、不逐阶段汇报）；[`docs/52`](52-review-report-v2.md)（**报告（已完成）**：P0=0 / P1=1 已闭环 /
P2 11 条登记，A–P 逐维结论 + 台账 + 15 项指标 + 未覆盖清单）；[`docs/54`](54-remediation-plan-v2.md)
（修复计划：RV2-P1-01 根因/改法/先红测试/同类变体/回滚 + P2 逐条结论 + 2 条 decision-required）；
[`docs/55`](55-second-iteration-acceptance-v2.md)（二次迭代验收：闭环复验、门禁连续两次 `+2870 ~66`、
设备实帧、收敛判据 8 条逐项、未达 100% 两项如实登记）。
证据：`evidence/2026-10-22-full-review-v2/`（static/code/ui/tests/device/perf/edges/docs/ai）。
门禁 `review-v2-final` `+2870 ~66` → Key 对账升级 `+2876 ~66` ×2（三方对账 **338/338**）→ 收尾批（退役三份 AI 契约 + 清死码 + 三处加固）**`+2846 ~66` ×2**（`close3`+`close4`）。
**收尾批结论**：`RV2-P2-01` 契约退役（`docs/03` §9/§14/§15 as-built、`docs/21` D12）、`RV2-P2-02` 仅 2 个真死符号已删（4 个 extension 为误判）、`RV2-P2-05` **证伪**（测量假象）、`RV2-P2-06` FAB 覆盖带已修、`RV2-P2-08` 冻结预算门禁、`RV2-P2-07` 对账 338/338、`RV2-P3-01` 未来日期已拦；`RV2-P2-03` 按推荐不做。证据 `evidence/2026-10-22-full-review-v2/fixes/round3-retirement-and-hardening.md`。
收尾二批：10 个隔离变异 **0 存活/10**（先跑出 5 个真实弱点再补断言）、分层门禁锁死 66 条跨 feature 边（`RV2-P2-03` 闭环、重构不做）、iOS 补蓝牙权限说明；门禁 **`+2850 ~66` ×2**（`mut1`/`mut2`）。证据 `evidence/2026-10-22-full-review-v2/tests/mutation.md` 与 `fixes/round3-retirement-and-hardening.md`。
APK：**vc2052 universal**（`50b022d1…b195`）+ **vc6052 x86_64 分片**（`8074f110…73fe`，已装自有 AVD）+ arm64 分片 vc4052；打包/版本号约定见 `docs/09` §D（**发布只发 arm64 分片**）。未发布。

**2026-10-22/23 用户需求批次 1–3（审查后新增面，已交付）**：台账见 [`docs/52`](52-review-report-v2.md) §7（`RV3-*` 12 条：4 条 P1 + 8 条 P2/P3）；验收与限制见 [`docs/55`](55-second-iteration-acceptance-v2.md) §11；裁决见 [`docs/54`](54-remediation-plan-v2.md) §5。要点：整日推荐合成一张整套卡、营养达标改按「未超上限」、菜品删除（弹层 context）、导入=内置（全清保留）、AI 对话界面与去重/查库/分组、AI 建议气泡、训练 AI 入口只留 ➕、步数应用内开关。门禁 **`review-v2-batch7` `+2849 ~66`** 全绿。
**2026-10-24 追加**：食堂目录与菜品库**合并为一个库**（写营养即自动进菜品库、按来源键更新、删来源跟随删），
「加入菜品库」按钮与「整理重复菜品 / 关联到食堂菜品」整族退役（`docs/52` §7.1、`docs/40` §4 as-built）；
门禁 **`review-v2-merge2` `+2848 ~66`** 全绿；APK **vc4058/3058/6058**（arm64 sha256 `ff99d93f…df42`）在 `dist/`，
局域网 `http://10.38.159.142:8792/`。**`docs/09` §D.1 的 x86_64 偏移已按实测修正（+4000，原写 +5000）。**

**2026-10-24 用户需求批次 4（17 项）的审查计划（计划已交付，实现未开工）**：
[`docs/56`](56-batch-review-plan-2026-10-24.md)——17 条诉求拆成 `R1–R17`，逐条给「代码现状（含行号）/
根因假设 / 改动面 / 先红判据 / 风险」，附 5 批执行顺序、测试退役台账（15 份）、7 条待裁决
（下一餐整族是否退役、陈旧提示族是否退役、整套换在无 AI 时的行为、两按钮是否合并、
显示/发送文本是否分离、两枚 chip 选哪套、关键词选中态是否全局改）与 R16 的四套候选方案。
关键根因（已核实，非猜测）：① SnackBar 带 `action` 时 SDK 默认 `persist=true` ⇒ 删除提示永不消失；
② 训练计划天数 `ValueNotifier` 未监听 ⇒ 界面不重建（且界面停 3 天、实际按 4 天发出）；
③ 食堂菜进菜品库时 `DishDraft` 未传 `imagePath` ⇒ 有照片也永远走渐变占位；
④ 「鸡蛋」在 23,919 条库里命中 154 条、`鸡蛋（熟）` 排第 32 位而结果只取 10 条 ⇒ 搜索「匹配是对的、被排序+上限藏了」；
⑤ `daily-menu-plan` 启动卡的提示词仍要求已退役的 v1 JSON 契约；
⑥ `LfPillButton` 的类注释写「选中：加 `Semantics(selected)`」但**实现里没有**（读屏听不出哪个被选中，
对照 `LfFilterChip`/`AppMorphChip`/`LfSegmentedToggle`/`_SlotPill` 四处都真发了）——
写控件门禁时发现，已登记为 `RV4-P1-09`。

**2026-10-24 批次 4 审查结果与修复（**已收敛**：B1–B6 全跑完 + 用户追加三轮修复，门禁连续两次全绿）**：
[`docs/57`](57-review-report-batch4.md)（审查报告：A–P 十六维逐维结论 + 台账
**P0=0 / P1=8 / P2=12 / P3=5** + 「三条假绿是怎么形成的」交叉验证 + 未覆盖清单 6 项）；
[`docs/58`](58-remediation-plan-batch4.md)（修复计划 v2：**B1 先建控件交互门禁**（L1 状态 / L2 重建 /
L3 语义 / L4 可测性四层，专防「训练天数选不了」复发）→ B2–B5 业务修复 → B6 退役收尾；
每条含 RED 断言原文与回滚；19 条测试退役台账；收敛判据 8 条；9 项风险缓解）。
**基线**：`batch4-review-baseline` `+2856 ~66` / exit 0 / `changed_during_run: []`；
Key 三方对账通过。**变异抽验 3 点**：搜索排序变异 **RED（有守护）**；
补上缺失的 `imagePath` **12 条测试全绿不变（盲区确认）**；选中态对比度 1.07 vs 1.12 **无测试（盲区确认）**。
证据 [`evidence/2026-10-24-batch4/`](evidence/2026-10-24-batch4/)（static/tests/baseline）。
**执行结果**（2026-10-24 本轮）：**B1 四层控件门禁**（L1 `+7` / L2 `+2` / L3 `+13` / L4 `+2`，四个文件带
`@Tags(['interaction-gate'])`）+ 变异抽验 **M-G1/G2/G3 全红后逐字节还原复绿**；B2 提示与控件 →
B3 记录路径（**R4「下一餐」整族退役**，分层边 **66 → 64**）→ B4 菜品库与菜单 → B5 AI → B6 退役收尾
→ **R1 补做**（两行数字卡，objective 验收物优先于 docs/58 分批）。
门禁终态 **`batch4-final17` / `final18` 连续两次 `+2916 ~67` 全绿**（format 0 / analyze 干净 / exit 0 /
`changed_during_run: []`）。设备实帧 21 张 / 8 类；AI 两类按 `ai-live: not run` 显式豁免；
偏差裁决见 `evidence/2026-10-24-batch4/decisions-required.md`。

**用户追加（同日三轮）**：①「应用本组」样式改显眼（`LfTextButton` → `LfSoftButton`，三档阶梯写进
`docs/21` 附录 D0，回归钉子 `chat_edit_group_apply_style_test`）；②「AI 对话卡片很多次不弹出」——
定位三个根因（协议关键规则埋在 63% 处 / `suggestions` 参数不全被静默丢弃导致整封信封作废 /
`edits` 缺键被判纯文本），协议规则 0 前置 + parser 三处放宽，宽口径 **81.5% → 100%**；
③「**不要模棱两可、不要推荐错误答案**」——判据收紧为「信封 + 精确命中 + 不夹带」，
修掉协议自相矛盾、顺手附送无关命令（M02）、空壳命令 + 谎报已记录（M22）、
拿克数当缺信息反问（M02/M09/M17/M08），严格口径 **73/75 = 97.3%**。详见
`evidence/2026-10-24-batch4/ai-chat-edit-card-rate.md` §六。
**APK 重建**：vc4062 / vc3062 / vc6062（`dist/` + `SHA256SUMS.txt` + `index.html`，`sha256sum -c` 三包 OK），
x86_64 包已装自有 AVD `emulator-5554`（vc6062，启动正常，实帧 `device/21-vc6062-running.png`）。
**AI 多轮理解专项（同日第三次追加）**：新建 12 剧本 × 2 轴多轮实测，抓到真实缺陷——模型看不见
「上一张卡还没应用」，会答「等你应用上一步后我再改」。修法：新快照段「尚未应用的提议」放最前 +
`PendingProposal` 透传到控制器（不动 wire / 命令表 / schema）。**单案复跑 A/B：OFF 1/3，ON 3/3**。
报告 `evidence/2026-10-24-batch4/ai-multi-turn-optimization.md`。

**AI 内容正确性专项（同日第四次追加）**：新增**提案审查器**（餐次不符 / 重复食物 /
疑似遗漏，**只标注不改数据**）+ 卡片警告条（不阻断应用）+ 协议规则 14（餐次按用户说的 /
items 不许同名重复 / 一样都不许漏）+ **37 条命令四处一致**的显性断言。真实模型
**27/27 连续两轮**，关键词判据与审查器**零分歧**。报告
`evidence/2026-10-24-batch4/ai-content-accuracy.md`。

**编辑卡改「清单式」（用户选定方案 B）**：卡头结论行 + 明细行、条目进 `MutedBlock` 分块、
行编号、`LfSoftButton` 新增 `dense` 档。**看图抓到 5 个测试抓不到的问题并修掉**。实帧
`device/22~24`；APK **vc4064 系列**（三包 `sha256sum -c` OK，x86_64 已装自有 AVD 验证）。

**AI 记忆专项（同日第五次追加）**：实测发现**记忆系统实际上不工作**——存了口味偏好与
过敏、问「今天吃什么」时**一条都注入不进去**（bigram 零交集 ⇒ 门控 ⇒ 只剩置顶/importance≥80，
而默认是 50）。判定为**判据错误**，改为**领域兜底 + 上限 4 条 + 领域信号强度排序**；
召回 **6 红 → 17 全绿**。写入侧修「常去窗口被当成新建地点」，真实模型 **22/22**。
审查器补 `implausiblePortion` / `vagueSlot`（13 → 19 条）。报告
`evidence/2026-10-24-batch4/ai-memory-effectiveness.md`。APK **vc4065 系列**。

**2026-10-25 GOAL（第三轮任务书）**：[`docs/61`](61-goal-round3-2026-10-25.md)
—— 可直接粘贴执行的完整任务书：先读清单、执行纪律（先红后绿/变异验证/看图）、
**四批施工顺序**、6d 卡片关联的 7 条硬要求、**需要用户先定的 3 件事**、验收清单、
允许停止的三种情况。

**2026-10-25 第二轮核查 + 修复文档**：[`docs/60`](60-pending-fixes-round2-2026-10-25.md)
—— 用户 25 项需求**逐条核查**（读代码找文件:行证据）：**9 项已完成 / 14 项未完成 /
2 项待实帧确认**。每条未完成项含：现状证据、根因、方案、验收判据、风险与回滚；
最该先做的是**卡片关联**（应用「记一餐」时提示先创建食材），最易做的是**版本号**
（根因是我构建时漏了 `--dart-define=APP_VERSION`）。

**2026-10-25 改动复核 + 待修复清单**：[`docs/59`](59-pending-fixes-2026-10-25.md)
（未完成项逐条：现状证据/根因/方案/判据/风险，含 3 项待用户裁决）+
`evidence/2026-10-24-batch4/review-2026-10-25.md`（复核报告：**变异验证 3 项全红**
证明修复有效；如实登记**我自己的 3 个错误**，其中一条是「结论完全说反」）。
**食材行按方案 B 实现**（大热量 + 三色点宏量，7 条测试）。

**GitHub 仓库（2026-10-25）**：`https://github.com/xiaopeng66/localfit-ai`（**private**，
`main` = `3fe552a`，2803 文件）。**根因是全局 git 代理失效**（`127.0.0.1:7897` 端口在监听
但不转发），GitHub 操作需 `-c http.proxy= -c https.proxy=` 绕过。上传前排除 7.2G 上游数据
快照（`.git` 3.4G → 195M）。**待裁决**：public/private（在线更新匿名读取需 public）。

**编辑卡按设计稿 B 1:1 重做（用户纠正「你这改的根本不是方案 b」）**：逐条比对发现 6 处偏离，
根因是**行按命令渲染而不是按食物**。用户裁决「改成子条目展示，但按钮只在组级」。已实现卡头三层
（kicker / 15px 标题 / 食物明细）、一行一个食物 + 白底描边序号、mini 描边组按钮、卡底撑满、液体 ml。
**两个预算门禁真实报红（字号字面量、无 Key 控件），按规则修不绕过**。实帧 `device/22~24`
逐项对照一致；APK **vc4066 系列**。
**未做**（如实）：arm64 真机、帧率采集、iOS 构建；设备上的 AI 帧因 App 内未配 key 仍按豁免处理；
**多轮改动后未重建 APK**（全量 gate 因 `Out of memory` 未过，已绿口径为 `test/app + test/features` +2834）。
设备实帧见 `evidence/2026-10-24-batch4/device/`。

**2026-10-21/22 食物库别名列 + 名称格式 + 分类硬门禁（ADR-037，最新）**：官方 CSV **10 列**
（别名紧跟食物名称）、别名落 `food_aliases` 且三处可写、分类只认十档（其他值整行拒绝并汇总）、
名称统一 `主名（备注）`、存量 23,919 条一次归一化（116 改名 / 135 分类纠正 / 6,711 行派生别名 /
43 条待复核）。决策 [`ADR-037`](DECISIONS.md)；证据
[`evidence/2026-10-21-food-library-audit/`](evidence/2026-10-21-food-library-audit/)；
门禁 `review-food-alias4` `+2869 ~66`；APK **vc2050 / vc4050**（未发布）。

**2026-10-21 食物库存储格式定死（ADR-036）**：存储 13 字段、schema **30**（DROP 17 列）、
官方导入 **9 列**（前 8 列与用户那份文件同序）、分类只剩 `FoodCategory` 十枚举一个指标、
详情卡撤掉分类文字（种类只由顶部胶囊筛选）、`food_aliases` 只读不写的事实澄清。
决策 [`DECISIONS.md` ADR-036](DECISIONS.md)；契约 [`docs/03`](03-data-and-contracts.md) §3.1/§3.2、
[`docs/32`](32-ui-redesign-round5-plan.md) §2·74 横幅、[`docs/21`](21-ui-redesign-spec.md) §5.3；
证据 [`evidence/2026-10-21-food-schema-adr036/delivery.md`](evidence/2026-10-21-food-schema-adr036/delivery.md)。
门禁 `review-food-schema5` `+2846 ~66`（format 0 / analyze clean / exit 0 / `changed_during_run: []`）；
APK **vc2046 / vc4046**（未发布）。**注意**：vc4043/vc4044 两个包漏 Kotlin 插件、装上一启动就崩，
已作废移出 `release/`（sha256 与根因见证据 §6）。

**2026-10-20 全应用审查 → 修复 → 二次验收**：
[`docs/47`](47-review-plan.md)（十四维度审查计划）、[`docs/48`](48-review-report.md)（报告 +
P0/P1/P2 台账）、[`docs/49`](49-remediation-plan.md)（14 条 P1 + 2 条 P2 提前修复方案）、
[`docs/50`](50-second-iteration-acceptance.md)（逐项闭环 + 指标对比 + 残留）；证据在
[`evidence/2026-10-20-full-app-review/`](evidence/2026-10-20-full-app-review/)。
**结论**：P0 = 0；P1 发现 14 条（另 1 条复验证伪）→ **闭环 14/14**；P2 27 条全闭环（2026-10-21 复核轮）。
门禁 `fix-p1-a2` `+2802 ~66` → `fix-p1-b2` `+2803 ~66` → `review-final3` `+2803 ~66` → `review-p2` `+2839 ~66` → **终态 `review-final` `+2839 ~66`**
（均 format 0 / analyze clean / exit 0 / `changed_during_run: []`）。APK vc2041 / vc4041（未发布）。

**最新实施**：用户已明确选择 Round7 A 完整主稿，按 [`迁移指导`](33-round7-native-ui-migration-guide.md) 阶段 0–7 实施。阶段 0 原始字节备份与本次 Flutter 2174 passed / 11 skipped 基线已完成；**阶段 1 共享原生层已收口**——`phase1-gate-2`（format 0 changed / analyze clean / 2200 passed / 12 skipped / exit 0、`changed_during_run: []`）、A 三层 CSS 对账随 `test/app/design` 211 项全绿、组件矩阵 72 张（浅/深 × 1.0/1.5/2.0 × 320/360/390/430）逐张实看通过、隔离变异与两次 golden 实看更新留 SHA。**阶段 2A 今日页已收口**——`2a-gate-11`（format 0 changed / analyze clean / 2226 passed / 12 skipped / exit 0）、今日页整页 24/24 帧逐张实看通过、三条测试先行 RED 与六项隔离变异（逐字节还原复核 SHA）在案。**阶段 2B 饮食·记录页已收口**——按 A `nutritionRecords()` 六步落地（子页签行 / 共享热量卡 / date-strip + selected-date / 趋势卡与分析卡 / 槽位分组与 `_ItemRow` 去截断 / 页序重组与页级间距），`2b-gate-order-3`（format 0 changed / analyze 0 问题 / **2268 passed / 12 skipped / exit 0**、`changed_during_run: []`；文档同步后的终态门禁 `2b-gate-order-4` 同数同口径，另定向复跑 Key 三方对账 + 500 行预算 3/3 绿）、记录页关键帧逐张实看 + 今日页 24 帧像素对账（仅 0.04% 像素变化 = 夹具用餐时间），十条测试先行真实 RED（含回归抓出的「历史日仍画加号」实现缺陷）与五项审看发现的既有缺陷（⑤页首卡全宽贴边 ⑥日期行→时间线 8dp ⑦时间线→分析卡 0dp ⑧趋势日号折行压 hint ⑨分析格数值被 ellipsis 裁字）在案。**阶段 3 剩余（3-2 收口项与识别/CSV）与阶段 4–7**、原生设备验收、480 矮视口整页组合和最终 APK 尚未完成。**阶段 3 步骤 1 饮食·菜单 tab 已收口**——按 A `nutritionMenus()` 改造（hero 退场改段头三件 / 槽卡骨架与 `.dish-action-row` / 页尾 `.list-link` + note，决策 D25–D30），`3-red-menu-1` 4 组 9 条真实 RED → `3-green-menu-2` 10/10 → **首拍渲染抓到缺陷 ⑩（`Wrap(spaceBetween)` 收缩到内容宽 ⇒ 两端对齐没落地，补三条几何断言先红 280.75/263.0/105.0 vs 448.0）并修** → 定向回归 61/60 → 门禁三次收敛（`3-gate-menu-3` 612/2278 → `3-gate-menu-4` **抓到捕获件未格式化** → **终态 `3-gate-menu-5`：format 613 文件 0 改动 / analyze 0 问题 / 2279 passed / 12 skipped / exit 0、`changed_during_run: []`**）；菜单 tab 专用捕获矩阵 24 帧（`renders/3a-step2`）实看 8 张裁片通过、未逐张静看的 16 帧如实登记，注释-only 编辑后重拍 `renders/3a-step3` 与审看帧逐字节一致。**阶段 3 步骤 2 食物库 tab 的 3-2a/3-2b 已收口**——按 A `nutritionFoods()` 改造：3-2a 落分类筛选（数据面可选分类 `WHERE` + `_fromMainRow` 补 `category`，**修既有语义洞**：旧实现按分类筛会把用户导入的主库筛空）、共享 `LfFilterChip`/`LfFilterChipRow`、「N 种食物」结果头与空态两分支，并修缺陷 ⑪（结果头 2.0× 溢出 60px）；3-2b 落单卡 `.food-list`（`FoodListCard`/`FoodListRow`，1px `--track` 线不占布局、末行不画）+ 行几何按 A 收口（56、方框 40×40 R12 `--bg`、环心 10、名称 w600、警告图标 `info_outline` 而色仍 `warning` = D38）+ 两条数据路径与骨架同件同形。真实 RED 两组（`3c-red-food-1` 18/12、`3c-red-food-2` 24/2：行距 64 vs 56、滑条 3,165,134.5 vs 49,464×56）；**渲染首拍抓到缺陷 ⑫（共享层既有）**：分类胶囊标签从不继承主题字体（`ButtonStyleButton` 替换环境 `DefaultTextStyle` + `LfText.caption` 无字体族 ⇒ 测试引擎里 `.notdef` 空方框），RED `3c-red-chipfont-1` → 修 → `3c-green-chipfont-1` 26/26；**回归抓到的是判据缺陷**（`SliverPrototypeExtentList` 原型不上屏 ⇒ 矩形 NaN 被遮挡判据夹到视口底，判据改为跳过原型叶子 + 新增「剩余叶子矩形必须有限」，`3c-judge-red-1` 证明仍对真内容变红）。定向回归 899/1/0；**终态 `3c-gate-order-5`：format 621 文件 0 改动 / analyze `No issues found!` / 2303 passed / 12 skipped / exit 0、`changed_during_run: []`**；食物库矩阵 `test/round7_foodlib_capture_test.dart`（24 帧整页 + 4 帧孤立骨架）在 `renders/3b-foodlib/` **28 帧逐张实看**（配 47 张裁片），frames5/frames6 与 frames4 **sha256 全等（28/28）**；两处捕获夹具缺陷（骨架呼吸相位、`AnimatedTheme` 200ms lerp）已修并写进注释。**阶段 3 步骤 2 食物库 tab 的 3-2c 已收口**——页尾 `.library-footer` 两链与空库行动钮按 A `app.js:201` 落地：新共享件 **B11 `LfLinkButton`**（A 实拍量取逐项同值：44 高 / 12 w500 / mint-700→暗色 mint-400 / 图标 16+间距 5 / 10px 副行）、**偏离 A 流内页尾落成贴底条**（D44：`itemCount` 是总数 ⇒ 流内页尾是死入口；条承担底栏预留、列表末端只留 8）、`importFoods`/`manageFoods` 接既有 CSV 与共享弹层通路（`food_data_flows.dart` 提件，**21 列契约与单事务守卫一字不动**、设置页标题与 Key 不变）、空库槽位接「导入食物数据」（`food-empty-import`）；测试先行编译红 → 行为红 `3d-red-batch-2/3` → `3d-red-all-1` +14 -7 → 首绿六文件 +89；**全量门禁抓到真回归缺陷 ⑬**（320dp+2.0× 条把空态挤溢 58px ⇒ 空态改 `Center + SingleChildScrollView` 可滚宿主、放得下逐像素不变；RED `3e-red-empty-squeeze-2` 233px / GREEN `3e-green-empty-squeeze-3` +26）与三处判据缺陷自纠（量 `Padding` 盒、直搜路径无列表键、`AnimatedTheme` lerp）；**门禁覆盖自纠**（捕获矩阵出生时间晚于 `3d-gate-footer-3` ⇒ `3d-gate-footer-4` 当场抓到未格式化 ⇒ 格式化后重拍 12 帧 SHA256 全等）⇒ **终态 `3d-gate-footer-5`：format 625 文件 0 改动 / analyze `No issues found!` / `+2327 ~12: All tests passed!` / exit 0、`changed_during_run: []`**；`renders/3c-footer/` 12 帧逐张实看通过 + A 参照实拍 1 张 + 裁片 3 张；320dp+2.0× 极限组合登记为限制（列表/空态区 ≈58–82dp：不溢出、可滚、可达但局促；根修 = 页头并进滚动体 = 范围变更候选，本轮不做）。**阶段 3 步骤 2 食物库 tab 的 3-2d（详情弹层与新建/编辑表单）已收口**——按 A `app.js:369/375` 收口：弹层首行标题 + hero（52 **R16** `--bg` 图标块 / **20px w600** 名 / **12px muted** meta + 徽标，分类判据与列表行同一处）、营养面板（r16 + 1px `--border` 实描边 + `--bg` + 内衬 18 + 环列 56 + 间距 24；环心 **14px**；宏量行 A 档：点 7 / 标签 12 / 值 14 w600 右端 / 行高铁定 17——`blockHeight` 67 与「环心 = 三行块中心」算式不动）、口径注横跨整宽**居中**（共享句单源）、行动行（1px `--track` 上边线 + `padding 12 0 2` + 两枚 **46 高**等宽钮 + 图标；仍 B6/B7 文字型 = 2026-10-03 裁决）、表单 2×2 数字网格 + 只搬成立三段的注；共享件四处**可选**参数（环心大档 16→14、`FoodDensityScaleNote.textAlign`、`FoodCategoryIcon.radius`、`_MacroDotItem` 仅 expanded 档、`LfTextButton`/`LfDangerButton.tapTargetSize`）默认值零迁移。测试先行 `3dd-red-structure-2` **9/9 真实 RED**（四处新键不存在 / 环心 16 vs 14 / `TextAlign.center` vs null / 表单两格相距 84）；**判据自纠 1 处**（行动行钮 48 vs A 46 = Material 默认触达盒撑高布局盒 ⇒ 可选 `shrinkWrap`，判据未放宽）；定向回归 `3dd-reg-1` **974 通过 / 1 跳过 / 0 红**（含 320dp+2.0× 两条大字审计与 500 行预算）；渲染矩阵 `3dd-cap-1` **12 帧逐张实看通过**（详情 8 + 表单 4，每帧哨兵）+ A 参照实拍 1 张，format 后重拍 `3dd-cap-2` 与实看帧 **SHA256 全等 12/12** ⇒ **终态 `3dd-gate-3`：format 627 文件 0 改动 / analyze `No issues found!` / `+2338 ~12: All tests passed!` / exit 0、`changed_during_run: []`**（2338 = 2327 + 11）；并登记**卡/详情 `canJoinPlan` 口径不一致**为既有行为观察项（不在视觉改造里改语义）。**3-2 收口已完成**——`docs/21` 一次同步（§3.8 新增 **B11 `LfLinkButton` 行** + 硬规则；§3.11 追加 3-2a–3-2d as-built 块与**新增 Key 全表**、残留刻度 900→1000 更正；§5.2 追加 as-built 块并给旧「原型卡取最高变体 ≈171dp」条加「已被 3-2b 取代」标注）、`LfEmptyState` 标题字重按 A `strong` 改 **14 w600**（测试先行 RED `w600 vs w400` → `LfText.bodyStrong` → 22/22；3-2c 的 12 帧整批重拍**恰 2 帧变化**、实看＝标题加粗）、**D35 基准**新件 `category_benchmark_test.dart`（2 万行 × 十档、分类列无索引：count **8 ms** / 首页 **9 ms** / 深页 **4 ms**，全在 <1000ms 护栏内）⇒ **终态 `3dd-gate-5`：format 628 文件 0 改动 / analyze `No issues found!` / `+2340 ~12: All tests passed!` / exit 0、`changed_during_run: []`**。**阶段 3 · 3-3（拍照识餐 · 识别/编辑）已完成**——A 未画，按 docs/33 §3.2 同主题补齐：状态覆盖审计逐项在册（处理中/取消/无结果/匹配歧义/剩餐净摄入/候选变更/保存失败/「已保存但清理未完成」独立阻断/只有确认才入账），新建 14 帧捕获矩阵逐张实看，修 **缺陷 ⑭**（两个编辑器的卡/分析/餐次/备注四键硬编码 ⇒ 随 `keyPrefix` 唯一，主编辑器键名不变）与 **缺陷 ⑮**（本地食物弹层行文字空方框，与 3-2b ⑫ 同族 ⇒ style 并入主题字体）；**⑯**（分析按钮在途/候选态）隐藏方案经回归 **8 条判据证伪**后收回并登记待裁决（收回后的在场契约钉进新判据）；测试先行 `3e-red-structure-1` **4 红 1 绿** → `3e-green-structure-3` 5/5，定向回归 `3e-reg-scan-2` **426/0**，重拍 14 帧 **11/12 逐字节相同、1 帧变化（空方框→真字形）** + 2 帧新增实看（净摄入 120g 正确）⇒ **终态 `3e-gate-3`：format 630 文件 0 改动 / analyze `No issues found!` / `+2347 ~12: All tests passed!` / exit 0、`changed_during_run: []`**；登记观察项 ⑰（行动行「编辑」与逐项修正重复）/⑱（「按净摄入入账」两行）。**四项裁决（`canJoinPlan` 口径、分析按钮文案、『修正识别』术语、净摄入钮单行）已按用户 2026-10-15 批准落地**：详情/卡同一来源（域层 getter → 显式字段）、有候选时分析钮写「重新分析」、行动行统一「修正识别」、`LfPrimaryButton` 新增可选 `fitLabel`（单行兜底）；`3f-red-rulings-2` 真实 RED → 回归 **943/1/0** → 终态 **`3f-gate-5`：format 630 文件 0 改动 / analyze `No issues found!` / `+2352 ~12: All tests passed!` / exit 0**（帧三批对账 10/12、6/14 → 10/14，变化面恰为改动面）。**3-4 CSV 导入预览已收口**——状态复核（取消/解析失败/写入失败单事务/成功刷新/三本账 + 重复样例 + 两条政策，**21 列契约与去重规则一字未动**）+ 6 帧逐张实看，修 **缺陷 ⑲**（320dp+2.0× 下三本账与两条动作钮同排不等高 ⇒ `IntrinsicHeight` + `stretch`；RED `Expected <0.5> of <97.0> / Actual <125.0>` → 4/4 绿；回归 `3g-reg-csv-1` **738/1/0**；6 帧重拍 **5/6 相同、恰 1 帧变化**）；`docs/21` 随本片一次同步（§3.8 新增 `LfPrimaryButton.fitLabel` 行；§3.11 把 `canJoinPlan` 观察项改判为已裁决落地）⇒ **终态 `3g-gate-3`：format 631 文件 0 改动 / analyze `No issues found!` / `+2354 ~12: All tests passed!` / exit 0、`changed_during_run: []`**。**阶段 3（菜单 / 食物库 / 识别 / CSV + 四项裁决）至此全部完成**。**阶段 4：训练页已收口**——A `app.js:209-268` 对账（§5.5 全部 Key 在库在册），18 帧逐张实看，修 **缺陷 ⑳**（容量图空柱被 `FractionallySizedBox(heightFactor: 0)` 压成 0 ⇒ 高度显式算：空日 3px / 有训练下限 6 / 封顶 72）与 **缺陷 ㉑**（2.0× 下三段统计被 ellipsis 裁成「0…」⇒ `FittedBox.scaleDown` + 列间 8）；**判据自纠并收回竖排方案**（回归证伪、不放宽判据；收回后 558/0）；既有颜色判据结构迁移（`Container`→`DecoratedBox`，颜色断言一字未改）；终态 **`4a-gate-8`：format 633 文件 0 改动 / analyze `No issues found!` / `+2360 ~12: All tests passed!` / exit 0**。**阶段 5：AI 创作与对话已收口**——A `aiPage()`/§5.7 对账（Key 全在册），11 帧逐张实看，修**主题层缺陷 ㉒**（`appBarTheme.titleTextStyle` 写死自建样式不带族 ⇒ 裸 `AppBar` 标题在帧里是空方框；删显式样式走 M3 默认 ⇒ 族随主题，**全仓 10 处裸 AppBar 一并修好**）；提案卡（docs/23 §5 / docs/33 §3.5）逐条状态与失败原因实看对账；宽回归 805/0；终态 **`5a-gate-2`：format 634 文件 0 改动 / analyze `No issues found!` / `+2364 ~12: All tests passed!` / exit 0**。**阶段 6 首批（我的/设置页 + 空态语言统一）已收口**——设置页 6 帧实看 + 修**缺陷 ㉓**（emoji 代替图标语言：隐私条 `🛡` 成空方框、5 处空态走旧 `AppEmptyState` emoji 圆 ⇒ **6 处换 `LfEmptyState`**（A 图标块）+ 隐私条换 `Icons.shield_outlined` + 欢迎语去 `😊`）；RED→3/3，回归 **1423/0**，帧对账（AI 2/训练 1 帧变化恰为修改面）+ 三张空态帧实看；终态 **`6a-gate-4`：format 637 文件 0 改动 / analyze `No issues found!` / `+2369 ~12: All tests passed!` / exit 0**。**阶段 6 余下（引导页 / 资料编辑）已收口**——6 帧实看；**㉓ 收尾**（引导页目标卡 emoji → 图标）与 **㉔ 帧保真缺陷**（资料编辑「训练目标」三行 `□□`：`AppTheme` 不内置族（§2.6.1）但把样式冻结在 `listTileTheme`、`ListTile` 替换环境样式 ⇒ 测试帧空方框；修法＝**捕获件注入族、生产不动**）；真 RED `6b-red-goal-5`（`Expected 'Round7LocalCjk' / Actual null`）→ 9/9；终态 **`6b-gate-3`：format 638 文件 0 改动 / analyze `No issues found!` / `+2373 ~12: All tests passed!` / exit 0**。**阶段 6 末批（AI 配置弹层）已收口——阶段 6 全部完成**：7 帧实看 + 修**缺陷 ㉕**（未配置时 Key 栏占位是 `••••••••`，把「没存过」伪装成「已保存」⇒ 改为「未配置 · 粘贴你的 API Key」；留空=保持语义未动）；真 RED（`Found 1 widget with text "••••••••"`）→ 6/6；终态 **`6c-gate-2`：format 639 文件 0 改动 / analyze `No issues found!` / `+2375 ~12: All tests passed!` / exit 0**。本阶段累计修 ㉓（emoji→图标）/㉔（主题冻结样式帧保真）/㉕。**阶段 7 已完成**：全量回归 **`7-gate-full-2`（format 640 文件 0 改动 / analyze `No issues found!` / `+2376 ~12: All tests passed!` / exit 0）**；设备与权限行补 4 帧实看；**最终 APK 已构建并交付**——`release/localfit-ai-vc2004-20261015-arm64-release.apk`（vc 2004 / 13,235,271 B / sha256 `800297304041bc4031338803a2a623f0d3ba027a2f56524e42d7c5a1dbdc5fbe`，签名仍 debug key）；**模拟器设备验收 16 帧**（建档→今日→饮食→训练→AI→我的 + 480dp 矮视口，⑳/㉓ 获真机见证）。**未做（如实）**：设备级键盘（模拟器 IME 不弹）/弹层拖动/读屏、真机安装升级与隔离数据保留、真实 AI 端到端（禁止项）——**阶段 0–7 的实做面至此完成**、原生设备验收与最终 APK。、A 的「记录这份食物」主行动（新功能）、原生设备验收与最终 APK。当前证据见 [本轮实施记录](evidence/2026-10-14-round7-native-implementation.md)。[先前评审](evidence/2026-10-14-round7-native-ui-review.md) 的“仅文档/A候选/原生未开始”只代表该历史任务，不覆盖本次用户的新实施授权。

**批次 B 落地（2026-10-15）**：`menu.snapshot.publish`（结构化菜单草案 JSON → 解码 → 发布快照，与文件导入同源；发布当日即菜单 tab「今日推荐」的 active 快照）+ `ChatEditArgSpec` 两处加法（`maxLength`、**`jsonObjectAllowed`**：真模型发对象形态也收）；`dish.nutrition.set`/`daily.plan.set` 按核查改判不做（登记）。**注册表现共 34 条**；mock 28/28；**实时矩阵 13/13（33 条命令真写库）**；`rB-gate-2`（format 638 文件 0 改动 / analyze 干净 / `+2390 ~29` / exit 0）；**APK vc4014**。

**AI 接口补全（2026-10-15，按 docs/34 落地）**：注册表 **23 → 33 条**——批次 A 训练域 6 条（开始/记组/结束会话 + 计划编排与改名）、批次 C 4 条（自建食物改删**仅自建行** + 身体资料 + 每日目标）、批次 D 快照加两段；同轮修快照 id 别名回填与 `FoodWriteFailure` 逃逸两个接口缺陷；**批次 B 三条改判登记**（一条不需要、一条建议单列批次、一条无存储不可实现）。mock 24/24 + 隔离变异红绿 + **实时矩阵 12/12（32 条命令真写库）**；`rACD-gate-3`（format 638 文件 0 改动 / analyze 干净 / `+2386 ~28` / exit 0）；**APK vc4013**。

**Round8 追加轮（2026-10-16 下半场）**：用户追加指令「纯文本回复也要给候选按钮 + 缺实体兜底扩到更多种类，
且对话只要涉及修改就必须正确识别指令、不许空回文字」。落地：①**三层保障**（协议硬规则 / App 自动带提示
重跑一次 / 气泡「让 AI 给出可应用的修改」词条 + 从落库消息重算 ⇒ 重启仍在）；②**缺实体兜底 1 → 4 类**
（食材 / 动作 / 地点 / 窗口，各自开预填名称的既有表单）；③自查优化（残留抗重启、协议编号统一、动作表单去重）。
实时矩阵 **12/15**（新增场景 ⑮ 实证「催信封」提示有效）。终态门禁 `r8-gate-b3`：format 645 文件 0 改动 /
analyze `No issues found!` / `+2437 ~31 全绿` / exit 0 / `changed_during_run: []`。

**Round8：AI 推荐交互 + 五页缺陷修复（2026-10-16）**：用户在真机实测后给出 21 条缺陷/需求，
计划与逐片台账见 [`docs/35-ai-recommend-and-polish-plan.md`](35-ai-recommend-and-polish-plan.md)，
执行证据见 [`evidence/2026-10-16-round8-ai-recommend-and-polish.md`](evidence/2026-10-16-round8-ai-recommend-and-polish.md)。
覆盖：AI 对话（chip 行/功能卡小卡/长按复制/提案卡卡壳/**推荐按钮**与缺食材兜底/**口语=命令**/
**图片真实上行 S1**）、今日页（体重卡周期注与浮窗与月轴/饮水步数一行式与达标徽标/步数读取根因/
弹层最小底衬）、饮食页（趋势目标标签移出柱区/餐食卡减噪/复用弹层卡片化）、训练（计划目标必填+
整库候选+共享 `PlanDraftCard`）、我的（头像昵称并入资料页/训练目标大卡/删水分卡）。
**终态门禁 `r8-gate-final2`：format 643 文件 0 改动 / analyze `No issues found!` /
`+2422 ~30: All tests passed!` / exit 0 / `changed_during_run: []`**。

**实时 AI 控制矩阵 + 控制面方案（2026-10-15）**：`test/ai_live/ai_live_control_matrix_test.dart`（默认跳过）把 **23 条编辑命令逐条真跑**（真模型→App 协议→App 解析→App 执行器→真库）：**9/9 场景、22 条命令全部写库成功**；修掉**快照 id 别名回填**这一真缺陷（`water:`/`wplan:` 等，测试先行 RED → mock 18/18 → 矩阵转✓）；另两类（散文+JSON、过期 id）确认非 App 缺陷。**控制面审计与补全方案**见 [`docs/34-ai-control-surface-audit-and-plan.md`](34-ai-control-surface-audit-and-plan.md)（能控制什么 / 未接入清单 P1–P3 / 四批补全方案含验收 / 永不接入的边界）。

**真实 AI 第二轮（river.ai）**：`zai-org/GLM-5.3-Flash` **4/4 全绿**（探针/流式/**编辑信封纯 JSON、`workout.plan.create` 用本地 id**/计划草案）；`deepseek-ai/DeepSeek-V4.1-Flash` 3/4（信封项因「散文+JSON」被严格解析丢弃）。⇒ 新增范围项 **R13**（解析严肃度是否放宽；建议保持严格）待裁决；设备 UI 全流程仍 blocked（宿主 3 模拟器）。本轮未改代码。

**死代码清理 + 真实 AI 测试（2026-10-15，用户指示）**：删 ≈660 行死代码（`AppEmptyState`+2 测试文件、`lf_bar_chart`/`progress_bar`/`ai_provenance_block` 三整件、`AiWorkbenchHub`、`AiDraftRejected`、`MealCard`，保留骨架）；**真实 AI**（用户授权、Key 走环境变量不入库）：探针/流式/编辑信封/计划草案 **4/4 绿**，抓到并修「协议未要求整段回复只放 JSON」的真实缺口（`workout.plan.create` 三天计划被解析出）；`glm-5.3-flash` 在该供应商 503 不可用，实测可用模型 `deepseek-v4.1-flash`；新增 `test/ai_live/`（默认跳过）；**设备 UI 全流程 blocked（宿主 3 模拟器致输入乱码 + system ANR）**，设备侧只验到字段输入与真实网络错误。`r9-gate-3`（format 637 文件 0 改动 / analyze 干净 / `+2378 ~16` / exit 0）；**APK vc4011**。

**批次 5/6（2026-10-15，按用户裁决落地）**：**R1** 计划卡今日卡 CTA、**R2** 训练统计弹层补口径说明句与肌群 kg、**R5** 只读「体重记录」弹层（身份卡当前体重入口）、**R11** 步数卡「查看详情」→ 共享的「步数与身体活动」弹层；**同批修两个既有缺陷**：㉖ 肌群分布恒为空（`exercises: const []`）、㉗ 训练统计容量图无有限高（真实数据下必崩）；R4/R6/R7/R8/R9/R12 按裁决保持并登记。`r7v6-gate-2`（format 642 文件 0 改动 / analyze `No issues found!` / `+2390 ~12: All tests passed!` / exit 0）；今日页 24 帧变化（恰为 24 张 today 帧）+ 训练/设置新增弹层帧并实看；**APK vc4009**；**设备实测 3/3**（步数卡查看详情、体重记录弹层）。**R1/R2 设备帧 not run**（模拟器无计划/无历史，如实登记）。

**批次 4（2026-10-15 续批）**：训练历史行 → 「训练回顾」只读弹层（`training-review-sheet`，估算消耗如实写「—」）+ AI 页两条 starter 行（只预填、不替用户发送）；`r7v4-gate-2`（format 640 文件 0 改动 / analyze `No issues found!` / `+2385 ~12: All tests passed!` / exit 0）；AI 欢迎区 2 帧变化 + 新增回顾弹层帧并实看；**APK vc4008** 覆盖安装成功；设备实测 2/2（点 starter 真的预填且未发送）；**训练回顾设备帧 not run**（模拟器无历史，如实登记）。

**批次 3（2026-10-15 续批，纯呈现）**：训练计划卡补 A 的**周安排块**（七枚日签 + 今日行，计划日集合与休息日图例同口径）；`r7v3-gate-1`（format 640 文件 0 改动 / analyze `No issues found!` / `+2383 ~12: All tests passed!` / exit 0）；训练矩阵 3 帧变化 + 新增 320×2.0 计划卡帧并实看；**APK vc4007** 覆盖安装成功；**设备级该卡 not run**（模拟器无训练计划，无从渲染，如实登记）。**范围变更矩阵 12 项（R1–R12）已单列进台账 §6 待裁决**。

**批次 2（2026-10-15 续批，纯呈现）**：C6 健康/成就文案与计数、C9 AI 页标题+副题与「AI 创作」chip、C13 动作库「N 个动作」计数均已收口（`r7v2-gate-1`：format 640 文件 0 改动 / analyze `No issues found!` / `+2381 ~12: All tests passed!` / exit 0；帧对账 AI 6/9、设置 4/6、动作库 4/4；**APK vc4006** 装入模拟器设备实测 4/4，含「AI 创作」chip 点开画廊）。**C11 饮食页页头改判为待裁决**（与 2026-10-03 胶囊行置顶要求冲突）。

**最新追加（2026-10-15）**：**「A 全部视图 ↔ App 全部页面」逐页对账已完成并落盘**——A 侧 8 主视图 + 23 弹层截帧（`renders/a-verify/`）+ App 侧设备帧 + 两份带 `file:line` 的只读跨页台账；**诚实结论：阶段 4–6（训练/动作库/AI/我的·设置/引导）此前只做「渲染审看」、未做逐元素对账，是确认存在的验证缺口**。已收口**纯呈现修复批次 1（4 项）**：训练页分段 `我的计划/训练历史`、动作库行副题「先了解动作，再开始训练」、设置页页头「我的 + 关于你，也关于你的数据」、页尾「让每一次记录，回到你自己。」（**不搬** A 的「本地优先」徽章，docs/33 §3.8）；`r7v-red-1` 真 RED → `r7v-green-1` → **`r7v-gate-4`（format 0 改动 / analyze `No issues found!` / `+2378 ~12: All tests passed!` / exit 0）**；**APK 0.1.0+5**：`release/localfit-ai-vc2005-20261015-arm64-release.apk`、`-vc4005-…-x86_64-emulator.apk`（已装模拟器并在设备上实看四处改动）。台账（含表 B 已登记反向偏离 / 表 C 待裁决范围项 / 表 D App 多出）：[`A↔App 逐页对账台账`](evidence/2026-10-15-round7-ab-page-ledger.md)。

**最新修复记录**：[`2026-10-13 整体回归后的 11 类缺陷修复`](evidence/2026-10-13-regression-repairs.md)。91 项新增回归、113 个有效行为变异、全量 2174 passed / 11 skipped，修复版 APK 构建与隔离安装通过；**Android GUI 验收受观察工具阻塞，未完成**。下表长段落保留各包当时记录，其中 T11「待新表头」已被 21 列落地取代，T10「手动计划返回不刷新」已由本次 B02 修复，不能继续当当前阻塞。

## 0. 权威源与读取顺序

| 权威 | 文件 |
|---|---|
| **本次文档评估与未来路线** | [`docs/33-round7-native-ui-migration-guide.md`](33-round7-native-ui-migration-guide.md)。原生实施进行中：阶段 0/1、2A 今日页、2B 记录页、3-1 菜单 tab、3-2a–3-2d 食物库（分类筛选/结果头/空态 + 单卡 `.food-list` 与行内分隔 + 页尾两链与空库行动钮 + 详情弹层与新建/编辑表单）与 **3-2 收口**（`docs/21` 同步、`LfEmptyState` 字重、D35 基准）、**3-3 拍照识餐（识别/编辑）**、**四项裁决（2026-10-15）**与 **3-4 CSV 导入预览**完成（**阶段 3 收束**）、**阶段 4 训练页**、**阶段 5 AI**、**阶段 6 全部完成**、**阶段 7 全量回归与设备验收与最终 APK 完成**，逐片证据见 [本轮实施记录](evidence/2026-10-14-round7-native-implementation.md)。 |
| **现有原生行为基线** | [`docs/32-ui-redesign-round5-plan.md`](32-ui-redesign-round5-plan.md) 的已落地裁决与 §9 回归修复；结合当前代码/测试，不能把早期未完成记录当作现状。 |
| 全应用审查与修复（2026-10-20） | [`docs/47`](47-review-plan.md) / [`docs/48`](48-review-report.md) / [`docs/49`](49-remediation-plan.md) / [`docs/50`](50-second-iteration-acceptance.md) |
| 长期目标与硬约束 | [`GOAL.md`](../GOAL.md) |
| 产品/数据/AI/验收契约 | [`docs/07-localfit-2.0-development-spec.md`](07-localfit-2.0-development-spec.md) |
| UI 结构与设计资料 | [`docs/21-ui-redesign-spec.md`](21-ui-redesign-spec.md)（2026-10-14 起含「Round7 A 接管」节 = 目标视觉唯一依据）+ `ui设计/pages/*.html`（迁移期仍是现有测试输入，逐页随阶段迁移）；[`design/round7`](../design/round7/README.md) 的 A 完整主稿已由用户选定并按 docs/33 接管视觉。 |
| AI 协议 / 对话式编辑 | [`docs/24-ai-provider-protocols.md`](24-ai-provider-protocols.md)、[`docs/23-chat-universal-edit.md`](23-chat-universal-edit.md) |
| 实时状态与交接 | [`STATUS.md`](../STATUS.md)（根目录，**只有它**能说「做到哪一步」） |
| 决策日志 | [`docs/DECISIONS.md`](DECISIONS.md)（追加式） |

**规则**：下表「权威性」为「无」的文件**不具备规范效力**——它们记录的是当时怎么做的，
不是现在必须怎么做。现有业务以 `docs/32` 已落地裁决和当前代码/实测为准；`docs/33` 提供候选视觉迁移路线，不提前覆盖现有行为、设计输入或执行授权。冲突先记录，不按旧方案恢复已退役功能。

## 1. 常青文档（长期有效）

| 文件 | 主题 | 状态 | 权威性 | 备注 |
|---|---|---|---|---|
| [`67-unified-nutrition-master-canteen-catalog-feasibility-plan-2026-11-09.md`](67-unified-nutrition-master-canteen-catalog-feasibility-plan-2026-11-09.md) | **统一营养主库＋食堂供应目录可行执行方案**：复用 foods 每100g事实、供应按ID引用并维护份量／图片、旧每份菜品写入退役 | **方案稿／未实施（2026-11-09）** | 候选实施路线，不构成业务开工授权 | 默认决策、产品闭环、营养／份量契约、旧库及旧.lfb转换矩阵、P0–P5任务／先红断言／阶段门、AI旧卡片与推荐适配、验收和回滚；仅文档交付，后续开发须另行授权 |
| `01-product.md` | 产品定位 | 有效 | 有（产品层） | |
| `02-architecture.md` | 架构 | 有效 | 有 | |
| `03-data-and-contracts.md` | 数据与契约 | 有效 | 有 | |
| `04-roadmap.md` | 路线图 | 有效 | 有 | |
| `05-quality-and-release.md` | 质量与发布 | 有效 | 有 | |
| `06-token-efficient-development.md` | 高效开发约定 | 有效 | 有 | |
| `07-localfit-2.0-development-spec.md` | 2.0 契约总集 | 有效 | **有（契约）** | 食谱/计划整族已于 2026-10-04 下线（见其 §6 注） |
| `08-store-privacy-and-permissions.md` | 隐私与权限 | 有效 | **有** | 权限变动（P9 加计步、P10 删录音）必须同步此文件 |
| `09-release-and-device-checklist.md` | 发布与设备清单 | 有效 | 有 | **被测试读盘**，勿移动 |
| `21-ui-redesign-spec.md` | UI 规范（结构树/token/Key） | 有效，持续维护 | **有（UI）** | **被测试读盘**，勿移动；每轮改 UI 都要同步它 |
| `23-chat-universal-edit.md` | 对话式全量编辑（**37 命令**，注册表 `chat_edit_registry.dart` 为单一事实源） | 有效 | **有** | 2026-10-17：新增 `memory.remember` / `memory.forget`（docs/38 S11），协议规则 10/11，快照加「饮食偏好与忌口」「长期记忆」两段；2026-10-16：新增 `canteen.dish.nutrition`；`canteen.dish.create/update` 去 `priceYuan`（价格全删） |
| `24-ai-provider-protocols.md` | 三协议 wire 事实 | 有效 | **有** | §6 转写已删（P10）、§7 入口形态已改（P4），均以文内日期注为准；P11 补记「prompt 模板＝输出契约唯一载体」 |
| `33-round7-native-ui-migration-guide.md` | Round7 原生 UI 全量替换与收尾指导 | 指导文档已交付；原生实施进行中（阶段 0/1、2A 今日页、2B 记录页、3-1 菜单 tab、3-2a–3-2d 食物库、3-2 收口、3-3 拍照识餐、四项裁决、3-4 CSV、阶段 4 训练页、阶段 5 AI、阶段 6 与阶段 7 全部完成） | 评估与实施路线，不覆盖现有行为 | 9 视图、8 组补设计、八阶段顺序、行为保护面、验收及回退；A 已由用户选定为完整主稿并实施。 |
| `37`（无）| — | — | — | 本轮真实 AI 综合实测的台账不新开文档：**范围变更与该轮结果并入 `docs/36` §7**（S9/S10、㉜–㊴ 缺陷、主机与设备侧结果、not run 清单），证据单独一份 `evidence/2026-10-16-ai-device-campaign.md` |
| `36-round9-defects-and-plan.md` | 真机复查第二批 18 项 + 食堂五条 + 价格全删（S8-b）的台账与执行结果 | **已收口**（视觉四阶段 + 阶段 A 五条 + S8-b 全删；帧实看另抓 4 个真缺陷并修） | 有（本阶段执行细则） | §1 逐项根因表（T1–T5/N1–N7/W1–W5/P1）、§3 范围变更（S8-b 经用户裁决）、§5/§6 执行结果与未做项；证据 `evidence/2026-10-16-round9-second-batch.md` |
| `42-next-phase-goal.md` | **下一阶段 Goal 引导文字（可直接粘贴启动新会话）** | 有效（2026-10-18） | 开工引导 | 自包含：任务与顺序（P1/P0 并行 → P2 → P3 → P4）、已锁定决策（不重议）、硬约束（路径/不提交/CSV/wire/真实 AI/设备/向量不绕硬约束）、工作纪律与交付、立即开始 |
| `43-next-phase-delivery-plan.md` | **下一阶段开发文档**：把「能力已建好但没接入口」的 4 项（菜单搜索/AI 短名单/索引调度/第三档对比）与「真没写」的 7 项（容量 2000/5000、向量判重、整理建议、会话提炼、口味向量、食物路由与 nutritionFrom、记忆分页）落成可执行规格 | **已执行（2026-10-20，M1/M2/M3 全部落地）** | 有（本阶段执行细则） | §1 逐条代码核对表；§3 每项：现状/目标/接口/Key/判据/测试/风险；§5 验收口径（RED→回归→门禁→设备→文档）；§6 风险与回滚（全加法、无 schema 变更）；§7 两个决策点（battery 依赖、自动提炼的真实 AI 调用） |
| `44-next-phase-goal.md` | **下一阶段 Goal 引导文字（可直接粘贴启动新会话，取代 `docs/42` 的 P1–P4 引导）** | 有效（2026-10-19） | 开工引导 | 自包含：必读清单、基线（p21-final / vc2037）、M1 可见性（菜单搜索/AI 短名单/第三档/调度）、M2 治理（容量/向量判重/整理建议/会话提炼/分页）、M3 个性化与协议（口味向量/食物路由）、锁定决策、硬约束、工作纪律、两个决策点与默认行为、立即开始 |
| `45-full-app-review-and-remediation-guide.md` | **全应用审查 → 报告 → 修复 → 二次验收的执行引导**（自包含） | 有效（2026-10-20） | 有（本阶段执行细则） | §0 六阶段与产物（47/48/49/50）；§2 自治（不停/绕行/仅三判据停/默认决策表）；§4 阶段门与时间盒；§5 十四维度矩阵；§6 覆盖目标与风险分层抽样；§7 Skill 矩阵；§8 证据规范；§9 定级；§10 三份文档骨架；§11 二次验收判据；§12 十条反模式 |
| `46-full-app-review-goal.md` | **全应用审查阶段的 Goal 引导文字**（可直接粘贴启动新会话，配套 `docs/45`） | 有效（2026-10-20） | 开工引导 | 自包含：必读清单、基线（bundled-food-final2 / vc2040）、四阶段产物、十四维度、自治与阻塞绕行（仅三种情况可停）、硬约束、门禁与交付、S6 验收判据、立即开始 |
| `41-memory-and-food-master-plan.md` | **总开发文档 v2（唯一开工入口）**：记忆（S11 已完成）+ 食物数据（S13）+ 检索（S12）三系统的完整功能、互链矩阵、性能专项、降级矩阵、schema 28 总表、P0–P4 | **已裁决可开工**（D1–D11 全部结论） | 有（总纲） | §1 需求 R1–R10；§3 裁决 D1–D11；§4 统一架构；§5 记忆完整清单；§6 检索完整清单；§7 食物/菜品完整清单；**§8 三系统互链矩阵**；**§9 性能与响应速度专项**（前缀稳定化/快照装配/去 N+1）；**§10 降级矩阵**；§11 schema 28 总表；§12 P0–P4（含 G 项归属）；**§14 第三轮自审 G16–G23**（任务队列/会话快照/实体链接/调试面板/导入校验/时间语义）；§15 明确不做 |
| `40-food-data-coexistence.md` | **食物数据共存模型**：食物库（每 100g 事实）/ 食堂菜品（供应事实）/ 菜品库（份量模板）/ 餐记录（快照）四层 + 显式链接（范围变更 S13） | **P1/P2/P3/P4 已实施**（2026-10-18/19：schema 28 + 份量口径 + 配料三层来源 + 参考食物库 chip + 手动营养 + 陈旧判定与展示徽标 + 同步动作 + 重复整理页；时间语义与 HNSW 未做） | 已裁决（`docs/41`） | §0 四条铁律；§1 现状与「100g 假设」；§2 字段增量与不变量；§2.3 食物库价值清单；§2.4 UI 暴露建议；**§2.5 配料与过敏原（三层来源、用户>AI>词典、食材推导过敏原、食物库无此字段的纠正）**；§3 写入路径矩阵；§3.1 建菜时的食物库匹配；§4 去重/关联；§4.5 重叠处理；§5 AI 路由；§6 同步与陈旧；§7 统一检索；§8 迁移；§9 P1–P4；§10 验收判据 |
| `39-memory-and-retrieval-architecture.md` | **记忆与检索目标架构 v2**：端上向量（bge-small-zh int8）+ **RRF 混合检索** + **菜品结构化标签/个人口味** + 记忆治理（范围变更 S12） | **P0 已实测、P3 已实施；向量已启用（2026-10-19）**（稳态复测后 maxLen 32+前缀 B 两门槛都过：p95 13.3ms、recall@10 相对 +92.6%；模型随包 + worker isolate + 空闲预热；RRF/查询理解/记忆 query-aware/前缀稳定化/IndexCoordinator/调试面板/任务调度均已落地） | 已裁决（`docs/41`） | §0 五个关键修正；§2 外部优势收敛；§4 嵌入层（模型/分词/量化/前缀 A/B）；§5 索引表与三档规模；§6 硬/软过滤 + RRF + MMR + 记忆门控；§7 写入治理（合并/替换/过期/节流）；§8 菜品标签/配料/口味向量/可用性；§9 性能预算；§10 ≥100 条评测与 hard negatives；§12 P0–P4；§15 与 v1 的差异 |
| `38-ai-memory-research-and-plan.md` | **AI 长期记忆**：外部调研（产品横评 + 开源记忆层 + 可嵌入性）+ 本仓方案与实施（v1 + v1.1） | **v1 与 v1.1 已实施（2026-10-17/18）**；仅「自动后台提炼」未做 | 有（本阶段执行细则） | §3.2 快照缺口 + §3.4 隐私承诺与裁决；§4 设计；§6 S11 边界与 `docs/03` §12 六问；**§11 v1 执行结果**；**§12 v1.1**（提炼记忆、forget 多候选点选、编辑去重守卫、快照 <32 KiB pin；门禁 `+2521 ~65`；真模型提炼与 ⑳ 复跑均通过）；**§13 外部参考**（Operit 图谱记忆 / Eta `MEMORY.md` 的源码级对照、容量表与 8 项可借鉴取舍）；§8 明确不做 |
| `35-ai-recommend-and-polish-plan.md` | Round8 计划与台账（21 条缺陷 + S1–S7 范围变更 + §9 追加轮） | **已收口** | 已完成（无规范效力） | 证据 `evidence/2026-10-16-round8-ai-recommend-and-polish.md`；§10 是 AI 对话错误文案的诊断清单 |
| `32-ui-redesign-round5-plan.md` | **原生第五轮方案（15+6 条需求 59–79，T1→T16）** | **全部交付（T1–T10 与 T6a/b/c、T12–T16 均已交付；T1 2026-10-11、T2–T5 与 T6 于 2026-10-12、T7/T8/T9/T12/T13/T14/T15/T16/T10 于 2026-10-13）；T11 四条验收全落地（1、2 落地 + 设置页「清空内置食物」入口于 2026-10-13 补做；**3 的「新结构真机侧」与 4 的「新表头对账」于 2026-10-13 收官解阻**——新结构 21 列落地、真机导入 19,974 行走通、对账 16/16，见证据 §14；同日摆好 3/4 的机器外框（「导出表头无静默列」pin + 2 条隔离变异 + 落地清单；另补「清空→回灌」连贯测试 = 验收 3 的机器侧、表头自适应；同日升级安装真机走查补齐「清空」正向分支与「清空 → 导出 → 回灌」全循环 = 旧结构 CSV 的真机侧（§10、22 帧）；同日补**表结构腿** pin = 验收 4 的第三条腿（§11）；再补**逐列值往返** pin = 值腿（§12）；同日完成 objective **完成度审计**（§13：八处定案逐条取机器证据 + §7 = 23 勾/0 未勾 + 门禁 `+2074` 复跑）；2026-10-13 08:40 在 `E:/AI/Codex/outputs/food-nutrition-20261008/` 发现**候选新结构文件**（`国内食品营养数据_扩充版2.csv`，21 列 / 19,974 行，流水线仍在迭代）⇒ 待用户裁定结构源 / 入库列范围 / 分类落法（见证据 §13.4；推荐默认下的落地规格草案见 §13.5）））** | **有（现有原生裁决）** | 用户 2026-10-11 一次性反馈 **15 条**（12 项改动 + 3 个提问：导出语义 / 水分目标来源 / 电子秤与小米支持）+ **同日追加 6 条（74–79）**，逐字归档于其 §1/§1.2；真机截图 8 张 `docs/evidence/2026-10-11-round5-feedback/01..08.jpg` + 新设计稿 `ui设计/pages/初始引导.html`（借鉴清单 §8；该页已纳入 `design_source_parity_test` 的 **8 页**设计源清单）。**自我包含：不引用任何既往文档**，现状描述全部标代码事实（文件:行号）。含裁决 **D1–D19**（其中 **8 处「✅用户已定」**：通勤删除/今日吃法降级/移除随包种子/弹层方案 B/秤接口预留/导出文案/阶段条视觉进度/CTA 用现有 h48）、bug 清单 **B1–B21**、工作包 **T1–T16**、三问答复（§5）、「不引入新 bug」防线（§6）与全局验收清单（§7）。**修正两处用户判断**：① 清空 4.9 万条须同时移除随包种子 `assets/seed/foods.v5.json`（否则每次启动回灌）；② 新食物结构**待用户提供文件**，表格与 CSV 契约留占位。**T1 证据**：`docs/evidence/2026-10-11-t1-weight-chart.md`（月视图改本月逐日格 + 左轴 4 档 + 柱点击浮窗 + 添加钮 28dp；设计稿 `ui设计/round5/t1-weight-chart.html`；门禁 EXIT=0 / 2101 passed）；**T2 证据**：`docs/evidence/2026-10-12-t2-onboarding-target-sheet.md`（目标抽屉图形化：热量主行 + 三宏量范围条，`[min,max]`→`[0,max×1.2]` 只画位置；设计稿 `ui设计/round5/t2-onboarding-target-sheet.html`；门禁 EXIT=0 / 2107 passed）；**T3 证据**：`docs/evidence/2026-10-12-t3-small-styles.md`（空态铺满 + 今日推荐按钮同高 h40 + 动作库行高去 +12；golden 基线更新 1 张；门禁 EXIT=0 / 2111 passed）；**T4 证据**：`docs/evidence/2026-10-12-t4-select-field.md`（统一下拉 `LfSelectField` + 11 站点迁移；设计稿 `ui设计/round5/t4-select-field.html`；门禁 EXIT=0 / 2119 passed）；**T5 证据**：`docs/evidence/2026-10-12-t5-sheet-stability.md`（食物详情 future 提升 + 训练弹层方案 B + 3 处迁 AppSheet + 2 处 AlertDialog 收敛；门禁 EXIT=0 / 2123 passed）；**T6a 证据**：`docs/evidence/2026-10-12-t6a-ai-gallery.md`（AI 创作画廊分组重设计 + 描述框；设计稿 `ui设计/round5/t6a-ai-gallery.html`；门禁 EXIT=0 / 2128 passed）；**T6b 证据**：`docs/evidence/2026-10-12-t6b-starter-handoff.md`（`planDays` 组合类型 + `workout.plan.create`（注册表 23→24）+ 路由级 pending 预填/自动发送 + S7 仪器同步 24 命令；门禁 EXIT=0 / 2144 passed）；**T6c 证据**：`docs/evidence/2026-10-12-t6c-pipeline-retirement.md`（旧任务执行管线退役：删 7 个生产文件 + 14 个测试族、模板逐字迁移保留、两处入口改接对话/描述框、安全断言重钉；门禁 EXIT=0 / 2052 passed，T6b 2144 → −92 即退役测试数）。**T7 证据**：`docs/evidence/2026-10-13-t7-identity.md`（身份卡与头像：schema 23 +`displayName`/`avatarPath`（删列与通勤代码留 T8，范围修订已回写 §3 D9/D10）、身份卡删副标题/头像昵称垂直居中/昵称弹层/头像选图、共享 `UserAvatar`（缺文件同步回退首字）、今日页与对话页头像接入身份并跳「我的」、`.lfb` 旧新兼容断言；设计稿 `ui设计/round5/t7-identity-avatar.html`；红先 12 条、变异 5/5、门禁 EXIT=0 / 2071 passed）。**T8 证据**：`docs/evidence/2026-10-13-t8-settings-cleanup.md`（设置清理与通勤全链路下线（需求 70/71，76 的文案随包交付）：schema 23→24 删退役列（先查表在不在 → 再查列存在性 → `DROP COLUMN`）、lib 16 文件 + `lib/features/routing/` 整目录删除（含命令 `commute.set`）、设置页删「添加自定义食材」行 / 扩展目录恢复入口条件渲染 / 三导出行定稿文案、退役特性 grep 门禁（逐行令牌白名单）；设计稿 `ui设计/round5/t8-settings-cleanup.html`；红先 15 条、隔离变异 5/5、门禁 EXIT=0 / 2008 passed，T7 2071 → −63）。**T9 证据**：`docs/evidence/2026-10-13-t9-goal-editing.md`（目标编辑（需求 64/72）：编辑资料页新增「每日目标」两行（`profile-steps-goal` 步 / `profile-water-target` L，空框 = 不改）、步数目标存 `AppSettings.steps_daily_goal`（缺键/坏值/越界读作 10000 且不写回，越界写抛 `ArgumentError`）、步数卡目标优先序 = 注入 > `watchDailyGoal()` 流 > 默认并删掉恒 10,000 的 `StepsStatCard.dailyStepGoal`、新用例 `UpdateWaterTargetMl`（今日已有行就地更新 / 否则复制上一生效行另起一行；越界 0.5–6.0 L 抛 `WaterTargetException`）、docs/21 §5 加两个新 Key；判据「未设置=2000」按代码事实收窄为「没有生效行 ⇒ 留空且不伪造」（已回写 docs/32 §4 T9）；设计稿 `ui设计/round5/t9-goal-editing.html`；红先 25 条、隔离变异 5/5、门禁 EXIT=0 / 2033 passed，T8 2008 → +25）。**T13 证据**：`docs/evidence/2026-10-13-t13-seed-removal.md`（移除随包食物种子（需求 75）：`foods.v5.json`（11,342,444 B / 49,444 条）与 `foods.v4.json`（10,703,218 B / 49,464 条）**归档**到仓库外 `E:/AI/Zcode/projects/localfit-ai/archive/food-seed-2026-10-13/`（sha256 与仓库生成物自带声明逐字一致）、pubspec 删声明、`lib/main.dart` 删调用、导入器与其实测试整份删除；**本包真正的工作量在测试面**——`FoodSeedImporter` 同时是 25 个测试文件 / 28 处的 fixture ⇒ 新增 `test/support/food_fixture.dart` 迁移全部调用点，`food_name_test` 的 49,444 条全量枚举改「有归档才注册」，隐私审计四处改写 + 新增「退役来源的 README 必须含上游/许可证原文/退役字样」，新增 `no_bundled_food_seed_test.dart` 4 条；来源标注新增 `DataDelivery.retiredSeed` ⇒ 设置页显示「历史随包 · 现已不随包」（继续写随包是假话、删条目也是假话）；B18 量化 842 ms/首装 + 10 ms/次启动 + 11.3 MB 资产；隔离变异 7 条全 RED 且还原后 sha256 一致（含一次如实记录：第一版变异驱动把没跑起来的跑测记成了 RED，已改成硬判据并重跑）；门禁 EXIT=0 / 2025 passed、`test_strip_seed.py` all checks passed；如实限制：归档在仓库外 ⇒ 三条断言在全新检出机器上不注册、生成脚本路径未逐个改、升级安装的 4.9 万行仍需 T11 清空）。**T16 证据**：并入 `docs/evidence/2026-10-13-t8-settings-cleanup.md` §7（通勤删除收口复核（需求 77）：只读四条判据全 ✅——`lib/`+`test/` 零活引用（可执行版本 = T8 的 `round5_retired_feature_grep_test.dart`）、注册表实测 23 条且计数断言在、AI 快照七段无「手动通勤」段、`.lfb` 旧包（含 `manualCommuteMinutes` 的）恢复往返通过；两处判据按代码事实回写 docs/32：grep 集合去掉 `travelFit`（D10 明文保留为中性参考值）、注册表 22→23；**补漏六处文档面**：`docs/08` 隐私说明三处（快照内容清单 / 「只实现本地手动通勤时间」/ 位置行）——最该修的一处、`docs/21` 设置页结构树（被测试读盘）+ 自门控例子改指 `settings-food-data`、`docs/23` 删 `commute.set` 行并补 T6b 漏记的 `workout.plan.create`、`GOAL.md` 已成假的「保留」句追加更正、`docs/07` §2.0-5 与 `docs/02`（数据清单 + §5.3）加退役注；历史叙述（01/04/09/28/29/30 与 evidence）故意不动；因动 `docs/21` 复跑门禁 EXIT=0 / 2025 passed）。**T12 证据**：并入 `docs/evidence/2026-10-13-t8-settings-cleanup.md` §8（导出文案去 "CSV" 后缀（需求 76）：**验证-only**——三行 label 精确断言（`导出饮食记录`/`导出训练记录`/`导出食物数据`）+ 全页 `textContaining('CSV') == findsNothing` + 三键 `cta-export-csv`/`backup-export-training-csv`/`backup-export-foods-csv` 不动 + 三行各自落盘文件名（`localfit-meals-`/`localfit-training-`/`localfit-foods-`）与正文回归，全部在 T8 的 `test/features/settings/round5_settings_cleanup_test.dart` 里；变异见证 = T8 的 M3；本包无代码改动 ⇒ 沿用门禁 EXIT=0 / 2025 passed）。**T14 证据**：`docs/evidence/2026-10-13-t14-scale-abstraction.md`（电子秤读数来源接口预留（需求 78/D16）：**只留挂点、不写解析**——`ScaleReadingSource`（`check`/`requestPermission`/`openAppSettings`/`parsers`/`readOnce`）+ `ScaleDevice`/`ScaleProtocolParser`/`ScaleParserRegistry`（`forDevice` 按广播名/服务 UUID 认领、重复 id 抛）+ 标准协议 `StandardScaleReadingSource`/`StandardWeightMeasurementParser`（0x181D，SFLOAT 解析仍在原生侧）；`ScaleSyncController` 改依赖抽象；接口操作面按平台事实收窄（原生只有合成原语 `scanOnce`，不做 `scan`+`readings` 假接口，已回写 §3 D16/§4 T14）；验收：老回归 8/8+10/10（断言零改动）、fake source 驱动七种结局、假厂商 parser 分派证明、`ble_scale`/同日不覆盖/权限清单不动（manifest 未动）；红先 = 60 条编译错误（API 缺席），行为牙齿 = 变异 5 条全 RED 且还原 sha256 一致；门禁 EXIT=0 / 2040 passed（+15 = 新测试 15 条）；原生零改动）。**T15 证据**：`docs/evidence/2026-10-13-t15-onboarding-merge.md`（引导页合并设计稿（需求 74/D18）：阶段条 4×24×4 + 微标签（视觉进度，`p = pixels / maxScrollExtent` 三段阈值，不足一屏恒第 1 段）+ 两张分组卡副文案 + 活动档仍 4 档描述式 + 性别自绘 `LfSegmentControl`（48dp 轨道）+ 行式安全筛查（三 Key 不变、46×28 `LfToggleSwitch`、整行可点、2 条 1px 分隔线）+ 主行动移入 `FixedBottomPrimaryAction`（**h48**）；设计稿 `ui设计/round5/t15-onboarding-merge.html`；自评两轮；阶段条**钉在正文之上**（放回列表滚到底会被回收，变异 m8 见证）；红先 20 条编译错 → 8/8 行为 RED → 8/8 绿；隔离变异 10 条全 RED 且还原 sha256 一致；既有 4 个测试文件只改脚手架（断言零改动，`secondary_entry_reachability_test` 收紧为 `hitTestable`）；`docs/21` 新增 §5.9 建档页 Key 表；门禁 EXIT=0 / 2048 passed（T14 2040 → **+8**））。**T11 证据**：`docs/evidence/2026-10-13-t11-food-rebuild.md`（食物库清空 + 导入器升级（需求 75）：**四条验收全落地（2026-10-13 收官：新结构 21 列落地 + 验收 3 的新结构真机侧 + 验收 4 的新表头对账；此前状态为「验收 1、2 落地，3、4 阻塞待用户新表头」）**。验收 1 = 新用例 `ClearBuiltinFoods(AppDatabase)`：单事务定点删 `foods` 里 `is_user_created = 0` 的行，先断开两处**无级联**引用（`meal_items.food_id` 置空 / `menu_item_food_matches` 删除，派生表走 cascade），「内置行」用子查询表达不拉 id 列表，可重跑幂等；**与 `ClearAllLocalData` 显式区分**（AI Key 写入内存 store 后跑清空仍读得到 + 按 `allTables` 逐表比行数，除被清的 6 张表外一张都不许少）。验收 2 = 导入器三处升级：上限 16 MiB → **256 MiB**（30/40 MB 放行、1 GiB 仍拒）、去重索引整表物化 → **分页**（`ORDER BY id ASC`）、落库逐行 `create` → `FoodRepository.createMany` **分批 + 单事务**（行构造抽 `_row()` 让两条路径共用同一套校验与自建标记）；**`failed` 语义按代码事实变更**——DB 级意外不再被吞（上抛 + 整批回滚），`app_router` 落库步骤补 try/catch 给中文原因。**实测 2 万行 preview+execute = 463 ms**（门禁日志）。红先 34 条编译错（API 缺席）+ 一条真行为红（drift 读回的 `DateTime` 本地表示）；隔离变异 **11 条全 RED** 且还原 sha256 逐字节一致；门禁 EXIT=0 / `580 files (0 changed)` / `+2060 ~11 passed`（T15 2048 → **+12**）。2026-10-13 **补做 §8：设置页「清空内置食物」入口已交付**（`settings-clear-builtin-foods` 放「食材库」组末、`destructive` 字色、三条判据全真才渲染；新增 `ClearBuiltinFoods.preview()` 让确认弹层的三组计数**现算**、0 的那句整条不提，预览为空不弹层；执行后就地重读概览 + snackbar 如实报数；设计稿 `ui设计/round5/t11-clear-foods.html` 5 帧自评两轮修 5 条瑕疵；新断言 9 条、隔离变异 6 条全 RED 且还原 sha256 一致；真机只验负分支（全新安装组内三行、无清空行），正向分支因内置行只来自升级安装 + 库为 SQLCipher 加密而不可达 ⇒ 用 host 渲染探针作几何/配色证据；docs/21 §5.8 同步三个新 Key；门禁 EXIT=0 / `581 files (0 changed)` / **+2070 passed**（T10 2061 → +9））。如实限制：正向分支无真机帧（仅探针）；不做「清空 + 立即导入」向导；「单事务」在清空侧是结构判据非注入测试；分批只压住分页正确性（没测内存峰值，`preview` 仍全量解析文本）；`ORDER BY id` 守卫本地测不出故未进变异表；无真机走查；同日再补 §9 = 验收 3/4 的机器外框（防静默丢列的 pin + 2 条隔离变异 + 落地清单；验收 3/4 仍未勾，阻塞待用户新表头；§9.7 再补「清空→回灌」连贯测试 = 验收 3 的机器侧（CSV 用导出器输出 ⇒ 表头自适应），验收 3 的**新结构**真机侧与 4 仍等用户文件；同日晚摆**升级安装真机走查**（§10）：把 Oct 11 pre-T13 构建真装一次（`FoodSeedImporter` 真灌 49,444 行）→ `adb install -r -d` 原地升级（数据完整保留）⇒ 「清空」正向分支首次真机可达（确认弹层 49,444 → 取消不变 → 导出 4.29 MB CSV → 执行 snackbar「已清空内置食物：删除 49,444 条。」+ 计数 0 条 + 行自隐），并补齐「清空 → 导出 → 回灌」全循环：回灌 49,444 条（可导入 49444/重复 0/错误 0 → 「49,444 条（自建 49,444 条）」）、同文件二遍全判重复（0/49444/0 = 分页去重索引真机判据）、旧 4 行 fixture 混账（2/1/1 + 「第 4 行「abc」不是数字。」）→ 「已导入 2 条食物（自建）。跳过重复 1 条。」→ 终态 49,446 条（自建 49,446 条）；22 帧 `docs/evidence/2026-10-13-t11-clear-device-upgrade/`；零代码改动不触发新门禁（沿用 +2072）；同日补 **§11 = 验收 4 的第三条腿**（表结构 ↔ CSV 映射 pin：断言 `foods` 17 列 == CSV 映射覆盖列 ∪ 显式不参与列、导出表头 == 映射键集；3 条隔离变异全 RED——含把 `app_database.g.dart` 里 `$FoodsTable` 的 SQL 列名改掉那条（本 pin 归因成立、爆炸半径 10/24 如实记：生成代码与迁移 DDL 分了家）；还原 sha256 一致、复跑基线绿；门禁 `+2073` EXIT=0）；同日再补 **§12 = 验收 4 的值腿**（导出 → 导入空库 → 再导出，数据行**逐列**相同、表头自适应；源行直插表避免被 `_row()` 的幂等掩盖；3 条隔离变异全 RED（落库丢列 / 导出错列 / 导入错列，后两条失败集合恰是本 pin ⇒ 「没这条 pin 会全绿」是量出来的）、还原一致、复跑绿；门禁 `+2074` EXIT=0）；**2026-10-13 收官（§14）**：新结构 21 列落地（`foods` 17→32 列 / schema 24→25 存在性驱动迁移 / 导出表头 21 列中文逐字 + `origin` 退役 / 导入 21 键别名表 + 24 库大类映射、表外整行拒绝）、测试 +9、门禁 **`+2083` EXIT=0**（`d-gate3`；文档同步后冻结树复跑 `d-gate4` 同样 EXIT=0 = 最终那次）、隔离变异 9 条全 RED 且逐字节还原（含表结构腿真跑 `build_runner`）；验收 3 新结构真机侧 ✅（全新安装 → 导入 19,974 行 → 预览 19974/0/0 → 计数 19,974 条（自建 19,974 条）→ 真机导出（宿主复核 8,703,486 B / BOM / 纯 CRLF / 19,975 行 × 21 格 / sha256 `7cb03804…`）→ 二遍全判重复；13 帧 `docs/evidence/2026-10-13-t11-new-structure-device/`）；验收 4 新表头对账 ✅（`accept4-report.json` 同目录，**16/16**：表头逐字 / 别名表 / 表列集独立解析 / 值体检 / 抽样 24 行 × 21 列对源 + `食品ID` 全集相等））。**T10 证据**：`docs/evidence/2026-10-13-t10-walkthrough.md` + 帧目录 `docs/evidence/2026-10-13-t10-walkthrough/`（42 张）（收口走查（需求 59–79）：release x86_64 全新安装起步、逐条 59–79 真机核对（59 目标抽屉 / 60–61 月视图与柱浮窗 / 62 画廊与描述框 / 63 空态 / 64+72 每日目标两行 / 65 按钮同高 / 66 下拉统一 / 67+79 弹层拖动（内容区与把手小幅下拖都不关窗）/ 68 动作库卡底距 / 69 昵称改名往返 / 70+76+77 设置三段且无通勤行、三导出行不带 CSV / 71 三问 / 73+78 秤文案与挂点 / 74 引导四帧 / 75 全新库 0 条→手工 1 条（自建 1 条））；**走查抓到两条**：① **当轮修复**——AI 创作三条卡面说明被截断（残留「；」「，」，`meal-pairing` 少一整句隐私承诺）：原文两处独立出处（旧帧 `w4-07` 的 `content-desc` + `docs/08:44`），只改 `ai_starter.dart` 三行字符串，新断言三条逐字 + 一条「不许停在 `；`/`，` 上」兜底，红先 EXIT=1 的失败信息即截断证据，隔离变异 2 条全 RED、还原 sha256 `724a006c…` 逐字节一致，重建 APK 后复拍 `25` 帧；② **遗留**——手动创建计划保存成功后训练页计划列表不刷新（`已保存「PlanA」。` 但空态持续，切 tab 无效、重启进程才出现；根因 = route 写路径不走本页 `setState`，属 docs/30 链路）；其余遗留：设置页清空入口（可选未做）、62 端到端需用户 AI Key、真秤待硬件、`关于`「版本未知」为既有降级约定、性能预算抗抖建议、模拟器时钟晚一天非缺陷。**docs/32 §7 已逐条勾**（21 条需求 + 每包 + T10 收口行）。**设计稿流程（2026-10-12 用户指示）**：不再送用户审批，改作者自检两轮后自动执行（§0 纪律 v3） |
| `31-ui-redesign-round4-plan.md` | 上一阶段方案（21 条需求 38–58，S1→S8） | **S1–S8 全部交付（S1–S4 于 2026-10-09，S5–S8 于 2026-10-10）** | 已完成（无规范效力） | 用户 2026-10-09 一次性反馈的 21 条 UI 需求（逐字归档于其 §1）+ 9 条裁决 D1–D9（§2）；含「已知会误导本轮的三处旧文本」清单（§0）。逐包证据 `docs/evidence/2026-10-09-s1-weight-card.md`（S1 体重卡）、`docs/evidence/2026-10-09-s2-schema22.md`（S2 体成分/过敏原下线，schema 22）、`docs/evidence/2026-10-09-s3-full-scale.md`（S3 满刻度 1000）、`docs/evidence/2026-10-09-s4-steps-denied.md`（S4 步数卡未授权态）、`docs/evidence/2026-10-10-s5-food-library.md`（S5 食物大库：种类落库 + CSV 导入导出 + 去重提示 + 设置入口）、`docs/evidence/2026-10-10-s6-ble-scale.md`（S6 电子体重秤：localfit/scale 通道 + source=ble_scale + 同日不覆盖手输）、`docs/evidence/2026-10-10-ai-takeover-multi-intent.md`（S7 AI 接管多条件实测：28 用例骨架 + 三态记录 + 23 命令覆盖表仪器，默认 skip 零外呼，实测待用户给 key 后回填）、**S8 全局收尾 `docs/evidence/2026-10-10-s8-wrapup.md`（DesignCard.semanticLabel 死参数修复 + ADR-034 + 文档同步）与设备走查 `docs/evidence/2026-10-10-s8-walkthrough.md`（360dp 全装机首启 + onboarding + 17 张证据帧；实测修出真缺陷：弹层写库后食材库计数停旧快照，已修 + 设备复核；装机慢启动 ~6 分钟如实记录为既有设计）**；**优化版 APK 再交付 `docs/evidence/2026-10-11-vc2003-delivery-apk.md`（versionCode 2003 = 首个含三四轮全部改动的优化包；2002 旧件保留 + 门禁抖动排查如实记）** |
| `30-ui-redesign-round3-plan.md` | 上一阶段方案（10 条需求，R1→R8） | **R1–R8 全部交付（2026-10-08）** | 已完成（无规范效力） | 用户 2026-10-08 一次性反馈的 10 条 UI 需求；逐包证据 `docs/evidence/2026-10-08-r1..r8-*.md`；设备走查 `docs/evidence/2026-10-08-r8-walkthrough/`（25 张 360dp 走查页 + 1 张缺陷取证帧，共 26 个 PNG）。**本轮改动落地时已同步改写 `docs/21` 对应小节** |
| `29-ui-ux-remediation-plan.md` | 上一阶段方案（39 条） | **P0–P12 全部交付（2026-10-07）** | 已完成（无规范效力） | 逐包证据见 `docs/evidence/2026-10-05-p*` 与 `2026-10-06/07-*`；P11 实测 `2026-10-05-ai-live-endpoint.md`；P12 收尾 `2026-10-07-p12-global-wrapup.md`；**P8b-2（食物库 v5 定稿与 App 升级，收尾最后一包）`2026-10-07-p8b2-v5-upgrade.md`**；**优化版 arm64 交付 APK（含 v4→v5 原地升级真机实测）`2026-10-07-p8b2-delivery-apk.md`**；**2026-10-08 缺陷排查 + AI 测试审查 + 优化版 APK 再交付（9 条修复含 3 处隐私假话、钉值/跨时区审查、versionCode 2002）`2026-10-08-bug-hunt-and-delivery.md`**（+ 截图 `docs/evidence/screenshots/bughunt-delivery/`） |
| `DECISIONS.md` | ADR 日志 | 追加式 | 有 | 新决策追加，不修改历史条目 |
| `THIRD_PARTY_LICENSES.md` | 第三方来源与许可 | 有效 | 有 | **被测试读盘（7 处）**，勿移动 |

## 2. 已完成的方案书（历史，无规范效力）

这六份**原位保留**（引用它们的代码注释共 51–210 处，搬移会造成大量死指针——理由见 `docs/29` §0.4），
但状态行已统一改写成「已完成 + 无规范效力」。**不要按它们开工。**

| 文件 | 主题 | 完成于 | 交付证据 |
|---|---|---|---|
| `11-code-review-and-bug-hunt-plan.md` | 代码审查与缺陷排查 | 2026-09-19 | `evidence/2026-09-19-bug-hunt*.md` |
| `22-ui-redesign-refactor-plan.md` | UI 重设计改造方案 | 由实现取代 2026-10-03 | `evidence/2026-09-2x-ui-*.md`、`2026-10-01-stage-*` |
| `25-code-review-plan.md` | 代码审查计划（code-review.v1） | 2026-10-02 | `evidence/2026-10-02-code-review-and-size.md` |
| `26-ui-display-review-plan.md` | 界面显示专项（11 项显示缺陷族） | 2026-10-03 | `evidence/2026-10-03-ui-display-review.md` |
| `27-ui-aesthetics-refinement-plan.md` | 界面美观与整齐性优化 | 2026-10-03 | `evidence/2026-10-03-nutrition-presentation-redesign.md`、`2026-10-03-button-card-unification.md` |
| `28-input-menu-foodlib-redesign-plan.md` | 输入弹窗/菜单页/食物库/动作库（七包 W1→W7） | 2026-10-04 | `evidence/2026-10-04-input-menu-foodlib-redesign.md`（+ 同名目录） |

## 3. 归档目录

| 目录 | 内容 |
|---|---|
| `docs/history/1.x/` | 1.x 时代文档（roadmap、evidence）。已无代码引用，物理归档。 |
| `docs/history/2.x/README.md` | 2.x 阶段归档清单与**为什么原位保留**的说明。 |

## 4. 证据目录

| 路径 | 内容 |
|---|---|
| `docs/evidence/README.md` | 命名规范与索引约定 |
| `docs/evidence/*.md` | 每轮切片的历史证据（标 historical / 未重跑） |
| `docs/evidence/<slice>/` | 截图 / XML dump / 日志等原始产物 |
| `docs/evidence/2026-10-20-m1-m2-m3-delivery.md` | **M1/M2/M3 交付证据**：A1–A4 / B5–B11 判据与测试、门禁 `next-final9`（`+2764 ~66`）、设备复验（菜单搜索仅语义命中 / 三档对比）、**4 个真实缺陷**（搜索刷新死循环、worker 资产读取、worker 平台通道初始化、待确认任务被调度器标失败）、not run 清单（A2/A3 设备侧）、APK vc2038/vc4038 与 sha256 |
| `docs/evidence/2026-10-20-bundled-food/` | 内置 8 列食物库的设备帧（食物库顶部「23,919 种食物」） |
| `tool/food_catalog/convert_food_xlsx.py` | 用户 8 列 xlsx → 21 列契约子集 CSV 的转换脚本（24 类库大类逐一命中 `FoodCategory`；真实导入冒烟 23,919 行全入库见 `importer_smoke_test.dart`） | 有效（2026-10-20） | 工具 | 配合「我的 → 食物库 → 导入」使用；导入器本身零改动 |
| `docs/evidence/2026-10-20-m1-m2-m3/` | 本轮设备帧（菜单搜索语义命中、调试面板三档） |
| `docs/evidence/2026-10-18-p0-eval.md` | **P0 端上嵌入实测**：100 查询 × 100 菜矩阵（int8/fp32、maxLen 32/64/128、前缀 A/B）、门槛判定（质量 +89~98% 通过 / p95 延迟未稳定通过 ⇒ 不上向量）、三个真实缺陷修复 |
| `docs/evidence/2026-10-18-p1-p2-p3-delivery.md` | **P1/P2/P3 交付证据**：门禁 `p21-final`（+2694 ~66；三次运行器故障已如实登记）、schema 28 回填与判据、检索/记忆选择/前缀稳定化、陈旧与份量徽标展示层（含 watchAll 闭环与弹层被底栏遮挡两个真实缺陷）、同步动作/反馈按钮/重复整理页/索引状态段/时间语义（S14 schema 29）、端上向量启用（模型随包 + worker isolate + 空闲预热）、设备复验帧、APK vc2036/vc4036 与 sha256（含随包模型与体积代价）、not run 清单 |
| `docs/evidence/2026-10-18-p0-eval/` | P0 设备原始 logcat、重建的 `p0_report.json` |
| `docs/evidence/2026-10-18-p1-p2-p3-device/` | 设备帧（记录入口弹层、搜索调试面板、vc4030/vc4031 启动与复验帧、参考食物库弹层、份量徽标、反馈提示、整理页、索引状态段）与 UI dump |

**被测试直接读盘的 evidence 文件**（勿移动、勿改名）：
`evidence/2026-10-04-input-menu-foodlib-redesign.md`、
`evidence/2026-09-16-2.0-1l-chinese-food-source-license-investigation.md`。

| `docs/68-unified-nutrition-data-contract.md` | **统一营养数据契约（schema 31，实际实现）**：主食物/修订/供应/台账/快照的角色与不变量、唯一写入入口、AI 协议增量、备份恢复口径、界面单位规则 | 生效（2026-11-09） | 契约 |
| `docs/evidence/2026-11-09-unified-nutrition-master/README.md` | P0–P5 实施证据：逐条 A01–A22 对应测试、门禁真实结果（含 `test/privacy` 既有红）、旧数据/旧备份/旧卡片处理、not run 清单 | 证据（2026-11-09） | 证据 |

## 5. 维护规则

1. 新增方案/规范 → 在本文件 §1 或 §2 登记（一行）。
2. 方案完成后 → 加统一状态横幅（格式见 `docs/29` §0.3），并从此表 §1 移到 §2。
3. 任何文档的「状态」行与本文件不一致时，**以本文件 + `STATUS.md` 为准**，并修文档。
4. 新阶段的方案文档接管「本阶段执行细则」位置后，上一份进入 §2。
- `evidence/2026-10-25-round3/` —— 第三轮修复（`docs/60` 清单）的 run-log、实帧与设备实测留痕。
