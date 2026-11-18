"""Dev server for the game: like `python -m http.server`, but tells the browser never to cache,
so every reload picks up the latest .js files (the plain server lets the browser reuse old
modules for minutes after you edit them).

    python tools/serve.py [port]      (default 8080, serves the project folder)
"""
import http.server, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


class NoCache(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **kw):
        super().__init__(*a, directory=ROOT, **kw)

    def end_headers(self):
        self.send_header('Cache-Control', 'no-store, must-revalidate')
        self.send_header('Expires', '0')
        super().end_headers()


port = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
http.server.ThreadingHTTPServer(('', port), NoCache).serve_forever()
