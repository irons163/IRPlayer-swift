#!/usr/bin/env python3
"""Verify that a stalled TLS handshake propagates AVERROR_EXIT."""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    environment_stage = os.environ.get("IRPLAYER_FFMPEG_SIM_STAGE")
    parser.add_argument(
        "--stage", type=Path,
        default=Path(environment_stage) if environment_stage else None,
        help="candidate stage root (or set IRPLAYER_FFMPEG_SIM_STAGE)",
    )
    parser.add_argument("--device", default="booted")
    parser.add_argument("--deadline-ms", type=int, default=500)
    args = parser.parse_args()
    if args.stage is None:
        parser.error("--stage or IRPLAYER_FFMPEG_SIM_STAGE is required")

    directory = Path(__file__).resolve().parent
    fixture = subprocess.Popen(
        [sys.executable, str(directory / "stall_tcp.py")],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    try:
        assert fixture.stdout is not None
        url = fixture.stdout.readline().strip()
        if not url.startswith("https://127.0.0.1:"):
            stderr = fixture.stderr.read() if fixture.stderr else ""
            raise RuntimeError(f"stall fixture failed to start: {url} {stderr}")
        command = [
            sys.executable, str(directory / "run_probe.py"), url,
            "--device", args.device,
            "--deadline-ms", str(args.deadline_ms),
            "--expect", "timeout",
        ]
        command += ["--stage", str(args.stage)]
        result = subprocess.run(command, text=True)
        if result.returncode == 0:
            print("iOS Simulator TLS deadline regression passed")
        return result.returncode
    finally:
        fixture.terminate()
        try:
            fixture.wait(timeout=3)
        except subprocess.TimeoutExpired:
            fixture.kill()
            fixture.wait(timeout=3)


if __name__ == "__main__":
    raise SystemExit(main())
