# Audio Output Session Lifecycle Implementation Plan

**Design:** See
`docs/superpowers/specs/2026-07-23-audio-output-session-lifecycle-design.md`.

## Phase 1: Graph And Callback Owners

- [x] Add `IRAudioGraphSession` with explicit repeatable/terminal phases.
- [x] Add an injectable graph driver and a real Core Audio implementation.
- [x] Build graph resources locally and clean every partial failure.
- [x] Serialize start, pause, volume, reset, and close.
- [x] Add `IRAudioRenderContext` with preallocated storage and non-blocking
  callback admission.
- [x] Fence callback deactivation before graph stop/disposal.

## Phase 2: Facade And Backend Integration

- [x] Reduce `IRAudioManager` to graph commands, format fallback, and event
  routing.
- [x] Replace selector observers with owned block observer tokens.
- [x] Synchronize handler target replacement/removal.
- [x] Consolidate notification/render invariants and remove
  `IRAudioManagerPolicy`.
- [x] Add `IRFFAudioRenderer` as the FFmpeg frame-consumption owner.
- [x] Stop/drain output before renderer reset and decoder close.
- [x] Use non-waiting audio-frame dequeue from the decoder.
- [x] Remove direct `IRFFPlayer: IRAudioManagerDelegate` conformance.

## Phase 3: Tests

- [x] Add graph-session lifecycle, retry, concurrent-close, and volume tests.
- [x] Inject every mandatory Core Audio build failure and verify exact cleanup.
- [x] Add optional-warning and format-validation driver tests.
- [x] Add Float32/Int16, interleaved/non-interleaved, bounds, silence, and
  contention render tests.
- [x] Add render/reset and render/close fencing tests.
- [x] Add notification binding/replacement/deinit tests.
- [x] Add FFmpeg renderer frame/copy/reset/concurrency tests.
- [x] Update manager, audio decoder, and FFPlayer integration regressions.

## Phase 4: Verification

- [x] Run focused audio, graph, render, notification, decoder, and FFPlayer
  suites.
- [x] Run affected lifecycle/concurrency suites with Thread Sanitizer.
- [x] Run `git diff --check` and Xcode project validation.
- [x] Run the full iOS Simulator suite.
- [x] Run a generic iOS device build.
- [x] Update the 2.0 completion audit and create a focused commit.

## Baseline

- Existing audio-manager/FFPlayer focused suites: 56 passed, 0 failed, 0
  skipped.

## Final Validation

- Expanded audio/decoder/FFPlayer focused suites: 135 passed, 0 failed, 0
  skipped.
- The same 135 focused cases under Thread Sanitizer: passed with no race
  diagnostics.
- Full iOS Simulator suite: 997 passed, 0 failed, 0 skipped.
- Generic iOS device build: passed.
- `git diff --check` and Xcode project `plutil` validation: passed.
