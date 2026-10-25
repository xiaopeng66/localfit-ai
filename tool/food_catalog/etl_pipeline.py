"""LocalFit AI 2.0 食物目录离线 ETL 管线（规范 5.4/5.8）。

阶段：normalize -> deduplicate -> validate -> shard(SQLite+FTS5) -> manifest。

用法：
    python build_catalog.py --input sources/openfoodfacts-products.jsonl.gz \
        --out ../../assets/catalog --catalog-version 2026.09 [--limit N]

输入是 Open Food Facts（ODbL）jsonl.gz；输出是分片 SQLite + catalog.manifest.json。
manifest JSON 形状与应用侧 `lib/features/nutrition/data/catalog_manifest.dart`
的 parseCatalogManifest 契约一一对应，任何违规（重复 ID、NaN/Inf、负营养值、
无许可证来源）都会让该条记录被丢弃，不进入发布分片。
"""

from __future__ import annotations

import argparse
import gzip
import hashlib
import json
import math
import os
import re
import sqlite3
import sys
from dataclasses import dataclass, field
from datetime import datetime, timezone

# etl-2：2.0-1j 起分片里真的产出 portions/revisions/evidence 三个实体
# （etl-1 的份量表是空的）。版本号要能区分这两种产物——导入器遇到旧分片会
# 按「没有实体表」处理，混在一批里会让人以为份量数据丢了。
TRANSFORM_VERSION = "etl-2"
MANIFEST_VERSION = 1
SOURCE = {
    "id": "openfoodfacts",
    "name": "Open Food Facts",
    "license": "odbl-1.0",
    "attribution": "(c) Open Food Facts contributors (ODbL)",
    "retrieved_at": None,  # 由 --retrieved-at 填写
}

# 每 100g 合理范围（规范 5.8：数值异常不得进入发布分片）。
KCAL_MIN, KCAL_MAX = 0.0, 900.0
MACRO_MIN, MACRO_MAX = 0.0, 100.0
# 能量与宏量差异检查：期望 kcal = 4*(P+C) + 9*F，偏差超过 60% 记为异常。
ENERGY_DEVIATION_TOLERANCE = 0.60
# 规范 §2.0-1：发布目录中具备完整四项宏量、可参与本地营养计算的条目比例 ≥95%。
MACRO_COMPLETE_MIN_RATIO = 0.95
# 发布分层上限（规范 §2.0-1 的性能设计点是 50k/100k：首屏搜索 P95 <200ms、
# 导入不能以十分钟计）。OFF 全量去重后约 170 万条完整条目，实测在 85 个分片
# 下单次搜索进程内就要 0.75s，因此发布目录按上游流行度截断到这个上限；
# 传 `--max-canonical 0` 可产出不经截断的全量目录（用于离线分析）。
RELEASE_CANONICAL_CAP = 100000

CJK_RE = re.compile(r"[\u4e00-\u9fff]")
SHARD_FILE_RE = re.compile(r"^foods-[a-z]+-\d{3}\.sqlite$")

# 份量（规范 §5.5 `food_portions`）：只认**上游自己声明为克**的份量。
# OFF 的 `serving_quantity` 语义是「克或毫升，看 `serving_size` 怎么写」，
# 且这份导出里没有 `serving_size_unit` 字段；把杯/盎司/毫升换算成克需要密度，
# 那是猜。规范 §5 又明确禁止「通过复制同一营养值或重复别名凑数」，所以宁可
# 在 10 万条目录里只产出约 1 万条真克重的份量，也不做单位换算。
SERVING_LEAD_RE = re.compile(r"^\s*([0-9]+(?:[.,][0-9]+)?)\s*([A-Za-z\u00b5]+)")
GRAM_UNITS = frozenset({"g", "gr", "grs", "gram", "grams", "gramme", "grammes"})
# 单份超过 5kg 的「份量」是上游脏数据（把整包重量写进了 serving_size）。
PORTION_MAX_GRAMS = 5000.0


