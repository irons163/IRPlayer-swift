# AGENTS.md — FFPlayer

FFmpeg-based player and decoder pipeline.

## Top-Level Files

| File                           | Purpose                                      |
|--------------------------------|----------------------------------------------|
| `IRFFPlayer.swift`             | Backend facade and request translation       |
| `IRFFPlayerExecutor.swift`     | Reentrant serial runtime execution domain    |
| `IRFFPlayerStateMachine.swift` | Playback state, intent, and preparation owner |
| `IRFFPlayerDecoderSession.swift` | Decoder generations, bridges, and seeks    |
| `IRFFPlayerRuntime.swift`      | Commands, audio ordering, time, and events   |
| `IRFFPlayerPresentation.swift` | Main-thread FFmpeg display configuration     |
| `IRFFAudioRenderer.swift`      | Synchronized decoded-audio frame consumer    |
| `IRFFPlayer.h`                 | Objective-C header for FFmpeg player bridge  |

## Subdirectory

- `FFmpeg/` — Full FFmpeg decode pipeline (format context, decoders, frames, tools).

## Agent Notes

- `IRFFPlayer` is the alternative to `IRAVPlayer` — used for FFmpeg-decoded
  content. Keep it as an adapter; mutable playback runtime state belongs in
  `IRFFPlayerRuntime`.
- Supports hardware decoding via VideoToolBox and software decoding.
- Handles custom video input (`IRFFVideoInput`) for direct frame injection.
- Route commands and decoder events through `IRFFPlayerExecutor`.
- Fence multi-step activation, play/pause, failure, and presentation work
  across synchronous callbacks so the newest reentrant command wins.
- Every installed decoder needs its own token and delegate bridge. Reject stale
  or unknown callbacks rather than forwarding them to the runtime.
- Publish and configure a complete decoder generation before calling `open()`.
- Detach decoder delegate, source, video output, and audio output before
  `closeFile()`.
- Keep seek completion generation-owned and exactly once. Reset/replacement
  cancels pending seeks with `false`; seeking without a decoder also completes
  `false`.
- Stop and drain `IRAudioManager` before resetting `IRFFAudioRenderer` or
  closing its decoder source.
- Audio dequeue from the decoder must be non-waiting; an empty queue produces
  silence for the current callback.
- Reset is repeatable, close is terminal/idempotent, and deinit must not publish
  state/time/failure events or clear a display that may have been reused.
- Apply or clear `IRGLView` presentation only through the main-thread
  presentation owner, before opening a replacement decoder.
- Tests: `IRFFPlayerTests.swift`, `IRFFAudioRendererTests.swift`, and
  `IRFFPlayerRuntimeOwnerTests.swift`.
