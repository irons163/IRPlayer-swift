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

## Subdirectory

- `FFmpeg/` — Full FFmpeg decode pipeline (format context, decoders, frames, tools).

## Agent Notes

- `IRFFPlayer` is the alternative to `IRAVPlayer` — used for FFmpeg-decoded
  content. Keep it as an adapter; mutable playback runtime state belongs in
  `IRFFPlayerRuntime`.
- Supports hardware decoding via VideoToolBox and software decoding.
- Handles custom video input (`IRFFVideoInput`) for direct frame injection.
- Route commands and decoder events through `IRFFPlayerExecutor`.
- A callback arriving from the decoder domain must never synchronously wait
  for `IRFFPlayerExecutor`: enqueue it when off-executor, while callbacks
  already on the executor may be delivered immediately.
- Decode-bound events (EOF, playback-finished, buffering, buffered duration,
  and progress) must carry the emitter's origin decode generation. Fence that
  generation together with decoder identity and the player token when the
  event actually executes; never infer origin from the decoder at bridge time.
- Opening and preparation are decoder-lifecycle events, so they are token-only.
  Failure is terminal and also token-only after commit because decoder state
  rejects any later seek admission while the stored error remains.
- Fence multi-step activation, play/pause, failure, and presentation work
  across synchronous callbacks so the newest reentrant command wins.
- Every installed decoder needs its own token and delegate bridge. Reject stale
  or unknown callbacks rather than forwarding them to the runtime.
- Publish one complete decoder collaborator generation—delegate bridge,
  source, video output, and audio output—before calling `open()`.
- Replacement, reset, close, and unpublished discard must invoke one terminal
  collaborator revoke before `closeFile()`; never clear those four links as
  independent mutations.
- Keep seek completion generation-owned and exactly once. Reset/replacement
  cancels pending seeks with `false`; seeking without a decoder also completes
  `false`.
- Keep progress-post throttling and live-duration decisions on
  `IRFFPlayerRuntime`, beside the timestamp and progress state they consume.
- Stop and drain `IRAudioManager` before resetting `IRFFAudioRenderer` or
  closing its decoder source.
- Audio dequeue from the decoder must be non-waiting; an empty queue produces
  silence for the current callback.
- Decoded audio samples are owned by `IRFFAudioFrame`. The decoder writes
  within its scoped mutable borrow; the renderer consumes only through the
  frame's checked byte-copy boundary.
- Keep audio sample allocation and growth out of
  `IRFFAudioRenderer.audioManager`.
- Reset is repeatable, close is terminal/idempotent, and deinit must not publish
  state/time/failure events or clear a display that may have been reused.
- Apply or clear `IRGLView` presentation only through the main-thread
  presentation owner, before opening a replacement decoder.
- Tests: `IRFFPlayerTests.swift`, `IRFFAudioRendererTests.swift`, and
  `IRFFPlayerRuntimeOwnerTests.swift`.
