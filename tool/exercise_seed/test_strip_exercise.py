"""`strip_exercise_source.py` 的测试（规范 §5.3「删除/替换来源的脚本」，docs/28 §7.5）。

运行：C:/ProgramData/miniconda3/python.exe test_strip_exercise.py

除了合成种子上的行为，这里还有三条**对真实发布物**的断言：真正要删来源时用的
就是 `assets/seed/exercises.v3.json`，所以「真实种子里的来源就是清单里那两个」
「剥掉上游派生来源后剩下的手写行 = `manual_rows.tsv` 里登记的那些」「剥完每条
保留行的键集合一字不差」必须在这个文件上验，不是在 fixture 上验。
"""

from __future__ import annotations

import json
import os
import pathlib
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from strip_exercise_source import (  # noqa: E402
    DECLARED_ORIGINS,
    known_origins,
    load_seed,
    main,
    strip,
)

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
SEED = os.path.join(ROOT, "assets", "seed", "exercises.v3.json")
MANUAL_TSV = os.path.join(HERE, "manual_rows.tsv")

# 合成 fixture 里的第三个来源：CLI 只认 DECLARED_ORIGINS 里的来源，但 `strip()`
# 本身按传入的来源删，测试用它验「删一个来源不动另一个来源」。
OTHER = "upstream-other"

ROW_KEYS = {"id", "name", "muscle_group", "equipment", "difficulty", "popularity", "origin"}

failures: list[str] = []


def check(label: str, condition: bool, detail: str = "") -> None:
    print(("  ok   " if condition else "  FAIL ") + label + (f" — {detail}" if detail and not condition else ""))
    if not condition:
        failures.append(label)


def exercise(exercise_id: str, origin: str, name: str = "测试动作") -> dict:
    return {
        "id": exercise_id,
        "name": name,
        "muscle_group": "chest",
        "equipment": "barbell",
        "difficulty": "beginner",
        "popularity": 50,
        "origin": origin,
    }


def sample_document() -> dict:
    return {
        "version": 3,
        "exercises": [
            exercise("ex-bench", "free-exercise-db", "杠铃卧推"),
            exercise("ex-squat", "free-exercise-db", "杠铃深蹲"),
            exercise("ex-wide-grip-pullup", "manual", "宽握引体向上"),
            exercise(f"ex-{OTHER}-1", OTHER, "别的上游"),
            exercise("ex-user-1", "manual", "用户自建占位"),
        ],
    }


def write_temp(document: dict) -> str:
    handle, path = tempfile.mkstemp(suffix=".json")
    with os.fdopen(handle, "w", encoding="utf-8") as stream:
        json.dump(document, stream, ensure_ascii=False)
    return path


def test_load_seed_requires_origin() -> None:
    print("load_seed 认为每条必须有 origin（来源标记缺失即报错）")
    path = write_temp({"version": 3, "exercises": [exercise("ex-a", "manual")]})
    try:
        load_seed(pathlib.Path(path))
        check("带 origin 的种子可读", True)
    except SystemExit as error:
        check("带 origin 的种子可读", False, str(error))
    os.remove(path)

    bad = exercise("ex-a", "manual")
    del bad["origin"]
    path = write_temp({"version": 3, "exercises": [bad]})
    try:
        load_seed(pathlib.Path(path))
        check("缺 origin 报错（SystemExit）", False, "没有报错")
    except SystemExit as error:
        check("缺 origin 报错（SystemExit）", "origin" in str(error), str(error))
    os.remove(path)

    path = write_temp({"version": 3, "exercises": {"ex-a": {}}})
    try:
        load_seed(pathlib.Path(path))
        check("exercises 不是数组也报错", False, "没有报错")
    except SystemExit as error:
        check("exercises 不是数组也报错", "exercises" in str(error), str(error))
    os.remove(path)


