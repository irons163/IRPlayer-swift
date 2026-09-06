#!/usr/bin/env python3
"""Exercise the candidate's real HLS demux path in an iOS Simulator."""

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
    expected: str,
    device: str,
    deadline_ms: int,
    stage: Path,
    headers: str | None = None,
    expected_stderr_marker: str | None = None,
) -> dict[str, object]:
    command = [
        sys.executable,
        str(runner),
        url,
        "--operation",
        "demux",
        "--verification",
        "default",
        "--ca-file",
        str(ca_file),
        "--deadline-ms",
        str(deadline_ms),
        "--max-packets",
        "8",
        "--device",
        device,
        "--expect",
        expected,
    ]
    if headers is not None:
        command += ["--headers", headers]
    command += ["--stage", str(stage)]
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
    records = []
    for line in result.stdout.splitlines():
        if line.startswith("{"):
            records.append(json.loads(line))
    if len(records) != 1:
        raise RuntimeError(f"expected one probe JSON record, got {records!r}")
    record = records[0]
    if record.get("operation") != "demux":
        raise RuntimeError(f"probe did not execute demux mode: {record!r}")
    if record.get("verification_mode") != "default_no_tls_verify_option":
        raise RuntimeError(f"probe supplied an unexpected verification option: {record!r}")
    if expected == "success" and int(record.get("packet_count", 0)) <= 0:
        raise RuntimeError(f"demux success did not return a packet: {record!r}")
    return record


def playlist(segment: str, *, key: str | None = None, iv: str | None = None) -> bytes:
    lines = ["#EXTM3U", "#EXT-X-VERSION:3", "#EXT-X-TARGETDURATION:1"]
    if key is not None:
        key_tag = f'#EXT-X-KEY:METHOD=AES-128,URI="{key}"'
        if iv is not None:
            key_tag += f",IV={iv}"
        lines.append(key_tag)
    lines += ["#EXTINF:0.08,", segment, "#EXT-X-ENDLIST", ""]
    return "\n".join(lines).encode("ascii")


def master_playlist(media_playlist: str) -> bytes:
    return (
        "#EXTM3U\n"
        "#EXT-X-STREAM-INF:BANDWIDTH=128000,CODECS=\"mpeg2video\"\n"
        f"{media_playlist}\n"
    ).encode("ascii")


