"""Shared assertions for local and real caller-owned scenario acceptance."""
import json
import os
import pathlib
import shutil
import signal
import subprocess
import sys
import time
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
FIXTURE = ROOT / "hurl-workbench-cli/test/fixtures/scenario-isolation"


def wait_for(condition, processes=(), timeout=15):
    deadline = time.monotonic() + timeout
    while not condition():
        if any(process.poll() is not None for process in processes):
            raise AssertionError("owned process exited before synchronization")
        if time.monotonic() >= deadline:
            raise AssertionError("synchronization deadline expired")
        time.sleep(0.01)


def alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False


def executable(name, override=None):
    result = override or shutil.which(name)
    if not result or not os.access(result, os.X_OK):
        raise RuntimeError(f"required executable unavailable: {name}")
    return os.path.abspath(result)


class ScenarioRun:
    def __init__(self, directory, workbench, connections, fixture_ids, memory=False, mode="success"):
        self.directory = pathlib.Path(directory)
        self.directory.mkdir(mode=0o700)
        self.workbench = workbench
        self.services = []
        self.mode = mode
        self.entries = []
        self.environment = {key: value for key, value in os.environ.items() if not key.startswith(("PG", "HINAGATA_"))}
        self.environment["SCENARIO_PRIVATE_TOKEN"] = "private-token-sentinel"
        self.environment["SCENARIO_HURL_PID_DIR"] = str(self.directory)
        # Capture actual execution PIDs without recording argv or binding paths.
        hurl = executable("hurl")
        wrapper = self.directory / "hurl"
        wrapper.write_text('#!' + executable("bash") + '\nif [[ "$*" != "--version" ]]; then printf "%s" "$$" > "$SCENARIO_HURL_PID_DIR/child-$$.pid"; fi\nexec ' + __import__('shlex').quote(hurl) + ' "$@"\n')
        wrapper.chmod(0o700)
        self.environment["PATH"] = str(self.directory) + os.pathsep + os.environ["PATH"]
        try:
            for index, name in enumerate(("first", "second")):
                environment = dict(self.environment, **connections[index])
                command = [sys.executable, str(FIXTURE / "server.py"), "--directory", str(self.directory), "--name", name, "--mode", mode]
                if memory:
                    command.append("--memory")
                process = subprocess.Popen(command, env=environment, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                self.services.append(process)
                wait_for(lambda: (self.directory / (name + ".ready.json")).exists(), self.services)
                ready = json.loads((self.directory / (name + ".ready.json")).read_text())
                def healthy():
                    try:
                        with urllib.request.urlopen(ready["endpoint"] + "/health", timeout=1) as response:
                            return response.status == 200
                    except OSError:
                        return False
                wait_for(healthy, self.services)
                self.entries.append({"scenario": "writes/" + name, "fixtureId": fixture_ids[index], "endpoint": ready["endpoint"], "endpointParameter": "baseUrl", "bindings": [{"parameter": "marker", "value": "private-" + name + "-marker"}], "secretEnvironment": [{"parameter": "token", "variable": "SCENARIO_PRIVATE_TOKEN"}]})
        except BaseException:
            self.stop()
            raise

    def invoke(self, label="run", entries=None, jobs=2, cancel=False):
        inputs = self.directory / (label + ".inputs.json")
        inputs.touch(mode=0o600)
        inputs.write_text(json.dumps({"version": 1, "scenarios": self.entries if entries is None else entries}))
        reports = self.directory / (label + ".reports")
        command = [self.workbench, "--workspace", str(FIXTURE / "hurl-workbench.dhall"), "test", "suite", "independent-writes", "--external-service", "--scenario-inputs", str(inputs), "--allow-mutating", "--jobs", str(jobs), "--max-time", "30", "--report", "json", "--report-dir", str(reports)]
        if self.mode == "failure":
            command.append("--fail-fast")
        with (self.directory / (label + ".stdout")).open("wb") as stdout, (self.directory / (label + ".stderr")).open("wb") as stderr:
            process = subprocess.Popen(command, env=self.environment, stdout=stdout, stderr=stderr, start_new_session=True)
            if cancel:
                wait_for(lambda: all((self.directory / (name + ".posted")).exists() for name in ("first", "second")), [process])
                process.send_signal(signal.SIGINT)
            try:
                status = process.wait(timeout=40)
                if status < 0:
                    status = 128 - status
            except BaseException:
                process.kill()
                process.wait()
                raise
        for pid_file in self.directory.glob("child-*.pid"):
            assert not alive(int(pid_file.read_text())), "Hurl child survived workbench return"
        assert all(service.poll() is None for service in self.services), "workbench stopped provider-owned service"
        summary = reports / "independent-writes/summary.json"
        if summary.exists():
            data = json.loads(summary.read_text())
            assert data["isolation"] == "independent-state"
            assert [case["scenario"] for case in data["cases"]] == ["writes/first", "writes/second"]
            raw = summary.read_bytes()
            for entry in self.entries:
                for sentinel in (entry["fixtureId"], entry["endpoint"], entry["bindings"][0]["value"], "SCENARIO_PRIVATE_TOKEN", self.environment["SCENARIO_PRIVATE_TOKEN"]):
                    assert sentinel.encode() not in raw, "summary contains private runtime metadata"
            if data["status"] in ("refused", "setup-failed"):
                assert all(case["status"] == "not-started" and not case["reports"] and "exitCode" not in case for case in data["cases"])
            diagnostics = (self.directory / (label + ".stderr")).read_bytes()
            for entry in self.entries:
                for sentinel in (entry["fixtureId"], entry["endpoint"], entry["bindings"][0]["value"], "SCENARIO_PRIVATE_TOKEN", self.environment["SCENARIO_PRIVATE_TOKEN"]):
                    assert sentinel.encode() not in diagnostics, "workbench diagnostics contain private runtime metadata"
        return status, summary

    def refuse_duplicates(self):
        for label, change in (("fixture", {"fixtureId": self.entries[0]["fixtureId"]}), ("endpoint", {"endpoint": self.entries[0]["endpoint"] + "/"})):
            entries = [self.entries[0], dict(self.entries[1], **change)]
            status, _ = self.invoke(label, entries)
            assert status == 2
        status, _ = self.invoke("incomplete", self.entries[:1])
        assert status == 2
        # A missing secret is a setup failure with no fabricated Hurl exit.
        entries = [dict(entry, secretEnvironment=[{"parameter": "token", "variable": "PRIVATE_ABSENT_SCENARIO_ENV_972638"}]) for entry in self.entries]
        status, summary = self.invoke("missing-secret", entries)
        assert status == 2
        if summary.exists():
            assert json.loads(summary.read_text())["status"] == "setup-failed"
            assert b"PRIVATE_ABSENT_SCENARIO_ENV_972638" not in summary.read_bytes()
            assert b"PRIVATE_ABSENT_SCENARIO_ENV_972638" not in (self.directory / "missing-secret.stderr").read_bytes()
        assert not list(self.directory.glob("child-*.pid")), "refusal started Hurl"
        assert not list(self.directory.glob("*.posted")), "refusal reached provider service"
        print("duplicate assignments refused: PASS", flush=True)

    def stop(self):
        for pid_file in self.directory.glob("child-*.pid"):
            assert not alive(int(pid_file.read_text())), "provider cleanup preceded Hurl cleanup"
        for process in self.services:
            process.terminate()
        for process in self.services:
            process.wait(timeout=10)
        assert all(process.poll() is not None for process in self.services)
