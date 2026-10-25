# 输入弹窗 / 菜单页 / 食物库 / 动作库 重设计方案（2026-10-04）

> 状态：已完成（2026-10-04）· 规范效力：无 · 后续以 `docs/29-ui-ux-remediation-plan.md` 为准 · 文档地图见 `docs/INDEX.md`

状态：**已完成（2026-10-04）。W1→W3→W7→W6→W2→W4→W5 七包全部交付，见 §9.6 与 `docs/evidence/2026-10-04-input-menu-foodlib-redesign.md`。**
用户指示「先拟订方案再实施 … 先不实施」，其后于同日补齐裁决（§0.2），最后要求复核全文并出终版（§13）。

依据优先级：**用户原话 > `ui设计/pages/*.html` > `docs/21` 设计系统**。
与设计稿冲突时按用户指示执行，并在证据文档里记下冲突点（§12）。

---

## 0. 需求与裁决

### 0.1 需求拆解（第一轮原话 → 编号）

| 编号 | 用户原话（截取） | 归属 |
|---|---|---|
| N1 | 「今日推荐卡片太丑了，很多文字堆在一起很杂乱，重新根据 app 主题进行多样化设计」 | W2 |
| N2 | 「食堂地点的选中和常态按钮也很丑，需要重新设计」 | W2 |
| N3 | 「添加窗口的界面也很丑陋，输入框和提示语的显示效果与软件风格格格不入，还有很多类似的输入弹窗，全部统一化」 | W1 |
| N4 | 「把食谱和计划界面删掉」 | W4 |
| N5 | 「菜单界面重新设计，能根据食堂窗口的菜品进行每日早中晚饭推荐」 | W2 |
| N6 | 「食物库界面添加食物的输入框也是，跟食堂窗口一样的问题…全部检查一遍统一改掉」 | W1 |
| N7 | 「食物添加窗口保存失败时，不要关闭窗口再弹出失败提示，而是可以继续编辑」 | W1 |
| N8 | 「食物卡片点击后需要有编辑和删除按钮」 | W3 |
| N9 | 「这里边不需要有份量（输入弹窗也不需要填写份量），营养修订也不需要，来源证据也不需要」 | W3 |
| N10 | 「这里需要的是食物名称，以及营养的图表，要可视化的图形风格界面」 | W3 |
| N11 | 「修订食物库的所有食物名称，不要有前边的编号之类的，只要品牌和名称（品牌在卡片的下边显示）」 | W3 |
| N12 | 「那个主库什么的是什么意思…（我一直都搞不清楚你那个我的界面的食物目录栏那是什么意思）」 | W3 |
| N13 | 「食物卡片右上角的 n kcal 每 100g 的标识太丑了，最好是图形化」 | W3 |

### 0.2 全部裁决（**已定，本方案的强制约束**）

| 裁决 | 内容 | 落在 |
|---|---|---|
| D1 | 食物库里**只有自建的食物**才有编辑/删除按钮，自带库没有 | W3 §5.3（**零 schema 变更**：内置条目不给入口，所以不需要墓碑表） |
| D2 | 添加标识分开「**自建**」和「**内置**」 | W3 §5.1 |
| D3 | 本周计划和食谱计划**彻底不要了，没啥用** | W4 §6 |
| D4 | 训练动作库**添加更多条目**，上网搜搜，多加一些，**做好分类** | W6 §7（新工作包） |
| D5 | 食物库下滑只能显示一部分，**加滑条**，4 万多个食物卡片都能滑动看到 | W7 §8（新工作包） |
| D6 | 食物卡**就三彩点**，但要设计好位置和排列 | W3 §5.1 |
| D7 | 今日推荐卡的**未知可以合并**，数据要清晰，最好图形化表达，少量文字 | W2 §4.4 |
| D8 | **三餐推荐不允许**同一道菜跨餐重复 | W2 §4.3 规则 3 |
| D9 | **三张表都删掉，相关的都删掉**（原话「这个功能都不需要了，要这个表干嘛，相关的都删掉」） | W4 §6（**含数据库 DROP、备份清单、清库、迁移；schema 18 → 19**） |
| D10 | **target muscle 那个不加了** | W6 §7.2（保持零 schema 变更） |

**第一轮与第二轮的待裁决已全部清空**（§11），开工前无需用户点头的项。

### 0.3 复核结论摘要（`docs/28` 终版的产出，明细见 §13）

复核查出 **10 处漏洞/矛盾**并已在本版修正（明细见 §13），其中四处会直接导致实施翻车：

1. **净多删 2 张表**：删掉 `recipe_planning/` 之后，`foodPriceFacts` / `pantryStocks`
   会变成"没有界面能看、只有 AI 能写"的孤儿（§13 H-1）。已按「一并删除」写进 §6.7
   —— **这是我超出你点名的三张表所做的唯一范围判断，单列 §6.7 讲清来龙去脉，**你可以推翻**。
2. **备份三向行为必须写清**：旧备份恢复到新版**不报错但静默丢弃**那三张表的数据；
   新版备份恢复到旧版**会报错**（§6.6）。这不是可选项，是你会碰到的真实场景。
3. **迁移顺序与守卫**：`DROP TABLE` 必须 `IF EXISTS`（v1/v2 库从没有过这些表）、
   必须子表在前、必须放在迁移链**最末**（§6.5）。漏了第一条会打死所有 v1/v2 用户的升级。
4. **17 份活文档会脱节**（§6.10 有完整清单）：不只是命令契约表与技术规范，
   还包括最容易被忽略的 **`GOAL.md`**（产品目标里还写着「本周安排」与「创作一周食谱」）、
   `README.md`、`docs/01`、`docs/08`（**隐私披露文案**，且它没有测试兜底）。
   （§13 H-8 / H-9 / H-10）

连带测试面也比原文档记的大一倍：**删 18 个文件 / 72 用例，改约 20 个文件**（§9.3）。

---

## 1. 现状定性（代码与数据核对，全部可复现）

### 1.1 输入框：`labelText` 的浮动标签 + 1px 描边 = 出框（N3 根因）

- 主题（`lib/app/app_theme.dart:181`）是 `filled: true` + `fillColor: lf.muted` +
  `enabledBorder: OutlineInputBorder(side: enabledBorderSide)`。
- 全仓 **35 处**用了 `InputDecoration(labelText:)`（**15 个文件，逐行 grep 实测**；
  另有 3 处在 `AppNumberField` 自身实现、2 处在 AI 命令 schema，与本问题无关）。
  M3 在聚焦/有值时把 label 升到输入框顶边，正好压在那条 `enabledBorder` 的 1px 描边上
  —— 设备截图 2 的「窗口名称」就是这个形态（标签骑在绿框上、框内还有独立的
  hint「例：一楼快餐」）。
- `AppNumberField` / `AppFieldLabel` 是**唯一**做对的写法：标签画在框外上方
  （`lib/app/design/widgets/app_number_field.dart:133`），所以数值字段全部安全。
- `docs/21 §3.3` 对 `TextField` 的规定是「底 `--lf-muted`、`rounded-[16px]`、
  `px-3.5 py-2.5`、**无边框**、placeholder 为 muted」——现有实现多了描边；
  而且**没有任何一份 HTML 设计稿画过"带描边的填写框"**（7 份稿子里只有
  我的页的 API Key 行内透明输入 `我的.html:421` 与对话底栏输入 `AI 工作.html:601`）。

### 1.2 弹窗清单与三处不统一

- 含文字输入的弹窗 **18 个**：17 个走 `AppSheet`，1 个是裸 `AlertDialog`
  （`next_meal_decision_section.dart:162` 通勤时间）。
- 输入框实例化点（逐行 grep）：`TextField()` 26 + `TextFormField()` 9 +
  `AppNumberField()` 32 + `LfSearchField()` 6 = **73 处**（含共享件自身的内部实现）。
  **浮动标签风险 = 上面那 35 处 `labelText`**，其中 5 处落在 W4 要删的三个编辑弹窗里
  ⇒ **实际迁移 30 处 / 12 个文件**（§3.3 有分文件清单）。
- 底部行动行：**15 处手写 `Row`** vs **2 处 `OverflowBar`**
  （`meal_editor_dialog.dart:121`、`recipe_editor_dialog.dart:97`）。
- 「保存失败先关窗再报错」：
  - **真·先关窗**（弹窗内零失败出口）：`canteen_form_sheet.dart`（表单零校验，
    保存键直接 pop 快照，错误由 `menu_tab_view._run:83` 在页面上弹 snackbar）、
    `profile_edit_page.dart:88`；
  - **混合**（本地校验内联、落库失败关窗后）：`water_entry_dialog`、
    `new_food_dialog`、`weight_entry_dialog`、`recipe_editor_dialog`、
    `meal_editor_dialog`、`meal_plan_editor_dialog`。
- 浮层内提示的硬规则（`docs/21 §3.3`）：`AppSheet` 走根导航器，浮层打开时
  页面上的 `AppSnackBar` **看不见**（实测：命中测试落在浮层内容上，且定时器
  根本不创建）——所以 N7 的诉求不是审美问题，是**当前做法在物理上不可见**。

### 1.3 今日推荐卡：一屏六行文字（N1 / D7）

`lib/features/daily_plan/presentation/next_meal_decision_card.dart`（315 行）单卡自上而下：
「下一餐」→ 餐次 + 时段 + 状态徽标 → `Wrap[「去哪里 地点未知」+「时间未知」]` →
`Row[56dp 封面 + 「吃什么」+「暂无候选」]` → 「目标影响 营养未知」→
「证据 暂无本地菜单证据」→ 一句「还没有可推荐的食堂菜品…」→ 4 个按钮。

空态下**五行都是"未知/暂无"**。诚实口径（不编数据）是对的，但没把"未知"收敛，
也没有任何图形落点（营养、进度、地点全靠字）。
另外卡外挂着一枚按钮（`next_meal_decision_section.dart:65` 的「通勤时间：时间未知」），
视觉上不属于这张卡。

使用点两处：食堂目录页顶部（`canteen_directory_page.dart:41` → `RecommendedMenuView`
→ `RecommendedMenuCard`，均为这张卡的壳）与记录页 / `next_meal_recommendation_page.dart`。

### 1.4 食堂地点选择（N2）

`canteen_venue_selector.dart`（80 行）：`AppMorphChip`、`SizedBox(height: 40)`、
标题 `titleSmall`、统计是一行长句（`我的校园 · 1 个窗口 · 1 道菜 · 已分析 0`）。
选中 = mint 实底白字、常态 = 灰底——两档形态没有进 `docs/21`，且 40 高低于 44 触达线。

### 1.5 窗口卡与菜品行

`canteen_window_card.dart:127` 的 `CanteenDishRow` 把营养拼成长串
（`295 kcal/100g · 蛋白 10g · 碳水 0g · 脂肪 24.8g`）+ `D 级`，与食物卡的
三彩点语言不是一套；卡片内距 12、三种按钮档位混排。

### 1.6 食物卡（N11 / N12 / N13 / D2 / D6）

`food_card.dart`（235 行）当前：`Row[44dp 图标 | 名称 + 三彩点宏量 | 右端「394 kcal」+「每 100g」]`
+ `Row[LfBadge「主库」| 品牌 · 份量g/份]` + 「营养不完整」行。三个问题：

1. **名称带品牌前缀**（种子库把品牌印在名字头里）；
2. **「主库 / 目录」徽标**是内部数据分层（`food_library_controller.dart:25`：
   已导入主库 = `main`、目录分片 = `catalog`），对用户无可行动信息（N12）；
3. **右上 `394 kcal` + `每 100g` 两行字**没有图形落点（N13）。

### 1.7 食物详情弹层（N9 / N10）

`food_detail_sheet.dart`（217 行）五段：`主库 · 自建 · 许可证：unknown` /
`每 100 克：…` / **份量** / **营养修订** / **来源证据**。后三段 N9 点名不要，
前两段是纯文字（N10 要图形）。

### 1.8 食物名称与品牌（N11）

- 现有 `lib/utils/text_utils.dart` 的 `normalizeFoodName` 只做「下划线/连字符换空格 +
  英文单词首字母大写」，**且有缺陷**：含中文的混合词会把内部大写压平
  （`dplus 天然酵母面包HokkaidoCream` → `…hokkaidocream`）。
- 种子库 `assets/seed/foods.v4.json`：**49,464 条，`brand` 字段一条都没有**，品牌只在 `name` 里。
- 形态实测：`^(拉丁) 其余` **5 条**（`(BellaMare)`/`(Beretta)`/`(PUAS)`/`(Bergin)`；
  `(韩国)蜂蜜柚子茶` 括号内是中文，**不是品牌**）；`拉丁首词 + 中文` **3,926 条**
  （首词 **1,596 个不同值**，其中只有 **12 个**是描述词）；`数字/℃ 开头` **201 条**；
  `名称(形态)` 的括号是食材说明（`面条(生)`、`饺子(猪肉韭菜馅)`，含括号共 12,580 条）
  —— **必须区分，不能一律砍括号**。

### 1.9 我的页「食物目录」段（N12）

`settings_page.dart:387` 的 `_catalogGroup()` **不是设计稿的产物**（`我的.html`
只有「食材库」一组）。2026-10-02 起目录不再随包（ADR-025），于是这段在正常构建里
**恒显示**「本次构建没有随包目录数据（中文食物已随包，目录按需导入）」——
一句解释自己不存在的话。

### 1.10 食谱 / 计划的完整引用面（N4 / D3 / D9）

**这是本轮最大的改动，也是复核改动最多的一节。** 逐项实测：

**（a）三个 feature 目录整体消失（30 个文件）**

| 目录 | 文件数 | 内容 |
|---|---|---|
| `lib/features/recipes/` | 6 | 仓储 / 域模型（`RecipeRecord`）/ 记录食谱为餐 / 列表 / 编辑弹窗 / 确认弹窗 |
| `lib/features/meal_plans/` | 7 | 仓储 / 周计划编辑 / 周计划视图 / 买菜清单域与弹窗 / `MealPlanEntryRecord` |
| `lib/features/recipe_planning/` | 17 | AI 生成食谱计划全链（provider / JSON 解码 / 约束与可行性评估 / 预览解析 / 激活 / 4 个弹窗 / facts 与 constraints 仓储） |

**（b）目录外还有 22 个文件引用它们**，按角色分四类：

- 装配与路由：`main.dart`（工厂与注册，:142/:147/:152/:197/:309/:317/:320/:354/:429/:487/:502-517/:540-562）、
  `app_router.dart`（:98-111 参数、:232/:364 两处 `?task=recipe-plan` 深链、:270-298 透传）、
  `localfit_app.dart`（:61-74 参数、:116-131 字段、:209-222 透传）
