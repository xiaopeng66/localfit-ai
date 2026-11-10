# 改进方案施工文档（2026-10-26，可直接执行）

> 来源：`docs/63` §6 的五套方案（A 删除与修正 / B 历史补记 / C 能力对等 / D 数据自检 /
> E 空态与极端字号）。本文把它们拆成**四个阶段、17 个施工项**，每项给出：现状证据
> （文件:行）、会红的判据（RED 断言原文）、施工步骤、文件清单、变异验证、实帧要求、
> 风险与回滚、验收勾选行。照本文件执行不需要再做设计决策。
>
> 三个前提先说清：
> 1. **不改 schema**（仍 30）、**不加第三方依赖**、**不动 AI wire 信封形状**；
> 2. 视觉类必须**逐张实看实帧**（本轮就是靠看图抓到 11px 溢出与一字一列）；
> 3. 每条**先红后绿 + 变异验证**，连坐红立刻修（照 `docs/60` §12 的纪律）。
>
> 验收命令（每个阶段末尾跑，一条都不能少）：
> ```bash
> flutter test --exclude-tags capture test/app test/features   # 全绿
> flutter test test/release                                    # +18（17c 判据在这套里）
> dart format --output=none --set-exit-if-changed lib test tool # 0 改动
> flutter analyze                                              # No issues found
> ```

## 0. 阶段总览与依赖

| 阶段 | 内容 | 项数 | 估时 | 是否阻塞用户 |
|---|---|---|---|---|
| **1** | 修正与删除：饮水删/体重删/菜品营养改/训练组次与会话删 | 5 | 半天 | 高（「记错了修不回来」） |
| **2** | 能力对等：能力矩阵测试 + 把 AI-only 的写入补 UI 或显式标注 | 4 | 1–2 天 | 中（不该为了删一条饮水去跟 AI 说话） |
| **3** | 数据自检页 + 空态/极端字号清扫 | 5 | 1 天 | 中（让「读了显示不对」可自查） |
| **4** | 历史日期补记（**需用户先裁决口径**） | 3 | 半天 | 高（但会改既有「历史只读」设计） |

依赖关系：
- 阶段 1 的四项互相独立，可并行；**A-1（饮水删除）是阶段 2 的 C-1 的样例**，先做它能定下「删除 + 撤销」的统一形态。
- 阶段 2 的 C-1（矩阵测试）**先写**，它会把「哪些真缺 UI」从猜测变成事实。
- 阶段 3 的 D 与 E 可同跑（都要做全页扫描），但 D 的自检项依赖 A 的删除能力（修孤儿要能删）。
- 阶段 4 必须最后做（它会把「写入日期」这条链路整体动一遍）。
- **唯一可插队项**：B-2（仓储未来日期守卫）——它不依赖任何裁决，且是「静默写错事实」类问题，
  按 `docs/61` 的纪律应当 P0 就地插队；建议**开工第一个就做**。

## 0.1 快速索引（17 项）

| ID | 一句话 | 判据要点（Key / 断言） | 主要文件 |
|---|---|---|---|
| A-1 | 饮水记录可看可删可撤销 | `water-record-sheet` / `water-record-delete-0` / 「撤销」 | `water_records_sheet.dart`(新)、`dashboard_quick_stats_row.dart`、`dashboard_page.dart` |
| A-2 | 体重可删一条 | `deleteWeight` 后 latest 回退 | `measurement_repository.dart`、`weight_records_sheet.dart`(新)、`dashboard_weight_card.dart` |
| A-3 | 菜品营养可手动改且不被 AI 覆盖 | `userEdited = true` 后来源同步不覆盖 | `dish_library_repository.dart`、`dish_nutrition_editor_sheet.dart`(新)、`menu_dish_list.dart` |
| A-4 | 训练可删一组/删整次 | `completedSetCount` 减少 / 历史行消失 | `workout_session_repository.dart`、`training_page.dart` |
| A-5 | 餐食/食物/记忆回归确认 | 三类增改删在 UI 可达 | `manual_entry_capability_test.dart`(新) |
| C-1 | AI↔UI 能力矩阵测试 | 注册表每条 action 都声明过 | `ai_ui_capability_matrix_test.dart`(新) |
| C-2 | 饮食约束（素食 + 过敏原）可自己设 | `load()` 读回同一份 / 超上限报错 | `dietary_constraints_sheet.dart`(新)、`settings_page.dart` |
| C-3 | `menu.snapshot.publish` 保持 ai-only | 矩阵里写理由 | 注册表注释 |
| C-4 | 聊天建议按钮复用 UI 入口 | 建议 action ⊆ UI 可达集合 | `chat_edit_turn.dart` 等（**可延后**） |
| D-1 | 数据自检页（三类脏数据） | 三类各检出 1 条、修复归零 | `data_self_check.dart`(新)、`data_self_check_page.dart`(新) |
| D-2 | 自检页显示上次备份时间 | 无记录时「还没有备份过」 | 同上 + 备份仓储 |
| E-1 | 6 个空态各补一个动作 | `<page>-empty-action` 存在且有效果 | 6 个页面 |
| E-2 | 12 页 320dp×2.0× 扫描 | 任一处溢出即红 | `extreme_scale_audit_test.dart`(新) |
| E-3 | 大数字极端字号不折行 | 文字盒高度 ≤ 1.5 行 | 4 处数字组件 |
| B-1 | 补记口径裁决（**先问**） | 记进 §0.5 | `docs/60` §0.3 |
| B-2 | 仓储拦未来日期（**可插队**） | `meal.create` 写未来日期抛错 | `meal_repository.dart` |
| B-3 | 过去日期也能补记 | 昨天「+」→ 记到昨天 | `nutrition_record_slot_grouping.dart`、`nutrition_page.dart` |