def test_known_origins() -> None:
    print("known_origins 按 origin 归类")
    counts = known_origins(sample_document()["exercises"])
    check("free-exercise-db 2 条", counts["free-exercise-db"] == 2, str(dict(counts)))
    check("manual 2 条", counts["manual"] == 2, str(dict(counts)))
    check("第三个来源 1 条", counts[OTHER] == 1, str(dict(counts)))


def test_strip_only_target_origin() -> None:
    print("strip 只动目标来源，保留条目逐字节不变")
    document = sample_document()
    result, kept, removed = strip(document, "free-exercise-db")
    check("剔除 2 条", removed == 2, str(removed))
    check("保留 3 条", kept == 3, str(kept))
    check(
        "剩下的 id 顺序不变",
        [row["id"] for row in result["exercises"]]
        == ["ex-wide-grip-pullup", f"ex-{OTHER}-1", "ex-user-1"],
        str([row["id"] for row in result["exercises"]]),
    )
    check(
        "保留条目对象未被改写",
        result["exercises"]
        == [row for row in document["exercises"] if row["origin"] != "free-exercise-db"],
    )
    check("version 字段保留", result["version"] == 3)
    check("不共享 exercises 列表（原文档没被改）", len(document["exercises"]) == 5)
    # 删一个来源不动另一个来源：manual 行原样还在、OTHER 行也在。
    check(
        "只删目标来源（manual / 别的上游都还在）",
        {row["origin"] for row in result["exercises"]} == {"manual", OTHER},
    )


def test_cli_unknown_origin_fails() -> None:
    print("CLI：清单外来源（打错字）报错且不写文件")
    path = write_temp(sample_document())
    out = path + ".out.json"
    code = main(["--seed", path, "--strip", "upstream-nope", "--out", out])
    check("退出码 1", code == 1, str(code))
    check("没有产出文件", not os.path.exists(out))
    os.remove(path)


def test_cli_idempotent() -> None:
    print("CLI：已声明来源已经被删过 → 幂等、退出 0、不写文件")
    document = sample_document()
    document["exercises"] = [
        row for row in document["exercises"] if row["origin"] != "free-exercise-db"
    ]
    path = write_temp(document)
    out = path + ".out.json"
    mtime_before = os.stat(path).st_mtime_ns
    code = main(["--seed", path, "--strip", "free-exercise-db", "--out", out])
    check("退出码 0", code == 0, str(code))
    check("没有产出文件", not os.path.exists(out))
    check("输入文件未被重写", os.stat(path).st_mtime_ns == mtime_before)
    os.remove(path)


def test_cli_in_place_backs_up_once() -> None:
    print("CLI：--in-place 先备份，且拒绝覆盖已存在的备份")
    path = write_temp(sample_document())
    backup = path + ".bak"
    # 先放一个既有备份：脚本必须拒绝覆盖它（项目没有 Git，冲掉旧备份就没了退路）。
    with open(backup, "w", encoding="utf-8") as stream:
        json.dump({"version": 3, "exercises": [exercise("ex-backup", "manual")]}, stream, ensure_ascii=False)
    code = main(["--seed", path, "--strip", "free-exercise-db", "--in-place"])
    check("已有 .bak 时退出码 1", code == 1, str(code))
    check("原文件未被改（仍 5 条）", len(load_seed(pathlib.Path(path))["exercises"]) == 5)
    check(
        "既有 .bak 未被覆盖",
        load_seed(pathlib.Path(backup))["exercises"][0]["id"] == "ex-backup",
    )
    os.remove(backup)
    code = main(["--seed", path, "--strip", "free-exercise-db", "--in-place"])
    check("删掉旧备份后退出码 0", code == 0, str(code))
    check("生成了 .bak", os.path.exists(backup))
    check("备份是剥离前的 5 条", len(load_seed(pathlib.Path(backup))["exercises"]) == 5)
    check("种子已剥离为 3 条", len(load_seed(pathlib.Path(path))["exercises"]) == 3)
    os.remove(backup)
    os.remove(path)


