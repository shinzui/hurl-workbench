"""Real Hinagata leases and database-backed concurrent scenario acceptance."""
import argparse
import json
import os
import pathlib
import secrets
import subprocess
import tempfile
from scenario_isolation import ScenarioRun, executable

parser = argparse.ArgumentParser()
parser.add_argument("--early", action="store_true", help="Run only the initial two-lease producer/consumer proof")
options = parser.parse_args()
hinagata = executable("hinagata", os.environ.get("HINAGATA_EXECUTABLE"))
workbench = executable("hurl-workbench", os.environ.get("HURL_WORKBENCH_EXECUTABLE"))
tools = {name: executable(name) for name in ("initdb", "pg_ctl", "psql", "id")}
environment = {key: value for key, value in os.environ.items() if not key.startswith(("PG", "HINAGATA_"))}


def run(argv):
    result = subprocess.run(argv, env=environment, capture_output=True)
    if result.returncode:
        raise RuntimeError(f"{pathlib.Path(argv[0]).name} failed (exit {result.returncode}); private diagnostics retained by caller")
    return result.stdout


with tempfile.TemporaryDirectory(prefix="scenario-provider-", dir="/tmp") as temporary:
    directory = pathlib.Path(temporary)
    socket = directory / "socket"
    socket.mkdir()
    data = directory / "data"
    password = secrets.token_hex(24)
    password_input = directory / "init-password"
    password_input.touch(mode=0o600)
    password_input.write_text(password + "\n")
    user = run([tools["id"], "-un"]).decode().strip()
    run([tools["initdb"], "-D", str(data), "--auth=scram-sha-256", "--pwfile", str(password_input), "--no-locale", "--encoding=UTF8"])
    passfile = directory / "admin.pgpass"
    passfile.touch(mode=0o600)
    passfile.write_text(f"*:5432:*:{user}:{password}\n")
    environment.update(PGHOST=str(socket), PGPORT="5432", PGUSER=user, PGDATABASE="postgres", PGPASSFILE=str(passfile))
    started = False
    try:
        run([tools["pg_ctl"], "-D", str(data), "-l", str(directory / "postgres.log"), "-o", f"-k {socket} -p 5432 -c listen_addresses=''", "-w", "start"])
        started = True
        fixtures = directory / "fixtures"
        (fixtures / "base").mkdir(parents=True)
        (fixtures / "base/fixture.sql").write_text("CREATE TABLE baseline_probe (id integer);\n")
        bundles = directory / "bundles"
        bundles.mkdir()
        config = directory / "hinagata.yaml"
        config.write_text("project:\n  id: scenario-workbench\nbaseline:\n  fixtures: [base]\n")
        environment.update(HINAGATA_ENDPOINT_HOST=str(socket), HINAGATA_ENDPOINT_PORT="5432", HINAGATA_FIXTURE_ROOT=str(fixtures), HINAGATA_BUNDLE_ROOT=str(bundles), HINAGATA_MAINTENANCE_DATABASE="postgres")
        for role in ("ADMINISTRATION", "SETUP", "APPLICATION"):
            for key, value in (("USER", user), ("DATABASE", "postgres"), ("PASSWORD", password)):
                environment[f"HINAGATA_{role}_{key}"] = value
        command = [hinagata, "--config", str(config)]
        for mode in (["success"] if options.early else ["success", "failure", "cancellation", "allocation-failure"]):
            leases = []
            services = None
            releases = []
            try:
                for index in range(2):
                    if mode == "allocation-failure" and index == 1:
                        refused = subprocess.run(command + ["db", "acquire", "--fixture", "absent", "--json"], env=environment, capture_output=True)
                        assert refused.returncode != 0
                        assert not (directory / mode).exists(), "incomplete allocation started consumers"
                        break
                    lease = json.loads(run(command + ["db", "acquire", "--json"]))
                    leases.append(lease)
                if mode == "allocation-failure":
                    print("partial allocation refused before consumers: PASS", flush=True)
                    continue
                connections = []
                for lease in leases:
                    connection = {"PGHOST": lease["host"], "PGPORT": str(lease["port"]), "PGUSER": lease["user"], "PGDATABASE": lease["database"], "PGPASSFILE": str(passfile), "SCENARIO_PSQL": tools["psql"]}
                    private = subprocess.run([tools["psql"], "-X", "-w", "-Atqc", "SELECT current_database(), current_user;"], env=dict(environment, **connection), capture_output=True)
                    assert private.returncode == 0 and private.stdout.decode().strip() == lease["database"] + "|" + lease["user"]
                    connections.append(connection)
                assert len({lease["database"] for lease in leases}) == 2
                services = ScenarioRun(directory / mode, workbench, connections, [lease["leaseId"] for lease in leases], mode=mode)
                if mode == "success":
                    services.refuse_duplicates()
                status, summary = services.invoke(jobs=1 if mode == "failure" else 2, cancel=mode == "cancellation")
                assert status == {"success": 0, "failure": 4, "cancellation": 130}[mode], f"unexpected workbench status {status} for {mode}"
                data_summary = json.loads(summary.read_text())
                if mode == "failure":
                    assert [case["status"] for case in data_summary["cases"]] == ["failed", "skipped-fail-fast"]
                    assert not (directory / mode / "second.posted").exists(), "queued case started after fail-fast"
                elif mode == "cancellation":
                    assert data_summary["status"] == "cancelled"
                    # A Hurl process can publish its actual failed exit while SIGINT
                    # is being delivered. Completed outcomes must be retained.
                    assert all(case["status"] in ("cancelled", "failed") for case in data_summary["cases"])
                    assert all(not case["reports"] for case in data_summary["cases"] if case["status"] == "cancelled")
                if mode == "success":
                    for index, connection in enumerate(connections):
                        query = subprocess.run([tools["psql"], "-X", "-w", "-Atqc", "SELECT marker FROM scenario_markers ORDER BY marker;"], env=dict(environment, **connection), capture_output=True)
                        assert query.returncode == 0 and query.stdout.strip() == (b"private-first-marker" if index == 0 else b"private-second-marker")
                    print("independent writes: PASS", flush=True)
            finally:
                if services is not None:
                    services.stop()
                for lease in leases:
                    assert lease["leaseId"] not in releases, "duplicate release"
                    run(command + ["db", "release", lease["leaseId"], "--json"])
                    releases.append(lease["leaseId"])
                    inspection = json.loads(run(command + ["inspect", lease["leaseId"], "--json"]))
                    assert inspection["candidate"]["state"] == "Released"
                    escaped = lease["database"].replace("'", "''")
                    assert run([tools["psql"], "-X", "-w", "-Atqc", f"SELECT count(*) FROM pg_database WHERE datname = '{escaped}'"]).strip() == b"0"
                assert len(releases) == len(leases)
                assert passfile.is_file(), "consumer removed provider credentials"
                print(f"provider cleanup ({mode}): PASS", flush=True)
    finally:
        if started:
            subprocess.run([tools["pg_ctl"], "-D", str(data), "-m", "immediate", "-w", "stop"], env=environment, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