## 0.2 开工前 5 分钟检查（照抄执行）

```bash
cd E:/AI/Zcode/projects/localfit-ai/localfit-ai
export PATH="/e/AI/toolchains/flutter/bin:$PATH"     # 本机 flutter 不在 PATH（见 android/local.properties）
flutter --version                                     # 记一笔版本
flutter test --no-pub --exclude-tags capture test/app test/features | tail -2   # 基线：应为 +2994 ~1
powershell -NoProfile -Command "\$os=Get-CimInstance Win32_OperatingSystem; 'FreeMB=' + [int](\$os.FreePhysicalMemory/1024)"
# 可用内存 < 2.5GB：先清僵尸进程，否则会 OOM（本轮实测踩过）
```

Frames 落盘约定（取帧件必须用这个环境变量，函数里有工作区校验）：
```bash
export LF_ROUND7_CAPTURE_DIR=E:/AI/Zcode/tmp/<context>/frames
flutter test --no-pub --tags capture test/<你的取帧件>.dart
```
看完帧后 **把 PNG 拷进 `docs/evidence/<日期>-<阶段>/frames/`，并清空 `tmp/<context>/`**。

## 0.3 定义完成（每个阶段都要满足这四条才进下一阶段）

1. **判据**：本阶段每项都有一条**先红后绿**的用例（RED 的失败原文记进 run-log）；
2. **变异**：标了「变异」的项逐条做过（改坏 → 确认红 → 逐字还原 → 复绿）；
3. **证据**：实帧逐张**自己看过**并归档；`run-log.md` 每项一行（模板见 §0.4）；
4. **门禁**：四条验收命令全绿，日志归档 `gate-logs/00-baseline.log`、`99-final.log`。

## 0.4 施工记录模板（每项一行，照 docs/60 §12.10 的表头）

```markdown
| A-1 饮水删除 | `water-record-delete-0` 删除后合计减少 + 出现「撤销」 | water_records_sheet.dart(新)、dashboard_quick_stats_row.dart、dashboard_page.dart | hydration 单测 3；变异 restore→add 1 红；帧 fix2-water-records-sheet |
```

## 0.5 裁决记录（执行时只追加，不改历史行）

| 项 | 问题 | 现状 | 结论 |
|---|---|---|---|
| B-1 | 历史日期能不能补记？ | 今天只读（`nutrition_record_slot_grouping.dart:133` 注释写着这是设计） | **待用户裁决** |
| B-1 | 能补多久？ | — | 建议 30 天，**待用户裁决** |
| B-1 | （2026-10-27 追加）两条口径按本表写进 `docs/60` §0.3 并停下等答复 | 现状同上 | **用户 2026-10-27 裁决：「30 天，继续」** ⇒ ① 可以补记（推翻「历史只读」旧设计）② 窗口 30 天 ⇒ B-3 立即开工 |
| A-3 | 改菜品营养要不要回改历史餐？ | 餐记录存快照，不回改 | 已定：**只影响以后**，弹层里明说 |
| C-3 | `menu.snapshot.publish` 要不要做按钮？ | 内部动作 | 已定：**保持 ai-only**，矩阵写理由 |

---

# 阶段 1 · 修正与删除（半天）

统一形态（四条都用它，别再各写一套）：
- **入口**：列表/卡片 **长按**（`onLongPress`）或行内 ⋮ 菜单 → 弹层列出可删项；
- **确认**：`AppSheet.show<bool>` 两按钮（取消 / 删除），标题写清「删的是哪一条」；
- **撤销**：删除成功后 `AppSnackBar` + 「撤销」→ 仓储的 `restore(...)`（已有 `waterRepository.restore`、`dishLibraryRepository.restore` 可照抄）；
- **不要在卡面上加删除按钮**（误触代价高，且卡片空间紧张）。

## A-1 饮水记录：可查看、可删、可撤销

**现状证据**
- 仓储已支持删除与回写：`lib/features/hydration/data/water_repository.dart:82`（`delete`）、
  `:96`（`restore`）。
- **界面上一个调用点都没有**：`grep -rn "waterRepository.delete" lib/features/*/presentation/` = 0。
  现在只能加（`dashboard_page.dart:372` → `WaterEntryDialog`），加错了只能靠 AI 聊天里的
  `water.delete` 命令。

**判据（先红）**——新文件 `test/features/hydration/water_record_delete_test.dart`
```dart
testWidgets('长按饮水卡 → 列出今天的记录 → 删一条 → 卡上合计减少 + 弹「撤销」', ...)
  await tester.longPress(find.byKey(const Key('dashboard-stat-water')));
  expect(find.byKey(const Key('water-record-sheet')), findsOneWidget);
  expect(find.byKey(const Key('water-record-0')), findsOneWidget);
  await tester.tap(find.byKey(const Key('water-record-delete-0')));
  await tester.tap(find.byKey(const Key('water-record-confirm')));
  expect(await repository.watchDay('2026-10-26').first, ...); // 少了那条
  expect(find.textContaining('撤销'), findsOneWidget);

testWidgets('撤销 → 记录回来（走 restore，不重新 add）', ...);
testWidgets('空记录：长按不弹空列表，给「还没有饮水记录」', ...);
```
**施工步骤**
1. `dashboard_quick_stats_row.dart` 的 `WaterStatCard` 加 `onLongPress`；
   `dashboard_page.dart` 传 `_openWaterRecords`（新方法）。
2. 新件 `lib/features/hydration/presentation/water_records_sheet.dart`：
   `Future<void> showWaterRecordsSheet(context, {required WaterRepository repository,
   required String localDate})` → `AppSheet.showCustom`，列出当天每条（amount + 时间 + 删除键
   `water-record-delete-<i>`），空态一行文案。
