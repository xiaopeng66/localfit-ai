# LocalFit AI — UI 重设计规范（normative）

> **状态**：生效中。本文是 LocalFit AI 视觉与交互的**唯一依据**。
> **视觉源**：`ui设计/pages/*.html`（7 个文件，2026-09-23 定稿）；**2026-10-14 起目标视觉由 §0 的 Round7 A 完整主稿接管**
> **生效日期**：2026-09-27
> **替代**：此前所有 UI 规范（方案 A「薄荷奶油」、薄荷奶油 2.0、旧布局细化、旧 IA 重设计、旧完整规范、旧设计系统、旧 HTML→Flutter 迁移方案）
> **已删除**（2026-09-28）：旧规范不再以任何形式留在仓库内。仓库内**不存在**旧视觉的可读来源——本设计稿是唯一依据。

---

## §0 Round7 A 接管（2026-10-14 生效）

> **用户 2026-10-14 明确选定 [`design/round7`](../design/round7/README.md) 的 A 完整主稿**（`index.html`），作为本轮及此后原生 UI 的**目标视觉唯一依据**；B/C 仅版式参考。实施按 [`docs/33`](33-round7-native-ui-migration-guide.md) 阶段 0–7 自共享层到全部页面逐片推进，进度以 [`STATUS.md`](../STATUS.md) 与 [本轮实施记录](evidence/2026-10-14-round7-native-implementation.md) 为准。

### 0.1 A 的权威读法（有效层叠）

- 以三层 CSS 的**有效层叠**为准：`styles.css` → `refinement.css` → `polish.css`（`design/round7/index.html:9-11` 的加载序，同特异性后出者胜）。
- 深色主题 = `html[data-theme="dark"]` 覆盖（选择器特异性高于 `:root`，其值不得被任何后出的 `:root` 覆盖回去）。
- 本节取值均由 `test/app/design/design_source_parity_test.dart` 的 `_Round7Source` 按上述规则解析对账（层叠/特异性、语义角色、几何三组断言）。

### 0.2 A 有效值（与本文其他小节或 `ui设计/pages` 冲突时，以本表为准）

| 角色 | 浅色 | 深色 |
|---|---|---|
| 页面底 `--bg` | `#F7F9F8` | `#0F1412` |
| 卡面 `--card` | `#FFFFFF` | `#171E1A` |
| 正文 `--fg` | `#1A201D` | `#DDE5E1` |
| 次文 `--muted`（polish 覆盖 styles） | `#5C7067` | `#8FA09A` |
| 品牌 `--brand` | `#2FBE8F` | `#4ED9A6` |
| 强调文字 `--brand-strong` | `#187653` | `#4ED9A6` |
| 浅品牌底 `--brand-soft` | `#ECFBF5` | `#203C30` |
| 轨迹 `--track` | `#EFF3F1` | `#26332C` |
| 描边 `--border` | `#DDE5E1` | `#2A342F` |

几何与组件角色（A 有效值，覆盖旧稿对应项）：标准卡 R16、动作卡特例 R14、按钮/输入 R12、弹层顶角 R24、弹层把手 32×4；主按钮最小高 44、`--brand` 底、**深墨字 `#10271D`**、无渐变无彩色阴影；卡片阴影浅色 `0 1px 3px #1A201D05`、深色无阴影且留 `--border` 描边；输入常态 `--bg` 底 + 1dp `--border` 描边、聚焦 2dp `--brand-strong`；底栏栏体恒 64、中央凸起 = 46 圆 + 5dp `--card` 描边（56 盒）、`--brand` 实心底 + 深色 sparkles、选中态（含中央槽）`--brand-strong` + w600。

### 0.3 接管规则

1. 本文其他小节与 `ui设计/pages/*.html` 中凡与本节冲突的**视觉值**，以 Round7 A 为准；旧页面 HTML 在对应页面完成迁移前仍是既有测试的设计输入，**逐页随 docs/33 阶段迁移**，不做一次性替换。
2. 业务行为、测试 Key、路由、持久化、AI 协议与权限**不因本接管改变**；本接管只覆盖视觉与呈现层，行为保护面见 docs/33。
3. 新页面/新组件一律按本节取值；尚未迁移页面内的旧值随其所属阶段更新，不为统一而提前改动。

---

## §1 文档地位与冲突裁决

### 1.1 优先级顺序

出现任何视觉或交互分歧时，按以下顺序裁决，**上位覆盖下位**：

1. `ui设计/pages/*.html` 的实际 DOM 结构与 class —— 设计源，不可推翻
2. 本文 —— 设计源在 Flutter 里的规范译法；HTML 存在歧义或不可直接翻译时以本文为准
3. `docs/01`~`docs/05`、`docs/07`~`docs/09` —— 产品、架构、数据、隐私、发布约束

**Round7 增量（2026-10-14 起）**：上述序列是 2026-09-27 的历史裁决；自 §0 生效后，**目标视觉**以 Round7 A 为准。当 A 与第 1/2 档冲突时，按「已授权的视觉迁移」处理：在 docs/33 对应阶段迁移该页面，同阶段同步更新本文相应小节、`docs/21` 相关表格与测试 pin（迁移处留 A 出处注释），禁止在阶段外提前替换或批量改测试。

旧 UI 规范**已于 2026-09-28 从仓库删除**（见 `docs/DECISIONS.md` ADR-024），不构成本序列的任何一档，也不保留任何旧设定的兼容分支。

### 1.2 「抛弃」的确切含义

用户裁决：**HTML 未画到的功能不是「冲突」，只是「设计稿没画到」**。两者处理方式不同：

| 情形 | 处理 |
|---|---|
| **冲突**（HTML 画了 A，旧实现是 B） | **抛弃 B**，按 HTML 实现 A。不留开关、不留兼容层 |
| **设计稿未画到**（功能存在但 HTML 无对应） | **保留数据与逻辑**，UI 上收进二级入口。禁止删除表、仓储、用例、测试 |

### 1.3 本文的可验证性

本文每条规范都应可被以下之一验证：单元/组件测试、`flutter analyze`、模拟器截图对比 `ui设计/pages/*.html`。**不可验证的形容词不算规范**（如"美观""自然""协调"），出现即应改写为可量化条款。

---

## §2 设计 token

> 所有值直接取自 `ui设计/pages/*.html` 的 `:root` 与 `html.dark` 块，**逐字抄录，不得近似**。

### 2.1 色板 — 亮色

#### 2.1.1 品牌 ramp（mint）

| 档位 | 值 | 用途 |
|---|---|---|
| mint-50 | `#ECFBF5` | 徽章底、chip 底（浅） |
| mint-100 | `#D2F5E6` | 头像底、时间线节点填充 |
| mint-200 | `#A8EBCF` | chip 边框、hero 渐变中段 |
| mint-300 | `#6FDBB0` | 虚线按钮边框 |
| mint-400 | `#4ED9A6` | 暗色锚点；亮色下用于渐变起点（AI 主按钮） |
| **mint-500** | `#2FBE8F` | **品牌锚点**：进度条、圆环、发送按钮、凸起圆 |
| mint-600 | `#22A877` | 强调文字、图标；hero 渐变起点 |
| mint-700 | `#1B8A62` | 深强调文字（mint-50/100 底上的文字） |
| mint-800 | `#166B4D` | 暗色渐变起点 |
| mint-900 | `#114A36` | — |

#### 2.1.2 中性 ramp

| 档位 | 值 | 语义角色 |
|---|---|---|
| neutral-50 | `#F7F9F8` | `--lf-background` 页面底色 |
| neutral-100 | `#EFF3F1` | `--lf-muted` 嵌套块底色（卡内子卡、输入框底、趋势迷你格） |
| neutral-200 | `#DDE5E1` | `--lf-border` / `--lf-input` 边框、分隔线 |
| neutral-300 | `#B8C6C0` | 占位、禁用 |
| neutral-400 | `#8FA09A` | 暗色 `--lf-muted-foreground` |
| neutral-500 | `#6B7E78` | `--lf-muted-foreground` 次要文字 |
| neutral-600 | `#556760` | — |
| neutral-700 | `#3D4A45` | — |
| neutral-800 | `#2A342F` | 暗色边框 |
| neutral-900 | `#1A201D` | `--lf-foreground` 主文字；**训练页暗色 hero 底** |
| 白 | `#FFFFFF` | `--lf-card` 卡片底、`--lf-primary-foreground` |

#### 2.1.3 分类数据可视化色（**编码永不改变或调换**）

| token | 值 | 100 档 | 含义 |
|---|---|---|---|
| `--lf-protein` | `#FF8A65` | `#FFE5DC` | 蛋白质 = 珊瑚 |
| `--lf-carbs` | `#FFC94D` | `#FFF4D6` | 碳水化合物 = 蜜黄 |
| `--lf-fat` | `#B39DDB` | `#EDE6F7` | 脂肪 = 雾紫 |
| `--lf-water` | `#A8C4D9` | — | 饮水 = 海盐 |
| `--lf-weight` | `#C9A27E` | — | 体重 = 可可 |

> 这五色是**领域数据色**，不是品牌色。任何页面提到蛋白/碳水/脂肪/饮水/体重都必须用这五色，不得使用品牌绿代替。

#### 2.1.4 状态色

| token | 值 | 前景 |
|---|---|---|
| `--lf-state-success` | `#2FBE8F` | `#FFFFFF` |
| `--lf-state-warning` | `#FF9800` | `#FFFFFF` |
| `--lf-state-error` | `#F44336` | `#FFFFFF` |
| `--lf-state-info` | `#42A5F5` | `#FFFFFF` |

> 注意：亮色下 `state-success` **等于** mint-500。这不是笔误——设计稿的"成功"就是品牌绿。

**2026-10-20 补充（全应用审查 RV-P1-13）**：`state-warning` / `state-error` 是**填充色**，
直接当正文/图标文字不满足对比度（实测 warning 对白底 2.16:1、error 3.68:1）。新增两个
**只当文字用**的派生 token（不替换上面的填充色，设计稿主稿无需改）：

| token | 亮色 | 暗色 | 判据 |
|---|---|---|---|
| `warningText`（Dart `LfSemanticColors.warningText`） | `#9A5B00` | `#FFB74D` | 对 card/background/muted ≥4.5:1（实测 5.43/5.13/4.85） |
| `errorText`（Dart `LfSemanticColors.errorText`） | `#B3261E` | `#EF5350` | 对 card ≥4.5:1 |

纪律：**填充用 `warning`/`error`，文字/图标用 `warningText`/`errorText`**；异常日期等
「tint 底 + 文字」场合用 `warning@12%` 底 + `warningText`（实测 4.95:1）。

#### 2.1.5 证据分级色

| token | 值 | 含义 |
|---|---|---|
| `--lf-evidence-a` | `#D2F5E6` | 已确认 / 营养师确认 |
| `--lf-evidence-b` | `#FFF4D6` | AI 估算 |
| `--lf-evidence-c` | `#EDE6F7` | 待补全 / 不完整 |

#### 2.1.6 语义表面 token（组件取色的唯一入口）

| token | 亮色值 | 说明 |
|---|---|---|
| `--lf-background` | `#F7F9F8` | 页面底 |
| `--lf-foreground` | `#1A201D` | 主文字 |
| `--lf-card` | `#FFFFFF` | 卡片底 |
| `--lf-card-foreground` | `#1A201D` | 卡片主文字 |
| `--lf-popover` | `#FFFFFF` | 浮层底 |
| `--lf-popover-foreground` | `#1A201D` | 浮层主文字 |
| `--lf-muted` | `#EFF3F1` | 嵌套块底 |
| `--lf-muted-foreground` | `#6B7E78` | 次要文字 |
| `--lf-border` | `#DDE5E1` | 边框、分隔线 |
| `--lf-input` | `#DDE5E1` | 输入框边框 |
| `--lf-ring` | `#2FBE8F` | 聚焦环 |
| `--lf-primary` | `#2FBE8F` | 主操作色 |
| `--lf-primary-foreground` | `#FFFFFF` | 主操作前景（**注意：也是训练页暗色 hero 的文字色**） |

### 2.2 色板 — 暗色（`html.dark`）

#### 2.2.1 覆盖值

| token | 暗色值 |
|---|---|
| mint-50 → mint-900 | `#0F1412` / `#1F2823` / `#242E28` / `#2A3A32` / **`#4ED9A6`（暗色锚点，提亮）** / `#2FBE8F` / `#22A877` / `#1B8A62` / `#166B4D` / `#114A36` |
| neutral-50 → neutral-900 | `#0F1412` / `#171E1A` / `#1F2823` / `#2A342F` / `#3D4A45` / `#556760` / `#6B7E78` / `#8FA09A` / `#B8C6C0` / `#DDE5E1` |
| protein / carbs / fat | `#FF9D7E` / `#FFD56B` / `#C3B0E5`（提亮并降饱和 5%） |
| protein-100 / carbs-100 / fat-100 | `#3A2820` / `#3A3320` / `#2A2438` |
| water / weight | `#B4D0E5` / `#D4B08E` |
| state-success / -warning / -error / -info | `#4ED9A6` / `#FFB74D` / `#EF5350` / `#64B5F6` |
| 四个 state-*-foreground | `#0F1412` / `#0F1412` / `#FFFFFF` / `#0F1412` |
| evidence-a / -b / -c | `#1F2823` / `#2A2438` / `#242E28` |
| background / foreground | `#0F1412` / `#DDE5E1` |
| card / card-foreground | `#171E1A` / `#DDE5E1` |
| popover / popover-foreground | `#1F2823` / `#DDE5E1` |
| muted / muted-foreground | `#1F2823` / `#8FA09A` |
| border / input / ring | `#2A342F` / `#2A342F` / `#4ED9A6` |
| primary / primary-foreground | `#4ED9A6` / `#0F1412` |

#### 2.2.2 暗色阴影

暗色下 `--lf-shadow-1` 改为描边：`0 0 0 1px rgba(255,255,255,0.04)`。浮层阴影不变。

### 2.3 圆角

| token | 值 | 用途 |
|---|---|---|
| `--lf-radius-xs` | `4px` | 极小件（点、条） |
| `--lf-radius-sm` | `8px` | 徽章、tags、"周"字标 |
| `--lf-radius-md` | `12px` | 图片缩略、输入框内部件 |
| `--lf-radius-lg` | `16px` | **卡片标准圆角**、按钮、输入框 |
| `--lf-radius-xl` | `16px` | 同 lg |
| `--lf-radius-2xl` | `16px` | 同 lg |
| `--lf-radius-full` | `9999px` | 药丸、圆环、头像、chip |

> **实测确认**：7 个 HTML 中 `rounded-sm|md|lg|xl|2xl` 工具类**使用 0 次**。实际出现的圆角只有三种：`rounded-full`（药丸/圆点）、`rounded-[16px]`（59 次，卡片与按钮）、`rounded-[12px]`（5 次，图片缩略）、`rounded-[8px]`（3 次，徽章）。
>
> **六档 radius 变量在两组文件里数值不一致**（`xs/sm/md/lg/xl/2xl`）：
>
> | 文件 | xs | sm | md | lg | xl | 2xl |
> |---|---|---|---|---|---|---|
> | 今日 · 我的 · 拍照识餐 · 饮食·菜单 | 4 | 8 | 12 | 16 | 16 | 16 |
> | AI 工作 · 训练 · 饮食·记录 | 8 | 12 | 16 | 20 | 24 | 32 |
>
> 但因为这六档**一次都没被用过**（用量 0），该差异**不产生任何视觉影响**。Flutter 侧统一按"卡片=16、缩略=12、徽章=8、药丸=full"实现即可；**不要试图从变量值反推设计意图**——出现差异的是两套复制粘贴时未同步的 `:root` 块，实际生效的只有上面那三类工具类。
>
> **注意 `rounded-b-*`（只圆下角）**：训练页暗色 hero 是 `rounded-b-[16px]`（`0 0 16px 16px`），**不是全角**。全角 16 的只有：我的身份卡、今日 AI 卡、普通卡片。
>
> **2026-10-08（`docs/30 §2 D4`）**：记录页与菜单页顶部卡已**白卡化**——它们不再是 `rounded-b-*` 的贴顶 hero，而是标准 `DesignCard`（全角 16 + 1px 描边）。设计稿里那两处 `rounded-b-[16px]` 因此**只剩训练页一处仍在生效**。
>
> **按钮圆角（详见 §3.8）**：按钮一共只出现两种圆角——`rounded-[16px]`（表单/弹层主行动
> B1、B1e）与 `rounded-full`（胶囊 B3、固定底栏确认 B2、图标圆钮 B4、虚线按钮 B5）。
> B8「保存配置」的 12 是实测特例（`我的.html:425`）。**不得引入 20/24/32。**

### 2.4 阴影与浮层

| token | 值 | 使用范围 |
|---|---|---|
| `--lf-shadow-1` | `0 1px 3px rgba(15,36,28,0.04), 0 1px 2px rgba(15,36,28,0.03)` | **静态表面**（卡片的默认阴影），全设计稿使用 38 次 |
| `--lf-shadow-float` | `0 8px 24px -8px rgba(15,36,28,0.04)` | **仅浮层**：modal / popover / dropdown / drawer / overlay |
| `--lf-shadow-float-lg` | `0 24px 60px -20px rgba(15,36,28,0.05)` | 大浮层 |

**硬规则**：静态卡片阴影 alpha 上限 0.05。任何超过 0.05 的静态阴影都是违规。彩色阴影只允许出现在**主操作元素**上（凸起圆、FAB、主按钮、AI 卡），形式为 `color-mix(in srgb, var(--lf-primary) N%, transparent)`，N ∈ {25, 30, 35, 40}。

设计稿实测彩色阴影共 **7 条**，全部落在主操作元素上：

| 元素 | 阴影 | 出处 |
|---|---|---|
| 底栏凸起圆 | `0 0 0 2px var(--lf-background), 0 4px 12px rgba(47,190,143,0.3)` | 7 页各一 |
| 进行中训练横幅 | `0 8px 24px -8px color-mix(in srgb, var(--lf-primary) 25%, transparent)` | 训练页 |
| AI 主按钮 `cta-write-plan` | `0 4px 16px -4px color-mix(in srgb, var(--lf-primary) 35%, transparent)` | AI 工作页 |
| 拍照页固定底栏按钮 `cta-confirm-scan` | `0 4px 20px -4px color-mix(in srgb, var(--lf-primary) 40%, transparent)` | 拍照识餐页 |
| 训练页 FAB `cta-new-plan` | `0 4px 16px color-mix(in srgb, var(--lf-primary) 40%, transparent)` | 训练页 |
| 饮食·记录页 FAB（无 id） | `0 4px 12px color-mix(in srgb, var(--lf-primary) 30%, transparent)` | 饮食·记录页 |
| 图片移除按钮 `btn-remove-image` | `0 2px 6px rgba(244,67,54,0.3)` | AI 工作页 |

> **注意一**：`btn-voice-send`（AI 工作页录音行的发送按钮）**没有任何阴影**——它只有 `background: var(--lf-primary)`。上表第 4 行的 20px/−4px/40% 组合属于**拍照页的确认按钮**，两者不要混。
>
> **注意二**：`cta-new-plan` 的 `0 4px 16px …40%`（**无负 spread**）与 `cta-write-plan` 的 `0 4px 16px -4px …35%`（**有负 spread、35%**）是两条不同的阴影，不要互相套用。
>
> **注意三（2026-10-06，docs/29 §P6）**：饮食·记录页 FAB 的阴影经用户反馈要求加强，实现 token
> `LfShadows.recordFab` 从 `0 4px 12px …30%` 改为 **`0 6px 20px …40%`**（blur 20 / offset y 6；
> docs/29 原文写 α .38，38 不在上面的白名单里，取最近档 40）。上表该行的 30% 保留为设计稿
> 实测原值（HTML 未回改），实现以本注记为准；白名单 N ∈ {25,30,35,40} 与「不新增 token」未破。
>
> **按钮阴影（详见 §3.8）**：按钮**默认无阴影**；彩色阴影只允许给主操作按钮，且只能用上表 7 条
> 中的 `aiPrimaryCta`（35%，B1e 强调主按钮）与 `scanConfirmCta`（40%，B2 底部确认）。
> **不新增阴影 token，也不新增第 10 条渐变。**

### 2.5 渐变

设计稿实测共 **9 条不同的渐变定义**。其中 hero 是**变量**（每页 `:root` 各声明一份），其余是内联字面量。**不得新增第 10 条**：

| 名称 | 定义 | 用途 | 出现方式 |
|---|---|---|---|
| hero（亮色，变量） | `linear-gradient(135deg, #2FBE8F 0%, #A8EBCF 55%, #ECFBF5 100%)` | 记录页 hero、菜单页 hero、我的身份卡、今日页 AI 卡、拍照页照片预览占位 | **声明 7 次**（每页一份）；`var()` **引用 5 处** |
| hero（暗色覆盖，变量） | `linear-gradient(135deg, #166B4D 0%, #1B8A62 50%, #0F1412 100%)` | 同上 5 处在 `html.dark` 下自动替换 | **声明 7 次**（每页 `html.dark` 一份） |
| 凸起圆 | `linear-gradient(135deg, var(--lf-mint-500), var(--lf-mint-600))` | 底栏中央槽 56×56 全圆 | 内联 **7 处**（每页各一） |
| 用户消息气泡／AI 主按钮 | `linear-gradient(135deg, var(--lf-mint-400), var(--lf-mint-500))` | AI 工作页用户气泡 ×3（含语音消息气泡）+ `cta-write-plan` | 内联 **4 处** |
| 进行中横幅 | `linear-gradient(135deg, var(--lf-primary), var(--lf-mint-600))` | 训练页进行中横幅 | 内联 **1 处** |
| 图片占位（暖） | `linear-gradient(135deg, #D4A574, #E8C9A0, #C4956C)` | **AI 工作页**功能卡内大图 + 缩略图 | 内联 **2 处** |
| 图片占位（蛋白色系） | `linear-gradient(135deg, var(--lf-protein-100), color-mix(in srgb, var(--lf-carbs) 20%, transparent))` | 菜单页第 1 张菜品卡 | 内联 **1 处** |
| 图片占位（mint 色系） | `linear-gradient(135deg, var(--lf-mint-100), color-mix(in srgb, var(--lf-mint-200) 20%, transparent))` | 菜单页第 2 张菜品卡 | 内联 **1 处** |
| 图片占位（脂肪色系） | `linear-gradient(135deg, var(--lf-fat-100), color-mix(in srgb, var(--lf-fat) 20%, transparent))` | 菜单页第 3 张菜品卡 | 内联 **1 处** |

> **hero 是变量，别按字面量出现次数去数**：`linear-gradient(` 字面量在 7 个文件中共出现 31 次，其中 **14 次是 hero 的声明**（亮 7 + 暗 7）、**17 次是内联使用**。真正的"渐变种类"是上表 9 条。
>
> **as-built（2026-10-08 落定，`docs/30 §2 D4/D5/D6`，R8 收口）**：上表是**设计稿**的实测值，仍然成立（本表描述的是 `ui设计/pages/*.html`）。实现侧的口径现在可以定死了：
>
> **hero 渐变在 `lib/` 里只剩 1 处引用**——`design_card.dart` 的 `HeroSection`，唯一使用者是**今日页 AI 入口卡**（`dashboard_ai_entry_card.dart`，`HeroShape.all`）。也就是说「大色块退场」这件事在实现层已经完成：
>
> | 曾经的引用点 | 现状 | 落点 |
> |---|---|---|
> | 记录页 hero | **改 `DesignCard`** | R4 |
> | 菜单页 hero | **改 `DesignCard`** | R4 |
> | 我的身份卡 | **改 `DesignCard`** | R5 |
> | 训练页 hero（暗色块） | **改 `DesignCard`** | R5 |
> | 今日页 AI 入口卡 | **保留 `HeroSection`**（它不是「数据卡」，是 AI 功能的入口） | — |
> | 拍照页照片预览占位 | **不适用**：该页在实现里用真实照片，没有占位渐变 | — |
>
> 追加的两条实现层事实（与上表的「渐变种类」无关，但同属 §2.5 的收口）：
> ① `LfSemanticColors` 里的占位渐变族（`warmPlaceholder` / `proteinPlaceholder` / `mintPlaceholder` / `fatPlaceholder`）**在 `lib/features/` 内零调用点**；
> ② `app_empty_state.dart` 的空态圆里有一条 `mint-100 → mint-50` 的装饰渐变（80dp 圆，`floatingEmoji` 底）——它**不在**上表的 9 条清单里，也不是大色块，记录在此以免下次审计时被当成「第 10 条渐变」误判。
>
> **判定「大色块退场」要看引用点而不是组件是否存在**：`HeroSection` 组件本身没有删（今日页 AI 卡仍在用），所以「渐变 hero 还在代码里」这件事本身不是回归信号。
>
> **图片占位共 6 处、两种风格**：AI 工作页 2 处用固定暖色三停靠；菜单页 3 处用**对应营养色的 100 档打底 + 该色 20% 叠加**；拍照页照片预览 1 处直接复用 **hero 变量**。
>
> 实现口径：图片占位的语义是「没有照片时不留空白」，色系可按 `DishLibrary.mealSlot` 或营养构成稳定选取，但**不得伪造菜品照片**（§6.1）。菜单页那 3 处按卡序取三色不是规范，可按数据稳定映射。

### 2.6 字体与类型阶

#### 2.6.1 字体族

设计稿声明 `PingFang SC / Noto Sans SC / HarmonyOS Sans SC / Microsoft YaHei / system-ui`。

**Flutter 侧不内置任何字体文件**，一律使用平台默认 CJK 字体（Android 为 Noto Sans CJK）。理由：Android 无法预装 PingFang，内置字体文件会显著增大 APK 且需要额外的许可审查（`docs/08`）。

**必须落实的是字体的排版特征，而非字体文件**：

| 特性 | 实现 |
|---|---|
| 显示数字族 `.lf-display` | `fontWeight: w800` + `tabular-nums` + `letterSpacing: -0.02em` + `height: 1.0` |
| 通用表格数字 `.lf-num` | `fontFeatures: [FontFeature.tabularFigures()]` |
| 字重 | 设计稿只用了三档：`font-medium`(w500, 68 次)、`font-semibold`(w600, 26 次)、`font-bold`(w700, 2 次) |

#### 2.6.2 类型阶（按设计稿实测用量）

设计稿实际使用了 **13 档字号**（`class` 内共 410 处声明）。用量最大的是 10px（107 次）、12px（167 次）、14px（68 次）——**小字号承担了绝大部分文本**。下表 11 档建 Flutter token，另 2 档（20/24px）复用就近档位、不建 token。

| 名称（Flutter） | px | 字重 | 行高 | 用途（设计稿实测） | 用量 |
|---|---|---|---|---|---|
| `micro` | **10** | w400/w500 | 1.4 | 底栏标签、图例、脚注、时间戳、迷你标签 | 107 |
| `microStrong` | **10** | w500 | 1.4 | 同上但需强调 | — |
| `label` | **11** | w500 | 1.4 | 徽章文字、卡内小标签、次要数值 | 21 |
| `caption` | **12** | w400 | 1.4 | 次要文字、说明、卡内描述 | 167 |
| `captionStrong` | **12** | w500 | 1.4 | 卡内小标题、时间线标题 | — |
| `bodySmall` | **13** | w400 | 1.4 | 少数说明文 | 1 |
| `body` | **14** | w400 | 1.5 | 正文、列表项、按钮文字 | 68 |
| `bodyStrong` | **14** | w500/w600 | 1.5 | 段落小标题 | — |
| `title` | **15** | w600 | 1.3 | **卡片标题**（今日页三张卡：今日热量/本周体重/今日饮食）+ 今日页头像首字 | 4 |
| `titleLarge` | **16** | w600 | 1.3 | 二级页标题与菜品名：拍照页标题、训练页进行中横幅会话名、菜单页菜品名 ×3、记录页营养分析三数值 | 11 |
| `headline` | **18** | w600 | 1.3 | 我的页身份卡姓名 + 6 个统计值、拍照页菜名、菜单 hero 两数值 + 菜单菜品 kcal ×3、今日页饮水/步数数值 | 15 |
| `displayLarge` | **22** | w800 | 1.1 | 今日页问候语 | 1 |
| `displayXLarge` | **26** | w800 | 1.0 | 圆环中心数值 | 1 |
| `displayHero` | **30** | w800 | 1.0 | 训练页 hero 三统计 | 3 |

