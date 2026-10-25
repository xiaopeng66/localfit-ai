"""ETL 管线 fixture 测试（不依赖 7.68GB 全量数据，下载完成后另有全量验收）。

运行：C:/ProgramData/miniconda3/python.exe test_pipeline.py
"""

from __future__ import annotations

import gzip
import hashlib
import json
import math
import os
import sqlite3
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from etl_pipeline import run_pipeline  # noqa: E402

HEX64 = set("0123456789abcdef")


def off_record(
    code,
    name,
    kcal=None,
    protein=None,
    carbs=None,
    fat=None,
    brand=None,
    lang="en",
    categories=None,
    popularity=None,
    serving_size=None,
    serving_quantity=None,
):
    nutriments = {}
    if kcal is not None:
        nutriments["energy-kcal_100g"] = kcal
    if protein is not None:
        nutriments["proteins_100g"] = protein
    if carbs is not None:
        nutriments["carbohydrates_100g"] = carbs
    if fat is not None:
        nutriments["fat_100g"] = fat
    rec = {"code": code, "product_name": name, "lang": lang, "nutriments": nutriments}
    if brand:
        rec["brands"] = brand
    if categories:
        rec["categories"] = categories
    if popularity is not None:
        rec["popularity_key"] = popularity
    if serving_size is not None:
        rec["serving_size"] = serving_size
    if serving_quantity is not None:
        rec["serving_quantity"] = serving_quantity
    return rec


def write_fixture(path: str, records: list[dict]) -> None:
    with gzip.open(path, "wt", encoding="utf-8") as fh:
        for rec in records:
            fh.write(json.dumps(rec, ensure_ascii=False) + "\n")


def fixture_records() -> list[dict]:
    return [
        # 完整宏量 verified；份量是「克」开头 → 产出 1 条 portion
        off_record(
            "1001",
            "Steamed Rice",
            130,
            2.7,
            28,
            0.3,
            brand="Generic",
            categories="Rice,Cereals",
            popularity=500,
            serving_size="30 g (30 g)",
            serving_quantity=30,
        ),
        # 中文 locale verified（FTS 逐字 token 查询用例）；份量是杯/毫升 →
        # **不产出** portion（ml 不是克，规范 5.5 不允许猜克数）
        off_record(
            "1002",
            "宫保鸡丁",
            190,
            12,
            9,
            11,
            brand="食堂",
            lang="zh",
            categories="川菜",
            popularity=900,
            serving_size="1 cup (240 ml)",
            serving_quantity=240,
        ),
        # 重复（name+brand 相同）→ 去重
        off_record("1003", "steamed rice", 130, 2.7, 28, 0.3, brand="generic"),
        # 负营养值 → 丢弃
        off_record("1004", "Bad Food", -5, 2, 2, 2),
        # kcal 超范围 → 丢弃
        off_record("1005", "Pure Oil", 1200, 0, 0, 100),
        # NaN kcal → normalize 阶段视为缺失 → incomplete
        {"code": "1006", "product_name": "NaN Food", "nutriments": {"energy-kcal_100g": None, "proteins_100g": 1}},
        # 能量与宏量严重不符 → 丢弃
        off_record("1007", "Energy Mismatch", 800, 1, 1, 1),
        # 无名称 → 丢弃
        {"code": "1008", "product_name": "", "nutriments": {"proteins_100g": 1}},
        # 部分宏量 → incomplete（进 brand 分片）
        off_record("1009", "Partial Yogurt", 60, 3.5),
        # 同一 code 两行（OFF 全量常见：多语言名称 + 同码重复行），名字不同 →
        # 名称去重抓不到，只有按 id 收敛才挡得住分片主键冲突。
        # 不完整的那行放在前面，验证「同 id 优先保留 verified」而不是「先到先得」。
        off_record("1010", "Yogurt Nature", 60, 3.5, lang="fr"),
        # 只有文字带克、没有结构化 serving_quantity → 仍产出 portion（文字自称克数）
        off_record(
            "1010",
            "Yogurt Natural",
            62,
            4,
            5,
            3,
            lang="en",
            popularity=9000,
            serving_size="150 g",
        ),
        # 份量是盎司（1 ONZ ≈ 28 g 但不是克单位）→ 不产出 portion
        off_record(
            "1011",
            "Ounce Snack",
            200,
            5,
            20,
            10,
            serving_size="1 onz",
            serving_quantity=28,
        ),
    ]


