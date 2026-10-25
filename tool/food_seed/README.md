# 食物种子数据生成（foods.v4/v5.json）

> **2026-10-13 起：整族退役、已移出仓库**（docs/32 §4 T13 / §3 D13，需求 75）。
> `foods.v4.json` 与 `foods.v5.json` 归档在仓库外的
> `../archive/food-seed-2026-10-13/`（来源交代、sha256、为什么退役，见那里的
> README）；`pubspec.yaml` 不再声明食物资产，App 首启也不再导入这 49,444 条。
> 本目录的脚本（生成、审核、剥离、词表）因此都成了**历史工具**：要重跑得先把
> 归档里的种子放回 `assets/seed/`，或直接传路径——`strip_seed_source.py` 认
> `$LOCALFIT_FOOD_SEED`，缺省依次找仓库内旧路径与归档副本。
> 上游归属与「未声明许可证」的调查结论继续留在本文档：升级安装的用户库里可能
> 仍有这批行，来源交代不能跟着种子一起消失。

`assets/seed/foods.v4.json` 是本目录脚本从公开数据集清洗生成的随包食物库，
**49,464 条中文食物**、每 100g 热量/蛋白质/碳水/脂肪，并带保守的饮食标签与
过敏原推断。App 的食物检索（`FoodRepository.search`）直接查这张表的 `name`。

## 数据来源

