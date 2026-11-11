"""Assert that public clean-suite metadata never contains ambient sentinels."""
import pathlib
import sys

summary = pathlib.Path(sys.argv[1]).read_text()
assert all(value not in summary for value in (
    "private-rei-sentinel", "private-config-sentinel", "private-mori-sentinel"
))
