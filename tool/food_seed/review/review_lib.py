#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""食物库全量人工审核（docs/29 §P8b-1）的**核心逻辑**——不碰网络、不碰 UI。

三份事实：

* **种子**：`assets/seed/foods.v4.json`（49,464 条，审核对象）；
* **上屏预览**：`reports/display_preview.jsonl`，由 App 的同一批 Dart 函数离线
  产出（`tool/food_seed/review/export_display_preview.dart`）。审核台显示「这条
  在卡上长这样」读的就是它——**这里不许重算拆分规则**，两份实现必然漂移，那样
  人审的就是一张并不存在的卡片；
* **账本**：`reports/review_ledger.jsonl`，**追加式、一行一条**，是「人工审核
  到底审了什么」唯一能点名的来源，也是 P8b-2 生成 v5 的唯一输入。

判据（docs/29 的出口条件）：覆盖率对账 100% = v5 每条 id 都能追到一条账本裁决；
报告必须**如实分列**「逐条核验」与「族批确认」——族批确认过的不许写成逐条核验。

本模块只依赖标准库，可独立单测（`test_review.py`）。
"""
from __future__ import annotations

import json
import re
import unicodedata
from pathlib import Path

# ---- 路径（相对仓库根；调用点可用 CLI 覆盖） --------------------------------

SEED_REL = "assets/seed/foods.v4.json"
PREVIEW_REL = "reports/display_preview.jsonl"
LEDGER_REL = "reports/review_ledger.jsonl"
CURSOR_REL = "reports/review_cursor.json"
GAZETTEER_REL = "lib/utils/food_brands.g.dart"

LEDGER_VERSION = 1
CURSOR_VERSION = 1

# ---- 八种裁决 ---------------------------------------------------------------
#
# 键盘八动作（docs/29 §P8b-1 第 2 条）与账本里的 `decision` 值一一对应。
DECISIONS = (
    "approve",  # 通过
    "rename",  # 改名称
    "set_brand",  # 定品牌
    "brand_token",  # 并入品牌词表
    "edit_nutrition",  # 改营养
    "delete",  # 删除
    "uncertain",  # 存疑
    "revert",  # 撤回
)

#: 会改变该 id 的存储字段的裁决（`revert` 单独处理）。
FIELD_DECISIONS = ("approve", "rename", "set_brand", "edit_nutrition", "delete", "uncertain")

#: 审核台里显示的字段名（账本 `before`/`after` 的键）。
FIELD_KEYS = ("name", "brand", "kcal", "protein", "carbs", "fat", "deleted")

#: 「改营养必须填来源」的白名单外默认值（不许无来源地改数字）。
NUTRITION_SOURCE_FALLBACK = "人工估值"
#: 人工裁决的营养值来源（`source` 字段取值）。
NUTRITION_SOURCES = ("人工估值", "包装标签", "上游标签页", "权威成分表")


class LedgerError(ValueError):
    """账本行不合法（拒绝写入，不许留半条）。"""


# ---- 载入 -------------------------------------------------------------------


def repo_root(start: Path | str | None = None) -> Path:
    """向上找到含 `pubspec.yaml` 的目录（从当前目录或 `start` 起）。"""
    here = Path(start).resolve() if start else Path.cwd().resolve()
    for candidate in (here, *here.parents):
        if (candidate / "pubspec.yaml").is_file():
            return candidate
    raise SystemExit(f"找不到仓库根（没有 pubspec.yaml）：从 {here} 向上找遍了")


def load_seed(path: Path) -> tuple[list[str], dict[str, dict]]:
    """读种子，返回（id 顺序, id → 原始行）。顺序 = 文件顺序，审核队列用它稳定排序。"""
    document = json.loads(path.read_text(encoding="utf-8"))
    foods = document["foods"]
    order = [row["id"] for row in foods]
    if len(order) != len(set(order)):
        raise LedgerError("种子里有重复 id —— 审核以 id 为主键，先修数据")
    return order, {row["id"]: row for row in foods}


def load_preview(path: Path) -> tuple[dict, dict[str, dict]]:
    """读上屏预览。第一行是 `_meta`（记录种子 sha256 与产出用的函数名）。"""
    meta: dict = {}
    previews: dict[str, dict] = {}
    with path.open(encoding="utf-8") as handle:
        for index, line in enumerate(handle):
            line = line.strip()
            if not line:
                continue
            row = json.loads(line)
            if index == 0 and "_meta" in row:
                meta = row["_meta"]
                continue
            previews[row["id"]] = row
    return meta, previews


_IN_DART_SET = re.compile(r'^  (".*"),$', re.M)


def load_brand_tokens(path: Path) -> set[str]:
    """读自动品牌词表（`lib/utils/food_brands.g.dart` 的 `kFoodBrandTokens`）。

    逐行按 JSON 解析：token 里可能出现 `"` 或反斜杠，直接正则抠内容会假红
    （`test_build_brand_gazetteer.py` 同一条理由）。
    """
    source = path.read_text(encoding="utf-8")
    body = source.split("const Set<String> kFoodBrandTokens", 1)[-1]
    return {json.loads(match.group(1)) for match in _IN_DART_SET.finditer(body)}


def seed_sha256(path: Path) -> str:
    import hashlib

    return hashlib.sha256(path.read_bytes()).hexdigest()


# ---- 账本 -------------------------------------------------------------------


def now_iso() -> str:
    from datetime import datetime, timezone

    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def canonical_fields(row: dict) -> dict:
    """一条种子行在账本里的字段快照（`before`/`after` 的形态）。

    「通过」也记录一份快照：账本因此能回答「当时审的是哪几个值」——种子日后改了
    而这一条被追认过，快照就是能对账的凭据。
    """
    return {
        "name": row["name"],
        "brand": row.get("brand"),
        "kcal": row["kcal"],
        "protein": row["protein"],
        "carbs": row["carbs"],
        "fat": row["fat"],
        "deleted": False,
    }


def validate_row(row: dict) -> None:
    """写入前校验——账本是唯一权威证据，半条不合法就整条拒绝。"""
    required = ("id", "decision", "before", "after", "source", "review_mode", "ts")
    missing = [key for key in required if key not in row]
    if missing:
        raise LedgerError(f"账本行缺字段：{missing}")
    if row["decision"] not in DECISIONS:
        raise LedgerError(f"未知裁决：{row['decision']!r}（合法值 {DECISIONS}）")
    if row["review_mode"] not in ("item", "batch"):
        raise LedgerError(f"review_mode 只能是 item/batch，收到 {row['review_mode']!r}")
    if not isinstance(row["id"], str) or not row["id"]:
        raise LedgerError("id 必须是非空字符串")
    if row["decision"] == "edit_nutrition":
        source = (row.get("source") or "").strip()
        if not source:
            raise LedgerError(
                "改营养必须填 source（docs/29 §P8b-1：不许无来源地改数字）"
            )
    if row["decision"] == "brand_token":
        token = (row.get("after") or {}).get("brand_token")
        if not isinstance(token, str) or not token.strip():
            raise LedgerError("brand_token 裁决必须带 after.brand_token")


def append_ledger(path: Path, rows: list[dict]) -> None:
    """追加写入（一行一条，UTF-8 不转义），写完立即 flush。

    追加式：文件只增不改，任何「撤销」都是**再加一行** `revert`。这样账本能重放，
    也能看出「先审成 X、后来撤销改回 Y」这类过程，不会被最后一次写覆盖掉历史。
    """
    for row in rows:
        validate_row(row)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8", newline="\n") as handle:
        for row in rows:
            handle.write(json.dumps(row, ensure_ascii=False) + "\n")
        handle.flush()


def read_ledger(path: Path) -> list[dict]:
    if not path.exists():
        return []
    rows = []
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = line.strip()
        if not line:
            continue
        try:
            row = json.loads(line)
        except json.JSONDecodeError as error:  # 账本坏了必须立刻知道
            raise LedgerError(f"{path}:{number} 不是合法 JSON：{error}") from error
        validate_row(row)
        rows.append(row)
    return rows


def replay(rows: list[dict]) -> dict[str, dict]:
    """重放账本 → 每个 id 的**生效**状态。

    每个 id 维护一个裁决栈：普通裁决压栈，`revert` 弹掉该 id 最近一条**未被弹过**
    的裁决（一次撤回 = 撤销最近一次）。栈空 ⇒ 该 id 回到「待审」。

    返回 `{id: {"decision":…, "after":…, "review_mode":…, "source":…, "ts":…,
    "reverted": n}}`；`reverted` = 被撤回压掉的条数（报告如实计数）。
    """
    stacks: dict[str, list[dict]] = {}
    reverted_count: dict[str, int] = {}
    for row in rows:
        if row["decision"] == "revert":
            stack = stacks.get(row["id"])
            if stack:
                stack.pop()
                reverted_count[row["id"]] = reverted_count.get(row["id"], 0) + 1
            continue
        stacks.setdefault(row["id"], []).append(row)

    state: dict[str, dict] = {}
    for food_id, stack in stacks.items():
        if not stack:
            continue
        top = stack[-1]
        state[food_id] = {
            "decision": top["decision"],
            "after": top["after"],
            "review_mode": top["review_mode"],
            "source": top.get("source"),
            "ts": top["ts"],
            "reverted": reverted_count.get(food_id, 0),
        }
    return state


def compute_stats(order: list[str], state: dict[str, dict]) -> dict:
    """五档进度（docs/29 §P8b-1 第 4 条）——**进度是唯一的完成度声明**。

    ``已裁决 = 逐条核验 + 族批确认``（互斥且穷尽）；``存疑`` 是已裁决的一个子集，
    单独列出但不额外计入分母。「族批确认」不许写成「逐条核验」。
    """
    item = 0
    batch = 0
    uncertain = 0
    for food_id in order:
        entry = state.get(food_id)
        if entry is None:
            continue
        if entry["review_mode"] == "item":
            item += 1
        else:
            batch += 1
        if entry["decision"] == "uncertain":
            uncertain += 1
    decided = item + batch
    total = len(order)
    return {
        "total": total,
        "decided": decided,
        "item_verified": item,
        "batch_confirmed": batch,
        "pending": total - decided,
        "uncertain": uncertain,
        "coverage": round(decided / total * 100, 2) if total else 0.0,
    }


def format_stats(stats: dict, scope: dict | None = None) -> str:
    """给人看的五档进度（`--stats`）。

    `scope` 是「只看某个标记」时的子集计数（`{"flag": …, "groups": …, "rows": …,
    "decided": …}`）——**全库进度才是完成度声明**，子集只是当前这一轮的工作面，
    所以两个数分开写、谁也不冒充谁。
    """
    text = (
        f"已裁决 {stats['decided']} / {stats['total']}"
        f"（{stats['coverage']}%）"
        f" = 逐条核验 {stats['item_verified']} + 族批确认 {stats['batch_confirmed']}\n"
        f"待审 {stats['pending']}｜其中存疑 {stats['uncertain']}"
    )
    if scope:
        text += (
            f"\n（当前工作面 --only {scope['flag']}：{scope['rows']} 条 / "
            f"{scope['groups']} 组，其中已裁决 {scope['decided']}）"
        )
    return text


# ---- 断点续审 ---------------------------------------------------------------


def write_cursor(
    path: Path,
    state: dict[str, dict],
    last_index: int = 0,
    *,
    seed_sha256_value: str = "",
) -> dict:
    """把生效状态落成 `review_cursor.json`（**派生自账本**，不是第二份事实）。

    写了它只为「打开就能接着审」；任何时候它以账本为准——载入时若发现两者不一致
    就按账本重写（见 `load_cursor` 的返回值）。
    """
    decided = {
        food_id: {
            "decision": entry["decision"],
            "review_mode": entry["review_mode"],
            "ts": entry["ts"],
        }
        for food_id, entry in sorted(state.items())
    }
    document = {
        "version": CURSOR_VERSION,
        "seed_sha256": seed_sha256_value,
        "last_index": last_index,
        "updated_at": now_iso(),
        "decided": decided,
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(document, ensure_ascii=False, indent=1, sort_keys=True) + "\n",
        encoding="utf-8",
        newline="\n",
    )
    return document


def read_cursor(path: Path) -> dict:
    if not path.exists():
        return {}
    return json.loads(path.read_text(encoding="utf-8"))


def cursor_matches(cursor: dict, state: dict[str, dict], seed_sha: str) -> bool:
    """游标与账本是否一致（不一致 ⇒ 以账本为准重写，不许两份事实打架）。"""
    if cursor.get("seed_sha256") != seed_sha:
        return False
    decided = cursor.get("decided") or {}
    if set(decided) != set(state):
        return False
    for food_id, entry in state.items():
        if decided[food_id].get("decision") != entry["decision"]:
            return False
        if decided[food_id].get("review_mode") != entry["review_mode"]:
            return False
    return True


# ---- 可疑队列（**只用于排序与预填，不是结论**） ------------------------------

HAN = re.compile(r"[\u4e00-\u9fff]")
ASCII_WORD = re.compile(r"[A-Za-z0-9]")
NUMBER_RUN = re.compile(r"[0-9]{2,}")

#: 队列排序用的严重度（数字越小越靠前）。同一个条目命中多条时取最小的。
FLAG_RANK = {
    "near_duplicate": 0,
    "brand_unresolved": 1,
    "duplicate_token": 2,
    "slash_or_number_run": 3,
    "kcal_macro_mismatch": 4,
    "nutrient_zero_or_missing": 5,
    "head_ascii": 6,
    "han_head_frequent": 7,
}

#: 人读的标记说明（审核台显示「为什么它在队里」）。
FLAG_LABEL = {
    "near_duplicate": "近似重名（去掉分隔符后同名）",
    "brand_unresolved": "首 token 像品牌但自动规则没拆",
    "duplicate_token": "名称里有重复的词",
    "slash_or_number_run": "名称含 / 或连续数字",
    "kcal_macro_mismatch": "热量与宏量不自洽（>±25%）",
    "nutrient_zero_or_missing": "营养四项有空或为 0",
    "head_ascii": "首 token 含 ASCII",
    "han_head_frequent": "纯汉字高频首词（可能是品牌）",
}

#: 纯汉字高频首词的阈值：出现次数 ≥ 该值才排队（不是结论，只是排队）。
HAN_HEAD_MIN_ROWS = 6

#: kcal 与 4/4/9 的允许偏差。
KCAL_TOLERANCE = 0.25


def head_token(name: str) -> str | None:
    """名称的第一个空格段（没空格则 None）。"""
    head, sep, rest = name.partition(" ")
    return head if sep and rest else None


def normalize_for_duplicate(name: str) -> str:
    """近似重名的归一：去掉空白与常见分隔符、全角转半角、统一大小写。"""
    folded = unicodedata.normalize("NFKC", name).casefold()
    return re.sub(r"[\s\-_/（）()·、,，.。]+", "", folded)


def compute_flags(
    order: list[str],
    rows: dict[str, dict],
    brand_tokens: set[str],
    extra_brand_tokens: set[str] | None = None,
) -> dict[str, list[str]]:
    """按 docs/29 §P8b-1 第 3 条给每条打「可疑」标记。

    **这些标记只决定排序与预填**（把可疑的排到前面），不是结论：机器判不出
    「明治 是品牌、迷你 不是」，那正是全量人工审核的意义。`extra_brand_tokens`
    是本次审核已裁决并入词表的 token（账本里 `brand_token` 的那些）——并进去之后
    相应条目就不再是「没拆」。
    """
    known = set(brand_tokens) | set(extra_brand_tokens or ())
    flags: dict[str, list[str]] = {food_id: [] for food_id in order}

    # 近似重名：归一后同名（只标全部成员，谁删谁留由人判）。
    by_normalized: dict[str, list[str]] = {}
    for food_id in order:
        by_normalized.setdefault(normalize_for_duplicate(rows[food_id]["name"]), []).append(
            food_id
        )
    for group in by_normalized.values():
        if len(group) > 1:
            for food_id in group:
                flags[food_id].append("near_duplicate")

    # 纯汉字高频首词：出现次数 ≥ 阈值的收集一次（排队用）。
    han_heads: dict[str, int] = {}
    for food_id in order:
        head = head_token(rows[food_id]["name"])
        if head and HAN.search(head) and not ASCII_WORD.search(head):
            han_heads[head] = han_heads.get(head, 0) + 1

    for food_id in order:
        row = rows[food_id]
        name = row["name"]
        head = head_token(name)

        if head and ASCII_WORD.search(head) and HAN.search(name.partition(" ")[2]):
            if head not in known:
                flags[food_id].append("brand_unresolved")
            flags[food_id].append("head_ascii")
        if head and han_heads.get(head, 0) >= HAN_HEAD_MIN_ROWS:
            flags[food_id].append("han_head_frequent")

        parts = name.split(" ")
        if len(parts) != len(set(parts)):
            flags[food_id].append("duplicate_token")
        if "/" in name or NUMBER_RUN.search(name):
            flags[food_id].append("slash_or_number_run")

        if any(not row.get(key) for key in ("kcal", "protein", "carbs", "fat")):
            flags[food_id].append("nutrient_zero_or_missing")
        kcal = row["kcal"]
        approx = 4 * row["protein"] + 4 * row["carbs"] + 9 * row["fat"]
        if kcal > 0 and abs(approx - kcal) / kcal > KCAL_TOLERANCE:
            flags[food_id].append("kcal_macro_mismatch")

    return flags


def flag_rank(flags: list[str]) -> int:
    return min((FLAG_RANK[f] for f in flags), default=len(FLAG_RANK))


def build_queue(
    order: list[str],
    rows: dict[str, dict],
    flags: dict[str, list[str]],
    state: dict[str, dict],
    *,
    only: str | None = None,
) -> list[list[str]]:
    """待审队列：**成组**返回，组内是同一关键词下的条目。

    - 命中最靠前标记的条目排前面（同分保持种子顺序 ⇒ 队列稳定、可续）；
    - 有首 token 的按首 token 成组（族批的原语：`明治` 的 288 条一次确认）；
    - 组内第一个元素是「代表条目」，其余是组员。

    `only` 过滤到某一个标记（`--only brand_unresolved` 之类），便于专项清理。
    已裁决的条目不再入队。
    """
    pending = [food_id for food_id in order if food_id not in state]
    if only:
        pending = [food_id for food_id in pending if only in flags.get(food_id, ())]

    index = {food_id: position for position, food_id in enumerate(order)}
    groups: dict[str, list[str]] = {}
    order_of_groups: list[str] = []
    for food_id in pending:
        head = head_token(rows[food_id]["name"]) or food_id
        key = head
        if key not in groups:
            groups[key] = []
            order_of_groups.append(key)
        groups[key].append(food_id)

    def group_rank(key: str) -> tuple[int, int]:
        members = groups[key]
        best = flag_rank(flags.get(members[0], []))
        best = min(best, flag_rank(flags.get(key, []))) if key in flags else best
        return (best, index[members[0]])

    order_of_groups.sort(key=group_rank)
    return [groups[key] for key in order_of_groups]


def group_is_batchable(members: list[str], rows: dict[str, dict]) -> bool:
    """一组是不是「同前缀」的族批（全部成员共享同一个首 token）。"""
    if len(members) < 2:
        return False
    heads = {head_token(rows[food_id]["name"]) for food_id in members}
    return len(heads) == 1 and None not in heads
