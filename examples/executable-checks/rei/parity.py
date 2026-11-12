#!/usr/bin/env python3
"""Rei-owned assertion over supported category CLI/HTTP contracts (MP29)."""
import json
import os
from pathlib import Path
import subprocess
import sys
from urllib.parse import urlencode, urlsplit
from urllib.request import Request, urlopen

cli_root, api_url, cli_id, api_id = sys.argv[1:]
cli_root = Path(cli_root)
cli_url = (cli_root / 'endpoint').read_text().strip()
assert cli_id and api_id and cli_id != api_id, 'fixture identities must differ'
assert urlsplit(cli_url).netloc != urlsplit(api_url).netloc, 'fixture endpoints must differ'
assert not any(key in os.environ for key in ('REI_PG_CONNECTION_STRING', 'MORI_API_URL', 'PGHOST')), 'ambient settings crossed Clean boundary'
env = dict(PATH=os.environ['PATH'], HOME=str(cli_root / 'home'),
           REI_CONFIG=str(cli_root / 'rei.yaml'), REI_API_URL=cli_url,
           REI_API_TOKEN=os.environ['PARITY_TOKEN'], REI_PG_CONNECTION_STRING=os.environ['CLI_DATABASE'],
           OTEL_SDK_DISABLED='true')
cli = subprocess.run([os.environ['REI_CLI'], 'category', 'list', '--all', '--json'],
                     env=env, stdin=subprocess.DEVNULL, capture_output=True, timeout=20)
assert cli.returncode == 0, 'supported category CLI failed'
cli_rows = json.loads(cli.stdout)
api_rows = []
after = None
# Complete bounded pages; a fixture accidentally larger than this is a refusal.
for _ in range(100):
    query = dict(first=100, status='all')
    if after is not None:
        query['after'] = after
    request = Request(api_url + '/api/v2/categories?' + urlencode(query), headers={'Authorization': 'Bearer ' + os.environ['PARITY_TOKEN']})
    with urlopen(request, timeout=10) as response:
        page = json.load(response)
    api_rows.extend(edge['node'] for edge in page['edges'])
    if not page['pageInfo']['hasNextPage']:
        break
    next_cursor = page['pageInfo']['endCursor']
    assert next_cursor and next_cursor != after, 'category paging did not advance'
    after = next_cursor
else:
    raise SystemExit('fixture exceeds bounded parity scope')


def normalize(rows):
    # Only generated identity/time/stream metadata is omitted. Compare persisted
    # domain meaning and discoverability, preserving None versus empty text.
    return sorted((row['slug'], row['name'], row['status'].lower(), row.get('description'), row.get('context')) for row in rows)


if normalize(cli_rows) != normalize(api_rows):
    raise SystemExit(f'persisted category parity differs: CLI {len(cli_rows)}, HTTP {len(api_rows)}')
assert cli_rows, 'empty fixture is not parity evidence'
print(f'persisted category parity matches: {len(cli_rows)} categories')