> Tailwind 具名类换算（1rem = 16px）：`text-xs`=12、`text-sm`=14、`text-base`=16、`text-lg`=18、`text-xl`=20、`text-2xl`=24、`text-3xl`=30。括号内为实测用量：`text-xs` 152、`text-sm` 67、`text-lg` 13、`text-base` 8、`text-2xl` 7、`text-xl` 4、`text-3xl` 3。
>
> **13 档与上表 11 行的差额 = 20px 与 24px**。这两档在设计稿里**只用 Tailwind 具名类**（`text-xl` 4 次、`text-2xl` 7 次），没有 `text-[Npx]` 写法，因此**不单独建 Flutter token**：
>
> | 未建 token 的档 | 实测用法 | Flutter 处置 |
> |---|---|---|
> | 20px | 训练页「训练」标题（`text-xl font-bold`）、菜单页「今日菜单」、记录页「饮食记录」 | 复用 `titleLarge 16` 或 `headline 18`，**按视觉就近取**，不得新造档 |
> | 24px | 「我的」页若干标题、训练页 hero 三统计（`text-2xl` + `.lf-display`） | 复用 `displayLarge 22` |
>
> **不得因为"没列进来"就自行发明新档**；训练页 hero 那三个统计数（30px `text-3xl`）用的是 `displayHero`，不要误当成 24。

#### 2.6.3 字号可达性例外条款

10px 与 11px 低于无障碍推荐值（12sp）。设计稿明确使用它们承载**辅助信息**（标签、图例、脚注）。

**规范**：允许 10/11px 用于**非交互、非唯一信息来源**的文本。若某信息只能通过 10/11px 文本获得，则必须同时提供语义标签（`Semantics(label:)`）供读屏获取。**任何可点击元素的命中区不得小于 44×44 dp**（`AppDimens.minTouchTarget`），与字号无关——底栏标签虽为 10px，其整个 64dp 高的槽位都是命中区。

### 2.7 间距与网格

设计稿的主容器为 `max-w-[430px]` / `max-w-md`（448px）居中，内容左右内边距 `px-4` = **16px**。

| token | 值 | 设计稿依据 |
|---|---|---|
| `spaceMicro` | **2px** | `gap-0.5`(35 次) |
| `spaceXSmall` | **4px** | `gap-1`(52 次) |
| `spaceTiny` | **6px** | `gap-1.5`(24 次) |
| `spaceSmall` | **8px** | `gap-2`(67 次)、`mb-2` |
| `spaceSmallPlus` | **10px** | `gap-2.5`、`mt-2.5` |
| `spaceMedium` | **12px** | `gap-3`(30 次)、`mt-3`(43 次) |
| `spaceMediumPlus` | **14px** | `gap-3.5`、`px-3.5` |
| `spaceLarge` | **16px** | `px-4`(57 次)、`p-4`(24 次)、`mt-4`(26 次)、`gap-4` |
| `spaceLargePlus` | **20px** | `p-5` |
| `pagePadding` | **16px** | 所有页面的 `px-4` |
| `cardPadding` | **16px** | 卡片的 `p-4` |
| `cardGap` | **16px** | 卡片之间的 `mt-4` |

> **与现有的关键差异**：当前 `AppDimens.pagePadding = 20`、`cardPadding = 16`、`spaceSmall = 12`。新设计统一为**页面内边距 16、卡片内边距 16、卡间距 16**。`spaceSmall` 从 12 改为 8 会牵动大量调用点——实现时**新增具名 token 而非修改现有值**，避免静默改变无关页面（详见 `docs/22` 阶段 A）。

### 2.8 与现有 token 的差异表（迁移口径）

> 这一节是**诚实清单**：旧 token 与新设计的差异远大于早前估计。品牌锚点与五个数据色可以复用，但**整套 ramp 与中性色需要重新灌注**。

#### 2.8.1 完全一致（可直接复用）

| 项 | 值 |
|---|---|
| 品牌锚点 mint-500 | `#2FBE8F` |
| protein | `#FF8A65` |
| carbs | `#FFC94D` |
| fat | `#B39DDB` |
| water | `#A8C4D9` |
| weight | `#C9A27E` |
| 暗色 background / surface / surfaceAlt | `#0F1412` / `#171E1A` / `#1F2823` |
| 卡片圆角 | 16px |
| 药丸圆角 | full |
| 触达下限 | 44dp |

#### 2.8.2 必须修改（逐项）

