# 训练动作种子数据生成（exercises.v3.json）

`assets/seed/exercises.v3.json` 是本目录脚本从公开数据集清洗生成的随包动作库，
**312 条中文动作名**，带肌群（7 档）、器械（6 档）、难度（3 档）与常用度（0–100）。
App 的动作库检索（`ExerciseRepository.search`）直接查这张表。

## 数据来源

| 文件 | 来源 | 许可/说明 |
| --- | --- | --- |
| `raw/free_exercise_db.json` | [yuhonas/free-exercise-db](https://github.com/yuhonas/free-exercise-db)（876 条） | **Unlicense / public domain**，`raw/LICENSE.md` 是上游原文；可自由再分发 |
| `name_zh.tsv` | 本仓库人工翻译（~205 行） | 上游**只有英文名**（`Incline_Dumbbell_Press`、`Dips_-_Chest_Version`），全部中文名由本仓库生成或手工定名 |
| `id_overrides.tsv` | 本仓库台账（51 行） | 上游 id → v2 本地 id 的映射，见「续号」小节 |
| `manual_rows.tsv` | 本仓库台账（7 行） | 上游没有对应条目、沿用 v2 事实手写保留的动作 |

上游只有英文名与事实字段（肌群/器械/难度/类别），**没有任何中文内容**；中文名全部
来自本仓库的合成词表 + `name_zh.tsv` 覆盖，所以这个种子的「中文」部分是本仓库原创。

**历史来源**：v1/v2 的 60 条动作（`source='seed-v1'/'seed-v2'`）是早期手写的最小
动作库，v3 已按 id 原地继承其中 58 条（另 2 条是重名重复行，见下）。

## 生成

```bash
cd tool/exercise_seed
C:/ProgramData/miniconda3/python.exe build_exercises.py --report   # 只报告分布，不写文件
C:/ProgramData/miniconda3/python.exe build_exercises.py --dump     # 再打印逐条清单（人工复核译名）
C:/ProgramData/miniconda3/python.exe build_exercises.py            # 写 assets/seed/exercises.v3.json
C:/ProgramData/miniconda3/python.exe build_exercises.py --check    # 重建结果与随包资产逐字节比对（手改资产会被抓住）
```

测试：

```bash
C:/ProgramData/miniconda3/python.exe test_build_exercises.py    # 规则 + 真实产物对账
C:/ProgramData/miniconda3/python.exe test_strip_exercise.py     # 剥离来源脚本
```

## 映射与筛选

- 上游 876 条 → 候选池 **748** 条：排除 `category='stretching'`（123 条，拉伸不是
  「训练动作」）与主肌群是脖子（`neck`）的 5 条（现有 7 档肌群没有颈部）。
- `primaryMuscles[0]` → 7 档：`traps → shoulders`（与 v2 既有「耸肩 = 肩」一致）、
  `lats/middle back/lower back → back`、`quadriceps/hamstrings/glutes/calves/abductors/adductors → legs`、
  `biceps/triceps/forearms → arms`、`abdominals → core`；`olympic weightlifting/strongman/cardio`
  三类整族归 `fullBody`。
- `equipment` → 6 档：`kettlebells/bands/medicine ball/exercise ball/foam roll → other`、
  上游 `null`/`body only → bodyweight`，其余同名直映。
- `level` → 3 档：`beginner/intermediate` 直映，**`expert → advanced`**（App 的枚举只有
  beginner/intermediate/advanced）。
- **筛选**（`select()`）三段：① v2 续号行**无条件全部入选**（换源不能让用户库里
  已存在的动作消失）；② 按 7 肌群目标条数取常用度最高的（`GROUP_TARGETS`：chest 40 /
  back 45 / legs 55 / shoulders 40 / arms 45 / core 45 / fullBody 30）；③ 补两轮下限——
  每档器械 ≥ 20 条（`EQUIPMENT_FLOOR`，machine 只有 20 条可挑，正好补满）、每肌群 ≥ 3 条
  高级动作（`ADVANCED_FLOOR`，被换掉的都是续号行以外的普通行）。合计 **312 条**
  （上游派生 305 + 手写保留 7）。

实际结果：肌群 chest 42 / back 46 / legs 62 / shoulders 41 / arms 45 / core 45 / fullBody 31；
器械 bodyweight 50 / barbell 124 / dumbbell 62 / machine 20 / cable 34 / other 22；
难度 beginner 171 / intermediate 122 / advanced 19；常用度 35–89。

### 常用度（popularity）

**确定性常量表，不是随机数**（同输入同输出，`test_build_exercises.py` 有断言）：基准 45
，`mechanic=compound` +18 / `isolation` −6，按肌群/器械/难度各加减一档
（`level` beginner +6 / intermediate +2 / expert −8），`secondaryMuscles` 非空 +6，
最后夹到 5–100。它只是「热门程度」的排序提示，不是真实统计值，App 里当排序权重用。

### 中文名（两段式，缺译即失败）

1. **合成**：`EQUIP_ZH` + `MOD_ZH` + `HEAD_ZH` 三张词表按最长匹配拼出「姿势修饰 +
   器械前缀 + 动作名词 + 后缀」。名字里已经写过器械的（`Smith_Machine_Squat`）不再
   加枚举前缀。
2. **覆盖**：`name_zh.tsv`（`归一化英文名 \t 中文`）兜不规则整名——上游 `Dips_-_Chest_Version`
   这类没法靠词法拼的、以及 v2 既有动作的定名全在这里。

合成遇到没登记的词汇会**报错退出并一次列出全部失败项**（`left:…` / `head:…`），
不许用「猜一个差不多的词」蒙过去；译名里出现拉丁字母也直接失败（`BuildError`）。
所以「无拉丁字母名」是构建期保证，不是事后清洗。

### 续号（换源不丢老动作）

`ExerciseSeedImporter` 用 `insertOnConflictUpdate` 按 **id** 覆盖写，所以只要 id 一样，
旧行就是被**刷新**（改名/补事实）而不是插成第二条同名动作。

- `id_overrides.tsv`：上游 id → v2 本地 id，51 条。v2 的 60 条里有 58 条在上游有对应
  动作，全部在这里登记。
- `manual_rows.tsv`：上游没有对应条目的 7 条（宽握引体向上、箭步蹲、侧箭步蹲、
  保加利亚分腿蹲、小腿提踵、哑铃前平举、波比跳），事实沿用 v2、id 沿用 v2。每条都
  写明了「上游为什么没有」，不是懒得找。
- v2 里的 **2 条重名重复行**（`ex-triceps-pushdown-rope` 与 `ex-cable-triceps-pushdown`
  都叫「绳索下压」；`ex-overhead-triceps-ext` 与 `ex-dumbbell-overhead-triceps-extension`
  都叫「哑铃颈后臂屈伸」）只延续一个，另一个由导入器做**一次性清理**，且**只删没有被
  训练计划或训练组引用的行**（与食物库 `_purgeLegacySeeds` 同一条纪律）。
- v2 里 3 条**已登记错译**（`坐姿好早上` / `后 deltoid 飞鸟` / `俄罗斯转弯`）在 v3 里用
  **同一个 id 写正确名字**，导入即覆盖修正，**不删**（删了还得按同 id 插回来，白白丢引用）。
- v2 → v3 共 20 条中文名发生变化，逐条登记在 `test_build_exercises.py` 的
  `V2_RENAME_ALLOWLIST` 里，名单两端各钉一次：多改一条或名单过期都红。

## 数据规模

- 上游 876 条 → 候选池 748 条 → 选中 **312 条**（`free-exercise-db` 305 + `manual` 7）。
- 每条 7 个键：`id / name / muscle_group / equipment / difficulty / popularity / origin`。
  与 v2 相比只多一个 `origin`（导入器不读它，多一个键无害）。
- id 一律 `ex-` 前缀、唯一；名称无重名、无拉丁字母；难度三档齐全；常用度 ∈ [0,100]。

## 来源标记与「删除/替换来源」

规范 §5.3 要求的脚本已就位：`strip_exercise_source.py`（测试 `test_strip_exercise.py`）。

```bash
C:/ProgramData/miniconda3/python.exe strip_exercise_source.py --list
C:/ProgramData/miniconda3/python.exe strip_exercise_source.py --strip free-exercise-db --out /tmp/exercises.stripped.json
C:/ProgramData/miniconda3/python.exe strip_exercise_source.py --strip free-exercise-db --in-place   # 先写 .bak
```

与食物种子（按 id 前缀分来源）不同，动作种子**按每条的 `origin` 字段**分来源：
id 必须沿用 v2 的本地 id（于是不能编码来源），`origin` 是逐条的显式声明。
`DECLARED_ORIGINS` 只有两个值：

| origin | 含义 |
| --- | --- |
| `free-exercise-db` | 从 yuhonas/free-exercise-db（Unlicense）派生的 305 条 |
| `manual` | 上游没有对应条目、沿用 v2 事实手写保留的 7 条（本仓库原创） |

脚本的失败要显眼：来源打错字（不在清单里）报错退出 1；已声明来源但文件里没有 =
「已经删过了」，幂等退出 0 且不写文件；剥离后一条不剩报错且不落盘；`--in-place` 先
写 `<path>.bak` 且拒绝覆盖已存在的备份（仓库无 Git，冲掉旧备份就没有退路了）。
它只改 `exercises` 与 `version`，其余顶层键和每条保留行的键集合一字不差。

**当前可分发状态**：两个来源都可自由再分发（上游 Unlicense + 本仓库原创），所以这个
种子**不是**对外分发的阻塞项——如果将来换上有许可问题的来源，跑一次 `--strip` 就能停发。

## 相关文件（改这个种子时要同步的地方）

- `assets/seed/exercises.v3.json` — 随包资产（`pubspec.yaml` 的 `assets:` 已登记；
  v2 仍保留是为了导入测试与升级路径）。
- `lib/features/training/data/exercise_seed_importer.dart` — 导入 + 一次性清理。
- `lib/features/training/data/exercise_repository.dart` — 检索（`limit` 默认 500）。
- `lib/features/training/domain/data_attribution.dart` — 数据来源与许可证（App「设置 →
  数据来源与许可证」里渲染）。
- `docs/THIRD_PARTY_LICENSES.md` — 随包动作种子小节的许可说明。

改动规则后必须重新生成资产并跑 `flutter test`：`test/features/training/` 下的种子
导入测试会校验条数、7 肌群下限、器械覆盖、难度/常用度取值范围与 v2 续号不丢。
