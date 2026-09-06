# Isolated FFmpeg 6.1.6 GnuTLS/SecTrust candidate build

## Status and boundary

Scripts/dependencies/build-ffmpeg-6.1.6.sh builds a GnuTLS 3.8.13 candidate
that delegates system-root and hostname trust evaluation to SecTrust. It never
writes the checked-in ThirdParty bundles, changes public SDK APIs, or makes a
release claim. A bootstrap build made with --without-transport-patches proves
toolchain compatibility only; it is explicitly ineligible for security
acceptance.

The final candidate must use the reviewed transport patch set and pass the
wire-level TLS, redirect, and HLS-header tests described by the secure
transport design and plan.

## Pinned inputs

- FFmpeg tag: n6.1.6
- FFmpeg commit: f1e3a2bf7a2f2cde936d1ed97f09a26853d20125
- FFmpeg origin: https://github.com/FFmpeg/FFmpeg.git
- GMP: 6.3.0, SHA-256
  a3c2b80201b89e68616f4ad30bc66aee4927c3ce50e33929ca819d5c43538898
- Nettle: 3.10.2, SHA-256
  fe9ff51cb1f2abb5e65a6b8c10a92da0ab5ab6eaf26e7fc2b675c45f1fb519b5
- GnuTLS: 3.8.13, SHA-256
  ffed8ec1bf09c2426d4f14aae377de4753b53e537d685e604e99a8b16ca9c97e
- NASM: 2.16.03, SHA-256
  1412a1c760bbd05db026b6c0d1657affd6631cd0a63cddb6f73cc6d4aa616148

The builder downloads GMP, Nettle, and GnuTLS detached signatures and records
their hashes. A downloaded signature is not represented as verified. The
separate GnuTLS and GMP authentication records are in
`docs/security/source-verification.md`, and the Nettle record is in
`docs/security/nettle-source-verification.md`. The builder records those
external successful proofs by reference but does not rerun them as an
automatic gate. NASM's release directory
publishes the source archive and git.id, but no detached signature; the recipe
records that limitation together with its pinned archive SHA-256 and published
git ID.

Before a candidate is accepted, verify the FFmpeg signed tag with a trusted
FFmpeg signing key outside the builder. The source checkout must be clean and
must resolve both the tag and HEAD to the pinned commit.

## Reproducible isolated setup

Use a new disposable directory for every different patch set, configuration,
or toolchain. Do not reuse a directory after an incompatible fingerprint
failure.

Each installed GMP, Nettle/Hogweed, and GnuTLS prefix has its own fail-closed
build marker. The marker fingerprints the pinned source archive, dependency
recipe, target triple, SDK identity, compiler/tool paths and versions,
configure inputs, and upstream static-archive hashes. It also records a stable
manifest of every installed regular file and symlink outside the marker itself,
including static archives, headers, pkg-config metadata, and generated tools.
Reuse is allowed only when the complete marker, current inputs, and the full
installed prefix all match. A pre-existing archive without that marker is
rejected with an instruction to use a fresh isolated root; the builder never
retroactively labels a manual build as reproducible.

~~~sh
BUILD_ROOT=$(mktemp -d /tmp/irplayer-ffmpeg-review.XXXXXX)
git clone --branch n6.1.6 --single-branch --depth 1 \
  https://github.com/FFmpeg/FFmpeg.git "$BUILD_ROOT/source"
git -C "$BUILD_ROOT/source" rev-parse HEAD
git -C "$BUILD_ROOT/source" status --porcelain

Scripts/dependencies/build-ffmpeg-6.1.6.sh \
  --work-root "$BUILD_ROOT" prepare
IRPLAYER_FFMPEG_JOBS=2 Scripts/dependencies/build-ffmpeg-6.1.6.sh \
  --work-root "$BUILD_ROOT" build ios-device-arm64 ios-simulator-arm64
Scripts/dependencies/build-ffmpeg-6.1.6.sh \
  --work-root "$BUILD_ROOT" package-minimal
~~~

The script canonicalizes the work root and only accepts a path under the
isolated /tmp/irplayer-ffmpeg-review.* namespace (including macOS's canonical
/private/tmp form). It performs no automatic deletion.

