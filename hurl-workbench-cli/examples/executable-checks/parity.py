#!/usr/bin/env python3
"""Application-owned comparison of independent supported CLI/HTTP observations."""
import json
import os
from pathlib import Path
import subprocess
import sys
from urllib.request import Request, urlopen

cli_fixture, api_url, cli_id, api_id = sys.argv[1:]
if not cli_id or not api_id or cli_id == api_id:
    raise SystemExit("independent logical fixture identities are required")
assert not any(name in os.environ for name in ("REI_PG_CONNECTION_STRING", "MORI_API_URL", "PGHOST"))
cli = json.loads(subprocess.check_output([sys.executable, str(Path(__file__).with_name("app.py")), "observe", cli_fixture]))
request = Request(api_url + "/facts", headers={"Authorization": "Bearer " + os.environ["PARITY_TOKEN"]})
with urlopen(request, timeout=5) as response:
    api = json.load(response)
normalize = lambda values: sorted((item["key"], item["value"]) for item in values)
if normalize(cli) != normalize(api):
    raise SystemExit("CLI/API persisted facts differ")
print("CLI/API persisted facts match")
