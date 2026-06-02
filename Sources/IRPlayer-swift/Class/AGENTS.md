# AGENTS.md — Class

This directory contains all the main Swift source code for the IRPlayer framework.

## Top-Level Files

| File                          | Purpose                                                    |
|-------------------------------|------------------------------------------------------------|
| `IRPlayerImp.swift`           | Main player implementation — public API entry point        |
| `IRPlayerAction.swift`        | Player action/event definitions                            |
| `IRPlayerDecoder.swift`       | Decoder configuration (AVPlayer vs FFmpeg, hardware flags) |
| `IRPlayerTrack.swift`         | Audio/video track model                                    |
| `IRPlayerLifecyclePolicy.swift` | Player lifecycle management policy                       |

## Subdirectories

- `Core/` — All internal subsystems: AVPlayer, FFmpeg decoder, audio, display/rendering, controllers, math, and tools.
- `Platform/` — Platform abstraction layer (image/view type aliases for iOS).

## Agent Notes

- `IRPlayerImp` is the central public class. Most changes to player behavior go through it.
- `IRPlayerDecoder` configures whether AVPlayer or FFmpeg is used and hardware decoding options.
- When modifying public API in these files, ensure backward compatibility or document breakage.
- Lifecycle policy was added recently — see `docs/superpowers/specs/` for design intent.
