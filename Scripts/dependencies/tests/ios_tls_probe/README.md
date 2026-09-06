# iOS Simulator TLS probe

This probe links directly to an isolated FFmpeg candidate or packaged SDK
XCFrameworks. Its default
`--operation avio` calls `avio_open2`, `avio_read`, and `avio_closep` inside a
booted iOS Simulator. `--operation demux` instead calls
`avformat_open_input`, `avformat_find_stream_info`, and `av_read_frame`; a
demux success requires a positive packet count.
The default probe mode is `--verification forced`, which supplies
`tls_verify=1`. Use `--verification default` to omit the option completely and
test the candidate's compiled default. Neither mode can supply `tls_verify=0`.

Every runner requires the candidate stage explicitly. Either pass
`--stage /path/to/ios-simulator-arm64` or set it once for all commands:

```bash
export IRPLAYER_FFMPEG_SIM_STAGE=/path/to/ios-simulator-arm64
```

The stage must contain `ffmpeg/include` and `ffmpeg/lib`, or be a directory
containing the five SDK XCFrameworks (`libavformat`, `libavcodec`, `libavutil`,
`libswresample`, `libswscale`). Packaged mode selects the arm64 iOS Simulator
slice from each Info.plist and verifies its Mach-O platform before linking.
It copies frameworks into a disposable runtime directory without modifying
the original binaries or install names.

`Scripts/ci/run-acceptance.sh transport` always tests the repository's bundled
XCFrameworks. This gate also runs as part of `framework` and `all`, including
on GitHub Actions; logs identify the tested binary paths and SHA-256 hashes.

Run against a system-trusted endpoint:

```bash
python3 Scripts/dependencies/tests/ios_tls_probe/run_probe.py \
  https://example.com/ --stage "$IRPLAYER_FFMPEG_SIM_STAGE" --expect success
```

Use `--ca-file CA.pem` for an explicit private CA. `--deadline-ms` controls
both FFmpeg's I/O timeout and its interrupt callback deadline. Results contain
each FFmpeg return code, positive bytes read, callback state, and whether an
actual `AVERROR_EXIT` propagated. The runner also applies a host-side watchdog,
verifies each resolved dylib is `IOSSIMULATOR`, and prints its source path and
SHA-256 digest.

Run the controlled TLS 1.3 regression with:

```bash
python3 Scripts/dependencies/tests/ios_tls_probe/run_tls13_regression.py \
  --stage "$IRPLAYER_FFMPEG_SIM_STAGE"
```

Pass `--verification default` to run the same positive, untrusted, and
hostname-mismatch cases without supplying any `tls_verify` option.

It generates a short-lived CA and localhost certificate in a disposable
directory, then starts `loopback_tls13.py`. The fixture permits only TLS 1.3
and records an HTTP request only after the handshake succeeds. The regression
requires the explicit-CA probe to succeed, requires the same server without
the CA to fail, requires an explicit-CA hostname mismatch to fail, and asserts
that both rejected handshakes emitted no HTTP request. No global or Simulator
trust store is changed.

Verify deadline cancellation against a server that accepts TCP but never
completes its TLS handshake:

```bash
python3 Scripts/dependencies/tests/ios_tls_probe/run_deadline_regression.py \
  --stage "$IRPLAYER_FFMPEG_SIM_STAGE"
```

This passes only when the interrupt callback fires and FFmpeg returns the
actual `AVERROR_EXIT`; an EOF/EIO translation or host-watchdog kill fails.

Run the AVIO HTTP redirect wire-policy regression with:

```bash
python3 Scripts/dependencies/tests/ios_tls_probe/run_http_regression.py \
  --stage "$IRPLAYER_FFMPEG_SIM_STAGE"
```

It uses default verification plus an explicit private CA and requires positive
AVIO reads after same-origin and foreign-origin HTTPS redirects. All recorded
requests are checked: raw caller headers must survive the same-origin redirect
and must be absent at the foreign origin. The HTTPS-to-HTTP case requires the
precise HTTPS policy-denial log, a verified HTTPS root request, and zero
plaintext requests.

Run the real HLS demux and wire-policy regression with:

```bash
python3 Scripts/dependencies/tests/ios_tls_probe/run_hls_regression.py \
  --stage "$IRPLAYER_FFMPEG_SIM_STAGE"
```

This always uses `--verification default`, so no `tls_verify` option is
supplied, while an explicit private CA is passed through `ca_file`. It verifies
positive packet reads from a trusted HTTPS playlist; successful AES-128-CBC
decryption with a foreign-origin HTTPS key and segment; stripping of raw caller
headers from both foreign requests; a foreign HTTPS media playlist and segment
that remain header-free while producing packets; rejection of a plaintext media
playlist referenced by an HTTPS master; and rejection of plaintext HLS segment
and key URLs before the HTTP fixture receives a request. The fixture server,
MPEG-TS sample, and sensitive-header list are imported read-only from
`../test_transport_security.py`.

The runner requires a booted arm64 Simulator and copies candidate dylibs plus
an optional CA into its own `mktemp` directory.

Run cached reconnect and HLS keepalive policy regressions with:

```bash
python3 Scripts/dependencies/tests/ios_tls_probe/run_reconnect_regression.py \
  --stage "$IRPLAYER_FFMPEG_SIM_STAGE"
```

The cached-redirect case completes a positive HTTPS read, forces an EOF
reconnect through a cached permanent redirect, and then verifies that a
plaintext redirect is denied before any HTTP request. The HLS case reads
positive packets from its first segment, verifies the second segment reuses
the same HTTPS connection, and requires its plaintext redirect denial to be
terminal. Both cases require the precise policy-denial log and wire-level zero
plaintext hits.

The same runner also includes the inverse nesting case: a controlled local HTTP
playlist opens two HTTPS child segments on one persistent connection. The first
must yield packets, while the second child's HTTP redirect must still be denied
without retry or a plaintext request. `--allow-http-root` permits controlled
HTTP-root fixtures; HTTPS remains the default root requirement and TLS verification
is never disabled.

Run automatic-cookie scope regressions with:

```bash
python3 Scripts/dependencies/tests/ios_tls_probe/run_cookie_regression.py \
  --stage "$IRPLAYER_FFMPEG_SIM_STAGE"
```

The ten cases require actual positive AVIO reads and inspect every recorded
destination request. They cover explicit Path and path-boundary separation,
default Path, relative-Path fallback, legitimate semicolon paths, default-path
attribute injection, HTTP Secure selection with a non-Secure positive control,
same-host cross-port preservation, and host-only cross-host rejection. HTTPS
cases use a dual-SAN localhost/IP certificate and explicit private CA with
default verification, so hostname rejection cannot masquerade as cookie
isolation. The two HTTP cases explicitly permit only their controlled root.

The source-level `fate-http-cookie` regression additionally exercises Domain
label boundaries, IPv4/IPv6 scoping, case-sensitive path selection, forged
private metadata, and invalid encoded metadata through the real jar functions.
These tests do not establish browser cookie-store equivalence: FFmpeg still
lacks public-suffix enforcement, multi-domain/path storage of same-name cookies,
and complete Max-Age/expired-cookie deletion semantics.
