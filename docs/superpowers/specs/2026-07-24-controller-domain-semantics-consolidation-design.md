# Controller Domain Semantics Consolidation Design

## Context

The controller domain still contains four policy types that do not represent
independent policy boundaries:

- `IRBouncePolicy`
- `IRePTZShiftPolicy`
- `IRGesturePolicy`
- `IRGLGesturePolicy`

Each is referenced by one owning controller, tests, and Xcode project
bookkeeping. `IRBounceController` and `IRePTZShiftController` already expose
forwarding static methods, while gesture controllers call their matching
policy directly. Tests consequently validate both the forwarding facade and
its implementation mirror.

The policy separation adds navigation and naming cost without isolating
mutable state, resources, threading, platform access, or a reusable
cross-domain algorithm.

## Goals

- Make each controller the single owner of the semantics it consumes.
- Remove the four forwarding-only policy types and project entries.
- Keep internal helper value/action types scoped to their controller.
- Preserve gesture, bounce, ePTZ, and GL interaction behavior.
- Reject non-finite derived bounce/render coordinates, not only malformed
  inputs.
- Rename policy-oriented tests to controller-oriented behavioral tests.
- Cover every known gesture-recognizer state and every scroll direction.
- Keep UIKit delivery and existing smooth-scroll/presentation ownership
  unchanged.

## Non-Goals

- Changing public controller APIs.
- Redesigning gesture recognizer installation or callback ordering.
- Changing scroll deceleration, Core Motion, render-mode, or transform
  ownership.
- Making UIKit controller instances thread-safe; they remain main-thread
  interaction objects.
- Combining unrelated render, transform, or FFmpeg policies into this slice.

## Ownership Design

### Bounce

`IRBounceController` owns:

- checked bounce path construction;
- direction-to-animation mapping;
- nested path geometry and animation plan values.

Path construction validates both source inputs and all derived points. Any
invalid or overflowing geometry falls back to the existing all-zero inert
geometry.

### Electronic PTZ

`IRePTZShiftController` owns checked degree normalization. Non-finite inputs,
zero angle, and overflowing arithmetic continue to produce zero.

### Base Gestures

`IRGestureController` owns:

- velocity/translation classification;
- touch-side classification;
- disabled-axis admission;
- recognizer-state actions;
- simultaneous-recognition admission.

Action values are nested under the controller. Runtime callbacks and pure
tests call the same owner methods.

### GL Gestures

`IRGLGestureController` owns:

- view-to-render coordinate conversion;
- pan and continuous recognizer-state actions;
- double-tap/swipe begin admission.

Coordinate conversion validates the resulting scaled point so finite inputs
that overflow during subtraction or multiplication become the inert zero
point.

## Test Architecture

- Rename `IRGesturePolicyTests.swift` to
  `IRGestureControllerTests.swift`.
- Test controller semantics directly; remove facade-vs-policy comparisons.
- Use complete direction/state tables where the domain is finite.
- Add derived-overflow cases for bounce geometry and GL render points.
- Retain controller callback and integration tests in their existing suites.

## Acceptance Criteria

- No source, test, or Xcode project reference to any of the four deleted
  policy types remains.
- The source tree policy count falls from 29 to 25.
- Focused bounce, ePTZ, base-gesture, and GL-gesture suites pass.
- Relevant controller/presentation suites pass under Thread Sanitizer.
- The full iOS Simulator suite passes.
- A generic iOS device Release build succeeds without changed-source
  warnings.
- Xcode project, stale-symbol, policy-count, and whitespace audits pass.
