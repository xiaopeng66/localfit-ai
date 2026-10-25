# LocalFit AI 2.0 路线图

> 本文只描述 2.0 阶段、依赖、交付物和退出条件。
> 当前正在做哪一项只看 `STATUS.md`；1.x 的阶段流水账已归档到 `docs/history/1.x/roadmap.md`。

## 执行方式

- 一次只做一个 active slice；切片 ID 和下一条命令在 `STATUS.md`。
- 阶段完成必须有实际验证证据，历史测试数字不算当前通过。
- 不跨阶段创建没有测试、迁移、隐私策略和回退路径的半成品。
- 每个新增实体都必须同步考虑 migration、backup、restore、clear、export、logging 和 failure rollback。
- AI 生成必须经过严格合同、本地校验和独立确认；AI 不可用时保留本地路径。

## 依赖图

```text
2.0-0 协议与安全
  ↓
2.0-1 食物目录 v2
  ↓
2.0-2 AI 创作工作台
  ↓
2.0-3 校园菜单
  ↓
2.0-4 每日计划 solver
  ↓
2.0-5 路线与可达性
  ↓
2.0-6 UI 2.0 与状态拆分
  ↓
2.0-7 真机、数据质量与发布
```

`2.0-3` 的基础菜单输入可以使用 2.0-2 的 `menu-normalize.v1` fake；`2.0-4` 的离线规则路径不依赖真实 AI 或路线服务。

## 2.0-0：协议和安全冻结

### 目标

把现有两条 AI Provider 的共同 HTTP 安全行为收拢为共享 `AiTransport`，冻结现有 v1 合同并补齐安全边界，为后续菜单和 AI 任务提供统一底座。

### 交付物

- `AiTransport` request/response/failure 最小接口；
- OpenAI-compatible transport：endpoint、header-only Key、HTTPS、禁止重定向、超时、取消、响应上限、状态分类和 content 提取；
- meal/workout adapter；
- `meal-estimate.v1`、`workout-plan.v1` 兼容测试；
- 字段级 0/负数/上限/NaN/Infinity 测试；
- 全部清除对 Secure Storage、临时文件、媒体和缓存的清理设计与测试基座；
- 状态、决策和 evidence 记录。

### 禁止范围

菜单正式表、FTS5、50k 数据、真实学校数据、真实 AI 调用、自动重试和路线。

### 退出条件

现有 AI、备份、迁移、离线餐食和训练测试不回归；共享 transport 失败路径覆盖；`STATUS.md` 记录 fresh verify 证据。

## 2.0-1：50k 食物目录和搜索

### 目标

将当前小规模食物种子升级为可审计、可分片、可分页搜索的 50,000+ canonical food 目录。

### 交付物

- 离线 ETL：normalize、deduplicate、validate、license/evidence；
- canonical foods、aliases、nutrition revisions、portions、evidence；
- manifest：版本、hash、来源、许可证、行数、质量报告；
- SQLite 分片和 FTS5；
- 分批导入、临时表、校验后切换、失败保留旧版本；
- 中文、拼音/英文、品牌、分类和别名搜索；
- top-K 本地 AI 匹配投影；
- 50k/100k 基准。

### 质量门槛

- ≥50,000 去重 canonical rows；
- ≥10,000 条常见中文/校园高频食物经过抽样审计；
- ≥95% 条目具备完整 kcal/protein/carbs/fat 并能参加本地计算；
- 无重复 ID、非法单位、负值、NaN/Infinity 或无许可证来源；
- 首屏搜索 P95 < 200ms，结果分页不超过 50 条；
- 历史餐食快照不受目录升级影响。

## 2.0-2：AI 创作工作台

### 目标

用任务卡和版本化结构化协议承载 AI 创作，不让开放式聊天直接进入数据层。

### 交付物

- capability registry；
- Prompt Catalog 和 input projection；
- `task_id/contract_version/prompt_version`；
- draft lifecycle、validation report、发送披露和独立确认；
- `menu-normalize.v1`、`daily-menu-plan.v1` decoder/fake provider；
- 原生 JSON Schema → JSON object → strict JSON fallback；
- AI 失败、取消、超时、非法 JSON、未知 ID 的可恢复 UI。

### 退出条件

固定脱敏集结构化通过率 ≥99%；未知 ID、越界数字、过大响应和不支持版本均拒绝且不写入正式事实；用户输入不因失败丢失。

## 2.0-3：校园菜单

### 目标

让用户在本地维护学校、食堂、窗口、营业时间和日期菜单，并且能够核对来源与营养证据。

### 交付物

- campus/venue/menu source/snapshot/service/item/match/evidence/import job；
- 粘贴文本、手动录入、TXT/CSV/JSON；
- 原文保留策略、快照 hash、日期、来源、过期和 superseded；
- 菜品去重、窗口和营业时间修正；
- 本地 food alias top-K 匹配和用户确认；
- `matched/estimated/unresolved/expired/closed` 状态；
- 解析失败保留输入、不覆盖有效旧快照。

