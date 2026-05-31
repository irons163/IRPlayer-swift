# AGENTS.md — Core

This directory contains all internal subsystems of the IRPlayer framework.

## Subdirectories

| Directory      | Purpose                                                                 |
|----------------|-------------------------------------------------------------------------|
| `AVPlayer/`    | Native AVPlayer wrapper (`IRAVPlayer.swift`)                            |
| `Audio/`       | Audio output manager (`IRAudioManager.swift`)                           |
| `Config/`      | Rendering configuration models (`IRFisheyeParameter`, `IRMediaParameter`) |
| `Controller/`  | Input controllers — gestures, scroll, bounce, device shift (ePTZ)      |
| `Display/`     | Rendering stack — Metal renderer and RenderKit (programs, modes, transforms) |
| `FFPlayer/`    | FFmpeg-based player and decoder pipeline                                |
| `Matrix/`      | Sensor/motion utilities (`IRSensor.swift`)                              |
| `Tools/`       | Utility helpers — FFmpeg error conversion, YUV tools, photo saver      |

## Standalone File

- `IRPlayerNotification.swift` — Notification definitions for player state, progress, playable, and error events.

## Agent Notes

- `Display/` is the largest and most complex subsystem — it hosts both the Metal renderer and the full RenderKit abstraction.
- `Controller/` subsystems are consumed by `Display/RenderKit/` for viewport manipulation.
- `FFPlayer/FFmpeg/` is the decode pipeline; `AVPlayer/` is the system-native alternative.
- Audio management is shared between both player backends.
- When editing cross-cutting concerns (e.g., frame delivery), trace the flow from FFPlayer → Frame → Display.
