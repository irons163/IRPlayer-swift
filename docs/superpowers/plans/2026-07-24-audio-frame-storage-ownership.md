# Audio Frame Storage Ownership Implementation Plan

**Design:** See
`docs/superpowers/specs/2026-07-24-audio-frame-storage-ownership-design.md`.

## Phase 1: Managed Storage Domain

- [x] Replace the stored sample pointer with Swift contiguous storage.
- [x] Consolidate checked byte-to-element arithmetic in the frame domain.
- [x] Add active element count and reusable capacity diagnostics.
- [x] Add a scoped mutable borrow and value snapshot.
- [x] Add a checked byte-copy operation for real-time consumption.
- [x] Make invalid input clear all active storage state.

## Phase 2: Producer And Consumer Integration

- [x] Convert decoded PCM within one mutable sample borrow.
- [x] Copy renderer bytes through the frame boundary.
- [x] Keep storage growth out of the real-time callback.
- [x] Preserve output offset, partial frame, and frame completion behavior.

## Phase 3: Policy Consolidation

- [x] Move storage decisions into `IRFFAudioFrame`.
- [x] Remove pointer-returning `samples`.
- [x] Remove facade-to-policy forwarding.
- [x] Remove `IRFFAudioFramePolicy.swift`.

## Phase 4: Tests

- [x] Replace pointer-identity and wrapper-equivalence assertions.
- [x] Add invalid, overflow, rounding, reuse, and growth coverage.
- [x] Add mutable-borrow, snapshot, and active-bound coverage.
- [x] Add full, partial, and rejected byte-copy coverage.
- [x] Extend renderer multi-frame and contended callback coverage.
- [x] Extend real PCM decode coverage with finite scaled samples.

## Phase 5: Verification

- [x] Run focused audio-frame/renderer/decoder tests.
- [x] Run focused tests with Thread Sanitizer.
- [x] Run decoder, audio-owner, and FFPlayer integration tests.
- [x] Run the full iOS Simulator suite.
- [x] Run a generic iOS device build.
- [x] Run package/project metadata, stale-pointer, and whitespace validation.
- [x] Update frame guidance and the 2.0 completion audit.
- [x] Create a focused commit.

## Verification Record

Completed on 2026-07-24:

- Audio-frame, renderer, and decoder focused suites: 53 passed, 0 failed.
- The same 53 tests under Thread Sanitizer: passed with no race diagnostics.
- Decoder, audio-session, audio-graph, FFPlayer, and runtime-owner integration
  suites: 184 passed, 0 failed.
- Full iOS Simulator suite: 1134 passed, 0 failed, 0 skipped.
- Generic iOS device build: passed.
- Swift package resolution, package dump/description, Xcode project listing,
  project property-list validation, stale-pointer/stale-policy search, and
  `git diff --check`: passed.
