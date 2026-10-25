"""规范 §5.3 要求的「删除/替换来源」脚本（删除半边）。

§5.3 原文：「2.0 发布前生成第三方许可清单**和删除/替换来源的脚本**」。本脚本就是
那后半句——按**来源前缀**（= id 前缀）把某一份来源的条目从随包种子里剔除，让
「停止分发某个来源」变成一条可执行、可复验、可回退的命令，而不是手工编辑 JSON。

典型用法（清单见 docs/THIRD_PARTY_LICENSES.md §4，调查见
docs/evidence/2026-09-16-2.0-1l-chinese-food-source-license-investigation.md）：

    # 1) 看现在有哪些来源、各多少条
    C:/ProgramData/miniconda3/python.exe strip_seed_source.py --list

    # 2) 试跑，写到新文件（不动 assets/）
    C:/ProgramData/miniconda3/python.exe strip_seed_source.py \
        --strip seed-fc- --out foods.stripped.json

    # 3) 真的要换掉随包文件（会先写 .bak，拒绝覆盖已存在的 .bak）
    C:/ProgramData/miniconda3/python.exe strip_seed_source.py \
        --strip seed-fc- --in-place

设计取舍（都是「失败要显眼」而不是「悄悄少几百条」）：

- **只按 id 前缀删**。id 就是来源（当前只有 `seed-fc-*` = FoodCalu），比按名字/字段猜可靠；前缀不存在时报错并列出实际前缀，
  避免打错字时「成功剥离 0 条」。
- **区分「已经删过了」和「打错字了」**。这两件事在文件里长得一样（前缀都不在文件里），
  所以脚本认识一份**已声明的来源清单**（`DECLARED_SOURCES`，与
  `docs/THIRD_PARTY_LICENSES.md` §1 和 App 内来源清单一致）：给的是已声明来源但文件里
  没有 = 已经删过了 → 不动文件、退出码 0；给的是清单外的前缀 = 打错字 → 退出码 1。
  测试会断言这份清单与真实发布物里的前缀集合一致，清单漂移会红。
- **已经是目标状态就不写文件**（幂等）：重复跑不会产生无意义的新文件/新差异。
- **结果为空报错**：如果剥离后一条不剩，说明参数给错了（种子必须至少留一条），
  此时不落盘。
- **`--in-place` 先备份**：项目没有 Git 元数据，改坏随包数据没有第二份可回退，
  所以原地改必须先写 `<path>.bak`，且**拒绝覆盖已存在的 .bak**（避免把上一次的
  好备份冲掉）。
- 只改 `foods` 数组与 `version` 字段，其余顶层键原样保留；每条被保留条目的键集合
  与原始完全一致（测试断言），不做任何字段级「顺手规范化」——剥离和改写是两件事。
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from collections import Counter
from pathlib import Path

HERE = Path(__file__).resolve().parent

# 2026-10-13（docs/32 §4 T13）：食物种子整族退役，`foods.v4/v5.json` 已移出仓库、
# 归档到 `<repo>/../archive/food-seed-2026-10-13/`（见那里的 README）。仓库里已经
# 没有默认种子了，所以按顺序找：`$LOCALFIT_FOOD_SEED` → 仓库内旧路径（万一恢复）
# → 归档副本。这条「停止分发某个来源」的命令要一直能跑，只是它现在操作的是归档
# 里那份历史数据。
REPO_SEED = HERE.parent.parent / "assets" / "seed" / "foods.v4.json"
ARCHIVED_SEED = (
    HERE.parent.parent.parent / "archive" / "food-seed-2026-10-13" / "foods.v4.json"
)


def default_seed_path() -> Path:
    override = os.environ.get("LOCALFIT_FOOD_SEED")
    if override:
        return Path(override)
    if REPO_SEED.exists():
        return REPO_SEED
    return ARCHIVED_SEED


DEFAULT_SEED = default_seed_path()

# 已声明的随包来源前缀（与 docs/THIRD_PARTY_LICENSES.md §1 表格、App 内
# lib/features/nutrition/domain/data_attribution.dart 一一对应）。
# 有这份清单才能把「已经删过了」和「前缀打错了」分开——两者在文件里都是
# 「前缀不存在」。test_strip_seed.py 会断言它与真实发布物的前缀一致。
DECLARED_SOURCES = {
    "seed-fc-": "FoodCalu 中文食物库（github.com/gaosheng293/FoodCalu）",
}


def known_prefixes(foods: list[dict]) -> Counter:
    """统计种子里的来源前缀（`seed-xxx-`，到第二个短横线为止）。

    `seed-fc-123` 归到 `seed-fc-`；不带第二段的 id（如用户自建 id）不会被任何
    已声明来源前缀命中。`--strip` 只接受清单里的来源前缀，其余条目不会被误删。
    """
    counts: Counter = Counter()
    for food in foods:
        identifier = str(food.get("id", ""))
        if not identifier.startswith("seed-"):
            counts["(无前缀)"] += 1
            continue
        head, _, rest = identifier.partition("-")[2].partition("-")
        counts[f"seed-{head}-" if rest else f"seed-{head}"] += 1
    return counts


def load_seed(path: Path) -> dict:
    document = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(document, dict):
        raise SystemExit(f"不是种子文档（顶层不是对象）：{path}")
    if not isinstance(document.get("foods"), list):
        raise SystemExit(f"种子文档缺少 foods 数组：{path}")
    for index, food in enumerate(document["foods"]):
        if not isinstance(food, dict) or not isinstance(food.get("id"), str):
            raise SystemExit(f"第 {index} 条不是合法条目（缺 id）：{path}")
    return document


def strip(document: dict, prefix: str) -> tuple[dict, int, int]:
    """返回 (新文档, 保留数, 剔除数)。prefix 必须是完整前缀（含尾部短横线）。"""
    foods = document["foods"]
    kept = [food for food in foods if not food["id"].startswith(prefix)]
    removed = len(foods) - len(kept)
    result = {**document, "foods": kept}
    return result, len(kept), removed


def write_seed(document: dict, out: Path) -> None:
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(
        json.dumps(document, ensure_ascii=False, separators=(",", ":")),
        encoding="utf-8",
    )


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="按来源前缀从随包食物种子里剔除条目（规范 §5.3 删除/替换来源）",
    )
    parser.add_argument(
        "--seed",
        type=Path,
        default=None,
        help=(
            "输入种子（默认 $LOCALFIT_FOOD_SEED，否则仓库内 "
            "assets/seed/foods.v4.json，再否则归档副本 "
            f"{ARCHIVED_SEED}）"
        ),
    )
    parser.add_argument(
        "--strip",
        metavar="ID_PREFIX",
        help="要剔除的来源前缀，例如 seed-fc-",
    )
    parser.add_argument("--out", type=Path, help="输出文件（默认 <seed>.stripped.json）")
    parser.add_argument(
        "--in-place",
        action="store_true",
        help="原地替换 --seed，替换前写 <seed>.bak（拒绝覆盖已存在的 .bak）",
    )
    parser.add_argument(
        "--list",
        action="store_true",
        help="只列出当前的来源前缀与条数，不做任何写入",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    if args.seed is None:
        args.seed = default_seed_path()

    if not args.seed.exists():
        print(f"找不到种子文件：{args.seed}", file=sys.stderr)
        return 2

    document = load_seed(args.seed)
    total = len(document["foods"])
    prefixes = known_prefixes(document["foods"])

    if args.list:
        print(f"{args.seed}  version={document.get('version')}  共 {total} 条")
        for prefix, count in prefixes.most_common():
            print(f"  {prefix}\t{count}")
        print("已声明来源（清单外的前缀视为打错字）：")
        for prefix, description in sorted(DECLARED_SOURCES.items()):
            state = "在种子里" if prefix in prefixes else "已不在种子里"
            print(f"  {prefix}\t{state}\t{description}")
        return 0

    if not args.strip:
        print("必须给出 --strip <ID_PREFIX> 或 --list", file=sys.stderr)
        return 2
    if args.strip not in prefixes:
        # 前缀不在文件里可能是「已经删过了」（正常、幂等、退出 0），也可能是
        # 「打错字了」（必须报错）。用已声明来源清单把两者分开。
        if args.strip in DECLARED_SOURCES:
            print(
                f"已声明来源 {args.strip}（{DECLARED_SOURCES[args.strip]}）"
                f"已经不在种子里（{total} 条未变），未写文件"
            )
            return 0
        print(
            f"种子里没有来源前缀 {args.strip!r}，它也不在已声明来源清单里"
            "（打错字了？）。当前前缀：" + "、".join(sorted(prefixes)),
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
        # 幂等：已经是目标状态，不写文件（避免产生无意义的新文件/差异）。
        print(f"{args.strip} 已经不存在于种子里（{total} 条未变），未写文件")
        return 0
    if args.in_place:
        backup = args.seed.with_suffix(args.seed.suffix + ".bak")
        if backup.exists():
            print(
                f"{backup} 已存在，拒绝覆盖（先把旧备份移走或改名）",
                file=sys.stderr,
            )
            return 1
        backup.write_bytes(args.seed.read_bytes())
        write_seed(result, args.seed)
        out = args.seed
        print(f"已备份 {backup.name}（{total} 条）")
    else:
        out = args.out or args.seed.with_suffix(".stripped.json")
        write_seed(result, out)

    print(f"剔除 {args.strip}：{removed} 条；保留 {kept} 条；写入 {out}")
    for prefix, count in known_prefixes(result["foods"]).most_common():
        print(f"  {prefix}\t{count}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
