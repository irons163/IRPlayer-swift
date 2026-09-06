# Release acceptance and delivery

IRPlayer releases use the same automated acceptance suite for pull requests,
branch builds, and tagged releases. A release is publishable only when every
gate below passes.

## Acceptance gates

The reusable `Acceptance` workflow runs four `macos-26` jobs in parallel,
using the image's Xcode 26 toolchain. The exact Xcode and Swift versions are
recorded in each job's `environment.txt`. Action dependencies are pinned to
commit SHAs and Dependabot proposes weekly updates.

1. `Framework build and tests`
   - validates the Swift package manifest;
   - performs a Release build for a generic iOS device without code signing;
   - runs the complete `IRPlayer-swiftTests` suite on an available iPhone
     simulator;
   - runs TLS 1.3 trust, HTTP/HLS redirect policy, reconnect, cancellation,
     and cookie-scope probes against the XCFrameworks actually bundled in
     `Sources/IRPlayer-swift/ThirdParty/IRFFMpeg/Libs`. Controlled loopback
     fixtures use ephemeral certificates without changing trust stores.
2. `Eight-mode playback UI tests`
   - runs the demo app's eight playback/rendering regression tests;
   - covers AVPlayer normal, VR, VR Box, FFmpeg software and hardware,
     fisheye, panorama, and multi-view playback.
   - uses a 60-second stream-copy repetition of the original six-second fisheye
     clip for UI automation only; DEBUG launch configuration selects it while
     ordinary demo playback retains the original clip. The tests verify its
     duration and reject reaching EOF during sampling. Regeneration and payload
     verification are documented in `Scripts/ci/fisheye-ui-fixture.md`.
3. `Swift package and SDK documentation`
   - builds the SwiftPM iOS device target graph;
   - compiles the complete SwiftPM iOS Simulator test graph;
   - builds the SDK DocC archive with documentation warnings treated as errors;
   - packages the complete DocC archive as `sdk-documentation.tar.gz` for
     artifact upload, preserving Swift symbol filenames containing colons.
     Extract with `tar -xzf sdk-documentation.tar.gz` on macOS to open the
     resulting `.doccarchive` in Xcode. The Ubuntu validation job tests archive
     round-tripping and rejects missing documentation or output overwrites.
4. `Thread Sanitizer`
   - executes the framework tests with Thread Sanitizer enabled, covering
     first-party instrumented code (the bundled prebuilt FFmpeg binaries are
     not instrumented).

An additional Ubuntu job validates every workflow with actionlint and exercises
the tag validator against isolated Git repositories, including annotated tags,
prereleases, commit mismatches, and unmerged commits. It also checks shell
syntax for CI scripts and the isolated dependency build recipes; it does not
rebuild the distributed iOS dependency bundles during acceptance. Source-verifier unit tests,
`go vet` and `govulncheck` also run here. The job separately checks out the
exact pinned FFmpeg n6.1.6 commit, applies the transport patchset, then compiles
and executes focused C regressions extracted from the patched GnuTLS source.
These regressions cover callback cancellation and peer-verification failure
handling with controlled stubs; they do not replace actual TLS handshakes,
Apple system-trust checks or playback acceptance against replacement binaries.
The isolated pkg-config facade's fail-closed tests and dependency provenance
regressions are also required, along with XCFramework probe layout tests and
per-architecture Apple framework dependency verifier tests (including Catalyst's
versioned system framework paths and missing-architecture rejection).
Package integrity tests also require relocatable license checksums and reject
changed, added, or removed framework symlinks, including retargeting to files
with identical contents. These tests run the builder's actual manifest functions
without invoking its build dispatch.
Framework metadata tests exercise the real plist generator for all seven
libraries and three platform families, including valid bundle identifiers.
App-level UI acceptance remains required: framework-only builds do not prove
that iOS will accept the embedded framework metadata.
The provenance tests load the real builder functions and
use tiny fixtures to reject missing markers, source/output tampering and build
input drift; they do not build or authenticate production dependency archives. Finally,
a minimal native FFmpeg build runs `fate-http-origin`, covering 16 canonical
origin cases, and `fate-http-cookie`, exercising cookie storage, serialization
and outbound selection through the patched implementation. This test build
enables HTTP/TCP only and is not a substitute
for TLS-provider or iOS binary validation.

The final `Release acceptance` job fails unless all five jobs succeed. Each macOS
job uploads its logs and available `.xcresult` bundles or DocC archives for
14 days, including failed runs.

Run the complete macOS suite locally:

```bash
Scripts/ci/run-acceptance.sh all
```

Individual modes are `framework`, `transport`, `ui`, `package`, and `sanitizer`.
`framework` includes `transport`; use `transport` alone for a focused rerun.
The transport gate deliberately rejects the old insecure bundles until the
reviewed replacement passes. It does not accept a developer's temporary stage
as a substitute for packaged binaries. Validate release scripts
locally with `bash Scripts/ci/test-release-tag.sh`; workflow validation uses
`go run github.com/rhysd/actionlint/cmd/actionlint@v1.7.12 -shellcheck=`.

To choose a particular installed simulator:

```bash
IRPLAYER_SIMULATOR_ID="<simulator-udid>" Scripts/ci/run-acceptance.sh all
```

## Continuous integration

`.github/workflows/ci.yml` runs acceptance for:

- every pull request targeting `main`;
- every push to `main` or a `codex/**` branch;
- manual runs from the Actions page.

After the first successful run, configure the `main` branch ruleset to require
the final check whose name ends in `Release acceptance`. Also require branches
to be up to date before merging. This makes the workflow an enforced merge
gate instead of an informational check.

## Continuous delivery

`.github/workflows/release.yml` reacts to a pushed version tag. Supported tag
forms include `2.0`, `2.0.1`, `v2.0.1`, and prereleases such as
`2.1.0-rc.1`.

The workflow:

1. rejects malformed tags and tags whose commit is not reachable from `main`;
2. runs the complete reusable acceptance workflow against the tagged commit;
3. creates a GitHub Release only after every gate succeeds, using the reviewed
   `docs/releases/<version>.md` file (with the optional `v` tag prefix removed);
4. marks tags containing a prerelease suffix as prereleases.

The library is distributed through Swift Package Manager, so the immutable Git
tag and GitHub's generated source archives are the release artifacts. No
repository secret is required; the publish job alone receives
`contents: write` permission through `GITHUB_TOKEN`.

Release from an accepted `main` commit:

```bash
git switch main
git pull --ff-only
git tag -a 2.0.1 -m "IRPlayer 2.0.1"
git push origin 2.0.1
```

Do not move or reuse a published version tag. If release acceptance fails, fix
the issue on `main` and create a new version tag.
