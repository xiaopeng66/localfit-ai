"""`build_brand_gazetteer.py` 的测试（docs/28 §5.4）。

运行：C:/ProgramData/miniconda3/python.exe test_build_brand_gazetteer.py

两类断言：
  * **合成输入**上的规则行为（停用词、括号、单 token、拉丁但无中文、粘连 token）；
  * **真实产物**上的对账——词表就是从 `assets/seed/foods.v5.json` 生成的，
    所以「Dart 常量就是当前种子按规则算出来的那一份」必须在真实文件上验，
    不是在 fixture 上验（fixture 再全也证明不了发布出去的那份没漂）。
"""

from __future__ import annotations

import json
import os
import pathlib
import re
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import build_brand_gazetteer as gz  # noqa: E402

FAILURES: list[str] = []


def check(label: str, condition: bool, detail: str = "") -> None:
    if condition:
        print(f"  ok   {label}")
    else:
        FAILURES.append(label)
        print(f"  FAIL {label} {detail}")


def test_rules() -> None:
    print("规则（合成输入）")
    names = [
        "7-ELEVEN 7-11御饭团",  # 数字+连字符品牌
        "Nichirei日冷 抹茶冰淇淋",  # 品牌与译名粘在一个 token 里
        "Golden 咸蛋黄饼干",  # 停用词：不收
        "Extra 口香糖",  # 停用词：不收
        "Foo Bar",  # 其余不含汉字：不收（整名是拉丁的，头不是品牌）
        "米饭",  # 单 token：不收
        "(Beretta) Prosciutto Cotto火腿片",  # 括号式交给 splitFoodName 规则 1
        "明治 酸奶",  # 纯中文前缀：**自动表**不收（人工表收，见 food_brands_reviewed）
    ]
    tokens = gz.brand_tokens(names)
    for expected in ("7-ELEVEN", "Nichirei日冷"):
        check(f"收 {expected}", expected in tokens, str(tokens))
    for rejected in ("Golden", "Extra", "Foo", "(Beretta)", "米饭", "明治"):
        check(f"不收 {rejected}", rejected not in tokens, str(tokens))
    check("结果是排序好的", tokens == sorted(tokens))
    check("是列表且无重复", len(tokens) == len(set(tokens)))
    check("停用表就是计划里的 12 个", len(gz.STOPWORDS) == 12, str(gz.STOPWORDS))


def test_real_seed() -> None:
    print("真实种子与已生成文件")
    seed = json.loads(gz.SEED.read_text(encoding="utf-8"))
    names = [item["name"] for item in seed["foods"]]
    tokens = gz.brand_tokens(names)
    dart = gz.OUT.read_text(encoding="utf-8")
    # 逐行按 JSON 解析（token 里可能出现 `"` 或反斜杠，直接正则抠内容会假红）。
    in_file = [
        json.loads(match.group(1))
        for match in re.finditer(r'^  (".*"),$', dart, re.M)
    ]

    # v5：49,464 条 v4 经全量人工审核后删掉 20 条非食物 -> 49,444 条。
    check(f"共 {len(names)} 条种子", len(names) == 49444, str(len(names)))
    check(f"词表 {len(tokens)} 条", len(tokens) > 2000, str(len(tokens)))
    check("Dart 常量与重算结果逐字一致", in_file == tokens, f"{len(in_file)} vs {len(tokens)}")
    check("没有停用词", not (set(tokens) & gz.STOPWORDS))
    check("没有带空白的 token", all(" " not in t and "\t" not in t for t in tokens))
    check("没有括号打头的 token", not [t for t in tokens if t.startswith("(")])
    check(
        "头部记录的 sha256 是当前种子的",
        gz.seed_sha256() in dart,
        gz.seed_sha256(),
    )
    check("头部条数与实际条数一致", f"// 条数：{len(tokens)}" in dart)
    # 词表里每一个 token 都真的能在种子里当首 token 命中（没有幽灵条目）。
    heads = {name.split(" ", 1)[0] for name in names if " " in name}
    check("没有幽灵条目", not (set(tokens) - heads))


def test_check_mode() -> None:
    print("--check 模式")
    check("当前文件是新鲜的", gz.main(["--check"]) == 0)
    original = gz.OUT
    with tempfile.TemporaryDirectory() as tmp:
        stale = pathlib.Path(tmp) / "food_brands.g.dart"
        stale.write_text("// 别的版本\n", encoding="utf-8")
        gz.OUT = stale
        try:
            check("文件过期时返回 1", gz.main(["--check"]) == 1)
        finally:
            gz.OUT = original


def main() -> int:
    test_rules()
    test_real_seed()
    test_check_mode()
    if FAILURES:
        print(f"\n{len(FAILURES)} 项失败：{FAILURES}")
        return 1
    print("\n全部通过")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
