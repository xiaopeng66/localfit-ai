# 2026-11-06 全量审查与新版本计划

模式：`audit→fix→re-audit` + `release-gate`；范围：LocalFit Android 私用/现有三 ABI 分发。

## 基线

- pubspec：`0.1.0+2111`；schema：30；目标新包基础号：2112。
- 现有门禁：`flutter test --no-pub --exclude-tags capture --concurrency=2 test/app test/features` → **+3234 ~1，全绿，exit 0**。
- 全量门禁日志：`docs/evidence/2026-11-06-full-audit/gate-logs/00-baseline.log`。
- 工作区已存在大量历史未提交改动（包括 Android/iOS 资源、STATUS、docs、catalog/AI 等）；本轮不重置、不覆盖，发布前必须复核 diff。
- 已有 v4111 产物是旧源码构建；本轮不把它当新源码验证。

## 本轮约束

- schema 仍 30；不加第三方依赖；不改 AI wire 信封。
- 只动自有 AVD `LocalFit_API35` / emulator-5554；不触碰 5558/5566。
- 真实 AI 无凭据记录 `ai-live: not run`；不入库、不上传。
- 不提交、不推送、不发布 GitHub；只打包并留证据。

## 交付

1. S0/S1/P1 修复与先红后绿证据。
2. `FINDINGS.md` / `COVERAGE.md` / `FIX-PLAN.md` / `REPORT.md`。
3. 新基础号 2112 的 arm32/arm64/x86_64 APK（若生产签名材料可确认；否则明确 BLOCKED）。
4. APK 级检查、x86_64 AVD 安装/升级证据；ARM 真机未验证如实登记。
