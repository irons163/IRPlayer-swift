# AGENTS.md — Core

This directory contains all internal subsystems of the IRPlayer framework.

## Subdirectories

| Directory      | Purpose                                                                 |
|----------------|-------------------------------------------------------------------------|
| `AVPlayer/`    | Native AVPlayer wrapper (`IRAVPlayer.swift`)                            |
| `Audio/`       | Core Audio graph session, driver, render context, and manager facade    |
| `Config/`      | Rendering configuration models (`IRFisheyeParameter`, `IRMediaParameter`) |
| `Controller/`  | Input controllers — gestures, scroll, bounce, device shift (ePTZ)      |
| `Display/`     | Rendering stack — Metal renderer and RenderKit (programs, modes, transforms) |
| `FFPlayer/`    | FFmpeg-based player and decoder pipeline                                |
| `Matrix/`      | Sensor/motion utilities (`IRSensor.swift`)                              |
| `Tools/`       | Utility helpers — FFmpeg error conversion, YUV tools, photo saver      |

## Standalone Files

- `IRPlayerNotification.swift` — Notification definitions for player state, progress, playable, and error events.
- `IRPlayerLoggingSession.swift` — Process-wide logging configuration,
  delegate snapshots, delivery accounting, and terminal lifecycle owner.

## Agent Notes

- `Display/` is the largest and most complex subsystem — it hosts both the Metal renderer and the full RenderKit abstraction.
- `Controller/` subsystems are consumed by `Display/RenderKit/` for viewport manipulation.
- `FFPlayer/FFmpeg/` is the decode pipeline; `AVPlayer/` is the system-native alternative.
- Audio management is shared between both player backends.
- When editing cross-cutting concerns (e.g., frame delivery), trace the flow from FFPlayer → Frame → Display.
- Logging delegates are weak between emissions and strongly snapshotted for one
  delivery. Never invoke a delegate or fallback sink under the logging-session
  lock.