Once the transport patch set is complete, create a new root and run the full
matrix:

~~~sh
IRPLAYER_FFMPEG_JOBS=2 Scripts/dependencies/build-ffmpeg-6.1.6.sh \
  --work-root "$BUILD_ROOT" all
~~~

For early compiler/bootstrap investigation only, append
--without-transport-patches. That option is recorded in patch metadata and
must never be used for a release candidate.

## Configuration and compatibility

The candidate retains the current seven library families:

- libavutil
- libswresample
- libswscale
- libavcodec
- libavformat
- libavfilter
- libavdevice

It retains arm64 iOS device, arm64/x86_64 simulator, and arm64/x86_64 Catalyst
slices. The wrapper still dynamically links its five public dependencies:
libavcodec, libavformat, libavutil, libswresample, and libswscale.

The final transport configuration enables GnuTLS and disables SecureTransport,
OpenSSL, mbedTLS, and libtls. GnuTLS is linked statically with Nettle, Hogweed,
and GMP; the patched GnuTLS transport uses Security and CoreFoundation for
SecTrust evaluation. GnuTLS retains TLS 1.3 protocol support while GMP also
keeps RTMP and RTMPE on their upstream dependency path. HTTP, HTTPS, HLS,
RTSP, RTMP, RTMPE, ffrtmpcrypt, file, AudioToolbox, VideoToolbox, and
AVFoundation are asserted in generated configuration headers.

Every target builds its own static GMP, Nettle/Hogweed, and GnuTLS archives.
GMP keeps its assembly implementation and is configured as PIC. Immediately
after each GMP build (and before downstream reuse), the recipe force-loads the
entire static archive into a target dylib; this catches non-PIC assembly text
relocations before Nettle or FFmpeg is built and records the probe hash and
Mach-O build-version evidence outside the dependency prefix.
GnuTLS uses its bundled libtasn1 4.20.0 and unistring implementations and
disables optional host dependencies. A separately downloaded libtasn1 archive
is not a build input. The bundled code is covered by the authenticated GnuTLS
archive. The copied license inventory includes the GnuTLS root licenses,
README and AUTHORS notice, plus the bundled x86, crau, inih, and extras license
files; file-level notices remain available in the authenticated source tree.
`isolated-pkg-config.sh` exposes only
the pinned target prefixes; neither GnuTLS nor FFmpeg may resolve a host
Homebrew library. It rejects unknown or multiple-package requests,
unsatisfied versions, unsupported query forms, and missing transitive target
prefixes instead of returning partial link flags.

Xcode 26 rejects FFmpeg 6.1's new scale_vt filter at the SDK's iOS 15
deployment target because it calls unguarded iOS 16 VTPixelTransferSession
APIs. The previous n6.0 artifacts do not contain that filter. The recipe
therefore disables only scale_vt; it keeps VideoToolbox and all existing
scalers enabled. Raising the iOS deployment floor or suppressing the
availability diagnostic is not an acceptable workaround.

FFmpeg 6.1 also treats Mac Catalyst as iPhone-family code when creating a
VideoToolbox pixel buffer, which selects an OpenGLES compatibility key that
the Catalyst SDK explicitly marks unavailable. The reviewed Catalyst patch
keeps the iOS OpenGLES and macOS OpenGL branches intact and selects the
cross-platform Metal compatibility key only for Catalyst; VideoToolbox itself
remains enabled.

x86_64 slices use an isolated source-built NASM rather than disabling assembly.
This avoids silently regressing the existing optimized x86_64 behavior.

## Recorded evidence

Each build root records:

- source commit/tree/origin, tool versions, SDK paths, configure inputs, and
  per-slice configuration logs;
- source archive, signature, license, GMP, Nettle, GnuTLS, and NASM archive
  hashes;
- lexicographically ordered transport patch hashes, immutable patch copies,
  and each slice's patch/fingerprint identity;
- installed dylib hashes, framework/XCFramework hashes, architecture and
  install-name checks, Security and CoreFoundation linkage, and a public
  Objective-C wrapper link probe.