# ---------------------------------------------------------------------------
# 阶段 1：normalize
# ---------------------------------------------------------------------------


@dataclass
class FoodRecord:
    id: str
    name: str
    state: str  # verified | estimated | incomplete
    locale: str | None
    category: str | None
    brand: str | None
    kcal: float | None
    protein: float | None
    carbs: float | None
    fat: float | None
    source_id: str
    source_version: str
    license_status: str
    # 上游原始记录的规范化 JSON 摘要（规范 §5.5 `food_evidence.record_hash`）。
    # 存 32 字节摘要而不是 64 字符十六进制：全量 320 万条记录都要带着它，
    # 字符串版本会多占几百 MB；写出分片时再 hex。
    record_hash: bytes = b""
    # 克重份量（名称, 克数）；上游没有自称克数时为 None（不换算、不猜）。
    portion: tuple[str, float] | None = None
    # 上游流行度（OFF popularity_key，越大越常见）。只用于发布分层选取，
    # 不进分片、不进 manifest 的逐条字段。
    popularity: int = 0


def iter_raw_records(path: str):
    opener = gzip.open if path.endswith(".gz") else open
    with opener(path, "rt", encoding="utf-8", errors="replace") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                yield json.loads(line)
            except json.JSONDecodeError:
                continue


def _num(value: object) -> float | None:
    if not isinstance(value, (int, float)):
        return None
    result = float(value)
    if math.isnan(result) or math.isinf(result):
        return None
    return result


def _first_tag(value: object) -> str | None:
    if isinstance(value, str) and value.strip():
        return value.split(",")[0].strip() or None
    return None


def record_hash(raw: dict) -> bytes:
    """上游原始记录的摘要（规范 §5.5「原始记录哈希」）。

    键排序 + 紧凑分隔符，保证同一份上游记录在任何机器上算出同一个值：
    应用侧只看得到哈希，要能拿上游原文独立复算。
    """
    canonical = json.dumps(
        raw, sort_keys=True, ensure_ascii=False, separators=(",", ":")
    )
    return hashlib.sha256(canonical.encode("utf-8")).digest()


def infer_portion(raw: dict) -> tuple[str, float] | None:
    """从 `serving_size`/`serving_quantity` 推出**克重**份量，否则 None。

    只接受「份量文字以克开头」的记录：`serving_quantity` 的单位由
    `serving_size` 的文字决定（OFF 这份导出没有独立单位字段），文字写 g 时
    它才是克。文字只有一个裸数字、或单位是杯/盎司/毫升/片时一律不产出——
    换算需要密度，规范 §5 不允许拿换算值凑数。
    """
    text = raw.get("serving_size")
    if not isinstance(text, str):
        return None
    match = SERVING_LEAD_RE.match(text)
    if match is None:
        return None
    unit = match.group(2).lower().rstrip(".")
    if unit not in GRAM_UNITS:
        return None
    quantity = _num(raw.get("serving_quantity"))
    if quantity is not None and quantity > 0:
        grams = quantity
    else:
        # 结构化字段缺失时用文字里的数字：它自己也写着「N g」。
        grams = float(match.group(1).replace(",", "."))
    if not 0 < grams <= PORTION_MAX_GRAMS:
        return None
    name = text.strip()
    return (name if name else f"{grams:g} g", grams)


