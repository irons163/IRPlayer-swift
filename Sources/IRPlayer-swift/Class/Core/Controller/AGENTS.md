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
|                          | `IRSmoothScrollSession.swift`     | Locked animation state and calculations     |

## Purpose

These controllers interpret user input (touch gestures, device motion) and translate them into viewport transform updates consumed by the rendering pipeline's transform controllers.

## Agent Notes

- Controllers feed into `Display/RenderKit/Transform/` controllers.
- `IRSensor` owns Core Motion input; `IRePTZShiftController` only translates
  configured device-shift degrees.
- Bounce geometry and animation mapping belong to `IRBounceController`; ePTZ
  degree normalization belongs to `IRePTZShiftController`.
- Base gesture classification/admission belongs to `IRGestureController`;
  render-space mapping and GL gesture admission belong to
  `IRGLGestureController`. Do not reintroduce forwarding policy mirrors.
- Keep UIKit controller delivery on the main thread.
- Smooth scrolling uses the shared `Display/IRDisplayLinkDriver.swift`; it must
  remain paused while the animation session is idle and close during
  presentation teardown.
- Velocity, easing, pending degree composition, timing, and one-shot bounds
  admission belong to `IRSmoothScrollSession`; do not reintroduce a forwarding
  policy or independently mutable controller fields.
- Gesture `willDecelerate` must reflect whether the session actually accepted
  work. Presentation motion restarts only after pan deceleration completion;
  sensor degree smoothing must not emit that gesture completion.
- Tests: `IRBounceControllerTests.swift`,
  `IRGestureControllerTests.swift`, `IRGLGestureControllerTests.swift`,
  `IRDisplayLinkDriverTests.swift`,
  `IRSmoothScrollSessionTests.swift`, `IRSmoothScrollControllerTests.swift`,
  and `IRePTZShiftControllerTests.swift`.