- 页面与动作：`nutrition_page.dart`（:220 分发 switch）、`nutrition_tab_bodies.dart`
  （两个 body 类）、`nutrition_actions.dart`（:48 `openRecipePlan`、:67 `addRecipeToMeal`、
  :87 `editRecipe`）、`dashboard_page.dart`（:39/:52/:115/:205/:220/:292/:317/:324/:330/:338/:343
  的 `mealPlanRepository` 参数与计划餐时间线）、`dashboard_meal_timeline.dart`
- AI 侧：`chat_edit_executor.dart`（:117-127 的 6 条命令）、`chat_edit_context_loader.dart`
  （:84 食谱段 + `_maxRecipes = 15`、:146-160 计划餐段、:164 `_recipeNameById`、:187 `_renderRecipes`）、
  `ai_workbench/application/recipe_plan_workbench_task.dart`、
  `ai_workbench/application/meal_pairing_workbench_task.dart`（:14 引 `recipe_record.dart`）
- 基础设施：`backup_table_registry.dart`、`clear_all_local_data.dart`

**（c）数据库层（44 张表里的 3 张，见 §6.5 的迁移细节）**

- `lib/data/database/tables.dart:366` `Recipes` / `:382` `RecipeItems` / `:403` `MealPlanEntries`
- `app_database.g.dart` 为生成物，删表类后必须重新 `build_runner` 生成
- `app_database.dart` 迁移链三处（`from < 3`、`from < 4`、`from < 10` 里的两个索引）
- **`Meals` 表不引用 `Recipes`**（`tables.dart:425`，只有 `localDate/slot/eatenAt/notes/source`）
  ⇒ **删这三张表不会碰到你的「记录」数据**，这一点是安全的
- 外键只有两处指向 `Recipes`：`RecipeItems.recipeId`（`ON DELETE CASCADE`）、
  `MealPlanEntries.recipeId`（普通引用）

**（d）测试面（实测，原文档记的偏小）**

- 专属测试目录整体删除：`test/features/recipes`（5 文件 / 18 用例）、
  `test/features/meal_plans`（3 / 9）、`test/features/recipe_planning`（10 / 45）
  = **18 个文件 / 72 个用例**
- 需改写的**约 20 个文件**：4 个数据库迁移/索引测试
  （`app_database_index_test`、`app_database_migration_test`、
  `app_database_v6_migration_test`、`app_database_v11_migration_test`）、
  `export_restore_test`（含硬编码的「44 张表」标题与三个 key 断言）、
  4 个 AI 侧（`chat_edit_executor_test`、`chat_edit_context_loader_test`、
  `meal_pairing_task_test`、`recipe_plan_task_test`）、
  7 个 app 级布局/可达性/遮挡审计、4 个饮食 tab 集成测试
- 需新增：`app_database_v19_migration_test.dart`（v18 → v19 删表）

### 1.11 训练动作库现状（D4）

- `assets/seed/exercises.v1.json` / `v2.json`：**各 60 条**（v2 = 实际导入，
  `exercise_seed_importer.dart:10` 的 `assetPath`），字段
  `id / name / muscle_group / equipment / difficulty / popularity`。
- 表结构（`tables.dart:257`）：`id / name / muscleGroup / equipment / source /
  difficulty(nullable) / popularity(nullable) / isUserCreated / createdAt / updatedAt`
  —— **没有细分部位的列**（D10 保持不加）。
- 7 个肌群分布：`legs 13 / arms 12 / chest 11 / shoulders 10 / back 8 / core 4 / fullBody 2`；
  6 种器械（bodyweight/barbell/dumbbell/machine/cable/other）；难度三档；常用度 0–100。
- 枚举 `MuscleGroup`（7 值）与 `Equipment`（6 值）在 `exercise_record.dart`，
  筛选 chips 由 `MuscleGroup.values` 生成（`exercise_library_page.dart:230`）。
- **已有数据质量缺陷**（扩充时顺手修）：`坐姿好早上`（Good Morning 误译）、
  `后 deltoid 飞鸟`（未译）、`俄罗斯转弯`（Russian Twist）、`箭步蹲` 与 `哑铃弓步蹲` 重复、
  `绳索下压` 与 `绳索下压` 重名、`哑铃颈后臂屈伸` 与 `哑铃颈后臂屈伸` 重名。
- **扩容会被截断**：`ExerciseRepository.search(..., {int limit = 100})`
  （`exercise_repository.dart:26` 的 `int limit = 100`）+ 动作库页面一次性渲染 ⇒ 加到 300 条只会显示 100 条。

### 1.12 食物库「只能显示一部分」的根因（D5）

- `FoodLibraryController.search` 合并两路：主库 `FoodRepository.search(query)`
  —— **默认 `limit = 30`**（`food_repository.dart:21`，`statement.limit(limit)`）；
  目录分片 FTS5 **只在查询非空时**才跑（`food_library_controller.dart:95`）。
- 所以**默认浏览只有 30 条**，而且没有分页、没有滑条 —— 这就是 D5 说的问题。
- 49,464 条随包种子在**首启导入主库**（`FoodSeedImporter`），即全部都在 `foods` 表里，
  分页对象是主库，不需要目录分片。
- 目录侧另一处上限：`catalog_search_service.dart:92` `_maxCandidatesPerShard = 1000`。
- **分页正确性陷阱**：现有排序是 `isUserCreated DESC, name ASC`，**没有唯一键兜底**。
  名称可重复（食物库与动作库都有重名行）⇒ `LIMIT/OFFSET` 翻页会**漏行或重复行**。
  必须补 `id ASC` 作最后一级排序，否则翻到第 N 页会出现同一张卡两次。

### 1.13 备份 / 迁移机制（W4 必须依赖的事实）

- 备份清单是**单一事实源** `LocalFitBackupTables`
  （`lib/features/backup/application/backup_table_registry.dart:106`），
  JSON 导出与 `.lfb` 加密备份共用它；顺序父表在前。
- **恢复遍历的是清单，不是备份文件的键**（`restore_localfit_data.dart:55`
  `for (final spec in LocalFitBackupTables(database).all)`）⇒ 备份文件里多出来的
  键会被**静默忽略**（不是报错）。
- 反向：清单里的表**必须**出现在备份里，否则抛 `备份缺少数据表：<key>`
  （除非该 spec 标了 `optional`）。
- 清库 `clear_all_local_data.dart` 逐表 `delete().go()`，顺序与外键一致。
- 当前 `schemaVersion => 18`（`app_database.dart:94`），迁移链是
  `onUpgrade` 里一串 `if (from < N)`；已知的历史守卫纪律：
  `createTable` 用的是**当前**表定义，所以更早的 `from < X` 分支建过的表，
  后面的 `addColumn` 要加下界（`from >= X`）否则 duplicate column（v15/v16/v18 三处注释）。
- **表总数 = 44**（`grep '^class .* extends Table' lib/data/database/tables.dart` 实测 44；
  `export_restore_test.dart:785` 的用例标题也写「44 张表逐表行数对账」）。
- **门禁基线**：`1782 passed / 3 skipped`，日志 `E:/AI/Zcode/tmp/verify_wave5e.log`
  末行 `+1782 ~3: All tests passed!`（**注意这个日志在 workspace 的 `E:/AI/Zcode/tmp/`，
  不在仓库里** —— 原文档把它写成仓库相对路径 `tmp/`，已修正）。

### 1.14 数据合规链路

- 随包数据源必须同步**三处**：`docs/THIRD_PARTY_LICENSES.md` +
  `lib/features/nutrition/domain/data_attribution.dart` + `tool/food_seed/README.md`，
  由 `test/privacy/privacy_statement_audit_test.dart:389` 对齐；
  同文件 `:459` 还要求**随包来源可删除**（需配 strip 工具，依据 docs/07 §5.3）。
- 应用侧接受的许可证白名单（`catalog_manifest.dart`）：`odbl-1.0`、`cc0-1.0`、
  `cc-by-4.0`、`cc-by-sa-3.0`、`cc-by-sa-4.0`、`public-domain`。

---

## 2. 方案总纲（七个工作包，各自独立过门禁）

| 包 | 内容 | 对应 | 改动面 |
|---|---|---|---|
| **W1** | 输入框与弹窗统一（新共享件 + 主题兜底 + 30 处迁移 + 「失败不关窗」机制） | N3 N6 N7 | 12 文件 + 1 新件 + 主题 |
| **W3** | 食物库（卡片图形化 + 三彩点排版 + 详情可视化 + 自建/内置 + 名称与品牌 + 我的页收口） | N8–N13 D1 D2 D6 | 7 文件 + 2 新件 + 词表生成物 |
| **W7** | 食物库全量浏览（分页 + 滑条 + 连续加载） | D5 | 3 文件 + 1 新件 |
| **W6** | 训练动作库扩充与分类（新上游 + ETL + 译名表 + 分页修正） | D4 D10 | 1 生成物 + 1 脚本 + 3 文件 |
| **W2** | 菜单页重设计（三餐推荐引擎 + 今日推荐卡 + 地点选择 + 窗口卡） | N1 N2 N5 D7 D8 | 6 文件 + 1 新 application 层 |
| **W4** | **删掉食谱/计划：界面 + 数据表 + AI 侧 + 迁移**（本方案最大改动） | N4 D3 D9 | **删 31 文件 / 改 22 文件**（其中装配层 5、页面与动作 5、AI 侧 5、基础设施 2、测试 20 改写另计）/ 删 3 表（§6.7 若不推翻则 5）/ schema 19 |
| **W5** | 测试、变异红证、设备走查、交付重建、文档与证据 | — | — |

执行顺序：**W1 → W3 → W7 → W6 → W2 → W4 → W5**。

理由：W1 是地基；W3/W7 同属食物库，一起走查；W6 独立；W2 先把菜单 tab 的结构定稿，
W4 再对页面壳做减项（避免同一文件改两轮）；**W4 排最后**是因为它动数据库与备份，
一旦出事影响面最大，放在前面所有切片都稳定之后再动；W5 收口。

---

## 3. W1 输入框与弹窗统一

### 3.1 新共享件 `LfTextField`（`lib/app/design/widgets/lf_text_field.dart`）

规格（写进 `docs/21 §3.10 输入框类`，**新章**）：

| 项 | 值 | 依据 |
|---|---|---|
| 标签 | 框**外上方**，与 `AppFieldLabel` 同源 | `docs/21 §3.3`「标签在行左」 |
| 底 | `--lf-muted` | §3.3 |
| 圆角 | 16 | §2.3 |
| 描边 | **常态无描边**；聚焦 2px `--lf-ring`；错误 1px `--lf-error` | §3.3「无边框」+ §2.1.6 |
| 内距 | `h 14 / v 12`（整行 h44） | §3.3 `px-3.5 py-2.5` |
| placeholder | `hintText`，muted 色 | §3.3 |
| 错误 | 框下 `bodySmall` error 色；**框内保持可编辑** | N7 |
| 无障碍 | 标签经 `Semantics` 并入输入框节点（与 `AppNumberField` 同法） | `docs/21 §8` |
| 能力 | `obscureText` / `keyboardType` / `maxLines` / `prefixIcon` / `controller` / `validator` / `autofocus` / `enabled` | 迁移面需要 |

**Key 必须落在内部 `TextField` 上**（沿用 `AppNumberField` 约定），
否则既有测试的 `enterText` / `tester.widget<TextField>()` 会失配。

### 3.2 主题层兜底（零调用点改动）

`inputDecorationTheme` 改为 `filled + muted 底 + 16 圆角 + enabledBorder
BorderSide.none + focusedBorder 2px ring + errorBorder 1px error`，
并加 **`floatingLabelBehavior: FloatingLabelBehavior.never`** —— 兜底：万一个别
`labelText` 漏网，它退化成框内占位文本，绝不会再骑到描边上。
规范靠 W1 的逐处迁移，主题层只是安全网。`searchBarTheme` 仍不引入。

### 3.3 迁移 30 处 `labelText` → `LfTextField`（12 个文件）

逐文件精确 `Edit`，改完按完整字面量 grep 复核计数（**禁止脚本化字符串手术**）。
下表是**逐行 grep 实测**的分布（合计 30；另有 5 处落在 W4 要删的三个编辑弹窗里，
不迁）：

| 文件 | 处数 | 备注 |
|---|---|---|
| `settings/…/settings_page.dart` | 7 | 协议 / Base URL / 模型名称 / 备份口令 ×2 / 恢复口令 / 清除确认 |
| `training/…/training_page.dart` | 6 | 计划名称 / 每周训练天数 / 目标描述 / 训练日 / 动作 ×2 |
| `training/…/exercise_library_page.dart` | 3 | 动作名称 / 目标肌群 / 器械类型 |
| `food_scan/…/scan_candidate_editor.dart` | 3 | 餐次 / 备注 / 食物名称 |
| `recipe_planning/…/planning_facts_editor_dialog.dart` | 3 | 预算币种 / 搜索食物 / 食物价格币种 ← **随 W4 删除，实际不迁** |
| `nutrition/…/new_food_dialog.dart` | 2 | 食物名称 / 品牌（N6） |
| `campus_menus/…/canteen_form_sheet.dart` | 1 | 用户点名的「窗口名称」 |
| `ai_workbench/…/menu_normalize_workbench_task.dart` | 1 | 菜名（卡片内嵌） |
| `ai_workbench/…/daily_menu_plan_workbench_task.dart` | 1 | 本地候选（卡片内嵌） |
| `progress/…/weight_entry_dialog.dart` | 1 | 备注 |
| `hydration/…/water_entry_dialog.dart` | 1 | 自定义毫升数 |
| `onboarding/…/onboarding_page.dart` | 1 | 日常活动程度 |
| **合计** | **30** | |
| （随 W4 删除，不迁） | 5 | `meal_plan_editor_dialog` 2、`recipe_editor_dialog` 2、`recipe_meal_confirmation_dialog` 1 |

**另外两处不属 `labelText` 但同一症状**（自绘 `Text` 当标签，一并收敛到
`AppFieldLabel`）：`training/…/workout_plan_create_page.dart`（3 处）、
`settings/…/profile_edit_page.dart`。

**顺序注意**：`planning_facts_editor_dialog.dart`（3 处）在 W4 里整文件删除。
若 W1 先做，则 W1 迁这 3 处、W4 再删文件（白做但不留残渣）；
若想省一次白做，可在 W1 里跳过它并在清单上标注「W4 将删除」。
**本方案取后者**（W1 记 27 处实做 / 12 文件，加 3 处标注跳过）。

### 3.4 底部行动行统一

全部表单弹窗按钮行统一 `Row(spaceBetween)`：**左 = 取消（B6）**、
**右 = 主行动（B2，`expand: false`）**；`OverflowBar` 两处例外收敛；
破坏性动作仍用 B7。弹层壳统一 `AppSheet`：唯一含输入的裸 `AlertDialog`
（通勤时间）迁到 `AppSheet.showForm`；两个无输入的确认对话框保留
（`dialogTheme` 已把它们收成卡片语言）。

