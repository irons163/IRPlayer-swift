# FFmpeg Decoder Session Lifecycle Implementation Plan

**Design:** See
`docs/superpowers/specs/2026-07-23-ff-decoder-session-lifecycle-design.md`.

## Phase 1: Session Owner

- [x] Add `IRFFDecoderSession` with explicit lifecycle phases.
- [x] Own and configure the operation queue and operation slots.
- [x] Own format/audio/video resources behind synchronized access.
- [x] Add external resource leases and deterministic close fencing.
- [x] Make concurrent close idempotent.

## Phase 2: Decoder Integration

- [x] Route open and worker scheduling through the session.
- [x] Route metadata, seek, audio fetch, render, and maintenance access through
  session resources.
- [x] Make open resource installation rejectable during close.
- [x] Route shutdown entirely through session teardown.
- [x] Remove direct resource/operation properties from `IRFFDecoder`.
- [x] Remove unreachable audio-track replacement state.
- [x] Remove `IRFFDecoderOperationPolicy` and its facade wrappers.

## Phase 3: Tests

- [x] Add duplicate-open and post-close rejection tests.
- [x] Add dependency/rescheduling tests.
- [x] Add close-waits-for-running-operation tests.
- [x] Add close-waits-for-external-lease tests.
- [x] Add concurrent-close ownership and resource-drain tests.
- [x] Update decoder operation tests for the new owner.

## Phase 4: Verification

- [x] Run session and decoder focused suites.
- [x] Run affected suites with Thread Sanitizer.
- [x] Run `git diff --check` and Xcode project validation.
- [x] Run the full iOS Simulator suite.
- [x] Run a generic iOS device build.
- [x] Update the 2.0 completion audit and create a focused commit.

## Results

- Focused decoder/session suites: passed.
- Thread Sanitizer decoder/state/queue suites: 89 passed, 0 failed.
- Full iOS Simulator suite: 958 passed, 0 failed, 0 skipped.
- Generic iOS device build: passed.
- Xcode project validation and `git diff --check`: passed.
