# 发布与设备验收清单（2.0-7 余项）

> 2.0-7d 整理。这份清单只列**本机当前不能验证、需要真机/商店/完整数据**的动作，
> 每条都写成「怎么做 → 判据 → 结果写哪里」。在本机已经验证过的部分见
> `STATUS.md` 的 Verified Evidence 与 `docs/evidence/`。
>
> 未执行的动作标 `not run`，**不得写「预计通过」**（`docs/05` §8）。

## A. 数据线：OFF 全量目录（2026-09-16 已执行完毕）

状态：**done（本机）**。全量 ETL 跑通、发布目录已产出并通过独立验收。
复核命令与结果见 `docs/evidence/2026-09-16-2.0-1h-full-etl-release-catalog.md`；
机器生成的验收报告是 `docs/evidence/catalog-acceptance-2026.09.md`（发布物）与
`catalog-acceptance-2026.09-full-corpus.md`（不截断全量）。

前置：`tool/food_catalog/sources/openfoodfacts-products.jsonl.gz`（HF jsonl-export，ODbL，7.68GB）已于 2026-09-16 02:52 下载完成（7,683,519,547 字节）。

```bash
cd E:/AI/Zcode/localfit-ai/tool/food_catalog
# 等下载满 → 流式 gzip 完整性校验 → 全量 ETL（校验失败即停）
bash run_full_etl.sh
# 发布物：按流行度截断到 10 万条（docs/07 §10 的性能设计点，ADR-016）
C:/ProgramData/miniconda3/python.exe build_catalog.py \
  --input sources/openfoodfacts-products.jsonl.gz \
  --out ../../assets/catalog \
  --catalog-version 2026.09 \
  --retrieved-at 2026-09-15T20:45:07Z \
  --source-version huggingface:openfoodfacts/openfoodfacts-jsonl-export \
  --max-canonical 100000
```

判据（`docs/05` §5「5 万级目录质量门槛」，逐项写进 manifest 报告）：

| 项 | 判据 | 本次实测 |
| --- | --- | --- |
| canonical 行数 | ≥ 50,000（alias 不计入） | 100,000 ✅ |
| 四项宏量完整率 | ≥ 95% | 1.0000 ✅ |
| 重复 ID / 缺失名称 / 非法单位 / 负值 / NaN·Infinity | 全部为 0（ETL 自检会直接失败） | 全 0 ✅ |
| 来源/许可证缺失数 | 0 | 0 ✅ |
| 中文/别名/品牌/校园高频覆盖 | 记录实际数值（不设虚假下限） | 中文 1.93%（1,932 条）/ alias 195,897 / 品牌 95.90% ✅（校园高频未统计） |
| FTS 索引 hash 与行数 | 记录 | `cf1319851d38bb65…` / 195,897 ✅ |
| 份量 / 营养修订 / 来源证据行数 | 记录（docs/07 §5.5 三实体） | 31,657 / 100,000 / 100,000 ✅（2.0-1j 起真产出） |
| 分片大小 / 压缩大小 | 记录 | 98.8 MiB（最大分片 20.3 MiB）/ 未产出压缩分片 ⚠️ 见下 |

> 2.0-1j 起分片包含份量/修订/证据三个实体，同一份 10 万条目录从 58.7 MiB 长到
> **98.8 MiB**（单分片 12.0 → 20.3 MiB，其中 20,000 行 `evidence.record_hash` 的
> 64 字符十六进制文本就占 1.22 MiB/分片）。随包 core 分片因此变大，APK 增量待重测
> （见第 5 条）；若要压回体积，可把 `record_hash` 改成 32 字节 BLOB（省一半哈希体积）
> ——属可选的发布层优化，尚未做。

产出后还要做：

