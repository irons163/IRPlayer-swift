# Decoded Frame Transport Ownership Implementation Plan

**Design:** See
`docs/superpowers/specs/2026-07-24-decoded-frame-transport-ownership-design.md`.

## Phase 1: Baseline And Frame Value

- [x] Record existing frame pool, queue, decoder, and renderer behavior.
- [x] Synchronize frame delegate, playing state, and transport metadata.
- [x] Move timestamp semantics into `IRFFFrameTime`.
- [x] Add coherent frame transport snapshots and lifecycle tests.

## Phase 2: Pool Owner

- [x] Add explicit open/closed phases and atomic diagnostics.
- [x] Keep owned identities partitioned into available, leased, and playing.
- [x] Validate factory type and duplicate identity before publication.
- [x] Reject foreign lifecycle callbacks.
- [x] Add reusable flush and terminal repeatable close.
- [x] Add pool failure, reuse, close, lifetime, and concurrency tests.

## Phase 3: Queue Owner

- [x] Add immutable admitted entries and typed admission results.
- [x] Freeze position, duration, and size at ownership transfer.
- [x] Reject duplicate and overflowing admission without corrupting state.
- [x] Replace polling with condition wait/signal/broadcast.
- [x] Drain and cancel owned frames on flush, close, and deinit.
- [x] Add atomic diagnostics and queue lifecycle/concurrency tests.

## Phase 4: Decoder Integration And Consolidation

- [x] Close frame queues and pools during audio/video decoder destroy.
- [x] Verify late decoded or external frames cannot publish after close.
- [x] Preserve reusable decoder flush behavior.
- [x] Align decoder worker QoS with packet/frame producer-consumer waits.
- [x] Remove frame-time, frame-pool, and frame-queue policy files.
- [x] Update Xcode project and ownership guidance.

## Phase 5: Verification

- [x] Run frame, pool, queue, audio/video decoder, and renderer focused tests.
- [x] Run focused tests with Thread Sanitizer.
- [x] Run decoder/display/audio integration suites.
- [x] Run the full iOS Simulator suite.
- [x] Run a generic iOS device build.
- [x] Run package/project, warning, stale-symbol, polling, and whitespace
  validation.
- [x] Update the 2.0 completion audit.
- [x] Create a focused commit.

## Baseline

Recorded on 2026-07-24 before implementation:

- Frame pool, frame queue, audio/video decoder, audio renderer, and decoder
  operation suites: 104 passed, 0 failed.

## Verification Record

Recorded on 2026-07-24 after implementation:

- Focused frame transport and decoder-owner suites: 119 passed, 0 failed.
- The same 119 tests under Thread Sanitizer: 119 passed, 0 failed, with no
  race or thread-performance diagnostics.
- Decoder, player, display, and audio integration suites: 255 passed, 0
  failed.
- Full iOS Simulator suite: 1237 passed, 0 failed, 0 skipped.
- Generic iOS device build: passed.
- Swift package manifest, Xcode project, deleted-policy references, legacy
  transport APIs, polling loop, warnings, and whitespace checks: passed.
- Only Xcode's expected AppIntents metadata-extraction warning remains.
