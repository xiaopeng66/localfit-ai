#!/usr/bin/env python3
"""从 yuhonas/free-exercise-db 生成 `assets/seed/exercises.v3.json`（docs/28 §7）。

上游（`raw/free_exercise_db.json`，876 条，Unlicense/public-domain）只有英文名与
肌群/器械/难度等事实字段，本脚本做四件事：

1. **映射**：`primaryMuscles[0]` → 现有 7 档 `MuscleGroup`；`equipment` → 现有 6 档
   `Equipment`；`level` → 三档 `ExerciseDifficulty`（expert → advanced）；`popularity`
   按**确定性常量表**算（多关节/大肌群高分，孤立小肌群低分），不随机。
2. **筛选**：按 docs/28 §7.2 的 7 肌群目标条数取分（`GROUP_TARGETS`），再补一轮
   「每档器械 ≥ 20」（`EQUIPMENT_FLOOR`）与「每肌群 ≥ 3 条高级」（`ADVANCED_FLOOR`）。
3. **翻译**：`EQUIP_ZH`/`MOD_ZH`/`HEAD_ZH`（本文件里的词表）合成「器械前缀 +
   动作名词」，`name_zh.tsv` 兜不规则整名（含 v2 既有动作的定名）。
   **缺译即失败退出**——不许拉丁字母名漏进库（上游名里有 `Dips_-_Chest_Version`、
   `3_4_Sit-Up` 这类，全走 `name_zh.tsv`）。
4. **续号**：`id_overrides.tsv` 把上游 id 映射回 v2 的本地 id，让
   `ExerciseSeedImporter` 的 `insertOnConflictUpdate` **原地刷新**旧行而不是插入
   第二条同名动作；上游没有对应条目的 v2 动作走 `manual_rows.tsv` 手写保留。

用法：

    C:/ProgramData/miniconda3/python.exe build_exercises.py --report   # 只报告，不写文件
    C:/ProgramData/miniconda3/python.exe build_exercises.py --dump     # 再打印逐条清单
    C:/ProgramData/miniconda3/python.exe build_exercises.py            # 写 assets/seed/exercises.v3.json

改规则后必须重跑并跑 `flutter test`（种子导入/分布测试会校验条数与 7 肌群下限）。
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter
from pathlib import Path

HERE = Path(__file__).resolve().parent
RAW = HERE / "raw" / "free_exercise_db.json"
NAME_ZH = HERE / "name_zh.tsv"
ID_OVERRIDES = HERE / "id_overrides.tsv"
MANUAL_ROWS = HERE / "manual_rows.tsv"
OUT = HERE.parent.parent / "assets" / "seed" / "exercises.v3.json"

VERSION = 3

# 上游来源标记，逐条写进资产（strip_exercise_source.py 按它剥离；
# 导入器只读 id/name/muscle_group/equipment/difficulty/popularity，多一个键无害）。
ORIGIN_UPSTREAM = "free-exercise-db"
ORIGIN_MANUAL = "manual"

# 上游 primaryMuscles → 7 档肌群。脖子（neck）在 7 档里没有对应，整族不选。
MUSCLE_TO_GROUP = {
    "chest": "chest",
    "lats": "back",
    "middle back": "back",
    "lower back": "back",
    "traps": "shoulders",  # 斜方肌：与 v2 既有「耸肩 = 肩」一致（中文健身语境常与肩同组）
    "shoulders": "shoulders",
    "quadriceps": "legs",
    "hamstrings": "legs",
    "glutes": "legs",
    "calves": "legs",
    "adductors": "legs",
    "abductors": "legs",
    "triceps": "arms",
    "biceps": "arms",
    "forearms": "arms",
    "abdominals": "core",
    "neck": None,
}

# 这些 category 的动作本身就练全身（举重/壮汉/有氧），整族算 fullBody；
# plyometrics 仍按主肌群算（跳深/跳箱落在腿），个别真正全身的进 FULLBODY_IDS。
FULLBODY_CATEGORIES = {"olympic weightlifting", "strongman", "cardio"}
FULLBODY_IDS: set[str] = {
    "Barbell_Clean_and_Press",
    "Clean_and_Press",
    "Push_Press",
    "Kettlebell_Thruster",
    "Mountain_Climbers",
    "Rope_Climbing",
    "Bear_Crawl_Sled_Drags",
}

# 拉伸不是「动作」（没有难度/常用度语义，7 肌群也装不下），整类不选。
EXCLUDED_CATEGORIES = {"stretching"}

# 上游 equipment → 6 档枚举。壶铃/弹力带/药球/瑞士球这些枚举里没有的进「其他」。
EQUIPMENT_MAP = {
    "body only": "bodyweight",
    None: "bodyweight",
    "barbell": "barbell",
    "e-z curl bar": "barbell",
    "olympic barbell": "barbell",
    "dumbbell": "dumbbell",
    "cable": "cable",
    "machine": "machine",
    "other": "other",
    "kettlebells": "other",
    "bands": "other",
    "medicine ball": "other",
    "exercise ball": "other",
    "foam roll": "other",
}

LEVEL_TO_DIFFICULTY = {
    "beginner": "beginner",
    "intermediate": "intermediate",
    "expert": "advanced",
}

# docs/28 §7.2 的 7 肌群目标条数。
GROUP_TARGETS = {
    "chest": 40,
    "back": 45,
    "legs": 55,
    "shoulders": 40,
    "arms": 45,
    "core": 45,
    "fullBody": 30,
}
GROUP_ORDER = ["chest", "back", "legs", "shoulders", "arms", "core", "fullBody"]

# docs/28 §7.2：器械每档 ≥ 20 条；难度三档要真的能筛出东西，每肌群至少 3 条高级。
EQUIPMENT_FLOOR = 20
ADVANCED_FLOOR = 3
EQUIPMENT_ORDER = ["bodyweight", "barbell", "dumbbell", "machine", "cable", "other"]

# 常用度规则表（确定性常量，不随机）。基础分 + 各维度加减，最后夹到 5–100。
POPULARITY_BASE = 45
POPULARITY_MECHANIC = {"compound": 18, "isolation": -6}
POPULARITY_GROUP = {
    "chest": 12,
    "back": 12,
    "legs": 12,
    "fullBody": 12,
    "shoulders": 8,
    "arms": 4,
    "core": 4,
}
POPULARITY_EQUIPMENT = {
    "bodyweight": 6,
    "dumbbell": 8,
    "barbell": 6,
    "cable": 2,
    "machine": 0,
    "other": -4,
    "kettlebells": -2,
    "bands": -2,
    "medicine ball": -2,
    "exercise ball": -2,
    "e-z curl bar": 2,
}
POPULARITY_LEVEL = {"beginner": 6, "intermediate": 2, "expert": -8}
POPULARITY_CATEGORY = {
    "strength": 0,
    "powerlifting": 2,
    "olympic weightlifting": 2,
    "strongman": -2,
    "cardio": 0,
    "plyometrics": 0,
}
MULTI_MUSCLE_BONUS = 6

# ---------------------------------------------------------------------------
# 词表（`name_zh.tsv` 只兜不规则整名，规则名由这三张表合成）
# ---------------------------------------------------------------------------

# 器械词：出现在名字里就不再追加器械前缀（否则「史密斯架」会变成「器械史密斯架」）。
# 空白值 = 该词不输出任何字（`Bodyweight_Squat` 的 `bodyweight` 不必译成「自重」）。
EQUIP_ZH = {
    "barbell": "杠铃",
    "dumbbell": "哑铃",
    "cable": "绳索",
    "machine": "器械",
    "smith": "史密斯架",
    "smith machine": "史密斯架",
    "kettlebell": "壶铃",
    "kettlebells": "壶铃",
    "band": "弹力带",
    "bands": "弹力带",
    "medicine ball": "药球",
    "exercise ball": "瑞士球",
    "swiss ball": "瑞士球",
    "stability ball": "瑞士球",
    "bosu ball": "波速球",
    "ez bar": "曲杆",
    "e z curl bar": "曲杆",
    "plate": "杠铃片",
    "plates": "杠铃片",
    "sled": "雪橇",
    "rope": "绳把",
    "lever": "器械",
    "bar": "杆",
    "body only": "",
    "bodyweight": "",
}

# 器械枚举 → 前缀。`other` 不写「其他」（那是筛选标签，不是名字的一部分）。
EQUIPMENT_ZH = {
    "bodyweight": "",
    "barbell": "杠铃",
    "dumbbell": "哑铃",
    "machine": "器械",
    "cable": "绳索",
    "other": "",
}

# 修饰词：出现在动作词前就前置；出现在动作词后**也**默认前置（中文语序）。
MOD_ZH = {
    "incline": "上斜",
    "decline": "下斜",
    "seated": "坐姿",
    "sitting": "坐姿",
    "standing": "站姿",
    "lying": "仰卧",
    "prone": "俯卧",
    "supine": "仰卧",
    "kneeling": "跪姿",
    "on knees": "跪姿",
    "bent over": "俯身",
    "bent knee": "屈膝",
    "bent arm": "屈臂",
    "bent": "屈体",
    "straight arm": "直臂",
    "straight bar": "直杆",
    "straight leg": "直腿",
    "stiff leg": "直腿",
    "stiff legged": "直腿",
    "single leg": "单腿",
    "one legged": "单腿",
    "single arm": "单臂",
    "one arm": "单臂",
    "two arm": "双臂",
    "double": "双",
    "double leg": "双腿",
    "two": "双臂",
    "alternate": "交替",
    "alternating": "交替",
    "reverse": "反向",
    "rear": "后",
    "rear delt": "后束",
    "delt": "三角肌",
    "front": "前",
    "side": "侧向",
    "lateral": "侧向",
    "close grip": "窄距",
    "wide grip": "宽握",
    "medium grip": "中握距",
    "hammer grip": "锤式握",
    "reverse grip": "反握",
    "pronated grip": "正握",
    "underhand": "反手",
    "overhand": "正手",
    "supinated": "反握",
    "pronated": "正握",
    "neutral": "对握",
    "palms down": "掌心向下",
    "palms up": "掌心向上",
    "palm in": "掌心相对",
    "palms in": "掌心相对",
    "palm": "掌",
    "behind the back": "背后",
    "behind the head": "头后",
    "behind the neck": "颈后",
    "behind neck": "颈后",
    "overhead": "过头",
    "donkey": "驴式",
    "deficit": "垫高",
    "from deficit": "垫高",
    "from blocks": "垫木上",
    "below the knees": "膝下",
    "below knees": "膝下",
    "off pins": "架上起",
    "from pins": "架上起",
    "box": "箱上",
    "floor": "地上",
    "on the floor": "地上",
    "wall": "靠墙",
    "against wall": "靠墙",
    "cross body": "交叉",
    "cross": "交叉",
    "hammer": "锤式",
    "inverted": "倒身",
    "suspended": "悬吊",
    "weighted": "负重",
    "isometric": "等长",
    "static": "静态",
    "rotational": "旋转",
    "rotation": "旋转",
    "with bands": "弹力带",
    "with chains": "加铁链",
    "chain": "铁链",
    "with straps": "用拉力带",
    "with a twist": "带转体",
    "with dumbbells": "持哑铃",
    "with neutral grip": "对握",
    "with palms in": "掌心相对",
    "with palms facing in": "掌心相对",
    "to the side": "侧向",
    "to chin": "至下巴",
    "to the chin": "至下巴",
    "to": "至",
    "head on bench": "头靠凳",
    "one and a quarter": "一次半",
    "speed": "速度",
    "explosive": "爆发",
    "vertical": "垂直",
    "horizontal": "水平",
    "low": "低位",
    "high": "高位",
    "upper": "上",
    "lower": "下",
    "middle": "中",
    "mid": "中位",
    "medium": "中位",
    "close stance": "窄站距",
    "narrow stance": "窄站距",
    "narrow": "窄",
    "wide stance": "宽站距",
    "wide": "宽",
    "sumo": "相扑",
    "goblet": "高脚杯",
    "zercher": "泽奇",
    "jefferson": "杰斐逊",
    "power": "力量",
    "side bending": "侧屈",
    "hang": "悬垂",
    "hanging": "悬垂",
    "arm": "臂",
    "leg": "腿",
    "ab": "腹",
    "abs": "腹",
    "oblique": "腹斜",
    "external": "外",
    "internal": "内",
    "hip": "髋",
    "glute": "臀",
    "glutes": "臀",
    "calf": "小腿",
    "thigh": "大腿",
    "back": "背",
    "chest": "胸",
    "shoulder": "肩",
    "shoulders": "肩",
    "elbow": "肘",
    "wrist": "腕",
    "forearm": "前臂",
    "bicep": "二头",
    "biceps": "二头",
    "tricep": "三头",
    "triceps": "三头",
    "lat": "背阔",
    "lats": "背阔",
    "trap": "斜方",
    "traps": "斜方",
    "scapular": "肩胛",
    "spinal": "脊柱",
    "full": "完整",
    "partial": "半程",
    "half": "半程",
    "quarter": "四分之一",
    "3/4": "四分之三",
    "towel": "毛巾",
    "neck": "颈",
    "pistol": "手枪",
    "sissy": "西斯",
    "hack": "哈克",
    "anti": "反重力",
    "assisted": "辅助",
    "backward": "向后",
    "bench": "凳上",
    "board": "木板",
    "bottoms": "倒立",
    "bradford": "布拉德福德",
    "chair": "椅上",
    "cuban": "古巴",
    "diagonal": "斜向",
    "elevated": "垫高",
    "fast": "快速",
    "flat": "平凳",
    "flexor": "屈肌",
    "frankenstein": "弗兰肯斯坦",
    "grip": "握",
    "guillotine": "断头台",
    "halo": "绕头",
    "heaving": "借力",
    "inner": "内侧",
    "jackknife": "折刀",
    "leverage": "器械",
    "long": "长杆",
    "military": "军事",
    "muscle": "肌肉",
    "olympic": "奥林匹克",
    "pallof": "帕洛夫",
    "parallel": "双杠",
    "pin": "架上",
    "plie": "相扑式",
    "plyo": "爆发式",
    "prowler": "雪橇推车",
    "pulley": "滑轮",
    "rack": "架上",
    "range of motion": "全幅度",
    "full range of motion": "全幅度",
    "ring": "吊环",
    "romanian": "罗马尼亚",
    "russian": "俄罗斯",
    "see saw": "跷跷板",
    "shotgun": "霰弹式",
    "sledgehammer": "大锤",
    "spider": "蜘蛛",
    "split": "分腿",
    "straight": "直",
    "t": "丁字",
    "v": "三角把",
    "flutter": "打水",
    "bicycle": "自行车",
    "jumping": "跳跃",
    "skipping": "跳绳",
    "walking": "行走",
    "and": "",
    "with": "持",
    "of": "",
    "the": "",
    "a": "",
    "an": "",
    "for": "",
}

# 留在动作词**后面**的修饰（版本/附件才是后缀；其余前置更符合中文语序）。
POST_ZH = {
    "version": "版本",
    "attachment": "附件",
}

# 动作名词：贪心取最长匹配，同长取**最靠后**的（`Barbell Walking Lunge` 要认「lunge」
# 而不是「walking」，`Clean Deadlift` 要认「deadlift」而不是「clean」）。
HEAD_ZH = {
    "internal rotation": "内旋",
    "external rotation": "外旋",
    "bench press": "卧推",
    "chest press": "推胸",
    "press": "推举",
    "presses": "推举",
    "push press": "借力推举",
    "squat": "深蹲",
    "squats": "深蹲",
    "split squat": "分腿蹲",
    "hack squat": "哈克深蹲",
    "deadlift": "硬拉",
    "deadlifts": "硬拉",
    "stiff leg deadlift": "直腿硬拉",
    "rack pull": "架上硬拉",
    "rack pulls": "架上硬拉",
    "row": "划船",
    "rows": "划船",
    "upright row": "直立划船",
    "curl": "弯举",
    "curls": "弯举",
    "hammer curl": "锤式弯举",
    "hammer curls": "锤式弯举",
    "preacher curl": "牧师凳弯举",
    "concentration curl": "集中弯举",
    "concentration curls": "集中弯举",
    "wrist curl": "腕弯举",
    "drag curl": "拖拽弯举",
    "raise": "平举",
    "raises": "平举",
    "lateral raise": "侧平举",
    "front raise": "前平举",
    "calf raise": "提踵",
    "calf raises": "提踵",
    "toe raise": "提踵",
    "toe raises": "提踵",
    "fly": "飞鸟",
    "flye": "飞鸟",
    "flyes": "飞鸟",
    "reverse fly": "反向飞鸟",
    "rear delt fly": "反向飞鸟",
    "pulldown": "下拉",
    "pulldowns": "下拉",
    "lat pulldown": "高位下拉",
    "pull up": "引体向上",
    "pull ups": "引体向上",
    "pullup": "引体向上",
    "pullups": "引体向上",
    "chin up": "反手引体向上",
    "chin ups": "反手引体向上",
    "push up": "俯卧撑",
    "push ups": "俯卧撑",
    "pushup": "俯卧撑",
    "pushups": "俯卧撑",
    "dip": "臂屈伸",
    "dips": "臂屈伸",
    "plank": "平板支撑",
    "crunch": "卷腹",
    "crunches": "卷腹",
    "sit up": "仰卧起坐",
    "sit ups": "仰卧起坐",
    "extension": "伸展",
    "extensions": "伸展",
    "triceps extension": "臂屈伸",
    "triceps extensions": "臂屈伸",
    "tricep extension": "臂屈伸",
    "french press": "颈后臂屈伸",
    "skullcrusher": "仰卧臂屈伸",
    "pushdown": "下压",
    "pushdowns": "下压",
    "lunge": "箭步蹲",
    "lunges": "箭步蹲",
    "step up": "台阶踏上",
    "step ups": "台阶踏上",
    "swing": "摆动",
    "swings": "摆动",
    "clean": "高翻",
    "snatch": "抓举",
    "jerk": "挺举",
    "pull": "拉",
    "pulls": "拉",
    "balance": "平衡",
    "shrug": "耸肩",
    "shrugs": "耸肩",
    "good morning": "早安式",
    "good mornings": "早安式",
    "hyperextension": "山羊挺身",
    "hyperextensions": "山羊挺身",
    "back extension": "背伸展",
    "pullover": "仰卧上拉",
    "pullovers": "仰卧上拉",
    "kickback": "后踢",
    "kickbacks": "后踢",
    "twist": "转体",
    "twists": "转体",
    "russian twist": "俄罗斯转体",
    "thruster": "蹲推",
    "hip thrust": "臀推",
    "glute bridge": "臀桥",
    "dead bug": "死虫式",
    "bird dog": "鸟狗式",
    "jackknife": "折刀",
    "scissor": "剪刀腿",
    "pull through": "胯下拉",
    "face pull": "面拉",
    "rollout": "滚轮",
    "rollouts": "滚轮",
    "side bend": "体侧屈",
    "hip raise": "抬髋",
    "hip raises": "抬髋",
    "leg raise": "举腿",
    "leg raises": "举腿",
    "leg curl": "腿弯举",
    "leg curls": "腿弯举",
    "leg extension": "腿屈伸",
    "leg extensions": "腿屈伸",
    "leg press": "腿举",
    "knee raise": "抬膝",
    "knee raises": "抬膝",
    "inverted row": "倒身划船",
    "mountain climbers": "登山者攀爬",
    "get up": "起身",
    "carry": "提行",
    "bend": "弯腰",
    "jump": "跳",
    "jumps": "跳",
    "hop": "跳",
    "hops": "跳",
    "bound": "跨步跳",
    "bounds": "跨步跳",
    "throw": "抛",
    "throws": "抛",
    "bike": "骑车",
    "bicycling": "骑车",
    "run": "跑",
    "running": "跑",
    "sprint": "冲刺",
    "walk": "行走",
    "air bike": "空中单车",
    "bear crawl": "熊爬",
    "crawl": "爬",
    "crawls": "爬",
    "slam": "砸",
    "slams": "砸",
    "drag": "拖拽",
    "drags": "拖拽",
    "pike": "折体举腿",
    "chest squeezes": "夹胸",
    "pull in": "抱膝",
}

MANUAL_SENTINEL = "-"  # name_zh.tsv 里 `-` 表示「不输出前缀」
LATIN = re.compile(r"[A-Za-z]")


class BuildError(SystemExit):
    """构建失败（缺译、id 冲突、分布不达标……都要显眼退出，不能悄悄少几条）。"""


def normalize_name(name: str) -> str:
    """归一化英文名：小写、`-`/`_` → 空格、折叠空白。词表键必须同样归一化。"""
    lowered = name.lower().replace("-", " ").replace("_", " ")
    return re.sub(r"\s+", " ", lowered).strip()


def load_full_names(path: Path) -> dict[str, str]:
    """`name_zh.tsv`：两列 `归一化英文名 \t 中文`，整名覆盖不规则名。"""
    table: dict[str, str] = {}
    for lineno, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) != 2:
            raise BuildError(f"{path.name}:{lineno} 不是两列：{line!r}")
        key, value = (part.strip() for part in parts)
        normalized = normalize_name(key)
        if normalized in table:
            raise BuildError(f"{path.name}:{lineno} 重复键：{normalized!r}")
        table[normalized] = "" if value == MANUAL_SENTINEL else value
    return table


def longest_head(tokens: list[str]) -> tuple[int, int, str] | None:
    """最长动作词短语；同长取最靠后（见 HEAD_ZH 的注释）。"""
    best: tuple[int, int, str] | None = None
    for start in range(len(tokens)):
        for end in range(len(tokens), start, -1):
            phrase = " ".join(tokens[start:end])
            if phrase in HEAD_ZH:
                if best is None or (end - start) >= (best[1] - best[0]):
                    best = (start, end, phrase)
                break
    return best


def consume_left(tokens: list[str]) -> tuple[list[str], bool]:
    """消费动作词**前面**的词。返回 (中文, 是否已经写出器械)。

    第二项是必需的：`Smith_Machine_Squat` 的 `smith machine` 已在名字里写出
    「史密斯架」，再追加器械前缀就成了「器械史密斯架深蹲」。
    """
    out: list[str] = []
    saw_equipment = False
    index = 0
    while index < len(tokens):
        for span in range(len(tokens) - index, 0, -1):
            phrase = " ".join(tokens[index : index + span])
            if phrase in EQUIP_ZH:
                out.append(EQUIP_ZH[phrase])
                saw_equipment = True
                index += span
                break
            if phrase in MOD_ZH:
                out.append(MOD_ZH[phrase])
                index += span
                break
            if phrase in HEAD_ZH:
                out.append(HEAD_ZH[phrase])
                index += span
                break
        else:
            raise KeyError(f"left:{tokens[index]}")
    return out, saw_equipment


def consume_right(tokens: list[str]) -> tuple[list[str], list[str]]:
    """消费动作词**后面**的词。返回 (前置修饰, 后缀修饰)。"""
    prefix: list[str] = []
    suffix: list[str] = []
    index = 0
    while index < len(tokens):
        for span in range(len(tokens) - index, 0, -1):
            phrase = " ".join(tokens[index : index + span])
            if phrase in POST_ZH:
                suffix.append(POST_ZH[phrase])
                index += span
                break
            if phrase in EQUIP_ZH:
                prefix.append(EQUIP_ZH[phrase])
                index += span
                break
            if phrase in MOD_ZH:
                prefix.append(MOD_ZH[phrase])
                index += span
                break
            if phrase in HEAD_ZH:
                prefix.append(HEAD_ZH[phrase])
                index += span
                break
        else:
            raise KeyError(f"right:{tokens[index]}")
    return prefix, suffix


def translate(name: str, equipment: str, full_names: dict[str, str]) -> str:
    """英文名 → 中文名：整名覆盖 → 「姿势 + 器械 + 动作 + 后缀」合成。"""
    key = normalize_name(name)
    if key in full_names:
        result = full_names[key]
    else:
        tokens = key.split(" ")
        head = longest_head(tokens)
        if head is None:
            raise KeyError(f"head:{key}")
        start, end, phrase = head
        left, saw_equipment = consume_left(tokens[:start])
        prefix, suffix = consume_right(tokens[end:])
        equipment_zh = "" if saw_equipment else EQUIPMENT_ZH[equipment]
        result = "".join([*left, *prefix, equipment_zh, HEAD_ZH[phrase], *suffix])
    if not result or LATIN.search(result):
        raise BuildError(f"译名不合格（含拉丁字母或为空）：{name} → {result!r}")
    return result


def popularity(record: dict, group: str) -> int:
    score = POPULARITY_BASE
    score += POPULARITY_MECHANIC.get(record.get("mechanic"), 0)
    if len(record.get("primaryMuscles") or []) >= 2:
        score += MULTI_MUSCLE_BONUS
    score += POPULARITY_GROUP[group]
    score += POPULARITY_EQUIPMENT.get(record.get("equipment"), 0)
    score += POPULARITY_LEVEL.get(record.get("level"), 0)
    score += POPULARITY_CATEGORY.get(record.get("category"), 0)
    return max(5, min(100, score))


class Candidate:
    def __init__(
        self, record: dict, group: str, local_id: str, is_continuation: bool
    ) -> None:
        self.record = record
        self.group = group
        self.local_id = local_id
        # 续号行（id_overrides.tsv 里映射回 v2 的本地 id）必须**无条件入选**：
        # 它们是用户库里已经存在的动作。按分数选的话，像「俯卧撑」（87 分）
        # 会被一堆 89 分的哑铃卧推挤出胸部前 40 —— 换源把老动作挤掉是回归，
        # 不是扩充（W6 初版就这么掉过 20 条，见证据里的「续号必选」）。
        self.is_continuation = is_continuation
        self.name_en = record["name"]
        self.normalized = normalize_name(self.name_en)
        self.equipment = EQUIPMENT_MAP[record["equipment"]]
        self.difficulty = LEVEL_TO_DIFFICULTY[record["level"]]
        self.popularity = popularity(record, group)

    @property
    def sort_key(self) -> tuple:
        return (-self.popularity, self.name_en, self.record["id"])


def slug(identifier: str) -> str:
    return "ex-" + re.sub(r"[^a-z0-9]+", "-", identifier.lower()).strip("-")


def load_candidates() -> list[Candidate]:
    raw = json.loads(RAW.read_text(encoding="utf-8"))
    overrides: dict[str, str] = {}
    for lineno, line in enumerate(
        ID_OVERRIDES.read_text(encoding="utf-8").splitlines(), 1
    ):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) != 2:
            raise BuildError(f"{ID_OVERRIDES.name}:{lineno} 不是两列：{line!r}")
        overrides[parts[0].strip()] = parts[1].strip()

    candidates: list[Candidate] = []
    seen_ids: dict[str, str] = {}
    for record in raw:
        primary = record["primaryMuscles"][0] if record["primaryMuscles"] else None
        if record["category"] in EXCLUDED_CATEGORIES:
            continue
        group = MUSCLE_TO_GROUP.get(primary)
        if record["id"] in FULLBODY_IDS or record["category"] in FULLBODY_CATEGORIES:
            group = "fullBody"
        if group is None:
            continue
        if record["equipment"] not in EQUIPMENT_MAP:
            raise BuildError(f"上游器械未映射：{record['equipment']!r}（{record['id']}）")
        if record["level"] not in LEVEL_TO_DIFFICULTY:
            raise BuildError(f"上游难度未映射：{record['level']!r}（{record['id']}）")
        local_id = overrides.get(record["id"]) or slug(record["id"])
        if local_id in seen_ids:
            raise BuildError(
                f"本地 id 冲突：{local_id}（{seen_ids[local_id]} 与 {record['id']}）"
            )
        seen_ids[local_id] = record["id"]
        candidates.append(
            Candidate(record, group, local_id, record["id"] in overrides)
        )

    unknown = set(overrides) - {record["id"] for record in raw}
    if unknown:
        raise BuildError(f"id_overrides.tsv 里的上游 id 不存在：{sorted(unknown)}")
    return candidates


def load_manual_rows() -> list[dict]:
    rows: list[dict] = []
    for lineno, line in enumerate(MANUAL_ROWS.read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        parts = [part.strip() for part in line.split("\t")]
        if len(parts) != 7:
            raise BuildError(f"{MANUAL_ROWS.name}:{lineno} 不是七列：{line!r}")
        identifier, name, group, equipment, difficulty, popularity, reason = parts
        if LATIN.search(name):
            raise BuildError(f"{MANUAL_ROWS.name}:{lineno} 手写名含拉丁字母：{name!r}")
        rows.append(
            {
                "id": identifier,
                "name": name,
                "muscle_group": group,
                "equipment": equipment,
                "difficulty": difficulty or None,
                "popularity": int(popularity) if popularity else None,
                "origin": ORIGIN_MANUAL,
                "reason": reason,
            }
        )
    if len({row["name"] for row in rows}) != len(rows):
        raise BuildError("manual_rows.tsv 里手写名重复")
    return rows


def select(candidates: list[Candidate]) -> tuple[list[Candidate], list[str]]:
    """按肌群目标取分 → 每肌群补足高级 → 每档器械补到下限。全部可重跑。"""
    notes: list[str] = []
    used_names: set[str] = set()
    used_local_ids: set[str] = set()
    by_group: dict[str, list[Candidate]] = {group: [] for group in GROUP_ORDER}
    ordered = sorted(candidates, key=lambda item: item.sort_key)

    def admit(candidate: Candidate) -> bool:
        if candidate.normalized in used_names:
            return False  # 上游英文重名：只留分最高的那条
        if len(by_group[candidate.group]) >= GROUP_TARGETS[candidate.group]:
            return False
        by_group[candidate.group].append(candidate)
        used_names.add(candidate.normalized)
        used_local_ids.add(candidate.local_id)
        return True

    # 第一轮：续号行无条件先占位（老动作不能被新一批高分动作挤掉）。
    continuations = [item for item in ordered if item.is_continuation]
    for candidate in continuations:
        if not admit(candidate):
            notes.append(f"续号行 {candidate.name_en} 与高分动作重名，未入选")
    # 第二轮：按分数补到各肌群目标条数。
    for candidate in ordered:
        if candidate.is_continuation:
            continue
        admit(candidate)

    for group in GROUP_ORDER:
        chosen = by_group[group]
        missing = GROUP_TARGETS[group] - len(chosen)
        if missing > 0:
            notes.append(f"{group} 只有 {len(chosen)} 条，比目标少 {missing}")
        advanced = [item for item in chosen if item.difficulty == "advanced"]
        need = ADVANCED_FLOOR - len(advanced)
        if need <= 0:
            continue
        pool = [
            item
            for item in sorted(candidates, key=lambda entry: entry.sort_key)
            if item.group == group
            and item.difficulty == "advanced"
            and item.local_id not in used_local_ids
            and item.normalized not in used_names
        ]
        victims = sorted(
            (
                item
                for item in chosen
                if item.difficulty != "advanced" and not item.is_continuation
            ),
            key=lambda item: item.sort_key,
        )[-need:]
        for addition, victim in zip(pool[:need], victims):
            chosen.remove(victim)
            chosen.append(addition)
            used_names.discard(victim.normalized)
            used_local_ids.discard(victim.local_id)
            used_names.add(addition.normalized)
            used_local_ids.add(addition.local_id)
            notes.append(f"{group} 用 {addition.name_en} 换掉 {victim.name_en}（高级下限）")

    selected = [item for group in GROUP_ORDER for item in by_group[group]]

    # 器械下限：从每个不足 20 的档里按分数补人（会略微超出总数，所以叫「约 300」）。
    counts = Counter(item.equipment for item in selected)
    for equipment in EQUIPMENT_ORDER:
        if counts[equipment] >= EQUIPMENT_FLOOR:
            continue
        pool = [
            item
            for item in sorted(candidates, key=lambda entry: entry.sort_key)
            if item.equipment == equipment
            and item.local_id not in used_local_ids
            and item.normalized not in used_names
        ]
        shortage = EQUIPMENT_FLOOR - counts[equipment]
        if len(pool) < shortage:
            raise BuildError(
                f"器械档 {equipment} 只有 {counts[equipment]} 条，可补的候选也不够"
                f"（需 ≥ {EQUIPMENT_FLOOR}）"
            )
        for item in pool[:shortage]:
            selected.append(item)
            used_local_ids.add(item.local_id)
            used_names.add(item.normalized)
            counts[equipment] += 1
        notes.append(f"{equipment} 补到 {counts[equipment]} 条（器械下限 {EQUIPMENT_FLOOR}）")
    return selected, notes


def build(report: bool, dump: bool, check: bool = False) -> int:
    full_names = load_full_names(NAME_ZH)
    candidates = load_candidates()
    manual = load_manual_rows()
    selected, notes = select(candidates)

    rows: list[dict] = []
    failures: list[str] = []
    for candidate in selected:
        try:
            name = translate(candidate.name_en, candidate.equipment, full_names)
        except KeyError as error:
            failures.append(f"{error.args[0]}\t{candidate.name_en}")
            continue
        rows.append(
            {
                "id": candidate.local_id,
                "name": name,
                "muscle_group": candidate.group,
                "equipment": candidate.equipment,
                "difficulty": candidate.difficulty,
                "popularity": candidate.popularity,
                "origin": ORIGIN_UPSTREAM,
                "_en": candidate.name_en,
            }
        )
    for row in manual:
        if row["name"] in {entry["name"] for entry in rows}:
            failures.append(f"与上游译名撞名\t{row['name']}")
            continue
        rows.append({key: value for key, value in row.items() if key != "reason"} | {"_en": ""})

    duplicates = [
        f"{name}（{count} 条）"
        for name, count in Counter(row["name"] for row in rows).items()
        if count > 1
    ]

    order = {group: index for index, group in enumerate(GROUP_ORDER)}
    rows.sort(key=lambda row: (order[row["muscle_group"]], row["name"], row["id"]))

    group_counts = Counter(row["muscle_group"] for row in rows)
    equipment_counts = Counter(row["equipment"] for row in rows)
    difficulty_counts = Counter(row["difficulty"] for row in rows if row["difficulty"])

    print(f"候选池 {len(candidates)} 条（上游 {len(json.loads(RAW.read_text('utf-8')))} 条）")
    print(f"选中 {len(rows)} 条（上游派生 {len(rows) - len(manual)} + 手写保留 {len(manual)}）")
    print("肌群：" + "、".join(f"{group} {group_counts[group]}" for group in GROUP_ORDER))
    print("器械：" + "、".join(f"{name} {equipment_counts[name]}" for name in EQUIPMENT_ORDER))
    print("难度：" + "、".join(f"{key} {value}" for key, value in sorted(difficulty_counts.items())))
    popularity_values = [row["popularity"] for row in rows if row["popularity"] is not None]
    print(
        f"常用度：{min(popularity_values)}–{max(popularity_values)}，"
        f"{len(set(popularity_values))} 个不同取值"
    )
    for note in notes:
        print(f"  · {note}")
    if dump:
        print("\n肌群\t器械\t难度\t常用度\t上游名\t中文名")
        for row in rows:
            print(
                f"{row['muscle_group']}\t{row['equipment']}\t{row['difficulty']}\t"
                f"{row['popularity']}\t{row['_en']}\t{row['name']}"
            )
    if failures:
        print(f"\n缺译/撞名 {len(set(failures))} 处（缺译即失败）：", file=sys.stderr)
        for failure in sorted(set(failures)):
            print(f"  {failure}", file=sys.stderr)
        return 1
    if duplicates:
        print("译名重复（必须整名覆盖消歧）：", file=sys.stderr)
        for duplicate in duplicates:
            print(f"  {duplicate}", file=sys.stderr)
        return 1
    short = [group for group in GROUP_ORDER if group_counts[group] < GROUP_TARGETS[group] - 2]
    if short:
        print(f"肌群缺口过大：{short}", file=sys.stderr)
        return 1
    for equipment in EQUIPMENT_ORDER:
        if equipment_counts[equipment] < EQUIPMENT_FLOOR:
            print(f"器械档 {equipment} 不足 {EQUIPMENT_FLOOR}", file=sys.stderr)
            return 1
    if len(difficulty_counts) != 3:
        print("难度三档不齐", file=sys.stderr)
        return 1

    document = {
        "version": VERSION,
        "exercises": [
            {key: value for key, value in row.items() if not key.startswith("_")}
            for row in rows
        ],
    }
    serialized = json.dumps(document, ensure_ascii=False, separators=(",", ":"))
    if check:
        if OUT.read_text(encoding="utf-8") != serialized:
            print(
                "随包资产与重建结果不一致：跑一次 build_exercises.py 重新生成"
                "（脚本是唯一事实源，手改资产会被这一步抓住）",
                file=sys.stderr,
            )
            return 1
        print("\n--check：随包资产与重建结果逐字节一致")
        return 0
    if report:
        print("\n--report：未写文件")
        return 0
    OUT.write_text(serialized, encoding="utf-8")
    print(f"\n写入 {OUT}（{OUT.stat().st_size} 字节）")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="生成 exercises.v3.json（docs/28 §7）")
    parser.add_argument("--report", action="store_true", help="只报告，不写资产文件")
    parser.add_argument("--dump", action="store_true", help="再打印逐条清单（人工复核译名）")
    parser.add_argument(
        "--check",
        action="store_true",
        help="重建并与随包资产逐字节比对（不写文件），用于测试与 CI",
    )
    args = parser.parse_args(sys.argv[1:] if argv is None else argv)
    return build(report=args.report, dump=args.dump, check=args.check)


if __name__ == "__main__":
    sys.exit(main())
