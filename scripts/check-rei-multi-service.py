#!/usr/bin/env python3
"""Caller-owned Hinagata lease for the production Rei lifecycle consumer."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import secrets
import signal
import time
import socket
import subprocess
import tempfile

parser = argparse.ArgumentParser()
for name in ["api", "rei", "schema-hook", "hinagata", "workbench"]:
    parser.add_argument("--" + name, required=True)
parser.add_argument("--evidence-root", required=True)
args = parser.parse_args()
evidence = Path(args.evidence_root).resolve()
evidence.mkdir(mode=0o700, parents=True)  # New evidence only.
repo = Path(__file__).resolve().parents[1]
env = {key: value for key, value in os.environ.items()
       if not key.startswith(("PG", "REI_", "MORI_", "HINAGATA_", "HURL_WORKBENCH_"))}
env["OTEL_SDK_DISABLED"] = "true"
if "hinagata_postgres_datadir" in os.environ:
    env["hinagata_postgres_datadir"] = os.environ["hinagata_postgres_datadir"]


def run(command):
    result = subprocess.run(command, env=env, capture_output=True)
    if result.returncode:
        with (evidence / "caller-error.log").open("ab") as output:
            output.write(result.stdout + result.stderr)
        (evidence / "caller-error.log").chmod(0o600)
        raise RuntimeError(f"{Path(command[0]).name} failed: see private caller-error.log")
    return result.stdout


def ports():
    sockets = [socket.socket(), socket.socket()]
    try:
        for s in sockets:
            s.bind(("127.0.0.1", 0))
        return [str(s.getsockname()[1]) for s in sockets]
    finally:
        for s in sockets:
            s.close()


with tempfile.TemporaryDirectory(prefix="wbr-", dir="/tmp") as temporary:
    root = Path(temporary)
    data = root / "pg"
    sock = root / "sock"
    sock.mkdir(mode=0o700)
    password = secrets.token_hex(24)
    password_input = root / "password"
    password_input.touch(mode=0o600)
    password_input.write_text(password + "\n")
    user = run(["id", "-un"]).decode().strip()
    run(["initdb", "-D", str(data), "--auth=scram-sha-256", "--pwfile", str(password_input), "--no-locale", "--encoding=UTF8"])
    passfile = root / "pgpass"
    passfile.touch(mode=0o600)
    passfile.write_text(f"*:5432:*:{user}:{password}\n")
    env.update(PGHOST=str(sock), PGPORT="5432", PGDATABASE="postgres", PGUSER=user, PGPASSFILE=str(passfile))
    run(["pg_ctl", "-D", str(data), "-l", str(root / "postgres.log"), "-o", f"-k {sock} -p 5432 -c listen_addresses=''", "-w", "start"])
    lease = None
    try:
        fixtures = root / "fixtures"
        bundles = root / "bundles"
        fixtures.mkdir()
        bundles.mkdir()
        config = root / "hinagata.json"
        role = dict(user=user, database="postgres", password=password)
        revision = hashlib.sha256(Path(args.schema_hook).read_bytes()).hexdigest()
        config.write_text(json.dumps(dict(project=dict(id="workbench-rei-lifecycle"),
            endpoint=dict(host=str(sock), port="5432"), fixture=dict(root=str(fixtures)),
            bundle=dict(root=str(bundles)), maintenance=dict(database="postgres"),
            administration=role, setup=role, application=role,
            migration=dict(executable=args.schema_hook, argv=["--hinagata-schema"], revision=revision),
            verification=dict(executable=args.schema_hook, argv=["--hinagata-verify"], revision=revision))))
        config.chmod(0o600)
        command = [args.hinagata, "--config", str(config)]
        run(command + ["db", "prepare", "--json"])
        lease = json.loads(run(command + ["db", "acquire", "--json"]))
        conn = " ".join(["host=" + lease["host"], "port=" + str(lease["port"]),
                         "dbname=" + lease["database"], "user=" + lease["user"], "passfile=" + str(passfile)])
        caller_config = root / "rei.yaml"
        caller_config.write_text("workspace:\n  path: " + str(root / "workspace") + "\n")
        env.update(REI_CONFIG=str(caller_config), REI_PG_CONNECTION_STRING=conn)
        # An independent static anchor fixture; the observed Note is created
        # exclusively through the production HTTP command and async owner.
        topic = "topic_01m76638egeeqa9pyrp8p3f3q5"
        env.update(PGHOST=lease["host"], PGPORT=str(lease["port"]), PGDATABASE=lease["database"], PGUSER=lease["user"])
        run(["psql", "-X", "-w", "-v", "ON_ERROR_STOP=1", "-c",
             "INSERT INTO public.topics (topic_id,topic_key,topic_label,created_at) VALUES ('" + topic + "','workbench-lifecycle','Workbench lifecycle fixture',now())"])
        api_port, stub_port = ports()
        env.update(REI_LIFECYCLE_DB=conn, REI_LIFECYCLE_TOKEN=secrets.token_hex(24),
                   REI_LIFECYCLE_TOPIC=topic, REI_LIFECYCLE_API=args.api,
                   REI_LIFECYCLE_CLI=args.rei, REI_LIFECYCLE_API_PORT=api_port,
                   REI_LIFECYCLE_STUB_PORT=stub_port, HURL_WORKBENCH_EXECUTABLE=args.workbench,
                   HURL_WORKBENCH_CONSUMER_WORKSPACE=str(repo / "examples/multi-service/rei/hurl-workbench.dhall"),
                   HURL_WORKBENCH_CONSUMER_SUITE="production", HURL_WORKBENCH_CONSUMER_EVIDENCE_ROOT=str(evidence / "variants"))
        env["HURL_WORKBENCH_CONSUMER_SECRET_SENTINEL"] = env["REI_LIFECYCLE_TOKEN"]
        run(["bash", str(repo / "scripts/check-multi-service-lease.sh")])
        run(command + ["db", "release", lease["leaseId"], "--json"])
        released = json.loads(run(command + ["inspect", lease["leaseId"], "--json"]))
        assert released["candidate"]["state"] == "Released"
        lease = None
        stopped_at = max(row["at"] for events in (evidence / "variants").glob("*/events.jsonl") for row in map(json.loads, events.read_text().splitlines()) if row["event"] == "consumers-stopped")
        released_at = time.time_ns()
        assert stopped_at < released_at
        (evidence / "release.json").write_text(json.dumps(dict(status="Released", consumersStoppedAt=stopped_at, releasedAt=released_at, ordering="all four consumer scopes stopped before caller release")))
        (evidence / "release.json").chmod(0o600)
        print("production Rei command/read, worker restart, failure/cancellation and caller lease release: PASS")
    finally:
        try:
            if lease is not None:
                # Never release an uncertain consumer scope. Hinagata preserves such a
                # clone until this disposable cluster is stopped by its caller.
                known = [pid for pids in (evidence / "variants").glob("*/pids.json") for pid in json.loads(pids.read_text())] if (evidence / "variants").exists() else []
                for pid in known:
                    try:
                        if os.getpgid(pid) == pid:
                            os.killpg(pid, signal.SIGTERM)
                    except ProcessLookupError:
                        pass
                deadline = time.monotonic() + 10
                while True:
                    alive = []
                    for pid in known:
                        try:
                            os.kill(pid, 0)
                            alive.append(pid)
                        except ProcessLookupError:
                            pass
                    if not alive or time.monotonic() >= deadline:
                        break
                    time.sleep(0.02)
                stopped = not alive
                if stopped:
                    run(command + ["db", "release", lease["leaseId"], "--json"])
        finally:
            run(["pg_ctl", "-D", str(data), "-m", "immediate", "-w", "stop"])
