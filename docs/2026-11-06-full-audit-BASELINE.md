# 2026-11-06 全量审查基线

| 项 | 结果 |
|---|---|
| pubspec build | 2111 |
| schema | 30 |
| 现有全量 fake gate | +3234 ~1，全绿，exit 0 |
| capture / interaction gate | 未纳入 baseline（后续单独跑） |
| ai-live | not run（无凭据） |
| ARM32/ARM64 真机 | unverified；只允许自有 x86_64 AVD 5554 |
| 生产签名 | 待构建前检查 `android/key.properties` 与 v4111 证书一致性 |
| 公共商店/Play 合规 | out-of-scope；bundled/derived food data 许可与 attribution 尚未满足 |
| Git 工作区 | dirty；既有历史改动，不做 reset |

基线日志：`docs/evidence/2026-11-06-full-audit/gate-logs/00-baseline.log`。
