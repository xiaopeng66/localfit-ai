# docs/24 — AI 供应商协议支持（Chat Completions / Responses / Anthropic Messages）

> 状态：**normative**（AI 出口的 wire 行为以本文为准；与 docs/07 §4 合同清单、
> docs/08 §3 披露、docs/22 A11 转写段冲突时以本文为准，后两者同步指向本文）。
> 需求（用户原话）：「不能添加 responses 协议支持和 Anthropic 的 messages 协议支持吗？」
> 日期：2026-10-02。schema v17 → **v18**（新增一列，只增不改）。

## 1. 一句话架构

本地约束（HTTPS-only、Key 只进认证头、只发必要数据）与协议无关，**先于任何网络
动作**；协议只决定四件事，且这四件事各只有一处定义：

```
用户在设置里选协议 ──→ AiProviderProtocol（唯一身份）
                              │
                     AiProtocolWire（extension，唯一 wire 表）
                              │  ① 请求路径 ② 请求体形状 ③ 认证头 ④ SSE/响应提取
        ┌──────────────┬──────┴───────┬──────────────┬─────────────┐
     对话服务      工作台 task    2 条 provider   转写服务      transport
     （流式）      capability    直连链路        （协议门）    （非流式提取）
```

**六个 AI 出口**（对话、工作台 6 任务、训练计划直连、拍照识别直连、
语音转写）全部从同一张 wire 表取行为；任何一个出口里再写一遍协议字符串字面量
都算返工。

四条硬规则（违反即返工）：

1. **Chat Completions 的请求体逐字节不变**。egress 评测集用 sha256 钉住了这些
   请求体（`ai_egress_evaluation_test.dart`）；`temperature` 只在该协议上发送，
   既为保持字节一致，也因为 Responses 在推理模型上直接拒绝它。
2. **旧库的 `protocol = NULL` 是「从未选过」，不是「选过 chat」**。迁移不写
   默认值，读取侧回落；「不知道」绝不伪装成显式选择。
3. **协议读不懂就等于没选过**（回落 Chat Completions），绝不猜别的协议——
   猜错会把用户的请求发到错误的端点形状上。
4. **不支持的组合诚实拒绝**（如非 chat 协议 + 语音转写），不发明兼容层。

## 2. 协议身份与持久化（`AiProviderProtocol`）

`lib/features/settings/domain/ai_provider_protocol.dart`：

| 枚举值 | 存储值 | 展示名 | 请求路径 |
|---|---|---|---|
| `chatCompletions` | `chat_completions` | Chat Completions（OpenAI 兼容） | `chat/completions` |
| `responses` | `responses` | Responses（OpenAI /v1/responses） | `responses` |
| `anthropicMessages` | `anthropic_messages` | Messages（Anthropic /v1/messages） | `messages` |

- **存储值是不透明的契约字符串**，与枚举索引解耦（顺序变则语义变＝缺陷，
  有变异红证钉住）。
- `fromStorage(null | '' | 未知)` → `chatCompletions`。
- `requestPath` 不带前导斜杠：baseUrl 已保证以 `/` 结尾（§3）。

**schema v18 迁移**（`app_database.dart`）：`AiProviderConfigs` 新增
`TextColumn protocol => text().nullable()`。迁移块带**两条守卫，缺一不可**：

- 下界 `from >= 2`：v1 及更早的库由 `from < 2` 分支 `createTable` 建表，而
  `createTable` 用的是**当前**表定义（已含 protocol 列），再 `addColumn` 会
  duplicate column（与 v15/v16 同类守卫同理）。
- 存在性守卫（`sqlite_master` 查表）：迁移测试的 v12/v13 fixture 是最小复现，
  根本没建这张表；生产路径（v2+ 真实库）恒有该表。

**两条迁移路径都指向同一列集** `['id','base_url','model','protocol']`（v1 直接
建表建出 4 列；v2..v17 由 addColumn 补到 4 列）——迁移测试两个方向都断言。

配置模型 `AiProviderConfiguration` / `AiProviderSettingsInput` 的 `protocol`
默认 `chatCompletions`＝旧行为；存储层 `save()` 写入 `storageValue`（**不写枚举
索引、不省略该列**，两条都有变异红证）。

## 3. Endpoint 解析与协议尾巴剥离（`OpenAiCompatibleEndpoint`）

本地硬约束不变（先于任何网络动作）：**只接受 https；端口只能 443 或省略**；
拒绝 userinfo / query / fragment / 点段 / 反斜杠 / `%2e`·`%2f`·`%5c`
（编码歧义能把「看起来同源」变成实际不同源）。