### 3.5 「保存失败不关窗」（N7 的机制化）

**实施口径（2026-10-04 落地，与本方案原稿有一处不同，如实记录）**：新增的是
`AppSheet.showSubmitForm<T>`（而不是给 `showForm` 加 `onSubmit` 可选参数）。
原因：要求「提交中**禁用行动行**」就必须由弹层自己渲染那一行——`showForm` 的
`actions` 是调用方给的 builder，弹层拿不到它去包 `IgnorePointer`/`busy`。
`showForm` / `show` / `showStateful` / `showCustom` 的既有签名一个字没动。

```dart
static Future<T?> showSubmitForm<T>(
  BuildContext context, {
  required String title,
  required Widget Function(BuildContext, StateSetter) body,
  required Future<String?> Function() onSubmit,   // null = 成功并关闭
  T? Function()? resultBuilder,
  String submitLabel = '保存',
  String cancelLabel = '取消',
  Key? submitKey,
  Key? errorKey,
});
```

`showSubmitForm` 由 `AppSheet` 持有「提交中 / 错误文案」两态：提交中整条行动行
`IgnorePointer` + 主行动 `busy`（防重复提交）；返回错误则**不 pop**，把文案画在
按钮行上方（`Key('<x>-sheet-error')`）；`onSubmit` 自身抛异常也兜底成一句
「保存失败，请重试。」，同样不关窗。

逐弹窗接线（**所有表单弹窗通查**，不只食物）：
`canteen_form_sheet`（校验与落库一起进 `onSubmit`：名称非空、`HH:MM` 合法、
结束晚于开始、价格可解析，见 `canteen_form_validation.dart`）、`new_food_dialog`、
`water_entry_dialog`、`weight_entry_dialog`、`meal_editor_dialog`（这三个改为把
落库闭包传给弹层，弹层持有提交态）、`profile_edit_page`（确认弹窗改
`actionsAlignment: spaceBetween`；它是无输入确认弹窗，壳保持 `AlertDialog`）、
`settings_page` 三处表单、训练页四处（后两组原本就已有内联错误态与「提交中」标记，
本轮只统一行动行版式）。
（`recipe_editor_dialog` / `meal_plan_editor_dialog` 不接线 —— W4 删除。）

### 3.6 W1 验收

- `test/app/design/lf_text_field_test.dart`：标签在框外、常态无描边、聚焦有 ring、
  错误双表达、语义单节点、明暗两态取 token。
- `test/app/design/app_sheet_form_submit_test.dart`：**参数化**跑每个表单弹窗 ——
  写库抛错时**弹窗仍在屏上** + 错误文案在内 + 输入内容不丢。
- 设备：添加窗口 / 添加地点 / 添加菜品 / 新建食物 / 记录体重 / 记录饮水 / AI 配置 /
  备份口令，键盘弹起时标签不被遮、长中文标签不折行、2.0× 抽查。

---

## 4. W2 菜单页重设计

### 4.1 页面结构（替换"平铺菜品列表"）

```
Column
├ 胶囊行（W4 后只剩：记录 / 菜单 / 食物库）
├ CustomScrollView
│   ├ Hero「今日菜单」：标题 +「按你的食堂窗口推荐今天吃什么」
│   │   └ 两个统计：已安排 N 餐 · 预计 X kcal   ← 未排写「—」，不写死 3/1470
│   ├ 三餐推荐区（3 块：早餐 / 午餐 / 晚餐）
│   │   └ 每块：头行（餐次 + 供应时段 + 状态徽标）
│   │           主推菜品卡（§4.2）
│   │           动作行：换一个 · 查看候选 N 道 · 加入午餐
│   │           空态：一句成因 + 一个行动
│   ├ 「其他已分析菜品」（不在推荐时段内，仍可手动加入）
│   └ 「管理食堂目录」二级入口
```

### 4.2 主推菜品卡（沿用并强化 `DishCard`，`docs/21 §5.3` 的 1:1 结构）

4:3 封面占位渐变（按主宏量稳定取色 `dish_card.dart:73`）→ 左上餐次角标 / 右上供应时段 /
左下 `本周热门` 徽标（§3.5）→ 菜名 16 w600 → **三宏量小卡**（圆点 + 名称 + 克数 +
该项热量贡献）→ 大号 kcal + 来源徽标 → 每日目标进度条（有目标才画）→
营养师点评块（有 `comment` 才画）→ 「加入午餐」主按钮。

**不画配料行**：`docs/21 §6.2` 裁决 13 已钉死（`DishLibrary` 没有配料列）。

### 4.3 三餐推荐引擎（新 application 层，本地确定性、零 AI）

`lib/features/nutrition/application/build_daily_meal_recommendation.dart`
（或放 `daily_plan/application`，复用既有解释器）：

- **输入**：三餐槽、每餐**窗口营业时间窗**（`CanteenWindow.openTime/closeTime`）、
  `DishLibrary` 菜品（kcal / 三宏量 / 证据等级）、`DailyTargets`、
  当日**已记录**餐食（已吃的扣预算）、当前时刻。
- **规则（确定性、可单测）**：
  1. **时段过滤**：窗口在该餐时段营业；
  2. **营养预算**：按剩余目标分配（早 30% / 午 40% / 晚 30%，常量集中一处）；
  3. **不跨餐重复（D8）**：同一道菜只出现在一餐；**候选不足时该餐不给推荐**
     （走规则 6 的空态并写明成因），**不拿别的餐已经推过的菜来填位**；
  4. **证据等级优先**：`verified` > `estimated`；`incomplete`（营养不全）**不当候选**；
  5. **稳定排序**：平票按 `dishId` 升序 —— 同输入必然同输出（否则每次重进页面
     推荐都会变，用户会失去信任）；
  6. **不猜**：没有窗口 / 没有已分析菜品 / 窗口关着 → 对应餐位给空态，不退回"随便挑一道"。
- **输出**：每餐 `{主推 1, 候选 ≤5, 原因}`，复用 `daily_plan_explainer` 的表达。
- **不重写** `NextMealDecisionController`：新引擎只做"三餐都要什么"，
  下餐决策控制器仍是"下一餐"的唯一事实源；两者共用 `DishLibrary` 与目标口径，不共用状态。

### 4.4 今日推荐卡重设计（N1 / D7：合并未知 + 图形化 + 少文字）

同一张 `NextMealDecisionCard`（食堂目录页顶部与记录页共用）改成：

```
Row[ 餐次 + 时段 | 状态徽标 ]
Row[ 64dp 封面缩略 | 菜名 w600 + 证据角标 ]
一条「目标进度」图形条：该餐 kcal / 该餐预算（无数据显示「—」，不画假进度）
一行图标+文字：📍 一食堂 · 步行 8 分钟        ← 地点与通勤合成一行
动作行：查看菜单 · 换一个 · 确认加入计划（主）
```

**把"未知五项"合并成一句**（D7）：原来的「时间未知 / 地点未知 / 营养未知 /
暂无候选 / 暂无本地菜单证据」五行，改成**一句成因 + 一个行动**
（如「今晚的窗口还没录菜品」+「去添加窗口」）—— 诚实但不啰嗦：
把"逐项报缺"换成"缺什么就补什么"。**有数据时**则尽量图形化：
kcal 用进度条、地点用图标行，文字只留菜名与结论。

卡外那枚「通勤时间」按钮**移进卡内**（它是这张卡的事实之一）。

### 4.5 地点选择重设计（N2）

`CanteenVenueSelector` 改成：

- 标题行：`食堂地点`（`LfText.label` muted，与"我的"页分组标题同源）+ 右侧 B6「添加地点」；
- 地点项（**新规格**，写进 `docs/21 §3.10`）：
  常态 = `card` 底 + 1px `c.border` + `foreground` 字；
  选中 = `mint-50` 底 + 1px `mint-200` 描边 + `mint-700` 字 + 左侧 6dp 圆点；
  **高 44**（触达线）；横向可滚；
- 统计行：`1 窗口 · 1 道菜 · 已分析 0` 三个小统计（`LfStatTile` 紧凑档），
  学校名降为副标题 —— 不再是「我的校园 · 1 个窗口 · 1 道菜 · 已分析 0」一整句。

实现上**扩 `AppMorphChip` 的形态参数**，不新造第三个 chip 件（防回退审计依赖它）。

### 4.6 窗口卡与菜品行

- `CanteenWindowCard`：内距 12 → 16；窗口名 + 时段徽标；删除钮保持 B4 圆钮；
  菜品行改为 名称 + **三彩点宏量**（复用 `MacroDotLine`）+ 右侧 kcal；
  「未分析营养」改 `LfBadge.neutral`；底部三钮（添加菜品 B5 / AI 分析 B3 solid /
  加入菜品库 B3 soft）统一为一行右对齐 + 溢出换行。
- 菜品行的营养长串（`canteen_window_card.dart:150`）不再拼接。

### 4.7 实施记录（2026-10-04 落地）

落地件（15 个 `lib/` 文件 + 9 个测试文件）：

| 件 | 文件 | 实测形态 |
|---|---|---|
| 页面结构 | `nutrition/presentation/sections/menu_dish_list.dart` | hero（`已安排 N 餐` · `预计 X kcal`，未排写「—」）+ 早/午/晚三块 + 「其他已分析菜品」；空菜品库不画三个空块，改一句成因 + 行动 |
| 主推卡 | `nutrition/presentation/sections/dish_card.dart` | 三宏量小卡（圆点 + 克数 + **该项热量贡献**）、大号 kcal + 来源徽标、目标进度条、点评块、「加入午餐」主按钮；**无配料行** |
| 三餐引擎 | `nutrition/application/build_daily_meal_recommendation.dart` | 纯函数、零 AI；时段带早 `(0, 570)` / 午 `(570, 840)` / 晚 `(840, 1230)`（与 `NextMealDecisionController._slotFor` 同源）；预算 30/40/30 且**只在「未记录 且 未过点」的餐位间重分配**；候选上限 5；排序 = 证据等级 → 与预算的差距 → `dish.id` |
| 推荐卡 | `daily_plan/presentation/next_meal_decision_card.dart` + `nutrition/presentation/sections/next_meal_decision_section.dart` | 卡内新增 `NextMealDecisionCardHost`（**两处共用的接线件**）：单餐预算 + 卡内「通勤时间」按钮；降级态只报一句成因 + 一个行动（D7）；`next-meal-adjust-time` 仅 `windowClosed` |
| 地点选择 | `campus_menus/presentation/canteen_venue_selector.dart` + `app/design/widgets/{app_morph_chip,lf_stat_tile}.dart` | 地点 chip **高 44**、选中 `mint`、未选 `outlined` 档（`AppMorphChipVariant.outlined`）；统计行三个 `LfStatTile` 紧凑档 + 学校名降副标题 |
| 窗口卡 | `campus_menus/presentation/canteen_window_card.dart` | 内距 12→16；菜品行 = 名称 + `MacroDotLine` + 右侧 kcal；「未分析营养」= `LfBadge.neutral`；三钮右对齐 `Wrap`（窄屏换行、不溢出） |

**★设备走查抓到一条测试到不了的真缺陷**：食堂目录二级页那份 `NextMealDecisionCard`
是另一处调用点（`RecommendedMenuView → RecommendedMenuCard`），**绕开了记录页那套接线** ⇒
卡上写「46 kcal · 预算未知」（有当日目标却不画进度条），且**整张卡没有任何通勤入口**。
两处各接一次必然长歪，修法 = 把接线整体提成 `NextMealDecisionCardHost`（单源），
把 `now` + `mealRepository` 从 `nutrition_page` → `CanteenDirectoryPage` → `RecommendedMenuView`
→ `RecommendedMenuCard` 一路串到 host；四处 Wiring 变异（M19/M20/M20b/M21）逐条红证。
这是「同一事实两处接线」的代价，也是 §4.4 末条把它写成**共用卡**的原因。

**验证**：门禁 `tool/verify.bat` EXIT=0（**1927 passed / 3 skipped / 0 failed**，format 0 改动、
analyze `No issues found!`；W6 后基线 1877/3，净增 50 例）；**变异红证 22/22 全捕获**
（18 条形态/行为 + 4 条接线，每条按文件字节还原并校验 sha256）；设备走查
（emulator-5556 / 1080×2340 @480 ⇒ 360dp / API 35）判据全绿：hero `3 餐 · 1340 kcal`
（= 300 + 620 + 420）、本餐预算早餐 53%（300/567）· 午餐 82%（620/756）· 晚餐 74%（420/567）、
「换一个」把换走的菜送回「其他已分析菜品」、候选弹层、窗口卡三钮右对齐换行、1.0×/2.0×/深色
三态。明细见 `docs/evidence/2026-10-04-input-menu-foodlib-redesign.md` 的 W2 段。

#### §4 的五处「方案原话 → 实测落地」（已就地改正）

| # | 方案原话 | 实测落地 | 为什么 |
|---|---|---|---|
| a | §4.1 结构图把「管理食堂目录」画成列表末尾的一行入口 | hero 右上角圆形图标钮 `cta-manage-canteen` | docs/22 裁决 ② + §3.8 B4：入口收进 hero；末尾那行会把三餐区推下一屏 |
| b | §4.1 动作行「换一个 · 查看候选 N 道 · 加入午餐」在同一行 | 动作行只放 `换一个 · 查看候选 N 道`；「加入午餐」是 `DishCard` 卡内底部主按钮（§4.2 明文） | 同一动作两个入口会让人猜「哪一下才算加入」 |
| c | §4.4 动作行「查看菜单 · 换一个 · 确认加入计划」 | 多一个 `next-meal-adjust-time`「调整到达时间」，且**只在 `windowClosed` 时渲染** | 窗口没关时改到达时间没有意义；这一支正是「窗口已关」唯二能做的事 |
| d | §4.5「写进 `docs/21 §3.10`」 | 实际落在 `docs/21 §3.12`「地点 chip 的描边档」 | §3.10 已被 W1 的 `LfTextField` 占用 |
| e | §4.4「同一张 `NextMealDecisionCard`（两页共用）」 | 共用的是**接线件** `NextMealDecisionCardHost`，卡本身保持纯展示 | 卡需要两件外部事实（单餐预算 + 通勤编辑回调）；两处各接一次已经长歪过（见上） |

---

## 5. W3 食物库

### 5.1 食物卡重设计（D2 / D6 / N11 / N13）

```
Row[ 40dp 分类图标 | 名称（清洗后） | 右端：图形化热量环 ]
★ 三彩点宏量行（位置与排列见下）
底行：品牌（muted 小字）  ·  LfBadge「自建」/「内置」
```

**D6：保留三彩点，但把位置与排列设计死**（现状的问题不是彩点本身，是它挤在
名称下面、与热量列互相压宽度）：

- 彩点行**独立成行**，占满卡片宽度，不再挤在名称列里（现状名称与彩点同列，
  名称被彩点行压成 1 行省略）；
