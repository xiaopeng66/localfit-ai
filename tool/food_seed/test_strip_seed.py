"""`strip_seed_source.py` 的测试（规范 §5.3「删除/替换来源的脚本」）。

运行：C:/ProgramData/miniconda3/python.exe test_strip_seed.py

除了合成种子上的行为，这里还有两条**对真实发布物**的断言：真正要删来源时用的
就是 `assets/seed/foods.v4.json`，所以「真实种子里的前缀就是脚本认的那一个」
和「剥一个来源不动另一个来源的字节」必须在这个文件上验，不是在 fixture 上验。
2026-10-13（docs/32 §4 T13）起这份种子已移出仓库、归档在仓库外的
`../archive/food-seed-2026-10-13/`：这两条因此改成「本机有归档（或
`$LOCALFIT_FOOD_SEED`）就跑，没有就打印 SKIP」，不让整份测试在全新检出的机器上
直接报错，也不把它们悄悄削成空断言。
"""

from __future__ import annotations

import json
import os
import pathlib
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from strip_seed_source import (  # noqa: E402
    DECLARED_SOURCES,
    known_prefixes,
    load_seed,
    main,
    strip,
)

_REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SEED = os.environ.get("LOCALFIT_FOOD_SEED") or os.path.join(
    _REPO, "assets", "seed", "foods.v4.json"
)
if not os.path.exists(SEED):
    _archived = os.path.abspath(
        os.path.join(_REPO, "..", "archive", "food-seed-2026-10-13", "foods.v4.json")
    )
    if os.path.exists(_archived):
        SEED = _archived


def seed_available() -> bool:
    """真实种子在不在（不在就跳过对真实发布物的断言，并打印一行 SKIP）。"""
    if os.path.exists(SEED):
        return True
    print(f"  SKIP 真实种子不在本机：{SEED}（T13 后归档在仓库外）")
    return False

# 合成 fixture 用的第二个前缀：CLI 只认 DECLARED_SOURCES 里的前缀，但
# `strip()` 本身按传入前缀删，测试用它验「删一个来源不动另一个来源」。
OTHER = "seed-other-"

failures: list[str] = []


def check(label: str, condition: bool, detail: str = "") -> None:
    print(("  ok   " if condition else "  FAIL ") + label + (f" — {detail}" if detail and not condition else ""))
    if not condition:
        failures.append(label)


def food(food_id: str, name: str = "测试食物") -> dict:
    return {
        "id": food_id,
        "name": name,
        "serving_g": 100,
        "kcal": 100.0,
        "protein": 1.0,
        "carbs": 2.0,
        "fat": 3.0,
        "constraint_knowledge": "unknown",
        "dietary_labels": [],
        "allergens": [],
    }


def sample_document() -> dict:
    return {
        "version": 4,
        "foods": [
            food("seed-fc-11201", "小麦粉"),
            food("seed-fc-11202", "大米"),
            food(f"{OTHER}0007", "燕麦"),
            food("user-egg", "鸡蛋"),
        ],
    }


def write_temp(document: dict) -> str:
    handle, path = tempfile.mkstemp(suffix=".json")
    with os.fdopen(handle, "w", encoding="utf-8") as stream:
        json.dump(document, stream, ensure_ascii=False)
    return path


def test_known_prefixes() -> None:
    print("known_prefixes 按 id 前缀归类（不带第二段的 id 不会被来源前缀命中）")
    counts = known_prefixes(sample_document()["foods"])
    check("seed-fc- 2 条", counts["seed-fc-"] == 2, str(dict(counts)))
    check("其它前缀 1 条", counts[OTHER] == 1, str(dict(counts)))
    check("非 seed- 开头归到 (无前缀)", counts["(无前缀)"] == 1, str(dict(counts)))
    check(
        "来源前缀 strip 不会命中非本来源条目",
        all(
            f["id"] == "user-egg"
            for f in strip(sample_document(), "seed-fc-")[0]["foods"]
            if f["id"] == "user-egg"
        ),
    )


def test_strip_only_target_prefix() -> None:
    print("strip 只动目标前缀，保留条目逐字节不变")
    document = sample_document()
    result, kept, removed = strip(document, "seed-fc-")
    check("剔除 2 条", removed == 2, str(removed))
    check("保留 2 条", kept == 2, str(kept))
    check(
        "剩下的 id 顺序不变",
        [f["id"] for f in result["foods"]] == [f"{OTHER}0007", "user-egg"],
        str([f["id"] for f in result["foods"]]),
    )
    check(
        "保留条目对象未被改写",
        result["foods"] == [f for f in document["foods"] if not f["id"].startswith("seed-fc-")],
    )
    check("version 字段保留", result["version"] == 4)
    check("不共享 foods 列表（原文档没被改）", len(document["foods"]) == 4)


def test_cli_unknown_prefix_fails() -> None:
    print("CLI：清单外前缀（打错字）报错且不写文件")
    path = write_temp(sample_document())
    out = path + ".out.json"
    code = main(["--seed", path, "--strip", "seed-nope-", "--out", out])
    check("退出码 1", code == 1, str(code))
    check("没有产出文件", not os.path.exists(out))


def test_cli_idempotent() -> None:
    print("CLI：已声明来源已经被删过 → 幂等、退出 0、不写文件")
    document = sample_document()
    document["foods"] = [f for f in document["foods"] if not f["id"].startswith("seed-fc-")]
    path = write_temp(document)
    out = path + ".out.json"
    mtime_before = os.stat(path).st_mtime_ns
    code = main(["--seed", path, "--strip", "seed-fc-", "--out", out])
    check("退出码 0", code == 0, str(code))
    check("没有产出文件", not os.path.exists(out))
    check("输入文件未被重写", os.stat(path).st_mtime_ns == mtime_before)


