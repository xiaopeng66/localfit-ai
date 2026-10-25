# LocalFit AI 第三方数据来源与许可证

> 2.0-7d 建立，2026-10-02 随「食物库整体替换」更新，2026-10-04 随「动作库换源
> 到 yuhonas/free-exercise-db」更新 §3。这份清单是**随包数据与按需下载数据**的
> 来源归属和许可依据；界面上的「我的 → 数据来源与许可证」直接读
> `lib/features/nutrition/domain/data_attribution.dart`（食物）与
> `lib/features/training/domain/data_attribution.dart`（动作），公共值类型在
> `lib/core/attribution.dart`，`test/privacy/privacy_statement_audit_test.dart`
> 会把两份清单、本文件引用的生成脚本和各自的 README 对齐——改一处忘另一处会红。
>
> 开源组件（Dart/Flutter 依赖）不在这里手抄：应用内「开源组件许可」走 Flutter
> 官方 `LicenseRegistry` 许可页，自动汇总各依赖包 LICENSE。

## 1. 随包食物种子（`assets/seed/foods.v4.json`，49,464 条）

| 来源 | 上游 | 许可证 / 上游声明 | 规模 | 风险 |
| --- | --- | --- | --- | --- |
| FoodCalu 中文食物库 | `gaosheng293/FoodCalu` 的 `app/src/main/assets/food_database.db` | 上游**未声明许可证**（仓库无 LICENSE 文件） | 49,464 条（源 49,520 − 归一化去重 54 − 不可能值 2） | ⚠️ **仅对外分发时阻塞**：docs/07 §5.3 明文「不清楚是否允许再分发的源不进入发布包」。当前定位是**个人自用不分发**（ADR-020 补记 + ADR-025），故保留随包；一旦要分发必须先处理 §4.1，删除工具已就位（`tool/food_seed/strip_seed_source.py`） |

生成脚本与清洗规则见 `tool/food_seed/README.md`；生成命令：

```bash
C:/ProgramData/miniconda3/python.exe tool/food_seed/build_foodcalu.py
```

上游 49,520 条里 **430 条名称不含汉字**（英文/日文/品牌名），由本仓库逐条人工
翻译，词表在 `tool/food_seed/raw/foodcalu/name_zh.tsv`；构建脚本对「缺译名」
直接报错退出，保证不会有拉丁字母名漏进库。

### 随包条目的许可证字段

`foods.licenseStatus` 对随包种子一律是 `unknown`（`lib/features/nutrition/data/food_seed_importer.dart`
导入时不写该列，`food_repository.dart` 对自建行同样写 `unknown`）：随包数据没有逐条
许可证记录，App **不假装**每一条都有独立许可证；来源归属由上面的清单和 App 内的
「数据来源与许可证」承担。

### 已下线的历史来源（2026-10-02）

| 来源 | 上游 | 曾用许可证 | 规模 | 处理 |
| --- | --- | --- | --- | --- |
| 中国食物成分表（标准版·第 6 版）数字化表格 | `Sanotsu/china-food-composition-data` | 上游声明「仅供学习研究」（无 LICENSE） | 1,634 条（`seed-cfct-`） | 随 v4 一并从仓库删除 |
| foodwake（USDA 数据中译） | `LuckyHookin/foodwake` | Apache-2.0 | 830 条（`seed-fw-`） | 随 v4 一并从仓库删除 |

`assets/seed/foods.v1.json` / `v2.json` / `v3.json`、两个生成脚本的原始输入
（`raw/cfct.csv`、`raw/foodwake.json`）与 `generate_seed.py` 都已删除，备份在
`E:/AI/Zcode/backups/localfit-old-food-library-2026-10-02/`（含 `_SHA256SUMS.txt`）。
老用户的库里残留的 `seed-v1/v2/v3` 行由 `FoodSeedImporter._purgeLegacySeeds`
在下次启动时清理——**只删没有被 `meal_items` / `menu_item_food_matches` 引用的行**。

