#!/usr/bin/env python3
"""Run positive and negative TLS 1.3 probes in an iOS Simulator."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path


def checked(command: list[str]) -> None:
    subprocess.run(command, check=True, capture_output=True, text=True)


def make_certificates(root: Path) -> tuple[Path, Path, Path]:
    ca_key = root / "ca.key"
    ca_cert = root / "ca.pem"
    server_key = root / "server.key"
    request = root / "server.csr"
    server_cert = root / "server.pem"
    extensions = root / "server.ext"
    extensions.write_text(
        "basicConstraints=critical,CA:FALSE\n"
        "keyUsage=critical,digitalSignature,keyEncipherment\n"
        "extendedKeyUsage=serverAuth\n"
        "subjectAltName=DNS:localhost\n",
        encoding="ascii",
    )
    checked([
        "openssl", "req", "-x509", "-new", "-nodes", "-newkey", "rsa:2048",
        "-keyout", str(ca_key), "-out", str(ca_cert), "-days", "1",
        "-subj", "/CN=IRPlayer Simulator Probe CA",
        "-addext", "basicConstraints=critical,CA:TRUE",
    ])
    checked([
        "openssl", "req", "-new", "-nodes", "-newkey", "rsa:2048",
        "-keyout", str(server_key), "-out", str(request),
        "-subj", "/CN=localhost",
    ])
    checked([
        "openssl", "x509", "-req", "-in", str(request),
        "-CA", str(ca_cert), "-CAkey", str(ca_key), "-CAcreateserial",
        "-out", str(server_cert), "-days", "1", "-extfile", str(extensions),
    ])
    return ca_cert, server_cert, server_key


def main() -> int:
    parser = argparse.ArgumentParser()
    environment_stage = os.environ.get("IRPLAYER_FFMPEG_SIM_STAGE")
    parser.add_argument(
        "--stage", type=Path,
        default=Path(environment_stage) if environment_stage else None,
        help="candidate stage root (or set IRPLAYER_FFMPEG_SIM_STAGE)",
    )
    parser.add_argument("--device", default="booted")
    parser.add_argument("--deadline-ms", type=int, default=5000)
    parser.add_argument("--verification", choices=("forced", "default"),
                        default="forced")
    args = parser.parse_args()
    if args.stage is None:
        parser.error("--stage or IRPLAYER_FFMPEG_SIM_STAGE is required")

    directory = Path(__file__).resolve().parent
    runner = directory / "run_probe.py"
    server_script = directory / "loopback_tls13.py"
    with tempfile.TemporaryDirectory(prefix="irplayer-ios-tls13-") as temporary:
        root = Path(temporary)
        ca_cert, server_cert, server_key = make_certificates(root)
        records = root / "requests.jsonl"
        server = subprocess.Popen(
            [
                sys.executable, str(server_script),
                "--cert", str(server_cert),
                "--key", str(server_key),
                "--record-file", str(records),
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        try:
            assert server.stdout is not None
            url = server.stdout.readline().strip()
            if not url.startswith("https://localhost:"):
                stderr = server.stderr.read() if server.stderr else ""
                raise RuntimeError(f"TLS fixture failed to start: {url} {stderr}")

            common = [
                sys.executable, str(runner), url,
                "--device", args.device,
                "--deadline-ms", str(args.deadline_ms),
                "--verification", args.verification,
            ]
            common += ["--stage", str(args.stage)]

            trusted = subprocess.run(
                [*common, "--ca-file", str(ca_cert), "--expect", "success"],
                text=True,
            )
            if trusted.returncode:
                return trusted.returncode

            untrusted = subprocess.run(
                [*common, "--expect", "failure"],
                text=True,
            )
            if untrusted.returncode:
                return untrusted.returncode

            mismatch_url = url.replace("https://localhost:", "https://127.0.0.1:")
            mismatch = subprocess.run(
                [
                    *common[:2], mismatch_url, *common[3:],
                    "--ca-file", str(ca_cert), "--expect", "failure",
                ],
                text=True,
            )
            if mismatch.returncode:
                return mismatch.returncode

            entries = [json.loads(line) for line in records.read_text().splitlines()]
            if entries != [{"path": "/probe", "tls_version": "TLSv1.3"}]:
                raise RuntimeError(
                    "expected exactly one post-validation TLS 1.3 HTTP request; "
                    "untrusted and hostname-mismatched handshakes must emit none, "
                    f"got {entries!r}"
                )
            print("iOS Simulator TLS 1.3 trust regression passed")
            return 0
        finally:
            server.terminate()
            try:
                server.wait(timeout=3)
            except subprocess.TimeoutExpired:
                server.kill()
                server.wait(timeout=3)


if __name__ == "__main__":
    raise SystemExit(main())
