# GOAL：改进四阶段（2026-10-26）

> 本文件是**可直接粘贴给 AI 执行的完整任务书**。复制「## 任务正文」整段即可。
> 依据：[`docs/64`](64-improvement-roadmap-2026-10-26.md)（四阶段 17 项：现状证据 / RED
> 断言原文 / 施工步骤 / 变异 / 实帧 / 验收行）；背景：[`docs/63`](63-manual-entry-fixes-2026-10-26.md) §6。

---

## 任务正文（从这里开始复制）

在 `E:/AI/Zcode/projects/localfit-ai/localfit-ai` 中，按
[`docs/64-improvement-roadmap-2026-10-26.md`](docs/64-improvement-roadmap-2026-10-26.md)
执行「改进四阶段」。本任务自包含：**连续做完、不逐条汇报、不等确认**；只在
「需要裁决」（阶段 4 的 B-1）或「同一项两轮修不绿」时停下说明。

### 先读（按顺序，读完再动手）

1. `docs/64-improvement-roadmap-2026-10-26.md` —— 本轮任务书（**唯一施工依据**：
   §0.1 快速索引 / §0.2 开工检查 / §0.3 定义完成 / §0.5 裁决记录 / 附录 A 能力矩阵 /
   附录 E 踩坑清单 / 附录 F 排期）
2. `docs/63-manual-entry-fixes-2026-10-26.md` —— 上一轮已完成的四处手动入口（不要重做，
   但门禁必须保证没被改坏）
3. `docs/60-pending-fixes-round2-2026-10-25.md` §12.9 —— RED 断言原文的写法示范（同一套口径）
4. `AGENTS.md` —— 路径与编码硬约束（含 `PYTHONUTF8`、`.ps1` BOM、tmp 目录规则）
5. `docs/21-ui-redesign-spec.md` 附录 D0（按钮三档）、§3.8（selected 档）、§6.2（裁决表：
   「不显示隐含目标」等 9 条诚实口径）
6. 各阶段第一个要改的文件（先读再改，别凭印象）：
   - A-1 `lib/features/hydration/data/water_repository.dart`（`delete`/`restore` 已有）
   - A-2 `lib/features/progress/data/measurement_repository.dart`（只有 upsert）
   - A-3 `lib/features/nutrition/data/dish_library_repository.dart`（有 delete/restore，
     缺「手动改营养」）
   - A-4 `lib/features/training/data/workout_session_repository.dart`（只有 start/logSet/finish）

### 现状（不要重做的部分）

- 上一轮已补齐四处手动入口：**自由训练**、**自定义一顿**、**手动步数（当天优先）**、
  **手动营养目标（卡上依据写「手动设定」）**；门禁基线 `+2994 ~1` 全绿。
- 已确认的 AI-only 写入：`water.delete`、`menu.snapshot.publish`、`constraints.set`、
  `dish.upsert` 的手动营养部分、`canteen.dish.nutrition` 的手动入口。
- 已知**没有**删除能力的记录：饮水、体重、菜品营养、训练组次/会话（本轮补）。

### 执行纪律（违反即回滚该条）

- **先红后绿**：每项先写会失败的断言（判据原文在 docs/64 对应小节），再改实现。
  不许改完补测试。
- **不许放宽**：不删断言换绿、不跳测试、不放宽预算。退役/改写的断言逐条写进证据并说明理由。
- **变异验证**：标了「变异」的项逐条做——刻意改坏 → 确认红 → **逐字还原** → 复绿。
- **连带红立刻修**：改完发现别的测试红了，修到绿再前进（唯一不能跳过的情形）。
- **看实图**：视觉类（版式/对齐/间距/弹层）必须**渲染实帧逐张自己看**；测试全绿不等于好看
  （本轮就是靠看图抓到 11px 溢出、备注一字一列、入口被浮钮压住）。
- **不许改 schema**（仍 30）、**不新增第三方依赖**、**不动 AI wire 信封形状**。
- **弹层一律** `useRootNavigator: true` + 弹层内 `Builder` context 取 Navigator；
  controller 由弹层自己的 State 持有并在 `dispose` 释放（别用 `whenComplete(dispose)`）。
- 只写 `E:/AI/Zcode` 内；临时文件只放 `E:/AI/Zcode/tmp/<context>/`，**用完即清**；
  实帧与日志归到 `docs/evidence/<日期>-<阶段>/`。

### 施工顺序（四阶段，每阶段末跑一次门禁再进下一阶段）

**阶段 0（插队，P0）**：`B-2` 仓储层「餐食不能写未来日期」（`meal_repository.dart:462`
只校验格式，与体重仓储的守卫对齐）。这是「静默写错事实」类问题，先修。

