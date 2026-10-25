#!/usr/bin/env bash
# 设备造数（本轮复验用）：新建档案 → 一个食堂菜 → 手动营养 → 加入菜品库。
# 只操作自有 AVD emulator-5554；全部坐标在运行中从 uiautomator dump 现取。
set -u
export PATH=/e/AI/Codex/android-sdk/platform-tools:$PATH
export MSYS_NO_PATHCONV=1
export MSYS2_ARG_CONV_EXCL='*'
SERIAL=emulator-5554
OUT="E:/AI/Zcode/tmp/localfit-next/ui"
mkdir -p "$OUT"

dump() { # dump <name> -> prints "x y text" for EditText, then all labeled nodes
  adb -s $SERIAL shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1
  adb -s $SERIAL pull /sdcard/ui.xml "$OUT/$1.xml" >/dev/null 2>&1
  python - "$OUT/$1.xml" <<'PY'
import sys, xml.etree.ElementTree as ET
root=ET.parse(sys.argv[1]).getroot()
def center(b):
    xs,ys=b.split('][')
    x0,y0=map(int,xs.strip('[]').split(',')); x1,y1=map(int,ys.strip('[]').split(','))
    return (x0+x1)//2,(y0+y1)//2
n=0
for node in root.iter('node'):
    t=(node.get('text') or '').strip(); d=(node.get('content-desc') or '').strip()
    cls=node.get('class','').split('.')[-1]
    if cls=='EditText': print(f'EDIT {center(node.get("bounds"))} {t!r}')
    if not (t or d): continue
    n+=1
    print(f"{'TAP' if node.get('clickable')=='true' else '   '} {center(node.get('bounds'))} [{cls}] {(t or d)!r}")
print(f'--- {n} labeled nodes ---')
PY
}

tap() { local x="$1" y="$2" d="${3:-1}"; adb -s $SERIAL shell input tap "$x" "$y"; sleep "$d"; }
text() { adb -s $SERIAL shell am broadcast -a ADB_INPUT_TEXT --es msg "$1" >/dev/null 2>&1; sleep 1; }
hidekb() { adb -s $SERIAL shell input keyevent 4; sleep 1; }

# 从 dump 里取第 N 个 EditText 的坐标
edit_coord() { # edit_coord <xml> <index>
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

fill_edit() { # fill_edit <xml> <index> <value>
  local value="$3"; local xy; xy=$(edit_coord "$1" "$2")
  if [ -z "$xy" ]; then echo "MISS EDIT $2 in $1"; return 1; fi
  set -- $xy
  adb -s $SERIAL shell input tap "$1" "$2"; sleep 1
  adb -s $SERIAL shell input keyevent 123  # move to end
  for _ in 1 2 3 4 5 6; do adb -s $SERIAL shell input keyevent 67; done
  text "$value"
}

# 坐标从 dump 文本里按 label 找（"TAP (x, y) [Button] '文本'"）
coord_of() { # coord_of <xml> <substring>
  python - "$OUT/$1.xml" "$2" <<'PY'
import sys, xml.etree.ElementTree as ET
root=ET.parse(sys.argv[1]).getroot(); needle=sys.argv[2]
def center(b):
    xs,ys=b.split(']['); x0,y0=map(int,xs.strip('[]').split(',')); x1,y1=map(int,ys.strip('[]').split(','))
    return (x0+x1)//2,(y0+y1)//2
for node in root.iter('node'):
    t=(node.get('text') or '').strip(); d=(node.get('content-desc') or '').strip()
    if needle in (t or d):
        print(*center(node.get('bounds'))); break
PY
}

tap_label() { local xy; xy=$(coord_of "$1" "$2"); [ -z "$xy" ] && { echo "MISS $2"; return 1; }; set -- $xy "${3:-2}"; tap "$1" "$2" "$3"; }

echo "== 启动 =="
adb -s $SERIAL shell am start -n com.localfit.ai/com.localfit.localfit_ai.MainActivity >/dev/null 2>&1
sleep 10

echo "== 建档 =="
dump s1
fill_edit s1 0 28
fill_edit s1 1 175
fill_edit s1 2 72
hidekb
tap_label s1 男性 1
tap_label s1 计算并确认目标 4
dump s2
tap_label s2 确认保存 5
sleep 3

echo "== 菜单页 =="
tap 332 2254 3
tap 540 131 3
dump m1
tap_label m1 管理食堂目录 4
tap_label m1 添加地点 3
dump v1
fill_edit v1 0 第三食堂
fill_edit v1 1 校本部
hidekb
tap_label v1 保存 4
dump v2
tap_label v2 添加窗口 3
dump w1
fill_edit w1 0 一楼快餐
hidekb
tap_label w1 保存 5
dump w2
tap_label w2 添加菜品 3
dump d1
fill_edit d1 0 番茄牛腩饭
hidekb
tap_label d1 保存 4
dump d2
echo "== 当前界面 =="
cat "$OUT/d2.xml" | python -c "import sys,xml.etree.ElementTree as ET;r=ET.parse(sys.stdin).getroot();print(' | '.join([(n.get('text') or n.get('content-desc') or '').replace(chr(10),'/') for n in r.iter('node') if (n.get('text') or n.get('content-desc'))]))"
