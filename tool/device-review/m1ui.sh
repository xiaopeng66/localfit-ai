#!/usr/bin/env bash
# 设备复验辅助（本轮）：固定 emulator-5554（自有 AVD LocalFit_API35）。
# 用法：bash tool/device-review/m1ui.sh dump <标签> | tap <x> <y> | text <ASCII>
set -u
export PATH=/e/AI/Codex/android-sdk/platform-tools:$PATH
export MSYS_NO_PATHCONV=1
export MSYS2_ARG_CONV_EXCL='*'
SERIAL=emulator-5554
OUT="E:/AI/Zcode/tmp/localfit-next/ui"
mkdir -p "$OUT"
case "${1:-dump}" in
  dump)
    NAME="${2:-ui}"
    adb -s $SERIAL shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1
    adb -s $SERIAL pull /sdcard/ui.xml "$OUT/$NAME.xml" >/dev/null 2>&1
    python - "$OUT/$NAME.xml" <<'PYEOF'
import sys, xml.etree.ElementTree as ET
root = ET.parse(sys.argv[1]).getroot()
def center(b):
    try:
        xs, ys = b.split('][')
        x0, y0 = map(int, xs.strip('[]').split(','))
        x1, y1 = map(int, ys.strip('[]').split(','))
        return (x0 + x1) // 2, (y0 + y1) // 2
    except Exception:
        return None
n = 0
for node in root.iter('node'):
    t = (node.get('text') or '').strip()
    d = (node.get('content-desc') or '').strip()
    if not (t or d):
        continue
    n += 1
    c = center(node.get('bounds', ''))
    click = node.get('clickable') == 'true'
    print(f"{'TAP' if click else '   '} {str(c):>16}  [{node.get('class','').split('.')[-1]}] {t or d!r}")
print(f'--- {n} labeled nodes ---')
PYEOF
    ;;
  tap)
    adb -s $SERIAL shell input tap "$2" "$3"
    ;;
  text)
    adb -s $SERIAL shell input text "$2"
    ;;
  shot)
    adb -s $SERIAL exec-out screencap -p > "E:/AI/Zcode/tmp/localfit-next/frames/$2.png"
    ;;
  swipe)
    adb -s $SERIAL shell input swipe "$2" "$3" "$4" "$5" "${6:-300}"
    ;;
esac
