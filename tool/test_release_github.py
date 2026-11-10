#!/usr/bin/env python3
"""release_github.py 的纯逻辑回归（不发网络请求）。

2026-11-10 复盘：旧脚本对已存在 tag 会静默「更新发行版」，且不校验新
versionCode 是否大于线上 latest——漏升版会发出一个「检查更新永远看不到」
的包。这里钉死两条防线：版本必须单调、覆盖必须显式 --force。
"""
from __future__ import annotations

from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))

from release_github import check_version_monotonic, parse_version_code


class ParseVersionCodeTest(unittest.TestCase):
    def test_plain_tag_parses_to_int(self) -> None:
        """`v4142` 解析成 4142，两侧空白不影响。"""
        self.assertEqual(parse_version_code("v4142"), 4142)
        self.assertEqual(parse_version_code("v0"), 0)
        self.assertEqual(parse_version_code("  v4141\n"), 4141)

    def test_non_version_tag_returns_none(self) -> None:
        """没有 release 或 tag 不带版本号时不瞎猜一个数字。"""
        self.assertIsNone(parse_version_code(None))
        self.assertIsNone(parse_version_code("latest"))
        self.assertIsNone(parse_version_code("release-4142"))


class VersionMonotonicTest(unittest.TestCase):
    def test_newer_than_latest_passes(self) -> None:
        """比线上新、或线上还没有 release，都允许发布。"""
        check_version_monotonic(4142, "v4141")
        check_version_monotonic(4142, None)
        check_version_monotonic(4141, "some-tag")

    def test_equal_to_latest_refuses(self) -> None:
        """versionCode 不增就是「检查更新永远看不到」的包，必须拒绝。"""
        with self.assertRaises(SystemExit):
            check_version_monotonic(4141, "v4141")

    def test_older_than_latest_refuses(self) -> None:
        with self.assertRaises(SystemExit):
            check_version_monotonic(4140, "v4141")


if __name__ == "__main__":
    unittest.main()
