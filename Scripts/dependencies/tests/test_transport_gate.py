#!/usr/bin/env python3
"""Exercise the real acceptance transport function with lightweight runners."""

from pathlib import Path
import os
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[2] / "ci" / "run-acceptance.sh"


class TransportGateTests(unittest.TestCase):
    def run_gate(self, failing_suite=""):
        source = SCRIPT.read_text()
        start = "run_transport_acceptance() {\n"
        end = "\nrun_framework_acceptance() {"
        self.assertEqual(source.count(start), 1)
        self.assertEqual(source.count(end), 1)
        function = start + source.split(start, 1)[1].split(end, 1)[0]
        with tempfile.TemporaryDirectory(prefix="irplayer gate test ") as temporary:
            root = Path(temporary)
            result = root / "results"
            result.mkdir()
            trace = root / "trace"
            env = dict(os.environ, repository_root=str(root),
                       result_directory=str(result), simulator_id="fixture-simulator",
                       TRACE=str(trace), FAIL_SUITE=failing_suite,
                       IRPLAYER_FFMPEG_SIM_STAGE="/must-not-use-external-stage")
            shell = r'''
set -euo pipefail
prepare_simulator() { :; }
python3() {
    printf '%s\t' "$@" >> "$TRACE"
    printf '\n' >> "$TRACE"
    printf 'fixture runner stdout\n'
    printf 'fixture runner stderr\n' >&2
    if [[ -n "$FAIL_SUITE" && "$1" == *"run_${FAIL_SUITE}_regression.py" ]]; then
        return 23
    fi
}
'''
            process = subprocess.run(
                ["bash", "-c", shell + function + '\nrun_transport_acceptance\necho GATE_PASSED\n'],
                env=env, capture_output=True, text=True, timeout=10,
            )
            calls = [line.rstrip("\t").split("\t") for line in trace.read_text().splitlines()]
            logs = {path.name: path.read_text() for path in result.glob("*.log")}
        return process, calls, logs, root

    def test_all_suites_use_shipped_binaries_and_selected_simulator(self):
        process, calls, logs, root = self.run_gate()
        self.assertEqual(process.returncode, 0, process.stderr)
        self.assertIn("GATE_PASSED", process.stdout)
        names = ("tls13", "http", "hls", "reconnect", "deadline", "cookie")
        self.assertEqual(len(calls), len(names))
        for name, call in zip(names, calls):
            self.assertEqual(Path(call[0]).name, f"run_{name}_regression.py")
            self.assertEqual(call[call.index("--stage") + 1],
                             str(root / "Sources/IRPlayer-swift/ThirdParty/IRFFMpeg/Libs"))
            self.assertEqual(call[call.index("--device") + 1], "fixture-simulator")
            self.assertNotIn("/must-not-use-external-stage", call)
            self.assertIn("fixture runner stdout", logs[f"transport-{name}.log"])
            self.assertIn("fixture runner stderr", logs[f"transport-{name}.log"])
        self.assertEqual(calls[0][calls[0].index("--verification") + 1], "default")

    def test_early_failure_stops_later_suites(self):
        process, calls, logs, _ = self.run_gate("tls13")
        self.assertEqual(process.returncode, 23)
        self.assertEqual(len(calls), 1)
        self.assertNotIn("GATE_PASSED", process.stdout)
        self.assertIn("fixture runner stderr", logs["transport-tls13.log"])

    def test_last_cookie_failure_cannot_be_masked_by_tee(self):
        process, calls, logs, _ = self.run_gate("cookie")
        self.assertEqual(process.returncode, 23)
        self.assertEqual(len(calls), 6)
        self.assertNotIn("GATE_PASSED", process.stdout)
        self.assertIn("fixture runner stderr", logs["transport-cookie.log"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
