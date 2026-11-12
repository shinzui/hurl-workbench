#!/usr/bin/env python3
"""Preserve declared workspace helper modes after Cabal's all-0644 sdist step."""
import gzip
import os
from pathlib import Path
import sys
import tarfile
import tempfile

archive = Path(sys.argv[1])
helpers = {'examples/executable-checks/parity.py', 'examples/executable-checks/rei/parity.py'}
found = set()
# No extraction or broad permission repair: only the declared helper entries
# change. Tar metadata and member order otherwise remain Cabal's original values.
fd, temporary = tempfile.mkstemp(prefix='.sdist-modes-', dir=archive.parent)
try:
    with os.fdopen(fd, 'wb') as raw, gzip.GzipFile(fileobj=raw, mode='wb', filename='', mtime=0) as zipped:
        with tarfile.open(archive, 'r:gz') as source, tarfile.open(fileobj=zipped, mode='w') as target:
            for entry in source:
                relative = entry.name.partition('/')[2]
                if relative in helpers:
                    assert entry.isfile(), 'declared helper must be a regular source file'
                    entry.mode = 0o755
                    found.add(relative)
                target.addfile(entry, source.extractfile(entry) if entry.isfile() else None)
    assert found == helpers, 'source archive is missing a declared check helper'
    os.replace(temporary, archive)
finally:
    if os.path.exists(temporary):
        os.unlink(temporary)
