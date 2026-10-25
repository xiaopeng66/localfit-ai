"""build_catalog.py：食物目录 ETL 的命令行入口。

    python build_catalog.py --input sources/openfoodfacts-products.jsonl.gz \
        --out ../../assets/catalog --catalog-version 2026.09 \
        --retrieved-at 2026-09-14T00:00:00Z [--limit 1000] [--shard-rows 20000] \
        [--max-canonical 100000]

`--max-canonical` 是发布分层上限（默认 100000，按上游流行度选取）；传 0 产出
不经截断的全量目录（约 170 万条、85 分片，只用于离线分析，不适合随包/按需分发）。
"""

from __future__ import annotations

import argparse
import sys

from etl_pipeline import RELEASE_CANONICAL_CAP, run_pipeline


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="LocalFit AI food catalog ETL")
    parser.add_argument("--input", required=True, help="Open Food Facts jsonl(.gz) path")
    parser.add_argument("--out", required=True, help="output directory for shards + manifest")
    parser.add_argument("--catalog-version", required=True)
    parser.add_argument("--retrieved-at", required=True, help="ISO-8601 instant of source retrieval")
    parser.add_argument("--source-version", default="", help="upstream snapshot identifier")
    parser.add_argument("--shard-rows", type=int, default=20000)
    parser.add_argument("--limit", type=int, default=None, help="cap raw records (testing)")
    parser.add_argument(
        "--max-canonical",
        type=int,
        default=RELEASE_CANONICAL_CAP,
        help="发布目录条目上限，按上游流行度选取；0 = 不截断（全量）",
    )
    args = parser.parse_args(argv)

    manifest = run_pipeline(
        input_path=args.input,
        out_dir=args.out,
        catalog_version=args.catalog_version,
        retrieved_at=args.retrieved_at,
        shard_rows=args.shard_rows,
        limit=args.limit,
        source_version=args.source_version,
        max_canonical=args.max_canonical,
    )
    print(f"catalog_version={manifest['catalog_version']}")
    print(f"shards={len(manifest['shards'])}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