## Current local integration evidence

The 2026-09-06 five-slice candidate under
`/private/tmp/irplayer-ffmpeg-review.final5.X92f0K` was built from immutable
patch manifest
`b4483dd4e56d70bbfd432621a9613616316c59941aa2c1b600abf1fda1b0398d`.
All five device, simulator, and Catalyst FFmpeg slices were compiled and
packaged. Four targets reused dependency prefixes only after the normal input
fingerprint and complete installed-prefix manifest checks passed; Catalyst
x86_64 built GMP, Nettle/Hogweed, and GnuTLS freshly. A post-build audit using
the exact original recipe revalidated every dependency and FFmpeg fingerprint
for all five targets.

The build recipe initially used an unversioned-only Security/CoreFoundation
path matcher. It correctly built the binaries but false-failed final package
verification because Catalyst records the same Apple system frameworks through
`Versions/A`. The package metadata therefore distinguishes the original build
recipe (SHA-256
`1ed7d15432a1a87920f93ca0997c4968763e43a96163b69432aed1feb987d808`)
from the corrected verification-only recipe. The corrected check requires each
architecture to contain either the exact unversioned system framework path or
its exact `Versions/A` form; it does not accept a match supplied by only one
member of a universal binary. Verification and checksum finalization did not
rerun `prepare`, rebuild a slice, or rewrite the original slice inputs. Both
recipe versions, the verification-only delta, validation logs, and their
roles are included in package metadata.

Before that successful finalization, the first attempt to run the archived
recipe as an audit harness used an incorrect source-truncation expression and
accidentally reached the recipe's normal `prepare` dispatch. It changed only
the active global patch manifest, then stopped at the existing device FFmpeg
fingerprint mismatch before compilation. The five stage binaries and packaged
binaries were not changed. The active metadata was restored byte-for-byte from
the complete-build evidence copy made before editing the verifier; the restored
and archived metadata tree manifests both have SHA-256
`a59828702c38e4588b8d6f48c46863df20b8f8e164a09069972dbdfebf959ce3`.
The incident record and restore manifests are under
`/private/tmp/irplayer-ffmpeg-review.final5.X92f0K/evidence/complete-patchset-built-with-pre-verifier-fix-20260906`.
The failed stdout was overwritten when the later successful audit reused its
log path, so the incident record states that limitation rather than presenting
the successful log as the failed one.

A reusable, non-dispatching replay harness is preserved at
`/private/tmp/irplayer-ffmpeg-review.final5.X92f0K/evidence/reverification-harness/reverify-final5.sh`.
On 2026-09-06 it exited zero after rechecking, without `prepare` or build
fingerprint restamping, all five targets' original dependency input/full-prefix
and FFmpeg fingerprints, all recorded stage dylib hashes, the existing package
checksum manifest, and the corrected three-family package verifier. Its new
transcript and attestation are `reverification-transcript.log` and
`reverification-attestation.txt` in the same directory. They are explicitly
new re-verification evidence and do not reconstruct the historically missing
failed-harness stdout. Copies of the package manifests that existed before any
later additive attestation are under `prior-package-manifests`.

The subsequent metadata-only hardening used recipe SHA-256
`92bc9f0a19fce991dae78d8532352516679c96a0bc6697c000adf3d856288765`.
That recipe did not compile the existing binaries: its recorded role is limited
to portable license checksums plus complete regular-file and raw symlink-target
inventories. The historical build recipe and corrected-verifier recipe remain
unchanged in package metadata. The resealed package contains 610 regular-file
records, 28 symlink records, and 18 package-relative license records. Its
regular-file, symlink, and license manifest SHA-256 values are respectively
`965b4f91d3321b6614c09888b0acbcd496e8e149d99c00612510db3d18154ee9`,
`444dbae42698a87362eda48e0ec28f64a4aa582a388cfe957e40a46d001b466f`,
and `f31d5651778f51e17f791d6f062c59da5207fa99cc79089106ef53eb02ec0ccd`.
Before and after inventories prove all 481 XCFramework regular files and 28
XCFramework symlinks are identical; those records are under
`/private/tmp/irplayer-ffmpeg-review.final5.X92f0K/evidence/metadata-hardening-finalization-20260906`.
The entire previous package metadata is preserved separately under
`evidence/pre-metadata-hardening-package-metadata-20260906`.

