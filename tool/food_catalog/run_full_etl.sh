#!/usr/bin/env bash
# 等 OFF 全量下载完成 → 完整性校验 → 全量 ETL 出分片 + manifest。
# 后台运行，日志 /tmp/etl_full.log。仅在本机执行，不发布任何东西。
set -u

ROOT=/e/AI/Zcode/localfit-ai
cd "$ROOT/tool/food_catalog" || exit 1
SRC=sources/openfoodfacts-products.jsonl.gz
TOTAL=7683519547
LOG=/tmp/etl_full.log
PY=C:/ProgramData/miniconda3/python.exe

echo "[$(date +%F' '%T)] wait for download to reach $TOTAL bytes" >> "$LOG"

# 最长等 8 小时；每 2 分钟探一次。
for i in $(seq 1 240); do
  sz=$(stat -c %s "$SRC" 2>/dev/null || echo 0)
  echo "[$(date +%F' '%T)] size=$sz" >> "$LOG"
  if [ "$sz" -ge "$TOTAL" ]; then
    echo "[$(date +%F' '%T)] download complete" >> "$LOG"
    break
  fi
  sleep 120
done

sz=$(stat -c %s "$SRC" 2>/dev/null || echo 0)
if [ "$sz" -lt "$TOTAL" ]; then
  echo "[$(date +%F' '%T)] ABORT: still $sz < $TOTAL after wait window" >> "$LOG"
  exit 2
fi

echo "[$(date +%F' '%T)] gzip integrity check (stream read)" >> "$LOG"
"$PY" - "sources/openfoodfacts-products.jsonl.gz" <<'PY' >> "$LOG" 2>&1
import gzip, sys
n = 0
with gzip.open(sys.argv[1], 'rb') as f:
    while True:
        b = f.read(1 << 24)
        if not b:
            break
        n += len(b)
print('decompressed_bytes', n)
PY
if [ $? -ne 0 ]; then
  echo "[$(date +%F' '%T)] ABORT: gzip integrity failed" >> "$LOG"
  exit 3
fi

echo "[$(date +%F' '%T)] full ETL start" >> "$LOG"
"$PY" build_catalog.py \
  --input "$SRC" \
  --out ../../assets/catalog \
  --catalog-version 2026.09 \
  --retrieved-at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --source-version huggingface:openfoodfacts/openfoodfacts-jsonl-export \
  >> "$LOG" 2>&1
rc=$?
echo "[$(date +%F' '%T)] full ETL exit=$rc" >> "$LOG"
exit $rc
