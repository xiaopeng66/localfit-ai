"""审核台 UI（`review_ui.html`）的静态契约测试（docs/29 §P8b-1）。

跑法：C:/ProgramData/miniconda3/python.exe test_review_ui.py

为什么要有这个文件：UI 的两个缺陷都属于「逻辑对了、界面在骗人」，只跑得起来
的服务器测试**看不见**它们（我实测踩过）：

  1. 屏上的键位提示写着「先填编辑框、再按数字键」，而 keydown 处理器在编辑框里
     把所有数字键都吞掉 ⇒ 照着提示做等于什么都没发生，改名静默丢失；
  2. `j`/`k` 改的是 `state.cursor`（键盘动作的目标），但「当前行」高亮只在整页
     渲染时算一次，而且拿成员**对象**去比行上的 id 字符串 ⇒ 永远挂不上 `active`，
     审到哪一行屏上完全看不出来。

两条都不能靠「跑一遍服务器」发现，所以这里做**静态契约**断言：提示文字与实际
行为必须一致、动作目标与视觉标记必须同一个来源。这些断言读的是 HTML/JS 源码，
规则一改就得跟着改（这也是它们该有的效果）。
"""
from __future__ import annotations

import os
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
UI = HERE / "review_ui.html"

FAILURES: list[str] = []


def check(label: str, condition: bool, detail: str = "") -> None:
    if condition:
        print(f"  ok   {label}")
    else:
        FAILURES.append(label)
        print(f"  FAIL {label} {detail}")


def main() -> int:
    source = UI.read_text(encoding="utf-8")

    print("UI 静态契约")
    check("文件存在且非空", len(source) > 2000, str(len(source)))

    # —— 提示与行为一致（缺陷 1） ——
    keymap = re.search(r'<div class="keymap">(.*?)</div>', source, re.S)
    check("有键位提示条", keymap is not None)
    text = keymap.group(1) if keymap else ""
    check(
        "提示说的是「在编辑框里按 Enter 提交」（而不是「再按数字键」）",
        "Enter" in text and "再按对应数字键" not in text,
        re.sub(r"<[^>]+>", " ", text)[:160],
    )
    check(
        "处理器在编辑框里按 Enter 时提交（commitField）",
        "function commitField(" in source and 'event.key === "Enter"' in source,
        "commitField 缺失",
    )
    check(
        "处理器在编辑框里不再吞掉数字键（数字要能输进名称）",
        "return; // 其余按键都当打字" in source,
        "编辑框分支缺失",
    )
    check(
        "编辑框按 Enter 提交的是**本行**、按字段选动作",
        "input.closest(\".row\")" in source and "FIELD_ACTION" in source,
        "FIELD_ACTION/ closest 缺失",
    )
    check(
        "名称框 → 改名称、品牌框 → 定品牌",
        'FIELD_ACTION = { name: "rename", brand: "set_brand" }' in source,
        "字段映射缺失",
    )

    # —— 动作目标与视觉标记同源（缺陷 2） ——
    focus = re.search(r"function focusActive\(\)\s*\{(.*?)\n\}", source, re.S)
    check("有 focusActive（统一挪动当前行标记）", focus is not None)
    body = focus.group(1) if focus else ""
    check(
        "focusActive 按 id 比较（不是拿成员对象比字符串）",
        "current.id" in body or ".id" in body,
        body[:200],
    )
    check(
        "render 里调用了 focusActive（渲染后也标当前行）",
        re.search(r"state\.groups\.forEach\(.*?\);\s*\n\s*focusActive\(\);", source, re.S)
        is not None,
        "render 未调用 focusActive",
    )
    check(
        "移动时重算标记（move → render → focusActive）",
        re.search(r"state\.cursor = next;\s*\n\s*render\(\);", source) is not None,
        "move 未重渲染",
    )

    # —— 撤回的语义（缺陷 3：撤的是最近一条，不是当前行） ——
    check(
        "撤回不带当前行的 id（服务端撤最近一条）",
        re.search(r'if \(action === "revert"\) \{\s*\n\s*return post\(\{ action, rows: \[\] \}',
                  source) is not None,
        "撤回仍在前端指定目标",
    )
    check(
        "撤回的提示说明撤的是「最近一条裁决」",
        "已撤回最近一条裁决" in source,
        "撤回提示缺失",
    )

    # —— 上屏预览不许在 JS 里重算（P8b-1 的头号纪律） ——
    check(
        "预览字段全部来自服务端（页面不自己拆名称）",
        "splitFoodName" not in source and "normalizeFoodName" not in source,
        "页面里出现了拆分规则实现",
    )
    check(
        "预览注明来源（App 同一批 Dart 函数）",
        "App 同一批 Dart 函数产出" in source,
        "来源说明缺失",
    )
    check(
        "族批入口是显式按钮且提示整组",
        "整组族批确认" in source and "submitBatch" in source,
        "族批入口缺失",
    )

    if FAILURES:
        print(f"\n{len(FAILURES)} 项失败：{FAILURES}")
        return 1
    print("\n全部通过")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
