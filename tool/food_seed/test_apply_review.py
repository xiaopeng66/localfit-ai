"""`apply_review.py` 的测试（docs/29 §P8b-2）。

运行：C:/ProgramData/miniconda3/python.exe test_apply_review.py

三类断言：
  * **幂等**：同一账本连跑两次，三份产物逐字节相同；
  * **出口守门**：覆盖率未达 `--require-coverage` 时拒绝产出（不出现「审了一半
    的种子」这种中间态）；
  * **覆盖率对账**（本包出口条件的机械证明）：v5 里**每一条 id** 都能在账本里
    追到一条生效裁决——**摘掉一条裁决 ⇒ 必须红**。

第三条用临时账本副本做（删一行、重放、断言 v5 少一条或覆盖率掉），不动真账本。
"""
from __future__ import annotations

import json
import os
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE / "review"))

import apply_review as ar  # noqa: E402
import review_lib as rl  # noqa: E402

FAILURES: list[str] = []


def check(label: str, condition: bool, detail: str = "") -> None:
    if condition:
        print(f"  ok   {label}")
    else:
        FAILURES.append(label)
        print(f"  FAIL {label} {detail}")


def test_outputs_exist_and_are_fresh() -> None:
    print("产物存在且新鲜")
    for path in (ar.OUT_SEED, ar.OUT_REVIEWED, ar.OUT_COUNT, ar.OUT_REPORT):
        check(f"{path.name} 在", path.is_file(), str(path))
    check("--check 通过（三份产物均最新）", ar.main(["--check"]) == 0)


def test_idempotent() -> None:
    print("幂等：连跑两次逐字节相同")
    texts_a = ar.build(100.0)
    texts_b = ar.build(100.0)
    seed_a, reviewed_a, count_a, report_a = texts_a[:4]
    seed_b, reviewed_b, count_b, report_b = texts_b[:4]
    check("seed 幂等", seed_a == seed_b)
    check("reviewed 幂等", reviewed_a == reviewed_b)
    check("count 幂等", count_a == count_b)
    check("report 幂等", report_a == report_b)
    # 再核对盘上文件与重建结果一致（防「生成后又被手改」）。
    check("盘上 seed 与重建一致", ar.OUT_SEED.read_text(encoding="utf-8") == seed_a)
    check(
        "盘上 reviewed 与重建一致",
        ar.OUT_REVIEWED.read_text(encoding="utf-8") == reviewed_a,
    )


def test_coverage_gate() -> None:
    print("出口守门：覆盖率不足即拒")
    # 要求 100% 而真实账本正好 100% -> 通过。
    check("要求 100% 时通过（真账本 100%）", ar.main(["--check"]) == 0)
    # 要求超过 100%（不可能）-> 必须抛 SystemExit。
    raised = False
    try:
        ar.build(100.01)
    except SystemExit:
        raised = True
    check("要求 100.01% 时拒绝", raised)


def test_coverage_reconciliation() -> None:
    print("覆盖率对账：账本任意一条被摘掉，v5 就少一条追溯")
    root = rl.repo_root(HERE)
    ledger_path = root / rl.LEDGER_REL
    seed_path = root / rl.SEED_REL
    if not ledger_path.is_file():
        check("账本在", False, str(ledger_path))
        return
    order, rows = rl.load_seed(seed_path)
    lines = [ln for ln in ledger_path.read_text(encoding="utf-8").splitlines() if ln.strip()]

    # 真账本重放：每个 id 都有生效裁决（覆盖率 100%）。
    # 账本行数 **>= 种子条数**：撤回与复核更正都是追加行（只增不改），所以行数
    # 会多于条目数——这不是缺陷，正是 append-only 的形态。判据看的是被覆盖的
    # id 集合，不是行数。
    state = rl.replay(rl.read_ledger(ledger_path))
    check(f"账本行 {len(lines)} >= 种子 {len(order)}", len(lines) >= len(order),
          f"{len(lines)} vs {len(order)}")
    missing = [food_id for food_id in order if food_id not in state]
    check("真账本：无未裁决 id", not missing, str(missing[:5]))

    # 摘掉一条裁决 -> 该 id 回到待审，覆盖率不再 100%（**必须红**）。
    # 取一条**当前生效**的普通裁决（不是 revert）来摘。
    victim = next(
        ln for ln in lines
        if json.loads(ln)["decision"] != "revert"
    )
    victim_id = json.loads(victim)["id"]
    with tempfile.TemporaryDirectory() as tmp:
        pruned = Path(tmp) / "pruned_ledger.jsonl"
        kept = [ln for ln in lines if ln is not victim]
        pruned.write_text("\n".join(kept) + "\n", encoding="utf-8")
        pruned_state = rl.replay(rl.read_ledger(pruned))
        # 若该 id 在别处还有生效裁决，才算「仍被覆盖」；这里只要求整体少一条
        # 或该 id 缺覆盖——两者任一都证明对账是活的。
        stats = rl.compute_stats(order, pruned_state)
        check("摘掉一条后 decided <= total - 1（或该 id 失覆盖）",
              stats["decided"] < stats["total"] or victim_id not in pruned_state,
              f"{stats['decided']}/{stats['total']}")
        # 出口守门会对这个不完整账本说不。
        raised = False
        try:
            ar.build(100.0, ledger_path=pruned)
        except SystemExit:
            raised = True
        check("不完整账本被出口守门拒绝", raised)
    # 原账本一字未动。
    check(
        "临时副本没动真账本",
        len([ln for ln in ledger_path.read_text(encoding="utf-8").splitlines() if ln.strip()])
        == len(lines),
    )


def test_v5_every_id_traces_to_a_decision() -> None:
    print("v5 每条产出 id 都能追到一条生效裁决")
    order, rows = rl.load_seed(ar.SEED)
    ledger_rows = rl.read_ledger(ar.LEDGER)
    state = rl.replay(ledger_rows)
    v5 = json.loads(ar.OUT_SEED.read_text(encoding="utf-8"))
    v5_ids = [row["id"] for row in v5["foods"]]
    check(f"v5 条数 = 种子 - 删除", len(v5_ids) == len(order) - len(
        [fid for fid in order if state[fid]["decision"] == "delete"]
    ))
    untraced = [food_id for food_id in v5_ids if food_id not in state]
    check("v5 里没有无裁决的 id", not untraced, str(untraced[:5]))
    # v5 与 version 字段。
    check("v5 version == 5", v5["version"] == 5)
    # 生成常量与 v5 实际条数一致。
    count_src = ar.OUT_COUNT.read_text(encoding="utf-8")
    check("生成常量条数 == v5 实际条数", f"kFoodSeedV5RowCount = {len(v5_ids)};" in count_src)


def main() -> int:
    test_outputs_exist_and_are_fresh()
    test_idempotent()
    test_coverage_gate()
    test_coverage_reconciliation()
    test_v5_every_id_traces_to_a_decision()
    print()
    if FAILURES:
        print(f"{len(FAILURES)} 项失败：{FAILURES}")
        return 1
    print("全部通过")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
