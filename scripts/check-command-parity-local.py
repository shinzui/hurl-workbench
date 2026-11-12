#!/usr/bin/env python3
"""Provision independent local example fixtures; caller owns their lifetime."""
import json
import os
from pathlib import Path
import secrets
import socket
import subprocess
import tempfile
import time
from urllib.request import urlopen

repo = Path(__file__).resolve().parents[1]
example = Path(os.environ.get('HURL_WORKBENCH_PARITY_EXAMPLE', repo / 'examples/executable-checks')).resolve()
with tempfile.TemporaryDirectory(prefix="workbench-parity-") as temporary:
    root = Path(temporary)
    for side in ('cli', 'api'):
        fixture = root / side
        fixture.mkdir(mode=0o700)
        (fixture / 'facts.json').write_text(json.dumps([dict(key='parity', value='same')]))
        (fixture / 'facts.json').chmod(0o600)
    with socket.socket() as s:
        s.bind(('127.0.0.1', 0))
        port = s.getsockname()[1]
    env = dict(os.environ, PARITY_TOKEN=secrets.token_hex(24))
    endpoint = f'http://127.0.0.1:{port}'
    server = subprocess.Popen(['python3', str(example / 'app.py'), 'serve', str(root / 'api'), str(port)], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        for _ in range(100):
            try:
                with urlopen(endpoint + '/health', timeout=0.1):
                    break
            except OSError:
                time.sleep(0.03)
        else:
            raise RuntimeError('example API did not become ready')
        env.update(HURL_WORKBENCH_CONSUMER_WORKSPACE=str(example / 'hurl-workbench.dhall'),
                   HURL_WORKBENCH_CONSUMER_SUITE='parity', HURL_WORKBENCH_CLI_FIXTURE=str(root / 'cli'),
                   HURL_WORKBENCH_API_URL=endpoint, HURL_WORKBENCH_CLI_FIXTURE_ID='local-cli', HURL_WORKBENCH_API_FIXTURE_ID='local-http',
                   HURL_WORKBENCH_CONSUMER_EVIDENCE_ROOT=str(root / 'evidence'), HURL_WORKBENCH_CONSUMER_SECRET_SENTINEL=env['PARITY_TOKEN'],
                   REI_PG_CONNECTION_STRING='irrelevant-ambient-sentinel', MORI_API_URL='irrelevant-ambient-sentinel')
        subprocess.run(['bash', str(repo / 'scripts/check-command-parity.sh')], env=env, check=True)
    finally:
        server.terminate()
        server.wait(timeout=5)