> **2026-10-21（ADR-037）**：随包新增 `assets/seed/food_library_normalization.v1.csv`，
> 它是 `user_foods_8col.v1.csv` 的**派生资产**（旧(名称,品牌) → 新名称/品牌/分类/别名），
> 由 `tool/food_catalog/normalize_food_library.py` 生成——**不引入任何新上游**，
> 来源与许可与 8 列用户食物库同一份（见本节）。

## 1b. 随包「用户食物库（8 列版）」（`assets/seed/user_foods_8col.v1.csv`，23,919 条）

2026-10-20 用户提供 xlsx 并明确要求内置。转换：`tool/food_catalog/convert_food_xlsx.py`；
首启导入：`BundledUserFoodImporter`（`app_settings.bundled_user_food_imported` 幂等标记）。
行形态与手动导入一致（`isUserCreated=true`、`licenseStatus='unknown'`）。

| 代码 | 来源 | 上游 | 许可证 / 上游声明 | 规模（清洗前保留） | 风险 |
| --- | --- | --- | --- | --- | --- |
| S1 | 中国食物成分表 6 版公开转录 | `github.com/Sanotsu/china-food-composition-data` | 上游**未声明许可证** | 1,549 | ⚠️ 仅对外分发时阻塞 |
| S2 | 薄荷（Boohee）SQL 历史存档 | `github.com/xiaok0928/spider-boohee-data` | 上游**未声明许可证** | 41,991 | ⚠️ 同上（爬虫抓取的内容，权利归属未明） |
| S3/S3b | 薄荷网页 JSON 存档 | `github.com/seawaylee/boohee_spider`、`github.com/eninem123/bohespider` | 上游**未声明许可证** | 2,476 + 130 | ⚠️ 同上 |
| S5 | 台湾食药署开放数据 | `data.fda.gov.tw` | 政府开放资料（**需署名**） | 2,094 | 署名已在本清单与 App 内提供 |

**结论与定位**：混合来源的**逐条再分发许可没有审计**，与已退役的 v4/v5
（FoodCalu，上游未声明许可证）属于同一类情形——当前定位是**个人自用不分发**
（ADR-020 补记 + ADR-025）。**一旦要对外分发**，必须先按本节逐源取得许可或
删除对应来源的行（删除工具：`tool/food_seed/strip_seed_source.py` 的模式可复用）。

成品 23,919 条 = 上述四源清洗保留（48,240）→ 跨源去重 / 名称归一 / 值域复核后
的定稿；逐源贡献比例不再精确可分（合并时已去重）。

## 2. 按需导入的食物目录（2026-10-02 起不随包任何分片）

| 来源 | 许可证（manifest `sources[].license`） | 归属文本（`attribution`） | 规模 |
| --- | --- | --- | --- |
| Open Food Facts 产品库 | `odbl-1.0` | `(c) Open Food Facts contributors (ODbL)` | 目标 ≥50k canonical |

- ETL：`tool/food_catalog/etl_pipeline.py`（`SOURCE` 常量声明的 license/attribution 会写进分片 manifest）。
- 应用侧只接受 `allowedCatalogLicenses` 白名单内的许可证才能导入（`lib/features/nutrition/data/catalog_manifest.dart`）。
  白名单当前是：`odbl-1.0`、`cc0-1.0`、`cc-by-4.0`、`cc-by-sa-3.0`、`cc-by-sa-4.0`、`public-domain`。
- **中文基础食物改由随包种子提供后，目录不再随包**：`assets/catalog/` 下的
  manifest 与 5 个分片已删除（备份同上），pubspec 也不再声明。目录机制保留给
  用户自备/按需导入的许可数据：把分片放进支持目录后「重新扫描本地分片」即可。
- 导入后每行 `foods.licenseStatus` 记录 manifest 里的原始许可证状态，不丢来源。
- **注意**：FoodCalu 数据**不能**走这条通道——目录清单要求来源有明确许可证
  （白名单是冻结的），无许可来源只能随包出现在种子层。

## 3. 训练动作种子（`assets/seed/exercises.v3.json`，312 条）