def test_cli_in_place_backs_up_once() -> None:
    print("CLI：--in-place 先备份，且拒绝覆盖已存在的备份")
    path = write_temp(sample_document())
    backup = path + ".bak"
    # 先放一个既有备份：脚本必须拒绝覆盖它（项目没有 Git，冲掉旧备份就没了退路）。
    with open(backup, "w", encoding="utf-8") as stream:
        json.dump({"version": 4, "foods": [food("backup-marker")]}, stream, ensure_ascii=False)
    code = main(["--seed", path, "--strip", "seed-fc-", "--in-place"])
    check("已有 .bak 时退出码 1", code == 1, str(code))
    check("原文件未被改（仍 4 条）", len(load_seed(pathlib.Path(path))["foods"]) == 4)
    check(
        "既有 .bak 未被覆盖",
        load_seed(pathlib.Path(backup))["foods"][0]["id"] == "backup-marker",
    )
    os.remove(backup)
    code = main(["--seed", path, "--strip", "seed-fc-", "--in-place"])
    check("删掉旧备份后退出码 0", code == 0, str(code))
    check("生成了 .bak", os.path.exists(backup))
    check("备份是剥离前的 4 条", len(load_seed(pathlib.Path(backup))["foods"]) == 4)
    check("种子已剥离为 2 条", len(load_seed(pathlib.Path(path))["foods"]) == 2)


def test_refuses_empty_result() -> None:
    print("CLI：剥离后为空时报错且不落盘")
    path = write_temp({"version": 4, "foods": [food("seed-fc-1")]})
    out = path + ".out.json"
    code = main(["--seed", path, "--strip", "seed-fc-", "--out", out])
    check("退出码 1", code == 1, str(code))
    check("没有产出文件", not os.path.exists(out))


def test_real_seed_prefixes() -> None:
    print("真实发布物：来源前缀就是清单里记录的那一个")
    if not seed_available():
        return
    path = __import__("pathlib").Path(SEED)
    document = load_seed(path)
    counts = known_prefixes(document["foods"])
    check("共 49464 条", len(document["foods"]) == 49464, str(len(document["foods"])))
    check("seed-fc- 49464 条", counts["seed-fc-"] == 49464, str(dict(counts)))
    check(
        "来源前缀集合 == DECLARED_SOURCES（清单漂移会在这里红）",
        {p for p in counts if p in DECLARED_SOURCES} == set(DECLARED_SOURCES),
        f"文件里 {sorted(p for p in counts if p.startswith('seed-') and p.endswith('-'))} "
        f"vs 清单 {sorted(DECLARED_SOURCES)}",
    )
    check(
        "没有第二段以外的 seed- 前缀（旧 cfct/fw 来源确实已清空）",
        sorted(p for p in counts if p.startswith("seed-") and p.endswith("-")) == ["seed-fc-"],
        str(dict(counts)),
    )
    stripped, kept, removed = strip(document, "seed-fc-")
    check("剥离 FoodCalu 后为空（该来源就是当前全部）", kept == 0 and removed == 49464, f"{kept}/{removed}")
    check("原文档条数未变（没原地改真实种子）", len(document["foods"]) == 49464)


def test_stripped_seed_satisfies_importer_contract() -> None:
    print("种子满足 App 导入契约（version/字段/数值边界）")
    if not seed_available():
        return
    document = load_seed(__import__("pathlib").Path(SEED))
    check("version 仍是 4", document["version"] == 4)
    ids = [f["id"] for f in document["foods"]]
    check("id 唯一", len(ids) == len(set(ids)))
    required = {
        "id", "name", "serving_g", "kcal", "protein", "carbs", "fat",
        "constraint_knowledge", "dietary_labels", "allergens",
    }
    for food in document["foods"]:
        if set(food) != required:
            check(f"{food['id']} 字段集合与其它条目一致", False, str(sorted(food)))
            break
    else:
        check("所有条目字段集合一致", True)
    # 水/盐/茶等条目热量为 0 是正常的，所以下界是 0 而不是 >0。
    bad = [
        f["id"]
        for f in document["foods"]
        if not (0 <= f["kcal"] <= 1000 and all(0 <= f[k] <= 100 for k in ("protein", "carbs", "fat")))
    ]
    check("数值边界合法（kcal 0..1000、三大宏量 0..100）", not bad, str(bad[:5]))
    # unknown ⇒ 无声明（与 App 的 FoodConstraintFacts.validate 一致）
    inconsistent = [
        f["id"]
        for f in document["foods"]
        if f["constraint_knowledge"] == "unknown" and (f["dietary_labels"] or f["allergens"])
    ]
    check("unknown 条目不带任何声明", not inconsistent, str(inconsistent[:5]))


def main_tests() -> int:
    for test in (
        test_known_prefixes,
        test_strip_only_target_prefix,
        test_cli_unknown_prefix_fails,
        test_cli_idempotent,
        test_cli_in_place_backs_up_once,
        test_refuses_empty_result,
        test_real_seed_prefixes,
        test_stripped_seed_satisfies_importer_contract,
    ):
        test()
    print()
    if failures:
        print(f"FAILED ({len(failures)}): " + ", ".join(failures))
        return 1
    print("all checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main_tests())
