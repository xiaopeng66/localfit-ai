# 食物库全量人工审核台（docs/29 §P8b-1）

用户 2026-10-05 裁定 **49,464 条逐条有人工裁决**（D6），本目录是那件事的**工具与
账本**（P8b-1）。它**不进 App 包**——审核台是开发工具，不是产品功能，所以只依赖
Python 标准库，零新依赖。

> **规模先说清**：按 3–5 s/条，逐条走完约 **40–70 小时**键盘时间。本目录保证的
> 是「工具就绪、进度可续、账本可真、覆盖率可见」，不是「几天就能做完」。

## 三份事实

| 文件 | 是什么 | 谁产出 |
| --- | --- | --- |
| `assets/seed/foods.v4.json` | 审核对象（49,464 条） | `build_foodcalu.py` |
| `reports/display_preview.jsonl` | **上屏预览**：每条在卡上长什么样 | **App 自己的 Dart 函数**，见下 |
| `reports/review_ledger.jsonl` | **账本**：一行一条裁决，**唯一权威证据** | 审核台（追加式） |

### 上屏预览必须由 App 的同一批函数产出

审核台的全部意义是「人看到的就是上屏的」。所以预览**不许**用 JS 或 Python 重写
一遍拆分规则（两份实现必然漂移，漂移之后人审的就是一张并不存在的卡片）：

```bash
# 在仓库根跑（改了种子、或改了显示口径之后都要重跑）
dart run tool/food_seed/review/export_display_preview.dart

# 只校验新鲜度（对不上就 exit 1）
dart run tool/food_seed/review/export_display_preview.dart --check
```

它调用的是屏上那三个函数本身——`splitFoodName` / `normalizeFoodName` /
`foodDisplayStrings`（最后一个是 D14 的显示口径单源，`lib/utils/food_display.dart`）。
预览文件头记了产出它的**种子 sha256** 与**函数名**，审核台启动时校验：种子换了而
预览没重跑，审核台**拒绝启动**（不会拿旧预览骗人）。

> `lib/utils/food_display.dart` **不许 import Flutter**：`dart run` 装不下
> Flutter 的渲染库，一旦引入，导出脚本先坏、审核台就会退回「别处再算一遍」。
> `test/utils/food_display_test.dart` 有一条断言钉住这件事。

## 用法

```bash
# 看进度（五档）
python tool/food_seed/review/review_server.py --stats

# 只审某一类（工作面，见下）
python tool/food_seed/review/review_server.py --stats --only near_duplicate

# 开审核台（默认 127.0.0.1:8787，只绑本机）
python tool/food_seed/review/review_server.py --serve
python tool/food_seed/review/review_server.py --serve --only brand_unresolved --port 8790
python tool/food_seed/review/review_server.py --serve --no-open     # 不开浏览器

# 只校验预览与种子同源
python tool/food_seed/review/review_server.py --check-preview
```

Windows 上 `python` 是 Miniconda，也可以写全 `C:/ProgramData/miniconda3/python.exe`。

## 键盘八动作

| 键 | 动作 | 说明 |
| --- | --- | --- |
| `1` | 通过 | 名称/品牌/非食物/重复四项都核过 |
| `2` | 改名称 | 填右侧「改名称」框 → 按 `2`（或在框里按 `Enter`） |
| `3` | 定品牌 | 填「定品牌」框 → 按 `3`（或在框里按 `Enter`） |
| `4` | 并入品牌词表 | 把**原始名称的首 token** 记为品牌（D13 的独立词表） |
| `5` | 改营养 | 填四个数字 + **来源**（留空按「人工估值」记；不许无来源地改数字） |
| `6` | 删除 | 非食物、真重复、无法修正的条目 |
| `7` | 存疑 | 拿不准就标存疑，报告里单独列 |
| `8` | 撤回 | 撤**账本里最近一条生效裁决**（不是「当前这一行」，见下） |
| `b` | 整组族批确认 | 同首词的整组一次确认，记 `review_mode=batch` |
| `j` / `k` | 上下移动当前行 | 高亮跟随，动作作用于高亮那一行 |

**在编辑框里**：按键就是打字（名称里有 `7-ELEVEN`、`450g` 这类数字，在框里劫持
数字键就没法输数据），改完按 `Enter` 提交该项、按 `Esc` 退出框。

**撤回为什么撤「最近一条」**：裁决一落账本就退出待审队列、也从屏上消失，按键那
一刻「当前行」早已是**下一行**。实测过这个缺陷（先按 `6` 删除、再按 `8` 撤回，
撤回落在下一行的空栈上、什么也没发生，删掉的条目再也回不来）。49,464 条靠键盘走，
按错一格是必然事件，所以 `8` 撤的是账本里最近一条生效裁决，账本里记 `before.
reverted_id` / `reverted_decision` 说明撤的是谁。