| 来源 | 上游 | 许可证 / 上游声明 | 规模 | 风险 |
| --- | --- | --- | --- | --- |
| free-exercise-db 动作库 | `yuhonas/free-exercise-db` 的 `exercises.json` | **Unlicense / public domain**（上游 `raw/LICENSE.md` 原文） | 312 条（源 876 − 拉伸 123 − 颈部主肌群 5 = 候选 748 → 按 7 肌群目标取 305，另 7 条本仓库手写） | ✅ 可自由再分发，**不是**分发阻塞项 |

生成脚本与映射规则见 `tool/exercise_seed/README.md`；生成命令：

```bash
C:/ProgramData/miniconda3/python.exe tool/exercise_seed/build_exercises.py
```

- 上游**只有英文名与事实字段**（肌群/器械/难度/类别），**不含任何中文内容**；
  312 条的中文名全部由本仓库生成（合成词表 + `tool/exercise_seed/name_zh.tsv`
  人工定名），所以中文部分是本仓库原创。构建脚本对「缺译名」和「译名含拉丁
  字母」都直接报错退出。
- 其中 **7 条上游没有对应条目**（宽握引体向上、箭步蹲、侧箭步蹲、保加利亚分腿蹲、
  小腿提踵、哑铃前平举、波比跳），沿用 v1/v2 种子的既有事实手写保留，是**本仓库
  原创**数据；来历逐条写在 `tool/exercise_seed/manual_rows.tsv`。
- 每条的 `origin` 字段（`free-exercise-db` / `manual`）就是来源标记，
  `tool/exercise_seed/strip_exercise_source.py`（测试 `test_strip_exercise.py`）
  按它剥离来源，与食物侧的 `strip_seed_source.py` 同一条纪律：

  ```bash
  C:/ProgramData/miniconda3/python.exe tool/exercise_seed/strip_exercise_source.py --list
  C:/ProgramData/miniconda3/python.exe tool/exercise_seed/strip_exercise_source.py \
      --strip free-exercise-db --in-place   # 先写 .bak，拒绝覆盖已有备份
  ```

### 历史版本（v1 / v2，各 60 条）

`assets/seed/exercises.v1.json` / `v2.json` 是本仓库最初手写的最小动作库（60 条），
无第三方来源。v3 按 **id 原地继承**其中 58 条（见
`tool/exercise_seed/id_overrides.tsv`），另外 2 条是 v2 里的重名重复行，不再收录；
v1/v2 两个文件仍随包保留，只用于向后兼容的导入测试与升级路径。

## 6. 端上嵌入模型（`assets/models/`，2026-10-19 起随包）

| 文件 | 来源 | 许可证 | 体积 |
|---|---|---|---|
| `model_int8.onnx` | BAAI **bge-small-zh-v1.5**（中文检索小模型，int8 动态量化导出） | **MIT** | 23.9 MB |
| `vocab.txt` | 同模型的 WordPiece 词表（21128 行） | MIT（随模型） | 0.13 MB |

* 用途：端上语义检索的查询/条目嵌入（`docs/39` §4.1）。**推理完全在本机**，
  不新增数据接收方（发送给 AI 供应商的仍只有文本，见 `docs/08`）。
* 导出与量化：int8 动态量化（`onnxruntime.quantization`），512 维、mean pooling
  + L2 归一；入库校验记录在 `docs/evidence/2026-10-18-p0-eval.md`（P0 矩阵与
  §7 稳态复测：maxLen 32 + 前缀 B 的 p95 = 13.3 ms、recall@10 相对 +92.6%）。
* 版本管理：文件名不带版本号，但 `embedding_index.modelId` 记录
  `bge-small-zh-v1.5-int8-v1`——**换模型必须换 modelId 并全量重建索引**
  （`docs/39` §16.2 的「向量空间不可混用」）。
* 替换规则：更新模型 = 更新本表 + `docs/evidence` 的评测数字 + `modelId`；
  体积代价记在 `docs/evidence/2026-10-18-p1-p2-p3-delivery.md` 的 APK 段。

## 4. 发布前必须处理

