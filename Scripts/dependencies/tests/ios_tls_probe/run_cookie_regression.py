#!/usr/bin/env python3
"""Detect host-only cookie leakage across HTTPS redirect hostnames."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import tempfile
from pathlib import Path

from probe_support import add_stage_argument, load_transport_fixture, require_stage


def checked(command: list[str]) -> None:
    subprocess.run(command, check=True, capture_output=True, text=True)


def make_dual_san_certificates(root: Path) -> tuple[Path, Path, Path]:
    """Create a private CA and a server cert valid for localhost and 127.0.0.1."""
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
        "subjectAltName=DNS:localhost,IP:127.0.0.1\n",
        encoding="ascii",
    )
    checked([
        "openssl", "req", "-x509", "-new", "-nodes", "-newkey", "rsa:2048",
        "-keyout", str(ca_key), "-out", str(ca_cert), "-days", "1",
        "-subj", "/CN=IRPlayer Simulator Cookie Probe CA",
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


def probe(
    runner: Path,
    url: str,
    ca_file: Path,
    *,
    stage: Path,
    device: str,
    deadline_ms: int,
    allow_http_root: bool = False,
) -> dict[str, object]:
    command = [
        sys.executable, str(runner), url,
        "--stage", str(stage),
        "--device", device,
        "--verification", "default",
        "--ca-file", str(ca_file),
        "--deadline-ms", str(deadline_ms),
        "--read-bytes", "16",
        "--operation", "avio",
        "--expect", "success",
    ]
    if allow_http_root:
        command.append("--allow-http-root")
    result = subprocess.run(command, text=True, capture_output=True)
    sys.stdout.write(result.stdout)
    sys.stderr.write(result.stderr)
    if result.returncode:
        raise RuntimeError(f"TLS redirect probe failed, runner rc={result.returncode}")
    records = [
        json.loads(line) for line in result.stdout.splitlines() if line.startswith("{")
    ]
    if len(records) != 1:
        raise RuntimeError(f"expected one probe JSON record, got {records!r}")
    record = records[0]
    if record.get("verification_mode") != "default_no_tls_verify_option":
        raise RuntimeError(f"probe did not use default verification: {record!r}")
    if record.get("operation") != "avio" or int(record.get("bytes_read", 0)) <= 0:
        raise RuntimeError(f"probe did not complete a positive AVIO read: {record!r}")
    return record


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

    fixture = load_transport_fixture("irplayer_cookie_fixture")
    LoopbackServer = fixture.LoopbackServer
    body: bytes = fixture.TS_FIXTURE
    runner = Path(__file__).with_name("run_probe.py")
    servers: list[object] = []
    evidence: dict[str, object] = {}

    with tempfile.TemporaryDirectory(prefix="irplayer-ios-cookie-") as temporary:
        ca_cert, server_cert, server_key = make_dual_san_certificates(Path(temporary))
        tls = (server_cert, server_key)
        try:
            def run_redirect_case(
                name: str,
                source_path: str,
                target_path: str,
                set_cookie: str,
                expected_cookie: str | None,
                *,
                target_host: str = "localhost",
                use_tls: bool = True,
            ) -> None:
                server_tls = tls if use_tls else None
                target = LoopbackServer(
                    lambda path, _headers: (
                        (200, {"Content-Type": "video/mp2t"}, body)
                        if path == target_path else (404, {}, b"")
                    ),
                    tls=server_tls,
                )
                servers.append(target)
                target.start()

                def origin_router(path: str, _headers: dict[str, str]):
                    if path == source_path:
                        return 302, {
                            "Location": target.url(target_path, host=target_host),
                            "Set-Cookie": set_cookie,
                        }, b""
                    return 404, {}, b""

                origin = LoopbackServer(origin_router, tls=server_tls)
                servers.append(origin)
                origin.start()
                result = probe(
                    runner, origin.url(source_path, host="localhost"), ca_cert,
                    stage=stage, device=args.device,
                    deadline_ms=args.deadline_ms,
                    allow_http_root=not use_tls,
                )
                root_requests = origin.recorder.for_path(source_path)
                target_requests = target.recorder.for_path(target_path)
                if len(root_requests) != 1 or not target_requests:
                    raise RuntimeError(
                        f"{name} did not complete its redirect wire chain: "
                        f"root={root_requests!r}, target={target_requests!r}"
                    )
                actual_cookies = [
                    request.headers.get("cookie") for request in target_requests
                ]
                if any(cookie != expected_cookie for cookie in actual_cookies):
                    raise RuntimeError(
                        f"{name} cookie selection mismatch: expected "
                        f"{expected_cookie!r}, got {actual_cookies!r}"
                    )
                evidence[name] = {
                    "bytes_read": result["bytes_read"],
                    "expected_cookie": expected_cookie,
                    "wire": [wire(source_path, root_requests),
                             wire(target_path, target_requests)],
                }

            # These cases exercise the full response-cookie jar round trip,
            # including option copying between the redirect contexts.
            run_redirect_case(
                "explicit_path_positive", "/scope/start", "/scope/final",
                "pathcase=positive; Path=/scope", "pathcase=positive",
            )
            run_redirect_case(
                "path_boundary_negative", "/scope/start", "/scope-other",
                "pathcase=boundary; Path=/scope", None,
            )
            run_redirect_case(
                "default_path_positive", "/default/start", "/default/final",
                "pathcase=default", "pathcase=default",
            )
            run_redirect_case(
                "relative_path_falls_back_to_default",
                "/relative/start", "/relative/final",
                "pathcase=relative; Path=relative", "pathcase=relative",
            )
            run_redirect_case(
                "semicolon_default_path_positive",
                "/semi;token/dir/start", "/semi;token/dir/final",
                "pathcase=semicolon", "pathcase=semicolon",
            )
            run_redirect_case(
                "default_path_attribute_injection_negative",
                "/private;Domain=127.0.0.1;__ffmpeg_host_only=127.0.0.1/start",
                "/private/final", "pathcase=injection; Domain=localhost", None,
                target_host="127.0.0.1",
            )
            run_redirect_case(
                "nonsecure_cookie_http_control",
                "/http/start", "/http/final",
                "transportcase=plain; Path=/", "transportcase=plain",
                use_tls=False,
            )
            run_redirect_case(
                "secure_cookie_http_negative",
                "/http-secure/start", "/http-secure/final",
                "transportcase=secure; Secure; Path=/", None,
                use_tls=False,
            )

            # Control: cookies are hostname-scoped, not port-scoped. A redirect
            # from localhost to localhost on another port must preserve it.
            control_target = LoopbackServer(
                lambda path, _headers: (
                    (200, {"Content-Type": "video/mp2t"}, body)
                    if path == "/control-final" else (404, {}, b"")
                ),
                tls=tls,
            )
            servers.append(control_target)
            control_target.start()

            def control_origin_router(path: str, _headers: dict[str, str]):
                if path == "/control-start":
                    return 302, {
                        "Location": control_target.url("/control-final", host="localhost"),
                        "Set-Cookie": "sid=control; Path=/",
                    }, b""
                return 404, {}, b""

            control_origin = LoopbackServer(control_origin_router, tls=tls)
            servers.append(control_origin)
            control_origin.start()
            control_result = probe(
                runner, control_origin.url("/control-start", host="localhost"), ca_cert,
                stage=stage, device=args.device, deadline_ms=args.deadline_ms,
            )
            control_root_requests = control_origin.recorder.for_path("/control-start")
            control_target_requests = control_target.recorder.for_path("/control-final")
            if len(control_root_requests) != 1 or not control_target_requests:
                raise RuntimeError(
                    "same-host control did not complete its redirect wire chain: "
                    f"root={control_root_requests!r}, target={control_target_requests!r}"
                )
            for request in control_target_requests:
                if request.headers.get("cookie") != "sid=control":
                    raise RuntimeError(
                        "same-host cross-port control failed to preserve its host-only cookie: "
                        f"{control_target_requests!r}"
                    )
            evidence["same_hostname_cross_port_control"] = {
                "bytes_read": control_result["bytes_read"],
                "wire": [wire("/control-start", control_root_requests),
                         wire("/control-final", control_target_requests)],
            }

            # Security case: a host-only localhost cookie must not be sent when
            # an otherwise trusted HTTPS redirect changes the host to 127.0.0.1.
            foreign_target = LoopbackServer(
                lambda path, _headers: (
                    (200, {"Content-Type": "video/mp2t"}, body)
                    if path == "/foreign-final" else (404, {}, b"")
                ),
                tls=tls,
            )
            servers.append(foreign_target)
            foreign_target.start()

            def foreign_origin_router(path: str, _headers: dict[str, str]):
                if path == "/foreign-start":
                    return 302, {
                        "Location": foreign_target.url("/foreign-final", host="127.0.0.1"),
                        "Set-Cookie": "sid=host-only-secret; Path=/",
                    }, b""
                return 404, {}, b""

            foreign_origin = LoopbackServer(foreign_origin_router, tls=tls)
            servers.append(foreign_origin)
            foreign_origin.start()
            foreign_result = probe(
                runner, foreign_origin.url("/foreign-start", host="localhost"), ca_cert,
                stage=stage, device=args.device, deadline_ms=args.deadline_ms,
            )
            foreign_root_requests = foreign_origin.recorder.for_path("/foreign-start")
            foreign_target_requests = foreign_target.recorder.for_path("/foreign-final")
            if len(foreign_root_requests) != 1 or not foreign_target_requests:
                raise RuntimeError(
                    "cross-host case did not complete its trusted TLS redirect wire chain: "
                    f"root={foreign_root_requests!r}, target={foreign_target_requests!r}"
                )
            leaked = [
                request.headers.get("cookie") for request in foreign_target_requests
                if request.headers.get("cookie") is not None
            ]
            evidence["cross_hostname_host_only_cookie"] = {
                "bytes_read": foreign_result["bytes_read"],
                "leaked_cookie_headers": leaked,
                "wire": [wire("/foreign-start", foreign_root_requests),
                         wire("/foreign-final", foreign_target_requests)],
            }
            print("cookie_wire_evidence=" + json.dumps(evidence, sort_keys=True))
            if leaked:
                print(
                    "COOKIE_LEAK_DETECTED: host-only localhost cookie reached "
                    f"foreign HTTPS host 127.0.0.1: {leaked!r}",
                    file=sys.stderr,
                )
                return 1
            print("iOS Simulator host-only cookie isolation regression passed")
            return 0
        finally:
            for server in reversed(servers):
                server.close()


if __name__ == "__main__":
    raise SystemExit(main())
