#!/usr/bin/env python3
"""Exercise HTTP redirect policy through candidate AVIO in an iOS Simulator."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import tempfile
from pathlib import Path

from probe_support import (
    add_stage_argument,
    expected_raw_headers,
    load_transport_fixture,
    require_stage,
)
from run_tls13_regression import make_certificates


def probe(
    runner: Path,
    url: str,
    ca_file: Path,
    *,
    stage: Path,
    device: str,
    deadline_ms: int,
    expected: str,
    headers: str | None = None,
    expected_stderr_marker: str | None = None,
) -> dict[str, object]:
    command = [
        sys.executable,
        str(runner),
        url,
        "--stage",
        str(stage),
        "--device",
        device,
        "--operation",
        "avio",
        "--verification",
        "default",
        "--ca-file",
        str(ca_file),
        "--deadline-ms",
        str(deadline_ms),
        "--read-bytes",
        "16",
        "--expect",
        expected,
    ]
    if headers is not None:
        command += ["--headers", headers]
    result = subprocess.run(command, text=True, capture_output=True)
    sys.stdout.write(result.stdout)
    sys.stderr.write(result.stderr)
    if result.returncode:
        raise RuntimeError(
            f"probe expectation {expected!r} failed with runner rc={result.returncode}"
        )
    if expected_stderr_marker is not None and expected_stderr_marker not in result.stderr:
        raise RuntimeError(
            "probe failed without the required policy-denial evidence: "
            f"marker={expected_stderr_marker!r}, stderr={result.stderr!r}"
        )
    records = [
        json.loads(line) for line in result.stdout.splitlines() if line.startswith("{")
    ]
    if len(records) != 1:
        raise RuntimeError(f"expected one probe JSON record, got {records!r}")
    record = records[0]
    if record.get("operation") != "avio":
        raise RuntimeError(f"probe did not execute AVIO mode: {record!r}")
    if record.get("verification_mode") != "default_no_tls_verify_option":
        raise RuntimeError(f"probe supplied an unexpected verification option: {record!r}")
    if expected == "success" and int(record.get("bytes_read", 0)) <= 0:
        raise RuntimeError(f"AVIO success did not read positive bytes: {record!r}")
    return record


def assert_headers(
    requests: list[object], expected: dict[str, str], *, present: bool, label: str
) -> None:
    if not requests:
        raise RuntimeError(f"expected at least one wire request for {label}")
    violations: list[str] = []
    for index, request in enumerate(requests):
        actual = getattr(request, "headers")
        for name, value in expected.items():
            if present and actual.get(name) != value:
                violations.append(
                    f"request {index} expected {name}={value!r}, got {actual.get(name)!r}"
                )
            if not present and name in actual:
                violations.append(
                    f"request {index} leaked {name}={actual[name]!r}"
                )
    if violations:
        raise RuntimeError(f"{label} header policy mismatch: {violations}")


def wire(path: str, requests: list[object]) -> dict[str, object]:
    return {
        "path": path,
        "count": len(requests),
        "headers": [getattr(request, "headers") for request in requests],
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    add_stage_argument(parser)
    parser.add_argument("--device", default="booted")
    parser.add_argument("--deadline-ms", type=int, default=5000)
    args = parser.parse_args()
    stage = require_stage(parser, args)
    if args.deadline_ms <= 0:
        parser.error("deadline must be positive")

    fixture = load_transport_fixture("irplayer_http_transport_fixture")
    LoopbackServer = fixture.LoopbackServer
    raw_headers: str = fixture.RAW_HEADERS
    expected_headers = expected_raw_headers(raw_headers)
    body: bytes = fixture.TS_FIXTURE
    runner = Path(__file__).with_name("run_probe.py")
    servers: list[object] = []
    evidence: dict[str, object] = {}

    with tempfile.TemporaryDirectory(prefix="irplayer-ios-http-") as temporary:
        ca_cert, server_cert, server_key = make_certificates(Path(temporary))
        tls = (server_cert, server_key)
        try:
            def same_router(path: str, _headers: dict[str, str]):
                if path == "/same-start":
                    return 302, {"Location": same.url("/same-final", host="localhost")}, b""
                if path == "/same-final":
                    return 200, {"Content-Type": "video/mp2t"}, body
                return 404, {}, b""

            same = LoopbackServer(same_router, tls=tls)
            servers.append(same)
            same.start()
            same_result = probe(
                runner, same.url("/same-start", host="localhost"), ca_cert,
                stage=stage, device=args.device, deadline_ms=args.deadline_ms,
                expected="success", headers=raw_headers,
            )
            same_start = same.recorder.for_path("/same-start")
            same_final = same.recorder.for_path("/same-final")
            assert_headers(same_start, expected_headers, present=True, label="same-origin root")
            assert_headers(same_final, expected_headers, present=True, label="same-origin redirect")
            evidence["same_origin_preserves_headers"] = {
                "bytes_read": same_result["bytes_read"],
                "wire": [wire("/same-start", same_start), wire("/same-final", same_final)],
            }

            foreign = LoopbackServer(
                lambda path, _headers: (
                    (200, {"Content-Type": "video/mp2t"}, body)
                    if path == "/foreign-final" else (404, {}, b"")
                ),
                tls=tls,
            )
            servers.append(foreign)
            foreign.start()

            def origin_router(path: str, _headers: dict[str, str]):
                if path == "/foreign-start":
                    return 302, {
                        "Location": foreign.url("/foreign-final", host="localhost")
                    }, b""
                return 404, {}, b""

            origin = LoopbackServer(origin_router, tls=tls)
            servers.append(origin)
            origin.start()
            foreign_result = probe(
                runner, origin.url("/foreign-start", host="localhost"), ca_cert,
                stage=stage, device=args.device, deadline_ms=args.deadline_ms,
                expected="success", headers=raw_headers,
            )
            origin_requests = origin.recorder.for_path("/foreign-start")
            foreign_requests = foreign.recorder.for_path("/foreign-final")
            assert_headers(origin_requests, expected_headers, present=True, label="foreign root")
            assert_headers(
                foreign_requests, expected_headers, present=False, label="foreign redirect"
            )
            evidence["foreign_origin_strips_headers"] = {
                "bytes_read": foreign_result["bytes_read"],
                "wire": [wire("/foreign-start", origin_requests),
                         wire("/foreign-final", foreign_requests)],
            }

            plain = LoopbackServer(
                lambda path, _headers: (
                    (200, {"Content-Type": "application/octet-stream"}, body)
                    if path == "/plain-final" else (404, {}, b"")
                )
            )
            servers.append(plain)
            plain.start()

            def downgrade_router(path: str, _headers: dict[str, str]):
                if path == "/downgrade-start":
                    return 302, {
                        "Location": plain.url("/plain-final", host="localhost")
                    }, b""
                return 404, {}, b""

            downgrade = LoopbackServer(downgrade_router, tls=tls)
            servers.append(downgrade)
            downgrade.start()
            policy_denial = "Refusing HTTP request because the root URL requires HTTPS"
            downgrade_result = probe(
                runner, downgrade.url("/downgrade-start", host="localhost"), ca_cert,
                stage=stage, device=args.device, deadline_ms=args.deadline_ms,
                expected="failure", headers=raw_headers,
                expected_stderr_marker=policy_denial,
            )
            root_requests = downgrade.recorder.for_path("/downgrade-start")
            plain_requests = plain.recorder.for_path("/plain-final")
            if len(root_requests) != 1:
                raise RuntimeError(
                    "downgrade probe did not reach exactly one verified HTTPS root: "
                    f"{root_requests!r}"
                )
            assert_headers(root_requests, expected_headers, present=True, label="downgrade root")
            if plain_requests:
                raise RuntimeError(f"HTTPS redirect emitted plaintext traffic: {plain_requests!r}")
            evidence["plaintext_redirect_denied"] = {
                "open_returncode": downgrade_result["open_returncode"],
                "policy_denial_marker": policy_denial,
                "https_root_hits": len(root_requests),
                "plain_hits": 0,
            }

            print("http_wire_evidence=" + json.dumps(evidence, sort_keys=True))
            print("iOS Simulator default-verification HTTP redirect regression passed")
            return 0
        finally:
            for server in reversed(servers):
                server.close()


if __name__ == "__main__":
    raise SystemExit(main())
