#!/usr/bin/env python3
"""Consumer-controlled failure injection inside a caller's active fixture lease."""
import json
import os
from pathlib import Path
import signal
import subprocess
import time


def events(path):
    if not path.exists():
        return []
    # Ignore a final line while the producer is appending it.
    return [json.loads(line) for line in path.read_text().splitlines(keepends=True) if line.endswith("\n")]


workspace = Path(os.environ["HURL_WORKBENCH_CONSUMER_WORKSPACE"])
root = Path(os.environ["HURL_WORKBENCH_CONSUMER_EVIDENCE_ROOT"])
if not workspace.is_absolute() or not workspace.is_file() or not root.is_absolute():
    raise SystemExit("consumer manifest and evidence root must be absolute paths")
root.mkdir(mode=0o700, parents=True, exist_ok=True)
root.chmod(0o700)
suite = os.environ["HURL_WORKBENCH_CONSUMER_SUITE"]
for variant in ["success", "readiness-failure", "unexpected-exit", "cancellation"]:
    evidence = root / variant
    evidence.mkdir(mode=0o700)  # Refuse reuse of stale PID or event evidence.
    env = dict(os.environ, HURL_WORKBENCH_CONSUMER_VARIANT=variant,
               HURL_WORKBENCH_CONSUMER_EVIDENCE_DIR=str(evidence))
    command = [os.environ["HURL_WORKBENCH_EXECUTABLE"], "--workspace", str(workspace),
               "test", "suite", suite, "--jobs", "1", "--allow-mutating",
               "--report-dir", str(evidence / "reports")]
    variables = env.get("HURL_WORKBENCH_CONSUMER_VARIABLES_FILE")
    if variables:
        command += ["--variables-file", variables]
    if variant == "success":
        unsafe = command.copy()
        unsafe[unsafe.index("--jobs") + 1] = "2"
        unsafe[unsafe.index("--report-dir") + 1] = str(evidence / "refused-reports")
        refused = subprocess.run(unsafe, env=env, stdin=subprocess.DEVNULL, capture_output=True, timeout=30)
        assert refused.returncode == 2 and b"shared-state-parallel-unsafe" in refused.stderr
        assert not (evidence / "events.jsonl").exists(), "isolation refusal must precede setup"
    log = evidence / "driver.log"
    with log.open("xb") as output:
        log.chmod(0o600)
        process = subprocess.Popen(command, env=env, stdin=subprocess.DEVNULL, stdout=output, stderr=output, start_new_session=True)
        try:
            if variant == "cancellation":
                deadline = time.monotonic() + 60
                while not any(row["event"] == "cancel-ready" for row in events(evidence / "events.jsonl")):
                    if process.poll() is not None or time.monotonic() >= deadline:
                        raise RuntimeError("consumer did not reach its cancellation checkpoint")
                    time.sleep(0.02)
                process.send_signal(signal.SIGINT)
            status = process.wait(timeout=90)
        finally:
            if process.poll() is None:
                process.send_signal(signal.SIGINT)
                process.wait(timeout=45)
    expected = {0} if variant == "success" else ({-signal.SIGINT, 130} if variant == "cancellation" else {4})
    assert status in expected, f"{variant}: unexpected exit {status}; see private driver.log"
    raw_summary = (evidence / "reports" / suite / "summary.json").read_text()
    assert str(evidence) not in raw_summary and str(workspace) not in raw_summary
    sentinel = env.get("HURL_WORKBENCH_CONSUMER_SECRET_SENTINEL")
    if sentinel:
        assert sentinel not in raw_summary
    summary = json.loads(raw_summary)
    rows = events(evidence / "events.jsonl")
    mutations = [row for row in rows if row["event"] == "mutation"]
    observations = [row for row in rows if row["event"] == "observation"]
    if variant == "success":
        assert len(mutations) == 1, "command must be submitted exactly once"
        assert observations and all(row["owner"] for row in observations), "real owner-backed observations required"
        assert summary["status"] == "passed"
        assert any(step.get("action") == "restart" and step["status"] == "passed" for step in summary["steps"])
    if variant == "readiness-failure":
        assert not mutations, "readiness failure must precede mutation"
    assert rows[-1]["event"] == "consumers-stopped", "consumer must confirm shutdown before returning to the lease owner"
    pids = json.loads((evidence / "pids.json").read_text())
    assert len(pids) >= 3, "API, stub and actual projection owner must supply PID evidence"
    for pid in pids:
        assert isinstance(pid, int) and pid > 1
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            continue
        raise AssertionError(f"{variant}: owned consumer survived")
print("real leased consumer lifecycle: PASS; caller still owns lease release")
