# Player Lifecycle Policy Design

## Summary

Phase 2 starts with a low-risk player-core slice: make `IRPlayerImp` lifecycle decisions explicit and testable without changing the public API or the concrete AVPlayer/FFmpeg playback implementations.

The work introduces an internal pure policy helper that answers when `IRPlayerImp` should forward lifecycle commands, stop an old backend during replacement, and resume after app foreground events. `IRPlayerImp` keeps its current method signatures and remains the public entry point.

## Goals

- Preserve source compatibility for `IRPlayerImp` public methods and existing notification names.
- Extract lifecycle decisions from `IRPlayerImp` into a small internal helper with deterministic unit tests.
- Keep behavior equivalent for `play`, `pause`, `replaceVideoWithURL`, background handling, and foreground handling.
- Make no-op behavior explicit for `.none`, `.error`, and missing backend states.
- Add focused tests before production code changes.

## Non-Goals

- Do not refactor `IRAVPlayer` or `IRFFPlayer` playback internals.
- Do not change seek, buffering, decoder open/close, rendering, or audio pipeline behavior.
- Do not add required public API.
- Do not alter notification payload formats or notification timing beyond preserving existing behavior.

## Architecture

Add an internal helper named `IRPlayerLifecyclePolicy` in a small sibling file under `Sources/IRPlayer-swift/Class`.

The helper should be pure: it accepts simple value inputs and returns simple decisions. It must not hold references to `IRPlayerImp`, `IRAVPlayer`, `IRFFPlayer`, UIKit, or NotificationCenter.

Expected decision areas:

- Command forwarding:
  - `.avPlayer` forwards lifecycle commands to the AV backend.
  - `.ffmpeg` forwards lifecycle commands to the FFmpeg backend.
  - `.none`, `.error`, and nil decoder type do nothing.
- Replacement:
  - Replacing with `.avPlayer` stops an existing FFmpeg backend before replacing AV.
  - Replacing with `.ffmpeg` stops an existing AV backend before replacing FFmpeg.
  - Replacing with `.error`, `.none`, or nil stops any existing backends and avoids creating a new one.
- Background policy:
  - `.autoPlayAndPause` pauses only when the effective state is `.playing` or `.buffering`.
  - `.nothing` and `.continuing` do not pause.
  - Pausing for background marks `needAutoPlay` true.
- Foreground policy:
  - `.autoPlayAndPause` resumes only when the effective state is `.suspend` and `needAutoPlay == true`.
  - Resuming clears `needAutoPlay`.
  - `.nothing` and `.continuing` do not resume.

`IRPlayerImp` should use the helper to select branches, but backend calls remain in `IRPlayerImp` so the public object continues to own lazy player creation and existing side effects.

## Data Flow

For `play` and `pause`, `IRPlayerImp` computes a policy target from `decoderType`, updates the idle timer as it currently does, and forwards to the selected backend only if the target is AV or FFmpeg.

For replacement, `IRPlayerImp` still updates `error`, `contentURL`, `videoInput`, `decoderType`, and `videoType` as today. It then asks the policy which old backends to stop and which new backend to replace. Existing `videoInput.videoOutput` assignment behavior remains unchanged.

For background and foreground, `IRPlayerImp` asks the policy for an action using `backgroundMode`, current state, and `needAutoPlay`. UIKit notification registration remains unchanged.

## Error Handling

Invalid or unsupported decoder decisions are treated as no-op or stop-only paths, matching current behavior. The policy must not throw. Any future error notification behavior remains outside this slice.

## Testing

Add `IRPlayerLifecyclePolicyTests` for pure policy behavior:

- `play` and `pause` command targets for `.avPlayer`, `.ffmpeg`, `.error`, `.none`, and nil.
- Replacement stop/replace decisions for AV-to-FFmpeg, FFmpeg-to-AV, error, none, and nil.
- Background auto-pause decisions for `.playing`, `.buffering`, `.readyToPlay`, `.suspend`, `.failed`, and non-auto background modes.
- Foreground auto-resume decisions for `.suspend` with and without `needAutoPlay`, plus non-auto background modes.

Add or extend `IRPlayerImp` smoke tests only if needed to prove the public entry points still route through the expected lazy player paths. Keep these tests lightweight and avoid real playback.

## Acceptance Criteria

- `IRPlayerLifecyclePolicyTests` are added and fail before implementation.
- The focused tests pass after implementation.
- Existing `IRPlayerImp` behavior remains source-compatible.
- Full iOS simulator test suite passes:

```sh
xcodebuild test -project IRPlayer-swift.xcodeproj -scheme IRPlayer-swift -destination 'id=D13E4DB6-F55D-4967-95DA-CBA3C506A2F3'
```

## Implementation Boundary

Place production lifecycle policy code in `Sources/IRPlayer-swift/Class/IRPlayerLifecyclePolicy.swift`. Keep `IRPlayerImp.swift` focused on public API, backend ownership, UIKit side effects, and concrete backend calls.