> **当前项目定位：个人自用，不商业化、不上架分发**（用户 2026-09-16 裁定，见 ADR-020 补记）。
> 因此下面第 1 条**对自用构建不是阻塞项**——随包 FoodCalu 条目保留、不改数据。但**一旦要
> 对外分发（商店/公开下载/给他人用），第 1 条立刻变回阻塞项**，必须先处理再发布。

1. **FoodCalu 来源条目：仅对外分发时才阻塞**。随包 `assets/seed/foods.v4.json` 的
   49,464 条全部来自 FoodCalu，而**上游没有任何再分发授权**（仓库无 LICENSE 文件）。
   docs/07 §5.3 明文「不清楚是否允许再分发的源**不进入发布包**」，所以**对外分发时**
   它是在包违规；自用不分发不触发该门槛。两条出路（ADR-025）：
   - **A 取得许可**：联系 FoodCalu 作者取得再分发/商用授权。需人工对外联络，结果不可控。
   - **B 移除来源（已有可执行工具）**：§5.3 要求的「删除/替换来源的脚本」已落地
     ——`tool/food_seed/strip_seed_source.py`（测试 `tool/food_seed/test_strip_seed.py`）：

     ```bash
     # 先看有哪些来源、各多少条（只读）
     C:/ProgramData/miniconda3/python.exe tool/food_seed/strip_seed_source.py --list
     # 试跑，写到新文件（不动 assets/）
     C:/ProgramData/miniconda3/python.exe tool/food_seed/strip_seed_source.py \
         --strip seed-fc- --out E:/AI/Zcode/tmp/foods.stripped.json
     # 真要换掉随包文件（先写 .bak，拒绝覆盖已存在的 .bak）
     C:/ProgramData/miniconda3/python.exe tool/food_seed/strip_seed_source.py \
         --strip seed-fc- --in-place
     ```

     注意 v4 是**单一来源**，剥掉 `seed-fc-` 后一条不剩，脚本会直接报错拒写
     （「随包种子不能为空」）——真要走 B，必须同时准备一个可再分发的替代中文源。
   - **推荐**：只要不分发就维持现状；要分发时优先 A，A 不成再按 B 换源。

2. **数据增补的可用来源（已查证）**：USDA FoodData Central 是本次调查里唯一拿到明确许可的
   成分库——官方 API 指南原文「USDA FoodData Central data are in the public domain and they are
   not copyrighted.」「They are published under CC0 1.0 Universal (CC0 1.0)」「No permission is
   needed for their use, but we request that users list FoodData Central as the source of the
   data」，建议引用「U.S. Department of Agriculture, Agricultural Research Service. FoodData
   Central, 2019. fdc.nal.usda.gov.」。**但它不是中文成分表**，只能提升基础食物的数据质量，
   不能解决「≥10,000 中文条目」（规范 §5.2 A 层，2026-10-02 起由随包 FoodCalu 中文库在
   数据量上达成，但**合规上仍是无许可来源**，见 §4.1）。若将来接入，许可证 `cc0-1.0`
   已在 `allowedCatalogLicenses` 白名单内。
3. **ODbL 的署名与同库要求**：应用内已提供来源清单；如对 OFF 数据做公开的衍生数据库
   分发（超过应用内使用范围），需按 ODbL 4.x 处理署名与 share-alike。
4. **随包第三方许可文本**：Android/Flutter 依赖的许可文本在应用内「开源组件许可」页
   可查阅；如果商店或分发渠道要求独立文本文件，再从 `LicenseRegistry` 导出。

## 5. 变更规则

新增或替换随包数据集、或扩 `allowedCatalogLicenses` 白名单时：

1. 先在本文件记录来源、许可证原文和归属方式；
2. 同步对应的 App 清单：食物 → `lib/features/nutrition/domain/data_attribution.dart`，
   动作 → `lib/features/training/domain/data_attribution.dart`；
3. 跑 `flutter test test/privacy`（清单与生成脚本/README 的一致性断言）；
4. 在 `docs/evidence/` 写当次审查证据，并更新 `STATUS.md`。
