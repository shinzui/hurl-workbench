"""Opt-in real Hinagata acceptance in a disposable password-authenticated cluster.

Discover/build HINAGATA_EXECUTABLE through mori://shinzui/hinagata first.
Requires PostgreSQL tools, Hurl, and the built workbench in the caller environment.
"""
import json
import os
import pathlib
import secrets
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent


def executable(name, override=None):
    value = override or shutil.which(name)
    if not value or not os.access(value, os.X_OK):
        raise SystemExit(f"required executable unavailable: {name}")
    return os.path.abspath(value)


HINAGATA = executable("hinagata", os.environ.get("HINAGATA_EXECUTABLE"))
WORKBENCH = executable("hurl-workbench", os.environ.get("HURL_WORKBENCH_EXECUTABLE"))
TOOLS = {name: executable(name) for name in ("initdb", "pg_ctl", "psql", "bash")}
# Remove ambient libpq/provider configuration before creating our own test cluster.
environment = {k: v for k, v in os.environ.items() if not k.startswith(("PG", "HINAGATA_"))}
environment["HURL_WORKBENCH_EXECUTABLE"] = WORKBENCH


def run(argv, **kwargs):
    result = subprocess.run(argv, env=environment, capture_output=True, **kwargs)
    if result.returncode:
        # Deliberately avoid forwarding connection diagnostics or credentials.
        raise RuntimeError(f"{pathlib.Path(argv[0]).name} failed (exit {result.returncode})")
    return result.stdout


CALLBACK = '''
import json, os, pathlib, subprocess, sys
password_file = pathlib.Path(os.environ["PGPASSFILE"])
assert password_file.stat().st_mode & 0o077 == 0
result = subprocess.run([sys.argv[1], sys.argv[2], "--mode", sys.argv[4], "--propagate-status"])
assert password_file.is_file(), "consumer removed the owner's password file"
pathlib.Path(sys.argv[3]).write_text(json.dumps({
    "database": os.environ["PGDATABASE"], "passwordFile": str(password_file)
}))
print("consumers stopped before owner release: PASS", flush=True)
sys.exit(result.returncode)
'''

with tempfile.TemporaryDirectory(prefix="clean-provider-", dir="/tmp") as temporary:
    directory = pathlib.Path(temporary)
    data = directory / "data"
    socket = directory / "socket"
    socket.mkdir()
    password = secrets.token_hex(24)
    password_input = directory / "init-password"
    password_input.touch(mode=0o600)
    password_input.write_text(password + "\n")
    user = run(["id", "-un"]).decode().strip()
    run([TOOLS["initdb"], "-D", str(data), "--auth=scram-sha-256",
         "--pwfile", str(password_input), "--no-locale", "--encoding=UTF8"])
    environment.update(PGHOST=str(socket), PGPORT="5432", PGUSER=user, PGDATABASE="postgres")
    admin_passfile = directory / "admin.pgpass"
    admin_passfile.touch(mode=0o600)
    admin_passfile.write_text(f"*:5432:*:{user}:{password}\n")
    environment["PGPASSFILE"] = str(admin_passfile)
    try:
        run([TOOLS["pg_ctl"], "-D", str(data), "-l", str(directory / "postgres.log"),
             "-o", f"-k {socket} -p 5432 -c listen_addresses=''", "-w", "start"])
        fixtures = directory / "fixtures"
        (fixtures / "base").mkdir(parents=True)
        (fixtures / "base" / "fixture.sql").write_text("CREATE TABLE lease_probe (id integer);\n")
        bundles = directory / "bundles"
        bundles.mkdir()
        config = directory / "hinagata.yaml"
        config.write_text("""project:
  id: clean-workbench
baseline:
  fixtures: [base]
""")
        environment.update(
            HINAGATA_ENDPOINT_HOST=str(socket), HINAGATA_ENDPOINT_PORT="5432",
            HINAGATA_FIXTURE_ROOT=str(fixtures), HINAGATA_BUNDLE_ROOT=str(bundles),
            HINAGATA_MAINTENANCE_DATABASE="postgres",
        )
        for role in ("ADMINISTRATION", "SETUP", "APPLICATION"):
            for key, value in (("USER", user), ("DATABASE", "postgres"), ("PASSWORD", password)):
                environment[f"HINAGATA_{role}_{key}"] = value
        command = [HINAGATA, "--config", str(config)]
        for mode in ("success", "failure", "cancellation"):
            callback_audit = directory / f"callback-{mode}.json"
            result = subprocess.run(command + ["db", "with", "--json", "--", sys.executable,
                                "-c", CALLBACK, TOOLS["bash"],
                                str(ROOT / "scripts/check-clean-environment-lease.sh"),
                                str(callback_audit), mode], env=environment, capture_output=True)
            report = json.loads(result.stdout)
            assert report["status"] == result.returncode
            if mode == "success":
                assert report["ok"] and result.returncode == 0
            elif mode == "failure":
                assert not report["ok"] and result.returncode == 4
            else:
                assert not report["ok"] and result.returncode == 130
            assert report["disposition"] == "LeaseReleased"
            inspection = json.loads(run(command + ["inspect", report["leaseId"], "--json"]))
            assert inspection["candidate"]["state"] == "Released"
            audit = json.loads(callback_audit.read_text())
            assert not pathlib.Path(audit["passwordFile"]).exists(), "owner password file still exists"
            database = audit["database"].replace("'", "''")
            count = run([TOOLS["psql"], "-X", "-w", "-Atqc",
                     f"SELECT count(*) FROM pg_database WHERE datname = '{database}'"])
            assert count.strip() == b"0", "released clone still exists"
            label = "success" if mode == "success" else mode + " cleanup"
            line = f"clean lease {label}: PASS"
            assert line.encode() in result.stderr
            assert b"consumers stopped before owner release: PASS" in result.stderr
            assert password.encode() not in result.stdout + result.stderr
            print(line)
            print(f"Hinagata {mode}: consumers stopped; state Released; clone absent; password file removed: PASS (child exit {result.returncode})", flush=True)
    finally:
        subprocess.run([TOOLS["pg_ctl"], "-D", str(data), "-m", "immediate", "-w", "stop"],
                       env=environment, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