| 项 | 旧值 | **新值** | 影响面 |
|---|---|---|---|
| 页面底色 | `#FAFBF9` | **`#F7F9F8`** | 全局 |
| 边框 | `#EEF1EE` | **`#DDE5E1`**（明显深一档） | 全局 |
| 嵌套块底色 | `#F4F7F5`（surfaceAlt） | **`#EFF3F1`**（muted） | 卡内子块 |
| 主文字 | `#17251E` | **`#1A201D`** | 全局 |
| 次要文字 | `#5A6B62` | **`#6B7E78`** | 全局 |
| 三级文字 | `#93A29A` | **`#8FA09A`**（暗色档位） | 全局 |
| mint ramp 50/100/200/300/400 | `#F0FBF7`/`#E3F6EE`/`#C9EEDF`/`#A5E2CB`/`#63D2A8` | **`#ECFBF5`/`#D2F5E6`/`#A8EBCF`/`#6FDBB0`/`#4ED9A6`** | 徽章、头像、时间线 |
| mint ramp 600/700/800/900 | `#1FA377`/`#17875F`/`#0F6B4A`/`#0A4F37` | **`#22A877`/`#1B8A62`/`#166B4D`/`#114A36`** | 强调文字 |
| 蛋白/碳水/脂肪 100 档 | `#FFE9E1`/`#FFF3D9`/`#EFE9F9` | **`#FFE5DC`/`#FFF4D6`/`#EDE6F7`** | 徽章底 |
| success | `#34B37E` | **`#2FBE8F`**（= mint-500） | 状态 |
| warning | `#F5A623` | **`#FF9800`** | 状态 |
| error | `#E5484D` | **`#F44336`** | 状态 |
| info | `#5B8DEF` | **`#42A5F5`** | 状态 |
| evidence A / B / C | 暗色系三值 | **`#D2F5E6`/`#FFF4D6`/`#EDE6F7`**（亮色） | 徽章 |
| 暗色主文字 | `#E9F1EC` | **`#DDE5E1`** | 暗色全局 |
| 暗色 mint 锚点 | `#4ED9A6`（同值） | `#4ED9A6` | 暗色品牌 |
| hero 渐变 | `[#2FBE8F, #7ADCB8, #D9F6E9]` | **[#2FBE8F, #A8EBCF, #ECFBF5]**（中末段不同） | 4 处 hero |
| 卡片阴影 | elevation 6 / opacity 0.06 | **`0 1px 3px rgba(15,36,28,.04), 0 1px 2px rgba(15,36,28,.03)`** | 全局 |
| 浮层阴影 | elevation 12 / opacity 0.12 | **`0 8px 24px -8px rgba(15,36,28,.04)`** | 浮层 |
| 页面内边距 | 20px | **16px** | 全局 |
| 封面渐变 6 组 | matcha/peach/honey/taro/seaSalt/cocoa | **删除**——新设计的图片占位不用生成式纹理，改用 §2.5 的 6 处图片占位渐变 | 餐食封面（原食谱功能已下线） |

#### 2.8.3 类型阶差异

| 现有 | 新设计 |
|---|---|
| `displayXL 64` `displayNumber 56` `displayM 40` `numberMedium 28` | **设计稿未使用**。最大字号为 30px。保留但不用于新页面 |
| `numberS 18` | 映射到 `headline 18` |
| `h1 24` | 设计稿 `text-2xl 24` 仅少量使用 |
| `h2 18` | 映射到 `titleLarge 16` / `headline 18` |
| `body 15` | 保留；**卡片标题统一改用 15 w600** |
| `secondary 13` | 保留 |
| `label 11` | 保留 |
| — | **新增** `micro 10`、`caption 12`、`body 14`、`title 15`、`titleLarge 16`、`displayLarge 22`、`displayXLarge 26`、`displayHero 30` |

### 2.9 动效

设计稿内联动画共 **5 组 keyframes**，全部在 `ui设计/pages/AI 工作.html` 的 `<style>` 中声明（其余 6 页无 `@keyframes`）：

| `@keyframes` 名 | 类名 | 时长 | 曲线 | 用途 |
|---|---|---|---|---|
| `typing-dot` | `.typing-dot` | **1.4s** 无限循环 | ease-in-out | AI「正在输入」三点跳动（`opacity .3→1`、`scale .8→1.15`；第 2/3 点 `animation-delay` 0.2s / 0.4s） |
| `rec-pulse` | `.rec-pulse-ring` | **1.5s** 无限循环 | ease-out | 录音红点脉冲圈（`scale 1→1.6`、`opacity .5→0`） |
| `wave-bar` | `.wave-bar` | **1.1s** 无限循环 | ease-in-out | 录音行波形（`scaleY .2→1→.2`，7 个关键帧） |
| `wave-played` | — | 未在 HTML 中引用 | — | 语音消息「已播放/未播放」过渡（`from opacity .35 → to 1`）。**设计稿只定义未使用**——已发送语音消息的不透明梯度是**静态内联样式**，不是这个动画 |
| `img-preview-in` | `.img-preview-anim` | **0.28s**，一次性 | **`cubic-bezier(0.34, 1.2, 0.64, 1)`**（带过冲） | 图片预览条入场（`opacity 0→1`、`translateY 6px→0`、`scale .96→1`） |

另有 1 处 Tailwind 内置循环类：**`animate-pulse`** 用于训练页进行中横幅的脉冲白点（Tailwind 默认 2s 无限、`cubic-bezier(.4,0,.6,1)`）。

> **注意：类名 ≠ keyframes 名。** `.img-preview-anim` 引用的是 `img-preview-in`；`.rec-pulse-ring` 引用的是 `rec-pulse`。实现时按 **keyframes 名**对齐时长与曲线（上表第 2、4 列），不要按类名后缀去猜。

**规范**：
- 无限循环动画**仅限"正在进行"状态**（录音中、训练进行中、AI 正在输入）。页面静止时不得有循环动画。
- 所有动效必须响应系统「减少动态效果」（`MediaQuery.disableAnimationsOf(context)`）——开启时循环动画停止在静态首帧。
- 其余交互动效沿用现有 `AppMotion`（fast 150 / base 250 / 标准 spring）。

---

## §3 组件库

> 命名用「新建」= 当前 `lib/app/design/widgets/` 无此件；「改造」= 已有但需按新设计调整；「废弃」= 有但新设计不用。

### 3.1 容器类

| 组件 | 状态 | 规格 |
|---|---|---|
| `DesignCard` | **新建** | 白底 + `1px --lf-border` 描边 + 16 圆角 + `--lf-shadow-1` + `p-4`。**这是新设计里唯一的卡片形态**；旧 `BentoCell`（24/32 圆角 + 重阴影）**废弃** |
| `DesignCard.dashed` | 同一件的变体 | 虚线描边 `border-dashed`，用于 AI 页「添加」按钮（原今日页晚餐时间线的「计划态」已随 `MealPlanEntries` 删表下线）。虚线模式 4/4 |
| `DesignCardHeader` | **新建** | 标题（15 w600）+ 可选副标题（12 muted）+ 可选尾部徽章 |
| `MutedBlock` | **新建** | `--lf-muted` 底 + 16 圆角 + `p-3`。用于卡内子块（时间线条目、趋势迷你格）。**注意：不是白卡**——设计稿嵌套块用 muted 底色，不用第二层白卡 |
| `HeroSection` | **新建** | hero 渐变底 + 顶部 `p-5`。**圆角分两种，不可混用**：训练页暗色 hero = `rounded-b-[16px]`（**只圆下角**，实测 `0 0 16px 16px`）；今日页 AI 卡 = `rounded-[16px]`（全角，`p-4`）。**`rounded-[20px]` 在设计稿中出现 0 次**。**2026-10-08（`docs/30 §2 D4/D5/D6`）后剩余使用者**：今日页 AI 入口卡（`dashboard_ai_entry_card.dart`）——记录 / 菜单 / 我的身份卡 / 训练页四处已改白卡。`HeroShape.bottomOnly` 的注释同步改写 |
| `SettingsGroup` | **新建** | `overflow-hidden rounded-[16px]` + `divide-y` 行分隔。每行 `min-h-[52px] px-4`。组标题在组外。用于我的页 4 个设置分组 |

**废弃的容器与图案件**（新设计不含此视觉，实现时删除或停止引用）：

| 组件 | 废弃理由 |
|---|---|
| `BentoCell` | 圆角 24/32 + 重阴影与设计稿的"卡片=16 圆角 + 1px 描边 + 浅阴影"冲突 |
| `AppCoverPattern` / `AppCoverArt` | 设计稿的封面是**图片占位渐变**（`linear-gradient(135deg, #D4A574, #E8C9A0, #C4956C)`），不用生成式纹理。6 组封面渐变已删除 |
| `MacroPill` | 设计稿的宏量是**横条 + 标签行**（`MacroBar`），不是 32dp 药丸

### 3.2 数据可视化类

| 组件 | 状态 | 规格 |
|---|---|---|
| `CalorieRing` | **重写** | 旧件是半圆（`startAngle = pi`，208px，带宏量内段与辉光）。新设计是**完整圆环**：120×120，`r=52`，`stroke-width=10`，轨道色 `--lf-muted`，进度色 `--lf-primary`，`stroke-linecap=round`，从 -90° 起画。**中心三段文字**：26px w800 数值 / 11px muted "/ N kcal" / 11px w600 mint-600 百分比。旧件的宏量内段、拖拽明细、辉光**全部移除** |
| `MacroBar` | **新建** | 标签行（8px 圆点 + 12px 名称 …… 12px muted "42 / 60 g"）+ 下方 `h-1.5` 全圆角轨道 + 按比例填充。圆点色 = 对应数据色 |
| `MacroRatioRow` | **新建** | 一行三个「名称 百分比」，用于 4/4/9 热量占比。11px |
| `WeightBarChart` | **新建（2026-10-08 R2 取代 `WeightLineChart`）** | 手绘**柱状图**（`CustomPainter` 只画网格，柱是 widget 树，**不用 fl_chart**）。**左侧 y 轴三档刻度 + 顶部 `kg` 单位**：轴范围 = 数据真实 min/max 各外扩 25%（`axisPadRatio`），单点时固定 ±0.5kg（`singlePointHalfSpanKg`）；**不从 0 起**（体重从 0 画会把小幅漂移压成平线，与热量柱图的 0 基线口径**故意不同**，注释写清）。柱：周视图**恒定七格**（周一…周日，无记录日为空槽——不画柱、标签显示且更淡，空槽不参与轴 min/max，docs/31 S1 需求 41）、月视图一箱一根（**本月**自适应分箱均值——口径是本月不是近 30 天，docs/31 S1 需求 42），圆角顶 6，`mint-500`，末柱（最新）`mint-600`。网格 = 与刻度对齐的 3 条水平虚线（dash 3 / gap 4）。横轴标签在柱下方（周一…日 / `8/8`）；**标签盒允许跨格**（`OverflowBox` 上限 `LfDimens.weightChartAxisLabelMaxWidth = 56`）——月视图一格只有绘图区/当月天数 （360dp 下约 10dp），给格宽会把「9/14」压成「9」（2026-10-16 月视图帧实看抓到；用户早前看到的「一堆 1」也是同一处截断：10/15/20/25 被压成首字符）。`ChartSemantics` 一行摘要。**柱宽上限 22dp**（`maxBarWidth`，docs/31 S1 需求 40 由 40 收窄；格内水平内边距 3→8，相邻柱净空隙 16dp）——`Expanded` 只负责把柱**分到**格子，柱自身由 `Align(bottomCenter)` + `FractionallySizedBox`(高度) + `ConstrainedBox(maxWidth 40)`(宽度) 三层合成：**`Align` 不能用 `Center`**，`Center` 会让柱竖向上浮（2026-10-08 R8 设备走查实测：单条记录时那一根柱曾撑满整个绘图区 256dp，改成 `Center` 后又变成浮空 65dp 高的方块）|
| `WeightLineChart` / `MiniSparkline` / `TrendTile` | **已删除（2026-10-08 R2）** | 三者随需求 2「数据做成柱状图，左边要有坐标」「下边的本周趋势三个小卡片不要了，不需要统计体脂率和肌肉量了」整件删除，`lib/` 内零调用点。体脂率/肌肉量**数据层已随 schema 22 整族删除**（2026-10-09 docs/31 S2：`Measurements` 两列 + 弹层字段 + AI 参数 + 旧 `.lfb` 恢复即丢） |
| `BarChart` | **新建** | 7 柱日趋势（饮食·记录页）+ 容量图（训练页）。柱宽按容器均分，圆角顶。达标日与未达标日取色不同；训练页休息日柱高为 0 且用 muted 色 |
| `WeekStrip` | **新建** | 7 列，每列（星期字 + 日期数字圆）。今天 = 实心 mint 圆白字；异常日 = warning 色；其余 = 无底 |
| `ProgressBar` | 改造 | 已有 `progress_bar.dart`。新设计统一 `h-1.5` 全圆角；进度条必须 `ExcludeSemantics`（信息由相邻文字承载） |
| `ChartSemantics` | 保留 | 图表必须有文字等价物（`docs/07` 无障碍条款） |

**fl_chart 的取舍**：设计稿的折线与柱图都是内联 SVG/Chart.js，样式极简。`fl_chart` 默认带网格、动画与 tooltip，反而需要大量覆写才能还原。**规范：新设计的图表一律手绘 `CustomPainter`**。现有使用 `fl_chart` 的组件保留，但新页面不得引入。

### 3.3 表单与设置类

| 组件 | 状态 | 规格 |
|---|---|---|
| `AppNumberField` | 保留 | 浮动标签已在框外，符合新设计的"标签在行左"风格 |
| `SettingRow` | **新建** | `min-h-[52px] px-4 py-3.5`，左（20px 图标 muted + 14px 名称）… 右（值 14px muted / 或 chevron / 或开关）。**2026-10-04 补 `subtitle`（可选）**：给了就在标题下加一行 `caption` muted（如「导入扩展食物目录（可选）」的导入状态）——二行形态仍是一个 `Expanded` 列，值/chevron 的右对齐不变 |
| `SettingToggle` | **新建** | `role=switch`，44×24 全圆角，开 = `--lf-primary` 底 + 右侧白圆，关 = muted 底 + 左侧圆 |
| `TextField` | 改造 | 底 `--lf-muted`、`rounded-[16px]`、`px-3.5 py-2.5`、无边框、placeholder 为 muted。**与现有 `InputDecoration` 的 16 圆角白底描边不同** |
| `AppSheet` | 保留 | 浮层用 `--lf-shadow-float`。**浮层内的提示见下方硬规则** |
| `AppSnackBar` | 保留 | **只用于浮层已关闭后的提示**（见下方硬规则） |
| `AppEvidenceBadge` | 改造 | 三档：`已确认`/`营养师确认` = `--lf-evidence-a` 底；`AI 估算` = `--lf-evidence-b`；待补全 = `--lf-evidence-c`。形状 `rounded-[8px] px-2 py-1` 11px w500 |

> **浮层内提示的硬规则（2026-10-02 模拟器实证）**：`AppSheet` 全部走
> `useRootNavigator: true`，浮层是根导航器上的一条 modal route；而 `AppSnackBar`
> 画在页面自己的 `Scaffold` 里 ⇒ **浮层打开时发出的 snackbar 被盖在浮层下面**。
> 两个判据都实测过：① 在 snackbar 自身矩形中心做命中测试，命中的是浮层的内容；
> ② 页面 route 不是 current，snackbar 的自动消失定时器根本不会被创建（永远不消失）。
> 因此：**任何在浮层仍然打开时产生的成功/失败提示，必须画在浮层内部**
> ——弹层内的错误/成功文本（`errorText` / `notice`），或**先 `pop` 浮层再发
> `AppSnackBar`**。用户看到的「点了没反应」根因通常就在这里。

### 3.4 对话类（AI 对话页专用）

| 组件 | 规格 |
|---|---|
| `AiMessageBubble` | AI 侧：白底 + 描边 + 16 圆角（左上角 4）。14px |
| `UserMessageBubble` | 用户侧：135° 渐变（mint-400→mint-500）底 + 白字 + 16 圆角（右上角 4）+ **右下 45° 旋转小方块尾角**。14px |
| `FeatureCardMessage` | AI 消息内的富文本卡：muted 底 + **3 个居中列**（每列 = 40×40 `mint-50` 圆 + 20px primary 色图标 + 10px w500 标签）+ 右上「点击查看」药丸徽章（`protein-100` 底 + protein 色字 + chevron）+ AI 主按钮。**底部按钮 `cta-write-plan` 文字「立即查看专属理想方案」**，底色同 `UserMessageBubble` 的渐变 |
| `ImageMessage` | 用户消息带图：缩略图（`rounded-[12px]`，最大宽度约 200）+ 文件名 + 说明文字 |
| `VoiceMessage` | 用户语音消息：**圆形播放按钮（28×28，半透明白底）+ 14 根静态波形条 + 时长文字**。波形条 3px 宽、全圆角、高度 `h-1~h-5` 五档交错，**颜色是白色（`rgba(255,255,255,0.3~0.95)` 递减，用来表达"已播放/未播放"）——不是 mint 色**。**该行不带动画**（`wave-played` 设计稿定义了但未引用） |
| `TypingIndicator` | AI 正在输入：三点跳动（现有 `AppButtonDotsLoader` 可复用）。设计稿为 `.typing-dot`，1.4s 无限、三点 `animation-delay` 0/0.2/0.4s |
| `ChatInputBar` | **双状态**：默认行 = 图片按钮 + 麦克风按钮 + 文字输入 + 发送按钮；录音行 = 取消按钮 + [脉冲红点 + **16 根波形** + 计时] + 发送按钮。两行互斥显示 |
| `ChatQuickChips` | 输入栏上方四个 chip：`拍照识别`（mint-50 底 + mint-200 描边 + primary 文字）/ `手动记录` / `我可以吃吗` / **`AI 创作`**（后三个 muted 底；第四个为 Round7 逐页对账批次 2 按 A `app.js:207` 补齐，点击推入起手画廊 `aiWorkbench`，与今日页 AI 入口卡同一路由） |
| `ImagePreviewStrip` | 已选图片预览：56×56 缩略（12 圆角 + 2px mint-200 描边）+ 右上角移除圆钮（error 底）+ 文件名 + "已添加 N 张图片" + 「添加」虚线按钮 |

> **录音行波形（16 根，mint 色、带动画）与已发送语音消息波形（14 根，白色、静态）是两件不同的东西**——数量、颜色、是否动画三处都不同，不要复用同一个组件而不分参数。

### 3.5 徽章与状态类

| 组件 | 规格 |
|---|---|
| `StatusBadge` | `rounded-[8px] px-2 py-1` 11px w500。例：`燃脂中`（mint-50 底 + mint-700 字 + flame 图标） |
| `SourceBadge` | 见 `AppEvidenceBadge` |
| `HotBadge` | `本周热门`，honey 系底 |
| `UnitBadge` | 卡片标题右侧的"周"字标：muted 底 + 11px muted 字 + 8 圆角 |
| `PlannedTag` | `晚餐 · 计划` 的虚线态标签（原周计划态；功能下线后已无使用点，仅保留为设计稿术语） |

### 3.6 导航类

| 组件 | 状态 | 规格 |
|---|---|---|
| `FloatingNavBar` | **重写** | 设计稿底栏是**贴底的直角容器**（`h-[64px]`、`border-t`、`bg-[var(--lf-card)]/95` + `backdrop-blur`、`grid-cols-5`、`px-2`），**不是现有的悬浮胶囊**（72dp 高、12dp 边距、20 圆角、mint 滑动指示器）。滑动指示器**取消** |
| 普通槽位 | — | 24px 图标 + 10px 标签（选中：图标与标签均 `--lf-primary`、标签 w500；未选中：均 `--lf-muted-foreground`、标签 w400）。`gap-0.5` 竖排，槽高 64dp |
| 凸起槽位（中间） | — | 56×56（`w-14 h-14`）全圆 + 135° 渐变（mint-500→mint-600）+ 白 sparkles 图标 + `-mt-4` 位移 + 白描边阴影。**这是设计稿最强的视觉标识**。净视觉上凸约 9.5dp（§5.8.4 有实测） |
| 页面顶栏 | **新建** | 非首页的顶栏：左侧返回按钮（`back-*`）+ 居中标题 + 右侧动作（如 `cta-rescan`）。**无阴影、无渐变**，与页面同底色 |
| `LfScrollbar` | **新建**（2026-10-04 补） | 常显 + 可拖动的滚动条，把 `Scrollbar` 的默认值收到一处：`thumbVisibility: true`、`interactive: true`。长列表一律挂它——**食物库（随包 49,444 条，v5；2026-10-07 P8b-2 前为 49,464 条）、动作库（312 条）、记录页**（docs/28 §8.3）。传 `controller` 时与列表共用一个（需要按拖动落点做事的页面）；不传时本件自建一个并经 `PrimaryScrollController` 交给子滚动视图。**注意**：`thumbVisibility: true` 必须能拿到附着在滚动位置上的 controller，否则运行期断言失败——子列表不写 `controller` 时才会继承本件给的那个 |

### 3.7 动效件

| 组件 | 状态 |
|---|---|
| `PressableScale` | 保留（0.97 按压缩放） |
| `EntranceItem` | 保留（列表入场） |
| `CountUpText` | 保留（数值滚动）。**注意**：设计稿未声明数值滚动，但它是既有交互增强，保留不影响视觉还原 |
| `AppCelebrationBurst` | 保留（建档完成庆祝） |
| `SkeletonBox` | 保留（加载态） |
| `AppEmptyState` | 保留（空态） |
| `RecPulseDot` | **新建**（录音脉冲） |
| `VoiceWaveBars` | **新建**（参数化两态：录音行 16 根 / 已发送消息 14 根；见 §3.4） |

### 3.8 按钮类（2026-10-03 补章，**此前规范缺失**）

> **为什么补这一章**：§3 原先有容器/图表/表单/对话/徽章/导航/动效七类，**没有按钮类**；
> 而 HTML 里其实有一套完整且一致的按钮语言（下表逐条给出出处）。缺规范的直接后果是实
> 现层各自裸用 Material 默认样式。用户 2026-10-03 点名的今日页「记录第一条」是
> `FilledButton.tonal` 且未设颜色——**实测它走的是 `ColorScheme` 的回落链
> `secondaryContainer ?? secondary`，也就是与「实心主按钮」同色的 mint-600**，
> 于是一颗实心主按钮塞在空态里抢视觉：这正是「空态一律用 B6 文字按钮」这条规则的由来。
>
> 同一份 `ColorScheme` 还有两条**覆盖面更大**的回落（源码 `color_scheme.dart` 的 getter
> 已逐条核对，不是推测）：`onSurfaceVariant ?? onSurface`、`outline / outlineVariant ??
> onBackground`。亮色下 `onSurface / onBackground` 是 M3 默认的**纯黑**、暗色下是**纯白**
> ——所以「次级文字 / 图标 / 分隔线 / 描边」曾经既不是主题的 `mutedForeground` 也不是
> `border`，而是纯黑/纯白。这是「控件跟新主题不搭」里覆盖面最大的一条（Divider、
> IconButton、ListTile 副标题、chip 描边都在这一条上）。
>
> **圆角纪律（§2.3）**：HTML 实测 `rounded-sm|md|lg|xl|2xl` 使用 **0 次**，按钮只出现两种
> 圆角——`rounded-[16px]`（表单/弹层主行动、B8 的 12 亦为实测特例）与 `rounded-full`
> （胶囊、固定底栏确认、图标圆钮）。**不得引入 20/24/32 圆角。**
>
> **阴影纪律（§2.4）**：按钮默认**无阴影**；彩色阴影只允许给主操作元素，且只能用既有的
> 7 条（本节用到的是 `aiPrimaryCta` 35% 与 `scanConfirmCta` 40%），**不新增第 10 条渐变、
> 不新增阴影 token**。
>
> **文字纪律（§2.6）**：按钮文字是 `body 14`；主行动 w600，胶囊/小按钮 w500。

> **选中态判据（2026-10-24，`RV4-P1-07`）**：选择语义的胶囊**必须比未选中更远离背景**。
> 实测旧行为反了——选中底 `brandSoft #ECFBF5` 对白卡 **1.07**，未选中 `muted #EFF3F1` 对白卡
> **1.12**：未选中比选中还显眼，用户说的「点了没反应」在视觉上成立。所以新增 `selected` 档
> （取值见上表），并把「`selected: true` + `tone: muted`」的自动升级目标从 `soft` 改为 `selected`。
> **`soft` 渲染未动**（5 处轻强调动作：识餐修正 / 饮水快捷值 / 菜单去维护 / 训练开始 ×2），
> **`LfColors.brandSoft()` 未动**（10 处主题语义）。回退钉子：`test/app/design/lf_pill_selected_test.dart`。
>
> **设计稿未画的形态**：HTML 没有弹层（dialog/sheet）内的按钮。本规范裁决：**弹层底部主
> 行动归 B2**（与固定底栏确认同类，都是"流程末端的确认"），弹层内次级行动归 B6。

| 组件 | 状态 | 形态 | 尺寸 | 颜色 | 阴影 | 用途 | HTML 出处 |
|---|---|---|---|---|---|---|---|
| `LfPrimaryButton` (B1) | **新建** | 实心圆角矩形 | 16 圆角 / h40（`py-2.5`）/ 14 w600 | 底 `--lf-primary` + 字 `--lf-primary-foreground` | 无 | 表单与弹层主行动 | §2.3 radius-lg「按钮」 |
| `LfPrimaryButton.emphasized` (B1e) | 同上变体 | 渐变圆角矩形 | 16 圆角 / h40 / 14 w600 | `linear-gradient(135deg, mint-400, mint-500)` + `primary-foreground` | `0 4px 16px -4px primary@35%` | AI 类主 CTA（"立即查看专属理想方案"） | `AI 工作.html:449`（`cta-write-plan`） |
| `LfConfirmButton` (B2) | **新建** | 实心**全圆角** | full / h48（`py-3.5`）/ 14 w600 | 底 `--lf-primary` + 字 `primary-foreground` | `0 4px 20px -4px primary@40%` | 固定底栏确认、弹层底部确认 | `拍照识餐.html:513`（`cta-confirm-scan`） |
| `LfPillButton` (B3) | **新建** | 胶囊，`tone` **四态** | full / h32（`py-1.5`）/ 12 w500 | `solid` = primary 底 + 白字；`muted` = muted 底 + mutedForeground 字；`soft` = mint-50 底 + primary 字（带边框时 mint-200）**（轻强调动作，不是选中态）**；**`selected`（2026-10-24 新增，`RV4-P1-07`/D7）** = 亮 `mint-200 #A8EBCF` 底 + `mint-900 #114A36` 字（底 vs 卡面 1.36 / 字对比 7.51）、暗 `mint-300 #2A3A32` 底 + `mint-400 #4ED9A6` 字（1.41 / 6.74） | 无 | 内联动作、筛选、快捷值、"加入早餐"；`selected` 用于**选择语义**（训练天数/目标关键词） | `饮食 · 记录.html:346-350`（tab 胶囊）、`拍照识餐.html:341`（`cta-edit-items`） |
| `LfCircleIconButton` (B4) | 改造（已存在） | 圆形图标钮，`variant` 三态 | 视觉 36（`w-9 h-9`）/ 触达 44 | `muted` = muted 底 + foreground 图标；`primary` = primary 底 + primaryForeground 图标；`overlay` = card@90% 底 + foreground 图标 | 无（**`btn-voice-send` 明确无阴影**） | 返回、上传、麦克风、发送、录音取消/发送、照片上的"重拍" | `AI 工作.html:592-641`、`拍照识餐.html:311/315/327` |
| `LfDashedButton` (B5) | **新建** | 虚线胶囊 | full / h28（`px-2.5 py-1.5`）/ 10 w500 | transparent 底 + mint-300 虚线边 + primary 字 | 无 | "添加"类（添加图片、添加菜品） | `AI 工作.html:583` |
| `LfTextButton` (B6) | **新建** | 纯文字 | 内边距随文本 / 14 w500 | 透明底 + primary 字 | 无 | **空态行动**、取消、查看全部 | 旧稿 `今日.html:481-484`（`cta-view-menu`/`cta-quick-log` 两个已被 Round7 A 退役的捷径）；A 起（阶段 2A）落到餐次卡「查看全部」`cta-view-all-meals` 与各处空态行动 |
| `LfDangerButton` (B7) | **新建** | 纯文字（破坏性） | 同 B6 / 14 w500 | 透明底 + `--lf-state-error` 字 | 无 | 清除数据、删除计划（**必须配二次确认浮层**） | `我的.html:524`（`cta-clear-data` 行式） |
| `LfSmallButton` (B8) | **新建** | 实心小矩形 | **12 圆角** / h36（`px-4 py-2`）/ 12 w500 | primary 底 + primaryForeground 字 | 无 | 设置组内"保存配置" | `我的.html:425`（`cta-save-ai-config`） |
| `LfLinkButton` (B11) | **新建**（Round7 阶段 3 · 3-2c） | 纯文字链接（可带副行） | min **44×44** / 12 w500；可选副行 10 w400（lh 1.6）；可选 16dp 前置图标（间距 5） | 透明底 + `--brand-strong` 字（暗色 mint-400，取 `LfColors.mintText`） | 无 | 食物库页尾两链（「导入食物数据」带副行 /「食物管理」）；A 里页面上最轻的一档，但热区不许缩水 | A `styles.css:135`（`.link-button`）+ `refinement.css:18`（min-width 44）+ `polish.css:26-29`（wrap gap / 副行列排 lh 1.6） |

**按钮硬规则**：
- 触达 **≥44dp**（视觉 36 的图标钮靠 44 触达盒达成，见 §3.6 `LfCircleIconButton` 既有实现）；
  仅有 tooltip 不够，必须有 `Semantics(button: true)` 语义标签。
- 主按钮的"实心档位"随主题走：亮 `mint-600` / 高对比 `mint-700` / 暗 `primary(mint-400)`
  ——与既有 `elevatedButtonTheme` 同源，不得另起一套。
- 空态一律用 B6 文字按钮（2026-10-03 用户裁决），不用实心或淡底，避免与页面主行动抢视觉。
- 破坏性操作必须"文字型 + 二次确认"，设计稿没有实心 error 按钮。
- **B11 是「链接语言」而不是「更弱的 B6」**（Round7 阶段 3 · 3-2c 单列一型）：12 w500 +
  min 44×44 + 可选副行；两件共用同一触达盒（主行 + 副行同一条链）。A 的
  `min-height:46px`（食物详情行动行 `.food-detail-actions .btn`）是**盒高＝连热区一起**：
  `LfTextButton`/`LfDangerButton` 增**可选** `tapTargetSize`（默认 `padded` 不动），只在
  「盒高必须等于 A 实测值」的调用点传 `shrinkWrap`（同 3-2a 给 `LfFilterChip` 的口径）。

### 3.9 徽章与标签族（`LfBadge`，2026-10-03 补章）

§3.5 点名了 `StatusBadge`/`UnitBadge`/`HotBadge`/`PlannedTag` 四件，但实现层从未把它们做成
共享件，于是各页面各写一份（`dashboard_weight_card.dart` 的 `_UnitBadge`、`food_card.dart`
的 `_Tag`…）。收敛为**一件带变体的 `LfBadge`**：

| 组件 | 变体 | 形态 | 用途 |
|---|---|---|---|
| `LfBadge` | `neutral` | 8 圆角 / `px-2 py-1` / 11 w500，muted 底 + mutedForeground 字 | 卡片标题右侧的"周""每 100g"等单位/口径标（原 `UnitBadge`） |
| `LfBadge` | `mint` | 同上，mint-50 底 + primary 字（强调档 mint-100 底 + mint-700 字） | `燃脂中` 等状态标（原 `StatusBadge`） |
| `LfBadge` | `honey` | 同上，honey 系底 + 深字 | `本周热门`（原 `HotBadge`） |
| `LfBadge` | `dashed` | 同上 + 虚线边（mint-300）+ primary 字 | `晚餐 · 计划` 计划态（原 `PlannedTag`；随周计划下线，现无使用点，变体保留） |

> 既有 `LfEvidenceBadge` / `AppEvidenceBadge`（证据等级）**保持独立**：它们承载的是
> 「已确认 / AI 估算 / 待补全」的证据语义（docs/07 诚实性条款），不是装饰性标签，不并入
> `LfBadge`。

### 3.10 输入框类（`LfTextField`，2026-10-04 补章）

> **为什么补这一章**：§3.3 只写了 `TextField` 的**底/圆角/内距**，没写标签；实现层于是沿用
> Material 的 `labelText`。M3 会在聚焦/有值时把 label 升到输入框**顶边之上**——而 `app_theme`
> 给 `enabledBorder` 画了 1px 描边，于是标签正好**骑在描边上**、框内还留着自己的 placeholder
> （用户 2026-10-03 点名的「添加窗口」就是这个形态）。`AppNumberField` / `AppFieldLabel` 一直
> 是唯一做对的写法。收敛为**共用一列「框外标签 + 输入框」的 `LfTextField`**，主题层
> `floatingLabelBehavior: never` 只作安全网。

| 项 | 值 | 说明 |
|---|---|---|
| 标签 | 框**外上方**，与 `AppFieldLabel` 同源（`ExcludeSemantics` 后由 `Semantics` 承载可访问名） | 与 `AppNumberField` 完全同法；单位与「可选」并进标签括号 |
| 底 / 圆角 | `--lf-muted` / 16 | §2.3 |
| 描边 | **常态无描边**；聚焦 2px `--lf-ring`（= `primary`）；错误 1px `--lf-error`；**聚焦 + 错误 2px `--lf-error`** | 无边框是设计稿口径；末一档是实测补的：不定义 `focusedErrorBorder` 时，聚焦的错误框**一条边都不画** |
| 内距 | `h 14 / v 12` | §3.3 `px-3.5 py-2.5` |
| placeholder | `hintText`，muted 色 | §3.3 |
| 错误 | 框沿 error 色 **+** 框下 `bodySmall` error 文案；**框内保持可编辑** | 双表达；错误不是禁用态 |
| 无障碍 | 标签并入输入框节点（模拟遍历读到「标签\|值」一个节点） | §8 |
| Key | 落在**内部 `TextFormField`** 上 | 与 `AppNumberField` 同约定，既有 `enterText` 不失配 |

> **弹层行动行（§3.8 的补充）**：表单弹层的按钮行统一 `Row(spaceBetween)`——**左 = 取消（B6）**、
> **右 = 主行动（B2，`expand: false`）**；破坏性动作仍用 B7。`AlertDialog` 那类壳用
> `actionsAlignment: MainAxisAlignment.spaceBetween`（它透传给内层 `OverflowBar`）达到同一版式。

> **提交型弹层（N7「保存失败不关窗」）**：`AppSheet.showSubmitForm` 由弹层自己持有「提交中 /
> 错误文案」两态——`onSubmit` 返回 `null` = 成功并关闭（返回值由 `resultBuilder` 给出）；
> 返回字符串 = **不 pop**，把这条错误画在行动行上方（`Key('<x>-sheet-error')`），用户输入原样保留；
> 提交中整行 `IgnorePointer` + 主行动 `busy`。落库仍由调用方在 `onSubmit` 里做（表现层不接管业务），
> 但**异常必须翻成一句人话返回**，不要再「先关窗再发 snackbar」——弹层挂在根导航器上，
> 那条提示物理上看不见（§3.3 末尾的硬规则）。

> **弹层体必须自己滚 + 键盘内边距只由壳给一次（2026-10-04 设备 2.0× 抽查补）**：
> `showCustom` 的壳只固定标题与行动行、**不给内容滚动区**——调用方自己要包
> `Flexible(child: SingleChildScrollView(...))`，标题与行动行留在滚动区外
> （`showForm` / `showSubmitForm` 的 body 由壳代劳）。刚性 `Column` 在 2.0× + 键盘下
> 会 `RenderFlex overflowed`，**行动行被画到弹层框之外（键盘底下）** ⇒ 主行动点不到
> （实测 `更新今日体重` 保存按钮落 1855–2008、键盘顶 1563）。同理**不要自己再加一遍
> `MediaQuery.viewInsetsOf(...).bottom`**：壳已经给过一次，叠加会白吃整整一个键盘高
> （实测 `记录饮水`）。

### 3.11 食物卡与食物详情弹层（`FoodCard` / `FoodDetailSheet`，2026-10-04 补章；2026-10-06 按 D14 重写；2026-10-08 按 `docs/30` §2 D1/D2 单行化）

> **为什么补这一章**：食物卡在 `docs/28 §5.1` 之前是 `ListTile` 形态（名称一行 + 热量
> 一行数字），用户 2026-10-03 点名「食物库的界面也很丑，食物卡片的表现形式不直观」，
> 2026-10-04 又点名「右上角的 n kcal 每 100g 太丑，最好图形化」「名称不要有前缀编号，
> 只要品牌和名称，品牌显示在卡片下边」「自建和内置要分开」。这一章把三张屏（食物库、
> 记录页搜索、详情弹层）共用的形态与**缺数据的诚实口径**钉死。
>
> **2026-10-06（P8a）按 `docs/29` D14 重写**：用户 2026-10-05 走查要求「宏量指标位置要
> 固定，没有的写 0g」「圆环小一点（三个营养同行）」「只要克数不要百分比」「自建/内置放
> 卡片右下角」「品牌做带边框小标签放左下角」，与本节旧版的「`0` 也当没有」「缺项的宏量
> **不占位**」「占比行整行不渲染」正面冲突 ⇒ 按 D14 改为**固定三格、缺值与 0 都写 `0g`**；
> 「上游把『没填』写成 0」这条数据事实移到 `docs/07` 数据契约。逐条落点见
> `docs/29` §P8a 与设计稿 `ui设计/remediation/食物库-卡片与抽屉.html`。
>
> **2026-10-08 第四轮再收一次（`docs/30` §2 D1/D2，用户走查需求 1）**：用户原话「食物库
> 的数据，主界面只显示图标，名称和再小一点的热量圆环，都在一行，水平居中，卡片缩短上下
> 宽度，点击后的卡片才显示详细的三营养数据，三行数据的所在行需要与圆环的圆心上下对齐」。
> 于是**前两轮逐条加出来的四行（环下口径行 / 宏量三彩点行 / 品牌 chip + 自建·内置徽标行 /
> 「营养不完整」文字行）全部收回**，卡恒为**单行三件**；详情弹层从「三格一行」改成
> **三行竖排**，且**三行块中心 = 环心**。逐条落点与几何算式见
> `docs/evidence/2026-10-08-r3-food-card.md`，设计稿
> `ui设计/remediation/食物库-单行卡与详情.html`。

| 项 | 值 | 说明 |
|---|---|---|
| 卡（单行三件） | ① 40dp 分类图标 ② 清洗后产品名（`maxLines: 1` + ellipsis）③ **能量密度环 36dp / stroke 4**（`LfDimens.foodKcalRingSmallSize`；刻度 `kFoodDensityFullScaleKcal`，2026-10-09 由 900 改 **1000**）。三件 **`CrossAxisAlignment.center` 共一条水平中线** | 「水平居中」的落点 = **三件沿同一条水平中线**，不是「整行内容在卡内水平居中」：名称长度天然不一，整行居中会让扫一列卡片时名称起点逐行跳动。**环必须比图标（40dp）矮**：44 档会把行高顶到 44+，与「卡片缩短上下宽度」相反；36dp 时行高由图标决定 ⇒ 卡高 = 40 + 上下各 8 = **56dp**（上一版五段卡实测 ≈136dp，同屏从 ~2.5 张变 ~6 张） |
| 卡上不再有的四件 | 环下口径行、宏量三彩点行、品牌 chip + 自建/内置徽标行、「营养不完整」文字行 | 全部退到**详情弹层**（点卡才有）。`brand` / `isUserCreated` / 三个宏量参数**保留在构造器上**（调用点两处都还在传，删参数会牵动与本轮无关的改动面），只是卡面不再渲染 |
| 唯一的例外：不可加入计划 | `canJoinPlan == false` 时在**名称之后**内联一枚 12dp 警告图标（`food-card-incomplete-<id>`）+ `Semantics('营养不完整，不可加入计划')` | `docs/07 §9.3`「能搜到不等于能进计划」是**功能事实，不能只活在详情里**。它不占独立行、不加卡高（原型仍是单行），也不贴右边缘（贴右会与环挤在一起，且看不出它修饰的是名称） |
| 卡内边距 | `EdgeInsets.symmetric(horizontal: 12, vertical: 8)` | 单行卡里没有底行，留 12 会让上下明显不等厚（上一版是 `12/12/12/8`，因为底行自带 23.4dp 行高） |
| 满刻度上屏 | 列表头**一句** `环 = 每 100g 能量密度 · 满刻度 1000 kcal/100g`（`FoodDensityScaleNote`，数字由常量插值 `kFoodDensityFullScaleKcal`；2026-10-09 docs/31 S3 需求 49 由 900 改 1000——纯油脂约 900 不该顶格） | 不逐卡重复（需求 23）：卡上已经**没有**第二行放口径，而环的语义不能只靠记忆 |
| 详情弹层（环列只放环） | 食物名（headline）+ 品牌 · 徽标 + **大环**（`foodKcalRingLargeSize` 56dp / stroke 6）+ **三行竖排宏量块**（`MacroDotRows`，每行：彩点 6dp + 名称 + 克数）+ 环的口径一行 + 行动（编辑 / 删除，仅自建） | 份量 / 营养修订 / 来源证据三节**从这一屏删掉**（数据层照旧，别处有归属：许可证在「我的 → 数据来源与许可证」）。**供能占比行整行删除**（需求 28）：同一份数据既写百分比又写克数迟早打架 |
| 三行块 ↔ 环心对齐（需求 1 后半句） | 三行块 = 行高 17 × 3 + 行距 8 × 2 = **67dp**，块中心 33.5dp；环列**只含环**（56dp），`Row(crossAxisAlignment: center)` 下环被下推 (67−56)/2 = 5.5dp ⇒ 环心 28 + 5.5 = **33.5dp = 块中心** | **对齐的前提是环列里只有环**：上一版环列 = 环 56 + 2 + 口径标签 14 = 72dp，`center` 居中的是**整列**⇒ 三格文字落在环心下方 8dp —— 这正是用户说的「对不齐」。行高用 `minHeight` 而不是定高 `SizedBox(height:)`：定高在 2.0× 下把 33.6dp 的文字塞进 17dp（拦腰截断），而 `center` 是按实际高度算的（块变高、环跟着下推，环心仍在块中心） |
| 宏量口径（D14，口径未变） | **恒为三行**：数值 > 0 写值；`null`（上游没给）与 `0`（上游把没填写成 0）都写 `0g`（`macroGramsOnScreen`，显式三态） | 位置固定 ⇒ 三行的 y 坐标恒定，「行 ↔ 环心」这条对齐才有对象。`0g` 是**显示约定、不作为计算依据**；「这一项没有 / 这条不完整」由「营养不完整」那句承担，两者并存、互不替代 |
| 热量口径 | 环走**事实判断**（`kcalOrMissing`）：`null` 与 `0` 都当没有 ⇒ 环里写 `—`、口径行写「无热量数据」（有热量时才讲 0–1000 满刻度） | 与宏量那三行的口径**不同且各自成立**：热量那一格说的是「这条数据没有热量」，不编 `0 kcal` |
| 列表行高已知 | `SliverPrototypeExtentList` 的原型卡 = **真卡形态**（单行三件） | 单行化后**所有变体天然等高**（「营养不完整」不再占独立行）⇒ 原型不再需要「取最高变体」。一页失败的「说明 + 重试」也从竖排（写死 96dp）改成**一行横排 + `FittedBox.scaleDown`**：96dp 塞进 56dp 的行里实测 RenderFlex overflow 13px |
| 顶栏 | 食物库 tab **没有**细顶栏；自建食物入口在搜索框右侧（`LfCircleIconButton`，命中盒 44 / 视觉圆 36） | `LfTopBar` 是共享件（拍照识餐 / 食堂目录 / 下一餐推荐 / 动作库 / AI 对话五处二级页都要返回键）⇒ 加 `showBack`/`showTitle` 开关（**默认 `true` = 现状不变**），撤的是食物库那一条的渲染，不是组件本身（需求 29/30） |
| 两条数据路径 | 分页浏览（`FoodLibraryView`）与仓库直搜（`FoodSearchTab`）共用同一张卡、同一套骨架/空态、同一条搜索行（`FoodLibraryHeader`，Key = `NutritionTabs.foodLibraryHeaderKey`）与同一枚「自建食物」按钮 | 入口与呈现只有一份实现（页头也因此从两份手写改成共享件 `food_library_header.dart`），用户看到的食物卡不因数据来源而变样 |

> **2.0× 复核点**：删掉占比行之后不再有「名称 / 百分比」折行的退化路径；卡上三件
> （图标定宽 / 名称 `maxLines: 1` / 环定宽）任何字号下都在一行；详情弹层三行块
> 行高随字号增长（`minHeight`），环跟着下推、环心仍在块中心。
> 骨架 `FoodCardSkeleton` 与真卡**逐件同构**（图标 40 / 名称条 / 环 36 + 内边距 12/8）——
> 骨架与真卡差几十像素时列表会在加载完成时整体跳一下（2026-10-04 的旧毛病）。

> **Round7 阶段 3（2026-10-14）as-built：食物库 tab（3-2a–3-2d）与详情/表单按 A 收口**
> （A `app.js:188–202/369/375`；决策 D31–D52 与逐条证据见
> `docs/evidence/2026-10-14-round7-native-implementation.md`）。**本节中与之冲突的形态描述以本块为准**：
> - **列表**：单卡 `.food-list`（`FoodListCard` = `DecoratedSliver` 卡面 + 行内衬左右 12）包住行
>   （`FoodListRow`：行高 **56** = 图标 40 + 上下 8；行间 1px `--track` 分隔线**不进布局**、
>   **末行不画**；分类方框 40×40 **r12** 底 `--bg` 且图形充满（`FoodCategoryIcon` 的
>   `background`/`padding` 由调用点给）；名称 14 w600；环 36/4 + 环心 **10**；
>   `canJoinPlan=false` 的警告图标 16dp **`info_outline`**，**色仍 `warning`**——D38 反向偏离：
>   这一格是功能事实（不可加入确认计划），不降成 A 的 muted）。两条数据路径与骨架同件同形。
> - **分类筛选**：`LfFilterChip`/`LfFilterChipRow`（A `.food-category-row`：min-height 44 / 横滑 /
>   gap 4 / 命中 `--brand-soft` 底 + `--brand-strong` 字 w600；`tapTargetSize: shrinkWrap` 必须，
>   否则 Material 把布局盒撑到 48）+ `FoodCategoryChipRow`（「全部」+ `FoodCategory.values`
>   十档**真实**分类，不用 A 的 8 枚演示标签；筛选判据 = **落库枚举 id**（`tryFromId`），
>   不猜关键词）。数据面：`FoodRepository.count/page` 增**可选**分类 `WHERE`（默认 null ⇒
>   老路径一字不改）；`FoodLibraryItem.category` 在主库行补上（**修既有语义洞**：旧实现
>   按分类筛会把用户导入的主库筛空）。
> - **结果头**：`FoodLibraryResultsHead`（`food-library-count`）＝「**N 种食物**」+
>   「kcal / 100g」两端，**0 行也画**（D32 按 A 字面；旧「全部 N 条 / 搜到 N 条」退役）。
> - **空态两分支**（`FoodLibraryEmptyState` → 共享件 `LfEmptyState`）：无结果
>   「没有找到这类食物」+ `food-empty-clear`；真空库「食物库还是空的」+ `food-empty-import`
>   （走**真实 CSV 导入**通路；A 的「导入示例食物」不搬 = 不塞演示数据）。空态宿主 =
>   `Center + SingleChildScrollView`（键 `food-empty-scroll`；矮视口可滚降级，缺陷 ⑬ 的修法）。
>   A 的 `.subtle-note`「演示食物」不搬（D43）。
> - **页尾**：`FoodLibraryFooter`（`food-library-footer`）＝**贴底条**——D44 **偏离 A 的流内页尾**：
>   本仓 `itemCount` 是总数（可达 4.9 万行），流内页尾 = 两个死入口；**底栏预留改由条承担**
>   （`LfInsets.navReserve`），列表末端只留 8；两链回调都缺省时条仍占预留。链 = §3.8 的
>   **B11 `LfLinkButton`**：「导入食物数据 / 从文件读取到食物库」（`-import`）与「食物管理」
>   （`-manage`）——分别接既有 CSV 通路（`runFoodCsvImportFlow`）与共享「食物数据」弹层
>   （`showFoodDataSheet`，标题「食物库管理」）；两条通路提到 `presentation/food_data_flows.dart`，
>   **21 列契约与单事务守卫单源**，设置页标题与 `food-data-sheet-*` Key 一字不动。
> - **详情弹层**（`FoodDetailSheet`）：弹层首行标题「食物详情」；**meta 行只写品牌 +
>   `LfBadge`（自建/内置）——分类的文字 2026-10-21（ADR-036）从详情里撤掉：种类是**列表的
>   筛选维度**，由搜索行下面的 `food-library-category-row` 承担（同一值在一屏上说两遍互相打架），
>   分类的**图形**仍留在 hero 图标块上（与点进来的那一行同一枚）。hero = **52×52 r16** `--bg`
>   图标块（图形 40 ⇒ 内衬 6；分类与列表行**同一 `FoodCategory.classify`**）+ **20px w600**
>   名称（A 20 w650 → 仓内 600）+ **12px muted** meta（品牌 + `LfBadge`，`Wrap` gap 6、
>   距标题 7；品牌仍是**裸品牌名的独立文本**，两处精确断言在册）；营养面板 = **r16 + 1px
>   `--border` 实描边 + `--bg` + 内衬 18**、环列 56 与宏量列间距 **24**；大环 56/6、**环心 14**
>   （A 14 w700 → 600）；宏量行按 A `.food-macro-stack`（点 **7** / 点距 **8** / 名称 **12** /
>   克数 **14 w600 右端** / 行高**铁定 17**，高度因子 17/14）——三行块 67 与「环心 = 块中心」的
>   算式不变；口径注 `FoodDensityScaleNote` **横跨整宽居中**（共享句单源；`textAlign` 为可选
>   参数、列表头继续左对齐）；行动行 = 1px `--track` 上边线 + padding `12 0 2` + 两枚 **46 高**
>   等宽按钮（**B6/B7 文字型** + `edit/trash` 图标；A 的描边型不搬 = 2026-10-03 裁决）。
> - **新建/编辑表单**：品牌下方新增**可选「别名」**输入（ADR-037；Key `new-food-aliases`，
>   占位文案「多个用逗号分隔，如：西红柿、洋柿子」；编辑态回显现有别名、保存即替换）；
>   四个数字字段落 A `.form-grid` **2×2**（gap 12；字段名与 Key 不动——它们
>   已自带「每 100 g」口径）+ 表单注 `new-food-note`（只写成立的三段：每 100g / 热量 0 按无数据
>   展示 / 改动不会回写已记餐次；A 的「留空表示未知」与本仓必填校验矛盾，不搬）。
> - **新增 Key（本阶段）**：`food-library-category-row`、`food-category-chip-all`、
>   `food-category-chip-<id>`、`food-library-count`、`food-library-list`、
>   `food-library-row-divider-<id>`、`food-empty-clear`、`food-empty-import`、`food-empty-scroll`、
>   `food-library-footer`、`food-library-footer-import`、`food-library-footer-manage`、
>   `food-library-delete-confirm`、`food-detail-sheet`、`food-detail-hero`、
>   `food-detail-brand`、`food-detail-meta`、`food-detail-panel`、`food-detail-actions`、
>   `food-detail-edit`、`food-detail-delete`、`food-detail-ring-kcal`、`food-detail-ring-label`、
>   `food-detail-loading`、`food-detail-error`、`food-detail-missing`、`new-food-name`、
>   `new-food-brand`、`new-food-brand-hint`、`new-food-aliases`（ADR-037 可选别名输入）、
>   `new-food-category`、`new-food-save`、
>   `new-food-sheet-error`、`new-food-note`、`new-food-每 100g <项>`。
> - **观察项已裁决落地（2026-10-15，用户批准）**：`FoodDetail.canJoinPlan` 原为 getter
>   （`state == verified|estimated`）——`state` 里的 `user_created` 是**来源**值，于是
>   自建 + 四值齐的食物在详情被判「不可加入确认计划」，与列表卡（主库行恒 `true`）打架。
>   现改为**显式 `required final bool canJoinPlan`**，规则**逐来源**给、与列表卡同源：
>   主库装载器（`food_detail_repository.dart`）⇒ `true`（主库行四值必填 = 完整）；
>   分片装载器（`catalog_shard_detail_source.dart`）⇒ 上游质量档（同 `CatalogSearchRow`）。
>   自建食物的详情**不再**显示「营养不完整，暂不可加入确认计划」。

### 3.12 地点 chip 的「描边档」（`AppMorphChipVariant.outlined`，2026-10-04 补章）

> **为什么补这一章、又为什么不是 §3.10**：`docs/28 §4.5` 要求「地点项（新规格，写进
> `docs/21 §3.10`）」，但 §3.10 已在 W1 被「输入框类（`LfTextField`）」占用 ⇒ 新规格
> 落到本章；`docs/28 §4.5` 里的编号是笔误（用户裁决：文档与实测不符以实测为准，记录
> 后回改文档）。**不新造第三个 chip 件**：全仓只有 `AppMorphChip` 一枚（防回退审计
> 依赖这个事实），新形态是它的第二档参数。

| 项 | 值 |
|---|---|
| 常态 | `semantic.card` 底 + 1px `semantic.border` 描边 + `foreground` 字 |
| 选中 | `semantic.card` 底（**不换底**）+ **2px `mint-600` 描边** + `mintText`（亮色 `mint-700`）字 + `BoxShadow(0, 1, 3, mint-500 @30%)` 轻微抬升 |
| 圆角 | **恒为胶囊**（`radiusFull`）——选中不再靠形状变化表达 |
| 高 | `LfDimens.minTouchTarget`（**44**，触达线；低于它就不该当作可点控件） |
| 内距 | 横 `spaceMedium` / 纵 `spaceSmall` |

**选中态重做（2026-10-06，docs/29 §P7 需求 19）**：旧选中态是「`mint-50` 极淡底色 +
1px `mint-200` 描边 + 左侧 6dp 圆点」——三个信号里两个极淡（淡底 & 淡描边）缩略图/远看
几乎不可辨，剩下那个圆点又让 chip 内部多出一个与文字无干的形状。新选中态把权重压到
**一个信号**：描边加粗到 2px 且换 `mint-600`（对比度足够）、文字换 `mintText`、下面
加一枚 `mint-500 @30%` 的 1px/3px 抬升阴影。**圆点删除**：色觉障碍下「描边粗细 + 文字
颜色」两个信号仍可区分（粗细不依赖色相）。

**为什么抬升阴影不算违反 §2.4 阴影白名单**：§2.4 管的是**按钮 CTA**（不给每个按钮加
投影）；chip 的抬升是**控件状态表达**（选中≠未选中），且 `mint-500 @30%` 是 **§2.4 白名单
色**——不引入新常量、不与卡片投影同权重。

**为什么与变形档（§3 默认档）分开**：变形档的表达是「形状变化」（s 圆角扁块 ↔ 胶囊），
在筛选用途上会被误读成「折叠 / 展开」；地点选择是**单选**，需要的是「同一形状里换描边
粗细与字色」——不靠形状变化，也不靠底色深浅。

**用在哪**：`CanteenVenueSelector`（菜单页 / 食堂目录页的地点行）。横向可滚
（`ListView.separated`，高 44）。

---

## §4 导航架构

### 4.1 底栏（5 槽，`data-mobile-nav="global"`）

| 槽序 | key | 图标 | 标签 | 路由 | 形态 |
|---|---|---|---|---|---|
| 1 | `dashboard` | home | 今日 | `/today` | 普通 |
| 2 | `nutrition` | utensils | 饮食 | `/nutrition` | 普通 |
| 3 | **`ai`** | **sparkles** | **AI** | `/ai-chat` | **凸起圆** |
| 4 | `training` | dumbbell | 训练 | `/training` | 普通 |
| 5 | `settings` | user | 我的 | `/settings` | 普通 |

> **与当前实现的差异（已裁决）**：当前中间槽是**拍照**（`/scan` 分支，相机图标，凸起圆）。新设计中间槽是 **AI 对话**。
> **处置**：取消 `/scan` 作为 shell 分支；**拍照识餐改为推入式二级页**，从 AI 对话页的 `拍照识别` chip 与饮食页的 FAB 进入。已有的 `/meal-recognition` 推入式路由保留并成为唯一入口。

### 4.2 二级页（推入，带返回）

| 页面 | 进入方式 | 返回目标 |
|---|---|---|
| 拍照识餐 | **2026-10-23 起无 UI 入口**（AI 对话 `cta-photo-scan` chip 已按用户要求换成「确认应用」；页面与路由保留，深链仍可达） | 来源页（`back-nutrition` 的语义按设计稿 = 回结果页） |
| AI 工作台 | 现有入口（今日页 AI 卡等） | `/today` |
| 训练计划新建 | 训练页 `cta-new-plan` → 模式弹层「AI 生成」 | `/training` |
| 手动创建计划 | 训练页 `cta-new-plan` → 模式弹层「手动创建」 | `/training` |
| 训练会话详情 | 训练页「查看详情」/`cta-continue-session` | `/training` |
| 建档引导 | 首次启动 | — |
| 资料编辑 | 我的页 `cta-edit-profile`（**`push` 进入**，页面只有 `onClose` 一条出口） | `/settings` |
| 饮食各 sub-tab | 饮食页 chips（记录/菜单/食物库） | 页内切换，非路由 |
| 校园食堂 / 食物库 | 饮食页对应 sub-tab 内 | 页内 |

### 4.3 饮食页的 sub-tab 结构（设计稿 `tab-*`）

| chip | key | 设计稿状态 | 说明 |
|---|---|---|---|
| 记录 | 无 id | 记录页 **active** | `饮食 · 记录.html` 全文 |
| 菜单 | `tab-menu` | 菜单页 **active** | `饮食 · 菜单.html` |
| 食物库 | `tab-foodlib` | — | 现有食物库（样式化） |

> **五项 → 三项（2026-10-04，docs/28 §6.1）**：设计稿画的是五项 chip（记录/计划/菜单/食谱/食物库），其中「计划」「食谱」两枚随「食谱 / 周计划」整族下线，应用只保留上表三项；`nutrition-tab-plan` / `nutrition-tab-recipe` 两个 Key 与 `NutritionTabs.planIndex` / `recipeIndex` 一并删除。设计稿 HTML 里的 `tab-plan` / `tab-recipe` **不再是实现目标**。

> **注意两个文件各自的 `id` 缺口（实测，容易看反）**：
> - `饮食 · 菜单.html` 的 chip 行是 `tab-record`（**带 id**）+ `tab-plan` / `tab-recipe` / `tab-foodlib`；**没有 `tab-menu`**——因为它自己就是菜单页（`tab-plan` / `tab-recipe` 已下线）。
> - `饮食 · 记录.html` 的 chip 行是 `tab-menu`（**带 id**）+ `tab-plan` / `tab-recipe` / `tab-foodlib`；**没有 `tab-record`**——因为它自己就是记录页（同上）。
>
> 即：**每个文件都省略了自己那个 active chip 的 id**（active 态直接写成内联样式，故不配 id）。本文 §5 的 Key 表补的是 `nutrition-tab-*` 三个**统一**命名（记录/菜单/食物库），与设计稿的 id 缺口无关。
>
> chip 行是 **sticky** 定位（设计稿 `sticky top-0`）。

### 4.4 交叉导航图（设计稿实际声明的跳转）

```
今日 ─ cta-view-all-meals ──→ 饮食·记录（餐次卡「查看全部」，A `nutrition-records`）
     ├ cta-log-meal ────────→ （2026-10-22 退场：块按钮「记录饮食」删除，
     │                          D9 通道改由 cta-log-dinner / 饮食页 FAB 承担）
     ├ cta-log-dinner ──────→ 餐食编辑（下一餐卡，槽位 = 晚餐，D9 意图通道）
     ├ cta-ai-workbench ────→ AI 工作（AI 创作行）
     ├ 底栏「饮食」─────────→ 饮食·记录 / 菜单 / 食物库（D4：今日页不再有菜单捷径）
     └ avatar ─────────────→ 我的（设计稿未声明，按惯例）
饮食·记录 ─ FAB ────────────→ 餐食录入
        └ tab-chips ────────→ 饮食·菜单 / 食物库
饮食·菜单 ─ tab-chips ──────→ 饮食·记录 / 食物库
        └ cta-add-meal-N ───→ 加入该餐
拍照识餐 ─ back-nutrition ──→ 返回
        ├ cta-rescan ───────→ 重新识别
        ├ cta-retake ───────→ 重新拍摄
        ├ cta-edit-items ───→ 修正食材
        └ cta-confirm-scan ─→ 确认记录此餐（固定底栏按钮）
AI 工作 ─ back-dashboard ───→ 今日
       ├ ai-chat-chip-remaining → 今天还剩多少（本地算，不发模型）
       ├ ai-chat-chip-log-meal → 记一餐（复用 B3 的 openMealRecordSheet，不跳页）
       ├ cta-write-plan ────→ （食谱计划预览：随「食谱 / 周计划」整族下线，此跳转已移除，按钮不再接线）
       └ 三个快捷 chip ─────→ 今天还剩多少 / 记一餐 / AI 创作
训练 ─ cta-continue-session → 训练会话（现有训练器）
    ├ 查看详情 ─────────────→ 训练会话详情（现有弹层）
    └ cta-new-plan ─────────→ 模式弹层（AI 生成 / 手动创建，docs/30 §2 D7）
        ├ plan-mode-ai ─────→ 训练计划新建（现有页面 /workout-plan-create）
        └ plan-mode-manual ─→ 手动创建计划（/workout-plan-manual）
我的 ─ cta-edit-profile ────→ 资料编辑（push；训练目标 + 身高/年龄/性别，2026-10-05 docs/29 §P1）
    ├ settings-ai-model-row ─→ AI 配置弹层（协议 / Base URL / 模型+探测+模型列表 / 推理开关 / API Key；2026-10-05 docs/29 §P4）
    ├ cta-backup / cta-restore / cta-export-csv → 现有备份/恢复/导出
    └ cta-clear-data ───────→ 清除所有数据（现有，需二次确认；2026-10-23 起
                              **内置食物库（含导入行）保留**，自建食物才删）
```

---

## §5 逐页规范

> 每页给出：结构树 / 数据来源 / 交互 / 空态 / 测试 Key。**Key 命名约定**：`<page>-<element>[-<index>]`，kebab-case，页前缀为 `dashboard-` / `nutrition-record-` / `nutrition-menu-` / `scan-` / `training-` / `settings-` / `ai-chat-` / `onboarding-`（§5.9）。

### 5.1 今日页（`今日.html` / Round7 A 变体 A）

> **2026-10-14（Round7 阶段 2A）本节按 A 重写**：权威源是 `design/round7/index.html`
> 的**变体 A**（`app.js` 的 `todayPage()`，级联有效值见 docs/33 §1.2 与
> `docs/evidence/2026-10-14-round7-native-implementation.md` 阶段 2 段）。栏目
> 顺序、卡内结构、Key 与文案以 A 为准；A 未画而原生已有的事实（百分比第三行、
> 增减量、空态行动等）按 docs/33 §1.1 保留，逐条记在证据文件的 D1–D13 决策表。

**结构树**

```
ListView (pagePadding 16, bottom = navBarReservedSpace)
├ 问候头 page-head                   ← 无 AppBar，直接顶部；min-height 50
│   ├ 问候 "早安，小林" h1           22px w800
│   ├ 日期 "9月23日 周二"            12px muted（问候下 3px）
│   └ 头像 44 圆                     brand-soft 底 / brand-strong 首字 / 描边
├ EnergySummaryCard（热量卡）        A `.energy-summary`：padding 16/18/18
│   ├ card-row: "今日营养"           15px w600 + 状态徽标（「燃脂中」）
│   │                               （历史日期写「当日营养」，A `date===today?`）
│   ├ energy-main                    grid 120px|1fr / gap 20 / padding 18 0
│   │   ├ CalorieRing 120            中心：值 26 + 「已摄入 kcal」+「N%」第三行（D6）
│   │   └ MacroBar × 3（蛋白/碳水/脂肪）5px 点 + 标签 12 muted +
│   │                               值 15 + 「/ N g」11 muted + 5px 轨（跨两列）
│   ├ energy-foot                    上边框 1px track / padding-top 11 / 11px
│   │   ├ 左「目标 N kcal」          （无目标 → 「尚未设定目标」）
│   │   └ 右「还可摄入 N kcal」/「超出 N kcal」（无目标 → 「设置目标后查看进度」）
│   └ macro-ratios 10px              整卡宽一行（A 从右列移到 main 之下）
├ WeightChartCard（体重卡）          A `.weight-card`：padding 10/16/14；
│                                   semanticLabel='本周体重'/'本月体重，近一个月'
│                                   （docs/31 S8：该参数曾是死参数被静默丢弃，
│                                   2026-10-10 起真进语义树）
│   ├ 标题「体重趋势」               恒为「体重趋势」（周/月之别由 mini-tabs 的
│   │                               选中态 + 周期注 + 读屏标签三处表达）
│   ├ mini-tabs 36                   周/月（dashboard-weight-range，LfSegmentedToggle）
│   ├ 添加图标钮                     36dp 视觉 / 44dp 命中（dashboard-weight-add）
│   ├ caption                        值 26 w750 + `kg` /「最近记录（↓/↑ M）」
│   │                                （2026-10-16 用户裁决：不再写周期注）

│   └ WeightBarChart                 高 150（含 25dp 标签行）；轴宽 30；柱 max 22；
│                                    默认 --weight、当前日 = brand；测点浮窗；
│                                    hint 10px（有柱才画）
├ 饮水 / 步数两格                    grid 1fr 1fr / gap 12；卡 padding 14 /
│   │                                min-height 183
│   ├ 水卡                           标题 14 + 状态徽标；值 22 档 + `ml`；
│   │                                「目标 N ml」；「+ 250 ml」文字按钮
│   └ 步数卡                         同构；四态（有数据 / 未授权 / 无传感器 / **已关闭**）；
│                                    2026-10-16 用户裁决删掉「查看详情」行（R11 作废）——
│                                    卡上不再有进弹层的入口；应用内开关与「去系统设置」都在
│                                    设置页「步数与身体活动」那一枚弹层里（`showStepsPermissionSheet`）
│                                    「目标 N 步」+「还差 N 步」；关闭态正文指路「在设置页
│                                    「步数与身体活动」里重新开启」
├ NextMealCard（下一餐）             A `.next-meal`；新卡（旧 bento 已按 docs/22
│   ├ 标题「下一餐，留给晚餐」+ pill   裁决② 收进二级）
│   ├ 预算行 22 + 轨 + facts         facts 18 间距 / 11px：N 笔已记 · 目标 N
│   └ 「记录晚餐」块按钮             outline brand（D9 意图通道）
├ MealsCard（餐次卡）                A `.meals-card`
│   ├ section-title "今天吃了什么" + 「查看全部」（→ 记录页）
│   ├ N × meal-row                   36 symbol + 槽位 12/600 + 时间 11 +
│   │                                菜名 12 + kcal 14 w600（行可点开编辑）
│   ├ 空态                           图标 + 「从第一餐开始」+ 说明
│   ├ source-summary                 小环 20 + 「已确认 N 项 / 估算 M 项」11px
│   │                                brand-strong（零餐不渲染，D5）
│   └ 「记录饮食」块按钮             （D9 意图通道）
├ AiEntryLine（AI 创作）             A `.ai-entry-line`：36 mint chip + 13 标题 +
│                                    12 副标题 + chevron（平卡，非渐变 hero）
└ QuickStatsRow                      2 列（见上「饮水 / 步数两格」）
```

> A 的 `sample-strip`（示例数据横幅）与 `activity`（进行中训练卡）不移植，见
> 证据文件 D1 / D2；A 的 `.page` 上边距 12 由主壳统一承担。

**数据来源**

| 元素 | 来源 |
|---|---|
| 日期 / 问候 | `now`；问候按小时切换（早/午/晚） |
| 头像首字 | 本地档案姓名首字；无档案 → 「Fit」 |
| 剩余 kcal | `DailyTargets.calorieMaxKcal − 今日已摄入`。为负时改口「超出 N kcal」（A 的 `.energy-foot`；负号不显示，见 `LfEnergyCard`） |
| 圆环 | 已摄入 / 目标；百分比 = round(consumed / target × 100)，第三行（D6） |
| 三条宏量 | `MealItems` 快照聚合 / `DailyTargets.protein|carbs|fat` |
| 宏量占比 | 4/4/9 kcal/g 计算（现有 `_MacroRatios` 逻辑保留） |
| 靶标 kcal | `DailyTargets.calorieMaxKcal`；无目标 → 「尚未设定目标」（诚实文本，不用示例值） |
| 体重柱图 | `Measurements` 本周 `weightKg`（周视图恒定七格，无记录日空槽）/ 本月自适应分箱均值（月视图，口径=本月） |
| 下一餐 | 同一天的 `DailyNutritionSummary`（预算 = 目标 − 已摄入；facts = 当天餐数 + 目标）；**无新数据源** |
| 餐次卡 | `Meals` + `MealItems`（按 `slot` 排序；行 = 槽位 + 首项时间 + 菜名 + 该餐 kcal）。**原「计划态」= `MealPlanEntries` 当天有、`Meals` 没有的 slot，随该表删除整段移除（再无写入路径 ⇒ 死 UI）**。原时间线 14 节点形态退场（D4） |
| source-summary | `MealItems.source`：已确认 = 非估算项 / 估算 = 估算项；**零餐不渲染**（D5） |
| 饮水卡 | **新增域**饮水摄入 / `DailyTargets.waterTargetMl` |
| 步数卡 | 本机计步（`ACTIVITY_RECOGNITION` 权限 + MethodChannel）；三态见下 |

**交互**

| 元素 | 行为 |
|---|---|
| 头像 | 跳 `/settings`（`dashboard-avatar`） |
| MacroBar / 圆环 | 只读，无点击（环中心三段文字不响应点击，D6） |
| 体重卡「添加」（纯图标 `LfIconButton`，docs/31 S1 需求 44） | 打开体重录入弹层（现有 `WeightEntryDialog`）。**整卡不再可点**（2026-10-07 P9 已改口径） |
| 体重卡 周 / 月切换（统一轨道 `LfSegmentedToggle`，`dashboard-weight-range-week` / `-month`） | 切换分段，换柱图数据口径（2026-10-10 docs/31 S1 需求 39：两颗独立胶囊 → 统一轨道 + 内嵌白滑块，视觉压到 28dp——R3 嫌的是尺寸不是形态） |
| 体重测点（`weight-bar-chart-bar-<i>`） | 点击柱条开浮窗（值 + 日期），**再点同一条收起**；滚动页面也收起（A `weight-point` 的 toggle 语义） |
| 体重图空态「记录第一条」（`dashboard-weight-record`） | 打开同一个体重录入弹层 |
| 下一餐卡「记录晚餐」（`cta-log-dinner`） | 经 D9 意图通道打开餐食编辑（槽位 = 晚餐），落到既有 `MealEditorDialog` |
| 餐次卡「查看全部」（`cta-view-all-meals`） | 跳 `/nutrition-records`（记录页）。**A 的今日页餐次卡没有菜单入口**（D4） |
| 餐次卡「记录饮食」（`cta-log-meal`，**2026-10-22 退场**） | D9 通道改由 `cta-log-dinner` 与饮食页 FAB 承担 |
| 餐次卡行（`dashboard-meal-row-<slot>-<i>`） | 点击已记录项 → 该餐详情弹层（原「点击计划项 → 加入/记录该餐」已随计划态移除） |
| 饮水卡 | 点击 → 加水弹层（2026-10-16：卡内「+ 250 ml」按钮下线，整卡仍是入口） |
| 步数卡 | 未授权：**只留右上角「未授权」徽标**（与已授权态逐像素同构，占位文本不进语义树），点卡片申请权限；无传感器：「这台设备没有计步传感器」（docs/31 需求 48，P9 接线） |
| AI 创作行（`cta-ai-workbench`） | 跳 `/ai-workbench`（AI 工作台；A 的 `.ai-entry-line` 平卡形态，不再是渐变 hero） |

**空态**

| 场景 | 呈现 |
|---|---|
| 无任何记录 | 圆环 0 / 目标、宏量全 0；餐次卡显示「从第一餐开始 / 从食物库选择，记录实际吃下的食物。」+ 「记录饮食」；**source-summary 不渲染**（D5，零餐 ≠ 零值记录） |
| 无体重数据（**真的 0 条记录**） | 柱图区显示「本周/本月还没有记录」+ 「记录第一条」入口。**1 条记录不再算空态**：柱图天然支持单柱（2026-10-08 R2 修复了旧口径「2–7 条月视图只出 1 点 ⇒ 谎报没有记录」） |
| 无目标 | 热量卡 foot 左写「尚未设定目标」、右写「设置目标后查看进度」；环内不画百分比第三行（没有分母就没有百分比，D6）；**剩余额度行不在**（它是派生量） |
| 步数未授权 / 无传感器 | 只留徽标 + 同构骨架（文案不进语义树），与「0 步」互不混同（docs/31 需求 48） |

> 2026-10-16（第二轮用户实测）：今日页两卡改为「标题 / 数值 / 进度条」三行同构并**去掉
> `min-height:183`**（用户：「卡片高度需要调整，底下太空白了」）；步数卡右上角恢复步行图标
> 并与「达标 N%」徽标并列；删掉 `dashboard-steps-remaining`（「还差 n 步」）；体重趋势横轴
> **周/月都标日期**：周视图每天 `M/D`，月视图只标**每周一**的 `M/D`。我的页身份卡的头像与
> 昵称改为**不可点**（只有「编辑资料」按钮入口）。

> 2026-10-16（用户实测批次）：体重趋势卡不再写周期注（周/月都不要）；月视图横轴锚点日
> 恒显示日号；选中浮窗定宽 64 居中；饮水/步数卡数值行改「当前 / 目标 单位」一行式并删
> 独立目标行；步数卡状态位改「达标 N%」徽标、删「查看详情」；步数 `no_event` 不再当
> 「没有传感器」。相关 Key 增删见下表。

> 2026-10-16（真实 AI 综合实测补）：**食堂目录对「别处写入」自动刷新**——设备实测里
> 用户点「AI 分析」→ 到对话应用 `canteen.dish.nutrition` → 回到那张还活着的目录页时，
> 行上仍写「未分析营养」、统计仍写「0 道 已分析」（营养其实已落库）⇒ 用户会以为分析失败。
> 现在 `MenuTabView` 订阅 `CanteenRepository.watchDirectory()`（菜品/营养证据/窗口/地点四表），
> 自己写入期间不重复刷新、已在刷新则合并一趟。
>
> 2026-10-16（Round9 第二批，食堂五条 + 价格全删 + 帧实看抓到四件）：
> ① **横轴日期标签必须真的画全**（见上表：`OverflowBox` + 56dp 上限；判据改用
> `RenderParagraph.didExceedMaxLines == false`——字符串对不算数）；
> ② 「下一餐决策卡」**本餐热量行**右列改 `Expanded` + `textAlign.end`（原来是
> `Text + Spacer + Text`，320dp × 2.0× 实测溢出 102px；给剩余宽度后超长文案换行而不是被裁）；
> ③ **计划卡标题只写计划名**（去掉 `计划名 · 周一` 后缀）：星期由右侧徽章承担
> （`周一` / `今天`），两处各写一遍是重复，且 2.0× 下后缀被挤到第二行；`distinctDayCount`
> 参数随之删除（死代码纪律）；
> ④ **B5 虚线按钮文案必须带主题字体族**（与 `_lfButtonLabel` 同一口径）：`TextButton`
> 自带的 `DefaultTextStyle` 会替换环境那层，裸 `LfText.microStrong` 会让族为 null
> （2026-10-16 食堂目录帧实看：CJK 渲染成豆腐块）。
> ⑤ 食堂菜品**价格整条退役**（表单/目录行/推荐卡/CSV/AI 命令/提示词/DB 列）：见
> `docs/03 §4` 末注、`docs/23 §2`、`docs/36 §3` S8-b；`canteen-dish-price` 不再存在。

**测试 Key**：`dashboard-greeting`、`dashboard-date-label`、`dashboard-avatar`、`dashboard-avatar-image`、`dashboard-avatar-initial`、`dashboard-calorie-ring`、`lf-calorie-ring`、`dashboard-ring-consumed`、`dashboard-ring-percent`、`dashboard-ring-target`、`dashboard-ring-status`、`dashboard-remaining-line`、`nutrition-macro-protein`、`nutrition-macro-carbs`、`nutrition-macro-fat`、`dashboard-macro-ratios`、`dashboard-weight-chart`、`dashboard-weight-trend-value`、`dashboard-weight-hint`、`dashboard-weight-range`、`dashboard-weight-range-week`、`dashboard-weight-range-month`、`dashboard-weight-add`、`dashboard-weight-empty`、`dashboard-weight-record`、`weight-bar-chart`、`weight-bar-chart-plot`、`weight-bar-chart-slot-<i>`、`weight-bar-chart-bar-<i>`、`weight-bar-chart-tick-<i>`、`weight-bar-chart-grid-line-<i>`、`weight-bar-chart-tooltip`、`weight-bar-chart-tooltip-text`、`dashboard-stat-water`、`dashboard-stat-steps`、`dashboard-water-value`、`dashboard-water-status`、`dashboard-steps-value`、`dashboard-steps-status`、`dashboard-steps-empty`、`dashboard-next-meal`、`dashboard-next-meal-chip`、`dashboard-next-meal-remaining`、`dashboard-next-meal-note`、`dashboard-next-meal-count`、`dashboard-next-meal-goal`、`cta-log-dinner`、`dashboard-meals-card`、`dashboard-meal-row-<slot>-<i>`、`dashboard-meals-empty`、`cta-view-all-meals`、`cta-ai-workbench`

> **2026-10-07 P9 / 2026-10-09 docs/31 S1·S4 的 as-built 增补已并入上文**（体重卡
> 周/月切换与添加图标、步数卡真接线与三态形态、AI 入口文案与路由）。历史证据：
> `docs/evidence/2026-10-05-ui-ux-remediation/`、`docs/31-ui-redesign-round4-plan.md`。
> P9 记的「体重卡选日期」不在当前实现里：A 的体重卡只有周/月与添加（阶段 2A 已核对）。

### 5.2 饮食 · 记录（`饮食 · 记录.html`）

**结构树（as-built，2026-10-14 阶段 2B 收口）**

```
SubTabChips                         sticky（页壳画，三页共用一份；A `.tabs` 轨道 + 三段）
└ CustomScrollView（记录页正文，常显 LfScrollbar）
    ├ NutritionRecordWeekSection    A `.date-strip` → `.selected-date`（**页首**；顶距 12）
    │   └ 右侧「复用历史餐食」入口  （设计稿未画，按裁决 ② 收在周条工具位）
    ├ LfEnergyCard（记录页装配）    `nutrition-record-energy*`：A `energy(ui.date)`，标题随选中日
    │                               （今天「今日营养」/ 历史「当日营养」）
    ├ NutritionRecordSourceSummary  A `.source-summary`：页级一行「已确认 N 项 / 估算 M 项」
    │                               （空列表连同段间距整段退场）
    ├ NextMealEntryCard（可选）     设计稿未画；按裁决 ② 收在摘要之下（仅今天）
    ├ CalorieTrendCard              A `nutritionTrend()`；`nutrition-record-trend-*`
    ├ NutritionRecordSlotGrouping   A `.meal-timeline`：四张槽位卡按 `MealSlot.values` 域序、卡间 12dp
    │   └ N × _SlotCard             DesignCard：槽头（28dp 无底图标 + 槽名 + 合计/尚未记录 + 仅今天的加号）
    │                               + 空槽行（今天「还没记录这一餐」/ 历史「当天没有这餐记录」）
    │                               / 内嵌餐卡（`embedded`：无卡中卡，行事实与 Key 不变）
    └ NutritionAnalysisSliver       DesignCard「营养分析」（本仓件）：3 统计 + ≤3 条彩点洞察
    （其下 navReserve 预留）
FAB                                 固定右下（`nutrition-record-fab`）48×48 mint 圆 + plus 白图标
```

**页序与页级间距**：照 A `nutritionRecords()`（`design/round7/app.js:171`）与其页容器
`.page{padding:12px 16px 28px; gap:16px}`（`refinement.css:3`）——页首周条顶距 12、
左右 16、相邻区块净距 16；`.date-strip` 与 `.selected-date` 之间 8（A `margin-top:-8px`）；
时间线内 12；时间线 → 分析卡 16。A 页尾那枚全宽「+ 记录饮食」主按钮与历史日的
「历史样例只读」提示**不搬**（职责分别由常驻 FAB 与既有历史写入通道承担；本仓历史日
仍可写入，搬那行提示是假话）。

**数据来源**：`Meals` + `MealItems` 聚合（现有）；`DailyTargets`；周趋势用现有 `LoadIntakeTrend`（7 日）；达标天数 = **有记录且摄入未超过目标上限**（`kcal ≤ calorieMax`）的天数；低于下限（`kcal < calorieMin`）的日子单独计数并在洞察里提示「未超上限，但可能吃太少」，不混入达标判定（2026-10-23 用户：目标区间是中心值 ±5%，按 `[min,max]` 判会让「达成率 95%」与「达标 0/7」同时出现）。

**交互**：FAB → 餐食录入；chip 切换 sub-tab；周条日期 → 定位到该日；餐卡 → 该餐详情。

**测试 Key**：`nutrition-record-energy`、`nutrition-record-energy-consumed`、`nutrition-record-energy-target`、`nutrition-record-energy-remaining`、`nutrition-record-energy-percent`、`nutrition-record-energy-ratios`、`nutrition-record-energy-status`、`nutrition-record-trend-chart`、`nutrition-record-trend-tracked`、`nutrition-record-trend-chart-area`、`nutrition-record-trend-axis`、`nutrition-record-trend-plot`、`nutrition-record-trend-empty`、`nutrition-record-selected-date`、`nutrition-tab-record`、`nutrition-tab-menu`、`nutrition-tab-foodlib`、`nutrition-record-week-strip`、`nutrition-record-slot-<slot>`、`nutrition-record-slot-<slot>-total`、`nutrition-record-slot-<slot>-add`、`nutrition-record-slot-<slot>-empty`、`nutrition-record-analysis`、`nutrition-record-fab`

> **页序与页级间距（2026-10-14，Round7 阶段 2B 步骤 6）**：页级顺序按 A
> `nutritionRecords()` 重排为「周条 → 日期行 → 热量卡 → 摘要 → 下一餐入口 →
> 趋势卡 → 时间线 → 分析卡」，间距照 A `.page{padding:12px 16px 28px; gap:16px}`
> 钉住。同一步修掉三处改造前的装配缺陷：页首热量卡**全宽贴边**（旧页首是渐变
> hero，sliver 从来没有横向内衬，换成共享白卡后卡从屏幕边缘长出来）、日期行 →
> 时间线 8→16、时间线 → 分析卡 0→16；并修两处 2.0×/320 文字缺陷（趋势图日号
> 折行压住 hint、分析卡数值被 `ellipsis` 裁成「3…」）。逐条 Delta、红证与实看
> 帧见 `docs/evidence/2026-10-14-round7-native-implementation.md`（阶段 2B
> 步骤 5/6）。

> **记录页页首卡换成共享热量卡（2026-10-14，Round7 阶段 2B D10）**：上面这段
> 结构描述是**旧件 as-built**（标题「饮食记录」+ 日期 + 三段统计 + 达成度条）。
> 阶段 2B 起页首卡与今日页共用 `LfEnergyCard`（Round7 A 变体 A 的 `energy()`）：
> 标题「今日营养 / 当日营养」、锚点 `nutrition-record-energy*`（环心两段 + 脚注
> 目标/剩余 + 占比行 + 状态 pill），`nutrition-record-hero*` 七个 Key 全部退役；
> 日期与周条一并按 A 重构（`.date-strip` + `.selected-date`）。本节的完整重写
> 与逐节 Delta 见 `docs/evidence/2026-10-14-round7-native-implementation.md`
> （阶段 2B 设计补全表）。

> **趋势卡与置信摘要行的位置（2026-10-14，Round7 阶段 2B 步骤 4）**：趋势卡
> 按 A `nutritionTrend()` 重画——标题行「七日摄入趋势」+「N 天有记录」、图区
> 145（柱区 101 + 上下 22 内边距）、轴宽 30（大字号按实测让位、上限 28% 卡宽）、
> 柱色三档（无记录 `--border` / 超目标 `--protein` / 其余 `--brand`）、柱下 6dp
> 日号、目标虚线 + 「目标 N」标签、空态 80；**`nutrition-record-trend-goal`
> 达标徽标与副标题退役**（达标天数留在分析卡，D13），纵轴上界改 A 口径
> `max(2200, 目标, 峰值)`（D17）。置信摘要（`confidence-summary`）按 A
> `.source-summary` 从分析卡卡尾挪成**热量卡之下的页级一行**，空列表时连同
> 段间距整段退场。逐节 Delta 与实测值见
> `docs/evidence/2026-10-14-round7-native-implementation.md`。

> **sub-tab 胶囊行由五项收敛为三项（2026-10-04，docs/28 §6.1）**：计划与食谱两枚
> 随「食谱 / 周计划」整族下线，`nutrition-tab-plan` / `nutrition-tab-recipe`
> 两个 Key 一并删除（`NutritionTabs.planIndex` / `recipeIndex` 同理）。

> **as-built（2026-10-07，P8b-2）：随包种子已换成 v5 = 49,444 条**。下文凡写
> 「49,464 条」的数字都是**当时的实测值**，规范含义是「计数行取自 `COUNT(*)`、
> 不是硬编码常量」这条不变量——具体数字以运行期查询为准，勿当规范值引用。
> 设备走查实测计数行为「全部 49,444 条」，证据
> `docs/evidence/2026-10-07-p8b2-v5-upgrade.md`。

> **食物库 sub-tab 的分页与滑条（2026-10-04 补，docs/28 §8；设计稿画不到这一层）**：
> 旧实现一次只取 30 条 ⇒ 下滑永远只有 30 张卡（用户点名 D5）。现在——
> 搜索框下加**真实计数行**（默认浏览「全部 49,464 条」、搜索「搜到 N 条」，
> `Key('food-library-count')`）；列表 `itemCount` 是**总数**而不是已加载数；
> 未加载区间画与真卡同构的 `FoodCardSkeleton`（不是假卡）；一页失败只在该页
> 第一格画一行「这一段没加载出来。 / 重试」；常显可拖滑条走 `LfScrollbar`（§3.6）。
> 记录页的整页 `CustomScrollView` 同样挂 `LfScrollbar`。
>
> **计数行与首页在「自建食物」之后必须重来一次（2026-10-04 W5 设备走查补）**：
> 顶栏那枚「自建食物」是 **tab 级动作**（不在食物库视图里），落库成功后页面只把
> `revision` 抬一 ⇒ 分页视图收这个数，`didUpdateWidget` 里按**当前查询词**重来一次
> （`invalidate()` 搜索缓存 + 重取 `COUNT(*)` + 清页缓存）。少了这条接线，计数行与
> 已缓存的第一页都停在旧数据上：真机实测「我的」页（另一个 `COUNT(*)`）已经是
> `49,465 条（自建 1 条）`，食物库却还写 `全部 49,464 条`，列表里也看不见刚建的那条。
> 视图端与透传端各一条断言，都在 `food_library_paging_test.dart`。
>
> **列表必须是行高已知的 sliver**（`SliverPrototypeExtentList`，2026-10-04 走查后补）：
> 滑条拖动是 `jumpTo(比例 × maxScrollExtent)`，在 4.9 万行上就是一次上百万像素的
> 远跳；行高未知的 `SliverList` 必须在单帧内逐行实体化到落点 ⇒ 真机 ANR
> （实测 `input dispatching timed out`）。原型卡取**最高变体**（三项宏量 + 品牌 +
> 徽标 + 「营养不完整」提示行），该高度施加给所有行，因此行高统一（约 171dp，
> 同屏 3 张），矮卡底部留白是预留的提示行。理由与红证见 docs/28 §8 实施记录二。
> **（本条已被 3-2b 取代：单行卡 56dp、原型 = 真行；`SliverPrototypeExtentList` 行高已知的
> 前提不变。）**

> **Round7 阶段 3（2026-10-14）as-built：食物库 sub-tab 按 A `nutritionFoods()` 收口**
> （D31–D52；逐条证据见 `docs/evidence/2026-10-14-round7-native-implementation.md`）。
> 页序（两条数据路径共用）：搜索行 → 分类胶囊行（横滑，`food-library-category-row`）→
> 结果头「**N 种食物** / kcal / 100g」（`food-library-count`，0 行也画）→ 密度口径注
> （`FoodDensityScaleNote`，位置**保持在列表头**——D39 改判：分页列表里放列表尾等于谁都
> 看不到）→ 列表（单卡 `.food-list`，见 §3.11）→ **贴底页尾条**（D44：承担底栏预留；
> 两链 `food-library-footer-import` / `-manage`）。空态 / 失败态 / 骨架都在列表区，页尾条
> **永远在**。详情入口 = 行点击（`FoodDetailSheet`，见 §3.11）；自建入口 = 搜索行右侧圆钮
> （不变）。**上文「全部 49,464 条 / 搜到 N 条」措辞已退役**（D32 改「N 种食物」）。
> **极端组合（320dp + 2.0×）如实登记**：页头区 ≈342 + 贴底条 ≈216 ⇒ 列表/空态区只剩
> ≈58–82dp，**不溢出**（空态走可滚降级、行动钮可达）但观感局促；根修（把钉住的页头并入
> 滚动体）会改 3-2a/3-2b 已验收的滚动结构 ⇒ 登记为范围变更候选，本轮不做。

### 5.3 饮食 · 菜单（`饮食 · 菜单.html`）

> **2026-10-04 重设计（`docs/28 §4.1`）**：平铺菜品列表 → hero + 三餐推荐 + 「其他已分析
> 菜品」。下面的结构树已按新形态改写；旧树里那张卡的**配料行**按 `§6.2` 裁决 13 删除
> （`DishLibrary` 没有配料列），其余行保留。
>
> **2026-10-14 Round7 阶段 3 步骤 1（A `nutritionMenus()`，`app.js:181–185`）**：页首
> **hero 卡退场**，改 A 的段头块（段标题 15 w600「每日菜品推荐」+ `.pill`「本地已分析
> 菜品」+ `.intro-copy` 指引行 + 原生两枚统计的 `.quiet-label` 汇总行）；槽块改 A
> `.dish-recommendation` 骨架（padding `14px 16px`、heading 行右端「换一个」`link()`、
> 块底 `.dish-action-row`「查看候选 N 道」+「加入<槽>」）；「管理食堂目录」入口从页首
> 圆钮迁到页尾 A `.list-link`（+ `.subtle-note` 中在本仓成立的那半句）。**Key 不退役**：
> `nutrition-menu-hero` 改由段头块承接，`-hero-planned` / `-hero-kcal` 落在汇总行两段
> 文字上。记录见 `docs/evidence/2026-10-14-round7-native-implementation.md`（D25–D30）。

**结构树**

```
Column
├ 胶囊行（页级唯一实例，画在本组件之上：记录 / 菜单 / 食物库）
├ CustomScrollView
│   ├ 段头块（顶距 12 = A `.page{padding-top:12px}`；`nutrition-menu-hero`，**不是卡**）
│   │   ├ 行一 `Wrap(spaceBetween)`：「每日菜品推荐」15 w600（A `.section-title`）
│   │   │        + `LfBadge.neutral`「本地已分析菜品」（A `.pill`）
│   │   ├ 行二 指引行 12 muted：「按你的食堂窗口推荐 · 先看看今天的候选，
│   │   │        选好份量后再加入饮食记录。」（A `.intro-copy` 的字面句 + 原 hero
│   │   │        副标题里的来源事实）
│   │   └ 行三 汇总行 12 muted：`已安排 N 餐`（`nutrition-menu-hero-planned`）·
│   │            `预计 X kcal`（`‑hero-kcal`）——未排餐写「—」，不写死 3/1470
│   ├ 整套推荐卡 `nutrition-menu-daily-set`（2026-10-22：早/午/晚收进**同一张卡**，
│   │            「一整套，不是分开」；A `.dish-recommendation` 的每段 padding 14/16）
│   │   ├ 卡头：`nutrition-menu-daily-set-title`「今日三餐推荐」15 w600
│   │   │        + `…-badge`「一整套」+ `…-intro`「早餐 → 午餐 → 晚餐 一次排出 ·
│   │   │        同一道菜不跨餐重复」
│   │   └ 三段（`nutrition-menu-meal-<breakfast|lunch|dinner>`，段间 1px 分隔线）
│   │       └ 每段：heading 行 `Wrap(spaceBetween)` =（餐次 15 w600 + `mealBandLabels`
│   │                时段带 + 状态徽标 `…-badge`）+ 右端（候选 >1 时）`…-swap`「换一个」
│   │                ├ 有主推：DishCard（§4.2 形态，`targetKcal = 本餐预算`、
│   │                │           `progressLabel = 本餐预算`、**卡内不画加入钮**）
│   │                │           + 成因 `…-reason`
│   │                │           + 段底动作行 `.dish-action-row`：`…-candidates`
│   │                │             「查看候选 N 道」`link()` + `cta-add-meal-<n>`
│   │                │             「加入<菜品自己的餐次>」`.btn.outline-brand`
│   │                └ 空态：一句成因 `…-reason` + 一个行动 `…-action`
│   ├ 页尾 `cta-manage-canteen`：A `.list-link`「管理食堂目录 / 地点、窗口与菜品」
│   │        （chip + 两行 + 右箭头，整行可点，**不是卡**）
│   ├ `nutrition-menu-note`：A `.subtle-note` 中在本仓成立的那半句
│   │        「加入餐次会记为已吃，保存前请确认。」（接了加入动作才画）
│   └ 底部导航预留
```

**三餐推荐的判据（实现在 `build_daily_meal_recommendation.dart`，`docs/28 §4.3`）**

| 元素 | 来源 / 规则 |
|---|---|
| 候选 | `DishLibrary` 里 `evidenceGrade != incomplete` 且 `kcal > 0` 的菜品 |
| 时段过滤 | 菜品 `servingWindow` 与该餐时段带（早 ≤09:30 / 午 ≤14:00 / 晚 ≤20:30）**有交集**才算候选；没有供应时段 → 退回菜品自己的餐次标签 |
| 预算 | 剩余目标（`DailyTargets.calorieMaxKcal` − 今日已记录 kcal）按 30/40/30 分给「还没吃、还没过」的餐位；没有当日目标 → 全部 null（此时不按预算挑，也不画进度条） |
| 排序 | 稳定三元组：证据等级 → 与该餐预算的差距 → `dish.id`（同输入必然同输出） |
| 不跨餐重复 | **主推**进 `used` 集合，同一道菜不会在第二餐被主推；候选被吃光时该餐给空态并写明成因，不回头重挑 |
| 状态徽标 | `planned`「已记录」（当天已记录过这一餐，推荐不再插嘴）/ `recommended`「已推荐」/ `empty`「暂无推荐」 |
| 空态行动 | `MealEmptyAction.openCanteen` →「去维护食堂目录」；时段已过 → `none`（没有可执行的动作，不画按钮） |
| 段头汇总行 | `已安排` = 已记录餐 + 有主推餐；`预计 kcal` = 已记录实际热量 + 主推热量；**0 餐时写「—」，不写 0 kcal**（0 的意思是「今天不吃」）。口径与原 hero 完全一致，只是从卡上的两列大数字降为 A `.quiet-label` 的一行两段（`docs/21 §5.3` 2026-10-14 记） |

**数据来源**

| 元素 | 来源 |
|---|---|
| 菜名 / 三宏量 / kcal | `DishLibrary`（**唯一主来源**，见下） |
| 图片 | `DishLibrary.imagePath`；为空 → 图片占位渐变（`docs/21 §2.5`），**不伪造菜品照片** |
| 「本周热门」 | `DishLibrary.isHot` |
| 营养师点评 | `DishLibrary.comment`；为空 → **不渲染该块** |
| 微量营养素 | `DishLibrary.fiberG / sodiumMg / vitaminDMcg`；为空 → **不渲染该行** |
| 进度条分母 | **本餐预算**（`mealBudgetFor`，与「下一餐推荐卡」同一套口径）；每段的进度条分母都是本餐预算，不再有「按全天目标」的第二套口径 |
| 供应时段 | `DishLibrary.servingWindow` |
| 已记录 | `MealRepository.watchForDate` → `recordedKcalBySlot`（同时供三餐预算与段头汇总行） |

**数据源裁决（原写「校园菜单目录 **或** AI 工作台产出」是两可表述，此处钉死）**

主来源是 **`DishLibrary`**，两条写入路径：

1. **用户自建**（主要路径）：沿用现有校园食堂三级结构（地点 → 窗口 → 菜品）录入，经 AI 营养分析（现有 `dish-nutrition` 任务）补齐三宏量与 kcal，并可在同一流程补点评与微量营养素；
2. **AI 生成**：现有 `daily-menu-plan` 任务的产出**写入 `DishLibrary`**，而不是只停留在草案层——这样「本周热门」与「营养师点评」才有稳定载体。

**不得**把 `MenuItems`（校园菜单原始条目，含 `itemStatus='unresolved'`）直接渲染成菜品卡：那张表的语义是「菜单上印着的名字」，证据等级常为 D 且可能没有营养值，直接渲染会违反 `docs/07 §9.2` 的证据表达要求。`MenuItemFoodMatches` / `MenuItemNutritionEvidence` 是**写入 `DishLibrary` 时的证据来源**，不是展示层数据源。

**菜品卡的「加入 N 餐」文案取菜品自己的 `mealSlot`**，不取所在块的餐次：`AddDishToMeal.run`
写入的是 `dish.mealSlot`（`add_dish_to_meal.dart`）。跨时段窗口（如 11:00–20:00 的窗口同时
覆盖午、晚）会让卡片出现在午餐块里而按钮写「加入晚餐」——这是**已知且刻意**的口径：按钮
说的是「记到哪里」，不是「推荐给哪一餐」。要让按钮跟块走，得先改写入语义。按钮自
2026-10-14 起画在**块底动作行**（A `.dish-action-row`）而不是卡内，文案裁决不变。

**测试 Key**：`nutrition-menu-hero`、`nutrition-menu-hero-planned`、`nutrition-menu-hero-kcal`、`cta-manage-canteen`、`nutrition-menu-note`、`nutrition-menu-daily-set`、`nutrition-menu-daily-set-title`、`nutrition-menu-daily-set-badge`、`nutrition-menu-daily-set-intro`、`nutrition-menu-meal-<slot>`、`nutrition-menu-meal-<slot>-badge`、`nutrition-menu-meal-<slot>-reason`、`nutrition-menu-meal-<slot>-swap`、`nutrition-menu-meal-<slot>-candidates`、`nutrition-menu-meal-<slot>-action`、`nutrition-menu-candidate-<n>`、`nutrition-menu-dish-card-<n>`、`nutrition-menu-macro-row-<n>`、`nutrition-menu-dish-hot-<n>`、`nutrition-menu-dish-source-<n>`、`nutrition-menu-dish-comment-<n>`、`cta-add-meal-<n>`

**食堂目录（同一 sub-tab 的第二段，`docs/28 §4.5`/`§4.6`）的 Key**：`canteen-add-venue`、`canteen-venue-<id>`、`canteen-venue-stats`、`canteen-stat-windows`、`canteen-stat-dishes`、`canteen-stat-analyzed`、`canteen-window-<id>`、`canteen-window-window-<id>`（时段徽标）、`canteen-delete-window-<id>`、`canteen-dish-<id>`、`canteen-dish-grade-<id>`、`canteen-dish-unanalyzed-<id>`、`canteen-add-dish-<id>`、`canteen-analyze-<id>`
（**2026-10-24 退役**：`canteen-add-to-library-<id>`——食堂目录与菜品库**就是一个库**，
写营养即自动进菜品库、改名/改份量按来源键更新、删菜/删窗口/删地点跟着删，
用户不再需要手动「加入菜品库」）

**食堂目录 · docs/29 §P7 新增 Key（需求 16/17/18）**：`canteen-windows-retry`（窗口列表加载失败的「重试」）、`canteen-dish-index-<id>`（无照片时的序号圆）、`canteen-dish-station-<id>`（档口副行）、`canteen-dish-photo-thumb-<id>`（菜品行缩略图）、`canteen-dish-photo`（表单照片字段）、`canteen-dish-photo-empty`（虚线空态）、`canteen-dish-photo-preview`（已选照片预览）、`canteen-dish-photo-shoot`（拍照）、`canteen-dish-photo-gallery`（从相册选）、`canteen-dish-photo-remove`（移除照片）

> **2026-10-14 清理**：这里原本重复贴了一遍上面的「数据源裁决」正文，并跟着一行**已经写短了**的
> 测试 Key（缺 `-hero-planned`/`-hero-kcal` 等）——一次旧合并留下的残件，与本节结构树和上面
> 那行完整 Key 表自相矛盾。已删；本节的数据源裁决以上面那一处为准。

### 5.4 拍照识餐（`拍照识餐.html`）

**结构树**

```
Column
├ TopBar                             [back-nutrition] + "拍照识餐" 居中 + [cta-rescan]
├ PhotoPreviewCard                   DesignCard
│   ├ 照片                           4:3，圆角
│   └ 覆盖信息条                     "已拍摄 · 12:15" + cta-retake "重新拍摄"
├ RecognitionResultCard              DesignCard "AI 识别结果"
│   ├ 菜名 18 w600 + SourceBadge "AI 估算"
│   ├ 置信度条                       94% (mint 进度条 + 百分比)
│   ├ 预估总热量                     520 kcal (26 w800) + cta-edit-items "修正"
│   └ 识别食材列表
│       └ N × 行                     名称 + 数量单位 … kcal
├ NutritionBreakdownCard             DesignCard "营养拆分"
│   ├ 总热量 + 三宏量 (g + kcal + 百分比)
├ AiAdviceCard                       mint-50 底卡 + lightbulb 图标 + 建议文字
└ FixedBottomPrimaryAction           cta-confirm-scan "确认记录此餐"
```

**数据来源**：现有拍照识别管线（`prepareMealImage` → `recognizeConfirmedMealImage` → `resolveMealScanCandidates`）+ 新增域「拍照识别结果」（时间戳/菜名/置信度/食材清单/宏量拆分/AI 建议）。

**交互**：`cta-retake` 重拍、`cta-rescan` 重识别、`cta-edit-items` 进入现有候选编辑器（**保留，作为二级流程**）、`cta-confirm-scan` 入账。

> **P10（需求 37，2026-10-07）拍照直通**：入口（AI 对话 `cta-photo-scan` chip、
> 饮食 FAB）直接调系统相机，拍到图**带图 push 本页并自动开始识别**，不再有
> 「拍摄/从相册选择」落地屏（`_ScanEmptyState` 已删）；空态（深链兜底）只剩
> 一枚「拍摄照片」主钮。相册入口保留在 AI 对话的图片按钮与剩余(餐前餐后)
>
> **2026-10-23 用户**：「底部拍照识别删掉改『确认应用』」——AI 对话的
> `cta-photo-scan` chip 曾换成 ai-chat-chip-apply-edits（退役）；**2026-10-24（`RV4-R16`）**
> 该 chip 也退役（行级应用之后多余），换成「今天还剩多少 / 记一餐」。
> 本页因此没有 UI 入口（页面、路由与识别管线保留；深链 `/meal-recognition` 仍可达）。
> 流程里；识别结果/确认/剩余流程与 `cta-rescan` 不变。

**发送披露（设计稿未画到，按裁决保留）**

设计稿没有画出「这张照片发给谁」的披露行，但这是 `docs/07`/`docs/08` 的隐私义务，**必须保留为常驻一行**。

| 项 | 规格 |
|---|---|
| 位置 | 照片预览卡的覆盖信息条内，或识别结果卡上方（取视觉干扰更小者） |
| 文案（已配置） | `点击即把当前图片发送给你配置的 AI 服务：<destinationHost> · <model>。` |
| 文案（未配置/读失败） | `点击即把当前图片发送给你配置的 AI 服务（供应商与模型见设置）。` |
| 读取失败时 | **退回通用文案，不保留旧值**——披露的全部意义是如实告知「发给谁」，写一个可能已改掉的主机名比不写更糟 |
| 失败时不上屏错误 | 披露是辅助信息，读不到只用兜底文案；真正需要配置的时机是点「使用 AI 分析餐食」 |
| 分支保活 | 拍照页作为推入路由不涉及保活；但若将来改为保活分支，必须按可见性重读（现有 `didChangeDependencies` + `Visibility.of` 方案保留） |
| 测试 Key | `scan-send-disclosure` |

**测试 Key**：`scan-back`、`scan-title`、`cta-rescan`、`scan-photo-preview`、`scan-photo-meta`、`cta-retake`、`scan-result-name`、`scan-result-source`、`scan-result-confidence`、`scan-result-kcal`、`cta-edit-items`、`scan-ingredient-<n>`、`scan-breakdown-total`、`scan-breakdown-protein`、`scan-breakdown-carbs`、`scan-breakdown-fat`、`scan-ai-advice`、`cta-confirm-scan`

### 5.5 训练（`训练.html`）

**结构树**

```
Column
├ DesignCard                        **与其余卡片同一形态**（2026-10-08 docs/30 §2 D6 起）
│   ├ "训练" text-xl w700 … "第 38 周"
│   ├ 三段统计: 4 已完成训练 / 2.8h 总时长 / 1,840 消耗 kcal (30px w800)
│   ├ CapacityChart                 7 柱（分钟）今日柱最深，无训练日为 muted
│   └ 图例                          休息日 · 二 / 四 / 日 + 训练日圆点
│   ⚠ 页面顶部留白 = pagePadding + 状态栏叠层（页面给，卡片不给）
├ ActiveSessionBanner               仍在：mint 渐变 + 上叠 + 16 圆角
│   ├ 脉冲白点 + "进行中" … "剩余 18 分钟"
│   ├ 会话名 16 w600
│   ├ 进度条 65%                    白 20% 底 + 纯白填充
│   └ cta-continue-session "继续训练" + "查看详情"
├ SegmentedControl                  我的计划 (active) / 训练历史（Round7 A `app.js:216` 四字标签，2026-10-15 逐页对账第一批）
├ MuscleChips                       <span> 行: 全部(active) / 胸 / 背 / 肩 / 手臂 / 核心 / 腿
├ WeekStatsCard                     DesignCard "本周训练统计" + 分类型行
│                                   力量训练 1 次 · 45 min / 跑步 / 骑行 / 核心
├ PlanCardList
│   └ N × PlanCard                  DesignCard
│       ├ 序号 + 计划名 16 w600 + 时间标签 (今天/周三/周五/周六/下周)
│       ├ Round7 对账批次 3：周安排块（A `app.js:216` 的 `.plan-days` + `.plan-today`）
│       │    ├ training-plan-weekdays-<n>   七枚 31dp 圆签（一~日）：计划日=mint-50 底、
│       │    │                              今天=**primary 实心底**（A `.day-chip.today` 后置覆盖 .on）、
│       │    │                              其余=轨道底；`training-plan-weekday-<n>-<1..7>`
│       │    ├ training-plan-today-note-<n> 「今天是训练日」/「今天休息，恢复也很重要」
│       │    └ training-plan-start-<n> 「开始训练」/「继续训练」CTA（Round7 裁决 R1，A `.plan-today` 右端钮；
│       │         **只在今天那张卡给**——A 画在每张卡、非今日 disabled，本仓一计划日一张卡，永久禁用的按钮只是噪音，登记为形态差异）
│       │                                  （判定＝今天是否在这份计划的训练日集合里；
│       │                                   集合口径同休息日图例：该 weekday 有 PlannedExercises）
│       ├ 动作列表                  每个: 名称 + 组次×重量 (力量) 或 配速/阻力 (有氧)
│       └ 元信息                    4 动作 · 45 分钟 · 中等强度
│   ⚠ 卡面 CTA 已按 **2026-10-15 用户裁决 R1** 落地：只在今天那张卡「开始训练/继续训练」（同一写入路径，详情入口保留）
└ cta-new-plan FAB                  右下 mint 圆 + plus
```

**二级入口行**（docs/22 裁决 ②，2026-10-15 逐页对账第一批按 A 补副题）：组末三行 `_SecondaryEntry`——`training-stats` 训练统计 / `training-target-progress` 训练达标 / `training-exercise-library` 动作库——**动作库行按 A `app.js:216` 的 list-link 带副题「先了解动作，再开始训练」**（其余两行保持单行；A 只画了这一行的 list-link 形态）。**`training-ai-plan` 行已于 2026-10-23 退役**（AI 入口只在 FAB 模式弹层里）。

**训练统计弹层的口径与缺陷登记**（Round7 裁决 R2 / 批次 5）：容量趋势下加 A 的口径说明句「**容量 = 每组重量 × 次数的合计**」（`training-trend-note`）；肌群分布每行补 **kg 绝对值**（`training-muscle-kg-<muscle>`，A 的图例是「名称 / 百分比 / kg」三件）。**两个既有缺陷同批修掉（帧审看抓到）**：**㉖** 肌群分布此前恒为空——`_StatisticsSheetContent` 只传会话仓储、`muscleGroupDistribution(exercises: const [])` 的 `exerciseId→肌群` 映射永远失败 ⇒「肌群分布（按容量）」在真实数据下也只会写「暂无肌群分布数据。」（修法：把动作库一起传进去，一次读完 312 条）；**㉗** 容量图柱体此前只有 `width: 32` **没有高度** ⇒ 外层 `Column(mainAxisSize: min)` 给无界高、`FractionallySizedBox` 拿不到有限高，**带真实训练数据打开「训练统计」必抛** `BoxConstraints has NaN values in minHeight/maxHeight`（修法：柱区显式 `height: 80`）。两条都此前无任何用例/帧走过这条路。

**训练回顾弹层**（Round7 逐页对账批次 4 按 A `app.js:559`）：训练历史行可点 → `AppSheet`（标题「训练回顾」，键 `training-review-sheet`）：组数大字 `training-review-sets` + 「已完成组数」+ 计划名 + 四行 `training-review-date` / `-duration` / `-volume` / `-kcal`。**只读**（全部取自 `WorkoutSessionRecord`，新增零查询零写入）；估算消耗按本仓口径写「—」并在注里说明原因（`WorkoutSets` 无热量列）。

**动作库页结果计数**（Round7 逐页对账批次 2 按 A `app.js:225`）：筛选/搜索之后画一行「**N 个动作**」（`exercise-result-count`）。**加载中/失败不画数字**（不能把「还没读到」说成 0），有数据时 0 也照画（同食物库 D32 口径）；位置固定在列表之上而非流内——本页是 312 条网格，计数滚走就没人看得见（与 D32 的位置裁决同向，**登记为反向偏离**）。

**数据来源**：`WorkoutPlans` / `WorkoutDays` / `PlannedExercises` / `WorkoutSessions` / `WorkoutSets`（现有）；「第 N 周」= 从首个 session 起算的周序号（派生）；容量图 = 各 weekday 的训练分钟数（派生）；`已完成训练 / 总时长 / 消耗` = 现有 `TrainingStats`；**心血管处方（配速/阻力）= 新增域**。

**交互**：`cta-continue-session` → 现有训练器；`查看详情` → 现有会话详情弹层；肌肉 chips → 过滤动作；分段 → **我的计划/训练历史**（Round7 A `app.js:216` 文案）；`cta-new-plan` → **模式弹层**（AI 生成 / 手动创建，见下）。

**本页计划新建的口径（2026-10-08 docs/30 §2 D7，需求 7）**：
- **FAB 总是先问「怎么建」**：`cta-new-plan` 打开 `AppSheet` 模式弹层，两行是**同级**
  的两个动作（左图标方块 + 标题 + 一句说明 + 徽标 + 右箭头），不是「主 + 次」。
  旧实现按依赖分叉（AI 依赖齐全 → 直跳 `/workout-plan-create`；缺失 → 弹一个只输名称的
  框、`days: const []` 建**空计划**），于是配好 AI 的用户**永远看不到**手动这条路
  ——这正是用户说的「不能手动」。
- **AI 行禁用但可见**：四项依赖（`exerciseRepository` / `workoutPlanRepository` /
  `workoutPlanProvider` / `loadWorkoutPlanDisclosure`）不全时该行不可点，说明改成
  「未配置 AI（我的 → AI 模型）。配好后这里就能用。」并挂 `未配置` 徽章。
  与全仓「可选能力缺失时如实说明、不静默隐藏」一致（对比设置页的 AI 组）。
- **手动行两态都可用**：它只依赖 `exerciseRepository` + `workoutPlanRepository`
  （训练页本身就在用这两个仓），AI 配没配都不影响。
- **手动页是独立页**（`/workout-plan-manual`），不是 AI 页的 `mode` 参数：两者的表单、
  阶段机（表单/披露/生成/预览）与依赖完全不同，共用的只是数据契约
  （`WorkoutPlanDraft` + `PlannedExerciseDraft` + `create(source:)`）。
- **没内容就存不下来**：保存前置条件是「名称非空 + 至少一个动作」，不满足时按钮禁用
  并说明差什么。旧路径允许「先建壳再补」，中途退出会留下一个看起来存在、实际是空的计划。
- **「添加动作」表单是共享件**：手动页与计划详情都调 `showPlannedEntrySheet`，
  字段 Key 逐一对齐（`training-entry-weekday` / `-exercise` / `-sets` / `-reps` /
  `-weight`，保存 `training-entry-save`），**不新造一套字段名**。
- **计划详情显示来源标签**：`WorkoutPlans.source` 早在落库（`ai` / `manual`），
  本轮在详情顶栏把它显示出来（`LfBadge` neutral 档）。**不认识的来源原样透出**——
  把 `imported` 显示成「手动创建」就是编造。
- **二级入口 `training-ai-plan` 于 2026-10-23 退役**（用户：「删『AI 生成训练
  计划』按钮，功能转移到 ➕」）：AI 入口只在 FAB `cta-new-plan` 的模式弹层里
  （`plan-mode-ai` → `/workout-plan-create`）；
  空态文案「还没有本地训练计划 → 新建一个计划」不变。

**本页顶部卡的口径（2026-10-08 docs/30 §2 D6，需求 6）**：
- **形态**：`neutral-900` 色块（含只圆下角、`respectTopInset`）**退场**，改用全 App 统一的 `DesignCard` ⇒ 底 `card` 不透明 + 1px 描边 + 16 圆角 + 左右 `pagePadding` 留白。**取消**「色块铺满屏宽」这条旧契约：贴屏边的黑块在亮色主题下与其余页面读起来不是同一套语言。
- **顶部叠层改由页面让**：卡片不再铺到屏幕物理顶边，于是 `training_page.dart` 的 `ListView` 顶部 padding 从「无」改为 `LfDimens.pagePadding + LfInsets.top(context)`——**不是只给叠层**，那样卡片会顶到状态栏下缘而与左右 16 留白不对称。底栏预留（`LfInsets.navReserve`）不变。
- **容量图配色反转为「越深越近」**：旧实现是暗底（`onHero` 白系），今日柱最亮 = 最显眼；白底上「白」不再显眼，所以今日 `mint-600`、其余训练日 `mint-400`、**无训练日 `muted`**（旧写法 `onHero.withValues(alpha: 0.12)` 在白底上近乎不可见）。星期标签与图例文字从 `onHero` 系改为 `mutedForeground` / `cardForeground`。
- **字阶与数值口径一字未改**：三段统计仍是 30px w800（`displayHero`），`totalKcal` 仍恒传 `null` ⇒ 渲染「—」而不是编一个数（`WorkoutSets` 没有热量列）。
- **全 App 贴顶清单随之收缩**：只剩「今日页整块内容随叠层下移」与「二级页 `LfTopBar` 自己吃叠层」两处（§5.8.5）。

**测试 Key**：`training-hero`、`training-hero-week`、`training-hero-count`、`training-hero-duration`、`training-hero-kcal`、`training-capacity-chart`、`training-rest-legend`、`training-active-banner`、`cta-continue-session`、`training-session-detail`、`training-segment-plan`、`training-segment-history`、`training-muscle-<name>`、`training-week-stats`、`training-plan-card-<n>`、`cta-new-plan`、`plan-mode-ai`、`plan-mode-manual`、`training-plan-source`、`manual-plan-name`、`manual-plan-weekday-<n>`、`manual-plan-empty-hint`、`manual-plan-day-<n>`、`manual-plan-day-add-<n>`、`manual-plan-entry-remove-<weekday>-<i>`、`manual-plan-error`、`manual-plan-save`、`manual-plan-save-hint`

### 5.6 我的（`我的.html`）

**结构树**

```
Column
├ 页头                            "我的" + "关于你，也关于你的数据"
│                                 （A `app.js:271` head()；2026-10-15 逐页对账第一批）
│                                 ⚠ **不搬** A 页头右侧「本地优先」徽章：docs/33 §3.8
│                                 明令不用它概括所有流向，诚实披露由页尾隐私条 +
│                                 「数据来源与许可证」承担（哨兵断言在 settings_page_test）
├ DesignCard                        **与其余卡片同一形态**（2026-10-08 docs/30 §2 D5 起）
│   ├ 头部一行: 头像 56×56 圆 + mint-100 底 + "Fit"（mint-700）
│   │            ^ 右邻: 姓名 18 w600 + "已坚持 N 天 · 目标减脂 M kg"（次级色，单行省略）
│   │            ^ 行尾: cta-edit-profile "编辑资料"（B6 文字钮）
│   └ 三段统计: 65.2 kg 当前体重 / 5,840 总记录 / 128 连续天数
│                  ⚠ 「当前体重」**可点**（`settings-stat-weight-open`）→ 「体重记录」只读弹层
│                    （Round7 裁决 R5，A `app.js:570`：大字最新一条 `weight-history-latest` +
│                     全部记录行 `weight-history-row-<date>`（日期 + kg + 来源徽标 手输/秤同步）；
│                     **不搬** A 的「记录今天的体重」写入按钮——写入通路在今日页体重卡，
│                     只读列表里再放写入口会把「看记录」变浑）
│                  竖直分隔线 ×2（1px border），各段 数值 + 标签 两行
├ HealthMetricsCard                 **我的健康指标**：三张**图形卡**（docs/29 §P2 / 裁决 D10，2026-10-05 起）；
│   ⚠ 标题与右端 `资料与今日记录`、BMI 分档边界说明 `18.5 / 24 / 28 为分档边界，仅作健康参考`（`settings-health-bmi-note`）
│      为 Round7 逐页对账批次 2 按 A `app.js:248` 补（原为「健康数据」单标题，`.section-title.with-link` 两端形态）
│   ├ settings-health-bmi            BMI 分档刻度尺：四段（偏瘦/正常/超重/肥胖）**按真实数值区间成比例**
│   │                                + 指示器（有值才画）+ 档位徽标（右上一枚；空态没有徽标也没有指示器）
│   ├ settings-health-bmr            基础代谢率**区间指示**：值 + 目标热量区间 + 标记点（没有区间整块不画）
├ AchievementsCard                  SettingsGroup「**每一份坚持，都算数**」+ 右端「N / N 已解锁」+ 四张**行卡**（docs/29 §P3，2026-10-05 起）
│                                   标题/计数/尾注 `进度为历史最高值，不因删记录而回退。` 为 Round7 逐页对账批次 2 按 A `app.js:252` 补
│                                   （尾注是本仓已成立的事实：`progress` 在库里就是历史最大值，见 `achievement_levels.dart`）
│   └ settings-achievement-<n>      44dp 勋章环（等级色进度弧 + 内盘）+ 名称（单行）+ 等级徽标
│                                   + 进度条 + `n/目标`；解锁行内盘换**实心等级色**、第 2 行原位改「已解锁」
├ SettingsGroup × 4                 overflow-hidden rounded-[16px] divide-y
│   ├ AI 配置                        AI 模型 → <当前模型>（settings-ai-model-row，点击开弹层）
│   │                                AI 记忆 → 让 AI 记住你的习惯（settings-ai-memory-row，push /ai-memory；docs/38 S11）
│   │                                弹层 = ai-protocol / ai-base-url / ai-model + ai-config-probe（连通性测试，
│   │                                结果内联 ai-config-probe-result）+ ai-model-search / ai-model-option-<n>（/models
│   │                                拉取后点选回填）+ ai-reasoning（推理开关）+ ai-api-key（密码框）+ 保存 ai-config-sheet-save
│   ├ 数据管理                       cta-backup / cta-restore / cta-export-csv / 导出训练 CSV
│   │                                + **settings-steps-permission**（docs/30 §2 D9，2026-10-08 起：
│   │                                标题「步数与身体活动」+ 状态徽章四态（已授权 mint / 未授权 honey /
│   │                                设备不支持 muted / 状态未知 muted）；点击开说明弹层：**应用内开关
│   │                                `steps-enabled-switch`（2026-10-23：「步数授权取消不掉」——关闭后
│   │                                真的停读停写，步数卡显示「已关闭」）+ `steps-enabled-note` 写明
│   │                                「开关 ≠ 撤销系统权限」+ `cta-open-app-settings` → 本应用系统设置页；
│   │                                未接线 stepsRepository 时不渲染）
│   │                                + **settings-scale-row**（docs/31 S6，2026-10-10 起：标题「电子体重秤」
│   │                                + 状态徽章（已授权 mint / 未授权 honey / 设备不支持 muted / 状态未知
│   │                                muted）；点击开授权弹层 → 扫描进度 → 七种结局各自的下一步文案，
│   │                                同日冲突走二选一弹层默认保留原记录；未接线 scaleSync 时不渲染）
│   │                                + 自动本地备份开关
│   ├ 食材库                         食材数据库 → N 条（自建 M 条）/ 维护地点 / 窗口 / 菜品
│   │                                / **食物数据行**（docs/31 S5，2026-10-10 起：
│   │                                settings-food-data「添加食物数据」→ 弹层两动作 手动添加
│   │                                （复用 NewFoodDialog，含 new-food-category 种类下拉）/
│   │                                CSV 导入（预览三本账 + 跳过重复/全部导入）+
│   │                                backup-export-foods-csv 导出 8 列 CSV；未接线时不渲染）
│   │                                （**「添加自定义食材」独立行已删**：2026-10-13 docs/32 §3 D10
│   │                                ——同一动作收进「添加食物数据」弹层，行序 = 三行常驻）
│   │                                / **清空内置食物行**（docs/32 §4 T11 需求 75，2026-10-13 起：
│   │                                settings-clear-builtin-foods「清空内置食物数据」放**组末**，
│   │                                destructive 字色；**只在库里有内置行时渲染**
│   │                                （概览 foodCount > userCreatedFoodCount）⇒ 全新安装与
│   │                                未接线 clearBuiltinFoods 都不出现。点击 → 弹层用
│   │                                ClearBuiltinFoods.preview() **现算**三组计数
│   │                                （内置 N / 引用它们的餐次条目 M / 菜单匹配 K，0 的那句
│   │                                整条不提）→ 取消（LfTextButton，左）/ 清空内置食物数据
│   │                                （LfDangerButton = error 字色文字按钮，§3.8 B7，右）；
│   │                                执行后就地重读概览（计数行与行本身一起回到真实态）+
│   │                                snackbar 如实报数；预览为空时不弹层，只回
│   │                                「没有内置食物可清空。」）
│   │                                （**通勤时间行已删**：2026-10-13 docs/32 §3 D10——键
│   │                                settings-commute-row / -minutes / -save / -clear 与
│   │                                ManualCommuteDialog 整族下线，手动通勤列随 schema 23→24 drop；
│   │                                本行原有「未接线仓储就不渲染」的自门控约定仍有效，只是对象已不在）
│   └ 关于                           关于 LocalFit AI → vN / 检查更新 / cta-clear-data (error 色)
└ Footer                            "清除数据后不可恢复" + "LocalFit AI vN"
                                    + "让每一次记录，回到你自己。"（A `.page-end`，2026-10-15 逐页对账第一批）
```

**数据来源**：档案（`Profiles`/`Goals`）、`Measurements`（体重/体脂）、`Meals` 计数（总记录）、连续天数（派生）、BMI（派生：体重/身高²）、基础代谢率（派生：Mifflin-St Jeor）、成就解锁态（**新增域**）、食材库条数（`Foods` count）。**健康数据三张图形卡另加了两次「只读不算」的取数**（docs/29 §P2）：BMR 卡的区间 = 该用户自己的 `Goals.calorieMin/Max`（同一行已有列，透传给区间指示用）、饮水环的达成度分子 = 今日 `WaterIntakes` 合计（与 `WaterRepository.watchDay` 同口径）；**BMI/BMR/水目标的派生逻辑一行未改**。

**健康数据三张卡的口径（docs/29 §D10）**：BMI 有公认分档 ⇒ 刻度尺（边界 18.5/24.0/28.0，左闭右开）；BMR **没有**公认的「正常区间」，套分档就是伪造语义 ⇒ 只回答「静息消耗相对你自己的每日目标热量区间在哪一边」；饮水是单值目标 ⇒ 画达成度。口径（谁算正常、边界在哪）在 `lib/features/settings/domain/health_metric_bands.dart`，画法在 `lib/app/design/widgets/lf_metric_gauge.dart`，设计层不认识业务词。**空态一律不给假信息**：值为空 ⇒ 轨道全灰、不画指示器/标记点、不放档位徽标，只留「—」。

**刻度尺的两条几何契约（2026-10-05 设备实测钉入）**：
① 段宽按**真实数值区间**成比例（轴 15–35，段界在 18.5 / 24.0 / 28.0），不是等宽——等宽会把「5.5 个点宽」和「无上界的最后一档」画成一样长；
② 档界数字的**中心**落在轴上它标的那一点（设备实测偏差 ≤1.1px）。位置不能拿 `Align(Alignment(x, 0))` 算：那是往**剩余空间**按比例摆（`x` 只分配减掉字宽之后的空间），字越宽越往中间挤（2.0× 下 18.5 偏 26px）。刻度行**行高不写死**（写死 14px 时 2.0× 的 20px 字被上下各裁一半）。

**成就分级与进度的口径（docs/29 §P3 / 需求 5）**：四格灰瓦片换成**行卡**，每行自证三件事——等级（徽标 + 环色）、进度（环 + 条）、还差多少（`n/目标`）。
- **等级三档**：`progress < 0.5` 铜、`[0.5, 1)` 银、`1.0` 金（边界**含等号**：0.5 就是银；非有限值按铜兜底）。金与「已解锁」是**同义词**——`unlockedAt` 一经写入不回收、`progress` 取历史最大值，所以 `progress ≥ 1 ⇔ 已解锁`，提前给金就是谎报。
- **计数**：`n = floor(progress × target + ε)`，且**未解锁时上限 `target - 1`**（0.99 的 7 天连续打卡显示 `6/7`，绝不四舍五入成 `7/7` 去跟银档打架；`progress = 1 - 1e-10` 这种被 ε 顶到目标线的值同样封在 `target - 1`）。`n` 与进度条**同源**（都用 `progress`）——拿实时计数配历史进度会出现「条满着、数字掉下来」。
- **目标值单源**：`AchievementSpec`（key/名称/7、7、10、30）在 `lib/features/settings/domain/achievement_levels.dart`，`_evaluateAchievements` 与页面占位行都取它，页面不再自己认 7/10/30。
- **等级色**（只用既有 token）：铜 `weight`、银 `mutedForeground`、金 `carbs`；徽标 = 等级色**淡染底**（`alpha 0.18`）+ `foreground` 文字。金色在亮色主题下是亮琥珀，白字压上去看不清，所以不写「实心底 + 白字」。
- **解锁行的内盘墨色**用字面量 `#1A201D`（neutral-900）：金牌在暗色主题下仍是亮金（`carbsDark #FFD56B`），而 `foreground` 在暗色下近白（`#E8EFEB`），白图标画在亮金上等于看不见；`LfColors.neutral(brightness).tone(900)` 也不能用（暗色 ramp 的 900 是浅色，正好反过来）。
- **名称绝不省略**：`maxLines: 1` + `FittedBox(scaleDown)`，放不下整体等比缩小。实测最长的「7天连续打卡」在 **2.0× / 320dp** 下**还排得下**（需要 157.5dp、可用 161.75dp，余 4.25dp）⇒ 兜底在 320dp 上**不参与工作**（去掉它的变异是等价变异，先跑绿才发现）。所以测试分两条钉：320dp 用例钉「兜底在场且是 `scaleDown`」的结构，**300dp** 用例钉「真放不下时整体缩小而不是省略」（该宽度下 157.5dp > 可用 141.75dp，兜底真介入）。
- **行高与解锁状态无关**：解锁只在第 2 行**原位**把 `n/目标` 换成「已解锁」，不新增行、不加徽标块；分隔线在行**之间**（`SettingsGroup` 的 1px `Container`），不落在行盒里 ⇒ 混态也严格等高（`<0.5px`）。
- **设备像素复核（亮/暗 × 1.0×/2.0×）**：条填充/条轨恒等于 `progress`（1/7→0.1424、1/30→0.0324、7/30→0.2330、7/7→1.0）；环弧角恒等于 `progress × 360° + 圆头帽`（实测 59.0°/19.5°/91.5° vs 理论 58.8°/19.4°/91.4°）；未解锁内盘 = `muted`、解锁内盘 = 等级色 token **逐字节相等**（亮 `#FFC94D` / 暗 `#FFD56B`）。**2.0× 行距是分数 dp**（零进度 `[294,291,291]`、金档 `[294,291,292]`；1.0× 实测 206–208px，零进度两组全 207）——该倍数下改由文字度量撑定行高，既不换行也不裁切，如实记为边界。
- 口径（等级/计数）在 `domain/achievement_levels.dart`，画法在 `lib/app/design/widgets/lf_achievement_row.dart`（`LfMedalTier` + `medalTierStyle`），页面只做「业务枚举 → 设计枚举」映射。**不落库、不改 schema**。

**「数据同步」开关的处置（已裁决）**：设计稿该开关为 `aria-checked="true"` 且名为「数据同步」。**降级为「自动本地备份」**：复用现有加密备份格式（`.lfb`）、开关值存本地设置。不引入任何云端语义。

> **分支切回会重读派生数据（2026-10-05 docs/29 §P2 起）**：本页挂在 `StatefulShellRoute`
> 的分支上，切 tab 不重建、`initState` 只跑一次；但 go_router 给非当前分支套
> `Offstage(child: TickerMode(enabled: false))`（17.1.0 `src/route.dart:1695-1698`），
> 所以「重新可见」是可观测的：`SettingsPage.didChangeDependencies` 在
> `TickerMode` 由 false 翻 true 的那一次重造 `_overviewFuture`，并把「加载那一刻的快照」
> 换成新值。重读不闪空态——`FutureBuilder` 换 future 时保留上一次的 data
> （`AsyncSnapshot.withData(ConnectionState.waiting, 旧 data)`），各区块的判据是
> `snapshot.data`，旧值一直显示到新值到达。
> **仍未覆盖**：① 停留在本页期间别处写库（要应用级变更通知，见下条）；② 分支内 push 的
> 二级页（`/profile-edit`）返回时 `TickerMode` 不变 ⇒ 不触发重读（候选：RouteObserver
> 或让 push 的调用点回读）。

> **已知限制：本页的计数是「进页面那一刻」的快照（2026-10-04 W5 走查实测，记录未修；
> 2026-10-05 docs/29 §P2 起「切 tab 回来」这一半已修）**。
> 身份卡 / 健康数据 / 成就 / 食材库四块共用**一个** `_overviewFuture`
> （`settings_page.dart` 在 `initState` 里造一次并全程复用），而本页挂在 shell
> 的分支上、切 tab 不重建 ⇒ 在别处新增/删除食物后回到本页，读数**不会跟着变**
> （切走再切回来会重读，**停在本页不动**或**从 push 的二级页返回**仍不会）。
> 实测：种 1 条自建食物 → 重启 → 第一次进本页 `49,465 条（自建 1 条）` ✅；
> **不重启**再去食物库加 1 条（食物库当场 `49,466`）后回本页仍写 `49,465 条（自建 1 条）` ❌。
> 剩余那一半的正确修法需要一个**应用级的「数据变了」通知**（`main.dart` 造一个 `Listenable`，
> 同时驱动 `NutritionPage` 的 `revision` 与本页重取 overview），跨装配层数个文件，属新功能；
> 故本切片按「记录 + 落规范」处置，不静默放过。
> 证据：`docs/evidence/2026-10-04-input-menu-foodlib-redesign.md` 的 W5 段（F2）、
> 截图 `w5-49-mine-e1-fresh` / `w5-50-mine-e2-stale`、
> 日志 `E:/AI/Zcode/tmp/w5-52-mine-stale-log.txt`。切回重读的**缺陷**是 2026-10-05 设备实测抓到的
> （今日页记 500ml 显示 `0.5 / 2.0 L` 之后切回本页，水分卡仍写 `0%`、`今日已饮 0.0 L`）；
> **修法的设备复验未取得**（模拟器在重装/重启中反复退出），修法证据为 widget 级
> （`settings_branch_refresh_test.dart` 2 例 + 变异 M15/M16），见
> `docs/evidence/2026-10-05-p2-health-metrics.md` §6。

**步数授权行的口径（2026-10-08 docs/30 §2 D9，需求 3）**：
- **不做应用内「取消授权」开关**。Android 的运行时权限（`ACTIVITY_RECOGNITION`）**只能由用户在系统设置里撤销**；应用内做一个开关只能停用我们自己的读数、撤不掉权限本身 ⇒ 设置页会说「已取消」而系统里权限还在，直接违背诚实条款。所以这一行**只回答两件事**：现在什么状态、去哪里改。这也解释了为什么全屏**没有任何 `Switch`**（有断言钉着）。
- **四态各自说实话**，短词只回答「现在能不能读」：`available` → 已授权（mint 档）、`denied` → 未授权（honey 档）、`noSensor` → 设备不支持（muted）、其余（含 `noReading` 与首帧未读到）→ 状态未知（muted）。**不合并**——「用户点一下就能有」与「这台设备永远没有」的用户动作完全不同。状态用 `LfBadge` 而不是 `SettingRow.value`：短词要带底色才分得清可用/不可用，而 `value` 格是纯文字的，四态在上面长得一样。
- **读数与今日页步数卡同源**（`StepsChannel.read`），所以两处不会各说一套。新增 `StepsRepository.readAvailability()` 只探一次状态，**不落库、不动基线**——用 `syncToday` 顺带取状态会在设置页产生写副作用（重设基线、写入 0 步行），测试有一条专钉「探完之后步数表仍是空的」。
- **「去系统设置」在四态下都可点**：已授权时它是「去撤销」的入口，未授权时是「去开启」的入口，两者是同一个动作（`openAppSettings` → `ACTION_APPLICATION_DETAILS_SETTINGS`）。授权了就藏按钮等于把撤销路堵死。
- **弹层先关再跳**：系统设置页在前台出现时不该还看到我们的弹层压着；从系统设置回来也不该被「弹层还开着」绊一下。
- **未接线（`stepsRepository == null`）时不渲染该行**（「未接线就不渲染」这条自门控约定的既有同例是 `settings-food-data` 行）。注意「数据管理」组的自门控因此也把步数仓储算进去了（三者任一在场就渲染整组）。

**身份卡的口径（2026-10-08 docs/30 §2 D5，需求 6）**：
- **形态**：`hero` 渐变 + 径向点纹理 + 20 圆角 + 半透明白底药丸**全部退场**，改用全 App 统一的 `DesignCard`。旧形态的根因是**白字依赖渐变底**——白卡化后任何一处漏改就是白底白字；所以这次同时把**所有**卡内文字改成 `cardForeground` / `mutedForeground`，并用 `identity_training_card_white_test.dart` 的「卡上不得出现任何白色文字」逐节点扫描 + WCAG 对比度 ≥4.5 钉住。
- **头像 64 → 56**：卡片从「铺满宽度的色块」变成「有左右留白的卡」，头部再放 64dp 会喧宾夺主。底色 `mint-100`、字 `mint-700`（`LfColors.mintText(Brightness.light)`）——**不是 `primary`**：mint-100 底上 `primary` 对比不足，且浅色主题的 `mintText` 正是 mint-700。
- **一行三项**：头像 → 姓名 + 副标题 → 行尾「编辑资料」。入场rhythm 由「三段竖向堆叠」改为「卡片两段」（头部一行 + 统计一行），卡片高度随之下降。
- **三段统计的几何**：用 `IntrinsicHeight` + `CrossAxisAlignment.stretch` 让两条 1px 分隔线**撑满行高**，而不是写死高度；分隔线左右各留 `spaceMediumPlus` 外边距。等分靠 `Expanded`，段宽不同也让分隔线间距一致。
- **渲染仍走 `FutureBuilder<ProfileOverview?>`**，空态口径不变（无档案时副标题与三段数值如实显示「—」/占位）。

> 2026-10-16（用户：「去除水分摄入目标卡片」）：健康区由三格回到两格（BMI 分档
> 刻度尺 + 基础代谢率区间指示）。`settings-health-water` 与 `LfProgressRingGauge`
> 一起下线（后者零调用方，按死代码纪律删除）；饮水事实由今日页饮水卡承载。

**测试 Key**：`settings-identity-card`、`cta-edit-profile`、`settings-avatar`、`settings-avatar-initial`、`settings-name`、`dashboard-avatar-initial`、`ai-chat-avatar-initial`、`settings-stat-weight`、`settings-stat-records`、`settings-stat-streak`、`settings-health-metrics`、`settings-health-bmi`、`settings-health-bmr`、`settings-achievements`、`settings-achievement-<n>`、`lf-achievement-medal`、`lf-achievement-name`、`lf-achievement-tier`、`lf-achievement-count`、`settings-group-ai`、`settings-ai-model-row`、`ai-protocol`、`ai-base-url`、`ai-model`、`ai-config-probe`、`ai-config-probe-result`、`ai-model-search`、`ai-model-option-<n>`、`ai-reasoning`、`ai-api-key`、`ai-key-clear`、`ai-config-sheet-save`、`settings-group-data`、`cta-backup`、`cta-restore`、`cta-export-csv`、`settings-auto-backup-toggle`、`settings-steps-permission`、`steps-permission-sheet-body`、`steps-enabled-switch`、`steps-enabled-note`、`cta-open-app-settings`、`settings-group-catalog`、`settings-food-db-row`、`settings-menu-sources`、`settings-catalog-import`、`settings-clear-builtin-foods`、`clear-builtin-foods-body`、`clear-builtin-foods-confirm`、`settings-group-about`、`settings-version-row`、`settings-check-update`、`cta-clear-data`；食物库大库（docs/31 S5）：`settings-food-data`、`food-data-sheet-body`、`food-data-sheet-manual`、`food-data-sheet-import`、`backup-export-foods-csv`、`backup-export-training-csv`、`food-import-count-new`、`food-import-count-dup`、`food-import-count-error`、`food-import-dup-samples`、`food-import-error-sample`、`food-import-skip-dup`、`food-import-import-all`、`food-import-cancel`、`new-food-category`；电子体重秤（docs/31 S6）：`settings-scale-row`、`scale-permission-sheet-body`、`scale-action-sync`、`scale-action-app-settings`、`scale-sync-progress`、`scale-sync-cancel`、`scale-conflict-body`、`scale-conflict-keep`、`scale-conflict-overwrite`；编辑资料「每日目标」（docs/32 §4 T9 / §3 D11）：`profile-steps-goal`、`profile-water-target`；身份（2026-10-16 S6：头像与昵称统一在资料页改，设置页那对就地编辑键随弹层下线）：`profile-avatar`、`profile-avatar-image`、`profile-avatar-initial`、`profile-display-name`

**测试 Key（AI 记忆页，docs/38 S11）**：`settings-ai-memory-row`、`ai-memory-close`、`ai-memory-add`、`ai-memory-search`、`ai-memory-list`、`ai-memory-row-<n>`、`ai-memory-empty`、`ai-memory-injection-toggle`、`ai-memory-copy-all`、`ai-memory-clear-all`、`ai-memory-clear-confirm`、`ai-memory-editor-text`、`ai-memory-editor-kind`、`ai-memory-editor-domain`、`ai-memory-editor-pinned`、`ai-memory-editor-save`、`ai-memory-delete-confirm`

### 5.7 AI 对话（`AI 工作.html`）

**结构树**

```
Column
├ AppHeader                         [back-dashboard] + sprout 头像 + "AI 助手"（`ai-chat-title`；2026-10-23 用户：删副题，标题单行、头像与标题垂直居中）+ 用户头像
├ ChatArea                          scrollable
│   └ N × Message                   见下表 6 种形态
└ InputBar (固定底部)
    ├ AiStarterRow × 2             **今天晚餐怎么搭配？**(`ai-chat-starter-dinner`) / **制定轻量训练计划**(`ai-chat-starter-plan`)
    │                              （Round7 逐页对账批次 4 按 A `app.js:207` 的 `.conversation-starters` 补；
    │                               **只预填输入框、不替用户发送**——与「我可以吃吗」chip 同一条诚实口径）
    ├ ChatQuickChips                今天还剩多少(ai-chat-chip-remaining) / 记一餐(ai-chat-chip-log-meal) / AI 创作(ai-chat-chip-ai-create)
    │                              （2026-10-16 用户裁决：`手动记录` 下线；2026-10-23 用户：
    │                               `拍照识别` 换成「确认应用」；余三枚**等宽占满一整行**，不再横滑）
    ├ ImagePreviewStrip             (有图时显示) image-preview-bar
    └ ChatInputBar 默认行            btn-image-upload / 文字输入 / btn-send
    （P10 需求 35/36 删除：免责声明行、录音行与 btn-voice-* 三键；
      ai-chat-voice-<n> 仅在历史库存在旧语音消息时以降级气泡出现）
```

**消息 7 种形态**（第 7 种「编辑卡」由 docs/23 §5 增补）

| 形态 | 内容 |
|---|---|
| AI 文本 | 白底描边气泡，支持 emoji |
| 用户文本 | primary 底白字气泡 |
| AI 功能卡 | muted 底卡 + 3 条特性（图标 + 标题 + 说明）。原底部 AI 主按钮 `cta-write-plan`「立即查看专属理想方案」的食谱计划预览跳转随功能下线，欢迎卡不再接线（组件仍保留该 Key） |
| 用户图片 | 缩略图 + 文件名 + 说明文字 |
| 用户语音 | 圆形播放按钮 + 波形（**14 根静态白条**，见 §3.4）+ 时长 `3″` |
| AI 输入中 | 三点跳动 |
| AI 编辑卡 | reply 气泡 + 按类分组（记一餐 / 新建自定义食材 / 其他修改）+ 逐条修改行（图标+标题+摘要+状态）+ 组头「应用本组」+ 卡底「全部应用 / 忽略」；只有用户点应用才写库（docs/23）。2026-10-23 用户：单独应用一组后点「忽略」只忽略仍待应用的行，**不撤销已应用**（`dismissEdits` 只改 proposed 行） |

**数据来源**：现有 `AiConversationService`（流式）+ 新增域「聊天记录」（持久化）。图片消息复用现有 `prepareMealImage`；语音消息复用新增的录音+转写。

**语音输入（P10 需求 36 已删除，2026-10-07）**：录音行、`btn-voice-*` 三键、`record` 依赖与 `RECORD_AUDIO` 权限整族移除。历史库中的旧语音消息（D8 保留 `kind=voice` 与 `durationMs` 列）降级为普通用户气泡渲染，只读不写。免责声明行（需求 35）一并删除。

**测试 Key**：`ai-chat-back`、`ai-chat-title`、`ai-chat-message-<n>`、`ai-chat-feature-card`、`cta-write-plan`、`ai-chat-image-<n>`、`ai-chat-typing`、`ai-chat-chip-remaining`、`ai-chat-chip-log-meal`、`ai-chat-chip-ai-create`、`ai-chat-suggestion-<n>-<m>`、`image-preview-bar`、`btn-remove-image`、`btn-image-upload`、`ai-chat-text-input`、`btn-send`；编辑卡（docs/23 §5）：`chat-edit-card-<n>`、`chat-edit-group-<n>-<meal|food|other>`、`chat-edit-group-apply-<n>-<meal|food|other>`、`chat-edit-row-<n>-<m>`、`chat-edit-apply-<n>`、`chat-edit-dismiss-<n>`、推荐按钮 `chat-edit-suggest-<n>-<m>`、修复按钮 `chat-edit-repair-<n>-<m>`；带图时的发送披露行 `image-send-disclosure`；历史库旧语音消息（D8 只读兼容，降级为普通用户气泡）：`ai-chat-voice-<n>`；**结束本次对话**（`RV4-P2-04/05`，D4 合并后）：`ai-chat-end-session`（唯一入口）、提炼忙态行 `ai-chat-extracting`、会话结束分隔线 `ai-chat-session-ended`、候选复选 `ai-memory-candidate-<n>`、保存 `ai-memory-candidate-save`；
**清除聊天记录**（`RV4-P2-06`）：`ai-chat-clear-history` + 二次确认 `ai-chat-clear-history-confirm` / `-cancel` / `-confirm-ok`；
**今天还剩多少**（`RV4-R16`）：结果卡 `ai-chat-remaining-card`；
**行级应用**（`RV4-P2-07`）：`chat-edit-row-apply-<n>-<m>`

> P10（2026-10-07）删除的 Key：免责声明行与录音行整块下线，相关键（发送侧语音三键、免责声明）从上表移除，组件与测试同步删除。
> 2026-10-16 删除的 Key：`ai-chat-chip-manual`（「手动记录」chip 下线）。
> 2026-10-23 删除的 Key：`ai-chat-subtitle`（副题退场）、`cta-photo-scan`（chip 换成
> ai-chat-chip-apply-edits（退役）；拍照识餐页与路由保留，但不再有 UI 入口）。
> 2026-10-24 删除的 Key（`RV4-R16` / `RV4-P2-04` / `RV4-P2-05`）：
> ai-chat-chip-apply-edits（退役）（行级应用后多余）、ai-chat-chip-can-i-eat（退役）（只塞半句话）、
> ai-chat-extract-memory（退役）（与 `ai-chat-end-session` **合并**为「结束本次对话」）。
> 顶栏那枚合并后的 `ai-chat-end-session` **恒可点**：回复中点会先取消当前流再结算
> （不再用 `isReplying` 禁用）；**显式动作不受「自动提炼」开关约束**（D4）。
> **AI 聊天建议**（2026-10-23）：每条助手文本回复完成后，用 `suggestionService`
> 再做一次模型调用（路由默认复用对话服务；可注入不同模型的实例），把回复里
> 的 2–3 句用户口吻短回复渲染成 `ai-chat-suggestion-<n>-<m>` 气泡，点一下
> 直接发送。失败静默（建议是增强内容），每条消息只请求一次。

### 5.8 跨页横切契约（设计稿未画到，按裁决保留）

> 以下四项是全 App 级的行为契约，**任何单个 HTML 文件都画不到**。它们有既有测试覆盖，属于必须保留的行为资产，在此收编为规范。

#### 5.8.1 错误、取消与中断恢复矩阵

| 场景 | 必须保留 | 用户操作 | **不允许的行为** | 验收重点 |
|---|---|---|---|---|
| 权限拒绝 / 相册取消 | 当前页面与已确认草稿 | 去设置、重新选择、返回 | 伪造图片或卡在 loading | 冷启动与二次进入都可恢复 |
| 网络断开 / 超时 / 401 / 429 / 5xx | 输入 projection、草稿、来源摘要 | 重试、改用本地路径、取消 | 清空输入或重复发送无确认请求 | 重试不重复写事实 |
| 非法 JSON / 未知 ID / 营养缺失 | 原始草案只在受控内存中、用户输入 | 重新生成、手动整理、丢弃 | 显示为已验证或写入正式表 | `needs-confirmation` 清晰可见 |
| 本地数据库读取失败 | 当前筛选与未提交输入 | 重试、返回 | **显示空列表冒充无数据** | `error` 与 `empty` 可区分 |
| 本地写入失败 | 提交前的 draft 与旧事实 | 重试、保存为草稿、返回 | 显示成功或部分成功为全部成功 | 失败后再次提交幂等 |
| 文件清理部分失败 | 未清理文件的标识与状态 | 单项重试、稍后清理 | 从 UI 删除引用后假装文件不存在 | 进程重启仍可发现并处理 |
| 低存储 / 导入中断 | 旧有效目录、导入进度 | 释放空间、继续、回滚 | 切换成半套目录 | 旧数据仍可搜索 |
| 页面销毁 / 进程被杀 | 已确认事实；未确认 draft 按策略 | 重启后恢复或明确丢弃 | 在已销毁 State 上更新或泄漏临时文件 | 记录恢复策略与证据 |
| 备份恢复失败 | 当前数据库与外围文件 | 返回、重新选择文件 | **先删当前数据再验证备份** | 失败前后当前数据一致 |

#### 5.8.2 导航意图与跨页面状态契约

跨页动作必须传递**意图**，不得依赖全局隐式递增值。实现可用 typed route extra、受控 query 或一次性 intent store，但必须能在冷启动与惰性分支创建时重放。

| 意图 | 目标 | 必传状态 | 返回策略 | 保留状态 |
|---|---|---|---|---|
| `openNutritionRecord` | 饮食页「记录」chip | 日期、来源 | 返回原今日分支 | 日期、滚动位置、搜索草稿 |
| `openNutritionMenu` | 饮食页「菜单」chip | 日期、筛选 | 返回来源页 | chip、日期、筛选、未发布草稿 |
| `openFoodScan` | 拍照识餐（推入） | 来源、餐次可选 | 返回来源分支 | 未确认草稿按恢复策略 |
| `openAiTask` | AI 工作台任务详情 | `taskId`、来源 route、输入摘要引用 | 详情返回一次回来源 | 任务 draft、取消状态 |
| `openAiChat` | `/ai-chat` | 来源与上下文类型 | 返回来源页 | 仅当前会话文本，不写业务事实 |
| `openProfileEdit` | 资料编辑 | 当前 goal、来源 route | push；保存/取消只返回一次 | 未保存表单保留或明确丢弃 |
| `openWorkoutPlanCreate` | 训练计划新建 | 来源、计划日、编辑模式 | push；完成返回训练页 | 草案表单与计划日 |
| `resumeWorkout` | 训练执行态 | session ID、计划日 | 从今日/训练恢复同一 session | 当前组、RPE、休息计时 |
| `openMenuSourceManager` | 菜单维护（二级） | campus/venue/service ID | 从我的进入，返回我的页 | 维护表单与导入草案 |

**导航验收规则**（5 条，逐条必须有测试）：

1. 底栏分支切换由 `StatefulNavigationShell` 控制；route-level 页面使用 `push`，**不得用替换式跳转破坏来源返回栈**
2. 外部程序化跳转必须同步 active 指示、语义选中状态与当前分支；**不能只改变页面内容**
3. 目标 chip、日期与筛选器必须在目标页面首次创建前可读取；**惰性创建不能丢失一次性意图**
4. 每个返回按钮、系统返回键与弹层关闭动作都要定义优先级；**同一成功事件只能执行一次 pop**
5. 未确认草稿不能因切换底栏而静默写入；离开时须显示"继续编辑 / 丢弃 / 取消"决策

#### 5.8.3 响应式与无障碍

| 约束 | 要求 |
|---|---|
| 宽度 | 320 / 360 / 390 / 430dp 与平板约束宽度均需验证 |
| 窄屏降级 | `<360dp` 时今日页多列卡片降为单列；菜单始终单栏 |
| 横向条 | chip / 日期条使用懒加载并**保持选中项可见** |
| 稳定约束 | 图片占位（4:3）、图表、按钮、固定底部操作使用稳定约束，避免动态文字改变布局 |
| 长标题 | 允许换行；**不得用不可见截断掩盖信息** |
| 触达 | ≥44dp；图标按钮必须有 tooltip / semantic label |
| 颜色不是唯一表达 | 图表、圆环、颜色标签**必须同时提供文字摘要** |
| 语义树 | 骨架屏、装饰图案、背景点排除出语义树；输入框只播报一次标签与单位 |
| 文字缩放 | 1.3x / 2.0x 字体、暗色、高对比、reduced motion 均需专门测试 |

#### 5.8.4 底栏几何的 hit-test 回归

底栏凸起圆必须固定几何并做 hit-test / 裁剪回归测试，确认「**看得见也点得到**」：

| 项 | 值 |
|---|---|
| 底栏高 | 64dp（设计稿 `h-[64px]`） |
| 凸起圆直径 | 56dp（设计稿 `w-14 h-14`） |
| `-mt-4` 位移量 | 16dp |
| **净视觉上凸量** | **约 9.5dp**（见下） |
| 内容底部预留 | 64 + safe-area（`extendBody` 下页面需留出底栏高度） |

> **「位移量 ≠ 净视觉量」——这一条有实测数据，实现时不要用 16。**
>
> `-mt-4` 是 16dp 的 **margin 位移**，但槽位是 `flex flex-col items-center justify-center` + `h-full`：负 margin 参与 flex 分配后，**圆顶超出底栏顶边只有约 9.5dp**。真实浏览器实测（390×844，7 个 HTML 全部一致）：
>
> | 量 | 实测值 |
> |---|---|
> | 底栏高 | 64.0 |
> | 圆直径 | 56.0 |
> | 底栏顶边 − 圆顶边 | **9.5** |
> | 圆底边距槽底边 | 17.5 |
> | 槽内 `gap` | 2（`gap-0.5`） |
>
> 因此**槽位盒必须覆盖圆顶：上边距按 ≥ 10dp 预留，不要按 16dp 留**——多留只是浪费，但**少留就会重演历史缺陷**（下条）。反之，若按 16dp 去校验"是否够高"，会得到 6.5dp 的**假超标**，掩盖真正的问题。
>
> 历史教训：本项目曾出现「拍照钮上半部分看不到」的真机缺陷——根因是玻璃层把上凸圆一起裁掉了，且圆钮盒未覆盖上凸带导致既削平又点不到。**新底栏必须同时验证可见性与命中区，两项分别断言**；且**断言必须用实测的 9.5dp，而不是 class 上的 16**。

#### 5.8.5 系统叠层（状态栏 / 手势条）契约

设计稿是浏览器视口截图，**不画任何系统叠层**；状态栏与手势条的高度只能来自运行环境（`MediaQuery.padding`），**不得硬编码成常量**。统一取值走 `LfInsets.top/bottom`（`lib/app/design/lf_insets.dart`）。

> **贴顶清单在 2026-10-08 收缩了**（docs/30 §2 D4/D5/D6）：记录页 / 菜单页 / 身份卡 / 训练页
> 四处顶部卡白卡化后都不再铺到屏幕物理顶边，**只剩「今日页整块内容随叠层下移」与
> 「二级页 `LfTopBar` 自己吃叠层」两处**。下面第一行的「贴顶 hero」因此不再指任何页面，
> 仅作为 `HeroSection.respectTopInset` 的机制说明保留（今日页 AI 卡仍是该机制的唯一使用点）。

| 页面顶部的形态 | 规则 | 验收重点（两项分别断言） |
|---|---|---|
| **贴顶 hero**（今日页 AI 卡；2026-10-08 后仅此一处） | 背景与渐变**必须铺到屏幕物理顶边**（`y == 0`），只有**内容**整体下移 `padding.top` | ① hero 背景块 `top == 0`；② 内容首节点 `top >= 原始内边距 + padding.top` |
| **非贴顶**（今日 / 饮食 / 训练 / 我的四个列表页、二级页 `LfTopBar`、带 `appBar` 的页面） | 整块内容起点 = 设计内边距 **+ `padding.top`** | 首个内容节点 `top >= 原始内边距 + padding.top`；**页面自己给**（卡片与 `HeroSection` 都不再消费叠层） |

三条硬约束：

1. **禁止把 `SafeArea` 套在贴顶 hero 外层**（换句话说：hero 的 bleed 不能被安全区打断）。套上去会把渐变一起推下去，屏幕顶部留出一条页面底色带——那条带只存在于实现里，不存在于设计稿。
2. 带 `appBar` 的页面由 `Scaffold` 负责（`removeTopPadding: appBar != null`），body 里**不要再叠一层**顶部安全区，否则双倍留白。
3. **`LfTopBar` 自己吃顶部叠层**（栏高 = 60 + `padding.top`，内容再加同值内边距）：它作为 `Scaffold.appBar` 时，Scaffold 给的槽位高度本来就是 `preferredSize + padding.top`，栏填满槽位即为正确，不会双倍；**它外面不要再套 `SafeArea`**（饮食未画 tab 与 AI 对话页曾各套一层）。若把它放在 body 里而前面又已有别的叠层处理，用 `respectTopInset: false` 显式声明。
4. 测试必须**注入**人造 `padding.top`（如 48dp）再断言偏移量：widget 测试默认 `padding == 0`，不注入则断言恒真（阶段 J 实测：漏掉 4 个页面正是因为没有一条叠层规则，也就没有一条断言）。

> 实测背景（阶段 J，API 35 模拟器 1080×2400 @420）：状态栏 `frame=[0,0][1080,128]`（128px = 48.8dp，含刘海）。修复前各页内容首节点 `top`：今日 21 / 饮食·记录 53 / 训练 hero 内标题 53 / 我的 53 / 拍照识餐顶栏返回键 20（全部落在 0..128 带内，被状态栏时钟压住）；饮食·菜单因外层套了 `SafeArea` 而 `top=128` 但渐变没铺到顶边，属同类偏差的另一种表现。修复后：今日 149 / 记录 181 / 菜单 181 / 训练 181 / 我的 181 / 顶栏内 20+128。
（2026-10-08 补记：这条实测记录的是**当日**的形状，此后记录 / 菜单 / 训练 / 我的四处
顶部卡白卡化，四页的首节点位置随卡片形态变化重算——见各页 §5.2 / §5.3 / §5.5 / §5.6，
断言在 `test/app/design/system_inset_test.dart`。）

---

### 5.9 建立本地档案（`初始引导.html`；2026-10-13 按 `docs/32` §4 T15 补章）

> §5.1–§5.7 覆盖七个主页，建档页一直没有本节。补记它的**落地形状与测试 Key**
> （结构按 `docs/32` §3 D18 与设计稿合并：借布局与交互，主题/图标/动效仍按
> 本仓现状）。

| 项 | 规范 |
|---|---|
| 路由 | `/onboarding`；首启必经，**不加「跳过」**（`docs/32` §3 D18 第 8 条：设计稿的跳过与必经流程语义冲突） |
| 阶段条 | 4 段 24×4dp 胶囊，已过的段累计填充主色；**仅视觉进度**——按滚动位置 `p = pixels / maxScrollExtent` 映射（`<.25 / <.5 / <.75` 三档；不足一屏恒为第 1 段），不拆步、不与校验状态绑定 |
| 微标签 | `STEP n / 4 · 建立档案`（label 档、字距放宽 1.2、主色） |
| 卡片副文案 | 基本信息「用于计算基础代谢率与营养分配」；你的目标「选择主要方向，系统将据此调整营养与训练计划」 |
| 活动档 | **4 档**（`ActivityLevel` 枚举不动），标签描述式：久坐 — 几乎不运动 / 轻度 — 每周 1-2 次低强度 / 中度 — 每周 3-4 次中等强度 / 高强度 — 每周 5-6 次较高强度 |
| 分段控件（性别） | `LfSegmentControl`：48dp 轨道 + 3dp 内衬 + radiusMd；选中段 card 底 + 主色字 w600 + surface 阴影 |
| 安全筛查 | 行式：左问题文本 + 右 46×28 `LfToggleSwitch`；行间 1px 分隔线；**整行可点**（行高 ≥ 44dp），开关本身不接手势 |
| 主行动 | `FixedBottomPrimaryAction`（贴底、不随内容滚动；**h48**，不采设计稿 52dp） |

**测试 Key**：`onboarding-progress`、`onboarding-progress-label`、`onboarding-sex-female`、`onboarding-sex-male`、`onboarding-safety-card`、`onboarding-submit`、`onboarding-pregnancy-risk`、`onboarding-chronic-risk`、`onboarding-eating-risk`

---

## §6 诚实规则与设计稿矛盾裁决

### 6.1 诚实规则（最高优先级的行为约束）

设计稿是**视觉稿**，其中的数值全部是**演示数据**。以下数值**不得**作为真实数据显示给用户，必须由本地库真值渲染：

`9月23日 周二`、`早安，小林`、`552 kcal`、`1800 kcal`、`1248`、`69%`、`42/60g`、`156/200g`、`38/50g`、`30%/50%/20%`、`69.4 kg`、`↓0.8`、`18.2%`、`31.5 kg`、`423 kcal`、`730 kcal`、`95 kcal`、`460 kcal`、`1.5/2.0L`、`75%`、`6,602 步`、`1.4k`、`1247`、`553`、`4/7`、`1561`、`87%`、`1470 kcal`、`520 kcal`、`94%`、`35g/52g/19g`、`第38周`、`4 已完成训练`、`2.8h`、`1,840`、`18分钟`、`65%`、`128 天`、`5kg`、`65.2 kg`、`5,840`、`22.6 BMI`、`1,480`、`12,580 条`、`v1.0.0`、`320大卡`

**无数据时用诚实空态**，不得用示例值填充：

| 场景 | 空态文案 |
|---|---|
| 无体重 | `--` 或「还没有体重记录」 |
| 无体脂/肌肉量 | ~~`--`~~ → **2026-10-09 schema 22（docs/31 S2）废止**：体脂率/肌肉量字段、数据、入口整族删除，本空态不再适用 |
| 无饮水记录 | `暂无记录` |
| 无步数 | ~~`暂无记录`（已裁决，不引设备依赖）~~ → **2026-10-07 P9 as-built 修订**：本机步数已接线（§6.2 #9），无传感器时显示「这台设备没有计步传感器」，未授权时显示说明态 |
| 无成就 | 全部显示未解锁态 |
| 无 AI 配置 | 「尚未配置」+ 去设置入口 |
| 无菜品点评 | **不渲染该块**（不是显示占位） |
| 无微量营养素 | **不渲染该行** |

### 6.2 设计稿内部矛盾裁决表

设计稿由 7 个独立文件构成，存在若干内部不一致。**逐条裁决如下**：

| # | 矛盾 | 裁决 |
|---|---|---|
| 1 | 今日页 `1248 / 552`，饮食·记录页 `1247 / 553`（差 1） | **无关紧要**。两页都由真值渲染，天然一致 |
| 2 | 饮食·记录 hero `1247` ≠ 该页餐卡合计 `960` | **无关紧要**。hero 显示当日全部摄入，餐卡列表是真值的子集，由数据自然决定 |
| 3 | 今日页体重 `69.4 kg`，我的页 `65.2 kg`（同日） | **无关紧要**。都取 `Measurements` 最新值，天然一致 |
| 4 | 训练页容量图"今天"索引=0（周一），但日期是周二；且"休息日 二/四/日"与"进行中训练"矛盾 | **必须按真实数据推导**：容量图的"今天"取 `now.weekday`；休息日**来自计划**（该 weekday 无 `PlannedExercises`），不硬编码"二/四/日"；"进行中"只在确有 `status='active'` 的 session 时显示 |
| 5 | AI 工作页底栏高亮在 dashboard | **修正为 ai 槽高亮**（设计稿是复制粘贴失误） |
| 6 | 拍照识餐页**有**底栏块但**没有任何 `data-active`** | **有意偏离设计稿**：它是二级页，实现为推入式路由**不带底栏**。注意设计稿 `拍照识餐.html` **确实包含完整的 `<nav data-mobile-nav="global">`**（`<!-- 8. BOTTOM NAV -->`，5 槽齐全），只是**没给任何槽打 active 标记**——这正是"它是二级页"的佐证，但**不能说"设计稿没画底栏"**。实现时删掉这段 nav 是有依据的偏离，须在本条留档 |
| 7 | 训练页 hero 三段统计与"本周训练统计"卡内容重复 | **按设计稿保留重复**。hero 是概览、卡片是分类型明细，信息层级不同 |
| 8 | 我的页 `1,480 基础代谢率` 无单位 | **补单位 `kcal/天`**。设计稿缺漏 |
| 9 | 训练页步数目标从未打印（`还差 1.4k` 隐含 8000） | **今日页步数卡显示「暂无记录」**，不显示隐含目标（已裁决）。**2026-10-07 P9 as-built 修订**：P9 已为本机步数接线（`ACTIVITY_RECOGNITION` 权限 + MethodChannel 读计步），本条「不引设备依赖」的前提不再成立，原裁决废止——步数卡按数据可得性显示三态（记录中 / 未授权说明 / 无传感器「这台设备没有计步传感器」）；「不显示隐含目标」的原则保留（步数目标不硬编码进 UI） |
| 10 | 微量营养素行只出现在菜单第 3 张卡 | **仅在数据存在时渲染**该行，不做"第 3 张卡才有"的硬编码 |
| 11 | 成就 4 个看起来都是已解锁，无未解锁态 | **必须补未解锁态**（灰度 + 锁图标 + muted 文字），否则空态无表达 |
| 12 | 「我的」页身份卡"目标减脂 5kg" | 取 `Goals.type` + 目标体重差；无目标则不显示该短语 |
| 13 | 菜单页菜品卡的「配料行」（`燕麦 + 牛奶 + 蓝莓 + 杏仁`）在 §5.3 数据来源表里**没有对应列** | **不渲染该行**。`DishLibrary` 没有配料列，§5.3 已逐项钉死每个元素取哪个列、唯独没有它；凭菜名反推配料就是编事实（§6.1）。若日后需要，须先加列 + 在写入路径填充，不得在展示层猜 |

---

## §7 数据契约 — 新增域

> **关键前提**：新增域必须走**现有架构约定**——Drift 表 + 仓储 + 用例，不得在 UI 层直连数据库。schema 版本 16 → **17**，一次性迁移到位。

### 7.1 派生只读（**不建表**）

| 项 | 来源 | 公式 |
|---|---|---|
| BMI | `Measurements.weightKg` + `Profiles.heightCm` | `w / (h/100)²`；**分档口径**（偏瘦/正常/超重/肥胖，边界 18.5/24.0/28.0 左闭右开）见 `lib/features/settings/domain/health_metric_bands.dart`（docs/29 §P2 起，本文件不复制边界） |
| 基础代谢率 | `Profiles`（性别/年龄/身高/体重） | Mifflin-St Jeor |
| 连续天数 streak | `Meals` 按日分组 | 从今天向前连续有记录的天数 |
| 总记录数 | `Meals` count | — |
| 进行中会话进度 % | `WorkoutSets` / `PlannedExercises.targetSets` | 已完成组数 / 计划组数 |
| 第 N 周 | 首个 `WorkoutSessions.localDate` → 今天 | 周序号 |
| 训练容量（按 weekday） | `WorkoutSets.completedAt` 聚合 | 各 weekday 的训练分钟数 |

### 7.2 新增表

| 表 | 列 | 说明 |
|---|---|---|
| `WaterIntakes` | id, localDate, amountMl, recordedAt, createdAt, updatedAt | 饮水摄入。`localDate` 建索引 |
| `BodyCompositions` | **已删除（2026-10-09 schema 22，docs/31 S2）** | 本行旧文「也可扩展 `Measurements` 加列」已随需求 45/46 反转：实测走的是**扩展 `Measurements`**（同一测量时刻同行），而 `bodyFatPercent`/`muscleMassKg` 两列因「其他所有地方都删掉」连数据一起 drop（本仓第一次减列迁移，旧 `.lfb` 里这两个键恢复时被静默忽略）——独立建表与加列两条路都没留。原记载按 docs/31 §0 第 1 条作废，勿照做 |
| `Achievements` | id, key, unlockedAt?, progress (0.0) | 成就与解锁态。`key` 唯一 |

**成就解锁条件（设计稿只给了 4 个名字，未给规则——此处补齐，实施时不得再发明）**

| key | 名称 | 解锁条件 | 进度口径 |
|---|---|---|---|
| `streak-7` | 7天连续打卡 | 连续记录天数 ≥ 7 | `min(streak / 7, 1.0)` |
| `nutrition-master` | 营养达人 | 累计 **达标天数** ≥ 7（达标 = 当日摄入未超过目标上限 `calorieMaxKcal`；低于下限另由分析卡提示，2026-10-23 与 `hitCount` 统一口径） | `min(达标天数 / 7, 1.0)` |
| `workout-athlete` | 运动健将 | 累计已完成训练次数 ≥ 10 | `min(完成次数 / 10, 1.0)` |
| `healthy-diet` | 健康饮食 | 累计记录餐次 ≥ 30 | `min(餐次数 / 30, 1.0)` |

**规则**：`unlockedAt` 一经写入**不可回退**（即使连续天数后来断了，成就保持已解锁——成就是对历史事实的确认，不是当前状态的镜像）。

> **2026-10-05 docs/29 §P3 起，下面那句的视觉部分已被取代**（解锁条件、进度口径与「不可回退」不变）：四列网格改成**行卡**。未解锁 = muted 内盘 + 挂锁 + 等级徽标（铜/银）；已解锁 = **实心等级色内盘** + 该成就自己的图标 + 第 2 行改「已解锁」。名称两态**用同一个颜色**（`foreground`）——名称是信息，不该因为「未解锁」就被压低对比（旧写法是解锁给 `textPrimary`、未解锁给 `textTertiary`）。「未解锁不得塌陷或隐藏」这条继续有效，且升级成**混态也严格等高**（`<0.5px`）。详见 §5.6 的「成就分级与进度的口径」。
> 旧的视觉描述（存档）：徽章**未解锁**态 = 灰度底 + 锁图标 + `textTertiary` 名称；**已解锁** = `mint-100` 底 + 图标 + `textPrimary` 名称。四格高度一致，未解锁不得塌陷或隐藏。

| `DishLibrary` | id, name, imagePath?, mealSlot, servingWindow, isHot, kcal, proteinG, carbsG, fatG, fiberG?, sodiumMg?, vitaminDMcg?, source, comment?, createdAt, updatedAt | 菜品库（菜单页数据源）。含微量营养素与营养师点评 |
| `CardioPrescriptions` | id, plannedExerciseId, kind (pace|resistance|duration), value, unit | 心血管处方。**与力量组次不同型**，单独建表而非塞进 `PlannedExercises` 的数值列 |
| `RecognitionResults` | id, mealId?, capturedAt, dishName, confidence, imagePath, estimatedKcal, advice?, ingredientsJson, macroJson | 拍照识别结果快照 |
| `ConversationMessages` | id, sessionId, role, text, createdAt, imagePath?, audioPath?, durationMs?, status | AI 聊天记录 |
| `AppSettings` | key (PK), value | 键值设置（自动本地备份开关等） |

### 7.3 AI 生成项（走现有 AI 任务管线）

| 项 | 复用 |
|---|---|
| 微量营养素（膳食纤维/钠/维D） | 现有 `dish-nutrition` 任务扩展 JSON 字段 |
| 营养师点评 | 现有 `dish-guidance` 任务产出 |
| 菜品库推荐 | 现有 `daily-menu-plan` 任务产出 |

**证据分级必须贯穿**：AI 生成的数据一律标 `AI 估算`（evidence-b），用户确认后才升级为 `已确认`（evidence-a）。这是现有系统的既有能力，新页面**必须**继续展示分级徽章。

### 7.4 迁移要求

| 要求 | 说明 |
|---|---|
| 版本 | `schemaVersion` 16 → **17** |
| 兼容 | 迁移必须**只增不改不删**——现有 **37 张**逻辑表的结构与数据不得变动（口径 = `AppDatabase` 的 `@DriftDatabase(tables:)` 清单，与 `LocalFitBackupTables` 对账；`STATUS.md` Baseline 同口径） |
| 测试 | 必须有 16→17 迁移测试：造 16 版数据库 → 迁移 → 断言旧数据完整 + 新表可用 |
| 备份 | **`local_fit` 备份的表清单是 `lib/features/backup/application/backup_table_registry.dart` 的 `LocalFitBackupTables`**（单一事实源，导出与恢复共用），8 张新表必须逐张加入，否则备份会漏数据。`docs/03` §12 只定原则（是否进 `.lfb`、字段预览、失败回滚），**不含表清单**——不要去找它。仓库已有「备份清单 == schema 全部逻辑表」的对账断言，漏加会直接红 |

---

## §8 测试策略

> 用户裁决：「**测试跟随新设计改写**」——保留全部行为断言，改写绑定旧布局的视觉断言。
### 8.1 分类口径

| 类别 | 判定 | 处置 |
|---|---|---|
| **行为测试** | 不含 `testWidgets`，或虽含但只断言数据/路由/错误路径 | **保留**。这类测试共 114 个文件 / 694 个 `test`，是项目的核心资产 |
| **视觉测试** | 断言具体文案、控件类型、布局 Key | **改写**。共 95 个文件 / 456 个 `testWidgets`，其 313 个 Key 字面量需按 §5 的新 Key 表替换 |

### 8.2 改写规则

1. **先改 Key，再看断言**：§5 已为每页定义新 Key 表，先机械替换 Key，再处理断言。
2. **文案断言必须改为语义断言**：不写 `find.text('今日热量')`，改写为 `find.byKey(Key('dashboard-calorie-ring'))`。理由：文案会随设计调整，Key 是稳定的。
3. **每个新测试必须配隔离变异红证**：在 `lib/` 里制造一个变异使该测试变红，确认后还原（`grep -rn MUTATION lib/ test/ | wc -l` 必须为 0）。**在缺陷代码上仍全绿的测试是空转测试**。
4. **禁止放宽断言换绿灯**。测试红时的正确动作是：判断是测试错还是生产代码错。若测试红是因为定位变化（Key/结构变了），**按新结构重新定位**；若是生产缺陷，修生产代码。
5. **测试数量可以波动**，不设"不得少于 N 条"的硬指标。但**每条行为断言不得丢失**——迁移时必须逐一确认旧断言在新测试中有对应。

### 8.3 视觉验收（不可替代）

单测与 `flutter analyze` **不能**证明"看起来像设计稿"。每个页面完成后必须：

1. 在模拟器（`LocalFit_API35`，`emulator-5556`）上运行
2. `adb shell uiautomator dump` + 截图
3. **与 `ui设计/pages/*.html` 并排比对**（背景色、卡片圆角、边框存在性、色块位置、字号层级、间距）
4. 差异写入 `docs/evidence/` 证据文档

### 8.4 门禁

`tool/verify.bat`（`pub get` → `dart format --set-exit-if-changed` → `flutter analyze` → `flutter test`）全部退出码 0。

**注意**：`dart format --output=none` **不写回格式**。改完代码必须单独跑 `E:/AI/toolchains/flutter/bin/dart format lib test`，否则门禁会在 format 步骤失败。

---

## 附录 A：设计稿文件清单

| 文件 | 对应路由 | 底栏高亮 | 体积 |
|---|---|---|---|
| `ui设计/pages/今日.html` | `/today` | dashboard | 30 KB |
| `ui设计/pages/饮食 · 记录.html` | `/nutrition`（记录 chip） | nutrition | 33 KB |
| `ui设计/pages/饮食 · 菜单.html` | `/nutrition`（菜单 chip） | nutrition | 28 KB |
| `ui设计/pages/拍照识餐.html` | `/meal-recognition` | **无 active 标记**（二级页；该文件含底栏块，实现时按 §6.2 #6 有意省略） | 25 KB |
| `ui设计/pages/训练.html` | `/training` | training | 36 KB |
| `ui设计/pages/我的.html` | `/settings` | settings | 29 KB |
| `ui设计/pages/AI 工作.html` | `/ai-chat` | **ai**（设计稿误标 dashboard） | 36 KB |

## 附录 B：设计稿的静态性质

7 个 HTML 是**静态视觉稿**：Tailwind 4.3.1 浏览器 CDN + lucide 1.8.0 图标 + Chart.js 4.4.1 图表，**零事件处理器**（`onclick` / `addEventListener` 均无）。

因此：
- 所有交互行为必须从**标签文字、`data-dom-id`、结构与状态类**推断，本文 §5 已完成推断
- 无 id 的控件（10 处，见 §5 各页 Key 表）由本文补齐命名
- 6 个 radius 变量跨文件不一致（`4/8/12/16/16/16` vs `8/12/16/20/24/32`），但因 `rounded-sm|md|lg|xl|2xl` 用量为 0，**不产生视觉影响**（见 §2.3 实测）

## 附录 C：术语

| 术语 | 含义 |
|---|---|
| 凸起圆 | 底栏中间槽位的 56×56 全圆按钮；`-mt-4` 位移 16dp，**净视觉上凸约 9.5dp**（见 §5.8.4） |
| muted 块 | 卡内使用 `--lf-muted` 底色的嵌套块，**不是白卡** |
| 计划态 | 已规划但未记录的餐次，用虚线边框 + 虚线节点表达（**随周计划 / `MealPlanEntries` 删表下线，现无对应 UI**） |
| 证据分级 | `已确认`(a) / `AI 估算`(b) / `待补全`(c) 三档，色见 §2.1.5 |
| 诚实空态 | 无数据时显示 `--` / `暂无记录` / 不渲染，**绝不用示例值** |

## 附录 D0：2026-10-24 编辑卡三档按钮层级（`docs/56` R15 后续）

用户 2026-10-24：「**要应用本组，但是按钮样式要显眼一些**，你优化一下，现在纯文本看着难受」。

编辑卡内三种「应用」动作按**粒度**分层，视觉强度跟着粒度走：

| 档 | 控件 | 粒度 | 取色 | Key |
|---|---|---|---|---|
| 行级 | `LfPillButton`（B3 胶囊，默认 muted） | 一行 | `muted` 底 + `mutedForeground` 字 | `chat-edit-row-apply-<c>-<r>` |
| **组级** | **`LfSoftButton(dense: true)`（B10 软底强调，h48 / R12 / 14px 字 / 12px 内边距）** | 一组 | **`brandSoft` 浅品牌底 + `mintText` 品牌字 + `done_all` 图标** | `chat-edit-group-apply-<c>-<kind>` |
| 卡级 | `LfPrimaryButton`（B1 实心，h44） | 整卡 | 主色实底 + `primaryForeground` 字 | `chat-edit-apply-<c>` |

**纪律**：组级**不得**升到 `LfPrimaryButton` —— 一卡只有一个主行动（「全部应用」），
否则「应用本组」会抢主按钮的层级。组级此前是 `LfTextButton`（透明底纯文本），
与它承担的「一次应用这一组」重要性相反，已按用户要求改为软底。
回归钉子：`test/features/ai_conversation/chat_edit_group_apply_style_test.dart`（5 条：
可见底色 / 命中 ≥44 / 取 soft 档且卡底仍是实心 / 点击仍只提交本组 / 忙碌时不渲染）。

> **2026-10-24 追加：组级改用 `dense` 档**（用户随后选定方案 B「清单式」）。
>
> 分块版式让卡片变高，按原尺寸（h44 / 15px / 16px 内边距）的「应用本组」在 390dp 宽下
> 占近半行宽，与卡底「全部应用」抢主行动。`LfSoftButton` 因此增 `dense` 参数：
> **14px 字 + 12px 内边距**，仍是 B10 软底——**档位不变，只收横向与字号**。
>
> **高度刻意保持 48**：实测把 `minimumSize` 写成 36 也会被 Material 的 `tapTargetSize`
> 抬回 48。这是对的——可点控件的触控目标不该为了好看低于无障碍下限。**不许绕过它**。
>
> **卡片版式同步改为「清单式」**（docs/56 方案 B）：卡头 = 结论行（「午餐 · 3 条修改」）
> + 明细行（这条要记的东西）；条目进 `MutedBlock` 分块、带编号、组内分隔线。
> 待确认态徽标改为「待确认」（数量已在结论行，重复写是噪音）。

## 附录 D：2026-10-18 as-built（P1 统一体验新增面与 Key）

本轮（`docs/41` P1）不改既有页面结构，只在三处新增交互面；Key 与文案如下
（新页面/新状态都在 `Key` 表中可测）。

### D1 记录餐两个入口（`docs/40` §2.4）

| Key | 形态 | 文案/行为 |
|---|---|---|
| `meal-entry-chooser` | `AppSheet` 弹层根 | 标题「记录一餐」；说明句「按食材记账用食物库（每 100g）；吃现成的菜用我的菜（按份）。」 |
| `meal-entry-by-food` | `DesignCard` 行（可点） | 「按食材记录 / 食物库 · 每 100g × 克数」→ 既有 `MealEditorDialog`（键契约不变） |
| `meal-entry-by-dish` | `DesignCard` 行（可点） | 「按菜品记录 / 我的菜 · 按份记入」→ `dish-meal-picker` |
| `dish-meal-picker` | 弹层根 | 菜品库列表（空态见下一行） |
| `dish-meal-picker-empty` | 空态文案 | 菜品库为空时的**可行动**文案「先存为菜品 / 在食堂目录里分析菜品」；不写「暂无数据」 |
| `dish-meal-picker-item-<dishId>` | 列表行 | 名称 + 餐次 + kcal/份 + 来源徽标（与菜品卡同源） |
| `dish-meal-confirm` / `dish-meal-cancel` | B3 / B6 | 「记一份」/「取消」 |
| `meal-entry-by-food` 之后的既有键 | — | `meal-food-search` / `meal-save` / `meal-grams-item-N` 一字不动 |

进口径：`FAB → 入口弹层 → 按食材 = 旧编辑弹层；按菜品 = 选菜 → 确认（整份）`。
**不新增写路径**：两条都落到 `MealRepository.create`（`source` 分别为
`manual` / `dish_library`）。

### D2 建食堂菜时的「参考食物库」chip（`docs/40` §3.1）

| Key | 文案/行为 |
|---|---|
| `food-reference-sheet` | 弹层根；标题「食物库里有「<菜名>」吗？」 |
| `food-reference-adopt` | B3「引用食物库营养」→ 证据表 per100g + `origin=food_library` + 链接 confirmed |
| `food-reference-analyze` | B6「让 AI 重新分析」→ 既有分析入口 |
| `food-reference-skip` | B6「先不填」→ 不写任何数据 |
| ~~`food-reference-source` / `food-reference-evidence`~~ | **2026-10-24 退役**（`RV4-P2-12` / `docs/56` R7）：弹层在「决策前」，菜还没有营养、来源尚未确定，两枚徽标在这个语境没有信息量。三枚动作 Key（`-adopt` / `-analyze` / `-skip`）**保留** |

**不静默填**：命中才弹，弹层并排显示食物库每 100g 值与匹配分；没有命中/未接线
时行为与旧版逐字一致。

### D3 手动营养与记忆晋升

| Key | 文案/行为 |
|---|---|
| `canteen-dish-manual-nutrition` | 菜品动作表新增项「手动填写营养（每 100g）」 |
| `manual-nutrition-sheet` | 表单根；四个数字字段 `manual-nutrition-kcal/protein/carbs/fat` |
| `manual-nutrition-save` | B3「保存（标为用户输入）」→ `origin=user_input`、grade D |
| `manual-nutrition-error` | 就地错误（数字非法/越界；不关窗） |
| `ai-memory-promote-delete` | 「转为忌口/偏好」成功后追问「顺便删掉这条记忆？」的删除钮；晋升走 `constraints.set` 同一写路径，**不自动删** |

### D4 来源徽标统一（`docs/41` §7 铁律 ④）

`LfSourceBadgePair` 是唯一来源/证据组合件：左「来源种类」（食物/菜品/食堂菜/
扫描/手动/对话），右「证据」（已确认/AI 估算/待补全；食堂营养另用
`食物库/用户输入/AI 估算` 三档文案）。餐记录卡、菜品选择行、参考食物库弹层、
手动营养入口都用它，**不许各页自绘**。

### D5 搜索调试面板（`docs/39` G21）

| Key | 形态 | 行为 |
|---|---|---|
| `settings-retrieval-debug-row` | 设置页 AI 组行 | 「搜索调试 / 看检索为什么命中/不命中」→ 推入 `/retrieval-debug`；未接线时不渲染 |
| `retrieval-debug-title` / `retrieval-debug-close` | 顶栏 | 标题「搜索调试」+ 关闭（`LfIconButton`） |
| `retrieval-debug-query` | 输入框 | 改查询即时重跑（与检索服务同源） |
| `retrieval-debug-results` | 卡片 | 前 5 条：名称 · 分数（命中路）；无命中显示「（无命中…）」 |
| `retrieval-debug-hit-<id>` | 结果行 | 单条命中（测试锚点） |
| `retrieval-debug-rerun` | 文字按钮 | 重新运行 |

面板内容四段：查询理解（关键词/扩展词/槽位/否定/语义路开关）、各路命中
（关键词/标签/语义 + 候选总数）、模式对比（BALANCED / KEYWORD_FIRST）、前 5 条。
**只读**：不写库、不改设置、不调 AI。

### D6 菜品卡的份量与陈旧徽标（`docs/40` §2.2 / §6，2026-10-18 晚补）

| Key | 形态 | 行为 |
|---|---|---|
| `nutrition-menu-dish-basis-<index>` | 中性徽标「按 100g 估算」 | 仅 `basisAssumed=true`（份量未知/历史回填）时渲染；**不假装知道份量** |
| ~~`nutrition-menu-dish-stale-<index>`~~ | **2026-10-24 退役**（`RV4-P2-09` / `docs/56` R10-c / 裁决 D2）：「陈旧提示 + 手动同步」整族退役——自动同步已覆盖建菜/改名/换照片/写营养/删菜/删窗口/删地点七条写路径，且 `userEdited` 行现被**冻结**（`DishLibraryRepository.upsertBySource` 跳过手改行）。详见 `docs/40 §6` |

判定与订阅都在菜单页自己完成（`DishStalenessChecker`；显式注入优先，否则用
菜品库仓储自带的库），宿主不再传 map。订阅 `menu_items` 表变更后重判，结果与
当前值相等时**不** setState——否则会形成「刷新 → 重建 → 换流重订阅 → 再刷新」
的闭环（2026-10-18 实测一次 `pumpAndSettle` 触发 3001 次刷新）。

### D7 同步、反馈、整理与索引状态（2026-10-19 补齐）

| Key | 形态 | 行为 |
|---|---|---|
| ~~`nutrition-menu-dish-sync-<index>`~~ | **2026-10-24 退役**（同上）：手动同步没有对象了——自动同步是唯一路径，用户手改行被冻结 |
| `nutrition-menu-meal-<slot>-like` | 槽卡 heading 行右端「不错」 | 记一次 `FeedbackVote.like`（`app_settings` KV，不新增表），成功后提示「已记下「不错」，以后同类会多推荐」 |
| ~~`nutrition-menu-meal-<slot>-swap`~~ | **2026-10-24 退役**（`RV4-P2-08` / `docs/56` R10-a / D3）：三格各自「换一个」会破坏整套营养平衡（用户：「换就整整齐齐换一套」）。替代：`nutrition-menu-daily-set-repick`（卡头「换一整套」，**未配置 AI 也可点**，走本地重排 + 一句实话） |
| （2026-10-24 整族退役，无 Key） | **整理重复菜品 / 关联到食堂菜品** | 用户：「我希望他们就是一个库，不要分开，不要自己加入。这样就不需要整理重复菜品和关联到食堂菜品」——食堂菜自动进菜品库且按来源键更新，同名副本不再产生，重复整理与关联动作没有对象；页面/路由/设置入口/`loadDuplicateSuggestions` 全部删除 |
| `retrieval-debug-index`（段） | 搜索调试面板首段 | 「索引与后台任务」：`向量索引：N 条（语义检索关，P0 门槛未过）`、后台任务最近 5 条（类型·状态 + 进度/失败原因）；无任务写「无」 |

**纪律**：同步只在用户点「同步」时发生；反馈只由点击产生（无静默学习）；关联只建立
链接、不合并、不改营养；索引段只读，0 条也如实显示。

### D9 记忆时间语义与「按日期回看」（S14 / G23，2026-10-19）

| Key | 形态 | 行为 |
|---|---|---|
| `ai-memory-asof` | 记忆页底部文字按钮「按日期回看」 | 选一天，列出**那天成立**的记忆（查询时刻取当天 23:59:59 本地）；旧条在改口前仍然返回 |
| `ai-memory-asof-sheet` | 结果弹层根 | 标题「YYYY-MM-DD 那天记住的」 |
| `ai-memory-asof-row-<id>` | 结果行 | 「正文（类型 · 域 · 有效期）」 |
| 副标题后缀 | 仅**已闭合**条目 | 「· 有效期 2026-10-01 – 2026-10-10（已改口）」；开放中的条目不显示（避免噪声） |

日期选择通过 `AiMemoryPage.pickAsOfDate` 注入（null＝系统日期选择器），
测试不依赖平台对话框。空态「那天还没有任何记忆。」。
**只读**：回看不写库、不改变当前列表。

### D8 弹层必须浮在贴底栏之上（2026-10-19 修）

`showModalBottomSheet` 的默认 `useRootNavigator: false` 会把弹层挂进**分支
导航器**；而 `AppShell` 是 `Scaffold(extendBody: true)`（正文延伸到贴底栏
之下），于是弹层的最后一行会被底栏盖住——2026-10-19 设备实测：手动营养弹层
的「保存（标为用户输入）」bounds 落在导航条下面，点击被导航吃掉（跳到 AI 页），
营养没写进库。

**约定**（新弹层一律照此写，`AppSheet` 早已如此）：
`useRootNavigator: true` + `enableDrag: false`（拖拽只认把手）+
`sheetBottomInset(context)`（键盘 + 安全区 + 最小留白）。
回归钉子 `manual_nutrition_sheet_test` 的宿主按 shell 同形搭
（`extendBody: true` + 正文内嵌 Navigator + 贴底导航条）——在根 Navigator 里
测**复现不出来**，这也是该缺陷此前没被发现的原因。

### D10 下一阶段可见性、治理与食物路由（`docs/43` A1–A4 / B5–B11，2026-10-20）

| Key | 形态 | 行为 |
|---|---|---|
| `nutrition-menu-search` | 菜单页段头下方搜索框 | 输入即检索（200ms 防抖）；语义可用时三路（关键词+标签+语义），不可用自动退两路，**不弹错** |
| `nutrition-menu-search-clear` | 搜索框右端清空钮 | 清空即回推荐区（不保留搜索态） |
| `nutrition-menu-search-count` | 结果头「找到 N 道」 | 有结果才渲染（空态不写「找到 0 道」） |
| `nutrition-menu-search-hit-<id>` | 结果行 | 名称 + kcal/份 + 来源徽标 + 窗口 + 「命中：关键词/标签/语义」 |
| `nutrition-menu-search-reasons-<id>` | 结果行的命中原因 | 只列真的参与的路，不编造语义命中 |
| `nutrition-menu-search-add-<id>` | 结果行「加入餐」 | 复用 `onAddToMeal`（与菜品卡同一写路径） |
| `nutrition-menu-search-empty` | 空态 | 「没有匹配「<query>」的菜。」+「试试更短的关键词或口味词。」 |
| `nutrition-menu-degraded-note` | 搜索结果区提示行（2026-10-20 RV-P1-09） | 语义不可用时显示矩阵文案；引擎可用但候选不过阈值时显示「语义候选相关度不足，本次按关键词 + 标签显示」 |
| `nutrition-menu-intro` | 段头指引行 | 搜索态改为搜索说明；非搜索态仍是「按你的食堂窗口推荐…」 |
| `training-retry` / `canteen-directory-retry` | 错误态重试钮（2026-10-20 RV-P1-12） | 训练/食堂目录加载失败时渲染（不再永久 spinner） |
| `retrieval-debug-mode-balanced` / `-keyword` / `-semantic` | 调试面板「模式对比」三行 | 同一查询分别按 BALANCED / KEYWORD_FIRST / SEMANTIC_FIRST 跑一次，显示条数与首条 |
| `retrieval-debug-semantic-reason` | 语义卡「未参与原因」 | 开关关/索引空/引擎失败等原因可见（docs/43 A1 要求） |
| `ai-memory-usage` | 记忆页「已用 N / 2000（软顶）」 | 达硬顶时写入被拒（文案指向整理） |
| `ai-memory-softcap-hint` | 记忆页超软顶提示 | 「已超过软顶，建议整理。」 |
| `ai-memory-hygiene` | 记忆页入口 | 「整理建议」→ 弹层（只建议，确认才动） |
| `ai-memory-hygiene-sheet` | 整理弹层根 | 「可能重复（N 簇）」「长期未用（N 条）」；空态「暂时没有整理建议。」 |
| `ai-memory-hygiene-merge-<id>` / `-archive-<id>` / `-skip-<id>` | 整理行动作 | 合并 = `supersede`（旧条闭合、历史可回看）；归档 = `status='archived'`；先不管不写库 |
| `ai-memory-pending` | 记忆页「待确认 N 条」 | 打开待确认弹层（会话结束提炼的候选） |
| `ai-memory-pending-sheet` | 待确认弹层根 | 逐条「保存 / 忽略」；保存走 `remember(source='extracted')` |
| `ai-memory-pending-save-<n>` / `-ignore-<n>` / `-error-<n>` | 待确认动作与就地错误 | 忽略只移出 payload；失败（重复/合并建议）就地显示，不吞 |
| `ai-memory-load-more` | 记忆页底部「加载更多」 | 总数 >50 或搜索非空时分页（每页 50） |
| `ai-memory-total` | 记忆页「共 N 条」 | 分页模式的头部计数 |
| `ai-chat-end-session` | 对话页顶栏「结束本次会话」 | 可用消息 ≥6 且 `ai_memory_auto_extract` 开启才提炼；候选进待确认，**不静默写库** |
| `ai-chat-offline-note` | 对话页输入区上方提示条（2026-10-21 裁决 D-2） | 仅在有「最近 10 分钟内连接失败」证据时出现；文案「当前连不上网络：AI 回复不可用；本地记录、搜索与记忆写入不受影响。」；一次成功请求即消失 |

**纪律**：搜索只读（不写库）；整理建议只产生建议，合并/归档都由用户点击触发；
待确认候选确认才写 `ai_memories`；调度器的「未接充电判定：应用在后台近似空闲
（重任务暂不自动跑）」在调试面板如实显示（决策点 D1 未答复 ⇒ 实现 B）。

---
**测试 Key（docs/43 下一阶段，2026-10-20）**：`nutrition-menu-search`、`nutrition-menu-search-clear`、`nutrition-menu-search-count`、`nutrition-menu-search-hit-<id>`、`nutrition-menu-search-reasons-<id>`、`nutrition-menu-search-add-<id>`、`nutrition-menu-search-empty`、`nutrition-menu-intro`、`retrieval-debug-mode-balanced`、`retrieval-debug-mode-keyword`、`retrieval-debug-mode-semantic`、`retrieval-debug-semantic-reason`、`ai-memory-usage`、`ai-memory-softcap-hint`、`ai-memory-hygiene`、`ai-memory-hygiene-sheet`、`ai-memory-hygiene-merge-<id>`、`ai-memory-hygiene-archive-<id>`、`ai-memory-hygiene-skip-<id>`、`ai-memory-pending`、`ai-memory-pending-sheet`、`ai-memory-pending-save-<n>`、`ai-memory-pending-ignore-<n>`、`ai-memory-pending-error-<n>`、`ai-memory-load-more`、`ai-memory-total`、`ai-chat-end-session`、`ai-memory-auto-extract-toggle`、`ai-memory-auto-extract-confirm`（2026-10-20 D2：结束会话自动提炼开关，默认关、开启前确认）

### D11 记餐搜索结果行必须可区分同名食物（2026-10-22，RV2-P1-01）

**规则**：`记录一餐 → 按食材记录` 的搜索结果行、以及拍照识餐的「本地食物更精确」选择行，
在食物**有品牌**时，副标题写成 `品牌 · N kcal / 100g`（无品牌时保持 `N kcal / 100g` 逐字不变）；
按钮语义标签写成 `添加 名称（品牌）`。

**为什么**：真实库 23,916 条里「米饭」有四条——116 kcal（无品牌）、156 kcal（叮咚）、
181 kcal（松屋）、338 kcal（千丰香米）。只印名称 + 热量时三行几乎一致，点错就把 338 记成 116
（静默记错营养，P1）。

**与 §3.11 的分界**：`FoodCard`（食物库列表）**仍不显示品牌**——那是**浏览**，docs/21 §3.11
的单行三件与「品牌退到详情」继续有效；本节只约束**选择动作**的行。
落点：`meal_editor_dialog.dart` 的 `_FoodResultRow`、`scan_candidate_editor.dart` 的本地食物 `ListTile`；
回归断言 `test/features/nutrition/nutrition_presentation_design_test.dart`（「同名食物（不同品牌）
在结果行里必须可区分」）。

### D12 AI 创作三张卡的答复形态（2026-10-22，RV2-P2-01 退役契约）

`解析学校菜单` / `分析菜品营养` / `训练计划` 三张卡仍走**结构化合同**（`menu-normalize.v1` 由
`menu.snapshot.publish` 解码、菜品营养走 `canteen.dish.nutrition`、训练计划走
`workout.plan.create`，均带 allow-list 与校验）。

`生成今日吃法`（`daily-menu-plan.v1`）、`这道菜怎么吃`（`dish-guidance.v1`）、
`常吃搭配`（`meal-pairing.v1`）三张卡**不再有自己的 decoder**：它们只把启动提示词发进对话，
写库统一由 chat-edit 命令层承担。`docs/03` §9/§14/§15 已加 as-built 退役横幅；
若要恢复结构化草案，须先补实现 + 断言（不得只改文档）。
