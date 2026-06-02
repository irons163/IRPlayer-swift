# AGENTS.md — Controller

Input and interaction controllers for the rendering viewport.

## Subdirectories

| Directory                | File                              | Purpose                                    |
|--------------------------|-----------------------------------|--------------------------------------------|
| `Bounce/`                | `IRBounceController.swift`        | Elastic bounce-back for viewport limits    |
| `DeviceShiftController/` | `IRePTZShiftController.swift`     | Electronic PTZ (pan-tilt-zoom) via device motion |
| `GestureController/`     | `IRGLGestureController.swift`     | GL-level gesture handling for render views |
|                          | `IRGestureController.swift`       | Base gesture controller                    |
| `ScrollController/`      | `IRSmoothScrollController.swift`  | Smooth inertial scrolling for viewport     |

## Purpose

These controllers interpret user input (touch gestures, device motion) and translate them into viewport transform updates consumed by the rendering pipeline's transform controllers.

## Agent Notes

- Controllers feed into `Display/RenderKit/Transform/` controllers.
- `IRePTZShiftController` uses CoreMotion — needs device permission handling.
- `IRBounceController` enforces viewport boundaries with spring-like behavior.
- Tests: `IRGLGestureControllerTests.swift`, `IRePTZShiftControllerTests.swift`.
