"""Dev server for demo.html.

Serves this directory on :5500 and proxies /api/* to the backend, so the demo
runs same-origin — the way the widget is deployed on the real site, and with no
CORS configuration needed. Not for production.
"""
import http.server
import pathlib
import urllib.error
import urllib.request

ROOT = str(pathlib.Path(__file__).parent)
UPSTREAM = "http://localhost:8000"


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **kw):
        super().__init__(*a, directory=ROOT, **kw)

    def _proxy(self, method):
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length) if length else None
        req = urllib.request.Request(UPSTREAM + self.path, data=body, method=method)
        if self.headers.get("Content-Type"):
            req.add_header("Content-Type", self.headers["Content-Type"])
        try:
            with urllib.request.urlopen(req) as res:
                payload, status, ctype = res.read(), res.status, res.headers.get("Content-Type")
        except urllib.error.HTTPError as exc:
            payload, status, ctype = exc.read(), exc.code, exc.headers.get("Content-Type")
        self.send_response(status)
        self.send_header("Content-Type", ctype or "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self):
        self._proxy("GET") if self.path.startswith("/api/") else super().do_GET()

    def do_POST(self):
        self._proxy("POST")

    def log_message(self, *a):
        pass


if __name__ == "__main__":
    print("Widget demo on http://localhost:5500/demo.html")
    http.server.ThreadingHTTPServer(("127.0.0.1", 5500), Handler).serve_forever()
