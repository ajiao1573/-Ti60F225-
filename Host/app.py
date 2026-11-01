"""Offline localhost control service. No cloud, video or mock results."""
import argparse
import json
from pathlib import Path
import sys
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit

ROOT = Path(getattr(sys, "_MEIPASS", Path(__file__).resolve().parent))
sys.path.insert(0, str(ROOT / "vendor"))
from controller import Controller, LinkError, serial_ports


def make_server(controller, port=8765, port_provider=serial_ports):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, fmt, *args):
            if args and str(args[1]) not in ("200", "304"):
                super().log_message(fmt, *args)

        def send(self, code, data, content_type="application/json; charset=utf-8"):
            body = json.dumps(data, ensure_ascii=False).encode("utf-8") if isinstance(data, (dict, list)) else data
            self.send_response(code)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.send_header("X-Content-Type-Options", "nosniff")
            self.send_header("Content-Security-Policy", "default-src 'self'; script-src 'self'; style-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'")
            self.end_headers()
            self.wfile.write(body)

        def local_request(self):
            authority = f"127.0.0.1:{self.server.server_port}"
            if self.headers.get("Host") != authority:
                self.send(403, {"error": "服务仅接受本机页面访问"})
                return False
            origin = self.headers.get("Origin")
            if origin and origin != "http://" + authority:
                self.send(403, {"error": "不允许其他网页发送控制命令"})
                return False
            return True

        def do_GET(self):
            if not self.local_request():
                return
            path = urlsplit(self.path).path
            if path == "/api/state":
                return self.send(200, controller.snapshot())
            if path == "/api/ports":
                try:
                    return self.send(200, {"ports": port_provider()})
                except Exception as exc:
                    return self.send(503, {"error": f"读取串口列表失败：{exc}"})
            if path == "/api/health":
                return self.send(200, {"service": "ti60-vision-control", "version": 2, "tasks": [0, 1, 3]})
            assets = {"/": "index.html", "/style.css": "style.css", "/app.js": "app.js", "/diagnosis.js": "diagnosis.js"}
            if path in assets:
                file = ROOT / "static" / assets[path]
                mime = {".html": "text/html", ".css": "text/css", ".js": "text/javascript"}[file.suffix]
                return self.send(200, file.read_bytes(), mime + "; charset=utf-8")
            self.send(404, {"error": "未找到页面"})

        def do_POST(self):
            if not self.local_request():
                return
            if self.headers.get("Content-Type", "").split(";")[0] != "application/json":
                return self.send(415, {"error": "需要JSON请求"})
            try:
                length = int(self.headers.get("Content-Length", "0"))
                if not 0 < length <= 2048:
                    raise ValueError("请求长度错误")
                data = json.loads(self.rfile.read(length))
                if not isinstance(data, dict):
                    raise ValueError("请求必须为JSON对象")
                path = urlsplit(self.path).path
                if path == "/api/connect":
                    return self.send(200, controller.connect(data.get("port")))
                if path == "/api/disconnect":
                    return self.send(200, controller.disconnect())
                if path == "/api/command":
                    return self.send(200, controller.command(data.get("command"), data.get("value")))
                self.send(404, {"error": "未知接口"})
            except (ValueError, TypeError) as exc:
                self.send(400, {"error": str(exc)})
            except LinkError as exc:
                self.send(502, {"error": str(exc)})

    return ThreadingHTTPServer(("127.0.0.1", port), Handler)


def main():
    parser = argparse.ArgumentParser(description="Ti60 多模式视觉控制台")
    parser.add_argument("--port", type=int, default=8765, help="本地HTTP端口；0为自动选择")
    parser.add_argument("--no-browser", action="store_true")
    args = parser.parse_args()
    controller = Controller()
    try:
        try:
            server = make_server(controller, args.port)
        except OSError:
            if args.port == 0:
                raise
            server = make_server(controller, 0)
        url = f"http://127.0.0.1:{server.server_port}/"
        print("Ti60 多模式视觉控制台", flush=True)
        print(url, flush=True)
        print("保持此窗口运行。关闭窗口或按 Ctrl+C 退出；网页中选择串口后连接。", flush=True)
        if not args.no_browser:
            webbrowser.open(url)
        try:
            server.serve_forever(poll_interval=0.2)
        except KeyboardInterrupt:
            pass
        finally:
            server.server_close()
    finally:
        controller.close()


if __name__ == "__main__":
    main()
