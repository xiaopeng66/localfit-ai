# LocalFit AI 代码审查计划方案（code-review.v1）

> 状态：已完成（2026-10-02）· 规范效力：无 · 后续以 `docs/29-ui-ux-remediation-plan.md` 为准 · 文档地图见 `docs/INDEX.md`

> 本文是**审查怎么做**的规范（normative）：范围、审查轴、判据、证据纪律、退出条件。
> 实际执行结果与红证记录写在 `docs/evidence/2026-10-02-code-review-and-size.md`。
> 与 `docs/11-code-review-and-bug-hunt-plan.md`（历史审查线）的关系：那份是 1.x→2.0 过渡期的
> 分域清单（§3-A~§3-H），本轮**沿用它的"先证可达性再登记"纪律**，但范围更新到当前代码
> （UI 重建后 + AI 三协议 + chat-edit v1 + 浮层内反馈修复），并新增两条轴：**响应/输入上限**与**体积**。

---

## 1. 目的与范围

审查对象是 `lib/` + `android/` + `assets/` 的**当前快照**（无 Git 元数据，按现状审查）。

**在范围内**：

- 安全与隐私（凭据、日志、明文、重定向、SSRF 面、系统备份、文件路径边界）
- 数据完整性与可恢复性（迁移、备份/恢复/清除、外键与事务、读取侧兜底）
- 资源上限与 DoS 面（请求/响应/文件大小、流式累积、超时、解压炸弹等价物）
- 异步生命周期与错误卫生（`mounted`、dispose、取消语义、上屏文案不泄漏内部异常）
- 依赖与供应链（未使用依赖、精确钉版、上游不自洽的 override）
- 体积与发布面（原生库、资产、资源、混淆与符号剥离）
- 测试有效性（断言是否锁得住缺陷；替身是否比产品宽松）

**不在范围内**（本轮不做，原因随附）：

- 真机性能门槛（需中档 Android 真机）、真实第三方 AI 端点联调（需真实 Key）、
  iOS 真机（本机无法构建验证）、应用商店合规表单（分发范畴）。
- 已在别处裁定为「不可得/不适用」的项：≥10k 中文基础食物（ADR-020）、
  对外分发时的许可证问题（ADR-025）。

---

## 2. 审查轴与判据

每条轴给「查什么 + 怎么判 + 反例长什么样」。**判据必须能在代码里定位**，不接受印象式结论。

| # | 轴 | 查什么 | 判据 | 已见过的反例 |
|---|---|---|---|---|
| A | 凭据与密钥 | Key 的存储、传递、日志、导出、`toString()` | Key 只进 Keystore/加密存储；只经 header 出网；不进日志/备份/CSV/异常文案 | —（本轮未发现） |
| B | 网络出口 | HTTPS、明文禁用、重定向、端点校验 | `followRedirects:false` + `maxRedirects:0`；端点必须 https/443/无 query·fragment·userinfo | RelayTester 的跨主机重发凭据（本项目已堵） |
| C | 本地文件边界 | 路径拼接、删除范围、覆盖、恢复注入的路径 | 删除/读取前 `canonicalize + startsWith(root+sep)`；命名冲突绝不覆盖 | 上一轮：删除有边界、**渲染侧没有** |
| D | 数据完整性 | 迁移守卫、备份清单对账、事务、读取侧兜底 | 迁移两条守卫（下界 + `sqlite_master` 存在性）；清单与 schema 逐表对账；脏值整单回滚 | BUG-15/16、v15/v18 迁移 |
| E | 上限与 DoS | 请求/响应/文件大小、流式累积、超时 | 每个出口都有**累计**上限（不只是空闲超时）；外部文件先查长度再读 | 非流式有 128KB、**流式没有** |
| F | 异步与错误卫生 | `mounted`、dispose、取消、上屏文案 | await 后 setState 有守卫；取消不是错误；文案只来自本地撰写 | BUG-12/13/14、浮层内反馈 |
| G | 依赖 | 未使用依赖、版本钉法、override | 声明的依赖必须有 import；override 必须写明理由与删除条件 | fl_chart 等 5 个未使用依赖 |
| H | 体积 | 原生库、资产、资源、混淆 | 每一项都能量化到「多少字节、来自哪」；优化不得改变行为 | 原生库未压缩（≈16 MB 可省） |
| I | 测试有效性 | 断言强度、替身强度、机械对账哨兵 | 断言能区分「修好/没修好」；替身与真实实现同口径 | 弹层内提示（`find.text` 抓不到）、宽松的 fake store、`ui_spec_key_sync` 需要 `>100` 哨兵 |

