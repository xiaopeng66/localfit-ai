# -*- coding: utf-8 -*-
"""食物库归一化 + 别名推导 + 分类审计（一次性工具，产出随包资产与审计报告）。

输入：assets/seed/user_foods_8col.v1.csv（23,919 行，用户原始数据）
输出：
  assets/seed/food_library_normalization.v1.csv   旧身份 → 新名称/品牌/分类/别名（只含需要改或能派生别名的行）
  docs/evidence/2026-10-21-food-library-audit/changes.csv   逐行改动（含原因）
  docs/evidence/2026-10-21-food-library-audit/audit-report.md 汇总 + 待人工复核清单

纪律：
  * 只做**确定性**变换（括号统一/合并、空白归一、重复品牌去重、尾规格入括号、
    短横线后缀入括号、别名派生）。拿不准的一律不改，进「待人工复核」清单。
  * 名称改动不丢信息：只把文字搬家（进括号/合并），不删任何备注文字。
  * 分类只在「关键词与基础名强匹配」时纠正；其余进复核清单。
"""
from __future__ import annotations

import csv
import io
import json
import os
import re
import sys
from collections import Counter, defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = f'{ROOT}/assets/seed/user_foods_8col.v1.csv'
OUT_CSV = f'{ROOT}/assets/seed/food_library_normalization.v1.csv'
EVID = f'{ROOT}/docs/evidence/2026-10-21-food-library-audit'

# ---- 24 个一级分类 → 十档（与 lib/.../food_category.dart 的 _libraryGroups 逐字一致）
GROUPS = {
    '谷物及主食': 'staple', '薯类及淀粉': 'staple', '粥类': 'staple', '中式面点': 'staple',
    '零食及甜品': 'snack', '烘焙食品': 'snack',
    '蔬菜及制品': 'vegetable', '菌藻类': 'vegetable',
    '水果及制品': 'fruit',
    '乳类及制品': 'dairy',
    '饮料类': 'beverage',
    '调味品': 'condiment', '油脂类': 'condiment',
    '菜肴及地方食品': 'prepared', '菜肴及快餐': 'prepared',
    '汤羹炖品': 'prepared', '酱卤熟食': 'prepared',
    '蛋类及制品': 'protein', '畜肉及制品': 'protein', '禽肉及制品': 'protein',
    '水产及制品': 'protein', '豆类及制品': 'protein', '坚果种子': 'protein',
    '其他食品': 'other',
}
CAT_LABEL = {
    'staple': '主食', 'protein': '蛋白质食物', 'vegetable': '蔬菜', 'fruit': '水果',
    'dairy': '乳制品', 'beverage': '饮品', 'snack': '零食甜点', 'condiment': '调味品',
    'prepared': '预制餐食', 'other': '其他食物',
}

# ---- 括号统一
OPEN = '（'
CLOSE = '）'
BRACKET_MAP = {
    '(': OPEN, '[': OPEN, '【': OPEN, '〔': OPEN, '「': OPEN, '『': OPEN, '《': OPEN, '〈': OPEN,
    ')': CLOSE, ']': CLOSE, '】': CLOSE, '〕': CLOSE, '」': CLOSE, '』': CLOSE, '》': CLOSE, '〉': CLOSE,
}
STRAY = '"\'“”‘’'

# ---- 备注分段里「不是别名」的词（口味/工艺/状态，单独出现时没有检索价值）
NOTE_STOPWORDS = {
    '生', '熟', '干', '湿', '鲜', '冷冻', '速冻', '冷藏', '常温', '原味', '无糖', '低糖',
    '低脂', '脱脂', '全脂', '加糖', '不加糖', '调制', '发酵', '灭菌', '巴氏杀菌', '脱盐',
    '含盐', '不加盐', '加盐', '甜', '咸', '辣', '香辣', '麻辣', '五香', '椒盐', '烧烤',
    '原切', '切片', '整粒', '去壳', '带壳', '去皮', '可食部', '均值', '代表值', '混合',
    '自制', '市售', '生鲜', '熟制', '即食', '冲泡', '冲调', '固体饮料', '粉状', '块状',
    '片状', '颗粒', '液体', '罐装', '袋装', '瓶装', '盒装', '散装', '礼盒', '组合装',
}
NOTE_NOUNS = {
    '乳', '奶', '粉', '粥', '饭', '面', '饼', '包', '糕', '酥', '糖', '酱', '汁', '油', '醋',
    '茶', '酒', '水', '肉', '鱼', '虾', '蟹', '蛋', '豆', '米', '麦', '薯', '菜', '果',
    '瓜', '菌', '菇', '藻', '藕', '笋', '椒', '葱', '姜', '蒜', '盐', '蜜', '酪',
}
UNIT_RE = re.compile(r'^\d+(\.\d+)?\s*(kg|g|mg|ml|l|克|千克|公斤|毫升|升|袋|包|瓶|盒|罐|片|粒|支|条|份|斤|两|只|个|串|块|枚|听|杯|碗)$', re.I)

