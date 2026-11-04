"""Filesystem regressions for the runtime-to-offsite trust boundary; no network."""
import gzip
import hashlib
import importlib.util
import os
from pathlib import Path
import tempfile
import time
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('stage_offsite', Path(__file__).with_name('stage-offsite.py'))
staging = importlib.util.module_from_spec(spec)
spec.loader.exec_module(staging)


class StageOffsiteTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='em-stage-check-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.source = self.root / 'shared'
        self.private = self.root / 'private'
        self.source.mkdir()
        self.private.mkdir(mode=0o700)
        self.output = self.private / 'upload.snapshot.gz'
        self.archive = self.source / 'world-2026-11-04T150000.123Z.snapshot.gz'
        self.sidecar = Path(str(self.archive) + '.sha256')

    def write_archive(self, raw=b'world snapshot'):
        data = gzip.compress(raw)
        self.archive.write_bytes(data)
        digest = hashlib.sha256(data).hexdigest()
        self.sidecar.write_text(f'{digest}  {self.archive}\n')
        return data, digest

    def test_verified_copy_is_private_and_survives_shared_source_replacement(self):
        data, digest = self.write_archive()
        self.assertEqual(staging.stage(self.source, self.output), (self.archive.name, digest, len(data)))
        self.assertEqual(self.output.stat().st_mode & 0o777, 0o600)
        self.archive.write_bytes(b'changed after verification')
        self.assertEqual(self.output.read_bytes(), data)

    def test_checksum_records_cannot_target_other_files_or_hide_a_mismatch(self):
        _, digest = self.write_archive()
        for value in [f'{digest}  /etc/passwd\n', f'{"0" * 64}  {self.archive}\n', 'x' * 513]:
            with self.subTest(record=value[:70]):
                self.sidecar.write_text(value)
                with self.assertRaises(ValueError):
                    staging.stage(self.source, self.output)
                self.assertFalse(self.output.exists())

    def test_archive_swapped_to_a_symlink_between_selection_and_open_is_rejected(self):
        self.write_archive()
        protected = self.private / 'credential.gz'
        protected.write_bytes(gzip.compress(b'private data must never be copied'))
        real_open = os.open

        def swap_before_open(path, flags, *args, **kwargs):
            if Path(path) == self.archive:
                self.archive.unlink()
                self.archive.symlink_to(protected)
            return real_open(path, flags, *args, **kwargs)

        with patch.object(staging.os, 'open', side_effect=swap_before_open):
            with self.assertRaises(OSError):
                staging.stage(self.source, self.output)
        self.assertFalse(self.output.exists())

    def test_symlinked_checksum_is_not_followed(self):
        self.write_archive()
        protected = self.private / 'checksum'
        protected.write_bytes(self.sidecar.read_bytes())
        self.sidecar.unlink()
        self.sidecar.symlink_to(protected)
        with self.assertRaises(OSError):
            staging.stage(self.source, self.output)
        self.assertFalse(self.output.exists())

    def test_gzip_expansion_and_corrupt_archives_are_rejected_before_upload(self):
        self.write_archive(b'x' * 4_000_001)
        with self.assertRaises(ValueError):
            staging.stage(self.source, self.output)
        self.write_archive()
        self.archive.write_bytes(b'not gzip')
        digest = hashlib.sha256(self.archive.read_bytes()).hexdigest()
        self.sidecar.write_text(f'{digest}  {self.archive}\n')
        with self.assertRaises(OSError):
            staging.stage(self.source, self.output)
        self.assertFalse(self.output.exists())

    def test_stale_future_and_oversized_inputs_cannot_be_staged(self):
        self.write_archive()
        for modified in [time.time() - 31 * 3600, time.time() + 3600]:
            os.utime(self.archive, (modified, modified))
            with self.assertRaises(ValueError):
                staging.stage(self.source, self.output)
        self.archive.write_bytes(b'x' * 8_000_001)
        with self.assertRaises(ValueError):
            staging.stage(self.source, self.output)
        self.assertFalse(self.output.exists())


if __name__ == '__main__':
    unittest.main()