---

## 3. 方法与证据纪律（硬要求）

1. **先证可达性再登记**：一个缺陷必须能从真实用户路径走到，或在测试里构造出等价条件；
   不可达的一律记为「加固，非修复」，不许用「修了缺陷」的措辞（`docs/11` 第 3 轮的教训）。
2. **每条真缺陷配三件套**：回归测试（先红后绿）+ **隔离变异红证**（只改一处实现 ⇒ 指定测试
   必须变红 ⇒ 按字节还原并核对 sha256）+ 证据文档条目。
3. **判据从输出解，不从退出码转述**：测试判定读 `All tests passed.` / `Some tests failed.`；
   `verify.bat` 的退出码写文件再读，不经管道（阶段 I 的假绿教训）。
4. **子代理/工具报告一律逐条核验**：报告里的每一条都要在代码里指出来才算数；
   历史上出现过「17 条缺陷无一成立」。
5. **改动不得放宽既有断言**：因行为变更而失效的测试是**重新定位**，不是放松判据。
6. **量化优先**：涉及性能/体积/几何的结论必须给数字（多少次、多少字节、多少毫秒）。
7. **红线不变**：零真实 AI 请求（全部 fake provider）、Key 不进日志/截图/文档、
   仓库无 Git 元数据所以**删除不可逆**（删前备份）。

---

## 4. 本轮覆盖矩阵

| 轴 | 本轮做法 | 状态 |
|---|---|---|
| A 凭据 | 读 Key 存储/传递/日志/导出路径；核对 `PrivacyLogger` 白名单与 `toString()` | 已执行（未发现问题） |
| B 网络出口 | 核对三协议出口的重定向与超时配置、端点校验规则 | 已执行（未发现问题） |
| C 文件边界 | 核对删除/读取/渲染三处的边界校验；核对恢复可注入的路径列 | 已执行（发现 2 处，见 §5） |
| D 数据完整性 | 核对迁移守卫、备份清单与 schema 对账、恢复事务与值校验 | 已执行（发现 1 处） |
| E 上限与 DoS | 逐个出口/入口量「有没有上限」：transport、对话流、备份读取、菜单导入 | 已执行（发现 3 处） |
| F 异步与错误卫生 | 抽查 await/dispose/取消；错误文案来源 | 已执行（本轮未新增发现） |
| G 依赖 | 逐条依赖 grep import；核对 override 的说明 | 已执行（发现 5 个未使用依赖） |
| H 体积 | APK 逐条目量化；量化每个优化项的收益与代价 | 已执行（见 §6） |
| I 测试有效性 | 复核本轮新断言能否区分修好/没修好；替身强度 | 已执行 |

---

## 5. 本轮发现（按严重度）

严重度口径：**High** = 违反项目自述硬约束或可致数据/隐私外泄；**Medium** = 可致崩溃/OOM/异常
行为且用户可触发；**Low** = 边界/加固类；**Info** = 卫生项（依赖、死代码、口径）。

