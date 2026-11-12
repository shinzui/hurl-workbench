#!/usr/bin/env python3
"""Verify effective permission refusal through the public CLI, even as root."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

binary = os.environ["HURL_WORKBENCH_EXECUTABLE"]
repo = Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory(prefix="file-root-permissions-", dir="/tmp") as temporary:
    root = Path(temporary)
    root.chmod(0o755)
    workspace = root / "workspace"
    workspace.mkdir()
    # A developer checkout may have private ancestor directories. Exercise an
    # installed-style copy without changing permissions on the caller's tree.
    installed = root / "hurl-workbench"
    shutil.copyfile(binary, installed)
    installed.chmod(0o755)
    shutil.copytree(repo / "schema", root / "schema", copy_function=shutil.copyfile)
    manifest = workspace / "hurl-workbench.dhall"
    source = (repo / "examples/file-body/hurl-workbench.dhall").read_text()
    manifest.write_text(source.replace("../../schema/package.dhall", str(root / "schema/package.dhall")))
    shutil.copyfile(repo / "examples/file-body/request.hurl", workspace / "request.hurl")
    tools = root / "bin"
    tools.mkdir()
    markers = root / "markers"
    markers.mkdir()
    markers.chmod(0o777)
    for name in ("hurl", "hurlfmt"):
        probe = tools / name
        probe.write_text('#!/usr/bin/env python3\nimport os\nfrom pathlib import Path\nPath(os.environ["PROBE_MARKER"]).touch()\nraise SystemExit(99)\n')
        probe.chmod(0o755)
    uid = os.geteuid()
    identity = {}
    if uid == 0:
        uid = 65534
        identity = {"user": uid, "group": uid, "extra_groups": []}
    env = dict(os.environ, PATH=str(tools) + os.pathsep + os.environ["PATH"], PROBE_MARKER=str(markers / "started"), HOME=str(markers))
    selections = [("run", "workflow", "send-body"), ("test", "workflow", "send-body"), ("run", "recipe", "send-body"), ("test", "recipe", "send-body"), ("matrix", "bodies"), ("test", "suite", "bodies")]
    for mode in (0o300, 0o600):
        body = root / f"body-{mode:o}"
        body.mkdir()
        if os.geteuid() == 0:
            os.chown(body, uid, uid)
        body.chmod(mode)
        try:
            for selection in selections:
                result = subprocess.run([str(installed), "--workspace", str(manifest), *selection, "--file-root", str(body)], env=env, cwd=root, capture_output=True, **identity)
                assert result.returncode == 2, (selection, mode, result.returncode, result.stderr)
                assert b"readable, searchable directory" in result.stderr, result.stderr
                assert not (markers / "started").exists(), "a child probe ran"
        finally:
            body.chmod(0o700)
print(f"effective file-root permissions: PASS (uid {uid})")