def normalize_record(raw: dict, source_version: str) -> FoodRecord | None:
    code = raw.get("code")
    name = raw.get("product_name") or raw.get("product_name_zh") or ""
    name = name.strip()
    if not code or not name:
        return None

    nutriments = raw.get("nutriments") or {}
    kcal = _num(nutriments.get("energy-kcal_100g"))
    protein = _num(nutriments.get("proteins_100g"))
    carbs = _num(nutriments.get("carbohydrates_100g"))
    fat = _num(nutriments.get("fat_100g"))

    complete = None not in (kcal, protein, carbs, fat)
    if complete:
        state = "verified"
    elif any(v is not None for v in (kcal, protein, carbs, fat)):
        state = "incomplete"
    else:
        state = "incomplete"

    lang = raw.get("lang") or raw.get("lc") or ""
    locale = "zh" if lang.startswith("zh") else "en"

    popularity_key = _num(raw.get("popularity_key"))

    return FoodRecord(
        id=f"off:{code}",
        name=name,
        state=state,
        locale=locale,
        category=_first_tag(raw.get("categories")),
        brand=_first_tag(raw.get("brands")),
        kcal=kcal,
        protein=protein,
        carbs=carbs,
        fat=fat,
        source_id=SOURCE["id"],
        source_version=source_version,
        license_status="allowed",
        record_hash=record_hash(raw),
        portion=infer_portion(raw),
        popularity=int(popularity_key) if popularity_key is not None else 0,
    )


# ---------------------------------------------------------------------------
# 阶段 2：deduplicate
# ---------------------------------------------------------------------------


def _dedup_key(rec: FoodRecord) -> tuple[str, str]:
    return (rec.name.strip().lower(), (rec.brand or "").strip().lower())


def deduplicate(records: list[FoodRecord]) -> tuple[list[FoodRecord], int, int]:
    """两级去重，返回 (保留记录, 按 id 丢弃数, 按名称+品牌丢弃数)。

    第一级是**按 `id`（= `off:<code>`）**：OFF 全量里同一个 code 会出现多行
    （多语言名称、同码重复行），而 `foods.id` 在分片里是主键——不先按 id 收敛，
    分片插入会直接撞 `UNIQUE constraint failed: foods.id`（20k 前缀冒烟撞不到，
    全量必炸）。同 id 多行时保留「宏量完整（verified）」的那条，同等完整度保留
    先出现的，保证结果只依赖输入顺序、可复现。

    第二级才是规范 5.2 的近重复规则 `(name.lower(), brand.lower())`。
    """
    by_id: dict[str, FoodRecord] = {}
    dropped_by_id = 0
    for rec in records:
        existing = by_id.get(rec.id)
        if existing is None:
            by_id[rec.id] = rec
            continue
        dropped_by_id += 1
        if existing.state != "verified" and rec.state == "verified":
            by_id[rec.id] = rec

    seen: dict[tuple[str, str], FoodRecord] = {}
    dropped_by_name = 0
    for rec in by_id.values():
        key = _dedup_key(rec)
        if key in seen:
            dropped_by_name += 1
            continue
        seen[key] = rec
    return list(seen.values()), dropped_by_id, dropped_by_name


# ---------------------------------------------------------------------------
# 阶段 3：validate
# ---------------------------------------------------------------------------


@dataclass
class QualityReport:
    canonical_rows: int = 0
    alias_rows: int = 0
    duplicate_ids: int = 0
    macro_complete_ratio: float = 0.0
    anomaly_count: int = 0
    chinese_name_coverage: float = 0.0
    missing_license_count: int = 0
    fts_index_rows: int = 0
    fts_sha256: str = ""
    # 规范 §5.5/§5 要求 manifest 报告 portions / revisions / evidence 行数。
    # 2.0-1j 之前这三张表只有表结构没有生产者，报告只能写 0。
    portion_rows: int = 0
    revision_rows: int = 0
    evidence_rows: int = 0
    # 发布目录里不存在的条目也要有账可查：候选源里四项宏量不全的有多少、
    # 因异常被丢弃的有多少。manifest 对外只描述发布物，这两个数字进 manifest
    # 的 quality 块是为了让「为什么只有这些行」可审计，不是凑数。
    dropped_incomplete_macros: int = 0
    candidate_rows: int = 0
    # 发布分层：OFF 全量去重后有 ~170 万条完整条目，而规范的性能设计点是
    # 50k/100k（首屏搜索 P95 <200ms、导入不能以十分钟计）。超过 cap 的部分
    # 按上游流行度截断，被截断的数量如实计数。
    dropped_over_cap: int = 0


