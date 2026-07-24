# FFmpeg Packet Ownership Implementation Plan

**Design:** See
`docs/superpowers/specs/2026-07-24-ffmpeg-packet-ownership-design.md`.

## Phase 1: Packet Owner

- [x] Add empty, ready, and closed packet phases.
- [x] Add reference-moving raw packet ingestion.
- [x] Add one-shot fill and immutable routing snapshot.
- [x] Add fixed-result scoped packet access.
- [x] Add idempotent close and automatic unref.
- [x] Add injectable move/unref runtime.

## Phase 2: Typed Queue

- [x] Store packet owners instead of copied `AVPacket` structs.
- [x] Add explicit packet, flush, and closed queue items.
- [x] Preserve FIFO, byte, and duration accounting.
- [x] Release queued packets on flush and destroy.
- [x] Close packets rejected after destroy.
- [x] Consolidate accounting and remove `IRFFPacketQueuePolicy`.

## Phase 3: Pipeline Integration

- [x] Create one owner per format read attempt.
- [x] Transfer video packet owners into the queue.
- [x] Consume and close audio packet owners synchronously.
- [x] Release ignored and failed-read packets deterministically.
- [x] Decode video packets within a scoped owner borrow.
- [x] Remove raw flush and negative-index sentinels.

## Phase 4: Tests

- [x] Add exactly-once move, fill, close, and deinit coverage.
- [x] Add concurrent close and borrow/close ordering coverage.
- [x] Replace raw queue tests with owned typed-item assertions.
- [x] Add rejected, flushed, and destroyed packet release coverage.
- [x] Update audio/video packet lifecycle tests.
- [x] Preserve real PCM, software-video, and reader integration coverage.

## Phase 5: Verification

- [x] Run focused packet/format/audio/video/decoder tests.
- [x] Run focused tests with Thread Sanitizer.
- [x] Run decoder-session and FFPlayer integration tests.
- [x] Run the full iOS Simulator suite.
- [x] Run a generic iOS device build.
- [x] Run package/project metadata, stale-symbol, and whitespace validation.
- [x] Update FFmpeg/frame guidance and the 2.0 completion audit.
- [x] Create a focused commit.

## Baseline

Recorded on 2026-07-24 before implementation:

- Packet queue, format context, audio decoder, video decoder, and decoder
  operation suites: 110 passed, 0 failed.

## Verification Record

Completed on 2026-07-24:

- Packet owner/queue, format context, audio decoder, video decoder, and decoder
  operation focused suites: 116 passed, 0 failed.
- The same 116 tests under Thread Sanitizer: passed with no race diagnostics.
- Packet/frame, format-resource, decoder-session, VideoToolbox, and all FFPlayer
  runtime-owner integration suites: 314 passed, 0 failed.
- Full iOS Simulator suite: 1147 passed, 0 failed, 0 skipped.
- Generic iOS device build: passed.
- Swift package resolution, package dump/description, Xcode project listing,
  project property-list validation, stale-symbol search, and
  `git diff --check`: passed.