Xcode's embedded-framework validation subsequently rejected the original
underscore-containing `CFBundleIdentifier` values. A separate candidate copied
from the sealed package was amended to use
`org.irplayer.ffmpeg.n6-1-6.<library>` for all 21 frameworks and then ad-hoc
signed. This was metadata/signature-only work: it did not invoke `prepare`,
compile or link FFmpeg, or restamp a slice fingerprint. The signed Mach-O hashes
changed for all 21 binaries, as expected; normalized per-architecture hashes of
`__TEXT,__text`, exported symbols, linked dependencies, and install names were
identical before and after (both evidence inventories SHA-256
`9b8745652db1a92a7290bcd04c42e0207954ee190861248158232fb0de506d0e`).
The original package remains unchanged. The corrected package contains 620
regular-file and 28 symlink records and has manifest SHA-256
`77ae5f243a7b979d460e4a9454ddec7d433b708f603b9a9b77de3fc1b5485de8`.
Its amendment attestation, historical pre-amendment manifest, exact recipe
snapshot, commands, signature validation, and identity inventories are under
`metadata/bundle-id-amendment`. The corrected recipe snapshot records only the
later identifier-generator fix; the historical binary-build recipe remains the
record of what compiled and linked the binaries.

The read-only evidence can be replayed locally without invoking the recipe CLI
dispatcher:

~~~sh
/private/tmp/irplayer-ffmpeg-review.final5.X92f0K/evidence/reverification-harness/reverify-final5.sh
~~~

Against the packaged universal arm64/x86_64 simulator libavformat (SHA-256
`c3bb02ecb4b5333fa325816bca36aede6267fe8ce356c4bcf3b18ba6ff9698aa`),
the TLS 1.3/default verification/public-trust, HTTP and nested/encrypted HLS,
redirect-cookie scoping, reconnect, parent-header, and deadline regressions
passed. Those simulator runs provide executable transport-policy evidence;
they do not replace device and Catalyst runtime coverage.

After explicit dependency-upgrade approval, the seven sealed candidate
XCFrameworks were installed into
`Sources/IRPlayer-swift/ThirdParty/IRFFMpeg/Libs`. The installed tree matches
the candidate across all 481 regular files and 28 raw symlink targets; the
existing Objective-C wrapper and its two public wrapper files were preserved.
Repository provenance and license material is under
`Sources/IRPlayer-swift/ThirdParty/IRFFMpeg/Provenance/ffmpeg-n6.1.6-gnutls-sectrust`.
The previous seven bundles remain recoverable locally at
`/private/tmp/irplayer-ffmpeg-bundles-backup.jVMtRD/Libs` while acceptance is
in progress. This was an explicitly authorized integration step, not an action
performed by the isolated builder, and CI must validate rather than rebuild the
checked-in binaries.

The earlier `/private/tmp/irplayer-ffmpeg-review.JSsLCB` arm64 integration
build remains comparison evidence only. Its device dependency archives were
manual and its earlier GnuTLS configuration recorded an empty `--build`
value; it must not be presented as the reproducible final build.

Final GnuTLS/SecTrust package output is under:

  BUILD_ROOT/artifacts/ffmpeg-n6.1.6-gnutls-sectrust

The arm64 GnuTLS bootstrap output is under:

  BUILD_ROOT/artifacts/ffmpeg-n6.1.6-gnutls-unpatched-arm64-bootstrap

After applying the transport patches, an arm64-only candidate package is under:

  BUILD_ROOT/artifacts/ffmpeg-n6.1.6-gnutls-sectrust-arm64-prototype

Earlier `ffmpeg-n6.1.6-securetransport*` directories are comparison prototypes
only. They do not preserve TLS 1.3 and are ineligible for final acceptance.

FFmpeg's version3 configuration and the GMP, Nettle, and GnuTLS dependency
licenses require the copied notices and a downstream license review before
distribution.
