#!/usr/bin/env python3
"""Loopback acceptance tests for the IRPlayer FFmpeg transport patches.

The target must be a host ffprobe built from FFmpeg n6.1.6 with the two
patches in ``Scripts/dependencies/patches`` applied.  The test server never
uses a system trust-store modification: HTTPS tests install a temporary test
CA only through FFmpeg's ``-ca_file`` input option.
"""

from __future__ import annotations

import argparse
import base64
import os
import shutil
import ssl
import subprocess
import tempfile
import threading
import unittest
from dataclasses import dataclass
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Callable


RAW_HEADERS = (
    "X-IRPlayer-Secret: root-only\r\n"
    "X-IRPlayer-Trace: root-only\r\n"
    "Authorization: Bearer root-only\r\n"
    "Cookie: root-only=yes\r\n"
)
RAW_HEADER_NAMES = (
    "x-irplayer-secret",
    "x-irplayer-trace",
    "authorization",
    "cookie",
)
# A two-frame, valid MPEG-TS fixture generated from a synthetic black frame.
TS_FIXTURE = base64.b64decode(
    "R0AREABC8CUAAcEAAP8B/wAB/IAUSBIBBkZGbXBlZwlTZXJ2aWNlMDF3fEPK////////////////////////////////////////"
    "////////////////////////////////////////////////////////////////////////////////////////////////////"
    "//////////////////////////////////////////////////9HQAAQAACwDQABwQAAAAHwACqxBLL/////////////////////"
    "////////////////////////////////////////////////////////////////////////////////////////////////////"
    "////////////////////////////////////////////////////////////////////////////////////////////////////"
    "/0dQABAAArASAAHBAADhAPAAAuEA8ACeiyPR////////////////////////////////////////////////////////////////"
    "////////////////////////////////////////////////////////////////////////////////////////////////////"
    "////////////////////////////////////////////////////R0EAMGtQAAB7DH4A////////////////////////////////"
    "////////////////////////////////////////////////////////////////////////////////////////////////////"
    "/wAAAeAAAIDACjEADZeBEQAH2GEAAAGzAQAQEv//4BgAAAG1FIoAAQAXAAABuAAIAEAAAAEAAA//+AAAAbWP//NBgAAAAQET+H0p"
    "SIhHQBERAELwJQABwQAA/wH/AAH8gBRIEgEGRkZtcGVnCVNlcnZpY2UwMXd8Q8r/////////////////////////////////////"
    "////////////////////////////////////////////////////////////////////////////////////////////////////"
    "/////////////////////////////////////////////////////0dAABEAALANAAHBAAAAAfAAKrEEsv//////////////////"
    "////////////////////////////////////////////////////////////////////////////////////////////////////"
    "////////////////////////////////////////////////////////////////////////////////////////////////////"
    "////R1AAEQACsBIAAcEAAOEA8AAC4QDwAJ6LI9H/////////////////////////////////////////////////////////////"
    "////////////////////////////////////////////////////////////////////////////////////////////////////"
    "//////////////////////////////////////////////////////9HQQAxa1AAASrUfgD/////////////////////////////"
    "////////////////////////////////////////////////////////////////////////////////////////////////////"
    "////AAAB4AAAgMAKMQATVqERAA2XgQAAAbMBABAS///gGAAAAbUUigABABcAAAG4AAgAwAAAAQAAD//4AAABtY//80GAAAABARP4"
    "fSlIiA=="
)


@dataclass(frozen=True)
class Request:
    path: str
    headers: dict[str, str]
    client_port: int


class Recorder:
    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._requests: list[Request] = []

    def add(self, path: str, headers: dict[str, str], client_port: int) -> None:
        with self._lock:
            self._requests.append(Request(path, headers, client_port))

    def for_path(self, path: str) -> list[Request]:
        with self._lock:
            return [request for request in self._requests if request.path == path]


# The optional fourth tuple item deliberately closes the TCP connection after
# sending a short body. It lets a test trigger FFmpeg's EOF reconnect path.
Response = tuple[int, dict[str, str], bytes] | tuple[int, dict[str, str], bytes, bool]
Router = Callable[[str, dict[str, str]], Response]


