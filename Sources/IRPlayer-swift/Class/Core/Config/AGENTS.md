# AGENTS.md — Config

## Contents

| File                       | Purpose                                              |
|----------------------------|------------------------------------------------------|
| `IRFisheyeParameter.swift` | Fisheye lens calibration parameters (rx, ry, cx, cy, latmax) |
| `IRMediaParameter.swift`   | General media/rendering configuration parameters     |

## Purpose

Holds configuration models used by render modes and programs to set up projection geometry. These are passed into render modes (e.g., `IRGLRenderMode3DFisheye`, `IRGLRenderModeMulti4P`) to configure lens correction.

## Agent Notes

- `IRFisheyeParameter` is critical for fisheye-to-perspective and fisheye-to-panorama modes.
- Changes to parameter fields may affect multiple render programs — trace usages before modifying.
