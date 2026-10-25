#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""食物库人工审核台（docs/29 §P8b-1）——本地开发工具，**不进 App 包**。

只依赖 Python 标准库（`http.server`），零新依赖。审核台只绑 `127.0.0.1`，
不服务任何静态目录（只有一个内嵌的 HTML 页），所以它暴露的东西被钉死成
「种子 + 账本 + 上屏预览」这三份本地文件。

用法（在仓库根跑）：

    python tool/food_seed/review/review_server.py --stats
    python tool/food_seed/review/review_server.py --serve
    python tool/food_seed/review/review_server.py --serve --only near_duplicate

**上屏预览**由 App 自己的 Dart 函数离线产出（`export_display_preview.dart`）；
本脚本在启动时校验它的 sha256 与当前种子一致，不一致就拒绝启动——审核台显示
的必须是**当下**的上屏结果，否则人审的是一张并不存在的卡片。
"""
from __future__ import annotations

import argparse
import json
import sys
import threading
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import review_lib as rl  # noqa: E402

UI_PATH = Path(__file__).resolve().parent / "review_ui.html"


class Workbench:
    """审核台的**状态**：种子 + 标记 + 账本重放结果（全部可重建）。

    没有第二份事实：内存里的 `state` 是账本重放出来的，落盘只写账本（追加）与
    游标（派生）。进程被杀掉再起来，接着审的位置完全由账本决定。
    """

    def __init__(self, root: Path, only: str | None = None) -> None:
        self.root = root
        self.seed_path = root / rl.SEED_REL
        self.preview_path = root / rl.PREVIEW_REL
        self.ledger_path = root / rl.LEDGER_REL
        self.cursor_path = root / rl.CURSOR_REL
        self.only = only
        self.lock = threading.Lock()

        missing = [p for p in (self.seed_path,) if not p.is_file()]
        if missing:
            raise SystemExit(f"缺少种子：{missing[0]}")
        if not self.preview_path.is_file():
            raise SystemExit(
                "缺少上屏预览 reports/display_preview.jsonl。\n"
                "先跑：flutter pub get && dart run tool/food_seed/review/"
                "export_display_preview.dart\n"
                "（审核台显示的必须是 App 的同一批 Dart 函数产出的结果）"
            )

        self.order, self.rows = rl.load_seed(self.seed_path)
        self.meta, self.previews = rl.load_preview(self.preview_path)
        self.brand_tokens = rl.load_brand_tokens(root / rl.GAZETTEER_REL)
        self.seed_sha = rl.seed_sha256(self.seed_path)

        if self.meta.get("seed_sha256") != self.seed_sha:
            raise SystemExit(
                "上屏预览与当前种子不同源：预览 "
                f"{self.meta.get('seed_sha256')} vs 种子 {self.seed_sha}。\n"
                "重跑 dart run tool/food_seed/review/export_display_preview.dart"
            )

        self.state = rl.replay(rl.read_ledger(self.ledger_path))
        unknown = set(self.state) - set(self.rows)
        if unknown:
            raise SystemExit(
                f"账本里有种子里不存在的 id：{sorted(unknown)[:5]}（种子被换过？）"
            )
        # 已裁决并入词表的 token：让相应条目不再报「没拆」。
        self.extra_tokens = set()
        for entry in self.state.values():
            if entry["decision"] == "brand_token":
                token = (entry["after"] or {}).get("brand_token")
                if token:
                    self.extra_tokens.add(token)
        self.flags = rl.compute_flags(
            self.order, self.rows, self.brand_tokens, self.extra_tokens
        )
        self._rebuild_queue()

    # -- 队列 ---------------------------------------------------------------

    def _rebuild_queue(self) -> None:
        self.queue = rl.build_queue(
            self.order, self.rows, self.flags, self.state, only=self.only
        )
        self.queue_ids = [food_id for group in self.queue for food_id in group]

    def stats(self) -> dict:
        return rl.compute_stats(self.order, self.state)

    def last_decidable_id(self) -> str | None:
        """账本里**最近一条生效裁决**的 id —— 「撤回」的语义目标。

        为什么需要它：裁决一写进账本，那一条就退出待审队列、也从屏上消失，所以
        「撤回当前这一行」在按键那一刻已经指不到刚审的那一条了（实测：先按 6 删除、
        再按 8 撤回，撤回落在**下一行**的空栈上、什么也没发生，删掉的条目再也回不
        来）。49,464 条靠键盘走，按错一格是必然会发生的，撤回必须撤「最近那一次」，
        而不是「当前这一行」。

        这里从账本重算（按 `replay` 的同一套栈语义），不额外记第二份状态。
        """
        rows = rl.read_ledger(self.ledger_path)
        stacks: dict[str, list[int]] = {}
        for position, row in enumerate(rows):
            if row["decision"] == "revert":
                stack = stacks.get(row["id"])
                if stack:
                    stack.pop()
                continue
            stacks.setdefault(row["id"], []).append(position)
        best_position = -1
        best_id: str | None = None
        for food_id, stack in stacks.items():
            if stack and stack[-1] > best_position:
                best_position = stack[-1]
                best_id = food_id
        return best_id

    def window(self, index: int, size: int) -> dict:
        """从 `index` 起的一窗**待审分组**（组内顺序保留）。"""
        index = max(0, min(index, len(self.queue)))
        groups = self.queue[index : index + size]
        items = []
        for group in groups:
            members = []
            for food_id in group:
                row = self.rows[food_id]
                preview = self.previews.get(food_id, {})
                members.append(
                    {
                        "id": food_id,
                        "raw": row["name"],
                        "name": preview.get("name"),
                        "brand": preview.get("brand"),
                        "ring": preview.get("ring"),
                        "ring_label": preview.get("ring_label"),
                        "protein": preview.get("protein"),
                        "carbs": preview.get("carbs"),
                        "fat": preview.get("fat"),
                        "kcal": row["kcal"],
                        "protein_g": row["protein"],
                        "carbs_g": row["carbs"],
                        "fat_g": row["fat"],
                        "serving_g": row.get("serving_g"),
                        "flags": self.flags.get(food_id, []),
                        "flag_labels": [
                            rl.FLAG_LABEL.get(f, f) for f in self.flags.get(food_id, [])
                        ],
                    }
                )
            items.append(
                {
                    "head": rl.head_token(self.rows[group[0]]["name"]),
                    "batchable": rl.group_is_batchable(group, self.rows),
                    "members": members,
                }
            )
        return {
            "index": index,
            "total_groups": len(self.queue),
            "pending_rows": len(self.queue_ids),
            "stats": self.stats(),
            "only": self.only,
            "scope": self.scope(),
            "groups": items,
        }

    def scope(self) -> dict | None:
        """`--only` 时的工作面计数（**不是**完成度声明；全库进度见 `stats`）。"""
        if not self.only:
            return None
        rows = 0
        decided = 0
        for food_id in self.order:
            if self.only not in self.flags.get(food_id, ()):
                continue
            rows += 1
            if food_id in self.state:
                decided += 1
        return {
            "flag": self.only,
            "rows": rows,
            "groups": len(self.queue),
            "decided": decided,
        }

    # -- 裁决 ---------------------------------------------------------------

    def decide(self, payload: dict) -> dict:
        """把一批裁决写进账本（追加），返回新的进度。

        `review_mode` 由**服务端**判定，不由前端自报：单条裁决一律 `item`，
        `batch` 只有「整组族批确认」成立时才给——即提交的 id **恰好等于**同首词
        全部待审成员的集合。报告里「逐条核验 / 族批确认」两个数就是靠这一条守住的
        （族批确认过的不许写成逐条核验，逐条核过的也不许被凑成族批）。
        """
        action = payload.get("action")
        rows = payload.get("rows") or []
        if action not in rl.DECISIONS:
            raise rl.LedgerError(f"未知动作：{action!r}")
        # `revert` 不看 `rows`：它撤的是账本里最近一条生效裁决（服务端自己查），
        # 前端传什么都不作数。其余动作必须点名要审的条目。
        if action != "revert" and not rows:
            raise rl.LedgerError("没有要提交的条目")

        with self.lock:
            wants_batch = bool(payload.get("batch"))
            ledger_rows = []
            if action == "revert":
                # 撤回只撤「账本里最近一条生效裁决」，**不看前端报的是哪一条**：
                # 裁决一落账本就退出队列、也从屏上消失，按键那一刻「当前行」早已
                # 不是刚审的那一条（否则按错一格就再也回不来）。一次一条，撤回
                # 本身就是小心的操作，不许批量。
                target = self.last_decidable_id()
                if target is None:
                    raise rl.LedgerError("账本里没有可撤回的裁决（还没审过任何条目）")
                ledger_rows.append(self._revert_row(target))
            for item in rows if action != "revert" else ():
                food_id = item.get("id")
                if food_id not in self.rows:
                    raise rl.LedgerError(f"种子里没有这个 id：{food_id!r}")
                ledger_rows.append(
                    self._decision_row(food_id, action, item, payload)
                )
            if wants_batch:
                self._require_whole_group(action, [item.get("id") for item in rows])
                for row in ledger_rows:
                    row["review_mode"] = "batch"
            rl.append_ledger(self.ledger_path, ledger_rows)
            self.state = rl.replay(rl.read_ledger(self.ledger_path))
            for row in ledger_rows:
                if row["decision"] == "brand_token":
                    token = (row["after"] or {}).get("brand_token")
                    if token:
                        self.extra_tokens.add(token)
            self.flags = rl.compute_flags(
                self.order, self.rows, self.brand_tokens, self.extra_tokens
            )
            self._rebuild_queue()
            rl.write_cursor(
                self.cursor_path,
                self.state,
                last_index=0,
                seed_sha256_value=self.seed_sha,
            )
        return {"stats": self.stats(), "written": len(ledger_rows)}

    def _require_whole_group(self, action: str, ids: list[str]) -> None:
        """族批确认的成立条件（不成立就整批拒绝，**不降级记成 item**）。

        降级比拒绝更糟：把「族批确认」写成「逐条核验」正是 docs/29 点名的混称。
        """
        if action != "approve":
            raise rl.LedgerError(f"只有「通过」能整组族批确认，收到 {action!r}")
        if len(ids) < 2:
            raise rl.LedgerError("族批确认至少两条（单条请按逐条核验记）")
        heads = {rl.head_token(self.rows[food_id]["name"]) for food_id in ids}
        if len(heads) != 1 or None in heads:
            raise rl.LedgerError("族批确认要求整组同首词（这一批的首词不止一个）")
        head = heads.pop()
        pending_members = {
            food_id
            for food_id in self.order
            if food_id not in self.state and rl.head_token(self.rows[food_id]["name"]) == head
        }
        if set(ids) != pending_members:
            raise rl.LedgerError(
                f"族批确认必须是整组：该组还有 {len(pending_members - set(ids))} 条"
                "没有一起确认（族批不是抽样，漏下的会算不进去）"
            )

    def _revert_row(self, food_id: str) -> dict:
        current = self.state.get(food_id)
        return {
            "id": food_id,
            "decision": "revert",
            # 记下**撤掉的是哪一条裁决**：账本要能回答「这一行撤回指向谁」。
            "before": {
                "reverted_id": food_id,
                "reverted_decision": current["decision"] if current else None,
            },
            "after": {"reverted": True},
            "source": "人工撤回",
            "review_mode": "item",
            "ts": rl.now_iso(),
        }

    def _decision_row(
        self, food_id: str, action: str, item: dict, payload: dict
    ) -> dict:
        row = self.rows[food_id]
        before = rl.canonical_fields(row)
        after = dict(before)

        if action == "rename":
            name = (item.get("name") or "").strip()
            if not name:
                raise rl.LedgerError(f"{food_id}：改名称必须给出非空名称")
            after["name"] = name
        elif action == "set_brand":
            after["brand"] = (item.get("brand") or "").strip() or None
        elif action == "brand_token":
            token = (item.get("brand_token") or "").strip()
            if not token:
                raise rl.LedgerError(f"{food_id}：并入词表必须给出 token")
            after = {"brand_token": token}
        elif action == "edit_nutrition":
            values = item.get("nutrition") or {}
            for key in ("kcal", "protein", "carbs", "fat"):
                if key not in values:
                    raise rl.LedgerError(f"{food_id}：改营养缺 {key}")
                try:
                    number = float(values[key])
                except (TypeError, ValueError) as error:
                    raise rl.LedgerError(f"{food_id}：{key} 不是数字") from error
                if not (number >= 0) or number != number or number in (
                    float("inf"),
                    float("-inf"),
                ):
                    raise rl.LedgerError(f"{food_id}：{key} 必须是非负有限数字")
                after[key] = number
        elif action == "delete":
            after["deleted"] = True
        elif action == "uncertain":
            after = dict(before)

        source = (item.get("source") or "").strip()
        if action == "edit_nutrition" and not source:
            # docs/29 §P8b-1：改数值必须填 `source` 或标「人工估值」。
            source = rl.NUTRITION_SOURCE_FALLBACK
        if not source:
            source = "人工核验名称/品牌" if action != "approve" else "人工通过"

        return {
            "id": food_id,
            "decision": action,
            "before": before,
            "after": after,
            "source": source,
            # `review_mode` 由 `decide` 统一决定（族批要整组才成立），这里先按
            # 逐条记 —— 混称的代价是报告失真，宁可让整批被拒。
            "review_mode": "item",
            "ts": rl.now_iso(),
        }


# ---- HTTP ------------------------------------------------------------------


def make_handler(workbench: Workbench):
    class Handler(BaseHTTPRequestHandler):
        server_version = "LocalFitFoodReview/1"

        def log_message(self, fmt, *args):  # 静音：审核时控制台只该有进度
            pass

        def _send(self, status: int, body: bytes, content_type: str) -> None:
            self.send_response(status)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)

        def _json(self, status: int, payload: dict) -> None:
            self._send(
                status,
                json.dumps(payload, ensure_ascii=False).encode("utf-8"),
                "application/json; charset=utf-8",
            )

        def do_GET(self) -> None:  # noqa: N802（stdlib 命名）
            path = self.path.split("?", 1)[0]
            if path in ("/", "/index.html"):
                self._send(200, UI_PATH.read_bytes(), "text/html; charset=utf-8")
                return
            if path == "/api/window":
                query = self.path.split("?", 1)[1] if "?" in self.path else ""
                params = dict(
                    pair.split("=", 1) for pair in query.split("&") if "=" in pair
                )
                index = int(params.get("index", "0"))
                size = max(1, min(200, int(params.get("size", "20"))))
                self._json(200, workbench.window(index, size))
                return
            if path == "/api/stats":
                self._json(200, workbench.stats())
                return
            # 不服务任何静态目录：审核台只暴露这三份本地文件。
            self._json(404, {"error": "not found"})

        def do_POST(self) -> None:  # noqa: N802
            if self.path.split("?", 1)[0] != "/api/decide":
                self._json(404, {"error": "not found"})
                return
            length = int(self.headers.get("Content-Length") or 0)
            raw = self.rfile.read(length) if length else b"{}"
            try:
                payload = json.loads(raw.decode("utf-8"))
            except (UnicodeDecodeError, json.JSONDecodeError) as error:
                self._json(400, {"error": f"请求体不是合法 JSON：{error}"})
                return
            try:
                self._json(200, workbench.decide(payload))
            except rl.LedgerError as error:
                # 校验失败：账本一个字节都没写（追加前整批校验），如实回话。
                self._json(400, {"error": str(error)})

    return Handler


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="食物库人工审核台（docs/29 §P8b-1）")
    parser.add_argument("--serve", action="store_true", help="启动审核台")
    parser.add_argument("--stats", action="store_true", help="只打印五档进度")
    parser.add_argument("--port", type=int, default=8787)
    parser.add_argument("--only", default=None, help="只审带某个标记的条目")
    parser.add_argument("--no-open", action="store_true", help="不自动开浏览器")
    parser.add_argument("--root", default=None, help="仓库根（默认向上找 pubspec.yaml）")
    parser.add_argument("--check-preview", action="store_true", help="只校验预览新鲜度")
    args = parser.parse_args(argv)

    root = Path(args.root).resolve() if args.root else rl.repo_root()
    if args.only and args.only not in rl.FLAG_RANK:
        parser.error(f"--only 只认这些标记：{', '.join(rl.FLAG_RANK)}")

    if args.check_preview:
        preview = root / rl.PREVIEW_REL
        if not preview.is_file():
            print("缺少 reports/display_preview.jsonl", file=sys.stderr)
            return 1
        meta, rows = rl.load_preview(preview)
        seed_sha = rl.seed_sha256(root / rl.SEED_REL)
        if meta.get("seed_sha256") != seed_sha:
            print(
                f"STALE: 预览来自 {meta.get('seed_sha256')}，当前种子 {seed_sha}",
                file=sys.stderr,
            )
            return 1
        print(f"OK: 预览 {len(rows)} 条，与种子 sha256 {seed_sha[:12]} 同源")
        return 0

    if args.stats:
        workbench = Workbench(root, only=args.only)
        print(rl.format_stats(workbench.stats(), workbench.scope()))
        return 0

    if not args.serve:
        parser.error("要么 --serve，要么 --stats / --check-preview")

    workbench = Workbench(root, only=args.only)
    handler = make_handler(workbench)
    server = ThreadingHTTPServer(("127.0.0.1", args.port), handler)
    url = f"http://127.0.0.1:{args.port}/"
    print(f"审核台：{url}")
    print(rl.format_stats(workbench.stats()))
    print(f"待审队列 {len(workbench.queue)} 组（{len(workbench.queue_ids)} 条）")
    print("Ctrl+C 退出。每次裁决立即追加进", rl.LEDGER_REL)
    if not args.no_open:
        threading.Timer(0.4, lambda: webbrowser.open(url)).start()
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n已停止（账本已落盘，接着审只需重开）")
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
