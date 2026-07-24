# FF Player Runtime Owners Implementation Plan

**Design:** See
`docs/superpowers/specs/2026-07-24-ff-player-runtime-owners-design.md`.

## Phase 1: Execution And State

- [x] Add a reentrant-safe FF player executor with diagnostics.
- [x] Add an explicit state machine for play intent, preparation, and playback
  transitions.
- [x] Move all `IRFFPlayerPlaybackPolicy` behavior into the state machine and
  delete the policy file.
- [x] Cover every state transition, reset, and reentrant execution.

## Phase 2: Decoder Generation Ownership

- [x] Add a decoder session with phase, token, generation bridge, factory
  injection, and diagnostics.
- [x] Publish a complete decoder generation before opening it.
- [x] Reject stale/unknown callbacks and detach callbacks before close.
- [x] Add exactly-once generation-owned seek tickets.
- [x] Cover activation, replacement, adoption, pending seek cancellation,
  stale completion, reset, and terminal close.

## Phase 3: Runtime And Adapter

- [x] Add the aggregate FF player runtime for decoder commands, playback/time
  state, audio ordering, host events, configuration, and coherent snapshots.
- [x] Reduce `IRFFPlayer` to host/request/presentation translation and computed
  compatibility accessors.
- [x] Fix FFmpeg seeking/snapshot reporting.
- [x] Make stop resettable and deinit close silently.
- [x] Isolate main-thread presentation mapping and cleanup.

## Phase 4: Verification

- [x] Expand player/runtime/session/presentation tests.
- [x] Run FF player and audio renderer suites with Thread Sanitizer.
- [x] Run affected coordinator/facade/decoder suites.
- [x] Run the full iOS Simulator suite.
- [x] Run the generic iOS device build.
- [x] Run package/project validation and `git diff --check`.
- [x] Update owner documentation and the 2.0 completion audit.
- [x] Create a focused commit.

## Baseline

- Existing `IRFFPlayerTests` and `IRFFAudioRendererTests`: 39 tests.
- Baseline focused Thread Sanitizer: 39 passed, no race diagnostics.
- Full iOS Simulator suite: 1069 tests.

## Result

- Added 36 focused owner tests; the combined FF player/audio owner suites pass
  75/75.
- The same 75 tests pass with Thread Sanitizer and no race diagnostics.
- The full iOS Simulator suite passes 1105/1105.
- The generic iOS device build passes.
- `swift package resolve`, package manifest description/dump, Xcode project
  plist validation, and `git diff --check` pass.
- Host `swift build` remains inapplicable to the iOS-only FFmpeg XCFramework
  package: the macOS build cannot import the bundled iOS `libavutil` headers.