# ---- 同义词表（双向展开；只在名称里出现时补另一写法）
SYNONYMS = [
    ('番茄', '西红柿'),
    ('马铃薯', '土豆'),
    ('红薯', '地瓜'), ('红薯', '番薯'),
    ('花生', '落花生'),
    ('卷心菜', '包菜'), ('卷心菜', '圆白菜'),
    ('香菜', '芫荽'),
    ('猕猴桃', '奇异果'),
    ('西兰花', '绿花菜'), ('西兰花', '青花菜'),
    ('花菜', '菜花'),
    ('豇豆', '长豆角'),
    ('鲑鱼', '三文鱼'),
    ('金枪鱼', '吞拿鱼'),
    ('奶酪', '芝士'), ('奶酪', '起司'),
    ('酸奶', '优格'),
    ('苏打水', '气泡水'),
    ('方便面', '泡面'),
    ('四季豆', '豆角'),
]

# ---- 分类审计关键词（只收高置信词；打分：名==词 强、名以词开头 中、名含词 弱）
CAT_KEYWORDS = {
    'staple': ['米饭', '大米', '糙米', '小米', '面条', '挂面', '馒头', '花卷', '包子', '饺子', '蒸米糕',
               '馄饨', '米粉', '米线', '年糕', '面包', '吐司', '燕麦', '荞麦', '玉米',
               '小麦', '面粉', '红薯', '马铃薯', '土豆', '藕粉', '粉丝', '粉条',
               '粥', '八宝饭', '粽子', '汤圆', '元宵', '窝头', '发糕', '烧饼', '油条', '烙饼'],
    'protein': ['鸡蛋', '鸭蛋', '鹅蛋', '鹌鹑蛋', '蛋黄', '蛋清', '猪肉', '牛肉', '羊肉', '鸡肉',
                '鸭肉', '鹅肉', '鸡胸', '鸡腿', '鸡翅', '猪蹄', '猪肝', '猪肚', '牛排', '鱼',
                '虾', '蟹', '贝', '蛤', '蚝', '鱿鱼', '章鱼', '海参', '豆腐', '豆干', '豆皮',
                '腐竹', '千张', '素鸡', '豆腐泡', '黑豆腐', '黄豆', '黑豆', '红豆', '绿豆',
                '花生', '核桃', '杏仁', '腰果', '松子', '瓜子', '芝麻'],
    'vegetable': ['白菜', '菠菜', '生菜', '油菜', '芹菜', '韭菜', '香菜', '黄瓜', '番茄',
                  '西红柿', '茄子', '萝卜', '胡萝卜', '青椒', '辣椒', '洋葱', '大蒜', '生姜',
                  '大葱', '香菇', '蘑菇', '木耳', '银耳', '海带', '紫菜', '豆芽', '豆角',
                  '南瓜', '冬瓜', '丝瓜', '苦瓜', '西葫芦', '莲藕', '莴笋', '竹笋', '芦笋',
                  '西兰花', '花菜', '卷心菜', '包菜', '芥蓝', '茼蒿', '空心菜'],
    'fruit': ['苹果', '香蕉', '橙', '橘子', '柑', '葡萄', '西瓜', '梨', '桃', '李子', '杏',
              '樱桃', '草莓', '蓝莓', '树莓', '芒果', '菠萝', '猕猴桃', '柚子', '柠檬', '荔枝',
              '龙眼', '石榴', '哈密瓜', '火龙果', '榴莲', '椰子', '山楂', '枇杷', '杨梅',
              '甘蔗', '柿子', '无花果', '百香果', '牛油果', '枣', '桑葚'],
    'dairy': ['牛奶', '酸奶', '鲜奶', '奶粉', '奶酪', '芝士', '炼乳', '乳酪', '奶油', '黄油', '乳脂', '酥油',
              '奶片', '奶豆腐', '发酵乳', '纯牛奶', '羊奶', '乳粉'],
    'beverage': ['可乐', '雪碧', '汽水', '咖啡', '茶', '奶茶', '果汁', '饮料', '矿泉水',
                 '苏打水', '啤酒', '白酒', '红酒', '黄酒', '米酒', '豆浆', '豆浆粉', '豆奶粉'],
    'snack': ['薯片', '锅巴', '糖果', '巧克力', '果冻', '蜜饯', '果脯', '蛋糕', '曲奇', '饼干', '麻花',
              '威化', '膨化', '爆米花', '瓜子酥', '麻花', '沙琪玛', '雪糕', '冰淇淋', '冰棍'],
    'condiment': ['酱油', '生抽', '老抽', '醋', '食盐', '盐', '味精', '鸡精', '蚝油', '料酒',
                  '豆瓣酱', '甜面酱', '辣椒酱', '芝麻酱', '花生酱', '番茄酱', '沙拉酱',
                  '食用油', '花生油', '菜籽油', '橄榄油', '大豆油', '香油', '调和油', '白糖',
                  '红糖', '冰糖', '蜂蜜', '胡椒粉', '花椒', '八角', '桂皮', '咖喱'],
    'prepared': ['炒', '烧', '炖', '煮', '蒸', '炸', '煎', '烤', '拌', '卤', '酱', '汤',
                 '羹', '煲', '锅', '糕', '丸', '串', '汉堡', '披萨', '寿司'],
    'other': [],
}
# 出现在「别的类」里很正常的词：复合名/加工品不据此判
WEAK_IN_COMPOUND = re.compile('菜|汤|饭|面|包|饼|卷|糕|酱|汁|味|香|丝|片|丁|块|丸|串|烤|炸|卤|炒|拌|蒸|煮|炖|干|脯|条|果|露|沙|饮|酥|油|粉|乳|酪')
# 风味/工艺标记：出现它说明这是**加工零食**（紫菜（辣味）是零食，不是蔬菜）
FLAVOR_RE = re.compile('味|香|辣|麻|椒盐|芥|蒜|烧烤|原味|盐焗|卤|蜜|糖|甜|咸|酸|醋|奶油|巧克力|海苔|番茄|牛肉|鸡肉|芝士')
PREPARED_MARK = re.compile('炒|烧|炖|煮|蒸|炸|煎|烤|拌|卤|酱|汤|羹|煲|锅|丸|串')


