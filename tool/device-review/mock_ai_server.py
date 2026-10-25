"""本地 mock AI 端点（设备复验专用）：记录请求体，回一条 SSE 流式回复。
用法：python mock_ai_server.py <log_dir>
端点：POST /v1/chat/completions、GET /v1/models
"""
from __future__ import annotations

import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

LOG_DIR = Path(sys.argv[1] if len(sys.argv) > 1 else 'E:/AI/Zcode/tmp/localfit-next/mock')
LOG_DIR.mkdir(parents=True, exist_ok=True)
COUNTER = {'n': 0}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):  # noqa: A003 - 静音默认日志
        pass

    def do_GET(self):  # noqa: N802
        if self.path.rstrip('/').endswith('/models'):
            body = json.dumps({
                'object': 'list',
                'data': [{'id': 'mock-model', 'object': 'model'}],
            }).encode()
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        self.send_error(404)

    def do_POST(self):  # noqa: N802
        length = int(self.headers.get('Content-Length') or 0)
        raw = self.rfile.read(length)
        COUNTER['n'] += 1
        n = COUNTER['n']
        try:
            payload = json.loads(raw.decode('utf-8'))
        except Exception:
            payload = {'_raw': raw.decode('utf-8', 'replace')}
        (LOG_DIR / f'request-{n}.json').write_text(
            json.dumps(payload, ensure_ascii=False, indent=2), encoding='utf-8'
        )
        # 模型回复（客户端只关心增量文本）
        reply = '收到，已按候选里的 id 来回答。'
        self.send_response(200)
        self.send_header('Content-Type', 'text/event-stream; charset=utf-8')
        self.send_header('Cache-Control', 'no-cache')
        self.end_headers()
        for chunk in [reply[i:i + 6] for i in range(0, len(reply), 6)]:
            frame = {'choices': [{'delta': {'content': chunk}, 'index': 0}]}
            self.wfile.write(f'data: {json.dumps(frame, ensure_ascii=False)}\n\n'.encode())
            self.wfile.flush()
        self.wfile.write(b'data: [DONE]\n\n')
        self.wfile.flush()


if __name__ == '__main__':
    server = ThreadingHTTPServer(('0.0.0.0', 8099), Handler)
    print('mock AI listening on 0.0.0.0:8099', flush=True)
    server.serve_forever()
