"""`build_exercises.py` 的测试（docs/28 §7.3/§7.4）。

运行：C:/ProgramData/miniconda3/python.exe test_build_exercises.py

两类断言：
  * **合成输入**上的规则行为（合成词序、器械不重复、缺译即失败、拉丁字母拒绝、
    常用度确定性、续号行必选、器械/难度下限）；
  * **真实产物**上的对账——`assets/seed/exercises.v3.json` 就是本脚本生成的，
    所以「条数/分布/无拉丁字母名/无重名/id 唯一/ex- 前缀/v2 续号齐全」必须在这份
    文件上验，不是在 fixture 上验；再加一条「重建结果与随包资产逐字节一致」
    （手改资产会被这条抓住）。
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import build_exercises as b  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
ASSET = os.path.join(ROOT, "assets", "seed", "exercises.v3.json")
V2_ASSET = os.path.join(ROOT, "assets", "seed", "exercises.v2.json")
PYTHON = "C:/ProgramData/miniconda3/python.exe"

# v2 里改了中文名的动作，逐条登记（docs/28 §7.3.3）：换源只允许动这一批。
# 名单两端各钉一次——多改一条（源或译名表漂移）或名单里有一条其实没改（名单
# 过期成空转）都算失败。三类：
#   A 已登记错译：坐姿好早上→坐姿早安式、后 deltoid 飞鸟→绳索反向飞鸟、
#     俄罗斯转弯→俄罗斯转体（v3 用同一个 id 写正确名字，不是删了重插）。
#   B 中文书写不规范：斜板卧推→上斜卧推、T杠→丁字杠、腿弯举→俯卧腿弯举、
#     腿伸展→腿屈伸、牧师弯举→牧师凳弯举、锤子弯举→锤式弯举、
#     专注弯举→集中弯举、Arnold 推举→阿诺德哑铃推举。
#   C 补器械/姿势前缀（v3 名字由动作事实合成，比 v2 的裸名更准）：耸肩→
#     杠铃耸肩、前平举→哑铃前平举、哑铃侧平举→坐姿哑铃侧平举、
#     杠铃肩部推举→站姿军事推举、哑铃颈后臂屈伸→哑铃单臂臂屈伸、
#     臂屈伸→哑铃臂后伸、力量板卧推→器械推胸、哑铃弓步蹲→哑铃箭步蹲。
V2_RENAME_ALLOWLIST = {
    "ex-seated-good-morning",  # A
    "ex-rear-delt-fly",  # A
    "ex-russian-twist",  # A
    "ex-db-incline-press",  # B
    "ex-bb-incline-press",  # B
    "ex-t-bar-row",  # B
    "ex-leg-curl",  # B
    "ex-leg-extension",  # B
    "ex-preacher-curl",  # B
    "ex-hammer-curl",  # B
    "ex-concentration-curl",  # B
    "ex-arnold-press",  # B
    "ex-shrugs",  # C
    "ex-front-raise",  # C
    "ex-dumbbell-lateral-raise",  # C
    "ex-bb-shoulder-press",  # C
    "ex-dumbbell-overhead-triceps-extension",  # C
    "ex-triceps-kickback",  # C
    "ex-chest-press-machine",  # C
    "ex-dumbbell-lunge",  # C
}

FAILURES: list[str] = []


def check(name: str, ok: bool, detail: str = "") -> None:
    if ok:
        print(f"  ok  {name}")
    else:
        FAILURES.append(f"{name}{'：' + detail if detail else ''}")
        print(f"  FAIL {name} {detail}")


def translate(name: str, equipment: str = "other", full: dict[str, str] | None = None) -> str:
    return b.translate(name, equipment, full or {})


def main_tests() -> int:
    print("normalize_name / 词表")
    check("归一化小写去连字符", b.normalize_name("Push-Up_Wide") == "push up wide")
    check("归一化折叠空白", b.normalize_name("Dips_-_Chest_Version") == "dips chest version")
    check("最长动作词优先", b.longest_head(["leg", "press"])[2] == "leg press")
    check(
        "同长动作词取靠后的（Barbell Walking Lunge 认 lunge）",
        b.longest_head(["barbell", "walking", "lunge"])[2] == "lunge",
    )
    check(
        "同长动作词取靠后的（Clean Deadlift 认 deadlift）",
        b.longest_head(["clean", "deadlift"])[2] == "deadlift",
    )

    print("合成译名（用不在 name_zh.tsv 里的名字，验的是合成规则本身）")
    check("器械枚举前缀 + 动作词", translate("Leg_Press", "machine") == "器械腿举")
    check("姿势词前置", translate("Seated_Dumbbell_Press", "dumbbell") == "坐姿哑铃推举")
    check("组合顺序：姿势 → 器械 → 动作", translate("Incline_Dumbbell_Press", "dumbbell") == "上斜哑铃推举")
    check("绳索硬拉（枚举前缀）", translate("Cable_Deadlifts", "cable") == "绳索硬拉")
    check("杠铃行走箭步蹲", translate("Barbell_Walking_Lunge", "barbell") == "杠铃行走箭步蹲")
    check(
        "名字里写过器械就不再加前缀",
        translate("Smith_Machine_Squat", "machine") == "史密斯架深蹲",
    )
    check("后缀修饰留在后面", translate("Dips_-_Version", "bodyweight") == "臂屈伸版本")
    check("整名覆盖优先", translate("Anything", "other", {"anything": "整名"}) == "整名")
    real_full = b.load_full_names(b.NAME_ZH)
    check(
        "随包译名表把不规则名定死",
        translate("Incline_Dumbbell_Press", "dumbbell", real_full) == "哑铃上斜卧推",
    )

    print("缺译即失败 / 不许拉丁字母")
    try:
        translate("Blorp_Frizzle", "other")
        check("未知动作词报错", False)
    except KeyError as error:
        check("未知动作词报错", "head:blorp frizzle" in str(error))
    try:
        b.translate("X", "other", {"x": "Push Up"})
        check("拉丁字母译名报错", False)
    except b.BuildError:
        check("拉丁字母译名报错", True)

    print("常用度规则")
    compound = {"mechanic": "compound", "primaryMuscles": ["chest", "triceps"], "equipment": "dumbbell", "level": "beginner", "category": "strength"}
    isolation = {"mechanic": "isolation", "primaryMuscles": ["biceps"], "equipment": "cable", "level": "expert", "category": "strength"}
    check("多关节大肌群分数更高", b.popularity(compound, "chest") > b.popularity(isolation, "arms"))
    check("确定性（同输入同输出）", b.popularity(compound, "chest") == b.popularity(compound, "chest"))
    check("夹在 5–100 之间", 5 <= b.popularity(isolation, "arms") <= 100)

    print("选择规则")
    candidates = b.load_candidates()
    selected, _ = b.select(candidates)
    groups = {}
    for item in selected:
        groups.setdefault(item.group, []).append(item)
    for group, target in b.GROUP_TARGETS.items():
        count = len(groups.get(group, []))
        check(f"{group} 达到目标（{count} ≥ {target - 2}）", count >= target - 2)
    equipments = {}
    for item in selected:
        equipments[item.equipment] = equipments.get(item.equipment, 0) + 1
    for equipment in b.EQUIPMENT_ORDER:
        check(f"器械 {equipment} ≥ {b.EQUIPMENT_FLOOR}", equipments.get(equipment, 0) >= b.EQUIPMENT_FLOOR)
    advanced = {group: sum(1 for item in items if item.difficulty == "advanced") for group, items in groups.items()}
    check("每个肌群都有高级动作", all(count >= 1 for count in advanced.values()), str(advanced))
    continuations = [item for item in candidates if item.is_continuation]
    selected_ids = {item.local_id for item in selected}
    missing = [item.local_id for item in continuations if item.local_id not in selected_ids]
    check("续号行必须全部入选", not missing, str(missing))

    print("真实产物")
    with open(ASSET, encoding="utf-8") as handle:
        document = json.load(handle)
    rows = document["exercises"]
    check("version = 3", document["version"] == 3)
    check("规模约 300（250–340）", 250 <= len(rows) <= 340, str(len(rows)))
    keys = {"id", "name", "muscle_group", "equipment", "difficulty", "popularity", "origin"}
    check("字段与 v2 兼容（多一个 origin）", all(set(row) == keys for row in rows))
    check("id 唯一且以 ex- 开头", len({row["id"] for row in rows}) == len(rows) and all(row["id"].startswith("ex-") for row in rows))
    check("无重名", len({row["name"] for row in rows}) == len(rows))
    check("无拉丁字母名", not [row["name"] for row in rows if re.search(r"[A-Za-z]", row["name"])])
    check("常用度 ∈ [0,100]", all(0 <= row["popularity"] <= 100 for row in rows))
    check(
        "难度 ∈ {beginner,intermediate,advanced}",
        {row["difficulty"] for row in rows} <= {"beginner", "intermediate", "advanced"},
    )
    check("难度三档齐全", {row["difficulty"] for row in rows} == {"beginner", "intermediate", "advanced"})
    check(
        "肌群 ∈ 7 档",
        {row["muscle_group"] for row in rows} <= set(b.GROUP_ORDER),
    )
    check(
        "器械 ∈ 6 档",
        {row["equipment"] for row in rows} <= {"bodyweight", "barbell", "dumbbell", "machine", "cable", "other"},
    )
    check(
        "来源只有两个已声明值",
        {row["origin"] for row in rows} <= set(__import__("strip_exercise_source").DECLARED_ORIGINS),
    )

    print("v2 续号对账")
    with open(V2_ASSET, encoding="utf-8") as handle:
        v2_rows = json.load(handle)["exercises"]
    dropped = {"ex-overhead-triceps-ext", "ex-triceps-pushdown-rope"}
    ids = {row["id"] for row in rows}
    stale = [row["id"] for row in v2_rows if row["id"] not in dropped and row["id"] not in ids]
    check("v2 的 58 个动作全部还在（换源不丢老动作）", not stale, str(stale))
    check("两条重名重复行不再收录", not (ids & dropped))
    v2_names = {row["id"]: row["name"] for row in v2_rows}
    changed = {
        row["id"]: (v2_names[row["id"]], row["name"])
        for row in rows
        if row["id"] in v2_names and v2_names[row["id"]] != row["name"]
    }
    undeclared = sorted(set(changed) - V2_RENAME_ALLOWLIST)
    check(
        "改名没有超出登记名单",
        not undeclared,
        str({key: changed[key] for key in undeclared}),
    )
    unused = sorted(V2_RENAME_ALLOWLIST - set(changed))
    check("登记名单没有过期条目（每条都真的改了）", not unused, str(unused))

    print("重建一致性")
    result = subprocess.run(
        [PYTHON, os.path.join(HERE, "build_exercises.py"), "--check"],
        capture_output=True,
        text=True,
        encoding="utf-8",
        cwd=HERE,
    )
    check("--check 通过（随包资产 = 脚本重建结果）", result.returncode == 0, (result.stderr or "")[-300:])

    if FAILURES:
        print(f"\nFAILED ({len(FAILURES)}):")
        for failure in FAILURES:
            print(f"  - {failure}")
        return 1
    print("\nall checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main_tests())
