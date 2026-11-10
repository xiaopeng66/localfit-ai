# docs/66 — 应用卡片按需生成（内容优先）方案

> 状态：**方案 v2，待用户批准；本文只设计，尚未改代码。**
> 日期：2026-11-06
> 用户原话：
> 「我发送对话或者图片的时候，AI先分析，但不弹出应用卡片，但输出内容卡片的右下角
> 要加一个生成应用卡片的按钮，点击后，根据对话内容生成应用卡片，这样不用每个对话
> 都生成卡片，只有我明确需要的时候主动生成。」
>
> 依据：`docs/23`（chat-edit v1）、当前 `ConversationController` / `AiEnvelopeCompiler`
> 实现、`docs/24`（供应商协议）。本文不改变执行器的写入语义：**卡片仍然只是提议，
> 用户点「应用」才写库**。

---

## 0. 一句话架构

```
正常对话：用户消息 → AI 自然语言回答（不强制 JSON、不自动挂卡）
                                      │
                                      └─ 内容卡右下角「生成应用卡片」
                                                     │ 用户点击
                                                     ▼
                                   强制 JSON 编译器（用户请求 + 最近对话 +
                                   目标回复 + 协议 + 当前快照）
                                                     │
                                                     ▼
                                   严格 decoder → 挂到**同一条助手消息**
                                                     │
                                                     ▼
                                   编辑卡（用户点应用才执行，语义不变）
```

核心变化只有一句：**把「说话」和「出可执行信封」彻底拆成两次生成，第二次由用户点击触发。**

---

## 1. 现状与根因

### 1.1 现在的自动链路

| 步骤 | 现状 | 证据 |
|---|---|---|
| 首轮请求 | 修改请求/照片记餐直接 `sendMessageForcedJson`，首轮就要求模型输出 JSON | `conversation_controller.dart:681-705` |
| 回复完成 | 解析到信封就 `_promoteEditTurn`，自动把回复换成编辑卡 | `conversation_controller.dart:1024-1080` |
| 解析不到 | 自动催信封最多 2 次，产生隐藏补跑气泡；失败再给兜底卡 | `conversation_controller.dart:810-960` |
| UI | `message.isEditProposal` 就直接渲染「气泡 + ChatEditCard」 | `ai_conversation_page.dart:1593-1624` |
| 落库 | 编辑卡把整个信封编码进 `textContent`，重启后还原 | `drift_conversation_message_repository.dart:89-116` |

### 1.2 为什么用户觉得吵

1. **每轮修改/照片都可能自动弹卡**，哪怕用户只是想让 AI 分析、解释、给建议；
2. 模型一旦只回散文，App 会自己补跑、隐藏气泡、再补卡——用户看到的是「AI 自己接话」；
3. 卡片和内容绑定在一起，用户没有「这次先只看内容」的选择；
4. 补信封机制为了兜底，堆了隐藏气泡、重试账本、兜底卡三套状态，维护成本高。

### 1.3 可复用的资产（这次不重造）

- `AiEnvelopeCompiler`：已经能把「用户请求 + 助手回复 + 协议/快照」编译成信封，
  纯文字、强制 JSON、支持取消（`ai_envelope_compiler.dart`、
  `open_ai_compatible_conversation_service.dart:118-192`）。
- `parseChatEditTurn` / `ChatEditTurn`：严格 decoder、结果回写、落库编码都已稳定。
- `ChatEditCard` / `ChatEditCoordinator` / executor：卡片渲染、审查、应用、失败修复全部不动。
- `buildSystemContext`：协议 + 快照的组装已经存在，只是需要拆成「聊天上下文」和
  「编译上下文」两份。

---

## 2. 目标与非目标

### 2.1 目标

1. 正常对话**永远不自动挂编辑卡**，包括修改请求和照片记餐；
2. 今天完成的 AI 内容卡右下角有「生成应用卡片」入口，用户主动点击才编译；
3. 编译结果挂到**同一条助手消息**，不新增气泡、不覆盖原文；
4. 生成失败/没有可执行操作时，给可理解、可重试的行内状态，不显示原始 JSON；
5. 落库后重启仍保持「原文 + 卡片」；旧版本已存在的编辑卡照常显示；
6. 不改 schema、不加第三方依赖、不改 `chat-edit` 信封形状与执行器语义。

### 2.2 非目标（本版不做）

- 不做离线/本地规则把散文硬解析成 37 条命令（只保留编译器）；
- 不把编辑卡改成「自动执行」——仍然必须用户点应用；
- 不重写 37 条命令的注册表/执行器；
- 不做「卡片重新生成/撤销卡片」入口（可作为下一版）；
- 不改图片识别、食物库、菜单等业务逻辑；
- 不在本方案里发版。

### 2.3 备选方案与取舍

| 方案 | 做法 | 为什么不选 |
|---|---|---|
| A 自动卡 + 折叠 | 保持自动弹卡，卡默认折叠 | 仍是每轮自动生成；用户要先看到「这里有一张卡」才折叠，噪音没消失 |
| B 每轮两段生成 | 先内容，再自动编译一张隐藏卡，按钮只负责展开 | 每轮多一次请求/成本；用户没点也生成了卡，违背「按需」 |
| C 首轮仍强制 JSON | 内容从信封的 `reply` 取，按钮只展开 | 模型仍被 JSON 约束，照片/散文场景容易失去自然分析；且信封已生成，按需语义是假的 |
| D 本地散文解析 | 不用 AI，规则抽取食物/克数 | 只覆盖记餐，37 条命令覆盖不了；误抽风险高 |
| **E 本次方案** | 内容纯自然语言；点击后一次强制 JSON 编译 | 用户可控、无自动卡、编译器复用现成能力；代价是点击后多一次请求 |

选 E 的核心理由：**生成时机由用户决定，而不是由模型是否听话决定**。

---

## 3. 交互设计

### 3.1 正常态

```
┌──────────────────────────────────────┐
│ AI 头像   ┌────────────────────────┐  │
│           │ 你说的这餐大概 520 kcal…│  │
│           │ 米饭 150g、鸡胸肉 150g…│  │
│           │        [生成应用卡片]  │  │  ← 气泡内右下角
│           └────────────────────────┘  │
└──────────────────────────────────────┘
```

- 按钮放在 **AI 气泡内部底行、右对齐**（不是整页右侧，也不是独立浮钮），
  视觉上属于内容卡；
- 使用现有 `LfTextButton`（`lf_buttons.dart:824`），图标
  `Icons.auto_awesome_outlined`（与 AI 入口同一套图标语言），文案「生成应用卡片」；
- 触控高度保持 ≥44dp；320dp × 2.0× 字号下允许按钮文字换行/省略，但不能溢出；
- Key：`ai-chat-generate-card-<messageIndex>`（页面）与
  `ai-chat-card-generation-status-<messageIndex>`（状态行）。

### 3.2 点击后

```
气泡原文不动
┌────────────────────────────┐
│ 米饭 150g、鸡胸肉 150g…    │
│              [生成中…]      │
└────────────────────────────┘
              ↓ 编译成功
┌────────────────────────────┐
│ 米饭 150g、鸡胸肉 150g…    │
└────────────────────────────┘
┌─ 编辑卡（同一条消息下面）────┐
│ 待你确认  午餐 · 2 条修改    │
│ …                           │
│ [全部应用]        [忽略]    │
└────────────────────────────┘
```

- **不新增助手消息**；`message.text` 保持原文；
- 卡片出现后按钮消失（消息已经是 `isEditProposal`）；
- 若用户点「忽略」/应用，后续仍走现有卡状态，不改。

### 3.3 按钮出现规则

只对同时满足以下条件的助手消息显示：

