#!/usr/bin/env python3
"""Ensure transport gate outcomes reject unexpected success and crashes."""

from contextlib import redirect_stderr, redirect_stdout
import importlib.util
import io
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch


SOURCE = Path(__file__).parent / "ios_tls_probe" / "run_probe.py"
SPEC = importlib.util.spec_from_file_location("run_probe_results", SOURCE)
PROBE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PROBE)


class ProbeResultTests(unittest.TestCase):
    def run_result(self, expected, actual):
        arguments = [str(SOURCE), "https://localhost/", "--stage", "/unused-stage"]
        if expected is not None:
            arguments += ["--expect", expected]
        result = subprocess.CompletedProcess([], actual, stdout="", stderr="")
        output, errors = io.StringIO(), io.StringIO()
        with patch.object(PROBE.sys, "argv", arguments), \
                patch.object(PROBE, "prepare_candidate", return_value=([], [])), \
                patch.object(PROBE, "compile_probe"), \
                patch.object(PROBE, "booted_device", return_value="fixture-device"), \
                patch.object(PROBE.subprocess, "run", return_value=result), \
                redirect_stdout(output), redirect_stderr(errors):
            status = PROBE.main()
        return status, errors.getvalue()

    def test_only_exact_expected_outcomes_pass(self):
        for expected, code in (("success", 0), ("failure", 10), ("timeout", 11)):
            with self.subTest(expected=expected):
                status, errors = self.run_result(expected, code)
                self.assertEqual(status, 0)
                self.assertEqual(errors, "")

    def test_unexpected_success_is_explicit_failure(self):
        status, errors = self.run_result("failure", 0)
        self.assertEqual(status, 1)
        self.assertIn("expected=failure simulator_process_returncode=0", errors)

    def test_crashes_and_other_errors_are_not_expected_security_failures(self):
        for code in (-9, -11, 1, 2, 11, 124, 127):
            with self.subTest(code=code):
                status, errors = self.run_result("failure", code)
                self.assertEqual(status, 1)
                self.assertIn("probe_expectation_failed", errors)

    def test_failure_cannot_substitute_for_cancellation(self):
        status, errors = self.run_result("timeout", 10)
        self.assertEqual(status, 1)
        self.assertIn("expected=timeout simulator_process_returncode=10", errors)

    def test_no_expectation_preserves_process_status(self):
        status, errors = self.run_result(None, 10)
        self.assertEqual(status, 10)
        self.assertEqual(errors, "")


if __name__ == "__main__":
    unittest.main(verbosity=2)