| # | 轴 | 严重度 | 判定 | 位置 | 问题一句话 | 本轮处置 |
|---|---|---|---|---|---|---|
| H1 | A/C | **High** | 真缺陷 | `android/app/src/main/AndroidManifest.xml:5-9` | 未声明 `allowBackup`/`dataExtractionRules`：默认允许 Android 云备份把应用私有数据（聊天图片、菜单原文等**未加密**文件）上传 | **修**（禁用系统备份 + 规则文件 + 隐私审计断言） |
| M1 | E | Medium | 真缺陷 | `lib/features/ai_conversation/data/open_ai_compatible_conversation_service.dart:147-206` | 对话 SSE 只有空闲超时、**没有累计字节上限**，与非流式出口（128KB）不对称：指向的端点可无限输出 ⇒ 内存/落库无界增长 | **修**（累计字节上限 + 总时限 + 回归测试） |
| M2 | E | Medium | 真缺陷 | `lib/features/backup/application/lfb_backup_codec.dart:105-146`、`lib/features/backup/data/backup_file_store.dart:43-56` | `encode` 有 `maxPayloadBytes`（256MB）但 `decode` 不校验，且选文件后**整份读入**无长度检查 ⇒ 任意大 `.lfb` 直接 OOM | **修**（两侧都加上限，并把上限降成与真实备份相称的值） |
| L3 | E/F | Low | 真缺陷 | `lib/features/nutrition/data/catalog_search_service.dart:118-129` | 只处理「分片文件被删」，没处理「分片损坏/不是 SQLite」：一个坏分片让**整页食物搜索报错**（应用自己引导用户往该目录放文件） | **修**（坏分片跳过，与缺文件同策略） |
| L4 | C | Low | 真缺陷 | `lib/features/backup/application/csv_exporters.dart:143-148` | CSV 只做引号转义，未中和公式注入：食物名/备注以 `=` `+` `-` `@` 开头时，在 Excel/WPS 里被当公式执行 | **修**（前置单引号中和 + 回归测试） |
| L2 | C/D | Low | 真缺陷（弱） | `lib/features/backup/application/backup_table_registry.dart:309-312`、`lib/features/backup/application/restore_localfit_data.dart:54-82` | 恢复只校验 ISO 日期列，**不校验路径列**：备份可把 `conversation_messages.image_path/audio_path` 写成任意路径，读取侧 `Image.file` 会渲染它 | **修**（恢复时形状校验）+ 残留记为待办 |
| L1 | C | Low | 加固 | `lib/features/campus_menus/data/file_menu_raw_content_store.dart:38-43` | `resolve()` 把相对路径直接 `joinAll` 且放行绝对路径；当前**无调用者**（死代码），一旦接线就是越界读原语 | **修**（加 `canonicalize + startsWith` 守卫，与 chat image store 同款） |
| L5 | E | Low | 加固 | `lib/features/campus_menus/application/menu_file_importer.dart:97-105` | 菜单导入 `readAsBytesSync()` 无大小上限（仅扩展名白名单）⇒ 超大文件 OOM（该链路当前无生产入口） | **修**（长度上限） |
| D1 | G | Info | 真缺陷 | `pubspec.yaml:15` | `fl_chart` 声明但全仓无 import（图表已改手绘 `CustomPainter`） | **修**（移除） |
| D2 | G | Info | 真缺陷 | `pubspec.yaml:18,20,52,53` | `freezed_annotation`/`json_annotation`/`freezed`/`json_serializable` 声明但无任何 `.freezed.dart`/`@JsonSerializable` 使用 | **修**（移除 4 个） |
| I3 | A | Info | 加固 | `lib/features/ai/domain/ai_transport.dart:34-35` | `AiTransportRequest.apiKey` 明文持有 Key 但 transport 从不读它（认证头由 `headers` 注入）⇒ 内存里多一份副本 | 记录，本轮不改（波及所有出口调用点与测试） |
| I1 | B | Info | 设计允许 | `lib/features/settings/domain/open_ai_compatible_endpoint.dart:48-84` | BYOK 允许任意 host（含私网/回环），仅 https/443 约束；无 host 白名单 | 记录（BYOK 语义），建议设置页对私网 host 给显式提示 |
| I4 | A | Info | 口径 | `lib/features/backup/application/lfb_backup_codec.dart:270-277` | 口令只判 `trim().isEmpty`，派生用原串：前后空格会得到不同密钥 | 记录（改不得：会让既有备份解不开） |

**落地状态（2026-10-02 收口，详见 `docs/evidence/2026-10-02-code-review-and-size.md`）**：