| 条件 | 说明 |
|---|---|
| `role == assistant` | 用户消息不给入口 |
| `status == sent` | 流式中、失败气泡不给 |
| `text.trim().isNotEmpty` | 空回复不给 |
| `!isEditProposal` | 已有卡片不再给 |
| 前面至少有一条用户消息 | 避免开场白/引导语下面出现按钮 |
| 消息本地日期 == 今天 | 只给**今天**的内容卡入口；昨天/更早不提供 |
| 服务实现 `AiEnvelopeCompiler`，且 `chatEdit != null` | 不支持编译器/无编辑协调器的嵌入点直接不显示 |

**推荐 v1 显示在「今天的所有已完成内容卡」上**，不是全部历史，也不是仅最新一条：

- 今天早上的回复，下午仍能生成卡片——不会被后来一句闲聊顶掉；
- 目标日期与快照里的「今天」一致，编译器不会把「今晚」解析成错误日期；
- 不显示昨天/更早的入口，避免「旧回复里的今天」与当前快照错位；
- 如果实机觉得今天的历史按钮仍太多，再收窄为「仅最新一条」。

> v1 不给**昨天/更早创建的旧助手消息**显示生成按钮（需按消息日期解析相对时间）；
> 但今天这轮里用户明确要求“记昨天”等非今天日期时，命令日期保留，并按 §5.10
> 在应用前确认。

### 3.4 状态机（单条消息）

| 状态 | 按钮/文案 | 可点 | 说明 |
|---|---|---|---|
| `idle` | 「生成应用卡片」 | 是 | 默认；消息完成且无卡 |
| `generating` | 「生成中…」+ 三点 loader +「取消」 | 生成按钮否；取消可点 | 编译请求进行中 |
| `empty` | 「这条回复没有可应用的操作」+「重新检查」 | 是 | 编译成功但 `rows` 与 `suggestions` 都空 |
| `failed` | 失败原因 +「重试」 | 是 | 网络/超时/非法 JSON/解析失败 |
| `attached` | 无按钮 | — | 消息已是 `editProposal`，卡片接管 |
| 卡片已应用/忽略 | 无按钮 | — | 仍是卡片，不回到内容态 |

> 代码里的枚举只需要 `idle / generating / empty / failed` 四态；
> `attached` 不是枚举值，而是由 `message.isEditProposal` 推导出来的终态。

- `empty` 与 `failed` 都不挂空卡；空卡比没有卡更让人困惑。
- 失败文案用现有 `safeFailureText` 翻成人话；**编译器原始 JSON 永不上屏**。
- 状态是**内存态**，不落库：重启后没有卡的旧消息回到 `idle`，按钮重新出现即可。

---

## 4. 数据流

### 4.1 正常发送（改动后）

```
用户消息
  → 历史（只含 sent 消息）
  → chatContext = 聊天指引 + 数据快照（不含 chat-edit 命令协议）
  → AiConversationService.sendMessage（不 forceJson）
  → 自然语言流式回复
  → 完成：只显示文本；不挂卡、不自动补跑
     （防守：若模型意外回了合法信封，只取其中的 reply 作显示，不挂卡）
```

关键点：**普通对话不再注入命令清单/JSON 协议**，模型没有「必须输出信封」的压力；
数据快照仍保留，用于个性化回答。协议只在编译请求里注入。

### 4.2 点击「生成应用卡片」

```
messageId
  → 取目标助手消息（必须已完成、无卡、本地日期 = 今天）
  → 取该消息前的用户请求（wireText 优先）
  → 取最近对话（最多 6 条 / 按字节裁剪，见 §5.2）
  → 记录目标消息本地日期（今天）
  → 现场构建 editContext = 完整协议 + 当前数据快照
  → AiEnvelopeCompiler.compileEnvelope(
        userText: 用户请求,
        assistantReply: 目标消息原文,
        conversationContext: 最近对话,
        systemContext: editContext,
      )
  → 缓冲输出（不逐字上屏）
  → parseChatEditTurn（严格 decoder）
  → `rows` 非空：丢弃 `suggestions`，把 turn 挂到**同一条消息**
  → `rows` 为空：按 `empty` 展示原因，不挂空卡（即使信封带 suggestions）
  → 异步审查 warnings（现有 _auditProposal）
  → 落库（现有 repository）
```

### 4.3 挂卡与落库的不变式

这是本方案最容易写错的地方，先钉死：

1. `message.text` **永远是原始内容**，生成卡片不改写它；
2. 挂卡时构造：
   ```dart
   ChatEditTurn(
     reply: message.text,       // ← 用原文，不用编译器返回的 reply
     rows: decoded.rows,
     suggestions: const [], // 手动生成路径不保留可直接写库的 suggestions
   )
   ```
3. 消息变成 `kind = editProposal`、`editTurn = 上述 turn`；
4. repository 现有逻辑把 `turn` 编码进 `textContent`，其中 `reply` 就是原文；
   重启后 `parseChatEditTurn` 还原出同样的 `text + editTurn`；
5. 应用/忽略时 `_updateTurn` 会 `msg.copyWith(text: updated.reply)`，仍是原文；
6. **不新增 schema 列，不加 kind 字段**；
7. **目标日期必须钉进命令**，不能靠执行时的“今天”：
   - `weight.log`、`water.add`、`meal.create`、`session.start` 等已带可选
     `localDate` 的命令，挂卡时若模型没给日期，用目标消息的本地日期补上；同时
     **同步改 `row.raw`**（落库编码读的是 `raw`，只改 `command.args` 重启会丢）；
   - 执行器的 `targets.update` 饮水目标分支也按日期写入，但当前注册表缺少该参数；
     给它**向后兼容地增加可选 `localDate` 命令参数**，只在 `waterMl` 非空时钉住
     目标日期。`steps` 目标仍保持当前全局语义，不加日期；旧信封没有该参数时维持
     “执行日”的既有行为；
   - 模型显式给了别的日期（例如用户说“记昨天”）**保留**，不强行改成今天；
   - 给 `ChatEditTurnItem.copyWith` 增加 `raw` 参数，供日期钉死与“选择卡重放”
     同步更新。
8. 执行前如果**本次选中的命令**带有不是今天的 `localDate`，由控制器统一调用页面确认回调，提示「这张卡记录的是 YYYY-MM-DD，应用后会写到那一天」。用户确认才执行；拒绝则卡片原样保留（可再忽略）。此守卫覆盖整卡、分组、旧卡 suggestion 和修复重放，不允许 UI 入口绕过。

> 编译器返回的 `reply` 只在「没有可执行操作」时作为提示语参考，不覆盖内容气泡。

---

## 5. 关键设计决策

### 5.1 普通对话与编译上下文拆分

在 `ChatEditCoordinator` 增加两个入口：

| 方法 | 内容 | 使用方 |
|---|---|---|
| `buildChatContext(...)` | **内容纪律 + 能力边界 + 数据快照**，不含命令清单/JSON 规则 | 正常发送、错误重试、`sendImageBatch`（照片轮也要走新路径，不能漏——`_runRequest` 的 `forceJson` 判定里有 `hasImage`，不改会继续强制 JSON、但新模式又不挂卡，结果照片回复被 `replyTextForDisplay` 整段换成「格式有误」） |
| `buildEditContext(...)` | **完整 chat-edit 协议 + 数据快照**（现有 `buildSystemContext`） | 手动生成卡片 |

`buildChatContext(...)` 必须继续接 `pendingProposal: _latestPendingProposal()`：
否则用户对着上一张待应用卡说“米饭改成 100 克”时，内容 AI 又会回
“等你先应用再说”（2026-10-24 修过的回归）。新模式下也要有一条测试。

聊天指引建议文案（写入 systemContext 开头）：

