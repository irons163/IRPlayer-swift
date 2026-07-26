# Custom Video Decode Value Boundary Implementation Plan

**Design:** See
`docs/superpowers/specs/2026-07-24-custom-video-decode-values-design.md`.

## Phase 1: Baseline and Values

- [x] Audit public custom-input callbacks, decoder packet borrows, codec
  ownership, async documentation, and tests.
- [x] Record the pre-change focused custom-decode baseline.
- [x] Add immutable codec and identifier values with checked extradata copying.
- [x] Add immutable compressed-packet and side-data values with checked copying.
- [x] Make decoder info immutable and pointer-free.

## Phase 2: Pipeline Integration

- [x] Build one immutable codec descriptor for the decoder generation.
- [x] Route with an allocation-free borrowed packet descriptor, then copy an
  owned compressed packet only after the source opts in.
- [x] Preserve synchronous returned frames.
- [x] Replace ambiguous async `nil` with typed frame/drop/deferred/failure
  outcomes and a one-shot completion token.
- [x] Count deferred reservations in bounded frame admission and hold EOF until
  current-generation reservations resolve.
- [x] Cancel reservations on seek/stop and reclaim late or duplicate frames.
- [x] Synchronize output rebinding, make it non-owning, and freeze routing
  mode at initialization.
- [x] Preserve built-in VideoToolbox and software decode fallback.
- [x] Remove `IRFFDecoderCodecContextPolicy`.

## Phase 3: Public Migration

- [x] Update `IRFFVideoInput` callback types.
- [x] Update README async custom-decode guidance.
- [x] Document the 2.0 source migration and pointer-lifetime change.
- [x] Document typed completion ownership, EOF, cancellation, and direct
  forwarding admission.
- [x] Update local FFmpeg and test architecture guidance.

## Phase 4: Tests

- [x] Cover codec identifiers, fields, extradata, and malformed contexts.
- [x] Cover payload, timestamps, flags, file position, and empty input.
- [x] Cover ordered side-data copying and malformed entries.
- [x] Prove captured values survive source mutation and internal packet close.
- [x] Prove both custom callbacks receive the same generation.
- [x] Prove explicit drop, deferred EOF wait, unretained-token auto-drop,
  exactly-once resolution, and late-frame reclaim.
- [x] Prove same-generation active-worker flush rejection and stale EOS ticket
  fencing.
- [x] Prove generation-advancing invalidation and destroy can publish
  cancellation while EOS drain is waiting for output capacity.
- [x] Preserve software, VideoToolbox, queue, decoder, and player integration.

## Phase 5: Historical Verification (2026-07-24)

- [x] Run focused custom-input, packet, decoder, queue, and player suites.
- [x] Run the changed decoder boundary under Thread Sanitizer.
- [x] Run decoder and playback integration suites.
- [x] Run the full iOS Simulator suite.
- [x] Run a generic iOS device Release build.
- [x] Run project metadata, stale-symbol, warning, and whitespace checks.
- [x] Update the 2.0 completion audit.
- [x] Create a focused commit.

These checks describe the 2026-07-24 pointer-boundary implementation. They are
a historical checkpoint, not verification of the later typed-completion,
bounded-admission, and terminal-transition work.

## Phase 6: Typed Completion Revalidation (2026-07-26)

- [x] Build the current test target for the iOS Simulator.
- [x] Run the typed custom decoder and input suites: 54 passed, 0 failed,
  0 skipped.
- [x] Type-check an external public-API custom decoder consumer.
- [x] Run the merged admission-ledger, queue-interruption, and terminal-error
  regression suites: 89 passed, 0 failed, 0 skipped.
- [ ] Run the full iOS Simulator suite.
- [ ] Run the changed boundary under Thread Sanitizer.
- [ ] Run a generic iOS device Release build.
- [ ] Run stale-symbol, warning, project metadata, and whitespace checks.
- [ ] Create the final 2.0 commit.

## Baseline

Recorded on 2026-07-24 before implementation:

- Custom input, video decoder, decoder operation, packet, packet queue, and
  FFPlayer runtime-owner suites: 77 passed, 0 failed, 0 skipped.

## Historical Verification

Recorded on 2026-07-24 after implementation:

- Focused custom input, decoder, session, facade, and FFPlayer suites: 100
  passed, 0 failed, 0 skipped.
- Thread Sanitizer on the same custom decode and binding boundary: 100 passed,
  0 failed, 0 skipped, with no race diagnostics.
- Packet, queue, VideoToolbox, format-generation, and FFPlayer integration
  suites: 148 passed, 0 failed, 0 skipped.
- Full iOS Simulator suite: 1296 passed, 0 failed, 0 skipped.
- Generic iOS device Release build: passed with no changed-source warnings.
- Package manifest, project metadata, stale-symbol, pointer-surface, and
  whitespace checks: passed.