1. ✅ `flutter.bat test test/features/nutrition` —— 分片导入器 + manifest 校验回归；
2. ✅ 真实分片导入：`test/perf/catalog_real_scale_test.dart` 已在**真分片**上跑通导入与搜索
   （2.0-1j 在 etl-2 发布物上单独进程实测：50k 3 分片/60,000 行 7,935 ms、100k 5 分片/100,000 行
   13,908 ms；全量 5 分片 P50 20.4 / P95 31.6 ms），但那是桌面进程内的内存库；
   导入变慢是**功能变多**的直接代价——2.0-1j 起导入器同时写入份量/修订/证据三张实体表
   （每分片多约 4 万行的解析与插入，行口径仍是 foods 行数）；
   **设备走查已做（2.0-1k）**：API 35 模拟器 release 分包包首装导入 core 分片 20,000 条
   （DB 905,216 → 14,184,448 B）、设置页「本次导入 20000 条（1/5 个分片）」、`milk` 搜索出现
   来源徽标「目录」的分片命中、详情弹层显示 etl-2 修订/证据；过程与逐字 logcat 见
   `docs/evidence/2026-09-16-2.0-1k-device-import-fix.md`（含两个设备专属缺陷的修复：
   分片 ATTACH 到 SQLCipher 主库连接、主 isolate 缺 SQLCipher 库解析覆盖）。
   **仍未测**：中档真机（非模拟器）的冷启动导入耗时与峰值内存（见 B 节）；
3. ✅ 50k / 100k 的导入耗时与峰值内存实测；**备份导出体积**未测（98.8 MiB 是分片体积，不是 `.lfb` 导出体积）；
4. ✅ 结果已写 `docs/evidence/`，`STATUS.md` 的 Baseline 与 Risks 已更新。
5. ⚠️ 随包落段（2026-09-16 2.0-1i 落地，2.0-1j 换 etl-2 发布物）：`pubspec.yaml` 只声明
   `catalog.manifest.json` 与 `foods-core-000.sqlite`；`CatalogBootstrap.prepare()` 在 `runApp` 前
   把随包分片落到 `<supportDir>/catalog/`（`.bundled-shards.json` 记 sha256 版本），
   `importAvailable()` 在首帧之后导入。2.0-1i 实测包内只有 manifest 与 core 分片
   （当时 core 分片 12,587,008 B，三 ABI 各 +3.5~3.6 MB）；**换 etl-2 发布物后 core 分片
   21,266,432 B（ZIP 内压缩到 5.80 MiB），三 ABI 各再 +2.4~2.5 MB**（v7a 29.1 / arm64 32.6 /
   x86_64 34.6 MB），与 2.0-6 无目录基线相比累计 +6.0 MB/ABI。包内仍然只有 manifest 与 core
   分片两条。判据与边界见 `docs/evidence/2026-09-16-2.0-1i-bundled-core-shard.md` 与
   `docs/evidence/2026-09-16-2.0-1j-etl2-release-and-artifacts.md`。

**2.0-1j 起已闭合的三项**：docs/07 §5.5 的 `food_portions` / `food_nutrition_revisions` /
`food_evidence` 已有生产者（ETL 产行 + manifest 报告 + `accept_catalog.py` 门槛）与消费者
（食物库详情弹层，含「没有份量/修订/证据」的如实空态）；docs/07 §9.3 的搜索优先级分层已实现
（匹配层 + bm25，真分片 P95 31.6 ms）；两者证据分别是
`docs/evidence/2026-09-16-2.0-1j-ontology-entities-and-detail.md` 与
`docs/evidence/2026-09-16-2.0-1j-search-priority-layering.md`。

**2.0-1l 起「中文条目」这条已结案**：≥10,000 条中文基础食物在**可再分发**前提下**不可得**
（CFCT 镜像无 LICENSE、官方中文成分平台只标「版权所有」、无任何 CC0/PD/CC-BY 中文成分表、
唯一明确许可的 USDA FDC 是英文库；发布目录实测中文名 1,932 条、带中文品牌仅 823 条）——
授权问题而非工程量问题，不硬凑数字（ADR-020）。**但同一次调查查出随包 CFCT 种子违反 §5.3，
那是上架阻塞项**（见 E 节第 2 条）。

**仍未闭合**：core 分片导入的**中档真机**冷启动耗时与峰值内存未测（模拟器走查已由 2.0-1k
完成——首装导入/搜索/详情全链可用，证据见上第 2 条；§5.6 的应用侧路径已落地并随包，见第 5 条）。

## B. 中档 Android 真机（性能与鲁棒性）

判据来自 `docs/05` §3。每条都先记**基准与瓶颈**，不先引入无证据的缓存。

| 项 | 判据 |
| --- | --- |
| 冷启动到可操作首页 | < 2.5 s |
| 今日/计划查询 P95 | < 300 ms |
| 食物首屏搜索 P95 | < 200 ms |
| 50k 分片导入 | 不阻塞 UI isolate |
| 大图处理 | 在后台 isolate/worker |
| 普通滚动 | 无持续全表查询、无明显丢帧 |
| AI 请求 | 有总超时且可取消 |
| 无用户动作时 | 不持续联网 |