- 上表中标「修」的 **8 条真缺陷 + D1/D2 依赖项**已全部落地；**19 条隔离变异全部报红且还原字节一致**
  （`E:/AI/Zcode/tmp/mutation_1002b.log`）；门禁 1652/3 → **1671/3**。
- **L1/L5 的修复在交付产物里被 AOT 树摇剪掉**：它们所在整条链（`MenuTabController.importFrom` →
  `MenuFileImporter.importFile` → `rawContentStore.save`）在 `lib/` 里没有调用者，字面量在
  `libapp.so` 里查不到（同文件 `clearAll` 的文案能查到）。所以这两条**今天不是"已上线的加固"，
  而是"回归保护 + 将来接线时不再是越界原语"**；"文件导入无 UI 入口"已作为功能缺口登记（证据文档 §8①）。
- 标「记录，本轮不改」的四项（I3/I1/I4 + 私网提示）维持原判，理由见上表。

**已执行但未发现问题的面**（避免误读为"没查"）：Key 泄漏（日志/异常/导出/`toString`/截图/明文输入框）、
数据库密钥来源与设备绑定、备份口令 KDF（PBKDF2-SHA256 60 万次 + 16 字节盐 + AES-256-GCM + 双完整性）、
聊天图/餐图删除边界与原子写、Android 导出组件与 deep link（只有 LAUNCHER）、恢复的表名白名单与事务回滚、
FTS5 查询串注入（白名单化后再拼）、catalog manifest 的路径越界、语音临时音频（cache + 用完即删）、
非流式 transport 的双层字节上限、AI allow-list 投影「只能在本地候选里选」。

---

## 6. 体积优化口径

### 6.0 实测结果（2026-10-02 收口）

| 阶段 | 动作 | APK 字节 | 相对上一行 |
|---|---|---|---|
| 起点 | 上一轮交付件 | 31,439,721 | — |
| ① | 代码改动（8 处修复 + 移除 5 个依赖），无打包/编译优化 | 31,439,561 | −160 B（≈0，与预期一致） |
| ② | `useLegacyPackaging = true` | 14,888,421 | **−16,551,140 B** |
| ③ | `--obfuscate --split-debug-info` | 13,965,181 | −923,240 B |
| ④ | `+ --extra-gen-snapshot-options=--strip --dart-define=APP_VERSION=0.1.0` | **13,965,669** | +488 B（只来自注入的版本串） |

**2026-10-07 追加（P8b-2 交付件）**：`E:/AI/Zcode/localfit-ai-simple-arm64-release.apk`
= **13,915,632 B**（13.3 MiB），相对上一交付件 13,837,354 B 仅 **+78,278 B**——差全部来自
`libapp.so`（+95,351 B，P8b-2 代码 + 显示层改动）与食物库资产（v4→v5，+11,475 B），
`libflutter.so`/`libsqlcipher.so` **逐字节未变**。

**本轮踩坑（写进口径，避免复现）**：`--target-platform android-arm64` **不加
`--split-per-abi`** 时**不裁剪其它 ABI 的预编译依赖**——产物 18,374,994 B，包内混进
armeabi-v7a 与 x86_64 的 `libsqlcipher.so`/`libdartjni.so`（该开关只决定编译哪套 AOT
快照）。**单 ABI 交付必须同时给 `--split-per-abi`**，并以 `aapt2 dump badging` 的
`native-code` 字段复核只有一个 ABI。另：`--strip` 在本 Flutter 版本仍是**零收益**
（与 §6.0 一致），如实不记成成果。

**v5 种子比 v4 大 639 KB（原始）/ 11 KB（压缩）的原因**：v5 行数更少（49,444 < 49,464）
但每行多一个 `brand` 键（`"brand":null` ≈ 14 B × 49,444），只有 208 行有真值——
这是 D6 品牌拆分的必然代价，`null` 高度可压缩，**不是回归**。

**交付件 13,965,669 B = 上一轮交付件的 −55.58%**；`lib/` 4 条 packed 合计 28,995,264 → 11,575,162。
**`--strip` 在本 Flutter 版本下零收益**（`libapp.so` 前后同为 10,093,448 B，产物里查不到
`.debug_info`/`.debug_line`/`.debug_str`）——那条 DWARF 提示是通用提示，不记成收益。
条目级对照与"下载变小但装机占用变大"的口径说明见证据文档 §5.2。

