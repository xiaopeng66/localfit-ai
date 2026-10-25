# 低 Token 持续开发规范

本规范服务于 LocalFit AI 2.0 的连续开发。它减少每轮读取和输出范围，但不以节省上下文为由跳过测试、安全、迁移、隐私或真实验证。

## 1. 权威层级

- `STATUS.md`：唯一实时状态、唯一 active slice、唯一当前交接入口。
- `GOAL.md`：2.0 长期目标、硬约束、路线和总验收；不记录当前进度。
- `docs/01-product.md`：2.0 产品范围和用户流程。
- `docs/02-architecture.md`：2.0 分层、架构和隐私边界。
- `docs/03-data-and-contracts.md`：2.0 数据实体、迁移和 AI 合同。
- `docs/04-roadmap.md`：2.0 阶段、依赖和退出条件；不记录聊天流水账。
- `docs/05-quality-and-release.md`：2.0 质量、性能、安全和发布门槛。
- `docs/21-ui-redesign-spec.md`：**UI 唯一依据**（token / 组件 / 逐页规范 / 数据契约 / 测试策略）。
- `docs/22-ui-redesign-refactor-plan.md`：UI 重设计改造方案（现状评估 / 策略 / 阶段编排 / 风险）。
- `docs/23-chat-universal-edit.md`：AI 对话通用编辑（chat-edit.v1 信封 / 命令注册表 / 写库硬门）。
- `docs/24-ai-provider-protocols.md`：**AI 供应商协议三选一**（Chat Completions / Responses / Anthropic Messages 的 wire 表与迁移）。
- `docs/07-localfit-2.0-development-spec.md`：2.0 详细规范契约。
- `docs/DECISIONS.md`：追加式架构和产品决策。
- `docs/evidence/`：实际验证证据；`docs/history/1.x/` 仅作历史追溯。

代码与文档冲突时，先读取当前实现并在 `STATUS.md` 记录 discrepancy，再修正过期文档。不要用聊天记忆或历史路线图猜测进度。

## 2. 新会话首读顺序

每次中断、新开对话或代理接手，严格按以下顺序：

1. 读取 `STATUS.md`。
2. 读取 `GOAL.md`。
3. 读取 `STATUS.md` 的 Active Slice 指定的 `docs/07...` 相关章节。
4. 只读取 Active Slice 直接涉及的源码和测试。
5. 读取相关 `docs/DECISIONS.md` 条目和 `docs/evidence/` 记录。
6. 执行 `STATUS.md` 的 `Next Command`；若发现不一致，先记录而不是静默覆盖。

不要从 `README.md`、`docs/history/1.x/` 或旧截图推断当前状态。

## 3. 每轮工作协议

1. 先明确当前 slice 的目标、in scope、out of scope 和验收标准。
2. 用一次有边界的搜索定位符号；已知路径直接读取，不扫描整个仓库。
3. 只选择一个最小可验收切片；涉及行为变更时先写失败测试，再实现。
4. 只修改完成该切片必需的文件，不顺手重构邻近代码。
5. 在开始、检查点、验证、阻塞和结束时更新 `STATUS.md`。
6. 先运行最窄相关测试，再运行 format、analyze 和阶段级验证。
7. 真实命令、环境、结果、范围、产物和限制写入 `docs/evidence/YYYY-MM-DD-<slice>-<kind>.md`。
8. 只有真实验证完成才把状态写成 `verified`；失败写 `blocked`，未运行写 `not run`。
9. 最终汇报仅包含完成结果、实际改动、验证结果、限制和当前状态。

## 4. 代码与上下文约束

- 文件职责单一；页面不直接执行 SQL 或 HTTP。
- 领域层不依赖 Flutter、Dio 或具体供应商。
- 公共抽象至少有两个真实调用方；首个实现优先简单具体代码。
- AI Prompt、合同、Schema 和种子数据放在独立文件，不塞进大型 UI 文件。
- 生成代码不手改；修改源模型后重新生成。
- 测试使用小型 builder/fixture；大图片和数据集放测试资源。
- 不在对话中复制整份规范；引用文件和章节即可。
- 同一时间只保留一个 active slice，不跨阶段铺开半成品。

## 5. AI 请求和数据边界

- 只发送当次任务需要的最小本地投影和 allow-list。
- API Key 只在 Secure Storage 和 Authorization header；不进 body、日志、证据或备份明文。
- 图片先去 EXIF、压缩并披露；菜单原文、健康资料、学校、地点和模型正文不写普通日志。
- 营养、过敏、价格、库存、营业时间和路线结论在本地重算或由明确来源决定。
- AI 结果永远是可编辑草案；生成和写入是两个独立确认步骤。
- 失败保留用户输入和本地回退；不以正则从自由文本猜测正式事实。
- 对相同图片哈希、Prompt 版本、模型和参数的本地复用必须由用户选择，缓存只在设备内。

## 6. 验证与证据规则

- 证据必须包含 exact command/action、时间、环境、结果、范围、产物和限制。
- `historical / not rerun` 与 fresh evidence 分开记录。
- 不存 API Key、图片、模型原文、菜单原文、健康数据或精确位置。
- 旧测试数字、旧截图、旧 APK 只能引用为历史背景，不能证明当前代码。
- 文档链接、Active Slice、Changed Files 和 Next Command 每次切片边界都要可复核。
- 项目无 Git 元数据时，`STATUS.md` 的 Changed Files 是必填事实记录。

## 7. 会话结束格式

```text
完成：一句话结果。
改动：关键文件与行为。
验证：实际运行的命令及结果；未运行项明确写 not run。
限制：仍未验证或已知风险。
状态：STATUS.md 中的 active slice 和 status。
```

不自动创建提交、不推送、不发布。除非用户明确要求，否则下一轮从 `STATUS.md` 的 Active Slice 和 Next Command 继续。