```
【对话模式】用自然语言回答用户，不要输出 JSON 信封或 JSON 代码围栏。
用户在描述记录/修改时，请在正文里写清可执行的对象与数值
（食物名、克数、餐次、日期、目标值等），但不要声称已经写入。
食量没说就按常见份量估算并写出具体数字，不要只写“一碗”或反问“多少克”。
照片记餐：先列识别到的食物名与估算克数，再给建议。
不要反复反问“要不要生成”；用户需要时会点内容卡右下角的“生成应用卡片”。
```

**不能把协议整段删掉就算完**：协议里有一批规则不是「JSON 格式」，而是
**内容事实纪律**。它们必须压缩后留在聊天侧，否则内容回复本身就会错，编译器
再准也救不回来：

| 必须保留的聊天侧规则 | 不保留会怎样 |
|---|---|
| 不谎报「已记录/已保存」；没卡片就不提「点应用」 | 用户以为已写入，实际什么都没有 |
| 食量/克数没说 ⇒ 按常见份量估算并写出具体数字，不反问 | 内容只有「一碗米饭」，编译器不敢造数 ⇒ 点生成后空卡 |
| 只做用户这句话要求的事，不顺手附送 | 内容多提一项，编译器就多生成一条待应用行 |
| 餐次按用户说的；同名食物合并；用户点到的每样都要列全 | 记错餐次/漏食物 |
| 饮食偏好与忌口是硬约束 | 推荐/记录违忌口食物 |
| 步数是系统读的；「今天走了一万步」不是改步数目标 | 编译器可能把事实写成 `targets.update` |
| 食物来源优先级；今天已有的餐别重复记 | 重复记一餐、用错库 |
| 设置/API Key 永远不能通过对话修改 | 内容承诺改设置，实际没有入口 |

这八条压成一段「内容纪律」（约 1–1.5 KB），**不列 37 条命令、不教 JSON 格式**；
完整命令清单/参数仍只在 `buildEditContext` 里注入。聊天侧再加一句能力边界摘要
（可记录餐食/饮水/体重/目标/训练/食物菜品/食堂/记忆；设置与凭据不可改），
避免内容 AI 承诺 App 根本做不到的事。

**构造失败语义**：现有 loader **段级**失败已经容错（失败段列进「未包含」并
继续），只有整次 `build()` 抛异常时 `ChatEditCoordinator.buildSystemContext`
才返回 null——那时协议也会一起丢。

- `buildChatContext`：**始终返回**「内容纪律 + 能力边界」；快照整体抛错时只省略
  快照段，不返回 null；
- `buildEditContext`：**始终返回**完整协议；同样只省略快照段；
- 实现：coordinator 里写成 `'${renderProtocol(...)}\n\n${trySnapshot()}'`，
  不沿用「整段失败就 null」的旧拼法；
- 这样「快照抖动」不会让编译器变成无协议裸奔；代价只是少了数据定位，卡片可能
  在执行时失败，失败会如实显示。

这样做的收益：

- 模型不再被协议逼着每轮出 JSON，自动弹卡的源头被拔掉；
- 普通对话 token 变少（协议约 6.6k 字不再每轮发送）；
- 编译器仍然拿到完整协议，结构准确率不降；
- 内容回复保留事实纪律，不会为了「去 JSON」把准确性一起删掉。

### 5.2 编译器输入扩展

`AiEnvelopeCompiler.compileEnvelope` 增加可选参数：

```dart
String conversationContext = '',
```

编译器 prompt 增加一段：

```
最近对话（只用于理解“刚才那份/第二项”等指代，不是新的请求）：
<最近 6 条，单条 ≤600 字，总 ≤3000 字>

用户请求：
<该条助手消息之前最近一条用户消息，wireText 优先>

目标助手回复（本地日期：<YYYY-MM-DD>）：
<被点击的那条助手消息全文，≤6000 字>

任务：把目标助手回复中**已经明确提出**的可执行操作转成 chat-edit 信封。
- 只使用目标回复/最近对话中出现过的实体和数字，不新增、不改数、不估算。
- 只抽取**对用户当前请求的直接记录/修改提议**；不要从饮食建议、科普、
  “明天可以吃…”这类推荐里抽取命令。
- 最近对话只用于补齐指代；不能把更早的闲聊当成新的提议。
- 目标回复没有可执行操作 ⇒ edits 为空，reply 说明原因。
- 缺参数时不要猜，也**不要输出 suggestions**：在 reply 里说清缺哪一项。
- **这条覆盖协议规则 0 的“可估算”**：编译器不做份量估算；目标回复没写克数
  就不要补，返回空，不能生成用户没看过的数字。
```

边界：

- 最近对话只取目标消息之前、`status == sent` 的消息；图片消息用「[图片]」占位，
  不重发图片字节；**不把目标回复本身再放进最近对话**（避免重复）。
- 目标回复是主体，最近对话是辅助；超长时先裁最近对话，再裁更早的对话；
  **不静默截断目标回复**——目标回复本身超预算就返回可重试的
  「这条回复太长，无法生成卡片，请精简后再试」。
- 编译请求在点击时**现场构建快照**，不用发送时旧快照。
- **快照检索参数要拆开**：不能把「用户请求 + 目标回复」直接塞进
  `build(userMessage:)`——那个参数同时驱动食物库预检索、菜品推荐意图门控
  （`吃/饭/菜/午餐`一命中就多出最多 30 条候选菜品）和记忆检索，拼长文会
  让编译请求膨胀、把无关菜品塞给编译器。
  - `ChatEditContextBuilder.build` 增加可选 `foodQuery`，**只**给食物库预览用；
  - manual 编译时：`userMessage` 仍传真实用户请求；`foodQuery` 传
    「用户请求 + 目标回复（截断）」；照片轮 caption 为空时才需要靠
    `foodQuery` 找回食物名；
  - 菜品推荐门控与记忆检索继续用真实 `userMessage`，语义不变。
- 默认不注入「上一张待应用卡」；避免用户对今天更早的消息生成卡片时被另一张卡
  干扰。若实测发现重复提议，再按「目标是最新消息时注入 pendingProposal」加回。
- **请求字节预算**：现有服务的 body 闸门（`maxRequestBytes` = 64 KiB）在
  body 构建后检查，已经包含 JSON 转义和 system prompt 包装——**控制器不要
  自己估一个粗略字节数**（会漏 systemPrompt / JSON 转义 / 协议包装）。控制器
  只做一个保守的**目标回复字符上限**（如 6000 字）：超过 ⇒ 直接 `failed`
  （`retryable: false`），不发编译请求。编译器/服务侧的 body 闸门继续兜底；
  两层失败都给同一句人话：「这条回复太长，无法生成卡片，请精简后重试。」
- **上下文失败不丢协议**：见 §5.1；快照失败时仍发送协议 + 目标回复。
- **已知限制：`wireText` 不落库**。同一会话内生成卡片时 `wireText` 优先可用；
  但重启后只剩显示文本，内部 id（如 `[canteen-dish:…]`）丢失。编译器只能靠
  快照段里的候选行重新定位。这可能导致 `canteen.dish.nutrition` 类命令失败。
  **v1 接受**：不为此改 schema；如真机实测反复失败，下一版评估把 `wireText`
  编进 `textContent` 或加独立列。

### 5.2.1 编译协议变体、suggestions 与数字接地

**协议必须有一份编译模式变体**，不能只靠 user prompt 覆盖：

- `ChatEditCommandRegistry.renderProtocol({bool compileMode = false})`：
  - 普通模式保持现状（旧路径不变）；
  - 编译模式**去掉**“食量没说按常见份量估算”“缺信息用 suggestions”等对话型规则；
  - 保留命令清单、id/日期规则、食物来源优先级、忌口等事实规则；
  - 编译模式明确：“目标回复没有写出的数字不要补；缺参数就 edits 空 + reply 说原因”。