- 三项**等宽分布**（`Row` + `Expanded`），每项结构固定为
  **圆点(6dp) + 名称(10px muted) + 克数(12px w600 前景色)**，三项基线对齐；
- 排列顺序恒定 `蛋白质 → 碳水 → 脂肪`（与色板 §2.1.3 的编码顺序一致，永不调换）；
- 缺项的宏量**不占位**：剩两项时按两项等宽，不留空槽（不留白，也不编 0）；
- 三项都缺 → 整行不渲染（与现状一致）；
- 2.0× 字号下换行规则：每项 `maxLines: 1` + `FittedBox.scaleDown` 兜底，
  **不允许**把「蛋白质 12.3g」折成两行（折行会让三列基线错位）。

**D2：添加标识分两档**（不是删徽标，是换成语义正确的两档）：

| 档 | 条件 | 形态 |
|---|---|---|
| 自建 | `isUserCreated == true` | `LfBadge.mint('自建')` |
| 内置 | 其余（随包种子 / 导入目录） | `LfBadge.neutral('内置')` |

**N13：右上角 kcal 图形化** → 44dp 迷你环形 + 中心数字（`LfCaloriesRing` 的小尺寸档），
环下 10px muted 标 `每 100g`。**环的口径必须诚实**：刻度用**能量密度 0–900 kcal/100g**
（常量单源），语义写进 `Semantics`（「每 100 克 n 千卡，约为能量密度满刻度的 x%」）。
**不采用"相对每日目标"** —— 那会把"每 100 克"与"一餐预算"两个单位混进一个环里。

**N11：品牌挪到卡底**，名称用 §5.4 清洗后的 `name`。

### 5.2 食物详情弹层重设计（N9 / N10）

```
食物名（清洗后，headline）
品牌 · 自建/内置徽标
【图形化营养】大环（kcal，带每 100g 刻度）+ 三宏量占比条（4/4/9 折算，MacroRatioRow）
「营养不完整，暂不可加入确认计划」（仅不可加入时）
行动：加入餐次（如接线）· 编辑 · 删除（后两个仅自建条目渲染）
```

**删除三节**：份量 / 营养修订 / 来源证据（N9）。`FoodDetailLoader` 与数据层不动；
许可证与来源仍可在 我的 → 「数据来源与许可证」查到（`settings_page.dart:535` 已有）。

### 5.3 编辑 / 删除（N8 + D1）

**裁决 D1 已定**：只有自建条目有编辑/删除，内置库没有。

- `FoodRepository` 现状**只有** `search / searchExact / getById / create`
  —— 需新增 `update`（仅 `isUserCreated == true`，否则抛固定文案）与
  `delete`（仅 `isUserCreated == true`）；
- **零 schema 变更**：内置条目不给删除入口，所以不需要墓碑表；
- 内置条目的详情弹层**不渲染编辑/删除**（不是灰掉——不给点不动的按钮）；
- 内置条目若想改 → 后续可选做「复制为我的食物」，**本轮不做**（D1 未要求）；
- 编辑弹层 = 新建弹层的编辑态（同 `LfTextField` + 同「失败不关窗」提交路径）。

### 5.4 名称与品牌清洗（N11）

落地为**显示层纯函数**（不改 49,464 行数据、不重生成种子库）：

```dart
// lib/utils/food_name.dart
({String name, String? brand}) splitFoodName(String raw);
```

规则（按序，全部确定性）：

1. `^(拉丁词) 其余` → `brand = 括号内`、`name = 其余`
   （括号内只含拉丁字母时才算品牌；`(韩国)蜂蜜柚子茶` 不动）；
2. `首 token 其余` 且 token ∈ **品牌词表** → `brand = token`、`name = 其余`；
3. 其余原样返回（`name = raw, brand = null`）。

**品牌词表是生成物**：`tool/food_seed/build_brand_gazetteer.py` 从种子库抽出全部
「首 token」，减去 **12 个描述词停用表**
（`Golden/Value/Classic/organic/super/Pure/FINE/raw/MULTI/Fresh/premium/Extra`），
产出 `assets/seed/food_brands.v1.json`（约 1,584 条）+ 生成脚本自带单测。

**不变量（强保证，自动枚举全部 49,464 条）**：
`normalize(brand + ' ' + name) == normalize(raw)` —— **拆分绝不丢字**。
fixture 覆盖：5 条括号式、12 条停用词、`面条(生)`（括号是食材说明）、
`7-ELEVEN 7-11御饭团`、纯中文名。

**同时修 `normalizeFoodName` 的缺陷**：只对**纯拉丁**词做 title case，
含中文的混合词不压平内部大写（现在 `HokkaidoCream` → `hokkaidocream`）。

**搜索不受影响**：搜索仍按原始 `name`（含品牌）匹配 —— 搜「Beretta」依然找得到，
只是卡上不再显示前缀。

> **实施记录（2026-10-04，以实测为准）**：词表落地成 **`lib/utils/food_brands.g.dart`
> 里生成的 Dart 常量**（`kFoodBrandTokens`，**2,651 条**，sha 记在文件头），不是
> `assets/seed/food_brands.v1.json`——Flutter 读随包 JSON 只有异步 API
> （`rootBundle.loadString` 是 `Future`），而拆名发生在 `build()` 里、必须同步；
> 既有 `foods.v4.json` 也是走异步预载的，卡上不能等它。
>
> 生成脚本 `tool/food_seed/build_brand_gazetteer.py` 保留（`--check` 模式核哈希），
> 只是输出目标换成 Dart。两条阈值是实测调的：首 token 至少出现 **6 次**才算品牌；
> **纯汉字首 token 一律排除**——否则「迷你 / 理想 / 特惠 / 有限会社」这类描述词
> 会把 1,451 个词条（23,067 行）标成品牌。代价如实记录：明治 / 光明 / 雀巢这类
> 纯中文品牌留在名称里、不上卡底（不编事实优于编一个像品牌的词）；多词品牌只搬
> 首 token（约 89 行，如 `van Houten` / `la torinese` / `Dr Schar`）。
>
> 三条规则与不变量按方案实现：`test/utils/food_name_test.dart` 枚举全部 49,464 条
> （`normalize(brand + ' ' + name) == normalize(raw)` 逐条成立）；4 行以 `(` 起头的
> 名字（如 `(韩国)蜂蜜柚子茶`）按规则 1 不动。`normalizeFoodName` 的压平缺陷已修
> （只对纯拉丁词 title case，含中文的混合词保留内部大写——那是品牌在名称里的唯一线索）。

### 5.5 添加食物弹窗（N6 / N9）

- **删掉「默认份量」字段**（N9）；营养四项保留（kcal / 蛋白 / 碳水 / 脂肪，每 100g）；
- 名称 + 品牌走 `LfTextField`；**粘贴 `(Brand) 名称` 自动拆进品牌框**并给出可见提示
  （与 §5.4 同一套规则，不另写一份）；
- **保存失败不关窗**（N7）：同名重复、数值越界、写库异常全部内联，可继续编辑；
- 底部行动行统一（§3.4）。

### 5.6 我的页「食物目录」收口（N12）

- **删掉独立的「食物目录」分组**（`settings_page.dart:387` 的 `_catalogGroup`）；
- 「按需导入扩展目录」收进「食材库」组的一行 **「导入扩展食物目录（可选）」**，
  状态写副标题（正常构建不显示"本次构建没有随包目录数据"这类自述不存在的句子）；
- 「食材数据库」行的值改成可读口径：`49,464 条（自建 N 条）`。

> **实施记录（2026-10-04，以实测为准）**：`_catalogGroup` 与 `_CatalogImportCard`
> 整段删除（不是隐藏）；「导入扩展食物目录（可选）」落在「食材库」组，**状态写副标题**
> 四态：无结果时「正在检查本地分片…」、失败时「上次导入未完成：<原因>」、无分片时
> 「没有可导入的分片。」、有分片时「上次导入 N 条（x/y 个分片）。 · 未导入的分片：…」，
> 成功且全部导入写「已在库中，无需重复导入（版本）」。
>
> 「食材数据库」的 N 走新字段 `ProfileOverview.userCreatedFoodCount`
> （`COUNT(*) WHERE is_user_created = 1`）——**不用 `state` 判**：种子/导入条目也可能是
> `user_created` 之外的其它 state，而「自建」在这套数据里只有一个真源（`is_user_created`）。
> 四条用户可见文案里的指路路径同步改成「我的 → 食材库 → 导入扩展食物目录」
> （`catalog_bootstrap.dart`），设备上逐条核对过。


---

## 6. W4 删掉食谱 / 计划（N4 / D3 / D9）——本方案最大改动

### 6.0 删除范围总表（三环 + 一处超范围判断）

| 环 | 内容 | 量 |
|---|---|---|
| **1 界面与入口** | `features/recipes/`(6) + `features/meal_plans/`(7) + `features/recipe_planning/`(17) 三个目录整体删除；`recipe_plan_workbench_task.dart`；`nutrition_tab_bodies.dart` 的两个 body 类 | 删 31 文件 |
| **2 数据与基础设施** | `tables.dart` 三个表类、`app_database.g.dart` 重新生成、迁移链四处、`backup_table_registry.dart` 三条 spec、`clear_all_local_data.dart` 三行 | schema 18→19 |
| **3 AI 侧** | 6 条命令（`recipe.create/update/delete` + `plan.create/update/delete`）、`chat_edit_context_loader` 两段、任务注册（`main.dart:429`）、两处深链（`app_router.dart:232`/`:364`） | 6 命令 + 4 处 |
| **⚠ 我多删的两张表**（超出你点名范围，**可推翻**） | `foodPriceFacts` + `pantryStocks` 与相关命令 —— 见 §6.7 | 2 表 + 3 命令 |

### 6.1 胶囊行与分发

`nutrition_legacy_tab_shell.dart`：`labels/keys` 由 5 项 → **3 项**
（记录 / 菜单 / 食物库），删 `planIndex`、`recipeIndex`；
`nutrition_page.dart:220` 的 switch 与 `_selectedPlanWeek`、`_planBody`、
`_recipeBody`、`_recipeActions` 一并删除；
`app_router.dart:291-299` / `localfit_app.dart` / `main.dart` 里注入给 `NutritionPage`
的 recipe/meal_plan 参数收回。

### 6.2 三个 feature 目录删除（**动手前先整树备份**）

备份到 `E:/AI/Zcode/backups/localfit-before-plan-removal-2026-10-04/`（**本仓无 git，
删除不可逆**），然后删目录：

- `lib/features/recipes/`（6 文件）
- `lib/features/meal_plans/`（7 文件，含 `weekly_shopping_list.dart` 域）
- `lib/features/recipe_planning/`（17 文件）
- `lib/features/ai_workbench/application/recipe_plan_workbench_task.dart`
- `nutrition_tab_bodies.dart` 只删两个 body 类（文件保留）

对应测试目录同时删除：`test/features/recipes`、`test/features/meal_plans`、
`test/features/recipe_planning`（**18 文件 / 72 用例**，§9.3）。

### 6.3 装配层收线（改 5 个文件）

逐个删除下列点（括号内是实测行号）：

- `main.dart`：`recipeRepository` :142、`mealPlanRepository` :147、
  `recordRecipeMeal` :152、`buildWeeklyShoppingList` :197、
  `generateRecipePlan` :309、`loadRecipePlanDisclosure` :317、
  `resolveRecipePlanPreview` :320、`activateRecipePlan` :354、
  `RecipePlanWorkbenchTask` :429、:487 的 `createRecipe`、
  :502-517 与 :540-562 的透传，以及相应的 12 条 import
- `app_router.dart`：:26-33 的 import、:98-111 的 11 个参数、
  :232/:364 两处 `onOpenRecipePlan` 深链、:270-298 的透传
- `localfit_app.dart`：:26-33 import、:61-74 参数、:116-131 字段、:209-222 透传
- `dashboard_page.dart`：:39/:52/:115/:205/:220/:292/:317/:324/:330/:338/:343 的
  `mealPlanRepository` 参数与「计划餐」时间线分节（`dashboard_meal_timeline.dart` 同步）
- `nutrition_actions.dart`：整个文件删（:48 `openRecipePlan`、:67 `addRecipeToMeal`、
  :87 `editRecipe` 三个方法都只服务被删功能 —— 删前 grep 确认无其他调用点）

### 6.4 AI 侧收线

- 退役 **6 条对话命令**（`chat_edit_executor.dart:117-127`）：
  `recipe.create` / `recipe.update` / `recipe.delete` / `plan.create` /
  `plan.update` / `plan.delete`，连同 `_recipeCreate/_recipeUpdate/_recipeDelete/
  _planCreate/_planUpdate/_planDelete` 六个私有方法与
  `chat_edit_registry.dart` 里对应的注册项（**注册表与 switch 必须同步**，
  `chat_edit_executor.dart:166` 有测试钉住这条）。
- `chat_edit_context_loader.dart`：删 `_renderRecipes`（:187）与 `_maxRecipes`（:20）、
  计划餐段（:146-160）与 `_recipeNameById`（:164），以及 :38-51 的两个仓储字段。
- `meal_pairing_workbench_task.dart:14` 引 `features/recipes/domain/recipe_record.dart`
  —— **这个任务不是"食谱计划"，是要保留的**，需把其中依赖食谱的部分摘掉
  （改完单独跑 `test/features/ai_workbench/meal_pairing_task_test.dart` 验证）。
- 今日页「计划餐」时间线条目渲染移除（再无写入路径 ⇒ 死 UI）；
  `Meals`（你的用餐记录）**完全不受影响**（§1.10(c)）。

### 6.5 数据库迁移（**最容易出事的一节**）

`lib/data/database/app_database.dart`：

1. `schemaVersion => 18` 改 **`19`**；
2. 删 `tables.dart:366/382/403` 三个表类（`Recipes` / `RecipeItems` / `MealPlanEntries`）
   与它们上面的 `@TableIndex` 注解；
3. 重新生成 `app_database.g.dart`（`dart run build_runner build --delete-conflicting-outputs`）；
4. 迁移链**四处**改动：

   | 位置 | 动作 | 理由 |
   |---|---|---|
   | `if (from < 3) { createTable(recipes); createTable(recipeItems); }` | **整块删除**（该分支只做这两件事） | 表已不存在 |
   | `if (from < 4) { createTable(mealPlanEntries); }` | **整块删除** | 同上 |
   | `if (from < 10)` 分支 | **只删两行**：`createIndex(idxMealPlanEntriesLocalDate)`、`createIndex(idxRecipeItemsRecipeId)` | **其余 5 个索引必须保留**，整块删会丢掉它们 |
   | 迁移链**最末** | **新增** `if (from < 19)`：`DROP TABLE IF EXISTS recipe_items; … meal_plan_entries; … recipes;` | 见下三条约束 |

