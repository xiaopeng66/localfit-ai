#!/usr/bin/env python3
"""P0 评测报告接收器（dev-only）。

Android 11+ 的 scoped storage 不让 adb shell 读别的应用的
`/sdcard/Android/data/<pkg>/files`，所以设备端的评测结果由应用自己
POST 回来：模拟器里 `10.0.2.2` 就是宿主机回环地址。

用法（宿主机，先启动再跑评测 APK）：

    python tool/retrieval_eval/report_server.py --out docs/evidence/<dir> --port 8765

应用端每次落盘（每档一次）都会 POST 一份；本脚本同名覆盖写
`<out>/p0_report.json` 与 `<out>/p0_run.log`，并在 stdout 打印一行摘要。
"""
from __future__ import annotations

import argparse
import json
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path


class Handler(BaseHTTPRequestHandler):
    out_dir: Path = Path('.')

    def do_POST(self) -> None:  # noqa: N802 (http.server API)
        length = int(self.headers.get('Content-Length', '0'))
        body = self.rfile.read(length)
        try:
            payload = json.loads(body)
        except json.JSONDecodeError:
            self.send_response(400)
            self.end_headers()
            return
        report = payload.get('report', payload)
        log = payload.get('log', '')
        self.out_dir.mkdir(parents=True, exist_ok=True)
        (self.out_dir / 'p0_report.json').write_text(
            json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8'
        )
        if log:
            (self.out_dir / 'p0_run.log').write_text(log, encoding='utf-8')
        verdict = report.get('verdict-default', {})
        print(f'[report] keys={len(report)} verdict={verdict}', flush=True)
        self.send_response(200)
        self.send_header('Content-Type', 'text/plain')
        self.end_headers()
        self.wfile.write(b'ok')

    def log_message(self, *args) -> None:  # 静音默认访问日志
        pass


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--out', required=True)
    parser.add_argument('--port', type=int, default=8765)
    args = parser.parse_args()
    Handler.out_dir = Path(args.out)
    server = HTTPServer(('0.0.0.0', args.port), Handler)
    print(f'listening on 0.0.0.0:{args.port} -> {Handler.out_dir.resolve()}', flush=True)
    server.serve_forever()
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