- 为什么不能只加一句 prompt：协议作为 system context 注入，和编译 prompt 冲突时
  模型会摇摆；必须在协议源头消掉冲突。

**suggestions 不作为手动卡的写库通道**：

- 现有 `suggestions` 的 args 完整时是**可直接执行**的命令，chip 只显示 label，
  用户看不到克数/参数；点了就写库。手动生成不能再引入这种“无预览写库”。
- 手动编译结果中的 `suggestions` **全部丢弃**；只有 rows 才挂卡。
  - rows 为空 + suggestions 非空 ⇒ 视为 `empty`，显示编译器 reply 的缺信息原因；
  - 旧卡/旧路径的 suggestions 保持不变（本次不改旧行为）。
- 编译器 prompt 明确：“不要输出 suggestions；缺信息就把原因写进 reply”。

**数字接地闸门（本地硬校验）**：

- 先给注册表中的每个数值型写入字段建立显式策略；至少覆盖：
  - `meal.create.items[].grams`、`meal.item.update.grams`、`water.add.amountMl`、
    `weight.log.weightKg`、`targets.update.waterMl/steps`；
  - `set.log.weightKg/reps/rpe`、`plan.entry.add.weekday/sets/reps/weightKg`；
  - `profile.body.update.heightCm/birthYear`、`profile.goal.update.targetWeightKg`；
  - `dish.upsert`、`canteen.dish.nutrition`、`food.update` 的数值字段与份量字段；
  - 注册表中其他命令及嵌套载荷里会落库/执行的数值字段。日期、ID、枚举索引不当作数量接地，分别按日期/目标引用规则校验；新增数值写入字段若没有策略，手动编译默认拒绝挂卡。
- 每个字段的数值都必须在「当前用户请求 + 目标回复 + 仅用于指代消解的相关最近对话」中有可见依据；按数字边界与单位/语义别名匹配（`150` 可匹配 `150g/150 克/150.0`，不能匹配 `1500`；`weekday=1` 可由明确的「周一」接地）。不能只因无关旧消息里出现过同一个数字就通过，数量还必须与同一对象/操作对应；无法保守确认就拒绝整张卡，不静默丢掉某一行。
- 任一数值缺少接地 ⇒ 状态 `empty`，提示「这条回复里有数值没法核对，请让 AI 明确说出对象和具体数值后再试」；不挂卡、不写库。
- 唯一当前例外：`food.create` 的每 100g 营养估算字段可不要求出现在内容原文，但必须在应用前的编辑卡里**完整显示数值与单位**；`servingGrams` 仍须接地。任何新增例外需明确列字段、理由与回归测试，不得按 action 整体放宽。
- 宁可少一张卡，也不生成用户没看过且未在卡片预览中明确展示的数值。

> 这三条是 P0：不做的话，“内容优先”会把“没写克数”变成“编译器偷偷补 150g”，
> 或者通过 suggestions 一键写库，用户完全没预览。

### 5.3 控制器新增状态与 API

```dart
enum CardGenerationPhase { idle, generating, empty, failed }

@immutable
final class CardGenerationState {
  const CardGenerationState(this.phase, {this.message, this.retryable = true});
  final CardGenerationPhase phase;
  final String? message;

  /// false = 这类失败重试也不会变（原文太长 / 跨天）⇒ UI 不显示重试按钮。
  final bool retryable;
}

// ConversationController
final bool manualCardGeneration; // 构造参数，页面/旧路径都要读
bool canGenerateCard(String messageId);
Future<void> generateEditCard(String messageId);
CardGenerationState cardGenerationOf(String messageId);
void cancelCardGeneration(String messageId);
```

`canGenerateCard` 是唯一判据（页面不自己拼条件），内部同时检查：角色、`sent`、
非空、非卡片、**本地日期 = 今天**、前面有用户消息、`manualCardGeneration`、
`chatEdit != null`、服务实现 `AiEnvelopeCompiler`、当前未在生成。页面只调它。

内部：

- `Map<String, CardGenerationState> _cardGeneration = {}`（内存态）；
- `ValueNotifier<Map<String, CardGenerationState>> _cardGenerationNotifier`
  （页面只监听它画按钮）；**不要用主 `notifyListeners()` 通知生成中/失败**，
  否则页面现有的「控制器一响就滚到底」监听会把正在翻旧消息的用户拽走；
  ⚠ 写入时必须**替换整个 Map 实例**（copy-on-write），不能原地改——`ValueNotifier`
  靠 `==` 判等，原地改不会通知；`dispose` 时要 `_cardGenerationNotifier.dispose()`。
- `Set<String> _generatingCardIds = {}` 防双击；
- 页面注入 `confirmEditDates(Set<String> dates)` 回调（类似现有 `editDependencyConfirm`），由控制器在执行前统一调用；新模式下回调缺失时，非今天日期的写入默认拒绝，不能静默放行；
- **新写 `_runManualCompile`，不要复用 `_runCompiler`**：现有 `_runCompiler`
  写 `_pending`、逐片 `_updateAssistantMessage`，会把目标消息原文替换成半截
  JSON，且生成中发新消息会覆盖 `_pending` 导致卡片永不出现。手动路径只用：
  局部 buffer + 局部 subscription + job epoch + 独立取消 token；
- 每条消息一个 `StreamController<void>` 取消令牌；`dispose`/清空历史时取消并清空；
- 取消语义：**先使 epoch 失效，再 `cancelController.add(null)` 发出取消事件、`subscription.cancel()`、close token，最后显式回 `idle`**；仅 `close()` 不够——当前 service 用 `cancelToken.listen((_) => dioCancelToken.cancel())` 监听数据事件，关闭流不等同于取消；完成回调第一行校验 epoch 与“消息仍在列表”，晚到的 onDone 一律丢弃；
- 生成期间**不占用 `_pending`**，也不改 `ConversationState.status`；
  普通聊天可继续发送（两条请求互不改写对方状态）；
- 成功后：主 `_updateState` 只改目标消息（挂卡）+ 日期钉死 + `_persist` +
  `_auditProposal`；同时从 `_cardGeneration` 删除该条；
- **应用日期确认必须由控制器集中守卫**：`applyEdits`（整卡/分组）、`applySuggestion`
  和 `retryEditRowWithReference` 都经过同一私有 preflight；先确定本次实际将执行的
  commands、收集非今天 `localDate`、调用页面注入的确认回调，再改状态/`raw`、落库或
  执行 executor。选卡重放必须先对重写后的 candidate command 确认；拒绝时原失败行
  与数据均不变。确认结果在本次重放链路内复用，不能弹两次。不能只在 UI 的整卡按钮
  前包确认，否则分组、旧卡 suggestion 和修复重放会绕过；新模式下缺确认回调就拒绝
  非今天写入。旧模式回滚维持旧行为。
- 失败/空结果只写 `_cardGenerationNotifier`，不改消息文本、不落库。
- `manualCardGeneration=false` 时 `_runCompiler` 原样保留给旧补跑路径，不重写。

### 5.4 失败与空结果

| 结果 | 处理 |
|---|---|
| 网络/超时/取消 | `failed` + 人话；不挂卡；可重试 |
| 编译器返回非法 JSON / decoder 失败 | `failed`，给「生成失败，请重试」；**不显示 JSON** |
| `rows.isEmpty && suggestions.isEmpty` | `empty`；优先显示编译器 `reply` 的人话原因（如「找不到你说的那条午餐」），为空时用「这条回复没有可应用的操作」；`reply` 先经 `replyTextForDisplay` 清洗并截到 200 字，可再检查 |
| `rows` 有失败行 | 正常挂卡；失败行显示原因/修复按钮（现有卡逻辑） |
| 全部行失败（无 proposed） | 卡头不能显示绿色「已完成」；改为中性「未应用」，`failed` 行不变 |
| 只有 `suggestions` | 手动编译**丢弃 suggestions**，按 `empty` 处理（避免无预览写库）；旧卡/旧路径的 suggestions 原样保留，卡头另修「需要补充信息 / N 个可选项」 |

