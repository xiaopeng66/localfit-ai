# 全应用审查计划（2026-10-20）

> 执行引导：[`docs/45`](45-full-app-review-and-remediation-guide.md)。本文件是 S1 产物：
> 十四维度逐维给出「检查项 / 方法 / 证据 / 判据 / 覆盖目标」，附抽样规则与可直接执行的命令清单。
> 审查阶段**只读**：不改 `lib/`，缺陷只登记（`docs/48`）。

---

## 0 范围与不做

**范围**：`lib/`（375 个 Dart 文件）、`test/`（353 个测试文件）、`android/`、`assets/`、`docs/`、
`release/` 与当前门禁/设备状态。

**做**：

1. 十四维度（A–N）逐维审查，每维至少一条汇总证据；
2. 覆盖硬目标：页面 100% 进入一次；写路径 100% 端到端（含失败）；`docs/21` Key 100% 有断言；
   降级矩阵 5×4 逐格；性能 ≥10 项有数字；边界 ≥20 条；设备 ≥8 类场景有实帧；
3. 缺陷定级 P0/P1/P2/P3 并挂证据；
4. 出报告 → 修复文档 → 逐 ID 修复 → 二次验收。

**不做（本轮明确排除）**：

- 不改 21 列 CSV 契约、不改 AI wire 形状、不新增表/列（schema 29 冻结）；
- 不新增第三方依赖（除非阻塞 P0）；不提交/推送/发布；
- 不调用真实 AI（环境无 `LF_AI_LIVE_*` 凭据；只做契约/mock 验证，不声称真机 AI 已验证）；
- 不做架构级重构与文案润色；P3 只登记不修。

---

## 1 基线（开工时实测）

| 项 | 值 | 来源 |
|---|---|---|
| 门禁 | `review-baseline2`：format 0（lib/test 分别跑）/ analyze `No issues found!` / `+2772 ~66` / exit 0 / `changed_during_run: []` | `logs/review-baseline2.json` |
| 上一轮记录基线 | `bundled-food-final2`：`+2772 ~66` exit 0 | `STATUS.md` 顶部 |
| APK | arm64 vc2040 39,126,517 B sha256 `38323ddd…4e71`；x86_64 vc4040 41,470,927 B `5f187946…5666` | `release/` + aapt2 |
| schema | 29（`AppDatabase.schemaVersion`） | `lib/data/database/app_database.dart:96` |
| 端上向量 | 已启用（maxLen 32 + 前缀 B；worker isolate） | `main.dart` 装配 |
| 随包用户食物库 | 23,919 条 / 1,652,576 B / sha256 `65ac89ed…3557` | `assets/seed/user_foods_8col.v1.csv` |
| 设备 | 自有 AVD `LocalFit_API35`（x86_64, API 35）；同机 `emulator-5558` 属其它项目，不触碰 | `adb devices` |
| 开工时基线红项 | `importer_smoke_test.dart` 依赖仓库外 `E:/AI/Zcode/tmp/localfit-next/食品营养数据库_8列版_utf8.csv`（已被清理）⇒ 基线红；用随包 CSV（同 sha256）恢复该临时文件后转绿。**登记为缺陷 P1**（门禁不可自包含） | `logs/review-baseline.log` vs `review-baseline2.log` |

---

## 2 维度矩阵（A–N）

> 每维五列：**检查项 / 方法 / 证据 / 判据 / 覆盖目标**。证据目录统一为
> `docs/evidence/2026-10-20-full-app-review/`（下称 `EV/`）。

### A 功能正确性

