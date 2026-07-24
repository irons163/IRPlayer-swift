# Sensor Motion Session Ownership Design

## Summary

`IRSensor` currently starts Core Motion on a newly created operation queue and
mutates reference attitude, accumulated offsets, and interface orientation from
both the motion callback and the main thread. Stop and restart have no request
identity, so a callback or main-thread delivery already in flight can update a
new session or scroll after motion has stopped.

Replace that implicit lifetime with one synchronized, generation-fenced motion
session. A small driver adapts `CMMotionManager` into immutable value samples.
`IRSensor` owns one serial callback queue, one driver, and one lifecycle
mutation gate. A dedicated `IRSensorMotionSession` owns the locked generation,
orientation, reference quaternion, and accumulated offsets. Motion calculation
updates only that session; UIKit delivery is admitted again on the main thread
against the same generation and orientation.

## Problems

- `referenceAttitude` is read and written from a Core Motion callback while
  reset and orientation work can mutate it from another thread.
- `orientation` is read on the motion queue and written on the main thread
  without synchronization.
- Per-session previous offsets are captured mutable variables in an escaping
  callback rather than state owned by the sensor.
- Every reset creates an unowned `OperationQueue`.
- `stopDeviceMotionUpdates()` does not revoke callbacks already queued by Core
  Motion or scroll work already queued to the main thread.
- A callback from an older reset can capture a reference or deliver movement
  into the current session.
- `resetUnit()` reports success even when device motion is unavailable.
- Runtime behavior cannot be tested without physical Core Motion input.

## Goals

- Introduce an injectable motion driver that converts Core Motion objects to
  immutable quaternion, pitch, and roll values at the framework boundary.
- Own one named serial callback queue for the lifetime of each sensor.
- Serialize start and stop mutations.
- Represent idle and active motion generations explicitly.
- Fence both callback processing and main-thread scroll delivery by generation.
- Keep reference quaternion, previous offsets, and interface orientation under
  one lock.
- Rebaseline tracking when the interface orientation changes or a sample is
  invalid for the active orientation.
- Synchronize weak target and smooth-scroll references.
- Return `false` when the driver cannot start.
- Stop automatically during deinitialization without retaining the sensor from
  the driver callback.
- Add deterministic lifecycle, stale-work, failure, quaternion, orientation,
  deinitialization, and concurrency tests.

## Non-Goals

- Change public player, render-mode, or motion-controller APIs.
- Change the existing 15-degree orientation admission thresholds.
- Add sensor fusion beyond the device-motion attitude supplied by Core Motion.
- Add smoothing or inertia beyond `IRSmoothScrollController`.
- Make Core Motion available in the simulator.

## Components

### Immutable Motion Values

`IRSensorQuaternion` and `IRSensorMotionSample` are finite value boundaries.
Quaternion normalization and relative-attitude multiplication are checked
before angle extraction. No `CMAttitude` instance crosses into session state or
is mutated in place.

### Motion Driver

`IRSensorMotionDriving` exposes availability, start, and stop. The system
implementation owns one `CMMotionManager`, configures its update interval, and
maps each valid `CMDeviceMotion` callback into an immutable sample. Tests inject
a recording driver and control every captured callback.

### Motion Session And Sensor Facade

`IRSensorMotionSession` owns:

- one state lock;
- one monotonically increasing request generation;
- idle or active tracking state;
- reference quaternion, previous offsets, and interface orientation.

`IRSensor` owns:

- one lifecycle mutation lock;
- one serial callback queue;
- one driver;
- synchronized weak display and scroll targets.

Reset revokes the previous generation before stopping its driver, publishes a
fresh active state, then starts a callback carrying that generation. A failed
start returns the generation to idle. Stop revokes the generation before asking
the driver to stop.

### Sample Processing

The first valid sample becomes the reference quaternion and produces no scroll.
Later samples are made relative to the reference, mapped through the existing
orientation equations, and accumulated under the state lock. Invalid
quaternions, unsupported orientations, and out-of-threshold samples clear the
tracking reference so the next sample establishes a safe baseline.

### Main-Thread Delivery

Each calculated shift captures the active generation and expected orientation.
The delivery closure rechecks both after reaching the main executor. A current
window-scene orientation change updates locked state, clears the tracking
baseline, and drops that shift. Stop, reset, and deinit therefore cannot admit
stale scroll work, while target access remains coherent with lifecycle
mutation.

## Invariants

- Only the active generation may mutate tracking state.
- Only the active generation and current orientation may deliver a scroll.
- Stop revokes callback and delivery work before the driver is stopped.
- Reset revokes all earlier handlers before the next handler is installed.
- The first sample of every session or orientation establishes a reference and
  never scrolls.
- Reference quaternion and previous offsets belong to exactly one generation.
- Core Motion objects and mutable `CMAttitude` values never cross the driver
  boundary.
- Driver callbacks capture the sensor weakly.
- A failed start leaves the sensor idle.
- Deinitialization always stops the driver and cancels queued operations.

## Testing

- Driver availability and start failure.
- Initial active diagnostics and repeatable stop.
- First-sample reference capture and relative quaternion movement.
- Invalid quaternion and threshold rejection rebaseline.
- Restart rejects an older captured handler.
- Stop rejects callback work and already queued main delivery.
- Orientation changes drop movement and establish a new reference.
- Target and smooth-scroll replacement remain synchronized.
- Driver callbacks do not retain a released sensor.
- Concurrent reset, stop, sample emission, orientation updates, diagnostics,
  and target access under Thread Sanitizer.
- Presentation-session motion install, gesture replacement, zoom/drag restart,
  and terminal close integration.

## Acceptance Criteria

- `IRSensor` has no unsynchronized mutable callback state.
- Core Motion is accessed only through the injectable driver.
- No stale callback or main delivery can scroll after stop or across reset.
- Motion availability and start failure are observable through `resetUnit()`.
- Existing orientation math and player-facing APIs remain compatible.
- Focused, Thread Sanitizer, integration, full simulator, and generic iOS
  device validation pass.