### 5.5 与正常回复的异常兼容

去掉协议后，模型理论上不会再输出 JSON。但仍要做防守：

1. 正常回复完成后，如果 `chatEdit.decode(text)` 意外成功：
   - **不挂卡**；
   - 用 `turn.reply` 作为气泡文本（而不是把原始 JSON 上屏）；
   - **必须在 `_finalizeAssistantMessage` / `_persist` 之前完成替换**；
     否则 DB 里仍是原始 JSON，重启后 repository 会把它解析成编辑卡，
     用户没点生成却“长出”一张卡；
   - 加一条 repository 回环测试：合法信封 + 新模式 → save/load 后仍是纯文本、
     `editTurn == null`；
2. 如果文本看起来像 JSON 且 decode 失败：
   - 不显示半截 JSON；
   - **按模型分两套文案**：`kMalformedEnvelopeNotice`（现有文案）引用了
     「让 AI 给出可应用的修改」入口，新模式下这个入口不存在——新路径改用
     `kMalformedEnvelopeNoticeManualCard`：「这次回复格式有误，没能整理成内容。
     可以重试，或把要求说得更具体一点。」（旧路径保留原文案，不改既有测试语义）；
   - `replyTextForDisplay` 增加可选参数 `manualCardMode`（默认 false），
     旧调用点行为不变。
3. **内容侧“假完成态”提示**：如果用户这条像修改请求（或带图）且模型回复命中
   `replyClaimsChanges`（「已记录/已添加…」），但这一轮没有卡片：
   - **不自动补跑、不自动挂卡**；
   - 在按钮旁显示一枚中性提示「尚未写入」，让用户知道要主动生成/应用；
   - 这是诚实性保护，不是卡片触发器；不要因此改变消息内容或写入任何数据。

### 5.6 旧机制清理（v2117，不本次施工）

本次只加新路径并保留旧路径；以下清单**留到下一版**，避免“要回滚却已经把
回滚依赖删了”。本次施工只做两件事：新模式下把 `needsEnvelopeRetry` 关掉，
以及每个旧符号保持原样可编译。

- `_runRequest` 里的 `forceJson` / `hasImage` / `sendMessageForcedJson` 分支；
- `_completeReply` 里的 `_promoteEditTurn` 与 `_maybeRetryForEnvelope`；
- `_rerunForEnvelope`、`_runCompiler`（旧的自动补信封编译路径；新路径独立使用 `_runManualCompile`）、`requestEnvelope`；
- `_retryBubbleOrigin`、`_retryRoot`、`_hiddenChainFor`、`_discardHiddenRetry`、
  `_hiddenRetryBubbles`、`_envelopeRetryAttempts`、`_envelopeRetryOffers`、
  `_envelopeRetryDismissed`；
- 页面 `_EnvelopeFallbackCard`、`needsEnvelopeRetry`、隐藏补跑气泡过滤；
  新模式下 `needsEnvelopeRetry` 必须恒为 false，否则会和「生成应用卡片」按钮
  同时出现两套入口；
- `JsonForcedConversationService`：**旧路径保留期间不能删**（`_runRequest` 的
  `forceJson` 还靠它）；等下一版删除旧路径时再一起退役。编译器内部仍用
  `_send(forceJson: true)`，不依赖这个对外接口。
- `decodeProseMealFallback` / `chatEditEnvelopeNudge*` 等只服务于自动补跑的提示，
  一并清理；
- **保留** `looksLikeModificationRequest` / `replyClaimsChanges`：§5.5 的
  「尚未写入」提示还要用它们，不要顺手删掉。

> 删除前先 `grep` 全仓引用；每删一组跑一次定向测试，避免一次性大爆炸。

### 5.7 旧数据与旧卡片

- 旧消息的 `editTurn` 仍由 repository 解析并渲染，不改；
- 旧消息没有卡片的：只有**今天**的会显示「生成应用卡片」；更早的不显示；
- 旧的内存态（隐藏补跑/兜底卡）本来就不落库，升级后自然消失；
- 旧信封格式、`outcomes`、repair 回环全部不变。

### 5.8 前置修复：`dismissed` 与 `raw` 的落库回环

这两条是现有缺陷，不修就会让新卡片“重启后诈尸/回退”，必须先补：

1. `encodeChatEditTurn` 只编码 `applied/failed`，**`dismissed` 丢失**；
   重启后 `_parseRow` 默认恢复 `proposed`，用户忽略过的卡又能再应用。
   - outcomes 增加 `status: "dismissed"`（或等价的 `dismissed: true`），
     `_parseRow` 优先读 `status`，兼容旧 `ok:true/false`；
   - 这是**落库编码**的向后兼容扩展，不是模型 wire 信封。
2. `ChatEditTurnItem.copyWith` 没有 `raw` 参数；日期钉死（§4.3 #7）和
   “选择卡重放”只改 `command`，但 `encodeChatEditTurn` 读的是 `row.raw`，
   重启后回退到旧引用/无日期。
   - 加 `raw` 参数；所有改写 command args 的地方同步更新 raw；
   - 补 repository 真往返测试：生成 → 忽略/重放 → save → loadRecent →
     状态与引用一致。

> 不做这两条，就不能在 §4.3/§8 里声称“重启后原文 + editTurn 原样还原”。

### 5.9 待应用卡摘要必须截断

`ChatEditTurn.reply` 在手动卡片里是**整段原文**，而 `_latestPendingProposal()`
会把它塞进下一轮快照（`PendingProposal.summary`）。不处理会把整段长回复带进
后续每次请求。改为：

- 压平空白后最多 240 字，超出加「…」；
- 摘要为空时用「（上一条待应用卡）」；
- 仍然只列 proposed 行，已应用/已忽略的不进摘要；
- **任何新代码不得把 `turn.reply` 当短摘要用**；要摘要就从 rows 生成或走
  上面的截断函数。旧卡的 `reply` 是信封短句，新卡是整段原文，两种都存在。

### 5.10 日期语义与跨日边界

- 按钮条件用 `formatLocalDate(message.createdAt) == formatLocalDate(clock.nowUtc())`
  判断「今天」；不能用 UTC 日期，否则晚上 8 点后会错。
- 编译器 prompt 明确写目标回复的本地日期；v1 只允许**目标助手消息本身是今天**，
  因而默认/相对「今天」与快照一致。用户在今天这轮明确说“记昨天”等日期时，显式
  `localDate` 仍可保留，但要经应用前确认；这不等于允许从昨天的旧助手消息生成卡。
- 跨零点后，昨天的内容卡不再显示按钮；不会出现「拿昨天的对话记到今天」。
- 点击时记住 `targetLocalDate`；编译完成时如果已经跨日（`targetLocalDate !=
  当前本地日期`），不挂卡，状态 `failed`「跨天了，请重新发起」——避免执行器
  按“今天”写入。
- `assistant.createdAt` 是**发送开始时刻**：23:59 发出、00:00 完成的回复会被
  归到昨天，按钮不显示。这是刻意的保守行为（宁可少一个入口，不写错日期）；
  用户重新问一句即可。
- 页面可见性可能跨零点滞后（没有午夜定时重建）：`generateEditCard` 入口必须
  重新校验日期；不合法时写 `failed`「已跨天，请重新发起」，不能静默无反应。
