#!/usr/bin/env python3
"""Exercise cached reconnect and HLS keepalive downgrade policy in Simulator."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import tempfile
from pathlib import Path

from probe_support import add_stage_argument, load_transport_fixture, require_stage
from run_tls13_regression import make_certificates


POLICY_DENIAL = "Refusing HTTP request because the root URL requires HTTPS"


def run_probe(command: list[str], *, expected: str) -> tuple[dict[str, object], str]:
    result = subprocess.run([*command, "--expect", expected], text=True, capture_output=True)
    sys.stdout.write(result.stdout)
    sys.stderr.write(result.stderr)
    if result.returncode:
        raise RuntimeError(f"probe expectation {expected!r} failed, runner rc={result.returncode}")
    records = [
        json.loads(line) for line in result.stdout.splitlines() if line.startswith("{")
    ]
    if len(records) != 1:
        raise RuntimeError(f"expected one probe JSON record, got {records!r}")
    record = records[0]
    if record.get("verification_mode") != "default_no_tls_verify_option":
        raise RuntimeError(f"probe did not use default verification: {record!r}")
    return record, result.stderr


def main() -> int:
    parser = argparse.ArgumentParser()
    add_stage_argument(parser)
    parser.add_argument("--device", default="booted")
    parser.add_argument("--deadline-ms", type=int, default=8000)
    args = parser.parse_args()
    stage = require_stage(parser, args)
    if args.deadline_ms <= 0:
        parser.error("deadline must be positive")

    fixture = load_transport_fixture("irplayer_reconnect_fixture")
    LoopbackServer = fixture.LoopbackServer
    # Repeat the shared two-frame fixture to give the demuxer enough probe data.
    media = fixture.TS_FIXTURE * 8
    runner = Path(__file__).with_name("run_probe.py")
    servers: list[object] = []
    evidence: dict[str, object] = {}

    with tempfile.TemporaryDirectory(prefix="irplayer-ios-reconnect-") as temporary:
        ca_cert, server_cert, server_key = make_certificates(Path(temporary))
        tls = (server_cert, server_key)
        common = [
            sys.executable, str(runner),
            "--stage", str(stage),
            "--device", args.device,
            "--verification", "default",
            "--ca-file", str(ca_cert),
            "--deadline-ms", str(args.deadline_ms),
        ]
        try:
            # A permanent redirect is cached. A deliberately truncated body
            # forces a fresh connection directly to the cached target; that
            # second target response attempts a plaintext redirect.
            plain = LoopbackServer(lambda _path, _headers: (200, {}, b"plaintext"))
            servers.append(plain)
            plain.start()

            def cached_router(path: str, _headers: dict[str, str]):
                if path == "/origin.ts":
                    return 301, {"Location": cached.url("/cached.ts", host="localhost")}, b""
                if path == "/cached.ts":
                    cached_requests = cached.recorder.for_path("/cached.ts")
                    if len(cached_requests) == 1:
                        return (
                            200,
                            {
                                "Content-Type": "video/mp2t",
                                "Content-Length": str(len(media) * 2),
                            },
                            media,
                            True,
                        )
                    return 302, {
                        "Location": plain.url("/reconnect-target", host="localhost")
                    }, b""
                return 404, {}, b""

            cached = LoopbackServer(cached_router, tls=tls)
            servers.append(cached)
            cached.start()
            cached_command = [
                *common[:2], cached.url("/origin.ts", host="localhost"), *common[2:],
                "--operation", "avio",
                "--read-bytes", str(len(media) * 2),
                "--read-iterations", "2",
                "--reconnect", "--reconnect-streamed",
            ]
            cached_result, cached_stderr = run_probe(cached_command, expected="failure")
            origin_requests = cached.recorder.for_path("/origin.ts")
            cached_requests = cached.recorder.for_path("/cached.ts")
            plain_requests = plain.recorder.for_path("/reconnect-target")
            if int(cached_result.get("bytes_read", 0)) <= 0:
                raise RuntimeError(f"cached reconnect never completed a positive HTTPS read: {cached_result!r}")
            if len(origin_requests) != 1 or len(cached_requests) != 2:
                raise RuntimeError(
                    "cached redirect was not reused on EOF reconnect: "
                    f"origin={origin_requests!r}, cached={cached_requests!r}"
                )
            if cached_requests[0].client_port == cached_requests[1].client_port:
                raise RuntimeError("EOF reconnect did not establish a new HTTPS connection")
            if POLICY_DENIAL not in cached_stderr:
                raise RuntimeError(f"cached reconnect lacked policy-denial evidence: {cached_stderr!r}")
            if plain_requests:
                raise RuntimeError(f"cached reconnect emitted plaintext traffic: {plain_requests!r}")
            evidence["cached_permanent_redirect_eof_reconnect"] = {
                "bytes_read_before_denial": cached_result["bytes_read"],
                "origin_hits": len(origin_requests),
                "cached_target_hits": len(cached_requests),
                "cached_client_ports": [request.client_port for request in cached_requests],
                "policy_denial_marker": POLICY_DENIAL,
                "plain_hits": 0,
            }

            # A single persistent HTTPS connection reads a valid first HLS
            # segment and requests the second, whose redirect is denied before
            # the plaintext target. The second request must not be retried.
            hls_plain = LoopbackServer(lambda _path, _headers: (200, {}, b"plaintext"))
            servers.append(hls_plain)
            hls_plain.start()

            def hls_router(path: str, _headers: dict[str, str]):
                if path == "/keepalive.m3u8":
                    playlist = (
                        "#EXTM3U\n#EXT-X-TARGETDURATION:2\n"
                        "#EXTINF:2.0,\nfirst.ts\n"
                        "#EXTINF:2.0,\nsecond.ts\n#EXT-X-ENDLIST\n"
                    )
                    return 200, {"Content-Type": "application/vnd.apple.mpegurl"}, playlist.encode("ascii")
                if path == "/first.ts":
                    return 200, {"Content-Type": "video/mp2t"}, media
                if path == "/second.ts":
                    return 302, {
                        "Location": hls_plain.url("/keepalive-target", host="localhost")
                    }, b""
                return 404, {}, b""

            hls = LoopbackServer(hls_router, tls=tls)
            servers.append(hls)
            hls.start()
            hls_command = [
                *common[:2], hls.url("/keepalive.m3u8", host="localhost"), *common[2:],
                "--operation", "demux", "--max-packets", "64",
                "--http-persistent", "1", "--http-multiple", "0",
            ]
            hls_result, hls_stderr = run_probe(hls_command, expected="success")
            playlist_requests = hls.recorder.for_path("/keepalive.m3u8")
            first_requests = hls.recorder.for_path("/first.ts")
            second_requests = hls.recorder.for_path("/second.ts")
            hls_plain_requests = hls_plain.recorder.for_path("/keepalive-target")
            if int(hls_result.get("packet_count", 0)) <= 0:
                raise RuntimeError(f"HLS keepalive never returned a positive packet: {hls_result!r}")
            if len(playlist_requests) != 1 or not first_requests or len(second_requests) != 1:
                raise RuntimeError(
                    "HLS did not reach playlist, first segment, and exactly one second segment: "
                    f"playlist={playlist_requests!r}, first={first_requests!r}, second={second_requests!r}"
                )
            if first_requests[-1].client_port != second_requests[-1].client_port:
                raise RuntimeError("HLS second segment did not reuse the first segment connection")
            if POLICY_DENIAL not in hls_stderr:
                raise RuntimeError(f"HLS keepalive lacked policy-denial evidence: {hls_stderr!r}")
            if hls_plain_requests:
                raise RuntimeError(f"HLS keepalive emitted plaintext traffic: {hls_plain_requests!r}")
            evidence["hls_keepalive_downgrade_terminal"] = {
                "packet_count_before_denial": hls_result["packet_count"],
                "playlist_hits": len(playlist_requests),
                "first_segment_hits": len(first_requests),
                "second_segment_hits": len(second_requests),
                "reused_client_port": first_requests[-1].client_port,
                "policy_denial_marker": POLICY_DENIAL,
                "plain_hits": 0,
            }

            # An HTTP parent must not weaken the HTTPS requirement acquired by
            # its child segment connection. Reuse that HTTPS connection for a
            # second segment whose plaintext redirect must remain terminal.
            parent_plain_target = LoopbackServer(
                lambda _path, _headers: (200, {}, b"plaintext")
            )
            servers.append(parent_plain_target)
            parent_plain_target.start()

            def child_router(path: str, _headers: dict[str, str]):
                if path == "/child-first.ts":
                    return 200, {"Content-Type": "video/mp2t"}, media
                if path == "/child-second.ts":
                    return 302, {
                        "Location": parent_plain_target.url(
                            "/http-parent-target", host="localhost"
                        )
                    }, b""
                return 404, {}, b""

            child = LoopbackServer(child_router, tls=tls)
            servers.append(child)
            child.start()

            def parent_router(path: str, _headers: dict[str, str]):
                if path != "/parent.m3u8":
                    return 404, {}, b""
                playlist = (
                    "#EXTM3U\n#EXT-X-TARGETDURATION:2\n"
                    "#EXTINF:2.0,\n"
                    f"{child.url('/child-first.ts', host='localhost')}\n"
                    "#EXTINF:2.0,\n"
                    f"{child.url('/child-second.ts', host='localhost')}\n"
                    "#EXT-X-ENDLIST\n"
                )
                return 200, {
                    "Content-Type": "application/vnd.apple.mpegurl"
                }, playlist.encode("ascii")

            parent = LoopbackServer(parent_router)
            servers.append(parent)
            parent.start()
            parent_command = [
                *common[:2], parent.url("/parent.m3u8", host="localhost"), *common[2:],
                "--operation", "demux", "--max-packets", "64",
                "--http-persistent", "1", "--http-multiple", "0",
                "--allow-http-root",
            ]
            parent_result, parent_stderr = run_probe(parent_command, expected="success")
            parent_requests = parent.recorder.for_path("/parent.m3u8")
            child_first_requests = child.recorder.for_path("/child-first.ts")
            child_second_requests = child.recorder.for_path("/child-second.ts")
            parent_plain_requests = parent_plain_target.recorder.for_path(
                "/http-parent-target"
            )
            if int(parent_result.get("packet_count", 0)) <= 0:
                raise RuntimeError(
                    f"HTTP-parent HLS never returned a positive HTTPS child packet: {parent_result!r}"
                )
            if (len(parent_requests) != 1 or not child_first_requests or
                    len(child_second_requests) != 1):
                raise RuntimeError(
                    "HTTP-parent HLS did not reach parent, first child, and exactly one second child: "
                    f"parent={parent_requests!r}, first={child_first_requests!r}, "
                    f"second={child_second_requests!r}"
                )
            if child_first_requests[-1].client_port != child_second_requests[-1].client_port:
                raise RuntimeError("HTTP-parent HLS did not reuse its HTTPS child connection")
            if POLICY_DENIAL not in parent_stderr:
                raise RuntimeError(
                    f"HTTP-parent HLS lacked child policy-denial evidence: {parent_stderr!r}"
                )
            if parent_plain_requests:
                raise RuntimeError(
                    f"HTTP-parent HLS emitted plaintext child traffic: {parent_plain_requests!r}"
                )
            evidence["http_parent_https_child_downgrade_terminal"] = {
                "packet_count_before_denial": parent_result["packet_count"],
                "http_parent_hits": len(parent_requests),
                "https_first_child_hits": len(child_first_requests),
                "https_second_child_hits": len(child_second_requests),
                "reused_https_client_port": child_first_requests[-1].client_port,
                "policy_denial_marker": POLICY_DENIAL,
                "plain_target_hits": 0,
            }

            print("reconnect_wire_evidence=" + json.dumps(evidence, sort_keys=True))
            print("iOS Simulator reconnect and keepalive regression passed")
            return 0
        finally:
            for server in reversed(servers):
                server.close()


if __name__ == "__main__":
    raise SystemExit(main())
