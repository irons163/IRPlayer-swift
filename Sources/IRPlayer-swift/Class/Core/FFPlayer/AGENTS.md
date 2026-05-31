# AGENTS.md — FFPlayer

FFmpeg-based player and decoder pipeline.

## Top-Level Files

| File                  | Purpose                                           |
|-----------------------|---------------------------------------------------|
| `IRFFPlayer.swift`    | FFmpeg player implementation                      |
| `IRFFPlayer.h`        | Objective-C header for FFmpeg player bridge        |

## Subdirectory

- `FFmpeg/` — Full FFmpeg decode pipeline (format context, decoders, frames, tools).

## Agent Notes

- `IRFFPlayer` is the alternative to `IRAVPlayer` — used for FFmpeg-decoded content.
- Supports hardware decoding via VideoToolBox and software decoding.
- Handles custom video input (`IRFFVideoInput`) for direct frame injection.
- Tests: `IRFFPlayerTests.swift`.
