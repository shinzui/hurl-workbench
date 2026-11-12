#!/usr/bin/env python3
"""Adapters for real Rei executables; database allocation belongs to the caller."""
import http.client
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import pty
import select
import signal
import subprocess
import sys
import time

assert not any(name in os.environ for name in ["REI_PG_CONNECTION_STRING", "MORI_API_URL", "PGHOST", "PGDATABASE", "PGPASSFILE"]), "managed command inherited ambient database configuration"
root = Path(os.environ["EVIDENCE"])
variant = os.environ["VARIANT"]
role = sys.argv[1]


def event(name, **fields):
    data = (json.dumps(dict(event=name, at=time.time_ns(), **fields)) + "\n").encode()
    fd = os.open(root / "events.jsonl", os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
    try:
        os.write(fd, data)
    finally:
        os.close(fd)


def pid(value):
    path = root / "pids.json"
    values = json.loads(path.read_text()) if path.exists() else []
    path.write_text(json.dumps(values + [value]))
    path.chmod(0o600)


def environment():
    return {"PATH": os.environ["PATH"], "HOME": str(root / "home"),
            "REI_CONFIG": str(root / "rei.yaml"), "REI_PG_CONNECTION_STRING": os.environ["DB"],
            "REI_API_PORT": os.environ["API_PORT"], "REI_API_TOKENS": os.environ["TOKEN"] + "=human",
            "MORI_API_URL": "http://127.0.0.1:" + os.environ["STUB_PORT"], "OTEL_SDK_DISABLED": "true"}


if role == "setup":
    (root / "home").mkdir(mode=0o700)
    (root / "workspace").mkdir(mode=0o700)
    (root / "rei.yaml").write_text("workspace:\n  path: " + str(root / "workspace") + "\n")
    (root / "rei.yaml").chmod(0o600)
    event("setup")
    raise SystemExit(0)
if role == "teardown":
    for value in json.loads((root / "pids.json").read_text()) if (root / "pids.json").exists() else []:
        try:
            os.kill(value, 0)
        except ProcessLookupError:
            continue
        raise RuntimeError("owned process survived cleanup")
    event("consumers-stopped")
    raise SystemExit(0)
if role == "probe-worker":
    raise SystemExit(0 if variant != "readiness-failure" and (root / "worker-ready").exists() else 1)

pid(os.getpid())
event("start", service=role)
if role == "stub":
    class Proxy(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def request(self):
            if self.path == "/health":
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b"ok")
                return
            if self.path == "/after" and variant == "unexpected-exit":
                time.sleep(2)
            if self.path == "/after" and variant == "cancellation":
                event("cancel-ready")
                time.sleep(60)
                return
            if self.path == "/after":
                self.path = "/api/v2/notes?tag=workbench-" + variant + "&first=10"
            body = self.rfile.read(int(self.headers.get("Content-Length", "0")))
            connection = http.client.HTTPConnection("127.0.0.1", int(os.environ["API_PORT"]), timeout=15)
            headers = {key: value for key, value in self.headers.items() if key.lower() not in ("host", "content-length")}
            connection.request(self.command, self.path, body=body, headers=headers)
            response = connection.getresponse()
            data = response.read()
            if self.command == "POST" and response.status == 201:
                event("mutation")
            if self.command == "GET" and response.status == 200:
                parsed = json.loads(data)
                if parsed.get("edges"):
                    event("observation", owner="rei-note-query-projection")
                    if variant == "unexpected-exit":
                        (root / "worker-exit").touch()
            self.send_response(response.status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            connection.close()

        do_GET = request
        do_POST = request

    server = ThreadingHTTPServer(("127.0.0.1", int(os.environ["STUB_PORT"])), Proxy)
    server.daemon_threads = True
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    try:
        server.serve_forever(poll_interval=0.02)
    finally:
        server.server_close()
        event("stop", service=role)
    raise SystemExit(0)

argv = [os.environ["API"]] if role == "api" else [os.environ["REI"], "worker", "query-projections"]
master = slave = None
with (root / (role + ".log")).open("wb") as output:
    (root / (role + ".log")).chmod(0o600)
    if role == "worker":
        master, slave = pty.openpty()
    child = subprocess.Popen(argv, env=environment(), stdin=subprocess.DEVNULL,
                             stdout=slave if slave is not None else output, stderr=subprocess.STDOUT)
    pid(child.pid)
    if slave is not None:
        os.close(slave)
    stopping = False

    def stop(*_):
        global stopping
        stopping = True
        if child.poll() is None:
            child.terminate()

    signal.signal(signal.SIGTERM, stop)
    try:
        buffer = b""
        death_at = None
        while child.poll() is None:
            if master is not None and select.select([master], [], [], 0.02)[0]:
                try:
                    data = os.read(master, 65536)
                except OSError:
                    data = b""
                output.write(data)
                output.flush()
                buffer = (buffer + data)[-65536:]
                if b"Starting Note, assignment and definition query projection workers." in buffer:
                    (root / "worker-ready").touch()
            else:
                time.sleep(0.02)
            if role == "worker" and (root / "worker-exit").exists():
                death_at = death_at or time.monotonic() + 0.15
                if time.monotonic() >= death_at:
                    child.terminate()
                    child.wait(timeout=4)
                    raise SystemExit(9)
        raise SystemExit(0 if stopping else child.returncode)
    finally:
        if child.poll() is None:
            child.terminate()
        child.wait(timeout=4)
        if master is not None:
            os.close(master)
        if role == "worker":
            (root / "worker-ready").unlink(missing_ok=True)
        event("stop", service=role)