v18 新增**协议尾巴剥离**：用户把完整端点粘进来是常态
（`https://host/v1/chat/completions`）。解析时把末尾的**已知协议尾巴**剥掉一次
（大小写不敏感），得到 API 根，再由 `protocol.requestPath` 拼出真正要请求的
路径：

```
输入 https://api.example.com/v1/chat/completions  +  Responses
 → baseUrl  https://api.example.com/v1/
 → requestUri  https://api.example.com/v1/responses
```

- 尾巴表：`chat/completions`、`responses`、`messages`、`completions`、
  `embeddings`、`audio/transcriptions`、`audio/speech`。**只剥最外层一次**，
  不递归（`/v1/messages/messages` 不是合法输入，不猜）。
- 这样用户**切换协议不必改 Base URL**，也不会拼出
  `/v1/chat/completions/chat/completions`。
- 剥尾巴对**所有协议**生效（含默认 chat）；`requestUri` 由
  `protocol.requestPath` 决定，写死 chat 是缺陷（有变异红证）。

## 4. 协议 wire 表（`AiProtocolWire`）

`lib/features/ai/data/ai_protocol_wire.dart`，**extension on AiProviderProtocol**
（不是平行枚举：协议身份只有一个，wire 行为挂在它身上；新增协议时每个
exhaustive switch 都编译报错，逼你补齐每一项能力）。

| 分歧点 | Chat Completions | Responses | Anthropic Messages |
|---|---|---|---|
| 路径 | `chat/completions` | `responses` | `messages` |
| system | `messages[0].role=system` | 顶层 `instructions` | 顶层 `system` |
| 输入键 | `messages` | `input` | `messages` |
| 输出上限 | `max_tokens` | `max_output_tokens` | `max_tokens`（**必填**）|
| `temperature` | 发送（`0`） | **不发** | **不发** |
| 推理开关（2026-10-05，docs/29 §P4）| 关闭推理时发 `thinking: {"type": "disabled"}` | **始终不发** | **始终不发** |
| 认证 | `Authorization: Bearer` | `Authorization: Bearer` | `x-api-key` + `anthropic-version: 2023-06-01` |
| 非流式回复 | `choices[0].message.content` | `output[].content[].text`（`output_text` 兜底）| `content[].text` |
| 流式增量 | `choices[].delta.content` | `response.output_text.delta` | `content_block_delta.delta.text` |
| 流结束 | `[DONE]` 字面量 | `response.completed` | `message_stop` |

三条比表格更细的规范：

- **快照与主 system 的合并**：Chat Completions 发**两条 system 消息**（chat-edit
  协议 + 快照，docs/23 §3）；Responses 与 Anthropic 没有「多条 system」的概念，
  合并成一段（`systemPrompt\n\nsystemContext`）。空串/null 一律不发，
  **绝不用空串占位**。
- **相邻同角色合并（仅 Anthropic）**：协议要求 user/assistant 交替，本地历史里
  失败的助手回复会被排除，可能出现连续两条 user——合并（`\n\n` 连接）后语义
  不变，且避免 400。
- **视觉图片形状**：Chat Completions 用 `image_url` 块（data URL）；Responses
  用 `input_image` 块（`image_url` 字段放 data URL）；Anthropic 用 `image` 块，
  `source` 里放**裸 base64**（不是 data URL）+ `media_type`。
- **响应提取形状不符一律返回 null**（调用方转「供应商返回格式无法识别」），
  **不猜**：宁可报格式错，也不把人肉拼出来的内容当成模型的回答。
  Responses 的提取**优先 `output` 数组**（原始事实），`output_text` 只是兜底
  ——自建网关/中转常只回前者。
- **流结束判别只认自家的类型字符串**：放宽成「别家 type 也认」会让 Anthropic
  的 `message_stop` 提前终结 Responses 流（有双向变异红证）。
- **推理开关（`AiReasoningMode`，docs/29 §P4）**：设置里全局一处，作用于全部
  AI 出口。默认「关闭推理」——Chat Completions 发 `thinking: {"type": "disabled"}`
  （顶层 `enable_thinking: false` 实测 400，不可用）；Responses / Anthropic
  两协议**始终不发**推理字段（未实测，诚实边界）。配套兜底：非流式 `content`
  空而 `reasoning_content` 有货、或整条流只有推理增量时，报可解释错误
  （「模型只返回了推理内容，请在设置里关闭推理或增大输出上限。」）而不是
  「格式无法识别」/静默空气泡——推理型模型把 token 花在 `reasoning_content`
  上是实测行为，不是格式损坏。流式侧 Responses / Anthropic 的推理增量
  检测恒 null（未实现，不算识别失败）。