class _Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_GET(self) -> None:  # noqa: N802 - HTTP server callback name
        headers = {name.lower(): value for name, value in self.headers.items()}
        self.server.recorder.add(self.path, headers, self.client_address[1])  # type: ignore[attr-defined]
        response = self.server.router(self.path, headers)  # type: ignore[attr-defined]
        status, response_headers, body = response[:3]
        close_connection = len(response) == 4 and response[3]
        self.send_response(status)
        for name, value in response_headers.items():
            self.send_header(name, value)
        if not any(name.lower() == "content-length" for name in response_headers):
            self.send_header("Content-Length", str(len(body)))
        if close_connection:
            self.send_header("Connection", "close")
        self.end_headers()
        if body:
            self.wfile.write(body)
        self.close_connection = close_connection

    def log_message(self, _format: str, *_args: object) -> None:
        pass


class LoopbackServer:
    def __init__(self, router: Router, tls: tuple[Path, Path] | None = None) -> None:
        self.recorder = Recorder()
        self._server = ThreadingHTTPServer(("127.0.0.1", 0), _Handler)
        self._server.daemon_threads = True
        self._server.recorder = self.recorder  # type: ignore[attr-defined]
        self._server.router = router  # type: ignore[attr-defined]
        self._tls = tls
        self._thread: threading.Thread | None = None

    @property
    def port(self) -> int:
        return int(self._server.server_address[1])

    def url(self, path: str, host: str = "127.0.0.1") -> str:
        scheme = "https" if self._tls else "http"
        return f"{scheme}://{host}:{self.port}{path}"

    def start(self) -> None:
        if self._tls:
            cert, key = self._tls
            context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
            context.load_cert_chain(certfile=cert, keyfile=key)
            self._server.socket = context.wrap_socket(self._server.socket, server_side=True)
        self._thread = threading.Thread(target=self._server.serve_forever, daemon=True)
        self._thread.start()

    def close(self) -> None:
        self._server.shutdown()
        self._server.server_close()
        if self._thread:
            self._thread.join(timeout=2)


