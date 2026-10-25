#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Generate assets/seed/foods.v4.json from the FoodCalu food database.

Source (see raw/foodcalu/ and tool/food_seed/README.md):
  raw/foodcalu/food_database.db : FoodCalu 随包 SQLite
      github.com/gaosheng293/FoodCalu 的 app/src/main/assets/food_database.db
      （表 food: id/name/calories/protein/fat/carbs，均为每 100g 值）
      上游未声明许可证，与 CFCT 同属「个人自用、不再分发」来源。

Non-Chinese names are translated by hand in raw/foodcalu/name_zh.tsv; this
script refuses to run while any name without Han characters lacks a
translation, so a new upstream drop cannot silently ship Latin names.

Output schema matches FoodSeedImporter: per-100g macros plus conservative
dietary labels / allergens inferred from the food name (knowledge=known only
when the name is unambiguous; mixed dishes, brand-only names and processed
products stay unknown unless the name itself names an allergen).
"""
import json
import re
import sqlite3
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
RAW = HERE / "raw" / "foodcalu"
DB = RAW / "food_database.db"
ZH = RAW / "name_zh.tsv"
OUT = HERE.parent.parent / "assets" / "seed" / "foods.v4.json"

V, VG, DF, GF = "vegetarian", "vegan", "dairyFree", "glutenFree"

HAN = re.compile(r"[\u4e00-\u9fff]")

# ---------------------------------------------------------------- name事实推断
# 「素鸡/植物肉」这类名字里带动物词但是植物制品，先剔除再判动物性。
RE_PLANT_SUBSTITUTE = re.compile(r"素鸡|素鸭|素肉|素火腿|素肠|植物肉|植物蛋白")
# 动物词：鸡蛋/牛奶 里的 鸡/牛 不构成「肉」。
RE_MEAT = re.compile(
    r"猪|牛|羊|鸡|鸭|鹅|火鸡|兔|驴|鹿|肉|排骨|里脊|腩|火腿|培根|香肠|腊肠|腊肉"
    r"|叉烧|肉松|肉酱|肉丸|肉饼|肉干|肉脯|肠|肝|蹄|爪|翅|腿|胸|烧鹅|烧鸭|卤"
)
RE_FISH = re.compile(r"鱼|鳀|鳕|鲈|鳗|鳝|鲅|鲳|鲑|鲷|鲶|鲆|鲽|沙丁|金枪")
# 甲壳/软体：只认明确的贝类词，不认单独的「贝」——「贝果/贝蒂妙厨/巴黎贝甜」
# 这类品牌与器形词（贝壳面）会让几百条烘焙品被误标 shellfish。
RE_SHELLFISH = re.compile(
    r"虾|蟹|蛤|蚝|牡蛎|扇贝|干贝|鲜贝|海贝|全贝|赤贝|北极贝|贝肉|贝柱|贝类"
    r"|瑶柱|带子|花甲|淡菜|螺|鱿|章鱼|鲍|蚬|蛏|蚌|蚶|海参|海蜇"
)
RE_EGG = re.compile(r"蛋")
RE_DAIRY = re.compile(r"奶|乳|奶酪|芝士|黄油|奶油|酸奶|炼乳|干酪|起司|优格")
RE_SOY = re.compile(r"大豆|黄豆|豆腐|豆浆|腐竹|豆豉|千张|豆皮|豆干|豆奶|毛豆|豆花|腐乳|纳豆|素鸡")
RE_PEANUT = re.compile(r"花生")
RE_TREENUT = re.compile(r"核桃|杏仁|腰果|开心果|榛子|榛果|松子|巴旦木|碧根果|夏威夷果|板栗|栗子")
RE_SESAME = re.compile(r"芝麻")
RE_WHEAT = re.compile(
    r"小麦|面粉|面条|挂面|拉面|面|馒头|包子|饺子|馄饨|面包|土司|吐司|饼干|蛋糕|糕|酥|派|塔"
    r"|华夫|贝果|汉堡|麦|麸|披萨|意面|通心粉|油条|烧饼|煎饼"
)
RE_RICE = re.compile(r"大米|米饭|米线|米粉|糯米|小米|玉米|高粱|燕麦|荞麦|薏米|粥|饭|年糕|米糕")
# 复合/加工：名字本身说明不是单一食材，不声明饮食属性。
RE_COMPOSITE = re.compile(
    r"品牌|餐厅|料理|酱|汁|调味|汤|方便|速食|罐头|罐|丸|肠|糕|酥|糖|饮料|酒|咖啡"
    r"|雪糕|冰淇淋|零食|沙拉|布丁|果冻|蜜饯|果脯|寿司|披萨|汉堡|卷|棒|代餐|风味"
)
# 明确的植物词：只有出现这些词才声明 V/VG（避免「伊利 安慕希」这类名字被默认成素食）。
RE_PLANT = re.compile(
    r"菜|蔬|果|瓜|豆|米|麦|粉|薯|芋|藕|菇|菌|耳|笋|葱|蒜|姜|椒|茄|萝卜|白菜|菠菜|芹"
    r"|韭|黄瓜|番茄|西红柿|苹果|香蕉|橙|桔|橘|柚|柠檬|桃|梨|葡萄|莓|枣|枸杞|坚果|仁|籽"
    r"|叶|茎|玉米|芝麻|蜂蜜|菊花|薄荷|山楂|梅|椰|杏|李|柿|石榴|荔枝|龙眼|芒果|菠萝|木瓜"
    r"|猕猴桃|火龙果|榴莲|山竹|枇杷|杨梅|甘蔗|甜菜|南瓜|冬瓜|丝瓜|苦瓜|西葫芦|芦笋|生菜"
    r"|莴苣|香菜|茴香|芥|秋葵|西兰花|花菜|卷心菜|甘蓝|蘑菇|木耳|银耳|香菇|金针菇|平菇"
    r"|海带|紫菜|裙带菜|豆腐|坚果|杏仁|核桃|茶|麦片|燕麦|荞麦|藜麦|意面|米粉|米线|杂粮"
)

# 「肉」在这些词里不代表肉：肉桂（香料）、果肉（水果可食部分）、皮蛋瘦肉粥里的
# 瘦肉是真的肉，不剔除。「奶白菜」是菜不是奶。蛋白粉/蛋白棒/蛋白肽是补充剂。
RE_NOT_MEAT = re.compile(r"肉桂|果肉")
RE_NOT_DAIRY = re.compile(r"奶白菜")
RE_NOT_EGG = re.compile(r"蛋白(?:粉|棒|肽)")
# 品牌名与食物名撞车：金龙鱼（粮油品牌）、鲍勃红磨坊（Bob's Red Mill）、
# 鱼腥草（植物）。器形词：螺旋/螺丝/螺纹/陀螺面（意面形状）、贝壳形。
RE_NOT_FISH = re.compile(r"金龙鱼|鱼腥草")
RE_NOT_SHELLFISH = re.compile(r"鲍勃|螺旋|螺丝|螺纹|螺形|螺号|陀螺|贝壳|蟹味菇")


def _probe(name: str) -> str:
    """去掉「鸡蛋/牛奶」这类里的动物字，再判是否含肉词。"""
    s = RE_PLANT_SUBSTITUTE.sub("", name)
    s = RE_NOT_MEAT.sub("", s)
    return re.sub(r"(鸡|鸭|鹅|牛|羊|猪)(蛋|奶|乳)", "", s)


def name_facts(name: str):
    """Return (knowledge, labels, allergens) for a food name.

    Conservative: 只有名字本身说得清时才声明 known；复合菜/品牌名/加工品
    保持 unknown（与 unknown ⇒ 无标签无过敏原 的契约一致）。
    """
    allergens = set()
    meat = bool(RE_MEAT.search(_probe(name)))
    fish = bool(RE_FISH.search(RE_NOT_FISH.sub("", name)))
    shell = bool(RE_SHELLFISH.search(RE_NOT_SHELLFISH.sub("", name)))
    egg = bool(RE_EGG.search(RE_NOT_EGG.sub("", name)))
    dairy = bool(RE_DAIRY.search(RE_NOT_DAIRY.sub("", name)))
    if dairy:
        allergens.add("milk")
    if egg:
        allergens.add("egg")
    if fish:
        allergens.add("fish")
    if shell:
        allergens.add("shellfish")
    if RE_PEANUT.search(name):
        allergens.add("peanut")
    if RE_TREENUT.search(name):
        allergens.add("treeNut")
    if RE_SESAME.search(name):
        allergens.add("sesame")
    if RE_SOY.search(name):
        allergens.add("soy")
    wheat = bool(RE_WHEAT.search(name))
    riceish = bool(RE_RICE.search(name))
    if wheat and not riceish:
        allergens.add("gluten")

    composite = bool(RE_COMPOSITE.search(name))
    animal = meat or fish or shell or egg or dairy

    if composite:
        if allergens:
            return "known", [], sorted(allergens)
        return "unknown", [], []

    labels = set()
    if meat or fish or shell:
        if not dairy:
            labels.add(DF)
        if not wheat or riceish:
            labels.add(GF)
    elif dairy or egg:
        labels.add(V)
        if not dairy:
            labels.add(DF)
        if not wheat or riceish:
            labels.add(GF)
    elif RE_PLANT.search(name):
        labels |= {V, VG, DF}
        if not wheat or riceish:
            labels.add(GF)
    else:
        # 既无动物词也无植物词（多为纯品牌名）：不猜。
        if allergens:
            return "known", [], sorted(allergens)
        return "unknown", [], []
    return "known", sorted(labels), sorted(allergens)


# ---------------------------------------------------------------- helpers
def clean_name(name: str) -> str:
    n = (name or "").replace("品牌未知", "")
    n = re.sub(r"\s+", " ", n).strip()
    return n


# 上游有 1,232 行把同一个品牌块写了两遍甚至三遍，例如
#   「Kelsen凯尔森 Kelsen 凯尔森 黄油曲奇饼干」
#   「DXC稻香村 稻香村 DXC 青团」
#   「MABROC(玛勃洛克) MABROC(玛勃洛克) MABROC(玛勃洛克) MABROC/玛勃洛克 高地锡兰红茶」
# 这些重复在界面上就是纯噪声，而它们本身**不是**需要翻译的英文——品牌名保留是
# 有意的（用户按品牌搜索）。所以这里只折叠重复，绝不翻译：
#   * 某个空格分隔段与更早的段「归一后完全相同」→ 丢弃；
#   * 或者某个非末段里的每个构件（汉字串 / ≥2 字母的拉丁词）都已在更早的段里
#     出现过 → 丢弃（「DXC稻香村 稻香村 DXC」正是这种）。
# 末段永不丢弃，全为空的段不参与，丢弃后仍须含汉字（由 main 断言）。
NAME_LAT_RUN = re.compile(r"[A-Za-z][A-Za-z0-9'’&\-\.]*")
NAME_HAN_RUN = re.compile(r"[\u4e00-\u9fff]+")
NAME_SEP = re.compile(r"[\s/、,，·\-–—\.&']+")


def _name_components(segment: str) -> list:
    components = [m.group(0) for m in NAME_HAN_RUN.finditer(segment)]
    components += [
        m.group(0).lower()
        for m in NAME_LAT_RUN.finditer(segment)
        if len(m.group(0)) >= 2
    ]
    return components


def collapse_repeated_brand_block(name: str) -> str:
    segments = [s for s in re.split(r"\s+", name.strip()) if s]
    if len(segments) < 2:
        return name
    kept = []
    seen_components = set()
    seen_segments = set()
    for index, segment in enumerate(segments):
        is_last = index == len(segments) - 1
        normalized = NAME_SEP.sub("", segment).lower()
        components = _name_components(segment)
        duplicate = bool(normalized) and normalized in seen_segments
        subsumed = (
            not is_last
            and len(normalized) >= 2
            and bool(components)
            and all(c in seen_components for c in components)
        )
        if not (duplicate or subsumed):
            kept.append(segment)
        if normalized:
            seen_segments.add(normalized)
        seen_components.update(components)
    return " ".join(kept) if kept else name


def load_translations() -> dict:
    mapping = {}
    for line in ZH.read_text(encoding="utf-8").splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) != 2:
            sys.exit(f"name_zh.tsv: 需要两列（原名<TAB>中文名）: {line!r}")
        key = re.sub(r"\s+", " ", parts[0]).strip()
        value = parts[1].strip()
        if not HAN.search(value):
            sys.exit(f"name_zh.tsv: 译名不含汉字: {line!r}")
        if key in mapping and mapping[key] != value:
            sys.exit(f"name_zh.tsv: 重复的原名: {key!r}")
        mapping[key] = value
    return mapping


def main() -> None:
    translations = load_translations()
    con = sqlite3.connect(DB)
    rows = con.execute(
        "select id, name, calories, protein, fat, carbs from food order by id"
    ).fetchall()

    foods, missing, ids, names = [], [], set(), set()
    deduped = []
    dropped_invalid = []
    collapsed = []
    for food_id, raw_name, kcal, protein, fat, carbs in rows:
        name = clean_name(raw_name)
        if not HAN.search(name):
            translated = translations.get(name)
            if translated is None:
                missing.append(name)
                continue
            name = translated
        before_collapse = name
        name = collapse_repeated_brand_block(name)
        if not name or not HAN.search(name):
            sys.exit(f"name lost its Chinese text for id={food_id}: {name!r}")
        if name != before_collapse:
            collapsed.append((food_id, before_collapse, name))
        kcal = float(kcal or 0.0)
        protein = float(protein or 0.0)
        fat = float(fat or 0.0)
        carbs = float(carbs or 0.0)
        # 上游有 2 行不可能值（蛋白质 202g/100g、碳水 228.7g/100g），这种行会
        # 直接把摄入统计算错，丢弃并打印。
        if max(protein, fat, carbs) > 100 or protein + fat + carbs > 103:
            dropped_invalid.append((food_id, name, protein, fat, carbs))
            continue
        # 源数据里热量为 0 的行（盐/水/茶/膳食纤维/糖醇类果冻等）保持原样：
        # 纤维素与糖醇确实不产能，按 Atwater 系数强补热量反而是错的。
        knowledge, labels, allergens = name_facts(name)
        seed_id = f"seed-fc-{food_id}"
        if seed_id in ids:
            sys.exit(f"duplicate seed id: {seed_id}")
        ids.add(seed_id)
        # 只差空格/斜杠/间隔号的近似重复（如「埃可托 天然多彩蔬菜面」与
        # 「埃可托天然多彩蔬菜面」），保留 id 较小的一条，其余丢弃并打印。
        # 去重跑在品牌块折叠之后，所以这里丢弃的行里含「折叠后才暴露」的真重复；
        # 当前实测共丢弃 54 条（不含折叠时已改名的 1,234 行）。
        key = re.sub(r"[\s/·]+", "", name).lower()
        if key in names:
            deduped.append((food_id, name))
            continue
        names.add(key)
        foods.append({
            "id": seed_id,
            "name": name,
            "serving_g": 100,
            "kcal": kcal,
            "protein": protein,
            "carbs": carbs,
            "fat": fat,
            "constraint_knowledge": knowledge,
            "dietary_labels": labels,
            "allergens": allergens,
        })

    if missing:
        sys.exit("name_zh.tsv 缺少下列非中文名的译名（%d 条）:\n  %s"
                 % (len(missing), "\n  ".join(missing)))
    if len(foods) + len(deduped) + len(dropped_invalid) != len(rows):
        sys.exit(f"row count mismatch: {len(foods)}+{len(deduped)}+"
                 f"{len(dropped_invalid)} != {len(rows)}")
    for f in foods:
        assert 0 <= f["kcal"] <= 1000, f
        for k in ("protein", "carbs", "fat"):
            assert 0 <= f[k] <= 100, f

    OUT.write_text(json.dumps({"version": 4, "foods": foods}, ensure_ascii=False,
                              separators=(",", ":")), encoding="utf-8")
    known = sum(1 for f in foods if f["constraint_knowledge"] == "known")
    labelled = sum(1 for f in foods if f["dietary_labels"])
    allergenic = sum(1 for f in foods if f["allergens"])
    print(f"rows: {len(foods)}, known: {known}, labelled: {labelled}, "
          f"with allergens: {allergenic}")
    print(f"dropped near-duplicate names: {len(deduped)}")
    for item in deduped:
        print(f"  dropped id={item[0]} {item[1]}")
    print(f"collapsed repeated brand blocks: {len(collapsed)}")
    for item in collapsed:
        print(f"  id={item[0]}: {item[1]!r} -> {item[2]!r}")
    print(f"dropped impossible macros: {len(dropped_invalid)}")
    for item in dropped_invalid:
        print(f"  dropped id={item[0]} {item[1]} "
              f"P/F/C={item[2]}/{item[3]}/{item[4]}")
    print(f"written {OUT} ({OUT.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