def test_refuses_empty_result() -> None:
    print("CLI：剥离后为空时报错且不落盘")
    path = write_temp({"version": 3, "exercises": [exercise("ex-only", "free-exercise-db")]})
    out = path + ".out.json"
    code = main(["--seed", path, "--strip", "free-exercise-db", "--out", out])
    check("退出码 1", code == 1, str(code))
    check("没有产出文件", not os.path.exists(out))
    os.remove(path)


def test_cli_list_names_declared_origins() -> None:
    print("CLI：--list 列出实际来源与已声明来源，不写任何文件")
    path = write_temp(sample_document())
    before = os.stat(path).st_mtime_ns
    code = main(["--seed", path, "--list"])
    check("退出码 0", code == 0, str(code))
    check("输入文件未被重写", os.stat(path).st_mtime_ns == before)
    check("清单里两个来源都在 DECLARED_ORIGINS", set(DECLARED_ORIGINS) == {"free-exercise-db", "manual"}, str(DECLARED_ORIGINS))
    os.remove(path)


def test_real_seed_origins() -> None:
    print("真实发布物：来源就是清单里记录的那两个")
    document = load_seed(pathlib.Path(SEED))
    counts = known_origins(document["exercises"])
    check("共 312 条", len(document["exercises"]) == 312, str(len(document["exercises"])))
    check(
        "来源集合 == DECLARED_ORIGINS（清单漂移会在这里红）",
        set(counts) == set(DECLARED_ORIGINS),
        f"文件里 {sorted(counts)} vs 清单 {sorted(DECLARED_ORIGINS)}",
    )
    check("free-exercise-db 305 条", counts["free-exercise-db"] == 305, str(dict(counts)))
    check("manual 7 条", counts["manual"] == 7, str(dict(counts)))


def test_real_manual_rows_match_source_of_truth() -> None:
    print("真实发布物：手写行 = manual_rows.tsv 里登记的那些（一一对应，不漂移）")
    document = load_seed(pathlib.Path(SEED))
    manual = {row["id"]: row["name"] for row in document["exercises"] if row["origin"] == "manual"}
    declared = {}
    with open(MANUAL_TSV, encoding="utf-8") as handle:
        for line in handle:
            line = line.rstrip("\n")
            if not line or line.startswith("#"):
                continue
            columns = line.split("\t")
            declared[columns[0]] = columns[1]
    check("条数一致（7）", len(manual) == len(declared) == 7, f"{len(manual)}/{len(declared)}")
    check(
        "id 集合一致",
        set(manual) == set(declared),
        f"资产多 {sorted(set(manual) - set(declared))} 缺 {sorted(set(declared) - set(manual))}",
    )
    mismatch = {key: (declared[key], manual[key]) for key in set(manual) & set(declared) if declared[key] != manual[key]}
    check("名称一致", not mismatch, str(mismatch))


def test_strip_keeps_row_shape() -> None:
    print("真实发布物：剥掉上游派生来源后，每条保留行的键集合一字不差")
    document = load_seed(pathlib.Path(SEED))
    result, kept, removed = strip(document, "free-exercise-db")
    check("剔除 305 条", removed == 305, str(removed))
    check("保留 7 条", kept == 7, str(kept))
    check("version 仍是 3", result["version"] == 3)
    bad = [row["id"] for row in result["exercises"] if set(row) != ROW_KEYS]
    check("保留行键集合 == 7 个键", not bad, str(bad))
    check("保留行来源全是 manual", {row["origin"] for row in result["exercises"]} == {"manual"})
    check("顶层键原样保留", set(result) == set(document), f"{sorted(result)} vs {sorted(document)}")
    check("原文档条数未变（没原地改真实种子）", len(document["exercises"]) == 312)


def main_tests() -> int:
    for test in (
        test_load_seed_requires_origin,
        test_known_origins,
        test_strip_only_target_origin,
        test_cli_unknown_origin_fails,
        test_cli_idempotent,
        test_cli_in_place_backs_up_once,
        test_refuses_empty_result,
        test_cli_list_names_declared_origins,
        test_real_seed_origins,
        test_real_manual_rows_match_source_of_truth,
        test_strip_keeps_row_shape,
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
