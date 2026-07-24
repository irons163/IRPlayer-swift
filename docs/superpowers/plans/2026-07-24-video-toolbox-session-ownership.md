# VideoToolbox Session Ownership Implementation Plan

**Design:** See
`docs/superpowers/specs/2026-07-24-video-toolbox-session-ownership-design.md`.

## Phase 1: Lifecycle Owner

- [x] Add the generic `IRFFVideoToolBoxSession<Resource>` owner.
- [x] Model idle, setting-up, active, resetting, closing, and closed phases.
- [x] Add generation-fenced setup tickets.
- [x] Add resource leases and draining reset/close behavior.
- [x] Add synchronized callback state.

## Phase 2: VideoToolbox Integration

- [x] Replace facade-owned resource and callback fields with one complete
  generation.
- [x] Serialize setup, decode, reset, and close.
- [x] Retain callback context per generation and release it after session
  invalidation.
- [x] Route packet submission and image access through active resource leases.
- [x] Make flush repeatable and close terminal.
- [x] Preserve synchronous decode flags and software fallback behavior.

## Phase 3: Policy Consolidation

- [x] Move H.264 validation, NAL parsing, converted-block ownership, and format
  description construction beside `IRFFVideoToolBox`.
- [x] Remove facade-to-policy forwarding.
- [x] Remove `IRFFVideoToolBoxPolicy.swift`.
- [x] Update tests to assert domain behavior rather than wrapper equivalence.

## Phase 4: Tests

- [x] Add phase, duplicate setup, stale ticket, reset, terminal close, and
  exactly-once drain tests.
- [x] Add lease-versus-drain concurrency coverage.
- [x] Add callback snapshot and concurrent reset/publish coverage.
- [x] Update facade tests for diagnostics and retained callback context.
- [x] Add concurrent invalid-setup, flush, and image-access stress coverage.

## Phase 5: Verification

- [x] Run focused VideoToolbox/session tests.
- [x] Run the focused tests with Thread Sanitizer.
- [x] Run affected video-decoder and FF-decoder integration tests.
- [x] Run the full iOS Simulator suite.
- [x] Run a generic iOS device build.
- [x] Run package/project metadata and whitespace validation.
- [x] Update FFmpeg guidance and the 2.0 completion audit.
- [x] Create a focused commit.

## Verification Record

Completed on 2026-07-24:

- VideoToolbox/session focused suites: 31 passed, 0 failed.
- Thread Sanitizer VideoToolbox/session suites: 31 passed, 0 failed, no race
  diagnostics.
- VideoToolbox, video-decoder, and FF-decoder integration suites: 69 passed,
  0 failed.
- Full iOS Simulator suite: 1113 passed, 0 failed, 0 skipped.
- Generic iOS device build: passed.
- Swift package resolution, package dump/description, Xcode project listing,
  project property-list validation, and `git diff --check`: passed.
- Build warnings remain confined to bundled FFmpeg headers and Xcode's
  AppIntents metadata processor.