def validate_record(rec: FoodRecord, report: QualityReport) -> bool:
    """返回 False 表示该记录必须被丢弃（规范 5.8 硬门槛）。"""
    values = (rec.kcal, rec.protein, rec.carbs, rec.fat)
    present = [v for v in values if v is not None]
    if any(v < 0 for v in present):
        report.anomaly_count += 1
        return False
    if rec.kcal is not None and not (KCAL_MIN <= rec.kcal <= KCAL_MAX):
        report.anomaly_count += 1
        return False
    for v in (rec.protein, rec.carbs, rec.fat):
        if v is not None and not (MACRO_MIN <= v <= MACRO_MAX):
            report.anomaly_count += 1
            return False
    if rec.kcal is not None and rec.protein is not None and rec.carbs is not None and rec.fat is not None:
        expected = 4.0 * (rec.protein + rec.carbs) + 9.0 * rec.fat
        if expected > 0:
            deviation = abs(rec.kcal - expected) / expected
            if deviation > ENERGY_DEVIATION_TOLERANCE:
                report.anomaly_count += 1
                return False
    if rec.license_status != "allowed":
        report.missing_license_count += 1
        return False
    return True


# ---------------------------------------------------------------------------
# 阶段 4：分片 SQLite + FTS5
# ---------------------------------------------------------------------------

SHARD_SCHEMA = """
CREATE TABLE foods (
  id TEXT NOT NULL PRIMARY KEY,
  name TEXT NOT NULL,
  state TEXT NOT NULL,
  locale TEXT,
  category TEXT,
  brand TEXT,
  kcal_per100g REAL,
  protein_per100g REAL,
  carbs_per100g REAL,
  fat_per100g REAL,
  source_id TEXT NOT NULL,
  source_version TEXT,
  license_status TEXT NOT NULL
);
CREATE TABLE aliases (
  food_id TEXT NOT NULL REFERENCES foods(id),
  normalized_text TEXT NOT NULL,
  language TEXT,
  alias_type TEXT,
  confidence REAL NOT NULL DEFAULT 1.0
);
CREATE TABLE portions (
  id TEXT NOT NULL PRIMARY KEY,
  food_id TEXT NOT NULL REFERENCES foods(id),
  name TEXT NOT NULL,
  grams REAL NOT NULL,
  locale TEXT,
  source TEXT
);
CREATE TABLE revisions (
  id TEXT NOT NULL PRIMARY KEY,
  food_id TEXT NOT NULL REFERENCES foods(id),
  revision_number INTEGER NOT NULL,
  kcal_per100g REAL,
  protein_per100g REAL,
  carbs_per100g REAL,
  fat_per100g REAL,
  source_evidence_id TEXT REFERENCES evidence(id),
  quality_status TEXT NOT NULL,
  valid_from TEXT
);
CREATE TABLE evidence (
  id TEXT NOT NULL PRIMARY KEY,
  source_id TEXT NOT NULL,
  license TEXT NOT NULL,
  attribution TEXT,
  retrieved_at TEXT NOT NULL,
  transform_version TEXT NOT NULL,
  quality_status TEXT NOT NULL,
  record_hash TEXT NOT NULL
);
CREATE VIRTUAL TABLE food_search USING fts5(
  food_id UNINDEXED, text, brand, category
);
"""


def _cjk_spaced(text: str) -> str:
    """FTS5 unicode61 不分 CJK：CJK 字符逐字独立成 token（两侧加空格），
    连续拉丁/数字段保持整词（unicode61 按空白分词）。"""
    out: list[str] = []
    buffer: list[str] = []
    for ch in text:
        if CJK_RE.match(ch):
            if buffer:
                out.append("".join(buffer))
                buffer = []
            out.append(ch)
        else:
            buffer.append(ch)
    if buffer:
        out.append("".join(buffer))
    return " ".join(out)


def infer_aliases(rec: FoodRecord) -> list[tuple[str, str, float]]:
    """别名推断（基础版）：规范化名、品牌组合名；拼音与人工审计在后续子切片。"""
    aliases = [(rec.name.strip().lower(), "normalized", 1.0)]
    if rec.brand:
        aliases.append(
            (f"{rec.brand.strip()} {rec.name.strip()}".lower(), "brand", 0.9)
        )
    return aliases