- **应用时防漂移**：挂卡时把缺省 `localDate` 钉成目标日期（同时改 `raw`），包括
  `targets.update` 中带 `waterMl` 的日期型目标；`steps` 仍是全局目标。应用前由
  控制器检查本次执行命令的 `localDate`，若有日期不是今天，通过页面确认回调说明
  「这张卡记录的是 YYYY-MM-DD，应用后写到那一天」。这样：
  - 23:59 挂卡、00:01 应用 ⇒ 仍写生成当天，不会漂到次日；
  - 挂卡后杀进程、次日再应用 ⇒ 日期在 `raw` 里，仍写生成当天；
  - 用户明确说“记昨天” ⇒ 显式日期保留，确认后写昨天。
- 这条依赖 `ChatEditTurnItem.copyWith(raw:)`；没有它，日期只改内存、
  重启回退，是**假修复**。
- 若以后允许从昨天/更早创建的**历史助手消息**生成卡片：必须把目标日期传给编译器，
  要求所有日期命令显式使用该日期，并在按钮/卡片上显示目标日期；这与「今天的消息
  明确要求记昨天」是两种场景。前者 **v1 不做**，后者按本节规则保留并确认。

---

## 6. UI 落点

### 6.1 气泡

给 `AiMessageBubble` 增加可选 `Widget? footer`（或等价的底部插槽）：

```
Container(
  padding: ...,
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      markdown/text,
      if (footer != null) ...[
        const SizedBox(height: 4),
        Align(alignment: Alignment.centerRight, child: footer),
      ],
    ],
  ),
)
```

- 只在 `ai_conversation_page.dart` 的普通助手消息分支传入按钮；
- 编辑卡消息分支不传（按钮消失）；
- 长按复制仍由外层手势处理，按钮点击优先。

### 6.2 按钮状态

- `CardGenerationState.generating`：**不用 `LfTextButton(busy: true)`**
  （它的 `_lfButtonLabel` 会把 label 替换成三点 loader，用户看不到"生成中…"）。
  改用 `Row(mainAxisSize: min, [AppButtonDotsLoader, Text('生成中…'), LfTextButton('取消', key: '...-cancel')])`
  —— 视觉就是三点 + 短文案 + 取消，320dp × 2.0× 也不挤；
- `failed` (`retryable: true`)：`LfTextButton(label: '重试生成')` + 下方
  `Text` 错误原因（`LfText.micro`, error 色）；
- `failed` (`retryable: false`)：不显示重试按钮，只显示错误文案
  （「这条回复太长…」/「跨天了…」——重试也不能变好，给个假按钮反而误导）；
- `empty`：`LfTextButton(label: '重新检查')` + 下方 muted 提示；
- `idle`：`LfTextButton(label: '生成应用卡片', icon: Icons.auto_awesome_outlined)`；
- 若命中「内容声称已保存但没有卡」（§5.5），在按钮旁加中性小字「尚未写入」，
  不改变按钮行为；仅新模式显示，旧路径不显示。

### 6.3 可访问性

- 按钮语义标签包含「生成应用卡片」；
- busy 时 `liveRegion` 提示「正在生成应用卡片」；
- 状态文本不只靠颜色（有文字）；
- 320dp × 2.0× 不溢出；按钮触控 ≥44dp。

### 6.4 滚动与页面稳定性

聊天页现在监听控制器，**任何状态变化都会 `_scrollToBottom`**。手动生成卡片
如果也走主 `notifyListeners()`，用户正在翻今天早上的消息时点按钮，会被直接
拽到最底部——这是新交互最容易引入的「新 bug」。

处理：

- 生成中/失败/空结果只更新独立的 `cardGenerationNotifier`，不触发主状态通知；
  按钮用 `ListenableBuilder`/`ValueListenableBuilder` 包住，只重建按钮那一小块；
- 挂卡成功时主状态更新，但页面监听改为「消息条数变化 / 发送中」才滚到底，
  单纯的消息内容替换（同一条消息挂卡）不滚；
- `manualCardGeneration=false` 的旧路径保留原来的「任何状态变化都滚到底」，
  不让回滚路径的行为也变；
- 挂卡后用 `Scrollable.ensureVisible` 定位到**目标消息的卡片**，只在卡片
  确实不在视口内时滚动；
- 用户正在翻历史时生成今天更早的卡片，不跳到会话底部；若新卡片超出视口，只最小滚动到目标卡片可见；
- 测试：滚到中间 → 点今天更早消息的生成 → 断言 scroll offset 不被重置；
  生成后卡片可见。

### 6.5 应用前日期确认

- 页面通过 `confirmEditDates` 回调提供确认 UI（key `chat-edit-date-confirm`）；实际命令选择与守卫在控制器，整卡、分组、suggestion 和选卡重放统一经过同一检查；
- 本次选中的命令全部是今天（或没有日期参数）⇒ 直接应用；有非今天日期 ⇒ 弹确认框，文案写清每个目标日期；确认后照常应用，拒绝/回调异常/未接线均不写库；
- 确认只影响“应用”动作，不改变卡片数据；弹框失败或用户拒绝绝不能静默应用。

---

## 7. 施工拆分（建议四批）

| 批次 | 内容 | 主要文件 | 完成判据 |
|---|---|---|---|
| **1** | 上下文拆分 + 正常路径去 JSON + 旧自动路径开关 | `chat_edit_coordinator.dart`、`conversation_controller.dart`、`chat_edit_registry.dart`、`ai_conversation_page.dart`、`app_router.dart`（路由传 `true`；main 不持有 controller） | 修改请求/照片不再首轮强制 JSON；普通消息不自动挂卡；旧卡片测试仍绿 |
| **2** | 编译协议变体 + 手动生成控制器 + 日期/数字接地 | `chat_edit_registry.dart`、`ai_envelope_compiler.dart`、`open_ai_compatible_conversation_service.dart`、`conversation_controller.dart`、`chat_edit_turn.dart` | `targets.update` 为水目标新增可选 `localDate`；`generateEditCard` 单测：同消息挂卡、原文不变（含水目标日期钉死）、数字接地、无 suggestions 写库、所有写入口日期确认、取消、失败/空结果、落库回环 |
| **3** | 内容卡按钮与状态 UI | `lf_chat_bubbles.dart`、`ai_conversation_page.dart`、`chat_edit_card.dart` | 按钮出现规则（含今天）、busy/empty/failed、同消息卡片、suggestions-only 卡头、滚动隔离、320×2 实帧 |
| **4** | 新路径测试、文档与实帧（**不删旧路径**） | 控制器/页面/测试/`docs/23`/`docs/INDEX`/`STATUS` | 全量门禁 + release + format + analyze；旧路径保持 2115 行为；清理清单登记到 v2117 |

施工纪律沿用本仓：先红后绿、变异验证、实帧逐张看、连带红立刻修、临时文件只进
`E:/AI/Zcode/tmp/<context>/` 并清空。

---

## 8. 测试矩阵（施工时照此建）

### 8.1 控制器（核心）

新增 `test/features/ai_conversation/manual_card_generation_test.dart`：