### 6.1 优化前的估算口径（保留，作为当时判断依据）

**基线**：`localfit-ai-simple-arm64-release.apk` 31,439,721 B（单 ABI arm64-v8a）。
逐条目量化（compressed = APK 内实际占用）：

| 组成 | 占用 | 说明 |
|---|---|---|
| `lib/arm64-v8a/libapp.so` | 11.93 MB | Dart AOT 快照（**含调试信息**，可剥离/混淆） |
| `lib/arm64-v8a/libflutter.so` | 11.75 MB | Flutter 引擎（固定，不可拆） |
| `lib/arm64-v8a/libsqlcipher.so` | 5.19 MB | 加密 SQLite（功能必需） |
| `assets/.../foods.v4.json` | 1.51 MB（原 10.70 MB） | 中文食物库 49,464 条（功能必需，已 deflate） |
| `classes.dex` | 0.50 MB | 已开 R8 minify + shrinkResources |
| `res/` + 其余资产 | ≈0.34 MB | 已 shrink/重命名 |

**三条杠杆（按收益排序）**：

1. **原生库压缩**（`jniLibs.useLegacyPackaging = true`）：三个 `.so` 当前以 **STORED（未压缩）**
   进包，共 28.99 MB；实测 gzip-9 比例 0.39/0.47/0.44 ⇒ **下载体积可省约 16.4 MB**。
   代价：安装时解压（`extractNativeLibs=true`），设备上占用 ≈ 下载 + 解压后副本，
   首次启动略慢。**判定：采用**（交付物是"传给人的 apk"，下载体积优先；代价在文档里写明并给回退方法）。
2. **符号剥离 + 混淆**（`--split-debug-info=<dir> --obfuscate`）：把调试信息移出 `libapp.so`。
   代价：线上崩溃栈需要符号文件还原（保留在 `build/symbols/`）。**判定：采用**。
3. **移除未使用依赖**（D1/D2）：APK 侧收益接近 0（未 import 的库已被 tree-shake），
   但缩小供应链面与 `NOTICES.Z`。**判定：采用**。

**不做**的项与理由：`libflutter.so`/`libsqlcipher.so` 是引擎与加密实现，不可拆；
`foods.v4.json` 是功能数据（删了就没中文食物库）；`exercises.v1/v2.json` 保留（向后兼容测试与
隐私审计断言需要）；`NOTICES.Z` 是许可证合规必需；R8 与资源收缩已开启（无剩余空间）。

**验收口径**：优化后必须 ① `verify.bat` EXIT=0；② 逐条目量化对比表（体积差 + 差在哪）；
③ 模拟器装机走查（安装、启动、若干页面、食物搜索、设置页）无崩溃；
④ 产物内嵌字符串核验（本次修复相关文案 + 协议 key）仍在。

---

## 7. 退出条件与复审触发

**本轮退出条件**（2026-10-02 收口：四条全部满足，证据见 `docs/evidence/2026-10-02-code-review-and-size.md`）：

1. §5 表中标「修」的条目全部落地，且每条**真缺陷**都有先红后绿的回归测试 + 隔离变异红证。
   → 19/19 变异 RED；**例外已声明**：L1/L5 在产物里被树摇剪掉（无 UI 入口），按"未闭合"登记。
2. `tool/verify.bat` EXIT=0（format 0 changed / analyze No issues found / 全量测试通过）。
   → RC=0，1671 passed / 3 skipped（+19）。
3. 体积优化的量化对比表与装机走查证据写入证据文档。→ 已写入（§5、§7）。
4. 交付简化版 APK，并记录 sha256、体积、ABI、签名证书与**未取得项**。
   → `E:\AI\Zcode\localfit-ai-simple-arm64-release.apk`，13,965,669 B，
   sha256 `14d2c5927fe42bf6e60570c2aada168a5dd709195c6be29ef441b7549e0bb611`，单 ABI arm64-v8a，
   `CN=LocalFit Personal`；未取得项 = 真机（arm64）装机走查。