| 项 | 内容 |
|---|---|
| 检查项 | ① 每个写路径的失败分支（餐/菜品/食堂/食物/饮水/体重/训练/记忆/备份/全清/CSV/AI 命令）；② 重复提交幂等；③ 营养/份量/趋势/推荐计算；④ 跨零点与日期边界；⑤ 导入导出与备份恢复；⑥ 37 条 AI 命令逐条成功+失败；⑦ 记忆判重/注入/改口/归档/待确认；⑧ 检索三路与融合 |
| 方法 | 读生产代码 + 对照测试；写路径用「入口→仓储→表」三跳核对；命令用注册表逐条比对执行器与测试；数学用常量代入手算比对 |
| 证据 | `EV/code/audit-A-F.md`；命令覆盖表（37 行）；写路径表 |
| 判据 | 端到端可复现；数字与手算一致；失败分支有人话且不逃逸；同一写路径第二次提交不产生第二条事实 |
| 覆盖目标 | 写路径 100%（含失败）；命令 37/37 |

### B 界面与视觉

| 项 | 内容 |
|---|---|
| 检查项 | token 一致性；正文对比度 ≥4.5:1；禁 emoji 图标；空/加载/错误/骨架四态；深色模式；同组件同形态；裁字/溢出；图片缺失不伪造 |
| 方法 | token 与硬编码扫描（`rg "Color\(0x"`）；用脚本按 WCAG 公式实测 token 配对比值；emoji 码点扫描；逐页四态核对；读 `TextOverflow.ellipsis` 命中的用户内容 |
| 证据 | `EV/code/audit-B-C-E-J.md` §2 对比度表、§3 四态矩阵；`EV/static/` 扫描输出 |
| 判据 | 与 `docs/21` 一致；正文对比度 ≥4.5（大字 ≥3.0）；帧上看不出裁切；没有用示例值伪造数据 |
| 覆盖目标 | 11 个数据页四态；主要 token 配对所有组合 |

### C 交互

| 项 | 内容 |
|---|---|
| 检查项 | 热区 ≥48dp；反馈在弹层内可见；危险操作二次确认；取消/重试；返回与手势；键盘遮挡；弹层根导航器/不被底栏遮挡/拖拽只认把手；滚动位置；防抖；长按多选 |
| 方法 | `rg showModalBottomSheet` 逐个核对三件套（root navigator / enableDrag / sheetBottomInset）；热区看有效尺寸（Material 默认算入）；写入型按钮查 busy/disable；危险动作查确认弹层 |
| 证据 | `EV/code/audit-B-C-E-J.md` §4；`EV/device/` 帧 |
| 判据 | 每步可点、有反馈、可撤回；底栏不遮挡弹层最后一行；连点不产生第二条事实 |
| 覆盖目标 | 全部 24 个弹层入口（含 `AppSheet` 与非 `AppSheet`） |

### D 流畅性/性能

| 项 | 内容 |
|---|---|
| 检查项 | 冷启动首帧；切页掉帧；1000+ 行滚动；搜索 p50/p95；DB 耗时与 N+1；内存峰值（模型 + 2.4 万食物）；APK 体积；后台任务 |
| 方法 | 仓内既有基准测试（`category_benchmark` / `catalog_search_perf` / `query_benchmark` / `memory_governance` B5 分页）+ 设备 `am start -W` / `dumpsys gfxinfo` / `dumpsys meminfo`；每项 3 次取中位数并记录环境 |
| 证据 | `EV/perf/*.csv` + `EV/perf/*.md` |
| 判据 | 有数字基线；无 >500ms 卡顿；与基线对比劣化 ≤10% |
| 覆盖目标 | ≥10 项指标有数字 |

### E 动画

| 项 | 内容 |
|---|---|
| 检查项 | 时长/曲线统一（`AppMotion`）；入场/退场；被打断/重入；无限动画不阻塞；reduce motion |
| 方法 | `rg "Duration\(milliseconds"` 与 `AppMotion` 对照；`rg "\.repeat\("` 逐个核对是否 reduce-motion 守卫；查 `disableAnimations` |
| 证据 | `EV/code/audit-B-C-E-J.md` §5 |
| 判据 | 曲线一致；不卡帧；`pumpAndSettle` 可收敛 |
| 覆盖目标 | 全部 `.repeat()` 与主要转场 |

