# LocalFit AI 2.0 质量与发布门槛

> 本文定义如何证明 2.0 正确、可恢复、可发布。
> 每次实际验证的命令、时间、环境、结果和限制写入 `docs/evidence/`，并在 `STATUS.md` 摘要引用。
> 历史 1.x 结果只在 `docs/history/1.x/` 追溯，不作为当前证据。

## 1. Definition of Done

一个 2.0 切片只有同时满足以下条件才算完成：

- 范围、数据边界和失败回退符合 `GOAL.md` 与 2.0 规范；
- 代码遵守 feature-first 分层，页面不执行 SQL/HTTP；
- 有最小充分单元、数据、widget 或集成测试；
- `dart format`、`flutter analyze`、相关测试通过；
- 涉及数据库有 migration、rollback/保持现状和旧备份测试；
- 涉及 AI 有合同、Prompt、非法响应、取消、超时、未知 ID 和日志隐私测试；
- 涉及菜单有来源、日期、快照、过期、人工修正和导入回滚测试；
- 涉及目录有 manifest、许可证、唯一 ID、营养范围、FTS 和规模基准；
- 涉及 UI 有亮暗色、窄屏、大字体、无障碍和错误/空/离线态验证；
- `STATUS.md` 标记真实状态，证据区分 fresh 与 historical。

## 2. 测试层级

### 单元测试

覆盖纯 Dart 逻辑：

- 单位转换、营养合计、目标缺口和范围；
- 食物名称归一化、alias 匹配、canonical 去重；
- 营养 revision 选择和快照不变性；
- 菜单日期、时区、营业时段、跨午夜窗口和过期；
- daily solver 硬约束、排序、reason code 和无解原因；
- route interval、TTL、取消和来源；
- AI decoder、Prompt projection、allow-list 和字段边界；
- backup KDF、加密、hash 和版本；
- 导入 manifest、hash、唯一 ID、许可证和异常值。

边界必须包含空集合、0、负数、极大值、NaN/Infinity、重复值、超长文本、超数组、时区/DST 和取消。

### 数据库和文件测试

- 每个公开 schema 版本迁移到当前版本；
- 新表和旧表数据保留；
- 菜单 snapshot 原子发布、失败保留旧版本；
- catalog 分片重复导入幂等；
- 导入中断、校验失败、低存储和回滚；
- meal/recipe/daily plan/menu snapshot 不串表；
- 历史营养快照不因 food revision 更新改变；
- `.lfb` 新旧版本导出/恢复和失败保持现状；
- 全部清除删除数据库、媒体、raw files、缓存、临时文件和 Secure Storage 引用；
- CSV/JSON 字段策略和敏感数据预览明确。

### AI Provider 和 Transport

覆盖：

- 原生 JSON Schema、JSON object 和 strict JSON fallback；
- string content、content blocks、native JSON、空 content；
- 非 JSON、Markdown、代码围栏、多个根对象；
- unknown schema、缺字段、空文本、非法枚举；
- 0/负数/非有限值/最大值和数组/文本/响应上限；
- 未知 food/menu/exercise ID；
- HTTPS、非 443、query/fragment/userinfo、路径歧义、重定向和证书；
- header-only Key、Key 不进 body/log；
- 401/403/408/429/5xx、超时、取消和连接失败；
- 不自动重放照片 POST，不丢输入；
- Prompt/contract 版本记录和固定脱敏评测。

自动测试全部使用 fake，不消耗真实 token。真实供应商只做手动 smoke test，且不能把真实健康资料、菜单原文或 Key 写入证据。

### 菜单测试

- 手动、粘贴文本、TXT/CSV/JSON 的有效/空/损坏/超限输入；
- PDF/OCR/URL 适配器的失败和取消；
- 学校/食堂/窗口/日期/时区/跨午夜营业时间；
- 同名菜不同窗口、重复导入、价格缺失、来源过期；
- raw 保留/删除策略；
- AI 解析失败后人工修正；
- evidence 等级和 `matched/estimated/unresolved/expired/closed` 状态；
- 菜单不会直接写 `meals`；
- 快照、备份、恢复和清除。

### Solver 和路线

- 目标存在/缺失、已摄入、超标和估算范围；
- 已知冲突、未知事实、待匹配食物和过期菜单；
- 窗口关闭、无可用时间、路线未知、无候选；
- 排序 reason code 稳定；
- 加入计划不写 consumed meal；
- 记录已吃必须二次确认并使用本地快照；
- 路线取消/超时/过期/来源缺失；
- 精确位置不进日志或 AI 请求。