3. 删除后 `AppSnackBar.show(actionLabel: '撤销', onAction: () => repository.restore(record))`。
4. 合计与卡片由 `watchDay` 流自动刷新（**不要手动 setState 算合计**）。

**变异**：把 `restore` 接成 `add`（金额相同但生成新 id）→ 撤销用例应红（id 变了）。
**实帧**：`fix2-water-records-sheet`（列表 + 撤销条）。
**风险**：长按与「点卡加水」冲突 → 用 `InkWell(onTap: 加水, onLongPress: 列表)`，两者都保留。
**验收行**：`A-1 | 长按→列表→删→合计减少+撤销 | water_repository.dart(无改动)、dashboard_quick_stats_row.dart、water_records_sheet.dart(新)、dashboard_page.dart | hydration 单测 3 条；变异 1 红；实帧 1`

## A-2 体重：可删一条（现在只能同日覆盖）

**现状证据**
- `lib/features/progress/data/measurement_repository.dart:23` 只有 `saveManualWeight`
  （按 `localDate` upsert），**没有删除**；`grep -n "delete"` 该文件 = 0。
- 体重卡（`sections/dashboard_weight_card.dart`）只有「添加」，卡面不可点（需求 32）。

**判据**
```dart
// test/features/dashboard/weight_record_delete_test.dart
test('仓储：deleteWeight 删掉那一行；不存在的 id 返回 null', ...);
testWidgets('体重卡「记录」→ 列出现有记录 → 删今天那条 → 最新体重回退到前一天', ...);
testWidgets('撤销：删完点撤销 → 记录回来（restore）', ...);
```
**施工步骤**
1. `MeasurementRepository` 加 `Future<WeightMeasurement?> delete(String id)` 与
   `Future<void> restore(WeightMeasurement record)`（照 `water_repository` 的两段式）。
2. 新件 `sections/weight_records_sheet.dart`（形态与 A-1 完全一致：列表 + 删除 + 撤销）。
3. 体重卡加「查看记录」入口：`dashboard-weight-add` 左侧加一枚 ⋮（`weight-records-menu`），
   **不改整卡可点**（需求 32 明确去掉过）。

**变异**：删除后不刷新 overview（去掉 `didChangeDependencies` 的重读）→ 用例红。
**实帧**：`fix2-weight-records-sheet`。
**风险**：删掉唯一一条体重会影响目标推导（`profileOverviewLoader`）→ 删完必须重读 overview
（既有 `_refreshOverviewAfterFoodWrite` 是同一套做法，照抄）。

## A-3 菜品库：营养可手动修正（现在只能被 AI 来源覆盖）

**现状证据**
- `DishLibraryRepository` 有 `create:46`、`upsertByName:138`、`upsertBySource:171`、
  `updateNutritionFromSource:318`、`delete:397`、`restore:411`——**没有「用户手动改营养」**。
- UI：菜品库列表（`sections/menu_dish_list.dart`）只展示与加入餐；无编辑入口。

**判据**
```dart
// test/features/nutrition/dish_nutrition_edit_test.dart
test('updateManualNutrition：改 kcal/三宏量；userEdited 置 true；来源同步不再覆盖', ...);
testWidgets('菜品行 → 详情 → 编辑营养 → 保存 → 列表与餐卡同步', ...);
testWidgets('编辑后 userEdited=true：dish_source_sync 不覆盖（回归既有契约）', ...);
```
**施工步骤**
1. 仓储加 `Future<DishRecord> updateManualNutrition(String id, {required double kcal,
   double? protein, double? carbs, double? fat})`：写 `dish_library` 四列 +
   `userEdited = true`（该列已存在，`upsertBySource` 会跳过 userEdited）。
2. 新弹层 `dish_nutrition_editor_sheet.dart`（复用 `AppNumberField`，形态照
   `custom_meal_sheet.dart`：热量必填、三宏量可选、**说明「改后 AI 分析不再覆盖」**）。
3. `menu_dish_list.dart` 的菜品行加 ⋮ → 「编辑营养 / 删除」（删除走 `delete` + 撤销，
   与 A-1 同形态）。

**变异**：不置 `userEdited` → 第三条判据红（同步会把用户改的数字覆盖回去）。
**实帧**：`fix2-dish-nutrition-editor`。
**风险**：菜品被「加入餐」时写的是**快照**，改菜品不会回改历史餐（`docs/60` §2 记过）——
在弹层里**明说**这一点，并给「只影响以后」的文案。

## A-4 训练：删一组 / 删一次训练

**现状证据**
- `WorkoutSessionRepository` 只有 `start:39` / `logSet:79` / `finish:166` / `listFinished*`
  ——**没有删除**。
- `WorkoutSets.sessionId` 有 `onDelete: KeyAction.cascade`（`tables.dart:344`），且
  `AppDatabase` 三处都开了 `PRAGMA foreign_keys = ON`（`app_database.dart:88/102/746`）
  ⇒ 删会话会级联删组；**测试里也要确认这条 pragma 生效**（内存库同样走 beforeOpen）。
- 训练弹层只有「记录一组 / 结束训练」；训练历史只有「训练回顾」（只读）。

**判据**
```dart
// test/features/training/session_delete_test.dart
test('deleteSet：删掉一组；会话的 completedSetCount 减少', ...);
test('deleteSession：删整次（含组次级联）；统计/历史里不再出现', ...);
testWidgets('训练弹层：长按某组 → 删除这一组（确认）', ...);
testWidgets('训练回顾：底部「删除这次训练」→ 历史行消失 + 周统计回退', ...);
```
**施工步骤**
1. 仓储加 `Future<bool> deleteSet(String setId)`、`Future<bool> deleteSession(String sessionId)`。
   级联已开（见上），但 `deleteSession` 仍**显式**删 `workout_sets` 再删会话：级联依赖
   pragma，显式删除在「pragma 被谁关掉」时也不会留孤儿（与 `clearAllLocalData` 的写法一致）。