### F 状态与一致性

| 项 | 内容 |
|---|---|
| 检查项 | 单一事实源；写后刷新；多入口同步；竞态（旧请求后落地）；双击幂等；常驻页跨零点；缓存失效（段级/textHash）；乐观 UI 回滚 |
| 方法 | 读状态持有者与流订阅；查 build 内建流/改状态；查异步请求代次令牌；双入口写同一表；缓存键构成 |
| 证据 | `EV/code/audit-A-F.md` §4（A-F05/A-F06/A-F10/A-F13/A-F19） |
| 判据 | 任一入口改，其他入口一致；旧响应不覆盖新结果 |
| 覆盖目标 | 6 个跨入口写路径 + 3 个常驻页 |

### G 错误与降级

| 项 | 内容 |
|---|---|
| 检查项 | 断网/无 AI/模型不可用/权限拒绝/DB 损坏/备份损坏/坏行导入/超时；降级矩阵 5×4 逐格且必须标注 |
| 方法 | 读 `degradation_matrix.dart` 20 格并与 docs/41 §10 逐条对照；核对实际调用点（是否有人渲染 notice）；错误分类出口是否泄漏内部信息；权限拒绝文案 |
| 证据 | `EV/code/audit-G-H.md` §2 逐格表、§5 台账 |
| 判据 | 每格有结论；降级有标注（禁止静默降级）；文案可行动 |
| 覆盖目标 | 5×4 = 20 格逐格 |

### H 数据与迁移

| 项 | 内容 |
|---|---|
| 检查项 | schema 守卫；回填；旧备份可恢复；恢复后索引重建；21 列契约；全清覆盖；悬空引用；UTC |
| 方法 | 读迁移分支逐版本核对存在性守卫；核对备份注册表覆盖所有表；构造/读取旧包结构（缺列）核对 `fromJson`；全清参数逐项核对生产装配 |
| 证据 | `EV/code/audit-G-H.md` §3/§4；`EV/edges/` |
| 判据 | 旧包能恢复；CSV 逐字节不变；全清不留用户字节 |
| 覆盖目标 | v3/v5/v27/v28→29 四条迁移；全部表 |

### I 隐私与安全

| 项 | 内容 |
|---|---|
| 检查项 | 出网面只有 AI 出口；Key 在 secure storage 且零日志；敏感信息红线；权限最小化；SQLCipher；相册副本清理；来源与许可标注 |
| 方法 | 全仓出网调用扫描（http/Dio/HttpClient/WebSocket/Uri）；Key 字段与日志扫描；`AndroidManifest` 权限逐项；隐私审计测试实际断言；明文目录清单 |
| 证据 | `EV/code/audit-I-K-L-M-N.md` §2/§3；`EV/docs/licenses.md` |
| 判据 | 审计测试全绿；无明文 Key；无未声明出网 |
| 覆盖目标 | 全部出网调用点；全部权限；全部落盘目录 |

### J 无障碍与适配

| 项 | 内容 |
|---|---|
| 检查项 | 字号 1.0/1.3/2.0；320dp；读屏标签；对比度；触控目标；横屏 |
| 方法 | 测试矩阵映射（`rg "2\.0|320"`）；`semanticLabel` 扫描；对比度复用 B；横屏锁检查 |
| 证据 | `EV/code/audit-B-C-E-J.md` §4/§6 |
| 判据 | 2.0×/320dp 不溢出、不裁字；图标钮有可读标签 |
| 覆盖目标 | 全部主页面 × 320dp/2.0×；主流程图标钮 |

### K 边界与异常输入

| 项 | 内容 |
|---|---|
| 检查项 | 空/超长/特殊字符/emoji；极值/负数/NaN；未来/过去日期；同秒并发；首装/升级/清数据；低内存；损坏输入；超时 |
| 方法 | 读校验代码 + 运行定向探针/测试；每条给「输入/期望/实际/位置」 |
| 证据 | `EV/code/audit-I-K-L-M-N.md` §4（≥20 条）；`EV/edges/*.md` |
| 判据 | ≥20 条各一次，未处理的如实登记 |
| 覆盖目标 | ≥20 条 |

