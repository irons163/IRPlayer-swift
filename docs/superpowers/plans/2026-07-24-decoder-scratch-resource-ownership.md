# Decoder Scratch Resource Ownership Implementation Plan

**Design:** See
`docs/superpowers/specs/2026-07-24-decoder-scratch-resource-ownership-design.md`.

## Phase 1: Decode Frame Owner

- [x] Add injectable AVFrame allocate/free runtime.
- [x] Add failable complete-frame construction.
- [x] Add fixed-result scoped frame borrow.
- [x] Add repeatable close and automatic cleanup.
- [x] Add borrow/close lifecycle diagnostics.

## Phase 2: Audio Resampler Owner

- [x] Add local all-or-nothing resampler construction.
- [x] Free contexts on allocation and initialization failures.
- [x] Replace raw scratch allocation with managed `Int16` storage.
- [x] Add checked capacity growth and reuse.
- [x] Add fixed-result converted-sample consumption.
- [x] Add typed conversion outcomes and repeatable close.

## Phase 3: Decoder Integration

- [x] Replace audio raw frame/context/buffer fields with owners.
- [x] Replace video raw frame field with the shared owner.
- [x] Receive and consume decoded frames within scoped borrows.
- [x] Consolidate resampled and direct audio-frame population.
- [x] Return rejected pooled audio frames for reuse.
- [x] Remove manual decoder resource cleanup.
- [x] Correct video frame teardown to `av_frame_free`.

## Phase 4: Tests

- [x] Add allocation failure, diagnostics, close, and deinit coverage.
- [x] Add concurrent frame borrow/close coverage.
- [x] Add partial resampler setup cleanup coverage.
- [x] Add same-count channel-layout generation identity coverage.
- [x] Add conversion failure and consumer rejection coverage.
- [x] Add managed capacity growth/reuse coverage.
- [x] Add concurrent resampler conversion/close coverage.
- [x] Preserve real PCM and software-video decode coverage.

## Phase 5: Verification

- [x] Run frame/resampler/audio/video focused tests.
- [x] Run focused tests with Thread Sanitizer.
- [x] Run decoder-session and FFPlayer integration tests.
- [x] Run the full iOS Simulator suite.
- [x] Run a generic iOS device build.
- [x] Run package/project metadata, stale-symbol, and whitespace validation.
- [x] Update FFmpeg guidance and the 2.0 completion audit.
- [x] Create a focused commit.

## Baseline

Recorded on 2026-07-24 before implementation:

- Audio and video decoder suites: 46 passed, 0 failed.

## Verification Record

Completed on 2026-07-24:

- Decode-frame owner, resampler owner, audio decoder, and video decoder focused
  suites: 58 passed, 0 failed.
- The same 58 tests under Thread Sanitizer: passed with no race diagnostics.
- Packet/frame, format-resource, decoder-session, VideoToolbox, and all FFPlayer
  runtime-owner integration suites: 326 passed, 0 failed.
- Full iOS Simulator suite: 1159 passed, 0 failed, 0 skipped.
- Generic iOS device build: passed.
- Swift package resolution, package dump/description, Xcode project listing,
  project property-list validation, stale-resource search, and
  `git diff --check`: passed.