def build_shard(
    path: str,
    records: list[FoodRecord],
    kind: str,
    report: QualityReport,
    retrieved_at: str,
) -> int:
    """写单个分片 SQLite；返回该分片 FTS 行数。"""
    if os.path.exists(path):
        os.remove(path)
    con = sqlite3.connect(path)
    try:
        con.executescript(SHARD_SCHEMA)
        fts_rows = 0
        hash_lines: list[str] = []
        seen_ids: set[str] = set()
        for rec in records:
            # foods.id 是主键：同 id 两条记录若漏到这一步，sqlite 只会抛
            # 「UNIQUE constraint failed: foods.id」——不看代码根本不知道是
            # 哪条数据、哪个上游字段导致的。这里先自查并报出 id + 名称。
            if rec.id in seen_ids:
                raise ValueError(
                    f"duplicate food id in shard {os.path.basename(path)}: "
                    f"{rec.id} ({rec.name!r}, brand={rec.brand!r}) — "
                    "deduplicate() 应按 id 收敛后再分片"
                )
            seen_ids.add(rec.id)
            con.execute(
                "INSERT INTO foods (id, name, state, locale, category, brand,"
                " kcal_per100g, protein_per100g, carbs_per100g, fat_per100g,"
                " source_id, source_version, license_status)"
                " VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)",
                (
                    rec.id,
                    rec.name,
                    rec.state,
                    rec.locale,
                    rec.category,
                    rec.brand,
                    rec.kcal,
                    rec.protein,
                    rec.carbs,
                    rec.fat,
                    rec.source_id,
                    rec.source_version,
                    rec.license_status,
                ),
            )
            # 规范 §5.5 的三个实体（2.0-1j 起有真实生产者）。每条发布记录都带
            # 一条 evidence（原始记录哈希 + 来源/许可证/采集时间/质量等级）和
            # 一条 revision（四项宏量 + 指向 evidence + 质量等级），份量则只在
            # 上游自称克数时产出。id 由 food id 派生，导入与查询都稳定可复现。
            evidence_id = f"{rec.id}:ev"
            con.execute(
                "INSERT INTO evidence (id, source_id, license, attribution,"
                " retrieved_at, transform_version, quality_status, record_hash)"
                " VALUES (?,?,?,?,?,?,?,?)",
                (
                    evidence_id,
                    rec.source_id,
                    SOURCE["license"],
                    SOURCE["attribution"],
                    retrieved_at,
                    TRANSFORM_VERSION,
                    rec.state,
                    rec.record_hash.hex(),
                ),
            )
            report.evidence_rows += 1
            con.execute(
                "INSERT INTO revisions (id, food_id, revision_number,"
                " kcal_per100g, protein_per100g, carbs_per100g, fat_per100g,"
                " source_evidence_id, quality_status, valid_from)"
                " VALUES (?,?,?,?,?,?,?,?,?,?)",
                (
                    f"{rec.id}:rev:1",
                    rec.id,
                    1,
                    rec.kcal,
                    rec.protein,
                    rec.carbs,
                    rec.fat,
                    evidence_id,
                    rec.state,
                    retrieved_at,
                ),
            )
            report.revision_rows += 1
            if rec.portion is not None:
                portion_name, grams = rec.portion
                con.execute(
                    "INSERT INTO portions (id, food_id, name, grams, locale,"
                    " source) VALUES (?,?,?,?,?,?)",
                    (
                        f"{rec.id}:portion:1",
                        rec.id,
                        portion_name,
                        grams,
                        rec.locale,
                        rec.source_id,
                    ),
                )
                report.portion_rows += 1
            for text, alias_type, confidence in infer_aliases(rec):
                if text:
                    con.execute(
                        "INSERT INTO aliases (food_id, normalized_text,"
                        " language, alias_type, confidence) VALUES (?,?,?,?,?)",
                        (rec.id, text, rec.locale, alias_type, confidence),
                    )
                    # 别名行也进 FTS 索引（规范 5.7 搜索优先级含别名）；
                    # normalized 名与主名相同则只索引主名行，避免重复计分。
                    if text != rec.name.strip().lower():
                        con.execute(
                            "INSERT INTO food_search (food_id, text, brand,"
                            " category) VALUES (?,?,?,?)",
                            (
                                rec.id,
                                _cjk_spaced(text),
                                "",
                                "",
                            ),
                        )
                        fts_rows += 1
            brand_text = _cjk_spaced(rec.brand) if rec.brand else ""
            category_text = _cjk_spaced(rec.category) if rec.category else ""
            fts_text = _cjk_spaced(rec.name)
            con.execute(
                "INSERT INTO food_search (food_id, text, brand, category)"
                " VALUES (?,?,?,?)",
                (rec.id, fts_text, brand_text, category_text),
            )
            fts_rows += 1
            hash_lines.append(f"{rec.id}\t{fts_text}")
            report.alias_rows += len([a for a in infer_aliases(rec) if a[0]])

        report.fts_index_rows += fts_rows
        digest = hashlib.sha256()
        for line in hash_lines:
            digest.update(line.encode("utf-8"))
            digest.update(b"\n")
        # 单分片 FTS hash 由 manifest 阶段聚合；此处返回行数。
        con.commit()
        return fts_rows
    finally:
        con.close()