2. `_ActiveSessionSheet` 的组次行加长按 → 确认删除；`_SessionReviewContent` 底部加
   「删除这次训练」（destructive 档，两按钮确认）。
3. 删除后 `setState` 触发 `_reloadSession` / 历史重读（页面已有的重读钩子）。

**变异**：`deleteSession` 只删会话不删组 → 判据 2 红（统计仍在）。
**实帧**：`fix2-session-review-delete`。
**风险**：删除进行中的会话会让「继续训练」横幅消失 → 弹层内必须先说明再删。

## A-5 餐食/食物/记忆：回归确认（不重做）

这三类已有完整增改删。**只加一条回归**：`test/app/manual_entry_capability_test.dart`
列出「每类记录的增/改/删在 UI 上都可达」的清单，防止以后又漏（见 C-1 的矩阵，同一张表）。

---

# 阶段 2 · 能力对等（AI 能做的，UI 要么能做要么明说）（1–2 天）

## C-1 能力矩阵测试（**先写这个**，它把猜测变成事实）

**现状证据**
- 注册表 37 条命令：`lib/features/ai_conversation/domain/chat_edit/chat_edit_registry.dart`
  （`grep -c "action: '"` = 37）。
- **已核实的 AI-only**：
  | 命令 | 证据 |
  |---|---|
  | `water.delete` | presentation 下无 `waterRepository.delete` 调用（A-1 补） |
  | `menu.snapshot.publish` | 无 UI 调用点，仅聊天命令 + `menu_snapshots` 表 |
  | `constraints.set` | `planningConstraintsRepository` 在 `lib/features`（非 ai_conversation）下无调用点 |
  | `canteen.dish.nutrition` | 只有 `dish_source_sync.dart`（AI 分析链路）调 `updateNutritionFromSource`，无手动入口（A-3 补） |
  | `dish.upsert` 的手动营养部分 | 同 A-3 |
- **已核实的双侧**：`meal.*`、`food.*`、`memory.*`、`profile.*`、`plan.*`、`workout.plan.*`、
  `session.start/finish`、`set.log`、`targets.update`（步数/饮水目标在资料页）、
  `weight.log`、`water.add`、`canteen.venue/window.*`、`canteen.dish.create/delete`。

**判据**——`test/app/ai_ui_capability_matrix_test.dart`
```dart
// 每一条命令必须在这张表里被声明为 ui / ai-only（带理由）/ both。
const declared = <String, CapabilityStatus>{ 'water.add': ..., 'water.delete': aiOnly('待 A-1'), ... };
test('注册表里的每条 action 都在矩阵里声明过（新增命令不声明就红）', ...);
test('声明为 ui 的 action，其仓储方法至少被一处 presentation 调用（静态扫描）', ...);
test('声明为 ai-only 的 action 必须写明理由，且不在 UI 可达（反之亦然）', ...);
```
实现方式：**文本扫描**（读 `lib/` 源码，正则取 `action: '...'` 与 presentation 下的仓储调用），
不引依赖、不跑运行时。矩阵表本身就是文档。

**施工步骤**
1. 建 `test/app/ai_ui_capability_matrix_test.dart` + 一张 `_declared` 表（先按上面的已核实
   结果填，未核实的标 `unknown`）。
2. 逐个核实 `unknown`（方法：`grep -rn "<repoMethod>" lib/features/*/presentation/`），
   把结论写进表——**这一步本身就是审计**。
3. 每条 `ai-only` 决定：**补 UI**（进 A/C 的某条）或**保持 ai-only 并写理由**
   （例：`menu.snapshot.publish` 是「把菜单发给 AI」的内部动作，不适合做成按钮）。

## C-2 `constraints.set` → 设置里的「饮食约束」（素食标签 + 过敏原）

> 注：这条命令不是训练限制，是**饮食约束**——`chat_edit_registry.dart:737`
> 的 `constraints.set` 只收 `dietaryLabels`（素食/纯素/无乳/无麸质）与
> `allergenAvoidances`（过敏/忌口食材）。

**现状**
- 模型：`lib/features/daily_plan/domain/planning_constraints.dart:18`
  （`dietaryLabels` ≤4、`allergenAvoidances` ≤9、`validate()` 已写好）。
- 仓储：`lib/features/daily_plan/data/planning_constraints_repository.dart:32 load()` /
  `:43 save()`——**写路径现成**。
- **没有 UI**：`grep -rn "planningConstraintsRepository\." lib/features`（排除
  `ai_conversation`）= 0。

**判据**——`test/features/daily_plan/dietary_constraints_ui_test.dart`
```dart
testWidgets('设置 → 饮食约束：勾素食 + 填「芒果」→ 保存 → load() 读回同一份', ...);
testWidgets('AI 写的约束，UI 打开就能看到（同一张表，不做第二份）', ...);
testWidgets('超过上限（5 个标签 / 10 个过敏原）→ 就地报错、不保存', ...);
test('保存后 AI 快照里出现「饮食偏好与忌口」段（硬约束）', ...); // 复用现有快照测试
```
**施工步骤**
1. 设置页「我的健康指标」组下加一行 `settings-dietary-constraints`（值显示
   「素食 · 忌口 2 项」或「未设置」）。
2. 新弹层 `dietary_constraints_sheet.dart`：四枚 `LfFilterChip`（素食/纯素/无乳制品/
   无麸质）+ 一组过敏原 chips（预置常见九类）+ 自由输入（回车添加）；保存走 `save()`。
