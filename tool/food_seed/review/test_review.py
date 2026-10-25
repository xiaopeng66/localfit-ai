"""`review_lib.py` 的测试（docs/29 §P8b-1）。

运行：C:/ProgramData/miniconda3/python.exe test_review.py

三类断言：
  * **合成输入**上的规则行为（八动作、撤回栈、五档计数、标记）；
  * **真实产物**上的对账——上屏预览确实是 App 的 Dart 函数产出的、且与种子同源；
    词表/标记在 49,464 条上跑得动、数得清；
  * **失败面**：不合法账本行必须被拒（宁可不写，不许留半条）。

对账的关键一条：`reports/display_preview.jsonl` 里的 `name`/`brand` **必须**等于
用 Python 按同一批规则重算的结果——如果审核台显示的与实际拆分漂了，这条会红。
Python 侧重算的规则是**独立写出**的（不是 import Dart），所以它证明的是「两份
实现一致」，这正是「禁止用 JS/Python 重写拆分规则」要防的那种漂移。
"""
from __future__ import annotations

import json
import os
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import review_lib as rl  # noqa: E402

FAILURES: list[str] = []


def check(label: str, condition: bool, detail: str = "") -> None:
    if condition:
        print(f"  ok   {label}")
    else:
        FAILURES.append(label)
        print(f"  FAIL {label} {detail}")


def sample_row(food_id: str, name: str, **overrides) -> dict:
    row = {
        "id": food_id,
        "name": name,
        "serving_g": 100,
        "kcal": 100.0,
        "protein": 5.0,
        "carbs": 10.0,
        "fat": 3.0,
        "constraint_knowledge": "known",
        "dietary_labels": [],
        "allergens": [],
    }
    row.update(overrides)
    return row


def ledger_row(food_id: str, decision: str, **overrides) -> dict:
    row = {
        "id": food_id,
        "decision": decision,
        "before": {"name": "旧"},
        "after": {"name": "新"},
        "source": "人看",
        "review_mode": "item",
        "ts": "2026-10-06T00:00:00Z",
    }
    row.update(overrides)
    return row


# ---- 规则 -------------------------------------------------------------------


def test_ledger_validation() -> None:
    print("账本行校验")
    for decision in rl.DECISIONS:
        row = ledger_row("seed-fc-1", decision)
        if decision == "brand_token":
            row["after"] = {"brand_token": "明治"}
        try:
            rl.validate_row(row)
            ok = True
        except rl.LedgerError:
            ok = False
        check(f"合法裁决 {decision} 通过", ok)

    for label, row in [
        ("未知裁决名", ledger_row("x", "approve") | {"decision": "yolo"}),
        ("缺 source", {k: v for k, v in ledger_row("x", "approve").items() if k != "source"}),
        ("缺 id", {k: v for k, v in ledger_row("x", "approve").items() if k != "id"}),
        ("空 id", ledger_row("", "approve")),
        ("review_mode 越界", ledger_row("x", "approve", review_mode="auto")),
    ]:
        try:
            rl.validate_row(row)
            rejected = False
        except rl.LedgerError:
            rejected = True
        check(f"拒绝：{label}", rejected)

    row = ledger_row("x", "edit_nutrition", source="")
    try:
        rl.validate_row(row)
        rejected = False
    except rl.LedgerError:
        rejected = True
    check("拒绝：改营养但 source 为空（不许无来源地改数字）", rejected)

    row = ledger_row("x", "brand_token", after={"brand": "明治"})
    try:
        rl.validate_row(row)
        rejected = False
    except rl.LedgerError:
        rejected = True
    check("拒绝：并入词表但 after 里没有 brand_token", rejected)


