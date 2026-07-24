# AGENTS.md — Class

This directory contains all the main Swift source code for the IRPlayer framework.

## Top-Level Files

| File                              | Purpose                                                    |
|-----------------------------------|------------------------------------------------------------|
| `IRPlayerImp.swift`               | Public player facade and runtime-owner composition         |
| `IRPlayerImp+Compatibility.swift` | Internal legacy collaborator adapters                      |
| `IRPlayerImp+Environment.swift`   | Legacy notification API compatibility                     |
| `IRPlayerImp+Presentation.swift`  | Public presentation forwarding API                         |
| `IRPlayerAction.swift`            | Player action/event definitions                            |
| `IRPlayerDecoder.swift`           | Decoder configuration (AVPlayer vs FFmpeg, hardware flags) |
| `IRPlayerLogger.swift`            | Public logging value and synchronized-owner accessors      |
| `IRPlayerTrack.swift`             | Audio/video track model                                    |

## Subdirectories

- `Core/` — All internal subsystems: AVPlayer, FFmpeg decoder, audio, display/rendering, controllers, math, and tools.
- `Platform/` — Platform abstraction layer (image/view type aliases for iOS).

## Agent Notes

- `IRPlayerImp` is the public facade. Runtime behavior belongs in the focused
  owners under `Core/Playback/` and `Core/Display/`; keep the facade limited to
  API translation and composition.
- `IRPlayerDecoder` configures whether AVPlayer or FFmpeg is used and hardware decoding options.
- When modifying public API in these files, ensure backward compatibility or document breakage.
- Lifecycle decisions live in `IRPlayerLifecycleController`, owned and
  synchronized by `IRPlayerEnvironmentSession`.
- Keep `IRPlayerImp.Logger` as compatibility accessors over
  `IRPlayerLoggingSession`; do not add mutable static logger state.
- Keep notification payload construction, numeric decoding, and finite defaults
  on `IRPlayerNotificationPayload`; do not recreate a forwarding policy layer.
- Use `IRPlaybackTimeRange` for shared finite non-negative duration bounds.