5. **三条硬约束（每条都有具体失败模式）**：

   - **必须 `IF EXISTS`**：v1/v2 的老库从来没建过这三张表（它们由 `from < 3` / `from < 4`
     建），裸 `DROP TABLE recipes` 会抛 `no such table`，把**所有 v1/v2 用户的升级**打死。
   - **必须子表在前**：`recipe_items.recipeId` 与 `meal_plan_entries.recipeId`
     都引用 `recipes(id)`（前者 `ON DELETE CASCADE`）。顺序
     `recipe_items → meal_plan_entries → recipes`，不依赖 FK 的未定义行为。
   - **必须是最后一步**：放在迁移链最末，将来若有人（或某分支）恢复建表逻辑，
     也不会出现"建完又被后面的分支留下"的错序。同时这条也满足"防回退"的排序纪律。

6. **不可逆**：v18 → v19 的**第一次启动就会 DROP**，这三张表里的数据（用户录过的食谱、
   计划）**永久消失**。这是 D9 的明确后果，不是意外。

### 6.6 备份 / 恢复的三向行为（必须写清，且要有测试）

清单 `backup_table_registry.dart:139/141/146` 三条 spec 删除后：

| 方向 | 行为 | 依据 |
|---|---|---|
| **新备份（v19）** | 不再包含这三张表 | registry 是导出与恢复共用的单一事实源 |
| **旧备份 → 新版应用**（v18 备份 + v19 应用） | **不报错，静默丢弃**这三张表的数据 | `restore_localfit_data.dart:55` 遍历的是 **registry**，文档里多出来的键被忽略 |
| **新备份 → 旧版应用**（v19 备份 + v18 应用） | **报错**「备份缺少数据表：recipes」 | 老版 registry 里它们非 `optional` |

- 第一、二向**要在用户可见处说明**：用 v18 时代的备份恢复到新版后，
  食谱与计划数据**不会回来**（其余表正常）。这不是 bug，是删表的既定后果。
- 第三向**不做兼容**（本应用不做降级），但要在证据文档里写明，避免以后被当成缺陷排查。
- 测试：`export_restore_test.dart` 补一条「v18 时代含三表的备份恢复到 v19 应用 →
  其余表逐表还原、不抛错、三表不被写入」。

### 6.7 ⚠ 这里我多删了两张表 —— **超出你点名的范围，你可以推翻**

**先说这两张表是什么**（都用大白话）：

| 表 | 存什么 | 举例 |
|---|---|---|
| `foodPriceFacts` | 你给某个食物记的**价格** | 「鸡蛋 8.5 元/斤」 |
| `pantryStocks` | 你家里**现有的存粮** | 「鸡蛋还有 6 个」 |

它们与你要删的三张表不是一回事，但**同属"食谱计划"那套功能**——是 v6 为了给
AI 生成食谱计划时算预算、算"冰箱里有的就不用买"而加进来的，和 `profiles` 上那四个
`planningBudget*` 列同一批。

**复核发现（§13 H-1）**：删掉 `recipe_planning/` 之后，这两张表**唯一的界面入口**
`planning_facts_editor_dialog.dart`（那个填"预算币种 / 食物价格 / 库存"的表单）
会跟着目录一起消失。剩下的消费者只有两处：

- `chat_edit_context_loader.dart`（AI 把它们读进上下文，喂给**已被删掉**的食谱计划生成器）
- 三条 AI 命令 `price.set` / `pantry.set` / `pantry.clear`（:129-133）

⇒ 也就是会变成**"界面上看不到、只有跟 AI 说话才能写进去"的孤儿数据**。

**我的处理：一并删掉**（两张表 + 三条 AI 命令 + `FoodPriceFact`/`PantryStock`
两个域模型 + 备份清单两条 + 清库两行）。表总数因此从 **44 → 39**。

**保留不动**：`profiles` 上的四个 planning 列（`planningBudgetMinorUnits` /
`planningBudgetCurrency` / `maximumDraftDeclaredMinutes` / `pantryCoverageEnabled`）
—— SQLite 删列要整表重建（drop + recreate + copy），风险与收益不成比例，空列不可见。

> **这是我自作的判断，不是你要求的**（你只点名了那三张表）。
> 之所以先删、而非先问：你说的是「相关的都删掉」，而这两张表确实只被这套功能用着。
> **不认同就说一句，改回很便宜**：把 `planning_facts_editor_dialog.dart` 从
> `recipe_planning/` 目录搬到中立位置（它自己不依赖计划生成），两张表与三条命令
> 照旧保留，价格与库存功能继续可用。**改动只涉及本节，其余方案不受影响。**

### 6.8 连带损失（实施前必须知道，均为 D3/D9 的预期）

1. 周计划与食谱的人工编辑入口消失，且**旧数据随 DROP 永久消失**；
2. 买菜清单入口消失；
3. AI 工作台的「生成食谱计划」任务入口消失；
4. 对话里「把这道菜加进周三午餐」这类指令不再识别（6 条命令退役）；
5. AI 不再知道你的食谱与计划（上下文两段移除）。
   以上不做补偿入口。

### 6.9 测试与文档同步

- 删 3 个测试目录（18 文件 / 72 用例）；改约 20 个文件（§9.3 有清单与逐条判据）；
- 新增 `app_database_v19_migration_test.dart`：v18 库（含三表与行）升到 v19 →
  **三表不存在**、其余表数据完整、`schemaVersion == 19`；
  并补一条 **v1/v2 库直接升到 v19 不抛错**（`IF EXISTS` 的守卫红证）；
- `app_database_index_test.dart`：删 `contains('idx_meal_plan_entries_local_date')`、
  `contains('idx_recipe_items_recipe_id')` 两条与 `containsAll` 里的同名两条；
- `export_restore_test.dart`：:411 `containsAll` 去三键、:435 `tables['recipes']` 断言删、
  :450-451 两条 `hasLength(1)` 删、:785 标题「44 张表」→「41 张表」（若按 §6.7 一并删则 39）；
  `seedSampleData` 里的食谱播种删掉；
- `docs/21 §4.3`（sub-tab 表）、`§5.3`（菜单页）、`§4.4`（交叉导航图）同步更新；
- **`docs/23-chat-universal-edit.md:75-80`**：那张「对话可改内容」表里的 6 行
  （`recipe.create/update/delete`、`plan.create/update/delete`）必须整行删除，
  并同步该文档的命令计数与 §「不在对话里改」清单 —— **这份文档是命令契约的单一事实源**，
  漏改会让后来者以为命令还在；
- **`docs/03-data-and-contracts.md:54`**：那条严格营养计算规则里点名了
  `recipe_items` 与「计划快照」（「历史 `meal_items`、`recipe_items` 和计划快照必须保留
  使用的 revision 或完整数值快照」）。删除这两张表后该句要改成只留 `meal_items`，
  否则契约文档在描述不存在的表；
- **`docs/07-localfit-2.0-development-spec.md`**：:91 的饮食 tab 清单（`记录、计划、校园菜单、
  食物库、食谱、采购清单`）改成 `记录、菜单、食物库`；:101「创作一周食谱」场景标注下线；
  :57-58 的「事实源」与「三个 Provider 合同」（含 `recipe-plan.v1`）同步改为两个
  （餐图识别 + 训练计划）—— **这三处都在讲"系统有什么能力"，不改会与实际不符**；
- **`GOAL.md`（实测 6 行要改；它是"活文档清单"里最容易漏的一份）**：
  :16 产品目标「今天和**本周**应该怎样安排饮食与训练」、:33 AI 工作台任务「创作一周食谱」、
  :43 冻结合同里的 `recipe-plan.v1`、:81 饮食页「五 chip」与菜单页描述、
  :93 本地数据清单里的「食谱、计划」、:107 执行路线 2.0-4「菜单/**食谱**/食物候选」。
  **这 6 行都在描述"系统有什么能力"，不改就是"目标文档说要做、代码已经删了"。**
  （这类活文档漏网是本项目的已知坑：上一轮 UI 重建就漏过 GOAL/README/docs01/docs04 ——
  查引用要按「活文档清单」过一遍，不能只 grep 表名。）
- 备份格式文档与「数据来源」页若提到这三张表，一并更新（`docs/evidence/` 下的历史证据
  文档是**当时的记录**，不回改，只在新证据里说明它们记录的功能已下线）。

### 6.10 活文档同步完整清单（17 份，实测逐份 grep 得出）

**A 类：必须改（描述"系统有什么能力"，不改就是文档与代码互斥）**

| 文档 | 要改的点 |
|---|---|
| `GOAL.md` | :16 产品目标「今天和**本周**」/ :33 AI 任务「创作一周食谱」/ :43 冻结合同 `recipe-plan.v1` / :81「五 chip」与菜单页 / :93 本地数据清单 / :107 执行路线 2.0-4 |
| `README.md` | :42 冻结合同 `recipe-plan.v1` / :47「饮食页五 chip」 |
| `docs/01-product.md` | :56 五 chip 导航 / :60 计划 tab / :62 食谱 tab / :95「创作食谱」/ :156 / :176 / :177（AI 周计划/周报） |
| `docs/02-architecture.md` | :104「餐图、食谱计划和训练计划」三个 Provider / :238 |
| `docs/03-data-and-contracts.md` | :54 严格营养计算规则点名 `recipe_items` 与计划快照 |
| `docs/04-roadmap.md` | :47 `recipe-plan.v1` 兼容测试 / :84 / :136 |
| `docs/07-localfit-2.0-development-spec.md` | :57/:58 事实源与三个 Provider 合同 / :91 饮食 tab 清单 / :101「创作一周食谱」场景 |
| `docs/08-store-privacy-and-permissions.md` | :22（食谱任务的约束名称入 prompt）/ :23 / :24 AI 快照清单含「计划餐、库存、食谱」/ :41 食谱创作合同行 / :95 披露文案覆盖范围 —— **这份最重要：隐私说明必须与实际行为一致（GOAL §7 总验收的硬要求）** |
| `docs/21-ui-redesign-spec.md` | 12 处：§4.3 sub-tab 表、§4.4 交叉导航图、§5.3 菜单页结构、§7.2 新增表（含 `recipe_items` 等）、§8 测试策略 |
| `docs/22-ui-redesign-refactor-plan.md` | 9 处（UI 改造方案里对食谱/计划页的作业项） |
| `docs/23-chat-universal-edit.md` | :75-80 六条命令的契约表 + 命令计数 + 「不在对话里改」清单 |
| `docs/24-ai-provider-protocols.md` | :23「七个 AI 出口」含食谱直连 / :215「三个直连 provider」 |
| `docs/DECISIONS.md` | :12 事实源清单含「食谱、计划」（**只加一条新 ADR 记录本次删除，不改历史 ADR 原文**）/ :22 |

**B 类：顺带改（举例或清单里提到，留着不算错但会误导）**

| 文档 | 要改的点 |
|---|---|
| `docs/11-code-review-and-bug-hunt-plan.md` | :92 举例「食谱计划启用要一次建食谱+计划餐次」 |
| `docs/26-ui-display-review-plan.md` | :40 二级页面清单含「食物/食谱/计划编辑」 |
| `docs/THIRD_PARTY_LICENSES.md` | :46 食物种子的清理规则写「只删没有被**食谱**/餐次/菜单匹配/库存/价格事实引用的行」——删表后这条要改成只列剩余引用者 |

**C 类：明确不改**

- `docs/evidence/**`（历史证据）：**当时的记录**，不回改；只在本次新证据里说明
  它们记录的功能已下线。
- `docs/history/**`：历史归档，同上。
- `docs/25-code-review-plan.md`、`docs/09-*`、`docs/05-*`、`docs/06-*`：实测 grep 零命中，不动。

**顺带提醒**：`test/privacy/privacy_statement_audit_test.dart:389` 对齐的是
`data_attribution.dart` + `tool/food_seed/README.md` + `THIRD_PARTY_LICENSES.md`
三处（**未**覆盖 `docs/08` 的披露文案），所以 docs/08 的改动**不会有测试兜底**
—— 必须靠人工核对，别指望门禁红。

### 6.11 实施记录（2026-10-04 落地，以实测为准）

**先说与方案原稿不同的地方**（按 §3.5 / §4.7 / §5.5 / §7.6 的同一体例，逐条如实记）：

1. **`nutrition_actions.dart` 文件保留**（方案 §6.3 写的是「整个文件删」）。实测删掉
   `openRecipePlan` / `addRecipeToMeal` / `editRecipe` **三个方法**即可——该文件里
   还有 5 个方法（`editMeal` / `deleteMeal` / `deleteMeals` / `reuseMeal` /
   `createFood`）被 `nutrition_page.dart` 使用，删整文件会连带打死餐食编辑、
   删除、复用与自建食物四个入口。**方案原文写错了，代码以实测为准。**
2. **`constraints.set` 未退役**（方案 §6.4 只说要退役 6 条，没提它）。它写的是
   `profiles.allergenAvoidancesJson`，**活跃读取者是 `DailyPlanEngine` 的过敏冲突
   过滤**，与食谱无关。该命令所依赖的 `PlanningConstraints` 与仓储原先住在被删的
   `recipe_planning/` 目录里，因此**搬迁**到 `lib/features/daily_plan/domain/
   planning_constraints.dart` 与 `lib/features/daily_plan/data/
   planning_constraints_repository.dart`（两个文件顶部都留了「位置说明」注释）。
   已记入 ADR-026 的 Consequences ④。
3. **退役命令是 10 条，不是 9 条**：方案预计 6 条（§6.4）+ 3 条（§6.7）= 9 条，
   实测还多退役一条 **`planning.preferences.set`**——它写的是同一套「预算 / 库存
   覆盖」规划偏好，两张表与生成器都删了之后它也变成「界面无入口、只能跟 AI 说」。
   命令注册表 **33 → 23**（`chat_edit_registry` 与 `chat_edit_executor` 的 switch
   同步；`constraints.set` 在 23 条里）。
4. **迁移链是 5 处改动，不是 4 处**（方案 §6.5 列了四处）：方案没列
   **`if (from < 6)` 分支里的两条 `createTable(foodPriceFacts)` /
   `createTable(pantryStocks)`**——这两张表随 §6.7 一并删了，留着这两行会
   `undefined getter`（编译期就红）。该分支的四个 `addColumn(profiles, planning*)`
   **原样保留**（那四列按 §6.7 不删）。新增的 `if (from < 19)` DROP 块含 **5 条**
   `DROP TABLE IF EXISTS`（方案里是 3 条），顺序
   `recipe_items → meal_plan_entries → recipes → pantry_stocks → food_price_facts`
   （子表在前），且**位于迁移链最末**。
5. **`DROP` 前的备份**：整树备份落在
   `E:/AI/Zcode/backups/localfit-2026-10-04-before-w4/localfit-lib-test-tree.tgz`
   （730 条目 / 585 个 `.dart`：`lib/` 322、`test/` 263；
   sha256 `185025464389be12720cd20cc2f106ff37c16a981e34e3e1973842b4e309bb4b`）。
   设备走查前另备份了模拟器上的 v18 数据库（见证据文档）。
