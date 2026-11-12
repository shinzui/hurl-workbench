"""Disposable provider-owned HTTP fixture. Database mode requires real psql.

Only --memory selects the local test fixture; real lease acceptance never falls
back to it. Credentials remain in the provider's environment/protected passfile.
"""
import argparse
import http.server
import json
import os
import pathlib
import subprocess
import threading
import time

parser = argparse.ArgumentParser()
parser.add_argument("--directory", type=pathlib.Path, required=True)
parser.add_argument("--name", required=True, choices=("first", "second"))
parser.add_argument("--mode", default="success", choices=("success", "failure", "cancellation"))
parser.add_argument("--memory", action="store_true")
options = parser.parse_args()
markers = []
lock = threading.Lock()


def sql(statement):
    result = subprocess.run([os.environ["SCENARIO_PSQL"], "-X", "-w", "-Atq"],
                            input=statement.encode(), capture_output=True, timeout=10)
    if result.returncode:
        raise RuntimeError("private database operation failed")
    return result.stdout.decode().strip().splitlines()


if not options.memory:
    assert sql("SELECT current_database();") == [os.environ["PGDATABASE"]]
    assert sql("SELECT current_user;") == [os.environ["PGUSER"]]
    sql("CREATE TABLE scenario_markers (marker text NOT NULL);")


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_args):
        pass

    def reply(self, status, body):
        data = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path == "/health":
            self.reply(200, {})
            return
        with lock:
            values = list(markers) if options.memory else sql("SELECT marker FROM scenario_markers ORDER BY marker;")
        self.reply(200, {"count": len(values), "marker": values[0] if len(values) == 1 else None})

    def do_POST(self):
        data = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        marker = data["marker"]
        assert marker in ("private-first-marker", "private-second-marker")
        with lock:
            if options.memory:
                markers.append(marker)
            else:
                sql("INSERT INTO scenario_markers VALUES ('" + marker + "');")
        (options.directory / (options.name + ".posted")).touch()
        if options.mode == "failure":
            self.reply(500, {})
            return
        deadline = time.monotonic() + 20
        while options.mode == "cancellation" or not all((options.directory / (name + ".posted")).exists() for name in ("first", "second")):
            if time.monotonic() >= deadline:
                self.reply(504, {})
                return
            time.sleep(0.01)
        self.reply(201, {})


server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
ready = options.directory / (options.name + ".ready.json")
temporary = ready.with_suffix(".tmp")
temporary.touch(mode=0o600)
temporary.write_text(json.dumps({"endpoint": f"http://127.0.0.1:{server.server_port}", "pid": os.getpid()}))
temporary.replace(ready)
server.serve_forever()