def event(path: str, requests: list[object]) -> dict[str, object]:
    return {
        "path": path,
        "count": len(requests),
        "headers": [getattr(request, "headers") for request in requests],
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    add_stage_argument(parser)
    parser.add_argument("--device", default="booted")
    parser.add_argument("--deadline-ms", type=int, default=8000)
    args = parser.parse_args()
    stage = require_stage(parser, args)
    if args.deadline_ms <= 0:
        parser.error("deadline must be positive")

    fixture = load_transport_fixture("irplayer_transport_fixture")
    LoopbackServer = fixture.LoopbackServer
    raw_headers: str = fixture.RAW_HEADERS
    raw_header_names: tuple[str, ...] = fixture.RAW_HEADER_NAMES
    expected_headers = expected_raw_headers(raw_headers)
    # The shared fixture is intentionally only two frames. Repeat it so the
    # HLS child demuxer has enough probe bytes to auto-detect MPEG-TS rather
    # than guessing the elementary MPEG-video demuxer.
    ts_fixture: bytes = fixture.TS_FIXTURE * 8
    runner = Path(__file__).with_name("run_probe.py")
    servers: list[object] = []
    evidence: dict[str, object] = {}

    with tempfile.TemporaryDirectory(prefix="irplayer-ios-hls-") as temporary:
        ca_cert, server_cert, server_key = make_certificates(Path(temporary))
        tls = (server_cert, server_key)

        try:
            # 1. A same-origin, explicitly trusted HTTPS playlist must yield a
            # real packet via avformat_open_input/find_stream_info/read_frame.
            def trusted_router(path: str, _headers: dict[str, str]):
                if path == "/trusted.m3u8":
                    return 200, {"Content-Type": "application/vnd.apple.mpegurl"}, playlist("segment.ts")
                if path == "/segment.ts":
                    return 200, {"Content-Type": "video/mp2t"}, ts_fixture
                return 404, {}, b""

            trusted = LoopbackServer(trusted_router, tls=tls)
            servers.append(trusted)
            trusted.start()
            trusted_result = probe(
                runner, trusted.url("/trusted.m3u8", host="localhost"), ca_cert,
                expected="success", device=args.device,
                deadline_ms=args.deadline_ms, stage=stage,
            )
            trusted_playlist = trusted.recorder.for_path("/trusted.m3u8")
            trusted_segment = trusted.recorder.for_path("/segment.ts")
            if not trusted_playlist or not trusted_segment:
                raise RuntimeError("trusted HLS did not fetch both playlist and segment")
            evidence["trusted_explicit_ca"] = {
                "packet_count": trusted_result["packet_count"],
                "wire": [event("/trusted.m3u8", trusted_playlist),
                         event("/segment.ts", trusted_segment)],
            }

            # 2. Decrypt an AES-128-CBC segment whose key and media are on a
            # foreign HTTPS port. Raw caller headers must reach the root only.
            encryption_key = bytes.fromhex("00" * 16)
            encrypted_fixture = subprocess.run(
                [
                    "openssl", "enc", "-aes-128-cbc", "-K", "00" * 16,
                    "-iv", "00" * 16,
                ],
                input=ts_fixture,
                check=True,
                capture_output=True,
            ).stdout

            def foreign_router(path: str, _headers: dict[str, str]):
                if path == "/key.bin":
                    return 200, {"Content-Type": "application/octet-stream"}, encryption_key
                if path == "/encrypted.ts":
                    return 200, {"Content-Type": "video/mp2t"}, encrypted_fixture
                return 404, {}, b""

            foreign = LoopbackServer(foreign_router, tls=tls)
            servers.append(foreign)
            foreign.start()

            def origin_router(path: str, _headers: dict[str, str]):
                if path == "/foreign.m3u8":
                    key_url = foreign.url("/key.bin", host="localhost")
                    media_url = foreign.url("/encrypted.ts", host="localhost")
                    body = playlist(media_url, key=key_url, iv="0x" + "00" * 16)
                    return 200, {"Content-Type": "application/vnd.apple.mpegurl"}, body
                return 404, {}, b""

            origin = LoopbackServer(origin_router, tls=tls)
            servers.append(origin)
            origin.start()
            foreign_result = probe(
                runner, origin.url("/foreign.m3u8", host="localhost"), ca_cert,
                expected="success", device=args.device,
                deadline_ms=args.deadline_ms, stage=stage, headers=raw_headers,
            )
            origin_requests = origin.recorder.for_path("/foreign.m3u8")
            foreign_key_requests = foreign.recorder.for_path("/key.bin")
            foreign_segment_requests = foreign.recorder.for_path("/encrypted.ts")
            if not origin_requests or not foreign_key_requests or not foreign_segment_requests:
                raise RuntimeError("encrypted HLS did not fetch playlist, key, and segment")
            missing_at_root = [
                name for name in raw_header_names
                if name not in origin_requests[0].headers
            ]
            leaked_key = sorted({
                name for request in foreign_key_requests for name in raw_header_names
                if name in request.headers
            })
            leaked_segment = sorted({
                name for request in foreign_segment_requests for name in raw_header_names
                if name in request.headers
            })
            leaked = sorted(set(leaked_key + leaked_segment))
            if missing_at_root or leaked:
                raise RuntimeError(
                    f"raw-header origin policy mismatch: missing={missing_at_root}, leaked={leaked}"
                )
            evidence["encrypted_foreign_origin_header_strip"] = {
                "packet_count": foreign_result["packet_count"],
                "root_header_names": sorted(
                    name for name in raw_header_names if name in origin_requests[0].headers
                ),
                "foreign_key_sensitive_header_names": leaked_key,
                "foreign_segment_sensitive_header_names": leaked_segment,
                "wire": [event("/foreign.m3u8", origin_requests),
                         event("/key.bin", foreign_key_requests),
                         event("/encrypted.ts", foreign_segment_requests)],
            }

            # 3. A foreign media playlist inherits the root security policy but
            # not the root's caller-provided headers. Its segment must remain
            # header-free while still producing real packets.
            def nested_foreign_router(path: str, _headers: dict[str, str]):
                if path == "/media.m3u8":
                    return 200, {
                        "Content-Type": "application/vnd.apple.mpegurl"
                    }, playlist("nested.ts")
                if path == "/nested.ts":
                    return 200, {"Content-Type": "video/mp2t"}, ts_fixture
                return 404, {}, b""

            nested_foreign = LoopbackServer(nested_foreign_router, tls=tls)
            servers.append(nested_foreign)
            nested_foreign.start()

            def nested_root_router(path: str, _headers: dict[str, str]):
                if path == "/master.m3u8":
                    media_url = nested_foreign.url("/media.m3u8", host="localhost")
                    return 200, {
                        "Content-Type": "application/vnd.apple.mpegurl"
                    }, master_playlist(media_url)
                return 404, {}, b""

            nested_root = LoopbackServer(nested_root_router, tls=tls)
            servers.append(nested_root)
            nested_root.start()
            nested_result = probe(
                runner, nested_root.url("/master.m3u8", host="localhost"), ca_cert,
                expected="success", device=args.device,
                deadline_ms=args.deadline_ms, stage=stage, headers=raw_headers,
            )
            master_requests = nested_root.recorder.for_path("/master.m3u8")
            media_playlist_requests = nested_foreign.recorder.for_path("/media.m3u8")
            nested_segment_requests = nested_foreign.recorder.for_path("/nested.ts")
            if not master_requests or not media_playlist_requests or not nested_segment_requests:
                raise RuntimeError(
                    "nested HLS did not fetch master, foreign media playlist, and segment"
                )
            mismatched_nested_root = sorted({
                name for request in master_requests
                for name, value in expected_headers.items()
                if request.headers.get(name) != value
            })
            leaked_nested_foreign = sorted({
                name
                for request in [*media_playlist_requests, *nested_segment_requests]
                for name in raw_header_names
                if name in request.headers
            })
            if mismatched_nested_root or leaked_nested_foreign:
                raise RuntimeError(
                    "nested HLS header policy mismatch: "
                    f"root_mismatched={mismatched_nested_root}, "
                    f"foreign_leaked={leaked_nested_foreign}"
                )
            evidence["nested_foreign_media_playlist_header_strip"] = {
                "packet_count": nested_result["packet_count"],
                "root_header_names": sorted(raw_header_names),
                "foreign_sensitive_header_names": leaked_nested_foreign,
                "wire": [event("/master.m3u8", master_requests),
                         event("/media.m3u8", media_playlist_requests),
                         event("/nested.ts", nested_segment_requests)],
            }

            # 4. An HTTPS master may not open a plaintext media playlist. The
            # denial must happen after fetching the verified master and before
            # emitting any request to the HTTP fixture.
            nested_plain = LoopbackServer(
                lambda _path, _headers: (
                    200, {"Content-Type": "application/vnd.apple.mpegurl"},
                    playlist("never.ts")
                )
            )
            servers.append(nested_plain)
            nested_plain.start()

            def nested_downgrade_router(path: str, _headers: dict[str, str]):
                if path == "/downgrade-master.m3u8":
                    media_url = nested_plain.url("/plain-media.m3u8", host="localhost")
                    return 200, {
                        "Content-Type": "application/vnd.apple.mpegurl"
                    }, master_playlist(media_url)
                return 404, {}, b""

            nested_downgrade = LoopbackServer(nested_downgrade_router, tls=tls)
            servers.append(nested_downgrade)
            nested_downgrade.start()
            policy_denial = "Refusing HTTP request because the root URL requires HTTPS"
            nested_failure = probe(
                runner,
                nested_downgrade.url("/downgrade-master.m3u8", host="localhost"),
                ca_cert, expected="failure", device=args.device,
                deadline_ms=args.deadline_ms, stage=stage,
                expected_stderr_marker=policy_denial,
            )
            downgrade_master_requests = nested_downgrade.recorder.for_path(
                "/downgrade-master.m3u8"
            )
            plain_media_requests = nested_plain.recorder.for_path("/plain-media.m3u8")
            if len(downgrade_master_requests) != 1:
                raise RuntimeError(
                    "nested downgrade did not reach exactly one verified HTTPS master: "
                    f"{downgrade_master_requests!r}"
                )
            if plain_media_requests:
                raise RuntimeError(
                    f"nested downgrade emitted plaintext media request: {plain_media_requests!r}"
                )
            evidence["nested_plain_media_playlist_denied"] = {
                "master_hits": len(downgrade_master_requests),
                "plain_media_hits": 0,
                "packet_count": nested_failure["packet_count"],
                "policy_denial_marker": policy_denial,
            }

            # 5a/5b. HTTPS playlists may not downgrade either the media segment
            # or an AES key to plaintext. Denial must occur before an HTTP GET.
            plain = LoopbackServer(
                lambda _path, _headers: (200, {"Content-Type": "application/octet-stream"}, ts_fixture)
            )
            servers.append(plain)
            plain.start()

            def downgrade_router(path: str, _headers: dict[str, str]):
                if path == "/plain-segment.m3u8":
                    return 200, {"Content-Type": "application/vnd.apple.mpegurl"}, playlist(
                        plain.url("/plain.ts", host="localhost")
                    )
                if path == "/plain-key.m3u8":
                    return 200, {"Content-Type": "application/vnd.apple.mpegurl"}, playlist(
                        "encrypted.ts", key=plain.url("/key.bin", host="localhost")
                    )
                if path == "/encrypted.ts":
                    return 200, {"Content-Type": "video/mp2t"}, ts_fixture
                return 404, {}, b""

            downgrade = LoopbackServer(downgrade_router, tls=tls)
            servers.append(downgrade)
            downgrade.start()
            policy_denial = "Refusing HTTP request because the root URL requires HTTPS"
            segment_failure = probe(
                runner, downgrade.url("/plain-segment.m3u8", host="localhost"), ca_cert,
                expected="failure", device=args.device,
                deadline_ms=args.deadline_ms, stage=stage,
                expected_stderr_marker=policy_denial,
            )
            key_failure = probe(
                runner, downgrade.url("/plain-key.m3u8", host="localhost"), ca_cert,
                expected="failure", device=args.device,
                deadline_ms=args.deadline_ms, stage=stage,
                expected_stderr_marker=policy_denial,
            )
            segment_playlist_hits = downgrade.recorder.for_path("/plain-segment.m3u8")
            key_playlist_hits = downgrade.recorder.for_path("/plain-key.m3u8")
            plain_segment_hits = plain.recorder.for_path("/plain.ts")
            plain_key_hits = plain.recorder.for_path("/key.bin")
            if len(segment_playlist_hits) != 1 or len(key_playlist_hits) != 1:
                raise RuntimeError(
                    "downgrade probes did not each reach exactly one verified HTTPS playlist: "
                    f"segment={segment_playlist_hits!r}, key={key_playlist_hits!r}"
                )
            if plain_segment_hits or plain_key_hits:
                raise RuntimeError(
                    "HTTPS HLS downgrade emitted plaintext traffic: "
                    f"segment={plain_segment_hits!r}, key={plain_key_hits!r}"
                )
            evidence["plaintext_segment_and_key_denied"] = {
                "segment_probe_packet_count": segment_failure["packet_count"],
                "key_probe_packet_count": key_failure["packet_count"],
                "plain_segment_hits": 0,
                "plain_key_hits": 0,
                "policy_denial_marker": policy_denial,
                "https_playlist_hits": {
                    "/plain-segment.m3u8": len(segment_playlist_hits),
                    "/plain-key.m3u8": len(key_playlist_hits),
                },
            }

            print("hls_wire_evidence=" + json.dumps(evidence, sort_keys=True))
            print("iOS Simulator default-verification HLS regression passed")
            return 0
        finally:
            for server in reversed(servers):
                server.close()


if __name__ == "__main__":
    raise SystemExit(main())
