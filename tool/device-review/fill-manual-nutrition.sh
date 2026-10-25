#!/usr/bin/env bash
# 手动营养弹层：每次填写前重新 dump（键盘会把弹层顶上去），填完保存。
# 用法：bash fill-manual-nutrition.sh <kcal> <protein> <carbs> <fat>
set -u
export PATH=/e/AI/Codex/android-sdk/platform-tools:$PATH
export MSYS_NO_PATHCONV=1
export MSYS2_ARG_CONV_EXCL='*'
SERIAL=emulator-5554
OUT="E:/AI/Zcode/tmp/localfit-next/ui"
mkdir -p "$OUT"
VALS=("$1" "$2" "$3" "$4")

coord() { # coord <dumpname> <index>
  adb -s $SERIAL shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1
  adb -s $SERIAL pull /sdcard/ui.xml "$OUT/$1.xml" >/dev/null 2>&1
  python - "$OUT/$1.xml" "$2" <<'PY'
import sys, xml.etree.ElementTree as ET
root=ET.parse(sys.argv[1]).getroot(); idx=int(sys.argv[2]); i=0
for node in root.iter('node'):
    if node.get('class','').endswith('EditText'):
        if i==idx:
            b=node.get('bounds'); xs,ys=b.split(']['); x0,y0=map(int,xs.strip('[]').split(',')); x1,y1=map(int,ys.strip('[]').split(','))
            print((x0+x1)//2,(y0+y1)//2); break
        i+=1
PY
}

for i in 0 1 2 3; do
  xy=$(coord "mn$i" "$i")
  [ -z "$xy" ] && { echo "MISS field $i"; exit 1; }
  set -- $xy
  adb -s $SERIAL shell input tap "$1" "$2"; sleep 1
  adb -s $SERIAL shell input keyevent 123
  for _ in 1 2 3 4 5 6; do adb -s $SERIAL shell input keyevent 67; done
  adb -s $SERIAL shell input text "${VALS[$i]}"; sleep 1
  echo "field $i <- ${VALS[$i]}"
done

# 收起键盘后按钮位置会回到底部，重新取「保存」的坐标。
adb -s $SERIAL shell input keyevent 4; sleep 1
xy=$(coord final_save 9) # 9 = 不存在的 index，仅为了 dump
python - "$OUT/final_save.xml" <<'PY'
import xml.etree.ElementTree as ET
root=ET.parse(__import__('sys').argv[1]).getroot()
for node in root.iter('node'):
    t=(node.get('text') or '').strip()
    if '保存（标为用户输入）' in t:
        b=node.get('bounds'); xs,ys=b.split(']['); x0,y0=map(int,xs.strip('[]').split(',')); x1,y1=map(int,ys.strip('[]').split(','))
        print((x0+x1)//2,(y0+y1)//2); break
PY