`authHeaders(apiKey)` 是 **Key 唯一出现的地方**：不进 body、不进日志、不进任何
文案。transcript 的 FormData 里也只有 `model` + `file`。

## 5. 统一错误口径（跨协议）

**不向用户暴露协议细节**：三种协议的所有解析失败共用同一句
「供应商返回格式无法识别。」（`NetworkFailureKind.invalidResponse`），状态码
映射（401/403 → Key 无效，429 → 频繁，5xx → 暂不可用，3xx → 重定向被安全策略
阻止）与协议无关，沿用 transport 既有实现。

协议在**请求上**（`AiTransportRequest.protocol`，默认 chat）而不是 transport
构造器上：协议来自每次请求前才读到的用户配置，而 transport 实例是长期持有的。
认证头同样由调用方按 wire 表注入，transport 只逐字发出、**不做协议猜测**
（忽略 `request.protocol` 按 chat 提取是缺陷，有变异红证）。

流式对话（`OpenAiCompatibleConversationService`）的两个正确性要件：

- **流式 UTF-8 解码 + 行缓冲**：用 `utf8.decoder.bind(stream)`（不是
  `stream.transform`——后者泛型是 `StreamTransformer<Uint8List, String>`，而
  `ResponseBody.stream` 是 `Stream<List<int>>`，会在运行时类型检查上炸）。
  被网络切断的多字节序列保留在解码器内部等下一块接上；**不解析半行**。
- **事件判别**：`data:` 前缀（允许一个空格或不带）→ `[DONE]` 短路 →
  jsonDecode（单条坏 JSON 只跳过那一条）→ `protocol.isStreamEndEvent` →
  `protocol.extractDelta`。CRLF 与 LF 都兼容。

## 6. 转写服务的协议门

> **2026-10-07 P10 状态修订：语音转写整族已删除**（入口、转写服务与其测试一并移除，
> 见 docs/29 §P10 与 docs/08 §4 录音权限注）。本节保留为历史 wire 事实存档——
> 若日后恢复转写，协议门行为以本节为准。

`audio/transcriptions` 是 **OpenAI 兼容面独有的端点**，Responses 与 Anthropic
Messages 都没有对应路由。选了后两者时**不发请求**、直接抛
`NetworkFailure('当前供应商协议不支持语音转写，请改用文字输入。')`——这比去猜
一个 `/v1/messages` 上的多媒体字段更诚实。文字输入始终可用。

## 7. 设置页（用户唯一入口）

> **2026-10-05 P4 状态修订：「我的」页 AI 配置已改为单行入口（`AI 配置 / AI 模型 / 未配置`）+
> 点开配置弹层**（协议下拉 / Base URL / API Key / 推理档「默认 · 关闭推理（更快）」/ 「测试连通性」），
> 页面级「保存配置」按钮不复存在；`ai-config-sheet-error` 仍在弹层内渲染。
> P4 另新增**模型拉取**（`GET /models` 探测）与连通性分档错误映射（401「API Key 无效」/
> 404·503「供应商暂时不可用」）。本节下述弹层规则继续有效，入口形态以本注为准。
> **2026-10-07 P11 补记**：真实端点实测（docs/evidence/2026-10-05-ai-live-endpoint.md）确认
> wire 从不发送 `response_format` ⇒ **prompt 模板是输出契约的唯一载体**——五个工作台模板
> 已逐一枚举全部键/类型/枚举（`promptVersion -2`），详见 docs/29 §P11。

配置弹层新增协议下拉（`Key('ai-protocol')`，三项＝`AiProviderProtocol.values`
的 `label`），切换时用 `setDialogState` **重新校验 Base URL**（因为尾巴剥离的
结果可能改变），保存时随 `AiProviderSettingsInput` 一起落库。说明行写明各协议
的请求路径，并声明「配置仅保存在本机上」。