def split_shards(
    records: list[FoodRecord],
    shard_rows: int,
) -> list[tuple[str, list[FoodRecord]]]:
    """core = 完整宏量的 verified 记录（首装即导入）；brand = 其余。"""
    core = [r for r in records if r.state == "verified"]
    rest = [r for r in records if r.state != "verified"]
    shards: list[tuple[str, list[FoodRecord]]] = []
    for i in range(0, len(core), shard_rows):
        shards.append((f"foods-core-{len(shards):03d}.sqlite", core[i : i + shard_rows]))
    for i in range(0, len(rest), shard_rows):
        shards.append((f"foods-brand-{len(shards) - (len(core) + shard_rows - 1) // shard_rows:03d}.sqlite", rest[i : i + shard_rows]))
    return shards


# ---------------------------------------------------------------------------
# 阶段 5：manifest
# ---------------------------------------------------------------------------


def sha256_file(path: str) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def fts_content_sha256(con: sqlite3.Connection) -> str:
    """分片 FTS 索引的**内容**哈希（与文件名/rowid/插入顺序无关）。

    按 (food_id, text, brand, category) 排序后逐行写入，字段间用 \\x01 分隔，
    空值当空串——这样应用侧或第三方可以独立复算。manifest 里的
    `quality.fts_sha256` 由各分片的本摘要按分片名顺序再哈希得到。
    """
    digest = hashlib.sha256()
    cursor = con.execute(
        "SELECT food_id, text, brand, category FROM food_search "
        "ORDER BY food_id, text, brand, category"
    )
    for row in cursor:
        digest.update("\x01".join("" if v is None else str(v) for v in row).encode("utf-8"))
        digest.update(b"\n")
    return digest.hexdigest()


