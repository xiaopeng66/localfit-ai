#!/usr/bin/env bash
# BUG-17/18 设备复验（终版）：-wipe-data 重置 AVD 用户数据 → 装 APK → 走完引导
# → 从宿主机 assets/catalog/ 推入 001–004 → 填盘到只剩 ~40MB → 重启触发导入
# → 读「我的」页卡片，期望「设备剩余空间不足…」而不是类型名。
#
# 为什么要 -wipe-data：这套 userdata 镜像被反复填满/清空过，qemu 连续 6 次在
# 「写库那一刻」段错误退出（exit 139）；换 -gpu off / -no-window 一样，而同一
# 宿主机上别的 AVD 跑得住 —— 指向 userdata 镜像状态而不是 GPU/内存。
#
# 分片来源：仓库自带的 assets/catalog/foods-core-00{1..4}.sqlite（与 manifest
# 里的 sha256 一致），所以重置镜像后仍能造出「增量导入 4 个分片」的场景。
set -u
export MSYS_NO_PATHCONV=1
export PATH=/e/AI/Codex/android-sdk/platform-tools:$PATH
REPO=/e/AI/Zcode/localfit-ai
EVID="$REPO/docs/evidence/2026-09-19-device-review"
EVIDW='E:/AI/Zcode/localfit-ai/docs/evidence/2026-09-19-device-review'
ASSETS='E:/AI/Zcode/localfit-ai/assets/catalog'
PKG=com.localfit.ai
ACT=$PKG/com.localfit.localfit_ai.MainActivity
WINAPK='E:/AI/Zcode/localfit-ai/build/app/outputs/flutter-apk/app-x86_64-release.apk'

step() { echo; echo "=== $* ==="; }
free_mb() { adb shell "df -k /data | tail -1" | awk '{print int($4/1024)}'; }
db_size() { adb shell "stat -c %s /data/data/$PKG/files/localfit.sqlite 2>/dev/null" | tr -d '\r'; }
dumpq() { bash $REPO/tool/device-review/dump.sh "$1" >/dev/null 2>&1; }

start_emu() {
  cd /e/AI/Codex/android-sdk/emulator
  ./emulator.exe -avd LocalFit_API35 -no-snapshot -no-boot-anim -gpu swiftshader_indirect "$@" > /tmp/emu-v3.log 2>&1 &
  EMU=$!
  for i in $(seq 1 90); do
    [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ] && break
    sleep 4
  done
  echo "  boot=$i avd=$(adb shell getprop ro.boot.qemu.avd_name | tr -d '\r')"
  adb root >/dev/null 2>&1; sleep 4
}
stop_emu() { kill $EMU 2>/dev/null; adb emu kill >/dev/null 2>&1; sleep 6; }

step "1. -wipe-data 重置 AVD 用户数据"
start_emu -wipe-data
echo "  free=$(free_mb)MB"

step "2. 装 APK + 首装导入（只随包 core-000）"
adb shell ime disable com.google.android.inputmethod.latin/com.android.inputmethod.latin.LatinIME >/dev/null 2>&1
adb install -r "$WINAPK" 2>&1 | tail -1
adb shell am start -n $ACT >/dev/null 2>&1
for _ in $(seq 1 30); do
  s=$(db_size); [ -n "$s" ] && [ "$s" -gt 10000000 ] 2>/dev/null && break
  sleep 4
done
sleep 12
echo "  db=$(db_size) free=$(free_mb)MB"

step "3. 走完引导"
adb shell input swipe 540 700 540 2000 300; sleep 3
dumpq ui-95-onb
PY=/c/ProgramData/miniconda3/python.exe
i=0
for v in 30 175 70; do
  c=$($PY -c "
import re,sys
t=open(r'$EVIDW/ui-95-onb.xml',encoding='utf-8').read()
hits=[x for x in re.findall(r'<node[^>]*>',t) if 'EditText' in x]
b=re.search(r'bounds=\"\[(\d+),(\d+)\]\[(\d+),(\d+)\]\"',hits[int(sys.argv[1])])
x1,y1,x2,y2=map(int,b.groups()); print((x1+x2)//2,(y1+y2)//2)
" "$i")
  echo "  [fill#$i] @ $c = $v"
  adb shell input tap $c; sleep 2; adb shell input text "$v"; sleep 1
  i=$((i+1))
done
adb shell input tap 449 1034; sleep 1
adb shell input swipe 540 1900 540 500 400; sleep 3
adb shell input tap 540 2120; sleep 7
adb shell input tap 881 2263; sleep 14
dumpq ui-95-in-app
grep -q 'content-desc="建立本地档案"' "$EVID/ui-95-in-app.xml" \
  && echo "  !! 仍在引导页" || echo "  OK 已进主界面"
echo "  db=$(db_size)"

step "4. 推入 001–004 分片（取自仓库 assets/catalog）"
adb shell "mkdir -p /data/local/tmp/seed"
for n in 001 002 003 004; do
  adb push "$ASSETS/foods-core-$n.sqlite" /data/local/tmp/seed/ >/dev/null 2>&1
done
adb shell "cp /data/local/tmp/seed/*.sqlite /data/data/$PKG/files/catalog/; chown u0_a213:u0_a213 /data/data/$PKG/files/catalog/*; rm -rf /data/local/tmp/seed"
adb shell "ls -l /data/data/$PKG/files/catalog/"

step "5. 填盘到只剩 ~40MB"
t=$(( $(free_mb) - 40 ))
[ "$t" -gt 0 ] && adb shell "mkdir -p /data/local/tmp/fill; dd if=/dev/zero of=/data/local/tmp/fill/big bs=1M count=$t 2>&1 | tail -1"
echo "  free=$(free_mb)MB"

step "6. 重启 → 导入 001–004 → 撞满盘"
adb shell am force-stop $PKG; sleep 2
adb logcat -c
adb shell am start -n $ACT >/dev/null 2>&1
sleep 55
echo "  db=$(db_size)（导入前 14184448）free=$(free_mb)MB"
PID=$(adb shell pidof $PKG | tr -d '\r')
adb logcat -d 2>/dev/null | grep -E "^\S+ \S+ +$PID " | grep -iE "sqlite|disk|space|full" | head -5

step "7. 读「我的」页卡片（期望「设备剩余空间不足…」）"
adb shell input tap 945 2142; sleep 5
for _ in 1 2 3 4; do
  dumpq ui-95-card
  grep -q 'content-desc="食物目录' "$EVID/ui-95-card.xml" && break
  adb shell input swipe 540 1800 540 700 400; sleep 2
done
grep -o 'content-desc="食物目录[^"]*"' "$EVID/ui-95-card.xml" | head -3

step "收工"
stop_emu
echo done
