# FFmpeg Decoder Runtime State Implementation Plan

**Design:** See
`docs/superpowers/specs/2026-07-23-ff-decoder-runtime-state-design.md`.

## Phase 1: Synchronized State Owner

- [x] Add `IRFFDecoderRuntimeState`.
- [x] Add immutable snapshots and change results.
- [x] Add atomic close ownership.
- [x] Add atomic seek replacement/consumption.
- [x] Protect current audio and video frames.

## Phase 2: Decoder Integration

- [x] Route decoder status properties through runtime state.
- [x] Route read/display loop decisions through coherent snapshots.
- [x] Route pause, resume, seek, audio fetch, error, and close through the state
  owner.
- [x] Keep delegate and completion callbacks outside locks.
- [x] Remove superseded mutable storage from `IRFFDecoder`.

## Phase 3: Thread Sanitizer Hardening

- [x] Replace process-global `DispatchQueue.once` bookkeeping with a Swift
  static initialization boundary for FFmpeg bootstrap.
- [x] Synchronize packet/frame queue accounting reads with queue mutations.
- [x] Synchronize `IRFFVideoDecoder` worker flags and runtime configuration.
- [x] Add concurrent queue and video-decoder state regression tests.
- [x] Run the affected real-media decoder tests with Thread Sanitizer.

## Phase 4: Verification

- [x] Add focused runtime-state transition tests.
- [x] Add concurrent snapshot and idempotent-close tests.
- [x] Run all FF decoder focused suites.
- [x] Run `git diff --check` and Xcode project validation.
- [x] Run the full iOS Simulator suite.
- [x] Run a generic iOS device build.
- [x] Record remaining risks and update the project completion audit.

## Verification Record

Completed on 2026-07-23:

- FFmpeg focused decoder suites: 64 passed before sanitizer hardening.
- Thread Sanitizer decoder/state/queue suites: 76 passed, 0 failed.
- Full iOS Simulator suite on iPhone 17 / iOS 26.4: 950 passed, 0
  failed, 0 skipped.
- Generic iOS device build: passed.
- `git diff --check` and Xcode project property-list validation: passed.
- Build warnings remain confined to bundled FFmpeg headers.

The broader 2.0 modernization remains active. See
`docs/superpowers/2.0-completion-audit.md` for the next architecture boundaries.