class TransportSecurityTests(unittest.TestCase):
    ffprobe: str

    @classmethod
    def setUpClass(cls) -> None:
        if not shutil.which("openssl"):
            raise unittest.SkipTest("openssl is required for local TLS tests")
        cls.tempdir = tempfile.TemporaryDirectory(prefix="irplayer-transport-")
        cls.workdir = Path(cls.tempdir.name)
        cls.trusted_ca, cls.trusted_cert, cls.trusted_key = cls._make_certificate("trusted")
        cls.untrusted_ca, cls.untrusted_cert, cls.untrusted_key = cls._make_certificate("untrusted")
        cls.mismatch_ca, cls.mismatch_cert, cls.mismatch_key = cls._make_certificate(
            "hostname-mismatch", dns_name="not-localhost", include_ip=False
        )

    @classmethod
    def tearDownClass(cls) -> None:
        cls.tempdir.cleanup()

    @classmethod
    def _make_certificate(
        cls, name: str, dns_name: str = "localhost", include_ip: bool = True
    ) -> tuple[Path, Path, Path]:
        directory = cls.workdir / name
        directory.mkdir()
        ca_key = directory / "ca.key"
        ca_cert = directory / "ca.pem"
        key = directory / "server.key"
        csr = directory / "server.csr"
        cert = directory / "server.pem"
        ext = directory / "server.ext"
        subject_alt_name = f"DNS:{dns_name}"
        if include_ip:
            subject_alt_name += ",IP:127.0.0.1"
        ext.write_text(
            "basicConstraints=critical,CA:FALSE\n"
            "keyUsage=critical,digitalSignature,keyEncipherment\n"
            "extendedKeyUsage=serverAuth\n"
            f"subjectAltName={subject_alt_name}\n",
            encoding="ascii",
        )
        cls._checked(
            [
                "openssl", "req", "-x509", "-new", "-nodes", "-newkey", "rsa:2048",
                "-keyout", str(ca_key), "-out", str(ca_cert), "-days", "1",
                "-subj", f"/CN=IRPlayer {name} CA",
                "-addext", "basicConstraints=critical,CA:TRUE",
            ]
        )
        cls._checked(
            [
                "openssl", "req", "-new", "-nodes", "-newkey", "rsa:2048",
                "-keyout", str(key), "-out", str(csr), "-subj", "/CN=localhost",
            ]
        )
        cls._checked(
            [
                "openssl", "x509", "-req", "-in", str(csr), "-CA", str(ca_cert),
                "-CAkey", str(ca_key), "-CAcreateserial", "-out", str(cert), "-days", "1",
                "-extfile", str(ext),
            ]
        )
        return ca_cert, cert, key

    @staticmethod
    def _checked(command: list[str]) -> None:
        subprocess.run(command, check=True, capture_output=True, text=True)

    def setUp(self) -> None:
        self.servers: list[LoopbackServer] = []

    def tearDown(self) -> None:
        for server in reversed(self.servers):
            server.close()

    def serve(self, router: Router, tls: tuple[Path, Path] | None = None) -> LoopbackServer:
        server = LoopbackServer(router, tls)
        server.start()
        self.servers.append(server)
        return server

    def probe(
        self,
        url: str,
        headers: str | None = None,
        ca_file: Path | None = None,
        input_options: list[str] | None = None,
    ) -> subprocess.CompletedProcess[str]:
        command = [
            self.ffprobe,
            "-v",
            os.environ.get("IRPLAYER_TRANSPORT_LOGLEVEL", "error"),
            "-rw_timeout",
            "3000000",
        ]
        if ca_file:
            # SecureTransport reads the test CA through FFmpeg I/O, whose HTTP
            # default whitelist excludes file:. This is local test plumbing,
            # not a trust-store modification.
            command += ["-protocol_whitelist", "file,http,https,tls,tcp,crypto"]
            command += ["-ca_file", str(ca_file)]
        if headers:
            command += ["-headers", headers]
        if input_options:
            command += input_options
        command += ["-show_format", "-of", "json", url]
        environment = os.environ.copy()
        for name in ("http_proxy", "https_proxy", "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "all_proxy"):
            environment.pop(name, None)
        return subprocess.run(
            command,
            check=False,
            capture_output=True,
            text=True,
            timeout=12,
            env=environment,
        )

    def request_headers(self, server: LoopbackServer, path: str) -> dict[str, str]:
        requests = server.recorder.for_path(path)
        self.assertTrue(requests, f"expected a request for {path}")
        return requests[-1].headers

    def assert_raw_headers_present(self, headers: dict[str, str]) -> None:
        self.assertEqual(headers.get("x-irplayer-secret"), "root-only")
        self.assertEqual(headers.get("x-irplayer-trace"), "root-only")
        self.assertEqual(headers.get("authorization"), "Bearer root-only")
        self.assertEqual(headers.get("cookie"), "root-only=yes")

    def assert_raw_headers_absent(self, headers: dict[str, str]) -> None:
        for name in RAW_HEADER_NAMES:
            self.assertNotIn(name, headers, f"foreign request leaked {name}")

    def encrypted_fixture(self) -> bytes:
        result = subprocess.run(
            [
                "openssl", "enc", "-aes-128-cbc", "-K", "00" * 16,
                "-iv", "00" * 16, "-nopad",
            ],
            check=True,
            input=TS_FIXTURE,
            capture_output=True,
        )
        return result.stdout

    def test_same_origin_redirect_keeps_raw_headers(self) -> None:
        server: LoopbackServer

        def router(path: str, _headers: dict[str, str]) -> Response:
            if path == "/start":
                return 302, {"Location": server.url("/final")}, b""
            return 200, {"Content-Type": "video/MP2T"}, TS_FIXTURE

        server = self.serve(router)
        result = self.probe(server.url("/start"), headers=RAW_HEADERS)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_raw_headers_present(self.request_headers(server, "/final"))

    def test_foreign_redirect_strips_every_raw_header(self) -> None:
        foreign = self.serve(lambda _path, _headers: (200, {"Content-Type": "video/MP2T"}, TS_FIXTURE))
        origin: LoopbackServer

        def router(path: str, _headers: dict[str, str]) -> Response:
            if path == "/start":
                return 302, {"Location": foreign.url("/foreign")}, b""
            return 404, {}, b""

        origin = self.serve(router)
        result = self.probe(origin.url("/start"), headers=RAW_HEADERS)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_raw_headers_absent(self.request_headers(foreign, "/foreign"))

    def test_https_redirect_to_http_never_reaches_plain_server(self) -> None:
        plain = self.serve(lambda _path, _headers: (200, {"Content-Type": "video/MP2T"}, TS_FIXTURE))
        secure: LoopbackServer

        def router(path: str, _headers: dict[str, str]) -> Response:
            if path == "/downgrade":
                return 301, {"Location": plain.url("/downgrade-target")}, b""
            return 404, {}, b""

        secure = self.serve(router, tls=(self.trusted_cert, self.trusted_key))
        result = self.probe(secure.url("/downgrade", host="localhost"), ca_file=self.trusted_ca)
        self.assertNotEqual(result.returncode, 0, result.stderr)
        self.request_headers(secure, "/downgrade")
        self.assertIn("Refusing HTTP request because the root URL requires HTTPS", result.stderr)
        self.assertFalse(plain.recorder.for_path("/downgrade-target"))

    def test_https_cached_redirect_reconnect_never_reaches_plain_server(self) -> None:
        plain = self.serve(lambda _path, _headers: (200, {}, b"plaintext"))
        secure: LoopbackServer

        def router(path: str, _headers: dict[str, str]) -> Response:
            if path == "/origin.ts":
                return 301, {"Location": secure.url("/cached.ts", host="localhost")}, b""
            if path == "/cached.ts":
                cached_requests = secure.recorder.for_path("/cached.ts")
                if len(cached_requests) == 1:
                    # Advertise more data than is sent, then close. This makes
                    # -reconnect re-enter http_open_cnx through the permanent
                    # redirect cache instead of requesting /origin.ts again.
                    return (
                        200,
                        {
                            "Content-Type": "video/MP2T",
                            "Content-Length": str(len(TS_FIXTURE) * 2),
                        },
                        TS_FIXTURE,
                        True,
                    )
                return 302, {"Location": plain.url("/reconnect-target")}, b""
            return 404, {}, b""

        secure = self.serve(router, tls=(self.trusted_cert, self.trusted_key))
        result = self.probe(
            secure.url("/origin.ts", host="localhost"),
            ca_file=self.trusted_ca,
            input_options=["-reconnect", "1", "-reconnect_streamed", "1"],
        )
        self.assertEqual(len(secure.recorder.for_path("/origin.ts")), 1, result.stderr)
        self.assertEqual(len(secure.recorder.for_path("/cached.ts")), 2, result.stderr)
        self.assertIn("Refusing HTTP request because the root URL requires HTTPS", result.stderr)
        self.assertFalse(plain.recorder.for_path("/reconnect-target"))

    def test_tls_default_verification_accepts_only_the_supplied_local_ca(self) -> None:
        trusted = self.serve(
            lambda _path, _headers: (200, {"Content-Type": "video/MP2T"}, TS_FIXTURE),
            tls=(self.trusted_cert, self.trusted_key),
        )
        result = self.probe(trusted.url("/trusted.ts", host="localhost"), ca_file=self.trusted_ca)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(trusted.recorder.for_path("/trusted.ts"), result.stderr)

        untrusted = self.serve(
            lambda _path, _headers: (200, {"Content-Type": "video/MP2T"}, TS_FIXTURE),
            tls=(self.untrusted_cert, self.untrusted_key),
        )
        result = self.probe(untrusted.url("/untrusted.ts", host="localhost"), ca_file=self.trusted_ca)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(untrusted.recorder.for_path("/untrusted.ts"))

    def test_tls_hostname_mismatch_never_reaches_http(self) -> None:
        mismatch = self.serve(
            lambda _path, _headers: (200, {"Content-Type": "video/MP2T"}, TS_FIXTURE),
            tls=(self.mismatch_cert, self.mismatch_key),
        )
        result = self.probe(mismatch.url("/hostname.ts", host="localhost"), ca_file=self.mismatch_ca)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(mismatch.recorder.for_path("/hostname.ts"))

    def test_hls_same_origin_segment_keeps_raw_headers(self) -> None:
        playlist = b"#EXTM3U\n#EXT-X-TARGETDURATION:2\n#EXTINF:2.0,\nsame.ts\n#EXT-X-ENDLIST\n"

        def router(path: str, _headers: dict[str, str]) -> Response:
            if path == "/same.m3u8":
                return 200, {"Content-Type": "application/vnd.apple.mpegurl"}, playlist
            if path == "/same.ts":
                return 200, {"Content-Type": "video/MP2T"}, TS_FIXTURE
            return 404, {}, b""

        server = self.serve(router)
        result = self.probe(server.url("/same.m3u8"), headers=RAW_HEADERS)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_raw_headers_present(self.request_headers(server, "/same.ts"))

    def test_hls_crypto_https_foreign_key_and_segment_strip_raw_headers(self) -> None:
        encrypted = self.encrypted_fixture()
        foreign = self.serve(
            lambda path, _headers: (
                (200, {"Content-Type": "application/octet-stream"}, b"\0" * 16)
                if path == "/key.bin"
                else (200, {"Content-Type": "video/MP2T"}, encrypted)
                if path == "/encrypted.ts"
                else (404, {}, b"")
            ),
            tls=(self.trusted_cert, self.trusted_key),
        )
        origin: LoopbackServer

        def router(path: str, _headers: dict[str, str]) -> Response:
            if path != "/foreign.m3u8":
                return 404, {}, b""
            key_url = foreign.url("/key.bin", host="localhost")
            segment_url = foreign.url("/encrypted.ts", host="localhost")
            playlist = (
                "#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-TARGETDURATION:2\n"
                f"#EXT-X-KEY:METHOD=AES-128,URI=\"{key_url}\",IV=0x{'00' * 16}\n"
                f"#EXTINF:2.0,\n{segment_url}\n#EXT-X-ENDLIST\n"
            ).encode("ascii")
            return 200, {"Content-Type": "application/vnd.apple.mpegurl"}, playlist

        origin = self.serve(router, tls=(self.trusted_cert, self.trusted_key))
        result = self.probe(
            origin.url("/foreign.m3u8", host="localhost"),
            headers=RAW_HEADERS,
            ca_file=self.trusted_ca,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_raw_headers_present(self.request_headers(origin, "/foreign.m3u8"))
        self.assert_raw_headers_absent(self.request_headers(foreign, "/key.bin"))
        self.assert_raw_headers_absent(self.request_headers(foreign, "/encrypted.ts"))

    def test_https_hls_never_opens_plain_segment_or_key(self) -> None:
        plain = self.serve(lambda _path, _headers: (200, {}, b"plaintext"))
        secure: LoopbackServer

        def router(path: str, _headers: dict[str, str]) -> Response:
            if path == "/segment.m3u8":
                playlist = f"#EXTM3U\n#EXT-X-TARGETDURATION:2\n#EXTINF:2.0,\n{plain.url('/segment.ts')}\n#EXT-X-ENDLIST\n"
                return 200, {"Content-Type": "application/vnd.apple.mpegurl"}, playlist.encode("ascii")
            if path == "/key.m3u8":
                playlist = (
                    "#EXTM3U\n#EXT-X-TARGETDURATION:2\n"
                    f"#EXT-X-KEY:METHOD=AES-128,URI=\"{plain.url('/key.bin')}\",IV=0x{'00' * 16}\n"
                    "#EXTINF:2.0,\nsame.ts\n#EXT-X-ENDLIST\n"
                )
                return 200, {"Content-Type": "application/vnd.apple.mpegurl"}, playlist.encode("ascii")
            if path == "/same.ts":
                return 200, {"Content-Type": "video/MP2T"}, TS_FIXTURE
            return 404, {}, b""

        secure = self.serve(router, tls=(self.trusted_cert, self.trusted_key))
        for path, plain_path in (("/segment.m3u8", "/segment.ts"), ("/key.m3u8", "/key.bin")):
            result = self.probe(secure.url(path, host="localhost"), ca_file=self.trusted_ca)
            self.assertNotEqual(result.returncode, 0)
            self.request_headers(secure, path)
            self.assertIn("Refusing HTTP request because the root URL requires HTTPS", result.stderr)
            self.assertFalse(plain.recorder.for_path(plain_path))

    def test_https_hls_keepalive_policy_failure_is_terminal(self) -> None:
        plain = self.serve(lambda _path, _headers: (200, {}, b"plaintext"))
        secure: LoopbackServer

        def router(path: str, _headers: dict[str, str]) -> Response:
            if path == "/keepalive.m3u8":
                playlist = (
                    "#EXTM3U\n#EXT-X-TARGETDURATION:2\n#EXTINF:2.0,\nfirst.ts\n"
                    "#EXTINF:2.0,\nsecond.ts\n#EXT-X-ENDLIST\n"
                )
                return 200, {"Content-Type": "application/vnd.apple.mpegurl"}, playlist.encode("ascii")
            if path == "/first.ts":
                return 200, {"Content-Type": "video/MP2T"}, TS_FIXTURE
            if path == "/second.ts":
                return 302, {"Location": plain.url("/keepalive-target")}, b""
            return 404, {}, b""

        secure = self.serve(router, tls=(self.trusted_cert, self.trusted_key))
        result = self.probe(
            secure.url("/keepalive.m3u8", host="localhost"),
            ca_file=self.trusted_ca,
            input_options=["-http_persistent", "1", "-http_multiple", "0"],
        )
        first_requests = secure.recorder.for_path("/first.ts")
        second_requests = secure.recorder.for_path("/second.ts")
        self.assertTrue(first_requests, result.stderr)
        self.assertTrue(second_requests, result.stderr)
        self.assertEqual(len(second_requests), 1, "policy denial must not retry via a new connection")
        self.assertEqual(first_requests[-1].client_port, second_requests[-1].client_port)
        # ffprobe may still exit 0 after parsing the first valid segment. The
        # security oracle is the reused-connection request plus the no-hit
        # assertion below, not the aggregate probe status.
        self.assertIn("Refusing HTTP request because the root URL requires HTTPS", result.stderr)
        self.assertFalse(plain.recorder.for_path("/keepalive-target"))

    def test_http_parent_hls_keepalive_cannot_reset_https_requirement(self) -> None:
        plain = self.serve(lambda _path, _headers: (200, {}, b"plaintext"))
        secure: LoopbackServer

        def secure_router(path: str, _headers: dict[str, str]) -> Response:
            if path == "/first.ts":
                return 200, {"Content-Type": "video/MP2T"}, TS_FIXTURE
            if path == "/second.ts":
                return 302, {"Location": plain.url("/http-parent-target")}, b""
            return 404, {}, b""

        secure = self.serve(secure_router, tls=(self.trusted_cert, self.trusted_key))

        def origin_router(path: str, _headers: dict[str, str]) -> Response:
            if path != "/parent.m3u8":
                return 404, {}, b""
            playlist = (
                "#EXTM3U\n#EXT-X-TARGETDURATION:2\n"
                f"#EXTINF:2.0,\n{secure.url('/first.ts', host='localhost')}\n"
                f"#EXTINF:2.0,\n{secure.url('/second.ts', host='localhost')}\n#EXT-X-ENDLIST\n"
            )
            return 200, {"Content-Type": "application/vnd.apple.mpegurl"}, playlist.encode("ascii")

        origin = self.serve(origin_router)
        result = self.probe(
            origin.url("/parent.m3u8"),
            ca_file=self.trusted_ca,
            input_options=["-http_persistent", "1", "-http_multiple", "0"],
        )
        self.request_headers(origin, "/parent.m3u8")
        first_requests = secure.recorder.for_path("/first.ts")
        second_requests = secure.recorder.for_path("/second.ts")
        self.assertTrue(first_requests, result.stderr)
        self.assertTrue(second_requests, result.stderr)
        self.assertEqual(len(second_requests), 1, "policy denial must not retry via a new connection")
        self.assertEqual(first_requests[-1].client_port, second_requests[-1].client_port)
        self.assertIn("Refusing HTTP request because the root URL requires HTTPS", result.stderr)
        self.assertFalse(plain.recorder.for_path("/http-parent-target"))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ffprobe", required=True, help="patched host ffprobe executable")
    args, unittest_args = parser.parse_known_args()
    TransportSecurityTests.ffprobe = str(Path(args.ffprobe).resolve())
    if not Path(TransportSecurityTests.ffprobe).is_file():
        parser.error(f"ffprobe does not exist: {TransportSecurityTests.ffprobe}")
    unittest.main(argv=["test_transport_security.py", *unittest_args], verbosity=2)
    return 0


if __name__ == "__main__":
    main()