3. 注意：**不要**把这些写进 AI 记忆（记忆是「用户说过的话」，约束是「硬规则」），
   两处各管各的；快照里两段都已经存在。

**变异**：保存后不刷新行（去掉 `setState`）→ 判据 1 红。
**实帧**：`fix2-dietary-constraints`。

## C-3 `menu.snapshot.publish`：保持 ai-only（写理由）

**判定**：这是「把今天的菜单发给模型」的内部动作（AI 起草菜单时的上下文发布），
做成手动按钮没有用户价值。**在矩阵里标 `aiOnly('内部动作：AI 起草菜单时发布快照')`**，
并补一条注释在注册表那条命令旁。

## C-4 chat 推荐按钮复用 UI 入口

**现状**：聊天卡片上的「建议按钮」已经能执行命令；但有些建议的内容（如「去看食堂目录」）
没有对应 UI 动作。
**做法**：把 `chat_edit_turn.dart` 的 suggestion 执行路径与 UI 的 action 入口共享一份
「动作名 → 回调」映射（现在执行器按命令名 switch，UI 按页面回调，两套）。
**判据**：`test/features/ai_conversation/suggestion_ui_parity_test.dart`：每条
`suggestion` 的 action 在「UI 可达」集合里（复用 C-1 的矩阵）。
**风险**：这是重构，收益不如 C-1/C-2 → **可延后**，若时间紧就只做 C-1 的静态校验。

---

# 阶段 3 · 自检与清扫（1 天）

## D-1 数据自检页（设置 → 数据管理 → 「数据自检」）

**现状证据**：没有任何自检入口；`grep -n "自检\|integrity" lib/features/settings` = 0。
已知可检的三类问题：
1. **孤儿引用**：`meal_items.food_id` 指向已删食物（`MealItems.foodId` 可空外键，删食物时
   `clearBuiltinFoods` 会置空，但「删单个食物」的路径未必）；
2. **日期格式异常**：`local_date` 不符合 `yyyy-MM-dd`（仓储有校验，但历史数据可能带进来）；
3. **步数手动行残留**：`steps_daily.source = 'manual'` 且超过 7 天（用户忘了「恢复自动读取」）。

**判据**——`test/features/settings/data_self_check_test.dart`
```dart
test('三类问题各造一条脏数据 → 都能被检出（计数正确）', ...);
testWidgets('自检页显示三类计数；点「修复孤儿引用」→ 计数归零、餐记录内容不变', ...);
testWidgets('无问题时如实说「没有发现问题」（不编一个 0 计数列表）', ...);
```
**施工步骤**
1. 新件 `lib/features/settings/application/data_self_check.dart`（纯查询 + 计数，返回
   `DataSelfCheckReport`），三条 SQL 用 drift 的 `customSelect`。
2. 新页/弹层 `data_self_check_page.dart`：三行（问题名 / 计数 / 「查看」或「修复」）。
   修复动作**只做安全的**：孤儿引用置空 `food_id`、手动步数行删除（保留传感器行）。
3. 设置页「数据管理」组加一行 `data-self-check`。

**变异**：修复只改一个表 → 计数不归零 → 用例红。
**实帧**：`fix2-data-self-check`（有脏数据 / 无问题两态）。

## D-2 自检的「写入时间」与备份时间对齐

**现状**：设置页有「自动本地备份」开关，但没有「上次备份是什么时候」。
**做法**：自检页顶部一行「最近一次备份：…」；没有就如实写「还没有备份过」。
**判据**：`backup` 仓储/设置中有记录时显示；无记录时显示「还没有备份过」。

## E-1 空态清单：每个空态都给一个能做的事

**现状证据**（`grep -rn "LfEmptyState("`）：

| 位置 | 现在 | 要补的动作 |
|---|---|---|
| `campus_menus/presentation/menu_tab_view.dart:364`「还没有食堂地点」 | 无 action | 「新建地点」→ 既有表单 |
| `dashboard/.../dashboard_meals_card.dart:142`「从第一餐开始」 | 无 action | 「记一餐」→ `recordMealEntry` |
| `nutrition/.../menu_dish_list.dart:276`「菜品库尚未配置」 | 无 action | 说明 + 「去食堂目录」 |
| `nutrition/.../menu_dish_list.dart:479`「菜品库还是空的」 | 无 action | 「去分析今天的菜单」/「手动建菜」 |
| `training/.../exercise_library_page.dart:289`「没有匹配的本地动作」 | 无 action | 「新建自定义动作」 |
| `training/.../training_page.dart:534`「还没有已结束的训练」 | 无 action | 「自由训练」→ `_startFreeSession`（2026-10-26 已加） |
| `training/.../training_page.dart:319`「还没有本地训练计划」 | **已有 action**（本轮加） | — |
| `nutrition/.../food_list_states.dart:150` | 已支持 action | — |

**判据**：每条空态一个 widget 断言 `find.byKey(Key('<page>-empty-action'))` 存在且点了有效果
（不是空回调）。**实帧**：每条一张（可合并成 `fix2-empty-states-<page>`）。

## E-2 320dp × 2.0× 全页扫描清单

**做法**：建 `test/app/extreme_scale_audit_test.dart`，对下列页面逐个挂载并断言
`tester.takeException()` 为 null + 关键 Key 可见：
今日 / 记录 / 菜单 / 食物库 / 训练 / 训练计划创建 / 动作库 / 我的（设置）/ 资料编辑 /
AI 助手 / 记忆 / 备份。
**已知历史坑**（都在文档里）：热量卡脚注（本轮修）、记录页备注（本轮修）、
步骤卡徽标行、AI 编辑卡组头（2.0× 溢出 57px，2026-10-23 修）。
**判据**：任何一页溢出即红，报出页面名 + 溢出像素。