### L AI 交互质量

| 项 | 内容 |
|---|---|
| 检查项 | 协议段完整；信封解析严格；缺实体修复按钮；短名单注入；错误分类与重试；截断如实标注 |
| 方法 | 读协议构建器与解析器；四类 repair 逐个核对入口；短名单门控与体积；错误分类出口；流式结束原因解析 |
| 证据 | `EV/code/audit-I-K-L-M-N.md` §5（L 项）；`EV/code/audit-A-F.md` §3 |
| 判据 | mock 一轮；错误分类不泄漏；截断有标注 |
| 覆盖目标 | 37 条命令 + 4 类 repair + 3 条出口（对话/计划/识餐） |

### M 文档与测试一致性

| 项 | 内容 |
|---|---|
| 检查项 | `docs/21` Key 三方对账；文档 vs 行为；判据有测试；已知偏差已登记 |
| 方法 | 提取 `docs/21` 全部 Key → 代码 Key → 测试断言，三方对账；抽样 10 条文档行为核对代码；`docs/43` 判据指向的测试文件必须存在 |
| 证据 | `EV/docs/key-sync.md`（完整表）；`EV/code/audit-I-K-L-M-N.md` §5 |
| 判据 | 对账全绿；判据文件存在；偏差有登记 |
| 覆盖目标 | `docs/21` Key 100% |

### N 构建与发布

| 项 | 内容 |
|---|---|
| 检查项 | 门禁；APK 与源码同源（aapt2 + sha256）；体积；版本号；许可证；隐私说明 |
| 方法 | `aapt2 dump badging`；`sha256sum`；`unzip -l` 核对随包资产；源码 mtime 与 APK 对比；体积 Top10 |
| 证据 | `EV/docs/apk.md`；`EV/static/` |
| 判据 | aapt2 与 sha256 可复核；版本号与 pubspec 一致 |
| 覆盖目标 | 两个 ABI 包 |

---

## 3 抽样与优先级

| 层 | 模块 | 策略 |
|---|---|---|
| P0 必查（全量） | AI 对话/命令执行、记餐与营养计算、备份/恢复/清空、权限与隐私、菜单搜索+语义、记忆写入与注入 | 全路径 + 失败分支 + 设备帧 |
| P1 抽 30% | 菜单/菜品库、食堂目录、食物库导入、训练计划与会话、饮水/体重/步数 | 主路径 + 一个失败分支 |
| P2 抽 10% | 设置与关于、成就、引导页、图库 | 进入 + 空/错误态 |

**抽样规则**：

1. 每个 P0 模块先列「写路径清单」，全部走一遍；P1 模块按 `RAND()`（文件名字典序每 3 取 1）；
2. 视觉抽样按「主题 × 字号 × 宽度」矩阵取边界组合（浅/深 × 1.0/2.0 × 320/430），中间档靠既有捕获矩阵；
3. 设备场景按「首装 / 升级 / 清数据 / 断网 / 无 AI / 弹层 / 搜索 / 错误态」八类各至少 1 帧；
4. 性能每项 3 次取中位数；环境（设备型号、API、字号、dpr）写进 CSV 表头。

---

## 4 命令清单（可直接复制）

