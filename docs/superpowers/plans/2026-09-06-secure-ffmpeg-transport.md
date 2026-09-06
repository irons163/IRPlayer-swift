# Secure FFmpeg transport implementation plan

Design: [secure transport](../specs/2026-09-06-secure-ffmpeg-transport-design.md).

- [x] Verify current binary version/configuration and reachable parser finding.
- [x] Probe trusted HTTPS with explicit verification; reject the regressing
  source-only patch.
- [x] Verify signed n6.1.6 tag and create an isolated source checkout.
- [x] Establish redirect, header and HLS persistent-I/O interception gaps.
- [ ] Implement a reproducible isolated GnuTLS/GMP build recipe and
  version/hash/license provenance.
  - Apply the immutable patch snapshot whose hashes are recorded, including
    newly added files, and ship the patch manifest and sources with provenance.
  - Generate relative artifact checksums after verification outputs are final;
    exclude the checksum file itself and validate with `shasum -c`.
    Bind framework symlink topology as well as regular-file contents; license
    checksums must remain verifiable after moving the package. Preserve exact
    commands and outcomes for verification-only provenance amendments.
  - Verify platform-specific framework metadata and Catalyst framework search
    paths rather than relying only on architecture names.
  - Dependency reuse must compare completed input/output fingerprints, not
    merely archive existence, architecture or a saved config log. Include
    source hashes, target/SDK/toolchain, recipe/configuration and prerequisite
    archive hashes. Output manifests must cover the installed prefix's regular
    files and symlink targets, including headers and pkg-config metadata, not
    only static archives. Reject missing or mismatched provenance instead of
    retrospectively certifying a manually built archive.
- [x] Build prototype device/simulator artifacts, then complete all existing
  architecture/platform slices.
- [x] Implement and review the origin/redirect/TLS patchset with focused tests.
  - Preserve the HTTPS requirement across reused-request option updates even
    when no custom headers were supplied; test an HTTP playlist parent whose
    HTTPS child subsequently attempts plaintext reuse.
  - Reject cross-scheme connection reuse even without a header-origin policy,
    and keep credentials and URL query tokens out of new policy diagnostics.
  - Treat a transport-policy denial as terminal across HLS new-connection
    fallback; retrying must not restore weaker parent options after HTTPS
    reuse was refused.
- [x] Integrate the patchset into the isolated artifact build and prove
  trusted/untrusted TLS, headers and downgrade behavior over controlled I/O.
  - Preserve TLS 1.3 with updated GnuTLS and Apple SecTrust verification;
    SecureTransport arm64 builds remain comparison prototypes only.
- [x] Compare protocol/codec/slice inventories and load commands with the
  current bundles; resolve compatibility differences explicitly.
- [x] Integrate a complete reviewed replacement set and update provenance/docs.
  - User authorized the upgrade. Corrected bundle IDs after app-embedding
    validation rejected underscores; keep metadata/signature amendments distinct
    from the original binary compilation. Full acceptance remains the next gate.
- [ ] Run all acceptance modes and verify current candidate CI.
- [ ] Verify physical-device trust/playback or record the precise outstanding
  device requirement without claiming simulator evidence proves it.
- [ ] Resolve new release version, metadata and notes; preserve the published
  2.0 tag and enforce required merge/release gates.

Concurrent ownership: the build agent owns build scripts and isolated build
outputs; the transport agent owns patches 0001/0002 and
`Scripts/dependencies/tests/`; main owns patch 0003 for GnuTLS/SecTrust in a
separate isolated source checkout, plus design/integration; the acceptance
agent owns test execution. Coordinate source patch application and heavy
builds so no running build observes a partly edited upstream source tree.