def build_manifest(
    out_dir: str,
    shard_names: list[str],
    catalog_version: str,
    retrieved_at: str,
    report: QualityReport,
) -> dict:
    shards = []
    combined_fts = hashlib.sha256()
    for name in shard_names:
        if not SHARD_FILE_RE.match(name):
            raise ValueError(f"shard file name must match foods-<kind>-NNN.sqlite: {name}")
        path = os.path.join(out_dir, name)
        con = sqlite3.connect(path)
        try:
            rows = con.execute("SELECT COUNT(*) FROM foods").fetchone()[0]
            fts_rows = con.execute("SELECT COUNT(*) FROM food_search").fetchone()[0]
            shard_fts = fts_content_sha256(con)
            # 分片级计数：导入器可以拿它对账「拷进来的行数」与 manifest 申报，
            # 不用信任 ETL 的累加器。
            portion_rows = con.execute("SELECT COUNT(*) FROM portions").fetchone()[0]
            revision_rows = con.execute("SELECT COUNT(*) FROM revisions").fetchone()[0]
            evidence_rows = con.execute("SELECT COUNT(*) FROM evidence").fetchone()[0]
        finally:
            con.close()
        combined_fts.update(f"{name}:{shard_fts}\n".encode("utf-8"))
        kind = name.split("-")[1]
        shards.append(
            {
                "file": name,
                "kind": kind,
                "rows": rows,
                "sha256": sha256_file(path),
                "fts_rows": fts_rows,
                "portion_rows": portion_rows,
                "revision_rows": revision_rows,
                "evidence_rows": evidence_rows,
            }
        )
    # 应用侧 parseCatalogManifest 要求 quality.fts_sha256 是 64 位小写十六进制，
    # 空串会被整包拒绝（导入根本起不来）。
    report.fts_sha256 = combined_fts.hexdigest()

    manifest = {
        "manifest_version": MANIFEST_VERSION,
        "catalog_version": catalog_version,
        "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "transform_version": TRANSFORM_VERSION,
        "sources": [
            {
                "id": SOURCE["id"],
                "name": SOURCE["name"],
                "license": SOURCE["license"],
                "attribution": SOURCE["attribution"],
                "retrieved_at": retrieved_at,
            }
        ],
        "shards": shards,
        "quality": {
            "canonical_rows": report.canonical_rows,
            "alias_rows": report.alias_rows,
            "portion_rows": report.portion_rows,
            "revision_rows": report.revision_rows,
            "evidence_rows": report.evidence_rows,
            "duplicate_ids": report.duplicate_ids,
            "macro_complete_ratio": round(report.macro_complete_ratio, 6),
            "anomaly_count": report.anomaly_count,
            "chinese_name_coverage": round(report.chinese_name_coverage, 6),
            "missing_license_count": report.missing_license_count,
            "fts_index_rows": report.fts_index_rows,
            "fts_sha256": report.fts_sha256,
            "candidate_rows": report.candidate_rows,
            "dropped_incomplete_macros": report.dropped_incomplete_macros,
            "dropped_over_cap": report.dropped_over_cap,
        },
    }
    if report.duplicate_ids != 0 or report.missing_license_count != 0:
        raise ValueError(
            "quality gate failed: duplicate_ids/missing_license_count must be 0"
        )
    if report.macro_complete_ratio < MACRO_COMPLETE_MIN_RATIO:
        raise ValueError(
            "quality gate failed: macro_complete_ratio "
            f"{report.macro_complete_ratio} < {MACRO_COMPLETE_MIN_RATIO} "
            "(发布目录里的条目必须都能参与本地营养计算)"
        )
    # 比值必须在 [0,1]：应用侧 parseCatalogManifest 对此是硬契约，写出 16.93
    # 这种值会让整包被拒，而 ETL 自己的测试不会发现（2.0-1h 实测抓到过）。
    if not 0.0 <= report.macro_complete_ratio <= 1.0:
        raise ValueError(
            f"quality gate failed: macro_complete_ratio "
            f"{report.macro_complete_ratio} 不在 [0,1]（分子分母的取样范围不一致？）"
        )
    with open(os.path.join(out_dir, "catalog.manifest.json"), "w", encoding="utf-8") as fh:
        json.dump(manifest, fh, ensure_ascii=False, indent=2, sort_keys=True)
    return manifest


# ---------------------------------------------------------------------------
# 主流程
# ---------------------------------------------------------------------------


