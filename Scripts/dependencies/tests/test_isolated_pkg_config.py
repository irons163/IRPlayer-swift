#!/usr/bin/env python3
"""Exercise the isolated pkg-config facade's fail-closed boundary."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest


FACADE = Path(__file__).resolve().parents[1] / "isolated-pkg-config.sh"


class IsolatedPkgConfigTests(unittest.TestCase):
    def setUp(self):
        self.workspace = tempfile.TemporaryDirectory(prefix="irplayer-pkg-config-test-")
        self.addCleanup(self.workspace.cleanup)
        self.env = {key: value for key, value in os.environ.items()
                    if not key.startswith("IRPLAYER_PKG_CONFIG_")}
        self.prefixes = {}
        for name in ("GMP", "NETTLE", "GNUTLS"):
            prefix = Path(self.workspace.name) / name.lower()
            (prefix / "include").mkdir(parents=True)
            (prefix / "lib").mkdir()
            self.prefixes[name] = prefix
            self.env[f"IRPLAYER_PKG_CONFIG_{name}_PREFIX"] = str(prefix)

    def query(self, *arguments):
        return subprocess.run(["bash", str(FACADE), *arguments], env=self.env,
                              capture_output=True, text=True, timeout=10)

    def assert_rejected(self, result):
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertEqual(result.stdout, "", "rejected query emitted usable flags")

    def test_valid_static_link_inputs(self):
        result = self.query("--static", "--libs", "gnutls")
        self.assertEqual(result.returncode, 0, result.stderr)
        for prefix in self.prefixes.values():
            self.assertIn(f"-L{prefix}/lib", result.stdout)
        self.assertNotIn("-L/lib", result.stdout)

    def test_unsatisfied_version_is_rejected(self):
        self.assert_rejected(self.query("--exists", "gnutls >= 999"))

    def test_multiple_packages_do_not_silently_drop_first(self):
        self.assert_rejected(self.query("--libs", "gmp", "gnutls"))

    def test_missing_transitive_prefix_is_rejected(self):
        del self.env["IRPLAYER_PKG_CONFIG_GMP_PREFIX"]
        self.assert_rejected(self.query("--libs", "gnutls"))

    def test_combined_flags_fail_without_partial_output(self):
        del self.env["IRPLAYER_PKG_CONFIG_GMP_PREFIX"]
        self.assert_rejected(self.query("--cflags", "--libs", "gnutls"))

    def test_version_comparison_boundaries(self):
        for expression, expected in (("gnutls = 3.8.13", 0),
                                     ("gnutls >= 3.8.12", 0),
                                     ("gnutls <= 3.8.14", 0),
                                     ("gnutls > 3.8.13", 1),
                                     ("gnutls < 3.8.13", 1)):
            with self.subTest(expression=expression):
                result = self.query("--exists", expression)
                if expected:
                    self.assert_rejected(result)
                else:
                    self.assertEqual(result.returncode, 0, result.stderr)

    def test_unknown_package_is_rejected(self):
        self.assert_rejected(self.query("--exists", "unknown-host-library"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
