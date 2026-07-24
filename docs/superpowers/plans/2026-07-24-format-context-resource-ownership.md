# Format Context Resource Ownership Implementation Plan

**Design:** See
`docs/superpowers/specs/2026-07-24-format-context-resource-ownership-design.md`.

## Phase 1: Resource Generation

- [x] Add a complete format/codec resource generation.
- [x] Make generation teardown idempotent.
- [x] Free every codec context with `avcodec_free_context`.
- [x] Close the input context before callback-reference release.
- [x] Build locally and publish only after setup succeeds.

## Phase 2: Lifecycle And Callback

- [x] Add idle, opening, active, failed, closing, and closed phases.
- [x] Serialize setup, read, seek, track replacement, and destruction.
- [x] Add a separately retained synchronized interrupt state.
- [x] Request interruption before destroy waits for the operation gate.
- [x] Make destroy terminal and repeatable.
- [x] Expose coherent diagnostics for tests.

## Phase 3: Semantics Consolidation

- [x] Move pure timing, format, track, and selection behavior beside the
  `IRFFFormatContext` domain.
- [x] Remove facade-to-policy forwarding.
- [x] Remove `IRFFFormatContextPolicy.swift`.
- [x] Preserve existing successful single-track setup behavior.

## Phase 4: Tests

- [x] Replace wrapper-equivalence assertions with domain behavior assertions.
- [x] Add generation close and exact-once callback-release coverage.
- [x] Add interrupt decision, forced interrupt, weak-owner, and concurrency
  coverage.
- [x] Add failed/active/closed lifecycle coverage.
- [x] Add real-file duplicate setup and terminal destroy coverage.
- [x] Add concurrent read/getter/destroy stress coverage.

## Phase 5: Verification

- [x] Run focused format-context tests.
- [x] Run focused tests with Thread Sanitizer.
- [x] Run affected audio/video/decoder integration tests.
- [x] Run the full iOS Simulator suite.
- [x] Run a generic iOS device build.
- [x] Run package/project metadata and whitespace validation.
- [x] Update FFmpeg guidance and the 2.0 completion audit.
- [x] Create a focused commit.

## Verification Record

Completed on 2026-07-24:

- Format-context resource/callback focused suites: 35 passed, 0 failed.
- Thread Sanitizer focused suites: 35 passed, 0 failed, no race diagnostics.
- Format-context, audio/video decoder, decoder-session, and decoder-operation
  integration suites: 113 passed, 0 failed.
- Full iOS Simulator suite: 1121 passed, 0 failed, 0 skipped.
- Generic iOS device build: passed.
- Swift package resolution, package dump/description, Xcode project listing,
  project property-list validation, and `git diff --check`: passed.
- Build warnings remain confined to bundled FFmpeg headers and Xcode's
  AppIntents metadata processor.
