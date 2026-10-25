#!/usr/bin/env bash
# docs/11 §4 设备走查专用构建（O-2：命令固化，防止再出混淆包）。
#
# 走查包**绝不能加 --obfuscate**：混淆后上屏的异常类型名只剩两三个字符
# （2026-09-19 走查实录：用户读到的是「意外错误（oL）」），设备走查要看的
# 正是这些失败文案。产物在 build/app/outputs/flutter-apk/ 下。
#
# 用法：bash tool/device-review/build-walkthrough-apk.sh
set -euo pipefail

FLUTTER="${FLUTTER:-E:/AI/toolchains/flutter/bin/flutter.bat}"

cd "$(dirname "$0")/../.."

# x64 模拟器用 android-x64；真机走查把 target-platform 换成
# android-arm64（同样不许 --obfuscate）。
"$FLUTTER" build apk --release --split-per-abi --target-platform android-x64

echo
echo '--- 走查包已就绪（未混淆）---'
ls -la build/app/outputs/flutter-apk/*x64*.apk 2>/dev/null || true
