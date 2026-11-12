#!/usr/bin/env python3
"""Two independently provisioned Rei scopes for the executable-check consumer."""
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
from urllib.request import Request, urlopen

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


(evidence / 'artifacts.json').write_text(json.dumps({name: hashlib.sha256(Path(value).read_bytes()).hexdigest() for name, value in vars(args).items() if name != 'evidence_root'}))
(evidence / 'artifacts.json').chmod(0o600)

with tempfile.TemporaryDirectory(prefix="wbp-", dir="/tmp") as temporary:
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
    leases = []
    consumers = []
    try:
        fixtures = root / "fixtures"
        bundles = root / "bundles"
        fixtures.mkdir()
        bundles.mkdir()
        config = root / "hinagata.json"
        role = dict(user=user, database="postgres", password=password)
        revision = hashlib.sha256(Path(args.schema_hook).read_bytes()).hexdigest()
        config.write_text(json.dumps(dict(project=dict(id="workbench-rei-parity"),
            endpoint=dict(host=str(sock), port="5432"), fixture=dict(root=str(fixtures)),
            bundle=dict(root=str(bundles)), maintenance=dict(database="postgres"),
            administration=role, setup=role, application=role,
            migration=dict(executable=args.schema_hook, argv=["--hinagata-schema"], revision=revision),
            verification=dict(executable=args.schema_hook, argv=["--hinagata-verify"], revision=revision))))
        config.chmod(0o600)
        command = [args.hinagata, "--config", str(config)]
        run(command + ["db", "prepare", "--json"])
        token = secrets.token_hex(24)
        connections = []
        for side in ('cli', 'http'):
            lease = json.loads(run(command + ['db', 'acquire', '--json']))
            leases.append(lease)
            connections.append(' '.join(['host=' + lease['host'], 'port=' + str(lease['port']),
                                         'dbname=' + lease['database'], 'user=' + lease['user'],
                                         'passfile=' + str(passfile)]))
        assert leases[0]['database'] != leases[1]['database']
        api_ports = ports()
        endpoints = []
        for index, side in enumerate(('cli', 'http')):
            scope = root / side
            scope.mkdir(mode=0o700)
            (scope / 'home').mkdir(mode=0o700)
            (scope / 'workspace').mkdir(mode=0o700)
            config = scope / 'rei.yaml'
            config.write_text('workspace:\n  path: ' + str(scope / 'workspace') + '\ngit:\n  enabled: false\n')
            endpoint = 'http://127.0.0.1:' + api_ports[index]
            endpoints.append(endpoint)
            (scope / 'endpoint').write_text(endpoint)
            child_env = dict(env, HOME=str(scope / 'home'), REI_CONFIG=str(config),
                             REI_PG_CONNECTION_STRING=connections[index], REI_API_PORT=api_ports[index],
                             REI_API_TOKENS=token + '=human', MORI_API_URL='http://127.0.0.1:1')
            log = (evidence / (side + '-api.log')).open('wb')
            (evidence / (side + '-api.log')).chmod(0o600)
            try:
                child = subprocess.Popen([args.api], env=child_env, stdin=subprocess.DEVNULL,
                                         stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
            finally:
                log.close()
            consumers.append(child)
            for _ in range(400):
                try:
                    with urlopen(endpoint + '/health/ready', timeout=0.2) as response:
                        if response.status == 200:
                            break
                except OSError:
                    time.sleep(0.05)
                if child.poll() is not None:
                    raise RuntimeError('Rei API exited; see private API log')
            else:
                raise RuntimeError('Rei API readiness timed out')
        cli_env = dict(env, REI_CONFIG=str(root / 'cli' / 'rei.yaml'), HOME=str(root / 'cli' / 'home'),
                       REI_PG_CONNECTION_STRING=connections[0], REI_API_URL=endpoints[0], REI_API_TOKEN=token)
        created = subprocess.run([args.rei, 'category', 'create', 'Workbench parity', '--description', 'Independent parity fact'],
                                 env=cli_env, stdin=subprocess.DEVNULL, capture_output=True, timeout=30)
        if created.returncode:
            (evidence / 'cli-create.log').write_bytes(created.stdout + created.stderr)
            (evidence / 'cli-create.log').chmod(0o600)
            raise RuntimeError('Rei CLI category create failed; see private log')
        request = Request(endpoints[1] + '/api/v2/categories',
                          data=json.dumps(dict(name='Workbench parity', description='Independent parity fact')).encode(),
                          headers={'Authorization': 'Bearer ' + token, 'Content-Type': 'application/json'})
        with urlopen(request, timeout=15) as response:
            assert response.status == 201
        env.update(PARITY_TOKEN=token, HURL_WORKBENCH_PARITY_REI=args.rei,
                   REI_PARITY_CLI_DATABASE=connections[0], HURL_WORKBENCH_EXECUTABLE=args.workbench,
                   HURL_WORKBENCH_CONSUMER_WORKSPACE=str(repo / 'examples/executable-checks/rei/hurl-workbench.dhall'),
                   HURL_WORKBENCH_CONSUMER_SUITE='parity', HURL_WORKBENCH_CLI_FIXTURE=str(root / 'cli'),
                   HURL_WORKBENCH_API_URL=endpoints[1], HURL_WORKBENCH_CLI_FIXTURE_ID=leases[0]['leaseId'],
                   HURL_WORKBENCH_API_FIXTURE_ID=leases[1]['leaseId'],
                   HURL_WORKBENCH_CONSUMER_EVIDENCE_ROOT=str(evidence / 'consumer'),
                   HURL_WORKBENCH_CONSUMER_SECRET_SENTINEL=token,
                   MORI_API_URL='ambient-mori-sentinel', REI_PG_CONNECTION_STRING='ambient-db-sentinel')
        run(['bash', str(repo / 'scripts/check-command-parity.sh')])
        print('real Rei independent category CLI/API parity and semantic mismatch: PASS')
    finally:
        try:
            # Stop and prove absence of both owned groups before releasing either
            # fixture. Even failed acceptance stops this disposable cluster below.
            for child in consumers:
                try:
                    os.killpg(child.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
            for child in consumers:
                try:
                    child.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    os.killpg(child.pid, signal.SIGKILL)
                    child.wait(timeout=5)
                try:
                    os.killpg(child.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                deadline = time.monotonic() + 5
                while True:
                    try:
                        os.killpg(child.pid, 0)
                    except ProcessLookupError:
                        break
                    if time.monotonic() >= deadline:
                        raise RuntimeError('owned API group survived; refuse fixture release')
                    time.sleep(0.01)
            stopped_at = time.time_ns()
            releases = []
            for lease in leases:
                run(command + ['db', 'release', lease['leaseId'], '--json'])
                state = json.loads(run(command + ['inspect', lease['leaseId'], '--json']))
                assert state['candidate']['state'] == 'Released'
                releases.append(dict(state='Released', at=time.time_ns()))
            (evidence / 'release.json').write_text(json.dumps(dict(consumersStoppedAt=stopped_at, groupsAbsent=True, releases=releases)))
            (evidence / 'release.json').chmod(0o600)
        finally:
            run(['pg_ctl', '-D', str(data), '-m', 'immediate', '-w', 'stop'])
