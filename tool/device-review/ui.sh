#!/usr/bin/env bash
# 列出 dump xml 里的可见文本与关键节点，便于在终端核对界面
# 用法：bash ui.sh <name>   （对应 docs/evidence/2026-09-19-device-review/<name>.xml）
set -u
NAME="$1"
PY=/c/ProgramData/miniconda3/python.exe
export MSYS_NO_PATHCONV=1
WINXML="E:/AI/Zcode/localfit-ai/docs/evidence/2026-09-19-device-review/$NAME.xml"
"$PY" - "$WINXML" <<'PYEOF'
import sys, xml.etree.ElementTree as ET
p = sys.argv[1]
try:
    root = ET.parse(p).getroot()
except Exception as e:
    print("PARSE ERROR", e); sys.exit(1)
n = 0
for node in root.iter('node'):
    t = (node.get('text') or '').strip()
    d = (node.get('content-desc') or '').strip()
    cls = node.get('class','')
    rid = node.get('resource-id','')
    if t or d:
        n += 1
        b = node.get('bounds','')
        print(f"[{cls.split('.')[-1]}] text={t!r} desc={d!r} id={rid.split('/')[-1]!r} {b}")
print(f"--- {n} labeled nodes ---")
PYEOF