| 文件 | 来源 | 许可/说明 |
| --- | --- | --- |
| `raw/foodcalu/food_database.db` | [gaosheng293/FoodCalu](https://github.com/gaosheng293/FoodCalu) 的 `app/src/main/assets/food_database.db`（SQLite，49,520 条） | 上游未声明许可证（个人自用）；数值为公开营养数据，App 内已注明数据出处 |
| `raw/foodcalu/name_zh.tsv` | 本仓库人工翻译（430 条） | 上游条目里名称**不含汉字**的行（英文/日文/品牌名），逐条译成中文，见下 |

**历史来源已下线**：v1/v2/v3 种子里的《中国食物成分表》派生素材
（`seed-cfct-`，1,634 条）与 foodwake/USDA 中译（`seed-fw-`，830 条）已随 v4 一并
从仓库删除，索引时也被 `FoodSeedImporter` 从用户库里清理。备份在
`E:/AI/Zcode/backups/localfit-old-food-library-2026-10-02/`（含 sha256 清单）。

## 生成

```bash
C:/ProgramData/miniconda3/python.exe build_foodcalu.py
```

读 `raw/foodcalu/food_database.db`，输出 `../../assets/seed/foods.v4.json`
（`{"version": 4, "foods": [...]}`，紧凑 JSON，UTF-8 不转义）。

清洗规则要点：

- 名称去掉 `品牌未知` 占位符、折叠空白；**不含汉字**的名称用 `name_zh.tsv`
  覆盖（缺翻译直接报错，不让英文条目漏进库）。同一归一化名称只留 id 最小的一条。
- **重复品牌块折叠**（`collapse_repeated_brand_block`）：源里 1,234 行把同一个
  品牌写了两三遍（`Kelsen凯尔森 Kelsen 凯尔森 黄油曲奇饼干`、
  `MABROC(玛勃洛克) MABROC(玛勃洛克) MABROC(玛勃洛克) MABROC/玛勃洛克 高地锡兰红茶`），
  折叠规则是「某空格段与更早的段归一后相同」或「非末段的每个构件（汉字串 /
  ≥2 字母的拉丁词）都已在更早的段出现过」就丢弃。**只折叠重复，不翻译品牌**：
  品牌名保留是有意的（用户按品牌搜索），所以库里仍会有拉丁品牌词。
  折叠后每个名字仍必须含汉字（否则构建报错退出）；折叠也暴露了 4 行原本只差
  品牌重复的真重复条目，一并去重。
- id 为 `seed-fc-<原表 id>`；`serving_g` 统一 100g（源库就是每 100g 口径）。
- 数值照抄源数据，不做 Atwater 修正：源里 206 条 0 kcal 的是纤维素/糖醇类
  （魔芋果冻、零卡调味），按 4-4-9 强补热量反而是错的。仅丢弃 2 条物理不可能
  的行（蛋白 202 g/100g 之类）。
- 饮食标签（vegetarian/vegan/dairyFree/glutenFree）与过敏原
  （egg/milk/soy/gluten/peanut/treeNut/fish/shellfish/sesame）按名称关键词保守
  推断：加工混合制品（复合词命中）默认不声明属性，仅当能明确推断过敏原时保留。
- 名称关键词有撞车黑名单（`RE_NOT_*`），例如「贝」不认（贝果/巴黎贝甜/贝壳面是
  品牌与器形，误标过 628 条）、「螺旋/螺丝/陀螺面」不是螺、「金龙鱼」是粮油
  品牌、「鱼腥草」是植物、「蟹味菇」是菌菇、「肉桂/果肉」不是肉、「蛋白粉/棒/
  肽」是补充剂、「奶白菜」是菜。过敏原仍是**名称启发式**，会有漏标/多标。
- `constraint_knowledge=unknown` 的行不带任何标签与过敏原（与
  `FoodConstraintFacts.validate()` 一致）。

## 数据规模

- 源 49,520 条 → 归一化去重 54 条、丢弃 2 条不可能值 → **随包 49,464 条**。
- 标签分布（known / 有标签 / 有过敏原）：36,366 / 25,212 / 24,250。
- 过敏原条数：gluten 11,751、milk 7,960、egg 2,625、fish 2,198、
  shellfish 1,294、treeNut 1,850、soy 1,014、sesame 839、peanut 564。
- 每条名字都含汉字（0 条纯外文）；其中 20.4% 的行仍含拉丁字母，绝大多数是
  **品牌名**（`Coles 鸡胸肉片`、`Wernli万恩利 橙子青柠味夹心威化饼干`），
  这是刻意保留的检索标识，不是漏翻。

## 注意

- **FoodCalu 来源条目：仅对外分发时才是阻塞项**：上游仓库没有 LICENSE 文件，
  按「不清楚是否允许再分发的源不进入发布包」（规范 §5.3）的原则，**当前定位是
  个人自用、不商业化、不上架分发**（ADR-020 补记），所以随包保留、不改数据；
  **一旦要对外分发就立刻变回阻塞项**。注意它**不能**走食物目录（catalog）通道：
  目录清单的许可证白名单是冻结的（odbl/cc/public-domain 系），无许可来源进不去，
  所以它只随包出现在种子层。两条出路见 `docs/THIRD_PARTY_LICENSES.md` §4.1。
- **规范 §5.3 要求的「删除/替换来源的脚本」已就位**：`strip_seed_source.py`（测试
  `test_strip_seed.py`）按 id 前缀剥离某个来源，`--list` 查看来源与条数、`--in-place`
  先写 `.bak` 再原地替换（拒绝覆盖已有备份），剥离后为空或前缀打错时都会报错，
  剥离后为空时不落盘。自用场景下不会用到它，它的作用是让「停止分发某个来源」
  保持一条命令、可回退。
- 修改规则后需重新生成并跑 `flutter test`（种子导入测试会校验条目数、中文名
  覆盖与 unknown 约束自洽）。
- 种子仅含宏量营养素；微量营养素（维生素/矿物质）不在 App 数据模型中。

---

## 2026-10-20：随包「用户食物库（8 列版）」

用户提供 `食品营养数据库_8列版.xlsx`（23,919 条、8 列）并要求内置。转换脚本在
`tool/food_catalog/convert_food_xlsx.py`，产物 `assets/seed/user_foods_8col.v1.csv`
（utf-8-sig，sha256 `65ac89ed30f41462d5691028f71baba9f3f0d017a752fac6f137fe95c6293557`）。
首启由 `BundledUserFoodImporter` 幂等导入（`app_settings.bundled_user_food_imported`
标记；行与手动导入同构：`isUserCreated=true`）。

**来源（混合，逐源登记）**：

| 代码 | 上游 | 许可/说明 | 规模 |
| --- | --- | --- | --- |
| S1 | `github.com/Sanotsu/china-food-composition-data`（中国食物成分表 6 版公开转录） | 上游未声明许可证（个人自用） | 1,549 |
| S2 | `github.com/xiaok0928/spider-boohee-data`（薄荷 SQL 历史存档） | 上游未声明许可证（个人自用） | 41,991 |
| S3/S3b | `github.com/seawaylee/boohee_spider`、`github.com/eninem123/bohespider`（薄荷网页 JSON 存档） | 上游未声明许可证（个人自用） | 2,476 + 130 |
| S5 | `data.fda.gov.tw`（台湾食药署开放数据） | 政府开放资料（需署名） | 2,094 |

**许可证短名**：`混合来源（个人自用）`——与 App 内「数据来源与许可证」的
`foodDataAttributions` 逐字一致（审计按字面比对，不美化）。

> 混合源的**再分发许可未逐条审计**：与 v4/v5 同一个定位（个人自用不分发），
> 详见 `docs/THIRD_PARTY_LICENSES.md` §1b。一旦对外分发必须先处理该节的阻塞项。
> 数量口径：审计记录为清洗前各源保留数（合计 48,240），去重与二次过滤后成品
> 23,919 条。

