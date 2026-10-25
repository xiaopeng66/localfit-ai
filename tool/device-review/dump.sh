#!/usr/bin/env bash
# 抓取当前界面 dump 到 docs/evidence/2026-09-19-device-review/<name>.xml
# 用法：bash dump.sh <name>
# 注意：MSYS_NO_PATHCONV=1 下远端 /sdcard 与 Windows 形式的目标路径都要显式给全
set -u
export PATH=/e/AI/Codex/android-sdk/platform-tools:$PATH
export MSYS_NO_PATHCONV=1
NAME="$1"
WINDIR='E:/AI/Zcode/localfit-ai/docs/evidence/2026-09-19-device-review'
mkdir -p /e/AI/Zcode/localfit-ai/docs/evidence/2026-09-19-device-review
adb shell uiautomator dump /sdcard/dump.xml >/dev/null 2>&1
adb pull /sdcard/dump.xml "$WINDIR/$NAME.xml" 2>&1 | tail -1
if [ -f "/e/AI/Zcode/localfit-ai/docs/evidence/2026-09-19-device-review/$NAME.xml" ]; then
  echo "saved: $NAME.xml ($(wc -c < "/e/AI/Zcode/localfit-ai/docs/evidence/2026-09-19-device-review/$NAME.xml") bytes)"
else
  echo "FAILED to pull dump for $NAME"
  exit 1
fi
