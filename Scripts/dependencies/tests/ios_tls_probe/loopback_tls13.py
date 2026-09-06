#!/usr/bin/env python3
"""TLS 1.3-only HTTP fixture for the iOS Simulator AVIO probe."""

from __future__ import annotations

import argparse
import http.server
import json
import ssl
from pathlib import Path


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_GET(self) -> None:
        record = {
            "path": self.path,
            "tls_version": self.connection.version(),
        }
        with self.server.record_file.open("a", encoding="utf-8") as output:
            output.write(json.dumps(record, sort_keys=True) + "\n")
        body = b"IRPlayer TLS 1.3 probe\n"
        self.send_response(200)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format: str, *args: object) -> None:
        return


class Server(http.server.ThreadingHTTPServer):
    record_file: Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--cert", type=Path, required=True)
    parser.add_argument("--key", type=Path, required=True)
    parser.add_argument("--record-file", type=Path, required=True)
    args = parser.parse_args()

    server = Server(("127.0.0.1", 0), Handler)
    server.record_file = args.record_file
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.minimum_version = ssl.TLSVersion.TLSv1_3
    context.maximum_version = ssl.TLSVersion.TLSv1_3
    context.load_cert_chain(args.cert, args.key)
    server.socket = context.wrap_socket(server.socket, server_side=True)
    print(f"https://localhost:{server.server_port}/probe", flush=True)
    server.serve_forever()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