1. 修改请求完成 → **不自动挂卡**，消息仍是纯文本；
2. 照片请求完成 → **不自动挂卡**；
3. 点生成 → 调用编译器一次，参数含目标回复 + 最近对话 + 完整协议快照；
4. 编译器返回 2 条 `meal.create` → 挂到**原消息**；`messages.length` 不变；
5. 挂卡后 `message.text` 与生成前逐字一致；
6. 落库后再 `loadRecent` → 原文 + 卡片都在；按钮不出现；
7. 编译器返回空信封 → 不进 `editProposal`，状态 `empty`，不显示卡片；
8. 编译器抛网络错 → 状态 `failed`，原文不变，可重试；
9. 非法 JSON → `failed`，不显示 JSON；
10. 双击生成 → 只调用一次编译器；
11. 已是编辑卡/流式中/错误消息/非今天/无前置用户消息 → 不生成；
12. 旧版本落库的编辑卡 → 照常加载/应用/忽略；
13. 生成卡片后 `turn.reply == 原文`；应用/忽略/加警告后仍是原文；
14. 超长原文（> 6000 字）→ 控制器直接 `failed`（`retryable: false`），不发编译请求；快照/协议整体仍超 body 闸门 → 服务抛 `ValidationFailure` → 控制器翻译成人话；
15. 上下文构建抛错 → 编译仍然带完整协议（快照可缺）；普通聊天仍带内容纪律；
16. `PendingProposal.summary` 为 240 字以内且压平空白；
17. 点击时是今天、编译完成时已跨日 → `failed`，不挂卡、不写入；
18. 目标回复没有克数 → 编译器不得估算；数字接地闸门拒绝挂卡。并覆盖 `targets.update`、`set.log`、`plan.entry.add`、`profile.*` 等全部数值写入字段：数值不在相关可见文字/语义别名里、只在无关旧消息里出现或字段无策略 ⇒ 整张卡 `empty`；`food.create` 营养字段是唯一例外，须完整显示在卡片预览中，`servingGrams` 仍须接地；
19. 编译器返回带 `grams/amountMl/weightKg` 的 suggestions → 手动模式丢弃，
    不出现可一键写库的 chip；
20. 相关食材/操作旁明确出现“150g” → 接地通过；“1500g”不能被 `150` 误匹配；同一数字只出现在无关对象或不相关历史对话里 → 不通过；`weekday=1` 可由明确的「周一」别名接地；
21. 纯饮食建议/科普（“明天可以吃…”）→ 不生成记录命令；
22. `manualCardGeneration=false`：旧自动弹卡/补跑仍工作，且不显示新按钮
    （回滚路径冒烟）；
23. 23:59 生成 → 时钟跳到次日 → 经日期确认再应用：`meal.create` / `water.add` / `weight.log` / `session.start` 与 `targets.update` 的 `waterMl` 仍写**生成当天**；`targets.update.steps` 保持全局语义；
24. 生成后重启（`loadRecent`）→ 应用：日期仍来自 `raw`，不漂移；
25. 模型显式给 `localDate=昨天` → 保留；`applyEdits` 与旧卡的 `applySuggestion` 执行前均经过日期确认回调；拒绝/未接线不写库，确认后写入指定日期；选卡重放后重试也不能绕过此守卫；
26. 忽略卡片 → save → loadRecent：仍是 `dismissed`，不会复活成 `proposed`；
27. 选择卡重放改写引用 → save → loadRecent：`raw` 与 `command` 都是新引用；
28. 生成中点取消 → 先失效 epoch 并向 `cancelToken` 发取消事件，再取消订阅、关闭 token、回 idle；fake 编译器即使随后 emit 完整信封也不挂卡、不落库；
29. 生成期间发新消息 → 新回复正常，旧目标消息不被 JSON 覆盖，卡片仍能完成；
30. 清空历史时正在生成 → 取消，完成后不把已删消息写回。

### 8.2 上下文

1. 普通发送 `systemContext` 含内容纪律 + 能力边界 + 快照，**不含**命令清单/JSON 协议；
   至少断言「不谎报已保存」「按常见份量估算」「步数不是目标」「忌口硬约束」
   四条关键短语存在；
2. 生成卡片时 `systemContext` 含**编译协议变体** + 快照；该变体不含
   「按常见份量估算」「用 suggestions」的字样，但保留命令清单；
3. 最近对话最多 6 条、单条/总长有上限；不含图片字节；不重复目标回复；
4. 超长时先裁最近对话；目标回复本身超预算则失败，不静默截断；
5. 快照构建抛错：普通发送仍有内容纪律；生成卡片仍有完整协议；
6. 服务对最终 UTF-8 JSON body（含转义与 system prompt 包装）执行 64 KiB 闸门；控制器不做粗略字节估算；覆盖闸门内放行、超限抛 `ValidationFailure` 并翻译成人话；
7. 内容纪律段长度 ≤2 KB，且不出现 `meal.create` / `"edits"` 这类命令/JSON 字样
   （防止协议又被整段带回来）；
8. 照片轮 caption 为空时，`foodQuery` 含目标回复里的食物名，但菜品推荐
   门控/记忆检索仍按真实用户请求；目标回复不会凭空触发 30 条候选菜。
9. 新模式的普通发送仍注入 `pendingProposal`（上一张待应用卡）——
   否则用户对上一张卡说「米饭改成 100 克」时，内容 AI 又会回
   「等你先应用再说」；断言 `systemContext` 含「上一轮我对用户说的话」段。

### 8.3 UI

`ai_conversation_page_test.dart` 迁移/新增：

1. 完成的助手文本下出现 `ai-chat-generate-card-<n>`；
2. 流式/错误/编辑卡消息没有该按钮；
3. 点击 → busy；成功 → 同一条消息下面出现卡，不新增气泡；
4. 失败 → 行内错误 + 重试；空结果 → 行内提示；
5. 320dp × 2.0× 无 overflow；
6. 长按复制不被按钮破坏；按钮点击不被气泡长按手势吞掉；
7. 昨天/更早的助手消息没有按钮；跨零点后页面重建时按钮消失；若页面尚未重建，点击回调仍拒绝生成（§5.10）；
8. 在历史中间生成今天更早的卡片 → 不跳到会话底部；仅必要时最小滚动到目标卡片可见；
9. 旧路径/既有数据中的 suggestions-only 卡：卡头是「需要补充信息 / N 个可选项」，
   不是「这次修改的结果」，且不出现「全部应用」；手动生成路径则丢弃 suggestions 并进入 `empty`；
10. 生成中点「取消」→ 回 idle，原文不变，之后可重新生成；
11. 修改请求 + 内容声称「已记录」但无卡 → 按钮旁出现「尚未写入」，
    不自动挂卡、不自动补跑；
12. 新模式下旧的 `_EnvelopeFallbackCard` 不出现（不能和生成按钮同时显示）；
13. 卡片含非今天日期 → 整卡/分组应用，以及旧卡 suggestion 或选卡重放执行，都经控制器统一调 `confirmEditDates` 并弹 `chat-edit-date-confirm`；拒绝/未接线不写库。

### 8.4 需要迁移/退役的旧断言

| 文件 | 处理 |
|---|---|
| `conversation_controller_test.dart` | **旧用例全部保留**（默认 `manualCardGeneration=false`，继续验证 2115 行为）；新路径另开文件，构造时显式 `true` |
| `_CompilingService`（同文件 fake） | `compileEnvelope` 加 `conversationContext` 后必须补参数，否则整套测试编译失败；列进批次 2 的第一件事 |
| `ai_conversation_page_test.dart` | 旧断言保留；新路径测试显式传 `manualCardGeneration: true`，发送后点按钮再断言卡片 |
| `open_ai_compatible_conversation_service_test.dart` | `sendMessageForcedJson` 用例**保留**（旧路径还在）；新增“普通 sendMessage 不带 response_format” |
| `test/features/ai_conversation/domain/chat_edit/chat_edit_intent_test.dart` | 路径修正；旧路径还用它，**本次不删** |
| `test/round7_ai_capture_test.dart` | 仍依赖“发送后自动出卡”，随旧路径保留；新路径另加实帧，不改旧 capture |
| `test/ai_live/*` | 新路径评估脚本要从“发送后直接判信封”改成“内容完成后调用编译器”；旧脚本保留用于回归 |
| `drift_conversation_message_repository_test.dart` | 新增 dismissed/raw 真往返用例（§5.8） |

> 本次原则：**旧测试不动、旧路径不删**；新路径新增测试。只有 v2117 删旧路径时
> 才迁移/退役旧断言。

