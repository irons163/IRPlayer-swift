#!/usr/bin/env python3
"""Validate packaged probe slice selection without requiring Xcode."""

import importlib.util
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch


SOURCE = Path(__file__).parent / "ios_tls_probe" / "run_probe.py"
SPEC = importlib.util.spec_from_file_location("run_probe", SOURCE)
PROBE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PROBE)


class ProbeLayoutTests(unittest.TestCase):
    def setUp(self):
        self.workspace = tempfile.TemporaryDirectory(prefix="irplayer-probe-layout-")
        self.addCleanup(self.workspace.cleanup)
        self.root = Path(self.workspace.name)

    def bundle(self, name="libavformat", entries=None):
        bundle = self.root / f"{name}.xcframework"
        framework = bundle / "ios-arm64_x86_64-simulator" / f"{name}.framework"
        (framework / "Headers").mkdir(parents=True)
        (framework / name).write_bytes(b"fixture binary")
        entry = {
            "LibraryIdentifier": "ios-arm64_x86_64-simulator",
            "LibraryPath": f"{name}.framework",
            "SupportedPlatform": "ios",
            "SupportedPlatformVariant": "simulator",
            "SupportedArchitectures": ["arm64", "x86_64"],
        }
        self.write_entries(bundle, [entry] if entries is None else entries)
        return bundle, framework, entry

    def write_entries(self, bundle, entries):
        with (bundle / "Info.plist").open("wb") as stream:
            plistlib.dump({"AvailableLibraries": entries}, stream)

    def test_selects_simulator_not_device_or_catalyst(self):
        bundle, framework, entry = self.bundle()
        device = dict(entry, SupportedPlatformVariant="")
        catalyst = dict(entry, SupportedPlatformVariant="maccatalyst")
        self.write_entries(bundle, [device, entry, catalyst])
        self.assertEqual(PROBE.simulator_framework(bundle, "libavformat"), framework.resolve())

    def test_rejects_absent_ambiguous_or_intel_only_slice(self):
        bundle, _, entry = self.bundle()
        for entries in ([], [entry, entry],
                        [dict(entry, SupportedArchitectures=["x86_64"])]):
            with self.subTest(entries=entries):
                self.write_entries(bundle, entries)
                with self.assertRaisesRegex(RuntimeError, "expected one arm64"):
                    PROBE.simulator_framework(bundle, "libavformat")

    def test_rejects_path_escape_and_wrong_framework_name(self):
        bundle, _, entry = self.bundle()
        for path in ("../../libavformat.framework", "/libavformat.framework",
                     "libavcodec.framework"):
            with self.subTest(path=path):
                self.write_entries(bundle, [dict(entry, LibraryPath=path)])
                with self.assertRaisesRegex(RuntimeError, "invalid framework path"):
                    PROBE.simulator_framework(bundle, "libavformat")

    def test_rejects_missing_headers_or_binary(self):
        bundle, framework, _ = self.bundle()
        (framework / "Headers").rmdir()
        with self.assertRaisesRegex(RuntimeError, "headers or binary"):
            PROBE.simulator_framework(bundle, "libavformat")
        (framework / "Headers").mkdir()
        (framework / "libavformat").unlink()
        with self.assertRaisesRegex(RuntimeError, "headers or binary"):
            PROBE.simulator_framework(bundle, "libavformat")

    def test_framework_mode_copies_all_sdk_dependencies_without_mutation(self):
        names = ("libavformat", "libavcodec", "libavutil", "libswresample", "libswscale")
        originals = [self.bundle(name)[1] / name for name in names]
        work = self.root / "work"
        work.mkdir()
        with patch.object(PROBE, "assert_simulator_library",
                          side_effect=lambda path: {"path": str(path),
                                                    "sha256": PROBE.sha256(path)}) as verify:
            flags, manifest = PROBE.prepare_candidate(self.root, work)
        self.assertEqual(verify.call_count, 5)
        self.assertEqual(len(manifest), 5)
        self.assertIn("-F", flags)
        self.assertIn("-Wl,-rpath,@executable_path/Frameworks", flags)
        self.assertNotIn("-L", flags)
        for name, original in zip(names, originals):
            self.assertEqual(original.read_bytes(), b"fixture binary")
            copied = work / "Frameworks" / f"{name}.framework" / name
            self.assertEqual(copied.read_bytes(), original.read_bytes())
            self.assertNotEqual(copied.resolve(), original.resolve())


if __name__ == "__main__":
    unittest.main(verbosity=2)
