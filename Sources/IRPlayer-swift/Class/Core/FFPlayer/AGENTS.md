# AGENTS.md — FFPlayer

FFmpeg-based player and decoder pipeline.

## Top-Level Files

| File                      | Purpose                                       |
|---------------------------|-----------------------------------------------|
| `IRFFPlayer.swift`        | FFmpeg player implementation                  |
| `IRFFAudioRenderer.swift` | Synchronized decoded-audio frame consumer     |
| `IRFFPlayer.h`            | Objective-C header for FFmpeg player bridge   |

## Subdirectory

- `FFmpeg/` — Full FFmpeg decode pipeline (format context, decoders, frames, tools).

## Agent Notes

- `IRFFPlayer` is the alternative to `IRAVPlayer` — used for FFmpeg-decoded content.
- Supports hardware decoding via VideoToolBox and software decoding.
- Handles custom video input (`IRFFVideoInput`) for direct frame injection.
- Stop and drain `IRAudioManager` before resetting `IRFFAudioRenderer` or
  closing its decoder source.
- Audio dequeue from the decoder must be non-waiting; an empty queue produces
  silence for the current callback.
- Tests: `IRFFPlayerTests.swift` and `IRFFAudioRendererTests.swift`.
