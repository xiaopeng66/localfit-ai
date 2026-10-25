#!/usr/bin/env bash
# 走查辅助：dump 当前界面并列出可见文本/可点节点的边界（坐标用于 input tap）
# 用法：bash dumpui.sh <标签>
set -u
NAME="${1:-ui}"
ADB=/e/AI/Codex/android-sdk/platform-tools/adb.exe
export MSYS_NO_PATHCONV=1
export MSYS2_ARG_CONV_EXCL='*'
OUT="E:/AI/Zcode/tmp/p8b2-delivery-walk"

"$ADB" -s emulator-5556 shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1
"$ADB" -s emulator-5556 pull /sdcard/ui.xml "$OUT/$NAME.xml" >/dev/null 2>&1
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
