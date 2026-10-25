#!/usr/bin/env bash
# 设备走查辅助：统一 adb 调用，规避 Git Bash 的 MSYS 路径转换
# 用法：bash adbx.sh <adb 参数...>
export PATH=/e/AI/Codex/android-sdk/platform-tools:$PATH
export MSYS_NO_PATHCONV=1
export MSYS2_ARG_CONV_EXCL='*'
exec adb "$@"