6. **一处方案没列举的死入口**：AI 对话**欢迎卡**的底部 CTA。方案 §6.8 写「不做补偿
   入口」，但没点名这个组件——`FeatureCardMessage.onPrimaryTap` 原先必填且指向
   「食谱计划预览」。落地做法是把两个回调改成**可选**（`VoidCallback?`），欢迎卡
   一个都不传 ⇒ `cta-write-plan` 与右上角 `feature-card-view` 两个 Key 都**不再
   渲染**；卡片本身保留（3 条特性列，只展示能力、无动作）。这是「删掉死入口」而不是
   「给食谱计划找新去处」。
7. **两处用户可见文案顺带改正**（都属于「描述不存在的能力」）：
   - 设置页「清除全部本地数据」确认文案改为「将删除全部档案、餐食、训练与统计，
     以及导入的校园菜单与食物目录数据，且不可撤销。此操作不会删除已导出的备份文件。」
   - 新建 / 编辑食物弹窗「我已确认本地事实」的副标题：原「未知时不会用于
     **食谱限制核验**。」→ 现「未知时标签留空，**过敏冲突核验**不会用到它。」。
     依据是实测：`FoodConstraintKnowledge` 已经没有 live 门控消费者，实际参与核验的
     只有 `DailyPlanEngine` 的 `food.allergensJson ∩ profiles.allergenAvoidancesJson`
     过敏冲突——写「食谱限制核验」是在承诺一个已删功能的门控。

**计数核对（as-built，逐项实测）**：

| 项 | 方案预期 | 实测 |
|---|---|---|
| 数据库表 | 44 → 41（若按 §6.7 一并删则 39） | **39** |
| 备份 registry spec | 同表数 | **39** |
| 对话命令 | 33 → 24（若按 §6.7 则 23） | **23** |
| AI 出口 | 7 → 6（直连 3 → 2） | **6 / 2** |
| 营养页 sub-tab | 5 → 3 | **3** |
| AI 工作台任务 | 7 → 6 | **6** |
| `schemaVersion` | 18 → 19 | **19** |
| `app_database.g.dart` 里五个旧表引用 | 0 | **0** |

**测试面**：删 3 个测试目录（`test/features/recipes` / `meal_plans` /
`recipe_planning`）；新增 `app_database_v19_migration_test.dart` 两条（满库 v18 →
v19、裁剪 v1 库 → v19）；`app_database_v6_migration_test.dart` 重写为「v5 → v19」
（第二处 `IF EXISTS` 覆盖点——v5 库从没有价格 / 库存表）；
`export_restore_test.dart` 新增一条 §6.6 的行为测试「v18 时代的备份恢复到 v19
应用：其余表还原、不抛错、已删表不被写入」，并把「44 张表逐表对账」改成 **39 张表**。
**三向行为**里「旧备份 → 新版应用」有测试兜底；另两向（新备份 → 旧版应用报错、
新版备份不含这五张表）由 registry 单一事实源决定、不做降级，见 §6.6 与 ADR-026。

**门禁 / 变异 / 设备**：见 `docs/evidence/2026-10-04-input-menu-foodlib-redesign.md`
的 W4 段（退出码、变异红证明细、360dp 逐页截图与 2.0× 抽查）。

---

## 7. W6 训练动作库扩充与分类（D4 / D10）

### 7.1 上游选型（许可证优先）

| 候选 | 许可证 | 内容 | 结论 |
|---|---|---|---|
| **yuhonas/free-exercise-db** | **Unlicense（public domain）** | **800+ 条**，字段 `id / name / force / level / mechanic / equipment / primaryMuscles / secondaryMuscles / instructions / category / images` | **选它**：许可证映射到白名单里的 `public-domain`，无归属义务、无 share-alike |
| wger（wger.de） | CC-BY-SA 4.0 | 量大 | 备用；share-alike 与归属文本要单独处理 |
| ExerciseDB / MuscleWiki / ExRx | 专有 | — | 不用 |

选它的另一个理由：`primaryMuscles` 有细分部位（胸/上背/下背/臀/小腿/前臂/腹/斜方…），
`level` 直接映射我们已有的三档难度；`equipment` 映射到 6 种器械枚举。

### 7.2 规模与分类目标

- **规模：60 → 约 300 条**（上游 800+ 里筛掉需要器械我们枚举不了的、以及重复动作）；
  **实测 312 条**（上游派生 305 + 手写保留 7；候选池 748 / 上游 876），逐肌群实测见 §7.6；
- **7 大肌群分布目标**（用现有 `MuscleGroup` 枚举，筛选 chips 不变）：
  `chest ≈ 40 / back ≈ 45 / legs ≈ 55 / shoulders ≈ 40 / arms ≈ 45 / core ≈ 45 / fullBody ≈ 30`；
- **器械**覆盖现有 6 档（自重/杠铃/哑铃/器械/绳索/其他），每档 ≥ 20 条；
- **难度**三档齐全；**常用度** 0–100（上游无此字段 → 由规则生成：多关节/大肌群基础动作
  高分，孤立小肌群动作低分，映射表是**确定性常量**，不随机）；
- **分类呈现**：肌群筛选 chips（现有）+ 器械（卡片副行已有）+ 难度（卡片已有）+
  搜索（动作名 + 肌群标签，现有）。
- **细分部位不上卡（D10 已定）**：上游的 `primaryMuscles`（上胸/背阔肌/斜方肌…）
  **本轮不落库、不上卡**。理由是现有 `exercises` 表没有能存它的列，显示「胸 · 上胸」
  需要加一个可空列 ⇒ schema 18 → 19 的迁移 + 备份/清库/CSV 表清单 + 迁移测试；
  而"做好分类"用 7 肌群 + 器械 + 难度三层已经满足。
  （**注意版本号冲突**：W4 也把 schema 推到 19。两包都动 schema，所以
  **W4 与 W6 的 schema 变更要合并成同一次版本号 19**，否则会出现 19/20 两次迁移。
  D10 决定不加列后，实际上 schema 19 只由 W4 触发，W6 零 schema 变更 —— 无冲突。）

### 7.3 落地方式（沿用食物种子的纪律）

1. 上游 JSON 保留原始文件 `tool/exercise_seed/raw/free_exercise_db.json`（ETL 可重跑）；
2. `tool/exercise_seed/build_exercises.py`：
   - 器械前缀 + 动作名词表翻译英文名 → 中文（`name_zh.tsv` 人工表兜不规则名）；
   - **缺译即失败退出**（沿用食物种子的硬规则：不许拉丁字母名漏进库）；
   - 肌群映射表 `primaryMuscles → MuscleGroup`（多主肌群时取第一个，其余进 secondary）；
   - 输出 `assets/seed/exercises.v3.json`（`version` + `exercises[]`），
     字段与 v2 兼容（`id/name/muscle_group/equipment/difficulty/popularity`）
     **外加一个 `origin` 来源标记**（§7.5 的删除工具按它作业；Dart 导入器不读它，
     所以仍然是零 schema 变更）；
3. `ExerciseSeedImporter` 的 `assetPath` 改指 v3；旧 v1/v2 行按既有的
   「只插缺的 id」策略处理，并**新增一次性清理**：删掉 v2 里已知的错译/重名行
   （`坐姿好早上`、`后 deltoid 飞鸟`、`俄罗斯转弯`、重复的 `绳索下压`、
   重复的 `哑铃颈后臂屈伸`），**只删没有被训练会话引用的行**（与食物库
   `_purgeLegacySeeds` 同一纪律）；
   **实测落地（偏离，见 §7.6）**：3 条错译改成**同一个 id 原地改对**不删行，
   只有 2 条重名重复行会被删、且要没被 `planned_exercises`/`workout_sets` 引用；
4. 单测：条数、7 肌群分布下限、器械全覆盖、无拉丁字母名、无重名、
   `popularity ∈ [0,100]`、`difficulty ∈ {beginner,intermediate,advanced}`、
   id 唯一且全部以 `ex-` 开头。

### 7.4 必须同时修的分页/截断（否则加了白加）

- `ExerciseRepository.search(..., {int limit = 100})` → 提到 **500**（300 条一次取完，
  动作库不是 4 万条量级，不需要虚拟滚动）；**已实施**（`exercise_repository.dart`
  `int limit = 500`；实测「空查询返回整库 312 条」有专门断言）；
- 排序补唯一键兜底：现在是 `isUserCreated DESC, name ASC`，
  **重名动作（如两个「绳索下压」）在 LIMIT 下顺序不稳定** ⇒ 末尾补 `id ASC`；
- 动作库列表加 `Scrollbar`（与 W7 同一件共享件，见 §8.3）。

### 7.5 合规同步（三处 + 一个测试）

`docs/THIRD_PARTY_LICENSES.md`（新增「随包动作种子」小节，写上游 / Unlicense /
规模 / 可删除工具）、`lib/features/nutrition/domain/data_attribution.dart`
（或新建 `features/training/…/data_attribution` 并在 App 内「数据来源与许可证」列出）、
`tool/food_seed/README.md`（生成脚本的家）—— 由
`test/privacy/privacy_statement_audit_test.dart:389` 对齐；
并按 `:459` 的要求提供 **可删除工具**（`tool/exercise_seed/strip_exercise_source.py`，
与食物种子的 strip 脚本同形）。

**实测落地（偏离，见 §7.6）**：三处 = `lib/core/attribution.dart`（共享值类型）+
`lib/features/nutrition/domain/data_attribution.dart`（食物清单）+
**`lib/features/training/domain/data_attribution.dart`（动作清单）**，由
`settings_page.dart` 的「数据来源与许可证」弹层合并列出；动作种子的家是
**`tool/exercise_seed/README.md`**（不是 `tool/food_seed/README.md`）；对齐它的是
**按名字定位**的两条新测试：`动作来源清单与生成脚本/README 对齐`（`:501`）与
`docs/28 §7.5 的「删除/替换来源」脚本存在（动作种子那一份），且来源清单与种子里的一致`（`:539`）。
（原稿的 `:389` / `:459` 是**食物**那两条的行号，且会随文件增长漂移，改成按名字定位。）

### 7.6 实施记录（2026-10-04 落地）

规模与分布（`build_exercises.py --report` 实测，脚本默认输出 = 重建随包资产）：

| 维度 | 实测 |
|---|---|
| 规模 | **312 条** = 上游派生 305 + 手写保留 7（候选池 748 / 上游 876；排除 123 条拉伸 + 5 条以颈部为主） |
| 肌群 | chest 42 / back 46 / legs 62 / shoulders 41 / arms 45 / core 45 / fullBody 31（目标 ≈40/45/55/40/45/45/30 **全部达标**） |
| 器械 | bodyweight 50 / barbell 124 / dumbbell 62 / machine 20 / cable 34 / other 22（每档 ≥ 20，machine 正压线） |
| 难度 | beginner 171 / intermediate 122 / advanced 19（每肌群 ≥ 1 条高级） |
| 常用度 | 35–89，29 个不同取值（确定性常量表，非随机） |

- **器械下限在生成器里也拦一道**：任一档不足 20 时 `build_exercises.py` 以 1 退出、
  不写文件（变异 P9 实测），所以「每档 ≥ 20」不只是测试里的断言。
- **保 id 换源**：3 条错译（`坐姿好早上`→`坐姿早安式`、`后 deltoid 飞鸟`→`绳索反向飞鸟`、
  `俄罗斯转弯`→`俄罗斯转体`）用**同一个 id 原地改对**；只有 2 条重名重复行
  （`绳索下压`、`哑铃颈后臂屈伸` 的重复项）会被删，且**只删没被
  `planned_exercises`/`workout_sets` 引用的**（`_purgeBadLegacyRows`，双向守卫；
  实测被计划引用时那行会被保住 —— 变异 D3 里数据库甚至直接用外键拒绝删）。
- 改名是**双向登记**的：`test_build_exercises.py` 里的 `V2_RENAME_ALLOWLIST`
  （20 条，A 错译 3 / B 书写 9 / C 补前缀 8）两端各钉一次 —— 多改一条红、
  名单里有一条其实没改也红。
- 资产多一个 `origin` 字段（剥离工具靠它）；Dart 导入器不读 ⇒ **W6 零 schema 变更**（D10）。
- §7.4 三项全部落地；`LfScrollbar` 在 W7 已挂到动作库，本包未再动。
- **验证**：门禁 `tool/verify.bat` EXIT=0（1877 passed / 3 skipped / 0 failed，format 0 改动、
  analyze `No issues found!`）；**变异红证 19/19 捕获**（11 条 Python ETL/剥离 + 8 条 Dart，
  每条都字节还原并校验 sha256）；设备走查（emulator-5556 / 360dp）判据 ①–⑨ 全绿，
  含「走到底收齐的动作名集合 == 随包 312 条」。明细见
  `docs/evidence/2026-10-04-input-menu-foodlib-redesign.md` 的 W6 段。

#### §7 的三处「方案原话 → 实测落地」（已就地改正）

| # | 方案原话 | 实测落地 | 为什么 |
|---|---|---|---|
| a | §7.3.3「删掉 v2 里已知的错译/重名 5 行」 | 3 条错译**原地改名保 id**，只删 2 条重名重复行（且要没被引用） | 删行会让用户已有的计划/历史指空，v2 的 id 是用户数据的锚 |
| b | §7.5「（生成脚本的家）`tool/food_seed/README.md`」 | `tool/exercise_seed/README.md` | 动作 ETL 有自己的目录与自己的剥离工具，塞进食物 README 会让两边都对不上 |
| c | §7.5 用 `privacy_statement_audit_test.dart:389/:459` 定位 | 改成按**测试名**定位（两条新测试） | 行号随文件增长漂移，钉名字才不空转 |

---

## 8. W7 食物库全量浏览（D5：滑条 + 手滑到底）

### 8.1 根因回顾

默认浏览走了 `FoodRepository.search(query)` 的 **`limit = 30`**（`food_repository.dart:21`），
所以下滑永远只有 30 张卡（§1.12）。要"4 万多个都能滑到"，必须换成分页 + 滑条。

### 8.2 分页方案（随机访问优先，因为滑条要能拖到任意位置）

- **总数**：`SELECT COUNT(*)` 拿真实总数（49,464），一次即可，用于
  **让滑条的长度代表真实总量**（而不是"已加载量"）；
- **分页**：`LIMIT 50 OFFSET n`（**OFFSET 而非 keyset**）：滑条拖动要跳到任意位置，
  keyset 做不到随机访问。49k 行在 `(isUserCreated, name, id)` 索引上做 OFFSET 是毫秒级；
- **排序必须补唯一键**：`isUserCreated DESC, name ASC, id ASC`（§1.12 的漏行/重复行陷阱）；
- **页面缓存**：`Map<int pageIndex, List<FoodLibraryItem>>` + LRU 上限
  （例如 60 页 = 3,000 条），滑回去时重新拉；