def split_notes(note: str) -> list[str]:
    # 只按中文分号/顿号/逗号切：斜杠不切（"脂肪3g/100g" 会被切坏）
    return [seg.strip() for seg in re.split(r'[；;、,，]', note) if seg.strip()]


def unify_brackets(name: str) -> str:
    out = []
    for ch in name:
        if ch in BRACKET_MAP:
            out.append(BRACKET_MAP[ch])
        elif ch in STRAY:
            continue
        else:
            out.append(ch)
    s = ''.join(out)
    # 结构本来就坏（右括号出现在左括号前面 / 主名为空）：原样返回，别猜
    first_open = s.find(OPEN)
    first_close = s.find(CLOSE)
    if first_close != -1 and (first_open == -1 or first_close < first_open):
        return name
    # 括号不配对：补/删（保守：多余的左括号补右括号，多余的右括号丢弃）
    while s.count(OPEN) > s.count(CLOSE):
        s += CLOSE
    if s.count(CLOSE) > s.count(OPEN):
        # 从右往左删多余的右括号
        need = s.count(CLOSE) - s.count(OPEN)
        for _ in range(need):
            idx = s.rfind(CLOSE)
            s = s[:idx] + s[idx + 1:]
    return s


def normalize_name(raw: str, brand: str, known_brands: set[str] | None = None) -> tuple[str, list[str]]:
    """返回 (新名称, flags)。只搬文字，不删内容。"""
    flags: list[str] = []
    s = unify_brackets(raw).strip()
    if s != raw.strip():
        flags.append('括号统一')

    # 抽掉备注，处理主名，再把备注统一挂到末尾
    notes: list[str] = []
    main_parts: list[str] = []

    def take(match: re.Match) -> str:
        notes.extend(split_notes(match.group(1)))
        return ''

    main = re.sub(r'（([^）]*)）', take, s)

    # 主名里的重复片段（品牌/名称被复制两遍）：ABAB... → AB...
    m = re.match(r'^(.{2,8}?)\1', main)
    if m:
        main = m.group(1) + main[m.end():]
        flags.append('去重复前缀')

    # 尾规格（52g / 300克）进括号
    m = re.search(r'(\d+(?:\.\d+)?\s*(?:kg|g|mg|ml|L|克|千克|公斤|毫升|升|袋|包|瓶|盒|罐|片|粒|支|条|份|斤|两|只|个|串|块|枚|听|杯|碗))\s*$', main, re.I)
    if m and len(main) > len(m.group(1)):
        notes.append(m.group(1).strip())
        main = main[:m.start()].strip()
        flags.append('尾规格入括号')

    # 短横线后缀（鲫鱼-天津）进括号；只在后缀 2–6 字且不含数字时做。
    # 斜杠不搬（"52g/包"、"A/B" 这类斜杠切开会把规格切断），留在「待复核」清单里。
    m = re.search(r'^(.+?)[-—]\s*([\u4e00-\u9fffA-Za-z]{2,6})$', main)
    if m:
        notes.append(m.group(2))
        main = m.group(1).strip()
        flags.append('后缀入括号')

    main = re.sub(r'\s+', '', main) if ' ' in main else main
    main = main.strip(' 、，；,;')
    if not main:
        # 主名为空（整名都在括号里，如「【咸烧白】（扣肉）」）：原样不动，
        # 别把括号内容搬两遍。
        return raw, ['主名为空未改']

    clean_notes: list[str] = []
    for note in notes:
        note = re.sub(r'\s+', '', note).strip(' 、，；,;')
        if note and note not in clean_notes:
            clean_notes.append(note)
    new = main + (f'{OPEN}{"；".join(clean_notes)}{CLOSE}' if clean_notes else '')
    if new != raw:
        flags.append('名称重排')
    # 名称里的品牌：**只认品牌列自身**（列里有值且名称以它开头）。
    # 不用「品牌词表」猜：源数据里很多品牌列的值就是食材词（豆干/芝麻酱/白玉米），
    # 拿它剥前缀会把「豆干丁」改成「丁」——2026-10-21 实测踩过，规则撤掉。
    if brand and len(brand) >= 2 and main.startswith(brand) and len(main) > len(brand):
        main2 = main[len(brand):].lstrip('（-—· ')
        new = main2 + (f'{OPEN}{"；".join(clean_notes)}{CLOSE}' if clean_notes else '')
        flags.append('品牌剥离')
    return new, flags