### 8.5 验收门禁

```bash
flutter test --exclude-tags capture test/app test/features   # 全绿
flutter test test/release                                    # +18
dart format --output=none --set-exit-if-changed lib test tool
flutter analyze
python E:/AI/Zcode/scripts/check-encoding.py
```

视觉实帧：390dp 正常态、320dp×2.0×、生成中、空结果、失败、生成后的卡；归档
`docs/evidence/<日期>-manual-card/frames/`。

---

## 9. 风险与对策

| 风险 | 影响 | 对策 |
|---|---|---|
| 内容回复没有写克数/餐次，编译器不敢补 | 点生成后空结果 | 聊天指引要求写清数值；数字接地闸门拒绝无数字挂卡；行内提示「再让 AI 说清克数/餐次」 |
| 照片回复只有模糊描述 | 照片轮生成失败 | 保留原文；提示用户让 AI 补充；下一版可评估「编译时附带图片」但会重发图片、成本高 |
| 模型仍然输出 JSON | 原始 JSON 上屏/误挂卡 | 普通上下文去掉协议；完成时 decode 只取 reply，不挂卡；非法 JSON 给人话错误 |
| 多一次请求的延迟/成本 | 点击后等待 | 只按需触发；loading 状态；可取消；普通对话反而少了协议 token |
| 生成期间用户继续发消息 | 状态竞争 | 生成不占 `_pending`；只改目标消息；双击守卫；dispose 取消 |
| 旧自动重试机制删除带来回归 | 核心对话路径 | 双路径保留一个版本（见 §10），旧测试继续跑；下一版再删 |
| 内容回复丢了协议里的**事实纪律** | 记错餐次/谎报已保存/把步数事实当目标 | 聊天侧保留 8 条压缩纪律（§5.1），不是把协议删光了事 |
| 跨日/旧消息把「今天」记错 | 昨天聊天生成今天的记录 | v1 只给**今天**的内容卡按钮；跨日先隐藏（§5.10） |
| 生成状态触发全局滚到底 | 翻历史时被拽走 | 生成状态独立 notifier；挂卡才用 ensureVisible（§6.4） |
| 待应用卡摘要是整段长文 | 后续每轮请求膨胀 | `_latestPendingProposal` 压平并截 240 字（§5.9） |
| 原文+快照超 64 KiB | 供应商 400 / 点生成失败 | 控制器目标回复字符上限 → `retryable: false`；服务 body 闸门精确兜底；两层同一句人话（§5.2） |
| 落库后原文丢失 | 重启变样 | 钉死 `turn.reply = 原 message.text`；repository round-trip 测试 |
| 测试迁移工作量大 | 施工周期 | 先改控制器语义测试，再改页面测试；直接构造卡片的测试不受影响 |

### 9.1 施工防回归红线（每条都要有测试）

1. **不自动挂卡**：修改请求/照片正常回复永远不出现 `editProposal`；
2. **不重复入口**：新模式下 `needsEnvelopeRetry` 为 false，不出现旧兜底卡；
3. **不改原文**：挂卡/应用/忽略/加审查警告后，`message.text` 逐字不变；
4. **不丢卡片**：apply/dismiss/repair/suggestion 四条旧链路全部复跑；
5. **不写错日期**：只对今天创建的助手消息开放入口；点击/编译完成跨日即拒绝；显式非今天目标日期保留并经统一确认，目标日期写入命令避免漂移；
6. **不滚错位置**：生成状态不触发全局滚底；挂卡后只 ensureVisible 目标；
7. **不撑爆请求**：控制器对目标回复超长直接失败、不静默截断；服务对最终 UTF-8 JSON body 执行 64 KiB 闸门并翻译成人话；
8. **不丢协议**：快照构建失败时，编译上下文仍有完整协议；
9. **不泄 JSON**：非法编译输出/意外信封都不把原文 JSON 上屏；
10. **不挤爆窄屏**：320dp × 2.0×、按钮 + 长原文不 overflow。

---

## 10. 发布与回滚

建议 **保留一个版本的旧路径**，用构造参数切换：

```dart
// 页面参数默认 false；路由构建页面时显式打开
AiConversationPage(
  ...
  manualCardGeneration: true, // 新路径；false = 现有自动弹卡行为
)

// 页面 initState：
_controller = ConversationController(
  widget.service,
  manualCardGeneration: widget.manualCardGeneration,
  ...
);
```

- 参数**默认 `false`**：既有页面测试、未接线嵌入点行为完全不变；
  `app_router.dart` 显式传 `true`，避免“升级后所有旧测试一起红”；
- 加一个路由/页面构建测试，断言线上入口确实拿到 `true`（防“测试全绿、
  线上仍走旧路径”）；
- `false` 时继续使用现有 `buildSystemContext` + 自动弹卡/补跑链路，行为与 2115 一致；
- 旧路径只保留一个版本，下一版删除自动补跑/隐藏气泡/兜底卡，并把默认改为 `true`；
- 新路径不改变 `ChatEditCard`/executor/落库格式，回滚不会产生数据不兼容；
- 版本号建议施工完成后 bump 到 2116；**是否发布另行确认**。

---

## 11. 需要用户拍板（推荐项已标）

| 问题 | 选项 | 推荐 |
|---|---|---|
| 按钮出现范围 | A 今天的全部内容卡 / B 仅最新一条 / C 全部历史（需目标日期解析） | **A**（今天内可回看；跨日先不做，避免日期错位；嫌多再收窄到 B） |
| 空结果 | A 行内提示 + 重新检查 / B 弹一张空卡 | **A**（空卡更困惑） |
| 旧自动补信封机制 | A 保留一个版本再删 / B 本次直接删 | **A**（AI 对话是核心路径，留回滚） |
| 生成时能否继续发消息 | A 可以（独立请求） / B 锁定输入 | **A**（编译不占 `_pending`，互不改写） |
| 编译器上下文 | A 目标回复 + 最近 6 条 / B 只目标回复 | **A**（支持“刚才那份”指代） |
| 照片轮编译 | A 只用文字回复 / B 编译时重发图片 | **A**（成本/兼容性；失败再让 AI 说清） |

---

## 12. 验收清单（Definition of Done）

- [ ] 修改请求/照片轮正常回复**不自动出卡**；
- [ ] 内容卡右下角有「生成应用卡片」，点击后同一条消息下出卡，不新增气泡；
- [ ] **只有今天**的内容卡有按钮；昨天/更早没有，跨零点自然失效；
- [ ] 生成后原文逐字不变，重启后仍是原文 + 卡；
- [ ] 空结果/失败/非法 JSON 均有人话状态，不显示原始 JSON，不挂空卡；
- [ ] 已有卡片的旧消息照常应用/忽略/显示警告；
- [ ] 普通发送注入**内容纪律 + 能力边界 + 快照**（不注入命令协议）；
      编译请求注入**完整协议 + 最新快照**；快照失败时协议不丢；
- [ ] 双击/重复点击只跑一次；取消/dispose 不悬挂；
- [ ] 待应用卡摘要 ≤240 字；服务对最终 UTF-8 JSON 请求体（含转义/system prompt）执行 64 KiB 闸门，超限以人话失败；控制器仅对目标回复做字符上限保护；
- [ ] 滚到历史中间生成卡片不会被拽到底部；
- [ ] 320dp × 2.0× 不溢出，按钮触控 ≥44dp；
- [ ] 全量测试、release、format、analyze、encoding 全绿；
- [ ] 实帧归档并逐张看过；
- [ ] 文档更新：`docs/23`（正常对话/编译两段、**手动卡的 `reply` = 原文**）、
      `docs/24`（编译器上下文）、`docs/INDEX`、`STATUS`；
      如果采用双路径，注明删除旧路径的下一版计划。
