#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""P8b-2：账本 → v5 种子 + 人工品牌词表 + 审核报告（docs/29 §P8b-2）。

输入只有一个：`reports/review_ledger.jsonl`（**唯一权威证据**）。产出三份：

1. `assets/seed/foods.v5.json` —— 把账本里每条的生效裁决落到 v4 种子上：
   `rename` 改名称、`set_brand` 定品牌、`delete` 从库里移除、`edit_nutrition`
   改四个数值；`approve`/`brand_token`/`uncertain` 不改存储字段（品牌 token 只
   影响显示层词表，见第 2 项）。`brand_token` 裁决里的 token 是**人工确认的品牌**，
   与 v4 一样不改 `name` 列（显示层负责剥头，搜索仍按原名）。
2. `lib/utils/food_brands_reviewed.g.dart` —— D13 要求人工品牌词表**独立存放**：
   自动表（`food_brands.g.dart`）「可从种子重算」，人工 token 一旦混进那张表，
   它就再也重算不出来。所以这里生成**另一张**常量表，显示层两份并集使用。
3. `reports/review_report.md` —— 人读的审核报告：覆盖率、逐条核验/族批确认分列
   （族批确认过的不许写成逐条核验）、四类处置计数、存疑清单。

**出口守门**：`--require-coverage 100` —— 未审完**不产出 v5**（App 继续用 v4，
不出现「审了一半的种子」这种中间态）。覆盖率 = 有生效裁决的 id 数 / 种子总数。

**幂等**：同一账本两次生成逐字节相同（`--check` 用来断言这一点，对不上就 exit 1）。

用法：
    python tool/food_seed/apply_review.py                    # 产出三份（需 100%）
    python tool/food_seed/apply_review.py --require-coverage 100
    python tool/food_seed/apply_review.py --check            # 校验三份是否最新
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent


def _find_repo_root(start: Path) -> Path:
    for candidate in (start, *start.parents):
        if (candidate / "pubspec.yaml").is_file():
            return candidate
    raise SystemExit(f"找不到仓库根（没有 pubspec.yaml）：从 {start} 向上找遍了")


ROOT = _find_repo_root(HERE)

sys.path.insert(0, str(HERE / "review"))
import review_lib as rl  # noqa: E402

SEED = ROOT / rl.SEED_REL
LEDGER = ROOT / rl.LEDGER_REL
GAZETTEER = ROOT / rl.GAZETTEER_REL
OUT_SEED = ROOT / "assets" / "seed" / "foods.v5.json"
OUT_REVIEWED = ROOT / "lib" / "utils" / "food_brands_reviewed.g.dart"
OUT_REPORT = ROOT / "reports" / "review_report.md"
OUT_COUNT = ROOT / "lib" / "features" / "nutrition" / "domain" / "food_seed_count.g.dart"


# ---- 裁决 → v5 行 -----------------------------------------------------------


def apply_decisions(order, rows, state):
    """把生效裁决落到种子上，返回（v5 行列表, 计数, 存疑清单）。"""
    out_rows = []
    counts = {key: 0 for key in ("approve", "rename", "set_brand", "brand_token",
                                 "edit_nutrition", "delete", "uncertain")}
    deleted_ids = []
    uncertain_ids = []
    for food_id in order:
        entry = state[food_id]
        decision = entry["decision"]
        counts[decision] += 1
        after = entry["after"] or {}
        row = rows[food_id]

        if decision == "delete":
            deleted_ids.append(food_id)
            continue
        if decision == "uncertain":
            # 存疑：**照原样保留**（不清洗、不删除），但报告里单独列出。
            uncertain_ids.append(food_id)
        # rename / set_brand / edit_nutrition 都改存储字段；approve / brand_token
        # / uncertain 保留原字段。`deleted` 不写进 v5（删除靠移出列表表达）。
        if decision == "rename":
            row = {**row, "name": after["name"]}
        elif decision == "set_brand":
            row = {**row, "brand": after.get("brand")}
        elif decision == "edit_nutrition":
            row = {
                **row,
                "kcal": after["kcal"],
                "protein": after["protein"],
                "carbs": after["carbs"],
                "fat": after["fat"],
            }
        # 显式写 brand 列（哪怕为 null）：v5 里品牌列是审核过的，空就是空。
        row = {**row, "brand": row.get("brand")}
        out_rows.append(row)
    return out_rows, counts, deleted_ids, uncertain_ids


def reviewed_tokens(state, automatic: set[str]):
    """人工并入的品牌 token（账本里所有 `brand_token` 生效裁决的 token）。

    自动表里已有的 token **不重复收**（两份并集才是运行时词表；重复收会让
    「人工表 ⊆ 自动表之外」这条对账变脏）。
    """
    tokens = set()
    for entry in state.values():
        if entry["decision"] == "brand_token":
            token = (entry["after"] or {}).get("brand_token")
            if token:
                tokens.add(token)
    return sorted(tokens - automatic)