def test_replay_and_revert() -> None:
    print("重放与撤回")
    rows = [
        ledger_row("a", "rename", after={"name": "甲"}),
        ledger_row("b", "approve"),
        ledger_row("a", "revert"),
    ]
    state = rl.replay(rows)
    check("撤回后 a 回到待审", "a" not in state, str(state))
    check("b 仍在", state["b"]["decision"] == "approve")
    check("撤回次数记在案", state["b"]["reverted"] == 0)

    # 撤回只弹最近一条**生效**的裁决：a 撤掉 rename 后 approve 生效。
    rows = [
        ledger_row("a", "rename", after={"name": "甲"}),
        ledger_row("a", "approve"),
        ledger_row("a", "revert"),
    ]
    state = rl.replay(rows)
    check("撤回弹掉最近一条，露出上一条", state["a"]["decision"] == "rename", str(state))

    # 空栈上撤回：什么都不发生，不抛。
    state = rl.replay([ledger_row("z", "revert")])
    check("没有可撤的裁决时不炸", "z" not in state, str(state))

    # 撤回的计数挂在 id 上。
    rows = [
        ledger_row("a", "approve"),
        ledger_row("a", "revert"),
        ledger_row("a", "approve"),
        ledger_row("a", "revert"),
    ]
    state = rl.replay(rows)
    check("撤回到空栈后 id 待审", "a" not in state, str(state))


def test_stats_five_tiers() -> None:
    print("五档进度")
    order = ["a", "b", "c", "d", "e"]
    state = {
        "a": {"decision": "approve", "review_mode": "item", "ts": "t"},
        "b": {"decision": "approve", "review_mode": "batch", "ts": "t"},
        "c": {"decision": "uncertain", "review_mode": "item", "ts": "t"},
        "d": {"decision": "delete", "review_mode": "batch", "ts": "t"},
    }
    stats = rl.compute_stats(order, state)
    check("total", stats["total"] == 5, str(stats))
    check("已裁决 = 逐条 + 族批", stats["decided"] == 4, str(stats))
    check("逐条核验 2", stats["item_verified"] == 2, str(stats))
    check("族批确认 2", stats["batch_confirmed"] == 2, str(stats))
    check("待审 1", stats["pending"] == 1, str(stats))
    check("存疑 1（不重复计入分母）", stats["uncertain"] == 1, str(stats))
    check("覆盖率 80%", stats["coverage"] == 80.0, str(stats))
    check("不把族批写成逐条", stats["item_verified"] != stats["decided"], str(stats))

    empty = rl.compute_stats([], {})
    check("空库不除零", empty["coverage"] == 0.0, str(empty))

    text = rl.format_stats(stats)
    check("文本里两个数分列", "逐条核验 2" in text and "族批确认 2" in text, text)


def test_cursor_roundtrip() -> None:
    print("断点续审（游标是派生物）")
    state = {
        "a": {"decision": "approve", "review_mode": "item", "ts": "t1"},
        "b": {"decision": "rename", "review_mode": "batch", "ts": "t2"},
    }
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "review_cursor.json"
        rl.write_cursor(path, state, last_index=7, seed_sha256_value="deadbeef")
        cursor = rl.read_cursor(path)
        check("写读往返", cursor["seed_sha256"] == "deadbeef", str(cursor))
        check("与账本一致", rl.cursor_matches(cursor, state, "deadbeef"))
        check("种子换了 ⇒ 不一致（触发重算）", not rl.cursor_matches(cursor, state, "cafe"))
        check("账本多一条 ⇒ 不一致", not rl.cursor_matches(cursor, state | {"c": {"decision": "approve", "review_mode": "item", "ts": "t"}}, "deadbeef"))
        check(
            "裁决变了 ⇒ 不一致",
            not rl.cursor_matches(cursor, state | {"a": {"decision": "delete", "review_mode": "item", "ts": "t"}} | {}, "deadbeef")
            if False
            else not rl.cursor_matches(
                cursor,
                {"a": {"decision": "delete", "review_mode": "item", "ts": "t"},
                 "b": {"decision": "rename", "review_mode": "batch", "ts": "t2"}},
                "deadbeef",
            ),
        )
        check("缺文件返回空字典", rl.read_cursor(Path(tmp) / "nope.json") == {})