def derive_aliases(raw_name: str, new_name: str, brand: str) -> list[str]:
    """从名称/备注派生别名。只收「像食物叫法」的段（精度优先）。"""
    aliases: list[str] = []
    nouns = set(NOTE_NOUNS)
    for words in CAT_KEYWORDS.values():
        nouns.update(words)

    def looks_like_food(value: str) -> bool:
        return any(noun in value for noun in nouns)

    def add(value: str, *, from_note: bool = False) -> None:
        value = re.sub(r'\s+', '', value).strip(' 、，；,;')
        if not value or len(value) < 2 or len(value) > 16:
            return
        if value in NOTE_STOPWORDS or UNIT_RE.match(value):
            return
        if value == new_name or value in aliases:
            return
        # 备注段当别名：至少 3 字且含一个食物名词——
        # 「脂肪酸调整」「寡糖强化」「即溶」「普通」这类描述词一律不收。
        if from_note and (len(value) < 3 or not looks_like_food(value)):
            return
        # 描述性备注不收：以「不/无/低/高/加/减/少/多」起头或以「味/色/香」收尾的
        #（不加油 / 无糖 / 蛋奶味 / 低脂），它们讲的是**做法或风味**，不是叫法。
        if from_note and (value[0] in '不无低高加减多少' or value[-1] in '味色香版款型'):
            return
        aliases.append(value)

    # ① 备注段（精度过滤见 add）
    for note in re.findall(r'（([^）]*)）', unify_brackets(raw_name)):
        for seg in split_notes(note):
            add(seg, from_note=True)
    # ② 去掉括号后的基础名（"莲藕（生）" ⇒ 别名"莲藕"）
    base = re.sub(r'（[^）]*）', '', unify_brackets(raw_name)).strip()
    base = re.sub(r'\s+', '', base)
    if base and base != new_name:
        add(base)
    # ③ 同义词展开：只给「短名」加（长名多是成品/菜肴，加了会把整道菜挂到食材别名上）
    if len(new_name) <= 10:
        hay = new_name + base
        for a, b in SYNONYMS:
            if a in hay:
                add(b)
            if b in hay:
                add(a)
    # ④ 品牌在前、名称在后：别名 = 名称去掉品牌后再拼一次（搜品牌+品类能找到）
    if brand and brand in new_name:
        stripped = new_name.replace(brand, '').strip('（）')
        add(stripped)
    return aliases


