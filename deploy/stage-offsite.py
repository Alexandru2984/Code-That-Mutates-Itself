#!/usr/bin/env python3
"""Freeze a bounded verified archive before crossing the runtime/offsite UID boundary."""
import argparse
import gzip
import hashlib
import io
import os
from pathlib import Path
import re
import stat
import tempfile
import time
import zlib

ARCHIVE = re.compile(r'world-\d{4}-\d{2}-\d{2}T\d{6}(?:\.\d+)?Z\.snapshot\.gz')


def read_regular(path, maximum, *, fresh=False):
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(descriptor, 'rb') as handle:
        metadata = os.fstat(handle.fileno())
        if not stat.S_ISREG(metadata.st_mode) or not 0 < metadata.st_size <= maximum:
            raise ValueError('Unexpected backup file type or size')
        if fresh and not -300 <= time.time() - metadata.st_mtime <= 30 * 3600:
            raise ValueError('Local backup timestamp is not fresh')
        content = handle.read(maximum + 1)
        if not 0 < len(content) <= maximum:
            raise ValueError('Backup file grew beyond its size limit')
        return content


def stage(source, destination):
    candidates = []
    with os.scandir(source) as entries:
        for entry in entries:
            if ARCHIVE.fullmatch(entry.name) and entry.is_file(follow_symlinks=False):
                candidates.append((entry.stat(follow_symlinks=False).st_mtime_ns, entry.name))
    if not candidates:
        raise ValueError('No local backup archive')
    name = max(candidates)[1]
    archive = Path(source) / name
    data = read_regular(archive, 8_000_000, fresh=True)
    checksum = read_regular(Path(str(archive) + '.sha256'), 512).decode('ascii')
    match = re.fullmatch(r'([0-9a-f]{64}) [ *]([^\r\n]+)\n?', checksum)
    if not match or match[2] not in (str(archive), name):
        raise ValueError('Unexpected backup checksum record')
    digest = hashlib.sha256(data).hexdigest()
    if digest != match[1]:
        raise ValueError('Local backup checksum does not match')
    with gzip.GzipFile(fileobj=io.BytesIO(data)) as compressed:
        raw = compressed.read(4_000_001)
    if not 0 < len(raw) <= 4_000_000:
        raise ValueError('Snapshot expansion exceeds the restore limit')
    destination = Path(destination)
    descriptor, temporary = tempfile.mkstemp(prefix='.verified-upload-', dir=destination.parent)
    try:
        with os.fdopen(descriptor, 'wb') as handle:
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, destination)
    finally:
        Path(temporary).unlink(missing_ok=True)
    return name, digest, len(data)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    try:
        print(*stage(Path(args.source), Path(args.output)))
    except (OSError, ValueError, UnicodeError, EOFError, zlib.error) as error:
        raise SystemExit(f'Offsite staging rejected: {type(error).__name__}') from None


if __name__ == '__main__':
    main()