**保存失败必须画在弹层里**（2026-10-02 模拟器走查抓到的真缺陷，规则见 docs/21
§3.3）：弹层走根导航器、盖住整页，页面级 `AppSnackBar` 会被遮在下面 ⇒ 首次配置
时点「保存」（此时没有 API Key，`LocalAiProviderSettingsStore.save` 抛
`ValidationFailure('首次保存时必须填写 API Key。')`）用户看到的是「点了没反应」，
重启后什么都没存。修法：`_saveConfig` 增加 `onError` 出口，弹层把失败渲染成
`Key('ai-config-sheet-error')`（页面上的「保存配置」按钮不传 `onError`，仍走页面
snackbar）。**同一缺陷类另修 5 处**：训练「开始训练」冲突改为先关弹层再提示、
拍照修正弹层的拒绝原因、草案弹层的保存限制结果与启用结果、规划事实弹层的保存
结果——全部改为弹层内渲染。每条都有回归测试 + 隔离变异红证
（`E:/AI/Zcode/tmp/sheet_error_mutation.py`，6/6 RED）。

## 8. 披露与提示文案（docs/08 §3 同步）

六个 AI 出口的披露文案里的 `'[OI]-compatible chat/completions 主机'` 一律改为
**协议中立**的「设置中的 BYOK AI 供应商主机」（`prompt_catalog.dart` + 5 个
工作台任务 + `workout_plan.dart`）——协议现在是用户可选的。

## 9. 测试矩阵与红证（本切片的硬门槛）

| 面 | 覆盖 |
|---|---|
| v18 迁移 | 旧行保留、`protocol == null`、`fromStorage(null)==chat`、未知值回落、写读往返、`user_version == 18`、两条迁移路径列集一致 |
| wire 表 | 22 条：三协议认证头、请求体形状（含 `max_output_tokens` 的**值落对键**）、Anthropic 合并、视觉形状、非流式提取、跨协议拒绝、增量提取、流结束双向、推理开关（thinking 只在 chat+关闭推理时发 / `extractReasoningDelta` / `reasoningOnlyHint`，docs/29 §P4）|
| 对话服务 | 12 条：三协议的路径/头/体、跨块事件拆分、**跨块多字节 UTF-8**、CRLF、401 错误卫生、推理开关与空回复兜底（不发 thinking / 纯推理流报可解释错误 / 推理+正文混合不误报，docs/29 §P4）|
| endpoint | 10 条：三协议 `requestUri`、尾巴剥离（大小写/多段/只剥一次）、既有安全约束回归 |
| 存储 | 9 条：`storageValue` 契约、未知值回落、协议列写读往返、推理档写读往返（docs/29 §P4）|
| transport | 12 条：按请求协议提取、认证头由调用方注入 |
| 转写 | 非 chat 协议的闸门（不发请求直接拒绝） |
| 浮层内提示（补） | 6 条：AI 配置弹层失败画在弹层内且协议真的落库、训练冲突先关弹层、修正弹层拒绝原因、草案弹层保存限制结果、草案弹层启用结果（含真实条数）、规划事实弹层保存结果 |

**隔离变异红证 23/23 RED**（`tmp/protocol_mutation_final.py`，每条只改一处实现、
跑指定测试文件、要求变红、随即还原并按 sha256 核对）。**浮层内提示另有 6 条**
（`tmp/sheet_error_mutation.py`：3 条失败提示 + 3 条成功提示，含「启用条数差一」
这类证明断言锁的是真实计数的变异），6/6 RED。变异清单即缺陷清单：

认证头退回 Bearer / 丢 `anthropic-version` / `max_output_tokens` 还原 /
`input` 还原 / 丢顶层 `system` / 不合并相邻角色 / 视觉 base64 改 data URL /
Responses 只认 `output_text` / 流结束判别放宽（×2）/ chat 增量读 `message` /
端点尾巴剥离关掉 / 请求路径写死 chat / 未知存储值猜 Responses / 存储值改枚举
索引 / 丢流式 UTF-8 解码 / 只处理带 `type` 的事件 / 转写门移除 / 存储不写协议列 /
迁移写虚假默认值 / transport 忽略请求协议 / task capability 丢认证头 /
vision 请求体退回 chat。

## 10. 连带影响与诚实边界

- **两个直连 provider**（拍照识别、训练计划）与 task capability
  的连带改动：协议感知的端点解析、按 wire 表构建请求体、注入认证头。四处的
  protocol 都必须来自 `configuration.protocol`（任何一处退回硬编码 chat 都有
  变异红证）。
- **本轮不做的**（如实登记，不是漏做）：
  - Responses 的 `reasoning` / `include` 等高级字段：不做，最小可行集。
  - Anthropic 的 `tool_use` / `thinking` 块：解析侧只取文本块，其余跳过。
  - 非 chat 协议的语音转写兼容层：不做（§6 诚实拒绝）。
  - 真机对真实第三方端点的走查：等用户提供 Base URL + Key 后在模拟器/真机
    实测（Key 只进 App 的加密存储，不进日志/截图/文档）。
