"""规范 §5.3 要求的「删除/替换来源」脚本（动作种子那一份，docs/28 §7.5）。

与 `tool/food_seed/strip_seed_source.py` 同形：按**来源**把某一份来源的条目从随包
种子里剔除，让「停止分发某个来源」保持一条可执行、可复验、可回退的命令。

动作种子的来源标记写在**每一条**的 `origin` 字段上（`free-exercise-db` = 上游
派生，`manual` = 上游没有对应动作、沿用 v2 事实手写保留的行）。食物种子用 id 前缀
区分来源，这里用 `origin` 更直接：id 要沿用 v2 的本地 id（于是不能编码来源），
而 `origin` 是逐条的显式声明。

    # 1) 看现在有哪些来源、各多少条
    C:/ProgramData/miniconda3/python.exe strip_exercise_source.py --list

    # 2) 试跑，写到新文件（不动 assets/）
    C:/ProgramData/miniconda3/python.exe strip_exercise_source.py \
        --strip free-exercise-db --out exercises.stripped.json

    # 3) 真的要换掉随包文件（会先写 .bak，拒绝覆盖已存在的 .bak）
    C:/ProgramData/miniconda3/python.exe strip_exercise_source.py \
        --strip free-exercise-db --in-place

设计取舍（都是「失败要显眼」而不是「悄悄少几百条」）：

- **只按 `origin` 删**，比按名字/字段猜可靠；来源不存在时报错并列出实际来源，
  避免打错字时「成功剥离 0 条」。
- **区分「已经删过了」和「打错字了」**：认识的已声明来源但文件里没有 = 已经删过
  （幂等、退出 0）；清单外的来源 = 打错字（退出 1）。
- **已经是目标状态就不写文件**（幂等）。
- **结果为空报错**：剥离后一条不剩说明参数给错了，此时不落盘。
- **`--in-place` 先备份**：项目没有 Git 元数据，改坏随包数据没有第二份可回退，
  所以原地改必须先写 `<path>.bak`，且**拒绝覆盖已存在的 .bak**。
- 只改 `exercises` 数组与 `version` 字段，其余顶层键原样保留；每条被保留条目的
  键集合与原始完全一致（测试断言），不做任何字段级「顺手规范化」。
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter
from pathlib import Path

HERE = Path(__file__).resolve().parent
DEFAULT_SEED = HERE.parent.parent / "assets" / "seed" / "exercises.v3.json"

# 已声明的随包来源（与 docs/THIRD_PARTY_LICENSES.md 的动作种子小节、
# lib/features/training/domain/data_attribution.dart、tool/exercise_seed/README.md
# 一一对应）。有这份清单才能把「已经删过了」和「来源打错了」分开——
# 两者在文件里都是「这个来源不存在」。test_strip_exercise.py 会断言它与
# 真实发布物里的 origin 集合一致。
DECLARED_ORIGINS = {
    "free-exercise-db": "yuhonas/free-exercise-db（Unlicense/public-domain）",
    "manual": "上游没有对应条目、沿用 v2 事实手写保留的动作（本仓库原创）",
}


def load_seed(path: Path) -> dict:
    document = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(document, dict):
        raise SystemExit(f"不是种子文档（顶层不是对象）：{path}")
    if not isinstance(document.get("exercises"), list):
        raise SystemExit(f"种子文档缺少 exercises 数组：{path}")
    for index, exercise in enumerate(document["exercises"]):
        if not isinstance(exercise, dict) or not isinstance(
            exercise.get("origin"), str
        ):
            raise SystemExit(f"第 {index} 条缺 origin（来源标记）：{path}")
    return document


def known_origins(exercises: list[dict]) -> Counter:
    return Counter(exercise["origin"] for exercise in exercises)


def strip(document: dict, origin: str) -> tuple[dict, int, int]:
    exercises = document["exercises"]
    kept = [exercise for exercise in exercises if exercise["origin"] != origin]
    removed = len(exercises) - len(kept)
    return {**document, "exercises": kept}, len(kept), removed


def write_seed(document: dict, out: Path) -> None:
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(
        json.dumps(document, ensure_ascii=False, separators=(",", ":")),
        encoding="utf-8",
    )


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="按来源从随包动作种子里剔除条目（规范 §5.3 删除/替换来源）",
    )
    parser.add_argument(
        "--seed",
        type=Path,
        default=DEFAULT_SEED,
        help=f"输入种子（默认 {DEFAULT_SEED}）",
    )
    parser.add_argument("--strip", metavar="ORIGIN", help="要剔除的来源，例如 free-exercise-db")
    parser.add_argument("--out", type=Path, help="输出文件（默认 <seed>.stripped.json）")
    parser.add_argument(
        "--in-place",
        action="store_true",
        help="原地替换 --seed，替换前写 <seed>.bak（拒绝覆盖已存在的 .bak）",
    )
    parser.add_argument(
        "--list",
        action="store_true",
        help="只列出当前的来源与条数，不做任何写入",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)

    if not args.seed.exists():
        print(f"找不到种子文件：{args.seed}", file=sys.stderr)
        return 2

    document = load_seed(args.seed)
    total = len(document["exercises"])
    origins = known_origins(document["exercises"])

    if args.list:
        print(f"{args.seed}  version={document.get('version')}  共 {total} 条")
        for origin, count in origins.most_common():
            print(f"  {origin}\t{count}")
        print("已声明来源（清单外的来源视为打错字）：")
        for origin, description in sorted(DECLARED_ORIGINS.items()):
            state = "在种子里" if origin in origins else "已不在种子里"
            print(f"  {origin}\t{state}\t{description}")
        return 0

    if not args.strip:
        print("必须给出 --strip <ORIGIN> 或 --list", file=sys.stderr)
        return 2
    if args.strip not in origins:
        # 来源不在文件里可能是「已经删过了」（正常、幂等、退出 0），也可能是
        # 「打错字了」（必须报错）。用已声明来源清单把两者分开。
        if args.strip in DECLARED_ORIGINS:
            print(
                f"已声明来源 {args.strip}（{DECLARED_ORIGINS[args.strip]}）"
                f"已经不在种子里（{total} 条未变），未写文件"
            )
            return 0
        print(
            f"种子里没有来源 {args.strip!r}，它也不在已声明来源清单里（打错字了？）。"
            "当前来源：" + "、".join(sorted(origins)),
            file=sys.stderr,
        )
        return 1
    if args.in_place and args.out:
        print("--in-place 与 --out 不能同时用", file=sys.stderr)
        return 2

    result, kept, removed = strip(document, args.strip)
    if kept == 0:
        print(
            f"剥离 {args.strip} 后一条不剩——随包种子不能为空，未写文件",
            file=sys.stderr,
        )
        return 1

    if removed == 0:
        print(f"{args.strip} 已经不存在于种子里（{total} 条未变），未写文件")
        return 0
    if args.in_place:
        backup = args.seed.with_suffix(args.seed.suffix + ".bak")
        if backup.exists():
            print(f"{backup} 已存在，拒绝覆盖（先把旧备份移走或改名）", file=sys.stderr)
            return 1
        backup.write_bytes(args.seed.read_bytes())
        write_seed(result, args.seed)
        out = args.seed
        print(f"已备份 {backup.name}（{total} 条）")
    else:
        out = args.out or args.seed.with_suffix(".stripped.json")
        write_seed(result, out)

    print(f"剔除 {args.strip}：{removed} 条；保留 {kept} 条；写入 {out}")
    for origin, count in known_origins(result["exercises"]).most_common():
        print(f"  {origin}\t{count}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
