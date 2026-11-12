"""Public CLI handoff proof with two explicit in-memory provider fixtures."""
import os
import pathlib
import tempfile
from scenario_isolation import ScenarioRun, executable

workbench = executable("hurl-workbench", os.environ.get("HURL_WORKBENCH_EXECUTABLE"))
with tempfile.TemporaryDirectory(prefix="scenario-local-") as temporary:
    run = ScenarioRun(pathlib.Path(temporary) / "services", workbench, [{}, {}], ["private-fixture-a", "private-fixture-b"], memory=True)
    try:
        run.refuse_duplicates()
        status, summary = run.invoke()
        assert status == 0, "independent local writes failed"
        print("independent local writes: PASS", flush=True)
    finally:
        run.stop()