场景走查（`docs/05` §7 第 3 步）：飞行模式、低存储写满（导入中断不损坏数据）、
进程杀死后恢复、拒绝相机/文件权限后手动记录仍可用、暗色、大字体、减弱动画。

已在本机/模拟器做过的部分：暗色、大字体、减弱动画（2.0-6i-4 巡检）；**API 35 模拟器**
（release 分包包）的建档 → 今日页 → 记录 tab → 通勤对话框 → 冷启动（2.0-6i-5）、
**首装目录导入 → 搜索 → 详情**（2.0-1k）、**飞行模式 / 低存储两档 / 导入中断 /
进程杀死恢复 / 清除全部本地数据 / 文件选择器两级取消路径**（2.0-7f，2026-09-16，
8 场景 0 FATAL，证据 `docs/evidence/2026-09-16-2.0-7f-device-robustness.md`）。
注意模拟器是 x86_64 且宿主机是桌面 CPU，测得的是**功能可用性**，不是上表任何一条性能
门槛——门槛必须在中档真机上量。仍未做：上表全部性能项（等中档真机，外部阻塞）；
备份→清除→恢复的真机端到端闭环止步于 SAF 取消路径（全自动点 SAF 不稳定，确认词真机
输入待人工用输入法手输补验）。

## C. 构建与签名

- **每个 release 包必须装到设备/模拟器上真的点开一次**（2026-10-21 事故：vc4043/vc4044
  两轮包构建成功、`aapt2 dump badging` 也报出 launcher activity，但
  `android/app/build.gradle.kts` 漏了 Kotlin 插件 ⇒ `classes.dex` 里没有 MainActivity，
  装上一点就 `ClassNotFoundException` 秒崩；直到食物库设备复验才发现）。
  构造期判据已固化成测试：`test/release/apk_launch_contract_test.dart`
  （plugins 里有 Kotlin 插件 + launcher activity 解析后在 Kotlin 源码里真有这个类）。
  门禁跑不到设备，所以「安装并启动一次」仍必须人工/脚本做一次并留帧。
- `android/app/build.gradle.kts` 的签名配置 TODO：换 release 签名（当前 release 包仍用 debug 签名，2.0-6i-5 已记录）。
- 签名包上重跑一遍本机静态审计（`test/privacy` 只扫 `lib/`+`assets/`+`android/`；包内 Key/明文 URL/权限需要另行检查）。
- 包内第三方许可文本：应用内「开源组件许可」页（`LicenseRegistry`）可查阅；若渠道要求独立文本，从该页导出。
- Android 封闭测试（`docs/05` §7 第 5 步）。

## D. iOS（本机不可验证）

Keychain、应用私有文件、SQLCipher 适配，以及 `docs/05` §7 第 6 步的真机走查；
`ios/` 工程骨架存在但从未在本机构建过，结果写 `not run` 直到有设备。

## E. 商店材料与阻塞项

1. 按 `docs/08-store-privacy-and-permissions.md` 逐项填 Google Play Data safety / Apple App 隐私；
   提交结果（哪一天、哪个渠道、什么版本）写回 7d 证据。
2. **随包食物来源（FoodCalu）：仅对外分发时阻塞**（`docs/THIRD_PARTY_LICENSES.md` §4.1，
   2026-10-02 食物库整体替换后更新，见 ADR-025）：随包 `assets/seed/foods.v4.json` 的
   49,464 条全部来自 FoodCalu，上游**没有任何再分发授权**（仓库无 LICENSE），而 docs/07 §5.3
   明文「不清楚是否允许再分发的源不进入发布包」。**当前项目定位是个人自用、不商业化、不上架
   分发（ADR-020 补记），所以随包保留、不改数据**——本清单的 B~D 节（真机、签名包、iOS、商店）
   整体属于「将来要分发时才做」的范畴。一旦要对外分发，这条立刻变回阻塞项，两条出路：
   **A** 联系作者取得再分发授权（需人工对外联络）；**B** 用已就位的删除工具换源
   （`tool/food_seed/strip_seed_source.py`，`--list` 查看来源、`--in-place` 先备份）——注意 v4 是
   **单一来源**，剥掉 `seed-fc-` 后一条不剩，脚本会直接拒绝写空种子，所以走 B 必须先备好一个
   可再分发的替代中文源。推荐分发前优先 A。