**阶段 1 · 修正与删除（半天，5 项）**
`A-1 饮水删/撤销`（形态样例，先做）→ `A-2 体重删` → `A-3 菜品营养手动改` →
`A-4 训练删组/删整次` → `A-5 餐食/食物/记忆回归确认`。
统一形态：**长按/⋮ → 弹层列表 → 删除（确认）→ SnackBar 撤销（走 restore）**；
每条删除后**重读派生数据**（合计/周统计/overview），不许手动算。

**阶段 2 · 能力对等（1–2 天，先写 C-1）**
`C-1 AI↔UI 能力矩阵测试`（37 条命令逐条声明 ui / both / ai-only+理由；新增命令不声明就红）
→ `C-2 饮食约束可自己设`（素食标签 + 过敏原；仓储 `load/save` 现成）→
`C-3 menu.snapshot.publish 保持 ai-only（写理由）` →（可延后）`C-4 建议按钮复用 UI 入口`。

**阶段 3 · 自检与清扫（1 天，5 项）**
`D-1 数据自检页`（孤儿 `food_id` / 日期格式异常 / 步数手动行残留，各给安全修复）→
`D-2 上次备份时间` → `E-1 六个空态各补一个动作` → `E-2 12 页 320dp×2.0× 扫描` →
`E-3 大数字不折行`。D 与 E 可同跑（都要全页扫描）。

**阶段 4 · 历史补记（半天，先裁决）**
`B-1` 把两条口径（能不能补记 / 补多久，建议 30 天）写进 `docs/60` §0.3 并**等用户答复**；
拿到答复后做 `B-3 过去日期也能「+」`（写路径已按选中日，只放开 UI 门禁 + 加「补记」徽标）。
未裁决就跳过本阶段，其余 14 项不受影响。

### 每项的完成判据（Definition of Done）

1. 有**先红后绿**的用例，RED 的失败原文记进 run-log；
2. 标注的**变异**做过并逐字还原；
3. 视觉类有实帧且**自己看过**，归档到 `docs/evidence/<日期>-<阶段>/frames/`；
4. run-log 每项一行（模板见 docs/64 §0.4）；
5. 阶段末四条门禁全绿：
   ```bash
   flutter test --exclude-tags capture test/app test/features
   flutter test test/release
   dart format --output=none --set-exit-if-changed lib test tool
   flutter analyze
   ```

### 验收（一条都不能少）

- 每个阶段：`docs/evidence/<日期>-<阶段>/` 下有 `run-log.md`（逐项一行）、
  `frames/`（实帧）、`gate-logs/00-baseline.log` 与 `99-final.log`；
- `docs/64` 的附录 C 验收表按阶段逐行填勾；
- `STATUS.md` 与 `docs/INDEX.md` 在**每个阶段结束时**追加一段（含门禁数字与实帧路径）；
- 不改 schema、不加依赖、不动 wire 信封（有违反即回滚该条）。

### 允许停止的三种情况

① 工具链彻底不可用（`flutter` 找不到 / 依赖解析连失败 3 次）；
② 磁盘或权限导致连证据都写不了；
③ 同一项连续两轮修不绿且已试过替代方案。
其余一律：按 docs/64 做完并登记，**不询问、不等待**。新发现 P0（崩溃 / 数据丢失 /
静默写错事实）就地插队修。

### 设备与凭据约束

- 只动自有 AVD `LocalFit_API35`（`emulator-5554`），禁止触碰 `emulator-5558` / `emulator-5566`。
- 真实 AI 只走环境变量，零入库；无凭据时记 `ai-live: not run`，不得声称真模型已验证。
- 本轮**不需要** GitHub / 发版操作；如果自发决定发版，先确认代理与 API 直连规则
  （git 走代理；`api.github.com` 必须直连）。

## 任务正文（复制到这里结束）

---

## 附：为什么这样写 GOAL

| 设计 | 原因 |
|---|---|
| 先读清单把 docs/64 放第一位 | docs/64 已经写死了每项的判据与文件清单，重读别的文档只会漂 |
| 阶段 0 把「未来日期守卫」插队 | 它不需要任何裁决，但是「静默写错事实」类问题（`docs/61` 纪律要求 P0 插队） |
| 阶段 1 先做 A-1 | 饮水删除把「删除 + 撤销 + 重读派生数据」的形态定死，后面三项照抄，避免四套写法 |
| 阶段 2 先写 C-1 | 能力矩阵把「哪些真缺 UI」从我的推测变成静态扫描的事实，后面的 C-2 才不白做 |
| 阶段 4 单独放最后且先裁决 | 补记会推翻「历史只读」这条既有设计；没裁决时跳过不影响其它 14 项 |
| 把 9 条踩坑写进附录 E | 这些坑在本轮各花掉 20–60 分钟（无限动画、fake_async、controller 生命周期、`dart format`） |
| 只留三种停止条件 | 避免「遇到小问题就停下等指令」，也避免「无限循环」 |