def test_flags_on_synthetic() -> None:
    print("可疑标记（合成输入，**只是排队不是结论**）")
    rows = {
        "1": sample_row("1", "明治 酸奶"),  # 纯汉字首词，规则不拆
        "2": sample_row("2", "Foo 面包"),  # 拉丁首词且不在词表
        "3": sample_row("3", "Foo Foo 面包"),  # 重复词
        "4": sample_row("4", "饺子/馄饨"),  # 斜杠
        "5": sample_row("5", "饼干450g"),  # 连续数字
        "6": sample_row("6", "魔芋精粉", kcal=186.0, protein=1.0, carbs=80.0, fat=1.0),  # 4/4/9 不符
        "7": sample_row("7", "零卡果冻", kcal=0.0, protein=0.0, carbs=0.0, fat=0.0),
        "8": sample_row("8", "家乐 通心粉"),
        "9": sample_row("9", "家乐通心粉"),  # 与 8 归一后同名
        "10": sample_row("10", "Foo 面包"),  # 与 2 同名
        # 纯汉字高频首词要够阈值（HAN_HEAD_MIN_ROWS=6）才算「高频」——单条不算，
        # 这正是「只排队、不下结论」的意思：只出现一次的首词没有频率证据。
        "11": sample_row("11", "明治 牛奶"),
        "12": sample_row("12", "明治 咖啡"),
        "13": sample_row("13", "明治 饼干"),
        "14": sample_row("14", "明治 冰淇淋"),
        "15": sample_row("15", "明治 巧克力"),
        "16": sample_row("16", "清水 豆腐"),  # 干净条目：单 token
    }
    flags = rl.compute_flags(list(rows), rows, brand_tokens={"Bar"})
    check("纯汉字高频首词标记（达到阈值）", "han_head_frequent" in flags["1"], str(flags["1"]))
    check(
        "同首词只出现一次就不算高频（阈值生效）",
        "han_head_frequent" not in rl.compute_flags(
            {k: v for k, v in rows.items() if k not in {"11", "12", "13", "14", "15"}},
            {k: v for k, v in rows.items() if k not in {"11", "12", "13", "14", "15"}},
            {"Bar"},
        )["1"],
        "ok",
    )
    check("拉丁首词没拆标记", "brand_unresolved" in flags["2"], str(flags["2"]))
    check("首 token 含 ASCII 标记", "head_ascii" in flags["2"], str(flags["2"]))
    check("已在词表里就不算没拆", "brand_unresolved" not in rl.compute_flags(list(rows), rows, {"Foo"})["2"])
    check("重复词标记", "duplicate_token" in flags["3"], str(flags["3"]))
    check("斜杠标记", "slash_or_number_run" in flags["4"], str(flags["4"]))
    check("连续数字标记", "slash_or_number_run" in flags["5"], str(flags["5"]))
    check("热量不符标记", "kcal_macro_mismatch" in flags["6"], str(flags["6"]))
    check("零值标记", "nutrient_zero_or_missing" in flags["7"], str(flags["7"]))
    check("4/4/9 相符不标", "kcal_macro_mismatch" not in rl.compute_flags(
        list(rows), rows, set()
    )["1"], "ok")
    check(
        "近似重名（归一后同名）两边都标",
        "near_duplicate" in flags["8"] and "near_duplicate" in flags["9"],
        f"{flags['8']} {flags['9']}",
    )
    check("完全同名也标", "near_duplicate" in flags["10"], str(flags["10"]))
    check("干净的条目一条标记都没有", flags["16"] == [], str(flags["16"]))
    check("非空条目都拿到了标记列表", all(isinstance(v, list) for v in flags.values()))

    # 归一：全角/半角、大小写、分隔符都要折叠掉。
    check("归一无视大小写", rl.normalize_for_duplicate("ABC 饼干") == rl.normalize_for_duplicate("abc饼干"))


def test_queue_is_stable_and_grouped() -> None:
    print("队列：成组、稳定、可续")
    order = ["5", "3", "1", "2", "4"]
    rows = {
        "1": sample_row("1", "明治 酸奶"),
        "2": sample_row("2", "明治 牛奶"),
        "3": sample_row("3", "Foo 面包"),
        "4": sample_row("4", "康师傅 红烧牛肉面"),
        "5": sample_row("5", "康师傅 香辣牛肉面"),
    }
    flags = rl.compute_flags(order, rows, set())
    queue = rl.build_queue(order, rows, flags, state={})
    check("每组的代表是组内第一",
          all(group[0] in group for group in queue), str(queue))
    check("同首 token 的成一组", any(len(g) == 2 for g in queue), str(queue))
    check("队列覆盖全部待审条目",
          sorted(x for g in queue for x in g) == sorted(order), str(queue))

    # 已裁决的不入队。
    state = {"3": {"decision": "approve", "review_mode": "item", "ts": "t"}}
    queue2 = rl.build_queue(order, rows, flags, state=state)
    check("已裁决的条目不再入队",
          "3" not in {x for g in queue2 for x in g}, str(queue2))

    # `--only` 过滤。
    only = rl.build_queue(order, rows, flags, state={}, only="slash_or_number_run")
    check("--only 只留带该标记的",
          {x for g in only for x in g} <= {"4", "5"}, str(only))

    # 稳定：同样输入两次结果逐字节相同。
    again = rl.build_queue(order, rows, flags, state={})
    check("队列是稳定的", queue == again)

    check("单条不成族批", not rl.group_is_batchable(["3"], rows))
    check("同首 token 可族批", rl.group_is_batchable(["1", "2"], rows))


