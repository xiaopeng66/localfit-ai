# 2026-11-06 全量审查与 2112 打包报告

## 结论

- S0/S1/P1 数据正确性与用户写入风险：**本轮修复并有回归证据**。
- 全量 fake tests：**+3240 ~1，全绿**；release tests **+18 全绿**；interaction-gate **+36 全绿**；analyze clean；format clean。
- 新三 ABI APK 已构建、生产签名与 v4111 一致、aapt2/apksigner/zipalign/资产检查通过。
- emulator-5554 上 x86_64 APK 安装成功并启动，versionCode=6112，无 FATAL/ANR/E/flutter；ARM 真机未验证。
- 本轮**未提交/未推送源码**；已按用户指令发布 GitHub Release **v4112**（三资产公开回读 SHA256 一致）。本包定位：个人自用三 ABI，不是 Play/公共商店发行。
- 应用内更新实测（emulator-5554）：v6111 → 检查更新显示 v4112 → 下载 40MB（5/44/95% 三帧）→ 系统安装器 → v6112 启动、数据保留；6112 再查显示「已是最新」。实帧见 `docs/evidence/2026-11-06-full-audit/frames/`。

## 修复摘要

1. 记录页整卡编辑按槽位传递记录，消除跨餐串改。
2. 训练回顾删除去掉 StatefulShellRoute 下的 branch 二次 pop。
3. MealItem scan 元数据 update/partial-delete/restore 保留；来源食物删除后 undo 保留快照。
4. venue 删除处理所有历史 snapshot/source；clear/meal delete/plan delete 处理 recognition/cardio 限制性 FK。
5. true v1 backup 缺 profiles/foods 后续字段补默认；餐食写入加 30 天窗口；canteen nutrition 做数值边界。
6. 菜单 publish 失败清理本次新建实体；executor 未知持久化异常变 row failure。
7. 下载进度补无障碍进度语义；自定义餐宏量单位填值后仍可见。
8. release base 2111→2112；三包版本码 3112/4112/6112；dist 与 LAN manifest 清理对齐。

## APK

| 包 | versionCode | ABI | SHA256 |
|---|---:|---|---|
| `dist/LocalFitAI-vc3112-arm32.apk` | 3112 | armeabi-v7a | `25b4478d06b59fd150a8a65f4ea20af2623a8f85a661fd5282dee1a0de599ffc` |
| `dist/LocalFitAI-vc4112-arm64.apk` | 4112 | arm64-v8a | `c35fa59cd1b07f24a8aa2fee7f253475c86fe30aa5a2d4ec75af8db705ed0192` |
| `dist/LocalFitAI-vc6112-x86_64.apk` | 6112 | x86_64 | `005b5baf119ac86c908c936daf86434a37cf9703ea2fcba8b3bacc17ba6e384b` |

签名证书 SHA-256：`87d0c6b06c997ff693ee0eda85aecf6740c5815c835d79832770c5637ca744c9`，与 v4111 arm64 历史包一致；三包均 v2 签名 true、zipalign 成功。

## 仍然未解决/未验证

- 仓储日期守卫的全域统一、self-check impossible date、target stream live invalidation、plannedExercise 归属、source-sync delete ghost、更多 320×2 弹层、debugPrint/privacy 漂移、update asset hash/host/size preflight、旧迁移半完成恢复、clean checkout ignored fixture、Gradle advisory/checksum。
- ARM32/ARM64 真机未验证；x86_64 仅自有 emulator-5554。
- 公共商店/Play 不可签收：bundled/derived food data 许可与 attribution UI、REQUEST_INSTALL_PACKAGES 政策、AAB/Play signing 均未完成。
- 工作区已有历史未提交改动；本轮不 reset、不 commit、不 push，发布前仍需人工 review 完整 diff。

证据总入口：`docs/evidence/2026-11-06-full-audit/run-log.md`；门禁日志与 APK 检查位于同目录及 `tmp/full-audit-2026-11-06/`。
