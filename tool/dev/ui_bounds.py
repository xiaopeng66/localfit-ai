"""ADB 冒烟辅助：把 uiautomator dump 里的可点节点（描述 + 中心坐标）打出来。

用法：python tool/dev/ui_bounds.py <ui.xml>
Flutter 只把语义树交给无障碍层，所以文本在 content-desc 里；坐标是
物理像素，直接喂给 `adb shell input tap`（不要再按截图缩放换算）。
"""

from __future__ import annotations

import re
import sys

NODE = re.compile(r"<node[^>]*/?>")
DESC = re.compile(r'content-desc="([^"]*)"')
BOUNDS = re.compile(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"')


def main(path: str) -> int:
    xml = open(path, encoding="utf-8").read()
    for tag in NODE.findall(xml):
        desc = DESC.search(tag)
        bounds = BOUNDS.search(tag)
        if not desc or not bounds or not desc.group(1):
            continue
        x1, y1, x2, y2 = (int(value) for value in bounds.groups())
        center = ((x1 + x2) // 2, (y1 + y2) // 2)
        print(f"{center}  {desc.group(1)[:70]!r}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