def audit_category(base_name: str, assigned: str, note: str = '') -> tuple[str, str | None, str]:
    """返回 (verdict, 建议分类id, 说明)。verdict ∈ ok / fix / review / unknown. """
    assigned_id = GROUPS.get(assigned)
    if assigned_id == 'snack' and FLAVOR_RE.search(note):
        return 'ok', None, '风味零食（备注含风味/工艺标记），不按食材名改类'
    if assigned_id is None:
        return 'unknown', None, f'一级分类「{assigned}」不在 24 个库大类里'
    scores: Counter[str] = Counter()
    strength: dict[str, int] = {}
    for cat, words in CAT_KEYWORDS.items():
        for word in words:
            if base_name == word:
                scores[cat] += 3
                strength[cat] = max(strength.get(cat, 0), 3)
            # 单字关键词（蒸/炸/煮/盐…）不做「以它开头」的强判：
            # 「蒸米糕」是米糕不是「蒸菜」。
            elif base_name.startswith(word) and len(word) > 1 and len(base_name) <= len(word) + 6:
                scores[cat] += 2
                strength[cat] = max(strength.get(cat, 0), 2)
            elif base_name.endswith(word) and len(base_name) <= len(word) + 4:
                scores[cat] += 2
                strength[cat] = max(strength.get(cat, 0), 2)
            elif word in base_name and not WEAK_IN_COMPOUND.search(base_name):
                scores[cat] += 1
                strength[cat] = max(strength.get(cat, 0), 1)
    # 麻花：油炸面食零食。源文件把它散落在谷物/水产/油脂/调味品里，全部纠正；
    # 但「麻花鳜鱼」「麻花鳝鱼」这类**菜名**（assigned=prepared）不动。
    if '麻花' in base_name and assigned_id != 'prepared':
        return 'fix', 'snack', '基础名含「麻花」（油炸面食零食）'
    if not scores:
        return 'ok', None, '无关键词冲突'
    best, best_score = scores.most_common(1)[0]
    if best == assigned_id:
        return 'ok', None, '关键词与分类一致'
    # 只在「强匹配且唯一领先」时自动纠正
    if strength.get(best, 0) >= 3 and scores[best] > scores.get(assigned_id, 0):
        return 'fix', best, f'基础名「{base_name}」是「{CAT_LABEL[best]}」的强关键词'
    if strength.get(best, 0) >= 2 and best_score - scores.get(assigned_id, 0) >= 3 and len(base_name) <= 8:
        # 零食/甜点、以及带烹饪标记的菜肴：名字里含食材词是**正常**的，不刷复核噪音
        if assigned_id == 'snack':
            return 'ok', None, '零食/甜点归类合理'
        if assigned_id == 'prepared' and PREPARED_MARK.search(base_name):
            return 'ok', None, '菜肴名含食材词属正常'
        return 'review', best, f'基础名「{base_name}」更像「{CAT_LABEL[best]}」'
    return 'ok', None, '关键词不构成强证据'