# ---- 渲染 -------------------------------------------------------------------


def render_reviewed(tokens, ledger_sha, seed_sha, auto_count):
    lines = [
        "// GENERATED FILE — 由 tool/food_seed/apply_review.py 生成，不要手改。",
        "//",
        "// 人工确认的品牌词表（docs/29 §P8b-2、D13）。与自动表 `food_brands.g.dart`",
        "// **分开存放**：自动表按 `build_brand_gazetteer.py` 的规则从种子重算得出，",
        "// 人工 token 一旦混进去，那张表就再也重算不出来。运行时词表 = 两张表的并集",
        "// （`food_name.dart` 读取）。",
        "//",
        f"// 账本：reports/review_ledger.jsonl（sha256 {ledger_sha}）",
        f"// 审核对象：assets/seed/foods.v4.json（sha256 {seed_sha}）",
        f"// 条数：{len(tokens)}（自动表 {auto_count} 条，两者并集为运行时词表）",
        "library;",
        "",
        "/// 生成该词表的账本 sha256（测试据此校验新鲜度）。",
        "///",
        "/// sha256 是 64 字符，与声明挤在一行会超过 `dart format` 的 80 列 ⇒ 输出成",
        "/// 换行形式，让生成结果直接就是 format-clean（否则 `tool/verify.bat` 的",
        "/// `dart format --set-exit-if-changed lib test` 每次都判红）。",
        "const String kFoodBrandsReviewedLedgerSha256 =",
        f"    '{ledger_sha}';",
        "",
        "/// 人工确认的品牌词表（自动表之外，纯汉字/拉丁/数字混合皆有）。",
        f"const Set<String> kFoodBrandTokensReviewed = <String>{{",
    ]
    for token in tokens:
        lines.append("  " + json.dumps(token, ensure_ascii=False) + ",")
    lines.append("};")
    lines.append("")
    return "\n".join(lines)


def render_count(count, seed_sha):
    grouped = f"{count:,}"
    return "\n".join([
        "// GENERATED FILE — 由 tool/food_seed/apply_review.py 生成，不要手改。",
        "//",
        "// v5 种子的**实际条数**，供「随包 49,4xx 条中文食物」这类文案取数——",
        "// 条数会随人工审核的删除而变，硬编码字面量被咬过一次（docs/29 §P8b-2 末条），",
        "// 所以这里从生成器派生，测试据此校验文案不漂。",
        "//",
        f"// 种子：assets/seed/foods.v5.json（sha256 {seed_sha}）",
        "library;",
        "",
        "/// v5 种子条目数（审核后的定稿条数）。",
        f"const int kFoodSeedV5RowCount = {count};",
        "",
        "/// [kFoodSeedV5RowCount] 的千分位显示串（与设置页文案口径一致）。",
        f"const String kFoodSeedV5RowCountGrouped = '{grouped}';",
        "",
    ])


def render_report(*, stats, counts, seed_total, deleted_ids, uncertain_ids,
                  reviewed_count, auto_count, ledger_sha, seed_sha, rows):
    pct = stats["coverage"]
    lines = [
        "# 食物库全量人工审核报告（docs/29 §P8b）",
        "",
        "> 本文件由 `tool/food_seed/apply_review.py` 从账本生成，不要手改。",
        "",
        "## 结果",
        "",
        f"- 种子规模：**{seed_total:,}** 条（`assets/seed/foods.v4.json`）",
        f"- 已裁决：**{stats['decided']:,}** 条（覆盖率 **{pct}%**）",
        f"  - 逐条核验：**{stats['item_verified']:,}** 条",
        f"  - 族批确认：**{stats['batch_confirmed']:,}** 条",
        f"  - 其中存疑：**{stats['uncertain']:,}** 条（未删未改，原样保留）",
        f"- v5 产出：**{seed_total - len(deleted_ids):,}** 条（删除 {len(deleted_ids)} 条）",
        "",
        "「逐条核验」与「族批确认」分列且互斥——族批确认过的不写成逐条核验。",
        "",
        "## 四类处置计数",
        "",
        "| 裁决 | 条数 |",
        "| --- | --- |",
    ]
    label = {
        "approve": "通过",
        "rename": "改名称",
        "set_brand": "定品牌",
        "brand_token": "并入品牌词表",
        "edit_nutrition": "改营养",
        "delete": "删除",
        "uncertain": "存疑",
    }
    for key in ("approve", "rename", "set_brand", "brand_token", "edit_nutrition",
                "delete", "uncertain"):
        lines.append(f"| {label[key]} | {counts[key]:,} |")
    lines += [
        "",
        "## 品牌词表",
        "",
        f"- 自动表 `food_brands.g.dart`：**{auto_count:,}** 条（可从种子重算）",
        f"- 人工表 `food_brands_reviewed.g.dart`：**{reviewed_count:,}** 条（本轮并入）",
        f"- 运行时词表 = 两表并集（`food_name.dart` 读取）",
        "",
        "## 删除清单",
        "",
    ]
    if deleted_ids:
        lines.append(f"共 {len(deleted_ids)} 条：")
        lines.append("")
        for food_id in deleted_ids:
            lines.append(f"- `{food_id}` — {rows[food_id]['name']}")
    else:
        lines.append("无。")
    lines += ["", "## 存疑清单", ""]
    if uncertain_ids:
        lines.append(f"共 {len(uncertain_ids)} 条（原样保留在 v5 里，未清洗）：")
        lines.append("")
        for food_id in uncertain_ids:
            lines.append(f"- `{food_id}` — {rows[food_id]['name']}")
    else:
        lines.append("无。")
    lines += [
        "",
        "## 证据",
        "",
        f"- 账本：`reports/review_ledger.jsonl`（sha256 `{ledger_sha}`）",
        f"- 种子：`assets/seed/foods.v4.json`（sha256 `{seed_sha}`）",
        "- 账本是唯一权威证据；本报告的每个数都能由账本重放复算。",
        "",
    ]
    return "\n".join(lines)