## E-3 极端字号下的「数字不折行」

**做法**：把「大数字 + 小单位」的四处（热量 / 饮水 / 步数 / 宏量值）统一走
`FittedBox(scaleDown)`（多数已是），并在 320×2.0× 断言**单行**（量 textbox 高度 ≤ 1.5 行）。
**判据**：`lineCount == 1`（用 `RenderParagraph` 的 `getBoxesForSelection` 或高度判定）。

---

# 阶段 4 · 历史日期补记（半天；**需先裁决**）

## B-1 裁决项（先问，不猜）

需要用户点头的两条：
1. **能不能补记？** 现在是「历史只读」（设计口径，见 `nutrition_record_slot_grouping.dart:133`
   的注释）。改成可补记 = 推翻这条设计。
2. **能补多久？** 建议 30 天（再往前意义不大、且误补风险高）。

> 执行前把这两条写进 `docs/60` §0.3 的裁决记录；没有裁决就不做本阶段。

## B-2 前置：仓储层「未来日期」守卫（**必做，且与补记无关也值得做**）

**现状证据**：`MealRepository._validateDate`（`meal_repository.dart:462`）**只校验格式**，
不拦未来日期；而体重仓储已有先例（`measurement_repository.dart:35` 明确拒绝未来日期）。
⇒ AI 的 `meal.create` 现在可以写未来日期的餐，污染「今天还剩多少」。

**判据**
```dart
test('餐食不能写在未来日期（与体重同一口径）：抛 FormatException 且不落库', ...);
test('今天与过去 30 天都能写（补记窗口内）', ...);
```
**施工步骤**：`_validateDate` 增加「晚于本机今天 ⇒ 拒绝」；`today` 从 `clock.nowUtc().toLocal()`
取（与 measurement 一致），**不要**用 `DateTime.now()` 直取（仓储持有 clock）。

## B-3 记录页：过去日期也能「+」（补记）

**现状证据**：`nutrition_record_slot_grouping.dart:134`
`onAdd: !_isToday || onAddToSlot == null ? null : ...`——非今天不画加号。
**判据**
```dart
// test/features/nutrition/history_backfill_test.dart
testWidgets('选中昨天：槽位头有「+」，点了记到昨天（不是今天）', ...);
testWidgets('补记的行与今天的分开：昨天的合计只影响昨天', ...);
testWidgets('今天以外超过窗口：不画「+」，如实说「只支持补记近 30 天」', ...);
testWidgets('未来日期：不画「+」（仓储也拒绝）', ...);
```
**施工步骤**
1. 把 `_isToday` 换成 `_canAdd`（今天或窗口内过去日期）。
2. 非今天时槽位头加一枚「补记」小标（`LfBadge.dashed('补记')`），避免用户误以为是今天。
3. `NutritionActions.editMeal` 已经用 `formatLocalDate(selectedDate())` 作为 `localDate`
   （**写路径本来就按选中日**）——所以只需放开 UI 门禁 + 加标注，**不要**新造写路径。

---

# 附录 A · AI ↔ UI 能力矩阵（起始快照，执行时逐条核实）

| action | UI 入口 | 状态 |
|---|---|---|
| `meal.create` / `meal.update` / `meal.delete` | 记录页 FAB / 点行编辑 / 菜单删除 | both |
| `meal.item.update` / `meal.item.delete` | 编辑弹层内改克数 / 移除条目 | both |
| `food.create` / `food.update` / `food.delete` | 食材库添加 / 详情编辑 / 删除 | both |
| `water.add` | 饮水卡加水 | both |
| `water.delete` | **无** | ai-only → A-1 补 |
| `weight.log` | 体重卡添加（同日覆盖） | both（缺删除 → A-2） |
| `session.start` | 训练页「开始训练」/「自由训练」 | both（本轮补齐） |
| `set.log` / `session.finish` | 训练弹层 | both |
| `workout.plan.create` / `workout.plan.delete` / `plan.*` | 计划页 / 详情 | both |
| `dish.upsert` / `dish.delete` / `dish.update` 的营养部分 | 无手动入口 | ai-only → A-3 补 |
| `canteen.venue/window.create/delete/rename`、`canteen.dish.create/delete` | 菜单页管理 | both |
| `canteen.dish.update` / `canteen.dish.nutrition` | 只有 AI 分析链路 | ai-only → A-3 / 保持 |
| `targets.update`（water/steps） | 资料编辑「每日目标」 | both |
| `profile.body.update` / `profile.goal.update` | 资料编辑 | both |
| `memory.remember` / `memory.forget` | AI 记忆页 | both |
| `constraints.set`（饮食约束：素食标签 + 过敏原） | **无**（「设置 · 饮食约束」→ C-2） | ai-only → C-2 补 |
| `menu.snapshot.publish` | **无** | ai-only（内部动作，保持） |

> 表里 `both` 的行也要被 C-1 的静态扫描验证（否则是「声称有、实际没有」）。

# 附录 B · 风险登记

| 风险 | 影响 | 处置 |
|---|---|---|
| 删除让统计回退错（周统计、连续天数、目标推导） | 数字变假 | 删除后**重读**派生数据（照 `_refreshOverviewAfterFoodWrite`），并加用例断言 |
| 补记推翻「历史只读」设计 | 与既有裁决冲突 | 阶段 4 先拿裁决；UI 加「补记」徽标 |
| 菜品改营养不改历史餐（快照） | 用户以为改了 | 弹层明说「只影响以后」，必要时提供「同步到今天已记的」二次确认 |
| 跨 feature 依赖边被新增 | 分层门禁红 | 需要时就近放在同 feature；确实要跨就在 `docs/52` 白名单里**只许减不许加**的原则下讨论 |
| 能力矩阵测试用文本扫描 | 重构改了写法就误报 | 扫描规则写在测试里并注释（`action: '<name>'` 的字面量是目前唯一写法） |
| 极端字号扫描耗时 | 门禁变慢 | 放 `@Tags(['interaction-gate'])`，本地/发布前各跑一次，不进日常循环 |

