# AGENTS.md — Controller

Input and interaction controllers for the rendering viewport.

## Subdirectories

| Directory                | File                              | Purpose                                    |
|--------------------------|-----------------------------------|--------------------------------------------|
| `Bounce/`                | `IRBounceController.swift`        | Elastic bounce-back for viewport limits    |
| `DeviceShiftController/` | `IRePTZShiftController.swift`     | Electronic PTZ (pan-tilt-zoom) via device motion |
| `GestureController/`     | `IRGLGestureController.swift`     | GL-level gesture handling for render views |
|                          | `IRGestureController.swift`       | Base gesture controller                    |
| `ScrollController/`      | `IRSmoothScrollController.swift`  | Main-thread smooth-scroll facade            |
|                          | `IRSmoothScrollDisplayLinkDriver.swift` | Paused/active display-link owner       |
|                          | `IRSmoothScrollSession.swift`     | Locked animation state and calculations     |

## Purpose

These controllers interpret user input (touch gestures, device motion) and translate them into viewport transform updates consumed by the rendering pipeline's transform controllers.

## Agent Notes

- Controllers feed into `Display/RenderKit/Transform/` controllers.
- `IRSensor` owns Core Motion input; `IRePTZShiftController` only translates
  configured device-shift degrees.
- `IRBounceController` enforces viewport boundaries with spring-like behavior.
- Keep UIKit controller delivery on the main thread.
- A smooth-scroll display link must remain paused while its session is idle and
  must be closed during presentation teardown.
- Velocity, easing, pending degree composition, timing, and one-shot bounds
  admission belong to `IRSmoothScrollSession`; do not reintroduce a forwarding
  policy or independently mutable controller fields.
- Gesture `willDecelerate` must reflect whether the session actually accepted
  work. Presentation motion restarts only after pan deceleration completion;
  sensor degree smoothing must not emit that gesture completion.
- Tests: `IRGLGestureControllerTests.swift`,
  `IRSmoothScrollDisplayLinkDriverTests.swift`,
  `IRSmoothScrollSessionTests.swift`, `IRSmoothScrollControllerTests.swift`,
  and `IRePTZShiftControllerTests.swift`.
