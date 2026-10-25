# LocalFit AI 2.0

本地优先、AI 辅助、以校园就餐决策为核心的饮食与健身管理 App。

## 新会话首读顺序

```text
STATUS.md
→ GOAL.md
→ docs/07-localfit-2.0-development-spec.md 的相关章节
→ STATUS Active Slice 指定的源码和测试
→ docs/DECISIONS.md / docs/evidence/ 中的链接
→ STATUS.md 的 Next Command
```

不要把聊天记忆、旧路线图、README 状态段落或历史测试数字当作当前进度。当前状态唯一看 [`STATUS.md`](STATUS.md)。

## 当前活动文档

1. [`STATUS.md`](STATUS.md)：当前切片、验证证据、风险、交接和下一条命令。
2. [`GOAL.md`](GOAL.md)：2.0 长期目标、硬约束、路线和总验收。
3. [`docs/01-product.md`](docs/01-product.md)：2.0 产品范围与用户流程。
4. [`docs/02-architecture.md`](docs/02-architecture.md)：2.0 技术架构、AI、存储和隐私。
5. [`docs/03-data-and-contracts.md`](docs/03-data-and-contracts.md)：2.0 数据模型和结构化合同。
6. [`docs/04-roadmap.md`](docs/04-roadmap.md)：2.0 阶段路线和退出条件。
7. [`docs/05-quality-and-release.md`](docs/05-quality-and-release.md)：2.0 质量与发布门槛。
8. [`docs/06-token-efficient-development.md`](docs/06-token-efficient-development.md)：持续开发与中断续接协议。
9. [`docs/21-ui-redesign-spec.md`](docs/21-ui-redesign-spec.md)：**UI 唯一依据**——按 `ui设计/pages/*.html` 制定的视觉与交互规范（token、组件、逐页规范、数据契约、测试策略）。
10. [`docs/22-ui-redesign-refactor-plan.md`](docs/22-ui-redesign-refactor-plan.md)：UI 重设计改造方案——现状评估、策略、阶段编排与风险。
11. [`docs/23-chat-universal-edit.md`](docs/23-chat-universal-edit.md)：**AI 对话通用编辑**——chat-edit.v1 信封契约、23 条命令注册表、可编辑数据快照、执行器与「用户点应用才写库」硬门。
12. [`docs/24-ai-provider-protocols.md`](docs/24-ai-provider-protocols.md)：**AI 供应商协议三选一**（Chat Completions / Responses / Anthropic Messages）——协议身份与 v18 迁移、wire 表、端点尾巴剥离、统一错误口径、转写协议门与红证清单。
13. [`docs/07-localfit-2.0-development-spec.md`](docs/07-localfit-2.0-development-spec.md)：2.0 综合产品、数据、AI、菜单、食物库、UI 和验收契约。
14. [`docs/08-store-privacy-and-permissions.md`](docs/08-store-privacy-and-permissions.md)：商店隐私说明、权限说明与实际网络/存储/日志行为的对照草稿。
15. [`docs/THIRD_PARTY_LICENSES.md`](docs/THIRD_PARTY_LICENSES.md)：随包与按需下载的食物数据来源、许可证和发布前待办。
14. [`docs/09-release-and-device-checklist.md`](docs/09-release-and-device-checklist.md)：真机/签名包/iOS/商店材料的可执行验收清单。
15. [`docs/DECISIONS.md`](docs/DECISIONS.md)：追加式架构与产品决策。
16. [`docs/evidence/`](docs/evidence/)：实际重新运行的验证记录。
17. [`docs/history/1.x/`](docs/history/1.x/)：1.x 历史归档，非当前状态，**其 UI 描述同样已作废**。

## 2.0 当前方向

- 统一现有 AI Provider 为 `AiTransport`，冻结 `meal-estimate.v1`、`workout-plan.v1`（2026-10-04：`recipe-plan.v1` 随食谱/周计划整族删除，见 `docs/28` §6）。
- 建立 `menu-normalize.v1` 和 `daily-menu-plan.v1`，让 AI 只生成可解析、可编辑、可校验的草案。
- 食物库已随包 **49,464 条中文食物**（FoodCalu 派生，`assets/seed/foods.v4.json`，2026-10-02 整体替换旧种子与随包分片，见 ADR-025）；离线 ETL、manifest、许可证、分片 SQLite 与 FTS5 机制保留给按需导入的许可数据（当前是 Open Food Facts / ODbL）。
- 增加学校、食堂、窗口、营业时间、日期菜单、营养证据和本地食物匹配。
- 用本地确定性 solver 生成“去哪里、吃什么、吃多少”的可解释候选，AI 只辅助创作和解释。
- **按 `ui设计/pages/*.html` 重建 UI**（唯一视觉依据，规范见 `docs/21`、方案见 `docs/22`）：底栏 5 槽（中间为 AI 对话凸起圆）、今日页为圆环+宏量+体重折线+三趋势格+计划态时间线、饮食页三 chip（记录 / 菜单 / 食物库；2026-10-04 起 `计划`、`食谱` 两个 chip 随整族删除，见 `docs/28` §6）、菜单页菜品卡、训练页暗色 hero 与心血管处方、我的页身份卡与成就网格、AI 对话页六种消息形态与语音输入；设计稿未画到的功能保留数据与逻辑、收进二级入口。

## 固定边界

- 无账号、无开发者业务后端、无云端用户库、无广告、无社区、无自动下单。
- 数据默认存本地加密 SQLite/应用私有文件；API Key 只存 Keychain/Keystore。
- AI、菜单 URL 和路线查询必须由用户主动触发并先披露发送范围。
- AI 永远只产生结构化草案；营养、过敏、价格、库存、营业时间和路线由本地事实或明确来源裁决。
- “加入计划”和“记录为已吃”严格分离；推荐不能直接创建 consumed meal。
- 不后台定位、不绕过登录/验证码、不把学校、菜单、精确位置和健康资料写入普通日志。

## 验证命令

统一验证：

```bat
cmd.exe //d //c "E:\AI\Zcode\localfit-ai\tool\verify.bat"
```

Android Debug 构建：

```bat
E:\AI\toolchains\flutter\bin\flutter.bat build apk --debug
```

实际运行结果必须写入 `STATUS.md` 和 `docs/evidence/`，不能用历史记录代替。
