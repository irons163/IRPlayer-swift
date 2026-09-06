#!/usr/bin/env python3
"""Test the real package manifest functions without dispatching the builder."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


BUILDER = Path(__file__).resolve().parents[1] / "build-ffmpeg-6.1.6.sh"
ENTRY = 'parse_arguments "$@"'


class PackageIntegrityTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="package integrity ")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.package = self.root / "candidate package"
        (self.package / "metadata/licenses").mkdir(parents=True)
        (self.package / "metadata/licenses/Example License").write_text("license bytes\n")
        (self.package / "binary").write_bytes(b"actual binary fixture")
        (self.package / "alias").symlink_to("binary")
        source = BUILDER.read_text()
        self.assertEqual(source.count(ENTRY), 1)
        self.loader = self.root / "declarations.sh"
        self.loader.write_text(source.split(ENTRY)[0])

    def run_functions(self, script, expected=0):
        environment = dict(os.environ, PACKAGE=str(self.package),
                           LOADER=str(self.loader), FIXTURE_ROOT=str(self.root))
        result = subprocess.run(
            ["bash", "-c", '''set -euo pipefail
source "$LOADER"
work_root="$FIXTURE_ROOT/work"
mkdir -p "$(metadata_dir)"
''' + script, str(BUILDER)], env=environment, capture_output=True, text=True)
        if expected == 0:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("unbound variable", result.stderr)
        return result

    def seal(self):
        self.run_functions('write_package_license_checksums "$PACKAGE"\n'
                           'write_package_artifact_checksums "$PACKAGE"\n'
                           'verify_package_artifact_checksums "$PACKAGE"')

    def test_valid_package_and_portable_license_checksums(self):
        self.seal()
        moved = self.root / "moved package"
        shutil.move(str(self.package), moved)
        self.package = moved
        self.run_functions('verify_package_artifact_checksums "$PACKAGE"\n'
                           'cd "$PACKAGE/metadata"\n'
                           'shasum -a 256 -c license-sha256sums.txt')
        self.assertNotIn(str(self.root), (moved / "metadata/license-sha256sums.txt").read_text())

    def test_retargeted_link_fails_even_when_target_bytes_are_equal(self):
        (self.package / "same bytes").write_bytes((self.package / "binary").read_bytes())
        self.seal()
        (self.package / "alias").unlink()
        (self.package / "alias").symlink_to("same bytes")
        result = self.run_functions('verify_package_artifact_checksums "$PACKAGE"', 1)
        self.assertIn("symlink inventory", result.stderr)

    def test_added_link_fails(self):
        self.seal()
        (self.package / "extra").symlink_to("binary")
        self.run_functions('verify_package_artifact_checksums "$PACKAGE"', 1)

    def test_deleted_link_fails(self):
        self.seal()
        (self.package / "alias").unlink()
        self.run_functions('verify_package_artifact_checksums "$PACKAGE"', 1)

    def test_regular_file_tampering_fails(self):
        self.seal()
        (self.package / "binary").write_bytes(b"changed")
        self.run_functions('verify_package_artifact_checksums "$PACKAGE"', 1)

    def test_added_regular_file_fails(self):
        self.seal()
        (self.package / "unlisted addition").write_bytes(b"unexpected")
        result = self.run_functions('verify_package_artifact_checksums "$PACKAGE"', 1)
        self.assertIn("regular-file inventory", result.stderr)

    def test_dangling_manifest_link_is_not_followed(self):
        target = self.root / "must not create"
        (self.package / "metadata/artifact-symlinks.txt").symlink_to(target)
        self.run_functions('write_package_artifact_checksums "$PACKAGE"', 1)
        self.assertFalse(target.exists())

    def test_symlink_manifest_is_bound_by_artifact_checksum(self):
        self.seal()
        (self.package / "metadata/artifact-symlinks.txt").write_text("")
        self.run_functions('verify_package_artifact_checksums "$PACKAGE"', 1)

    def test_existing_manifest_cannot_be_silently_replaced(self):
        self.seal()
        self.run_functions('write_package_artifact_checksums "$PACKAGE"', 1)

    def test_newline_in_link_path_and_target_is_unambiguous(self):
        (self.package / "line\nbreak").symlink_to("binary\n")
        self.seal()
        inventory = (self.package / "metadata/artifact-symlinks.txt").read_text()
        self.assertEqual(len(inventory.splitlines()), 2)
        (self.package / "line\nbreak").unlink()
        (self.package / "line\nbreak").symlink_to("binary")
        self.run_functions('verify_package_artifact_checksums "$PACKAGE"', 1)


if __name__ == "__main__":
    unittest.main(verbosity=2)
