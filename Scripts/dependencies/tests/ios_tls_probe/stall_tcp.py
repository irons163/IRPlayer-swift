#!/usr/bin/env python3
"""Accept TCP connections without completing TLS, for interrupt testing."""

from __future__ import annotations

import socket
import threading
import time


def hold(connection: socket.socket) -> None:
    with connection:
        time.sleep(60)


def main() -> int:
    with socket.socket() as listener:
        listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        listener.bind(("127.0.0.1", 0))
        listener.listen()
        print(f"https://127.0.0.1:{listener.getsockname()[1]}/probe", flush=True)
        while True:
            connection, _ = listener.accept()
            threading.Thread(target=hold, args=(connection,), daemon=True).start()


if __name__ == "__main__":
    raise SystemExit(main())
