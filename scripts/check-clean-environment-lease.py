"""Opt-in active PostgreSQL lease consumer; provisioning and release stay with caller."""
import json
import os
import pathlib
import shutil
import signal
import socket
import subprocess
import tempfile
import time

ROOT = pathlib.Path(__file__).resolve().parent.parent
REQUIRED = ["PGHOST", "PGPORT", "PGUSER", "PGDATABASE"]
if "PGPASSFILE" in os.environ:
    password_file = pathlib.Path(os.environ["PGPASSFILE"])
    info = password_file.stat()
    if not password_file.is_file() or info.st_uid != os.getuid() or info.st_mode & 0o077:
        raise SystemExit("PGPASSFILE must be a caller-owned protected file")
    os.environ["PGPASSFILE"] = str(password_file.resolve())
NAMES = REQUIRED + (["PGPASSFILE"] if "PGPASSFILE" in os.environ else [])


def executable(name, override=None):
    value = override or shutil.which(name)
    if not value:
        raise SystemExit(f"required executable unavailable: {name}")
    return str(pathlib.Path(value).resolve())


# Resolve all executables in the owner environment, before launching clean commands.
WORKBENCH = executable("hurl-workbench", os.environ.get("HURL_WORKBENCH_EXECUTABLE"))
PYTHON = executable("python3")
PSQL = executable("psql")

FIXTURE = r'''
import http.server, os, pathlib, subprocess, sys, time
mode, psql, directory, port = sys.argv[1:]
directory = pathlib.Path(directory)
assert not any(name in os.environ for name in ("REI_PG_CONNECTION_STRING", "REI_CONFIG", "MORI_API_URL"))
result = subprocess.run([psql, "-X", "-w", "-A", "-t", "-c", "SELECT current_database(), current_user"], capture_output=True)
assert result.returncode == 0, "lease query failed"
assert result.stdout.decode().strip() == os.environ["PGDATABASE"] + "|" + os.environ["PGUSER"], "lease identity mismatch"
if mode != "service":
    assert (directory / "service.pid").exists(), "service not ready"
    (directory / "probe.ok").touch()
    sys.exit(1 if mode == "failure" else 0)
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/wait":
            (directory / "callback.ready").touch()
            time.sleep(30)
        self.send_response(200)
        self.end_headers()
    def log_message(self, *args): pass
server = http.server.HTTPServer(("127.0.0.1", int(port)), Handler)
(directory / "service.pid").write_text(str(os.getpid()))
server.serve_forever()
'''


def wait_file(path, process):
    deadline = time.monotonic() + 15
    while not path.exists():
        if process.poll() is not None or time.monotonic() > deadline:
            raise RuntimeError("lease fixture did not reach callback")
        time.sleep(0.02)


def stopped(pid):
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return True
    return False


with tempfile.TemporaryDirectory(prefix="clean-environment-lease-") as temporary:
    directory = pathlib.Path(temporary)
    fixture = directory / "fixture.py"
    fixture.write_text(FIXTURE)
    for mode in ("success", "failure", "cancellation"):
        run = directory / mode
        run.mkdir()
        with socket.socket() as sock:
            sock.bind(("127.0.0.1", 0))
            port = sock.getsockname()[1]
        request_path = "/wait" if mode == "cancellation" else "/health"
        (run / "health.hurl").write_text(f"GET http://127.0.0.1:{port}{request_path}\nHTTP 200\n")
        def command(phase):
            args = [str(fixture), phase, PSQL, str(run), str(port)]
            return f"Schema.CommandSpec::{{ executable = {json.dumps(PYTHON)}, arguments = {json.dumps(args)}, environmentPolicy = Schema.EnvironmentPolicy.Clean {json.dumps(NAMES)} }}"
        schema = ROOT / "schema/package.dhall"
        manifest = run / "hurl-workbench.dhall"
        manifest.write_text(f'''let Schema = {schema}
in Schema.Workspace::{{ schemaVersion = 1
, fragments = [ Schema.Fragment::{{ name = "health", path = "health.hurl" }} ]
, workflows = [ Schema.Workflow::{{ name = "health", fragments = [ "health" ] }} ]
, recipes = [ Schema.Recipe::{{ name = "health", workflow = "health", safety = Schema.Safety.ReadOnly }} ]
, services = [ Schema.Service::{{ name = "lease", command = {command("service")}, readiness = Schema.Readiness.Command Schema.CommandReadiness::{{ command = {command("failure" if mode == "failure" else "probe")}, timeoutSeconds = 2, intervalMilliseconds = 20 }} }} ]
, suites = [ Schema.Suite::{{ name = "lease", runs = [ Schema.RunReference.Recipe "health" ], service = Some "lease" }} ] }}''')
        environment = dict(os.environ, REI_PG_CONNECTION_STRING="private-rei-sentinel", REI_CONFIG="private-config-sentinel", MORI_API_URL="private-mori-sentinel")
        process = subprocess.Popen([WORKBENCH, "--workspace", str(manifest), "test", "suite", "lease", "--report-dir", str(run / "reports")], env=environment, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True, preexec_fn=lambda: signal.signal(signal.SIGINT, signal.SIG_DFL))
        try:
            if mode == "cancellation":
                wait_file(run / "callback.ready", process)
                os.killpg(process.pid, signal.SIGINT)
            code = process.wait(timeout=20)
            if mode == "success":
                assert code == 0, "clean lease success failed"
            elif mode == "failure":
                assert code == 4, "readiness failure classification changed"
            else:
                assert code != 0, "cancellation was ignored"
            pid = int((run / "service.pid").read_text())
            assert stopped(pid), "lease consumer still alive before owner regains control"
            assert (run / "probe.ok").exists(), "readiness did not access the lease"
            for artifact in (run / "reports").rglob("summary.json"):
                content = artifact.read_text()
                assert not any(value in content for value in ("private-rei-sentinel", "private-config-sentinel", "private-mori-sentinel"))
        finally:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGINT)
                process.wait(timeout=10)
            # On a failed assertion, contain this driver's fixture before returning.
            pid_file = run / "service.pid"
            if pid_file.exists() and not stopped(int(pid_file.read_text())):
                os.kill(int(pid_file.read_text()), signal.SIGKILL)
        label = "success" if mode == "success" else mode + " cleanup"
        print(f"clean lease {label}: PASS", flush=True)
