"""Serve the local release build without reusing assets from an earlier sprint."""
import argparse
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


class LocalBuildHandler(SimpleHTTPRequestHandler):
    def do_GET(self):
        # A build may replace an asset during an earlier request. Always return
        # its actual bytes, even if Chrome has a cached Last-Modified validator.
        for name in ('If-Modified-Since', 'If-None-Match'):
            if name in self.headers:
                del self.headers[name]
        super().do_GET()

    def end_headers(self):
        self.send_header('Cache-Control', 'no-store')
        super().end_headers()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', type=int, default=5173)
    args = parser.parse_args()
    directory = Path(__file__).resolve().parents[1] / 'apps/assignment/build/web'
    if not (directory / 'index.html').is_file():
        parser.error('Build Flutter web first; index.html is missing.')
    print(f'Local release: http://127.0.0.1:{args.port}; Cache-Control: no-store', flush=True)
    ThreadingHTTPServer(('127.0.0.1', args.port), partial(LocalBuildHandler, directory=str(directory))).serve_forever()
