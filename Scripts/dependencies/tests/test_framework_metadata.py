#!/usr/bin/env python3
"""Regression coverage for the metadata emitted by FFmpeg framework builds."""

from __future__ import annotations

import os
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile
import unittest


BUILDER = Path(__file__).resolve().parents[1] / "build-ffmpeg-6.1.6.sh"
ENTRY = 'parse_arguments "$@"'
LIBRARIES = (
    "libavutil",
    "libswresample",
    "libswscale",
    "libavcodec",
    "libavformat",
    "libavfilter",
    "libavdevice",
)
FAMILIES = {
    "ios-device": ("iPhoneOS", "MinimumOSVersion"),
    "ios-simulator": ("iPhoneSimulator", "MinimumOSVersion"),
    "maccatalyst": ("MacOSX", "LSMinimumSystemVersion"),
}
IDENTIFIER_PATTERN = re.compile(r"[A-Za-z0-9][A-Za-z0-9.-]*\Z", re.ASCII)
VERSION_PATTERN = re.compile(r"[0-9]+\.[0-9]+\.[0-9]+\Z", re.ASCII)


class FrameworkMetadataTests(unittest.TestCase):
    """Call the recipe's generator directly without invoking a framework build."""

    @classmethod
    def setUpClass(cls) -> None:
        source = BUILDER.read_text(encoding="utf-8")
        if source.count(ENTRY) != 1:
            raise AssertionError("builder main entry marker must occur exactly once")
        if source.count("write_framework_info_plist() {") != 1:
            raise AssertionError("framework metadata generator must occur exactly once")

        cls.tempdir = tempfile.TemporaryDirectory(prefix="irplayer-framework-metadata-")
        root = Path(cls.tempdir.name)
        cls.loader = root / "builder-declarations.sh"
        # Stop before parse_arguments' executable entry point. This keeps the
        # function under test in the recipe itself, while avoiding all builds.
        cls.loader.write_text(source.split(ENTRY, 1)[0], encoding="utf-8")
        cls.generated_root = root / "generated"

        shell = r'''
set -euo pipefail
source "$IRPLAYER_METADATA_LOADER"
for family in ios-device ios-simulator maccatalyst; do
    family_root="$IRPLAYER_METADATA_ROOT/$family"
    mkdir -p "$family_root"
    for library in "${libraries[@]}"; do
        write_framework_info_plist "$family_root/$library.plist" "$library" "$family"
    done
done
'''
        environment = dict(
            os.environ,
            IRPLAYER_METADATA_LOADER=str(cls.loader),
            IRPLAYER_METADATA_ROOT=str(cls.generated_root),
        )
        result = subprocess.run(
            ["bash", "-c", shell, str(BUILDER)],
            check=False,
            capture_output=True,
            text=True,
            timeout=10,
            env=environment,
        )
        if result.returncode != 0:
            raise AssertionError(
                f"metadata generator failed: stdout={result.stdout}\nstderr={result.stderr}"
            )

        cls.generated = {}
        for family in FAMILIES:
            cls.generated[family] = {}
            for library in LIBRARIES:
                plist = cls.generated_root / family / f"{library}.plist"
                with plist.open("rb") as stream:
                    cls.generated[family][library] = plistlib.load(stream)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.tempdir.cleanup()

    def test_generated_bundle_identifiers_are_ascii_and_distinct(self) -> None:
        for family, metadata in self.generated.items():
            identifiers = [metadata[library]["CFBundleIdentifier"] for library in LIBRARIES]
            with self.subTest(family=family):
                self.assertEqual(len(identifiers), 7)
                self.assertEqual(len(set(identifiers)), 7)
            for library, bundle_identifier in zip(LIBRARIES, identifiers):
                with self.subTest(family=family, library=library):
                    self.assertIsInstance(bundle_identifier, str)
                    self.assertTrue(bundle_identifier.isascii())
                    self.assertIsNotNone(IDENTIFIER_PATTERN.fullmatch(bundle_identifier))
                    self.assertEqual(
                        bundle_identifier,
                        f"org.irplayer.ffmpeg.n6-1-6.{library}",
                    )

    def test_original_underscore_identifier_is_rejected(self) -> None:
        original_fixture = "org.irplayer.ffmpeg.n6_1_6.libavformat"
        self.assertIsNone(IDENTIFIER_PATTERN.fullmatch(original_fixture))

    def test_generated_versions_are_sensible(self) -> None:
        for family, metadata in self.generated.items():
            for library in LIBRARIES:
                with self.subTest(family=family, library=library):
                    info = metadata[library]
                    self.assertEqual(info["CFBundleShortVersionString"], "6.1.6")
                    self.assertEqual(info["CFBundleVersion"], "6.1.6")
                    self.assertIsNotNone(
                        VERSION_PATTERN.fullmatch(info["CFBundleShortVersionString"])
                    )
                    self.assertIsNotNone(VERSION_PATTERN.fullmatch(info["CFBundleVersion"]))

    def test_generated_platform_metadata_matches_each_family(self) -> None:
        for family, (platform, minimum_key) in FAMILIES.items():
            other_minimum_key = (
                "LSMinimumSystemVersion"
                if minimum_key == "MinimumOSVersion"
                else "MinimumOSVersion"
            )
            for library in LIBRARIES:
                with self.subTest(family=family, library=library):
                    info = self.generated[family][library]
                    self.assertEqual(info["CFBundleSupportedPlatforms"], [platform])
                    self.assertEqual(info[minimum_key], "15.0")
                    self.assertNotIn(other_minimum_key, info)


if __name__ == "__main__":
    unittest.main(verbosity=2)
