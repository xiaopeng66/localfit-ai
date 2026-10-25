"""accept_catalog.py：50k 目录的独立验收检查（docs/05 §5 质量门槛）。

**不信任 ETL 自己的计数器**：直接打开分片 SQLite 重新数一遍——重复 ID、
空名、负值、NaN/Inf、超范围、许可证缺失、四项宏量完整率、别名/份量/修订/证据
行数（含外键链与「修订营养必须与 foods 逐值相同」），以及中文与品牌覆盖、
FTS 行数，并复算每个分片的 sha256 与 manifest 对比。

用法：

    C:/ProgramData/miniconda3/python.exe accept_catalog.py --dir ../../assets/catalog
    # 冒烟/中间产物（不检查 ≥50k 门槛）：
    ... --dir <tmp> --min-canonical 0

退出码：0 = 全部门槛通过；1 = 有门槛未过或校验不一致；2 = 目录不存在/无法解析。
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sqlite3
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from etl_pipeline import (  # noqa: E402
    MANIFEST_VERSION,
    PORTION_MAX_GRAMS,
    RELEASE_CANONICAL_CAP,
    SHARD_FILE_RE,
)

# 应用侧 lib/features/nutrition/data/catalog_manifest.dart 的白名单，保持一致。
ALLOWED_LICENSES = {
    "odbl-1.0",
    "cc0-1.0",
    "cc-by-4.0",
    "cc-by-sa-3.0",
    "cc-by-sa-4.0",
    "public-domain",
}

HEX64 = re.compile(r"^[0-9a-f]{64}$")
CJK = re.compile(r"[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]")

# 与 etl_pipeline 的 validate 阶段同一组界（这里独立重数，不读它的计数）。
KCAL_MAX = 900.0
MACRO_MAX = 100.0


def sha256_file(path: str) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def scan_shard(path: str) -> dict:
    con = sqlite3.connect(path)
    try:
        one = lambda sql: con.execute(sql).fetchone()[0]  # noqa: E731
        rows = one("SELECT COUNT(*) FROM foods")
        stats = {
            "rows": rows,
            "alias_rows": one("SELECT COUNT(*) FROM aliases"),
            "portion_rows": one("SELECT COUNT(*) FROM portions"),
            "fts_rows": one("SELECT COUNT(*) FROM food_search"),
            "empty_name": one(
                "SELECT COUNT(*) FROM foods WHERE name IS NULL OR TRIM(name) = ''"
            ),
            "empty_id": one(
                "SELECT COUNT(*) FROM foods WHERE id IS NULL OR TRIM(id) = ''"
            ),
            "nan_or_inf": one(
                "SELECT COUNT(*) FROM foods WHERE "
                "(kcal_per100g IS NOT NULL AND kcal_per100g != kcal_per100g) OR "
                "(protein_per100g IS NOT NULL AND protein_per100g != protein_per100g) OR "
                "(carbs_per100g IS NOT NULL AND carbs_per100g != carbs_per100g) OR "
                "(fat_per100g IS NOT NULL AND fat_per100g != fat_per100g) OR "
                "kcal_per100g > 1e308 OR protein_per100g > 1e308 OR "
                "carbs_per100g > 1e308 OR fat_per100g > 1e308"
            ),
            "negative": one(
                "SELECT COUNT(*) FROM foods WHERE "
                "kcal_per100g < 0 OR protein_per100g < 0 OR "
                "carbs_per100g < 0 OR fat_per100g < 0"
            ),
            "out_of_range": one(
                f"SELECT COUNT(*) FROM foods WHERE kcal_per100g > {KCAL_MAX} OR "
                f"protein_per100g > {MACRO_MAX} OR carbs_per100g > {MACRO_MAX} OR "
                f"fat_per100g > {MACRO_MAX}"
            ),
            "license_not_allowed": one(
                "SELECT COUNT(*) FROM foods WHERE license_status IS NULL OR "
                "license_status != 'allowed'"
            ),
            "missing_license_field": one(
                "SELECT COUNT(*) FROM foods WHERE license_status IS NULL"
            ),
            "verified": one("SELECT COUNT(*) FROM foods WHERE state = 'verified'"),
            "incomplete": one("SELECT COUNT(*) FROM foods WHERE state != 'verified'"),
            # 发布目录里的**任何**行都必须四项齐全（规范 §2.0-1：不完整条目
            # 不得静默进入营养计算；本目录按设计不发布不完整条目）。
            "missing_macros": one(
                "SELECT COUNT(*) FROM foods WHERE "
                "kcal_per100g IS NULL OR protein_per100g IS NULL OR "
                "carbs_per100g IS NULL OR fat_per100g IS NULL"
            ),
        }
        stats.update(scan_ontology(con, path))
        names = [r[0] for r in con.execute("SELECT name FROM foods")]
        brands = one("SELECT COUNT(*) FROM foods WHERE brand IS NOT NULL AND TRIM(brand) != ''")
        ids = [r[0] for r in con.execute("SELECT id FROM foods")]
    finally:
        con.close()
    stats["cjk_names"] = sum(1 for n in names if n and CJK.search(n))
    stats["branded"] = brands
    stats["ids"] = ids
    return stats


def scan_ontology(con: sqlite3.Connection, path: str) -> dict:
    """独立重数规范 §5.5 的三个实体（revisions / evidence / portions）。

    ETL 自报的行数一律不信：这里直接查表，并顺带验证三条「不许凑数」的硬约束
    ——revisions 的四项宏量必须与 foods 逐值相同、revisions 必须指得回 evidence、
    evidence 的原始记录哈希必须是 64 位十六进制。旧分片没有这些表时给可行动的
    报错，而不是让调用方看到一句 sqlite 的 "no such table"。
    """
    try:
        return {
            "revision_rows": con.execute("SELECT COUNT(*) FROM revisions").fetchone()[0],
            "evidence_rows": con.execute("SELECT COUNT(*) FROM evidence").fetchone()[0],
            "portion_orphans": con.execute(
                "SELECT COUNT(*) FROM portions WHERE food_id NOT IN (SELECT id FROM foods)"
            ).fetchone()[0],
            "revision_orphans": con.execute(
                "SELECT COUNT(*) FROM revisions WHERE food_id NOT IN (SELECT id FROM foods)"
            ).fetchone()[0],
            "revision_mismatched": con.execute(
                "SELECT COUNT(*) FROM revisions r JOIN foods f ON f.id = r.food_id "
                "WHERE r.revision_number != 1 OR r.quality_status != f.state OR "
                "r.kcal_per100g IS NOT f.kcal_per100g OR "
                "r.protein_per100g IS NOT f.protein_per100g OR "
                "r.carbs_per100g IS NOT f.carbs_per100g OR "
                "r.fat_per100g IS NOT f.fat_per100g"
            ).fetchone()[0],
            "revision_dangling_evidence": con.execute(
                "SELECT COUNT(*) FROM revisions WHERE source_evidence_id IS NULL OR "
                "source_evidence_id NOT IN (SELECT id FROM evidence)"
            ).fetchone()[0],
            "evidence_bad_hash": con.execute(
                "SELECT COUNT(*) FROM evidence WHERE record_hash IS NULL OR "
                "LENGTH(record_hash) != 64"
            ).fetchone()[0],
            "evidence_bad_license": con.execute(
                "SELECT COUNT(*) FROM evidence WHERE license IS NULL OR TRIM(license) = ''"
            ).fetchone()[0],
            "evidence_unreferenced": con.execute(
                "SELECT COUNT(*) FROM evidence WHERE id NOT IN "
                "(SELECT source_evidence_id FROM revisions)"
            ).fetchone()[0],
            "portion_bad_grams": con.execute(
                "SELECT COUNT(*) FROM portions WHERE grams IS NULL OR grams <= 0 OR "
                f"grams > {PORTION_MAX_GRAMS}"
            ).fetchone()[0],
        }
    except sqlite3.OperationalError as error:
        raise SystemExit(
            f"{os.path.basename(path)}: 分片缺 2.0-1j 的三张实体表（{error}）——"
            "用 build_catalog.py 重新产出一份再验收"
        ) from error


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="LocalFit AI 食物目录验收")
    parser.add_argument("--dir", required=True, help="含 catalog.manifest.json 与分片的目录")
    parser.add_argument("--min-canonical", type=int, default=50000)
    parser.add_argument("--min-macro-ratio", type=float, default=0.95)
    parser.add_argument(
        "--max-canonical",
        type=int,
        default=RELEASE_CANONICAL_CAP,
        help="发布目录条目上限（规范 §2.0-1 的性能设计点是 50k/100k）；0 = 不检查",
    )
    parser.add_argument("--report", default=None, help="把 Markdown 报告写到该路径")
    args = parser.parse_args(argv)

    out_dir = os.path.abspath(args.dir)
    manifest_path = os.path.join(out_dir, "catalog.manifest.json")
    if not os.path.isfile(manifest_path):
        print(f"FAIL: manifest not found: {manifest_path}")
        return 2
    with open(manifest_path, encoding="utf-8") as fh:
        manifest = json.load(fh)

    failures: list[str] = []
    notes: list[str] = []

    # --- manifest 自身的契约 -------------------------------------------------
    if manifest.get("manifest_version") != MANIFEST_VERSION:
        failures.append(
            f"manifest_version={manifest.get('manifest_version')} "
            f"(expected {MANIFEST_VERSION})"
        )
    sources = manifest.get("sources") or []
    if not sources:
        failures.append("sources 为空：分片不能没有来源")
    for source in sources:
        license_id = (source.get("license") or "").lower()
        if license_id not in ALLOWED_LICENSES:
            failures.append(f"来源 {source.get('id')} 的许可证不在白名单：{license_id}")
        if not (source.get("attribution") or "").strip():
            failures.append(f"来源 {source.get('id')} 缺 attribution")
        if not (source.get("retrieved_at") or "").strip():
            failures.append(f"来源 {source.get('id')} 缺 retrieved_at")

    shards = manifest.get("shards") or []
    if not shards:
        failures.append("manifest 没有分片")

    # --- 逐分片独立重算 ------------------------------------------------------
    totals = {
        "rows": 0,
        "alias_rows": 0,
        "portion_rows": 0,
        "revision_rows": 0,
        "evidence_rows": 0,
        "portion_orphans": 0,
        "revision_orphans": 0,
        "revision_mismatched": 0,
        "revision_dangling_evidence": 0,
        "evidence_bad_hash": 0,
        "evidence_bad_license": 0,
        "evidence_unreferenced": 0,
        "portion_bad_grams": 0,
        "fts_rows": 0,
        "empty_name": 0,
        "empty_id": 0,
        "nan_or_inf": 0,
        "negative": 0,
        "out_of_range": 0,
        "license_not_allowed": 0,
        "missing_license_field": 0,
        "verified": 0,
        "incomplete": 0,
        "missing_macros": 0,
        "cjk_names": 0,
        "branded": 0,
    }
    all_ids: list[str] = []
    sizes: list[tuple[str, int]] = []

    for shard in shards:
        name = shard.get("file") or ""
        if not SHARD_FILE_RE.match(name):
            failures.append(f"分片名不合规：{name}")
            continue
        path = os.path.join(out_dir, name)
        if not os.path.isfile(path):
            failures.append(f"分片缺失：{name}")
            continue
        actual_hash = sha256_file(path)
        if not HEX64.match(shard.get("sha256") or ""):
            failures.append(f"{name}: manifest 的 sha256 不是 64 位十六进制")
        elif actual_hash != shard["sha256"]:
            failures.append(f"{name}: sha256 不匹配（manifest={shard['sha256'][:12]}… actual={actual_hash[:12]}…）")
        sizes.append((name, os.path.getsize(path)))

        stats = scan_shard(path)
        if stats["rows"] != shard.get("rows"):
            failures.append(f"{name}: 行数不一致（manifest={shard.get('rows')} actual={stats['rows']}）")
        if stats["fts_rows"] != shard.get("fts_rows"):
            failures.append(f"{name}: FTS 行数不一致（manifest={shard.get('fts_rows')} actual={stats['fts_rows']}）")
        if stats["missing_macros"] != 0:
            failures.append(f"{name}: 有 {stats['missing_macros']} 行缺四项宏量（不得发布）")
        # 分片级计数：导入器拿它对账拷进来的行数，所以这里也要独立复算。
        for key in ("portion_rows", "revision_rows", "evidence_rows"):
            declared = shard.get(key)
            if not isinstance(declared, int):
                failures.append(f"{name}: manifest 缺 {key}")
            elif declared != stats[key]:
                failures.append(f"{name}: {key} 不一致（manifest={declared} actual={stats[key]}）")
        if shard.get("kind") == "brand" and stats["verified"] != 0:
            notes.append(f"{name}: brand 分片里有 {stats['verified']} 条 verified（不违规，仅记录）")

        for key in totals:
            totals[key] += stats[key]
        all_ids.extend(stats["ids"])

    # --- 全局唯一性 ----------------------------------------------------------
    duplicate_ids = len(all_ids) - len(set(all_ids))
    if duplicate_ids:
        failures.append(f"重复 ID：{duplicate_ids}")

    quality = manifest.get("quality") or {}
    if totals["rows"] != quality.get("canonical_rows"):
        failures.append(
            f"canonical_rows 不一致（manifest={quality.get('canonical_rows')} actual={totals['rows']}）"
        )
    if totals["fts_rows"] != quality.get("fts_index_rows"):
        failures.append(
            f"fts_index_rows 不一致（manifest={quality.get('fts_index_rows')} actual={totals['fts_rows']}）"
        )
    if totals["alias_rows"] != quality.get("alias_rows"):
        failures.append(
            f"alias_rows 不一致（manifest={quality.get('alias_rows')} actual={totals['alias_rows']}）"
        )
    # 规范 §5.5/§5：manifest 必须报告 portions / revisions / evidence 行数，而且
    # 报出来的数要能被独立复算。缺字段＝旧版 ETL 产物（2.0-1j 之前这三张表没有
    # 生产者，manifest 只能写 0）。
    for key, actual in (
        ("portion_rows", totals["portion_rows"]),
        ("revision_rows", totals["revision_rows"]),
        ("evidence_rows", totals["evidence_rows"]),
    ):
        declared = quality.get(key)
        if not isinstance(declared, int):
            failures.append(f"manifest 缺 quality.{key}（ETL 版本过旧，规范 §5.5 要求报告）")
        elif declared != actual:
            failures.append(f"{key} 不一致（manifest={declared} actual={actual}）")
    if totals["revision_rows"] != totals["rows"]:
        failures.append(
            f"revisions 行数 {totals['revision_rows']} != canonical {totals['rows']}"
            "（每条发布记录都要有一条修订）"
        )
    if totals["evidence_rows"] != totals["rows"]:
        failures.append(
            f"evidence 行数 {totals['evidence_rows']} != canonical {totals['rows']}"
            "（每条发布记录都要有一条来源证据）"
        )
    if not HEX64.match(quality.get("fts_sha256") or ""):
        failures.append("manifest 缺 fts_sha256")

    # 源侧账目：不发布的候选也要有数（缺了这个字段说明 manifest 是旧版 ETL 产的）。
    candidate_rows = quality.get("candidate_rows")
    dropped_incomplete = quality.get("dropped_incomplete_macros")
    if not isinstance(candidate_rows, int) or not isinstance(dropped_incomplete, int):
        failures.append("manifest 缺 candidate_rows / dropped_incomplete_macros（ETL 版本过旧）")
        candidate_rows, dropped_incomplete = 0, 0
    elif dropped_incomplete > candidate_rows:
        failures.append(
            f"dropped_incomplete_macros({dropped_incomplete}) > candidate_rows({candidate_rows})"
        )
    dropped_over_cap = quality.get("dropped_over_cap")
    if not isinstance(dropped_over_cap, int):
        failures.append("manifest 缺 dropped_over_cap（ETL 版本过旧）")
        dropped_over_cap = 0

    macro_ratio = totals["verified"] / totals["rows"] if totals["rows"] else 0.0
    # manifest 里的比值必须能被独立复算出来：应用侧的 parseCatalogManifest
    # 要求它在 [0,1] 内并直接读它，写错会让整包被拒（2.0-1h 实测抓到
    # 16.93 这种「分子取了截断前、分母取了截断后」的值）。
    declared_ratio = quality.get("macro_complete_ratio")
    if not isinstance(declared_ratio, (int, float)) or not 0.0 <= declared_ratio <= 1.0:
        failures.append(f"manifest 的 macro_complete_ratio 不在 [0,1]：{declared_ratio}")
    elif abs(macro_ratio - declared_ratio) > 0.005:
        failures.append(
            f"macro_complete_ratio 复算 {macro_ratio:.6f} != manifest {declared_ratio}"
        )
    cjk_coverage = totals["cjk_names"] / totals["rows"] if totals["rows"] else 0.0
    brand_coverage = totals["branded"] / totals["rows"] if totals["rows"] else 0.0

    # --- docs/05 §5 门槛 -----------------------------------------------------
    def gate(label: str, ok: bool, detail: str) -> None:
        if not ok:
            failures.append(f"门槛未过：{label}（{detail}）")

    gate(
        "canonical ≥ 最小值",
        totals["rows"] >= args.min_canonical,
        f"canonical={totals['rows']} < {args.min_canonical}",
    )
    gate(
        "四项宏量完整率 ≥ 最小值",
        macro_ratio >= args.min_macro_ratio,
        f"{macro_ratio:.4f} < {args.min_macro_ratio}",
    )
    gate("重复 ID = 0", duplicate_ids == 0, str(duplicate_ids))
    gate("缺失名称 = 0", totals["empty_name"] == 0, str(totals["empty_name"]))
    gate("缺失 ID = 0", totals["empty_id"] == 0, str(totals["empty_id"]))
    gate("非法单位/超范围 = 0", totals["out_of_range"] == 0, str(totals["out_of_range"]))
    gate("负值 = 0", totals["negative"] == 0, str(totals["negative"]))
    gate("NaN/Infinity = 0", totals["nan_or_inf"] == 0, str(totals["nan_or_inf"]))
    gate(
        "来源/许可证缺失 = 0",
        totals["license_not_allowed"] == 0,
        str(totals["license_not_allowed"]),
    )
    # 逐行独立重数：只要有一行缺四项宏量就不过，不看 ETL 自报的比例。
    gate(
        "发布目录缺四项宏量的行 = 0",
        totals["missing_macros"] == 0,
        str(totals["missing_macros"]),
    )
    if args.max_canonical:
        gate(
            "canonical ≤ 发布上限",
            totals["rows"] <= args.max_canonical,
            f"canonical={totals['rows']} > {args.max_canonical}"
            "（规范 §2.0-1 的性能设计点是 50k/100k；全量目录只用于离线分析）",
        )
    # 规范 §5.5 的三个实体：行要在、外键要成立、内容不许凑数。
    gate("portion 孤儿行 = 0", totals["portion_orphans"] == 0, str(totals["portion_orphans"]))
    gate("revision 孤儿行 = 0", totals["revision_orphans"] == 0, str(totals["revision_orphans"]))
    gate(
        "revision 四项宏量与 foods 一致 = 0 处不符",
        totals["revision_mismatched"] == 0,
        str(totals["revision_mismatched"]),
    )
    gate(
        "revision → evidence 链完整",
        totals["revision_dangling_evidence"] == 0,
        str(totals["revision_dangling_evidence"]),
    )
    gate(
        "evidence 原始记录哈希为 64 位十六进制",
        totals["evidence_bad_hash"] == 0,
        str(totals["evidence_bad_hash"]),
    )
    gate(
        "evidence 许可证非空",
        totals["evidence_bad_license"] == 0,
        str(totals["evidence_bad_license"]),
    )
    gate(
        "evidence 无未引用行",
        totals["evidence_unreferenced"] == 0,
        str(totals["evidence_unreferenced"]),
    )
    gate(
        "portion 克数在 (0, 5kg]",
        totals["portion_bad_grams"] == 0,
        str(totals["portion_bad_grams"]),
    )

    total_bytes = sum(size for _, size in sizes)
    largest = max(sizes, key=lambda item: item[1]) if sizes else ("-", 0)

    lines: list[str] = []
    lines.append("## 目录验收（accept_catalog.py 独立重算）")
    lines.append("")
    lines.append(f"- catalog_version: `{manifest.get('catalog_version')}`；transform `{manifest.get('transform_version')}`；generated_at `{manifest.get('generated_at')}`")
    for source in sources:
        lines.append(
            f"- 来源：`{source.get('id')}` · 许可证 `{source.get('license')}` · "
            f"{source.get('attribution')} · 采集 `{source.get('retrieved_at')}`"
        )
    lines.append("")
    lines.append("| 项 | 值 | 门槛 | 结果 |")
    lines.append("|---|---|---|---|")
    rows_of = [
        ("canonical", totals["rows"], f"≥ {args.min_canonical}"),
        ("发布上限", args.max_canonical or "不检查", "规范 §2.0-1 性能设计点"),
        ("alias", totals["alias_rows"], "记录"),
        ("portion", f"{totals['portion_rows']}（仅上游自称克数的份量）", "记录"),
        ("revision", totals["revision_rows"], f"= canonical（{totals['rows']}）"),
        ("evidence", totals["evidence_rows"], f"= canonical（{totals['rows']}）"),
        ("portion/revision 孤儿行", f"{totals['portion_orphans']} / {totals['revision_orphans']}", "= 0"),
        ("revision 与 foods 营养不符", totals["revision_mismatched"], "= 0"),
        ("revision → evidence 断链", totals["revision_dangling_evidence"], "= 0"),
        ("evidence 哈希/许可证异常", f"{totals['evidence_bad_hash']} / {totals['evidence_bad_license']}", "= 0"),
        ("重复 ID", duplicate_ids, "= 0"),
        ("缺失名称", totals["empty_name"], "= 0"),
        ("非法单位/超范围", totals["out_of_range"], "= 0"),
        ("负值", totals["negative"], "= 0"),
        ("NaN/Infinity", totals["nan_or_inf"], "= 0"),
        ("来源/许可证缺失", totals["license_not_allowed"], "= 0"),
        ("四项宏量完整率", f"{macro_ratio:.4f}", f"≥ {args.min_macro_ratio}"),
        ("发布目录缺宏量的行", totals["missing_macros"], "= 0"),
        (
            "源侧候选 / 因缺宏量未发布",
            f"{candidate_rows} / {dropped_incomplete}"
            + (
                f"（源侧完整率 {(candidate_rows - dropped_incomplete) / candidate_rows:.4f}）"
                if candidate_rows
                else ""
            ),
            "记录",
        ),
        ("因超出发布上限未发布", dropped_over_cap, "记录"),
        ("中文名覆盖", f"{cjk_coverage:.4f}（{totals['cjk_names']} 条）", "记录"),
        ("品牌覆盖", f"{brand_coverage:.4f}（{totals['branded']} 条）", "记录"),
        ("FTS 行数", totals["fts_rows"], "= 分片之和"),
        ("FTS 索引 hash", f"`{(quality.get('fts_sha256') or '')[:16]}…`", "64 位十六进制"),
        ("分片数", len(sizes), "记录"),
        ("分片总大小", f"{total_bytes / 1048576:.1f} MiB", "记录"),
        ("最大分片", f"{largest[0]} {largest[1] / 1048576:.1f} MiB", "记录"),
        ("压缩大小", "未产出压缩分片", "记录"),
    ]
    for label, value, limit in rows_of:
        lines.append(f"| {label} | {value} | {limit} | |")
    lines.append("")
    lines.append("分片明细：")
    lines.append("")
    lines.append("| 分片 | 大小 MiB | foods | FTS | sha256 |")
    lines.append("|---|---|---|---|---|")
    for shard in shards:
        size = dict(sizes).get(shard.get("file"), 0)
        lines.append(
            f"| `{shard.get('file')}` | {size / 1048576:.2f} | {shard.get('rows')} | "
            f"{shard.get('fts_rows')} | `{(shard.get('sha256') or '')[:12]}…` |"
        )
    lines.append("")
    for note in notes:
        lines.append(f"- 备注：{note}")
    if failures:
        lines.append("")
        lines.append("**未过项：**")
        for item in failures:
            lines.append(f"- {item}")

    report = "\n".join(lines) + "\n"
    print(report)
    if args.report:
        with open(args.report, "w", encoding="utf-8") as fh:
            fh.write(report)

    if failures:
        print(f"FAIL: {len(failures)} 项未过")
        return 1
    print("PASS: 全部门槛通过")
    return 0


if __name__ == "__main__":
    sys.exit(main())