- **列表形态**：`SliverPrototypeExtentList`（**行高实测为已知**）的 `itemCount = 总数`
  （**不是已加载数**）——未加载的区间渲染**骨架行**（`SkeletonBox`）并登记该页待加载；
  这样滑条位置与总长度真实对应，"手滑到底"能一路加载到最后一页；
  - **不能用行高未知的 `SliverList`**：滑条拖动 = `jumpTo(比例 × maxScrollExtent)`，
    在 49,464 行的列表上是一次上百万像素的远跳；行高未知时 sliver 必须在**一帧内**
    从当前位置逐行实体化到落点（O(跳距)）⇒ 主线程卡死。真机实测是 Android
    「input dispatching timed out」ANR（2026-10-04 走查实录，见本节的实施记录）；
  - 行高已知后跳转是算术，只有落点那一屏的行会被实体化；
  - 原型卡**必须取最高的那一种卡变体**（三项宏量 + 品牌/徽标 + 「营养不完整」提示行）：
    该高度会施加给所有行，取矮的变体那张卡就会在自己的固定行高里 RenderFlex 溢出；
- **诚实**：加载中显示骨架，不显示假卡；加载失败的那一页显示一行错误 + 重试；
- 搜索框保留（搜索仍是主路径）；搜索结果的列表用**同一套分页件**
  （搜索有命中总数，同样支持滑条）。

### 8.3 滑条（用户点名的"滑条"）

- 共享件 `LfScrollbar`（或直接用 `Scrollbar(thumbVisibility: true, interactive: true)`
  包一层，统一默认值）：**常显**、可拖动、`interactive: true`；
- 食物库（49,464 条）、动作库（约 300 条）、记录列表都挂同一个件；
- 拖动滑条跨过未加载区间时，按落点页优先加载（用户看到的是骨架 → 内容，而不是空白）；
- 顶部加一行真实计数（`全部 49,464 条`），让"总量"这件事在界面上可见。

### 8.4 性能与验收

- 单页 50 条 + 骨架行，滚动不卡；`ListView` 懒构建（不许一次性 build 49k）；
- 走查判据：① 滑条常显且能拖到底；② 拖到底能看到最后一页内容（不是骨架停在那儿）；
  ③ 同一张卡在一路下滑中**不重复出现**（唯一键排序的红证断言）；
  ④ 搜索「米饭」的结果数与计数一致（"结果数"= 一路下滑能走完的**不同**卡数；
  搜索结果的顺序是相关度序，不是名称序——见 §8 实施记录二）；
- 变异红证：去掉 `id ASC` 兜底 → 分页重复行断言必须转红。

> **实施记录（2026-10-04，以实测为准）**：落地成 **`count` + `page` 一对接口**
> （替掉原来的 `search` 一次性返回）：
>
> - `FoodRepository.count()` = `COUNT(*)`；`FoodRepository.page({query, offset, limit})`
>   = `LIMIT/OFFSET`，**两档排序都以 `id ASC` 收尾**。`search(query, limit:)` 保留为
>   `page(offset: 0, limit: limit)` 的薄封装（AI 工作台 / 拍照搜索等仍读它）。
> - **`id ASC` 的红证是可观测的**（不是「反正都行」）：插入序与 id 升序不一致时，
>   SQLite 的平局顺序跟着**扫描（插入）序**走 ⇒ 去掉 `id ASC`，同一分组内的先后变化，
>   断言立刻转红（M1 实测 RED）。这条已写进 `food_library_paging_test.dart`
>   （分组内 id 必须升序 + 各页恰好划分全集）。
> - 页大小 **50**（`FoodLibraryController.pageSize`），页缓存 LRU **60 页**（3,000 条）。
> - 列表 `itemCount = 总数`；未加载区间画 `FoodCardSkeleton` 并登记该页加载；
>   **一页失败只在那一页的第一格画一行「这一段没加载出来。 / 重试」**，同页其余格
>   收起（零高）——否则 50 格会画出 50 个同名 Key 的重试行。
> - 顶部加真实计数行：默认浏览「全部 49,464 条」，搜索「搜到 N 条」。
> - **搜索路径的两处调整**（均为「加」不是「减」）：主库命中上限 30 → **1000**
>   （与目录分片单次候选上限对齐，30 正是 D5 抱怨的成因）；合并结果**按查询词缓存
>   一次**（目录 FTS 是同步全量调用，每页重跑没意义），编辑/删除后由
>   `FoodLibraryController.invalidate()` 作废——否则删掉的行还在搜索结果里。
> - 新增共享件 **`LfScrollbar`**（`lib/app/design/widgets/lf_scrollbar.dart`）：
>   `thumbVisibility: true` + `interactive: true` 收到一处；不传 controller 时自建一个
>   并经 `PrimaryScrollController` 交给子滚动视图。**挂在食物库、动作库、记录页**三处
>   （§8.3），三处各有一条断言 + 一条变异红证（M11/M12）。
> - 顺带修掉一处 W3 遗留：旧 `FoodListSkeleton` 仍是「图标 + 两行文字」的固定 112 高，
>   与四行真卡差几十像素（加载完会跳一下）⇒ 重写成与卡同构的 `FoodCardSkeleton`。
>
> **工具陷阱（本轮最贵的教训）**：本仓部分文件是 **CRLF**。变异电池按字节读源码，
> 多行锚点里的 `\n` 匹配不到 `\r\n` ⇒ 锚点命中 0 次被记为 MANGLED；而用 Python
> **文本模式**读同一个文件时会因 universal-newlines 把 `\r\n` 折成 `\n`，于是「本地
> 单独复核」显示命中 1 次——一个会骗人的假绿。电池已改成先归一化换行再比对/改写，
> 写回时还原原换行。

> **实施记录二（2026-10-04 走查抓出的真缺陷：远跳卡死）**：上面那版落地后，
> 真机（emulator-5556）把滑条从顶部拖到底，**app 直接 ANR**（logcat：
> `input dispatching timed out`，主线程在逐帧实体化中间那上万行）。这是 widget
> 测试**到不了**的缺陷——测试里的列表只有几十行。
>
> - **归因（一条可复现的判据）**：`Slider`/`Scrollbar` 拖动的本质是
>   `jumpTo(比例 × maxScrollExtent)`。行高未知的 `SliverList` 只能把
>   [当前位置, 目标] 之间的行全部 layout 出来；49,464 行 × 171dp ⇒ 一次拖动的
>   目标可达数百万像素，O(跳距) 的实体化在单帧里做不完 ⇒ 主线程卡死。
> - **修法**：改用 `SliverPrototypeExtentList.builder`，`prototypeItem` 交给
>   `SliverPrototypeExtentList` 先量一次（它**不上屏、不响应点击**），量出的主尺寸
>   成为所有行的固定行高 ⇒ 跳转变成算术，只实体化视口内那几行。
>   原型取**最高变体**（三项宏量 + 品牌 + 徽标 + 提示行），理由见 §8.2。
> - **代价（如实记）**：行高从「按内容」变成「统一 171dp」，比 W3 走查时的
>   三项宏量卡（149dp）高约 22dp；矮卡底部留白 ≈ 24dp 是**预留的提示行**。
>   同一屏从 4 张卡变成 3 张。
> - **红证**：M13「退回行高未知的 `SliverList`」→ 宿主测试**卡死超时**
>   （150s 超时被判定 RED，不是"绿"）；M14「原型不取最高变体」→ 5s 内
>   RenderFlex 溢出转红（同一种卡在 1.0× 也会溢出，因为原型矮了）。
> - **回归测试**：`test/features/nutrition/food_library_far_jump_test.dart`
>   四条——①远跳只取落点那一页（请求 offset ≤ 6 次、渲染 id 不重复且都在末页集合内）；
>   ②滑条长度按**真实总量**算（只加载 1 页时 `maxScrollExtent > 总数×100`）；
>   ③完整卡与「营养不完整」卡**同一行高**（原型取最高变体）；
>   ④2.0× 字号下行高跟着放大（说明原型高度是量出来的，不是写死的数字）。
> - **设备复核（判据 ①–④，delivered APK 上重跑过）**：
>   ① 滑条常显（浅色 (188,188,188) / 深色 (204,204,204)）且能拖到轨底
>   （thumb y 878–1021 → 1904–2046，轨道 475–2078）；
>   ② 拖到底看到的是**种子库最后三条**（龟甲万 橙醋 / 龟甲万 瓶装酸醋调味料 /
>   ﾊﾅﾏﾙｷ白色豆酱，= 排序第 49,462–49,464 行，宿主按 `name` 字节序复算）；
>   ③ 一路下滑逐屏采样，屏内无重复，且各屏行号**严格递增**：
>   2460–2463 → 14518–14521 → 26576–26579 → 38634–38637 → 49462–49464；
>   ④ 搜索「米饭」：计数行 `搜到 108 条`，逐屏走完收到 **108 个不同卡名**，
>   集合与宿主复算的 108 条**完全相同**，且**顺序逐行一致**于
>   `food_repository.page(query:)` 的相关性排序（完全匹配 → `instr` 位置 →
>   长度 → 名称 → id），**不是**名称序——搜索顺序本来就是相关度序，这一点在
>   核对时踩过一次（拿名称序比对会得到 108 条对不上）。
>
> **走查工具的两个坑（都会伪造结论）**：
>
> - **`input swipe` 的动量会跳过整屏**：甩 1500px（> 视口 1598px 的动量）时
>   每步位移超过一屏 ⇒ 中间整行被跳过，只收到 86 条，看起来像"少了 22 条"的缺陷。
>   判据应改成「**相邻两屏必须有重叠**」：把每步位移压到小于视口高度（900px /
>   800ms）后收到恰好 108 条。
> - **`uiautomator dump` 里卡名在 `content-desc` 且带 XML 转义**：`&` 写成
>   `&amp;`，比对前要还原；另外卡上是**清洗后**的名称（品牌挪走 + `normalizeFoodName`
>   首字母大写，`of Change` → `Of Change`），只复算 `splitFoodName` 会得到
>   两条对不上的假差异。

---

## 9. W5 测试 / 验证 / 交付

### 9.1 新增契约测试

| 测试 | 断言要点 |
|---|---|
| `test/app/design/lf_text_field_test.dart` | 标签在框外、常态无描边、聚焦 ring、错误双表达、语义单节点 |
| `test/app/design/app_sheet_form_submit_test.dart` | 逐表单参数化：失败**不关窗** + 文案在内 + 输入不丢 |
| `test/utils/food_name_split_test.dart` | 规则三档 + 停用词 + **49,464 条全量不丢字** |
| `test/features/nutrition/build_daily_meal_recommendation_test.dart` | 时段 / 预算 / **不重复（D8）** / 证据优先 / 稳定排序 / 空态不猜 |
| `test/features/nutrition/food_card_visual_test.dart` | 环存在且语义含「每 100 克」；徽标是自建/内置；品牌在底行；三彩点三项等宽且缺项不留白 |
| `test/features/nutrition/food_detail_visual_test.dart` | 三节（份量/修订/证据）**不存在**；图形化营养存在；**内置条目无编辑/删除**、自建条目有两个 |
| `test/features/nutrition/food_library_paging_test.dart` | 总数=真实条数；翻页无重复无漏行；滑条可拖；加载失败有重试 |
| `test/features/training/exercise_seed_test.dart` | 条数/7 肌群分布下限/器械全覆盖/无拉丁名/无重名/取值域合法 |
| `test/data/database/app_database_v19_migration_test.dart` | v18→v19 三表消失其余完好；**v1/v2→v19 不抛错**；`schemaVersion == 19` |
| `test/features/backup/export_restore_test.dart`（改） | 新增「v18 时代含三表的备份恢复到 v19 → 其余表完好、不抛错、三表不写入」 |

### 9.2 变异红证

每个新断言配一条隔离变异（备份字节 → 一处最小改写 → 只跑该文件要求转红 →
逐字节还原并断言一致）。重点：环的刻度常量、预算分配比例、去重开关、证据排序、
`splitFoodName` 三条规则各一、`floatingLabelBehavior`、`onSubmit` 失败分支的 pop、
分页排序的唯一键兜底、`ExerciseRepository` 的 limit、
**迁移里 `IF EXISTS` 与 DROP 顺序**（去掉 `IF EXISTS` ⇒ v1/v2 升级测试必须转红）。

### 9.3 既有断言处置（实测面，比原文档记的大一倍）

- **整目录删除（18 文件 / 72 用例）**：`test/features/recipes`（5/18）、
  `test/features/meal_plans`（3/9）、`test/features/recipe_planning`（10/45）
- **改写（约 20 文件）**，逐条判定「兼容 / 规格回归（写原因）/ 需改」：
  - 数据库 4：`app_database_index_test`（删 4 条索引断言）、
    `app_database_migration_test`（31 处命中：v1/v2/v3 fixture 的
    「keeps recipes」语义翻面成「drops recipes」）、
    `app_database_v6_migration_test`（9 处）、`app_database_v11_migration_test`（3 处）
  - 备份 1：`export_restore_test`（§6.9 列出 5 个具体点）
  - AI 4：`chat_edit_executor_test`（6 条命令的用例）、`chat_edit_context_loader_test`、
    `meal_pairing_task_test`、`recipe_plan_task_test`（后者整文件删）
  - app 级 7：`large_font_layout_audit_test`、`narrow_layout_audit_test`、
    `secondary_entry_reachability_test`、`secondary_page_occlusion_test`、
    `stress_ui_test`、`ui_display_pages_test`、`dashboard_page_v2_test`
  - 饮食 tab 4：`nutrition_menu_tab_integration_test`、`nutrition_page_tabs_test`、
    `nutrition_subtab_occlusion_test`、`open_nutrition_menu_intent_test`
      （3 个 app 级审计里的 `for (chip in ['计划','菜单','食谱','食物库'])` 循环列表
      改成 `['菜单','食物库']`）
- **不放宽判据**：所有"需改"逐条记录原因，不顺带放宽阈值。

### 9.4 门禁与设备

- 每包一次 `tool/verify.bat`（退出码写文件，**不走管道**）；基线
  `1782 passed / 3 skipped`（`E:/AI/Zcode/tmp/verify_wave5e.log`）。
  W4 之后总数会**下降约 72**（删除的用例），这是预期，不是回归。
- 设备（**只动 emulator-5556**）360dp 逐页截图：菜单三餐（有数据 + 三种空态）、
  地点选择、添加窗口（键盘态）、食物卡列表、食物详情（自建 / 内置两态）、
  添加食物（失败态）、今日推荐卡（有数据 + 空态）、食物库滑条拖到底、动作库分类；
  **2.0× 字号**与**暗色主题**各抽查一轮。
