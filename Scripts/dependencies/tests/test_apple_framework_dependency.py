#!/usr/bin/env python3

import os
from pathlib import Path
import subprocess
import tempfile
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
VERIFIER = REPOSITORY_ROOT / "Scripts/dependencies/verify-apple-framework-dependency.sh"


class AppleFrameworkDependencyTests(unittest.TestCase):
    def run_verifier(self, mode: str, framework: str = "Security") -> subprocess.CompletedProcess[str]:
        with tempfile.TemporaryDirectory() as temporary_directory:
            fixture = Path(temporary_directory)
            binary = fixture / "libavformat"
            binary.touch()
            lipo = fixture / "lipo"
            lipo.write_text("#!/bin/sh\nprintf '%s\\n' 'arm64 x86_64'\n")
            otool = fixture / "otool"
            otool.write_text(
                """#!/bin/sh
arch="$2"
case "$FAKE_OTOOL_MODE/$arch" in
  unversioned/*) path='/System/Library/Frameworks/Security.framework/Security' ;;
  versioned/*) path='/System/Library/Frameworks/Security.framework/Versions/A/Security' ;;
  missing-one/arm64) path='/System/Library/Frameworks/Security.framework/Versions/A/Security' ;;
  missing-one/x86_64) path='/System/Library/Frameworks/CoreFoundation.framework/Versions/A/CoreFoundation' ;;
  lookalike/*) path='/tmp/System/Library/Frameworks/Security.framework/Security' ;;
esac
printf '%s:\\n\\t%s (compatibility version 1.0.0, current version 1.0.0)\\n' "$arch" "$path"
"""
            )
            lipo.chmod(0o755)
            otool.chmod(0o755)
            environment = os.environ.copy()
            environment["PATH"] = f"{fixture}:{environment['PATH']}"
            environment["FAKE_OTOOL_MODE"] = mode
            return subprocess.run(
                [str(VERIFIER), str(binary), framework, framework],
                capture_output=True,
                text=True,
                env=environment,
                check=False,
            )

    def test_unversioned_framework_is_accepted_for_every_architecture(self) -> None:
        self.assertEqual(self.run_verifier("unversioned").returncode, 0)

    def test_versioned_framework_is_accepted_for_every_architecture(self) -> None:
        self.assertEqual(self.run_verifier("versioned").returncode, 0)

    def test_framework_must_be_present_in_every_architecture(self) -> None:
        result = self.run_verifier("missing-one")
        self.assertEqual(result.returncode, 1)
        self.assertIn("x86_64", result.stderr)

    def test_lookalike_non_system_path_is_rejected(self) -> None:
        self.assertEqual(self.run_verifier("lookalike").returncode, 1)

    def test_unsupported_framework_is_rejected(self) -> None:
        self.assertEqual(self.run_verifier("versioned", "UIKit").returncode, 2)


if __name__ == "__main__":
    unittest.main(verbosity=2)
