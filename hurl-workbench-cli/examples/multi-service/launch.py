#!/usr/bin/env python3
"""Pass resolved environment values to the test fixture executable."""
import os
import sys

role = sys.argv[1]
if role in ("setup", "teardown"):
    from pathlib import Path
    root = Path(os.environ["STATE_DIR"])
    if role == "teardown" and (root / "pids").exists():
        for pid in map(int, (root / "pids").read_text().splitlines()):
            try:
                os.kill(pid, 0)
            except ProcessLookupError:
                continue
            raise RuntimeError("owned consumer survived before teardown")
    with (root / "events").open("a") as events:
        events.write(role + "\n")
    raise SystemExit(0)

os.execv(os.environ["FIXTURE_EXECUTABLE"], [os.environ["FIXTURE_EXECUTABLE"], "--role", sys.argv[1], "--port", os.environ["ROLE_PORT"], "--state-dir", os.environ["STATE_DIR"]])