3. ODbL 署名与 share-alike：应用内来源清单已满足应用内使用的署名；若对外分发衍生数据库，另行处理。
4. 逐条复核 `docs/05` §4 十条门槛里当前标「未验证」的三项（签名包扫描、真机权限拒绝路径、商店表单）。
5. 数据增补可用来源（已查证，供将来立项）：USDA FoodData Central 是 CC0 1.0 / 公有领域、可商用可
   再分发（署名为请求非义务），但它**不是中文成分表**，解决不了「≥10,000 中文条目」（该条已判定
   不可得，ADR-020）；许可证 id `cc0-1.0` 已在 `allowedCatalogLicenses` 白名单内。台湾 OGDL 1.0
   可商用可再分发（要求显名），但本机 DNS 不通、**未验证**到具体数据集，列为待查方向。

## F. 记录规则

- 每条结果写 `docs/evidence/<date>-<slice>-<topic>.md`：时间、环境（设备型号/Android 版本/
  构建类型）、完整命令或操作、真实结果、范围、产物、限制；
- `STATUS.md` 只保留索引、真实状态与限制；失败的命令也要留档，不覆盖不删除；
- 不存 API Key、图片、模型正文、菜单原文、健康数据和精确位置。

## D. 打包与版本号约定（2026-10-22 补，来源：审查 v2 的实测教训）

### D.1 ABI 与 versionCode 的对应关系（Flutter `--split-per-abi` 的真实行为）

Flutter 的 split 会给每个 ABI 额外加固定偏移（**2026-10-23 用 `--build-number 54` 与 `2054`
两次实测核对**）：

| 产物 | versionCode | 说明 |
|---|---|---|
| `app-armeabi-v7a-release.apk` | `buildNumber + 1000` | 实测：54 → **1054**；2054 → **3054** |
| `app-arm64-v8a-release.apk` | `buildNumber + 2000` | 实测：54 → **2054**；2054 → **4054** |
| `app-x86_64-release.apk` | `buildNumber + 4000` | 实测：54 → **4054**；2054 → **6054** |
| `app-release.apk`（universal） | `buildNumber` | 例：2054 |

> **2026-10-23 修正**：本表原先写 x86_64 是 `+5000`（依据是 2026-10-22 的命名推断，不是
> aapt2 实测）——实测偏移是 **+4000**；arm32/arm64 两行与实测一致。**推论**：`--build-number 54`
> 与 `--build-number 2054` 在 x86_64 上会得到同一个 4054/6054 系列的相邻值，跨系列混用时
> 必须按 D.3 单调递增，不能凭「感觉差不多」。

⇒ **同一 `--build-number` 下，arm64 包的 versionCode 比 universal 大 2000**。
2026-10-22 实测：先装 universal 4051、再装 universal 2052 被系统拒绝
（`INSTALL_FAILED_VERSION_DOWNGRADE`），因为 2052 < 4051。

### D.2 对外发布只发 arm64 分片

- **发布**：`flutter build apk --release --split-per-abi --build-number <N>`，
  取 `app-arm64-v8a-release.apk`（2026-10-23 实测 39,437,250 B）；
- **模拟器自测**：取 `app-x86_64-release.apk`（41,783,312 B）；
- **不要发 universal**：universal 是 87 MB（三个 ABI 全打进去），且它的
  versionCode 反而最小，和分片包混装会触发降级拒绝。

### D.3 versionCode 必须单调递增（跨 ABI 系列）

同一台设备上换包时，`versionCode` 必须比已装的大——按 D.1，**universal 的 N 永远小于
arm64 分片的 N+2000**。所以：

1. 固定「只装分片包」即可避免大部分冲突；
2. 若必须换装 universal（例如给他人通用包），把 `--build-number` 至少调到
   `已装 arm64 分片号 − 2000 + 1`；
3. 出包后**必须**用 `aapt2 dump badging` 核对 `versionCode` 并记进
   `release/vc<N>-sha256.txt`。
   **2026-10-23 本轮**：`--build-number 2054` ⇒ arm64 4054 / arm32 3054 / x86_64 6054；
   sha256 记在 `dist/SHA256SUMS.txt`（arm64 `09670ded…687b` / arm32 `52f4a9d6…4b45` /
   x86_64 `e3daa75f…ff14`）。**发的包必须比用户已装的大**：上一轮 arm64 是 4053。