def approx(value: float, expected: float) -> bool:
    return math.isclose(value, expected, rel_tol=1e-9)


def main() -> int:
    tmp = tempfile.mkdtemp(prefix="localfit-etl-")
    src = os.path.join(tmp, "fixture.jsonl.gz")
    out = os.path.join(tmp, "out")
    write_fixture(src, fixture_records())

    manifest = run_pipeline(
        input_path=src,
        out_dir=out,
        catalog_version="2026.09-test",
        retrieved_at="2026-09-14T00:00:00Z",
        shard_rows=2,
        source_version="fixture-1",
    )

    failures = []

    def check(name: str, cond: bool) -> None:
        print(("PASS " if cond else "FAIL ") + name)
        if not cond:
            failures.append(name)

    # --- manifest 形状与应用侧 Dart 契约对齐 ---
    check("manifest_version==1", manifest["manifest_version"] == 1)
    check("catalog_version", manifest["catalog_version"] == "2026.09-test")
    check("transform_version", manifest["transform_version"] == "etl-2")
    check("sources license odbl", manifest["sources"][0]["license"] == "odbl-1.0")
    check("sources retrieved_at", manifest["sources"][0]["retrieved_at"] == "2026-09-14T00:00:00Z")
    quality = manifest["quality"]
    check("duplicate_ids==0", quality["duplicate_ids"] == 0)
    check("missing_license_count==0", quality["missing_license_count"] == 0)

    # fixture 13 条 raw：按 id 去重 1（1010 两行）、按名称去重 1、负值 1、
    # kcal 超范围 1、能量失配 1、无名 1 → 候选 9
    # 其中四项宏量不全 2（1006/1009）不发布，异常 3（1004/1005/1007）
    # → canonical 4（1001/1002/1010/1011），全部 verified
    check("canonical_rows==4", quality["canonical_rows"] == 4)
    check("macro_complete_ratio==1.0", approx(quality["macro_complete_ratio"], 1.0))
    check("anomaly_count==3", quality["anomaly_count"] == 3)
    check("candidate_rows==9", quality["candidate_rows"] == 9)
    check("dropped_incomplete_macros==2", quality["dropped_incomplete_macros"] == 2)
    check("chinese_name_coverage==1/4", quality["chinese_name_coverage"] == round(1 / 4, 6))

    # --- 分片文件与 hash ---
    shard_files = [s["file"] for s in manifest["shards"]]
    check("shard naming", all(f.startswith("foods-") and f.endswith(".sqlite") for f in shard_files))
    check("core shard exists", any("-core-" in f for f in shard_files))
    # 不完整条目按规范 §2.0-1 不进发布目录，所以不该有 brand 分片
    check("no brand shard", not any("-brand-" in f for f in shard_files))
    for shard in manifest["shards"]:
        digest = shard["sha256"]
        check(f"sha256 hex64 {shard['file']}", len(digest) == 64 and set(digest) <= HEX64)
        path = os.path.join(out, shard["file"])
        actual = hashlib.sha256(open(path, "rb").read()).hexdigest()
        check(f"sha256 matches file {shard['file']}", actual == digest)

    # --- 分片内容：core 分片只含 verified，FTS 逐字 token 可查中文 ---
    core_name = next(f for f in shard_files if "-core-" in f)
    con = sqlite3.connect(os.path.join(out, core_name))
    try:
        ids = [r[0] for r in con.execute("SELECT id FROM foods ORDER BY id")]
        check("core contains 1001+1002", ids == ["off:1001", "off:1002"])
        states = {r[0] for r in con.execute("SELECT DISTINCT state FROM foods")}
        check("core states verified only", states == {"verified"})

        # 中文：FTS5 查询 "宫 保" 逐字 token；主名与品牌组合别名行都命中
        hits = con.execute(
            "SELECT food_id FROM food_search WHERE food_search MATCH ?",
            ("宫 保",),
        ).fetchall()
        check("fts cjk query hits 1002", {h[0] for h in hits} == {"off:1002"})

        # 别名层：normalized + brand 组合
        alias_rows = con.execute(
            "SELECT normalized_text, alias_type FROM aliases WHERE food_id='off:1002'"
        ).fetchall()
        texts = {t for t, _ in alias_rows}
        check("alias normalized", "宫保鸡丁" in texts)
        check("alias brand combo", "食堂 宫保鸡丁" in texts)

        # 无重复 ID（规范 5.8）
        dup = con.execute(
            "SELECT COUNT(*) FROM (SELECT id FROM foods GROUP BY id HAVING COUNT(*)>1)"
        ).fetchone()[0]
        check("no duplicate ids", dup == 0)
        # FTS 行数与 manifest 一致
        fts_rows = con.execute("SELECT COUNT(*) FROM food_search").fetchone()[0]
        declared = next(s for s in manifest["shards"] if s["file"] == core_name)["fts_rows"]
        check("fts rows match manifest", fts_rows == declared)
    finally:
        con.close()

    # --- 同 code 两行：按 id 去重后只剩一条，且留下的是 verified 那条 ---
    # 全量 ETL 正是死在这里（UNIQUE constraint failed: foods.id @ build_shard）：
    # 名称+品牌去重挡不住「同 code 不同名」的多语言行。逐分片扫一遍，
    # 谁再把按 id 去重删掉，这条会立刻红。
    all_ids: list[str] = []
    missing_macros = 0
    for shard in manifest["shards"]:
        con = sqlite3.connect(os.path.join(out, shard["file"]))
        try:
            all_ids.extend(r[0] for r in con.execute("SELECT id FROM foods"))
            missing_macros += con.execute(
                "SELECT COUNT(*) FROM foods WHERE kcal_per100g IS NULL OR "
                "protein_per100g IS NULL OR carbs_per100g IS NULL OR fat_per100g IS NULL"
            ).fetchone()[0]
            rows = con.execute(
                "SELECT name, state FROM foods WHERE id='off:1010'"
            ).fetchall()
        finally:
            con.close()
        if rows:
            check(f"1010 survivor in {shard['file']}", rows == [("Yogurt Natural", "verified")])
    check("1010 kept exactly once", all_ids.count("off:1010") == 1)
    check("id list has no repeats", len(set(all_ids)) == len(all_ids))
    check("no shipped row lacks macros", missing_macros == 0)

    # --- manifest 落盘且可 json 解析 ---
    with open(os.path.join(out, "catalog.manifest.json"), encoding="utf-8") as fh:
        on_disk = json.load(fh)
    check("manifest on disk", on_disk["catalog_version"] == "2026.09-test")

    # --- 发布分层：超过 cap 时按上游流行度截断（规范 §2.0-1 的 50k/100k 设计点）---
    # 85 分片 / 170 万条的真实目录下单次搜索要 0.75 s，因此发布物必须有上限，
    # 且截断要按流行度而不是输入顺序。这里用 max_canonical=2 固定住行为。
    capped_out = os.path.join(tmp, "capped")
    capped = run_pipeline(
        input_path=src,
        out_dir=capped_out,
        catalog_version="2026.09-cap",
        retrieved_at="2026-09-14T00:00:00Z",
        shard_rows=10,
        source_version="fixture-1",
        max_canonical=2,
    )
    capped_quality = capped["quality"]
    check("cap 生效：canonical==2", capped_quality["canonical_rows"] == 2)
    check("cap 生效：dropped_over_cap==2", capped_quality["dropped_over_cap"] == 2)
    # 比值必须在截断之后重算：曾经出现过 1.5 / 16.93（分子取截断前、分母取
    # 截断后），应用侧 parseCatalogManifest 要求它在 [0,1] 内。
    check(
        "cap 后的 macro_complete_ratio 在 [0,1]",
        0.0 <= capped_quality["macro_complete_ratio"] <= 1.0,
    )
    check("cap 后的 macro_complete_ratio==1.0", capped_quality["macro_complete_ratio"] == 1.0)
    capped_ids = []
    for shard in capped["shards"]:
        con = sqlite3.connect(os.path.join(capped_out, shard["file"]))
        try:
            capped_ids.extend(r[0] for r in con.execute("SELECT id FROM foods"))
        finally:
            con.close()
    # 流行度 9000（1010，输入顺序最后）> 900（1002，中文名）> 500（1001）——
    # 输入顺序与流行度顺序故意相反，先到先得会被这条抓住。
    check("cap 按流行度选取", sorted(capped_ids) == ["off:1002", "off:1010"])

    # cap=1 留下的必须是中文名那条（1002，流行度只有 900），不是最流行的
    # 1010（9000）：OFF 全量里中文条目只有 1,932 条，纯流行度截断会把它们
    # 几乎切光（实测发布目录只剩 4 条中文名），而规范 §5.2 的 A 层正是中文食物。
    cjk_out = os.path.join(tmp, "capped_cjk")
    cjk = run_pipeline(
        input_path=src,
        out_dir=cjk_out,
        catalog_version="2026.09-cjk",
        retrieved_at="2026-09-14T00:00:00Z",
        shard_rows=10,
        source_version="fixture-1",
        max_canonical=1,
    )
    cjk_ids = []
    for shard in cjk["shards"]:
        con = sqlite3.connect(os.path.join(cjk_out, shard["file"]))
        try:
            cjk_ids.extend(r[0] for r in con.execute("SELECT id FROM foods"))
        finally:
            con.close()
    check("cap 优先保留中文名条目", cjk_ids == ["off:1002"])
    check("cap=1 时 dropped_over_cap==3", cjk["quality"]["dropped_over_cap"] == 3)

    # --- 规范 §5.5 的三个实体：portions / revisions / evidence ---
    # 2.0-1j 之前这三张表（以及分片里的 portions）建了但没有任何生产者，
    # manifest 只能如实写「portion 0」。这里同时钉住「有产出」与「不猜克数」。
    check("quality 报告 portion_rows", quality["portion_rows"] == 2)
    check("quality 报告 revision_rows", quality["revision_rows"] == 4)
    check("quality 报告 evidence_rows", quality["evidence_rows"] == 4)
    check(
        "分片级计数之和 == quality 总计",
        sum(s["portion_rows"] for s in manifest["shards"]) == quality["portion_rows"]
        and sum(s["revision_rows"] for s in manifest["shards"]) == quality["revision_rows"]
        and sum(s["evidence_rows"] for s in manifest["shards"]) == quality["evidence_rows"],
    )
    # 1001 的文字自称克数且带结构化 serving_quantity；1010 只有文字「150 g」。
    # 1002 是杯/毫升、1011 是盎司——都不是克，不允许换算或猜。
    expected_portions = {"off:1001": 30.0, "off:1010": 150.0}
    seen_portions: dict[str, float] = {}
    for shard in manifest["shards"]:
        con = sqlite3.connect(os.path.join(out, shard["file"]))
        try:
            foods_count = con.execute("SELECT COUNT(*) FROM foods").fetchone()[0]
            revisions = con.execute(
                "SELECT COUNT(*) FROM revisions"
            ).fetchone()[0]
            evidence = con.execute("SELECT COUNT(*) FROM evidence").fetchone()[0]
            check(f"revisions == foods ({shard['file']})", revisions == foods_count)
            check(f"evidence == foods ({shard['file']})", evidence == foods_count)
            check(
                f"分片计数与 manifest 一致 ({shard['file']})",
                con.execute("SELECT COUNT(*) FROM portions").fetchone()[0]
                == shard["portion_rows"]
                and revisions == shard["revision_rows"]
                and evidence == shard["evidence_rows"],
            )
            for food_id, grams in con.execute("SELECT food_id, grams FROM portions"):
                seen_portions[food_id] = grams
            # 每行都必须挂在真实 food 上（规范 5.5 的外键语义）
            for table in ("portions", "revisions"):
                orphans = con.execute(
                    f"SELECT COUNT(*) FROM {table} WHERE food_id NOT IN (SELECT id FROM foods)"
                ).fetchone()[0]
                check(f"{table} 无孤儿行 ({shard['file']})", orphans == 0)
            # evidence 没有 food_id 列（它是「一次采集的证据」），靠 revisions
            # 的 source_evidence_id 指回来；反过来每条 evidence 也必须被引用。
            unused_evidence = con.execute(
                "SELECT COUNT(*) FROM evidence WHERE id NOT IN "
                "(SELECT source_evidence_id FROM revisions)"
            ).fetchone()[0]
            check(f"evidence 无未引用行 ({shard['file']})", unused_evidence == 0)
            # revisions 的营养必须与 foods 逐值相同（不允许复制价格/别名凑数）
            mismatched = con.execute(
                "SELECT COUNT(*) FROM revisions r JOIN foods f ON f.id = r.food_id "
                "WHERE r.revision_number != 1 OR r.quality_status != f.state OR "
                "r.kcal_per100g IS NOT f.kcal_per100g OR "
                "r.protein_per100g IS NOT f.protein_per100g OR "
                "r.carbs_per100g IS NOT f.carbs_per100g OR "
                "r.fat_per100g IS NOT f.fat_per100g"
            ).fetchone()[0]
            check(f"revisions 与 foods 逐值一致 ({shard['file']})", mismatched == 0)
            # evidence 的 record_hash 必须是 64 位十六进制，且指向存在的来源
            bad_hash = con.execute(
                "SELECT COUNT(*) FROM evidence WHERE LENGTH(record_hash) != 64"
            ).fetchone()[0]
            check(f"evidence record_hash hex64 ({shard['file']})", bad_hash == 0)
            check(
                f"evidence 许可证非空 ({shard['file']})",
                con.execute(
                    "SELECT COUNT(*) FROM evidence WHERE license IS NULL OR license = ''"
                ).fetchone()[0]
                == 0,
            )
            # revisions.source_evidence_id 必须能指回 evidence（读路径靠这条链）
            dangling = con.execute(
                "SELECT COUNT(*) FROM revisions WHERE source_evidence_id IS NOT NULL "
                "AND source_evidence_id NOT IN (SELECT id FROM evidence)"
            ).fetchone()[0]
            check(f"revisions→evidence 链完整 ({shard['file']})", dangling == 0)
        finally:
            con.close()
    check("份量只来自自称克数的条目", seen_portions == expected_portions)

    # 原始记录哈希可独立复算：应用侧只能看到哈希，必须能拿上游原文核对。
    raw_1001 = next(r for r in fixture_records() if r["code"] == "1001")
    expected_hash = hashlib.sha256(
        json.dumps(raw_1001, sort_keys=True, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    ).hexdigest()
    found_hash = None
    for shard in manifest["shards"]:
        con = sqlite3.connect(os.path.join(out, shard["file"]))
        try:
            row = con.execute(
                "SELECT record_hash FROM evidence WHERE id = 'off:1001:ev'"
            ).fetchone()
        finally:
            con.close()
        if row:
            found_hash = row[0]
    check("evidence record_hash 可独立复算", found_hash == expected_hash)

    # --- FTS 内容 hash：应用侧 parseCatalogManifest 要求 64 位小写十六进制 ---
    # 它曾经一直是空串（report.fts_sha256 从未被赋值），空串会让应用拒绝整包、
    # 50k 导入根本起不来。这里固定住「必须是 hex64」且「可独立复算」。
    fts_sha = quality["fts_sha256"]
    check("fts_sha256 hex64", len(fts_sha) == 64 and set(fts_sha) <= HEX64)
    check("fts_sha256 matches on-disk", on_disk["quality"]["fts_sha256"] == fts_sha)
    combined = hashlib.sha256()
    for shard in manifest["shards"]:
        con = sqlite3.connect(os.path.join(out, shard["file"]))
        try:
            single = hashlib.sha256()
            for row in con.execute(
                "SELECT food_id, text, brand, category FROM food_search "
                "ORDER BY food_id, text, brand, category"
            ):
                single.update(
                    "\x01".join("" if v is None else str(v) for v in row).encode("utf-8")
                )
                single.update(b"\n")
        finally:
            con.close()
        combined.update(f"{shard['file']}:{single.hexdigest()}\n".encode("utf-8"))
    check("fts_sha256 recomputes", combined.hexdigest() == fts_sha)

    print()
    if failures:
        print(f"{len(failures)} FAILED")
        return 1
    print("ALL PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