# 附录 C · 每阶段的验收勾选模板

照 `docs/60` §12.10 的表头逐行填（一项一行）：

| 项 | RED 断言原文（要点） | 改动文件 | 门禁 / 变异 / 实帧 |
|---|---|---|---|
| B-2 未来日期守卫 | ✅ `meal.create` 写未来日期抛 FormatException 且不落库 | meal_repository.dart、meal_future_date_test.dart(新) | ✅ 单测 3；✅ 变异 1 红（去守卫）；无实帧（仓储层）。证据 `evidence/2026-10-26-phase0-b2/` |
| A-1 饮水删除 | ✅ `water-record-delete-0` 删除后合计减少 + 「撤销」（restore 回原 id） | water_records_sheet.dart(新)、dashboard_quick_stats_row.dart、dashboard_page.dart | ✅ 单测 3；✅ RED（未接线 3 红）+ 变异 restore→add 1 红；✅ 帧 2。证据 `evidence/2026-10-26-phase1-delete/` |
| A-2 体重删除 | ✅ `delete` 后 latest 回退到前一天 + 撤销恢复（原 id） | measurement_repository.dart、weight_records_sheet.dart(新)、dashboard_weight_card.dart、dashboard_page.dart | ✅ 单测 3（1 仓储 + 2 页面）；✅ 变异「删除不落库」2 红；✅ 帧 1 |
| A-3 菜品营养改 | ✅ `updateManualNutrition` 置 `userEdited=true`，来源同步不再覆盖（99 保持） | dish_library_repository.dart、dish_nutrition_editor_sheet.dart(新)、dish_card.dart、daily_meal_set_card.dart、menu_dish_list.dart | ✅ 单测 3；✅ 变异「不置 userEdited」1 红；✅ 帧 2 |
| A-4 训练删除 | ✅ `deleteSet` 后 completedSetCount 减少；`deleteSession` 后历史消失且组次不残留 | workout_session_repository.dart、training_page.dart | ✅ 单测 2 + 页面 2；✅ 变异「deleteSession 不删」2 红（注：只删会话的变异被 FK 级联覆盖、如实记录）；✅ 帧 1 |
| A-5 回归清单 | ✅ 17 条能力（餐食/食物/记忆既有 + 本轮四类）在 presentation 静态可达 | manual_entry_capability_test.dart(新) | ✅ 扫描 17 条；✅ 变异「水印表删 restore 调用」1 红；无实帧 |
| C-1 能力矩阵 | ✅ 注册表 37 条逐条声明（30 ui/both 带调用点标记 + 4 aiOnly 带理由 + 拼写哨兵） | ai_ui_capability_matrix_test.dart(新) | ✅ 静态扫描 4 条；✅ RED（写作期抓到错标）+ 变异 1 红（删声明）；无实帧。证据 `evidence/2026-10-26-phase2-parity/` |
| C-2 饮食约束 | ✅ 保存后 `load()` 读回同一份；AI 写的 UI 能看到；超上限就地报错不落库；快照同表 | dietary_constraints_sheet.dart(新)、settings_page.dart（回调接线）、app_router.dart | ✅ 单测 5；✅ 变异「保存后不刷新行」1 红；✅ 帧 2（含报错态） |
| C-3 snapshot 保持 ai-only | ✅ 矩阵里写理由 + 注册表旁注释（§0.5 已定） | chat_edit_registry.dart（注释）、矩阵 aiOnly | ✅ aiOnly 理由断言覆盖 |
| D-1 数据自检 | ✅ 三类脏数据各检出 1 条；修复孤儿后归零且快照列不变；日期异常只报不修 | data_self_check.dart(新)、data_self_check_page.dart(新)、settings_page.dart（入口行）、app_router/localfit_app/main（接线） | ✅ 单测 6；✅ 变异「修复不落库」1 红；✅ 帧 2。证据 `evidence/2026-10-26-phase3-selfcheck/` |
| D-2 上次备份时间 | ✅ 无记录时「还没有备份过」；备份成功写 `last_backup_at_ms` | data_self_check.dart、data_self_check_page.dart、settings_page.dart（导出成功路径） | ✅ 单测 2；帧同 D-1 两张 |
| E-1 空态动作 | ✅ 五处新空态动作各一条断言（点了有效果：回调 / 真开表单 / 真开会话）+ 既有三处保持 | dashboard_meals_card.dart、menu_dish_list.dart（两处）、exercise_library_page.dart、training_page.dart | ✅ empty_state_actions_test 5 条；✅ 变异（摘 dashboard action）1 红；✅ 帧 5 |
| E-2 字号扫描 | ✅ 12 页 320dp×2.0× 无溢出 + 首屏关键件可见；**当场抓到并修掉记忆页两处溢出（177px/186px）** | extreme_scale_audit_test.dart(新)、ai_memory_page.dart（修复） | ✅ 扫描 12 条；RED = 扫描本身；interaction-gate 标签 |
| E-3 大数字不折行 | ✅ 四处大数字（热量 consumed / 饮水 / 步数 / 宏量值）盒高 ≤ 1.5 × 生效字号 | big_number_single_line_test.dart(新)；实现无需改 | ✅ 断言 4 处 |
| B-1 补记裁决 | ✅ **用户 2026-10-27 裁决：「30 天，继续」**（可以补记、窗口 30 天，推翻「历史只读」旧设计） | docs/60 §0.3（行 6/7）、docs/64 §0.5 | ✅ 已裁决并落地为 B-3 |
| B-3 历史补记 | ✅ 昨天槽位头有「+」且带「补记」徽标、点了按被点槽位触发；正好 30 天可补记、31 天前不画「+」并如实说窗口；未来不画「+」 | nutrition_record_slot_grouping.dart（`_canAdd` + 徽标 + 窗口说明）；既有两条断言按新口径改写（见 run-log） | ✅ 单测 4；✅ 连带红 2 条按新口径改写后全绿（nut+app 1150 条）；✅ 帧 2。证据 `evidence/2026-10-27-phase4-backfill/` |