**复审触发条件**（任一条成立就要重跑相应轴）：

- 新增或修改 AI 出口 ⇒ 重跑轴 B/E（上限、认证头、重定向）。
- 新增表 / 迁移 ⇒ 重跑轴 D（守卫、备份清单对账、恢复值校验）。
- 新增会读写应用私有目录的文件类型 ⇒ 重跑轴 C。
- 升级主要依赖（drift/dio/cryptography/flutter_secure_storage）⇒ 重跑轴 A/B/G。
- 每次发布前 ⇒ 全轴 + 体积对比。

### 7.1 2026-10-08 排查轮（触发条件命中后按本表重跑的记录）

2026-10-08 的「缺陷排查 + AI 测试审查」轮（`docs/11` 口径，证据
`docs/evidence/2026-10-08-bug-hunt-and-delivery.md`）**恰好由本表的触发条件命中**：
P7 的菜品照片（`DishImageStore`）属于「新增会读写应用私有目录的文件类型」，但当年
**没有回来重跑轴 C**——本轮重跑即在轴 C 上查出 P1 缺陷（见下）。各轴结果：

| 轴 | 本轮做法 | 状态 |
|---|---|---|
| A 凭据 | Key 仍只进 Keystore/只经 header 出网/不进日志（本轮未动） | 已执行（未发现问题） |
| B 网络出口 | 逐字节重建 5 条出口请求体 + 4 个模板，与钉住的 `requestSha256`/`templateSha256` 比对；核对 `today=`/`date=` 的时间来源 | 已执行（钉值全命中；查出**跨时区脆弱**一类，见 ADR-032） |
| C 文件边界 | **重跑**：全清名单 vs 磁盘上的文件型存储（餐照/菜单原文/聊天图片/**菜品照片**/API Key）逐项对账 | 已执行（**发现 P1**：菜品照片不被清除 ⇒ BUG-7，已修，ADR-030） |
| D 数据完整性 | 备份恢复、全清行删除、schema 迁移、种子 v4→v5 升级四态、写入路径事务、生命周期 | 已执行（无 P0；查出 1 项 P1 见轴 C、5 项 P2/P3 已登记） |
| E 上限与 DoS | AI 出口上限与超时抽查 | 已执行（未新增发现） |
| F 异步与错误卫生 | AI 任务卡「确认写入」的 await/dispose/防重入、卡片相位与提示 | 已执行（**发现 2 项**：双击重复写库 BUG-1、静默半写 BUG-2；另 2 项 P3 提示类 BUG-8/BUG-9） |
| I 测试有效性 | 「测试钉住假话」专项：全仓用户可见文案扫中文夹英文 + 断言方向核对 | 已执行（**发现 2 处被钉住的假话**：反馈弹层「当前版本不联网」等 ⇒ BUG-4/5/6，ADR-029） |
| H 体积 | 交付件逐条目核对（ABI 单列、`.so` DEFLATE、随包种子逐字节、内嵌文案探针） | 已执行（见证据 §5） |

**本轮新立的口径**（都进了 ADR，后续轮次照办）：①披露面文案只陈述真实行为，测试钉住旧错话时
**必须同步改测试**（ADR-029）；②「文件型存储」是清理名单的强制成员，新增一类即时回补
（ADR-030）；③AI 任务卡的 `onConfirm` 是异步契约，类型不许退回 `VoidCallback`
（ADR-031）；④测试里注入的固定时刻一律取本地墙钟正午 `DateTime(y,m,d,12).toUtc()`
（ADR-032）。

**本轮未闭环**（供下一轮接手）：轴 C 仍有 2 条 P2/P3（级联删行不清磁盘照片 = U6、
有导入菜单的地点删不掉 = U5，后者属破坏性语义需所有者裁决）；轴 I 的非 AI 面还有两处
同类时区脆弱（U9）；v4→v5 升级的 49k 行逐条 `UPDATE` 的**性能未测量**（U7）。