def run_pipeline(
    input_path: str,
    out_dir: str,
    catalog_version: str,
    retrieved_at: str,
    shard_rows: int = 20000,
    limit: int | None = None,
    source_version: str = "",
    max_canonical: int = RELEASE_CANONICAL_CAP,
) -> dict:
    os.makedirs(out_dir, exist_ok=True)
    report = QualityReport()

    raw_count = 0
    normalized: list[FoodRecord] = []
    for raw in iter_raw_records(input_path):
        if limit is not None and raw_count >= limit:
            break
        raw_count += 1
        rec = normalize_record(raw, source_version)
        if rec is not None:
            normalized.append(rec)

    normalized, dropped_by_id, dropped_by_name = deduplicate(normalized)
    # 断言而不是注释：分片主键就是 id，走到这里还残留重复 id 的话，
    # build_shard 会失败（或更糟：manifest 声明的行数与真实内容不符）。
    unique_ids = {rec.id for rec in normalized}
    if len(unique_ids) != len(normalized):
        raise ValueError(
            f"deduplicate() left {len(normalized) - len(unique_ids)} duplicate id(s)"
        )
    report.duplicate_ids = 0

    valid: list[FoodRecord] = []
    report.candidate_rows = len(normalized)
    for rec in normalized:
        # 规范 §2.0-1/§5.2：发布目录里 ≥95% 的条目必须具备完整四项宏量、
        # 可参与本地营养计算，不完整条目只能作搜索参考且不得超过 5%。
        # OFF 全量的四项完整率实测只有 ~80%，放进来就必然越过那 5% 预算，
        # 所以发布物里只保留完整条目；被排除的候选如实计数（不静默丢弃）。
        if rec.state != "verified":
            report.dropped_incomplete_macros += 1
            continue
        if validate_record(rec, report):
            valid.append(rec)

    # 发布分层：超出 cap 的部分按上游流行度截断（同分按 id，保证可复现）。
    if max_canonical and len(valid) > max_canonical:
        # 中文名条目优先保留：OFF 里中文条目总量极少（全量只有 1,932 条），
        # 纯按流行度截断会把它们几乎全切掉（实测发布目录只剩 4 条），而规范
        # §5.2 的 A 层正是「中文基础食物、熟制食品、校园高频菜」。
        valid.sort(
            key=lambda rec: (
                0 if CJK_RE.search(rec.name) else 1,
                -rec.popularity,
                rec.id,
            )
        )
        report.dropped_over_cap = len(valid) - max_canonical
        valid = valid[:max_canonical]
    report.canonical_rows = len(valid)
    # 分子分母都必须在**截断之后**取：截断前数 complete、截断后才取 len(valid)
    # 会写出 16.93 这种比值，应用侧 parseCatalogManifest 要求它在 [0,1] 内，
    # 整包会被拒（2.0-1h 实测抓到过）。
    complete = sum(1 for r in valid if r.state == "verified")
    # 由构造保证为 1.0（上面已过滤掉不完整条目）。真正的把关不在这里，
    # 而在 accept_catalog.py：它逐行读分片、独立断言每条都四项齐全。
    report.macro_complete_ratio = complete / len(valid) if valid else 0.0
    cjk = sum(1 for r in valid if CJK_RE.search(r.name))
    report.chinese_name_coverage = cjk / len(valid) if valid else 0.0

    shards = split_shards(valid, shard_rows)
    shard_names = []
    for name, records in shards:
        build_shard(os.path.join(out_dir, name), records, name, report, retrieved_at)
        shard_names.append(name)

    manifest = build_manifest(out_dir, shard_names, catalog_version, retrieved_at, report)
    # 丢弃计数写 stderr 供 ETL 复盘；不写入 manifest（manifest 只描述发布物）。
    print(
        f"raw={raw_count} normalized={len(normalized) + dropped_by_id + dropped_by_name} "
        f"dropped_by_id={dropped_by_id} dropped_by_name={dropped_by_name} "
        f"candidates={report.candidate_rows} "
        f"dropped_incomplete_macros={report.dropped_incomplete_macros} "
        f"anomalies={report.anomaly_count} "
        f"dropped_over_cap={report.dropped_over_cap} "
        f"canonical={report.canonical_rows} shards={len(shard_names)}",
        file=sys.stderr,
    )
    return manifest