# ---- 主流程 -----------------------------------------------------------------


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def build(require_coverage: float, ledger_path: Path | None = None):
    """账本 → 三份产物文本（不写盘）。`ledger_path` 缺省用真账本；测试传副本。"""
    order, rows = rl.load_seed(SEED)
    ledger = ledger_path or LEDGER
    ledger_rows = rl.read_ledger(ledger)
    state = rl.replay(ledger_rows)
    stats = rl.compute_stats(order, state)

    if stats["coverage"] < require_coverage or stats["pending"] > 0:
        # 判据用 pending 本身，不用四舍五入后的百分比：49,464 条里少 1 条仍是
        # 「100.0%」，只看百分比会把「差一条」放过去（这正是本包出口条件的
        # 反面——覆盖率对账要求每一条都能追到裁决）。
        raise SystemExit(
            f"覆盖率不足：{stats['coverage']}% < 要求 {require_coverage}%"
            f"（待审 {stats['pending']} 条）。未审完不产出 v5，App 继续用 v4。"
        )

    out_rows, counts, deleted_ids, uncertain_ids = apply_decisions(order, rows, state)

    automatic = rl.load_brand_tokens(GAZETTEER)
    reviewed = reviewed_tokens(state, automatic)

    seed_sha = rl.seed_sha256(SEED)
    ledger_sha = sha256_file(ledger)

    v5 = {"version": 5, "foods": out_rows}
    # 紧凑序列化（不缩进、分隔符无空格）：v5 每行多了 brand 列，缩进写法会把
    # 随包体从 ~10 MB 顶到 ~17 MB。逐字节确定，幂等不受影响。
    seed_text = json.dumps(v5, ensure_ascii=False, separators=(",", ":")) + "\n"
    reviewed_text = render_reviewed(reviewed, ledger_sha, seed_sha, len(automatic))
    count_text = render_count(len(out_rows), seed_sha)
    report_text = render_report(
        stats=stats, counts=counts, seed_total=len(order),
        deleted_ids=deleted_ids, uncertain_ids=uncertain_ids,
        reviewed_count=len(reviewed), auto_count=len(automatic),
        ledger_sha=ledger_sha, seed_sha=seed_sha, rows=rows,
    )
    return seed_text, reviewed_text, count_text, report_text, stats, reviewed, automatic


def main(argv):
    parser = argparse.ArgumentParser(description="账本 → v5 种子 + 人工品牌词表 + 审核报告")
    parser.add_argument("--require-coverage", type=float, default=100.0,
                        help="覆盖率下限（默认 100：未审完不产出 v5）")
    parser.add_argument("--check", action="store_true",
                        help="只校验三份产物是否为最新（对不上 exit 1）")
    args = parser.parse_args(argv)

    seed_text, reviewed_text, count_text, report_text, stats, reviewed, automatic = build(
        args.require_coverage
    )

    outputs = [
        (OUT_SEED, seed_text),
        (OUT_REVIEWED, reviewed_text),
        (OUT_COUNT, count_text),
        (OUT_REPORT, report_text),
    ]

    if args.check:
        stale = []
        for path, text in outputs:
            current = path.read_text(encoding="utf-8") if path.exists() else ""
            if current != text:
                stale.append(path)
        if stale:
            for path in stale:
                print(f"STALE: {path}", file=sys.stderr)
            return 1
        print(f"OK: 三份产物均最新（覆盖率 {stats['coverage']}%，人工 token {len(reviewed)}）")
        return 0

    for path, text in outputs:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8", newline="\n")
        print(f"wrote {path}")
    print(
        f"覆盖率 {stats['coverage']}%（逐条核验 {stats['item_verified']} + "
        f"族批确认 {stats['batch_confirmed']}）；"
        f"人工 token {len(reviewed)}（自动表 {len(automatic)}）"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
