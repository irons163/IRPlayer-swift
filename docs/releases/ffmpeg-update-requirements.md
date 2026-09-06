# Bundled FFmpeg update requirements

Status: required before accepting the redesigned SDK for release.

## Why the current binaries cannot be accepted

The shipped device and simulator headers identify FFmpeg `n6.0`, and the device
binary records an FFmpegKit build date of 20230903. The recorded supplier,
arthenica/ffmpeg-kit, is archived. The supported RTSP/H.264 parser path is
affected by CVE-2023-47342; FFmpeg documents its fix in 6.0.1. There is no
repository source/patch record demonstrating that this fix was backported.

Separately, the wrapper did not enforce TLS certificate verification. The
transport fix must cover initial input and nested HLS I/O, and trusted HTTPS must
continue working. Tests that only inspect an option dictionary are insufficient.

Source review also confirms that FFmpeg copies application raw headers through
HTTP redirects and HLS nested opens, including cross-origin resources, and
accepts HTTPS-to-HTTP redirects. Upgrading the TLS implementation alone does
not prevent Authorization/Cookie/custom-secret disclosure. The transport design
must bind application headers to an origin and reject secure-to-plaintext
downgrades, with any cross-origin credential policy explicitly designed.

## Candidate and compatibility work

The official release page lists FFmpeg 6.1.6 (2026-06-20), retaining the current
major ABI families: avcodec/avformat 60, avutil 58, swresample 4, and swscale 7.
It is a candidate for reducing migration scope while incorporating the current
6.1 branch fixes, not an assertion that every security issue is resolved.
Compare its advisories and enabled features before choosing the final version.

The official annotated `n6.1.6` tag resolves to commit
`f1e3a2bf7a2f2cde936d1ed97f09a26853d20125`; GitHub reports the tag signature
as verified/valid. An isolated source checkout for configuration review is at
`/tmp/irplayer-ffmpeg-review.OG97zp/source` (not a replacement artifact).

The current GnuTLS binary failed a trusted public HTTPS HLS integration probe
with `tls_verify=1` on the iOS 26.4 simulator. The replacement candidate uses
GnuTLS 3.8.13 for TLS (preserving TLS 1.3) and Apple SecTrust for default
system-root/hostname verification, with a separate fail-closed explicit-CA
path. SecureTransport was evaluated but its TLS 1.2 ceiling does not preserve
the previous capability. Merely adding the option to the current binary
is not an acceptable fix. See the
[transport design](../superpowers/specs/2026-09-06-secure-ffmpeg-transport-design.md).

Build replacement artifacts from authenticated upstream source in an isolated
location before replacing any bundled framework. The repository's ThirdParty
instructions prohibit unrequested third-party edits and prohibit rebuilding
these binaries in CI; routine acceptance should consume reviewed artifacts.

## Acceptance evidence for a replacement

- Record upstream source version, immutable commit, archive signature or other
  authenticated provenance, build toolchain, configure flags and artifact hashes.
- Account for all linked libraries: avcodec, avformat, avutil, swresample,
  swscale, and any embedded crypto/TLS dependencies with their notices.
- Preserve iOS device arm64 and simulator arm64/x86_64 support. Inventory the
  existing Catalyst slices and explicitly document any distribution change.
- Compare codec, demuxer and protocol inventories with the prior build,
  including RTSP, RTMP, HTTP(S), HLS, local files, software decode and
  VideoToolbox. Do not silently remove a supported input path.
- Verify trusted HTTPS succeeds; untrusted certificates and hostname mismatch
  fail; HLS segment and key requests enforce the same checks. Simulator success
  does not prove that a GnuTLS trust store exists on a physical iOS device.
- Verify same-origin headers survive and cross-origin resources do not inherit
  application secrets; reject HTTPS-to-HTTP redirects and nested downgrades.
  Cover both HTTP redirect handling inside a protocol open and HLS segment/key
  opens at the format boundary. `AVFormatContext.io_open` alone does not
  intercept each internal HTTP redirect.
- Run the full framework suite, SwiftPM graph builds, generic device Release
  build, eight playback UI cases, and relevant malformed-stream regressions.
- Review source/patch evidence against current advisories. A passing playback
  suite and a newer version string are not security clearance.

References: [FFmpeg release downloads](https://ffmpeg.org/download.html),
[FFmpeg security advisories](https://ffmpeg.org/security.html),
[RTSP parser fix](https://github.com/FFmpeg/FFmpeg/commit/07e3223dd0213cc5f0b65e98a6e1b1500d09ece0),
[recorded supplier](https://github.com/arthenica/ffmpeg-kit).
