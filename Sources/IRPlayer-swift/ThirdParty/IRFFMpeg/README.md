# Bundled IRFFMpeg binaries

`Libs/` contains the seven FFmpeg n6.1.6 XCFrameworks used by IRPlayer. Each
XCFramework contains an arm64 iOS device slice, an arm64/x86_64 simulator
slice, and an arm64/x86_64 Mac Catalyst slice. The five libraries linked by
the wrapper remain `libavcodec`, `libavformat`, `libavutil`, `libswresample`,
and `libswscale`; `libavdevice` and `libavfilter` are bundled but not linked by
default.

This build uses GnuTLS 3.8.13 with statically linked Nettle/Hogweed 3.10.2 and
GMP 6.3.0. SecureTransport, OpenSSL, mbedTLS, and libtls are disabled. The
reviewed transport patches enable Apple system trust through Security and
CoreFoundation while retaining TLS 1.3, HTTPS, HLS, RTMP, and RTMPE support.

The matching immutable build records, patch copies, configuration logs,
artifact inventories, recipe-role attestations, and license notices are in
`Provenance/ffmpeg-n6.1.6-gnutls-sectrust`. The binary-build recipe,
verification-only recipe, and later metadata-hardening recipe have distinct
recorded roles; the latter two must not be described as having compiled the
bundled binary bytes.

The embedded framework identifiers use the valid reverse-DNS form
`org.irplayer.ffmpeg.n6-1-6.<library>`. This was a bounded post-build plist and
ad-hoc-signature amendment: no FFmpeg object was recompiled and no slice build
fingerprint was restamped. Its before/after code-section, exported-symbol,
dependency, and install-name evidence is recorded separately from the binary
build recipe in the provenance directory.

These binaries are intentionally checked in. CI validates the bundled output
but does not rebuild FFmpeg. Rebuilding or replacing them requires an explicit
dependency-update review using `Scripts/dependencies/build-ffmpeg-6.1.6.sh`.
