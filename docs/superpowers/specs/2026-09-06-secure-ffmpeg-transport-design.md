# Secure FFmpeg transport for the redesigned SDK

## Objective

Close the confirmed bundled-parser, TLS-verification and application-header
forwarding findings without removing supported playback modes or rebuilding
third-party binaries during normal CI acceptance.

## Evidence and scope

The current n6.0 artifacts lack provenance for the RTSP/H.264 fix identified
as CVE-2023-47342. Enabling TLS verification in the existing GnuTLS build
failed a trusted HTTPS HLS probe. Upstream HTTP redirects and HLS resource
opens can forward raw application headers to another origin or plaintext URL.

Use signed FFmpeg n6.1.6 commit
`f1e3a2bf7a2f2cde936d1ed97f09a26853d20125` as the replacement candidate,
with an updated GnuTLS provider, Apple SecTrust verification, and the existing
GMP/RTMPE capability. Build all
seven existing framework families in isolation; integration requires a
consistent set of headers, binaries, install names, dependencies and notices.

Provider compatibility is not yet approved: Apple's SecureTransport API only
supports TLS through 1.2, while the old bundle includes GnuTLS 3.7.9 and TLS
1.3 support. Preserve the completed arm64 SecureTransport builds as comparison
prototypes, not final replacement candidates. The revised candidate uses
GnuTLS 3.8.13 for the handshake and SecTrust for system-root and hostname
verification before any application I/O. Keep explicit custom-CA validation
fail-closed, with no fallback from failed system trust to an unrelated store.
Successful TLS 1.2 trust tests alone do not prove an equivalent replacement. See
[Apple's SecureTransport documentation](https://developer.apple.com/documentation/security/secure-transport).

## Transport invariants

- Certificate and hostname verification are enabled by default. A valid
  system-trusted endpoint works; untrusted and mismatched certificates fail.
- Application-provided raw headers belong to the original canonical origin:
  scheme, case-normalized host and effective port. Default ports and IPv6
  parsing must be consistent; malformed origins fail closed.
- Same-origin requests retain those headers. Cross-origin HTTPS requests may
  proceed but receive none of the application headers, including arbitrary
  custom-secret fields rather than only Authorization and Cookie.
- Automatically stored Set-Cookie values retain their response-host scope
  across redirects, reconnects and nested inputs. Host-only cookies require
  an exact hostname match but remain valid across ports on that hostname.
  Domain cookies require a valid response-host relationship and a complete
  DNS-label boundary, not an arbitrary suffix match.
- HTTPS-to-HTTP redirects and HTTPS-source HLS resource downgrades fail before
  a plaintext request is emitted.
- The same rules hold for cached redirects, retries, reconnects, persistent
  requests, nested playlists, segments, keys and encrypted segment wrappers.
- Preserve FFmpeg interrupt/cancellation behavior and existing protocol limits.
- Do not introduce a public insecure bypass or silently remove redirect,
  encrypted HLS, keepalive, RTSP, RTMP or RTMPE support.

## Ownership and implementation boundary

Prefer a small, reviewable patchset at FFmpeg's HTTP request owner, where every
redirect and reused connection becomes a request. Immutable header-origin and
secure-transport requirements must survive option copying into nested inputs.
An `AVFormatContext.io_open` callback alone is insufficient: HTTP redirects
and HLS persistent reuse can happen below or around that boundary.

Keep the first-party Swift facade and public API stable. Add a Swift boundary
only if the patch implementation proves it necessary, with explicit resource
lifetime and close/interrupt tests. Do not replace the entire HTTP client with
custom AVIO/URLSession as an incidental release-preparation change.

## Build and acceptance

Record authenticated source, patch hashes, toolchain, configure arguments,
dependency versions, licenses and hashes for every output slice. Preserve
device arm64, simulator arm64/x86_64 and Catalyst arm64/x86_64. Existing
bundles remain untouched while the isolated candidate is being validated.

Acceptance requires canonical-origin unit tests and controlled wire-level
tests for each invariant, plus SwiftPM graphs, device Release build, full
framework tests, eight playback UI cases and sanitizer checks. A newer version
string, dictionary option test, or simulator-only trust result cannot replace
the relevant security evidence. Physical-device trust and playback must be
recorded separately from simulator results.

## Release constraints

The already-published `2.0` tag remains immutable. The redesigned API needs a
new version decision. Known security gaps remain release blockers until the
replacement and transport tests pass; documentation warnings alone do not
close them.
