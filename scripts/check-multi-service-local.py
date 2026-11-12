#!/usr/bin/env python3
"""Public CLI orchestration proof using deterministic roles, without a database."""
import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile


def ports():
    sockets = [socket.socket() for _ in range(3)]
    try:
        for s in sockets:
            s.bind(("127.0.0.1", 0))
        return [str(s.getsockname()[1]) for s in sockets]
    finally:
        for s in sockets:
            s.close()


binary = os.environ["HURL_WORKBENCH_EXECUTABLE"]
fixture = os.environ["HURL_WORKBENCH_FIXTURE_EXECUTABLE"]
workspace = Path(__file__).resolve().parents[1] / "examples/multi-service/hurl-workbench.dhall"
with tempfile.TemporaryDirectory(prefix="workbench-multi-") as temp:
    root = Path(temp)
    for suite, jobs in [("command-read", "1"), ("read-barriers", "2")]:
        state = root / suite
        state.mkdir(mode=0o700)
        if suite == "read-barriers":
            (state / "accepted").write_text("accepted")
        api, stub, worker = ports()
        env = dict(os.environ, HURL_WORKBENCH_FIXTURE_EXECUTABLE=fixture,
                   HURL_WORKBENCH_STATE_DIR=str(state), HURL_WORKBENCH_API_PORT=api,
                   HURL_WORKBENCH_STUB_PORT=stub, HURL_WORKBENCH_WORKER_PORT=worker,
                   PRIVATE_SENTINEL="private-summary-sentinel")
        command = [binary, "--workspace", str(workspace), "test", "suite", suite,
                   "--jobs", jobs, "--report-dir", str(state / "reports")]
        if suite == "command-read":
            unsafe = command.copy()
            unsafe[unsafe.index("--jobs") + 1] = "2"
            rejected = subprocess.run(unsafe + ["--allow-mutating"], env=env, capture_output=True, timeout=15)
            assert rejected.returncode == 2, rejected.stderr.decode()
            assert b"shared-state-parallel-unsafe" in rejected.stderr
            assert not (state / "events").exists()
            command += ["--allow-mutating", "--overwrite"]
        subprocess.run(command, env=env, check=True, timeout=30)
        raw = (state / "reports" / suite / "summary.json").read_text()
        assert "private-summary-sentinel" not in raw
        assert str(state) not in raw
        summary = json.loads(raw)
        assert summary["status"] == "passed"
        assert all(case["status"] == "passed" for case in summary["cases"])
        assert [step["action"] for step in summary["steps"] if step["kind"] == "service"] == ["restart"]
        assert [phase["status"] for phase in summary["phases"]] == ["passed", "passed"]
        events = (state / "events").read_text().splitlines()
        assert events[:7] == ["setup", "stub-start", "stub-ready", "api-start", "api-ready", "worker-start", "worker-ready"], events
        assert events[-4:] == ["worker-stop", "api-stop", "stub-stop", "teardown"], events
        assert events.count("api-mutation") == (1 if suite == "command-read" else 0)
        assert events.count("worker-start") == events.count("worker-ready") == events.count("worker-stop") == 2
        assert (state / "generation").read_text() == "2"
        for pid in map(int, (state / "pids").read_text().splitlines()):
            try:
                os.kill(pid, 0)
            except ProcessLookupError:
                continue
            raise AssertionError(f"owned process survived: {pid}")
print("multi-service command/read and parallel barriers: PASS (local roles; no lease evidence)")
