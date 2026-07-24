# Smooth Scroll Runtime Ownership Implementation Plan

**Design:** See
`docs/superpowers/specs/2026-07-24-smooth-scroll-runtime-ownership-design.md`.

## Phase 1: Display-Link Owner

- [x] Add explicit driver phases and diagnostics.
- [x] Add an injectable display-link protocol.
- [x] Implement one paused system link in common run-loop modes.
- [x] Make close terminal, repeatable, and weakly connected to the controller.
- [x] Add deterministic driver lifecycle tests.

## Phase 2: Animation Session

- [x] Add coherent idle and active animation generations.
- [x] Move pending movement, timing, pan mode, and bounce admission under one
  lock.
- [x] Consolidate velocity, easing, degree remainder, and bounds semantics.
- [x] Reject invalid and zero-work animation starts.
- [x] Add lifecycle, math, failure, completion, and concurrency tests.

## Phase 3: Controller And Integration

- [x] Reduce `IRSmoothScrollController` to driver/session/UI translation.
- [x] Activate the link only while session work exists.
- [x] Pause on reset, invalid tick, completion, and driver failure.
- [x] Expose coherent diagnostics instead of test reflection.
- [x] Report actual deceleration from gesture completion.
- [x] Restart presentation motion when deceleration completes.
- [x] Remove `IRSmoothScrollPolicy.swift`.

## Phase 4: Documentation

- [x] Update Controller and test ownership guidance.
- [x] Update the 2.0 completion audit.

## Phase 5: Verification

- [x] Run driver, session, controller, gesture, sensor, and presentation
  focused tests.
- [x] Run focused tests with Thread Sanitizer.
- [x] Run interaction, render-mode, transform, presentation, and facade
  integration suites.
- [x] Run the full iOS Simulator suite.
- [x] Run a generic iOS device build.
- [x] Run package/project, warning, stale-symbol, and whitespace validation.
- [x] Create a focused commit.

## Baseline

Recorded on 2026-07-24 before implementation:

- Smooth-scroll, gesture, sensor, and presentation suites: 64 passed, 0 failed.

## Verification Record

Recorded on 2026-07-24 after implementation:

- Display-link driver, animation session, controller, gesture, sensor, and
  presentation focused suites: 82 passed, 0 failed.
- The same focused suites under Thread Sanitizer: 82 passed, 0 failed, no race
  diagnostics.
- Interaction, render-mode, transform, presentation, sensor, and facade
  integration suites: 181 passed, 0 failed.
- Full iOS Simulator suite: 1232 passed, 0 failed, 0 skipped.
- Generic iOS device build: passed.
- Package manifest inspection, Xcode project plist and identity validation,
  stale policy/reflection scans, warning scans, and `git diff --check`: passed.