> 2026-10-27 施工注：**四阶段全部完成**——阶段 0/1 后 +3027、阶段 2 后 +3036、
> 阶段 3 后 +3061、阶段 4（B-1 裁决「30 天」后做 B-3）后 **+3066 ~1 全绿**（基线 +2994）。
> 逐项 RED 原文与变异结果见四个证据目录的 run-log：
> `docs/evidence/2026-10-26-phase0-b2/`、`-phase1-delete/`、`-phase2-parity/`、
> `-phase3-selfcheck/`，以及 `docs/evidence/2026-10-27-phase4-backfill/`。

# 附录 D · 可直接粘贴执行的引导话术

**完整任务书见 [`docs/65`](65-goal-improvement-phases-2026-10-26.md)**——复制其中
「## 任务正文」整段即可（含先读清单、纪律、阶段顺序、DoD、门禁、停止条件、设备约束）。
下面是最短版本，够启动、不够免责：

> 在 `E:/AI/Zcode/projects/localfit-ai/localfit-ai` 中，按
> `docs/64-improvement-roadmap-2026-10-26.md` 执行「改进四阶段」，连续做完、不逐条汇报、
> 不等确认。顺序：**阶段 0（B-2 未来日期守卫）→ 1（A-1～A-5）→ 2（C-1 先写）→
> 3（D+E）→（裁决后）4（B-3）**。
> 纪律：每条先红后绿（判据原文在 docs/64）、关键项做变异验证、视觉类取实帧逐张自看、
> 连坐红立刻修、不改 schema / 不加依赖 / 不动 wire 信封；阶段末跑四条验收命令
> （`flutter test --exclude-tags capture test/app test/features`、`flutter test test/release`、
> `dart format --set-exit-if-changed lib test tool`、`flutter analyze`）。
> 证据落 `docs/evidence/<日期>-<阶段>/`（run-log 每项一行 + frames + gate-logs）。
> 只在「阶段 4 需要裁决」或「同一项两轮不绿」时停下说明。

# 附录 E · 本轮踩过的坑（下一轮会重踩，先看）

| 坑 | 现象 | 处置 |
|---|---|---|
| `pumpAndSettle` 撞无限动画 | 训练页的活动横幅 / 容量图是 `animate-pulse`，测试挂 5 分钟 `did not complete` | 文件顶部设 `accessibilityFeaturesTestValue = FakeAccessibilityFeatures(disableAnimations: true)` |
| 在 fake_async 里跑真实异步 | `ExerciseSeedImporter().importIfNeeded()` 直接 await 会挂死 | 用 `tester.runAsync(...)` 包起来 |
| 弹层 controller 在退场动画被用 | `A TextEditingController was used after being disposed` | controller 由**弹层自己的 State** 持有并在 `dispose` 释放，别用 `whenComplete(dispose)` |
| `app_settings` 整表流被自己的写入触发 | 步数基线写库 → 开关流再触发一次同步 → 「首读不写 0」被二次同步抵消 | 监听方要比较**值的变化**，不能只跳过首帧 |
| 极端字号下的图标 | 320dp×2.0× 时 `Expanded` 只剩 ~9dp，14dp 图标溢出 11px | 用 `LayoutBuilder` 量真实余量决定画不画，或换 `Wrap` |
| `dart format` 会重排测试文件 | 手写代码后忘了跑 format，门禁红 | 每次改完先 `dart format lib test tool` 再跑测试 |
| 懒加载列表里的卡片没构建 | `find.byType(X).at(0)` 在空集上直接抛 IndexError | 先按名字 `scrollUntilVisible` 再取 |
| 取帧件缺关键件 | 弹层没打开 → `findsOneWidget` 红 | `shot()` 里先断言哨兵件；失败时先怀疑 route 复用了 Navigator（每轮先卸树） |
| 内存不足 OOM | VM 在**加载**测试文件时崩（`zone.cc: 95: error: Out of memory`） | 清僵尸 `flutter_tester`/`dart`；必要时 `--concurrency=2` |

# 附录 F · 估算汇总与建议排期

| 阶段 | 项 | 估时 | 依赖 |
|---|---|---|---|
| 0（插队） | B-2 未来日期守卫 | 1–2 小时 | 无 |
| 1 | A-1…A-5 | 半天 | 无（A-1 定形态） |
| 2 | C-1 → C-2 → C-3（C-4 可延后） | 1–2 天 | C-1 先写 |
| 3 | D-1/D-2 + E-1/E-2/E-3 | 1 天 | D 依赖 A 的删除能力 |
| 4 | B-1（裁决）→ B-3 | 半天 | 需裁决 |

建议按 **「B-2 → 阶段 1 → 阶段 2 → 阶段 3 →（裁决后）阶段 4」** 排；每个阶段单独一次
Git 提交（`docs/61` 的交付习惯），提交信息里带上 run-log 的相对路径。