def main() -> int:
    rows = list(csv.DictReader(io.open(SRC, encoding='utf-8-sig')))
    brand_counts = Counter((r['品牌'] or '').strip() for r in rows if (r['品牌'] or '').strip())
    known_brands = {b for b, c in brand_counts.items() if c >= 3 and len(b) >= 2}

    out_rows = []
    changes = []
    stats = Counter()
    alias_hist = Counter()
    review_rows = []
    cat_changes = []

    for r in rows:
        raw_name = (r['食物名称'] or '').strip()
        old_brand = (r['品牌'] or '').strip()
        group = (r['一级分类'] or '').strip()

        new_name, flags = normalize_name(raw_name, old_brand, known_brands)
        base = re.sub(r'（[^）]*）', '', unify_brackets(raw_name)).strip()
        base = re.sub(r'\s+', '', base)

        note_text = '；'.join(re.findall(r'（([^）]*)）', unify_brackets(raw_name)))
        verdict, suggested, why = audit_category(base, group, note_text)
        assigned_id = GROUPS.get(group)
        new_cat_id = assigned_id
        if verdict == 'fix' and suggested:
            new_cat_id = suggested
            cat_changes.append((raw_name, old_brand, group, CAT_LABEL[suggested], why))
            stats['分类已纠正'] += 1
        elif verdict == 'review':
            review_rows.append((raw_name, old_brand, group, CAT_LABEL.get(suggested or '', ''), why))
            stats['分类待复核'] += 1
        elif verdict == 'unknown':
            review_rows.append((raw_name, old_brand, group, '', why))
            stats['分类表外'] += 1
        else:
            stats['分类一致'] += 1

        aliases = derive_aliases(raw_name, new_name, old_brand)
        alias_hist[len(aliases)] += 1
        if aliases:
            stats['有别名的行'] += 1

        name_changed = new_name != raw_name
        cat_changed = new_cat_id != assigned_id
        if name_changed:
            stats['名称重排'] += 1
            for f in flags:
                stats[f'  flag:{f}'] += 1

        if name_changed or cat_changed:
            changes.append({
                '旧名称': raw_name, '旧品牌': old_brand,
                '新名称': new_name, '新品牌': old_brand,
                '旧分类': CAT_LABEL.get(assigned_id or '', group),
                '新分类': CAT_LABEL.get(new_cat_id or '', ''),
                '原因': '；'.join(flags + ([why] if cat_changed else [])),
            })

        out_rows.append({
            '旧名称': raw_name,
            '旧品牌': old_brand,
            '新名称': new_name,
            '新品牌': old_brand,
            '分类': new_cat_id or 'other',
            '别名': '、'.join(aliases),
        })

    os.makedirs(EVID, exist_ok=True)
    with io.open(OUT_CSV, 'w', encoding='utf-8-sig', newline='') as fh:
        w = csv.DictWriter(fh, fieldnames=['旧名称', '旧品牌', '新名称', '新品牌', '分类', '别名'])
        w.writeheader()
        w.writerows(out_rows)
    with io.open(f'{EVID}/changes.csv', 'w', encoding='utf-8-sig', newline='') as fh:
        w = csv.DictWriter(fh, fieldnames=['旧名称', '旧品牌', '新名称', '新品牌', '旧分类', '新分类', '原因'])
        w.writeheader()
        w.writerows(changes)

    lines = ['# 食物库归一化 / 别名 / 分类审计报告', '', f'源：`{SRC}`（{len(rows)} 行）', '',
             '## 汇总', '']
    for k in ['分类一致', '分类已纠正', '分类待复核', '分类表外', '名称重排', '有别名的行']:
        lines.append(f'- {k}：{stats[k]}')
    lines.append('')
    lines.append('### 名称改动按规则拆分')
    for k in sorted(stats):
        if k.startswith('  flag:'):
            lines.append(f'- {k[7:]}：{stats[k]}')
    lines += ['', '### 别名条数分布', '']
    for k in sorted(alias_hist):
        lines.append(f'- {k} 条别名的行：{alias_hist[k]}')
    lines += ['', '## 分类被纠正的行（全部列出）', '', '| 名称 | 品牌 | 原分类 | 新分类 | 依据 |', '|---|---|---|---|---|']
    for name, brand, old, new, why in cat_changes:
        lines.append(f'| {name} | {brand} | {old} | {new} | {why} |')
    lines += ['', '## 待人工复核（分类疑点，未自动改）', '', '| 名称 | 品牌 | 现分类 | 更像 | 依据 |', '|---|---|---|---|---|']
    for name, brand, old, sug, why in review_rows:
        lines.append(f'| {name} | {brand} | {old} | {sug} | {why} |')
    io.open(f'{EVID}/audit-report.md', 'w', encoding='utf-8', newline='').write('\n'.join(lines) + '\n')

    print(json.dumps({k: v for k, v in stats.items()}, ensure_ascii=False, indent=1))
    print('别名分布:', dict(sorted(alias_hist.items())))
    print('输出:', OUT_CSV, '| 行数', len(out_rows))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
