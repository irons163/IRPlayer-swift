# Sensor Motion Session Ownership Implementation Plan

**Design:** See
`docs/superpowers/specs/2026-07-24-sensor-motion-session-ownership-design.md`.

## Phase 1: Driver And Values

- [x] Add checked immutable quaternion and motion-sample values.
- [x] Add an injectable motion-driver protocol.
- [x] Adapt `CMMotionManager` behind the system driver.
- [x] Own and configure one serial callback queue per sensor.
- [x] Add driver/value regression tests.

## Phase 2: Explicit Session State

- [x] Add idle and active motion phases with coherent diagnostics.
- [x] Move reference attitude and previous offsets into locked active state.
- [x] Serialize reset and stop mutations.
- [x] Revoke the old generation before driver stop or replacement.
- [x] Return idle on unavailable or failed driver start.

## Phase 3: Fenced Processing And Delivery

- [x] Process only samples matching the active generation.
- [x] Rebaseline invalid and orientation-ineligible samples.
- [x] Fence queued main-thread delivery by generation and orientation.
- [x] Synchronize weak target and smooth-scroll references.
- [x] Stop and cancel pending work during deinitialization.

## Phase 4: Integration And Documentation

- [x] Preserve `IRPlayerMotionControlling` compatibility.
- [x] Cover presentation install, restart, replacement, and close behavior.
- [x] Update Matrix and test ownership guidance.
- [x] Update the 2.0 completion audit.

## Phase 5: Verification

- [x] Run sensor and presentation focused tests.
- [x] Run focused tests with Thread Sanitizer.
- [x] Run controller, render-mode, presentation, and facade integration suites.
- [x] Run the full iOS Simulator suite.
- [x] Run a generic iOS device build.
- [x] Run package/project, warning, stale-symbol, and whitespace validation.
- [x] Create a focused commit.

## Baseline

Recorded on 2026-07-24 before implementation:

- Sensor and presentation-session suites: 16 passed, 0 failed.

## Verification Record

Recorded on 2026-07-24 after implementation:

- Sensor driver/session/facade and presentation focused suites: 42 passed,
  0 failed.
- The same focused suites under Thread Sanitizer: 42 passed, 0 failed, no
  race diagnostics.
- Controller, rendering, presentation, and facade integration suites:
  132 passed, 0 failed.
- Full iOS Simulator suite: 1214 passed, 0 failed, 0 skipped.
- Generic iOS device build: passed.
- `swift package dump-package`, Xcode project plist validation, project-entry
  identity checks, stale-symbol scans, warning scans, and `git diff --check`:
  passed. SwiftPM test discovery remains unavailable because the package's
  prebuilt FFmpeg framework headers are supplied by the Xcode integration.
