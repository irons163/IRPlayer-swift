# Smooth Scroll Runtime Ownership Design

## Summary

`IRSmoothScrollController` currently creates and schedules a live
`CADisplayLink` during initialization, even when no animation is pending. The
display-link lifetime, easing state, pan/degree mode, bounce admission, UIKit
delivery, and pure calculations all live in one mutable object. Tests reach
through `Mirror` to inspect those private fields and manually invalidate the
timer.

Replace that implicit runtime with three explicit responsibilities:

- an injectable display-link driver that owns scheduling and teardown;
- a synchronized `IRSmoothScrollSession` that owns one coherent animation
  state and all associated calculations;
- a small `IRSmoothScrollController` facade that translates session ticks into
  viewport, render-mode, bounce, and delegate calls.

The display link is installed paused in common run-loop modes, becomes active
only while the session has real work, pauses immediately on reset, completion,
or invalid input, and is invalidated exactly once on close or deinit.

## Problems

- Every controller wakes the main run loop every display frame while idle.
- `CADisplayLink`, its proxy, and callback lifetime are not injectable or
  directly observable.
- Animation fields can represent incoherent combinations and are mutated
  independently.
- `lastTimestamp` is unused.
- Bounce flags are coupled to the controller's private storage.
- Tests depend on private field names and optional-storage representation via
  `Mirror`.
- `IRSmoothScrollPolicy` is a forwarding-only policy boundary rather than the
  owner of animation semantics.
- Invalid velocity produces no animation but gesture delivery reports that
  deceleration will occur.
- Nonzero velocity currently reports `willDecelerate == false`, causing motion
  input to restart while inertial scrolling is still active.
- Presentation does not restart motion when real deceleration completes.

## Goals

- Own `CADisplayLink` creation, pause/resume, callback, and teardown behind an
  injectable driver.
- Keep the system link paused while idle and schedule it in `.common` mode.
- Represent uninstalled, idle, active, and closed driver phases explicitly.
- Move pending point, consumed point, duration, start timestamp, pan mode, and
  per-axis bounce admission into one locked session.
- Replace independent field mutation with atomic start, reset, advance, and
  bounds-admission operations.
- Reject non-finite or zero-work animations without activating the driver.
- Return whether a velocity actually scheduled deceleration.
- Report nonzero inertial scrolling as decelerating and zero/invalid velocity
  as not decelerating.
- Restart motion only after the smooth-scroll completion callback.
- Preserve the public degree-shift API and viewport behavior.
- Remove `IRSmoothScrollPolicy`.
- Replace reflection-based tests with explicit diagnostics and injected probes.
- Add deterministic driver, session, controller, gesture, presentation,
  teardown, failure, stale-callback, and concurrency tests.

## Non-Goals

- Change the existing velocity-to-distance factor or ease-out curve.
- Change the 0.5-second sensor degree-shift duration.
- Redesign render-mode transform controllers.
- Redesign bounce drawing or animation geometry.
- Make UIKit rendering occur off the main thread.

## Components

### Display-Link Driver

`IRSmoothScrollDisplayLinkDriving` exposes install, active-state changes,
diagnostics, and terminal close. The system implementation owns exactly one
`CADisplayLink` and one weak proxy. Installation schedules the link on the main
run loop in common modes and leaves it paused. The callback carries only an
immutable timestamp.

The handler captures the controller weakly. Close clears the handler before
invalidating the link, releases the proxy, and is repeatable. An injected probe
can reject installation or activation and can emit controlled timestamps,
including after reset or controller deallocation.

### Animation Session

`IRSmoothScrollSession` owns:

- idle or active phase;
- monotonically increasing animation generation;
- final and already-consumed points;
- duration and optional start timestamp;
- pan-versus-degree delivery mode;
- horizontal and vertical bounce admission.

All state is protected by one lock. Starting a velocity or degree shift builds
one complete active generation or publishes idle. Advancing returns an
immutable tick value after updating state. Completion atomically returns to
idle. Reset revokes the active generation and clears all animation and bounce
state.

Velocity targeting, ease-out calculation, remaining-degree composition, and
bounds requests live beside this state. No policy facade remains.

### Controller Facade

The controller owns one session, driver, weak target/delegate references,
current render mode, and bounce adapter. It installs the driver once and
activates it only when the session accepts real work.

Each driver callback asks the session to advance. A pan tick scrolls the target
view; a degree tick shifts the active render mode and requests rendering. A
finished tick pauses the driver. A finished pan generation notifies the
deceleration delegate exactly once, while sensor degree smoothing does not
masquerade as gesture deceleration. Reset pauses before any later callback can
produce UI work.

### Gesture And Presentation Integration

`calculateSmoothScroll(velocity:)` returns `true` only when an active
deceleration was installed. `IRGLGestureController` forwards that exact value
to `glViewDidEndDragging`.

`IRPlayerPresentationSession` keeps motion stopped while deceleration is
active and restarts it from `glViewDidEndDecelerating`. Zero or invalid
velocity restarts motion immediately through the existing non-decelerating
path.

## Invariants

- Idle session implies a paused display link.
- Closed driver cannot be reinstalled or reactivated.
- At most one installed link and one active animation generation exist.
- Invalid, zero-distance, or zero-duration input never activates the link.
- Reset and completion clear pending movement and both bounce flags.
- A callback after reset cannot produce movement or completion delivery.
- Completion pauses the link; pan completion notifies the delegate once and
  degree completion does not.
- Driver callbacks do not retain the controller.
- Controller deinit closes the driver exactly once.
- Motion remains stopped during real inertial scrolling and restarts on its
  completion.

## Testing

- Driver phase transitions, duplicate install rejection, active pause/resume,
  common-mode configuration, terminal close, and weak callback ownership.
- Velocity targeting, finite checks, ease-out steps, completion, timestamp
  validation, degree remainder composition, reset, bounce admission, and
  concurrent session access.
- Controller idle installation, start/stop activation, install/activation
  failure, stale ticks, degree mode, bounce delivery, completion delivery, and
  deinitialization.
- Gesture zero, invalid, and nonzero velocity deceleration reporting.
- Presentation motion stop, no early restart, and completion restart.
- Focused suites under Thread Sanitizer plus integration, full simulator, and
  generic iOS device validation.

## Acceptance Criteria

- No idle controller has an active display link.
- No smooth-scroll test uses `Mirror` or accesses `CADisplayLink` storage.
- All animation state transitions are owned by `IRSmoothScrollSession`.
- `IRSmoothScrollPolicy.swift` and all references are removed.
- Nonzero velocity reports real deceleration; zero/invalid velocity does not.
- Motion restarts after, not during, inertial scrolling.
- Public degree-shift behavior remains compatible.
- Focused, Thread Sanitizer, integration, full simulator, and generic device
  gates pass.