### Widget/Golden/Accessibility

重点页面：今日决策、AI 工作台、菜单列表/详情、食物库搜索、计划确认、拍照候选和训练执行。

验证：

- empty/loading/error/offline/stale/conflict/needs-confirmation；
- 亮色/暗色、大字体、320dp 窄屏、减弱动画；
- 文字、图标、Semantics 同时表达证据、确认和不可用原因；
- 主按钮可触达区域 ≥44dp；
- 不以颜色单独表达安全或完成状态；
- 结构稳定后再保留少量关键 Golden，避免脆弱截图堆积。

## 3. 性能门槛

在中档 Android 真机、50k/100k 目录和约两年餐食/训练数据下验证：

- 冷启动到可操作首页 < 2.5 秒；
- 今日和计划查询 P95 < 300ms；
- 食物首屏搜索 P95 < 200ms；
- 50k 分片导入不阻塞 UI isolate；
- 大图片处理在后台 isolate/worker；
- 普通滚动无持续全表查询和明显丢帧；
- AI 请求默认有总超时且可取消；
- 无用户动作不持续联网。

如果真机不达标，先记录基准和瓶颈，不先引入无证据的复杂缓存。

## 4. 安全与隐私门槛

发布前必须逐项验证：

- 源码和构建产物无真实 API Key；
- Key 只进 Secure Storage 和 header，不进数据库明文/日志/body；
- 数据库在无正确 SQLCipher key 时 fail closed；
- 图片上传前去 EXIF、压缩并展示披露；
- 菜单原文、学校、地点、行程、food/menu/exercise ID、健康档案和 AI 正文不进普通日志；
- route adapter 不后台定位，精确坐标不长期保存；
- `.lfb` 使用认证加密，错误口令、篡改和损坏不泄露并保持现状；
- 清除全部数据同步删除数据库、媒体、raw files、缓存、临时文件和安全存储引用；
- 权限按需请求，拒绝相机/文件不影响手动记录；
- 商店隐私政策与实际网络/文件/权限行为一致。

## 5. 5 万级目录质量门槛

每个发布 manifest 必须报告：

- canonical、alias、portion、revision、evidence 行数；
- 重复 ID、缺失名称、非法单位、负值、NaN/Infinity；
- 四项宏量完整率；
- 来源/许可证缺失数；
- 中文、别名、品牌和校园高频覆盖；
- FTS 索引 hash 和行数；
- 分片大小、压缩大小、导入耗时和峰值内存。

不允许通过复制同一营养值或重复别名凑数。

## 6. AI 质量评测

建立小而固定的本地脱敏集，覆盖：

- 单品、混合中餐、遮挡、小份、饮料、校园菜名、无菜单和无法判断；
- 合法 JSON、Markdown、空结果、未知 ID、边界数字、内容块和超限响应。

每次 Prompt、模型或 decoder 变化记录：

- schema 通过率；
- 本地候选命中率/未知 ID 拒绝率；
- 估重区间覆盖率（仅作工程评估）；
- 无法判断拒绝率；
- 延迟、响应大小和 token 成本；
- 失败是否保留用户输入。

不得把评测结果表达为医疗精度或减重保证。

## 7. 发布顺序

1. 本地单元/数据库/Widget/AI fake 全绿；
2. `dart format`、`flutter analyze` 和 `tool\verify.bat` 通过；
3. 中档 Android 真机：飞行模式、低存储、权限拒绝、进程杀死、暗色、大字体；
4. SQLCipher、Secure Storage、文件选择器、签名包和迁移/恢复；
5. Android 封闭测试；
6. iOS 真机和 Keychain/文件/SQLCipher 适配；
7. 商店隐私、许可证和第三方来源检查（隐私/权限说明草稿见
   [`08-store-privacy-and-permissions.md`](08-store-privacy-and-permissions.md)，
   第三方来源与许可证清单见 [`THIRD_PARTY_LICENSES.md`](THIRD_PARTY_LICENSES.md)）。

每步真实结果写入 `docs/evidence/`，`STATUS.md` 只保留索引和限制。

## 8. 证据规则

- Evidence 必须包含时间、环境、完整命令/操作、结果、范围、产物和限制；
- `historical/not rerun` 与 fresh evidence 分开；
- 失败命令不能被覆盖或删掉；
- `build/` 生成物不是自动验证证据；
- 不存 API Key、图片、模型正文、菜单原文、健康数据和精确位置；
- 未运行的命令写 `not run`，不能写“预计通过”。