- **W4 专项**：装 v18 版 → 造食谱与计划数据 → 覆盖装 v19 版 → 确认
  ①启动无异常 ②两个 tab 消失 ③三张表已 DROP ④**记录/体重/饮水数据完好**
  ⑤用 v18 导出的备份恢复一次 → 其余表回来、不报错。

### 9.5 交付与文档

- 重建 arm64 包（`--obfuscate --split-debug-info=…`）+ 产物核验（正向标记、
  新中文文案按 **UTF-16LE** 查、负向对照、改动面 Key）；
- `docs/21`：新增 `§3.10 输入框类`与地点选择规格、`§3.8` 补 tone、`§5.3` 重写、
  `§4.3/4.4` 更新；`docs/07` 标注食谱/计划流程下线；
  `docs/THIRD_PARTY_LICENSES.md` 加动作种子来源；
- 证据 `docs/evidence/2026-10-04-input-menu-foodlib-redesign.md`；
- `STATUS.md` 顶部新 `Updated:` 条目；记忆 `localfit-ui-display-review` 第七轮。

### 9.6 实施记录（2026-10-04 W5 落地，以实测为准）

**与 §9 原稿不同的地方**（按 §4.7 / §6.11 / §7.6 的同一体例逐条记）：

1. **§9.1 有 4 处文件名落了地但不是原稿的名字**：
   `test/utils/food_name_split_test.dart` → `test/utils/food_name_test.dart`（与
   `normalizeFoodName` 同一件工具的两侧，拆开反而割裂）；
   `food_card_visual_test.dart` / `food_detail_visual_test.dart` /
   `exercise_seed_test.dart` → 落进既有同名文件
   `nutrition_presentation_design_test.dart`（22 例）/ `food_detail_sheet_test.dart`（15 例）/
   `exercise_seed_importer_test.dart`（8 例）。**判据一条没少，不为每个控件再造一个文件。**
2. **§9.4 的「每包一次门禁」在本包跑了 5 次**：第 1 次卡在 `dart format`
   （本包手改的两个文件只差折行）；第 2、3 次都是既有的
   `catalog_search_perf_test.dart` **50k 行墙钟基准**（两条用例各命中一次：期望 <100 ms、
   实际 103/…）——单跑该文件 3/3 全绿 ⇒ 全量并行下的负载抖动，**没有放宽那两条预算**。
   第 4 次取干净基线（`1835 / 3 / exit 0`），第 5 次取**变异电池之后**的终态（同样全绿）。
3. **走查抓出一条原稿没预见的真缺陷（本包唯一的业务代码改动）**：页面顶栏那枚
   「自建食物」落库成功后，**食物库页的计数行与已缓存的第一页不刷新**——`revision`
   这个信号只透传给了旧的 `FoodSearchTab`，**分页视图 `FoodLibraryView` 根本没接它**
   （旧注释还写着「视图层从未读过」= 一条死参数）。真机证据链：同一时刻食物库写
   `全部 49,464 条`、我的页写 `49,465 条（自建 1 条）` ⇒ 数据已落库、是视图没重来。
   修法＝视图收 `revision` 并在 `didUpdateWidget` 走 **post-frame** 重来一次
   （`_load` 第一句就 `setState`，build 阶段直接调会被框架拒）。修完在**最终冻结树**
   上复验：不离开本页 `49,464 → 49,465`、删掉后回到 `49,464`。
   **宿主测试与 1,833 条门禁都抓不到它**——门禁里的宿主不走「顶栏动作 → `revision` 抬格」这条线。
4. **§9.5 的产物核验多出一条反向发现**：正向标记里有一条
   （`food_search_tab.dart` 的「也可以点右上角「自建食物」。」）**在 release AOT 里缺席**。
   查清原因是 **TFA 把那一支摇掉了**——唯一调用点 `nutrition_page.dart:297` 传的是
   `main.dart:303` 造的非空 controller，`libraryController == null` 永不可达；
   同文件共有的 Key `food-library-search` 仍在包里 ⇒ 摇掉的是分支不是整个文件。
   **缺席是对的**，已把这条从「正向标记」改判成独立的「旧路径已摇掉」段，
   而不是删掉标记假装没这回事。
5. **暗色与 2.0× 的抽查**照 §9.4 做了一轮；2.0× 下一度以为子 tab 胶囊的字被裁，
   量过之后是**没有裁**（字形像素 `y 172–261`，控件边界 `172–262`）⇒ 按实测改正记录。
   另发现 2.0× 下 AI FAB 压住自己的底栏标签：**既有、底栏在 W1–W4 未改**，记录不修。
6. **走查副产物 F2（未修，已记入 `docs/21 §5.6`）**：我的页「食材数据库」计数是
   **进页面那一刻的快照**（`settings_page.dart:109-115` 的 `_overviewFuture` 只在
   `initState` 造一次，而 `SettingsPage` 挂在 shell 分支上切 tab 不重建）——
   实测「重启后第一次进 = 49,465（自建 1）✅、不重启再加一条后回来看仍是 49,465 ❌」。
   最小正确修法需要**应用级的「食物数据变了」通知**（跨装配层三四个文件 + 测试 + 变异），
   属于新功能而非「测试/验证/交付」，故**如实记录 + 落已知限制，不越界改写**。

**as-built 数字**：门禁 `1835 passed / 3 skipped`（基线 W4 `1833/3`，本包 +2）；
变异 **109 条**全捕获（W1 15 + W3 23 + W7 14 + W6 19 + W2 22 + W4 10 + **W5 3**）；
交付件 `E:/AI/Zcode/localfit-ai-simple-arm64-release.apk`
**13,837,354 B / sha256 `df293b50…`**（上一交付件 `211ed1e0…` 已备份，
与计划实施前那版逐字节相同）；走查件 x86_64 15,177,898 B / `7e714a38…`。
细节与截图清单见证据
`docs/evidence/2026-10-04-input-menu-foodlib-redesign.md` 的 W5 段。

---

## 10. 不变量

- 表现层 + 两个 application 层（三餐推荐引擎、动作种子 ETL）+ **一次 schema 迁移（18→19）**；
- 零真实 AI 请求（全程 fake provider）；不发布、不推送、不创建提交；
- 删除不可逆（本仓无 git）⇒ **W4 动手前整树备份 `lib/` + `test/`**；
- 明暗双主题 + 高对比 + 2.0× 三态同步成立；静态阴影 alpha ≤ 0.05；
  不新增圆角档（仍只有 16 与 full）；不引入新依赖（图表一律手绘 `CustomPainter`）；
- 随包新增数据源必须走合规三处 + 可删除工具（隐私审计测试会红）；
- **禁止脚本化字符串手术**（本项目曾因切片脚本误删 `settings_page.dart` 约 300 行）
  —— 一律逐文件精确 `Edit`，改完按完整字面量 grep 复核。

---

## 11. 待裁决（**已清空：0 条**）

| 原待裁决 | 归宿 |
|---|---|
| 1 种子条目能否编辑/删除（墓碑表 or 无 schema 变更） | **D1**：仅自建可编辑/删除，**零 schema 变更**，无墓碑表 |
| 2 买菜清单与「已启用食谱计划」的归宿 | **D3**：随两个 tab 彻底删除，不做补偿入口 |
| 3 三餐推荐是否允许跨餐重复 | **D8**：**不允许**；候选不足时该餐给空态，不拿别餐的菜填位 |
| 4 宏量可视化用 `MacroBar` 还是三彩点 | **D6**：三彩点，位置与排列按 §5.1 定死 |
| 5 今日推荐卡「未知五项」能否合并 | **D7**：合并成一句成因 + 一个行动，有数据处图形化 |
| 6 三张表是否一并删除 | **D9**：**删**（含 DROP、备份清单、清库、迁移；schema 18→19） |
| 7 动作表是否加细分部位列 | **D10**：**不加**（零 schema 变更） |

**唯一一处我自作的判断（你可以推翻）**：§6.7 的 `foodPriceFacts` /
`pantryStocks`（价格与库存两张孤儿表）我按 D9 的「相关的都删掉」一并归入删除。
要保留的话**只改 §6.7 一节**，其余方案不受影响。

---

## 12. 与既有裁决的冲突点（实施时必须在证据里记录）

1. `docs/21 §5.3` 的菜单页结构是"平铺菜品卡列表"，本轮改成"按三餐分组推荐"
   —— 用户指示优先，规范同步改写。
2. `docs/21 §4.3` 的五个 sub-tab 表要删两行 —— 规范改写，不是实现偏离。
3. `docs/21 §3.3` 只规定了 `TextField` 的底色/圆角/无边框，没规定标签位置与错误态
   —— `§3.10` 是**新增章节**，不是对既有规范的改动。
4. `docs/21 §3.2` 的宏量可视化首选是 `MacroBar` 横条，本轮食物卡**保留三彩点**（D6）
   —— 用户指示优先；`MacroBar` 仍用于别处（记录页宏量预算）。
5. `docs/THIRD_PARTY_LICENSES.md` 原先只覆盖食物数据，本轮新增动作种子来源
   —— 该文件与 `data_attribution.dart`、`tool/food_seed/README.md`、
   `privacy_statement_audit_test.dart` 必须同批改，否则门禁红。
6. **`docs/28` 自己的旧版（v3）把食谱/计划的数据层写成「不可删」，依据是旧的「只删界面」口径。**
   D9 改为**连表删除**，所以 v3 的 §1.10 与 §6.4 两处结论已在本版（v4）整体改写。
   另外**契约类文档有三份要同批改**（实测清单，漏改就是"文档说还在、代码已删"）：
   `docs/23-chat-universal-edit.md`（6 条命令的契约表）、
   `docs/03-data-and-contracts.md:54`（点名了 `recipe_items`）、
   `docs/07-localfit-2.0-development-spec.md:57/58/91/101`（事实源、Provider 合同、tab 清单、
   「创作一周食谱」场景）、**`GOAL.md:16/33/43/81/93/107`**（产品目标、AI 任务、冻结合同、
   chip 行、本地数据清单、执行路线）。
   **补查后共 17 份活文档要动，完整清单见 §6.10** —— 初版只列了 4 份，
   这是这次复核的第二个「漏网」教训：**只 grep 表名/标识符会漏掉中文描述**
   （「一周食谱」「买菜清单」「五 chip」这些词不含任何表名），
   必须按项目的活文档清单逐份过一遍。
7. `app_database.dart` 的迁移注释里有「只增不改不删：37 张既有表的结构与数据不动」
   （v17 分支的注释）。D9 是这条惯例的**第一次例外**，实施时要在新分支注释里
   显式写明"这是首次删除表，理由与不可逆后果"，不要让后来者以为漏了守卫。

---

## 13. 本次复核发现并已修正的问题（终版的产出）

| # | 问题 | 原文档（v3）状态 | 本版修正 |
|---|---|---|---|
| **H-1** | 删 `recipe_planning/` 后 `foodPriceFacts`/`pantryStocks` 变成无界面入口的孤儿（只剩 AI 4 条命令能写） | 完全未提 | 新增 §6.7，按「一并删除」处理并在 §6.7 标注**可推翻** |
| **H-2** | 备份三向行为（新备份少表 / 旧备份静默丢弃 / 新备份装旧版报错）未说明 | 只写了"保留三表"的理由 | 新增 §6.6，含用户可见说明与两条测试 |
| **H-3** | 迁移的 `IF EXISTS`、子表先行、**放迁移链最末**三条约束未写，裸 DROP 会打死 v1/v2 用户的升级 | 未提 | §6.5 列成表 + 三条硬约束 + 守卫红证测试 |
| **H-4** | 测试面记成「14 文件约 38 用例」，实测是**删 18 文件 / 72 用例 + 改约 20 文件** | 数字偏小一半 | §1.10(d) 与 §9.3 用实测数替换 |
| **H-5** | `export_restore_test` 有硬编码「44 张表」标题与三个 key 断言、`app_database_index_test` 有 4 条索引断言 —— 都会被删表打破 | 未提 | §6.9 逐点列出要改的行 |
| **H-6** | 门禁日志路径写成仓库相对 `tmp/verify_wave5e.log`，实际在 workspace `E:/AI/Zcode/tmp/` | 路径错 | §1.13 修正，并附末行证据 |
| **H-7** | `meal_pairing_workbench_task` 不是食谱计划任务（引 `recipe_record.dart` 但功能是配餐），原文档把它归入"AI 侧全撤"会误删 | 归入删除 | §6.4 明确保留 + 摘依赖 + 单独验证 |
| **H-8** | 三份**契约类文档**会与代码脱节：`docs/23`（6 条命令的契约表）、`docs/03:54`（点名 `recipe_items`）、`docs/07:57/58/91/101`（事实源 / Provider 合同 / tab 清单 / 场景） | 只写了笼统的「docs/07 标注下线」 | §6.9 与 §12.6 逐文件逐行列出要改的点 |
| **H-9** | 漏了 **`GOAL.md`**（本项目的已知坑：上一轮 UI 重建同样漏过）（6 行：产品目标「本周安排」、AI 任务「创作一周食谱」、冻结合同 `recipe-plan.v1`、饮食页「五 chip」、本地数据清单、执行路线 2.0-4） | **完全没提** —— 本项目的已知坑（上一轮 UI 重建同样漏过 GOAL/README/docs01/docs04） | §6.9 与 §12.6 补入，并写明"按活文档清单过一遍，不能只 grep 表名" |
| **H-10** | 活文档清单**系统性不全**：初版只列 4 份，实测 **17 份**要动（含 `README.md`、`docs/01`、`docs/02`、`docs/04`、`docs/08`、`docs/21`、`docs/22`、`docs/24`、`DECISIONS.md`、`THIRD_PARTY_LICENSES.md` 等） | 只列了要删功能的直接引用者 | 新增 **§6.10 完整清单（A 类必须改 / B 类顺带改 / C 类明确不改）**，并点明 `docs/08` 的披露文案**没有测试兜底** |

**另有三处自洽性问题，一并修掉**：

- §0.2 原写「七条裁决」，实际裁决已到 **10 条**（D1–D10），本版统一；
- §3.3 的迁移清单里 `planning_facts_editor_dialog`(3 处) 会在 W4 被删 ——
  v3 把它算进"迁移 30 处"造成"迁了又删"的白做，本版 §3.3 标注跳过
  （W1 实做 27 处，3 处留给 W4 连同文件一起消失）；
- W4 与 W6 都曾可能动 schema（W6 的细分部位列），本版在 §7.2 显式写明
  **D10 不加列后 schema 19 只由 W4 触发**，避免出现 19/20 两次迁移。

**复核确认无问题的点**（怕你担心，一并列出）：删除 `Recipes` **不会**动到
`Meals`/`MealItems`（用餐记录）——`tables.dart:425` 的 `Meals` 表没有任何
指向 `Recipes` 的列；`foods` 种子 49,464 条、`exercises` 60 条、`dish_library`
（食堂菜品）也都与这三个表无关。
