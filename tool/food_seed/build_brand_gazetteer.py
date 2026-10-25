#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Generate the brand gazetteer used by ``splitFoodName`` (docs/28 §5.4).

Source: ``assets/seed/foods.v5.json`` — the 49,464 bundled Chinese foods after
the 2026-10-06 full human review, whose ``brand`` column is empty for every
row: in the upstream data the brand is printed inside ``name``
(``7-ELEVEN 7-11御饭团``, ``Nichirei日冷 抹茶…``). docs/28 N11 asks the card to
show the product name only and move the brand to the card's bottom line, so the
display layer needs a list of tokens that are brands rather than product words.

Rule (deterministic, re-derived by the Dart test ``food_name_test.dart``):

  a first token is a brand word iff
    1. it contains at least one ASCII letter or digit
       (``7-ELEVEN``, ``Nichirei日冷``, ``9度缘`` — the seed glues the brand to
       its Chinese transliteration for 351 tokens), **and**
    2. the remainder of the name contains at least one Han character
       (a fully Latin name keeps its head where it is: the token then is the
       product name, not a brand), **and**
    3. it is not in ``STOPWORDS`` below.

Why ASCII letters/digits only: Chinese brand prefixes (``明治``/``光明``/
``雀巢``/…) have no marker separating them from the product name — the only
usable signal is frequency, and frequency is not enough: at "first token of
>=6 names" the list is 1,451 tokens covering 23,067 rows and already contains
descriptive words (``迷你``, ``理想``, ``特惠``, ``有限会社``, ``日本产``). A
wrong brand label is a false statement on the card, which the project's
honesty rules weigh heavier than a missing split.

Pure-Han prefixes stay out of **this** table by rule. They are no longer a gap:
the 2026-10-06 full human review adjudicated every row, and the brands it
confirmed are emitted by ``apply_review.py`` into the **separate** table
``lib/utils/food_brands_reviewed.g.dart`` (docs/29 D13). ``splitFoodName``
queries the union of the two tables, so ``明治`` and friends do get their head
stripped — from the reviewed table, not from a re-derivable rule.

Output: ``lib/utils/food_brands.g.dart`` — a compile-time ``Set<String>``.
`splitFoodName` is a synchronous pure function called during layout, and
Flutter has no synchronous asset read; a generated Dart constant needs no
async loading, adds no bundled dataset (so no new licence-audit entry in
``test/privacy/privacy_statement_audit_test.dart``) and no pubspec change.
The JSON asset the plan named is not shipped; see the evidence file.

Run: ``python build_brand_gazetteer.py``            (write the Dart file)
     ``python build_brand_gazetteer.py --check``    (exit 1 if stale)
"""
from __future__ import annotations

import hashlib
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
SEED = HERE.parent.parent / "assets" / "seed" / "foods.v5.json"
OUT = HERE.parent.parent / "lib" / "utils" / "food_brands.g.dart"

# docs/28 §5.4 的 12 个描述词：出现频率高，但是描述词不是品牌
# （``Golden 咸蛋黄…`` 的 Golden、``Extra 口香糖`` 的 Extra）。
STOPWORDS = frozenset(
    {
        "Golden",
        "Value",
        "Classic",
        "organic",
        "super",
        "Pure",
        "FINE",
        "raw",
        "MULTI",
        "Fresh",
        "premium",
        "Extra",
    }
)

HAN = re.compile(r"[\u4e00-\u9fff]")
ASCII_WORD = re.compile(r"[A-Za-z0-9]")


def brand_tokens(names: list[str]) -> list[str]:
    """Applies the documented rule to ``names``; returns a sorted token list."""
    found = set()
    for name in names:
        head, sep, rest = name.partition(" ")
        if not sep or not rest:
            continue
        if not ASCII_WORD.search(head):
            continue
        if not HAN.search(rest):
            continue
        if head in STOPWORDS:
            continue
        # 括号式名字（`(Beretta) Prosciutto…`）由 splitFoodName 的规则 1 处理，
        # 词表里再留一条带括号的 token 是永不命中的死数据。
        if head.startswith("("):
            continue
        found.add(head)
    return sorted(found)


def seed_sha256(path: Path = SEED) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def render(tokens: list[str], sha256: str) -> str:
    lines = [
        "// GENERATED FILE — 由 tool/food_seed/build_brand_gazetteer.py 生成，不要手改。",
        "//",
        "// 品牌词表（docs/28 §5.4）：`splitFoodName` 用它把食物名首部的品牌词挪到",
        "// 卡片底行。规则与理由见生成脚本的 docstring；`test/utils/food_name_test.dart`",
        "// 会在真实种子上按同一条规则重算一遍并与此常量逐字比较（改种子不重生成即红）。",
        "//",
        f"// 来源：assets/seed/foods.v5.json（sha256 {sha256}）",
        f"// 条数：{len(tokens)}",
        "library;",
        "",
        "/// 生成该词表的种子文件 sha256（`test/utils/food_name_test.dart` 校验）。",
        "///",
        "/// sha256 是 64 字符，与声明挤在一行会超过 `dart format` 的 80 列 ⇒ 输出成",
        "/// 换行形式，让生成结果直接就是 format-clean（否则 `tool/verify.bat` 的",
        "/// `dart format --set-exit-if-changed lib test` 每次都判红）。",
        "const String kFoodBrandSeedSha256 =",
        f"    '{sha256}';",
        "",
        "/// 品牌词表（拉丁/数字打头、其余含汉字、且不在 12 个描述词停用表里）。",
        f"const Set<String> kFoodBrandTokens = <String>{{",
    ]
    for token in tokens:
        lines.append("  " + json.dumps(token, ensure_ascii=False) + ",")
    lines.append("};")
    lines.append("")
    return "\n".join(lines)


def main(argv: list[str]) -> int:
    check = "--check" in argv
    seed = json.loads(SEED.read_text(encoding="utf-8"))
    names = [item["name"] for item in seed["foods"]]
    tokens = brand_tokens(names)
    sha256 = seed_sha256()
    rendered = render(tokens, sha256)

    if check:
        current = OUT.read_text(encoding="utf-8") if OUT.exists() else ""
        if current != rendered:
            print(
                f"STALE: {OUT} 与种子/规则不一致（期望 {len(tokens)} 条）",
                file=sys.stderr,
            )
            return 1
        print(f"OK: {OUT} 与 {SEED.name}（sha256 {sha256[:12]}）一致，{len(tokens)} 条")
        return 0

    OUT.write_text(rendered, encoding="utf-8")
    print(f"wrote {OUT} — {len(tokens)} tokens from {len(names)} names")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