## 可疑队列：**只用于排序与预填，不是结论**

机器判不出「明治 是品牌、迷你 不是」——那正是全量人工审核的意义所在。队列把下面
这些标记靠前的排到前面，**标记本身一个字都不会进账本**：

| 标记 | 实测条数（v4） |
| --- | --- |
| `near_duplicate` 近似重名（去分隔符后同名） | 42（20 组） |
| `brand_unresolved` 首 token 像品牌但自动规则没拆 | 34 |
| `duplicate_token` 名称里有重复的词 | 3 |
| `slash_or_number_run` 含 `/` 或连续数字 | 1,243 |
| `kcal_macro_mismatch` 4/4/9 不自洽 >±25% | 1,244 |
| `nutrient_zero_or_missing` 四项有空或为 0 | 7,909 |
| `head_ascii` 首 token 含 ASCII | 7,127 |
| `han_head_frequent` 纯汉字高频首词（可能是品牌） | **23,301** |

最后一行就是 `docs/29` D6 点名的**只有人工能关的缺口**：自动词表按设计排除纯汉字
首词（频率分不清品牌与描述词——`明治` 是品牌、`迷你` 不是），1,455 个纯汉字高频
首词覆盖 23,301 条，只能靠人一眼判。人工判下来的结论走 `4`（并入词表），落进账本，
P8b-2 生成 `lib/utils/food_brands_reviewed.g.dart`（D13：**独立**存放，自动表的
「可从种子重算」性质不能被人工 token 破坏）。

## 账本

`reports/review_ledger.jsonl`，**追加式**、一行一条，UTF-8 不转义：

```json
{"id":"seed-fc-469","decision":"rename","before":{…},"after":{…},
 "source":"人工核对包装","review_mode":"item","ts":"2026-10-06T16:40:33Z"}
```

- `decision` ∈ 上面八个动作；`review_mode` ∈ `item` | `batch`；
- `before`/`after` 是该条的字段快照（**「通过」也记一份**：日后种子改了，快照就是
  能对账的凭据）；
- **只增不改**：任何「撤销」都是**再加一行** `revert`，历史不会被覆盖；
- **整批校验后才写**：一行不合法（未知动作、改营养没来源、批次里混一条坏 id、
  族批不是整组…）⇒ 整批拒绝、**一个字节都不写**。

### `review_mode` 由服务端判定，不信前端

- 单条裁决一律 `item`；
- `batch` 只在「提交的 id **恰好等于**同首词全部待审成员」时给，其余一律**拒绝**
  （不是降级记成 `item`——把族批写成逐条核验正是 `docs/29` 点名的混称）。

### 断点续审

`reports/review_cursor.json` 是**派生物**（从账本重算），只为「打开就能接着审」。
删掉它不丢进度；任何时候都以账本为准（载入时发现两者不一致就按账本重写）。

## 五档进度

```
$ python tool/food_seed/review/review_server.py --stats
已裁决 0 / 49464（0.0%） = 逐条核验 0 + 族批确认 0
待审 49464｜其中存疑 0
```

**「进度」是唯一的完成度声明**，且 `已裁决 = 逐条核验 + 族批确认`（互斥且穷尽）；
`存疑` 是已裁决的子集，单独列出但不额外计入分母。**族批确认过的不许写成逐条核验**
——这两个数就是报告里必须分列的那两项。

## 审核边界（写死，不许含糊）

- **必审（全量）**：名称、品牌拆分与命名、明显非食物条目、重复条目。
- **可疑才改**：四项营养——**改数值必须填 `source` 或标「人工估值」**，账本留痕。
- **明确不审**（诚实边界）：营养学的绝对正确（需实验室数据）、过敏原/膳食标签
  （上游字段，与名称无关）——不假装审过。

## 测试

```bash
cd tool/food_seed/review
python test_review.py          # 核心规则 + 真实产物对账（含 Python 独立重算 vs Dart 预览）
python test_review_server.py   # 端到端 HTTP（临时仓库里打真请求、真写账本）
python test_review_ui.py       # 审核台 UI 的静态契约（提示与行为一致、动作目标与高亮同源）
```

外加 Dart 侧 `flutter test test/utils/food_display_test.dart`（显示口径 + 同源约束）。

`test_review.py` 里有一条关键对账：用**独立写出**的 Python 规则重算一遍拆分，与
Dart 导出的预览逐条比较（前 4,000 条）——它证明的正是「两份实现没漂」。

## P8b-2 会用到什么（下一步，不在本目录）

`tool/food_seed/apply_review.py`：账本 → `assets/seed/foods.v5.json` +
`lib/utils/food_brands_reviewed.g.dart` + `reports/review_report.md`，
带 `--require-coverage 100`（**未审完不产出 v5**，App 继续用 v4，不出现「审了一半
的种子」这种中间态），且幂等（同一账本两次生成逐字节相同）。