### 退出条件

有效导入、空/破损/超限输入、重复导入、过期、跨时区/跨午夜窗口、人工修正、备份恢复和清除均有测试；菜单不自动创建餐食。

## 2.0-4：每日菜单计划 solver

### 目标

根据用户今日事实给出可解释的“去哪里、吃什么、吃多少”候选，并且在 AI 不可用时照常运行。

### 交付物

- availability windows；
- daily plans、slots、candidates；
- 菜单/食物统一 candidate contract；
- 目标、已摄入、宏量、过敏、营养证据、营业时间和冲突硬约束；
- 营养偏差、宏量偏差、时间、通勤、偏好和新鲜度排序；
- reason codes、无解原因、手动回退；
- “加入计划”和“记录为已吃”分离。

### 退出条件

本地规则路径可离线执行；未知、过期、过敏冲突、不完整营养、关闭窗口和计划冲突不会误通过；推荐不会直接写 consumed meal。

## 2.0-5：路线和可达性

### 目标

在不引入后台定位的前提下，给出可理解的“去哪里”时间提示。

### 交付物

- 用户命名地点和手动通勤分钟数；
- 单一可取消 route adapter；
- duration range、confidence、source、queried_at、TTL；
- 失败回退手动时间；
- 位置字段白名单日志策略。

### 退出条件

无路线服务仍能看菜单和计划；精确位置不长期保存、不进入 AI payload/普通日志；超时、取消和过期行为可测。

## 2.0-6：UI 2.0 和状态拆分

### 目标

把 2.0 的信息层级落到 `ui设计/pages/*.html` 的设计稿 UI（见 `docs/21`），并让 AI/菜单流程可维护。

### 交付物

- 按 `ui设计/pages/*.html` 重建 7 个页面（今日 / 饮食·记录 / 饮食·菜单 / 拍照识餐 / 训练 / 我的 / AI 对话），规范见 `docs/21`、阶段编排见 `docs/22`；
- 底栏改为 5 槽贴底栏（中间为 AI 对话凸起圆），拍照识餐改为推入式二级页；
- schema 16→17：饮水、体成分、成就、菜品库、心血管处方、识别结果、聊天记录、应用设置共 8 张新表；
- 语音输入（录音 + BYOK 端点转写）与麦克风权限；
- 设计稿未画到的现有功能收进二级入口（可达性逐一验证）；
- 复杂 StatefulWidget 拆为 controller/draft/section/widget；
- 亮暗色、大字号、窄屏、无障碍和减弱动画。

### 退出条件

核心流程真机可操作；未知/待确认不只用颜色表达；AI/菜单/路线不可用时有可行动原因和本地回退；7 个页面完成「结构与设计稿逐节点对应 + 截图并排比对」（`docs/22` §2.4）。

## 2.0-7：发布与数据质量

### 目标

证明 2.0 在真实设备、低存储、迁移、备份、隐私和数据来源方面可发布。

### 交付物

- Android 中档真机性能和签名包测试；
- iOS 真机适配和 SQLCipher/Keychain/文件路径验证；
- migration、旧 `.lfb`、新表导出/恢复/清除；
- 50k/100k benchmark；
- AI 脱敏评测和 Prompt 版本报告；
- 菜单来源/许可证审查；
- 商店隐私政策和权限说明；
- `STATUS.md`/`docs/evidence/` 完整 fresh evidence。

### 退出条件

P0 崩溃和数据损坏为 0；核心旅程通过；签名包复测；真实设备性能达标；隐私声明与网络/存储/日志行为一致。

> **状态（2026-09-16，验收盘点 `docs/evidence/2026-09-16-2.0-acceptance-review.md`）**：
> 本机可做部分全部达成——migration/旧 `.lfb`/新表导出恢复清除（7a/7b）、50k/100k benchmark
> （2.0-1h/1i/1j）、AI 脱敏评测与 Prompt 版本报告（7c）、菜单来源/许可证审查（7d）、隐私
> 说明（7d + `docs/08`）、P0 崩溃与数据损坏为 0 + 核心旅程 + 低存储/进程杀死/飞行模式
> 走查（2.0-6 设备冒烟 + 2.0-7f 模拟器 8 场景 0 FATAL）、隐私声明与行为一致（7d）。
> 退出条件中两项不可在本机达成：**真实设备性能达标**（外部阻塞：无中档 Android 真机）与
> **签名包复测**（分发范畴；用户裁定个人自用不分发，ADR-020 补记——触发分发时先走
> `docs/09` E.2 CFCT 授权/剥离，再做签名与封闭测试）。iOS 同属外部阻塞（`docs/09` D）。

## 阶段交接规则

阶段只有在退出条件全部有证据时才允许进入下一阶段。若验证失败：

- `STATUS.md` 改为 `blocked`；
- 记录失败命令和限制；
- 不用旧测试数字覆盖失败；
- 修复或调整当前切片，不跨去下一个阶段。
