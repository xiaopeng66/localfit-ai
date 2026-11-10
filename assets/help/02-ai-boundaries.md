## AI 会直接改我的数据吗？

不会。AI 只生成草稿，草稿要先给你看清「发送了什么」，结果回来后还要你逐条确认，
确认过才写入本地事实。

## AI 没配置好会怎样？

需要 AI 的功能会如实说「未配置」并给出入口；本地功能（记录、搜索、统计、备份）
不受影响，照常可用。

## AI 服务地址怎么填？

先选协议，再填该协议对应的 Base URL：

- Chat Completions：请求路径为 `/chat/completions`
- Responses：请求路径为 `/responses`
- Anthropic Messages：请求路径为 `/messages`

把完整端点粘进 Base URL 也可以，末尾的协议路径会自动去掉。
「推理」选「关闭推理」时会附加 thinking 字段；如果供应商拒绝该字段，
把「推理」切回「默认」。
