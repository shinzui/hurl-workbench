#!/usr/bin/env python3
"""Disposable example application's supported CLI and HTTP facts interface."""
import json
import os
from pathlib import Path
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def facts(root):
    return json.loads((Path(root) / "facts.json").read_text())


def put(root, value):
    path = Path(root) / "facts.json"
    path.write_text(json.dumps(value))
    path.chmod(0o600)


def serve(root, port):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def do_GET(self):
            if self.path == "/health":
                self.send_response(200)
                self.end_headers()
                return
            if self.headers.get("Authorization") != "Bearer " + os.environ["PARITY_TOKEN"]:
                self.send_error(401)
                return
            if self.path != "/facts":
                self.send_error(404)
                return
            data = json.dumps(facts(root)).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def do_POST(self):
            if self.path != "/facts" or self.headers.get("Authorization") != "Bearer " + os.environ["PARITY_TOKEN"]:
                self.send_error(403)
                return
            value = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
            put(root, value)
            self.send_response(204)
            self.end_headers()

    ThreadingHTTPServer(("127.0.0.1", int(port)), Handler).serve_forever()


if __name__ == "__main__":
    if sys.argv[1] == "observe":
        print(json.dumps(facts(sys.argv[2])))
    elif sys.argv[1] == "serve":
        serve(*sys.argv[2:4])
    else:
        raise SystemExit("expected observe FIXTURE or serve FIXTURE PORT")
