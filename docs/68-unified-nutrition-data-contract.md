# 统一营养数据契约（schema 31，实际实现）

> 状态：**生效中**（2026-11-09）。本文记录**代码里实际成立**的契约，不是待实施的方案。
> 方案与产品理由见 [`docs/67`](67-unified-nutrition-master-canteen-catalog-feasibility-plan-2026-11-09.md)；
> 实施证据见 [`docs/evidence/2026-11-09-unified-nutrition-master/`](evidence/2026-11-09-unified-nutrition-master/README.md)。

## 1. 结构

| 实体 | 表 | 角色 |
|---|---|---|
| 主食物 | `foods` | **唯一可写的当前营养**（每 100g）+ 身份（名称/品牌/做法/变体/归档） |
| 营养修订 | `food_nutrition_revisions` | 每次营养修改追加一条；`foods.current_revision_id` 指向生效那条 |
| 食堂供应 | `menu_items` | 一条供应 = 某窗口的一道菜；`food_id` 是**权威主引用**，自带每份克数与可信度 |
| 旧实体台账 | `legacy_entity_mappings` | 旧键 → 主食物/供应的迁移结果与待补全原因（唯一键 `legacyKind+legacyId`） |
| 记餐快照 | `meal_items` | 名称/克数/四项营养 + `nutrition_revision_id`/`supply_id`/`servings`/`serving_grams` |
| 旧菜品库 | `dish_library` | **只读兼容**：不再被任何写入入口创建或更新（自动复制链已退役） |

## 2. 不变量

1. **唯一当前营养**：一处食物只有一条生效修订；`foods` 四项是它的投影，同事务写。
   任何新建/导入都必须带生效修订（`FoodRepository.create/createMany/update` 与
   `FoodCatalogService` 都保证）。
2. **单位**：主库每 100g；供应每份克数；记餐最终克数。
   `摄入营养 = 每100g × 实际克数 ÷ 100`；`实际克数 = 份数 × 该供应每份克数`。
3. **未知不填零**：四项不齐的主食物不参与计算、不显示 0 千卡；份量未知的供应
   不派生"一份多少千卡"。
4. **份量可信度**：`menu_items.serving_grams_status ∈ {known, estimated, unknown}` +
   `serving_grams_source ∈ {weighed, user_input, label, ai_estimate, legacy_unverified, legacy_unknown}`。
   只有 `known` 且来源属于 `{weighed,user_input,label}` 才进入自动推荐。
5. **历史不被重算**：修改主修订或供应份量不改变任何已有 `meal_items` 快照。
6. **删除纪律**：删供应不删主食物；主食物仍被供应引用时只能归档（`foods.archived_at`）。
7. **名字不裁定身份**：同名可以并存；`food.create` 只有"同名 + 同品牌 + 四项完全相同"
   才视为重复提交。

## 3. 写入路径（唯一入口）

| 意图 | 入口 | 落点 |
|---|---|---|
| 存库 | `FoodCatalogService.createMasterFood` / `createMasterFoodFromServing` | `foods` + 修订 + 指针 |
| 挂窗 | `FoodCatalogService.createSupply` / `CanteenRepository.createDish` / `linkSupplyToFood` | `menu_items.food_id` + 份量与来源 |
| 记餐 | `NutritionMath` → `MealRepository.create/update` 或 `FoodCatalogService.recordMeal` | `meals` + `meal_items` 快照 |
| 食堂批准营养 | `CanteenRepository.recordNutrition` + `MasterNutritionSink` | 证据行（分析记录）+ 主食物新修订 |

AI 命令（`food.create` / `dish.upsert` / `canteen.dish.create` / `canteen.dish.nutrition`）
全部走同一批服务；`dish.upsert` 只做旧信封兼容换算。

## 4. AI 协议增量（向后兼容）

新增**可选**参数（缺省 = 旧协议 `v1`，未知字段仍然整条拒绝）：

| 命令 | 新参数 | 语义 |
|---|---|---|
| `canteen.dish.create` | `foodId` / `servingGrams` / `servingGramsSource` / `contract` | 链接主食物；填这个窗口的每份克数与来源 |
| `canteen.dish.nutrition` | `contract` | 版本标记；数值仍写每 100g 证据 + 主修订 |
| `dish.upsert` | `contract` | `v1` = 旧"每份"语义；**必须有 `servingGrams`** 才能换算 |

`contract=v2` 时 `canteen.dish.create` 必须给 `foodId`（或 `nutritionFrom=food`）。

## 5. 备份与恢复

- 新表 `legacy_entity_mappings` 进 `LocalFitBackupTables`（父表在后、可选）。
- `food_nutrition_revisions` 的 schema 31 非空列有恢复默认值：
  `nutritionBasis=per100g`、`basisAssumed=false`、`origin=import`、`isEstimated=false`。
- `menu_items` 的恢复默认值：`servingGramsStatus=unknown`、`servingGramsSource=legacy_unknown`
  （**历史数字不会因为回填默认值变成可信份量**）。
- 恢复在**同一事务**里跑 `LegacyNutritionConverter`：旧包被归一，新包按幂等空跑。
- `.lfb` 仍不包含图片字节；界面与文档不得宣称"照片完整恢复"。

## 6. 界面口径

- 供应必须显示四种状态之一：待分析 / 份量未知 / 份量为估计 / 份量已知。
- "每 100g"与"每份"必须分开标注；份量未知时不给"一份多少千卡"。
- 记餐条目：按供应记时默认 1 份（克数 = 该供应每份克数）；手改克数后份数置空。
- 旧菜品（`dish_library`）份量不可信时**拒绝添加**并提示补全，不再按 100g 兜底。
