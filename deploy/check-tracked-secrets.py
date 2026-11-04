#!/usr/bin/env python3
"""Reject common credential files and high-confidence secret values in tracked files.

This is a small guard, not an exhaustive secret detector or a history rewrite.
Only filenames and line numbers are printed, never matched values.
"""
import pathlib
import re
import subprocess
import sys

root = pathlib.Path(__file__).resolve().parent.parent
paths = subprocess.check_output(["git", "ls-files", "-z"], cwd=root).decode().split("\0")
patterns = {
    "private key": re.compile(rb"-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----"),
    "GitHub token": re.compile(rb"gh[pousr]_[A-Za-z0-9]{30,}"),
    "AWS access key": re.compile(rb"(?:AKIA|ASIA)[A-Z0-9]{16}"),
    "Slack token": re.compile(rb"xox[baprs]-[A-Za-z0-9-]{20,}"),
}
failures = []
for name in filter(None, paths):
    path = root / name
    if path.name.startswith(".env") and path.name != ".env.example":
        failures.append((name, 1, "runtime environment file"))
    if not path.is_file():
        continue
    data = path.read_bytes()
    for kind, pattern in patterns.items():
        for match in pattern.finditer(data):
            failures.append((name, data[:match.start()].count(b"\n") + 1, kind))

for name, line, kind in failures:
    print(f"{name}:{line}: possible {kind}", file=sys.stderr)
if failures:
    sys.exit(1)
print("Tracked-file credential guard passed (limited pattern coverage).")