```bash
cd E:/AI/Zcode/projects/localfit-ai/localfit-ai

# 0 基线与静态
python E:/AI/Zcode/tmp/localfit-round7-native-20261014/run.py review-baseline2 gate
E:/AI/toolchains/flutter/bin/dart.bat format --output=none --set-exit-if-changed lib
E:/AI/toolchains/flutter/bin/dart.bat format --output=none --set-exit-if-changed test
E:/AI/toolchains/flutter/bin/flutter.bat analyze --no-pub

# 1 全量测试与跳过清单
E:/AI/toolchains/flutter/bin/flutter.bat test --no-pub --reporter expanded
rg -n "skip:" test/ | sed 's/:.*skip:/ | skip:/' > tmp-skips.txt

# 2 静态扫描
rg -n "Color\(0x" lib/features/*/presentation | wc -l
rg -nP "[\x{1F300}-\x{1FAFF}\x{2600}-\x{27BF}]" lib/
rg -n "showModalBottomSheet" lib/
rg -n "semanticLabel" lib/ | wc -l
rg -n "Duration\(milliseconds" lib/ | wc -l
rg -n "\.repeat\(" lib/
rg -n "disableAnimations|accessibleNavigation" lib/
rg -n "http|Uri\.parse|HttpClient|Dio|WebSocket" lib/ | rg -v "schemas|license" | head -50
rg -n "TextOverflow\.ellipsis" lib/features | wc -l

# 3 性能（每项 3 次）
E:/AI/toolchains/flutter/bin/flutter.bat test --no-pub test/features/nutrition/category_benchmark_test.dart
E:/AI/toolchains/flutter/bin/flutter.bat test --no-pub test/features/nutrition/catalog_search_perf_test.dart
E:/AI/toolchains/flutter/bin/flutter.bat test --no-pub test/features/nutrition/query_benchmark_test.dart
LOCALFIT_CATALOG_PERF=1 E:/AI/toolchains/flutter/bin/flutter.bat test --no-pub test/perf/catalog_real_scale_test.dart

# 4 设备（只动自有 AVD）
export ANDROID_HOME=E:/AI/Codex/android-sdk
$ANDROID_HOME/emulator/emulator.exe -avd LocalFit_API35 -no-snapshot-load &
$ANDROID_HOME/platform-tools/adb.exe wait-for-device
$ANDROID_HOME/platform-tools/adb.exe shell am start -W -n com.localfit.ai/.MainActivity
$ANDROID_HOME/platform-tools/adb.exe shell dumpsys gfxinfo com.localfit.ai
$ANDROID_HOME/platform-tools/adb.exe shell dumpsys meminfo com.localfit.ai
$ANDROID_HOME/platform-tools/adb.exe exec-out screencap -p > EV/device/<scene>.png
$ANDROID_HOME/platform-tools/adb.exe shell uiautomator dump /sdcard/ui.xml && adb pull /sdcard/ui.xml EV/device/<scene>.xml

# 5 发布事实
$ANDROID_HOME/build-tools/35.0.0/aapt2.exe dump badging release/<apk> | head -5
sha256sum release/*.apk
unzip -l release/<arm64>.apk | sort -k1 -n -r | head -12
```

---

## 5 进度与日志

进度戳追加到 `EV/run-log.md`，格式 `时间 | 阶段 | 已完成 | 正在做 | 阻塞`。
阶段边界（S1→S2→S3→S4→S5→S6）各写一次；每批修复后追加门禁标签。

---

## 6 风险与替代证据

| 风险 | 替代证据 | 登记 |
|---|---|---|
| AVD 起不来 / 内存不足 | 先清残留进程与锁重试；仍失败用 widget 测试 + 既有帧，`device: blocked` | run-log |
| 无真实 AI 凭据 | 契约/mock 测试；**不**声称真机 AI 已验证 | `docs/50` |
| 旧备份恢复需构造旧包 | 用当前导出裁剪列模拟（只读，不落库到用户库） | `EV/edges/` |
| 对比度属视觉判断 | 用 WCAG 公式算，标注「数值判定」；主观项标注「主观」 | `EV/code` |
| arm64 真机不可得 | x86_64 模拟器 + 桌面基准；不冒充真机 | `docs/50` |
| 门禁红与本轮无关 | 记录基线失败项 + 文件哈希证明非本轮引入 | run-log |