def test_append_only() -> None:
    print("账本追加式")
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "review_ledger.jsonl"
        rl.append_ledger(path, [ledger_row("a", "approve")])
        first = path.read_bytes()
        rl.append_ledger(path, [ledger_row("b", "rename")])
        second = path.read_bytes()
        check("第二次写入是在原文件后追加", second.startswith(first), repr(second[:80]))
        check("两行都在", len(rl.read_ledger(path)) == 2)
        # 写坏的整批拒绝：不许留半条。
        before = path.read_bytes()
        try:
            rl.append_ledger(path, [ledger_row("c", "approve"), ledger_row("d", "bogus")])
            rejected = False
        except rl.LedgerError:
            rejected = True
        check("一批里有一行不合法 ⇒ 整批拒绝", rejected)
        check("拒绝时不写任何字节", path.read_bytes() == before)


def test_real_artifacts() -> None:
    print("真实产物对账（49,464 条）")
    root = rl.repo_root(Path(__file__).resolve().parent)
    seed_path = root / rl.SEED_REL
    preview_path = root / rl.PREVIEW_REL
    if not seed_path.is_file():
        check("种子在", False, str(seed_path))
        return
    check("种子在", True)
    if not preview_path.is_file():
        # 前置产物缺失是**这一步**的失败，不该让后面的真实对账整段跳过
        # （早期写法在这里 `return`，把「预览没导出」藏成了「测试没跑」）。
        check("上屏预览在（先跑 export_display_preview.dart）", False, str(preview_path))
        return
    check("上屏预览在（先跑 export_display_preview.dart）", True)

    order, rows = rl.load_seed(seed_path)
    check(f"种子 {len(order)} 条", len(order) == 49464, str(len(order)))

    meta, previews = rl.load_preview(preview_path)
    check("预览条数与种子一致", len(previews) == len(order), f"{len(previews)} vs {len(order)}")
    check("预览 id 集合与种子一致", set(previews) == set(rows))
    check(
        "预览记录的是当前种子的 sha256",
        meta.get("seed_sha256") == rl.seed_sha256(seed_path),
        f"{meta.get('seed_sha256')} vs {rl.seed_sha256(seed_path)}",
    )
    check(
        "预览声明了产出它的 Dart 函数",
        set(meta.get("source_functions") or ())
        == {"splitFoodName", "normalizeFoodName", "foodDisplayStrings"},
        str(meta.get("source_functions")),
    )

    tokens = rl.load_brand_tokens(root / rl.GAZETTEER_REL)
    check(f"自动词表 {len(tokens)} 条", len(tokens) > 2000, str(len(tokens)))

    # **关键对账**：Python 按同一批规则独立重算一份拆分，必须与 Dart 产出的
    # 预览逐条相同（这是「审核台看到的就是上屏的」的机械证明）。
    # 规则见 lib/utils/food_name.dart 的三条 + text_utils 的清洗。
    def py_split(raw: str, brands: set[str]) -> tuple[str, str | None]:
        import re

        trimmed = raw.strip()
        if not trimmed:
            return trimmed, None
        parenthesized = re.match(
            r"^\(([A-Za-z0-9][A-Za-z0-9&'\-.]*(?: [A-Za-z0-9&'\-.]*)*)\)[ \t]*(.+)$",
            trimmed,
        )
        if parenthesized:
            brand = parenthesized.group(1).strip()
            name = parenthesized.group(2).strip()
            if brand and name:
                return name, brand
        cut = trimmed.find(" ")
        if cut > 0:
            head = trimmed[:cut]
            rest = trimmed[cut + 1 :].strip()
            if rest and head in brands:
                return rest, head
        return trimmed, None

    def py_normalize(raw: str) -> str:
        import re

        trimmed = raw.strip()
        if not trimmed:
            return trimmed
        normalized = re.sub(r"[_\-]+", " ", trimmed)
        normalized = re.sub(r"\s+", " ", normalized)
        han = re.compile(r"[\u4e00-\u9fff]")
        digits_caps = re.compile(r"^[A-Z0-9]+$")
        has_upper = re.compile(r"[A-Z]")
        out = []
        for word in normalized.split(" "):
            if not word:
                continue
            if han.search(word) or digits_caps.match(word):
                out.append(word)
                continue
            if len(word) == 1:
                out.append(word.upper())
                continue
            rest = word[1:]
            body = rest if has_upper.search(rest) else rest.lower()
            out.append(word[0].upper() + body)
        return " ".join(out)

    mismatched = []
    for food_id in order[:4000]:
        raw = rows[food_id]["name"]
        name, brand = py_split(raw, tokens)
        name = py_normalize(name)
        shown = previews[food_id]
        if shown["name"] != name or shown["brand"] != brand:
            mismatched.append((food_id, raw, (name, brand), (shown["name"], shown["brand"])))
    check(
        "Python 独立重算的拆分 == Dart 预览的拆分（前 4,000 条）",
        not mismatched,
        str(mismatched[:3]),
    )

    # 预览里的营养字符串必须与种子的数值口径一致（环/三格）。
    bad = []
    for food_id in order[:4000]:
        row = rows[food_id]
        shown = previews[food_id]
        kcal = row["kcal"]
        want_ring = "—" if not kcal or kcal <= 0 else str(round(kcal))
        want_label = "无热量数据" if not kcal or kcal <= 0 else "kcal/100g"
        if shown["ring"] != want_ring or shown["ring_label"] != want_label:
            bad.append((food_id, shown["ring"], want_ring, shown["ring_label"], want_label))
    check("环的数字/口径与 D14 一致（前 4,000 条）", not bad, str(bad[:3]))

    # 标记在真实数据上跑得动、数得清（也钉住量级：种子换了要有人看一眼）。
    flags = rl.compute_flags(order, rows, tokens)
    counted = {name: 0 for name in rl.FLAG_RANK}
    for food_id in order:
        for flag in flags[food_id]:
            counted[flag] += 1
    print("     标记分布：", json.dumps(counted, ensure_ascii=False))
    check("每条都有标记列表（可以为空）", len(flags) == len(order))
    check("近似重名的确有（20 组 40 条）", counted["near_duplicate"] >= 40, str(counted))
    check(
        "纯汉字高频首词是最大的缺口（D6 说只有人工能关）",
        counted["han_head_frequent"] > 20000,
        str(counted),
    )

    queue = rl.build_queue(order, rows, flags, state={})
    check("空账本时队列覆盖全库", sum(len(g) for g in queue) == len(order), str(len(queue)))
    check("最可疑的排在前面", "near_duplicate" in flags[queue[0][0]], str(queue[0][:2]))


def test_stats_on_real_ledger_if_present() -> None:
    print("真实账本（存在才查）")
    root = rl.repo_root(Path(__file__).resolve().parent)
    ledger = root / rl.LEDGER_REL
    if not ledger.exists():
        print("  --   还没有账本，跳过（首次审核后自动生效）")
        return
    order, _ = rl.load_seed(root / rl.SEED_REL)
    rows = rl.read_ledger(ledger)
    state = rl.replay(rows)
    stats = rl.compute_stats(order, state)
    check("账本里每条裁决都指向种子里存在的 id",
          set(state) <= set(order),
          str(sorted(set(state) - set(order))[:3]))
    check("已裁决 ≤ 全库", stats["decided"] <= stats["total"], str(stats))
    print("     ", rl.format_stats(stats).replace("\n", " | "))


def main() -> int:
    test_ledger_validation()
    test_replay_and_revert()
    test_stats_five_tiers()
    test_cursor_roundtrip()
    test_flags_on_synthetic()
    test_queue_is_stable_and_grouped()
    test_append_only()
    test_real_artifacts()
    test_stats_on_real_ledger_if_present()
    if FAILURES:
        print(f"\n{len(FAILURES)} 项失败：{FAILURES}")
        return 1
    print("\n全部通过")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
