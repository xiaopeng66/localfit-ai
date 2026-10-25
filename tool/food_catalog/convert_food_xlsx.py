"""把用户 xlsx 转成 App 可导入的 CSV（ADR-036 官方 9 列格式的前 8 列）。

用法：python convert_food_xlsx.py <输入.xlsx> <输出.csv>
输入列：id, 品牌, 名称, 一级分类, 热量, 蛋白质, 碳水, 脂肪
输出列：食品ID, 品牌, 食物名称, 一级分类, 热量(kcal/100g), 蛋白质(g/100g),
       碳水化合物(g/100g), 脂肪(g/100g)
—— 官方格式是 9 列（第 9 列「自建/内置」是展示列，导入侧读都不读），
   本脚本出的这 8 列**逐字同序**就是前 8 列，导入器照常认领；
   「一级分类」24 个库大类逐一命中 `FoodCategory._libraryGroups`（导入期翻成枚举 id，
   原文不落库）；「食品ID」读取后丢弃（身份去重走（名称, 品牌））。

ADR-036（2026-10-21）：旧 21 列文件仍可导入（未认领的列读取后丢弃），但新出的文件
一律用这套 8/9 列，不要再补二级分类 / 菜系 / 计量口径那些列。

Python 文本 I/O 显式 encoding（工作区规范）：读 xlsx 走 pandas，写 CSV 用
utf-8-sig（App 导入器剥 BOM；Excel 双击打开也不乱码）。
"""
from __future__ import annotations

import sys

import pandas as pd

RENAME = {
    'id': '食品ID',
    '品牌': '品牌',
    '名称': '食物名称',
    '一级分类': '一级分类',
}
NUTRIENTS = {
    '热量': '热量(kcal/100g)',
    '蛋白质': '蛋白质(g/100g)',
    '碳水': '碳水化合物(g/100g)',
    '脂肪': '脂肪(g/100g)',
}
COLUMN_ORDER = [
    '食品ID', '品牌', '食物名称', '一级分类',
    '热量(kcal/100g)', '蛋白质(g/100g)', '碳水化合物(g/100g)', '脂肪(g/100g)',
]


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    src, dest = sys.argv[1], sys.argv[2]
    df = pd.ExcelFile(src).parse(0)
    missing = [
        column
        for column in [*RENAME, *NUTRIENTS]
        if column not in df.columns
    ]
    if missing:
        print(f'输入缺少列：{missing}', file=sys.stderr)
        return 1
    df = df.rename(columns={**RENAME, **NUTRIENTS})
    df = df[COLUMN_ORDER].fillna('')
    df.to_csv(dest, index=False, encoding='utf-8-sig')
    print(f'{len(df)} 行 → {dest}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
